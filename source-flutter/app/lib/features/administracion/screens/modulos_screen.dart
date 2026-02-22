import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluent_ui_reactive/fluent_ui_reactive.dart';

import '../../../core/providers/modulos_provider.dart';

/// Pantalla de gestión de módulos activos de la empresa.
///
/// Muestra la lista de módulos actualmente activos obtenida de
/// [modulosActivosProvider]. Cada item indica el nombre, tipo y estado
/// del módulo con un icono de verificación.
///
/// La activación/desactivación de módulos se implementará en una iteración
/// posterior vía el RPC `activate_module()`.
class ModulosScreen extends ConsumerWidget {
  const ModulosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modulosAsync = ref.watch(modulosActivosProvider);
    final theme = FluentTheme.of(context);

    return ScaffoldPage(
      header: const PageHeader(title: Text('Módulos')),
      content: PilarAsyncBuilder<List<ModuloItem>>(
        value: modulosAsync,
        isEmpty: (list) => list.isEmpty,
        emptyWidget: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                FluentIcons.tiles,
                size: 48,
                color: theme.inactiveColor,
              ),
              const SizedBox(height: 16),
              Text(
                'No hay módulos activos',
                style: theme.typography.body,
              ),
            ],
          ),
        ),
        builder: (context, modulos) => ListView.separated(
          padding: const EdgeInsets.all(24),
          itemCount: modulos.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final m = modulos[i];
            return _ModuloListTile(modulo: m);
          },
        ),
      ),
    );
  }
}

class _ModuloListTile extends StatelessWidget {
  final ModuloItem modulo;

  const _ModuloListTile({required this.modulo});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return Card(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: theme.accentColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              FluentIcons.app_icon_default,
              color: theme.accentColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(modulo.nombre, style: theme.typography.bodyStrong),
                const SizedBox(height: 2),
                Text(
                  _tipoLabel(modulo.tipo),
                  style: theme.typography.caption,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            FluentIcons.check_mark,
            size: 16,
            color: theme.accentColor,
          ),
        ],
      ),
    );
  }

  String _tipoLabel(String tipo) {
    switch (tipo) {
      case 'infraestructura':
        return 'Infraestructura';
      case 'core':
        return 'Core';
      case 'auxiliar':
        return 'Extensión';
      default:
        return tipo;
    }
  }
}
