import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:fluent_ui_reactive/fluent_ui_reactive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/empresa_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/config/pilar_constants.dart';
import '../../../core/theme/pilar_spacing.dart';
import '../../../core/utils/ecuador_geo_provider.dart';
import '../../../core/widgets/loading_spinner.dart';
import '../../../features/administracion/providers/admin_providers.dart';
import '../../../features/administracion/providers/empresa_write_provider.dart';

// ---------------------------------------------------------------------------
// Data models
// ---------------------------------------------------------------------------

class _InvitacionPendiente {
  _InvitacionPendiente();

  String email = '';
  String rolCodigo = 'LECTURA';
}

// ---------------------------------------------------------------------------
// Roles fallback (used while rolesProvider is loading)
// ---------------------------------------------------------------------------

const _rolesFallback = [
  ('ADMIN', 'Administrador'),
  ('CONTADOR', 'Contador'),
  ('VENDEDOR', 'Vendedor'),
  ('BODEGUERO', 'Bodeguero'),
  ('LECTURA', 'Solo lectura'),
];

const _tipoSociedad = 'sociedad';
const _tipoPersonaNatural = 'persona_natural';

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

/// Wizard de configuración inicial mostrado cuando la empresa es un placeholder.
///
/// Pasos:
///   0 — Datos de empresa (nombre, RUC, tipo, dirección, provincia, ciudad, logo)
///   1 — Comunicación (email, teléfono, WhatsApp, Telegram)
///   2 — Equipo (invitaciones — opcional)
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
  int? _provinciaId;
  int? _ciudadId;

  // Logo
  String? _logoUploadedUrl; // URL after successful upload
  bool _logoUploading = false;
  String? _logoFileName;

  // ---- Step 1 — Comunicación ----
  final _emailController = TextEditingController();
  final _telefonoController = TextEditingController();
  final _whatsappController = TextEditingController();
  final _telegramController = TextEditingController();

  // ---- Step 2 — Equipo ----
  final List<_InvitacionPendiente> _invitaciones = [];
  final List<TextEditingController> _emailInvControllers = [];

  @override
  void initState() {
    super.initState();
    // Pre-fill company email with the authenticated user's email.
    final userEmail =
        Supabase.instance.client.auth.currentUser?.email ?? '';
    _emailController.text = userEmail;
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _rucController.dispose();
    _direccionController.dispose();
    _emailController.dispose();
    _telefonoController.dispose();
    _whatsappController.dispose();
    _telegramController.dispose();
    for (final c in _emailInvControllers) {
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
        title: const Text('Bienvenido a $kAppName'),
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
  // Step indicator
  // ---------------------------------------------------------------------------

  static const _stepTitles = ['Empresa', 'Comunicación', 'Equipo'];

  Widget _buildStepIndicator(FluentThemeData theme) {
    final itemCount = _stepTitles.length;

    return Row(
      children: List.generate(itemCount * 2 - 1, (i) {
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
        final iconOrLabelColor = (isActive || isCompleted)
            ? Colors.white
            : theme.resources.textFillColorPrimary;

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
                    ? Icon(FluentIcons.check_mark,
                        size: 14, color: iconOrLabelColor)
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
        return _buildStepComunicacion();
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
    final theme = FluentTheme.of(context);
    final provinciasAsync = ref.watch(provinciasEcProvider);
    final ciudadesAsync = _provinciaId != null
        ? ref.watch(ciudadesPorProvinciaProvider(_provinciaId!))
        : null;
    final provincias = provinciasAsync.valueOrNull ?? <EcuadorProvincia>[];
    final ciudades = ciudadesAsync?.valueOrNull ?? <EcuadorCiudad>[];

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

            // ---- Tipo contribuyente ----
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
                final digits =
                    value.trim().replaceAll(RegExp(r'\D'), '');
                if (_tipoContribuyente == _tipoSociedad &&
                    digits.length != 13) {
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

            // ---- Provincia + Ciudad (row) ----
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: InfoLabel(
                    label: 'Provincia',
                    child: ComboBox<int>(
                      value: _provinciaId,
                      placeholder: provinciasAsync.isLoading
                          ? const Text('Cargando...')
                          : const Text('Seleccione'),
                      items: provincias
                          .map((p) => ComboBoxItem<int>(
                                value: p.id,
                                child: Text(p.nombre),
                              ))
                          .toList(),
                      onChanged: provinciasAsync.isLoading
                          ? null
                          : (value) => setState(() {
                                _provinciaId = value;
                                _ciudadId = null;
                              }),
                      isExpanded: true,
                    ),
                  ),
                ),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: InfoLabel(
                    label: 'Ciudad',
                    child: ComboBox<int>(
                      value: _ciudadId,
                      placeholder: Text(
                        _provinciaId == null
                            ? 'Seleccione provincia primero'
                            : ciudadesAsync?.isLoading == true
                                ? 'Cargando...'
                                : 'Seleccione ciudad',
                      ),
                      items: ciudades
                          .map((c) => ComboBoxItem<int>(
                                value: c.id,
                                child: Text(c.nombre),
                              ))
                          .toList(),
                      onChanged: (_provinciaId == null ||
                              ciudadesAsync?.isLoading == true)
                          ? null
                          : (value) =>
                              setState(() => _ciudadId = value),
                      isExpanded: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.lg),

            // ---- Logo ----
            _buildSectionHeader(
              FluentIcons.image_pixel,
              'Logo de la empresa',
              'Sube el logo que aparecerá en documentos y el encabezado del ERP.',
            ),
            const SizedBox(height: Spacing.md),
            _buildLogoSection(theme),
            const SizedBox(height: Spacing.xl),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoSection(FluentThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: theme.resources.cardBackgroundFillColorDefault,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.resources.controlStrokeColorDefault),
      ),
      child: Row(
        children: [
          // Preview area
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: theme.resources.subtleFillColorSecondary,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: theme.resources.controlStrokeColorDefault),
            ),
            child: _logoUploadedUrl != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: Image.network(
                      _logoUploadedUrl!,
                      fit: BoxFit.contain,
                    ),
                  )
                : Icon(
                    FluentIcons.image_pixel,
                    size: 28,
                    color: theme.resources.textFillColorTertiary,
                  ),
          ),
          const SizedBox(width: Spacing.md),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_logoFileName != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Spacing.xs),
                    child: Text(
                      _logoFileName!,
                      style: theme.typography.caption,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (_logoUploadedUrl != null)
                  const Padding(
                    padding: EdgeInsets.only(bottom: Spacing.xs),
                    child: Row(
                      children: [
                        Icon(FluentIcons.check_mark,
                            size: 12, color: Colors.successPrimaryColor),
                        SizedBox(width: Spacing.xs),
                        Text(
                          'Logo subido correctamente',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.successPrimaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                Text(
                  'Formatos: PNG, JPG, WebP, SVG. Máx. 5 MB.',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.resources.textFillColorSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Spacing.md),

          // Upload / change button
          _logoUploading
              ? const PilarProgressRing(size: 20)
              : Button(
                  onPressed: _pickAndUploadLogo,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(FluentIcons.upload, size: 14),
                      const SizedBox(width: Spacing.xs),
                      Text(_logoUploadedUrl == null
                          ? 'Seleccionar'
                          : 'Cambiar'),
                    ],
                  ),
                ),
        ],
      ),
    );
  }

  Future<void> _pickAndUploadLogo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'svg'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.bytes == null) return;

    final empresaId = ref.read(empresaActivaIdProvider);
    if (empresaId == null) {
      setState(() => _errorMessage = 'No se pudo obtener el ID de empresa.');
      return;
    }

    setState(() {
      _logoUploading = true;
      _logoFileName = file.name;
      _errorMessage = null;
    });

    try {
      final ext = file.extension ?? 'png';

      final url = await ref.read(empresaWriteProvider.notifier).uploadLogo(
            bytes: file.bytes!,
            ext: ext,
            empresaId: empresaId,
          );
      setState(() => _logoUploadedUrl = url);
    } on StorageException catch (e) {
      setState(() => _errorMessage = 'Error al subir logo: ${e.message}');
    } catch (e) {
      setState(() => _errorMessage = 'Error al subir logo: $e');
    } finally {
      setState(() => _logoUploading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Step 1 — Comunicación
  // ---------------------------------------------------------------------------

  Widget _buildStepComunicacion() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionHeader(
            FluentIcons.mail,
            'Parámetros de comunicación',
            'Configure los canales por los que PILAR enviará notificaciones y '
                'se comunicará con sus clientes. Todos los campos son opcionales.',
          ),
          const SizedBox(height: Spacing.lg),

          // ---- Email ----
          PilarTextField(
            name: 'email',
            label: 'Correo electrónico empresarial',
            controller: _emailController,
            placeholder: 'contacto@miempresa.com',
            keyboardType: TextInputType.emailAddress,
            prefix: const Padding(
              padding: EdgeInsets.only(left: Spacing.sm),
              child: Icon(FluentIcons.mail, size: 16),
            ),
          ),
          const SizedBox(height: Spacing.md),

          // ---- Teléfono ----
          PilarTextField(
            name: 'telefono',
            label: 'Teléfono',
            controller: _telefonoController,
            placeholder: '+593 99 123 4567',
            keyboardType: TextInputType.phone,
            prefix: const Padding(
              padding: EdgeInsets.only(left: Spacing.sm),
              child: Icon(FluentIcons.phone, size: 16),
            ),
          ),
          const SizedBox(height: Spacing.lg),

          _buildSectionHeader(
            FluentIcons.chat,
            'Mensajería instantánea',
            'Integre WhatsApp Business y Telegram para enviar notificaciones '
                'automáticas a clientes y su equipo.',
          ),
          const SizedBox(height: Spacing.md),

          // ---- WhatsApp ----
          PilarTextField(
            name: 'whatsapp',
            label: 'WhatsApp Business (número)',
            controller: _whatsappController,
            placeholder: '+593 99 123 4567',
            keyboardType: TextInputType.phone,
            prefix: const Padding(
              padding: EdgeInsets.only(left: Spacing.sm),
              child: Icon(FluentIcons.device_run, size: 16),
            ),
          ),
          const SizedBox(height: Spacing.md),

          // ---- Telegram ----
          PilarTextField(
            name: 'telegram',
            label: 'Telegram (canal o ID de chat)',
            controller: _telegramController,
            placeholder: '@miempresa o -100123456789',
            prefix: const Padding(
              padding: EdgeInsets.only(left: Spacing.sm),
              child: Icon(FluentIcons.send, size: 16),
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
    final rolesAsync = ref.watch(rolesProvider);
    final roles = rolesAsync.valueOrNull ?? const [];

    // Build ComboBox items: prefer live roles, fall back to static list
    final roleItems = roles.isNotEmpty
        ? roles
            .map((r) => (r.codigo, r.nombre))
            .toList()
        : _rolesFallback.toList();

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

          if (_invitaciones.isEmpty)
            _buildEmptyEquipoHint()
          else
            ...List.generate(_invitaciones.length, (index) {
              return _InvitacionRow(
                key: ValueKey(index),
                emailController: _emailInvControllers[index],
                rolCodigo: _invitaciones[index].rolCodigo,
                roleItems: roleItems,
                onRolChanged: (rol) {
                  setState(() => _invitaciones[index].rolCodigo = rol);
                },
                onRemove: () {
                  setState(() {
                    _invitaciones.removeAt(index);
                    final c = _emailInvControllers.removeAt(index);
                    c.dispose();
                  });
                },
              );
            }),
          const SizedBox(height: Spacing.md),

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
            style: TextStyle(
                color: theme.resources.textFillColorSecondary),
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
      _emailInvControllers.add(TextEditingController());
    });
  }

  // ---------------------------------------------------------------------------
  // Navigation buttons
  // ---------------------------------------------------------------------------

  Widget _buildNavButtons(FluentThemeData theme) {
    final isLastStep = _currentStep == 2;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
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

        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLastStep) ...[
              Button(
                onPressed: _isLoading ? null : _onComplete,
                child: const Text('Omitir e ingresar'),
              ),
              const SizedBox(width: Spacing.sm),
            ],
            if (!isLastStep)
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
                    ? const PilarProgressRing.small()
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
      // ---- 1. Update empresa (nombre, RUC, tipo, dirección, geo, logo) ----
      final empresaData = <String, dynamic>{
        'nombre': _nombreController.text.trim(),
        'ruc': _rucController.text.trim(),
        'tipo_ruc': _tipoContribuyente,
        'direccion': _direccionController.text.trim(),
      };
      if (_provinciaId != null) {
        empresaData['provincia_id'] = _provinciaId;
      }
      if (_ciudadId != null) {
        empresaData['ciudad_id'] = _ciudadId;
      }
      if (_logoUploadedUrl != null) {
        empresaData['logo_url'] = _logoUploadedUrl;
      }
      // Communication fields that live directly on the empresas table
      final email = _emailController.text.trim();
      final telefono = _telefonoController.text.trim();
      if (email.isNotEmpty) empresaData['email'] = email;
      if (telefono.isNotEmpty) empresaData['telefono'] = telefono;

      await ref
          .read(empresaWriteProvider.notifier)
          .updateEmpresa(params: empresaData);

      // ---- 2. Update communication config_extra (WhatsApp, Telegram) ----
      final whatsapp = _whatsappController.text.trim();
      final telegram = _telegramController.text.trim();
      if (whatsapp.isNotEmpty || telegram.isNotEmpty) {
        final configData = <String, dynamic>{};
        if (whatsapp.isNotEmpty) configData['whatsapp_numero'] = whatsapp;
        if (telegram.isNotEmpty) configData['telegram_id'] = telegram;

        await ref
            .read(empresaWriteProvider.notifier)
            .updateConfigExtra(params: configData);
      }

      // ---- 3. Send team invitations ----
      final roles = ref.read(rolesProvider).valueOrNull ?? [];
      for (int i = 0; i < _invitaciones.length; i++) {
        _invitaciones[i].email = _emailInvControllers[i].text.trim();
        if (_invitaciones[i].email.isNotEmpty) {
          final rol = roles.firstWhere(
            (r) => r.codigo == _invitaciones[i].rolCodigo,
            orElse: () =>
                throw Exception('Rol "${_invitaciones[i].rolCodigo}" no encontrado'),
          );
          await ref.read(empresaWriteProvider.notifier).inviteUser(
            body: {
              'email': _invitaciones[i].email,
              'rol_id': rol.id,
            },
          );
        }
      }

      // ---- 4. Refresh session ----
      await ref.read(supabaseClientProvider).auth.refreshSession();

      if (mounted) {
        context.go(PilarRoutes.dashboard);
      }
    } on PostgrestException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Widget _buildSectionHeader(
      IconData icon, String title, String subtitle) {
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
          padding: const EdgeInsets.only(left: Spacing.lg),
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
// _InvitacionRow
// ---------------------------------------------------------------------------

class _InvitacionRow extends StatelessWidget {
  const _InvitacionRow({
    super.key,
    required this.emailController,
    required this.rolCodigo,
    required this.roleItems,
    required this.onRolChanged,
    required this.onRemove,
  });

  final TextEditingController emailController;
  final String rolCodigo;

  /// List of (codigo, nombre) tuples for the role ComboBox.
  final List<(String, String)> roleItems;

  final void Function(String) onRolChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    // Ensure current rolCodigo is in items; if not, pick first available.
    final validCodigo = roleItems.any((r) => r.$1 == rolCodigo)
        ? rolCodigo
        : (roleItems.isNotEmpty ? roleItems.first.$1 : rolCodigo);

    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Container(
        padding: const EdgeInsets.all(Spacing.md),
        decoration: BoxDecoration(
          color: theme.resources.cardBackgroundFillColorDefault,
          borderRadius: BorderRadius.circular(8),
          border:
              Border.all(color: theme.resources.controlStrokeColorDefault),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    final e = v.trim();
                    if (!e.contains('@') || !e.contains('.')) {
                      return 'Ingresa un correo válido';
                    }
                    return null;
                  },
                ),
              ),
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              flex: 3,
              child: InfoLabel(
                label: 'Rol',
                child: ComboBox<String>(
                  value: validCodigo,
                  items: roleItems
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
            Padding(
              padding: const EdgeInsets.only(top: Spacing.ml),
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
