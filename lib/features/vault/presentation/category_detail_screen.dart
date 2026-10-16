import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../vault/domain/vault_service.dart';
import '../../vault/domain/models/vault_item.dart';

/// Category detail screen — loads real items from DB
class CategoryDetailScreen extends ConsumerWidget {
  const CategoryDetailScreen({super.key, required this.categoryId});
  final String categoryId;

  String get _title {
    switch (categoryId) {
      case 'passwords': return 'Passwords';
      case 'identity': return 'Identity';
      case 'cards': return 'Cards';
      case 'notes': return 'Notes';
      case 'documents': return 'Documents';
      case 'media': return 'Media';
      default: return categoryId;
    }
  }

  Color get _accentColor {
    switch (categoryId) {
      case 'passwords': return AppColors.categoryPasswordsColor;
      case 'identity': return AppColors.categoryIdentityColor;
      case 'cards': return AppColors.categoryCardsColor;
      case 'notes': return AppColors.categoryNotesColor;
      case 'documents': return AppColors.categoryDocumentsColor;
      case 'media': return AppColors.categoryMediaColor;
      default: return AppColors.accentEmerald;
    }
  }

  Color get _accentBg {
    switch (categoryId) {
      case 'passwords': return AppColors.categoryPasswordsBg;
      case 'identity': return AppColors.categoryIdentityBg;
      case 'cards': return AppColors.categoryCardsBg;
      case 'notes': return AppColors.categoryNotesBg;
      case 'documents': return AppColors.categoryDocumentsBg;
      case 'media': return AppColors.categoryMediaBg;
      default: return AppColors.accentEmeraldLight;
    }
  }

  bool get _isFileBased => categoryId == 'documents' || categoryId == 'media';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(vaultItemsProvider(categoryId));

    return Scaffold(
      backgroundColor: AppColors.surfaceNeutral,
      appBar: AppBar(
        backgroundColor: AppColors.cardCanvas,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          color: AppColors.textPrimary,
          onPressed: () => context.pop(),
        ),
        title: Text(
          _title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: AppColors.primaryNavy,
          ),
        ),
      ),
      body: itemsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.accentEmerald),
        ),
        error: (e, _) => Center(
          child: Text('Error loading items: $e',
              style: const TextStyle(color: AppColors.destructiveRed)),
        ),
        data: (items) {
          if (items.isEmpty) {
            return _buildEmptyState(context);
          }
          return _buildItemList(context, ref, items);
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (_isFileBased) {
            // For documents/media, go back to dashboard and open add sheet
            context.pop();
          } else {
            context.push('/add/$categoryId');
          }
        },
        backgroundColor: _accentColor,
        elevation: 0,
        shape: const CircleBorder(),
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: _accentBg,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(_categoryIcon, color: _accentColor, size: 36),
            ),
            const SizedBox(height: 20),
            Text(
              'No $_title yet',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryNavy,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isFileBased
                  ? 'Tap + on the dashboard to import a file.'
                  : 'Tap + to add your first item.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemList(
      BuildContext context, WidgetRef ref, List<VaultItem> items) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _ItemTile(
          item: item,
          accentColor: _accentColor,
          accentBg: _accentBg,
          onDelete: () async {
            await ref.read(vaultServiceProvider).deleteItem(item);
            ref.invalidate(vaultItemsProvider);
          },
        );
      },
    );
  }

  IconData get _categoryIcon {
    switch (categoryId) {
      case 'passwords': return Icons.key_rounded;
      case 'identity': return Icons.badge_rounded;
      case 'cards': return Icons.credit_card_rounded;
      case 'notes': return Icons.sticky_note_2_rounded;
      case 'documents': return Icons.description_rounded;
      case 'media': return Icons.perm_media_rounded;
      default: return Icons.folder_rounded;
    }
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({
    required this.item,
    required this.accentColor,
    required this.accentBg,
    required this.onDelete,
  });

  final VaultItem item;
  final Color accentColor;
  final Color accentBg;
  final VoidCallback onDelete;

  IconData get _icon {
    switch (item.fileType) {
      case FileType.pdf: return Icons.picture_as_pdf_rounded;
      case FileType.docx: return Icons.description_rounded;
      case FileType.image: return Icons.image_rounded;
      case FileType.video: return Icons.videocam_rounded;
      case FileType.txt:
      case FileType.md: return Icons.article_rounded;
      default: return Icons.insert_drive_file_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.cardCanvas,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppColors.cardShadow,
      ),
      child: ListTile(
        onTap: () => context.push('/item/${item.id}'),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: accentBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(_icon, color: accentColor, size: 22),
        ),
        title: Text(
          item.displayName,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${item.sizeLabel} · ${_formatDate(item.modifiedAt)}',
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item.extractionStatus == ExtractionStatus.processing)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.accentEmerald,
                ),
              )
            else if (item.extractionStatus == ExtractionStatus.done)
              const Icon(Icons.check_circle_rounded,
                  size: 16, color: AppColors.accentEmerald),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _confirmDelete(context),
              child: const Icon(Icons.delete_outline_rounded,
                  size: 20, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Item'),
        content:
            Text('Permanently delete "${item.displayName}" from your vault?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              onDelete();
            },
            child: const Text('Delete',
                style: TextStyle(color: AppColors.destructiveRed)),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
