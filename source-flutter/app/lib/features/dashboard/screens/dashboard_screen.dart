import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluent_ui_reactive/fluent_ui_reactive.dart';

import '../../../core/providers/empresa_provider.dart';
import '../../../core/providers/modulos_provider.dart';
import '../widgets/module_launcher_grid.dart';

/// App Launcher — responsive grid of active modules for the current empresa.
///
/// Shows all modules activated for the authenticated user's empresa in a
/// responsive tile grid. Falls back to an empty state when no modules are
/// available (e.g. new empresa with no modules configured yet).
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modulosAsync = ref.watch(modulosActivosProvider);
    final empresaAsync = ref.watch(empresaConfigProvider);
    final theme = FluentTheme.of(context);

    return ScaffoldPage(
      header: PageHeader(
        title: Text(
          empresaAsync.valueOrNull?.nombre ?? 'Dashboard',
          style: theme.typography.title,
        ),
      ),
      content: PilarAsyncBuilder<List<ModuloItem>>(
        value: modulosAsync,
        isEmpty: (list) => list.isEmpty,
        emptyWidget: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                FluentIcons.app_icon_default,
                size: 48,
                color: theme.inactiveColor,
              ),
              const SizedBox(height: 16),
              Text(
                'No hay módulos activos',
                style: theme.typography.body,
              ),
              const SizedBox(height: 8),
              Text(
                'Contacta al administrador para activar módulos',
                style: theme.typography.caption,
              ),
            ],
          ),
        ),
        builder: (context, modulos) => ModuleLauncherGrid(modulos: modulos),
      ),
    );
  }
}
