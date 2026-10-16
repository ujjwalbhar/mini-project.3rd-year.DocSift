/// Shared text chunking utility used by all extractors.
/// Splits a long string into overlapping chunks at natural sentence boundaries.
class TextChunker {
  const TextChunker._();

  /// Splits [text] into chunks of approximately [chunkSize] characters.
  /// Prefers to split at sentence-ending punctuation ('. ', '! ', '? ', '\n\n').
  /// Optionally adds an [overlap] of characters from the previous chunk to
  /// preserve context across chunk boundaries (useful for Q&A accuracy).
  static List<String> chunk(
    String text, {
    int chunkSize = 1800,
    int overlap = 200,
  }) {
    final chunks = <String>[];
    final normalized = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .trim();

    if (normalized.isEmpty) return chunks;

    int start = 0;
    while (start < normalized.length) {
      int end = (start + chunkSize).clamp(0, normalized.length);

      if (end < normalized.length) {
        // Search backwards for a good break point
        final slice = normalized.substring(start, end);
        
        // Prefer double-newline (paragraph break)
        int breakPoint = slice.lastIndexOf('\n\n');
        
        // Fall back to sentence-ending punctuation
        if (breakPoint < chunkSize ~/ 2) {
          for (final sentinel in ['. ', '! ', '? ', '\n']) {
            final idx = slice.lastIndexOf(sentinel);
            if (idx > chunkSize ~/ 2) {
              breakPoint = idx + sentinel.length;
              break;
            }
          }
        } else {
          breakPoint += 2; // skip past the \n\n
        }

        if (breakPoint > chunkSize ~/ 2) {
          end = start + breakPoint;
        }
      }

      final chunk = normalized.substring(start, end).trim();
      if (chunk.isNotEmpty) {
        chunks.add(chunk);
      }

      // Move start with overlap to preserve context
      start = end - (end < normalized.length ? overlap : 0);
    }

    return chunks;
  }

  /// Splits text into chunks by paragraph first, then merges short paragraphs
  /// until the chunk size is reached. Good for structured documents.
  static List<String> chunkByParagraph(
    String text, {
    int chunkSize = 1800,
  }) {
    final paragraphs = text
        .split(RegExp(r'\n{2,}'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();

    final chunks = <String>[];
    final buffer = StringBuffer();

    for (final para in paragraphs) {
      if (buffer.length + para.length > chunkSize && buffer.isNotEmpty) {
        chunks.add(buffer.toString().trim());
        buffer.clear();
      }
      buffer.writeln(para);
    }

    if (buffer.isNotEmpty) {
      chunks.add(buffer.toString().trim());
    }

    return chunks;
  }
}
