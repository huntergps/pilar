import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:system_theme/system_theme.dart';

import 'core/config/supabase_config.dart';
import 'core/providers/theme_provider.dart';
import 'core/router/app_router.dart' show routerProvider, supabaseConfiguredProvider, supabaseUrlProvider;
import 'core/services/window_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // --- Desktop window setup (must happen before runApp) ---
  if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    await WindowService.initialize();
  }

  // --- System accent color ---
  // Load on mobile/web platforms; desktop platforms are already handled
  // inside WindowService.initialize(). Safe to call multiple times.
  if (kIsWeb || (!kIsWeb && (Platform.isAndroid || Platform.isIOS))) {
    await SystemTheme.accentColor.load();
  }

  // --- Supabase initialization ---
  // Try to load credentials (compile-time --dart-define or saved SharedPreferences).
  // When no credentials are found, the router redirects to /setup instead.
  final config = await SupabaseConfigService.load();
  final supabaseConfigured = config != null;

  if (supabaseConfigured) {
    await Supabase.initialize(url: config.url, anonKey: config.anonKey);
  } else {
    // Initialize with empty strings; the /setup screen will re-initialize.
    await Supabase.initialize(url: 'https://placeholder.supabase.co', anonKey: 'placeholder');
  }

  runApp(
    ProviderScope(
      overrides: [
        supabaseConfiguredProvider.overrideWith((ref) => supabaseConfigured),
        supabaseUrlProvider.overrideWith((ref) => config?.url ?? ''),
      ],
      child: const PilarApp(),
    ),
  );
}

/// Root application widget.
///
/// Uses [FluentApp.router] as required by the PILAR design system (fluent_ui).
/// Reads theme and router providers from Riverpod; no state is held locally.
class PilarApp extends ConsumerWidget {
  const PilarApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final lightTheme = ref.watch(pilarThemeProvider);
    final darkTheme = ref.watch(pilarDarkThemeProvider);
    final themeMode = ref.watch(themeBrightnessProvider);

    return FluentApp.router(
      title: 'PILAR ERP',
      // --- Routing ---
      routerConfig: router,
      // --- Theming ---
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      // --- Localization ---
      locale: const Locale('es'),
      supportedLocales: const [
        Locale('es'),
        Locale('en'),
      ],
      localizationsDelegates: FluentLocalizations.localizationsDelegates,
      // Disable the debug banner in all builds (ERP apps are always client-facing).
      debugShowCheckedModeBanner: false,
    );
  }
}
