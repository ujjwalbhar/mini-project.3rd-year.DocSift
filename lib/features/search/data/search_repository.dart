import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/providers/database_provider.dart';
import '../domain/models/search_result.dart';

final searchRepositoryProvider = Provider<SearchRepository>((ref) {
  return SearchRepository(ref.read(databaseProvider));
});

class SearchRepository {
  const SearchRepository(this._dbProvider);
  final DatabaseProvider _dbProvider;

  Future<List<SearchResult>> search(String query) async {
    if (query.trim().isEmpty) return [];
    
    // Convert to FTS query syntax. If user types "hello world", we match "hello* OR world*"
    // or just "hello* world*". Let's do prefix matching by appending '*'.
    final terms = query.trim().split(RegExp(r'\s+'));
    final matchQuery = terms.map((t) => '$t*').join(' ');

    final db = await _dbProvider.database;
    
    // SQLite FTS5 bm25 returns a score (lower is better, typically negative)
    final sql = '''
      SELECT 
        tc.vault_item_id, 
        tc.content, 
        bm25(chunks_fts) AS score,
        vi.name AS item_name,
        vi.file_type
      FROM chunks_fts
      JOIN text_chunks tc ON chunks_fts.rowid = tc.rowid
      JOIN vault_items vi ON tc.vault_item_id = vi.id
      WHERE chunks_fts MATCH ?
      ORDER BY score ASC
      LIMIT 20;
    ''';

    final rows = await db.rawQuery(sql, [matchQuery]);

    return rows.map((row) {
      return SearchResult(
        vaultItemId: row['vault_item_id'] as String,
        itemName: row['item_name'] as String,
        fileType: row['file_type'] as String,
        chunkContent: row['content'] as String,
        score: (row['score'] as num).toDouble(),
      );
    }).toList();
  }
}
