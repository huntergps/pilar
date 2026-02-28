// ChatterWidget — widget embeddable de comunicación interna para cualquier entidad.
//
// Muestra el historial de mensajes, logs de sistema, actividades y permite
// publicar comentarios con adjuntos desde cualquier pantalla de detalle.
//
// Uso:
//   ChatterWidget(
//     entidadTipo: 'facturas',
//     entidadId: facturaId,
//   )

import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart' show launchUrl, LaunchMode;

import '../models/adjunto_model.dart';
import '../models/chatter_actividad.dart';
import '../models/chatter_mensaje.dart';
import '../providers/chatter_provider.dart';
import '../services/upload_service.dart';
import 'enviar_mensaje_externo_button.dart';

// ---------------------------------------------------------------------------
// Widget principal
// ---------------------------------------------------------------------------

class ChatterWidget extends ConsumerStatefulWidget {
  /// Tipo de entidad propietaria del chatter (ej: 'facturas', 'contactos').
  final String entidadTipo;

  /// UUID del registro propietario del chatter.
  final String entidadId;

  /// Altura del widget. null = SizedBox.expand (ocupa todo el espacio disponible).
  final double? height;

  const ChatterWidget({
    required this.entidadTipo,
    required this.entidadId,
    this.height,
    super.key,
  });

  @override
  ConsumerState<ChatterWidget> createState() => _ChatterWidgetState();
}

class _ChatterWidgetState extends ConsumerState<ChatterWidget> {
  ChatterRef get _ref => (
        entidadTipo: widget.entidadTipo,
        entidadId: widget.entidadId,
      );

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    // Leer count de actividades pendientes para el tab badge
    final actividadesAsync =
        ref.watch(chatterActividadesPendientesProvider(_ref));
    final pendientesCount = actividadesAsync.valueOrNull?.length ?? 0;

    Widget body = TabView(
      currentIndex: 0,
      onChanged: (_) {},
      closeButtonVisibility: CloseButtonVisibilityMode.never,
      tabWidthBehavior: TabWidthBehavior.equal,
      tabs: [
        Tab(
          text: const Text('Mensajes'),
          body: _MensajesTab(
            entidadTipo: widget.entidadTipo,
            entidadId: widget.entidadId,
          ),
        ),
        Tab(
          text: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Actividades'),
              if (pendientesCount > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: theme.accentColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$pendientesCount',
                    style: theme.typography.caption?.copyWith(
                      color: Colors.white,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ],
          ),
          body: _ActividadesTab(
            entidadTipo: widget.entidadTipo,
            entidadId: widget.entidadId,
          ),
        ),
      ],
    );

    if (widget.height != null) {
      return SizedBox(height: widget.height, child: body);
    }
    return body;
  }
}

// ---------------------------------------------------------------------------
// Tab: Mensajes
// ---------------------------------------------------------------------------

class _MensajesTab extends ConsumerStatefulWidget {
  final String entidadTipo;
  final String entidadId;

  const _MensajesTab({required this.entidadTipo, required this.entidadId});

  @override
  ConsumerState<_MensajesTab> createState() => _MensajesTabState();
}

class _MensajesTabState extends ConsumerState<_MensajesTab> {
  ChatterRef get _ref => (
        entidadTipo: widget.entidadTipo,
        entidadId: widget.entidadId,
      );

  final _scrollController = ScrollController();
  final _textController = TextEditingController();
  final _adjuntosIds = <String>[];
  bool _esNotaInterna = false;
  bool _enviando = false;
  UploadCancelToken? _cancelToken;

  // Estado del upload en curso
  bool _subiendo = false;
  UploadProgress? _uploadProgress;

  @override
  void dispose() {
    _scrollController.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final mensajesAsync = ref.watch(chatterProvider(_ref));
    final esSeguidorAsync = ref.watch(chatterEsSeguidorProvider(_ref));

    return Column(
      children: [
        // Header con botón seguir
        _ChatterHeader(
          esSeguidorAsync: esSeguidorAsync,
          onSeguir: () async {
            await ref
                .read(chatterSeguimientoProvider(_ref).notifier)
                .seguir();
          },
          onDejarDeSeguir: () async {
            await ref
                .read(chatterSeguimientoProvider(_ref).notifier)
                .dejarDeSeguir();
          },
        ),

        // Sección de canales vinculados
        _CanalesVinculadosSection(chatterRef: _ref),

        // Lista de mensajes
        Expanded(
          child: mensajesAsync.when(
            loading: () => const Center(child: ProgressRing()),
            error: (e, _) => Center(
              child: InfoBar(
                title: Text('Error al cargar: $e'),
                severity: InfoBarSeverity.error,
              ),
            ),
            data: (mensajes) {
              if (mensajes.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        FluentIcons.chat,
                        size: 32,
                        color: theme.resources.textFillColorSecondary,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Sin mensajes aún',
                        style: theme.typography.body?.copyWith(
                          color: theme.resources.textFillColorSecondary,
                        ),
                      ),
                    ],
                  ),
                );
              }

              // Orden DESC (más reciente arriba, como Odoo)
              return ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                reverse: true,
                itemCount: mensajes.length,
                itemBuilder: (context, index) {
                  final mensaje = mensajes[index];
                  return _buildMensajeItem(context, mensaje);
                },
              );
            },
          ),
        ),

        // Botón de envío de mensaje externo (WhatsApp/Telegram/Email)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Align(
            alignment: Alignment.centerRight,
            child: EnviarMensajeExternoButton(
              entidadTipo: widget.entidadTipo,
              entidadId: widget.entidadId,
              compact: true,
            ),
          ),
        ),

        // Barra de compose
        _ComposeBar(
          controller: _textController,
          esNotaInterna: _esNotaInterna,
          adjuntosIds: List.unmodifiable(_adjuntosIds),
          enviando: _enviando,
          subiendo: _subiendo,
          uploadProgress: _uploadProgress,
          onToggleNota: () => setState(() => _esNotaInterna = !_esNotaInterna),
          onAdjuntar: _adjuntar,
          onEnviar: _enviar,
          onCancelarUpload: () => _cancelToken?.cancel(),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Construcción de items de mensaje
  // -------------------------------------------------------------------------

  Widget _buildMensajeItem(BuildContext context, ChatterMensaje m) {
    if (m.esLog) {
      return _LogSistemaItem(mensaje: m);
    }
    if (m.esActividad) {
      return _ActividadCompletadaItem(mensaje: m);
    }
    if (m.esEmail) {
      return _EmailEntrante(mensaje: m);
    }
    // mensajes de canales externos vinculados (WhatsApp, Telegram, Email API/SMTP)
    if (m.tipo == 'whatsapp' ||
        m.tipo == 'telegram' ||
        m.tipo == 'email_smtp' ||
        m.tipo == 'email_api') {
      return _MensajeExterno(mensaje: m);
    }
    // comentario (discusion o nota_interna)
    return _ComentarioItem(
      mensaje: m,
      entidadTipo: widget.entidadTipo,
      entidadId: widget.entidadId,
    );
  }

  // -------------------------------------------------------------------------
  // Upload de adjunto
  // -------------------------------------------------------------------------

  Future<void> _adjuntar() async {
    final empresaId =
        Supabase.instance.client.auth.currentSession?.user.userMetadata?['empresa_id']
            as String? ?? '';

    _cancelToken = UploadCancelToken();
    final progressCtrl = StreamController<UploadProgress>();

    progressCtrl.stream.listen((p) {
      if (mounted) setState(() => _uploadProgress = p);
    });

    if (mounted) setState(() => _subiendo = true);

    try {
      final file = await UploadService.pickFile();
      if (file == null) {
        await progressCtrl.close();
        if (mounted) setState(() => _subiendo = false);
        return;
      }

      final result = await UploadService.uploadResumable(
        file: file,
        empresaId: empresaId,
        entidadTipo: widget.entidadTipo,
        entidadId: widget.entidadId,
        progressController: progressCtrl,
        cancelToken: _cancelToken,
      );

      await progressCtrl.close();

      // Registrar en tabla adjuntos con tag 'chatter'
      final row = await Supabase.instance.client
          .rpc('registrar_adjunto', params: {
        'p_empresa_id': empresaId,
        'p_entidad_tipo': widget.entidadTipo,
        'p_entidad_id': widget.entidadId,
        'p_nombre': result.nombreOriginal,
        'p_nombre_original': result.nombreOriginal,
        'p_mime_type': result.mimeType,
        'p_tamanio_bytes': result.tamanioBytes,
        'p_storage_path': result.storagePath,
        'p_tags': ['chatter'],
      });

      String adjuntoId = '';
      if (row is Map<String, dynamic>) {
        adjuntoId = (row['id'] as String?) ?? '';
      } else if (row is String) {
        adjuntoId = row;
      }

      if (adjuntoId.isNotEmpty) {
        setState(() => _adjuntosIds.add(adjuntoId));
      }
    } on UploadException catch (e) {
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (_) => ContentDialog(
            title: const Text('Error al adjuntar'),
            content: Text(e.message),
            actions: [
              FilledButton(
                child: const Text('Cerrar'),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      // upload cancelado u otro error — ignorar silenciosamente
    } finally {
      _cancelToken = null;
      await progressCtrl.close().catchError((_) {});
      if (mounted) {
        setState(() {
          _subiendo = false;
          _uploadProgress = null;
        });
      }
    }
  }

  // -------------------------------------------------------------------------
  // Enviar mensaje
  // -------------------------------------------------------------------------

  Future<void> _enviar() async {
    final texto = _textController.text.trim();
    if (texto.isEmpty && _adjuntosIds.isEmpty) return;
    if (_enviando) return;

    setState(() => _enviando = true);
    try {
      await ref.read(chatterProvider(_ref).notifier).postMensaje(
            cuerpo: texto,
            subtype: _esNotaInterna ? 'nota_interna' : 'discusion',
            adjuntosIds: List.of(_adjuntosIds),
          );
      _textController.clear();
      setState(() => _adjuntosIds.clear());
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }
}

// ---------------------------------------------------------------------------
// Header con botón Seguir/Dejar de seguir
// ---------------------------------------------------------------------------

class _ChatterHeader extends StatelessWidget {
  final AsyncValue<bool> esSeguidorAsync;
  final VoidCallback onSeguir;
  final VoidCallback onDejarDeSeguir;

  const _ChatterHeader({
    required this.esSeguidorAsync,
    required this.onSeguir,
    required this.onDejarDeSeguir,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final esSeguidor = esSeguidorAsync.valueOrNull ?? false;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.resources.dividerStrokeColorDefault),
        ),
      ),
      child: Row(
        children: [
          Icon(
            FluentIcons.chat,
            size: 14,
            color: theme.resources.textFillColorSecondary,
          ),
          const SizedBox(width: 6),
          Text(
            'Chatter',
            style: theme.typography.bodyStrong,
          ),
          const Spacer(),
          if (esSeguidorAsync.isLoading)
            const SizedBox(
              width: 16,
              height: 16,
              child: ProgressRing(strokeWidth: 2),
            )
          else
            Button(
              onPressed: esSeguidor ? onDejarDeSeguir : onSeguir,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    esSeguidor
                        ? FluentIcons.unsubscribe
                        : FluentIcons.subscribe,
                    size: 12,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    esSeguidor ? 'Siguiendo' : 'Seguir',
                    style: theme.typography.caption,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Items de mensajes
// ---------------------------------------------------------------------------

/// Log de sistema: compacto, gris, sin burbuja.
class _LogSistemaItem extends StatelessWidget {
  final ChatterMensaje mensaje;
  const _LogSistemaItem({required this.mensaje});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final secondary = theme.resources.textFillColorSecondary;

    // Si tiene cambios de campo estructurados, los mostramos
    final cambios = mensaje.cambiosCampos;
    final tieneCambios = cambios.isNotEmpty;

    // Subtype cambio_estado: banner prominente
    if (mensaje.subtype == 'cambio_estado') {
      return _CambioEstadoBanner(mensaje: mensaje);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(FluentIcons.history, size: 12, color: secondary),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (tieneCambios)
                  ...cambios.map(
                    (c) => RichText(
                      text: TextSpan(
                        style: theme.typography.caption?.copyWith(
                          color: secondary,
                        ),
                        children: [
                          TextSpan(text: '${c.campo}: '),
                          if (c.antes != null)
                            TextSpan(
                              text: c.antes,
                              style: const TextStyle(
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                          if (c.antes != null && c.despues != null)
                            const TextSpan(text: ' → '),
                          if (c.despues != null)
                            TextSpan(
                              text: c.despues,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                        ],
                      ),
                    ),
                  )
                else if (mensaje.cuerpo != null)
                  Text(
                    mensaje.cuerpo!,
                    style: theme.typography.caption?.copyWith(color: secondary),
                  ),
                const SizedBox(height: 1),
                Text(
                  mensaje.tiempoRelativo(),
                  style: theme.typography.caption?.copyWith(
                    color: secondary,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Banner prominente para cambios de estado.
class _CambioEstadoBanner extends StatelessWidget {
  final ChatterMensaje mensaje;
  const _CambioEstadoBanner({required this.mensaje});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final cambios = mensaje.cambiosCampos;
    final antes = cambios.isNotEmpty ? cambios.first.antes : null;
    final despues = cambios.isNotEmpty ? cambios.first.despues : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: theme.accentColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: theme.accentColor.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          children: [
            Icon(FluentIcons.history, size: 14, color: theme.accentColor),
            const SizedBox(width: 8),
            Text('Estado: ', style: theme.typography.caption),
            if (antes != null) ...[
              Text(
                antes,
                style: theme.typography.caption?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.resources.textFillColorSecondary,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                FluentIcons.chevron_right,
                size: 10,
                color: theme.resources.textFillColorSecondary,
              ),
              const SizedBox(width: 6),
            ],
            if (despues != null)
              Text(
                despues,
                style: theme.typography.caption?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.accentColor,
                ),
              ),
            const Spacer(),
            Text(
              mensaje.tiempoRelativo(),
              style: theme.typography.caption?.copyWith(fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

/// Actividad completada: línea verde con checkmark.
class _ActividadCompletadaItem extends StatelessWidget {
  final ChatterMensaje mensaje;
  const _ActividadCompletadaItem({required this.mensaje});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(FluentIcons.check_mark, size: 12, color: Colors.green),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              mensaje.cuerpo ?? 'Actividad completada',
              style: theme.typography.caption?.copyWith(color: Colors.green),
            ),
          ),
          Text(
            mensaje.tiempoRelativo(),
            style: theme.typography.caption?.copyWith(
              fontSize: 10,
              color: theme.resources.textFillColorSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Email entrante: estilo compacto con asunto y remitente.
class _EmailEntrante extends StatelessWidget {
  final ChatterMensaje mensaje;
  const _EmailEntrante({required this.mensaje});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.resources.cardBackgroundFillColorDefault,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.resources.cardStrokeColorDefault),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(FluentIcons.mail, size: 14,
                color: theme.resources.textFillColorSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mensaje.autorNombre,
                    style: theme.typography.bodyStrong?.copyWith(fontSize: 12),
                  ),
                  if (mensaje.cuerpo != null)
                    Text(
                      mensaje.cuerpo!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.typography.caption,
                    ),
                ],
              ),
            ),
            Text(
              mensaje.tiempoRelativo(),
              style: theme.typography.caption?.copyWith(fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

/// Comentario / nota interna: burbuja con avatar.
class _ComentarioItem extends ConsumerWidget {
  final ChatterMensaje mensaje;
  final String entidadTipo;
  final String entidadId;

  const _ComentarioItem({
    required this.mensaje,
    required this.entidadTipo,
    required this.entidadId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = FluentTheme.of(context);
    final esNota = mensaje.esNotaInterna;

    // Color de fondo de la burbuja
    final bubbleColor = esNota
        ? const Color(0xFFFFF3CD) // amarillo/amber para nota interna
        : theme.resources.cardBackgroundFillColorDefault;

    final borderColor = esNota
        ? const Color(0xFFFFD700)
        : theme.resources.cardStrokeColorDefault;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          _AutorAvatar(
            nombre: mensaje.autorNombre,
            avatarUrl: mensaje.autorAvatar,
          ),
          const SizedBox(width: 8),
          // Burbuja
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(10),
                  bottomLeft: Radius.circular(10),
                  bottomRight: Radius.circular(10),
                ),
                border: Border.all(color: borderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Encabezado
                  Row(
                    children: [
                      Text(
                        mensaje.autorNombre,
                        style: theme.typography.bodyStrong
                            ?.copyWith(fontSize: 12),
                      ),
                      if (esNota) ...[
                        const SizedBox(width: 4),
                        const Icon(
                          FluentIcons.lock,
                          size: 10,
                          color: Color(0xFFB8860B),
                        ),
                        const SizedBox(width: 2),
                        Text(
                          'Nota interna',
                          style: theme.typography.caption?.copyWith(
                            color: const Color(0xFFB8860B),
                            fontSize: 10,
                          ),
                        ),
                      ],
                      const Spacer(),
                      Text(
                        mensaje.tiempoRelativo(),
                        style: theme.typography.caption
                            ?.copyWith(fontSize: 10),
                      ),
                    ],
                  ),
                  // Cuerpo
                  if (mensaje.cuerpo != null && mensaje.cuerpo!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    SelectableText(
                      mensaje.cuerpo!,
                      style: theme.typography.body?.copyWith(fontSize: 13),
                    ),
                  ],
                  // Adjuntos
                  if (mensaje.tieneAdjuntos) ...[
                    const SizedBox(height: 6),
                    _AdjuntosChips(adjuntosIds: mensaje.adjuntosIds),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Avatar del autor
// ---------------------------------------------------------------------------

class _AutorAvatar extends StatelessWidget {
  final String nombre;
  final String? avatarUrl;

  const _AutorAvatar({required this.nombre, this.avatarUrl});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final inicial = nombre.isNotEmpty ? nombre[0].toUpperCase() : '?';

    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          avatarUrl!,
          width: 30,
          height: 30,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _InicialCircle(
            inicial: inicial,
            theme: theme,
          ),
        ),
      );
    }

    return _InicialCircle(inicial: inicial, theme: theme);
  }
}

class _InicialCircle extends StatelessWidget {
  final String inicial;
  final FluentThemeData theme;

  const _InicialCircle({required this.inicial, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: theme.accentColor.withValues(alpha: 0.2),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          inicial,
          style: theme.typography.bodyStrong?.copyWith(
            fontSize: 13,
            color: theme.accentColor,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chips de adjuntos en un mensaje
// ---------------------------------------------------------------------------

class _AdjuntosChips extends StatefulWidget {
  final List<String> adjuntosIds;

  const _AdjuntosChips({required this.adjuntosIds});

  @override
  State<_AdjuntosChips> createState() => _AdjuntosChipsState();
}

class _AdjuntosChipsState extends State<_AdjuntosChips> {
  List<AdjuntoItem>? _adjuntos;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAdjuntos();
  }

  Future<void> _loadAdjuntos() async {
    if (!mounted) return;
    try {
      final rows = await Supabase.instance.client
          .from('adjuntos')
          .select()
          .inFilter('id', widget.adjuntosIds)
          .isFilter('eliminado_en', null);

      if (!mounted) return;
      setState(() {
        _adjuntos = (rows as List<dynamic>)
            .map((r) => AdjuntoItem.fromJson(r as Map<String, dynamic>))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 16,
        width: 16,
        child: ProgressRing(strokeWidth: 2),
      );
    }

    final items = _adjuntos ?? [];
    if (items.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: items
          .map((a) => _AdjuntoChip(adjunto: a))
          .toList(),
    );
  }
}

class _AdjuntoChip extends StatelessWidget {
  final AdjuntoItem adjunto;

  const _AdjuntoChip({required this.adjunto});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return GestureDetector(
      onTap: _open,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: theme.resources.cardBackgroundFillColorDefault,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.resources.cardStrokeColorDefault),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(FluentIcons.attach, size: 11,
                color: theme.resources.textFillColorSecondary),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                adjunto.nombre,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.typography.caption?.copyWith(fontSize: 11),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              adjunto.tamanioLabel,
              style: theme.typography.caption?.copyWith(
                fontSize: 10,
                color: theme.resources.textFillColorSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open() async {
    final url = await UploadService.createSignedUrl(adjunto.storagePath);
    if (url != null) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }
}

// ---------------------------------------------------------------------------
// Barra de composición de mensaje
// ---------------------------------------------------------------------------

class _ComposeBar extends StatelessWidget {
  final TextEditingController controller;
  final bool esNotaInterna;
  final List<String> adjuntosIds;
  final bool enviando;
  final bool subiendo;
  final UploadProgress? uploadProgress;
  final VoidCallback onToggleNota;
  final VoidCallback onAdjuntar;
  final VoidCallback onEnviar;
  final VoidCallback onCancelarUpload;

  const _ComposeBar({
    required this.controller,
    required this.esNotaInterna,
    required this.adjuntosIds,
    required this.enviando,
    required this.subiendo,
    required this.uploadProgress,
    required this.onToggleNota,
    required this.onAdjuntar,
    required this.onEnviar,
    required this.onCancelarUpload,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.resources.dividerStrokeColorDefault),
        ),
        color: esNotaInterna
            ? const Color(0xFFFFFAE6)
            : theme.resources.layerFillColorDefault,
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tipo de mensaje
          Row(
            children: [
              ToggleButton(
                checked: !esNotaInterna,
                onChanged: (_) {
                  if (esNotaInterna) onToggleNota();
                },
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(FluentIcons.chat, size: 12),
                    SizedBox(width: 4),
                    Text('Comentario'),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              ToggleButton(
                checked: esNotaInterna,
                onChanged: (_) {
                  if (!esNotaInterna) onToggleNota();
                },
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(FluentIcons.lock, size: 12),
                    SizedBox(width: 4),
                    Text('Nota interna'),
                  ],
                ),
              ),
              if (adjuntosIds.isNotEmpty) ...[
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${adjuntosIds.length} adjunto${adjuntosIds.length > 1 ? 's' : ''}',
                    style: theme.typography.caption?.copyWith(
                      color: theme.accentColor,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),

          // Progress de upload
          if (subiendo) ...[
            Row(
              children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: ProgressRing(strokeWidth: 2),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    uploadProgress != null
                        ? 'Subiendo: ${uploadProgress!.label}'
                        : 'Preparando…',
                    style: theme.typography.caption,
                  ),
                ),
                Button(
                  onPressed: onCancelarUpload,
                  child: const Text('Cancelar'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ProgressBar(
              value: uploadProgress != null
                  ? uploadProgress!.fraction * 100
                  : null,
            ),
            const SizedBox(height: 8),
          ],

          // TextBox
          TextBox(
            controller: controller,
            placeholder: esNotaInterna
                ? 'Escribe una nota interna...'
                : 'Escribe un comentario...',
            maxLines: 4,
            minLines: 2,
            expands: false,
            textInputAction: TextInputAction.newline,
          ),
          const SizedBox(height: 8),

          // Botones inferiores
          Row(
            children: [
              Button(
                onPressed: subiendo ? null : onAdjuntar,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(FluentIcons.attach, size: 14),
                    SizedBox(width: 4),
                    Text('Adjuntar'),
                  ],
                ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: enviando || subiendo ? null : onEnviar,
                child: enviando
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: ProgressRing(strokeWidth: 2),
                      )
                    : const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Enviar'),
                          SizedBox(width: 4),
                          Icon(FluentIcons.send, size: 12),
                        ],
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab: Actividades
// ---------------------------------------------------------------------------

class _ActividadesTab extends ConsumerWidget {
  final String entidadTipo;
  final String entidadId;

  const _ActividadesTab({
    required this.entidadTipo,
    required this.entidadId,
  });

  ChatterRef get _ref =>
      (entidadTipo: entidadTipo, entidadId: entidadId);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = FluentTheme.of(context);
    final actividadesAsync =
        ref.watch(chatterActividadesNotifierProvider(_ref));

    return Column(
      children: [
        Expanded(
          child: actividadesAsync.when(
            loading: () => const Center(child: ProgressRing()),
            error: (e, _) => Center(
              child: InfoBar(
                title: Text('Error: $e'),
                severity: InfoBarSeverity.error,
              ),
            ),
            data: (actividades) {
              if (actividades.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        FluentIcons.checkbox_composite,
                        size: 32,
                        color: theme.resources.textFillColorSecondary,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Sin actividades',
                        style: theme.typography.body?.copyWith(
                          color: theme.resources.textFillColorSecondary,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return ListView.separated(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: actividades.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (ctx, i) => _ActividadTile(
                  actividad: actividades[i],
                  onCompletar: () => _completarActividad(ctx, ref, actividades[i]),
                ),
              );
            },
          ),
        ),
        // Botón nueva actividad
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: Button(
              onPressed: () => _mostrarDialogNuevaActividad(context, ref),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(FluentIcons.add, size: 12),
                  SizedBox(width: 6),
                  Text('Nueva actividad'),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _completarActividad(
    BuildContext context,
    WidgetRef ref,
    ChatterActividad actividad,
  ) async {
    final resultCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => ContentDialog(
        title: const Text('Completar actividad'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(actividad.titulo),
            const SizedBox(height: 12),
            const Text('Resultado (opcional):'),
            const SizedBox(height: 6),
            TextBox(
              controller: resultCtrl,
              placeholder: 'Describe el resultado...',
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          Button(
            child: const Text('Cancelar'),
            onPressed: () => Navigator.pop(ctx, false),
          ),
          FilledButton(
            child: const Text('Completar'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    resultCtrl.dispose();
    if (confirmed == true) {
      await ref
          .read(chatterActividadesNotifierProvider(_ref).notifier)
          .completarActividad(
            actividad.id,
            resultado: resultCtrl.text.trim().isEmpty
                ? null
                : resultCtrl.text.trim(),
          );
    }
  }

  Future<void> _mostrarDialogNuevaActividad(
    BuildContext context,
    WidgetRef ref,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _NuevaActividadDialog(
        onCrear: (titulo, tipo, fechaLimite, descripcion) async {
          await ref
              .read(chatterActividadesNotifierProvider(_ref).notifier)
              .crearActividad(
                titulo: titulo,
                tipo: tipo,
                fechaLimite: fechaLimite,
                descripcion: descripcion,
              );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tile de actividad
// ---------------------------------------------------------------------------

class _ActividadTile extends StatelessWidget {
  final ChatterActividad actividad;
  final VoidCallback onCompletar;

  const _ActividadTile({
    required this.actividad,
    required this.onCompletar,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final completada = actividad.estaCompletada;

    Color estadoColor;
    switch (actividad.estado) {
      case 'vencida':
        estadoColor = Colors.red;
      case 'hoy':
        estadoColor = Colors.orange;
      case 'completada':
        estadoColor = theme.resources.textFillColorSecondary;
      default:
        estadoColor = theme.accentColor;
    }

    return Opacity(
      opacity: completada ? 0.55 : 1.0,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icono del tipo de actividad
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                _iconoTipo(actividad.tipo),
                size: 16,
                color: completada
                    ? theme.resources.textFillColorSecondary
                    : estadoColor,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    actividad.titulo,
                    style: theme.typography.body?.copyWith(
                      fontWeight: FontWeight.w600,
                      decoration: completada
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  Row(
                    children: [
                      Icon(
                        actividad.estado == 'vencida'
                            ? FluentIcons.warning
                            : FluentIcons.calendar,
                        size: 10,
                        color: estadoColor,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        actividad.fechaLimiteLabel,
                        style: theme.typography.caption?.copyWith(
                          color: estadoColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  if (actividad.descripcion != null &&
                      actividad.descripcion!.isNotEmpty)
                    Text(
                      actividad.descripcion!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.typography.caption?.copyWith(
                        color: theme.resources.textFillColorSecondary,
                      ),
                    ),
                ],
              ),
            ),
            // Botón completar (solo para pendientes)
            if (actividad.esPendiente)
              Tooltip(
                message: 'Marcar como completada',
                child: IconButton(
                  icon: Icon(
                    FluentIcons.check_mark,
                    size: 14,
                    color: Colors.green,
                  ),
                  onPressed: onCompletar,
                ),
              ),
          ],
        ),
      ),
    );
  }

  IconData _iconoTipo(String tipo) {
    switch (tipo) {
      case 'llamada':
        return FluentIcons.phone;
      case 'email':
        return FluentIcons.mail;
      case 'reunion':
        return FluentIcons.calendar;
      case 'documento':
        return FluentIcons.document;
      default:
        return FluentIcons.checkbox_composite;
    }
  }
}

// ---------------------------------------------------------------------------
// Dialog: Nueva actividad
// ---------------------------------------------------------------------------

class _NuevaActividadDialog extends StatefulWidget {
  final Future<void> Function(
    String titulo,
    String tipo,
    DateTime fechaLimite,
    String? descripcion,
  ) onCrear;

  const _NuevaActividadDialog({required this.onCrear});

  @override
  State<_NuevaActividadDialog> createState() => _NuevaActividadDialogState();
}

class _NuevaActividadDialogState extends State<_NuevaActividadDialog> {
  final _tituloCtrl = TextEditingController();
  final _descripCtrl = TextEditingController();
  String _tipo = 'tarea';
  DateTime _fechaLimite = DateTime.now().add(const Duration(days: 1));
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _tituloCtrl.dispose();
    _descripCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return ContentDialog(
      title: const Text('Nueva actividad'),
      constraints: const BoxConstraints(maxWidth: 420),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_error != null) ...[
            InfoBar(
              title: Text(_error!),
              severity: InfoBarSeverity.error,
            ),
            const SizedBox(height: 8),
          ],
          Text('Título *', style: theme.typography.bodyStrong),
          const SizedBox(height: 4),
          TextBox(
            controller: _tituloCtrl,
            placeholder: 'Descripción breve de la actividad',
          ),
          const SizedBox(height: 12),
          Text('Tipo', style: theme.typography.bodyStrong),
          const SizedBox(height: 4),
          ComboBox<String>(
            value: _tipo,
            items: const [
              ComboBoxItem(value: 'tarea', child: Text('Tarea')),
              ComboBoxItem(value: 'llamada', child: Text('Llamada')),
              ComboBoxItem(value: 'email', child: Text('Email')),
              ComboBoxItem(value: 'reunion', child: Text('Reunión')),
              ComboBoxItem(value: 'documento', child: Text('Documento')),
            ],
            onChanged: (v) => setState(() => _tipo = v ?? 'tarea'),
          ),
          const SizedBox(height: 12),
          Text('Fecha límite', style: theme.typography.bodyStrong),
          const SizedBox(height: 4),
          DatePicker(
            selected: _fechaLimite,
            onChanged: (d) => setState(() => _fechaLimite = d),
          ),
          const SizedBox(height: 12),
          Text('Descripción', style: theme.typography.bodyStrong),
          const SizedBox(height: 4),
          TextBox(
            controller: _descripCtrl,
            placeholder: 'Detalles opcionales...',
            maxLines: 3,
          ),
        ],
      ),
      actions: [
        Button(
          child: const Text('Cancelar'),
          onPressed: () => Navigator.pop(context),
        ),
        FilledButton(
          onPressed: _guardando ? null : _guardar,
          child: _guardando
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: ProgressRing(strokeWidth: 2),
                )
              : const Text('Crear actividad'),
        ),
      ],
    );
  }

  Future<void> _guardar() async {
    final titulo = _tituloCtrl.text.trim();
    if (titulo.isEmpty) {
      setState(() => _error = 'El título es obligatorio');
      return;
    }

    setState(() {
      _guardando = true;
      _error = null;
    });

    try {
      await widget.onCrear(
        titulo,
        _tipo,
        _fechaLimite,
        _descripCtrl.text.trim().isEmpty ? null : _descripCtrl.text.trim(),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _guardando = false;
        });
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Mensaje externo (WhatsApp / Telegram / Email)
// ---------------------------------------------------------------------------

/// Renderiza un mensaje del chatter que proviene de un canal externo vinculado.
class _MensajeExterno extends StatelessWidget {
  final ChatterMensaje mensaje;

  const _MensajeExterno({required this.mensaje});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    final (color, icon, label) = switch (mensaje.tipo) {
      'whatsapp' => (
          const Color(0xFF25D366),
          FluentIcons.chat,
          'WhatsApp',
        ),
      'telegram' => (
          const Color(0xFF229ED9),
          FluentIcons.send,
          'Telegram',
        ),
      'email_smtp' || 'email_api' => (
          theme.accentColor as Color,
          FluentIcons.mail,
          'Email',
        ),
      _ => (
          theme.accentColor as Color,
          FluentIcons.chat,
          mensaje.tipo,
        ),
    };

    final esEnviado = mensaje.metadatosJson['direccion'] == 'outbound';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: color, width: 3)),
          color: theme.resources.cardBackgroundFillColorDefault,
          borderRadius:
              const BorderRadius.horizontal(right: Radius.circular(8)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: theme.typography.caption?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        esEnviado
                            ? 'Enviado a ${mensaje.metadatosJson['destinatario'] ?? ''}'
                            : mensaje.autorNombre,
                        style: theme.typography.caption,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (mensaje.metadatosJson['via_contacto'] == true)
                        Text(
                          '(Conversación directa)',
                          style: theme.typography.caption?.copyWith(
                            color: theme.resources.textFillColorSecondary,
                            fontSize: 10,
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  mensaje.tiempoRelativo(),
                  style: theme.typography.caption?.copyWith(fontSize: 10),
                ),
              ],
            ),
            if (mensaje.cuerpo != null && mensaje.cuerpo!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                mensaje.cuerpo!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.typography.body?.copyWith(fontSize: 13),
              ),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: HyperlinkButton(
                onPressed: () => displayInfoBar(
                  context,
                  builder: (ctx, close) => InfoBar(
                    title: const Text('ID de conversación'),
                    content: Text(
                      mensaje.metadatosJson['conversacion_id']?.toString() ??
                          mensaje.id,
                    ),
                    action: IconButton(
                      icon: const Icon(FluentIcons.clear),
                      onPressed: close,
                    ),
                  ),
                ),
                child: const Text(
                  'Ver conversación →',
                  style: TextStyle(fontSize: 11),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sección "Canales vinculados" en el tab Mensajes
// ---------------------------------------------------------------------------

/// Sección colapsable que muestra las conversaciones externas vinculadas
/// a este registro y permite vincular nuevas o desvincular existentes.
class _CanalesVinculadosSection extends ConsumerStatefulWidget {
  final ChatterRef chatterRef;

  const _CanalesVinculadosSection({required this.chatterRef});

  @override
  ConsumerState<_CanalesVinculadosSection> createState() =>
      _CanalesVinculadasSectionState();
}

class _CanalesVinculadasSectionState
    extends ConsumerState<_CanalesVinculadosSection> {
  bool _expandida = true;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final vinculadasAsync =
        ref.watch(comConversacionesVinculadasProvider(widget.chatterRef));

    final count = vinculadasAsync.valueOrNull?.length ?? 0;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.resources.dividerStrokeColorDefault),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cabecera colapsable
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _expandida = !_expandida),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Icon(
                    _expandida
                        ? FluentIcons.chevron_down
                        : FluentIcons.chevron_right,
                    size: 10,
                    color: theme.resources.textFillColorSecondary,
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    FluentIcons.link,
                    size: 12,
                    color: theme.resources.textFillColorSecondary,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Canales vinculados',
                    style: theme.typography.caption?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (count > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: theme.accentColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$count',
                        style: theme.typography.caption?.copyWith(
                          color: theme.accentColor,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  // Botón vincular
                  Button(
                    onPressed: () => _mostrarDialogVincular(context),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(FluentIcons.add, size: 11),
                        SizedBox(width: 4),
                        Text('Vincular'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Lista de conversaciones vinculadas (colapsable)
          if (_expandida)
            vinculadasAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(8),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: ProgressRing(strokeWidth: 2),
                ),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Text(
                  'Error: $e',
                  style: theme.typography.caption
                      ?.copyWith(color: Colors.warningPrimaryColor),
                ),
              ),
              data: (lista) {
                if (lista.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    child: Text(
                      'Sin canales vinculados',
                      style: theme.typography.caption?.copyWith(
                        color: theme.resources.textFillColorSecondary,
                      ),
                    ),
                  );
                }
                return Column(
                  children: lista
                      .map((conv) => _CanalesVinculadoTile(
                            conv: conv,
                            onDesvincular: () => _desvincular(conv.id),
                          ))
                      .toList(),
                );
              },
            ),
        ],
      ),
    );
  }

  Future<void> _mostrarDialogVincular(BuildContext context) async {
    // Busca conversaciones externas existentes (WhatsApp/Telegram/Email) y las
    // vincula a este registro. Dirección: conversación → registro.
    await showDialog<void>(
      context: context,
      builder: (_) => _VincularConversacionDialog(chatterRef: widget.chatterRef),
    );
  }


  Future<void> _desvincular(String conversacionId) async {
    try {
      await ref
          .read(comVincularProvider(widget.chatterRef).notifier)
          .desvincular(conversacionId);
      if (mounted) {
        await displayInfoBar(
          context,
          builder: (ctx, close) => InfoBar(
            title: const Text('Conversación desvinculada'),
            severity: InfoBarSeverity.success,
            action:
                IconButton(icon: const Icon(FluentIcons.clear), onPressed: close),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        await displayInfoBar(
          context,
          builder: (ctx, close) => InfoBar(
            title: const Text('Error al desvincular'),
            content: Text(e.toString()),
            severity: InfoBarSeverity.error,
            action:
                IconButton(icon: const Icon(FluentIcons.clear), onPressed: close),
          ),
        );
      }
    }
  }
}

/// Tile de una conversación vinculada con botón de desvincular.
class _CanalesVinculadoTile extends StatelessWidget {
  final ComConversacionVinculada conv;
  final VoidCallback onDesvincular;

  const _CanalesVinculadoTile({
    required this.conv,
    required this.onDesvincular,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    final (color, icon) = switch (conv.canal) {
      'whatsapp' => (const Color(0xFF25D366), FluentIcons.chat),
      'telegram' => (const Color(0xFF229ED9), FluentIcons.send),
      'email_smtp' || 'email_api' => (theme.accentColor as Color, FluentIcons.mail),
      _ => (theme.accentColor as Color, FluentIcons.chat),
    };

    final tiempoRelativo = conv.ultimoMensajeEn == null
        ? ''
        : () {
            final diff =
                DateTime.now().difference(conv.ultimoMensajeEn!);
            if (diff.inMinutes < 1) return 'ahora';
            if (diff.inMinutes < 60) return 'hace ${diff.inMinutes}m';
            if (diff.inHours < 24) return 'hace ${diff.inHours}h';
            if (diff.inDays == 1) return 'ayer';
            return 'hace ${diff.inDays}d';
          }();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: conv.activa ? color : theme.inactiveColor,
            ),
          ),
          const SizedBox(width: 8),
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  conv.canalLabel,
                  style: theme.typography.caption?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                Text(
                  conv.displayName,
                  style: theme.typography.caption,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (tiempoRelativo.isNotEmpty)
            Text(
              tiempoRelativo,
              style: theme.typography.caption?.copyWith(fontSize: 10),
            ),
          const SizedBox(width: 6),
          Tooltip(
            message: 'Desvincular conversación',
            child: IconButton(
              icon: Icon(
                FluentIcons.remove_link,
                size: 13,
                color: theme.resources.textFillColorSecondary,
              ),
              onPressed: onDesvincular,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dialog: Vincular conversación existente a este registro
// ---------------------------------------------------------------------------

class _VincularConversacionDialog extends ConsumerStatefulWidget {
  final ChatterRef chatterRef;

  const _VincularConversacionDialog({required this.chatterRef});

  @override
  ConsumerState<_VincularConversacionDialog> createState() =>
      _VincularConversacionDialogState();
}

class _VincularConversacionDialogState
    extends ConsumerState<_VincularConversacionDialog> {
  final _busquedaCtrl = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _resultados = [];
  bool _buscando = false;
  bool _vinculando = false;
  String? _error;

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onBusquedaChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _buscar(value));
  }

  Future<void> _buscar(String query) async {
    if (!mounted) return;
    setState(() => _buscando = true);
    try {
      final rows = await Supabase.instance.client
          .from('com_conversaciones')
          .select('id, canal, destinatario_ref, destinatario_nombre, entidad_id')
          .isFilter('entidad_id', null)
          .ilike('destinatario_ref', '%$query%')
          .limit(20);

      if (!mounted) return;
      setState(() {
        _resultados = (rows as List<dynamic>)
            .map((r) => r as Map<String, dynamic>)
            .toList();
        _buscando = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _buscando = false;
        });
      }
    }
  }

  Future<void> _vincular(String conversacionId) async {
    setState(() => _vinculando = true);
    try {
      await ref
          .read(comVincularProvider(widget.chatterRef).notifier)
          .vincular(conversacionId);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _vinculando = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return ContentDialog(
      title: const Text('Vincular conversación'),
      constraints: const BoxConstraints(maxWidth: 460, maxHeight: 520),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Busca una conversación no vinculada para asociarla a este registro.',
            style: theme.typography.caption,
          ),
          const SizedBox(height: 10),
          TextBox(
            controller: _busquedaCtrl,
            placeholder: 'Buscar por número, email o nombre...',
            onChanged: _onBusquedaChanged,
            prefix: const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(FluentIcons.search, size: 13),
            ),
          ),
          const SizedBox(height: 8),
          if (_error != null) ...[
            InfoBar(
              title: Text(_error!),
              severity: InfoBarSeverity.error,
            ),
            const SizedBox(height: 8),
          ],
          if (_buscando)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: ProgressRing(),
              ),
            )
          else if (_resultados.isEmpty && _busquedaCtrl.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Sin resultados',
                style: theme.typography.body?.copyWith(
                  color: theme.resources.textFillColorSecondary,
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: _resultados.length,
                itemBuilder: (ctx, i) {
                  final r = _resultados[i];
                  final canal = r['canal'] as String? ?? '';
                  final ref2 = r['destinatario_ref'] as String? ?? '';
                  final nombre = r['destinatario_nombre'] as String?;

                  final (color, icon) = switch (canal) {
                    'whatsapp' => (
                        const Color(0xFF25D366),
                        FluentIcons.chat
                      ),
                    'telegram' => (
                        const Color(0xFF229ED9),
                        FluentIcons.send
                      ),
                    'email_smtp' ||
                    'email_api' => (
                        theme.accentColor as Color,
                        FluentIcons.mail
                      ),
                    _ => (theme.accentColor as Color, FluentIcons.chat),
                  };

                  return GestureDetector(
                    onTap: _vinculando ? null : () => _vincular(r['id'] as String),
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color:
                            theme.resources.cardBackgroundFillColorDefault,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: theme.resources.cardStrokeColorDefault,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(icon, size: 16, color: color),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  nombre?.isNotEmpty == true ? nombre! : ref2,
                                  style: theme.typography.bodyStrong
                                      ?.copyWith(fontSize: 13),
                                ),
                                Text(
                                  ref2,
                                  style: theme.typography.caption?.copyWith(
                                    color: theme.resources
                                        .textFillColorSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            canal,
                            style: theme.typography.caption?.copyWith(
                              color: color,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
      actions: [
        Button(
          onPressed: _vinculando ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        if (_vinculando)
          const SizedBox(
            width: 20,
            height: 20,
            child: ProgressRing(strokeWidth: 2),
          ),
      ],
    );
  }
}
