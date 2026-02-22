import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:window_manager/window_manager.dart';

import '../providers/modulos_provider.dart';
import '../router/app_router.dart';
import '../services/window_service.dart';
import 'pilar_header.dart';

/// The main authenticated navigation shell for PILAR ERP.
///
/// Wraps the go_router [ShellRoute] child in a [NavigationView] with:
/// - Adaptive pane (auto display mode: expanded → compact → minimal).
/// - Fixed pane items: Dashboard and Administración.
/// - Dynamic pane items generated from [modulosActivosProvider]
///   (excludes infra modules already in the fixed list).
/// - A custom [TitleBar] with the PILAR branding, notification bell and
///   user avatar via [PilarHeader].
/// - Window control buttons on Windows (minimize / maximize / close).
/// - Window geometry persistence via [WindowService.saveState].
///
/// The go_router [child] is rendered through [NavigationView.paneBodyBuilder]
/// so the router owns the page lifecycle — no [IndexedStack] needed.
class PilarShell extends ConsumerStatefulWidget {
  final Widget child;

  const PilarShell({super.key, required this.child});

  @override
  ConsumerState<PilarShell> createState() => _PilarShellState();
}

class _PilarShellState extends ConsumerState<PilarShell> with WindowListener {
  // ---- Window lifecycle ----------------------------------------------------

  /// True when running on a desktop OS (Windows / macOS / Linux).
  /// Guarded by [kIsWeb] to avoid dart:io on web.
  bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  @override
  void initState() {
    super.initState();
    if (_isDesktop) windowManager.addListener(this);
  }

  @override
  void dispose() {
    if (_isDesktop) windowManager.removeListener(this);
    super.dispose();
  }

  // Persist window geometry on every resize / move / maximize event.
  @override
  void onWindowResized() => WindowService.saveState();
  @override
  void onWindowMoved() => WindowService.saveState();
  @override
  void onWindowMaximize() => WindowService.saveState();
  @override
  void onWindowUnmaximize() => WindowService.saveState();

  // ---- Index calculation ---------------------------------------------------

  /// Maps the current route to the corresponding [NavigationPane] item index.
  ///
  /// Fixed items:
  ///   0 → Dashboard
  ///   1 → Administración
  ///
  /// Dynamic module items start at index 2.
  int _indexForRoute(String location, List<ModuloItem> modulos) {
    if (location.startsWith('/admin')) return 1;
    if (location.startsWith('/dashboard')) return 0;

    // Try to match a dynamic module route (future: '/<modulo.id>').
    final coreModulos = modulos.where((m) => m.tipo != 'infraestructura');
    int idx = 2;
    for (final m in coreModulos) {
      if (location.startsWith('/${m.id}')) return idx;
      idx++;
    }

    // Default to Dashboard if no match.
    return 0;
  }

  // ---- Sign-out ------------------------------------------------------------

  Future<void> _signOut(BuildContext context) async {
    await Supabase.instance.client.auth.signOut();
    if (context.mounted) context.go(PilarRoutes.login);
  }

  // ---- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final modulosAsync = ref.watch(modulosActivosProvider);
    final modulos = modulosAsync.valueOrNull ?? const <ModuloItem>[];
    final location = GoRouterState.of(context).matchedLocation;
    final selectedIndex = _indexForRoute(location, modulos);

    // Core non-infra modules shown as dynamic pane items after the fixed ones.
    final dynamicModulos = modulos.where((m) => m.tipo != 'infraestructura');

    return NavigationView(
      // ---- Title bar ----
      titleBar: TitleBar(
        // Back button is handled by go_router; hide the default one.
        isBackButtonVisible: false,
        title: Text(
          'PILAR ERP',
          style: FluentTheme.of(context).typography.bodyStrong,
        ),
        endHeader: PilarHeader(
          isDesktop: _isDesktop,
        ),
        // On Windows, provide custom caption controls; macOS has native ones.
        captionControls: (!kIsWeb && Platform.isWindows)
            ? const WindowButtons()
            : null,
      ),

      // ---- Navigation pane ----
      pane: NavigationPane(
        displayMode: PaneDisplayMode.auto,
        selected: selectedIndex,
        onChanged: (index) {
          switch (index) {
            case 0:
              context.go(PilarRoutes.dashboard);
            case 1:
              context.go(PilarRoutes.admin);
            default:
              // Dynamic module items start at index 2.
              final modIdx = index - 2;
              final list = dynamicModulos.toList();
              if (modIdx >= 0 && modIdx < list.length) {
                // Future: context.go('/${list[modIdx].id}');
                // Currently navigates to dashboard until module routes exist.
                context.go(PilarRoutes.dashboard);
              }
          }
        },
        items: [
          // ---- Fixed items ----
          PaneItem(
            icon: const Icon(FluentIcons.home),
            title: const Text('Dashboard'),
            body: const SizedBox.shrink(),
          ),
          PaneItem(
            icon: const Icon(FluentIcons.settings),
            title: const Text('Administración'),
            body: const SizedBox.shrink(),
          ),
          // ---- Dynamic module items ----
          ...dynamicModulos.map(
            (m) => PaneItem(
              icon: const Icon(FluentIcons.app_icon_default),
              title: Text(m.nombre),
              body: const SizedBox.shrink(),
            ) as NavigationPaneItem,
          ),
        ],
        footerItems: [
          PaneItemSeparator(),
          PaneItemAction(
            icon: const Icon(FluentIcons.sign_out),
            title: const Text('Salir'),
            onTap: () => _signOut(context),
          ),
        ],
      ),

      // ---- Body builder ----
      // Instead of using PaneItem.body, we hand over control to go_router's
      // ShellRoute child so page lifecycle is managed by the router.
      paneBodyBuilder: (_, __) => widget.child,
    );
  }
}
