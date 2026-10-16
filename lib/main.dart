import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/ai/data/model_manager.dart';
import 'features/auth/data/auth_repository.dart';

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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Pre-warm ONNX models in background
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(modelManagerProvider).init();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      // App went to background -> lock the vault automatically for security
      final authRepo = ref.read(authRepositoryProvider);
      if (!authRepo.isLocked && !authRepo.isBypassAutoLock) {
        authRepo.lock();
        ref.read(routerProvider).go(AppRoutes.lock);
      }
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
    );
  }
}
