import 'dart:io';

import 'package:brick_gen/brick_gen.dart';
import 'package:brick_offline_first_with_supabase/brick_offline_first_with_supabase.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
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
// Splash state
// ---------------------------------------------------------------------------

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
// Helper — ejecuta un paso con tiempo mínimo de visualización
// ---------------------------------------------------------------------------

/// Muestra [msg] en el splash, espera a que el frame se renderice,
/// ejecuta [op] y garantiza que el mensaje sea visible al menos [minMs] ms.
///
/// - Si [op] tarda más que [minMs] → sin pausa extra.
/// - Si [op] es muy rápida (< 16ms) → al menos un frame se renderiza +
///   se espera el tiempo restante hasta completar [minMs].
Future<T> _step<T>(
  _SplashState splash,
  String msg,
  double p,
  Future<T> Function() op, {
  int minMs = 220,
}) async {
  splash.report(msg, p);

  // Espera a que el frame con el nuevo mensaje se pinte en pantalla.
  // Sin esto, operaciones de < 16ms nunca renderizan su mensaje.
  await SchedulerBinding.instance.endOfFrame;

  final sw = Stopwatch()..start();
  final result = await op();
  sw.stop();

  // Completar el tiempo mínimo de visualización si la operación fue rápida.
  final remaining = minMs - sw.elapsedMilliseconds;
  if (remaining > 0) {
    await Future.delayed(Duration(milliseconds: remaining));
  }

  return result;
}

// ---------------------------------------------------------------------------
// Splash app
// ---------------------------------------------------------------------------

class _SplashApp extends StatelessWidget {
  final _SplashState state;

  /// Color de empresa leído desde SharedPreferences antes de este primer
  /// runApp. Si es null, se usa el color de acento del sistema operativo.
  final Color? initialColor;

  /// Tema leído desde SharedPreferences antes del primer runApp.
  /// Garantiza que el splash respeta dark/light del usuario desde el frame 1.
  final ThemeMode initialThemeMode;

  const _SplashApp({
    required this.state,
    required this.initialThemeMode,
    this.initialColor,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (_, __) {
        final accent = initialColor != null
            ? initialColor!.toAccentColor()
            : SystemTheme.accentColor.accent.toAccentColor();

        return FluentApp(
          debugShowCheckedModeBanner: false,
          themeMode: initialThemeMode,
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

  // ── 0. Leer caché de inicio rápido — ANTES de cualquier UI ──────────────────
  // SharedPreferences no requiere Supabase. Tres claves fijas permiten
  // restaurar el estado visual exacto de la última sesión:
  //   • cfg_last_empresa_id    — empresa activa (para trazabilidad)
  //   • cfg_last_empresa_color — color primario de esa empresa (ARGB int)
  //   • cfg_theme_mode         — preferencia claro/oscuro/sistema del usuario
  //
  // Estas claves se escriben cada vez que el valor cambia en la sesión activa
  // (cambio de empresa, update Realtime del admin, cambio de tema en perfil).
  final prefs = await SharedPreferences.getInstance();

  // Color de empresa:
  final savedColorValue = prefs.getInt(ConfigKeys.lastEmpresaColor);
  final savedEmpresaColor =
      (savedColorValue != null && savedColorValue != 0)
          ? Color(savedColorValue)
          : null;

  // Tema claro / oscuro / sistema:
  final savedThemeModeIdx = prefs.getInt(ConfigKeys.themeMode)
      ?? ThemeMode.system.index;
  final savedThemeMode = ThemeMode.values[
      savedThemeModeIdx.clamp(0, ThemeMode.values.length - 1)];

  // ── DIAGNÓSTICO — quitar después de confirmar ──────────────────────────────
  debugPrint('[PILAR-BOOT] === CACHÉ DE INICIO ===');
  debugPrint('[PILAR-BOOT] lastEmpresaColor key : ${ConfigKeys.lastEmpresaColor}');
  debugPrint('[PILAR-BOOT] lastEmpresaId  key   : ${ConfigKeys.lastEmpresaId}');
  debugPrint('[PILAR-BOOT] savedColorValue (int) : $savedColorValue');
  debugPrint('[PILAR-BOOT] savedEmpresaColor     : $savedEmpresaColor');
  debugPrint('[PILAR-BOOT] savedThemeMode        : $savedThemeMode');
  debugPrint('[PILAR-BOOT] lastEmpresaId (read)  : ${prefs.getString(ConfigKeys.lastEmpresaId)}');
  debugPrint('[PILAR-BOOT] todas las claves cfg_ : ${prefs.getKeys().where((k) => k.startsWith('cfg_')).toList()}');
  // ─────────────────────────────────────────────────────────────────────────

  // ── Splash — primer frame con el color Y tema correctos ───────────────────
  final splash = _SplashState();
  runApp(_SplashApp(
    state: splash,
    initialColor: savedEmpresaColor,
    initialThemeMode: savedThemeMode,
  ));

  // ── 1. Ventana desktop ────────────────────────────────────────────────────
  if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    await _step(
      splash,
      'Configurando ventana…',
      0.08,
      WindowService.initialize,
    );
  }

  // ── 2. Color de acento del sistema (solo mobile/web sin empresa color) ────
  // Si ya tenemos el color de empresa no necesitamos el color del SO.
  if (savedEmpresaColor == null &&
      (kIsWeb || (!kIsWeb && (Platform.isAndroid || Platform.isIOS)))) {
    await _step(
      splash,
      'Cargando tema del sistema…',
      0.18,
      SystemTheme.accentColor.load,
    );
  }

  // ── 3. Credenciales Supabase (dart-define → SharedPreferences → defaults) ─
  final config = await _step(
    splash,
    'Cargando configuración…',
    0.32,
    SupabaseConfigService.load,
  );

  // ── 4. Supabase + cliente offline ─────────────────────────────────────────
  if (!kIsWeb) {
    await _step(
      splash,
      'Conectando a Supabase…',
      0.52,
      () async {
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
      },
    );

    // ── 5. Base de datos local (SQLite + cola offline) ──────────────────────
    await _step(
      splash,
      'Iniciando base de datos local…',
      0.72,
      PilarRepository.instance.initialize,
    );
  } else {
    await _step(
      splash,
      'Conectando a Supabase…',
      0.62,
      () => Supabase.initialize(url: config.url, anonKey: config.anonKey),
    );
  }

  // ── 6. Listo ──────────────────────────────────────────────────────────────
  await _step(
    splash,
    'Preparando interfaz…',
    0.88,
    () async {}, // tiempo de visualización mínimo antes de la transición
  );

  splash.report('¡Listo!', 1.0);
  await SchedulerBinding.instance.endOfFrame; // renderizar el 100%
  await Future.delayed(const Duration(milliseconds: 400));

  // Reemplazar la splash app con la app real.
  runApp(
    ProviderScope(
      overrides: [
        supabaseConfiguredProvider.overrideWith((ref) => true),
        supabaseUrlProvider.overrideWith((ref) => config.url),
        if (savedEmpresaColor != null)
          empresaColorProvider.overrideWith((ref) => savedEmpresaColor),
      ],
      child: const PilarApp(),
    ),
  );
}

// ---------------------------------------------------------------------------
// Root application widget
// ---------------------------------------------------------------------------

class PilarApp extends ConsumerWidget {
  const PilarApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final config = ref.watch(appConfigProvider);
    final empresaColor = ref.watch(empresaColorProvider);

    return FluentApp.router(
      title: 'PILAR ERP',
      routerConfig: router,
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
