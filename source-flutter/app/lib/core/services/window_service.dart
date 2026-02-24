import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:fluent_ui/fluent_ui.dart' show Color;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:system_theme/system_theme.dart';
import 'package:window_manager/window_manager.dart';

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
  /// - Restores the last saved window size and maximized state.
  /// - Hides the native title bar (custom [DragToMoveArea] will be used).
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
    final width = prefs.getDouble(_keyWidth) ?? 1280.0;
    final height = prefs.getDouble(_keyHeight) ?? 800.0;
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

    await windowManager.setMinimumSize(const Size(800, 600));

    // Restore saved window geometry or fall back to defaults.
    if (width >= 800 && height >= 600) {
      await windowManager.setSize(Size(width, height));
    } else {
      await windowManager.setSize(const Size(1280, 800));
    }
    await windowManager.center();

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

    // Apply platform-specific translucency effect.
    if (Platform.isWindows) {
      await Window.setEffect(
        effect: WindowEffect.acrylic,
        color: const Color(0xCC1C1C1C),
      );
    } else if (Platform.isMacOS) {
      await Window.setEffect(effect: WindowEffect.sidebar);
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
