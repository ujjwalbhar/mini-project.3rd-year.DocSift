import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' hide TextLine;
import 'package:syncfusion_pdfviewer_platform_interface/pdfviewer_platform_interface.dart';
import 'package:docsift/features/ocr/data/image_ocr_extractor.dart';
import 'package:docsift/features/vault/domain/models/vault_item.dart';

class _FakePdfViewerPlatform extends PdfViewerPlatform {
  final List<int> renderedOneBasedPages = [];
  bool closed = false;
  int pageCount = 0;

  @override
  Future<String?> initializePdfRenderer(
      Uint8List documentBytes, String documentID) async {
    return pageCount.toString();
  }

  @override
  Future<List?> getPagesWidth(String documentID) async {
    return List<double>.filled(pageCount, 100.0);
  }

  @override
  Future<List?> getPagesHeight(String documentID) async {
    return List<double>.filled(pageCount, 100.0);
  }

  @override
  Future<Uint8List?> getPage(
      int pageNumber, int width, int height, String documentID) async {
    renderedOneBasedPages.add(pageNumber);
    // Return valid RGBA8888 buffer (opaque white with a black pixel)
    final buf = Uint8List(width * height * 4);
    for (int i = 0; i < buf.length; i += 4) {
      buf[i] = 255;
      buf[i + 1] = 255;
      buf[i + 2] = 255;
      buf[i + 3] = 255;
    }
    buf[0] = 0;
    buf[1] = 0;
    buf[2] = 0;
    return buf;
  }

  @override
  Future<void> closeDocument(String documentID) async {
    closed = true;
  }
}

TextLine _line(String text, double left, double top, double right, double bottom) {
  return TextLine(
    text: text,
    elements: const [],
    boundingBox: Rect.fromLTRB(left, top, right, bottom),
    recognizedLanguages: const ['en'],
    cornerPoints: <Point<int>>[
      Point(left.round(), top.round()),
      Point(right.round(), top.round()),
      Point(right.round(), bottom.round()),
      Point(left.round(), bottom.round()),
    ],
    confidence: 0.98,
    angle: 0.0,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FileType & extractability classification', () {
    test('classifies modern image extensions as extractable FileType.image', () {
      for (final ext in ['jpg', 'jpeg', 'png', 'webp', 'bmp', 'heic', 'heif']) {
        final type = fileTypeFromExtension(ext);
        expect(type, FileType.image, reason: 'ext=$ext');
        expect(isExtractableFileType(type), isTrue);
      }
      expect(isExtractableFileType(FileType.video), isFalse);
      expect(isExtractableFileType(FileType.zip), isFalse);
      expect(isExtractableFileType(FileType.other), isFalse);
    });
  });

  group('ImageOcrExtractor.rgba8888ToBmp', () {
    test('encodes valid 24-bit padded BMP and composites transparent pixels onto white', () {
      // 3x2 image -> rowStride = (3*3 + 3) & ~3 = 12 bytes/row, pixelData = 24, total = 78
      final rgba = Uint8List.fromList([
        // Top row (y = 0):
        // Pixel (0,0): opaque red (255, 0, 0, 255)
        255, 0, 0, 255,
        // Pixel (1,0): transparent iOS background (0, 0, 0, 0) -> must become white (255,255,255)
        0, 0, 0, 0,
        // Pixel (2,0): opaque black ink (0, 0, 0, 255)
        0, 0, 0, 255,

        // Bottom row (y = 1): all opaque blue (0, 0, 255, 255)
        0, 0, 255, 255,
        0, 0, 255, 255,
        0, 0, 255, 255,
      ]);

      final bmp = ImageOcrExtractor.rgba8888ToBmp(rgba, 3, 2);
      expect(bmp.length, 54 + 24);
      expect(bmp[0], 0x42); // 'B'
      expect(bmp[1], 0x4D); // 'M'

      final header = ByteData.sublistView(bmp, 0, 54);
      expect(header.getUint32(2, Endian.little), 78);
      expect(header.getUint32(10, Endian.little), 54);
      expect(header.getInt32(18, Endian.little), 3);
      expect(header.getInt32(22, Endian.little), 2);
      expect(header.getUint16(28, Endian.little), 24);

      // Bottom-up BMP: first scanline at offset 54 is y = 1 (opaque blue -> BGR = 255, 0, 0)
      expect(bmp.sublist(54, 57), [255, 0, 0]);

      // Second scanline at offset 54 + 12 = 66 is y = 0:
      // Pixel (0,0) red -> BGR = [0, 0, 255]
      expect(bmp.sublist(66, 69), [0, 0, 255]);
      // Pixel (1,0) transparent -> composited white BGR = [255, 255, 255]
      expect(bmp.sublist(69, 72), [255, 255, 255]);
      // Pixel (2,0) black ink -> BGR = [0, 0, 0]
      expect(bmp.sublist(72, 75), [0, 0, 0]);
    });
  });

  group('ImageOcrExtractor.assembleReadingOrderText', () {
    test('pairs horizontally aligned key-value columns and separates distant paragraphs', () {
      // Simulate ML Kit returning left labels in Block 1 and right values in Block 2
      final labelsBlock = TextBlock(
        text: 'Passport No.\nExpiry Date',
        lines: [
          _line('Passport No.', 20, 100, 140, 122),
          _line('Expiry Date', 20, 140, 130, 162),
        ],
        boundingBox: const Rect.fromLTRB(20, 100, 140, 162),
        recognizedLanguages: const ['en'],
        cornerPoints: const [],
      );

      final valuesBlock = TextBlock(
        text: 'Z8291044\n14/08/2032',
        lines: [
          _line('Z8291044', 220, 102, 340, 123),
          _line('14/08/2032', 220, 141, 340, 162),
        ],
        boundingBox: const Rect.fromLTRB(220, 102, 340, 162),
        recognizedLanguages: const ['en'],
        cornerPoints: const [],
      );

      final footerBlock = TextBlock(
        text: 'Issued by Republic of India',
        lines: [
          _line('Issued by Republic of India', 20, 240, 320, 262),
        ],
        boundingBox: const Rect.fromLTRB(20, 240, 320, 262),
        recognizedLanguages: const ['en'],
        cornerPoints: const [],
      );

      final recognized = RecognizedText(
        text: 'raw unordered',
        blocks: [valuesBlock, footerBlock, labelsBlock],
      );

      final assembled = ImageOcrExtractor.assembleReadingOrderText(recognized);
      expect(
        assembled,
        'Passport No.  Z8291044\n'
        'Expiry Date  14/08/2032\n'
        '\n'
        'Issued by Republic of India',
      );
    });
  });

  group('Zero-trust temporary file lifecycle & Hybrid/Scanned PDF OCR', () {
    test('scrubs and deletes temporary OCR image file even after completion or failure', () async {
      String? capturedPath;
      final extractor = ImageOcrExtractor(
        customRunner: (filePath) async {
          capturedPath = filePath;
          expect(await File(filePath).exists(), isTrue);
          return 'Driver License Number DL-998877';
        },
      );

      final payload = Uint8List.fromList(List<int>.generate(256, (i) => i % 251));
      final chunks = await extractor.extractImageChunks(payload, extension: 'jpg');

      expect(chunks, isNotEmpty);
      expect(chunks.first, contains('DL-998877'));
      expect(capturedPath, isNotNull);
      expect(await File(capturedPath!).exists(), isFalse);
      expect(await File(capturedPath!).parent.exists(), isFalse);
    });

    test('rasterizes ONLY scanned PDF pages while preserving digital PDF pages in order', () async {
      // Build a real 2-page PDF: Page 1 has digital text, Page 2 is blank/scanned
      final doc = PdfDocument();
      final page1 = doc.pages.add();
      page1.graphics.drawString(
        'Digital Page One: Primary Holder Ujjwal Bhardwaj.',
        PdfStandardFont(PdfFontFamily.helvetica, 12),
      );
      doc.pages.add(); // Page 2 has zero embedded text (simulating scanned image page)
      final pdfBytes = Uint8List.fromList(await doc.save());
      doc.dispose();

      final fakePlatform = _FakePdfViewerPlatform()..pageCount = 2;
      final previousPlatform = PdfViewerPlatform.instance;
      PdfViewerPlatform.instance = fakePlatform;

      try {
        final extractor = ImageOcrExtractor(
          customRunner: (bmpPath) async {
            final bytes = await File(bmpPath).readAsBytes();
            // Verify valid BMP header was written for ML Kit
            expect(bytes[0], 0x42);
            expect(bytes[1], 0x4D);
            return 'Scanned Page Two: Passport Number Z8291044.';
          },
        );

        final chunks = await extractor.extractPdfChunksWithOcrFallback(pdfBytes);
        final combined = chunks.join('\n');

        // Page 1 had digital text -> only Page 2 (1-based index 2) was rasterized!
        expect(fakePlatform.renderedOneBasedPages, [2]);
        expect(fakePlatform.closed, isTrue);
        expect(combined, contains('Primary Holder Ujjwal Bhardwaj'));
        expect(combined, contains('Passport Number Z8291044'));
        expect(
          combined.indexOf('Primary Holder'),
          lessThan(combined.indexOf('Passport Number')),
        );
      } finally {
        PdfViewerPlatform.instance = previousPlatform;
      }
    });
  });
}
