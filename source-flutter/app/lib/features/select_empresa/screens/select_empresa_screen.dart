import 'package:fluent_ui/fluent_ui.dart';
import 'package:fluent_ui_reactive/fluent_ui_reactive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/empresa_provider.dart';
import '../../../core/router/app_router.dart';

/// Company-selection screen shown after login when the user belongs to
/// more than one empresa (or when no empresa_id is present in the JWT).
///
/// Auto-selection rules (via [ref.listen]):
/// - 0 empresas → go to [PilarRoutes.onboarding] (create first empresa).
/// - 1 empresa  → auto-select silently, then:
///     • placeholder empresa (nombre "Mi Empresa" / ruc "9999999999999")
///       → [PilarRoutes.onboarding] to complete company setup.
///     • configured empresa → [PilarRoutes.dashboard].
/// - >1 empresas → show the picker grid so the user can choose.
///
/// Layout: responsive card grid.
/// - >900px  → 4 columns
/// - >600px  → 3 columns
/// - <=600px → 2 columns
class SelectEmpresaScreen extends ConsumerWidget {
  const SelectEmpresaScreen({super.key});

  /// Returns true when the empresa was created as a placeholder by the
  /// onboarding trigger and still needs the user to complete the wizard.
  static bool _esPlaceholder(EmpresaResumen e) =>
      e.nombre == 'Mi Empresa' || e.ruc == '9999999999999' || e.ruc == null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final misEmpresasAsync = ref.watch(misEmpresasProvider);

    ref.listen<AsyncValue<List<EmpresaResumen>>>(misEmpresasProvider, (_, next) {
      next.whenData((empresas) async {
        if (!context.mounted) return;

        if (empresas.isEmpty) {
          // No empresa at all → create first one.
          context.go(PilarRoutes.onboarding);
          return;
        }

        if (empresas.length == 1) {
          // Single empresa → auto-select without user interaction.
          final empresa = empresas.first;
          try {
            final switchFn = ref.read(switchEmpresaProvider);
            await switchFn(empresa.empresaId);
          } catch (_) {
            // Ignore — router will re-evaluate after session refresh.
          }
          if (!context.mounted) return;
          // Navigate based on whether the empresa data is configured.
          context.go(
            _esPlaceholder(empresa)
                ? PilarRoutes.onboarding
                : PilarRoutes.dashboard,
          );
        }
      });
    });

    return ScaffoldPage(
      header: const PageHeader(title: Text('Seleccionar empresa')),
      content: PilarAsyncBuilder<List<EmpresaResumen>>(
        value: misEmpresasAsync,
        isEmpty: (empresas) => empresas.isEmpty,
        emptyWidget: const Center(child: ProgressRing()),
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

// ---------------------------------------------------------------------------
// Letter avatar helper
// ---------------------------------------------------------------------------

class _LetterAvatar extends StatelessWidget {
  final String nombre;
  final FluentThemeData theme;

  const _LetterAvatar({required this.nombre, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      color: theme.accentColor.withValues(alpha: 0.15),
      alignment: Alignment.center,
      child: Text(
        nombre.isNotEmpty ? nombre[0].toUpperCase() : '?',
        style: theme.typography.subtitle,
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Individual empresa card.
///
/// Shows company logo (or letter avatar), name, RUC and the user's role.
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
              // Company logo or letter avatar
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: empresa.logoUrl != null
                    ? Image.network(
                        empresa.logoUrl!,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _LetterAvatar(
                          nombre: empresa.nombre,
                          theme: theme,
                        ),
                      )
                    : _LetterAvatar(nombre: empresa.nombre, theme: theme),
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
