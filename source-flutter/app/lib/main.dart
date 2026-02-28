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
import 'core/router/app_router.dart'
    show routerProvider, supabaseConfiguredProvider, supabaseUrlProvider;
import 'core/services/window_service.dart';
import 'features/splash/screens/splash_screen.dart';

// ---------------------------------------------------------------------------
// Splash state notifier
// ---------------------------------------------------------------------------

/// Estado compartido entre [main] y [_SplashApp].
///
/// [main] llama a [report] en cada paso de inicialización para actualizar
/// el texto y la barra de progreso de la pantalla splash.
class _SplashState extends ChangeNotifier {
  String step = 'Iniciando…';
  double progress = 0.0;

  void report(String msg, double p) {
    step = msg;
    progress = p;
    notifyListeners();
  }
}

// ---------------------------------------------------------------------------
// Splash app (reemplazada por PilarApp al terminar la inicialización)
// ---------------------------------------------------------------------------

/// [FluentApp] mínimo que solo renderiza [SplashScreen].
///
/// Se muestra mientras [main] completa la inicialización asíncrona.
/// Es reemplazado por un segundo [runApp] con el [PilarApp] real.
///
/// - Detecta modo claro/oscuro del SO en el primer frame via
///   [ThemeMode.system] + ambos [theme]/[darkTheme] configurados.
/// - El accent color usa [SystemTheme.accentColor.accent]; antes de que
///   [load()] termine devuelve el color del sistema operativo directamente
///   (azul Windows / azul macOS por defecto). Se actualiza automáticamente
///   al notificar el siguiente paso.
class _SplashApp extends StatelessWidget {
  final _SplashState state;

  const _SplashApp({required this.state});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (_, __) {
        final accent = SystemTheme.accentColor.accent.toAccentColor();

        return FluentApp(
          debugShowCheckedModeBanner: false,
          // ThemeMode.system → usa theme (light) o darkTheme (dark) según el SO.
          // El OS preference es detectado sincrónicamente por Flutter en el
          // primer frame — sin necesidad de SharedPreferences.
          themeMode: ThemeMode.system,
          theme: FluentThemeData(
            brightness: Brightness.light,
            accentColor: accent,
          ),
          darkTheme: FluentThemeData(
            brightness: Brightness.dark,
            accentColor: accent,
          ),
          home: SplashScreen(
            status: state.step,
            progress: state.progress,
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Mostrar splash ANTES de cualquier inicialización asíncrona.
  final splash = _SplashState();
  runApp(_SplashApp(state: splash));

  void step(String msg, double p) => splash.report(msg, p);

  // ── 1. Ventana desktop ────────────────────────────────────────────────────
  if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    step('Configurando ventana…', 0.08);
    await WindowService.initialize();
  }

  // ── 2. Color de acento del sistema ────────────────────────────────────────
  step('Cargando tema del sistema…', 0.18);
  if (kIsWeb || (!kIsWeb && (Platform.isAndroid || Platform.isIOS))) {
    await SystemTheme.accentColor.load();
  }

  // ── 3. Credenciales Supabase ──────────────────────────────────────────────
  step('Cargando configuración…', 0.32);
  final config = await SupabaseConfigService.load();

  // ── 4. Supabase + cliente offline ─────────────────────────────────────────
  step('Conectando a Supabase…', 0.50);
  if (!kIsWeb) {
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

    // ── 5. Base de datos local (SQLite + cola offline) ──────────────────────
    step('Iniciando base de datos local…', 0.70);
    await PilarRepository.instance.initialize();
  } else {
    // Web: sin cola offline (sqflite no disponible en browser)
    await Supabase.initialize(url: config.url, anonKey: config.anonKey);
  }

  // ── 6. Color de empresa desde caché ──────────────────────────────────────
  step('Preparando interfaz…', 0.88);
  Color? cachedEmpresaColor;
  try {
    final session = Supabase.instance.client.auth.currentSession;
    final empresaId = session?.user.appMetadata['empresa_id'] as String?;
    if (empresaId != null) {
      final prefs = await SharedPreferences.getInstance();
      final colorValue =
          prefs.getInt('${ConfigKeys.empresaColorPrefix}$empresaId');
      if (colorValue != null && colorValue != 0) {
        cachedEmpresaColor = Color(colorValue);
      }
    }
  } catch (_) {
    // Primer uso o prefs corruptas → sin color cacheado, sin problema.
  }

  // ── 7. Listo ─────────────────────────────────────────────────────────────
  step('¡Listo!', 1.0);
  // Pausa breve para que el usuario vea el 100% completado.
  await Future.delayed(const Duration(milliseconds: 350));

  // Reemplazar la splash app con la app real (Riverpod + go_router).
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

// ---------------------------------------------------------------------------
// Root application widget
// ---------------------------------------------------------------------------

/// Widget raíz de la app. Se monta después de que [main] completa la
/// inicialización y reemplaza [_SplashApp] con un segundo [runApp].
///
/// Usa [FluentApp.router] como requiere el design system PILAR (fluent_ui).
class PilarApp extends ConsumerWidget {
  const PilarApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final config = ref.watch(appConfigProvider);
    final empresaColor = ref.watch(empresaColorProvider);

    return FluentApp.router(
      title: 'PILAR ERP',
      // --- Routing ---
      routerConfig: router,
      // --- Theming ---
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
