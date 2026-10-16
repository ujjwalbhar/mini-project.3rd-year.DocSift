import 'package:flutter_test/flutter_test.dart';
import 'package:docsift/features/ai/domain/rag_service.dart';
import 'package:docsift/features/ai/data/embedding_repository.dart';
import 'package:docsift/features/ai/data/qa_repository.dart';
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
}
