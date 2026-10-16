import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../../../core/constants/app_colors.dart';
import '../../vault/domain/vault_service.dart';
import '../../vault/data/vault_repository.dart';
import '../domain/models/vault_item.dart';

final vaultItemProvider = FutureProvider.family<VaultItem?, String>((ref, id) async {
  final items = await ref.read(vaultServiceProvider).getVaultItems();
  try {
    return items.firstWhere((item) => item.id == id);
  } catch (_) {
    return null;
  }
});

final decryptedBytesProvider = FutureProvider.family<Uint8List, String>((ref, encryptedPath) async {
  return await ref.read(vaultRepositoryProvider).decryptToMemory(encryptedPath);
});

class ItemDetailScreen extends ConsumerWidget {
  const ItemDetailScreen({super.key, required this.itemId});
  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemAsync = ref.watch(vaultItemProvider(itemId));

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
        title: itemAsync.when(
          data: (item) => Text(
            item?.displayName ?? 'Not Found',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryNavy,
            ),
          ),
          loading: () => const Text('Loading...'),
          error: (_, __) => const Text('Error'),
        ),
        actions: itemAsync.maybeWhen(
          data: (item) {
            if (item != null && (item.fileType == FileType.json || item.fileType == FileType.txt || item.fileType == FileType.md)) {
              return [
                IconButton(
                  icon: const Icon(Icons.edit_rounded, color: AppColors.primaryNavy),
                  onPressed: () async {
                    // Pre-fetch the bytes to pass to the edit screen
                    final bytes = await ref.read(vaultRepositoryProvider).decryptToMemory(item.encryptedFilePath);
                    final text = utf8.decode(bytes);
                    if (context.mounted) {
                      context.push('/edit_text_item/${item.id}', extra: {
                        'item': item,
                        'content': text,
                      });
                    }
                  },
                ),
              ];
            }
            return null;
          },
          orElse: () => null,
        ),
      ),
      body: itemAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.accentEmerald),
        ),
        error: (e, _) => Center(
          child: Text('Error: $e', style: const TextStyle(color: AppColors.destructiveRed)),
        ),
        data: (item) {
          if (item == null) {
            return const Center(child: Text('Item not found.'));
          }

          if (item.fileType == FileType.txt || item.fileType == FileType.md) {
            return _buildTextContent(context, ref, item.encryptedFilePath);
          } else if (item.fileType == FileType.json) {
            return _buildJsonContent(context, ref, item, item.encryptedFilePath);
          } else if (item.fileType == FileType.image) {
            return _buildImageContent(context, ref, item.encryptedFilePath);
          } else if (item.fileType == FileType.pdf) {
            return _buildPdfContent(context, ref, item.encryptedFilePath);
          } else {
            return _buildUnsupportedContent(item);
          }
        },
      ),
    );
  }

  Widget _buildJsonContent(BuildContext context, WidgetRef ref, VaultItem item, String encryptedPath) {
    final bytesAsync = ref.watch(decryptedBytesProvider(encryptedPath));
    return bytesAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.accentEmerald),
      ),
      error: (e, _) => Center(
        child: Text('Error decrypting: $e', style: const TextStyle(color: AppColors.destructiveRed)),
      ),
      data: (bytes) {
        try {
          final text = utf8.decode(bytes);
          final Map<String, dynamic> data = jsonDecode(text);

          switch (item.categoryId) {
            case 'passwords':
              return _buildPasswordUi(context, data);
            case 'cards':
              return _buildCardUi(context, data);
            case 'identity':
              return _buildIdentityUi(context, data);
            case 'notes':
              return _buildNotesUi(context, data);
            default:
              return _buildDefaultJsonUi(context, data);
          }
        } catch (e) {
          return Center(child: Text('Failed to parse JSON data: $e'));
        }
      },
    );
  }

  Widget _buildPasswordUi(BuildContext context, Map<String, dynamic> data) {
    final title = data['title'] ?? data['website'] ?? data['appName'] ?? 'Unknown Account';
    final username = data['username'] ?? data['email'] ?? 'No Username';
    final password = data['password'] ?? '';
    final notes = data['notes'] ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCopyableField(context, 'Website / App', title),
          const SizedBox(height: 16),
          _buildCopyableField(context, 'Username / Email', username),
          const SizedBox(height: 16),
          _PasswordValueField(password: password),
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildCopyableField(context, 'Notes', notes),
          ],
        ],
      ),
    );
  }

  Widget _buildCardUi(BuildContext context, Map<String, dynamic> data) {
    final bankName = data['bankName'] ?? 'Unknown Bank';
    final cardHolder = data['cardHolder'] ?? 'Card Holder';
    final cardNumber = data['cardNumber'] ?? '**** **** **** ****';
    final expiry = data['expiry'] ?? 'MM/YY';
    final cvv = data['cvv'] ?? '***';
    final pin = data['pin'] ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primaryNavy, Color(0xFF1E3A5F)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryNavy.withValues(alpha: 0.4),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      bankName,
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const Icon(Icons.credit_card_rounded, color: Colors.white, size: 32),
                  ],
                ),
                const SizedBox(height: 32),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: cardNumber));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Card number copied to clipboard')),
                    );
                  },
                  child: Text(
                    _formatCardNumber(cardNumber),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      letterSpacing: 3,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('CARDHOLDER', style: TextStyle(color: Colors.white70, fontSize: 10)),
                        const SizedBox(height: 4),
                        Text(cardHolder.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 14)),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('EXPIRES', style: TextStyle(color: Colors.white70, fontSize: 10)),
                        const SizedBox(height: 4),
                        Text(expiry, style: const TextStyle(color: Colors.white, fontSize: 14)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(child: _buildCopyableField(context, 'CVV', cvv)),
              const SizedBox(width: 16),
              if (pin.isNotEmpty)
                Expanded(child: _buildCopyableField(context, 'ATM PIN', pin)),
            ],
          ),
        ],
      ),
    );
  }

  String _formatCardNumber(String number) {
    final clean = number.replaceAll(RegExp(r'\s+'), '');
    if (clean.length != 16) return number;
    return '${clean.substring(0,4)} ${clean.substring(4,8)} ${clean.substring(8,12)} ${clean.substring(12,16)}';
  }

  Widget _buildIdentityUi(BuildContext context, Map<String, dynamic> data) {
    final documentName = data['documentName'] ?? 'Identity Document';
    final idNumber = data['idNumber'] ?? '';
    final dob = data['dob'] ?? '';
    final issuedBy = data['issuedBy'] ?? '';
    final expiry = data['expiry'] ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.badge_rounded, size: 64, color: AppColors.primaryNavy),
          const SizedBox(height: 16),
          Text(
            documentName,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.primaryNavy),
          ),
          const SizedBox(height: 24),
          _buildCopyableField(context, 'ID Number', idNumber),
          const SizedBox(height: 16),
          Row(
            children: [
              if (dob.isNotEmpty) Expanded(child: _buildCopyableField(context, 'Date of Birth', dob)),
              if (dob.isNotEmpty && expiry.isNotEmpty) const SizedBox(width: 16),
              if (expiry.isNotEmpty) Expanded(child: _buildCopyableField(context, 'Expiry Date', expiry)),
            ],
          ),
          const SizedBox(height: 16),
          if (issuedBy.isNotEmpty) _buildCopyableField(context, 'Issued By', issuedBy),
        ],
      ),
    );
  }

  Widget _buildNotesUi(BuildContext context, Map<String, dynamic> data) {
    final title = data['title'] ?? 'Note';
    final content = data['content'] ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.primaryNavy),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.cardCanvas,
              borderRadius: BorderRadius.circular(16),
              boxShadow: AppColors.cardShadow,
            ),
            child: Text(
              content,
              style: const TextStyle(
                fontSize: 16,
                height: 1.5,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultJsonUi(BuildContext context, Map<String, dynamic> data) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.cardCanvas,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppColors.cardShadow,
        ),
        child: Text(
          const JsonEncoder.withIndent('  ').convert(data),
          style: const TextStyle(
            fontSize: 14,
            height: 1.5,
            fontFamily: 'monospace',
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildCopyableField(BuildContext context, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 14, color: AppColors.textMuted, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () {
            Clipboard.setData(ClipboardData(text: value));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('$label copied to clipboard')),
            );
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: AppColors.cardCanvas,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderLight),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: const TextStyle(fontSize: 16, color: AppColors.textPrimary),
                  ),
                ),
                const Icon(Icons.copy_rounded, size: 20, color: AppColors.primaryNavy),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextContent(BuildContext context, WidgetRef ref, String encryptedPath) {
    final bytesAsync = ref.watch(decryptedBytesProvider(encryptedPath));
    return bytesAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.accentEmerald),
      ),
      error: (e, _) => Center(
        child: Text('Error decrypting: $e', style: const TextStyle(color: AppColors.destructiveRed)),
      ),
      data: (bytes) {
        final text = utf8.decode(bytes);
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.cardCanvas,
              borderRadius: BorderRadius.circular(16),
              boxShadow: AppColors.cardShadow,
            ),
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 16,
                height: 1.5,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildImageContent(BuildContext context, WidgetRef ref, String encryptedPath) {
    final bytesAsync = ref.watch(decryptedBytesProvider(encryptedPath));
    return bytesAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.accentEmerald),
      ),
      error: (e, _) => Center(
        child: Text('Error decrypting: $e', style: const TextStyle(color: AppColors.destructiveRed)),
      ),
      data: (bytes) {
        return Center(
          child: InteractiveViewer(
            minScale: 1.0,
            maxScale: 4.0,
            child: Image.memory(
              bytes,
              fit: BoxFit.contain,
            ),
          ),
        );
      },
    );
  }

  Widget _buildPdfContent(BuildContext context, WidgetRef ref, String encryptedPath) {
    final bytesAsync = ref.watch(decryptedBytesProvider(encryptedPath));
    return bytesAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.accentEmerald),
      ),
      error: (e, _) => Center(
        child: Text('Error decrypting: $e', style: const TextStyle(color: AppColors.destructiveRed)),
      ),
      data: (bytes) {
        return SfPdfViewer.memory(bytes);
      },
    );
  }

  Widget _buildUnsupportedContent(VaultItem item) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.description_rounded, size: 64, color: AppColors.borderLight),
            const SizedBox(height: 20),
            Text(
              'File Type: ${item.originalExtension.toUpperCase()}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryNavy,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'In-app viewing for this file type is coming soon. The file is securely encrypted in your vault.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _PasswordValueField extends StatefulWidget {
  final String password;
  const _PasswordValueField({required this.password});

  @override
  State<_PasswordValueField> createState() => _PasswordValueFieldState();
}

class _PasswordValueFieldState extends State<_PasswordValueField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Password',
          style: TextStyle(fontSize: 14, color: AppColors.textMuted, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.cardCanvas,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  child: Text(
                    _obscured ? '•' * widget.password.length : widget.password,
                    style: const TextStyle(fontSize: 16, color: AppColors.textPrimary, letterSpacing: 2),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  _obscured ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                  color: AppColors.primaryNavy,
                ),
                onPressed: () {
                  setState(() {
                    _obscured = !_obscured;
                  });
                },
              ),
              IconButton(
                icon: const Icon(Icons.copy_rounded, color: AppColors.primaryNavy),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: widget.password));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Password copied to clipboard')),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
