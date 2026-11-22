import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/router/app_router.dart';
import '../../autofill/autofill_sync_service.dart';
import '../../ocr/domain/extraction_queue.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../vault/domain/vault_service.dart';
import '../../vault/presentation/dashboard_screen.dart';
import '../data/auth_repository.dart';
import 'widgets/pin_dot_row.dart';
import 'widgets/vault_numpad.dart';

/// Screen 5 — Immersive deep navy lock screen
class PinLockScreen extends ConsumerStatefulWidget {
  const PinLockScreen({super.key});

  @override
  ConsumerState<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends ConsumerState<PinLockScreen>
    with SingleTickerProviderStateMixin {
  String _pin = '';
  bool _isLoading = false;
  bool _hasError = false;
  int _attempts = 0;
  int _cooldownSeconds = 0;
  Timer? _cooldownTimer;
  late AnimationController _shakeCtrl;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _restoreLockoutAndPromptBiometric();
  }

  Future<void> _restoreLockoutAndPromptBiometric() async {
    final authRepo = ref.read(authRepositoryProvider);
    final lockout = await authRepo.getLockoutStatus();
    if (!mounted) return;

    if (lockout.failedAttempts > 0 || lockout.isCoolingDown) {
      setState(() {
        _attempts = lockout.failedAttempts;
        _hasError = lockout.failedAttempts > 0;
      });
      if (lockout.isCoolingDown) {
        _startCooldown(lockout.remainingCooldownSeconds);
        return;
      }
    }

    // Read persisted biometric preference directly to avoid cold-start async race
    final prefs = await SharedPreferences.getInstance();
    final bioEnabled = prefs.getBool('docsift_biometrics_enabled') ?? false;
    if (mounted && bioEnabled) {
      _handleBiometric();
    }
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _shakeCtrl.dispose();
    super.dispose();
  }

  void _startCooldown(int seconds) {
    _cooldownTimer?.cancel();
    setState(() => _cooldownSeconds = seconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_cooldownSeconds <= 1) {
        timer.cancel();
        setState(() => _cooldownSeconds = 0);
      } else {
        setState(() => _cooldownSeconds--);
      }
    });
  }

  void _onKey(String key) {
    if (_pin.length >= 6 || _isLoading || _cooldownSeconds > 0) return;
    HapticFeedback.lightImpact();
    setState(() {
      _pin += key;
      _hasError = false;
    });
    if (_pin.length == 6) {
      Future.delayed(const Duration(milliseconds: 150), _handleUnlock);
    }
  }

  void _onBackspace() {
    if (_pin.isEmpty || _isLoading || _cooldownSeconds > 0) return;
    HapticFeedback.selectionClick();
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  void _onUnlockSucceeded() {
    if (ref.read(ocrProcessingEnabledProvider)) {
      ref.read(extractionQueueProvider).resumePending();
    }
    // Import any credentials captured via OS Autofill & sync vault index
    ref
        .read(autofillSyncServiceProvider)
        .syncVaultAndImportCapturedLogins()
        .then((importedCount) {
      if (importedCount > 0) {
        ref.invalidate(vaultItemsProvider);
        ref.invalidate(recentItemsProvider);
        ref.invalidate(categoryCountsProvider);
      }
    });
    context.go(AppRoutes.dashboard);
  }

  Future<void> _handleUnlock() async {
    if (_cooldownSeconds > 0) return;
    setState(() => _isLoading = true);
    final authRepo = ref.read(authRepositoryProvider);
    final success = await authRepo.unlock(_pin);

    if (!mounted) return;

    if (success) {
      _onUnlockSucceeded();
      return;
    }

    HapticFeedback.vibrate();
    _shakeCtrl.forward(from: 0);

    final fallbackMax = ref.read(maxFailedAttemptsProvider);
    final status = await authRepo.recordFailedAttempt();
    final prefs = await SharedPreferences.getInstance();
    final int maxAttempts =
        prefs.getInt('docsift_max_failed_attempts') ?? fallbackMax;

    if (status.failedAttempts >= maxAttempts) {
      // Trigger zero-trust factory reset
      await ref.read(vaultServiceProvider).factoryReset();
      if (!mounted) return;
      context.go(AppRoutes.splash);
      return;
    }

    if (!mounted) return;
    setState(() {
      _attempts = status.failedAttempts;
      _hasError = true;
      _pin = '';
      _isLoading = false;
    });

    if (status.isCoolingDown) {
      _startCooldown(status.remainingCooldownSeconds);
    }
  }

  Future<void> _handleBiometric() async {
    if (_cooldownSeconds > 0) return;
    setState(() => _isLoading = true);
    final success = await ref
        .read(authRepositoryProvider)
        .unlockWithBiometrics('Please authenticate to unlock DocSift.');

    if (!mounted) return;

    if (success) {
      _onUnlockSucceeded();
      return;
    }

    setState(() {
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final biometricsEnabled = ref.watch(biometricsEnabledProvider);

    return Scaffold(
      backgroundColor: AppColors.lockScreenBg, // #2B3C5A
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 60),
            // Shield icon + status
            _buildStatusBadge().animate().fadeIn(duration: 500.ms).scale(
                  begin: const Offset(0.85, 0.85),
                  duration: 500.ms,
                  curve: Curves.easeOut,
                ),
            const SizedBox(height: 52),
            // PIN dots
            AnimatedBuilder(
              animation: _shakeCtrl,
              builder: (context, child) {
                final offset = _hasError
                    ? 8 * (0.5 - _shakeCtrl.value).abs() * 2
                    : 0.0;
                return Transform.translate(
                  offset: Offset(
                    _shakeCtrl.isAnimating
                        ? offset *
                            ((_shakeCtrl.value * 10).round().isEven ? 1 : -1)
                        : 0,
                    0,
                  ),
                  child: child,
                );
              },
              child: PinDotRow(filled: _pin.length, hasError: _hasError),
            ),
            if (_hasError || _cooldownSeconds > 0) ...[
              const SizedBox(height: 14),
              Consumer(
                builder: (context, ref, child) {
                  final maxAttempts = ref.watch(maxFailedAttemptsProvider);
                  final msg = _cooldownSeconds > 0
                      ? 'Too many attempts — wait ${_cooldownSeconds}s ($_attempts/$maxAttempts)'
                      : 'Incorrect PIN — $_attempts/$maxAttempts attempts';
                  return Text(
                    msg,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFFFF8A80),
                      fontWeight: FontWeight.w500,
                    ),
                  ).animate().fadeIn();
                },
              ),
            ],
            const Spacer(),
            // Keypad
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: CircularProgressIndicator(
                  color: AppColors.accentEmerald,
                  strokeWidth: 2.5,
                ),
              )
            else
              VaultNumpad(
                onKey: _onKey,
                onBackspace: _onBackspace,
                isDarkMode: true,
                showBiometric: biometricsEnabled && _cooldownSeconds == 0,
                onBiometric: (biometricsEnabled && _cooldownSeconds == 0)
                    ? _handleBiometric
                    : null,
              ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge() {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.15),
              width: 1.5,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22.5),
            child: Image.asset(
              'assets/logo.jpg',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.shield_rounded,
                color: AppColors.accentEmerald,
                size: 40,
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'DocSift Locked',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.white,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Enter your PIN to continue',
          style: TextStyle(
            fontSize: 14,
            color: Color(0xFFB0BEC5),
          ),
        ),
      ],
    );
  }
}
