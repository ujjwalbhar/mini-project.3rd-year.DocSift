import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:docsift/features/ai/data/wordpiece_tokenizer.dart';
import 'package:docsift/features/ai/data/embedding_repository.dart';
import 'package:docsift/features/ai/data/qa_repository.dart';

void main() {
  late WordPieceTokenizer tokenizer;

  setUpAll(() async {
    final vocabFile = File('assets/models/vocab.txt');
    expect(await vocabFile.exists(), isTrue,
        reason: 'assets/models/vocab.txt must be bundled');
    final vocabRaw = await vocabFile.readAsString();
    tokenizer = WordPieceTokenizer.fromVocabString(vocabRaw);
  });

  group('WordPieceTokenizer (bert-base-uncased)', () {
    test('loads canonical 30,522-token vocabulary and special token IDs', () {
      expect(tokenizer.vocabSize, 30522);
      expect(tokenizer.padId, 0);
      expect(tokenizer.unkId, 100);
      expect(tokenizer.clsId, 101);
      expect(tokenizer.sepId, 102);
      expect(tokenizer.tokenToId('the'), 1996);
      expect(tokenizer.tokenToId('password'), 20786);
    });

    test('preserves exact original character offsets across mixed-case secrets & symbols', () {
      const text = 'Netflix password is SuperSecret99! Email: User.Name@Example.COM.';
      final spans = tokenizer.tokenizeWithOffsets(text);
      expect(spans, isNotEmpty);

      // Every token span must slice cleanly inside the original text
      for (final s in spans) {
        expect(s.charStart, greaterThanOrEqualTo(0));
        expect(s.charEnd, lessThanOrEqualTo(text.length));
        expect(s.charEnd, greaterThan(s.charStart));
      }

      // Greedy WordPiece splits "SuperSecret99" into ["supers", "##ec", "##ret", ...]
      final expectedStart = text.indexOf('SuperSecret99');
      final expectedEnd = expectedStart + 'SuperSecret99'.length;
      final startIdx = spans.indexWhere((s) => s.charStart == expectedStart);
      final endIdx = spans.indexWhere((s) => s.charEnd == expectedEnd);
      expect(startIdx, greaterThanOrEqualTo(0));
      expect(endIdx, greaterThan(startIdx));
      final reconstructed =
          text.substring(spans[startIdx].charStart, spans[endIdx].charEnd);
      expect(reconstructed, 'SuperSecret99');
    });

    test('strips Latin accents while keeping original indices aligned', () {
      const text = 'Café résumé ID ZX99';
      final spans = tokenizer.tokenizeWithOffsets(text);
      expect(spans.first.token, 'cafe');
      expect(text.substring(spans.first.charStart, spans.first.charEnd), 'Café');
    });

    test('encodeSingle wraps sequence with [CLS] and [SEP] dynamically', () {
      final enc = tokenizer.encodeSingle('my passport number', maxLen: 256);
      expect(enc.inputIds.first, 101); // [CLS]
      expect(enc.inputIds.last, 102); // [SEP]
      expect(enc.length, enc.inputIds.length);
      expect(enc.attentionMask.every((m) => m == 1), isTrue);
      expect(enc.tokenTypeIds.every((t) => t == 0), isTrue);
    });

    test('encodeQuestionContextWindows slides with overlap across long contexts', () {
      final longContext = List.generate(
        120,
        (i) => 'Document clause $i specifies account code AC-${1000 + i}.',
      ).join(' ');

      final windows = tokenizer.encodeQuestionContextWindows(
        'What is the account code in clause 115?',
        longContext,
        maxLen: 128,
        maxQuestionTokens: 24,
        docStride: 32,
      );

      expect(windows.length, greaterThan(2));
      for (final w in windows) {
        expect(w.inputIds.first, 101);
        expect(w.inputIds.last, 102);
        expect(w.length, lessThanOrEqualTo(128));
        expect(w.contextEnd, greaterThanOrEqualTo(w.contextStart));
        // Question & special tokens have null spans; context tokens have non-null spans
        expect(w.spans[0], isNull);
        expect(w.spans[w.contextStart], isNotNull);
        expect(w.spans[w.contextEnd], isNotNull);
        expect(w.spans.last, isNull);
      }

      // Final window covers the end of the long context
      final lastSpan = windows.last.spans[windows.last.contextEnd]!;
      expect(lastSpan.charEnd, longContext.length);
    });
  });

  group('EmbeddingRepository pooling & deterministic fallback', () {
    test('meanPoolAndNormalize masks padded positions and L2-normalizes', () {
      final hidden = <List<double>>[
        [3.0, 0.0, 0.0], // active token 0
        [3.0, 8.0, 0.0], // active token 1 -> mean = [3.0, 4.0, 0.0], norm = 5.0
        [999.0, -999.0, 500.0], // masked pad token (ignored!)
      ];
      final mask = <int>[1, 1, 0];

      final pooled = EmbeddingRepository.meanPoolAndNormalize(hidden, mask);
      expect(pooled.length, 3);
      expect(pooled[0], closeTo(0.6, 1e-6));
      expect(pooled[1], closeTo(0.8, 1e-6));
      expect(pooled[2], closeTo(0.0, 1e-6));

      final normSq = pooled.fold<double>(0.0, (acc, v) => acc + v * v);
      expect(sqrt(normSq), closeTo(1.0, 1e-6));
    });

    test('fallbackEmbedding uses deterministic FNV-1a and captures subword similarity', () {
      final a1 = EmbeddingRepository.fallbackEmbedding('Passport expiry 2031');
      final a2 = EmbeddingRepository.fallbackEmbedding('Passport expiry 2031');
      final morphological = EmbeddingRepository.fallbackEmbedding('Passports expiring 2031');
      final unrelated = EmbeddingRepository.fallbackEmbedding('WiFi router admin login');

      expect(a1, equals(a2));
      expect(a1.length, 384);

      double dot(List<double> x, List<double> y) {
        double s = 0;
        for (int i = 0; i < x.length; i++) {
          s += x[i] * y[i];
        }
        return s;
      }

      expect(dot(a1, morphological), greaterThan(dot(a1, unrelated)));
    });
  });

  group('QaRepository SQuAD2 span decoder', () {
    test('extracts exact case-preserved span and expands split WordPiece subwords', () {
      const question = 'What is my Netflix password?';
      const context =
          'Account: Netflix. Username: user@example.com. Password is SuperSecret99!';

      final enc = tokenizer.encodeQuestionContext(question, context);
      final startLogits = List<double>.filled(enc.length, -8.0);
      final endLogits = List<double>.filled(enc.length, -8.0);

      // Set [CLS] null logits low
      startLogits[0] = -3.0;
      endLogits[0] = -3.0;

      // Peak start logit on interior subword (e.g. "##ret") and end logit on "!"
      // to verify both span extraction AND WordPiece subword boundary expansion!
      final secretOffset = context.indexOf('SuperSecret99');
      final interiorSubIdx = enc.spans.indexWhere(
        (s) =>
            s != null &&
            s.token.startsWith('##') &&
            s.charStart > secretOffset &&
            s.charEnd <= secretOffset + 'SuperSecret99'.length,
      );
      final bangIdx = enc.spans.lastIndexWhere(
        (s) => s != null && s.token == '!',
      );
      expect(interiorSubIdx, greaterThanOrEqualTo(enc.contextStart));
      expect(bangIdx, greaterThanOrEqualTo(interiorSubIdx));

      startLogits[interiorSubIdx] = 9.5;
      endLogits[bangIdx] = 9.2;

      final decoded = QaRepository.decodeSquadSpan(
        startLogits: startLogits,
        endLogits: endLogits,
        encoded: enc,
        originalContext: context,
      );

      expect(decoded, isNotNull);
      expect(decoded!.answer, 'SuperSecret99!');
      expect(decoded.confidence, greaterThan(0.9));
    });

    test('returns null when SQuAD2 [CLS] null score beats all context spans', () {
      const question = 'What is my Swiss bank IBAN?';
      const context = 'Grocery list: milk, eggs, coffee beans.';

      final enc = tokenizer.encodeQuestionContext(question, context);
      final startLogits = List<double>.filled(enc.length, -4.0);
      final endLogits = List<double>.filled(enc.length, -4.0);

      // [CLS] has strong logits indicating unanswerable context
      startLogits[0] = 6.5;
      endLogits[0] = 6.8;
      // Best context span is weak
      startLogits[enc.contextStart] = 1.0;
      endLogits[enc.contextStart] = 1.0;

      final decoded = QaRepository.decodeSquadSpan(
        startLogits: startLogits,
        endLogits: endLogits,
        encoded: enc,
        originalContext: context,
      );

      expect(decoded, isNull);
    });
  });
}
