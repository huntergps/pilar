import 'package:fluent_ui/fluent_ui.dart';
import 'package:fluent_ui_reactive/fluent_ui_reactive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/empresa_provider.dart';
import '../../../core/router/app_router.dart';

/// Company-selection screen shown after login when the user belongs to
/// more than one empresa (or when no empresa_id is present in the JWT).
///
/// Layout: responsive card grid.
/// - >900px  → 4 columns
/// - >600px  → 3 columns
/// - <=600px → 2 columns
///
/// Tapping a card calls [switchEmpresaProvider], refreshes the session so
/// the JWT includes the new empresa_id, then navigates to the dashboard.
class SelectEmpresaScreen extends ConsumerWidget {
  const SelectEmpresaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final misEmpresasAsync = ref.watch(misEmpresasProvider);

    return ScaffoldPage(
      header: const PageHeader(title: Text('Seleccionar empresa')),
      content: PilarAsyncBuilder<List<EmpresaResumen>>(
        value: misEmpresasAsync,
        isEmpty: (empresas) => empresas.isEmpty,
        emptyWidget: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(FluentIcons.company_directory, size: 48),
              const SizedBox(height: 16),
              Text(
                'No tienes empresas asignadas.',
                style: FluentTheme.of(context).typography.body,
              ),
            ],
          ),
        ),
        builder: (context, empresas) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final cols = width > 900 ? 4 : width > 600 ? 3 : 2;
                const spacing = 16.0;
                final cardWidth =
                    (width - (cols - 1) * spacing) / cols;

                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: empresas
                      .map(
                        (empresa) => SizedBox(
                          width: cardWidth,
                          child: _EmpresaCard(empresa: empresa),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// Individual empresa card.
///
/// Shows company avatar (first letter), name, RUC and the user's role.
/// Pressing the card switches the active empresa and navigates to dashboard.
class _EmpresaCard extends ConsumerWidget {
  final EmpresaResumen empresa;

  const _EmpresaCard({required this.empresa});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = FluentTheme.of(context);

    return Card(
      padding: EdgeInsets.zero,
      child: HoverButton(
        onPressed: () async {
          final switchFn = ref.read(switchEmpresaProvider);
          await switchFn(empresa.empresaId);
          if (context.mounted) {
            context.go(PilarRoutes.dashboard);
          }
        },
        builder: (context, states) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Company avatar — first letter on accent background
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: theme.accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  empresa.nombre.isNotEmpty
                      ? empresa.nombre[0].toUpperCase()
                      : '?',
                  style: theme.typography.subtitle,
                ),
              ),
              const SizedBox(height: 12),

              // Company name
              Text(
                empresa.nombre,
                style: theme.typography.bodyStrong,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),

              // RUC (optional)
              if (empresa.ruc != null) ...[
                const SizedBox(height: 2),
                Text(
                  empresa.ruc!,
                  style: theme.typography.caption,
                ),
              ],

              const SizedBox(height: 4),

              // Role badge
              Text(
                empresa.rolNombre,
                style: theme.typography.caption?.copyWith(
                  color: theme.accentColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
