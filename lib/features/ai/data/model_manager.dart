import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:onnxruntime/onnxruntime.dart';

final modelManagerProvider = Provider<ModelManager>((ref) {
  return ModelManager();
});

class ModelManager {
  OrtSession? _embeddingSession;
  OrtSession? _qaSession;
  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;

    try {
      OrtEnv.instance.init();
      
      final sessionOptions = OrtSessionOptions();
      
      // Load embedding model
      try {
        final embeddingModelRaw = await rootBundle.load('assets/models/minilm.onnx');
        final embeddingBytes = embeddingModelRaw.buffer.asUint8List(
            embeddingModelRaw.offsetInBytes, embeddingModelRaw.lengthInBytes);
        _embeddingSession = OrtSession.fromBuffer(embeddingBytes, sessionOptions);
      } catch (e) {
        // Fallback or log if model missing during dev
      }

      // Load QA model
      try {
        final qaModelRaw = await rootBundle.load('assets/models/distilbert_squad2.onnx');
        final qaBytes = qaModelRaw.buffer.asUint8List(
            qaModelRaw.offsetInBytes, qaModelRaw.lengthInBytes);
        _qaSession = OrtSession.fromBuffer(qaBytes, sessionOptions);
      } catch (e) {
        // Fallback or log if model missing during dev
      }

      _isInitialized = true;
    } catch (e) {
      // Init failed
    }
  }

  OrtSession? get embeddingSession => _embeddingSession;
  OrtSession? get qaSession => _qaSession;

  void dispose() {
    _embeddingSession?.release();
    _qaSession?.release();
    OrtEnv.instance.release();
  }
}
