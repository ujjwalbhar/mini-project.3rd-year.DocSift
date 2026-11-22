import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/router/app_router.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../vault/domain/vault_service.dart';
import '../data/auth_repository.dart';
import 'widgets/pin_dot_row.dart';
import 'widgets/vault_numpad.dart';

/// PIN Setup & Authenticated PIN Change flow:
/// - Initial onboarding: `Create your PIN` -> `Confirm your PIN`
/// - Manage PIN (from Settings): `Verify Current PIN` -> `Create New PIN` -> `Confirm your PIN`
class PinSetupScreen extends ConsumerStatefulWidget {
  const PinSetupScreen({
    super.key,
    required this.isConfirm,
    this.isVerifyCurrent = false,
    this.firstPin,
    this.verifiedCurrentPin,
  });

  final bool isConfirm;
  final bool isVerifyCurrent;
  final String? firstPin;
  final String? verifiedCurrentPin;

  @override
  ConsumerState<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends ConsumerState<PinSetupScreen> {
  String _pin = '';
  bool _hasError = false;
  String _errorMsg = '';
  bool _isLoading = false;

  bool get _isChangeFlow =>
      widget.isVerifyCurrent || widget.verifiedCurrentPin != null;

  String get _title {
    if (widget.isVerifyCurrent) return 'Verify Current PIN';
    if (widget.isConfirm) return 'Confirm your PIN';
    return widget.verifiedCurrentPin != null
        ? 'Create New PIN'
        : 'Create your PIN';
  }

  String get _subtitle {
    if (widget.isVerifyCurrent) {
      return 'Enter your current 6-digit PIN to continue';
    }
    if (widget.isConfirm) {
      return 'Re-enter your 6-digit PIN';
    }
    return widget.verifiedCurrentPin != null
        ? 'Choose a new 6-digit PIN for your vault'
        : 'Choose a 6-digit PIN to secure your vault';
  }

  void _onKey(String key) {
    if (_pin.length >= 6 || _isLoading) return;
    HapticFeedback.lightImpact();
    setState(() {
      _pin += key;
      _hasError = false;
    });
    if (_pin.length == 6) {
      Future.delayed(const Duration(milliseconds: 150), _handleComplete);
    }
  }

  void _onBackspace() {
    if (_pin.isEmpty || _isLoading) return;
    HapticFeedback.selectionClick();
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _handleComplete() async {
    final authRepo = ref.read(authRepositoryProvider);

    // Step 0 (Manage PIN only): verify existing PIN before allowing a change
    if (widget.isVerifyCurrent) {
      setState(() => _isLoading = true);
      final lockout = await authRepo.getLockoutStatus();
      if (lockout.isCoolingDown) {
        setState(() {
          _isLoading = false;
          _hasError = true;
          _errorMsg =
              'Too many failed attempts — wait ${lockout.remainingCooldownSeconds}s.';
          _pin = '';
        });
        return;
      }

      final entered = _pin;
      final isValid = await authRepo.verifyCurrentPin(entered);
      if (!mounted) return;

      if (!isValid) {
        HapticFeedback.vibrate();
        final status = await authRepo.recordFailedAttempt();
        final maxAttempts = ref.read(maxFailedAttemptsProvider);
        if (status.failedAttempts >= maxAttempts) {
          await ref.read(vaultServiceProvider).factoryReset();
          await authRepo.destroyVault();
          if (!mounted) return;
          context.go(AppRoutes.splash);
          return;
        }
        setState(() {
          _isLoading = false;
          _hasError = true;
          _errorMsg = status.isCoolingDown
              ? 'Too many attempts — wait ${status.remainingCooldownSeconds}s (${status.failedAttempts}/$maxAttempts)'
              : 'Incorrect current PIN (${status.failedAttempts}/$maxAttempts)';
          _pin = '';
        });
        return;
      }

      await authRepo.resetFailedAttempts();
      setState(() {
        _isLoading = false;
        _pin = '';
      });
      if (mounted) {
        context.push(
          AppRoutes.createPin,
          extra: <String, dynamic>{'currentPin': entered},
        );
      }
      return;
    }

    // Step 1: Enter new PIN -> push Confirm screen
    if (!widget.isConfirm) {
      final entered = _pin;
      setState(() => _pin = '');
      if (mounted) {
        if (widget.verifiedCurrentPin != null) {
          context.push(
            AppRoutes.confirmPin,
            extra: <String, dynamic>{
              'firstPin': entered,
              'currentPin': widget.verifiedCurrentPin,
            },
          );
        } else {
          context.push(AppRoutes.confirmPin, extra: entered);
        }
      }
      return;
    }

    // Step 2: Confirm step — validate match
    if (_pin != widget.firstPin) {
      HapticFeedback.vibrate();
      setState(() {
        _hasError = true;
        _errorMsg = 'PINs do not match. Please try again.';
        _pin = '';
      });
      return;
    }

    setState(() => _isLoading = true);
    try {
      if (widget.verifiedCurrentPin != null) {
        final changed =
            await authRepo.changePin(widget.verifiedCurrentPin!, _pin);
        if (!changed) {
          setState(() {
            _hasError = true;
            _errorMsg = 'Current PIN verification failed. Please try again.';
            _isLoading = false;
            _pin = '';
          });
          return;
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PIN updated successfully'),
            backgroundColor: AppColors.accentEmerald,
          ),
        );
        context.go(AppRoutes.settings);
      } else {
        await authRepo.setupPin(_pin);
        if (!mounted) return;
        context.go(AppRoutes.dashboard);
      }
    } catch (_) {
      setState(() {
        _hasError = true;
        _errorMsg = 'Something went wrong. Please try again.';
        _isLoading = false;
        _pin = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceNeutral,
      body: SafeArea(
        child: Column(
          children: [
            // Back button row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
                    color: AppColors.textPrimary,
                    onPressed: () {
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go(
                          _isChangeFlow
                              ? AppRoutes.settings
                              : AppRoutes.onboarding,
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Step indicator (3 dots for Manage PIN, 2 dots for initial setup)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: _isChangeFlow
                  ? [
                      const _StepDot(active: true),
                      const SizedBox(width: 8),
                      _StepDot(active: !widget.isVerifyCurrent),
                      const SizedBox(width: 8),
                      _StepDot(active: widget.isConfirm),
                    ]
                  : [
                      const _StepDot(active: true),
                      const SizedBox(width: 8),
                      _StepDot(active: widget.isConfirm),
                    ],
            ),
            const SizedBox(height: 32),
            // Title
            Text(
              _title,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryNavy,
                letterSpacing: -0.4,
              ),
            ).animate().fadeIn(duration: 400.ms),
            const SizedBox(height: 10),
            Text(
              _subtitle,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textMuted,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ).animate().fadeIn(delay: 100.ms, duration: 400.ms),
            const SizedBox(height: 48),
            // 6-dot PIN row
            PinDotRow(filled: _pin.length, hasError: _hasError),
            if (_hasError) ...[
              const SizedBox(height: 14),
              Text(
                _errorMsg,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.destructiveRed,
                  fontWeight: FontWeight.w500,
                ),
              ).animate().shakeX(amount: 4),
            ],
            const Spacer(),
            // Numpad
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
                isDarkMode: false,
              ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: active ? 24 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: active
            ? AppColors.accentEmerald
            : AppColors.accentEmerald.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
