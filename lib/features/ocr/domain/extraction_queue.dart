import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../vault/domain/models/vault_item.dart';
import '../data/ocr_repository.dart';

final extractionQueueProvider = Provider<ExtractionQueue>((ref) {
  final ocrRepo = ref.read(ocrRepositoryProvider);
  return ExtractionQueue(ocrRepo);
});

/// Manages a FIFO queue of vault items awaiting text extraction.
/// Processes up to [maxConcurrent] items at a time using background isolates.
class ExtractionQueue {
  ExtractionQueue(this._ocrRepo);

  final OcrRepository _ocrRepo;
  static const int maxConcurrent = 2;

  final List<VaultItem> _queue = [];
  int _running = 0;


  /// Adds an item to the extraction queue and starts processing if idle.
  void enqueue(VaultItem item) {
    _queue.add(item);
    _processNext();
  }

  /// Enqueues multiple items.
  void enqueueAll(List<VaultItem> items) {
    _queue.addAll(items);
    _processNext();
  }

  /// Re-queues all pending/failed items from the database.
  Future<void> resumePending() async {
    final pending = await _ocrRepo.getPendingItems();
    if (pending.isNotEmpty) {
      enqueueAll(pending);
    }
  }

  void _processNext() {
    while (_running < maxConcurrent && _queue.isNotEmpty) {
      final item = _queue.removeAt(0);
      _running++;
      _extract(item);
    }
  }

  void _extract(VaultItem item) {
    // Only extract supported types
    if (!_isSupportedType(item.fileType)) {
      _running--;
      _processNext();
      return;
    }

    _ocrRepo.extractAndSave(item).listen(
      (_) {}, // ignore progress updates here (use a StateNotifier for UI)
      onDone: () {
        _running--;
        _processNext();
      },
      onError: (_) {
        _running--;
        _processNext();
      },
      cancelOnError: false,
    );
  }

  bool _isSupportedType(FileType type) {
    return type == FileType.pdf ||
        type == FileType.docx ||
        type == FileType.txt ||
        type == FileType.md;
  }
}
