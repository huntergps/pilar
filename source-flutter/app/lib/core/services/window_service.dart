import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Offset, Size;
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:fluent_ui/fluent_ui.dart' show Color;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:system_theme/system_theme.dart';
import 'package:window_manager/window_manager.dart';

import 'config_service.dart' show ConfigKeys;
import '../theme/pilar_breakpoints.dart';

/// Manages desktop window initialization, sizing, and persistence.
///
/// Call [initialize] from main() before runApp() on desktop platforms.
/// Call [saveState] from a [WindowListener] to persist window geometry.
class WindowService {
  WindowService._();

  static const String _keyWidth = 'window_width';
  static const String _keyHeight = 'window_height';
  static const String _keyX = 'window_x';
  static const String _keyY = 'window_y';
  static const String _keyMaximized = 'window_maximized';

  /// Initializes the desktop window before runApp().
  ///
  /// - Loads the system accent color (for system_theme).
  /// - Initializes flutter_acrylic [Window].
  /// - Restores the last saved window size, position, and maximized state.
  /// - Hides the native title bar (custom [DragToMoveArea] will be used).
  /// - Enables preventClose so [onWindowClose] can save state before exiting.
  /// - Applies a platform-appropriate translucency effect.
  ///
  /// No-op on non-desktop platforms.
  static Future<void> initialize() async {
    if (!_isDesktop) return;

    await SystemTheme.accentColor.load();

    // flutter_acrylic: initialize only on platforms where we apply effects.
    // Windows: also hide native caption controls (custom WindowCaption used).
    if (Platform.isWindows) {
      await Window.initialize();
      await Window.hideWindowControls();
    } else if (Platform.isMacOS) {
      await Window.initialize(); // needed for sidebar translucency effect
    }

    await windowManager.ensureInitialized();

    final prefs = await SharedPreferences.getInstance();
    final savedWidth  = prefs.getDouble(_keyWidth);
    final savedHeight = prefs.getDouble(_keyHeight);
    final savedX      = prefs.getDouble(_keyX);
    final savedY      = prefs.getDouble(_keyY);
    final isMaximized = prefs.getBool(_keyMaximized) ?? false;

    // Set title bar style before waitUntilReadyToShow for reliable application.
    // windowButtonVisibility: false on all platforms — WindowCaption widget
    // (window_manager) renders the correct native controls per platform:
    //   macOS  → traffic-light buttons (red/yellow/green)
    //   Windows/Linux → minimize / maximize / close
    await windowManager.setTitleBarStyle(
      TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );

    await windowManager.setMinimumSize(const Size(PilarBreakpoints.minWindowWidth, PilarBreakpoints.minWindowHeight));

    // preventClose: true lets onWindowClose intercept the close event so we
    // can persist window state before actually destroying the window.
    await windowManager.setPreventClose(true);

    // Restore saved geometry, or fall back to defaults centered on screen.
    final width  = (savedWidth  != null && savedWidth  >= PilarBreakpoints.minWindowWidth)  ? savedWidth  : PilarBreakpoints.defaultWindowWidth;
    final height = (savedHeight != null && savedHeight >= PilarBreakpoints.minWindowHeight) ? savedHeight : PilarBreakpoints.defaultWindowHeight;
    await windowManager.setSize(Size(width, height));

    if (savedX != null && savedY != null) {
      await windowManager.setPosition(Offset(savedX, savedY));
    } else {
      await windowManager.center();
    }

    await windowManager.waitUntilReadyToShow(
      null,
      () async {
        if (isMaximized) {
          await windowManager.maximize();
        }
        await windowManager.show();
        await windowManager.focus();
      },
    );

    // Apply platform-specific translucency effect (reads persisted preference).
    // The stored value is WindowEffect.name (e.g. 'acrylic', 'mica', 'sidebar', 'disabled').
    final effectName = prefs.getString(ConfigKeys.windowEffect);
    if (Platform.isWindows) {
      final windowEffect = WindowEffect.values.firstWhere(
        (e) => e.name == effectName,
        orElse: () => WindowEffect.acrylic,
      );
      await Window.setEffect(effect: windowEffect, color: const Color(0xCC1C1C1C));
    } else if (Platform.isMacOS) {
      final windowEffect = WindowEffect.values.firstWhere(
        (e) => e.name == effectName,
        orElse: () => WindowEffect.sidebar,
      );
      await Window.setEffect(effect: windowEffect);
    }
    // Linux: no translucency effect (limited compositor support).
  }

  /// Persists the current window geometry and maximized state.
  ///
  /// Intended to be called from [WindowListener.onWindowResized],
  /// [WindowListener.onWindowMoved], and [WindowListener.onWindowMaximize] /
  /// [WindowListener.onWindowUnmaximize].
  ///
  /// No-op on non-desktop platforms.
  static Future<void> saveState() async {
    if (!_isDesktop) return;

    final prefs = await SharedPreferences.getInstance();
    final bounds = await windowManager.getBounds();
    final isMaximized = await windowManager.isMaximized();

    await prefs.setDouble(_keyWidth, bounds.width);
    await prefs.setDouble(_keyHeight, bounds.height);
    await prefs.setDouble(_keyX, bounds.left);
    await prefs.setDouble(_keyY, bounds.top);
    await prefs.setBool(_keyMaximized, isMaximized);
  }

  /// Returns true when the current platform is a desktop OS.
  static bool get _isDesktop =>
      !kIsWeb &&
      (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
}
