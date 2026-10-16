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

/// Screen 5 — Immersive deep navy lock screen per design.md
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
  late AnimationController _shakeCtrl;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    super.dispose();
  }

  void _onKey(String key) {
    if (_pin.length >= 6 || _isLoading) return;
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
    if (_pin.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _handleUnlock() async {
    setState(() => _isLoading = true);
    final success = await ref.read(authRepositoryProvider).unlock(_pin);

    if (!mounted) return;

    if (success) {
      context.go(AppRoutes.dashboard);
      return;
    }

    HapticFeedback.vibrate();
    _shakeCtrl.forward(from: 0);
    _attempts++;

    final maxAttempts = ref.read(maxFailedAttemptsProvider);

    if (_attempts >= maxAttempts) {
      // Trigger factory reset
      await ref.read(vaultServiceProvider).factoryReset();
      if (!mounted) return;
      context.go(AppRoutes.splash);
      return;
    }

    setState(() {
      _hasError = true;
      _pin = '';
      _isLoading = false;
    });
  }

  Future<void> _handleBiometric() async {
    setState(() => _isLoading = true);
    final success = await ref
        .read(authRepositoryProvider)
        .unlockWithBiometrics('Please authenticate to unlock DocSift.');

    if (!mounted) return;

    if (success) {
      context.go(AppRoutes.dashboard);
      return;
    }

    setState(() {
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
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
            if (_hasError) ...[
              const SizedBox(height: 14),
              Consumer(
                builder: (context, ref, child) {
                  final maxAttempts = ref.watch(maxFailedAttemptsProvider);
                  return Text(
                    'Incorrect PIN — $_attempts/$maxAttempts attempts',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFFFF8A80),
                      fontWeight: FontWeight.w500,
                    ),
                  ).animate().fadeIn();
                }
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
                showBiometric: true,
                onBiometric: _handleBiometric,
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
