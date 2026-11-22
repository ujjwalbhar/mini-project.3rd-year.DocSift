import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../../shared/providers/database_provider.dart';
import '../../auth/data/auth_repository.dart';
import '../data/backup_codec.dart';
import '../data/vault_repository.dart';
import 'models/vault_item.dart';

final vaultServiceProvider = Provider<VaultService>((ref) {
  final dbProvider = ref.read(databaseProvider);
  final vaultRepo = ref.read(vaultRepositoryProvider);
  final authRepo = ref.read(authRepositoryProvider);
  return VaultService(dbProvider, vaultRepo, authRepo);
});

// Riverpod state for the current vault item list (reactive UI)
final vaultItemsProvider = FutureProvider.family<List<VaultItem>, String?>(
  (ref, categoryId) async {
    final service = ref.read(vaultServiceProvider);
    return service.getVaultItems(categoryId: categoryId);
  },
);

final vaultStorageBytesProvider = FutureProvider<int>((ref) async {
  // Recompute whenever vault items change
  ref.watch(vaultItemsProvider(null));
  return ref.read(vaultServiceProvider).calculateStorageBytes();
});

/// Orchestrates file encryption via VaultRepository and metadata storage
/// via DatabaseProvider. Also provides reactive item lists.
class VaultService {
  VaultService(this._dbProvider, this._vaultRepo, [this._authRepo]);

  final DatabaseProvider _dbProvider;
  final VaultRepository _vaultRepo;
  final AuthRepository? _authRepo;
  final _uuid = const Uuid();

  /// Imports a file into the vault.
  ///   1. Encrypts the file and saves it to vault_files/
  ///   2. Inserts a VaultItem record into the DB
  ///   3. Returns the new [VaultItem] (caller should enqueue for OCR)
  Future<VaultItem> importFile(
    File sourceFile, {
    String? categoryId,
    String? customName,
  }) async {
    // 1. Encrypt and store
    final encryptedPath = await _vaultRepo.encryptAndStore(sourceFile);

    // 2. Gather metadata
    final fileName = customName ?? p.basename(sourceFile.path);
    final ext = p.extension(sourceFile.path).replaceAll('.', '').toLowerCase();
    final size = await sourceFile.length();
    final fileType = fileTypeFromExtension(ext);

    final now = DateTime.now();
    final item = VaultItem(
      id: _uuid.v4(),
      name: fileName,
      originalExtension: ext,
      categoryId: categoryId,
      encryptedFilePath: encryptedPath,
      fileSizeBytes: size,
      fileType: fileType,
      createdAt: now,
      modifiedAt: now,
      extractionStatus: isExtractableFileType(fileType)
          ? ExtractionStatus.pending
          : ExtractionStatus.done,
    );

    // 3. Insert into DB
    final db = await _dbProvider.database;
    await db.insert('vault_items', item.toMap());

    return item;
  }

  /// Imports a text string as a text file into the vault.
  Future<VaultItem> importTextItem(String title, String content, String categoryId) async {
    final tempDir = await Directory.systemTemp.createTemp('docsift_text_');
    try {
      final safeTitle = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final tempFile = File(p.join(tempDir.path, '$safeTitle.txt'));
      await tempFile.writeAsString(content);

      return await importFile(
        tempFile,
        categoryId: categoryId,
        customName: title,
      );
    } finally {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// Imports a text string as a JSON file into the vault.
  Future<VaultItem> importJsonItem(String title, Map<String, dynamic> data, String categoryId) async {
    final tempDir = await Directory.systemTemp.createTemp('docsift_json_');
    try {
      final safeTitle = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final tempFile = File(p.join(tempDir.path, '$safeTitle.json'));
      await tempFile.writeAsString(jsonEncode(data));

      return await importFile(
        tempFile,
        categoryId: categoryId,
        customName: title,
      );
    } finally {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// Updates an existing JSON item by replacing its encrypted file.
  Future<VaultItem> updateJsonItem(VaultItem item, String title, Map<String, dynamic> data) async {
    final tempDir = await Directory.systemTemp.createTemp('docsift_json_');
    try {
      final safeTitle = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final tempFile = File(p.join(tempDir.path, '$safeTitle.json'));
      await tempFile.writeAsString(jsonEncode(data));

      // Delete old encrypted file
      await _vaultRepo.deleteVaultFile(item.encryptedFilePath);

      // Encrypt new file
      final encryptedPath = await _vaultRepo.encryptAndStore(tempFile);
      final size = await tempFile.length();
      final now = DateTime.now();

      final updatedItem = item.copyWith(
        name: title,
        originalExtension: 'json',
        fileType: FileType.json,
        encryptedFilePath: encryptedPath,
        fileSizeBytes: size,
        modifiedAt: now,
        extractionStatus: ExtractionStatus.pending,
      );

      // Update DB
      final db = await _dbProvider.database;
      await db.update(
        'vault_items',
        updatedItem.toMap(),
        where: 'id = ?',
        whereArgs: [item.id],
      );

      return updatedItem;
    } finally {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// Updates an existing plain-text / markdown item by replacing its encrypted file.
  Future<VaultItem> updateTextItem(VaultItem item, String title, String content) async {
    final tempDir = await Directory.systemTemp.createTemp('docsift_text_');
    try {
      final ext = item.originalExtension.isNotEmpty ? item.originalExtension : 'txt';
      final safeTitle = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final tempFile = File(p.join(tempDir.path, '$safeTitle.$ext'));
      await tempFile.writeAsString(content);

      await _vaultRepo.deleteVaultFile(item.encryptedFilePath);

      final encryptedPath = await _vaultRepo.encryptAndStore(tempFile);
      final size = await tempFile.length();
      final now = DateTime.now();

      final updatedItem = item.copyWith(
        name: title,
        encryptedFilePath: encryptedPath,
        fileSizeBytes: size,
        modifiedAt: now,
        extractionStatus: ExtractionStatus.pending,
      );

      final db = await _dbProvider.database;
      await db.update(
        'vault_items',
        updatedItem.toMap(),
        where: 'id = ?',
        whereArgs: [item.id],
      );

      return updatedItem;
    } finally {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// Retrieves a list of all vault items, optionally filtered by category.
  Future<List<VaultItem>> getVaultItems({String? categoryId}) async {
    final db = await _dbProvider.database;

    final List<Map<String, dynamic>> maps;
    if (categoryId != null) {
      maps = await db.query(
        'vault_items',
        where: 'category_id = ?',
        whereArgs: [categoryId],
        orderBy: 'modified_at DESC',
      );
    } else {
      maps = await db.query(
        'vault_items',
        orderBy: 'modified_at DESC',
      );
    }

    return maps.map((map) => VaultItem.fromMap(map)).toList();
  }

  /// Retrieves item counts per category for the dashboard grid.
  Future<Map<String, int>> getCategoryCounts() async {
    final db = await _dbProvider.database;
    final rows = await db.rawQuery(
      '''
      SELECT category_id, COUNT(*) as count
      FROM vault_items
      GROUP BY category_id
      ''',
    );
    return {
      for (final r in rows)
        (r['category_id'] as String? ?? 'uncategorized'): r['count'] as int,
    };
  }

  /// Retrieves the N most recently modified vault items.
  Future<List<VaultItem>> getRecentItems({int limit = 6}) async {
    final db = await _dbProvider.database;
    final rows = await db.query(
      'vault_items',
      orderBy: 'modified_at DESC',
      limit: limit,
    );
    return rows.map((r) => VaultItem.fromMap(r)).toList();
  }

  /// Permanently deletes an item from the vault and its DB record.
  Future<void> deleteItem(VaultItem item) async {
    // 1. Securely delete the encrypted file
    await _vaultRepo.deleteVaultFile(item.encryptedFilePath);

    // 2. Delete the DB record (text_chunks cascade-delete via FK)
    final db = await _dbProvider.database;
    await db.delete(
      'vault_items',
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  /// Toggles the starred state of an item.
  Future<void> toggleStar(VaultItem item) async {
    final db = await _dbProvider.database;
    await db.update(
      'vault_items',
      {'is_starred': item.isStarred ? 0 : 1},
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  /// Calculates total disk space used by encrypted vault files and SQLCipher DB.
  Future<int> calculateStorageBytes() async {
    int totalBytes = 0;
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final vaultDir = Directory(p.join(docsDir.path, 'vault_files'));
      if (await vaultDir.exists()) {
        await for (final entity in vaultDir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            totalBytes += await entity.length();
          }
        }
      }
      final dbFile = File(p.join(docsDir.path, 'docsift_vault.db'));
      if (await dbFile.exists()) {
        totalBytes += await dbFile.length();
      }
    } catch (_) {}
    return totalBytes;
  }

  /// Creates a portable, password-protected `.docsift` encrypted backup archive
  /// containing the SQLCipher database, wrapped key material, and all `.enc` files.
  Future<File> exportEncryptedBackup(String passphrase) async {
    if (passphrase.trim().length < 6) {
      throw const BackupAuthException(
        'Backup passphrase must be at least 6 characters.',
      );
    }
    final vekList = _authRepo?.vaultEncryptionKey;
    if (vekList == null || vekList.length != 32) {
      throw const BackupAuthException(
        'Vault must be unlocked before creating an encrypted backup.',
      );
    }

    // Ensure DB exists and flush all SQLite pages cleanly before reading bytes
    await _dbProvider.database;
    final dbKey = await _dbProvider.readDbEncryptionKey();
    if (dbKey == null || dbKey.isEmpty) {
      throw const BackupAuthException('Database encryption key unavailable.');
    }
    await _dbProvider.closeDatabase();

    final docsDir = await getApplicationDocumentsDirectory();
    final dbFile = File(p.join(docsDir.path, 'docsift_vault.db'));
    final dbBytes =
        await dbFile.exists() ? await dbFile.readAsBytes() : Uint8List(0);

    final encryptedFiles = <String, Uint8List>{};
    final vaultDir = Directory(p.join(docsDir.path, 'vault_files'));
    if (await vaultDir.exists()) {
      await for (final entity in vaultDir.list(followLinks: false)) {
        if (entity is File && entity.path.endsWith('.enc')) {
          encryptedFiles[p.basename(entity.path)] = await entity.readAsBytes();
        }
      }
    }

    final archiveBytes = await BackupCodec.seal(
      passphrase: passphrase,
      vek: Uint8List.fromList(vekList),
      dbKey: dbKey,
      dbBytes: dbBytes,
      encryptedFiles: encryptedFiles,
    );

    final backupRoot = Directory(p.join(docsDir.path, 'vault_backups'));
    if (!await backupRoot.exists()) {
      await backupRoot.create(recursive: true);
    }

    final now = DateTime.now();
    final stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    final archiveFile =
        File(p.join(backupRoot.path, 'DocSift_Backup_$stamp.docsift'));
    await archiveFile.writeAsBytes(archiveBytes, flush: true);

    // Retain at most the 3 newest local backup archives to conserve disk space
    try {
      final snapshots = <File>[];
      await for (final entity in backupRoot.list(followLinks: false)) {
        if (entity is File && entity.path.endsWith('.docsift')) {
          snapshots.add(entity);
        }
      }
      snapshots.sort((a, b) => b.path.compareTo(a.path));
      for (int i = 3; i < snapshots.length; i++) {
        await snapshots[i].delete();
      }
    } catch (_) {}

    return archiveFile;
  }

  /// Authenticates and restores a `.docsift` encrypted backup archive into the
  /// current vault, remapping file paths to the local container directory and
  /// re-wrapping the restored VEK under [currentPin].
  /// Returns the number of vault items restored.
  Future<int> restoreEncryptedBackup({
    required File archiveFile,
    required String passphrase,
    required String currentPin,
    required bool biometricsEnabled,
  }) async {
    final authRepo = _authRepo;
    if (authRepo == null) {
      throw const BackupAuthException('Authentication service unavailable.');
    }

    // 1. Verify current Vault PIN BEFORE modifying any active vault state
    final pinValid = await authRepo.verifyCurrentPin(currentPin);
    if (!pinValid) {
      throw const BackupAuthException('Incorrect current Vault PIN.');
    }

    // 2. Authenticate & decrypt backup archive completely in memory BEFORE
    // touching the active database or vault_files directory
    final archiveBytes = await archiveFile.readAsBytes();
    final payload = await BackupCodec.open(
      archiveBytes: archiveBytes,
      passphrase: passphrase,
    );

    // 3. Close active SQLite connection so database files can be atomically swapped
    await _dbProvider.closeDatabase();

    final docsDir = await getApplicationDocumentsDirectory();
    final vaultDir = Directory(p.join(docsDir.path, 'vault_files'));
    if (await vaultDir.exists()) {
      await vaultDir.delete(recursive: true);
    }
    await vaultDir.create(recursive: true);

    // 4. Write all restored .enc files
    for (final entry in payload.encryptedFiles.entries) {
      final fileName = _portableBasename(entry.key);
      if (fileName.isEmpty) continue;
      final outFile = File(p.join(vaultDir.path, fileName));
      await outFile.writeAsBytes(entry.value, flush: true);
    }

    // 5. Replace SQLCipher database file & encryption key
    final dbPath = p.join(docsDir.path, 'docsift_vault.db');
    for (final suffix in ['', '-wal', '-shm', '-journal']) {
      final f = File('$dbPath$suffix');
      if (await f.exists()) {
        await f.delete();
      }
    }
    if (payload.dbBytes.isNotEmpty) {
      await File(dbPath).writeAsBytes(payload.dbBytes, flush: true);
    }
    await _dbProvider.writeDbEncryptionKey(payload.dbKey);

    // 6. Adopt restored 256-bit VEK under the user's current Vault PIN
    final adopted = await authRepo.adoptRestoredVek(
      payload.vek,
      currentPin: currentPin,
      biometricsEnabled: biometricsEnabled,
    );
    if (!adopted) {
      throw const BackupAuthException('Failed to bind restored vault key.');
    }

    // 7. Re-open database and remap encrypted_file_path to current OS sandbox path
    final db = await _dbProvider.database;
    final rows = await db.query(
      'vault_items',
      columns: ['id', 'encrypted_file_path'],
    );
    if (rows.isNotEmpty) {
      final batch = db.batch();
      for (final row in rows) {
        final id = row['id'] as String;
        final oldPath = row['encrypted_file_path'] as String? ?? '';
        final fileName = _portableBasename(oldPath);
        if (fileName.isNotEmpty) {
          batch.update(
            'vault_items',
            {'encrypted_file_path': p.join(vaultDir.path, fileName)},
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      }
      await batch.commit(noResult: true);
    }

    return rows.length;
  }

  static String _portableBasename(String rawPath) {
    final parts =
        rawPath.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return '';
    final last = parts.last;
    if (last == '.' || last == '..') return '';
    return last;
  }

  /// Factory Reset: Wipes all user data, encrypted files, database, and auth keys.
  Future<void> factoryReset() async {
    // 1. Delete all encrypted files in the vault_files and vault_backups directories
    final docsDir = await getApplicationDocumentsDirectory();
    final vaultDir = Directory(p.join(docsDir.path, 'vault_files'));
    if (await vaultDir.exists()) {
      await vaultDir.delete(recursive: true);
    }
    final backupDir = Directory(p.join(docsDir.path, 'vault_backups'));
    if (await backupDir.exists()) {
      await backupDir.delete(recursive: true);
    }

    // 2. Properly close and delete the SQLite database using DatabaseProvider
    await _dbProvider.deleteAndResetDatabase();

    // 3. Destroy all auth data (SecureStorage with PIN, salt, VEK, etc.)
    if (_authRepo != null) {
      await _authRepo.destroyVault();
    } else {
      const storage = FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true, sharedPreferencesName: 'docsift_secure_prefs'),
        iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
      );
      await storage.deleteAll();
    }

    // Also wipe shared prefs (settings) & native autofill credential store
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    try {
      await const MethodChannel('com.docsift.docsift/autofill')
          .invokeMethod<void>('clearAllAutofillData');
    } catch (_) {}
  }
}
