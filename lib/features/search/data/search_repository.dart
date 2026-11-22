import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/providers/database_provider.dart';
import '../domain/models/search_result.dart';

final searchRepositoryProvider = Provider<SearchRepository>((ref) {
  return SearchRepository(ref.read(databaseProvider));
});

class SearchRepository {
  const SearchRepository(this._dbProvider);
  final DatabaseProvider _dbProvider;

  static const metadataOnlySnippetPrefix = 'Matched vault item · ';

  static const _stopWords = {
    'what', 'is', 'are', 'the', 'my', 'a', 'an', 'of', 'in', 'to', 'for',
    'do', 'does', 'did', 'show', 'tell', 'me', 'about', 'where', 'when',
    'who', 'how', 'can', 'you', 'find', 'get', 'give', 'please',
  };

  /// Sanitizes [query], removes FTS5 punctuation/operators, and filters
  /// conversational stop-words when meaningful search terms are present.
  static List<String> extractEffectiveTerms(String query) {
    if (query.trim().isEmpty) return const <String>[];

    final sanitized = query
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .trim();
    if (sanitized.isEmpty) return const <String>[];

    final allTerms = sanitized
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (allTerms.isEmpty) return const <String>[];

    final filteredTerms =
        allTerms.where((t) => !_stopWords.contains(t)).toList();
    return filteredTerms.isNotEmpty ? filteredTerms : allTerms;
  }

  /// Merges FTS5 chunk-level BM25 hits with filename/tag/extension matches on
  /// `vault_items`, boosting items whose title AND content match while surfacing
  /// binary/unindexed items and title-matched documents cleanly.
  static List<SearchResult> mergeFtsAndItemMatches({
    required List<SearchResult> ftsResults,
    required List<Map<String, Object?>> itemRows,
    required List<String> effectiveTerms,
    int limit = 20,
  }) {
    final titleBoostByItem = <String, int>{};
    for (final row in itemRows) {
      final id = row['id'] as String;
      final name = (row['name'] as String? ?? '').toLowerCase();
      final ext = (row['original_extension'] as String? ?? '').toLowerCase();
      final tags = (row['tags'] as String? ?? '').toLowerCase();
      final haystack = '$name $ext $tags';

      int matchedCount = 0;
      for (final term in effectiveTerms) {
        if (haystack.contains(term)) {
          matchedCount++;
        }
      }
      titleBoostByItem[id] = matchedCount > 0 ? matchedCount : 1;
    }

    final seenItemIdsInFts = <String>{};
    final merged = <SearchResult>[];

    // 1. Keep all FTS5 chunk hits, boosting score when the item's title/tags also matched
    for (final fts in ftsResults) {
      seenItemIdsInFts.add(fts.vaultItemId);
      final titleMatches = titleBoostByItem[fts.vaultItemId] ?? 0;
      if (titleMatches > 0) {
        merged.add(
          SearchResult(
            chunkId: fts.chunkId,
            vaultItemId: fts.vaultItemId,
            itemName: fts.itemName,
            fileType: fts.fileType,
            chunkContent: fts.chunkContent,
            score: fts.score - (2.5 * titleMatches),
            embedding: fts.embedding,
          ),
        );
      } else {
        merged.add(fts);
      }
    }

    // 2. Append items matched by filename/tags/extension that had no FTS chunk hit
    for (final row in itemRows) {
      final id = row['id'] as String;
      if (seenItemIdsInFts.contains(id)) continue;

      final itemName = row['name'] as String;
      final fileType = row['file_type'] as String;
      final ext = (row['original_extension'] as String? ?? '').trim();
      final firstChunkId = row['first_chunk_id'] as String?;
      final firstChunkContent = row['first_chunk_content'] as String?;
      final firstChunkEmbedding = row['first_chunk_embedding'] as Uint8List?;
      final matchedTerms = titleBoostByItem[id] ?? 1;

      if (firstChunkContent != null && firstChunkContent.trim().isNotEmpty) {
        merged.add(
          SearchResult(
            chunkId: firstChunkId,
            vaultItemId: id,
            itemName: itemName,
            fileType: fileType,
            chunkContent: firstChunkContent,
            score: -4.0 * matchedTerms,
            embedding: firstChunkEmbedding,
          ),
        );
      } else {
        final badge = ext.isNotEmpty ? ext.toUpperCase() : fileType.toUpperCase();
        merged.add(
          SearchResult(
            chunkId: null,
            vaultItemId: id,
            itemName: itemName,
            fileType: fileType,
            chunkContent: '$metadataOnlySnippetPrefix$badge',
            score: -3.0 * matchedTerms,
            embedding: null,
          ),
        );
      }
    }

    // Lower (more negative) BM25/hybrid score ranks higher
    merged.sort((a, b) => a.score.compareTo(b.score));
    return merged.length > limit ? merged.sublist(0, limit) : merged;
  }

  Future<List<SearchResult>> search(String query) async {
    final effectiveTerms = extractEffectiveTerms(query);
    if (effectiveTerms.isEmpty) return [];

    // Use OR with prefix matching; BM25 naturally ranks multi-term matches highest
    final matchQuery = effectiveTerms.map((t) => '"$t"*').join(' OR ');

    final db = await _dbProvider.database;

    // 1. SQLite FTS5 chunk content search (bm25 returns negative score; lower is better)
    const ftsSql = '''
      SELECT 
        tc.id AS chunk_id,
        tc.vault_item_id, 
        tc.content, 
        tc.embedding,
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

    final ftsRows = await db.rawQuery(ftsSql, [matchQuery]);
    final ftsResults = ftsRows.map((row) {
      return SearchResult(
        chunkId: row['chunk_id'] as String?,
        vaultItemId: row['vault_item_id'] as String,
        itemName: row['item_name'] as String,
        fileType: row['file_type'] as String,
        chunkContent: row['content'] as String,
        score: (row['score'] as num).toDouble(),
        embedding: row['embedding'] as Uint8List?,
      );
    }).toList();

    // 2. Filename, extension & tags search across vault_items (including binary items
    // with zero text chunks and documents queried by their title)
    final likeClauses = <String>[];
    final likeArgs = <Object?>[];
    for (final term in effectiveTerms) {
      final pattern = '%$term%';
      likeClauses.add(
        "(LOWER(vi.name) LIKE ? OR LOWER(vi.original_extension) LIKE ? OR LOWER(COALESCE(vi.tags, '')) LIKE ?)",
      );
      likeArgs
        ..add(pattern)
        ..add(pattern)
        ..add(pattern);
    }

    final itemSql = '''
      SELECT
        vi.id,
        vi.name,
        vi.file_type,
        vi.original_extension,
        vi.tags,
        tc.id AS first_chunk_id,
        tc.content AS first_chunk_content,
        tc.embedding AS first_chunk_embedding
      FROM vault_items vi
      LEFT JOIN text_chunks tc
        ON tc.vault_item_id = vi.id AND tc.chunk_index = 0
      WHERE ${likeClauses.join(' OR ')}
      ORDER BY vi.modified_at DESC
      LIMIT 15;
    ''';

    final itemRows = await db.rawQuery(itemSql, likeArgs);

    return mergeFtsAndItemMatches(
      ftsResults: ftsResults,
      itemRows: itemRows,
      effectiveTerms: effectiveTerms,
    );
  }

  /// Caches a newly generated Float32 embedding BLOB onto an existing chunk row
  /// (e.g., after DB migration from schema v1 -> v2).
  Future<void> cacheChunkEmbedding(String chunkId, Uint8List embedding) async {
    try {
      final db = await _dbProvider.database;
      await db.update(
        'text_chunks',
        {'embedding': embedding},
        where: 'id = ?',
        whereArgs: [chunkId],
      );
    } catch (_) {}
  }
}
