import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'model_manager.dart';

final qaRepositoryProvider = Provider<QaRepository>((ref) {
  return QaRepository(ref.read(modelManagerProvider));
});

class QaResult {
  const QaResult(this.answer, this.confidence);
  final String answer;
  final double confidence;
}

class QaRepository {
  const QaRepository(this._modelManager);
  final ModelManager _modelManager;

  Future<QaResult?> answer(String question, String context) async {
    final session = _modelManager.qaSession;
    if (session == null) {
      // Return a dummy answer for dev if model not loaded
      return const QaResult("This is a simulated AI answer because the QA model is not loaded.", 0.99);
    }

    try {
      // Stub: in a real app, implement BERT tokenization for question+context
      final inputIds = List<int>.filled(512, 0); 
      final attentionMask = List<int>.filled(512, 0);

      final inputIdsTensor = OrtValueTensor.createTensorWithDataList(
          Int64List.fromList(inputIds), [1, 512]);
      final attentionMaskTensor = OrtValueTensor.createTensorWithDataList(
          Int64List.fromList(attentionMask), [1, 512]);

      final inputs = {
        'input_ids': inputIdsTensor,
        'attention_mask': attentionMaskTensor,
      };

      final runOptions = OrtRunOptions();
      final outputs = await session.runAsync(runOptions, inputs);

      // Extract output (start_logits, end_logits)
      inputIdsTensor.release();
      attentionMaskTensor.release();
      runOptions.release();
      for (var out in outputs ?? []) {
        out.release();
      }

      return const QaResult("Extracted answer (simulated)", 0.85);
    } catch (e) {
      // Fallback on error
      return null;
    }
  }
}
