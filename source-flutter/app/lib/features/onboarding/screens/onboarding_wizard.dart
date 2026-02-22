import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fluent_ui_reactive/fluent_ui_reactive.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/pilar_spacing.dart';

// ---------------------------------------------------------------------------
// Private data models
// ---------------------------------------------------------------------------

class _ModuloCard {
  const _ModuloCard({
    required this.id,
    required this.nombre,
    required this.desc,
    required this.icono,
    this.obligatorio = false,
  });

  final String id;
  final String nombre;
  final String desc;
  final IconData icono;
  final bool obligatorio;
}

class _InvitacionPendiente {
  _InvitacionPendiente();

  String email = '';
  String rolCodigo = 'LECTURA';
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const _provinciasEcuador = [
  'Azuay',
  'Bolívar',
  'Cañar',
  'Carchi',
  'Chimborazo',
  'Cotopaxi',
  'El Oro',
  'Esmeraldas',
  'Galápagos',
  'Guayas',
  'Imbabura',
  'Loja',
  'Los Ríos',
  'Manabí',
  'Morona Santiago',
  'Napo',
  'Orellana',
  'Pastaza',
  'Pichincha',
  'Santa Elena',
  'Santo Domingo de los Tsáchilas',
  'Sucumbíos',
  'Tungurahua',
  'Zamora Chinchipe',
];

const _availableModulos = [
  _ModuloCard(
    id: 'facturacion',
    nombre: 'Facturación',
    desc: 'Emisión de facturas electrónicas SRI',
    icono: FluentIcons.receipt_processing,
    obligatorio: true,
  ),
  _ModuloCard(
    id: 'ventas',
    nombre: 'Ventas',
    desc: 'Cotizaciones y órdenes de venta',
    icono: FluentIcons.money,
  ),
  _ModuloCard(
    id: 'compras',
    nombre: 'Compras',
    desc: 'Órdenes de compra y proveedores',
    icono: FluentIcons.shopping_cart,
  ),
  _ModuloCard(
    id: 'inventario',
    nombre: 'Inventario',
    desc: 'Control de stock y bodegas',
    icono: FluentIcons.product_catalog,
  ),
  _ModuloCard(
    id: 'contabilidad',
    nombre: 'Contabilidad',
    desc: 'Plan de cuentas y asientos',
    icono: FluentIcons.calculator,
  ),
];

const _rolesDisponibles = [
  ('ADMIN', 'Administrador'),
  ('CONTADOR', 'Contador'),
  ('VENDEDOR', 'Vendedor'),
  ('BODEGUERO', 'Bodeguero'),
  ('LECTURA', 'Solo lectura'),
];

// Tipo contribuyente constants — avoids magic strings in the step indicator.
const _tipoSociedad = 'sociedad';
const _tipoPersonaNatural = 'persona_natural';

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

/// Wizard de configuración inicial mostrado cuando empresa.ruc IS NULL.
///
/// Pasos:
///   0 — Datos de empresa (nombre, RUC/cédula, tipo, dirección, provincia)
///   1 — Selección de módulos del plan
///   2 — Invitación de colaboradores (opcional)
class OnboardingWizardScreen extends ConsumerStatefulWidget {
  const OnboardingWizardScreen({super.key});

  @override
  ConsumerState<OnboardingWizardScreen> createState() =>
      _OnboardingWizardState();
}

class _OnboardingWizardState extends ConsumerState<OnboardingWizardScreen> {
  // ---- Wizard navigation ----
  int _currentStep = 0;
  bool _isLoading = false;
  String? _errorMessage;

  // ---- Step 0 — Empresa ----
  final _formKeyEmpresa = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _rucController = TextEditingController();
  final _direccionController = TextEditingController();
  String _tipoContribuyente = _tipoSociedad;
  String? _provinciaSeleccionada;

  // ---- Step 1 — Módulos ----
  // 'facturacion' is always pre-selected and locked (obligatorio).
  final Set<String> _modulosSeleccionados = {'facturacion'};

  // ---- Step 2 — Equipo ----
  final List<_InvitacionPendiente> _invitaciones = [];

  // Parallel list of controllers for email TextFormBox fields.
  // Kept in sync with _invitaciones so content survives setState rebuilds.
  final List<TextEditingController> _emailControllers = [];

  @override
  void dispose() {
    _nombreController.dispose();
    _rucController.dispose();
    _direccionController.dispose();
    for (final c in _emailControllers) {
      c.dispose();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return ScaffoldPage(
      header: PageHeader(
        title: const Text('Bienvenido a PILAR ERP'),
        leading: Padding(
          padding: const EdgeInsets.only(left: Spacing.md),
          child: Icon(
            FluentIcons.globe,
            size: 24,
            color: theme.accentColor,
          ),
        ),
      ),
      content: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.lg,
              vertical: Spacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildStepIndicator(theme),
                const SizedBox(height: Spacing.xl),
                Expanded(child: _buildCurrentStep()),
                const SizedBox(height: Spacing.md),
                if (_errorMessage != null) ...[
                  InfoBar(
                    title: const Text('Error'),
                    content: Text(_errorMessage!),
                    severity: InfoBarSeverity.error,
                    onClose: () => setState(() => _errorMessage = null),
                  ),
                  const SizedBox(height: Spacing.sm),
                ],
                _buildNavButtons(theme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Step indicator (manual Row + Containers, no third-party step widget)
  // ---------------------------------------------------------------------------

  static const _stepTitles = ['Empresa', 'Módulos', 'Equipo'];

  Widget _buildStepIndicator(FluentThemeData theme) {
    final itemCount = _stepTitles.length;

    return Row(
      children: List.generate(itemCount * 2 - 1, (i) {
        // Even indices are step circles; odd indices are connector lines.
        if (i.isOdd) {
          final leftStep = i ~/ 2;
          final isCompleted = _currentStep > leftStep;
          return Expanded(
            child: Container(
              height: 2,
              color: isCompleted
                  ? theme.accentColor
                  : theme.resources.controlStrokeColorDefault,
            ),
          );
        }

        final stepIndex = i ~/ 2;
        final isActive = stepIndex == _currentStep;
        final isCompleted = stepIndex < _currentStep;

        final circleColor = (isActive || isCompleted)
            ? theme.accentColor
            : theme.resources.controlFillColorDefault;

        final borderColor = (isActive || isCompleted)
            ? theme.accentColor
            : theme.resources.controlStrokeColorDefault;

        final iconOrLabelColor =
            (isActive || isCompleted) ? Colors.white : theme.resources.textFillColorPrimary;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: circleColor,
                border: Border.all(color: borderColor, width: 2),
              ),
              child: Center(
                child: isCompleted
                    ? Icon(
                        FluentIcons.check_mark,
                        size: 14,
                        color: iconOrLabelColor,
                      )
                    : Text(
                        '${stepIndex + 1}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: iconOrLabelColor,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              _stepTitles[stepIndex],
              style: TextStyle(
                fontSize: 12,
                fontWeight:
                    isActive ? FontWeight.w600 : FontWeight.w400,
                color: (isActive || isCompleted)
                    ? theme.accentColor
                    : theme.resources.textFillColorSecondary,
              ),
            ),
          ],
        );
      }),
    );
  }

  // ---------------------------------------------------------------------------
  // Step router
  // ---------------------------------------------------------------------------

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 0:
        return _buildStepEmpresa();
      case 1:
        return _buildStepModulos();
      case 2:
        return _buildStepEquipo();
      default:
        return const SizedBox.shrink();
    }
  }

  // ---------------------------------------------------------------------------
  // Step 0 — Datos de empresa
  // ---------------------------------------------------------------------------

  Widget _buildStepEmpresa() {
    return SingleChildScrollView(
      child: Form(
        key: _formKeyEmpresa,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSectionHeader(
              FluentIcons.company_directory,
              'Datos de la empresa',
              'Ingrese la información fiscal de su empresa o negocio.',
            ),
            const SizedBox(height: Spacing.lg),

            // ---- Tipo contribuyente — RadioGroup pattern ----
            InfoLabel(
              label: 'Tipo de contribuyente',
              child: Padding(
                padding: const EdgeInsets.only(top: Spacing.xs),
                child: RadioGroup<String>(
                  groupValue: _tipoContribuyente,
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _tipoContribuyente = value);
                    }
                  },
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RadioButton<String>(
                        value: _tipoSociedad,
                        content: Text('Sociedad / Empresa'),
                      ),
                      SizedBox(height: Spacing.sm),
                      RadioButton<String>(
                        value: _tipoPersonaNatural,
                        content: Text('Persona Natural'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: Spacing.md),

            // ---- Nombre legal ----
            PilarTextField(
              name: 'nombre',
              label: 'Nombre o razón social',
              required: true,
              controller: _nombreController,
              placeholder: _tipoContribuyente == _tipoSociedad
                  ? 'Ej: Comercial XYZ S.A.'
                  : 'Ej: Juan Pérez Gómez',
              prefix: const Padding(
                padding: EdgeInsets.only(left: Spacing.sm),
                child: Icon(FluentIcons.company_directory, size: 16),
              ),
            ),
            const SizedBox(height: Spacing.md),

            // ---- RUC / Cédula ----
            PilarTextField(
              name: 'ruc',
              label: _tipoContribuyente == _tipoSociedad
                  ? 'RUC (13 dígitos)'
                  : 'RUC o cédula de identidad',
              required: true,
              controller: _rucController,
              placeholder: _tipoContribuyente == _tipoSociedad
                  ? '0912345678001'
                  : '0912345678 o 0912345678001',
              keyboardType: TextInputType.number,
              prefix: const Padding(
                padding: EdgeInsets.only(left: Spacing.sm),
                child: Icon(FluentIcons.i_d_badge, size: 16),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) return null;
                final digits = value.trim().replaceAll(RegExp(r'\D'), '');
                if (_tipoContribuyente == _tipoSociedad && digits.length != 13) {
                  return 'El RUC debe tener 13 dígitos';
                }
                if (_tipoContribuyente == _tipoPersonaNatural &&
                    digits.length != 10 &&
                    digits.length != 13) {
                  return 'Ingrese una cédula (10 dígitos) o RUC (13 dígitos)';
                }
                return null;
              },
            ),
            const SizedBox(height: Spacing.md),

            // ---- Dirección ----
            PilarTextField(
              name: 'direccion',
              label: 'Dirección fiscal',
              controller: _direccionController,
              placeholder: 'Ej: Av. 9 de Octubre 123 y Malecón',
              prefix: const Padding(
                padding: EdgeInsets.only(left: Spacing.sm),
                child: Icon(FluentIcons.location, size: 16),
              ),
            ),
            const SizedBox(height: Spacing.md),

            // ---- Provincia ----
            InfoLabel(
              label: 'Provincia',
              child: ComboBox<String>(
                value: _provinciaSeleccionada,
                placeholder: const Text('Seleccione una provincia'),
                items: _provinciasEcuador
                    .map(
                      (p) => ComboBoxItem<String>(
                        value: p,
                        child: Text(p),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setState(() => _provinciaSeleccionada = value),
                isExpanded: true,
              ),
            ),
            const SizedBox(height: Spacing.xl),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Step 1 — Módulos
  // ---------------------------------------------------------------------------

  Widget _buildStepModulos() {
    final theme = FluentTheme.of(context);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionHeader(
            FluentIcons.app_icon_default,
            'Módulos del sistema',
            'Seleccione los módulos que desea activar. '
                'Puede cambiarlos después desde Administración.',
          ),
          const SizedBox(height: Spacing.lg),
          ..._availableModulos.map(
            (modulo) => _ModuloToggleCard(
              modulo: modulo,
              isSelected: _modulosSeleccionados.contains(modulo.id),
              onToggle: modulo.obligatorio
                  ? null
                  : (value) {
                      setState(() {
                        if (value) {
                          _modulosSeleccionados.add(modulo.id);
                        } else {
                          _modulosSeleccionados.remove(modulo.id);
                        }
                      });
                    },
              theme: theme,
            ),
          ),
          const SizedBox(height: Spacing.xl),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Step 2 — Equipo
  // ---------------------------------------------------------------------------

  Widget _buildStepEquipo() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionHeader(
            FluentIcons.people,
            'Invite a su equipo',
            'Agregue los colaboradores que trabajarán en PILAR. '
                'Este paso es opcional — puede hacerlo más tarde desde Administración.',
          ),
          const SizedBox(height: Spacing.lg),

          // ---- Invitation rows or empty hint ----
          if (_invitaciones.isEmpty)
            _buildEmptyEquipoHint()
          else
            ...List.generate(_invitaciones.length, (index) {
              return _InvitacionRow(
                key: ValueKey(index),
                emailController: _emailControllers[index],
                rolCodigo: _invitaciones[index].rolCodigo,
                onRolChanged: (rol) {
                  setState(() => _invitaciones[index].rolCodigo = rol);
                },
                onRemove: () {
                  setState(() {
                    _invitaciones.removeAt(index);
                    final controller = _emailControllers.removeAt(index);
                    controller.dispose();
                  });
                },
              );
            }),
          const SizedBox(height: Spacing.md),

          // ---- Add collaborator button ----
          Button(
            onPressed: _addInvitacion,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(FluentIcons.add_friend, size: 16),
                SizedBox(width: Spacing.sm),
                Text('Agregar colaborador'),
              ],
            ),
          ),
          const SizedBox(height: Spacing.xl),
        ],
      ),
    );
  }

  Widget _buildEmptyEquipoHint() {
    final theme = FluentTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: theme.resources.cardBackgroundFillColorDefault,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.resources.controlStrokeColorDefault),
      ),
      child: Column(
        children: [
          Icon(
            FluentIcons.people_add,
            size: 40,
            color: theme.resources.textFillColorSecondary,
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            'No hay colaboradores agregados',
            style: TextStyle(color: theme.resources.textFillColorSecondary),
          ),
          const SizedBox(height: Spacing.xs),
          Text(
            'Puede omitir este paso y agregar colaboradores más tarde.',
            style: TextStyle(
              fontSize: 12,
              color: theme.resources.textFillColorTertiary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _addInvitacion() {
    setState(() {
      _invitaciones.add(_InvitacionPendiente());
      _emailControllers.add(TextEditingController());
    });
  }

  // ---------------------------------------------------------------------------
  // Navigation buttons
  // ---------------------------------------------------------------------------

  Widget _buildNavButtons(FluentThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // ---- Back button (hidden on first step) ----
        if (_currentStep > 0)
          Button(
            onPressed: _isLoading
                ? null
                : () => setState(() {
                      _currentStep--;
                      _errorMessage = null;
                    }),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(FluentIcons.chevron_left, size: 14),
                SizedBox(width: Spacing.xs),
                Text('Atrás'),
              ],
            ),
          )
        else
          const SizedBox.shrink(),

        // ---- Skip (step 2 only) + Continue/Complete ----
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_currentStep == 2) ...[
              Button(
                onPressed: _isLoading ? null : _onComplete,
                child: const Text('Omitir e ingresar'),
              ),
              const SizedBox(width: Spacing.sm),
            ],
            if (_currentStep < 2)
              FilledButton(
                onPressed: _isLoading ? null : _onContinue,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Continuar'),
                    SizedBox(width: Spacing.xs),
                    Icon(FluentIcons.chevron_right, size: 14),
                  ],
                ),
              )
            else
              FilledButton(
                onPressed: _isLoading ? null : _onComplete,
                child: _isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: ProgressRing(strokeWidth: 2),
                      )
                    : const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(FluentIcons.check_mark, size: 14),
                          SizedBox(width: Spacing.xs),
                          Text('Completar configuración'),
                        ],
                      ),
              ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Wizard logic
  // ---------------------------------------------------------------------------

  Future<void> _onContinue() async {
    setState(() => _errorMessage = null);

    if (_currentStep == 0) {
      // Validate step 0 form — non-empty checks are handled by PilarTextField
      // with required:true; the form key catches RUC format errors.
      if (!(_formKeyEmpresa.currentState?.validate() ?? false)) return;
    }

    setState(() => _currentStep++);
  }

  Future<void> _onComplete() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final client = Supabase.instance.client;

      // ---- 1. Update empresa ----
      final params = <String, dynamic>{
        'p_nombre': _nombreController.text.trim(),
        'p_ruc': _rucController.text.trim(),
        'p_tipo_contribuyente': _tipoContribuyente,
        'p_direccion': _direccionController.text.trim(),
      };
      if (_provinciaSeleccionada != null) {
        params['p_provincia'] = _provinciaSeleccionada;
      }
      await client.rpc('admin_update_empresa', params: params);

      // ---- 2. Activate selected modules ----
      // 'facturacion' is obligatorio: the backend pre-activates it during
      // onboarding, so we only send the user-selected non-mandatory modules.
      final toActivate = _modulosSeleccionados
          .where((id) => id != 'facturacion')
          .toList();

      for (final moduloId in toActivate) {
        await client.rpc(
          'admin_activate_module',
          params: {'p_modulo_id': moduloId},
        );
      }

      // ---- 3. Send invitations ----
      for (int i = 0; i < _invitaciones.length; i++) {
        // Sync email from the TextEditingController back into the model.
        _invitaciones[i].email = _emailControllers[i].text.trim();

        if (_invitaciones[i].email.isNotEmpty) {
          await client.rpc('admin_invite_user', params: {
            'p_email': _invitaciones[i].email,
            'p_rol_codigo': _invitaciones[i].rolCodigo,
          });
        }
      }

      // ---- 4. Refresh session — new JWT includes updated empresa state ----
      await client.auth.refreshSession();

      if (mounted) {
        context.go(PilarRoutes.dashboard);
      }
    } on PostgrestException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Widget _buildSectionHeader(IconData icon, String title, String subtitle) {
    final theme = FluentTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: theme.accentColor),
            const SizedBox(width: Spacing.sm),
            Text(title, style: FluentTheme.of(context).typography.subtitle),
          ],
        ),
        const SizedBox(height: Spacing.xs),
        Padding(
          padding: const EdgeInsets.only(left: 28),
          child: Text(
            subtitle,
            style: TextStyle(
              fontSize: 13,
              color: theme.resources.textFillColorSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _ModuloToggleCard — module selection card with animated border
// ---------------------------------------------------------------------------

class _ModuloToggleCard extends StatelessWidget {
  const _ModuloToggleCard({
    required this.modulo,
    required this.isSelected,
    required this.theme,
    this.onToggle,
  });

  final _ModuloCard modulo;
  final bool isSelected;
  final FluentThemeData theme;

  /// Null when the card is locked (obligatorio = true).
  final void Function(bool)? onToggle;

  bool get _isLocked => onToggle == null;

  @override
  Widget build(BuildContext context) {
    final activeBg = theme.accentColor.withValues(alpha: 0.08);
    final defaultBg = theme.resources.cardBackgroundFillColorDefault;
    final activeBorder = theme.accentColor.withValues(alpha: 0.50);
    final defaultBorder = theme.resources.controlStrokeColorDefault;

    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: GestureDetector(
        onTap: _isLocked ? null : () => onToggle!(!isSelected),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.md,
          ),
          decoration: BoxDecoration(
            color: isSelected ? activeBg : defaultBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? activeBorder : defaultBorder,
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            children: [
              // ---- Module icon container ----
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isSelected
                      ? theme.accentColor.withValues(alpha: 0.15)
                      : theme.resources.subtleFillColorSecondary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  modulo.icono,
                  size: 20,
                  color: isSelected
                      ? theme.accentColor
                      : theme.resources.textFillColorSecondary,
                ),
              ),
              const SizedBox(width: Spacing.md),

              // ---- Name + description ----
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          modulo.nombre,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: theme.resources.textFillColorPrimary,
                          ),
                        ),
                        if (_isLocked) ...[
                          const SizedBox(width: Spacing.xs),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: theme.accentColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Obligatorio',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: theme.accentColor,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      modulo.desc,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.resources.textFillColorSecondary,
                      ),
                    ),
                  ],
                ),
              ),

              // ---- Toggle switch (disabled for locked modules) ----
              ToggleSwitch(
                checked: isSelected,
                onChanged: _isLocked ? null : onToggle,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _InvitacionRow — one row per invited collaborator
// ---------------------------------------------------------------------------

class _InvitacionRow extends StatelessWidget {
  const _InvitacionRow({
    super.key,
    required this.emailController,
    required this.rolCodigo,
    required this.onRolChanged,
    required this.onRemove,
  });

  final TextEditingController emailController;
  final String rolCodigo;
  final void Function(String) onRolChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Container(
        padding: const EdgeInsets.all(Spacing.md),
        decoration: BoxDecoration(
          color: theme.resources.cardBackgroundFillColorDefault,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.resources.controlStrokeColorDefault),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---- Email field ----
            Expanded(
              flex: 5,
              child: InfoLabel(
                label: 'Correo electrónico',
                child: TextFormBox(
                  controller: emailController,
                  placeholder: 'colaborador@empresa.com',
                  keyboardType: TextInputType.emailAddress,
                  prefix: const Padding(
                    padding: EdgeInsets.only(left: Spacing.sm),
                    child: Icon(FluentIcons.mail, size: 14),
                  ),
                ),
              ),
            ),
            const SizedBox(width: Spacing.md),

            // ---- Rol picker ----
            Expanded(
              flex: 3,
              child: InfoLabel(
                label: 'Rol',
                child: ComboBox<String>(
                  value: rolCodigo,
                  items: _rolesDisponibles
                      .map(
                        (r) => ComboBoxItem<String>(
                          value: r.$1,
                          child: Text(r.$2),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) onRolChanged(v);
                  },
                  isExpanded: true,
                ),
              ),
            ),
            const SizedBox(width: Spacing.sm),

            // ---- Remove button — aligned to the input row ----
            Padding(
              padding: const EdgeInsets.only(top: 22),
              child: IconButton(
                icon: const Icon(FluentIcons.delete, size: 16),
                onPressed: onRemove,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
