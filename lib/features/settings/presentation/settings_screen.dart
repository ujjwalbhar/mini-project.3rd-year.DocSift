import 'dart:io';
import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/router/app_router.dart';
import '../../ai/data/model_manager.dart';
import '../../auth/data/auth_repository.dart';
import '../../autofill/autofill_sync_service.dart';
import '../../ocr/domain/extraction_queue.dart';
import '../../vault/domain/vault_service.dart';
import '../../vault/presentation/dashboard_screen.dart';
import 'settings_provider.dart';

final _localAuth = LocalAuthentication();
final _onnxRefreshTickProvider = StateProvider<int>((ref) => 0);

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
}

/// Screen 14 — Settings & Vault Administration
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final biometricsEnabled = ref.watch(biometricsEnabledProvider);
    final ocrProcessingEnabled = ref.watch(ocrProcessingEnabledProvider);
    final autoLockTimer = ref.watch(autoLockTimerProvider);
    final userName = ref.watch(vaultUserNameProvider);
    final storageBytesAsync = ref.watch(vaultStorageBytesProvider);
    ref.watch(_onnxRefreshTickProvider);
    final modelManager = ref.read(modelManagerProvider);
    final hasEmbedding = modelManager.embeddingSession != null;
    final hasQa = modelManager.qaSession != null;
    final String onnxSubtitle;
    if (hasEmbedding && hasQa) {
      onnxSubtitle = 'MiniLM + DistilBERT SQuAD2 (Active in RAM)';
    } else if (hasEmbedding || hasQa) {
      onnxSubtitle =
          '${hasEmbedding ? "MiniLM Active" : "MiniLM On-Demand"} • ${hasQa ? "DistilBERT Active" : "DistilBERT On-Demand"}';
    } else if (modelManager.isOrtUnavailable) {
      onnxSubtitle = 'Deterministic Offline RAG (Fallback Active)';
    } else {
      onnxSubtitle = 'MiniLM + DistilBERT SQuAD2 (Lazy On-Demand)';
    }

    return Scaffold(
      backgroundColor: AppColors.surfaceNeutral,
      body: CustomScrollView(
        slivers: [
          // Profile header
          SliverToBoxAdapter(
              child: _buildProfileHeader(context, ref, userName)),
          // Settings groups
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Consumer(builder: (context, ref, _) {
                    final maxAttempts = ref.watch(maxFailedAttemptsProvider);
                    return _SettingsGroup(
                      title: 'Security',
                      items: [
                        _SettingsTileData(
                          icon: Icons.pin_outlined,
                          iconColor: AppColors.categoryPasswordsColor,
                          iconBg: AppColors.categoryPasswordsBg,
                          title: 'Manage PIN',
                          onTap: () {
                            context.push(AppRoutes.changePin);
                          },
                        ),
                        _SettingsTileData(
                          icon: Icons.fingerprint_rounded,
                          iconColor: AppColors.accentEmerald,
                          iconBg: AppColors.categoryIdentityBg,
                          title: 'Biometrics',
                          trailing: Switch(
                            value: biometricsEnabled,
                            activeThumbColor: AppColors.accentEmerald,
                            onChanged: (val) async {
                              final authRepo = ref.read(authRepositoryProvider);
                              if (val) {
                                // Check if device supports biometrics
                                final canCheck = await _localAuth.canCheckBiometrics;
                                final isDeviceSupported = await _localAuth.isDeviceSupported();
                                if (!canCheck || !isDeviceSupported) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Biometrics not available on this device')),
                                    );
                                  }
                                  return;
                                }
                                // Prompt biometric auth to confirm enabling
                                authRepo.isBypassAutoLock = true;
                                bool authenticated = false;
                                try {
                                  authenticated = await _localAuth.authenticate(
                                    localizedReason: 'Authenticate to enable biometric unlock',
                                    biometricOnly: true,
                                  );
                                } finally {
                                  authRepo.isBypassAutoLock = false;
                                }
                                if (authenticated) {
                                  final stored =
                                      await authRepo.setBiometricUnlockEnabled(true);
                                  if (stored) {
                                    await ref
                                        .read(biometricsEnabledProvider.notifier)
                                        .setEnabled(true);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Biometrics enabled'),
                                          backgroundColor: AppColors.accentEmerald,
                                        ),
                                      );
                                    }
                                  }
                                }
                              } else {
                                await authRepo.setBiometricUnlockEnabled(false);
                                await ref
                                    .read(biometricsEnabledProvider.notifier)
                                    .setEnabled(false);
                              }
                            },
                          ),
                        ),
                        if (ref
                            .read(autofillSyncServiceProvider)
                            .isSupportedPlatform)
                          _SettingsTileData(
                            icon: Icons.bolt_rounded,
                            iconColor: AppColors.categoryDocumentsColor,
                            iconBg: AppColors.categoryDocumentsBg,
                            title: 'System Autofill & Auto-Save',
                            subtitle: ref
                                .watch(autofillEnabledStatusProvider)
                                .when(
                                  data: (enabled) => enabled
                                      ? 'Active · Fills apps & captures new logins'
                                      : 'Tap to enable DocSift Autofill on phone',
                                  loading: () => 'Checking OS autofill status...',
                                  error: (_, __) => 'Tap to configure Autofill',
                                ),
                            onTap: () async {
                              final sync = ref.read(autofillSyncServiceProvider);
                              final imported = await sync
                                  .syncVaultAndImportCapturedLogins();
                              if (imported > 0) {
                                ref.invalidate(vaultItemsProvider);
                                ref.invalidate(recentItemsProvider);
                                ref.invalidate(categoryCountsProvider);
                              }
                              final currentlyEnabled =
                                  await sync.isSystemAutofillEnabled();
                              if (!currentlyEnabled) {
                                await sync.requestEnableSystemAutofill();
                                ref.invalidate(autofillEnabledStatusProvider);
                              } else if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      imported > 0
                                          ? 'DocSift Autofill synced ($imported new login${imported == 1 ? '' : 's'} imported)!'
                                          : 'DocSift Autofill is active & synced with your vault.',
                                    ),
                                    backgroundColor: AppColors.accentEmerald,
                                  ),
                                );
                              }
                            },
                          ),
                        _SettingsTileData(
                          icon: Icons.timer_outlined,
                          iconColor: AppColors.categoryCardsColor,
                          iconBg: AppColors.categoryCardsBg,
                          title: 'Auto-Lock Timer',
                          subtitle: autoLockTimer == 0
                              ? 'Immediately'
                              : '$autoLockTimer minute${autoLockTimer > 1 ? 's' : ''}',
                          onTap: () {
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Auto-Lock Timer'),
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [0, 1, 5, 15, 30].map((mins) {
                                    return ListTile(
                                      title: Text(mins == 0
                                          ? 'Immediately'
                                          : '$mins minute${mins > 1 ? 's' : ''}'),
                                      onTap: () {
                                        ref.read(autoLockTimerProvider.notifier).state = mins;
                                        Navigator.pop(ctx);
                                      },
                                    );
                                  }).toList(),
                                ),
                              ),
                            );
                          },
                        ),
                        _SettingsTileData(
                          icon: Icons.shield_rounded,
                          iconColor: AppColors.destructiveRed,
                          iconBg: AppColors.destructiveRed.withValues(alpha: 0.1),
                          title: 'Factory Reset Threshold',
                          subtitle: '$maxAttempts Failed Attempts',
                          onTap: () {
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Failed Attempts Limit', style: TextStyle(color: AppColors.destructiveRed)),
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text('If someone enters an incorrect PIN this many times, ALL your data will be permanently wiped.'),
                                    const SizedBox(height: 16),
                                    ...[3, 5, 10].map((attempts) {
                                      return ListTile(
                                        title: Text('$attempts attempts'),
                                        onTap: () {
                                          ref.read(maxFailedAttemptsProvider.notifier).setAttempts(attempts);
                                          Navigator.pop(ctx);
                                        },
                                      );
                                    }),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    );
                  }),
                  const SizedBox(height: 16),
                  _SettingsGroup(
                    title: 'Vault Settings',
                    items: [
                      _SettingsTileData(
                        icon: Icons.storage_rounded,
                        iconColor: AppColors.categoryNotesColor,
                        iconBg: AppColors.categoryNotesBg,
                        title: 'Storage Used',
                        subtitle: storageBytesAsync.when(
                          data: (bytes) => _formatBytes(bytes),
                          loading: () => 'Calculating...',
                          error: (_, __) => '0 B',
                        ),
                        onTap: () {
                          ref.invalidate(vaultStorageBytesProvider);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Storage calculation synced.')),
                          );
                        },
                      ),
                      _SettingsTileData(
                        icon: Icons.backup_rounded,
                        iconColor: AppColors.categoryDocumentsColor,
                        iconBg: AppColors.categoryDocumentsBg,
                        title: 'Export Encrypted Backup',
                        subtitle: 'Create & share password-protected .docsift file',
                        onTap: () => _handleExportBackup(context, ref),
                      ),
                      _SettingsTileData(
                        icon: Icons.restore_page_rounded,
                        iconColor: AppColors.accentEmerald,
                        iconBg: AppColors.categoryIdentityBg,
                        title: 'Restore Encrypted Backup',
                        subtitle: 'Import a .docsift backup archive',
                        onTap: () => _handleRestoreBackup(
                          context,
                          ref,
                          biometricsEnabled,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _SettingsGroup(
                    title: 'AI Settings',
                    items: [
                      _SettingsTileData(
                        icon: Icons.psychology_rounded,
                        iconColor: AppColors.categoryMediaColor,
                        iconBg: AppColors.categoryMediaBg,
                        title: 'ONNX Model',
                        subtitle: onnxSubtitle,
                        onTap: () async {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                  'Warming up WordPiece tokenizer, MiniLM & DistilBERT SQuAD2...'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                          final ok = await modelManager.warmUpAll();
                          ref.read(_onnxRefreshTickProvider.notifier).state++;
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(ok
                                    ? 'MiniLM + DistilBERT SQuAD2 ONNX sessions verified & active.'
                                    : 'ONNX native runtime unavailable; using deterministic offline fallback.'),
                                backgroundColor: ok ? AppColors.accentEmerald : null,
                              ),
                            );
                          }
                        },
                      ),
                      _SettingsTileData(
                        icon: Icons.document_scanner_rounded,
                        iconColor: AppColors.categoryPasswordsColor,
                        iconBg: AppColors.categoryPasswordsBg,
                        title: 'OCR Processing',
                        trailing: Switch(
                          value: ocrProcessingEnabled,
                          activeThumbColor: AppColors.accentEmerald,
                          onChanged: (val) {
                            ref.read(ocrProcessingEnabledProvider.notifier).state = val;
                            if (val) {
                              ref.read(extractionQueueProvider).resumePending();
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _SettingsGroup(
                    title: 'About DocSift',
                    items: [
                      _SettingsTileData(
                        icon: Icons.info_outline_rounded,
                        iconColor: AppColors.textMuted,
                        iconBg: AppColors.surfaceNeutral,
                        title: 'Version',
                        subtitle: 'v1.0.0',
                      ),
                      _SettingsTileData(
                        icon: Icons.shield_outlined,
                        iconColor: AppColors.accentEmerald,
                        iconBg: AppColors.categoryIdentityBg,
                        title: 'Zero-Network Vault',
                        subtitle: 'No data leaves your device',
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Lock vault CTA
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        ref.read(modelManagerProvider).releaseQaSession();
                        ref.read(authRepositoryProvider).lock();
                        context.go(AppRoutes.lock);
                      },
                      icon: const Icon(Icons.lock_rounded, size: 18),
                      label: const Text('Log Out / Lock Vault'),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileHeader(
      BuildContext context, WidgetRef ref, String userName) {
    return Container(
      color: AppColors.cardCanvas,
      padding: const EdgeInsets.fromLTRB(20, 56, 20, 24),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          final ctrl = TextEditingController(text: userName);
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Edit Vault Name'),
              content: TextField(
                controller: ctrl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Enter your display name',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    final next = ctrl.text.trim();
                    if (next.isNotEmpty) {
                      ref.read(vaultUserNameProvider.notifier).state = next;
                    }
                    Navigator.pop(ctx);
                  },
                  child: const Text('Save',
                      style: TextStyle(color: AppColors.accentEmerald)),
                ),
              ],
            ),
          );
        },
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: AppColors.categoryPasswordsBg,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.person_rounded,
                color: AppColors.categoryPasswordsColor,
                size: 32,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          userName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primaryNavy,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.edit_outlined,
                          size: 15, color: AppColors.textMuted),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.verifiedGreenBg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Local Zero-Trust Vault',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.verifiedGreen,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleExportBackup(BuildContext context, WidgetRef ref) async {
    final passCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    String? errorText;
    bool obscure = true;

    final passphrase = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Export Encrypted Backup'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Choose a strong passphrase to encrypt your portable .docsift backup with PBKDF2-HMAC-SHA256 & AES-256-GCM. You will need this passphrase to restore.',
                  style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passCtrl,
                  obscureText: obscure,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Backup Passphrase (min 6 chars)',
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscure ? Icons.visibility_off : Icons.visibility,
                        size: 18,
                      ),
                      onPressed: () => setDialogState(() => obscure = !obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmCtrl,
                  obscureText: obscure,
                  decoration: const InputDecoration(
                    labelText: 'Confirm Passphrase',
                  ),
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    errorText!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.destructiveRed,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final p1 = passCtrl.text;
                final p2 = confirmCtrl.text;
                if (p1.trim().length < 6) {
                  setDialogState(() {
                    errorText = 'Passphrase must be at least 6 characters.';
                  });
                  return;
                }
                if (p1 != p2) {
                  setDialogState(() {
                    errorText = 'Passphrases do not match.';
                  });
                  return;
                }
                Navigator.pop(ctx, p1);
              },
              child: const Text('Encrypt & Export'),
            ),
          ],
        ),
      ),
    );

    passCtrl.dispose();
    confirmCtrl.dispose();
    if (passphrase == null || !context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            SizedBox(width: 16),
            Expanded(child: Text('Sealing AES-256-GCM backup archive...')),
          ],
        ),
      ),
    );

    File? archiveFile;
    Object? exportError;
    try {
      archiveFile =
          await ref.read(vaultServiceProvider).exportEncryptedBackup(passphrase);
    } catch (e) {
      exportError = e;
    }

    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }

    if (exportError != null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Backup failed: $exportError'),
            backgroundColor: AppColors.destructiveRed,
          ),
        );
      }
      return;
    }

    ref.invalidate(vaultStorageBytesProvider);
    final authRepo = ref.read(authRepositoryProvider);
    authRepo.isBypassAutoLock = true;
    try {
      await Share.shareXFiles(
        [XFile(archiveFile!.path)],
        subject: 'DocSift Encrypted Vault Backup',
      );
    } catch (_) {
      // Share sheet dismissed or unavailable on desktop test runner
    } finally {
      authRepo.isBypassAutoLock = false;
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Encrypted backup ready (${p.basename(archiveFile!.path)})',
          ),
          backgroundColor: AppColors.accentEmerald,
        ),
      );
    }
  }

  Future<void> _handleRestoreBackup(
    BuildContext context,
    WidgetRef ref,
    bool biometricsEnabled,
  ) async {
    final authRepo = ref.read(authRepositoryProvider);
    authRepo.isBypassAutoLock = true;
    fp.FilePickerResult? picked;
    try {
      picked = await fp.FilePicker.platform.pickFiles(type: fp.FileType.any);
    } finally {
      authRepo.isBypassAutoLock = false;
    }

    final filePath = picked?.files.single.path;
    if (filePath == null || !context.mounted) return;

    final passCtrl = TextEditingController();
    final pinCtrl = TextEditingController();
    String? errorText;
    bool obscure = true;

    final creds = await showDialog<(String, String)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Restore Encrypted Backup'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Selected: ${p.basename(filePath)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryNavy,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Restoring will replace current vault items with the verified contents of this backup archive.',
                  style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passCtrl,
                  obscureText: obscure,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Backup Passphrase',
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscure ? Icons.visibility_off : Icons.visibility,
                        size: 18,
                      ),
                      onPressed: () => setDialogState(() => obscure = !obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pinCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(
                    labelText: 'Current 6-Digit Vault PIN',
                    counterText: '',
                  ),
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    errorText!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.destructiveRed,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final pass = passCtrl.text;
                final pin = pinCtrl.text.trim();
                if (pass.isEmpty) {
                  setDialogState(() {
                    errorText = 'Enter the backup passphrase.';
                  });
                  return;
                }
                if (pin.length != 6) {
                  setDialogState(() {
                    errorText = 'Enter your 6-digit Vault PIN.';
                  });
                  return;
                }
                Navigator.pop(ctx, (pass, pin));
              },
              child: const Text('Verify & Restore'),
            ),
          ],
        ),
      ),
    );

    passCtrl.dispose();
    pinCtrl.dispose();
    if (creds == null || !context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            SizedBox(width: 16),
            Expanded(child: Text('Authenticating & restoring vault...')),
          ],
        ),
      ),
    );

    int? restoredCount;
    Object? restoreError;
    try {
      restoredCount =
          await ref.read(vaultServiceProvider).restoreEncryptedBackup(
                archiveFile: File(filePath),
                passphrase: creds.$1,
                currentPin: creds.$2,
                biometricsEnabled: biometricsEnabled,
              );
    } catch (e) {
      restoreError = e;
    }

    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }

    if (restoreError != null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Restore failed: $restoreError'),
            backgroundColor: AppColors.destructiveRed,
          ),
        );
      }
      return;
    }

    // Refresh all reactive vault providers & resume any pending OCR extractions
    ref.invalidate(vaultItemsProvider);
    ref.invalidate(recentItemsProvider);
    ref.invalidate(categoryCountsProvider);
    ref.invalidate(vaultStorageBytesProvider);
    ref.read(extractionQueueProvider).resumePending();
    ref.read(autofillSyncServiceProvider).syncVaultAndImportCapturedLogins();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Restored $restoredCount vault item${restoredCount == 1 ? '' : 's'} successfully!',
          ),
          backgroundColor: AppColors.accentEmerald,
        ),
      );
    }
  }
}

class _SettingsTileData {
  const _SettingsTileData({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.items});

  final String title;
  final List<_SettingsTileData> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: AppColors.textMuted,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.cardCanvas,
            borderRadius: BorderRadius.circular(16),
            boxShadow: AppColors.cardShadow,
          ),
          child: Column(
            children: items.asMap().entries.map((entry) {
              final i = entry.key;
              final item = entry.value;
              return Column(
                children: [
                  InkWell(
                    onTap: item.onTap,
                    borderRadius: BorderRadius.vertical(
                      top: i == 0 ? const Radius.circular(16) : Radius.zero,
                      bottom: i == items.length - 1
                          ? const Radius.circular(16)
                          : Radius.zero,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 13),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: item.iconBg,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(item.icon,
                                color: item.iconColor, size: 20),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                if (item.subtitle != null)
                                  Text(
                                    item.subtitle!,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          item.trailing ??
                              (item.onTap != null
                                  ? const Icon(Icons.chevron_right_rounded,
                                      color: AppColors.textMuted, size: 20)
                                  : const SizedBox.shrink()),
                        ],
                      ),
                    ),
                  ),
                  if (i < items.length - 1)
                    const Divider(height: 1, indent: 68),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
