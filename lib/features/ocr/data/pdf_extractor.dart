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

  /// Extracts full text from all pages of the PDF.
  static String extractFullText(Uint8List pdfBytes) {
    final PdfDocument doc;
    try {
      doc = PdfDocument(inputBytes: pdfBytes);
    } catch (e) {
      throw Exception('Failed to parse PDF: $e');
    }

    final buffer = StringBuffer();
    final extractor = PdfTextExtractor(doc);

    for (int i = 0; i < doc.pages.count; i++) {
      try {
        final pageText = extractor.extractText(
          startPageIndex: i,
          endPageIndex: i,
        );
        if (pageText.trim().isNotEmpty) {
          buffer.writeln(pageText.trim());
          buffer.writeln(); // paragraph separator
        }
      } catch (_) {
        // Skip pages that fail to extract
      }
    }

    doc.dispose();
    return buffer.toString().trim();
  }
}
