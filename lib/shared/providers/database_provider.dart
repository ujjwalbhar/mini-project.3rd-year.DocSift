import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:math';
import 'dart:convert';
import 'dart:io';

const _dbKeyStorageKey = 'docsift_db_encryption_key';

final databaseProvider = Provider<DatabaseProvider>((ref) {
  return DatabaseProvider();
});

class DatabaseProvider {
  Database? _db;
  
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      sharedPreferencesName: 'docsift_secure_prefs',
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dbPath = join(docsDir.path, 'docsift_vault.db');
    
    // Get or generate DB encryption key
    String? dbKey = await _storage.read(key: _dbKeyStorageKey);
    final dbFile = File(dbPath);
    final dbExists = await dbFile.exists();

    if (dbKey == null) {
      if (dbExists) {
        // Critical Error: We lost the encryption key but the database exists.
        // We can never decrypt this database again. Rename it so the app can start fresh.
        try {
          await dbFile.rename('${dbPath}_lostkey_${DateTime.now().millisecondsSinceEpoch}.bak');
        } catch (_) {}
      }

      final rng = Random.secure();
      final keyBytes = List<int>.generate(32, (_) => rng.nextInt(256));
      dbKey = base64Encode(keyBytes);
      await _storage.write(key: _dbKeyStorageKey, value: dbKey);
    }

    try {
      return await _openVaultDatabase(dbPath, dbKey);
    } catch (e) {
      if (e.toString().contains('open_failed') || e.toString().contains('not a database')) {
        // Database is corrupted or the key is wrong.
        if (await dbFile.exists()) {
          try {
            await dbFile.rename('${dbPath}_corrupted_${DateTime.now().millisecondsSinceEpoch}.bak');
          } catch (_) {}
        }
        // Try one more time to create a fresh DB
        return await _openVaultDatabase(dbPath, dbKey);
      }
      rethrow;
    }
  }

  Future<void> deleteAndResetDatabase() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
    final docsDir = await getApplicationDocumentsDirectory();
    final dbPath = join(docsDir.path, 'docsift_vault.db');
    final dbFile = File(dbPath);
    if (await dbFile.exists()) {
      await dbFile.delete();
    }

    // Cleanup any corrupted backups
    final dirFiles = docsDir.listSync();
    for (var f in dirFiles) {
      if (f.path.contains('docsift_vault.db')) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
  }

  Future<Database> _openVaultDatabase(String dbPath, String dbKey) async {
    return await openDatabase(
      dbPath,
      password: dbKey,
      version: 1,
      onCreate: (db, version) async {
        // Vault Items table
        await db.execute('''
          CREATE TABLE vault_items (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            original_extension TEXT NOT NULL,
            category_id TEXT,
            encrypted_file_path TEXT NOT NULL,
            file_size_bytes INTEGER,
            mime_type TEXT,
            thumbnail_path TEXT,
            created_at INTEGER NOT NULL,
            modified_at INTEGER NOT NULL,
            is_starred INTEGER DEFAULT 0,
            file_type TEXT NOT NULL,
            extraction_status TEXT NOT NULL,
            tags TEXT
          )
        ''');

        // Categories table
        await db.execute('''
          CREATE TABLE categories (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            icon_codepoint INTEGER,
            color_value INTEGER,
            created_at INTEGER NOT NULL,
            item_count INTEGER DEFAULT 0
          )
        ''');

        // Text Chunks table (for AI / FTS)
        await db.execute('''
          CREATE TABLE text_chunks (
            id TEXT PRIMARY KEY,
            vault_item_id TEXT NOT NULL,
            chunk_index INTEGER NOT NULL,
            content TEXT NOT NULL,
            embedding BLOB,
            FOREIGN KEY (vault_item_id) REFERENCES vault_items(id) ON DELETE CASCADE
          )
        ''');

        // FTS5 Virtual Table
        await db.execute('''
          CREATE VIRTUAL TABLE chunks_fts USING fts5(
            content,
            content='text_chunks',
            content_rowid='rowid'
          )
        ''');

        // FTS Triggers to keep FTS table in sync with text_chunks
        await db.execute('''
          CREATE TRIGGER text_chunks_ai AFTER INSERT ON text_chunks BEGIN
            INSERT INTO chunks_fts(rowid, content) VALUES (new.rowid, new.content);
          END;
        ''');
        
        await db.execute('''
          CREATE TRIGGER text_chunks_ad AFTER DELETE ON text_chunks BEGIN
            INSERT INTO chunks_fts(chunks_fts, rowid, content) VALUES('delete', old.rowid, old.content);
          END;
        ''');
        
        await db.execute('''
          CREATE TRIGGER text_chunks_au AFTER UPDATE ON text_chunks BEGIN
            INSERT INTO chunks_fts(chunks_fts, rowid, content) VALUES('delete', old.rowid, old.content);
            INSERT INTO chunks_fts(rowid, content) VALUES (new.rowid, new.content);
          END;
        ''');
      },
      onConfigure: (db) async {
        // Enable foreign keys
        await db.execute('PRAGMA foreign_keys = ON');
      }
    );
  }
}
