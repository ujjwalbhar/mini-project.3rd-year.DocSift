class SearchResult {
  const SearchResult({
    required this.vaultItemId,
    required this.itemName,
    required this.fileType,
    required this.chunkContent,
    required this.score,
  });

  final String vaultItemId;
  final String itemName;
  final String fileType;
  final String chunkContent;
  final double score;
}
