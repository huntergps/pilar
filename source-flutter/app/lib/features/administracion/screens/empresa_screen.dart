import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluent_ui_reactive/fluent_ui_reactive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/empresa_provider.dart';
import '../../../core/providers/usuario_provider.dart';

// ---------------------------------------------------------------------------
// Geographic catalog (Ecuador SRI — static)
// ---------------------------------------------------------------------------

// (id, nombre)
const _provincias = [
  (1, 'Azuay'),
  (2, 'Bolívar'),
  (3, 'Cañar'),
  (4, 'Carchi'),
  (5, 'Cotopaxi'),
  (6, 'Chimborazo'),
  (7, 'El Oro'),
  (8, 'Esmeraldas'),
  (9, 'Guayas'),
  (10, 'Imbabura'),
  (11, 'Loja'),
  (12, 'Los Ríos'),
  (13, 'Manabí'),
  (14, 'Morona Santiago'),
  (15, 'Napo'),
  (16, 'Pastaza'),
  (17, 'Pichincha'),
  (18, 'Tungurahua'),
  (19, 'Zamora Chinchipe'),
  (20, 'Galápagos'),
  (21, 'Sucumbíos'),
  (22, 'Orellana'),
  (23, 'Santo Domingo de los Tsáchilas'),
  (24, 'Santa Elena'),
];

// (id, nombre, provinciaId)
const _ciudades = [
  (101, 'Cuenca', 1),
  (201, 'Guaranda', 2),
  (301, 'Azogues', 3),
  (401, 'Tulcán', 4),
  (501, 'Latacunga', 5),
  (601, 'Riobamba', 6),
  (701, 'Machala', 7),
  (801, 'Esmeraldas', 8),
  (901, 'Guayaquil', 9),
  (1001, 'Ibarra', 10),
  (1101, 'Loja', 11),
  (1201, 'Babahoyo', 12),
  (1301, 'Portoviejo', 13),
  (1401, 'Macas', 14),
  (1501, 'Tena', 15),
  (1601, 'Puyo', 16),
  (1701, 'Quito', 17),
  (1702, 'Cayambe', 17),
  (1703, 'Rumiñahui', 17),
  (1801, 'Ambato', 18),
  (1901, 'Zamora', 19),
  (2001, 'Puerto Baquerizo Moreno', 20),
  (2002, 'Puerto Ayora', 20),           // cantón Santa Cruz
  (2003, 'Puerto Villamil', 20),        // cantón Isabela
  (2101, 'Nueva Loja (Lago Agrio)', 21),
  (2201, 'Puerto Francisco de Orellana', 22),
  (2301, 'Santo Domingo', 23),
  (2401, 'Santa Elena', 24),
];

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

/// Pantalla de configuración de la empresa activa.
///
/// Permite editar los datos principales (nombre, RUC, nombre comercial,
/// dirección, teléfono, email, web, provincia, ciudad, logo) usando
/// [PilarForm] y [PilarTextField].
///
/// Los cambios se guardan vía el RPC `admin_update_empresa`.
class EmpresaScreen extends ConsumerStatefulWidget {
  const EmpresaScreen({super.key});

  @override
  ConsumerState<EmpresaScreen> createState() => _EmpresaScreenState();
}

class _EmpresaScreenState extends ConsumerState<EmpresaScreen> {
  // PilarTextField onSaved values
  String? _nombre;
  String? _nombreComercial;
  String? _direccion;
  String? _telefono;
  String? _email;
  String? _web;

  // Tipo RUC
  String? _tipoRuc;

  // Geographic selectors
  bool _initialized = false;
  int? _provinciaId;
  int? _ciudadId;

  // Logo
  String? _logoUrl;
  bool _logoUploading = false;
  String? _logoFileName;

  // Branding
  final _colorPrimCtrl = TextEditingController();
  AccentColor? _selectedPrimario;
  // Último color guardado exitosamente en BD. Controla si "Aplicar a todos" está activo.
  String? _colorSavedInDb;

  @override
  void dispose() {
    _colorPrimCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Save handlers
  // ---------------------------------------------------------------------------

  Future<void> _handleSave() async {
    final data = <String, dynamic>{};
    if (_nombre != null)          data['nombre']          = _nombre;
    if (_nombreComercial != null) data['nombre_comercial'] = _nombreComercial;
    if (_direccion != null)       data['direccion']        = _direccion;
    if (_telefono != null)        data['telefono']         = _telefono;
    if (_email != null)           data['email']            = _email;
    if (_web != null)             data['web']              = _web;
    if (_tipoRuc != null)         data['tipo_ruc']         = _tipoRuc;
    if (_provinciaId != null)     data['provincia_id']     = _provinciaId;
    if (_ciudadId != null)        data['ciudad_id']        = _ciudadId;
    if (_logoUrl != null)         data['logo_url']         = _logoUrl;

    final color = _colorPrimCtrl.text.trim();

    if (data.isEmpty && color.isEmpty) return;

    bool ok = true;

    // ── Datos principales ──────────────────────────────────────────────────
    if (data.isNotEmpty) {
      final result = await Supabase.instance.client.rpc(
        'admin_update_empresa',
        params: {'p_data': data},
      );
      if (result is! Map || result['ok'] != true) {
        ok = false;
        if (mounted) {
          displayInfoBar(
            context,
            builder: (_, close) => InfoBar(
              title: const Text('Error al guardar datos de empresa'),
              content: Text(result?['error']?.toString() ?? 'Error desconocido'),
              severity: InfoBarSeverity.error,
              onClose: close,
            ),
          );
        }
      }
    }

    // ── Color primario ─────────────────────────────────────────────────────
    if (color.isNotEmpty) {
      final result = await Supabase.instance.client.rpc(
        'admin_update_branding',
        params: {'p_data': {'color_primario': color}},
      );
      if (result is Map && result['ok'] == true) {
        setState(() => _colorSavedInDb = color);
      } else {
        ok = false;
        if (mounted) {
          displayInfoBar(
            context,
            builder: (_, close) => InfoBar(
              title: const Text('Error al guardar color'),
              content: Text(result?['error']?.toString() ?? 'Error desconocido'),
              severity: InfoBarSeverity.error,
              onClose: close,
            ),
          );
        }
      }
    }

    if (ok) {
      ref.invalidate(empresaConfigProvider);
      if (mounted) {
        displayInfoBar(
          context,
          builder: (_, close) => InfoBar(
            title: const Text('Datos guardados correctamente'),
            severity: InfoBarSeverity.success,
            onClose: close,
          ),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Logo upload
  // ---------------------------------------------------------------------------

  Future<void> _pickAndUploadLogo(String empresaId) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'svg'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.bytes == null) return;

    setState(() {
      _logoUploading = true;
      _logoFileName = file.name;
    });

    try {
      final ext = file.extension ?? 'png';
      final path = '$empresaId/logo.$ext';
      final client = Supabase.instance.client;

      await client.storage.from('logos').uploadBinary(
            path,
            file.bytes!,
            fileOptions: FileOptions(upsert: true, contentType: 'image/$ext'),
          );

      final url = client.storage.from('logos').getPublicUrl(path);

      // Limpiar caché de imágenes de Flutter (la URL es idéntica tras upsert,
      // sin esto todas las pantallas siguen mostrando el logo anterior).
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();

      // Cache-buster para forzar recarga en Image.network (no se guarda en BD)
      final bustUrl = '$url?t=${DateTime.now().millisecondsSinceEpoch}';
      setState(() => _logoUrl = bustUrl);

      // Persist clean URL (sin cache-buster) en BD
      await client.rpc('admin_update_empresa',
          params: {'p_data': {'logo_url': url}});
      ref.invalidate(empresaConfigProvider);
    } on StorageException catch (e) {
      if (mounted) {
        displayInfoBar(
          context,
          builder: (_, close) => InfoBar(
            title: const Text('Error al subir logo'),
            content: Text(e.message),
            severity: InfoBarSeverity.error,
            onClose: close,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _logoUploading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final puedeEditar =
        ref.watch(hasPermissionProvider('administracion.empresa.editar'));
    final empresaAsync = ref.watch(empresaConfigProvider);
    final theme = FluentTheme.of(context);

    return ScaffoldPage(
      header: PageHeader(
        title: const Text('Empresa'),
        commandBar: puedeEditar
            ? CommandBar(
                mainAxisAlignment: MainAxisAlignment.end,
                primaryItems: [
                  CommandBarButton(
                    icon: const Icon(FluentIcons.save),
                    label: const Text('Guardar'),
                    onPressed: _handleSave,
                  ),
                ],
              )
            : null,
      ),
      content: PilarAsyncBuilder<EmpresaConfig?>(
        value: empresaAsync,
        builder: (context, empresa) {
          if (empresa == null) {
            return const Center(child: Text('Sin empresa activa'));
          }

          // Initialize state once from loaded data
          if (!_initialized) {
            _initialized = true;
            _tipoRuc = empresa.tipoRuc;
            _provinciaId = empresa.provinciaId;
            _ciudadId = empresa.ciudadId;
            _logoUrl = empresa.logoUrl;
            _colorPrimCtrl.text = empresa.colorPrimario ?? '';
            _colorSavedInDb = empresa.colorPrimario;
          }

          final ciudadesFiltradas = _provinciaId == null
              ? <(int, String, int)>[]
              : _ciudades
                  .where((c) => c.$3 == _provinciaId)
                  .toList()
                ..sort((a, b) => a.$2.compareTo(b.$2));

          // --- Form sections using FormSection ---
          final datosEmpresaSection = FormSection(
            title: 'Datos de la empresa',
            children: [
              if (!puedeEditar) ...[
                const InfoBar(
                  title: Text('Solo lectura'),
                  content: Text(
                      'Solo los administradores pueden editar los datos de la empresa.'),
                  severity: InfoBarSeverity.info,
                ),
              ],
              PilarTextField(
                name: 'nombre',
                label: 'Nombre de empresa',
                initialValue: empresa.nombre,
                required: true,
                readOnly: !puedeEditar,
                onSaved: (v) => _nombre = v,
              ),
              PilarTextField(
                name: 'nombre_comercial',
                label: 'Nombre comercial',
                initialValue: empresa.nombreComercial,
                readOnly: !puedeEditar,
                onSaved: (v) => _nombreComercial = v,
              ),
              PilarTextField(
                name: 'ruc',
                label: 'RUC / Cédula',
                initialValue: empresa.ruc,
                readOnly: true,
                infoMessage: 'El RUC no puede modificarse una vez registrado.',
              ),
              InfoLabel(
                label: 'Tipo de contribuyente',
                child: RadioGroup<String>(
                  groupValue: _tipoRuc ?? '',
                  onChanged: (v) {
                    if (puedeEditar) {
                      setState(() => _tipoRuc = v ?? _tipoRuc);
                    }
                  },
                  child: const Row(
                    children: [
                      RadioButton<String>(
                        value: 'sociedad',
                        content: Text('Sociedad'),
                      ),
                      SizedBox(width: 24),
                      RadioButton<String>(
                        value: 'persona_natural',
                        content: Text('Persona natural'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );

          final ubicacionSection = FormSection(
            title: 'Ubicacion',
            children: [
              PilarTextField(
                name: 'direccion',
                label: 'Direccion',
                initialValue: empresa.direccion,
                maxLines: 2,
                readOnly: !puedeEditar,
                onSaved: (v) => _direccion = v,
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: InfoLabel(
                      label: 'Provincia',
                      child: ComboBox<int>(
                        value: _provinciaId,
                        placeholder: const Text('Seleccione'),
                        items: _provincias
                            .map((p) => ComboBoxItem<int>(
                                  value: p.$1,
                                  child: Text(p.$2),
                                ))
                            .toList(),
                        onChanged: puedeEditar
                            ? (value) => setState(() {
                                  _provinciaId = value;
                                  _ciudadId = null;
                                })
                            : null,
                        isExpanded: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InfoLabel(
                      label: 'Ciudad',
                      child: ComboBox<int>(
                        value: _ciudadId,
                        placeholder: Text(
                          _provinciaId == null
                              ? 'Seleccione provincia primero'
                              : 'Seleccione ciudad',
                        ),
                        items: ciudadesFiltradas
                            .map((c) => ComboBoxItem<int>(
                                  value: c.$1,
                                  child: Text(c.$2),
                                ))
                            .toList(),
                        onChanged: (!puedeEditar || ciudadesFiltradas.isEmpty)
                            ? null
                            : (value) =>
                                setState(() => _ciudadId = value),
                        isExpanded: true,
                      ),
                    ),
                  ),
                ],
              ),
              PilarTextField(
                name: 'telefono',
                label: 'Telefono',
                initialValue: empresa.telefono,
                keyboardType: TextInputType.phone,
                readOnly: !puedeEditar,
                onSaved: (v) => _telefono = v,
              ),
              PilarTextField(
                name: 'email',
                label: 'Email',
                initialValue: (empresa.email?.isNotEmpty == true)
                    ? empresa.email
                    : Supabase.instance.client.auth.currentUser?.email,
                keyboardType: TextInputType.emailAddress,
                readOnly: !puedeEditar,
                onSaved: (v) => _email = v,
              ),
              PilarTextField(
                name: 'web',
                label: 'Sitio web',
                initialValue: empresa.web,
                keyboardType: TextInputType.url,
                readOnly: !puedeEditar,
                onSaved: (v) => _web = v,
              ),
            ],
          );

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final formSections = Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        datosEmpresaSection,
                        const SizedBox(height: 24),
                        ubicacionSection,
                      ],
                    );

                    // ---- Mobile (< 600 px): logo arriba, formulario abajo ----
                    if (constraints.maxWidth < 600) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildLogoMobile(theme, empresa.empresaId, puedeEditar),
                          const SizedBox(height: 24),
                          formSections,
                        ],
                      );
                    }

                    // ---- Desktop / tablet (>= 600 px): logo izquierda, form derecha ----
                    return ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 860),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 160,
                            child: _buildLogoDesktop(
                                theme, empresa.empresaId, puedeEditar),
                          ),
                          const SizedBox(width: 28),
                          Expanded(child: formSections),
                        ],
                      ),
                    );
                  },
                ),

                // ---- Seccion de branding (solo admins) ----
                if (puedeEditar) ...[
                  const SizedBox(height: 32),
                  _EmpresaBrandingSection(
                    colorPrimCtrl:    _colorPrimCtrl,
                    selectedPrimario: _selectedPrimario,
                    savedColor:       _colorSavedInDb,
                    onPrimarioChanged: (c) {
                      setState(() => _selectedPrimario = c);
                      _colorPrimCtrl.text = c != null
                          ? '#${c.toARGB32().toRadixString(16).substring(2).toUpperCase()}'
                          : '';
                    },
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  // ---- Logo: columna vertical para desktop (≥ 600 px) ----------------------

  Widget _buildLogoDesktop(
      FluentThemeData theme, String empresaId, bool puedeEditar) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Logo de empresa', style: theme.typography.bodyStrong),
        const SizedBox(height: 12),

        // Square preview — fills the 160 px column width
        AspectRatio(
          aspectRatio: 1,
          child: Container(
            decoration: BoxDecoration(
              color: theme.resources.cardBackgroundFillColorDefault,
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: theme.resources.controlStrokeColorDefault),
            ),
            child: _logoUrl != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: Image.network(
                      _logoUrl!,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Icon(
                        FluentIcons.image_pixel,
                        size: 40,
                        color: theme.resources.textFillColorTertiary,
                      ),
                    ),
                  )
                : Icon(
                    FluentIcons.image_pixel,
                    size: 40,
                    color: theme.resources.textFillColorTertiary,
                  ),
          ),
        ),
        const SizedBox(height: 8),

        if (_logoUrl != null) ...[
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(FluentIcons.check_mark,
                  size: 11, color: Colors.successPrimaryColor),
              SizedBox(width: 4),
              Text(
                'Logo cargado',
                style:
                    TextStyle(fontSize: 11, color: Colors.successPrimaryColor),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],

        if (puedeEditar)
          _logoUploading
              ? const Center(
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: ProgressRing(strokeWidth: 2)),
                )
              : Button(
                  onPressed: () => _pickAndUploadLogo(empresaId),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(FluentIcons.upload, size: 14),
                      const SizedBox(width: 6),
                      Text(_logoUrl == null ? 'Seleccionar' : 'Cambiar'),
                    ],
                  ),
                ),
        const SizedBox(height: 8),
        Text(
          'PNG, JPG, WebP, SVG\nMáx. 5 MB',
          style: TextStyle(
              fontSize: 11,
              color: theme.resources.textFillColorSecondary),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  // ---- Logo: fila horizontal para móvil (< 600 px) -----------------------

  Widget _buildLogoMobile(
      FluentThemeData theme, String empresaId, bool puedeEditar) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Logo de empresa', style: theme.typography.bodyStrong),
        const SizedBox(height: 4),
        const Divider(),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.resources.cardBackgroundFillColorDefault,
            borderRadius: BorderRadius.circular(8),
            border:
                Border.all(color: theme.resources.controlStrokeColorDefault),
          ),
          child: Row(
            children: [
              // Square preview 72 × 72
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: theme.resources.subtleFillColorSecondary,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: theme.resources.controlStrokeColorDefault),
                ),
                child: _logoUrl != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: Image.network(
                          _logoUrl!,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Icon(
                            FluentIcons.image_pixel,
                            size: 28,
                            color: theme.resources.textFillColorTertiary,
                          ),
                        ),
                      )
                    : Icon(
                        FluentIcons.image_pixel,
                        size: 28,
                        color: theme.resources.textFillColorTertiary,
                      ),
              ),
              const SizedBox(width: 16),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_logoFileName != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          _logoFileName!,
                          style: theme.typography.caption,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    if (_logoUrl != null)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Icon(FluentIcons.check_mark,
                                size: 12,
                                color: Colors.successPrimaryColor),
                            SizedBox(width: 4),
                            Text(
                              'Logo cargado',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.successPrimaryColor),
                            ),
                          ],
                        ),
                      ),
                    Text(
                      'PNG, JPG, WebP, SVG. Máx. 5 MB.',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.resources.textFillColorSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),

              if (puedeEditar)
                _logoUploading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: ProgressRing(strokeWidth: 2),
                      )
                    : Button(
                        onPressed: () => _pickAndUploadLogo(empresaId),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(FluentIcons.upload, size: 14),
                            const SizedBox(width: 6),
                            Text(_logoUrl == null ? 'Seleccionar' : 'Cambiar'),
                          ],
                        ),
                      ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sección de branding de empresa
// ---------------------------------------------------------------------------

class _EmpresaBrandingSection extends StatefulWidget {
  final TextEditingController colorPrimCtrl;
  final AccentColor? selectedPrimario;
  final void Function(AccentColor?) onPrimarioChanged;
  /// Último color confirmado en BD. "Aplicar a todos" solo está activo cuando
  /// el texto del controller coincide exactamente con este valor (ya guardado).
  final String? savedColor;

  const _EmpresaBrandingSection({
    required this.colorPrimCtrl,
    required this.selectedPrimario,
    required this.onPrimarioChanged,
    required this.savedColor,
  });

  @override
  State<_EmpresaBrandingSection> createState() => _EmpresaBrandingSectionState();
}

class _EmpresaBrandingSectionState extends State<_EmpresaBrandingSection> {
  bool _forcing = false;

  Future<void> _forceToAll() async {
    final color = widget.colorPrimCtrl.text.trim();
    if (color.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => ContentDialog(
        title: const Text('Aplicar color a todos'),
        content: const Text(
          'Esto descartará los colores personalizados de todos los usuarios '
          'de esta empresa en su próxima actualización de la app. '
          '¿Deseas continuar?',
        ),
        actions: [
          Button(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Aplicar a todos'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _forcing = true);
    try {
      final result = await Supabase.instance.client.rpc(
        'admin_force_empresa_color',
        params: {'p_color': color},
      );
      if (mounted) {
        if (result is Map && result['ok'] == true) {
          displayInfoBar(
            context,
            builder: (_, close) => InfoBar(
              title: const Text('Color aplicado a todos los usuarios'),
              content: const Text(
                'Los usuarios verán el nuevo color en la próxima vez que abran la app.',
              ),
              severity: InfoBarSeverity.success,
              onClose: close,
            ),
          );
        } else {
          displayInfoBar(
            context,
            builder: (_, close) => InfoBar(
              title: const Text('Error al aplicar'),
              content: Text(result?['error']?.toString() ?? 'Error desconocido'),
              severity: InfoBarSeverity.error,
              onClose: close,
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _forcing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    // "Aplicar a todos" solo activo si el color actual ya fue guardado en BD.
    final colorActual = widget.colorPrimCtrl.text.trim();
    final colorIsSaved = widget.savedColor != null &&
        widget.savedColor!.isNotEmpty &&
        widget.savedColor == colorActual;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Personalización', style: theme.typography.bodyStrong),
        const SizedBox(height: 4),
        const Divider(),
        const SizedBox(height: 4),
        Text(
          'Color de acento predeterminado para todos los usuarios de esta empresa. '
          'Cada usuario puede sobreescribir este color desde Configuración.',
          style: theme.typography.caption?.copyWith(color: theme.inactiveColor),
        ),
        const SizedBox(height: 16),

        InfoLabel(
          label: 'Color de acento de la empresa',
          child: _BrandingColorPicker(
            controller: widget.colorPrimCtrl,
            selected: widget.selectedPrimario,
            onSwatchSelected: widget.onPrimarioChanged,
          ),
        ),
        const SizedBox(height: 16),

        // Guardar se hace desde el botón principal del formulario.
        // "Aplicar a todos" solo disponible cuando el color ya está guardado en BD.
        _forcing
            ? const SizedBox(
                width: 20,
                height: 20,
                child: ProgressRing(strokeWidth: 2),
              )
            : Tooltip(
                message: colorIsSaved
                    ? 'Descarta el color personalizado de todos los usuarios '
                        'y les aplica el color de empresa en su próxima sesión.'
                    : 'Guarda los datos de la empresa primero para activar esta opción.',
                child: FilledButton(
                  onPressed: colorIsSaved ? _forceToAll : null,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(FluentIcons.sync, size: 14),
                      SizedBox(width: 6),
                      Text('Aplicar a todos'),
                    ],
                  ),
                ),
              ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Color picker para branding
// ---------------------------------------------------------------------------

class _BrandingColorPicker extends StatelessWidget {
  final TextEditingController controller;
  final AccentColor? selected;
  final void Function(AccentColor?) onSwatchSelected;

  const _BrandingColorPicker({
    required this.controller,
    required this.selected,
    required this.onSwatchSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ColorSwatchRow(
          selected: selected,
          onSelected: onSwatchSelected,
          includeNoneOption: true,
          noneLabel: 'Sin color',
        ),
        const SizedBox(height: 8),
        TextBox(
          controller: controller,
          placeholder: '#0078D4',
          prefix: const Padding(
            padding: EdgeInsets.only(left: 8),
            child: Icon(FluentIcons.color, size: 14),
          ),
        ),
      ],
    );
  }
}

class _ColorSwatchRow extends StatelessWidget {
  final AccentColor? selected;
  final void Function(AccentColor?) onSelected;
  final bool includeNoneOption;
  final String noneLabel;

  const _ColorSwatchRow({
    required this.selected,
    required this.onSelected,
    this.includeNoneOption = false,
    this.noneLabel = 'Ninguno',
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final bodyColor = theme.typography.body?.color ?? Colors.white;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (includeNoneOption)
          Tooltip(
            message: noneLabel,
            child: _SwatchCircle(
              color: theme.micaBackgroundColor,
              isSelected: selected == null,
              checkColor: bodyColor,
              border: BorderSide(color: theme.inactiveColor, width: 1.5),
              onTap: () => onSelected(null),
            ),
          ),
        ...Colors.accentColors.map((c) => Tooltip(
          message: _colorName(c),
          child: _SwatchCircle(
            color: c,
            isSelected: selected?.toARGB32() == c.toARGB32(),
            onTap: () => onSelected(c),
          ),
        )),
      ],
    );
  }

  String _colorName(AccentColor c) {
    const names = {
      'yellow': 'Amarillo', 'orange': 'Naranja', 'red': 'Rojo',
      'magenta': 'Magenta', 'purple': 'Morado', 'blue': 'Azul',
      'teal': 'Verde azulado', 'green': 'Verde',
    };
    for (final entry in names.entries) {
      if (c == _colorFor(entry.key)) return entry.value;
    }
    return 'Color';
  }

  AccentColor _colorFor(String name) => switch (name) {
    'yellow'  => Colors.yellow,
    'orange'  => Colors.orange,
    'red'     => Colors.red,
    'magenta' => Colors.magenta,
    'purple'  => Colors.purple,
    'blue'    => Colors.blue,
    'teal'    => Colors.teal,
    'green'   => Colors.green,
    _         => Colors.blue,
  };
}

class _SwatchCircle extends StatelessWidget {
  final Color color;
  final bool isSelected;
  final Color checkColor;
  final BorderSide? border;
  final VoidCallback onTap;

  const _SwatchCircle({
    required this.color,
    required this.isSelected,
    this.checkColor = Colors.white,
    this.border,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: isSelected
              ? Border.all(color: checkColor, width: 2.5)
              : border != null
                  ? Border.fromBorderSide(border!)
                  : null,
          boxShadow: isSelected
              ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 6, spreadRadius: 1)]
              : null,
        ),
        child: isSelected
            ? Icon(FluentIcons.check_mark, size: 16, color: checkColor)
            : null,
      ),
    );
  }
}
