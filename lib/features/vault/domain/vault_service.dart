import 'dart:io';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../shared/providers/database_provider.dart';
import '../data/vault_repository.dart';
import 'models/vault_item.dart';

final vaultServiceProvider = Provider<VaultService>((ref) {
  final dbProvider = ref.read(databaseProvider);
  final vaultRepo = ref.read(vaultRepositoryProvider);
  return VaultService(dbProvider, vaultRepo);
});

// Riverpod state for the current vault item list (reactive UI)
final vaultItemsProvider = FutureProvider.family<List<VaultItem>, String?>(
  (ref, categoryId) async {
    final service = ref.read(vaultServiceProvider);
    return service.getVaultItems(categoryId: categoryId);
  },
);

/// Orchestrates file encryption via VaultRepository and metadata storage
/// via DatabaseProvider. Also provides reactive item lists.
class VaultService {
  VaultService(this._dbProvider, this._vaultRepo);

  final DatabaseProvider _dbProvider;
  final VaultRepository _vaultRepo;
  final _uuid = const Uuid();

  /// Imports a plain-text file into the vault.
  ///   1. Encrypts the file and saves it to vault_files/
  ///   2. Inserts a VaultItem record into the DB
  ///   3. Returns the new [VaultItem] (caller should enqueue for OCR)
  Future<VaultItem> importFile(File sourceFile, {String? categoryId}) async {
    // 1. Encrypt and store
    final encryptedPath = await _vaultRepo.encryptAndStore(sourceFile);

    // 2. Gather metadata
    final fileName = p.basename(sourceFile.path);
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
      extractionStatus: ExtractionStatus.pending,
    );

    // 3. Insert into DB
    final db = await _dbProvider.database;
    await db.insert('vault_items', item.toMap());

    return item;
  }

  /// Imports a text string as a text file into the vault.
  Future<VaultItem> importTextItem(String title, String content, String categoryId) async {
    final tempDir = await Directory.systemTemp.createTemp('docsift_text_');
    // Sanitize title for filename
    final safeTitle = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final tempFile = File(p.join(tempDir.path, '$safeTitle.txt'));
    await tempFile.writeAsString(content);

    final item = await importFile(tempFile, categoryId: categoryId);

    // Clean up
    await tempFile.delete();
    return item;
  }

  /// Imports a text string as a JSON file into the vault.
  Future<VaultItem> importJsonItem(String title, Map<String, dynamic> data, String categoryId) async {
    final tempDir = await Directory.systemTemp.createTemp('docsift_json_');
    final safeTitle = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final tempFile = File(p.join(tempDir.path, '$safeTitle.json'));
    await tempFile.writeAsString(jsonEncode(data));

    final item = await importFile(tempFile, categoryId: categoryId);
    
    // Clean up
    await tempFile.delete();
    return item;
  }

  /// Updates an existing JSON item by replacing its encrypted file.
  Future<VaultItem> updateJsonItem(VaultItem item, String title, Map<String, dynamic> data) async {
    final tempDir = await Directory.systemTemp.createTemp('docsift_json_');
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
      encryptedFilePath: encryptedPath,
      fileSizeBytes: size,
      modifiedAt: now,
    );

    // Update DB
    final db = await _dbProvider.database;
    await db.update(
      'vault_items',
      updatedItem.toMap(),
      where: 'id = ?',
      whereArgs: [item.id],
    );

    await tempFile.delete();
    return updatedItem;
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

  /// Factory Reset: Wipes all user data, encrypted files, database, and auth keys.
  Future<void> factoryReset() async {
    // 1. Delete all encrypted files in the vault_files directory
    final docsDir = await getApplicationDocumentsDirectory();
    final vaultDir = Directory(p.join(docsDir.path, 'vault_files'));
    if (await vaultDir.exists()) {
      await vaultDir.delete(recursive: true);
    }

    // 2. Properly close and delete the SQLite database using DatabaseProvider
    await _dbProvider.deleteAndResetDatabase();

    // 3. Destroy all auth data (SecureStorage with PIN, salt, VEK, etc.)
    const storage = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true, sharedPreferencesName: 'docsift_secure_prefs'),
      iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
    );
    await storage.deleteAll();

    // Also wipe shared prefs (settings)
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
