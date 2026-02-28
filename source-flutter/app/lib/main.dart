import 'dart:io';

import 'package:brick_gen/brick_gen.dart';
import 'package:brick_offline_first_with_supabase/brick_offline_first_with_supabase.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart' show databaseFactory;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:system_theme/system_theme.dart';

import 'package:shared_preferences/shared_preferences.dart';

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

  // --- Supabase + Brick offline-first initialization ---
  // Siempre hay credenciales válidas: --dart-define > SharedPreferences > defaults.
  final config = await SupabaseConfigService.load();

  if (!kIsWeb) {
    // Native: create the offline-aware HTTP client BEFORE Supabase.initialize()
    // so every Supabase PostgREST call goes through the offline queue.
    final (offlineClient, offlineQueue) =
        OfflineFirstWithSupabaseRepository.clientQueue(
      databaseFactory: databaseFactory,
      ignorePaths: {'/auth/v1', '/storage/v1', '/functions/v1'},
    );
    await Supabase.initialize(
      url: config.url,
      anonKey: config.anonKey,
      httpClient: offlineClient,
    );
    PilarRepository.configure(
      supabaseClient: Supabase.instance.client,
      offlineQueue: offlineQueue,
    );
    // initialize() crea las tablas SQLite (modelos + HttpJobs de la cola offline)
    await PilarRepository.instance.initialize();
  } else {
    // Web: no offline queue (sqflite not available on web)
    await Supabase.initialize(url: config.url, anonKey: config.anonKey);
  }

  // Pre-carga el color primario de empresa desde caché (SharedPreferences) para
  // que el primer frame ya use el color correcto y no haya flash del azul del SO.
  // La caché se escribe en pilar_shell.dart cada vez que Supabase devuelve el color.
  Color? cachedEmpresaColor;
  try {
    final session = Supabase.instance.client.auth.currentSession;
    final empresaId = session?.user.appMetadata['empresa_id'] as String?;
    if (empresaId != null) {
      final prefs = await SharedPreferences.getInstance();
      final colorValue = prefs.getInt('${ConfigKeys.empresaColorPrefix}$empresaId');
      if (colorValue != null && colorValue != 0) {
        cachedEmpresaColor = Color(colorValue);
      }
    }
  } catch (_) {
    // Si falla la lectura (primer uso, prefs corruptas) se inicia sin color cacheado.
  }

  runApp(
    ProviderScope(
      overrides: [
        supabaseConfiguredProvider.overrideWith((ref) => true),
        supabaseUrlProvider.overrideWith((ref) => config.url),
        if (cachedEmpresaColor != null)
          empresaColorProvider.overrideWith((ref) => cachedEmpresaColor!),
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
    final router       = ref.watch(routerProvider);
    final config       = ref.watch(appConfigProvider);
    final empresaColor = ref.watch(empresaColorProvider);

    return FluentApp.router(
      title: 'PILAR ERP',
      // --- Routing ---
      routerConfig: router,
      // --- Theming — built inline so typography/spacing changes apply instantly ---
      theme: PilarTheme.build(
        brightness: Brightness.light,
        config: config,
        empresaColor: empresaColor,
      ),
      darkTheme: PilarTheme.build(
        brightness: Brightness.dark,
        config: config,
        empresaColor: empresaColor,
      ),
      themeMode: config.themeMode,
      // --- Localization ---
      locale: const Locale('es'),
      supportedLocales: const [
        Locale('es'),
        Locale('en'),
      ],
      localizationsDelegates: FluentLocalizations.localizationsDelegates,
      debugShowCheckedModeBanner: false,
    );
  }
}
