import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'model_manager.dart';

final embeddingRepositoryProvider = Provider<EmbeddingRepository>((ref) {
  return EmbeddingRepository(ref.read(modelManagerProvider));
});

class EmbeddingRepository {
  EmbeddingRepository(this._modelManager);
  final ModelManager _modelManager;
  final _AsyncSerialLock _sessionLock = _AsyncSerialLock();

  static const int embeddingDim = 384;

  Future<List<double>> generateEmbedding(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return List<double>.filled(embeddingDim, 0.0);
    }

    final tokenizer = await _modelManager.ensureTokenizer();
    final session = await _modelManager.ensureEmbeddingSession();
    if (tokenizer == null || session == null) {
      return fallbackEmbedding(trimmed);
    }

    OrtValueTensor? inputIdsTensor;
    OrtValueTensor? attentionMaskTensor;
    OrtValueTensor? tokenTypeIdsTensor;
    OrtRunOptions? runOptions;
    List<OrtValue?>? outputs;

    try {
      final enc = tokenizer.encodeSingle(trimmed, maxLen: 256);
      final shape = <int>[1, enc.length];

      inputIdsTensor =
          OrtValueTensor.createTensorWithDataList(enc.inputIds, shape);
      attentionMaskTensor =
          OrtValueTensor.createTensorWithDataList(enc.attentionMask, shape);
      tokenTypeIdsTensor =
          OrtValueTensor.createTensorWithDataList(enc.tokenTypeIds, shape);

      final inputs = <String, OrtValue>{
        'input_ids': inputIdsTensor,
        'attention_mask': attentionMaskTensor,
        'token_type_ids': tokenTypeIdsTensor,
      };

      runOptions = OrtRunOptions();
      outputs = await _sessionLock.run(
        () async => await session.runAsync(runOptions!, inputs),
      );

      if (outputs == null || outputs.isEmpty || outputs.first == null) {
        return fallbackEmbedding(trimmed);
      }

      // outputs.first IS the OrtValueTensor; .value yields [1][seqLen][384]
      final rawBatch = outputs.first!.value;
      if (rawBatch is! List || rawBatch.isEmpty) {
        return fallbackEmbedding(trimmed);
      }

      final seqList = rawBatch.first as List;
      final tokenEmbeddings = List<List<double>>.generate(
        seqList.length,
        (t) {
          final row = seqList[t] as List;
          return List<double>.generate(
            row.length,
            (d) => (row[d] as num).toDouble(),
            growable: false,
          );
        },
        growable: false,
      );

      return meanPoolAndNormalize(tokenEmbeddings, enc.attentionMask);
    } catch (_) {
      return fallbackEmbedding(trimmed);
    } finally {
      inputIdsTensor?.release();
      attentionMaskTensor?.release();
      tokenTypeIdsTensor?.release();
      runOptions?.release();
      if (outputs != null) {
        for (final out in outputs) {
          out?.release();
        }
      }
    }
  }

  /// SentenceTransformers attention-masked mean pooling followed by L2
  /// normalization over `[seqLen][hiddenDim]` token hidden states.
  static List<double> meanPoolAndNormalize(
    List<List<double>> tokenEmbeddings,
    List<int> attentionMask,
  ) {
    if (tokenEmbeddings.isEmpty) {
      return List<double>.filled(embeddingDim, 0.0);
    }
    final dim = tokenEmbeddings.first.length;
    final summed = List<double>.filled(dim, 0.0);
    double maskSum = 0.0;

    final count = min(tokenEmbeddings.length, attentionMask.length);
    for (int t = 0; t < count; t++) {
      final m = attentionMask[t];
      if (m <= 0) continue;
      final weight = m.toDouble();
      maskSum += weight;
      final row = tokenEmbeddings[t];
      for (int d = 0; d < dim; d++) {
        summed[d] += row[d] * weight;
      }
    }

    final denom = max(maskSum, 1e-9);
    for (int d = 0; d < dim; d++) {
      summed[d] /= denom;
    }

    return normalizeVector(summed);
  }

  /// Deterministic 384-d signed feature-hashed embedding (32-bit FNV-1a over
  /// unigrams, bigrams, and character 3-grams) used when native ONNX Runtime
  /// is unavailable (e.g., headless unit tests). Unlike `String.hashCode`,
  /// FNV-1a produces identical vectors across app restarts and platforms.
  static List<double> fallbackEmbedding(String text) {
    final vec = List<double>.filled(embeddingDim, 0.0);
    final words = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();

    for (int i = 0; i < words.length; i++) {
      final w = words[i];
      _accumulateFeature(vec, 'w:$w', 1.0);

      if (i + 1 < words.length) {
        _accumulateFeature(vec, 'b:$w:${words[i + 1]}', 0.5);
      }

      if (w.length >= 3) {
        final padded = '<$w>';
        for (int k = 0; k <= padded.length - 3; k++) {
          _accumulateFeature(vec, 'g:${padded.substring(k, k + 3)}', 0.25);
        }
      }
    }

    return normalizeVector(vec);
  }

  static void _accumulateFeature(
    List<double> vec,
    String feature,
    double weight,
  ) {
    final h = _fnv1a32(feature);
    final bucket = h % embeddingDim;
    final sign = ((h >> 17) & 1) == 0 ? 1.0 : -1.0;
    vec[bucket] += sign * weight;
  }

  static int _fnv1a32(String input) {
    int hash = 0x811c9dc5;
    for (int i = 0; i < input.length; i++) {
      hash ^= input.codeUnitAt(i);
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  /// Encodes a float vector into a compact Float32 BLOB for SQLite storage.
  Uint8List encodeEmbedding(List<double> vec) {
    final float32 = Float32List.fromList(vec);
    return float32.buffer
        .asUint8List(float32.offsetInBytes, float32.lengthInBytes);
  }

  /// Decodes a SQLite Float32 BLOB back into a `List<double>`.
  List<double> decodeEmbedding(Uint8List bytes) {
    if (bytes.isEmpty || bytes.lengthInBytes % 4 != 0) return const [];
    final aligned = Uint8List.fromList(bytes);
    final float32 = aligned.buffer.asFloat32List();
    return float32.map((v) => v.toDouble()).toList();
  }

  /// Computes cosine similarity between two 384-dimensional vectors.
  double cosineSimilarity(List<double> a, List<double> b) {
    final len = min(a.length, b.length);
    if (len == 0) return 0.0;
    double dot = 0.0;
    double normA = 0.0;
    double normB = 0.0;
    for (int i = 0; i < len; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    final denom = sqrt(normA) * sqrt(normB);
    return denom == 0.0 ? 0.0 : dot / denom;
  }

  static List<double> normalizeVector(List<double> vec) {
    double sum = 0.0;
    for (final v in vec) {
      sum += v * v;
    }
    if (sum == 0.0) return vec;
    final norm = sqrt(sum);
    return vec.map((v) => v / norm).toList();
  }
}

class _AsyncSerialLock {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    final prev = _tail;
    final done = Completer<void>();
    _tail = done.future;

    prev.whenComplete(() async {
      try {
        completer.complete(await action());
      } catch (e, st) {
        completer.completeError(e, st);
      } finally {
        done.complete();
      }
    });

    return completer.future;
  }
}
