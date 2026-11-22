import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/providers/database_provider.dart';
import '../../ai/data/embedding_repository.dart';
import '../../vault/data/vault_repository.dart';
import '../../vault/domain/models/vault_item.dart';
import '../../vault/domain/models/vault_templates.dart';
import 'pdf_extractor.dart';
import 'docx_extractor.dart';
import 'plain_text_extractor.dart';
import 'image_ocr_extractor.dart';

final ocrRepositoryProvider = Provider<OcrRepository>((ref) {
  final dbProvider = ref.read(databaseProvider);
  final vaultRepo = ref.read(vaultRepositoryProvider);
  final embeddingRepo = ref.read(embeddingRepositoryProvider);
  final imageOcr = ref.read(imageOcrExtractorProvider);
  return OcrRepository(dbProvider, vaultRepo, embeddingRepo, imageOcr);
});


// ── OcrRepository ────────────────────────────────────────────────────────────

/// Orchestrates text extraction from vault files and saves chunks to SQLite.
///
/// Extraction flow:
/// 1. Look up vault item in DB
/// 2. Decrypt file bytes on main isolate (VEK is in-memory, safe here)
/// 3. Run on-device ML Kit OCR (for images & scanned PDF pages) or background
///    isolate parsing (for digital PDF / DOCX / TXT / MD / JSON)
/// 4. Save chunks + MiniLM embeddings to text_chunks table
/// 5. Update extraction_status on vault_item
class OcrRepository {
  OcrRepository(
    this._dbProvider,
    this._vaultRepo, [
    this._embeddingRepo,
    this._imageOcrExtractor,
  ]);

  final DatabaseProvider _dbProvider;
  final VaultRepository _vaultRepo;
  final EmbeddingRepository? _embeddingRepo;
  final ImageOcrExtractor? _imageOcrExtractor;
  final _uuid = const Uuid();

  /// Extracts text from the given [item], saves chunks to DB, and updates
  /// the item's extraction status. Streams progress (0.0–1.0).
  Stream<double> extractAndSave(VaultItem item) async* {
    final db = await _dbProvider.database;

    // Mark as processing
    await db.update(
      'vault_items',
      {'extraction_status': ExtractionStatus.processing.name},
      where: 'id = ?',
      whereArgs: [item.id],
    );

    yield 0.05;

    Uint8List? plainBytes;
    try {
      // Step 1: Decrypt the file to memory (on main thread — VEK is here)
      plainBytes = await _vaultRepo.decryptToMemory(item.encryptedFilePath);
      yield 0.2;

      // Step 2: Extract text (on-device ML Kit OCR for images / scanned PDFs,
      // background isolate for DOCX / TXT / MD / JSON)
      final List<String> chunks;
      if (item.fileType == FileType.image) {
        final ocr = _imageOcrExtractor ?? ImageOcrExtractor();
        chunks = await ocr.extractImageChunks(
          plainBytes,
          extension: item.originalExtension,
        );
      } else if (item.fileType == FileType.pdf) {
        final ocr = _imageOcrExtractor ?? ImageOcrExtractor();
        chunks = await ocr.extractPdfChunksWithOcrFallback(plainBytes);
      } else {
        chunks = await _extractInIsolate(plainBytes, item.fileType);
      }
      yield 0.7;

      // Wipe plain bytes from memory as soon as extraction finishes
      for (int i = 0; i < plainBytes.length; i++) {
        plainBytes[i] = 0;
      }
      plainBytes = null;

      // Remove any previous chunks for this item (e.g., when re-indexing after an edit)
      await db.delete(
        'text_chunks',
        where: 'vault_item_id = ?',
        whereArgs: [item.id],
      );

      if (chunks.isEmpty) {
        await db.update(
          'vault_items',
          {'extraction_status': ExtractionStatus.done.name},
          where: 'id = ?',
          whereArgs: [item.id],
        );
        yield 1.0;
        return;
      }

      // Step 3: Save chunks & Float32List embeddings to DB
      final batch = db.batch();
      for (int i = 0; i < chunks.length; i++) {
        Uint8List? embeddingBlob;
        if (_embeddingRepo != null) {
          final vec = await _embeddingRepo.generateEmbedding(chunks[i]);
          embeddingBlob = _embeddingRepo.encodeEmbedding(vec);
        }
        batch.insert('text_chunks', {
          'id': _uuid.v4(),
          'vault_item_id': item.id,
          'chunk_index': i,
          'content': chunks[i],
          'embedding': embeddingBlob,
        });
        yield 0.7 + (0.25 * i / chunks.length);
      }
      await batch.commit(noResult: true);

      // Step 4: Mark done
      await db.update(
        'vault_items',
        {'extraction_status': ExtractionStatus.done.name},
        where: 'id = ?',
        whereArgs: [item.id],
      );

      yield 1.0;
    } catch (e) {
      await db.update(
        'vault_items',
        {'extraction_status': ExtractionStatus.failed.name},
        where: 'id = ?',
        whereArgs: [item.id],
      );
      yield 1.0;
      rethrow;
    } finally {
      if (plainBytes != null) {
        for (int i = 0; i < plainBytes.length; i++) {
          plainBytes[i] = 0;
        }
      }
    }
  }

  /// Marks non-text binary items (e.g. videos, archives) as done so they do not
  /// remain perpetually pending in SQLite.
  Future<void> markDoneWithoutExtraction(String vaultItemId) async {
    final db = await _dbProvider.database;
    await db.update(
      'vault_items',
      {'extraction_status': ExtractionStatus.done.name},
      where: 'id = ?',
      whereArgs: [vaultItemId],
    );
  }

  /// Runs the actual text extraction in a spawned Dart isolate.
  /// The bytes are passed as a [TransferableTypedData] to avoid copying.
  Future<List<String>> _extractInIsolate(
    Uint8List plainBytes,
    FileType fileType,
  ) async {
    final receivePort = ReceivePort();
    final transferable = TransferableTypedData.fromList([plainBytes]);

    await Isolate.spawn(
      _isolateExtractEntry,
      _IsolateExtractPayload(
        sendPort: receivePort.sendPort,
        data: transferable,
        fileTypeName: fileType.name,
      ),
    );

    final chunks = await receivePort.first as List<String>;
    return chunks;
  }

  /// Fetches all text chunks for a given vault item.
  Future<List<String>> getChunksForItem(String vaultItemId) async {
    final db = await _dbProvider.database;
    final rows = await db.query(
      'text_chunks',
      columns: ['content'],
      where: 'vault_item_id = ?',
      whereArgs: [vaultItemId],
      orderBy: 'chunk_index ASC',
    );
    return rows.map((r) => r['content'] as String).toList();
  }

  /// Returns all items that still need extraction.
  Future<List<VaultItem>> getPendingItems() async {
    final db = await _dbProvider.database;
    final rows = await db.query(
      'vault_items',
      where: "extraction_status = ? OR extraction_status = ?",
      whereArgs: [
        ExtractionStatus.pending.name,
        ExtractionStatus.failed.name,
      ],
    );
    return rows.map((r) => VaultItem.fromMap(r)).toList();
  }
}

// ── Isolate entry (top-level, transferable-data version) ────────────────────

class _IsolateExtractPayload {
  const _IsolateExtractPayload({
    required this.sendPort,
    required this.data,
    required this.fileTypeName,
  });
  final SendPort sendPort;
  final TransferableTypedData data;
  final String fileTypeName;
}

void _isolateExtractEntry(_IsolateExtractPayload payload) {
  final bytes = payload.data.materialize().asUint8List();
  List<String> chunks;

  try {
    switch (payload.fileTypeName) {
      case 'pdf':
        chunks = PdfExtractor.extractChunks(bytes);
        break;
      case 'docx':
      case 'doc':
        chunks = DocxExtractor.extractChunks(bytes);
        break;
      case 'txt':
      case 'md':
        final text = utf8.decode(bytes, allowMalformed: true);
        chunks = PlainTextExtractor.extractChunks(text);
        break;
      case 'json':
        final rawText = utf8.decode(bytes, allowMalformed: true);
        String formattedText = rawText;
        try {
          final decoded = jsonDecode(rawText);
          if (decoded is Map<String, dynamic>) {
            final buffer = StringBuffer();
            final label = (decoded['title'] ??
                    decoded['documentName'] ??
                    decoded['bankName'] ??
                    '')
                .toString()
                .trim();
            const ignoredKeys = <String>{
              'subType',
              'presetId',
              'docType',
              'domains',
              'androidPackages',
              'customFields',
            };
            for (final entry in decoded.entries) {
              if (ignoredKeys.contains(entry.key)) continue;
              final val = entry.value?.toString().trim() ?? '';
              if (val.isEmpty) continue;
              if (entry.key == 'title' ||
                  entry.key == 'documentName' ||
                  entry.key == 'bankName') {
                buffer.writeln('Item: $val.');
              } else {
                final humanKey = VaultTemplates.humanizeFieldKey(entry.key);
                if (label.isNotEmpty) {
                  buffer.writeln('$label $humanKey is $val.');
                } else {
                  buffer.writeln('$humanKey: $val.');
                }
              }
            }
            final custom = decoded['customFields'];
            if (custom is List) {
              for (final item in custom) {
                if (item is Map) {
                  final fLabel = item['label']?.toString().trim() ?? '';
                  final fVal = item['value']?.toString().trim() ?? '';
                  if (fLabel.isNotEmpty && fVal.isNotEmpty) {
                    if (label.isNotEmpty) {
                      buffer.writeln('$label $fLabel is $fVal.');
                    } else {
                      buffer.writeln('$fLabel: $fVal.');
                    }
                  }
                }
              }
            }
            formattedText = buffer.toString().trim();
          }
        } catch (_) {}
        chunks = PlainTextExtractor.extractChunks(
            formattedText.isNotEmpty ? formattedText : rawText);
        break;
      default:
        chunks = [];
    }
  } catch (_) {
    chunks = [];
  }

  // Wipe bytes
  for (int i = 0; i < bytes.length; i++) {
    bytes[i] = 0;
  }

  payload.sendPort.send(chunks);
}
