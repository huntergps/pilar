import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

import '../../../core/theme/pilar_breakpoints.dart';
import 'package:brick_gen/brick_gen.dart';
import '../../../core/theme/pilar_spacing.dart';
import '../../../core/widgets/loading_spinner.dart';
import '../providers/mensajes_provider.dart';

// ---------------------------------------------------------------------------
// Filtros locales
// ---------------------------------------------------------------------------

final _filtroCanalHistProvider = StateProvider<String?>((ref) => null);
final _filtroEstadoHistProvider = StateProvider<String?>((ref) => null);

// ---------------------------------------------------------------------------
// HistorialTab
// ---------------------------------------------------------------------------

class HistorialTab extends ConsumerWidget {
  const HistorialTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historialAsync = ref.watch(historialMensajesProvider);
    final filtroCanal = ref.watch(_filtroCanalHistProvider);
    final filtroEstado = ref.watch(_filtroEstadoHistProvider);

    final mensajes = historialAsync.valueOrNull ?? const [];
    final filtrados = mensajes.where((m) {
      if (filtroCanal != null && m.canal != filtroCanal) return false;
      if (filtroEstado != null && m.estado != filtroEstado) return false;
      return true;
    }).toList();

    return Column(
      children: [
        // ---- Barra de filtros ----
        _FiltrosBar(filtroCanal: filtroCanal, filtroEstado: filtroEstado),

        // ---- Contenido ----
        Expanded(
          child: historialAsync.when(
            loading: () => const PilarLoadingCenter(),
            error: (e, _) => Center(
              child: InfoBar(
                title: const Text('Error cargando historial'),
                content: Text(e.toString()),
                severity: InfoBarSeverity.error,
              ),
            ),
            data: (_) => context.isTablet || context.isDesktop
                ? _DataGridHistorial(mensajes: filtrados)
                : _ListaHistorial(mensajes: filtrados),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Filtros
// ---------------------------------------------------------------------------

class _FiltrosBar extends ConsumerWidget {
  final String? filtroCanal;
  final String? filtroEstado;

  const _FiltrosBar({required this.filtroCanal, required this.filtroEstado});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(Spacing.sm),
      child: Wrap(
        spacing: Spacing.sm,
        runSpacing: Spacing.xs,
        children: [
          // Filtro canal
          ComboBox<String?>(
            value: filtroCanal,
            placeholder: const Text('Canal'),
            items: const [
              ComboBoxItem(value: null, child: Text('Todos los canales')),
              ComboBoxItem(value: 'whatsapp', child: Text('WhatsApp')),
              ComboBoxItem(value: 'telegram', child: Text('Telegram')),
              ComboBoxItem(value: 'email_api', child: Text('Email (API)')),
              ComboBoxItem(value: 'email_smtp', child: Text('Email (SMTP)')),
            ],
            onChanged: (v) =>
                ref.read(_filtroCanalHistProvider.notifier).state = v,
          ),

          // Filtro estado
          ComboBox<String?>(
            value: filtroEstado,
            placeholder: const Text('Estado'),
            items: const [
              ComboBoxItem(value: null, child: Text('Todos los estados')),
              ComboBoxItem(value: 'enviado', child: Text('Enviado')),
              ComboBoxItem(value: 'entregado', child: Text('Entregado')),
              ComboBoxItem(value: 'leido', child: Text('Leído')),
              ComboBoxItem(value: 'fallido', child: Text('Fallido')),
              ComboBoxItem(value: 'pendiente', child: Text('Pendiente')),
              ComboBoxItem(value: 'encolado', child: Text('Encolado')),
            ],
            onChanged: (v) =>
                ref.read(_filtroEstadoHistProvider.notifier).state = v,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// DataGrid (≥ 600px)
// ---------------------------------------------------------------------------

class _DataGridHistorial extends StatefulWidget {
  final List<ComMensaje> mensajes;

  const _DataGridHistorial({required this.mensajes});

  @override
  State<_DataGridHistorial> createState() => _DataGridHistorialState();
}

class _DataGridHistorialState extends State<_DataGridHistorial> {
  late _HistorialDataSource _source;

  @override
  void initState() {
    super.initState();
    _source = _HistorialDataSource(widget.mensajes);
  }

  @override
  void didUpdateWidget(_DataGridHistorial old) {
    super.didUpdateWidget(old);
    if (old.mensajes != widget.mensajes) {
      _source = _HistorialDataSource(widget.mensajes);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mensajes.isEmpty) {
      return Center(
        child: Text(
          'Sin mensajes salientes',
          style: FluentTheme.of(context).typography.body,
        ),
      );
    }
    return SfDataGrid(
      source: _source,
      columnWidthMode: ColumnWidthMode.fill,
      gridLinesVisibility: GridLinesVisibility.horizontal,
      columns: [
        GridColumn(
          columnName: 'canal',
          columnWidthMode: ColumnWidthMode.fitByCellValue,
          label: const _ColHeader('Canal'),
        ),
        GridColumn(
          columnName: 'destinatario',
          label: const _ColHeader('Destinatario'),
        ),
        GridColumn(
          columnName: 'asunto',
          label: const _ColHeader('Asunto/Cuerpo'),
        ),
        GridColumn(
          columnName: 'estado',
          columnWidthMode: ColumnWidthMode.fitByCellValue,
          label: const _ColHeader('Estado'),
        ),
        GridColumn(
          columnName: 'fecha',
          columnWidthMode: ColumnWidthMode.fitByCellValue,
          label: const _ColHeader('Fecha'),
        ),
      ],
    );
  }
}

class _ColHeader extends StatelessWidget {
  final String label;

  const _ColHeader(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(Spacing.sm),
      child: Text(
        label,
        style: FluentTheme.of(context).typography.bodyStrong,
      ),
    );
  }
}

class _HistorialDataSource extends DataGridSource {
  final List<DataGridRow> _rows;

  _HistorialDataSource(List<ComMensaje> mensajes)
      : _rows = mensajes
            .map(
              (m) => DataGridRow(cells: [
                DataGridCell(columnName: 'canal', value: m.canal),
                DataGridCell(columnName: 'destinatario', value: m.destinatarioRef),
                DataGridCell(
                    columnName: 'asunto',
                    value: m.asunto?.isNotEmpty == true ? m.asunto : m.cuerpo ?? ''),
                DataGridCell(columnName: 'estado', value: m.estado),
                DataGridCell(
                    columnName: 'fecha',
                    value: m.enviadoEn ?? m.creadoEn),
              ]),
            )
            .toList();

  @override
  List<DataGridRow> get rows => _rows;

  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    final cells = row.getCells();
    return DataGridRowAdapter(
      cells: [
        // Canal badge
        _CanalBadge(canal: cells[0].value as String),
        // Destinatario
        Padding(
          padding: const EdgeInsets.all(Spacing.sm),
          child: Text(cells[1].value as String, overflow: TextOverflow.ellipsis),
        ),
        // Asunto/cuerpo
        Padding(
          padding: const EdgeInsets.all(Spacing.sm),
          child: Text(cells[2].value as String, overflow: TextOverflow.ellipsis),
        ),
        // Estado chip
        _EstadoChip(estado: cells[3].value as String),
        // Fecha
        Padding(
          padding: const EdgeInsets.all(Spacing.sm),
          child: Text(_formatFecha(cells[4].value as DateTime)),
        ),
      ],
    );
  }
}

String _formatFecha(DateTime dt) {
  return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

class _CanalBadge extends StatelessWidget {
  final String canal;

  const _CanalBadge({required this.canal});

  @override
  Widget build(BuildContext context) {
    final label = switch (canal) {
      'whatsapp' => 'WA',
      'telegram' => 'TG',
      'email_api' => 'API',
      'email_smtp' => 'SMTP',
      _ => canal.toUpperCase().substring(0, 2),
    };
    final color = switch (canal) {
      'whatsapp' => const Color(0xFF25D366),
      'telegram' => const Color(0xFF0088CC),
      _ => const Color(0xFF0078D4),
    };
    return Padding(
      padding: const EdgeInsets.all(Spacing.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: Spacing.xxs),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

class _EstadoChip extends StatelessWidget {
  final String estado;

  const _EstadoChip({required this.estado});

  @override
  Widget build(BuildContext context) {
    final color = switch (estado) {
      'enviado' || 'entregado' || 'leido' => Colors.green,
      'fallido' || 'rebotado' => Colors.warningPrimaryColor,
      'cancelado' => Colors.grey[80],
      _ => const Color(0xFFF0A500), // pendiente/encolado → amarillo
    };
    return Padding(
      padding: const EdgeInsets.all(Spacing.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: Spacing.xxs),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          estado,
          style: TextStyle(color: color, fontSize: 11),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Lista (< 600px)
// ---------------------------------------------------------------------------

class _ListaHistorial extends StatelessWidget {
  final List<ComMensaje> mensajes;

  const _ListaHistorial({required this.mensajes});

  @override
  Widget build(BuildContext context) {
    if (mensajes.isEmpty) {
      return Center(
        child: Text(
          'Sin mensajes salientes',
          style: FluentTheme.of(context).typography.body,
        ),
      );
    }
    return ListView.builder(
      itemCount: mensajes.length,
      itemBuilder: (ctx, i) {
        final m = mensajes[i];
        return ListTile(
          leading: _CanalBadge(canal: m.canal),
          title: Text(m.destinatarioRef, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            m.asunto?.isNotEmpty == true ? m.asunto! : m.cuerpo ?? '',
            overflow: TextOverflow.ellipsis,
          ),
          trailing: _EstadoChip(estado: m.estado),
        );
      },
    );
  }
}
