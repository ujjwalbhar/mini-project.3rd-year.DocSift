import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../data/search_repository.dart';
import '../domain/models/search_result.dart';
import '../../vault/domain/models/vault_item.dart' show FileType;

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<SearchResult> _results = [];
  bool _isLoading = false;

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (query.trim().isEmpty) {
        if (mounted) {
          setState(() {
            _results = [];
            _isLoading = false;
          });
        }
        return;
      }

      setState(() => _isLoading = true);
      try {
        final repo = ref.read(searchRepositoryProvider);
        final results = await repo.search(query);
        if (mounted) {
          setState(() {
            _results = results;
            _isLoading = false;
          });
        }
      } catch (e) {
        debugPrint('Search error: $e');
        if (mounted) {
          setState(() {
            _results = [];
            _isLoading = false;
          });
        }
      }
    });
  }

  IconData _iconForType(String fileTypeString) {
    final type = FileType.values.firstWhere(
      (e) => e.name == fileTypeString,
      orElse: () => FileType.other,
    );
    switch (type) {
      case FileType.pdf: return Icons.picture_as_pdf_rounded;
      case FileType.docx: return Icons.description_rounded;
      case FileType.txt:
      case FileType.md: return Icons.article_rounded;
      case FileType.image: return Icons.image_rounded;
      case FileType.video: return Icons.videocam_rounded;
      case FileType.zip: return Icons.folder_zip_rounded;
      default: return Icons.insert_drive_file_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceNeutral,
      appBar: AppBar(
        title: const Text('Search Vault'),
        backgroundColor: AppColors.cardCanvas,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.primaryNavy),
        titleTextStyle: const TextStyle(
          color: AppColors.primaryNavy,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      body: Column(
        children: [
          Container(
            color: AppColors.cardCanvas,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: TextField(
              controller: _controller,
              autofocus: true,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: AppStrings.searchHint,
                prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textMuted),
                suffixIcon: _controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, color: AppColors.textMuted),
                        onPressed: () {
                          _controller.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: AppColors.surfaceNeutral,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          
          Expanded(
            child: _isLoading 
                ? const Center(child: CircularProgressIndicator(color: AppColors.accentEmerald))
                : _results.isEmpty && _controller.text.trim().isNotEmpty
                    ? const Center(
                        child: Text(
                          'No results found.',
                          style: TextStyle(color: AppColors.textMuted),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _results.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final res = _results[index];
                          return GestureDetector(
                            onTap: () => context.push('/item/${res.vaultItemId}'),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppColors.cardCanvas,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: AppColors.cardShadow,
                              ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(_iconForType(res.fileType), size: 18, color: AppColors.accentEmerald),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        res.itemName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                          color: AppColors.primaryNavy,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  res.chunkContent,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textMuted,
                                    height: 1.4,
                                  ),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ));
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
