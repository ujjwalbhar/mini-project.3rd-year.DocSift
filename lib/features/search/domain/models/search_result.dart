import 'dart:typed_data';

class SearchResult {
  const SearchResult({
    required this.vaultItemId,
    required this.itemName,
    required this.fileType,
    required this.chunkContent,
    required this.score,
    this.chunkId,
    this.embedding,
  });

  final String vaultItemId;
  final String itemName;
  final String fileType;
  final String chunkContent;
  final double score;
  final String? chunkId;
  final Uint8List? embedding;
}
