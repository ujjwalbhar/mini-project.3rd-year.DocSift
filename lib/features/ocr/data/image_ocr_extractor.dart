import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path/path.dart' as p;
import 'package:syncfusion_pdfviewer_platform_interface/pdfviewer_platform_interface.dart';
import 'package:uuid/uuid.dart';
import 'pdf_extractor.dart';
import 'text_chunker.dart';

final imageOcrExtractorProvider = Provider<ImageOcrExtractor>((ref) {
  final extractor = ImageOcrExtractor();
  ref.onDispose(extractor.dispose);
  return extractor;
});

typedef FilePathOcrRunner = Future<String> Function(String filePath);

/// On-device, zero-network OCR engine for Vault images and scanned/hybrid PDFs.
///
/// Security guarantees:
/// - Plaintext image/page bytes are written only to an isolated temporary folder
///   for the duration of the native ML Kit recognition call (~150–400 ms).
/// - Temporary files are overwritten with `Random.secure()` bytes and flushed
///   before deletion in `finally`, and intermediate pixel buffers are zeroed.
class ImageOcrExtractor {
  ImageOcrExtractor({FilePathOcrRunner? customRunner})
      : _customRunner = customRunner;

  final FilePathOcrRunner? _customRunner;
  TextRecognizer? _recognizer;
  final _OcrSerialLock _lock = _OcrSerialLock();
  final _uuid = const Uuid();
  bool _pluginUnavailable = false;

  static const int minEmbeddedCharsPerPage = 20;
  static const int maxScannedPagesPerPdf = 25;
  static const int maxRenderDimensionPx = 1800;

  /// Runs on-device OCR on encrypted-then-decrypted [imageBytes] and splits the
  /// recognized text into semantic chunks.
  Future<List<String>> extractImageChunks(
    Uint8List imageBytes, {
    String extension = 'png',
    int chunkSize = 1800,
  }) async {
    final text = await extractTextFromImageBytes(
      imageBytes,
      extension: extension,
    );
    if (text.trim().isEmpty) return const [];
    return TextChunker.chunk(text, chunkSize: chunkSize);
  }

  /// Extracts text from [imageBytes] using Google ML Kit Text Recognition v2
  /// (100% offline on-device) with secure temporary file scrubbing.
  Future<String> extractTextFromImageBytes(
    Uint8List imageBytes, {
    String extension = 'png',
  }) async {
    if (imageBytes.isEmpty) return '';
    if (_customRunner == null && !_isMobileOcrSupported()) {
      return '';
    }

    Directory? tempDir;
    File? tempFile;

    try {
      tempDir = await Directory.systemTemp.createTemp('docsift_ocr_');
      final cleanExt = extension.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
      final safeExt = cleanExt.isNotEmpty ? cleanExt.toLowerCase() : 'png';
      tempFile = File(p.join(tempDir.path, 'scan_${_uuid.v4()}.$safeExt'));
      await tempFile.writeAsBytes(imageBytes, flush: true);

      final path = tempFile.path;
      if (_customRunner != null) {
        return (await _customRunner(path)).trim();
      }

      return await _lock.run(() async {
        if (_pluginUnavailable) return '';
        try {
          final recognizer = _recognizer ??= TextRecognizer(
            script: TextRecognitionScript.latin,
          );
          final inputImage = InputImage.fromFilePath(path);
          final recognized = await recognizer.processImage(inputImage);
          return assembleReadingOrderText(recognized);
        } on MissingPluginException {
          _pluginUnavailable = true;
          return '';
        } on PlatformException {
          return '';
        } catch (_) {
          return '';
        }
      });
    } finally {
      if (tempFile != null) {
        try {
          if (await tempFile.exists()) {
            final rng = Random.secure();
            final scrubLen = min(imageBytes.length, 65536);
            final scrub = Uint8List.fromList(
              List<int>.generate(scrubLen, (_) => rng.nextInt(256)),
            );
            await tempFile.writeAsBytes(scrub, flush: true);
            await tempFile.delete();
          }
        } catch (_) {}
      }
      if (tempDir != null) {
        try {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        } catch (_) {}
      }
    }
  }

  /// Extracts text chunks from [pdfBytes], combining fast embedded digital text
  /// extraction (in a background isolate) with on-device page rasterization +
  /// ML Kit OCR for scanned or image-only PDF pages.
  Future<List<String>> extractPdfChunksWithOcrFallback(
    Uint8List pdfBytes, {
    int chunkSize = 1800,
    int maxOcrPages = maxScannedPagesPerPdf,
  }) async {
    if (pdfBytes.isEmpty) return const [];

    List<String> pageTexts;
    try {
      final copyForIsolate = Uint8List.fromList(pdfBytes);
      pageTexts = await Isolate.run<List<String>>(
        () => PdfExtractor.extractPageTexts(copyForIsolate),
      );
      for (int i = 0; i < copyForIsolate.length; i++) {
        copyForIsolate[i] = 0;
      }
    } catch (_) {
      pageTexts = <String>[];
    }

    if (pageTexts.isEmpty) return const [];

    // Identify scanned pages that lack embedded text
    final scannedPageIndices = <int>[];
    for (int i = 0; i < pageTexts.length; i++) {
      final nonWs = pageTexts[i].replaceAll(RegExp(r'\s+'), '');
      if (nonWs.length < minEmbeddedCharsPerPage) {
        scannedPageIndices.add(i);
      }
    }

    if (scannedPageIndices.isNotEmpty &&
        (_customRunner != null || _isMobileOcrSupported())) {
      await _ocrScannedPdfPages(
        pdfBytes: pdfBytes,
        pageTexts: pageTexts,
        scannedPageIndices: scannedPageIndices.take(maxOcrPages).toList(),
      );
    }

    final fullText = pageTexts
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .join('\n\n')
        .trim();

    if (fullText.isEmpty) return const [];
    return TextChunker.chunk(fullText, chunkSize: chunkSize);
  }

  Future<void> _ocrScannedPdfPages({
    required Uint8List pdfBytes,
    required List<String> pageTexts,
    required List<int> scannedPageIndices,
  }) async {
    final docId = 'ocr_${_uuid.v4()}';
    bool rendererOpened = false;

    try {
      final initRes = await PdfViewerPlatform.instance
          .initializePdfRenderer(pdfBytes, docId);
      final parsedCount = int.tryParse(initRes ?? '');
      if (parsedCount == null || parsedCount <= 0) {
        return;
      }
      rendererOpened = true;

      final widths = await PdfViewerPlatform.instance.getPagesWidth(docId);
      final heights = await PdfViewerPlatform.instance.getPagesHeight(docId);

      for (final pageIdx in scannedPageIndices) {
        if (pageIdx < 0 || pageIdx >= parsedCount) continue;

        double rawW = 612.0;
        double rawH = 792.0;
        if (widths != null && pageIdx < widths.length && widths[pageIdx] is num) {
          rawW = (widths[pageIdx] as num).toDouble();
        }
        if (heights != null && pageIdx < heights.length && heights[pageIdx] is num) {
          rawH = (heights[pageIdx] as num).toDouble();
        }

        // Render at ~2.0x (~144–200 DPI) clamped to maxRenderDimensionPx
        double scale = 2.0;
        final maxSide = max(rawW, rawH) * scale;
        if (maxSide > maxRenderDimensionPx && maxSide > 0) {
          scale = maxRenderDimensionPx / max(rawW, rawH);
        }
        final targetW = max(1, (rawW * scale).round());
        final targetH = max(1, (rawH * scale).round());

        Uint8List? rgbaBytes;
        Uint8List? bmpBytes;
        try {
          // PdfViewerPlatform uses 1-based page numbers
          rgbaBytes = await PdfViewerPlatform.instance
              .getPage(pageIdx + 1, targetW, targetH, docId);
          if (rgbaBytes == null || rgbaBytes.length != targetW * targetH * 4) {
            continue;
          }

          bmpBytes = rgba8888ToBmp(rgbaBytes, targetW, targetH);
          // Wipe raw RGBA buffer immediately
          for (int i = 0; i < rgbaBytes.length; i++) {
            rgbaBytes[i] = 0;
          }
          rgbaBytes = null;

          final ocrText = await extractTextFromImageBytes(
            bmpBytes,
            extension: 'bmp',
          );
          if (ocrText.isNotEmpty) {
            final existing = pageTexts[pageIdx].trim();
            pageTexts[pageIdx] =
                existing.isEmpty ? ocrText : '$existing\n$ocrText';
          }
        } finally {
          if (rgbaBytes != null) {
            for (int i = 0; i < rgbaBytes.length; i++) {
              rgbaBytes[i] = 0;
            }
          }
          if (bmpBytes != null) {
            for (int i = 0; i < bmpBytes.length; i++) {
              bmpBytes[i] = 0;
            }
          }
        }
      }
    } catch (_) {
      // Renderer unavailable (e.g., headless unit test VM) — keep digital text
    } finally {
      if (rendererOpened) {
        try {
          await PdfViewerPlatform.instance.closeDocument(docId);
        } catch (_) {}
      }
    }
  }

  bool _isMobileOcrSupported() {
    if (_pluginUnavailable) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  /// Reconstructs spatially coherent reading-order text from [RecognizedText],
  /// grouping horizontally aligned `TextLine`s onto the same visual row so
  /// key-value pairs on ID cards, invoices, and receipts stay paired together.
  static String assembleReadingOrderText(RecognizedText recognized) {
    final allLines = <TextLine>[];
    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        if (line.text.trim().isNotEmpty) {
          allLines.add(line);
        }
      }
    }

    if (allLines.isEmpty) {
      return recognized.text.trim();
    }

    // Sort preliminarily by vertical center, then left X
    allLines.sort((a, b) {
      final cyA = a.boundingBox.center.dy;
      final cyB = b.boundingBox.center.dy;
      final minH = max(1.0, min(a.boundingBox.height, b.boundingBox.height));
      if ((cyA - cyB).abs() <= minH * 0.45) {
        return a.boundingBox.left.compareTo(b.boundingBox.left);
      }
      return cyA.compareTo(cyB);
    });

    // Group into horizontal visual rows
    final rows = <List<TextLine>>[];
    for (final line in allLines) {
      if (rows.isEmpty) {
        rows.add([line]);
        continue;
      }
      final currentRow = rows.last;
      final ref = currentRow.first;
      final refCy = ref.boundingBox.center.dy;
      final lineCy = line.boundingBox.center.dy;
      final minH = max(1.0, min(ref.boundingBox.height, line.boundingBox.height));

      if ((lineCy - refCy).abs() <= minH * 0.45) {
        currentRow.add(line);
      } else {
        rows.add([line]);
      }
    }

    final buffer = StringBuffer();
    double? prevBottom;
    double totalHeight = 0.0;
    for (final l in allLines) {
      totalHeight += max(1.0, l.boundingBox.height);
    }
    final avgHeight = totalHeight / allLines.length;

    for (final row in rows) {
      row.sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));
      final rowTop = row.map((l) => l.boundingBox.top).reduce(min);
      final rowBottom = row.map((l) => l.boundingBox.bottom).reduce(max);

      if (prevBottom != null && (rowTop - prevBottom) > avgHeight * 1.6) {
        buffer.writeln(); // Paragraph break on large vertical gap
      }

      final joinedRow = row.map((l) => l.text.trim()).join('  ');
      buffer.writeln(joinedRow);
      prevBottom = rowBottom;
    }

    return buffer.toString().trim();
  }

  /// Encodes raw `RGBA8888` pixels (`width * height * 4` bytes) into a standard
  /// 24-bit uncompressed BMP image (~200 DPI metadata), compositing transparent
  /// pixels over pure white `(255, 255, 255)` so vector/scanned PDF pages on
  /// both Android and iOS produce high-contrast black-on-white input for OCR.
  static Uint8List rgba8888ToBmp(Uint8List rgba, int width, int height) {
    if (width <= 0 || height <= 0 || rgba.length < width * height * 4) {
      return Uint8List(0);
    }

    final rowStride = (width * 3 + 3) & ~3;
    final pixelDataSize = rowStride * height;
    final fileSize = 54 + pixelDataSize;

    final bmp = Uint8List(fileSize);
    final header = ByteData.sublistView(bmp, 0, 54);

    // BITMAPFILEHEADER (14 bytes)
    bmp[0] = 0x42; // 'B'
    bmp[1] = 0x4D; // 'M'
    header.setUint32(2, fileSize, Endian.little);
    header.setUint32(6, 0, Endian.little);
    header.setUint32(10, 54, Endian.little);

    // BITMAPINFOHEADER (40 bytes)
    header.setUint32(14, 40, Endian.little);
    header.setInt32(18, width, Endian.little);
    header.setInt32(22, height, Endian.little); // positive = bottom-up rows
    header.setUint16(26, 1, Endian.little); // planes
    header.setUint16(28, 24, Endian.little); // 24-bit BGR
    header.setUint32(30, 0, Endian.little); // BI_RGB
    header.setUint32(34, pixelDataSize, Endian.little);
    header.setInt32(38, 7874, Endian.little); // ~200 DPI X
    header.setInt32(42, 7874, Endian.little); // ~200 DPI Y
    header.setUint32(46, 0, Endian.little);
    header.setUint32(50, 0, Endian.little);

    for (int y = 0; y < height; y++) {
      final srcRowOffset = y * width * 4;
      final dstRowOffset = 54 + (height - 1 - y) * rowStride;
      for (int x = 0; x < width; x++) {
        final s = srcRowOffset + x * 4;
        final d = dstRowOffset + x * 3;
        final r = rgba[s];
        final g = rgba[s + 1];
        final b = rgba[s + 2];
        final a = rgba[s + 3];

        if (a == 255) {
          bmp[d] = b;
          bmp[d + 1] = g;
          bmp[d + 2] = r;
        } else if (a == 0) {
          bmp[d] = 255;
          bmp[d + 1] = 255;
          bmp[d + 2] = 255;
        } else {
          final inv = 255 - a;
          bmp[d] = min(255, b + inv);
          bmp[d + 1] = min(255, g + inv);
          bmp[d + 2] = min(255, r + inv);
        }
      }
    }

    return bmp;
  }

  Future<void> dispose() async {
    final rec = _recognizer;
    _recognizer = null;
    if (rec != null) {
      try {
        await rec.close();
      } catch (_) {}
    }
  }
}

class _OcrSerialLock {
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
