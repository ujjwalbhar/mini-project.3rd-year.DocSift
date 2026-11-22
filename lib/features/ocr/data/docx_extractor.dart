import 'dart:convert';
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

  static const List<int> _ole2Magic = <int>[
    0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1,
  ];

  static const Set<String> _ole2Boilerplate = <String>{
    'root entry',
    'worddocument',
    '1table',
    '0table',
    'data',
    'summaryinformation',
    'documentsummaryinformation',
    'compobj',
    'msworddoc',
    'word.document.8',
    'word.document.12',
    'microsoft word',
    'microsoft office word',
    'normal.dot',
    'normal.dotm',
    'default paragraph font',
    'times new roman',
    'calibri',
    'arial',
  };

  /// Returns `true` when [bytes] starts with the 8-byte OLE2 Compound File
  /// Binary Format header used by legacy Microsoft Word 97–2003 `.doc` files.
  static bool isOle2CompoundDocument(Uint8List bytes) {
    if (bytes.length < _ole2Magic.length) return false;
    for (int i = 0; i < _ole2Magic.length; i++) {
      if (bytes[i] != _ole2Magic[i]) return false;
    }
    return true;
  }

  /// Extracts text from [docxBytes] (OOXML `.docx` ZIP or legacy OLE2 `.doc`)
  /// and returns the full text string.
  static String extractFullText(Uint8List docxBytes) {
    if (isOle2CompoundDocument(docxBytes)) {
      return extractLegacyDocText(docxBytes);
    }

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

    final xmlContent = utf8.decode(
      documentXml.content as List<int>,
      allowMalformed: true,
    );

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

  /// Extracts readable UTF-16LE and CP1252/ASCII document text runs from a
  /// legacy Microsoft Word 97–2003 OLE2 binary `.doc` file, filtering out
  /// OLE2 directory/header metadata boilerplate.
  static String extractLegacyDocText(Uint8List bytes) {
    // Skip 512-byte OLE2 Compound File header when file is larger than 512B
    final startOffset = bytes.length > 512 ? 512 : _ole2Magic.length;
    final segments = <String>[];
    final seen = <String>{};

    void addCandidate(String raw) {
      final normalized = raw
          .replaceAll('\r\n', '\n')
          .replaceAll('\r', '\n')
          .split('\n')
          .map((line) => line.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
          .where((line) => line.isNotEmpty)
          .toList();

      for (final line in normalized) {
        if (line.length < 5) continue;
        final lower = line.toLowerCase();
        if (_ole2Boilerplate.contains(lower)) continue;
        // Require a reasonable ratio of alphanumeric characters to reject binary noise
        final alphaNumCount =
            RegExp(r'[A-Za-z0-9]').allMatches(line).length;
        if (alphaNumCount < 4 || alphaNumCount * 2 < line.length) continue;
        if (seen.add(line)) {
          segments.add(line);
        }
      }
    }

    // 1. Scan 2-byte aligned UTF-16LE runs (Word Unicode piece streams)
    final alignedStart = startOffset.isEven ? startOffset : startOffset + 1;
    final utf16Run = <int>[];
    for (int i = alignedStart; i + 1 < bytes.length; i += 2) {
      final codeUnit = bytes[i] | (bytes[i + 1] << 8);
      if (_isPrintableDocCodeUnit(codeUnit)) {
        utf16Run.add(codeUnit);
      } else {
        if (utf16Run.length >= 5) {
          addCandidate(String.fromCharCodes(utf16Run));
        }
        utf16Run.clear();
      }
    }
    if (utf16Run.length >= 5) {
      addCandidate(String.fromCharCodes(utf16Run));
    }

    // 2. Scan single-byte compressed CP1252 / ASCII runs (Word compressed piece streams)
    final asciiRun = <int>[];
    for (int i = startOffset; i < bytes.length; i++) {
      final b = bytes[i];
      if ((b >= 0x20 && b <= 0x7E) || b == 0x09 || b == 0x0A || b == 0x0D) {
        asciiRun.add(b);
      } else {
        if (asciiRun.length >= 6) {
          addCandidate(String.fromCharCodes(asciiRun));
        }
        asciiRun.clear();
      }
    }
    if (asciiRun.length >= 6) {
      addCandidate(String.fromCharCodes(asciiRun));
    }

    return segments.join('\n').trim();
  }

  static bool _isPrintableDocCodeUnit(int c) {
    if (c == 0x09 || c == 0x0A || c == 0x0D) return true;
    if (c >= 0x20 && c <= 0x7E) return true;
    if (c >= 0xA0 && c <= 0x024F) return true; // Latin-1 + Latin Extended
    if (c >= 0x2013 && c <= 0x2026) return true; // Smart quotes, dashes, bullets
    return false;
  }
}
