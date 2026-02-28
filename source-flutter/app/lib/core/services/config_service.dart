import 'dart:async';
import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config_model.dart';

// ---------------------------------------------------------------------------
// PaneDisplayMode persistence helpers
// ---------------------------------------------------------------------------

int _paneDisplayModeToKey(PaneDisplayMode m) => switch (m) {
      PaneDisplayMode.auto     => 0,
      PaneDisplayMode.expanded => 1,
      PaneDisplayMode.compact  => 2,
      PaneDisplayMode.minimal  => 3,
      _                        => 0,
    };

PaneDisplayMode _paneDisplayModeFromKey(int key) => switch (key) {
      1 => PaneDisplayMode.expanded,
      2 => PaneDisplayMode.compact,
      3 => PaneDisplayMode.minimal,
      _ => PaneDisplayMode.auto,
    };

// ---------------------------------------------------------------------------
// SharedPreferences keys — also read by WindowService at startup.
// ---------------------------------------------------------------------------

abstract final class ConfigKeys {
  static const String themeMode        = 'cfg_theme_mode';
  // accentColor es por empresa: clave = 'cfg_accent_color_${empresaId}'
  // La clave legacy 'cfg_accent_color' (sin prefijo) se ignora.
  static const String accentColorPrefix = 'cfg_accent_color_';
  // Color primario de empresa cacheado para evitar flash al iniciar.
  // Clave: 'cfg_empresa_color_${empresaId}' (ARGB int)
  static const String empresaColorPrefix = 'cfg_empresa_color_';
  // Timestamp del último force de color que este dispositivo ha aplicado.
  // Clave: 'cfg_color_forzado_ack_${empresaId}' (ISO 8601)
  static const String colorForzadoAckPrefix = 'cfg_color_forzado_ack_';
  static const String displayFactor    = 'cfg_display_factor';
  static const String titleLargeFactor = 'cfg_title_large_factor';
  static const String titleFactor      = 'cfg_title_factor';
  static const String bodyLargeFactor  = 'cfg_body_large_factor';
  static const String bodyStrongFactor = 'cfg_body_strong_factor';
  static const String bodyFactor       = 'cfg_body_factor';
  static const String captionFactor    = 'cfg_caption_factor';
  static const String spacingFactor    = 'cfg_spacing_factor';
  static const String paneDisplayMode  = 'cfg_pane_display_mode'; // PaneDisplayMode.index
  static const String windowEffect     = 'cfg_window_effect';  // WindowEffect.name
}

// ---------------------------------------------------------------------------
// ConfigService
// ---------------------------------------------------------------------------

/// Manages and persists [AppConfigModel] across sessions.
///
/// **Design rule (same as dev_odoo18):** every setter updates [state]
/// *synchronously* so that Riverpod immediately notifies watchers and the UI
/// reflects the change in the same frame. Persistence to [SharedPreferences]
/// is fire-and-forget — no `await` in setters.
///
/// Usage:
/// ```dart
/// final config = ref.watch(appConfigProvider);
/// ref.read(appConfigProvider.notifier).setThemeMode(ThemeMode.dark);
/// ```
class ConfigService extends Notifier<AppConfigModel> {
  SharedPreferences? _prefs;

  /// ID de la empresa activa — determina la clave de accentColor.
  /// Null cuando el usuario no está autenticado o no ha seleccionado empresa.
  String? _empresaId;

  @override
  AppConfigModel build() {
    // Load global persisted values asynchronously; UI starts with defaults instantly.
    unawaited(_loadFromPrefs());
    return AppConfigModel.defaults;
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  Future<SharedPreferences> _getPrefs() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  String get _accentKey =>
      _empresaId != null ? '${ConfigKeys.accentColorPrefix}$_empresaId' : '';

  String get _empresaColorKey =>
      _empresaId != null ? '${ConfigKeys.empresaColorPrefix}$_empresaId' : '';

  AccentColor? _accentFromPrefs(SharedPreferences prefs) {
    final key = _accentKey;
    if (key.isEmpty) return null;
    final value = prefs.getInt(key) ?? 0;
    if (value == 0) return null;
    for (final c in Colors.accentColors) {
      if (c.toARGB32() == value) return c;
    }
    return null;
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await _getPrefs();

    // ThemeMode
    final themeModeIdx = prefs.getInt(ConfigKeys.themeMode) ?? ThemeMode.system.index;
    final themeMode = ThemeMode.values[themeModeIdx.clamp(0, ThemeMode.values.length - 1)];

    // AccentColor — por empresa (sin empresa: null)
    final accentColor = _accentFromPrefs(prefs);

    // WindowEffect
    final effectName = prefs.getString(ConfigKeys.windowEffect);
    final windowEffect = effectName != null
        ? WindowEffect.values.firstWhere(
            (e) => e.name == effectName,
            orElse: () => WindowEffect.acrylic,
          )
        : WindowEffect.acrylic;

    // PaneDisplayMode
    final paneKey = prefs.getInt(ConfigKeys.paneDisplayMode) ?? 0;
    final paneDisplayMode = _paneDisplayModeFromKey(paneKey);

    state = AppConfigModel(
      themeMode:        themeMode,
      accentColor:      accentColor,
      displayFactor:    (prefs.getDouble(ConfigKeys.displayFactor)    ?? 1.0).clamp(0.5, 2.0),
      titleLargeFactor: (prefs.getDouble(ConfigKeys.titleLargeFactor) ?? 1.0).clamp(0.5, 2.0),
      titleFactor:      (prefs.getDouble(ConfigKeys.titleFactor)      ?? 1.0).clamp(0.5, 2.0),
      bodyLargeFactor:  (prefs.getDouble(ConfigKeys.bodyLargeFactor)  ?? 1.0).clamp(0.5, 2.0),
      bodyStrongFactor: (prefs.getDouble(ConfigKeys.bodyStrongFactor) ?? 1.0).clamp(0.5, 2.0),
      bodyFactor:       (prefs.getDouble(ConfigKeys.bodyFactor)       ?? 1.0).clamp(0.5, 2.0),
      captionFactor:    (prefs.getDouble(ConfigKeys.captionFactor)    ?? 1.0).clamp(0.5, 2.0),
      spacingFactor:    (prefs.getDouble(ConfigKeys.spacingFactor)    ?? 1.0).clamp(0.5, 2.0),
      paneDisplayMode:  paneDisplayMode,
      windowEffect:     windowEffect,
    );
  }

  /// Persists all current state to [SharedPreferences]. Fire-and-forget.
  void _saveConfig() {
    unawaited(_persistAll());
  }

  Future<void> _persistAll() async {
    final prefs = await _getPrefs();
    await prefs.setInt(ConfigKeys.themeMode,           state.themeMode.index);
    final key = _accentKey;
    if (key.isNotEmpty) {
      await prefs.setInt(key, state.accentColor?.toARGB32() ?? 0);
    }
    await prefs.setDouble(ConfigKeys.displayFactor,    state.displayFactor);
    await prefs.setDouble(ConfigKeys.titleLargeFactor, state.titleLargeFactor);
    await prefs.setDouble(ConfigKeys.titleFactor,      state.titleFactor);
    await prefs.setDouble(ConfigKeys.bodyLargeFactor,  state.bodyLargeFactor);
    await prefs.setDouble(ConfigKeys.bodyStrongFactor, state.bodyStrongFactor);
    await prefs.setDouble(ConfigKeys.bodyFactor,       state.bodyFactor);
    await prefs.setDouble(ConfigKeys.captionFactor,    state.captionFactor);
    await prefs.setDouble(ConfigKeys.spacingFactor,    state.spacingFactor);
    await prefs.setInt(ConfigKeys.paneDisplayMode,     _paneDisplayModeToKey(state.paneDisplayMode));
    await prefs.setString(ConfigKeys.windowEffect,     state.windowEffect.name);
  }

  // ---------------------------------------------------------------------------
  // Empresa switching — carga accentColor específico de la empresa
  // ---------------------------------------------------------------------------

  /// Llama este método al cambiar la empresa activa.
  ///
  /// Actualiza [_empresaId] y recarga el [accentColor] guardado para esa
  /// empresa en SharedPreferences. Si no hay override guardado, [accentColor]
  /// queda en null (la app usa el color de la empresa o del SO).
  Future<void> switchEmpresa(String? empresaId) async {
    _empresaId = empresaId;
    final prefs = await _getPrefs();
    final accentColor = _accentFromPrefs(prefs);
    state = state.copyWith(accentColor: accentColor);
  }

  /// Persiste el color primario de la empresa para que el próximo inicio de la
  /// app pueda usarlo sin esperar a Supabase, eliminando el flash de color.
  ///
  /// Llamar desde pilar_shell.dart cada vez que [empresaColorProvider] se
  /// actualiza con el valor real de la empresa. Pasa [null] para borrar.
  Future<void> cacheEmpresaColor(Color? color) async {
    final key = _empresaColorKey;
    if (key.isEmpty) return;
    final prefs = await _getPrefs();
    if (color == null) {
      await prefs.remove(key);
    } else {
      await prefs.setInt(key, color.toARGB32());
    }
  }

  /// Comprueba si el admin ha forzado un color más reciente que el ack local.
  ///
  /// Si [colorForzadoEn] es posterior al ack guardado en este dispositivo,
  /// descarta el override personal del usuario y actualiza el ack.
  /// Devuelve true si se descartó el override (la UI debe aplicar el color de empresa).
  Future<bool> applyForceColorIfNeeded(DateTime? colorForzadoEn) async {
    if (_empresaId == null || colorForzadoEn == null) return false;
    final prefs = await _getPrefs();
    final ackKey = '${ConfigKeys.colorForzadoAckPrefix}$_empresaId';
    final ackStr = prefs.getString(ackKey);
    final ack = ackStr != null ? DateTime.tryParse(ackStr) : null;

    if (ack == null || colorForzadoEn.isAfter(ack)) {
      // El admin forzó un color después del último ack → limpiar override
      state = state.copyWith(accentColor: null);
      final accentKey = _accentKey;
      if (accentKey.isNotEmpty) await prefs.setInt(accentKey, 0);
      await prefs.setString(ackKey, colorForzadoEn.toIso8601String());
      return true;
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // Setters — SYNCHRONOUS state update, async fire-and-forget persistence
  // ---------------------------------------------------------------------------

  void setThemeMode(ThemeMode mode) {
    state = state.copyWith(themeMode: mode);
    _saveConfig();
  }

  /// Sets (or clears) the user's local accent color override.
  /// Pass [null] to fall back to empresa color or OS accent.
  void setAccentColor(AccentColor? color) {
    state = state.copyWith(accentColor: color);
    _saveConfig();
  }

  void setDisplayFactor(double v) {
    state = state.copyWith(displayFactor: v.clamp(0.5, 2.0));
    _saveConfig();
  }

  void setTitleLargeFactor(double v) {
    state = state.copyWith(titleLargeFactor: v.clamp(0.5, 2.0));
    _saveConfig();
  }

  void setTitleFactor(double v) {
    state = state.copyWith(titleFactor: v.clamp(0.5, 2.0));
    _saveConfig();
  }

  void setBodyLargeFactor(double v) {
    state = state.copyWith(bodyLargeFactor: v.clamp(0.5, 2.0));
    _saveConfig();
  }

  void setBodyStrongFactor(double v) {
    state = state.copyWith(bodyStrongFactor: v.clamp(0.5, 2.0));
    _saveConfig();
  }

  void setBodyFactor(double v) {
    state = state.copyWith(bodyFactor: v.clamp(0.5, 2.0));
    _saveConfig();
  }

  void setCaptionFactor(double v) {
    state = state.copyWith(captionFactor: v.clamp(0.5, 2.0));
    _saveConfig();
  }

  void setSpacingFactor(double v) {
    state = state.copyWith(spacingFactor: v.clamp(0.5, 2.0));
    _saveConfig();
  }

  void setDisplayMode(PaneDisplayMode mode) {
    state = state.copyWith(paneDisplayMode: mode);
    _saveConfig();
  }

  /// Updates the window effect, persists it, and applies it immediately on desktop.
  void setWindowEffect(WindowEffect effect) {
    state = state.copyWith(windowEffect: effect);
    _saveConfig();
    unawaited(_applyWindowEffect(effect));
  }

  // ---------------------------------------------------------------------------
  // Bulk reset helpers
  // ---------------------------------------------------------------------------

  void resetTypography() {
    state = state.copyWith(
      displayFactor: 1.0,
      titleLargeFactor: 1.0,
      titleFactor: 1.0,
      bodyLargeFactor: 1.0,
      bodyStrongFactor: 1.0,
      bodyFactor: 1.0,
      captionFactor: 1.0,
    );
    _saveConfig();
  }

  void resetSpacing() {
    state = state.copyWith(spacingFactor: 1.0);
    _saveConfig();
  }

  void reset() {
    state = AppConfigModel.defaults;
    _saveConfig();
  }

  // ---------------------------------------------------------------------------
  // Private
  // ---------------------------------------------------------------------------

  static Future<void> _applyWindowEffect(WindowEffect effect) async {
    if (kIsWeb) return;
    if (Platform.isWindows) {
      await Window.setEffect(effect: effect, color: const Color(0xCC1C1C1C));
    } else if (Platform.isMacOS) {
      await Window.setEffect(effect: effect);
    }
  }
}

/// Global provider for app configuration.
final appConfigProvider = NotifierProvider<ConfigService, AppConfigModel>(
  ConfigService.new,
);
