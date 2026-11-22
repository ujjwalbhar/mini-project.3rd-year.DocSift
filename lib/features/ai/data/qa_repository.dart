import 'dart:async';
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'model_manager.dart';
import 'wordpiece_tokenizer.dart';

final qaRepositoryProvider = Provider<QaRepository>((ref) {
  return QaRepository(ref.read(modelManagerProvider));
});

class QaResult {
  const QaResult(this.answer, this.confidence);
  final String answer;
  final double confidence;
}

class DecodedSquadSpan {
  const DecodedSquadSpan({
    required this.answer,
    required this.confidence,
    required this.margin,
    required this.startToken,
    required this.endToken,
  });

  final String answer;
  final double confidence;
  final double margin;
  final int startToken;
  final int endToken;
}

class QaRepository {
  QaRepository(this._modelManager);
  final ModelManager _modelManager;
  final _QaSerialLock _sessionLock = _QaSerialLock();

  Future<QaResult?> answer(String question, String context) async {
    final trimmedContext = context.trim();
    if (trimmedContext.isEmpty) return null;

    // 1. Attempt real DistilBERT SQuAD2 ONNX inference across sliding windows
    final tokenizer = await _modelManager.ensureTokenizer();
    final session = await _modelManager.ensureQaSession();

    if (tokenizer != null && session != null) {
      final onnxAnswer =
          await _runDistilBertSquad2(session, tokenizer, question, trimmedContext);
      if (onnxAnswer != null && onnxAnswer.answer.isNotEmpty) {
        return onnxAnswer;
      }
    }

    // 2. Fallback extractive sentence selection (used when ONNX native runtime
    // is unavailable in headless tests or for broad non-span summary prompts).
    return extractiveFallback(question, trimmedContext);
  }

  Future<QaResult?> _runDistilBertSquad2(
    OrtSession session,
    WordPieceTokenizer tokenizer,
    String question,
    String context,
  ) async {
    try {
      final windows = tokenizer.encodeQuestionContextWindows(
        question,
        context,
        maxLen: 384,
        maxQuestionTokens: 64,
        docStride: 128,
      );

      final outputNames = session.outputNames;
      final startIdx = outputNames.indexOf('start_logits');
      final endIdx = outputNames.indexOf('end_logits');
      final resolvedStartIdx = startIdx >= 0 ? startIdx : 0;
      final resolvedEndIdx = endIdx >= 0 ? endIdx : 1;

      DecodedSquadSpan? bestAcrossWindows;

      for (final win in windows) {
        if (win.contextEnd < win.contextStart) continue;

        OrtValueTensor? inputIdsTensor;
        OrtValueTensor? attentionMaskTensor;
        OrtRunOptions? runOptions;
        List<OrtValue?>? outputs;

        try {
          final shape = <int>[1, win.length];
          inputIdsTensor =
              OrtValueTensor.createTensorWithDataList(win.inputIds, shape);
          attentionMaskTensor =
              OrtValueTensor.createTensorWithDataList(win.attentionMask, shape);

          // DistilBERT takes ONLY input_ids and attention_mask (no token_type_ids)
          final inputs = <String, OrtValue>{
            'input_ids': inputIdsTensor,
            'attention_mask': attentionMaskTensor,
          };

          runOptions = OrtRunOptions();
          outputs = await _sessionLock.run(
            () async => await session.runAsync(runOptions!, inputs),
          );

          if (outputs == null ||
              outputs.length <= max(resolvedStartIdx, resolvedEndIdx)) {
            continue;
          }

          final rawStart = outputs[resolvedStartIdx]?.value;
          final rawEnd = outputs[resolvedEndIdx]?.value;
          if (rawStart is! List ||
              rawStart.isEmpty ||
              rawEnd is! List ||
              rawEnd.isEmpty) {
            continue;
          }

          final startRow = rawStart.first as List;
          final endRow = rawEnd.first as List;
          final startLogits = List<double>.generate(
            startRow.length,
            (i) => (startRow[i] as num).toDouble(),
            growable: false,
          );
          final endLogits = List<double>.generate(
            endRow.length,
            (i) => (endRow[i] as num).toDouble(),
            growable: false,
          );

          final candidate = decodeSquadSpan(
            startLogits: startLogits,
            endLogits: endLogits,
            encoded: win,
            originalContext: context,
          );

          if (candidate != null &&
              (bestAcrossWindows == null ||
                  candidate.margin > bestAcrossWindows.margin)) {
            bestAcrossWindows = candidate;
          }
        } finally {
          inputIdsTensor?.release();
          attentionMaskTensor?.release();
          runOptions?.release();
          if (outputs != null) {
            for (final out in outputs) {
              out?.release();
            }
          }
        }
      }

      if (bestAcrossWindows != null) {
        return QaResult(
          bestAcrossWindows.answer,
          bestAcrossWindows.confidence,
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Decodes SQuAD 2.0 `start_logits` and `end_logits` over [encoded],
  /// rejecting unanswerable spans where `[CLS]` (`index 0`) scores higher than
  /// every valid context span, and slicing [originalContext] by character
  /// offsets so original casing, digits, and symbols stay intact.
  static DecodedSquadSpan? decodeSquadSpan({
    required List<double> startLogits,
    required List<double> endLogits,
    required EncodedPair encoded,
    required String originalContext,
    int maxAnswerTokens = 40,
    double noAnswerThreshold = 0.0,
  }) {
    if (encoded.contextEnd < encoded.contextStart ||
        startLogits.length < encoded.length ||
        endLogits.length < encoded.length) {
      return null;
    }

    final nullScore = startLogits[0] + endLogits[0];
    double bestSpanScore = double.negativeInfinity;
    int bestS = -1;
    int bestE = -1;

    for (int s = encoded.contextStart; s <= encoded.contextEnd; s++) {
      if (encoded.spans[s] == null) continue;
      final maxE = min(encoded.contextEnd, s + maxAnswerTokens - 1);
      final sLogit = startLogits[s];
      for (int e = s; e <= maxE; e++) {
        if (encoded.spans[e] == null) continue;
        final score = sLogit + endLogits[e];
        if (score > bestSpanScore) {
          bestSpanScore = score;
          bestS = s;
          bestE = e;
        }
      }
    }

    if (bestS < 0 || bestE < 0) return null;

    final margin = bestSpanScore - nullScore;
    if (margin <= noAnswerThreshold) {
      return null;
    }

    // Expand contiguous WordPiece subwords (`##...`) at boundaries so codes,
    // IDs, or passwords split across subwords are never clipped mid-word.
    int expandedS = bestS;
    while (expandedS > encoded.contextStart &&
        encoded.spans[expandedS]!.token.startsWith('##') &&
        encoded.spans[expandedS - 1] != null &&
        encoded.spans[expandedS - 1]!.charEnd ==
            encoded.spans[expandedS]!.charStart) {
      expandedS--;
    }

    int expandedE = bestE;
    while (expandedE < encoded.contextEnd &&
        encoded.spans[expandedE + 1] != null &&
        encoded.spans[expandedE + 1]!.token.startsWith('##') &&
        encoded.spans[expandedE]!.charEnd ==
            encoded.spans[expandedE + 1]!.charStart) {
      expandedE++;
    }

    final charStart = encoded.spans[expandedS]!.charStart;
    final charEnd = encoded.spans[expandedE]!.charEnd;
    if (charStart < 0 ||
        charEnd > originalContext.length ||
        charEnd <= charStart) {
      return null;
    }

    final extracted = originalContext.substring(charStart, charEnd).trim();
    if (extracted.isEmpty) return null;

    final startProbs = _softmax(startLogits, encoded.length);
    final endProbs = _softmax(endLogits, encoded.length);
    final confidence = (startProbs[bestS] * endProbs[bestE]).clamp(0.01, 0.999);

    return DecodedSquadSpan(
      answer: extracted,
      confidence: confidence,
      margin: margin,
      startToken: expandedS,
      endToken: expandedE,
    );
  }

  static List<double> _softmax(List<double> logits, int length) {
    double maxLogit = double.negativeInfinity;
    for (int i = 0; i < length; i++) {
      if (logits[i] > maxLogit) maxLogit = logits[i];
    }
    final exps = List<double>.filled(length, 0.0);
    double sum = 0.0;
    for (int i = 0; i < length; i++) {
      final v = exp(logits[i] - maxLogit);
      exps[i] = v;
      sum += v;
    }
    final denom = max(sum, 1e-12);
    for (int i = 0; i < length; i++) {
      exps[i] /= denom;
    }
    return exps;
  }

  static QaResult? extractiveFallback(String question, String context) {
    try {
      final sentences = context.split(RegExp(r'(?<=[.!?\n])\s+'));
      final questionWords = question
          .toLowerCase()
          .replaceAll(RegExp(r'[^\w\s]'), ' ')
          .split(RegExp(r'\s+'));

      const stopWords = {
        'what', 'is', 'the', 'my', 'a', 'an', 'of', 'in', 'to', 'for',
        'do', 'does', 'did', 'show', 'tell', 'me', 'about', 'where',
        'when', 'who', 'which', 'how', 'can', 'you', 'find', 'give',
      };
      final keywords = questionWords
          .where((w) => w.isNotEmpty && !stopWords.contains(w))
          .toList();

      if (keywords.isEmpty || sentences.isEmpty) {
        return QaResult(context.trim(), 0.5);
      }

      String bestSentence = '';
      double bestScore = -1.0;

      for (final sentence in sentences) {
        if (sentence.trim().isEmpty) continue;

        final sentenceLower = sentence.toLowerCase();
        double score = 0.0;

        for (final keyword in keywords) {
          if (sentenceLower.contains(keyword)) {
            score += 1.0;
            if (RegExp(r'\b' + RegExp.escape(keyword) + r'\b')
                .hasMatch(sentenceLower)) {
              score += 0.5;
            }
          }
        }

        if (sentence.length > 200) {
          score -= 0.1;
        }

        if (score > bestScore) {
          bestScore = score;
          bestSentence = sentence;
        }
      }

      if (bestScore > 0 && bestSentence.isNotEmpty) {
        return QaResult(
          bestSentence.trim(),
          (bestScore / (keywords.length * 1.5)).clamp(0.1, 0.95),
        );
      }

      return QaResult(context.trim(), 0.4);
    } catch (_) {
      return null;
    }
  }
}

class _QaSerialLock {
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
