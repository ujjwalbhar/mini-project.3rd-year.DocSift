import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/constants/app_colors.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/ai/data/model_manager.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/settings/presentation/settings_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Light system UI overlay on navy splash
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  runApp(
    const ProviderScope(
      child: DocSiftApp(),
    ),
  );
}

class DocSiftApp extends ConsumerStatefulWidget {
  const DocSiftApp({super.key});

  @override
  ConsumerState<DocSiftApp> createState() => _DocSiftAppState();
}

class _DocSiftAppState extends ConsumerState<DocSiftApp> with WidgetsBindingObserver {
  DateTime? _backgroundedAt;
  Timer? _autoLockTimer;
  bool _isObscured = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _autoLockTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _lockVaultNow() {
    final authRepo = ref.read(authRepositoryProvider);
    if (!authRepo.isLocked && !authRepo.isBypassAutoLock) {
      ref.read(modelManagerProvider).releaseQaSession();
      authRepo.lock();
      ref.read(routerProvider).go(AppRoutes.lock);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final authRepo = ref.read(authRepositoryProvider);
    if (state == AppLifecycleState.inactive) {
      if (!authRepo.isBypassAutoLock && !_isObscured) {
        setState(() => _isObscured = true);
      }
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      if (!authRepo.isBypassAutoLock && !_isObscured) {
        setState(() => _isObscured = true);
      }
      if (authRepo.isLocked || authRepo.isBypassAutoLock) return;

      final timeoutMinutes = ref.read(autoLockTimerProvider);
      if (timeoutMinutes <= 0) {
        _lockVaultNow();
      } else {
        _backgroundedAt ??= DateTime.now();
        _autoLockTimer?.cancel();
        _autoLockTimer = Timer(Duration(minutes: timeoutMinutes), _lockVaultNow);
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_isObscured) {
        setState(() => _isObscured = false);
      }
      _autoLockTimer?.cancel();
      _autoLockTimer = null;
      if (_backgroundedAt != null && !authRepo.isLocked && !authRepo.isBypassAutoLock) {
        final timeoutMinutes = ref.read(autoLockTimerProvider);
        final elapsed = DateTime.now().difference(_backgroundedAt!);
        if (elapsed >= Duration(minutes: timeoutMinutes)) {
          _lockVaultNow();
        }
      }
      _backgroundedAt = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'DocSift',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: router,
      builder: (context, child) {
        return Stack(
          children: [
            if (child != null) child,
            if (_isObscured) const _PrivacyCurtain(),
          ],
        );
      },
    );
  }
}

class _PrivacyCurtain extends StatelessWidget {
  const _PrivacyCurtain();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.primaryNavy,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shield_rounded, color: AppColors.accentEmerald, size: 56),
            SizedBox(height: 12),
            Text(
              'DocSift Vault Protected',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
