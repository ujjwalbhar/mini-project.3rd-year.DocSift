import 'dart:math';
import 'dart:typed_data';

/// A single WordPiece token mapped back to its exact character range in the
/// original (unmodified, case-preserved) source string.
class TokenSpan {
  const TokenSpan({
    required this.id,
    required this.token,
    required this.charStart,
    required this.charEnd,
  });

  final int id;
  final String token;
  final int charStart;
  final int charEnd;
}

/// Encoded single-sequence inputs for BERT/MiniLM (`[CLS] text [SEP]`).
class EncodedSingle {
  const EncodedSingle({
    required this.inputIds,
    required this.attentionMask,
    required this.tokenTypeIds,
    required this.length,
  });

  final Int64List inputIds;
  final Int64List attentionMask;
  final Int64List tokenTypeIds;
  final int length;
}

/// Encoded question-context window for DistilBERT SQuAD2
/// (`[CLS] question [SEP] context_window [SEP]`).
class EncodedPair {
  const EncodedPair({
    required this.inputIds,
    required this.attentionMask,
    required this.length,
    required this.contextStart,
    required this.contextEnd,
    required this.spans,
  });

  final Int64List inputIds;
  final Int64List attentionMask;
  final int length;

  /// Inclusive start token index of context tokens in [inputIds].
  final int contextStart;

  /// Inclusive end token index of context tokens in [inputIds].
  /// When context is empty, `contextEnd < contextStart`.
  final int contextEnd;

  /// Parallel to [inputIds]; non-null for context token positions so predicted
  /// `(start, end)` indices map back to exact slices in the original context.
  final List<TokenSpan?> spans;
}

/// Pure-Dart `bert-base-uncased` WordPiece tokenizer compatible with both
/// `all-MiniLM-L6-v2` (`minilm.onnx`) and `distilbert-base-uncased-squad2`
/// (`distilbert_squad2.onnx`).
class WordPieceTokenizer {
  WordPieceTokenizer._(
    this._vocab, {
    required this.padId,
    required this.unkId,
    required this.clsId,
    required this.sepId,
  });

  factory WordPieceTokenizer.fromVocabString(String vocabContent) {
    final map = <String, int>{};
    final lines = vocabContent.split('\n');
    int id = 0;
    for (int i = 0; i < lines.length; i++) {
      var line = lines[i];
      if (line.endsWith('\r')) {
        line = line.substring(0, line.length - 1);
      }
      // Trailing newline at EOF after 30,522 lines should be ignored
      if (line.isEmpty && i == lines.length - 1) {
        continue;
      }
      map[line] = id++;
    }
    return WordPieceTokenizer._(
      map,
      padId: map['[PAD]'] ?? 0,
      unkId: map['[UNK]'] ?? 100,
      clsId: map['[CLS]'] ?? 101,
      sepId: map['[SEP]'] ?? 102,
    );
  }

  static const int maxInputCharsPerWord = 100;

  final Map<String, int> _vocab;
  final int padId;
  final int unkId;
  final int clsId;
  final int sepId;

  int get vocabSize => _vocab.length;

  int? tokenToId(String token) => _vocab[token];

  /// Tokenizes [text] using BERT uncased basic + WordPiece rules while
  /// preserving exact `[charStart, charEnd)` offsets into [text].
  List<TokenSpan> tokenizeWithOffsets(String text) {
    if (text.isEmpty) return const [];

    final results = <TokenSpan>[];
    final len = text.length;
    int i = 0;

    while (i < len) {
      final code = text.codeUnitAt(i);

      // Skip whitespace and control characters
      if (_isWhitespaceOrControl(code)) {
        i++;
        continue;
      }

      // Single-character punctuation or CJK ideograph basic token
      if (_isPunctuation(code) || _isCjk(code)) {
        final start = i;
        final end = i + 1;
        final raw = text.substring(start, end).toLowerCase();
        final tokenId = _vocab[raw] ?? unkId;
        results.add(TokenSpan(
          id: tokenId,
          token: _vocab.containsKey(raw) ? raw : '[UNK]',
          charStart: start,
          charEnd: end,
        ));
        i = end;
        continue;
      }

      // Contiguous word token up to next whitespace/control/punctuation/CJK
      final wordStart = i;
      while (i < len) {
        final c = text.codeUnitAt(i);
        if (_isWhitespaceOrControl(c) || _isPunctuation(c) || _isCjk(c)) {
          break;
        }
        i++;
      }
      final wordEnd = i;
      _tokenizeWord(text, wordStart, wordEnd, results);
    }

    return results;
  }

  void _tokenizeWord(
    String fullText,
    int wordStart,
    int wordEnd,
    List<TokenSpan> out,
  ) {
    final wordLen = wordEnd - wordStart;
    if (wordLen <= 0) return;
    if (wordLen > maxInputCharsPerWord) {
      out.add(TokenSpan(
        id: unkId,
        token: '[UNK]',
        charStart: wordStart,
        charEnd: wordEnd,
      ));
      return;
    }

    // Build normalized lowercase characters while tracking exact UTF-16
    // offsets back into fullText.
    final normBuffer = StringBuffer();
    final charStarts = <int>[];
    final charEnds = <int>[];

    for (int idx = wordStart; idx < wordEnd; idx++) {
      final unit = fullText.codeUnitAt(idx);
      // Skip combining diacritical marks (U+0300..U+036F) and zero-width format chars
      if ((unit >= 0x0300 && unit <= 0x036F) ||
          unit == 0x200B ||
          unit == 0xFEFF ||
          unit == 0x00AD) {
        if (charEnds.isNotEmpty) {
          charEnds[charEnds.length - 1] = idx + 1;
        }
        continue;
      }

      // Handle surrogate pairs cleanly
      String ch;
      int nextIdx = idx + 1;
      if (unit >= 0xD800 && unit <= 0xDBFF && idx + 1 < wordEnd) {
        final low = fullText.codeUnitAt(idx + 1);
        if (low >= 0xDC00 && low <= 0xDFFF) {
          ch = fullText.substring(idx, idx + 2);
          nextIdx = idx + 2;
        } else {
          ch = String.fromCharCode(unit);
        }
      } else {
        ch = _stripLatinAccent(unit);
      }

      final lowered = ch.toLowerCase();
      for (int k = 0; k < lowered.length; k++) {
        normBuffer.write(lowered[k]);
        charStarts.add(idx);
        charEnds.add(nextIdx);
      }
      idx = nextIdx - 1;
    }

    final norm = normBuffer.toString();
    if (norm.isEmpty) return;

    final subTokens = <TokenSpan>[];
    int pos = 0;
    bool isBad = false;

    while (pos < norm.length) {
      int end = norm.length;
      int? matchedId;
      String? matchedSub;

      while (pos < end) {
        final slice = norm.substring(pos, end);
        final candidate = pos == 0 ? slice : '##$slice';
        final id = _vocab[candidate];
        if (id != null) {
          matchedId = id;
          matchedSub = candidate;
          break;
        }
        end--;
      }

      if (matchedId == null || matchedSub == null) {
        isBad = true;
        break;
      }

      subTokens.add(TokenSpan(
        id: matchedId,
        token: matchedSub,
        charStart: charStarts[pos],
        charEnd: charEnds[end - 1],
      ));
      pos = end;
    }

    if (isBad) {
      out.add(TokenSpan(
        id: unkId,
        token: '[UNK]',
        charStart: wordStart,
        charEnd: wordEnd,
      ));
    } else {
      out.addAll(subTokens);
    }
  }

  /// Encodes a single text sequence `[CLS] + tokens + [SEP]` up to [maxLen].
  EncodedSingle encodeSingle(String text, {int maxLen = 256}) {
    final safeMax = maxLen.clamp(4, 512);
    final tokens = tokenizeWithOffsets(text);
    final count = min(tokens.length, safeMax - 2);
    final seqLen = count + 2;

    final inputIds = Int64List(seqLen);
    final attentionMask = Int64List(seqLen);
    final tokenTypeIds = Int64List(seqLen);

    inputIds[0] = clsId;
    attentionMask[0] = 1;

    for (int i = 0; i < count; i++) {
      inputIds[i + 1] = tokens[i].id;
      attentionMask[i + 1] = 1;
    }

    inputIds[seqLen - 1] = sepId;
    attentionMask[seqLen - 1] = 1;

    return EncodedSingle(
      inputIds: inputIds,
      attentionMask: attentionMask,
      tokenTypeIds: tokenTypeIds,
      length: seqLen,
    );
  }

  /// Encodes the first window of `[CLS] + question + [SEP] + context + [SEP]`.
  EncodedPair encodeQuestionContext(
    String question,
    String context, {
    int maxLen = 384,
    int maxQuestionTokens = 64,
  }) {
    return encodeQuestionContextWindows(
      question,
      context,
      maxLen: maxLen,
      maxQuestionTokens: maxQuestionTokens,
    ).first;
  }

  /// Encodes `[CLS] + question + [SEP] + context_window + [SEP]` across
  /// overlapping windows (`[docStride]`) so multi-chunk contexts are evaluated
  /// without truncating answers near the end of the retrieved context.
  List<EncodedPair> encodeQuestionContextWindows(
    String question,
    String context, {
    int maxLen = 384,
    int maxQuestionTokens = 64,
    int docStride = 128,
  }) {
    final safeMax = maxLen.clamp(16, 512);
    final qAll = tokenizeWithOffsets(question);
    final qCap = min(maxQuestionTokens, safeMax - 5);
    final qTokens = qAll.length > qCap ? qAll.sublist(0, qCap) : qAll;

    final cTokens = tokenizeWithOffsets(context);
    final maxContextLen = max(1, safeMax - qTokens.length - 3);

    if (cTokens.isEmpty) {
      final seqLen = qTokens.length + 3;
      final inputIds = Int64List(seqLen);
      final attentionMask = Int64List(seqLen);
      final spans = List<TokenSpan?>.filled(seqLen, null);

      inputIds[0] = clsId;
      attentionMask[0] = 1;
      for (int i = 0; i < qTokens.length; i++) {
        inputIds[i + 1] = qTokens[i].id;
        attentionMask[i + 1] = 1;
      }
      inputIds[qTokens.length + 1] = sepId;
      attentionMask[qTokens.length + 1] = 1;
      inputIds[qTokens.length + 2] = sepId;
      attentionMask[qTokens.length + 2] = 1;

      return [
        EncodedPair(
          inputIds: inputIds,
          attentionMask: attentionMask,
          length: seqLen,
          contextStart: qTokens.length + 2,
          contextEnd: qTokens.length + 1,
          spans: spans,
        ),
      ];
    }

    final windows = <EncodedPair>[];
    final step = max(1, maxContextLen - docStride);
    int winStart = 0;

    while (winStart < cTokens.length) {
      final winEnd = min(winStart + maxContextLen, cTokens.length);
      final winCount = winEnd - winStart;
      final seqLen = qTokens.length + winCount + 3;

      final inputIds = Int64List(seqLen);
      final attentionMask = Int64List(seqLen);
      final spans = List<TokenSpan?>.filled(seqLen, null);

      int cursor = 0;
      inputIds[cursor] = clsId;
      attentionMask[cursor] = 1;
      cursor++;

      for (int i = 0; i < qTokens.length; i++) {
        inputIds[cursor] = qTokens[i].id;
        attentionMask[cursor] = 1;
        cursor++;
      }

      inputIds[cursor] = sepId;
      attentionMask[cursor] = 1;
      cursor++;

      final contextStart = cursor;
      for (int i = winStart; i < winEnd; i++) {
        inputIds[cursor] = cTokens[i].id;
        attentionMask[cursor] = 1;
        spans[cursor] = cTokens[i];
        cursor++;
      }
      final contextEnd = cursor - 1;

      inputIds[cursor] = sepId;
      attentionMask[cursor] = 1;

      windows.add(EncodedPair(
        inputIds: inputIds,
        attentionMask: attentionMask,
        length: seqLen,
        contextStart: contextStart,
        contextEnd: contextEnd,
        spans: spans,
      ));

      if (winEnd >= cTokens.length) break;
      winStart += step;
    }

    return windows;
  }

  static bool _isWhitespaceOrControl(int c) {
    if (c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x00A0) {
      return true;
    }
    if (c <= 0x1F || (c >= 0x7F && c <= 0x9F)) {
      return true;
    }
    return c >= 0x2000 && c <= 0x200A;
  }

  static bool _isPunctuation(int c) {
    if ((c >= 33 && c <= 47) ||
        (c >= 58 && c <= 64) ||
        (c >= 91 && c <= 96) ||
        (c >= 123 && c <= 126)) {
      return true;
    }
    // General Unicode punctuation block (quotes, dashes, bullets, currency)
    return (c >= 0x2010 && c <= 0x2027) || (c >= 0x2030 && c <= 0x205E);
  }

  static bool _isCjk(int c) {
    return (c >= 0x4E00 && c <= 0x9FFF) ||
        (c >= 0x3400 && c <= 0x4DBF) ||
        (c >= 0xF900 && c <= 0xFAFF);
  }

  static String _stripLatinAccent(int c) {
    // Common precomposed Latin-1 / Latin Extended-A characters -> ASCII base
    if (c < 0x00C0 || c > 0x017F) return String.fromCharCode(c);
    const map = <int, String>{
      0x00C0: 'a', 0x00C1: 'a', 0x00C2: 'a', 0x00C3: 'a', 0x00C4: 'a', 0x00C5: 'a',
      0x00E0: 'a', 0x00E1: 'a', 0x00E2: 'a', 0x00E3: 'a', 0x00E4: 'a', 0x00E5: 'a',
      0x00C7: 'c', 0x00E7: 'c',
      0x00C8: 'e', 0x00C9: 'e', 0x00CA: 'e', 0x00CB: 'e',
      0x00E8: 'e', 0x00E9: 'e', 0x00EA: 'e', 0x00EB: 'e',
      0x00CC: 'i', 0x00CD: 'i', 0x00CE: 'i', 0x00CF: 'i',
      0x00EC: 'i', 0x00ED: 'i', 0x00EE: 'i', 0x00EF: 'i',
      0x00D1: 'n', 0x00F1: 'n',
      0x00D2: 'o', 0x00D3: 'o', 0x00D4: 'o', 0x00D5: 'o', 0x00D6: 'o',
      0x00F2: 'o', 0x00F3: 'o', 0x00F4: 'o', 0x00F5: 'o', 0x00F6: 'o',
      0x00D9: 'u', 0x00DA: 'u', 0x00DB: 'u', 0x00DC: 'u',
      0x00F9: 'u', 0x00FA: 'u', 0x00FB: 'u', 0x00FC: 'u',
      0x00DD: 'y', 0x00FD: 'y', 0x00FF: 'y',
    };
    return map[c] ?? String.fromCharCode(c);
  }
}

