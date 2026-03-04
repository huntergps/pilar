import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/empresa_provider.dart';
import '../../../core/config/pilar_constants.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/pilar_spacing.dart';
import '../../../core/widgets/loading_spinner.dart';

/// Pantalla de selección de empresa mostrada al iniciar sesión cuando el usuario
/// pertenece a más de una empresa (o cuando no hay empresa_id en el JWT).
///
/// Auto-selección:
/// - 0 empresas → [PilarRoutes.onboarding] (crear primera empresa).
/// - 1 empresa  → auto-selecciona silenciosamente:
///     • placeholder → [PilarRoutes.onboarding] para completar wizard.
///     • configurada → [PilarRoutes.dashboard].
/// - >1 empresas → muestra el picker centrado con branding PILAR.
class SelectEmpresaScreen extends ConsumerWidget {
  const SelectEmpresaScreen({super.key});

  static bool _esPlaceholder(EmpresaResumen e) =>
      e.nombre == 'Mi Empresa' || e.ruc == '9999999999999' || e.ruc == null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final misEmpresasAsync = ref.watch(misEmpresasProvider);
    final theme = FluentTheme.of(context);

    // Auto-selección cuando llegan los datos
    ref.listen<AsyncValue<List<EmpresaResumen>>>(misEmpresasProvider, (_, next) {
      next.whenData((empresas) async {
        if (!context.mounted) return;

        if (empresas.isEmpty) {
          context.go(PilarRoutes.onboarding);
          return;
        }

        if (empresas.length == 1) {
          final empresa = empresas.first;
          try {
            await ref.read(switchEmpresaProvider)(empresa.empresaId);
          } catch (_) {}
          if (!context.mounted) return;
          context.go(
            _esPlaceholder(empresa)
                ? PilarRoutes.onboarding
                : PilarRoutes.dashboard,
          );
        }
      });
    });

    return Container(
      color: theme.scaffoldBackgroundColor,
      child: Center(
        child: misEmpresasAsync.when(
          loading: () => const PilarProgressRing(),
          error: (e, _) => SizedBox(
            width: 360,
            child: InfoBar(
              title: const Text('Error al cargar empresas'),
              content: Text(e.toString()),
              severity: InfoBarSeverity.error,
            ),
          ),
          data: (empresas) {
            // Mostrar spinner mientras se hace auto-selección
            if (empresas.isEmpty || empresas.length == 1) {
              return const PilarProgressRing();
            }
            return _PickerContent(empresas: empresas);
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Picker content — visible solo cuando hay ≥ 2 empresas
// ---------------------------------------------------------------------------

class _PickerContent extends StatefulWidget {
  final List<EmpresaResumen> empresas;

  const _PickerContent({required this.empresas});

  @override
  State<_PickerContent> createState() => _PickerContentState();
}

class _PickerContentState extends State<_PickerContent> {
  final _searchCtrl = TextEditingController();
  String _busqueda = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final mostrarSearch = widget.empresas.length > 4;

    final filtradas = _busqueda.isEmpty
        ? widget.empresas
        : widget.empresas.where((e) {
            final q = _busqueda.toLowerCase();
            return e.nombre.toLowerCase().contains(q) ||
                (e.ruc?.contains(q) ?? false);
          }).toList();

    // Empresa activa (último uso) siempre primero
    final ordenadas = [...filtradas]
      ..sort((a, b) => (b.esActiva ? 1 : 0).compareTo(a.esActiva ? 1 : 0));

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.xxl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ---- Branding ----
              Text(
                kAppName,
                style: theme.typography.display?.copyWith(
                  color: theme.accentColor,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: Spacing.sm),
              Text(
                'Selecciona una empresa para continuar',
                style: theme.typography.subtitle?.copyWith(
                  color: theme.resources.textFillColorSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Spacing.xl),

              // ---- Búsqueda (solo si > 4 empresas) ----
              if (mostrarSearch) ...[
                TextBox(
                  controller: _searchCtrl,
                  placeholder: 'Buscar por nombre o RUC...',
                  prefix: const Padding(
                    padding: EdgeInsets.only(left: Spacing.sm),
                    child: Icon(FluentIcons.search, size: 14),
                  ),
                  suffix: _busqueda.isNotEmpty
                      ? Padding(
                          padding: const EdgeInsets.only(right: Spacing.xs),
                          child: IconButton(
                            icon: const Icon(FluentIcons.clear, size: 12),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _busqueda = '');
                            },
                          ),
                        )
                      : null,
                  onChanged: (v) => setState(() => _busqueda = v),
                ),
                const SizedBox(height: Spacing.ml),
              ],

              // ---- Grid de empresas ----
              if (ordenadas.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Spacing.xl),
                  child: Text(
                    'Sin resultados para "$_busqueda"',
                    style: theme.typography.body
                        ?.copyWith(color: theme.inactiveColor),
                  ),
                )
              else
                LayoutBuilder(
                  builder: (ctx, constraints) {
                    final cols = constraints.maxWidth > 480 ? 3 : 2;
                    const spacing = 12.0;
                    final cardWidth =
                        (constraints.maxWidth - (cols - 1) * spacing) / cols;
                    return Wrap(
                      spacing: spacing,
                      runSpacing: spacing,
                      children: ordenadas
                          .map(
                            (e) => SizedBox(
                              width: cardWidth,
                              child: _EmpresaCard(empresa: e),
                            ),
                          )
                          .toList(),
                    );
                  },
                ),

              const SizedBox(height: Spacing.lg),

              // ---- Crear nueva empresa ----
              HyperlinkButton(
                onPressed: () => context.go(PilarRoutes.onboarding),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(FluentIcons.add,
                        size: 14, color: theme.accentColor),
                    const SizedBox(width: Spacing.sm),
                    const Text('Crear nueva empresa'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tarjeta de empresa
// ---------------------------------------------------------------------------

class _EmpresaCard extends ConsumerStatefulWidget {
  final EmpresaResumen empresa;

  const _EmpresaCard({required this.empresa});

  @override
  ConsumerState<_EmpresaCard> createState() => _EmpresaCardState();
}

class _EmpresaCardState extends ConsumerState<_EmpresaCard> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final esActiva = widget.empresa.esActiva;

    return HoverButton(
      onPressed: _loading
          ? null
          : () async {
              setState(() => _loading = true);
              try {
                await ref.read(switchEmpresaProvider)(widget.empresa.empresaId);
                if (context.mounted) context.go(PilarRoutes.dashboard);
              } catch (_) {
                if (mounted) setState(() => _loading = false);
              }
            },
      builder: (ctx, states) {
        final hovered = states.isHovered;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: esActiva
                ? theme.accentColor.withValues(alpha: 0.06)
                : (hovered
                    ? theme.resources.subtleFillColorSecondary
                    : theme.cardColor),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: esActiva
                  ? theme.accentColor
                  : (hovered
                      ? theme.resources.controlStrokeColorDefault
                      : theme.resources.controlStrokeColorDefault
                          .withValues(alpha: 0.5)),
              width: esActiva ? 1.5 : 1,
            ),
          ),
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---- Logo + badge activa ----
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _EmpresaLogoAvatar(
                    logoUrl: widget.empresa.logoUrl,
                    nombre: widget.empresa.nombre,
                    size: 44,
                  ),
                  const Spacer(),
                  if (esActiva)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: Spacing.sm, vertical: Spacing.xxs),
                      decoration: BoxDecoration(
                        color: theme.accentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Activa',
                        style: theme.typography.caption?.copyWith(
                          color: theme.accentColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  if (_loading)
                    const PilarProgressRing.small(),
                ],
              ),
              const SizedBox(height: Spacing.ms),

              // ---- Nombre ----
              Text(
                widget.empresa.nombre,
                style: theme.typography.bodyStrong,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),

              // ---- RUC ----
              if (widget.empresa.ruc != null) ...[
                const SizedBox(height: Spacing.xxs),
                Text(
                  widget.empresa.ruc!,
                  style: theme.typography.caption,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              const SizedBox(height: Spacing.xs),

              // ---- Rol ----
              Text(
                widget.empresa.rolNombre,
                style: theme.typography.caption
                    ?.copyWith(color: theme.accentColor),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Logo / initial avatar de empresa
// ---------------------------------------------------------------------------

class _EmpresaLogoAvatar extends StatelessWidget {
  final String? logoUrl;
  final String nombre;
  final double size;

  const _EmpresaLogoAvatar({
    required this.logoUrl,
    required this.nombre,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final initial = nombre.isNotEmpty ? nombre[0].toUpperCase() : '?';

    Widget fallback() => Container(
          width: size,
          height: size,
          color: theme.accentColor.withValues(alpha: 0.15),
          alignment: Alignment.center,
          child: Text(
            initial,
            style: theme.typography.subtitle?.copyWith(
              color: theme.accentColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        );

    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.18),
      child: (logoUrl != null && logoUrl!.isNotEmpty)
          ? Image.network(
              logoUrl!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => fallback(),
            )
          : fallback(),
    );
  }
}
