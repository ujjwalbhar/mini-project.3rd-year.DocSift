import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../search/data/search_repository.dart';
import '../../search/domain/models/search_result.dart';
import '../data/embedding_repository.dart';
import '../data/qa_repository.dart';

final ragServiceProvider = Provider<RagService>((ref) {
  return RagService(
    ref.read(searchRepositoryProvider),
    ref.read(embeddingRepositoryProvider),
    ref.read(qaRepositoryProvider),
  );
});

class RagAnswer {
  const RagAnswer({
    required this.answer,
    required this.confidence,
    required this.sourceContexts,
  });

  final String answer;
  final double confidence;
  final List<SearchResult> sourceContexts;
}

class RagService {
  const RagService(
    this._searchRepo,
    this._embeddingRepo,
    this._qaRepo,
  );

  final SearchRepository _searchRepo;
  final EmbeddingRepository _embeddingRepo;
  final QaRepository _qaRepo;

  /// Detects if the question is conversational (greeting, small-talk, help)
  /// rather than a document search query.
  bool _isConversational(String q) {
    final lower = q.toLowerCase().trim();
    const greetings = [
      'hi', 'hello', 'hey', 'hii', 'howdy', 'sup', 'good morning',
      'good evening', 'good afternoon', 'what can you do', 'who are you',
      'help', 'how are you', 'what are you', 'what is docsift',
    ];
    return greetings.any((g) => lower == g || lower.startsWith('$g ') || lower.startsWith('$g,'));
  }

  String _conversationalReply(String q) {
    final lower = q.toLowerCase().trim();
    if (lower.contains('how are you')) {
      return "I'm running fully on-device and all systems are secure! How can I help you with your vault?";
    }
    if (lower.contains('who are you') || lower.contains('what are you')) {
      return "I'm DocSift AI — your private, on-device assistant. I can answer questions about your stored documents, passwords, notes, and cards. Everything stays on your device, nothing is sent to the cloud.";
    }
    if (lower.contains('what can you do') || lower == 'help') {
      return "I can help you:\n• Find info inside your stored documents\n• Search across passwords, notes, and cards\n• Answer questions about any file you've added to your vault\n\nTry asking something like: \"What is my Netflix password?\" or \"Summarise my passport details\"";
    }
    if (lower.contains('what is docsift')) {
      return "DocSift is a zero-trust, offline-first personal vault. All your files and data are encrypted with AES-256-GCM and never leave your device.";
    }
    // Default greeting
    return "Hello! I'm DocSift AI. I can answer questions about your stored documents, passwords, and notes — all on-device. What would you like to know?";
  }

  /// Given a user question, searches vault, re-ranks contexts, and generates an answer.
  Future<RagAnswer> query(String question) async {
    // 0. Handle conversational inputs without touching the DB
    if (_isConversational(question)) {
      return RagAnswer(
        answer: _conversationalReply(question),
        confidence: 1.0,
        sourceContexts: const [],
      );
    }

    // 1. BM25 Initial Search (Top 10)
    final bm25Results = await _searchRepo.search(question);
    if (bm25Results.isEmpty) {
      return const RagAnswer(
        answer: "I couldn't find any matching content in your vault for that question. Try adding documents, notes, or passwords first — then I can answer questions about them.",
        confidence: 1.0,
        sourceContexts: [],
      );
    }

    // 2. Generate embedding for the question
    await _embeddingRepo.generateEmbedding(question);

    // 3. Take top 3 BM25 results as context
    final topContexts = bm25Results.take(3).toList();
    
    // 4. Build Context String
    final contextBuilder = StringBuffer();
    for (final ctx in topContexts) {
      contextBuilder.writeln(ctx.chunkContent);
    }

    // 5. Run QA Model
    final qaResult = await _qaRepo.answer(question, contextBuilder.toString());
    
    if (qaResult == null) {
      return RagAnswer(
        answer: "I'm sorry, I encountered an error while trying to generate an answer.",
        confidence: 0.0,
        sourceContexts: topContexts,
      );
    }

    return RagAnswer(
      answer: qaResult.answer,
      confidence: qaResult.confidence,
      sourceContexts: topContexts,
    );
  }
}

