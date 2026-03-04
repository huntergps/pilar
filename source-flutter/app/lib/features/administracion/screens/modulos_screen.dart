import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluent_ui_reactive/fluent_ui_reactive.dart';
import '../../../core/providers/modulos_provider.dart';
import '../providers/admin_providers.dart';
import '../../../core/theme/pilar_spacing.dart';
import '../../../core/widgets/loading_spinner.dart';

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

/// Pantalla de gestión de módulos disponibles para la empresa.
///
/// Muestra TODOS los módulos del sistema agrupados por tipo.
/// Los módulos de infraestructura siempre están activos y no son desactivables.
/// Los módulos core y auxiliares pueden activarse/desactivarse vía
/// [admin_activate_module] / [admin_deactivate_module].
class ModulosScreen extends ConsumerWidget {
  const ModulosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modulosAsync = ref.watch(todosModulosProvider);
    final theme = FluentTheme.of(context);

    return ScaffoldPage(
      header: const PageHeader(title: Text('Módulos')),
      content: PilarAsyncBuilder<List<ModuloEstado>>(
        value: modulosAsync,
        isEmpty: (list) => list.isEmpty,
        emptyWidget: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(FluentIcons.tiles, size: 48, color: theme.inactiveColor),
              const SizedBox(height: Spacing.md),
              Text('No hay módulos disponibles',
                  style: theme.typography.body),
            ],
          ),
        ),
        builder: (context, modulos) {
          final infra = modulos
              .where((m) => m.tipo == 'infraestructura')
              .toList();
          final core = modulos
              .where((m) => m.tipo == 'core')
              .toList();
          final auxiliares = modulos
              .where((m) => m.tipo == 'auxiliar')
              .toList();

          return ListView(
            padding: const EdgeInsets.all(Spacing.lg),
            children: [
              if (infra.isNotEmpty) ...[
                _GroupHeader(
                  title: 'Infraestructura',
                  subtitle: 'Siempre activos — no desactivables',
                  theme: theme,
                ),
                const SizedBox(height: Spacing.sm),
                ...infra.map((m) => _ModuloTile(modulo: m)),
                const SizedBox(height: Spacing.lg),
              ],
              if (core.isNotEmpty) ...[
                _GroupHeader(
                  title: 'Core',
                  subtitle: 'Módulos principales del ERP',
                  theme: theme,
                ),
                const SizedBox(height: Spacing.sm),
                ...core.map((m) => _ModuloTile(modulo: m)),
                const SizedBox(height: Spacing.lg),
              ],
              if (auxiliares.isNotEmpty) ...[
                _GroupHeader(
                  title: 'Extensiones',
                  subtitle: 'Módulos opcionales activables por empresa',
                  theme: theme,
                ),
                const SizedBox(height: Spacing.sm),
                ...auxiliares.map((m) => _ModuloTile(modulo: m)),
              ],
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Group header
// ---------------------------------------------------------------------------

class _GroupHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final FluentThemeData theme;

  const _GroupHeader({
    required this.title,
    required this.subtitle,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.typography.bodyStrong),
        Text(subtitle,
            style: theme.typography.caption
                ?.copyWith(color: theme.inactiveColor)),
        const SizedBox(height: Spacing.xs),
        const Divider(),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Module tile with toggle
// ---------------------------------------------------------------------------

class _ModuloTile extends ConsumerStatefulWidget {
  final ModuloEstado modulo;

  const _ModuloTile({required this.modulo});

  @override
  ConsumerState<_ModuloTile> createState() => _ModuloTileState();
}

class _ModuloTileState extends ConsumerState<_ModuloTile> {
  bool _loading = false;

  Future<void> _toggle(bool newValue) async {
    if (_loading) return;

    // Confirm before deactivating a module
    if (!newValue) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => ContentDialog(
          title: Text('Desactivar ${widget.modulo.nombre}'),
          content: const Text(
            'Al desactivar este módulo perderás acceso a sus funciones. '
            '¿Deseas continuar?',
          ),
          actions: [
            Button(
              child: const Text('Cancelar'),
              onPressed: () => Navigator.pop(context, false),
            ),
            FilledButton(
              style: const ButtonStyle(
                backgroundColor: WidgetStatePropertyAll(
                  Colors.errorPrimaryColor,
                ),
              ),
              child: const Text('Desactivar'),
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() => _loading = true);

    try {
      final resultado = await ref.read(modulosAdminProvider.notifier).toggleModulo(
        moduloId: widget.modulo.id,
        activar: newValue,
      );

      if (resultado.ok) {
        ref.invalidate(todosModulosProvider);
        ref.invalidate(modulosActivosProvider);
      } else {
        if (mounted) {
          displayInfoBar(
            context,
            builder: (_, close) => InfoBar(
              title: Text(newValue ? 'Error al activar módulo' : 'Error al desactivar módulo'),
              content: Text(_errorMessage(resultado.error)),
              severity: InfoBarSeverity.error,
              onClose: close,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        displayInfoBar(
          context,
          builder: (_, close) => InfoBar(
            title: const Text('Error'),
            content: Text(e.toString()),
            severity: InfoBarSeverity.error,
            onClose: close,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _errorMessage(String? code) {
    switch (code) {
      case 'PERMISSION_DENIED':
        return 'No tienes permiso para gestionar módulos.';
      case 'MODULE_NOT_IN_PLAN':
        return 'Este módulo no está incluido en tu plan actual.';
      case 'INFRAESTRUCTURA_SIEMPRE_ACTIVA':
        return 'Los módulos de infraestructura siempre están activos.';
      default:
        return code ?? 'Error desconocido';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isInfra = widget.modulo.tipo == 'infraestructura';

    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Card(
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: widget.modulo.habilitado
                    ? theme.accentColor.withValues(alpha: 0.15)
                    : theme.resources.subtleFillColorSecondary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                FluentIcons.app_icon_default,
                color: widget.modulo.habilitado
                    ? theme.accentColor
                    : theme.inactiveColor,
                size: 22,
              ),
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.modulo.nombre,
                      style: theme.typography.bodyStrong),
                  const SizedBox(height: Spacing.xxs),
                  Text(
                    _tipoLabel(widget.modulo.tipo),
                    style: theme.typography.caption
                        ?.copyWith(color: theme.inactiveColor),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Spacing.md),
            if (_loading)
              const PilarProgressRing(size: 20)
            else if (isInfra)
              Tooltip(
                message: 'Siempre activo',
                child: Icon(
                  FluentIcons.lock,
                  size: 16,
                  color: theme.inactiveColor,
                ),
              )
            else
              ToggleSwitch(
                checked: widget.modulo.habilitado,
                onChanged: _toggle,
              ),
          ],
        ),
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
