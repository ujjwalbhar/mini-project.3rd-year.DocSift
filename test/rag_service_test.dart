import 'package:flutter_test/flutter_test.dart';
import 'package:docsift/features/ai/domain/rag_service.dart';
import 'package:docsift/features/ai/data/embedding_repository.dart';
import 'package:docsift/features/ai/data/qa_repository.dart';
import 'package:docsift/features/ocr/data/text_chunker.dart';
import 'package:docsift/features/search/data/search_repository.dart';
import 'package:docsift/features/search/domain/models/search_result.dart';
import 'package:docsift/shared/providers/database_provider.dart';
import 'package:docsift/features/ai/data/model_manager.dart';

// Simple mock classes
class MockSearchRepo extends SearchRepository {
  MockSearchRepo(super.db);
  @override
  Future<List<SearchResult>> search(String query) async {
    return [
      const SearchResult(
        vaultItemId: '1',
        itemName: 'Test Doc',
        fileType: 'txt',
        chunkContent: 'This is a test chunk containing the answer.',
        score: -2.5,
      ),
    ];
  }
}

class MockEmbeddingRepo extends EmbeddingRepository {
  MockEmbeddingRepo(super.manager);
  @override
  Future<List<double>> generateEmbedding(String text) async {
    return List<double>.filled(384, 0.1);
  }
}

class MockQaRepo extends QaRepository {
  MockQaRepo(super.manager);
  @override
  Future<QaResult?> answer(String question, String context) async {
    return const QaResult('Simulated answer', 0.99);
  }
}

class _CountingEmbeddingRepo extends EmbeddingRepository {
  _CountingEmbeddingRepo(super.manager, this.onGenerate);
  final void Function() onGenerate;

  @override
  Future<List<double>> generateEmbedding(String text) async {
    onGenerate();
    return super.generateEmbedding(text);
  }
}

class _PrecomputedSearchRepo extends SearchRepository {
  _PrecomputedSearchRepo(super.db, this.blob);
  final dynamic blob;

  @override
  Future<List<SearchResult>> search(String query) async {
    return [
      SearchResult(
        vaultItemId: 'doc-1',
        itemName: 'Passport',
        fileType: 'pdf',
        chunkContent: 'Passport number A1234567',
        score: -3.2,
        embedding: blob,
      ),
    ];
  }
}

void main() {
  test('RagService orchestrates search, embedding, and QA', () async {
    final mockDbProvider = DatabaseProvider();
    final mockManager = ModelManager();
    final searchRepo = MockSearchRepo(mockDbProvider);
    final embeddingRepo = MockEmbeddingRepo(mockManager);
    final qaRepo = MockQaRepo(mockManager);

    final ragService = RagService(searchRepo, embeddingRepo, qaRepo);

    final result = await ragService.query('What is this?');

    expect(result.answer, 'Simulated answer');
    expect(result.confidence, 0.99);
    expect(result.sourceContexts.length, 1);
    expect(result.sourceContexts.first.itemName, 'Test Doc');
  });

  test('RagService handles conversational prompts without hitting DB', () async {
    final mockDbProvider = DatabaseProvider();
    final mockManager = ModelManager();
    final ragService = RagService(
      MockSearchRepo(mockDbProvider),
      MockEmbeddingRepo(mockManager),
      MockQaRepo(mockManager),
    );

    final reply = await ragService.query('Hello');
    expect(reply.sourceContexts, isEmpty);
    expect(reply.confidence, 1.0);
    expect(reply.answer, contains('DocSift AI'));
  });

  test('EmbeddingRepository normalizes fallback embeddings and computes cosine similarity', () async {
    final repo = EmbeddingRepository(ModelManager());
    final v1 = await repo.generateEmbedding('netflix password account');
    final v2 = await repo.generateEmbedding('netflix password login');
    final v3 = await repo.generateEmbedding('passport expiry date');

    expect(v1.length, 384);
    final simSame = repo.cosineSimilarity(v1, v2);
    final simDiff = repo.cosineSimilarity(v1, v3);
    expect(simSame, greaterThan(simDiff));
  });

  test('EmbeddingRepository encodes and decodes Float32List BLOB losslessly', () async {
    final repo = EmbeddingRepository(ModelManager());
    final original = await repo.generateEmbedding('zero trust personal vault');
    final blob = repo.encodeEmbedding(original);

    expect(blob.lengthInBytes, 384 * 4);
    final decoded = repo.decodeEmbedding(blob);
    expect(decoded.length, original.length);
    for (int i = 0; i < original.length; i++) {
      expect(decoded[i], closeTo(original[i], 1e-6));
    }
  });

  test('RagService uses pre-computed SQLite BLOB embedding when present on SearchResult', () async {
    final mockDbProvider = DatabaseProvider();
    final mockManager = ModelManager();
    final embeddingRepo = EmbeddingRepository(mockManager);
    final precomputedVec = await embeddingRepo.generateEmbedding('Passport number A1234567');
    final precomputedBlob = embeddingRepo.encodeEmbedding(precomputedVec);

    int generateCalls = 0;
    final countingEmbeddingRepo = _CountingEmbeddingRepo(mockManager, () {
      generateCalls++;
    });

    final searchRepo = _PrecomputedSearchRepo(mockDbProvider, precomputedBlob);
    final qaRepo = MockQaRepo(mockManager);
    final ragService = RagService(searchRepo, countingEmbeddingRepo, qaRepo);

    final result = await ragService.query('What is my passport number?');
    expect(result.answer, 'Simulated answer');
    // Only 1 call for the user question; candidate chunk embedding was decoded from BLOB
    expect(generateCalls, 1);
  });

  test('QaRepository extracts matching sentence with highest keyword overlap', () async {
    final qaRepo = QaRepository(ModelManager());
    const context =
        'title: Netflix.\nNetflix username is user@example.com.\nNetflix password is SuperSecret99.';
    final res = await qaRepo.answer('What is my Netflix password?', context);
    expect(res, isNotNull);
    expect(res!.answer, contains('SuperSecret99'));
  });

  test('TextChunker splits long text at sentence boundaries with overlap', () {
    final paragraph = List.generate(30, (i) => 'Sentence number $i has some sample content.').join(' ');
    final chunks = TextChunker.chunk(paragraph, chunkSize: 300, overlap: 50);
    expect(chunks.length, greaterThan(1));
    for (final c in chunks) {
      expect(c, isNotEmpty);
    }
  });
}
