import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/auth/presentation/onboarding_screen.dart';
import '../../features/auth/presentation/pin_setup_screen.dart';
import '../../features/auth/presentation/pin_lock_screen.dart';
import '../../features/vault/presentation/dashboard_screen.dart';
import '../../features/ai/presentation/qa_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/vault/presentation/category_detail_screen.dart';
import '../../features/search/presentation/search_screen.dart';
import '../../features/vault/presentation/add_text_item_screen.dart';
import '../../features/vault/presentation/item_detail_screen.dart';

class AppRoutes {
  static const String splash = '/splash';
  static const String onboarding = '/onboarding';
  static const String createPin = '/create-pin';
  static const String confirmPin = '/confirm-pin';
  static const String lock = '/lock';
  static const String dashboard = '/dashboard';
  static const String aiChat = '/ai-chat';
  static const String settings = '/settings';
  static const String categoryDetail = '/category/:id';
  static const String itemDetail = '/item/:id';
  static const String add = '/add/:categoryId';
  static const String edit = '/edit_text_item/:itemId';
  static const String search = '/search';
}

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.splash,
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoutes.createPin,
        builder: (context, state) => const PinSetupScreen(isConfirm: false),
      ),
      GoRoute(
        path: AppRoutes.confirmPin,
        builder: (context, state) {
          final firstPin = state.extra as String? ?? '';
          return PinSetupScreen(isConfirm: true, firstPin: firstPin);
        },
      ),
      GoRoute(
        path: AppRoutes.lock,
        builder: (context, state) => const PinLockScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => _MainShell(child: child),
        routes: [
          GoRoute(
            path: AppRoutes.dashboard,
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: AppRoutes.aiChat,
            builder: (context, state) => const QaScreen(),
          ),
          GoRoute(
            path: AppRoutes.settings,
            builder: (context, state) => const SettingsScreen(),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.categoryDetail,
        builder: (context, state) => CategoryDetailScreen(
          categoryId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: AppRoutes.search,
        builder: (context, state) => const SearchScreen(),
      ),
      GoRoute(
        path: AppRoutes.itemDetail,
        builder: (context, state) => ItemDetailScreen(
          itemId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: AppRoutes.add,
        builder: (context, state) => AddTextItemScreen(
          categoryId: state.pathParameters['categoryId']!,
        ),
      ),
      GoRoute(
        path: AppRoutes.edit,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return AddTextItemScreen(
            categoryId: '', // will be inferred
            itemToEdit: extra['item'],
            initialContent: extra['content'],
          );
        },
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(child: Text('Page not found: ${state.uri}')),
    ),
  );
});

/// Bottom navigation shell — 3 tabs per design.md
class _MainShell extends ConsumerWidget {
  const _MainShell({required this.child});
  final Widget child;

  int _locationToIndex(String location) {
    if (location.startsWith('/dashboard')) return 0;
    if (location.startsWith('/ai-chat')) return 1;
    if (location.startsWith('/settings')) return 2;
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).uri.toString();
    final idx = _locationToIndex(location);

    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2B3C5A).withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(
                  icon: Icons.shield_outlined,
                  activeIcon: Icons.shield,
                  label: 'Vault',
                  isActive: idx == 0,
                  onTap: () => context.go(AppRoutes.dashboard),
                ),
                _NavItem(
                  icon: Icons.auto_awesome_outlined,
                  activeIcon: Icons.auto_awesome,
                  label: 'DocSift AI',
                  isActive: idx == 1,
                  onTap: () => context.go(AppRoutes.aiChat),
                ),
                _NavItem(
                  icon: Icons.settings_outlined,
                  activeIcon: Icons.settings,
                  label: 'Settings',
                  isActive: idx == 2,
                  onTap: () => context.go(AppRoutes.settings),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF2B3C5A).withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isActive ? activeIcon : icon,
              color: isActive
                  ? const Color(0xFF2B3C5A)
                  : const Color(0xFF718096),
              size: 22,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight:
                    isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive
                    ? const Color(0xFF2B3C5A)
                    : const Color(0xFF718096),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
