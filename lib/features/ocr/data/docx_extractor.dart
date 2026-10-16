import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'text_chunker.dart';

/// Synchronous DOCX text extraction — designed to run inside an Isolate.
///
/// A DOCX file is a ZIP archive containing `word/document.xml`.
/// This extractor unzips the bytes in memory, parses the XML,
/// and pulls out all `<w:t>` text nodes.
class DocxExtractor {
  const DocxExtractor._();

  /// Extracts all text from [docxBytes] and returns a list of text chunks.
  static List<String> extractChunks(
    Uint8List docxBytes, {
    int chunkSize = 1800,
  }) {
    final fullText = extractFullText(docxBytes);
    return TextChunker.chunk(fullText, chunkSize: chunkSize);
  }

  /// Extracts text from [docxBytes] and returns the full text string.
  static String extractFullText(Uint8List docxBytes) {
    late Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(docxBytes);
    } catch (e) {
      throw Exception('Failed to decode DOCX (not a valid ZIP): $e');
    }

    // Find word/document.xml inside the ZIP
    ArchiveFile? documentXml;
    for (final file in archive) {
      if (file.name == 'word/document.xml') {
        documentXml = file;
        break;
      }
    }

    if (documentXml == null) return '';

    final xmlContent = String.fromCharCodes(documentXml.content as List<int>);

    late XmlDocument parsedXml;
    try {
      parsedXml = XmlDocument.parse(xmlContent);
    } catch (_) {
      return '';
    }

    // Extract all <w:t> text nodes, respecting run spacing
    final textNodes = parsedXml.findAllElements('w:t');
    final buffer = StringBuffer();

    for (final node in textNodes) {
      // Check if parent run has xml:space="preserve"
      final text = node.innerText;
      if (text.isNotEmpty) {
        // Add paragraph break when encountering a new <w:p>
        buffer.write(text);
        buffer.write(' ');
      }
    }

    // Also insert newlines at paragraph boundaries for better chunking
    final paragraphs = parsedXml.findAllElements('w:p');
    final paraBuffer = StringBuffer();
    for (final para in paragraphs) {
      final wTexts = para.findAllElements('w:t');
      final paraText = wTexts.map((e) => e.innerText).join('');
      if (paraText.trim().isNotEmpty) {
        paraBuffer.writeln(paraText.trim());
      }
    }

    final result = paraBuffer.toString().trim();
    return result.isNotEmpty ? result : buffer.toString().trim();
  }
}
