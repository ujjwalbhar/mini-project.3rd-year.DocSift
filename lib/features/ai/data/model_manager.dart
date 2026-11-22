import 'dart:io';
import 'dart:isolate';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'wordpiece_tokenizer.dart';

final modelManagerProvider = Provider<ModelManager>((ref) {
  final manager = ModelManager();
  ref.onDispose(manager.dispose);
  return manager;
});

class ModelManager {
  WordPieceTokenizer? _tokenizer;
  OrtSession? _embeddingSession;
  OrtSession? _qaSession;

  Future<WordPieceTokenizer?>? _tokenizerFuture;
  Future<OrtSession?>? _embeddingFuture;
  Future<OrtSession?>? _qaFuture;

  bool _envInitialized = false;
  bool _ortUnavailable = false;

  WordPieceTokenizer? get tokenizer => _tokenizer;
  OrtSession? get embeddingSession => _embeddingSession;
  OrtSession? get qaSession => _qaSession;
  bool get isOrtUnavailable => _ortUnavailable;

  /// Lazily loads and parses the 30,522-token `bert-base-uncased` vocabulary
  /// on a background isolate.
  Future<WordPieceTokenizer?> ensureTokenizer() {
    if (_tokenizer != null) return Future.value(_tokenizer);
    return _tokenizerFuture ??= _loadTokenizer();
  }

  Future<WordPieceTokenizer?> _loadTokenizer() async {
    try {
      final rawVocab = await rootBundle.loadString('assets/models/vocab.txt');
      final parsed = await Isolate.run(
        () => WordPieceTokenizer.fromVocabString(rawVocab),
      );
      _tokenizer = parsed;
      return parsed;
    } catch (_) {
      _tokenizerFuture = null;
      return null;
    }
  }

  /// Lazily loads `minilm.onnx` off the UI thread when embeddings are needed.
  Future<OrtSession?> ensureEmbeddingSession() {
    if (_embeddingSession != null) return Future.value(_embeddingSession);
    if (_ortUnavailable) return Future.value(null);
    return _embeddingFuture ??= _loadEmbeddingSession();
  }

  Future<OrtSession?> _loadEmbeddingSession() async {
    final session = await _loadSessionOffThread(
      assetPath: 'assets/models/minilm.onnx',
      cacheFileName: 'minilm.onnx',
    );
    _embeddingSession = session;
    if (session == null) {
      _embeddingFuture = null;
    }
    return session;
  }

  /// Lazily loads `distilbert_squad2.onnx` off the UI thread only when the user
  /// invokes extractive Q&A.
  Future<OrtSession?> ensureQaSession() {
    if (_qaSession != null) return Future.value(_qaSession);
    if (_ortUnavailable) return Future.value(null);
    return _qaFuture ??= _loadQaSession();
  }

  Future<OrtSession?> _loadQaSession() async {
    final session = await _loadSessionOffThread(
      assetPath: 'assets/models/distilbert_squad2.onnx',
      cacheFileName: 'distilbert_squad2.onnx',
    );
    _qaSession = session;
    if (session == null) {
      _qaFuture = null;
    }
    return session;
  }

  /// Warms up tokenizer + both ONNX models on demand (e.g., from Settings).
  Future<bool> warmUpAll() async {
    final tok = await ensureTokenizer();
    final emb = await ensureEmbeddingSession();
    final qa = await ensureQaSession();
    return tok != null && emb != null && qa != null;
  }

  Future<void> init() async {
    await warmUpAll();
  }

  bool _ensureOrtEnv() {
    if (_envInitialized) return true;
    if (_ortUnavailable) return false;
    try {
      OrtEnv.instance.init();
      _envInitialized = true;
      return true;
    } catch (_) {
      _ortUnavailable = true;
      return false;
    }
  }

  Future<OrtSession?> _loadSessionOffThread({
    required String assetPath,
    required String cacheFileName,
  }) async {
    if (!_ensureOrtEnv()) return null;

    try {
      if (Platform.isWindows) {
        // onnxruntime-1.4.1 passes UTF-8 paths to CreateSession, whereas
        // Windows ORT expects wchar_t*; use zero-copy TransferableTypedData
        // + fromBuffer on a worker isolate on Windows.
        final raw = await rootBundle.load(assetPath);
        final bytes = raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes);
        final transferable = TransferableTypedData.fromList([bytes]);
        final address = await Isolate.run<int>(
          () => _createSessionFromBufferIsolate(transferable),
        );
        return OrtSession.fromAddress(address);
      }

      // On Android / iOS / macOS / Linux, cache asset to app support storage
      // once so OrtSession.fromFile maps directly from disk without allocating
      // duplicate Dart + C++ buffers in RAM.
      final supportDir = await getApplicationSupportDirectory();
      final modelDir = Directory(p.join(supportDir.path, 'onnx_models'));
      if (!await modelDir.exists()) {
        await modelDir.create(recursive: true);
      }
      final cachedFile = File(p.join(modelDir.path, cacheFileName));
      final raw = await rootBundle.load(assetPath);
      final expectedLen = raw.lengthInBytes;
      final exists = await cachedFile.exists();
      final currentLen = exists ? await cachedFile.length() : -1;

      if (!exists || currentLen != expectedLen) {
        final bytes = raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes);
        await cachedFile.writeAsBytes(bytes, flush: true);
      }

      final cachedPath = cachedFile.path;
      final address = await Isolate.run<int>(
        () => _createSessionFromFileIsolate(cachedPath),
      );
      return OrtSession.fromAddress(address);
    } catch (_) {
      return null;
    }
  }

  /// Releases the ~67 MB QA model when no longer needed while keeping the
  /// lightweight MiniLM embedding model available.
  void releaseQaSession() {
    _qaSession?.release();
    _qaSession = null;
    _qaFuture = null;
  }

  void dispose() {
    _embeddingSession?.release();
    _embeddingSession = null;
    _embeddingFuture = null;

    _qaSession?.release();
    _qaSession = null;
    _qaFuture = null;

    if (_envInitialized) {
      OrtEnv.instance.release();
      _envInitialized = false;
    }
  }
}

int _createSessionFromFileIsolate(String filePath) {
  OrtEnv.instance.init();
  final options = OrtSessionOptions()
    ..setIntraOpNumThreads(2)
    ..setInterOpNumThreads(1)
    ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);
  try {
    final session = OrtSession.fromFile(File(filePath), options);
    return session.address;
  } finally {
    options.release();
  }
}

int _createSessionFromBufferIsolate(TransferableTypedData transferable) {
  OrtEnv.instance.init();
  final bytes = transferable.materialize().asUint8List();
  final options = OrtSessionOptions()
    ..setIntraOpNumThreads(2)
    ..setInterOpNumThreads(1)
    ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);
  try {
    final session = OrtSession.fromBuffer(bytes, options);
    return session.address;
  } finally {
    options.release();
  }
}

