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
/// - Dashboard as a fixed item at index 0.
/// - Administración as a [PaneItemExpander] (header has body:null → not in
///   effectiveItems). Its four children are at indices 1–4:
///     1 → Empresa, 2 → Usuarios, 3 → Módulos, 4 → Configuración.
/// - Dynamic module items starting at index 5.
/// - Window geometry persistence via [WindowService.saveState].
class PilarShell extends ConsumerStatefulWidget {
  final Widget child;

  const PilarShell({super.key, required this.child});

  @override
  ConsumerState<PilarShell> createState() => _PilarShellState();
}

class _PilarShellState extends ConsumerState<PilarShell> with WindowListener {
  // ---- Window lifecycle ----------------------------------------------------

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

  @override
  void onWindowResized() => WindowService.saveState();
  @override
  void onWindowMoved() => WindowService.saveState();
  @override
  void onWindowMaximize() => WindowService.saveState();
  @override
  void onWindowUnmaximize() => WindowService.saveState();

  // ---- Index calculation ---------------------------------------------------

  /// Maps the current route to the [NavigationPane] effectiveItems index.
  ///
  /// Indices (PaneItemExpander header has body:null → NOT counted):
  ///   0 → Dashboard
  ///   1 → Empresa       (/admin/empresa)
  ///   2 → Usuarios      (/admin/usuarios)
  ///   3 → Módulos       (/admin/modulos)
  ///   4 → Configuración (/admin/configuracion)
  ///   5+ → Dynamic modules
  int _indexForRoute(String location, List<ModuloItem> modulos) {
    if (location.startsWith('/dashboard')) return 0;
    if (location.startsWith('/admin/empresa')) return 1;
    if (location.startsWith('/admin/usuarios')) return 2;
    if (location.startsWith('/admin/modulos')) return 3;
    if (location.startsWith('/admin/configuracion')) return 4;
    if (location.startsWith('/admin')) return 1; // /admin → empresa

    final coreModulos = modulos.where((m) => m.tipo != 'infraestructura');
    int idx = 5;
    for (final m in coreModulos) {
      if (location.startsWith('/${m.id}')) return idx;
      idx++;
    }

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

    final dynamicModulos = modulos.where((m) => m.tipo != 'infraestructura');

    return NavigationView(
      // ---- Title bar ----
      titleBar: TitleBar(
        isBackButtonVisible: false,
        title: const DragToMoveArea(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text('PILAR ERP'),
          ),
        ),
        endHeader: PilarHeader(isDesktop: _isDesktop),
        captionControls: _isDesktop
            ? SizedBox(
                width: 138,
                height: 50,
                child: WindowCaption(
                  brightness: FluentTheme.of(context).brightness,
                  backgroundColor: Colors.transparent,
                ),
              )
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
              context.go(PilarRoutes.adminEmpresa);
            case 2:
              context.go(PilarRoutes.adminUsuarios);
            case 3:
              context.go(PilarRoutes.adminModulos);
            case 4:
              context.go(PilarRoutes.adminConfiguracion);
            default:
              final modIdx = index - 5;
              final list = dynamicModulos.toList();
              if (modIdx >= 0 && modIdx < list.length) {
                // Future: context.go('/${list[modIdx].id}');
                context.go(PilarRoutes.dashboard);
              }
          }
        },
        items: [
          // ---- Dashboard ----
          PaneItem(
            icon: const Icon(FluentIcons.home),
            title: const Text('Dashboard'),
            body: const SizedBox.shrink(),
          ),

          // ---- Administración (expander, body:null → no index) ----
          PaneItemExpander(
            icon: const Icon(FluentIcons.settings),
            title: const Text('Administración'),
            // body: null → excluded from effectiveItems, not selectable.
            // Children are what get selected (indices 1–4).
            initiallyExpanded: location.startsWith('/admin'),
            items: [
              PaneItem(
                icon: const Icon(FluentIcons.company_directory),
                title: const Text('Empresa'),
                body: const SizedBox.shrink(),
              ),
              PaneItem(
                icon: const Icon(FluentIcons.people),
                title: const Text('Usuarios'),
                body: const SizedBox.shrink(),
              ),
              PaneItem(
                icon: const Icon(FluentIcons.tiles),
                title: const Text('Módulos'),
                body: const SizedBox.shrink(),
              ),
              PaneItem(
                icon: const Icon(FluentIcons.settings),
                title: const Text('Configuración'),
                body: const SizedBox.shrink(),
              ),
            ],
          ),

          // ---- Dynamic module items (index 5+) ----
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

      // go_router owns the page lifecycle via ShellRoute.
      paneBodyBuilder: (_, __) => widget.child,
    );
  }
}
