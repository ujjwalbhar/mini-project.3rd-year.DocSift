import 'text_chunker.dart';

/// Plain-text and Markdown text extractor.
/// Handles .txt and .md files — no external packages needed.
class PlainTextExtractor {
  const PlainTextExtractor._();

  /// Extracts chunks from raw UTF-8 text content.
  static List<String> extractChunks(
    String content, {
    int chunkSize = 1800,
  }) {
    // For markdown, prefer paragraph-based chunking to preserve structure
    if (_looksLikeMarkdown(content)) {
      return TextChunker.chunkByParagraph(content, chunkSize: chunkSize);
    }
    return TextChunker.chunk(content, chunkSize: chunkSize);
  }

  static bool _looksLikeMarkdown(String text) {
    // Heuristic: contains heading markers or bullet lists
    return text.contains(RegExp(r'^#{1,6}\s', multiLine: true)) ||
        text.contains(RegExp(r'^\s*[-*]\s', multiLine: true));
  }
}
