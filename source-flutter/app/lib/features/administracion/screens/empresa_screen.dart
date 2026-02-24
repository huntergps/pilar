import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluent_ui_reactive/fluent_ui_reactive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/empresa_provider.dart';

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
  String? _ruc;
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

  // ---------------------------------------------------------------------------
  // Save handler
  // ---------------------------------------------------------------------------

  Future<void> _handleSave() async {
    final data = <String, dynamic>{};
    if (_nombre != null) data['nombre'] = _nombre;
    if (_nombreComercial != null) data['nombre_comercial'] = _nombreComercial;
    if (_ruc != null) data['ruc'] = _ruc;
    if (_direccion != null) data['direccion'] = _direccion;
    if (_telefono != null) data['telefono'] = _telefono;
    if (_email != null) data['email'] = _email;
    if (_web != null) data['web'] = _web;
    if (_tipoRuc != null) data['tipo_ruc'] = _tipoRuc;
    if (_provinciaId != null) data['provincia_id'] = _provinciaId;
    if (_ciudadId != null) data['ciudad_id'] = _ciudadId;
    if (_logoUrl != null) data['logo_url'] = _logoUrl;

    if (data.isEmpty) return;

    final result = await Supabase.instance.client.rpc(
      'admin_update_empresa',
      params: {'p_data': data},
    );

    if (result is Map && result['ok'] == true) {
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
    } else {
      if (mounted) {
        displayInfoBar(
          context,
          builder: (_, close) => InfoBar(
            title: const Text('Error al guardar'),
            content: Text(result?['error']?.toString() ?? 'Error desconocido'),
            severity: InfoBarSeverity.error,
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
      setState(() => _logoUrl = url);

      // Persist immediately
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
    final empresaAsync = ref.watch(empresaConfigProvider);
    final theme = FluentTheme.of(context);

    return ScaffoldPage(
      header: const PageHeader(title: Text('Empresa')),
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
          }

          final ciudadesFiltradas = _provinciaId == null
              ? <(int, String, int)>[]
              : _ciudades
                  .where((c) => c.$3 == _provinciaId)
                  .toList()
                ..sort((a, b) => a.$2.compareTo(b.$2));

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PilarForm(
                    onSave: _handleSave,
                    padding: EdgeInsets.zero,
                    children: [
                      // ---- Datos fiscales ----
                      PilarTextField(
                        name: 'nombre',
                        label: 'Nombre de empresa',
                        initialValue: empresa.nombre,
                        required: true,
                        onSaved: (v) => _nombre = v,
                      ),
                      const SizedBox(height: 12),
                      PilarTextField(
                        name: 'nombre_comercial',
                        label: 'Nombre comercial',
                        initialValue: empresa.nombreComercial,
                        onSaved: (v) => _nombreComercial = v,
                      ),
                      const SizedBox(height: 12),
                      PilarTextField(
                        name: 'ruc',
                        label: 'RUC / Cédula',
                        initialValue: empresa.ruc,
                        onSaved: (v) => _ruc = v,
                      ),
                      const SizedBox(height: 12),

                      // ---- Tipo RUC ----
                      InfoLabel(
                        label: 'Tipo de contribuyente',
                        child: RadioGroup<String>(
                          groupValue: _tipoRuc ?? '',
                          onChanged: (v) =>
                              setState(() => _tipoRuc = v ?? _tipoRuc),
                          child: Row(
                            children: [
                              RadioButton<String>(
                                value: 'sociedad',
                                content: const Text('Sociedad'),
                              ),
                              const SizedBox(width: 24),
                              RadioButton<String>(
                                value: 'persona_natural',
                                content: const Text('Persona natural'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      PilarTextField(
                        name: 'direccion',
                        label: 'Dirección',
                        initialValue: empresa.direccion,
                        maxLines: 2,
                        onSaved: (v) => _direccion = v,
                      ),
                      const SizedBox(height: 12),

                      // ---- Provincia + Ciudad ----
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
                                onChanged: (value) => setState(() {
                                  _provinciaId = value;
                                  _ciudadId = null;
                                }),
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
                                onChanged: ciudadesFiltradas.isEmpty
                                    ? null
                                    : (value) =>
                                        setState(() => _ciudadId = value),
                                isExpanded: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // ---- Contacto ----
                      PilarTextField(
                        name: 'telefono',
                        label: 'Teléfono',
                        initialValue: empresa.telefono,
                        keyboardType: TextInputType.phone,
                        onSaved: (v) => _telefono = v,
                      ),
                      const SizedBox(height: 12),
                      PilarTextField(
                        name: 'email',
                        label: 'Email',
                        initialValue: empresa.email,
                        keyboardType: TextInputType.emailAddress,
                        onSaved: (v) => _email = v,
                      ),
                      const SizedBox(height: 12),
                      PilarTextField(
                        name: 'web',
                        label: 'Sitio web',
                        initialValue: empresa.web,
                        keyboardType: TextInputType.url,
                        onSaved: (v) => _web = v,
                      ),
                    ],
                  ),

                  // ---- Logo ----
                  const SizedBox(height: 24),
                  Text('Logo de empresa', style: theme.typography.bodyStrong),
                  const SizedBox(height: 4),
                  const Divider(),
                  const SizedBox(height: 12),
                  _buildLogoSection(theme, empresa.empresaId),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLogoSection(FluentThemeData theme, String empresaId) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.resources.cardBackgroundFillColorDefault,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.resources.controlStrokeColorDefault),
      ),
      child: Row(
        children: [
          // Preview
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
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Icon(FluentIcons.check_mark,
                            size: 12, color: Colors.successPrimaryColor),
                        const SizedBox(width: 4),
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
                  'Formatos: PNG, JPG, WebP, SVG. Máx. 5 MB.',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.resources.textFillColorSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),

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
    );
  }
}
