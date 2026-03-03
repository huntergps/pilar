import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/modulos_provider.dart';
import '../../../core/providers/usuario_provider.dart';
import '../../../core/router/app_router.dart';

// ---------------------------------------------------------------------------
// Route resolver (file-private)
// ---------------------------------------------------------------------------

/// Maps a module ID to its go_router route.
///
/// Returns null for modules without a dedicated route yet. Those tiles are
/// filtered out of the launcher in [ModuleLauncherGrid].
/// Extend this map whenever a new module screen is added.
String? _routeForModulo(String id) {
  const routes = <String, String>{
    'administracion': PilarRoutes.adminEmpresa,
    'comunicacion':   PilarRoutes.comunicacion,
    'entidades':      PilarRoutes.entidadesContactos,
  };
  return routes[id];
}

/// Responsive Wrap grid of module tiles for the Dashboard App Launcher.
///
/// Automatically adjusts the number of columns based on the available width:
/// - > 1200 px → 5 columns
/// - > 900 px  → 4 columns
/// - > 600 px  → 3 columns
/// - <= 600 px → 2 columns
///
/// Each tile is a [_ModuleTile] that displays the module icon and name.
class ModuleLauncherGrid extends ConsumerWidget {
  final List<ModuloItem> modulos;

  const ModuleLauncherGrid({super.key, required this.modulos});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tieneAdmin =
        ref.watch(hasPermissionProvider('administracion.empresa.menu'));

    return Padding(
      padding: const EdgeInsets.all(24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final cols =
              width > 1200 ? 5 : width > 900 ? 4 : width > 600 ? 3 : 2;
          // Subtract outer padding (48 total) + gaps between cols ((cols-1)*16)
          final itemSize =
              ((width - 48 - (cols - 1) * 16) / cols).clamp(100.0, 200.0);

          // Only render tiles that have a known route AND that the user
          // has permission to access.
          final navigable = modulos
              .where((m) => _routeForModulo(m.id) != null)
              .where((m) => m.id != 'administracion' || tieneAdmin)
              .toList();

          if (navigable.isEmpty) {
            return const Center(child: Text('No hay módulos disponibles'));
          }

          return Wrap(
            spacing: 16,
            runSpacing: 16,
            children: navigable
                .map((m) => _ModuleTile(modulo: m, size: itemSize))
                .toList(),
          );
        },
      ),
    );
  }
}

/// A single module tile in the App Launcher grid.
///
/// Renders a [Card] + [HoverButton] with a coloured icon container and the
/// module name. Tapping is a no-op for now; routing will be wired once
/// the per-module ShellRoute is in place.
class _ModuleTile extends StatelessWidget {
  final ModuloItem modulo;
  final double size;

  const _ModuleTile({required this.modulo, required this.size});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return SizedBox(
      width: size,
      height: size,
      child: Card(
        padding: EdgeInsets.zero,
        child: HoverButton(
          onPressed: () => context.go(_routeForModulo(modulo.id)!),
          builder: (ctx, states) => AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: states.isHovered
                  ? theme.accentColor.withValues(alpha: 0.08)
                  : null,
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: theme.accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _resolveIcon(modulo.icono),
                    size: 24,
                    color: theme.accentColor,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  modulo.nombre,
                  style: theme.typography.caption,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Maps the icon name string stored in the DB to a [FluentIcons] constant.
  ///
  /// Extends this map as new modules are registered. Falls back to
  /// [FluentIcons.app_icon_default] for unknown names.
  static IconData _resolveIcon(String name) {
    const map = <String, IconData>{
      'home': FluentIcons.home,
      'people': FluentIcons.people,
      'money': FluentIcons.money,
      'shopping_cart': FluentIcons.shopping_cart,
      'box': FluentIcons.cube_shape,
      'calculator': FluentIcons.calculator,
      'bank': FluentIcons.bank,
      'receipt': FluentIcons.receipt_processing,
      'settings': FluentIcons.settings,
      'mail': FluentIcons.mail,
      'chart': FluentIcons.bar_chart_vertical,
      'calendar': FluentIcons.calendar,
      'wrench': FluentIcons.build,
      'shield': FluentIcons.shield_alert,
      'cloud': FluentIcons.cloud,
      'apps': FluentIcons.waffle,
    };
    return map[name] ?? FluentIcons.app_icon_default;
  }
}
