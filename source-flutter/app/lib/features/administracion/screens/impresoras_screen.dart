import 'dart:typed_data';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sfpdf;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pilar_print/pilar_print.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/usuario_provider.dart';

// ---------------------------------------------------------------------------
// Providers locales
// ---------------------------------------------------------------------------

/// Lista de impresoras virtuales de la empresa (reloadable).
///
/// Provider público para poder hacer override en tests:
/// ```dart
/// impresorasScreenProvider.overrideWith((_) async => [...]);
/// ```
final impresorasScreenProvider =
    FutureProvider.autoDispose<List<ImpresoraVirtual>>((ref) async {
  final rows = await Supabase.instance.client
      .rpc('impresoras_get_catalogo')
      .then((data) => (data as List).cast<Map<String, dynamic>>());
  return rows.map(ImpresoraVirtual.fromJson).toList();
});

/// Configuración local guardada por nombre de impresora virtual.
final _configLocalProvider =
    FutureProvider.autoDispose.family<ConfiguracionLocal?, String>((ref, nombre) async {
  return PrintConfigStore().load(nombre);
});

// ---------------------------------------------------------------------------
// ImpresorasScreen
// ---------------------------------------------------------------------------

class ImpresorasScreen extends ConsumerWidget {
  const ImpresorasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tieneAdmin =
        ref.watch(hasPermissionProvider('administracion.empresa.menu'));
    final impresorasAsync = ref.watch(impresorasScreenProvider);

    return ScaffoldPage(
      header: PageHeader(
        title: const Text('Impresoras'),
        commandBar: CommandBar(
          primaryItems: [
            if (tieneAdmin)
              CommandBarButton(
                icon: const Icon(FluentIcons.add),
                label: const Text('Nueva impresora'),
                onPressed: () => _showCrearDialog(context, ref),
              ),
          ],
        ),
      ),
      content: impresorasAsync.when(
        data: (impresoras) => impresoras.isEmpty
            ? _EmptyState(tieneAdmin: tieneAdmin, onCrear: () => _showCrearDialog(context, ref))
            : _ImpresorasList(impresoras: impresoras, tieneAdmin: tieneAdmin),
        loading: () => const Center(child: ProgressRing()),
        error: (e, _) => Center(
          child: InfoBar(
            title: const Text('Error al cargar impresoras'),
            content: Text(e.toString()),
            severity: InfoBarSeverity.error,
          ),
        ),
      ),
    );
  }

  Future<void> _showCrearDialog(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _CrearImpresoraDialog(ref: ref),
    );
    if (result == true) ref.invalidate(impresorasScreenProvider);
  }
}

// ---------------------------------------------------------------------------
// Lista de impresoras
// ---------------------------------------------------------------------------

class _ImpresorasList extends ConsumerWidget {
  final List<ImpresoraVirtual> impresoras;
  final bool tieneAdmin;

  const _ImpresorasList({required this.impresoras, required this.tieneAdmin});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ---- Catálogo de empresa ----
        Text('Catálogo de empresa',
            style: FluentTheme.of(context).typography.subtitle),
        const SizedBox(height: 12),
        ...impresoras.map(
          (imp) => _ImpresoraCard(
            impresora: imp,
            tieneAdmin: tieneAdmin,
            onDeleted: () => ref.invalidate(impresorasScreenProvider),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tarjeta de impresora
// ---------------------------------------------------------------------------

class _ImpresoraCard extends ConsumerStatefulWidget {
  final ImpresoraVirtual impresora;
  final bool tieneAdmin;
  final VoidCallback onDeleted;

  const _ImpresoraCard({
    required this.impresora,
    required this.tieneAdmin,
    required this.onDeleted,
  });

  @override
  ConsumerState<_ImpresoraCard> createState() => _ImpresoraCardState();
}

class _ImpresoraCardState extends ConsumerState<_ImpresoraCard> {
  bool _expanded = false;
  bool _probando = false;

  Future<void> _probarConfig() async {
    setState(() => _probando = true);
    try {
      await _probar();
    } catch (e, st) {
      debugPrint('[pilar_print] error en _probar: $e\n$st');
    } finally {
      if (mounted) setState(() => _probando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final configAsync = ref.watch(_configLocalProvider(widget.impresora.nombre));
    final config = configAsync.valueOrNull;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---- Header ----
          Row(
            children: [
              Icon(
                _iconForTipo(widget.impresora.tipoDoc),
                color: theme.accentColor,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.impresora.nombre,
                        style: theme.typography.bodyStrong),
                    if (widget.impresora.descripcion != null)
                      Text(widget.impresora.descripcion!,
                          style: theme.typography.caption),
                  ],
                ),
              ),
              // Badge tipo de documento
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  widget.impresora.tipoDoc.name.toUpperCase(),
                  style: theme.typography.caption
                      ?.copyWith(color: theme.accentColor),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(
                    _expanded ? FluentIcons.chevron_up : FluentIcons.chevron_down),
                onPressed: () => setState(() => _expanded = !_expanded),
              ),
              if (widget.tieneAdmin) ...[
                const SizedBox(width: 4),
                const SizedBox(height: 20, child: Divider(direction: Axis.vertical)),
                IconButton(
                  icon: Icon(FluentIcons.delete,
                      color: Colors.red.normal, size: 16),
                  onPressed: () => _confirmarEliminar(context),
                ),
              ],
            ],
          ),

          // ---- Config local (expandible) ----
          if (_expanded) ...[
            const Divider(),
            const SizedBox(height: 8),
            Text('Mi dispositivo', style: theme.typography.bodyStrong),
            const SizedBox(height: 8),
            _ConfigLocalForm(
              impresora: widget.impresora,
              config: config,
              onSaved: () => ref.invalidate(_configLocalProvider(widget.impresora.nombre)),
              onProbar: _probarConfig,
              probando: _probando,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _probar() async {
    // Asegura que PrintService tiene el catálogo — usa los datos ya cargados
    // por impresorasScreenProvider (que ya resolvió para mostrar esta pantalla).
    final impresoras = ref.read(impresorasScreenProvider).valueOrNull ?? [];
    PrintService.instance.configure(impresoras);

    // Leer config guardada
    final config =
        await PrintService.instance.loadConfig(widget.impresora.nombre);
    if (config == null) {
      _mostrarResultado('Sin configuración',
          'Guarda la configuración antes de probar.', InfoBarSeverity.warning);
      return;
    }

    if (config.tipoConexion == TipoConexion.sistema) {
      await _probarSistema(config);
      return;
    }

    // TCP / Bluetooth / Gateway — enviar documento de prueba con timeout
    final doc = _buildTestDoc();
    PrintJobResult result;
    try {
      result = await PrintService.instance
          .print(widget.impresora.nombre, doc)
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () =>
                PrintJobResult.error('Sin respuesta (10 s) — verifica IP/BT'),
          );
    } catch (e) {
      result = PrintJobResult.error(e.toString());
    }
    _mostrarResultado(
      result.isOk ? 'Impresión enviada' : 'Error',
      result.errorMessage ?? 'Trabajo de prueba enviado correctamente',
      result.isOk ? InfoBarSeverity.success : InfoBarSeverity.error,
    );
  }

  /// Para TipoConexion.sistema maneja dos sub-casos:
  /// - Sin impresora fija → abre el visor PDF del OS (Preview.app en macOS).
  /// - Con impresora fija → verifica que el driver esté instalado sin imprimir.
  Future<void> _probarSistema(ConfiguracionLocal config) async {
    final printerName = config.printerName;

    if (printerName == null || printerName.isEmpty) {
      // Sin impresora fija → abrir PDF en visor del OS.
      final doc = _buildTestDoc();
      final result = await PrintService.instance
          .print(widget.impresora.nombre, doc);
      _mostrarResultado(
        result.isOk ? 'Enviado al OS' : 'Cancelado',
        result.errorMessage ?? 'Documento enviado correctamente',
        result.isOk ? InfoBarSeverity.success : InfoBarSeverity.warning,
      );
      return;
    }

    // Con impresora fija → verificar que el driver está instalado sin imprimir
    final disponibles = await PrintService.instance.getSystemPrinterNames();
    final encontrada =
        disponibles.any((n) => n.toLowerCase() == printerName.toLowerCase());
    _mostrarResultado(
      encontrada ? 'Impresora disponible' : 'Impresora no encontrada',
      encontrada
          ? '"$printerName" está instalada y disponible.'
          : '"$printerName" no se encontró. Verifica el driver.',
      encontrada ? InfoBarSeverity.success : InfoBarSeverity.error,
    );
  }

  PrintDocument _buildTestDoc() => switch (widget.impresora.tipoDoc) {
        TipoDocumento.pdf => PrintDocument.pdf(_dummyPdfBytes()),
        TipoDocumento.zpl => PrintDocument.zpl(ZplGenerator.buildLabel(
            nombre: 'TEST PILAR', codigo: '0000000', precio: '0.00')),
        TipoDocumento.escp   => PrintDocument.escp(_dummyEscPosBytes()),
        TipoDocumento.texto  => PrintDocument.texto(_dummyEscPosBytes()),
        TipoDocumento.escpos => PrintDocument.escpos(_dummyEscPosBytes()),
      };

  void _mostrarResultado(
      String title, String content, InfoBarSeverity severity) {
    if (!mounted) return;
    // Sin await — el InfoBar no debe bloquear la UI.
    displayInfoBar(
      context,
      builder: (_, close) => InfoBar(
        title: Text(title),
        content: Text(content),
        severity: severity,
        action: IconButton(icon: const Icon(FluentIcons.clear), onPressed: close),
      ),
    );
  }

  Future<void> _confirmarEliminar(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => ContentDialog(
        title: const Text('Eliminar impresora'),
        content: Text(
            '¿Eliminar la impresora virtual "${widget.impresora.nombre}"? '
            'Esta acción no se puede deshacer.'),
        actions: [
          Button(
            child: const Text('Cancelar'),
            onPressed: () => Navigator.pop(dialogCtx, false),
          ),
          FilledButton(
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.all(Colors.red),
            ),
            child: const Text('Eliminar'),
            onPressed: () => Navigator.pop(dialogCtx, true),
          ),
        ],
      ),
    );
    if (confirm == true && context.mounted) {
      await Supabase.instance.client
          .from('impresoras_virtuales')
          .update({'activo': false})
          .eq('id', widget.impresora.id);
      widget.onDeleted();
    }
  }

  IconData _iconForTipo(TipoDocumento tipo) {
    return switch (tipo) {
      TipoDocumento.escpos => FluentIcons.receipt_reply,
      TipoDocumento.zpl    => FluentIcons.tag,
      TipoDocumento.pdf    => FluentIcons.pdf,
      TipoDocumento.escp   => FluentIcons.print,
      TipoDocumento.texto  => FluentIcons.plain_text,
    };
  }

  // Bytes mínimos de prueba
  Uint8List _dummyEscPosBytes() => Uint8List.fromList([
        ...EscPosGenerator.init,
        ...EscPosGenerator.textLine('TEST PILAR'),
        ...EscPosGenerator.cutPartial,
      ]);

  Uint8List _dummyPdfBytes() {
    final doc = sfpdf.PdfDocument();
    final page = doc.pages.add();
    final font = sfpdf.PdfStandardFont(
        sfpdf.PdfFontFamily.helvetica, 14,
        style: sfpdf.PdfFontStyle.bold);
    final fontSmall = sfpdf.PdfStandardFont(sfpdf.PdfFontFamily.helvetica, 10);
    page.graphics.drawString(
      'PILAR ERP — Página de prueba',
      font,
      brush: sfpdf.PdfSolidBrush(sfpdf.PdfColor(0, 0, 0)),
      bounds: Rect.fromLTWH(40, 40, page.size.width - 80, 30),
    );
    page.graphics.drawString(
      'Impresora: ${widget.impresora.nombre}\n${DateTime.now()}',
      fontSmall,
      brush: sfpdf.PdfSolidBrush(sfpdf.PdfColor(80, 80, 80)),
      bounds: Rect.fromLTWH(40, 80, page.size.width - 80, 60),
    );
    final bytes = Uint8List.fromList(doc.saveSync());
    doc.dispose();
    return bytes;
  }
}

// ---------------------------------------------------------------------------
// Formulario de configuración local
// ---------------------------------------------------------------------------

class _ConfigLocalForm extends ConsumerStatefulWidget {
  final ImpresoraVirtual impresora;
  final ConfiguracionLocal? config;
  final VoidCallback onSaved;
  final Future<void> Function() onProbar;
  final bool probando;

  const _ConfigLocalForm({
    required this.impresora,
    required this.config,
    required this.onSaved,
    required this.onProbar,
    required this.probando,
  });

  @override
  ConsumerState<_ConfigLocalForm> createState() => _ConfigLocalFormState();
}

class _ConfigLocalFormState extends ConsumerState<_ConfigLocalForm> {
  late TipoConexion _tipoConexion;
  final _ipController = TextEditingController();
  final _puertoController = TextEditingController();
  final _printerNameController = TextEditingController();
  final _gatewayUrlController = TextEditingController();
  String? _btAddress;
  List<({String name, String address})> _btDevices = [];
  bool _loadingBt = false;
  List<String> _osPrinters = [];
  bool _loadingOsPrinters = false;
  // true cuando la config guardada coincide con el estado actual del formulario
  bool _configSaved = false;

  void _markDirty() {
    if (_configSaved) setState(() => _configSaved = false);
  }

  @override
  void initState() {
    super.initState();
    final c = widget.config;
    // Si ya hay una config guardada, "Probar" empieza habilitado
    _configSaved = c != null;
    _tipoConexion = c?.tipoConexion ?? TipoConexion.tcp;
    _ipController.text = c?.ip ?? '';
    _puertoController.text = c?.puerto?.toString() ?? '9100';
    _printerNameController.text = c?.printerName ?? '';
    _gatewayUrlController.text = c?.gatewayUrl ?? 'ws://localhost:8182';
    _btAddress = c?.btAddress;
    // Marcar dirty cuando cualquier campo de texto cambie
    _ipController.addListener(_markDirty);
    _puertoController.addListener(_markDirty);
    _printerNameController.addListener(_markDirty);
    _gatewayUrlController.addListener(_markDirty);
    if (_tipoConexion == TipoConexion.sistema) {
      _loadOsPrinters();
    }
  }

  @override
  void dispose() {
    _ipController.dispose();
    _puertoController.dispose();
    _printerNameController.dispose();
    _gatewayUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ---- Tipo de conexión ----
        InfoLabel(
          label: 'Tipo de conexión',
          child: ComboBox<TipoConexion>(
            isExpanded: true,
            value: _tipoConexion,
            items: const [
              ComboBoxItem(
                value: TipoConexion.tcp,
                child: Text('TCP — socket directo a IP:puerto (ESC/POS, ZPL)'),
              ),
              ComboBoxItem(
                value: TipoConexion.bluetooth,
                child: Text('Bluetooth — impresoras portátiles SPP'),
              ),
              ComboBoxItem(
                value: TipoConexion.gateway,
                child: Text('Gateway — servidor intermediario (QZ Tray, HTTP)'),
              ),
              ComboBoxItem(
                value: TipoConexion.sistema,
                child: Text('Sistema — driver instalado en el OS'),
              ),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() => _tipoConexion = v);
              _markDirty();
              if (v == TipoConexion.sistema && _osPrinters.isEmpty) {
                _loadOsPrinters();
              }
            },
          ),
        ),
        const SizedBox(height: 12),

        // ---- Campos según tipo ----
        if (_tipoConexion == TipoConexion.tcp) ...[
          Row(
            children: [
              const SizedBox(width: 56, child: Text('IP:')),
              Expanded(
                child: TextBox(controller: _ipController, placeholder: '192.168.1.100'),
              ),
              const SizedBox(width: 12),
              const Text('Puerto:'),
              const SizedBox(width: 8),
              SizedBox(
                width: 72,
                child: TextBox(controller: _puertoController, placeholder: '9100'),
              ),
            ],
          ),
        ] else if (_tipoConexion == TipoConexion.bluetooth) ...[
          Row(
            children: [
              if (_loadingBt) const ProgressRing(strokeWidth: 2),
              if (!_loadingBt && _btDevices.isEmpty)
                Button(
                  onPressed: _loadBtDevices,
                  child: const Text('Buscar dispositivos BT'),
                ),
              if (!_loadingBt && _btDevices.isNotEmpty)
                Expanded(
                  child: ComboBox<String>(
                    isExpanded: true,
                    value: _btAddress,
                    placeholder: const Text('Seleccionar dispositivo...'),
                    items: _btDevices
                        .map((d) => ComboBoxItem(
                              value: d.address,
                              child: Text('${d.name} (${d.address})'),
                            ))
                        .toList(),
                    onChanged: (v) { setState(() => _btAddress = v); _markDirty(); },
                  ),
                ),
            ],
          ),
        ] else if (_tipoConexion == TipoConexion.gateway) ...[
          InfoLabel(
            label: 'URL del servidor intermediario',
            child: TextBox(
              controller: _gatewayUrlController,
              placeholder: 'ws://localhost:8182  o  http://192.168.1.50:3000/print',
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'ws:// o wss:// → QZ Tray (WebSocket)\nhttp:// o https:// → Servidor HTTP personalizado',
            style: TextStyle(fontSize: 11),
          ),
          const SizedBox(height: 8),
          InfoLabel(
            label: 'Nombre de impresora en el gateway (opcional)',
            child: TextBox(
              controller: _printerNameController,
              placeholder: 'Dejar vacío para usar la predeterminada',
            ),
          ),
        ] else if (_tipoConexion == TipoConexion.sistema) ...[
          InfoLabel(
            label: 'Impresora del sistema operativo',
            child: _loadingOsPrinters
                ? const Row(children: [
                    ProgressRing(strokeWidth: 2),
                    SizedBox(width: 8),
                    Text('Cargando impresoras...'),
                  ])
                : _osPrinters.isEmpty
                    ? Row(children: [
                        const Text('No se encontraron impresoras.'),
                        const SizedBox(width: 8),
                        Button(
                          onPressed: _loadOsPrinters,
                          child: const Text('Reintentar'),
                        ),
                      ])
                    : ComboBox<String?>(
                        isExpanded: true,
                        value: _printerNameController.text.isEmpty
                            ? null
                            : _osPrinters.contains(_printerNameController.text)
                                ? _printerNameController.text
                                : null,
                        items: [
                          const ComboBoxItem<String?>(
                            value: null,
                            child: Row(children: [
                              Icon(FluentIcons.preview, size: 14),
                              SizedBox(width: 6),
                              Text('Vista previa / diálogo del OS'),
                            ]),
                          ),
                          ..._osPrinters.map((name) => ComboBoxItem<String?>(
                                value: name,
                                child: Text(name),
                              )),
                        ],
                        onChanged: (v) {
                          setState(() => _printerNameController.text = v ?? '');
                          _markDirty();
                        },
                      ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Si no seleccionas una impresora, se abrirá el diálogo del OS al imprimir.',
            style: TextStyle(fontSize: 11),
          ),
        ],

        const SizedBox(height: 12),
        Row(
          children: [
            Button(
              onPressed: _guardar,
              child: const Text('Guardar'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: (_configSaved && !widget.probando) ? widget.onProbar : null,
              child: widget.probando
                  ? const SizedBox(
                      width: 16, height: 16, child: ProgressRing(strokeWidth: 2))
                  : const Text('Probar'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _loadBtDevices() async {
    setState(() => _loadingBt = true);
    try {
      final devices = await PrintService.instance.getPairedBluetoothDevices();
      setState(() => _btDevices = devices);
    } finally {
      setState(() => _loadingBt = false);
    }
  }

  Future<void> _loadOsPrinters() async {
    setState(() => _loadingOsPrinters = true);
    try {
      final names = await PrintService.instance.getSystemPrinterNames();
      setState(() => _osPrinters = names);
    } finally {
      setState(() => _loadingOsPrinters = false);
    }
  }

  Future<void> _guardar() async {
    final config = ConfiguracionLocal(
      virtualNombre: widget.impresora.nombre,
      tipoConexion: _tipoConexion,
      ip: _tipoConexion == TipoConexion.tcp ? _ipController.text.trim() : null,
      puerto: _tipoConexion == TipoConexion.tcp
          ? int.tryParse(_puertoController.text.trim())
          : null,
      btAddress: _tipoConexion == TipoConexion.bluetooth ? _btAddress : null,
      gatewayUrl: _tipoConexion == TipoConexion.gateway
          ? _gatewayUrlController.text.trim()
          : null,
      printerName: (_tipoConexion == TipoConexion.gateway ||
              _tipoConexion == TipoConexion.sistema)
          ? (_printerNameController.text.trim().isEmpty
              ? null
              : _printerNameController.text.trim())
          : null,
    );
    await PrintService.instance.saveConfig(config);
    widget.onSaved();
    if (mounted) {
      setState(() => _configSaved = true);
      await displayInfoBar(
        context,
        builder: (_, close) => InfoBar(
          title: const Text('Configuración guardada'),
          severity: InfoBarSeverity.success,
          action: IconButton(icon: const Icon(FluentIcons.clear), onPressed: close),
        ),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Diálogo: crear impresora virtual
// ---------------------------------------------------------------------------

class _CrearImpresoraDialog extends ConsumerStatefulWidget {
  final WidgetRef ref;
  const _CrearImpresoraDialog({required this.ref});

  @override
  ConsumerState<_CrearImpresoraDialog> createState() =>
      _CrearImpresoraDialogState();
}

class _CrearImpresoraDialogState extends ConsumerState<_CrearImpresoraDialog> {
  final _nombreController = TextEditingController();
  final _descripcionController = TextEditingController();
  TipoDocumento _tipoDoc = TipoDocumento.pdf;
  bool _saving = false;

  @override
  void dispose() {
    _nombreController.dispose();
    _descripcionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 520),
      title: const Text('Nueva impresora virtual'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InfoLabel(
            label: 'Nombre (identificador único)',
            child: TextBox(
              controller: _nombreController,
              placeholder: 'ej: ticket_pos, etiqueta_producto, factura_a4',
            ),
          ),
          const SizedBox(height: 12),
          InfoLabel(
            label: 'Descripción (opcional)',
            child: TextBox(
              controller: _descripcionController,
              placeholder: 'Descripción para identificar el uso',
            ),
          ),
          const SizedBox(height: 12),
          InfoLabel(
            label: 'Tipo de documento',
            child: ComboBox<TipoDocumento>(
              isExpanded: true,
              value: _tipoDoc,
              items: const [
                ComboBoxItem(
                  value: TipoDocumento.pdf,
                  child: Text('PDF — impresoras de escritorio'),
                ),
                ComboBoxItem(
                  value: TipoDocumento.escpos,
                  child: Text('ESC/POS — térmica de ticket'),
                ),
                ComboBoxItem(
                  value: TipoDocumento.zpl,
                  child: Text('ZPL — etiquetas Zebra'),
                ),
                ComboBoxItem(
                  value: TipoDocumento.escp,
                  child: Text('ESC/P — matricial (formularios continuos)'),
                ),
                ComboBoxItem(
                  value: TipoDocumento.texto,
                  child: Text('Texto plano — ASCII/CR+LF'),
                ),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _tipoDoc = v);
              },
            ),
          ),
        ],
      ),
      actions: [
        Button(
          child: const Text('Cancelar'),
          onPressed: () => Navigator.pop(context, false),
        ),
        FilledButton(
          onPressed: _saving ? null : _guardar,
          child: _saving
              ? const SizedBox(
                  width: 16, height: 16, child: ProgressRing(strokeWidth: 2))
              : const Text('Crear'),
        ),
      ],
    );
  }

  Future<void> _guardar() async {
    final nombre = _nombreController.text.trim();
    if (nombre.isEmpty) return;
    setState(() => _saving = true);
    try {
      final empresaId = Supabase.instance.client.auth.currentSession
          ?.user.appMetadata['empresa_id'] as String?;
      if (empresaId == null) throw Exception('No hay empresa activa');
      await Supabase.instance.client.from('impresoras_virtuales').insert({
        'empresa_id': empresaId,
        'nombre': nombre,
        'descripcion': _descripcionController.text.trim().isEmpty
            ? null
            : _descripcionController.text.trim(),
        'tipo_doc': _tipoDoc.name,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        await displayInfoBar(
          context,
          builder: (_, close) => InfoBar(
            title: const Text('Error al crear impresora'),
            content: Text(e.toString()),
            severity: InfoBarSeverity.error,
            action: IconButton(icon: const Icon(FluentIcons.clear), onPressed: close),
          ),
        );
        setState(() => _saving = false);
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  final bool tieneAdmin;
  final VoidCallback onCrear;

  const _EmptyState({required this.tieneAdmin, required this.onCrear});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(FluentIcons.print, size: 48),
          const SizedBox(height: 16),
          Text(
            'No hay impresoras configuradas',
            style: FluentTheme.of(context).typography.subtitle,
          ),
          const SizedBox(height: 8),
          const Text('Crea impresoras virtuales para gestionar la impresión en PILAR ERP.'),
          if (tieneAdmin) ...[
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onCrear,
              child: const Text('Crear primera impresora'),
            ),
          ],
        ],
      ),
    );
  }
}
