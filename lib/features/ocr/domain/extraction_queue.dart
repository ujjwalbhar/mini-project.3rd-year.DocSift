import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../vault/domain/models/vault_item.dart';
import '../../vault/domain/vault_service.dart';
import '../data/ocr_repository.dart';

final extractionQueueProvider = Provider<ExtractionQueue>((ref) {
  final ocrRepo = ref.read(ocrRepositoryProvider);
  return ExtractionQueue(ocrRepo, ref);
});

/// Manages a FIFO queue of vault items awaiting text extraction.
/// Processes up to [maxConcurrent] items at a time using background isolates.
class ExtractionQueue {
  ExtractionQueue(this._ocrRepo, [this._ref]);

  final OcrRepository _ocrRepo;
  final Ref? _ref;
  static const int maxConcurrent = 2;

  final List<VaultItem> _queue = [];
  final Set<String> _inFlightIds = <String>{};
  int _running = 0;

  /// Adds an item to the extraction queue and starts processing if idle.
  void enqueue(VaultItem item) {
    if (_ref != null && !_ref.read(ocrProcessingEnabledProvider)) {
      return;
    }
    if (_inFlightIds.contains(item.id) ||
        _queue.any((queued) => queued.id == item.id)) {
      return;
    }
    _queue.add(item);
    _processNext();
  }

  /// Enqueues multiple items.
  void enqueueAll(List<VaultItem> items) {
    if (_ref != null && !_ref.read(ocrProcessingEnabledProvider)) {
      return;
    }
    for (final item in items) {
      if (!_inFlightIds.contains(item.id) &&
          !_queue.any((queued) => queued.id == item.id)) {
        _queue.add(item);
      }
    }
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
      _inFlightIds.add(item.id);
      _extract(item);
    }
  }

  void _extract(VaultItem item) {
    // Non-text binary types (video/zip/other): mark done immediately
    if (!_isSupportedType(item.fileType)) {
      _ocrRepo.markDoneWithoutExtraction(item.id).whenComplete(() {
        _inFlightIds.remove(item.id);
        _running--;
        _ref?.invalidate(vaultItemsProvider);
        _processNext();
      });
      return;
    }

    _ocrRepo.extractAndSave(item).listen(
      (_) {},
      onDone: () {
        _inFlightIds.remove(item.id);
        _running--;
        _ref?.invalidate(vaultItemsProvider);
        _processNext();
      },
      onError: (_) {
        _inFlightIds.remove(item.id);
        _running--;
        _ref?.invalidate(vaultItemsProvider);
        _processNext();
      },
      cancelOnError: false,
    );
  }

  bool _isSupportedType(FileType type) => isExtractableFileType(type);
}
