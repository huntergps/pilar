import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluent_ui_reactive/fluent_ui_reactive.dart';

import '../../../core/providers/empresa_provider.dart';
import '../../../core/providers/modulos_provider.dart';
import '../providers/dashboard_kpis_provider.dart';
import '../widgets/empresa_card.dart';
import '../widgets/module_launcher_grid.dart';

// ---------------------------------------------------------------------------
// KPI widgets
// ---------------------------------------------------------------------------

class _KpiRow extends StatelessWidget {
  final DashboardKpis kpis;
  const _KpiRow({required this.kpis});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 88,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        children: [
          _KpiCard(icon: FluentIcons.contact,  label: 'Contactos',     value: kpis.contactos),
          _KpiCard(icon: FluentIcons.product,  label: 'Productos',     value: kpis.productos),
          _KpiCard(icon: FluentIcons.chat,     label: 'Conv. activas', value: kpis.conversacionesActivas),
          _KpiCard(icon: FluentIcons.people,   label: 'Usuarios',      value: kpis.usuariosActivos),
          _KpiCard(icon: FluentIcons.waffle,   label: 'Módulos',       value: kpis.modulosActivos),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final int value;
  const _KpiCard({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Container(
      width: 130,
      margin: const EdgeInsets.only(right: 12),
      child: Card(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: theme.accentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(icon, size: 18, color: theme.accentColor),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('$value', style: theme.typography.subtitle),
                  Text(
                    label,
                    style: theme.typography.caption,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

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

    final empresa = empresaAsync.valueOrNull;

    return ScaffoldPage(
      header: const PageHeader(title: Text('Dashboard')),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Card de empresa (visible en cuanto carga el config)
          if (empresa != null) EmpresaCard(empresa: empresa),

          // KPI cards row
          Consumer(
            builder: (context, ref, _) {
              final kpisAsync = ref.watch(dashboardKpisProvider);
              return kpisAsync.when(
                loading: () => const SizedBox(
                  height: 80,
                  child: Center(child: ProgressRing()),
                ),
                error: (_, __) => const SizedBox.shrink(),
                data: (kpis) => _KpiRow(kpis: kpis),
              );
            },
          ),

          // Grid de módulos
          Expanded(
            child: PilarAsyncBuilder<List<ModuloItem>>(
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
              builder: (context, modulos) =>
                  ModuleLauncherGrid(modulos: modulos),
            ),
          ),
        ],
      ),
    );
  }
}
