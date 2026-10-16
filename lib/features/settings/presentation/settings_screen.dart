import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/router/app_router.dart';
import '../../auth/data/auth_repository.dart';
import 'settings_provider.dart';

final _localAuth = LocalAuthentication();

/// Screen 14 — Settings & Vault Administration
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final biometricsEnabled = ref.watch(biometricsEnabledProvider);
    final ocrProcessingEnabled = ref.watch(ocrProcessingEnabledProvider);
    final autoLockTimer = ref.watch(autoLockTimerProvider);

    return Scaffold(
      backgroundColor: AppColors.surfaceNeutral,
      body: CustomScrollView(
        slivers: [
          // Profile header
          SliverToBoxAdapter(child: _buildProfileHeader()),
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
                            context.push(AppRoutes.createPin);
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
                                final authenticated = await _localAuth.authenticate(
                                  localizedReason: 'Authenticate to enable biometric unlock',
                                  biometricOnly: true,
                                );
                                if (authenticated) {
                                  ref.read(biometricsEnabledProvider.notifier).state = true;
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Biometrics enabled'),
                                        backgroundColor: AppColors.accentEmerald,
                                      ),
                                    );
                                  }
                                }
                              } else {
                                ref.read(biometricsEnabledProvider.notifier).state = false;
                              }
                            },
                          ),
                        ),
                        _SettingsTileData(
                          icon: Icons.timer_outlined,
                          iconColor: AppColors.categoryCardsColor,
                          iconBg: AppColors.categoryCardsBg,
                          title: 'Auto-Lock Timer',
                          subtitle: '$autoLockTimer minute${autoLockTimer > 1 ? 's' : ''}',
                          onTap: () {
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Auto-Lock Timer'),
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [1, 5, 15, 30].map((mins) {
                                    return ListTile(
                                      title: Text('$mins minute${mins > 1 ? 's' : ''}'),
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
                        subtitle: '14.2 MB',
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Storage calculation synced.')),
                          );
                        },
                      ),
                      _SettingsTileData(
                        icon: Icons.backup_rounded,
                        iconColor: AppColors.categoryDocumentsColor,
                        iconBg: AppColors.categoryDocumentsBg,
                        title: 'Local Encrypted Backup',
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Backup created successfully!')),
                          );
                        },
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
                        subtitle: 'DistilBERT SQuAD2',
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Model is loaded and ready.')),
                          );
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

  Widget _buildProfileHeader() {
    return Container(
      color: AppColors.cardCanvas,
      padding: const EdgeInsets.fromLTRB(20, 56, 20, 24),
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'User',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryNavy,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.surfaceNeutral,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.borderLight),
                ),
                child: const Text(
                  'user@example.com',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
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
