import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:docsift/features/ai/data/embedding_repository.dart';
import 'package:docsift/features/ai/data/model_manager.dart';
import 'package:docsift/features/ai/data/qa_repository.dart';
import 'package:docsift/features/ai/domain/rag_service.dart';
import 'package:docsift/features/auth/data/auth_repository.dart';
import 'package:docsift/features/ocr/data/docx_extractor.dart';
import 'package:docsift/features/search/data/search_repository.dart';
import 'package:docsift/features/search/domain/models/search_result.dart';
import 'package:docsift/features/vault/data/backup_codec.dart';
import 'package:docsift/features/vault/data/vault_repository.dart';
import 'package:docsift/shared/providers/database_provider.dart';

class _BinaryStubSearchRepo extends SearchRepository {
  _BinaryStubSearchRepo(super.db);

  @override
  Future<List<SearchResult>> search(String query) async {
    return const [
      SearchResult(
        chunkId: null,
        vaultItemId: 'vid-1',
        itemName: 'Family_Trip_2026.mp4',
        fileType: 'video',
        chunkContent: 'Matched vault item · MP4',
        score: -3.0,
      ),
    ];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BackupCodec (.docsift zero-trust container)', () {
    test('seals and opens VEK, SQLCipher DB, and .enc files losslessly', () async {
      final vek = Uint8List.fromList(List<int>.generate(32, (i) => (i * 7 + 3) & 0xFF));
      final dbBytes = Uint8List.fromList(utf8.encode('simulated-sqlcipher-database-payload'));
      final fileA = Uint8List.fromList(List<int>.generate(256, (i) => i));
      final fileB = Uint8List.fromList(List<int>.generate(64, (i) => 255 - i));

      final archiveBytes = await BackupCodec.seal(
        passphrase: 'correct-horse-battery-staple',
        vek: vek,
        dbKey: 'sqlcipher-secret-key-b64',
        dbBytes: dbBytes,
        encryptedFiles: {
          '/old/device/vault_files/item_a.enc': fileA,
          r'C:\Users\OldPhone\vault_files\item_b.enc': fileB,
        },
        iterations: 2000,
      );

      // Verify magic header 'DSBK\x01'
      expect(archiveBytes.sublist(0, 5), [0x44, 0x53, 0x42, 0x4B, 0x01]);

      final opened = await BackupCodec.open(
        archiveBytes: archiveBytes,
        passphrase: 'correct-horse-battery-staple',
      );

      expect(opened.vek, equals(vek));
      expect(opened.dbKey, 'sqlcipher-secret-key-b64');
      expect(opened.dbBytes, equals(dbBytes));
      expect(opened.encryptedFiles.keys.toSet(), {'item_a.enc', 'item_b.enc'});
      expect(opened.encryptedFiles['item_a.enc'], equals(fileA));
      expect(opened.encryptedFiles['item_b.enc'], equals(fileB));
    });

    test('rejects wrong passphrase and tampered AAD or ciphertext bytes', () async {
      final vek = Uint8List.fromList(List<int>.filled(32, 0x42));
      final sealed = await BackupCodec.seal(
        passphrase: 'MyStrongBackupPassphrase!',
        vek: vek,
        dbKey: 'db-key',
        dbBytes: Uint8List.fromList([1, 2, 3, 4]),
        encryptedFiles: {'doc.enc': Uint8List.fromList([9, 8, 7])},
        iterations: 2000,
      );

      // 1. Wrong passphrase
      await expectLater(
        () => BackupCodec.open(
          archiveBytes: sealed,
          passphrase: 'WrongPassphrase!',
        ),
        throwsA(isA<BackupAuthException>()),
      );

      // 2. Tamper with AAD header (flip bit in salt byte 15)
      final tamperedAad = Uint8List.fromList(sealed);
      tamperedAad[15] ^= 0x01;
      await expectLater(
        () => BackupCodec.open(
          archiveBytes: tamperedAad,
          passphrase: 'MyStrongBackupPassphrase!',
        ),
        throwsA(isA<BackupAuthException>()),
      );

      // 3. Tamper with ciphertext / GCM authentication tag
      final tamperedCt = Uint8List.fromList(sealed);
      tamperedCt[tamperedCt.length - 1] ^= 0x80;
      await expectLater(
        () => BackupCodec.open(
          archiveBytes: tamperedCt,
          passphrase: 'MyStrongBackupPassphrase!',
        ),
        throwsA(isA<BackupAuthException>()),
      );
    });
  });

  group('Cross-Vault Restore & Off-Thread VaultRepository Crypto', () {
    test('restores backup VEK under a different device PIN and decrypts .enc files off-thread', () async {
      final tempDirA = await Directory.systemTemp.createTemp('docsift_vault_a_');
      final tempDirB = await Directory.systemTemp.createTemp('docsift_vault_b_');
      try {
        // Device A: setup PIN 111111 and encrypt a multi-KB payload off-thread
        final storeA = InMemorySecureStore();
        final authA = AuthRepository(store: storeA, pbkdf2Iterations: 1500);
        await authA.setupPin('111111');
        final repoA = VaultRepository(authA, vaultRootOverride: tempDirA);

        final originalPayload = Uint8List.fromList(
          List<int>.generate(64 * 1024, (i) => (i * 31 + 17) & 0xFF),
        );
        final srcFile = File(p.join(tempDirA.path, 'contract.pdf'));
        await srcFile.writeAsBytes(originalPayload);
        final encPathA = await repoA.encryptAndStore(srcFile);

        // Seal into portable .docsift archive
        final backupBytes = await BackupCodec.seal(
          passphrase: 'portable-backup-pass',
          vek: Uint8List.fromList(authA.vaultEncryptionKey!),
          dbKey: 'restored-db-key',
          dbBytes: Uint8List.fromList([10, 20, 30]),
          encryptedFiles: {
            encPathA: await File(encPathA).readAsBytes(),
          },
          iterations: 1500,
        );

        // Device B: brand-new vault with completely different PIN 999999
        final storeB = InMemorySecureStore();
        final authB = AuthRepository(store: storeB, pbkdf2Iterations: 1500);
        await authB.setupPin('999999');

        // Rejects adoptRestoredVek if wrong PIN is given
        final unsealed = await BackupCodec.open(
          archiveBytes: backupBytes,
          passphrase: 'portable-backup-pass',
        );
        expect(
          await authB.adoptRestoredVek(
            unsealed.vek,
            currentPin: '000000',
            biometricsEnabled: false,
          ),
          isFalse,
        );

        // Accepts adoptRestoredVek with Device B's real PIN 999999
        expect(
          await authB.adoptRestoredVek(
            unsealed.vek,
            currentPin: '999999',
            biometricsEnabled: false,
          ),
          isTrue,
        );

        // Write restored .enc file into Device B's vault_files directory
        final vaultDirB = Directory(p.join(tempDirB.path, 'vault_files'));
        await vaultDirB.create(recursive: true);
        final restoredEntry = unsealed.encryptedFiles.entries.single;
        final encPathB = p.join(vaultDirB.path, restoredEntry.key);
        await File(encPathB).writeAsBytes(restoredEntry.value);

        // Lock & re-unlock Device B with PIN 999999 to verify wrapped VEK persistence
        authB.lock();
        expect(authB.vaultEncryptionKey, isNull);
        expect(await authB.unlock('999999'), isTrue);

        final repoB = VaultRepository(authB, vaultRootOverride: tempDirB);
        final decryptedOnB = await repoB.decryptToMemory(encPathB);
        expect(decryptedOnB, equals(originalPayload));
      } finally {
        await tempDirA.delete(recursive: true);
        await tempDirB.delete(recursive: true);
      }
    });
  });

  group('SearchRepository Title/Tag Merging & RagService Binary Handling', () {
    test('merges FTS5 chunk hits with title-matched documents and binary files', () {
      final terms = SearchRepository.extractEffectiveTerms(
        'Where is my Passport_2026 scan?',
      );
      expect(terms, equals(['passport_2026', 'scan']));

      const ftsHit = SearchResult(
        chunkId: 'c1',
        vaultItemId: 'item-1',
        itemName: 'Travel Notes.txt',
        fileType: 'txt',
        chunkContent: 'Remember to bring passport scan to embassy.',
        score: -2.0,
      );

      final itemRows = <Map<String, Object?>>[
        // Matches title AND has first chunk even though FTS didn't match 'passport_2026'
        {
          'id': 'item-2',
          'name': 'Passport_2026_Scan.jpg',
          'file_type': 'image',
          'original_extension': 'jpg',
          'tags': 'identity',
          'first_chunk_id': 'c2',
          'first_chunk_content': 'REPUBLIC OF INDIA PASSPORT NO Z9876543',
          'first_chunk_embedding': null,
        },
        // Binary archive with zero text chunks
        {
          'id': 'item-3',
          'name': 'Passport_2026_Backup.zip',
          'file_type': 'zip',
          'original_extension': 'zip',
          'tags': null,
          'first_chunk_id': null,
          'first_chunk_content': null,
          'first_chunk_embedding': null,
        },
      ];

      final merged = SearchRepository.mergeFtsAndItemMatches(
        ftsResults: const [ftsHit],
        itemRows: itemRows,
        effectiveTerms: terms,
      );

      expect(merged.length, 3);
      // Title match on both 'passport_2026' and 'scan' (2 terms -> -8.0) ranks first!
      expect(merged[0].vaultItemId, 'item-2');
      expect(merged[0].chunkContent, contains('Z9876543'));
      // Binary .zip matched 'passport_2026' (-3.0) ranks ahead of single-term body hit (-2.0)
      expect(merged[1].vaultItemId, 'item-3');
      expect(merged[1].chunkContent, 'Matched vault item · ZIP');
      expect(merged[2].vaultItemId, 'item-1');
    });

    test('RagService reports binary vault matches cleanly without running QA on badges', () async {
      final manager = ModelManager();
      final rag = RagService(
        _BinaryStubSearchRepo(DatabaseProvider()),
        EmbeddingRepository(manager),
        QaRepository(manager),
      );

      final res = await rag.query('Find Family_Trip_2026');
      expect(res.answer, contains('Family_Trip_2026.mp4'));
      expect(res.answer, contains('does not contain extractable text'));
      expect(res.sourceContexts.single.vaultItemId, 'vid-1');
    });
  });

  group('DocxExtractor Legacy OLE2 .doc Fallback', () {
    test('detects OLE2 magic header and extracts UTF-16LE & ASCII text without ZIP errors', () {
      // Construct synthetic 1024-byte OLE2 Compound File (.doc)
      final docBytes = Uint8List(1024);
      // 8-byte OLE2 signature
      docBytes.setRange(0, 8, const [
        0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1,
      ]);

      // Noise in stream directory (should be ignored)
      void writeUtf16Le(int offset, String text) {
        for (int i = 0; i < text.length; i++) {
          final cu = text.codeUnitAt(i);
          docBytes[offset + i * 2] = cu & 0xFF;
          docBytes[offset + i * 2 + 1] = (cu >> 8) & 0xFF;
        }
      }

      writeUtf16Le(520, 'Root Entry');
      writeUtf16Le(560, 'WordDocument');
      // Actual document body in UTF-16LE piece stream
      writeUtf16Le(
        620,
        'Employment Agreement Clause 7: Annual salary is USD 145,000.',
      );
      // Compressed CP1252 ASCII piece stream
      final asciiText = utf8.encode('Confidential Addendum signed in Mumbai.');
      docBytes.setRange(820, 820 + asciiText.length, asciiText);

      expect(DocxExtractor.isOle2CompoundDocument(docBytes), isTrue);
      final extracted = DocxExtractor.extractFullText(docBytes);
      expect(extracted, contains('Employment Agreement Clause 7'));
      expect(extracted, contains('USD 145,000'));
      expect(extracted, contains('Confidential Addendum signed in Mumbai.'));
      expect(extracted, isNot(contains('Root Entry')));
      expect(extracted, isNot(contains('WordDocument')));
    });
  });
}

