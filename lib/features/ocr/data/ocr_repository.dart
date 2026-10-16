import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/providers/database_provider.dart';
import '../../vault/data/vault_repository.dart';
import '../../vault/domain/models/vault_item.dart';
import 'pdf_extractor.dart';
import 'docx_extractor.dart';
import 'plain_text_extractor.dart';

final ocrRepositoryProvider = Provider<OcrRepository>((ref) {
  final dbProvider = ref.read(databaseProvider);
  final vaultRepo = ref.read(vaultRepositoryProvider);
  return OcrRepository(dbProvider, vaultRepo);
});


// ── OcrRepository ────────────────────────────────────────────────────────────

/// Orchestrates text extraction from vault files and saves chunks to SQLite.
///
/// Extraction flow:
/// 1. Look up vault item in DB
/// 2. Decrypt file bytes on main isolate (VEK is in-memory, safe here)
/// 3. Spawn background isolate for heavy parsing (PDF/DOCX/TXT)
/// 4. Save chunks to text_chunks table
/// 5. Update extraction_status on vault_item
class OcrRepository {
  OcrRepository(this._dbProvider, this._vaultRepo);

  final DatabaseProvider _dbProvider;
  final VaultRepository _vaultRepo;
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

    try {
      // Step 1: Decrypt the file to memory (on main thread — VEK is here)
      final plainBytes = await _vaultRepo.decryptToMemory(item.encryptedFilePath);
      yield 0.2;

      // Step 2: Extract text in background isolate
      final chunks = await _extractInIsolate(plainBytes, item.fileType);
      yield 0.7;

      // Wipe plain bytes from memory
      for (int i = 0; i < plainBytes.length; i++) {
        plainBytes[i] = 0;
      }

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

      // Step 3: Save chunks to DB
      final batch = db.batch();
      for (int i = 0; i < chunks.length; i++) {
        batch.insert('text_chunks', {
          'id': _uuid.v4(),
          'vault_item_id': item.id,
          'chunk_index': i,
          'content': chunks[i],
          'embedding': null, // populated in Phase 4
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
    }
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
        final text = String.fromCharCodes(bytes);
        chunks = PlainTextExtractor.extractChunks(text);
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
