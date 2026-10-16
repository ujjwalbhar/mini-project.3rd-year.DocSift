import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/router/app_router.dart';
import '../data/auth_repository.dart';
import 'widgets/pin_dot_row.dart';
import 'widgets/vault_numpad.dart';

/// Screen 3 (isConfirm=false) and Screen 4 (isConfirm=true) — PIN Setup
class PinSetupScreen extends ConsumerStatefulWidget {
  const PinSetupScreen({
    super.key,
    required this.isConfirm,
    this.firstPin,
  });

  final bool isConfirm;
  final String? firstPin;

  @override
  ConsumerState<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends ConsumerState<PinSetupScreen> {
  String _pin = '';
  bool _hasError = false;
  String _errorMsg = '';
  bool _isLoading = false;

  String get _title => widget.isConfirm ? 'Confirm your PIN' : 'Create your PIN';
  String get _subtitle => widget.isConfirm
      ? 'Re-enter your 6-digit PIN'
      : 'Choose a 6-digit PIN to secure your vault';

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
    if (_pin.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _handleComplete() async {
    if (!widget.isConfirm) {
      // Move to confirm screen, pass the PIN as extra
      if (mounted) context.go(AppRoutes.confirmPin, extra: _pin);
      return;
    }

    // Confirm step — validate
    if (_pin != widget.firstPin) {
      HapticFeedback.vibrate();
      setState(() {
        _hasError = true;
        _errorMsg = 'PINs do not match. Please try again.';
        _pin = '';
      });
      return;
    }

    // Save
    setState(() => _isLoading = true);
    try {
      await ref.read(authRepositoryProvider).setupPin(_pin);
      if (mounted) context.go(AppRoutes.dashboard);
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
                    onPressed: () => context.pop(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Step indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _StepDot(active: true),
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
