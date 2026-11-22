import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:docsift/features/vault/domain/models/vault_item.dart';
import 'package:docsift/features/ocr/data/plain_text_extractor.dart';
import 'package:docsift/features/ocr/data/docx_extractor.dart';

void main() {
  test('VaultItem serializes toMap and deserializes fromMap accurately', () {
    final now = DateTime.fromMillisecondsSinceEpoch(1700000000000);
    final item = VaultItem(
      id: 'item-123',
      name: 'My Secret Note',
      originalExtension: 'txt',
      categoryId: 'cat-notes',
      encryptedFilePath: '/vault/item-123.enc',
      fileSizeBytes: 2048,
      fileType: FileType.txt,
      tags: const ['personal', 'secret'],
      createdAt: now,
      modifiedAt: now,
      isStarred: true,
      extractionStatus: ExtractionStatus.done,
      thumbnailPath: '/thumbs/item-123.jpg',
    );

    final map = item.toMap();
    final restored = VaultItem.fromMap(map);

    expect(restored.id, item.id);
    expect(restored.name, item.name);
    expect(restored.originalExtension, 'txt');
    expect(restored.categoryId, 'cat-notes');
    expect(restored.encryptedFilePath, item.encryptedFilePath);
    expect(restored.fileSizeBytes, 2048);
    expect(restored.sizeLabel, '2.0KB');
    expect(restored.fileType, FileType.txt);
    expect(restored.tags, ['personal', 'secret']);
    expect(restored.createdAt, now);
    expect(restored.modifiedAt, now);
    expect(restored.isStarred, isTrue);
    expect(restored.extractionStatus, ExtractionStatus.done);
    expect(restored.thumbnailPath, '/thumbs/item-123.jpg');
  });

  test('PlainTextExtractor splits plain text and markdown into chunks', () {
    const raw = '# Heading Title\r\n\r\nSome **bold** and *italic* text.\n\n- Bullet 1\n- Bullet 2';
    final chunks = PlainTextExtractor.extractChunks(raw);
    expect(chunks, isNotEmpty);
    expect(chunks.first, contains('Heading Title'));
  });

  test('DocxExtractor gracefully handles invalid zip bytes without throwing', () {
    final corruptBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
    final text = DocxExtractor.extractFullText(corruptBytes);
    final chunks = DocxExtractor.extractChunks(corruptBytes);
    expect(text, isEmpty);
    expect(chunks, isEmpty);
  });
}
