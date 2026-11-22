import 'dart:typed_data';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'text_chunker.dart';

/// Synchronous PDF text extraction — designed to run inside an Isolate.
///
/// Takes the raw decrypted bytes of a PDF and returns a list of text
/// chunks (~1800 chars / ~450 tokens each). This function MUST NOT
/// be called on the main thread.
class PdfExtractor {
  const PdfExtractor._();

  /// Extracts all text from [pdfBytes] and returns a list of chunks.
  static List<String> extractChunks(
    Uint8List pdfBytes, {
    int chunkSize = 1800,
  }) {
    final fullText = extractFullText(pdfBytes);
    return TextChunker.chunk(fullText, chunkSize: chunkSize);
  }

  /// Extracts embedded digital text for each page (index `0 .. pageCount - 1`).
  /// Pages with no embedded text (e.g., scanned image pages) yield `''`,
  /// allowing the caller to run on-device OCR selectively on those pages.
  static List<String> extractPageTexts(Uint8List pdfBytes) {
    final PdfDocument doc;
    try {
      doc = PdfDocument(inputBytes: pdfBytes);
    } catch (e) {
      throw Exception('Failed to parse PDF: $e');
    }

    final pageTexts = <String>[];
    final extractor = PdfTextExtractor(doc);

    for (int i = 0; i < doc.pages.count; i++) {
      try {
        final pageText = extractor.extractText(
          startPageIndex: i,
          endPageIndex: i,
        );
        pageTexts.add(pageText.trim());
      } catch (_) {
        pageTexts.add('');
      }
    }

    doc.dispose();
    return pageTexts;
  }

  /// Extracts full text from all pages of the PDF.
  static String extractFullText(Uint8List pdfBytes) {
    final pages = extractPageTexts(pdfBytes);
    return pages.where((p) => p.isNotEmpty).join('\n\n').trim();
  }
}
