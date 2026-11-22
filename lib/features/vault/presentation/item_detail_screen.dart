import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/secure_clipboard.dart';
import '../../auth/data/auth_repository.dart';
import '../../autofill/autofill_sync_service.dart';
import '../../ocr/data/docx_extractor.dart';
import '../../ocr/data/ocr_repository.dart';
import '../../ocr/domain/extraction_queue.dart';
import '../../vault/domain/vault_service.dart';
import '../../vault/data/vault_repository.dart';
import '../domain/models/vault_item.dart';
import '../domain/models/vault_templates.dart';
import 'dashboard_screen.dart';

final vaultItemProvider = FutureProvider.autoDispose.family<VaultItem?, String>((ref, id) async {
  final items = await ref.read(vaultServiceProvider).getVaultItems();
  try {
    return items.firstWhere((item) => item.id == id);
  } catch (_) {
    return null;
  }
});

final decryptedBytesProvider = FutureProvider.autoDispose.family<Uint8List, String>((ref, encryptedPath) async {
  final bytes = await ref.read(vaultRepositoryProvider).decryptToMemory(encryptedPath);
  ref.onDispose(() {
    for (int i = 0; i < bytes.length; i++) {
      bytes[i] = 0;
    }
  });
  return bytes;
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
            if (item == null) return null;
            final isEditable = item.fileType == FileType.json ||
                item.fileType == FileType.txt ||
                item.fileType == FileType.md;
            final hasOcrView = item.fileType == FileType.image ||
                item.fileType == FileType.pdf;
            return [
              if (hasOcrView)
                IconButton(
                  tooltip: 'Extracted OCR Text',
                  icon: const Icon(
                    Icons.document_scanner_outlined,
                    color: AppColors.primaryNavy,
                  ),
                  onPressed: () => _showExtractedTextSheet(context, ref, item),
                ),
              IconButton(
                tooltip: item.isStarred ? 'Unstar' : 'Star',
                icon: Icon(
                  item.isStarred ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: item.isStarred
                      ? AppColors.categoryCardsColor
                      : AppColors.primaryNavy,
                ),
                onPressed: () async {
                  await ref.read(vaultServiceProvider).toggleStar(item);
                  ref.invalidate(vaultItemProvider(item.id));
                  ref.invalidate(vaultItemsProvider);
                  ref.invalidate(recentItemsProvider);
                },
              ),
              if (isEditable)
                IconButton(
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit_rounded, color: AppColors.primaryNavy),
                  onPressed: () async {
                    final bytes = await ref
                        .read(vaultRepositoryProvider)
                        .decryptToMemory(item.encryptedFilePath);
                    final text = utf8.decode(bytes, allowMalformed: true);
                    for (int i = 0; i < bytes.length; i++) {
                      bytes[i] = 0;
                    }
                    if (context.mounted) {
                      context.push('/edit_text_item/${item.id}', extra: {
                        'item': item,
                        'content': text,
                      });
                    }
                  },
                ),
              IconButton(
                tooltip: 'Share',
                icon: const Icon(Icons.share_rounded, color: AppColors.primaryNavy),
                onPressed: () => _shareItem(context, ref, item),
              ),
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline_rounded, color: AppColors.destructiveRed),
                onPressed: () => _confirmDeleteItem(context, ref, item),
              ),
            ];
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
          } else if (item.fileType == FileType.docx) {
            return _buildDocxContent(context, ref, item.encryptedFilePath);
          } else if (item.fileType == FileType.json) {
            return _buildJsonContent(context, ref, item, item.encryptedFilePath);
          } else if (item.fileType == FileType.image) {
            return _buildImageContent(context, ref, item.encryptedFilePath);
          } else if (item.fileType == FileType.pdf) {
            return _buildPdfContent(context, ref, item.encryptedFilePath);
          } else {
            return _buildUnsupportedContent(context, ref, item);
          }
        },
      ),
    );
  }

  Future<void> _showExtractedTextSheet(
    BuildContext context,
    WidgetRef ref,
    VaultItem item,
  ) async {
    final chunks =
        await ref.read(ocrRepositoryProvider).getChunksForItem(item.id);
    if (!context.mounted) return;

    final fullText = chunks.join('\n\n').trim();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardCanvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          minChildSize: 0.35,
          maxChildSize: 0.9,
          builder: (_, scrollCtrl) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppColors.borderLight,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      const Icon(
                        Icons.document_scanner_rounded,
                        color: AppColors.accentEmerald,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Extracted OCR Text',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primaryNavy,
                          ),
                        ),
                      ),
                      if (fullText.isNotEmpty)
                        TextButton.icon(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: fullText));
                            Navigator.pop(sheetCtx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content:
                                    Text('Extracted text copied to clipboard'),
                              ),
                            );
                          },
                          icon: const Icon(Icons.copy_rounded, size: 16),
                          label: const Text('Copy'),
                        ),
                      TextButton.icon(
                        onPressed: () {
                          ref.read(extractionQueueProvider).enqueue(item);
                          Navigator.pop(sheetCtx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Queued on-device OCR scan...'),
                            ),
                          );
                        },
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text('Re-scan'),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  Expanded(
                    child: fullText.isEmpty
                        ? Center(
                            child: Text(
                              item.extractionStatus ==
                                      ExtractionStatus.processing
                                  ? 'On-device OCR is currently processing this file...'
                                  : 'No readable text was detected yet.\nTap "Re-scan" above to run on-device OCR.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 14,
                                color: AppColors.textMuted,
                                height: 1.5,
                              ),
                            ),
                          )
                        : SingleChildScrollView(
                            controller: scrollCtrl,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceNeutral,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: SelectableText(
                                fullText,
                                style: const TextStyle(
                                  fontSize: 14,
                                  height: 1.55,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _shareItem(BuildContext context, WidgetRef ref, VaultItem item) async {
    Directory? tempDir;
    Uint8List? bytes;
    final authRepo = ref.read(authRepositoryProvider);
    try {
      bytes = await ref
          .read(vaultRepositoryProvider)
          .decryptToMemory(item.encryptedFilePath);
      tempDir = await Directory.systemTemp.createTemp('docsift_share_');
      final safeBase = item.displayName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final ext = item.originalExtension.trim();
      final fileName = (ext.isNotEmpty && !safeBase.toLowerCase().endsWith('.${ext.toLowerCase()}'))
          ? '$safeBase.$ext'
          : safeBase;
      final tempFile = File(p.join(tempDir.path, fileName));
      await tempFile.writeAsBytes(bytes, flush: true);

      authRepo.isBypassAutoLock = true;
      await Share.shareXFiles([XFile(tempFile.path)], subject: item.displayName);

      // Overwrite temporary plaintext file before deletion
      final rng = Random.secure();
      final wipe = Uint8List.fromList(
        List<int>.generate(min(bytes.length, 65536), (_) => rng.nextInt(256)),
      );
      await tempFile.writeAsBytes(wipe, flush: true);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Share failed: $e'),
            backgroundColor: AppColors.destructiveRed,
          ),
        );
      }
    } finally {
      authRepo.isBypassAutoLock = false;
      if (bytes != null) {
        for (int i = 0; i < bytes.length; i++) {
          bytes[i] = 0;
        }
      }
      if (tempDir != null) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  void _confirmDeleteItem(BuildContext context, WidgetRef ref, VaultItem item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Item'),
        content: Text('Permanently delete "${item.displayName}" from your vault?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(vaultServiceProvider).deleteItem(item);
              ref.invalidate(vaultItemsProvider);
              ref.invalidate(recentItemsProvider);
              ref.invalidate(categoryCountsProvider);
              if (item.categoryId == 'passwords') {
                ref
                    .read(autofillSyncServiceProvider)
                    .syncVaultAndImportCapturedLogins();
              }
              if (context.mounted) {
                context.pop();
              }
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.destructiveRed),
            ),
          ),
        ],
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

  List<Widget> _buildCustomFieldWidgets(
    BuildContext context,
    Map<String, dynamic> data,
  ) {
    final raw = data['customFields'];
    if (raw is! List || raw.isEmpty) return const <Widget>[];
    final widgets = <Widget>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final label = entry['label']?.toString() ?? '';
      final val = entry['value']?.toString() ?? '';
      final isSecret = entry['isSecret'] == true;
      if (label.isEmpty || val.isEmpty) continue;
      widgets.add(const SizedBox(height: 16));
      if (isSecret) {
        widgets.add(_MaskedValueField(label: label, value: val));
      } else {
        widgets.add(_buildCopyableField(context, label, val));
      }
    }
    return widgets;
  }

  Widget _buildPasswordUi(BuildContext context, Map<String, dynamic> data) {
    final subType = PasswordSubTemplate.fromKey(data['subType'] as String?);
    final title = (data['title'] ??
            data['website'] ??
            data['appName'] ??
            'Unknown Account')
        .toString();
    final username =
        (data['username'] ?? data['email'] ?? data['customerId'] ?? '')
            .toString();
    final password = (data['password'] ?? '').toString();
    final url = (data['url'] ?? '').toString();
    final notes = (data['notes'] ?? '').toString();
    final domains =
        (data['domains'] as List?)?.map((e) => e.toString()).toList() ??
            const <String>[];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.categoryPasswordsBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(subType.icon,
                        size: 14, color: AppColors.categoryPasswordsColor),
                    const SizedBox(width: 6),
                    Text(
                      subType.label,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.categoryPasswordsColor,
                      ),
                    ),
                  ],
                ),
              ),
              if (domains.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.verifiedGreenBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bolt_rounded,
                          size: 14, color: AppColors.verifiedGreen),
                      SizedBox(width: 4),
                      Text(
                        'Autofill Ready',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.verifiedGreen,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 18),
          _buildCopyableField(
            context,
            subType == PasswordSubTemplate.wifi
                ? 'Network SSID'
                : subType == PasswordSubTemplate.bankLogin
                    ? 'Bank Name'
                    : 'App / Service',
            title,
            sensitive: false,
          ),
          if (username.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildCopyableField(
              context,
              subType == PasswordSubTemplate.bankLogin
                  ? 'Customer / User ID'
                  : 'Username / Email',
              username,
            ),
          ],
          if (subType == PasswordSubTemplate.bankLogin) ...[
            if ((data['accountNumber'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 16),
              _MaskedValueField(
                label: 'Account Number',
                value: data['accountNumber'].toString(),
              ),
            ],
            if ((data['ifscCode'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildCopyableField(
                context,
                'IFSC / SWIFT Code',
                data['ifscCode'].toString(),
                sensitive: false,
              ),
            ],
          ],
          if (subType == PasswordSubTemplate.apiKey &&
              (data['apiKey'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildCopyableField(context, 'Key / Client ID', data['apiKey'].toString()),
          ],
          if (password.isNotEmpty) ...[
            const SizedBox(height: 16),
            _MaskedValueField(
              label: subType == PasswordSubTemplate.wifi
                  ? 'Wi-Fi Password'
                  : subType == PasswordSubTemplate.apiKey
                      ? 'Secret Token'
                      : 'Password',
              value: password,
            ),
          ],
          if (subType == PasswordSubTemplate.bankLogin) ...[
            if ((data['transactionPassword'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 16),
              _MaskedValueField(
                label: 'Transaction Password',
                value: data['transactionPassword'].toString(),
              ),
            ],
            if ((data['upiPin'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 16),
              _MaskedValueField(
                label: 'UPI / MPIN',
                value: data['upiPin'].toString(),
              ),
            ],
          ],
          if (subType == PasswordSubTemplate.wifi) ...[
            if ((data['securityType'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildCopyableField(
                context,
                'Security Protocol',
                data['securityType'].toString(),
                sensitive: false,
              ),
            ],
            if ((data['routerIp'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildCopyableField(
                context,
                'Router Admin IP',
                data['routerIp'].toString(),
                sensitive: false,
              ),
            ],
          ],
          if (subType == PasswordSubTemplate.apiKey) ...[
            if ((data['environment'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildCopyableField(
                context,
                'Environment',
                data['environment'].toString(),
                sensitive: false,
              ),
            ],
            if ((data['expiry'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildCopyableField(
                context,
                'Expiry Date',
                data['expiry'].toString(),
                sensitive: false,
              ),
            ],
          ],
          if (url.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildCopyableField(context, 'Website URL', url, sensitive: false),
          ],
          ..._buildCustomFieldWidgets(context, data),
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildCopyableField(context, 'Notes', notes),
          ],
        ],
      ),
    );
  }

  Widget _buildCardUi(BuildContext context, Map<String, dynamic> data) {
    final bankName = (data['bankName'] ?? 'Unknown Bank').toString();
    final cardType = (data['cardType'] ?? '').toString();
    final cardHolder = (data['cardHolder'] ?? 'Card Holder').toString();
    final cardNumber = (data['cardNumber'] ?? '**** **** **** ****').toString();
    final network = (data['network'] as String?) ??
        VaultTemplates.detectCardNetwork(cardNumber);
    final expiry = (data['expiry'] ?? 'MM/YY').toString();
    final cvv = (data['cvv'] ?? '***').toString();
    final pin = (data['pin'] ?? '').toString();
    final notes = (data['notes'] ?? '').toString();

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
                    Flexible(
                      child: Text(
                        cardType.isNotEmpty ? '$bankName · $cardType' : bankName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        network,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                GestureDetector(
                  onTap: () => SecureClipboard.copy(
                    context,
                    label: 'Card number',
                    value: cardNumber.replaceAll(' ', ''),
                  ),
                  child: Text(
                    _formatCardNumber(cardNumber),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      letterSpacing: 2.5,
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
                        const Text('CARDHOLDER',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 10)),
                        const SizedBox(height: 4),
                        Text(cardHolder.toUpperCase(),
                            style: const TextStyle(
                                color: Colors.white, fontSize: 14)),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('EXPIRES',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 10)),
                        const SizedBox(height: 4),
                        Text(expiry,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 14)),
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
              Expanded(child: _MaskedValueField(label: 'CVV', value: cvv)),
              if (pin.isNotEmpty) ...[
                const SizedBox(width: 16),
                Expanded(
                    child: _MaskedValueField(label: 'ATM / Card PIN', value: pin)),
              ],
            ],
          ),
          ..._buildCustomFieldWidgets(context, data),
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildCopyableField(context, 'Notes', notes),
          ],
        ],
      ),
    );
  }

  String _formatCardNumber(String number) {
    final clean = number.replaceAll(RegExp(r'\s+'), '');
    if (clean.length != 16) return number;
    return '${clean.substring(0, 4)} ${clean.substring(4, 8)} ${clean.substring(8, 12)} ${clean.substring(12, 16)}';
  }

  Widget _buildIdentityUi(BuildContext context, Map<String, dynamic> data) {
    final template = VaultTemplates.inferIdentityTemplate(data);
    final documentName =
        (data['documentName'] ?? template.displayName).toString();
    final notes = (data['notes'] ?? '').toString();

    final renderedKeys = <String>{
      'docType',
      'documentName',
      'notes',
      'customFields',
    };

    final fieldWidgets = <Widget>[];
    for (final spec in template.fields) {
      renderedKeys.add(spec.key);
      final val = (data[spec.key] ?? '').toString().trim();
      if (val.isEmpty) continue;
      fieldWidgets.add(const SizedBox(height: 16));
      final prettyLabel = spec.label
          .split(' ')
          .map((w) => w.isEmpty
              ? w
              : (w.length <= 3 && w == w.toUpperCase()
                  ? w
                  : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}'))
          .join(' ');
      if (spec.isSecret) {
        fieldWidgets.add(_MaskedValueField(label: prettyLabel, value: val));
      } else {
        fieldWidgets.add(_buildCopyableField(context, prettyLabel, val));
      }
    }

    // Also render any legacy keys that weren't in the inferred template
    for (final entry in data.entries) {
      if (renderedKeys.contains(entry.key)) continue;
      final val = entry.value?.toString().trim() ?? '';
      if (val.isEmpty) continue;
      fieldWidgets.add(const SizedBox(height: 16));
      fieldWidgets.add(
        _buildCopyableField(
          context,
          VaultTemplates.humanizeFieldKey(entry.key).toUpperCase(),
          val,
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.categoryIdentityBg,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  template.icon,
                  size: 28,
                  color: AppColors.categoryIdentityColor,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      documentName,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryNavy,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      template.displayName,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.categoryIdentityColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...fieldWidgets,
          ..._buildCustomFieldWidgets(context, data),
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildCopyableField(context, 'Notes', notes),
          ],
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
            child: SelectableText(
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
        child: SelectableText(
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

  Widget _buildCopyableField(
    BuildContext context,
    String label,
    String value, {
    bool sensitive = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 14, color: AppColors.textMuted, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () => SecureClipboard.copy(
            context,
            label: label,
            value: value,
            sensitive: sensitive,
          ),
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
        final text = utf8.decode(bytes, allowMalformed: true);
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
            child: SelectableText(
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

  Widget _buildDocxContent(BuildContext context, WidgetRef ref, String encryptedPath) {
    final bytesAsync = ref.watch(decryptedBytesProvider(encryptedPath));
    return bytesAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.accentEmerald),
      ),
      error: (e, _) => Center(
        child: Text('Error decrypting: $e', style: const TextStyle(color: AppColors.destructiveRed)),
      ),
      data: (bytes) {
        String extractedText = '';
        try {
          extractedText = DocxExtractor.extractFullText(bytes);
        } catch (e) {
          extractedText = 'Unable to parse DOCX document: $e';
        }
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
            child: SelectableText(
              extractedText.isNotEmpty
                  ? extractedText
                  : '(Empty DOCX document)',
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

  Widget _buildUnsupportedContent(BuildContext context, WidgetRef ref, VaultItem item) {
    final modDate = '${item.modifiedAt.day}/${item.modifiedAt.month}/${item.modifiedAt.year}';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: AppColors.cardCanvas,
            borderRadius: BorderRadius.circular(20),
            boxShadow: AppColors.cardShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.categoryMediaBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  item.fileType == FileType.video
                      ? Icons.videocam_rounded
                      : item.fileType == FileType.zip
                          ? Icons.folder_zip_rounded
                          : Icons.insert_drive_file_rounded,
                  size: 36,
                  color: AppColors.categoryMediaColor,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                item.displayName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryNavy,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${item.originalExtension.toUpperCase()} · ${item.sizeLabel} · Modified $modDate',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
              ),
              const SizedBox(height: 16),
              const Text(
                'This file is encrypted with AES-256-GCM inside your vault. Use Share below to export or open a temporary copy in an external app.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.5),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _shareItem(context, ref, item),
                  icon: const Icon(Icons.share_rounded, size: 18),
                  label: const Text('Share / Open Externally'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MaskedValueField extends StatefulWidget {
  final String label;
  final String value;
  const _MaskedValueField({required this.label, required this.value});

  @override
  State<_MaskedValueField> createState() => _MaskedValueFieldState();
}

class _MaskedValueFieldState extends State<_MaskedValueField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    final maskedLen = widget.value.isNotEmpty ? widget.value.length : 6;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(fontSize: 14, color: AppColors.textMuted, fontWeight: FontWeight.w500),
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
                    _obscured ? '•' * maskedLen : widget.value,
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
                onPressed: () => SecureClipboard.copy(
                  context,
                  label: widget.label,
                  value: widget.value,
                  sensitive: true,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
