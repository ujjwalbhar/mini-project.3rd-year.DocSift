import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/router/app_router.dart';

/// Screen 2 — Onboarding Walkthrough
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceNeutral,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 48),
              // Vault illustration
              _VaultIllustration()
                  .animate()
                  .fadeIn(duration: 600.ms)
                  .slideY(begin: -0.1, end: 0, duration: 600.ms, curve: Curves.easeOut),
              const SizedBox(height: 48),
              // Welcome copy
              const Text(
                'Welcome to DocSift',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryNavy,
                  letterSpacing: -0.5,
                ),
                textAlign: TextAlign.center,
              ).animate().fadeIn(delay: 200.ms, duration: 500.ms),
              const SizedBox(height: 16),
              const Text(
                'Your safe place to store your passwords, documents, IDs, cards and more.',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textMuted,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ).animate().fadeIn(delay: 350.ms, duration: 500.ms),
              const SizedBox(height: 16),
              // Feature pills row
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: const [
                  _FeaturePill(icon: Icons.lock_rounded, label: 'AES-256 Encrypted'),
                  _FeaturePill(icon: Icons.wifi_off_rounded, label: '100% Offline'),
                  _FeaturePill(icon: Icons.psychology_rounded, label: 'On-Device AI'),
                ],
              ).animate().fadeIn(delay: 500.ms, duration: 500.ms),
              const Spacer(),
              // Next button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => context.go(AppRoutes.createPin),
                  child: const Text('Get Started'),
                ),
              ).animate().fadeIn(delay: 700.ms, duration: 400.ms).slideY(
                    begin: 0.3,
                    end: 0,
                    delay: 700.ms,
                    duration: 400.ms,
                    curve: Curves.easeOut,
                  ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => context.go(AppRoutes.createPin),
                child: const Text('Skip'),
              ).animate().fadeIn(delay: 800.ms),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _VaultIllustration extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 280,
      decoration: BoxDecoration(
        color: AppColors.cardCanvas,
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppColors.cardShadow,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background rings
          Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.accentEmeraldLight,
            ),
          ),
          Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.accentEmerald.withValues(alpha: 0.15),
            ),
          ),
          // Vault door icon
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              color: AppColors.primaryNavy,
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(
              Icons.lock_rounded,
              color: Colors.white,
              size: 48,
            ),
          ),
          // Users — left
          Positioned(
            left: 24,
            bottom: 40,
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.categoryPasswordsBg,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.cardCanvas, width: 3),
              ),
              child: const Icon(Icons.person_rounded,
                  color: AppColors.categoryPasswordsColor, size: 28),
            ),
          ),
          // Users — right
          Positioned(
            right: 24,
            bottom: 40,
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.accentEmeraldLight,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.cardCanvas, width: 3),
              ),
              child: const Icon(Icons.person_rounded,
                  color: AppColors.accentEmerald, size: 28),
            ),
          ),
          // Verified badge top-right
          Positioned(
            top: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.verifiedGreenBg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.verified_rounded,
                      color: AppColors.verifiedGreen, size: 14),
                  SizedBox(width: 4),
                  Text(
                    'Secured',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.verifiedGreen,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeaturePill extends StatelessWidget {
  const _FeaturePill({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.cardCanvas,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: AppColors.cardShadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.accentEmerald),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
