import 'dart:io';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as vector;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart' as fp;
import '../../../core/constants/app_colors.dart';
import '../../../core/router/app_router.dart';
import '../../ocr/domain/extraction_queue.dart';
import '../../vault/domain/vault_service.dart';
import '../../vault/domain/models/vault_item.dart';

import '../../auth/data/auth_repository.dart';

// ─── Providers ────────────────────────────────────────────────────────────────

final recentItemsProvider = FutureProvider<List<VaultItem>>((ref) {
  return ref.read(vaultServiceProvider).getRecentItems(limit: 6);
});

final categoryCountsProvider = FutureProvider<Map<String, int>>((ref) {
  return ref.read(vaultServiceProvider).getCategoryCounts();
});

// ─── Dashboard Screen ─────────────────────────────────────────────────────────

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _isImporting = false;

  Future<void> _importFile(String categoryId) async {
    Navigator.pop(context); // close bottom sheet

    // Suspend auto-lock while opening file picker
    ref.read(authRepositoryProvider).isBypassAutoLock = true;

    fp.FilePickerResult? result;
    try {
      result = await fp.FilePicker.platform.pickFiles(
        type: fp.FileType.custom,
        allowedExtensions: ['pdf', 'docx', 'doc', 'txt', 'md', 'jpg', 'jpeg', 'png', 'mp4', 'zip'],
        allowMultiple: false,
      );
    } finally {
      // Re-enable auto-lock
      ref.read(authRepositoryProvider).isBypassAutoLock = false;
    }

    if (result == null || result.files.isEmpty) return;

    final file = File(result.files.first.path!);

    setState(() => _isImporting = true);

    try {
      // Encrypt & save to vault
      final vaultService = ref.read(vaultServiceProvider);
      final newItem = await vaultService.importFile(file, categoryId: categoryId);

      // Kick off background OCR/extraction
      ref.read(extractionQueueProvider).enqueue(newItem);

      // Refresh UI
      ref.invalidate(recentItemsProvider);
      ref.invalidate(categoryCountsProvider);
      ref.invalidate(vaultItemsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${newItem.name} added to vault',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.accentEmerald,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import failed: $e'),
            backgroundColor: AppColors.destructiveRed,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceNeutral,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              _buildAppBar(),
              _buildSearchBar(),
              _buildCategoryGrid(),
              _buildRecentSection(),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
          // Import loading overlay
          if (_isImporting)
            Container(
              color: Colors.black.withValues(alpha: 0.4),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppColors.accentEmerald),
                    SizedBox(height: 16),
                    Text(
                      'Encrypting file...',
                      style: TextStyle(color: Colors.white, fontSize: 15),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: _buildFab(),
    );
  }

  // ─── App Bar ──────────────────────────────────────────────────────────────
  Widget _buildAppBar() {
    return SliverToBoxAdapter(
      child: Container(
        color: AppColors.cardCanvas,
        padding: const EdgeInsets.fromLTRB(20, 56, 20, 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _greeting(),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryNavy,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Your vault is secured',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.verifiedGreenBg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.verified_user_rounded,
                      size: 16, color: AppColors.verifiedGreen),
                  SizedBox(width: 6),
                  Text(
                    'Encrypted',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.verifiedGreen,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ).animate().fadeIn(duration: 400.ms),
    );
  }

  // ─── Search Bar ───────────────────────────────────────────────────────────
  Widget _buildSearchBar() {
    return SliverToBoxAdapter(
      child: Container(
        color: AppColors.cardCanvas,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: GestureDetector(
          onTap: () => context.push(AppRoutes.search),
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.surfaceNeutral,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderLight),
            ),
            child: const Row(
              children: [
                Icon(Icons.search_rounded,
                    color: AppColors.textMuted, size: 20),
                SizedBox(width: 10),
                Text(
                  'Search anything...',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Category Grid 2×3 ────────────────────────────────────────────────────
  Widget _buildCategoryGrid() {
    final countsAsync = ref.watch(categoryCountsProvider);
    final counts = countsAsync.valueOrNull ?? {};

    final categories = _categoryMeta();

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.55,
          ),
          itemCount: categories.length,
          itemBuilder: (context, index) {
            final cat = categories[index];
            final id = cat['id'] as String;
            return _CategoryCard(
              icon: cat['icon'] as IconData,
              label: cat['label'] as String,
              count: counts[id] ?? 0,
              iconColor: cat['color'] as Color,
              bgColor: cat['bg'] as Color,
              onTap: () => context.push('/category/$id'),
            ).animate().fadeIn(
                  delay: (index * 50).ms,
                  duration: 400.ms,
                ).slideY(
                  begin: 0.1,
                  end: 0,
                  delay: (index * 50).ms,
                  duration: 400.ms,
                  curve: Curves.easeOut,
                );
          },
        ),
      ),
    );
  }

  // ─── Recently Accessed ────────────────────────────────────────────────────
  Widget _buildRecentSection() {
    final recentAsync = ref.watch(recentItemsProvider);

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Recently Accessed',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryNavy,
              ),
            ),
            const SizedBox(height: 12),
            recentAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(
                    color: AppColors.accentEmerald),
              ),
              error: (_, __) => const _EmptyRecentState(),
              data: (items) => items.isEmpty
                  ? const _EmptyRecentState()
                  : Column(
                      children: items.map((item) {
                        return _RecentItemTile(item: item);
                      }).toList(),
                    ),
            ),
          ],
        ).animate().fadeIn(delay: 350.ms, duration: 400.ms),
      ),
    );
  }

  Widget _buildFab() {
    return FloatingActionButton(
      onPressed: () => _showAddSheet(),
      backgroundColor: AppColors.accentEmerald,
      elevation: 0,
      shape: const CircleBorder(),
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: AppColors.accentEmerald,
          shape: BoxShape.circle,
          boxShadow: AppColors.fabShadow,
        ),
        child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
      ),
    ).animate().scaleXY(
          begin: 0,
          delay: 500.ms,
          duration: 500.ms,
          curve: Curves.elasticOut,
        );
  }

  void _showAddSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddItemSheet(onImport: _importFile),
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning, User!';
    if (h < 17) return 'Good afternoon, User!';
    return 'Good evening, User!';
  }

  List<Map<String, dynamic>> _categoryMeta() => [
        {
          'id': 'passwords',
          'label': 'Passwords',
          'icon': Icons.key_rounded,
          'color': AppColors.categoryPasswordsColor,
          'bg': AppColors.categoryPasswordsBg,
        },
        {
          'id': 'identity',
          'label': 'Identity',
          'icon': Icons.badge_rounded,
          'color': AppColors.categoryIdentityColor,
          'bg': AppColors.categoryIdentityBg,
        },
        {
          'id': 'cards',
          'label': 'Cards',
          'icon': Icons.credit_card_rounded,
          'color': AppColors.categoryCardsColor,
          'bg': AppColors.categoryCardsBg,
        },
        {
          'id': 'notes',
          'label': 'Notes',
          'icon': Icons.sticky_note_2_rounded,
          'color': AppColors.categoryNotesColor,
          'bg': AppColors.categoryNotesBg,
        },
        {
          'id': 'documents',
          'label': 'Documents',
          'icon': Icons.description_rounded,
          'color': AppColors.categoryDocumentsColor,
          'bg': AppColors.categoryDocumentsBg,
        },
        {
          'id': 'media',
          'label': 'Media',
          'icon': Icons.perm_media_rounded,
          'color': AppColors.categoryMediaColor,
          'bg': AppColors.categoryMediaBg,
        },
      ];
}

// ─── Recent Item Tile ─────────────────────────────────────────────────────────

class _RecentItemTile extends StatelessWidget {
  const _RecentItemTile({required this.item});
  final VaultItem item;

  IconData get _icon {
    switch (item.fileType) {
      case FileType.pdf:
        return Icons.picture_as_pdf_rounded;
      case FileType.docx:

        return Icons.description_rounded;
      case FileType.image:
        return Icons.image_rounded;
      case FileType.video:
        return Icons.videocam_rounded;
      case FileType.txt:
      case FileType.md:
        return Icons.article_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  Widget _extractionBadge() {
    if (item.extractionStatus == ExtractionStatus.processing) {
      return const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.accentEmerald,
        ),
      );
    }
    if (item.extractionStatus == ExtractionStatus.done) {
      return const Icon(Icons.check_circle_rounded,
          size: 14, color: AppColors.accentEmerald);
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/item/${item.id}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.cardCanvas,
          borderRadius: BorderRadius.circular(12),
          boxShadow: AppColors.cardShadow,
        ),
        child: Row(
          children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.categoryDocumentsBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_icon, color: AppColors.categoryDocumentsColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.displayName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  item.sizeLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _extractionBadge(),
        ],
      ),
    ));
  }
}

// ─── Category Card ────────────────────────────────────────────────────────────
class _CategoryCard extends StatefulWidget {
  const _CategoryCard({
    required this.icon,
    required this.label,
    required this.count,
    required this.iconColor,
    required this.bgColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final int count;
  final Color iconColor;
  final Color bgColor;
  final VoidCallback onTap;

  @override
  State<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<_CategoryCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        transform: _pressed
            ? (Matrix4.identity()..scaleByVector3(vector.Vector3(0.97, 0.97, 1.0)))
            : Matrix4.identity(),
        decoration: BoxDecoration(
          color: AppColors.cardCanvas,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppColors.cardShadow,
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: widget.bgColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(widget.icon, color: widget.iconColor, size: 22),
            ),
            const Spacer(),
            Text(
              widget.label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${widget.count} items',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Empty Recent State ───────────────────────────────────────────────────────
class _EmptyRecentState extends StatelessWidget {
  const _EmptyRecentState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      decoration: BoxDecoration(
        color: AppColors.cardCanvas,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.cardShadow,
      ),
      child: const Column(
        children: [
          Icon(Icons.folder_open_rounded,
              size: 40, color: AppColors.borderLight),
          SizedBox(height: 12),
          Text(
            'No files yet',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryNavy,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Tap + to import your first document.',
            style: TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

// ─── Add Item Bottom Sheet ────────────────────────────────────────────────────
class _AddItemSheet extends StatelessWidget {
  const _AddItemSheet({required this.onImport});

  final void Function(String categoryId) onImport;

  @override
  Widget build(BuildContext context) {
    final options = [
      {
        'id': 'passwords',
        'icon': Icons.key_rounded,
        'label': 'Password',
        'desc': 'Save an app or web password',
        'color': AppColors.categoryPasswordsColor,
        'bg': AppColors.categoryPasswordsBg,
      },
      {
        'id': 'identity',
        'icon': Icons.badge_rounded,
        'label': 'Identity',
        'desc': 'Store identity document',
        'color': AppColors.categoryIdentityColor,
        'bg': AppColors.categoryIdentityBg,
      },
      {
        'id': 'cards',
        'icon': Icons.credit_card_rounded,
        'label': 'Card',
        'desc': 'Save payment cards',
        'color': AppColors.categoryCardsColor,
        'bg': AppColors.categoryCardsBg,
      },
      {
        'id': 'documents',
        'icon': Icons.description_rounded,
        'label': 'Document',
        'desc': 'Import PDF, DOCX, TXT files',
        'color': AppColors.categoryDocumentsColor,
        'bg': AppColors.categoryDocumentsBg,
        'filePicker': true,
      },
      {
        'id': 'notes',
        'icon': Icons.sticky_note_2_rounded,
        'label': 'Note',
        'desc': 'Write secure notes',
        'color': AppColors.categoryNotesColor,
        'bg': AppColors.categoryNotesBg,
      },
      {
        'id': 'media',
        'icon': Icons.perm_media_rounded,
        'label': 'Media',
        'desc': 'Store images, audio, video',
        'color': AppColors.categoryMediaColor,
        'bg': AppColors.categoryMediaBg,
        'filePicker': true,
      },
    ];

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.cardCanvas,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: AppColors.borderLight,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Add New Item',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryNavy,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded,
                    color: AppColors.textMuted),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const Text(
            'Choose a category',
            style: TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
          const SizedBox(height: 20),
          ...options.map(
            (opt) => _SheetOption(
              icon: opt['icon'] as IconData,
              label: opt['label'] as String,
              desc: opt['desc'] as String,
              color: opt['color'] as Color,
              bg: opt['bg'] as Color,
              showFilePicker: (opt['filePicker'] as bool?) ?? false,
              onTap: () {
                final isFilePicker = (opt['filePicker'] as bool?) ?? false;
                if (isFilePicker) {
                  onImport(opt['id'] as String);
                } else {
                  Navigator.pop(context);
                  context.push('/add/${opt['id']}');
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetOption extends StatelessWidget {
  const _SheetOption({
    required this.icon,
    required this.label,
    required this.desc,
    required this.color,
    required this.bg,
    required this.onTap,
    this.showFilePicker = false,
  });

  final IconData icon;
  final String label;
  final String desc;
  final Color color;
  final Color bg;
  final VoidCallback onTap;
  final bool showFilePicker;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    desc,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (showFilePicker)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.surfaceNeutral,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Pick file',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              )
            else
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textMuted, size: 20),
          ],
        ),
      ),
    );
  }
}
