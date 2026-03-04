import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/providers/empresa_provider.dart';
import '../../../core/theme/pilar_breakpoints.dart'; // BuildContextBreakpoints extension
import '../../../core/widgets/chatter_vincular_dialog.dart';
import '../../../core/widgets/user_card.dart';
import '../../entidades/widgets/contacto_picker.dart';
import '../models/com_conversacion.dart';
import '../models/com_mensaje.dart';
import '../providers/conversaciones_provider.dart';
import '../providers/mensajes_provider.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Invoca el Edge Function sender del canal para envío inmediato.
/// Fire-and-forget — errores se ignoran (el cron actúa como fallback).
void _invocarSender(String canal) {
  final fnName = switch (canal) {
    'telegram' => 'com-telegram-sender',
    'whatsapp' => 'com-whatsapp-sender',
    _ => null,
  };
  if (fnName == null) return;
  Supabase.instance.client.functions.invoke(fnName, body: {}).ignore();
}

/// Retorna el ícono y color según el canal de comunicación.
({IconData icon, Color color}) _canalMeta(String canal) {
  return switch (canal) {
    'whatsapp' => (icon: FluentIcons.chat_bot, color: const Color(0xFF25D366)),
    'telegram' => (icon: FluentIcons.send, color: const Color(0xFF0088CC)),
    'email_api' || 'email_smtp' => (
        icon: FluentIcons.mail,
        color: const Color(0xFF0078D4)
      ),
    _ => (icon: FluentIcons.chat, color: const Color(0xFF666666)),
  };
}

/// Formato relativo de timestamp (hace X min, ayer, etc.).
String _relativo(DateTime? dt) {
  if (dt == null) return '';
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'ahora';
  if (diff.inMinutes < 60) return 'hace ${diff.inMinutes}m';
  if (diff.inHours < 24) return 'hace ${diff.inHours}h';
  if (diff.inDays == 1) return 'ayer';
  if (diff.inDays < 7) return 'hace ${diff.inDays}d';
  return '${dt.day}/${dt.month}/${dt.year}';
}

// ---------------------------------------------------------------------------
// ConversacionesTab
// ---------------------------------------------------------------------------

class ConversacionesTab extends ConsumerWidget {
  /// Cuando `true` muestra conversaciones de cuentas de empresa
  /// (`usuario_id IS NULL`). Cuando `false` muestra las del usuario actual
  /// (`usuario_id = current_user`).
  final bool esEmpresa;

  const ConversacionesTab({super.key, this.esEmpresa = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final convSeleccionada = ref.watch(convSeleccionadaProvider);
    final isDesktop = context.isDesktop; // ≥ 900px

    if (isDesktop) {
      // Dos paneles lado a lado
      return Row(
        children: [
          SizedBox(
            width: 300,
            child: _PanelLista(esEmpresa: esEmpresa),
          ),
          const Divider(direction: Axis.vertical),
          const Expanded(child: _PanelDetalle()),
        ],
      );
    }

    // Móvil/tablet: stack de páginas
    if (convSeleccionada == null) {
      return _PanelLista(esEmpresa: esEmpresa);
    }
    return _PanelDetalleMovil();
  }
}

// ---------------------------------------------------------------------------
// Panel Lista (izquierdo)
// ---------------------------------------------------------------------------

class _PanelLista extends ConsumerWidget {
  final bool esEmpresa;

  const _PanelLista({required this.esEmpresa});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversaciones = ref.watch(conversacionesFiltradas);
    final canal = ref.watch(convFiltroCanal);
    final theme = FluentTheme.of(context);

    return Column(
      children: [
        // ---- Encabezado de scope ----
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              Icon(
                esEmpresa ? FluentIcons.company_directory : FluentIcons.contact,
                size: 16,
                color: theme.inactiveColor,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  esEmpresa ? 'Mensajes de empresa' : 'Mis mensajes',
                  style: theme.typography.caption?.copyWith(
                    color: theme.inactiveColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Tooltip(
                message: 'Nueva conversación',
                child: IconButton(
                  icon: const Icon(FluentIcons.add, size: 14),
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (ctx) => UncontrolledProviderScope(
                      container: ProviderScope.containerOf(context),
                      child: const _NuevaConversacionDialog(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // ---- Filtros de canal ----
        _FiltroCanal(canalActivo: canal),

        // ---- Lista ----
        Expanded(
          child: conversaciones.when(
            loading: () => const Center(child: ProgressRing()),
            error: (e, _) => Center(
              child: InfoBar(
                title: const Text('Error cargando conversaciones'),
                content: Text(e.toString()),
                severity: InfoBarSeverity.error,
              ),
            ),
            data: (lista) {
              if (lista.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(FluentIcons.chat, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        'Sin conversaciones',
                        style: FluentTheme.of(context).typography.subtitle,
                      ),
                      const SizedBox(height: 4),
                      const Text('Pulsa + para iniciar una conversación'),
                    ],
                  ),
                );
              }
              return ListView.builder(
                itemCount: lista.length,
                itemBuilder: (ctx, i) => _ConvListTile(conv: lista[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Filtro Canal
// ---------------------------------------------------------------------------

class _FiltroCanal extends ConsumerWidget {
  final String? canalActivo;

  const _FiltroCanal({required this.canalActivo});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const canales = [
      (label: 'Todos', value: null),
      (label: 'WhatsApp', value: 'whatsapp'),
      (label: 'Telegram', value: 'telegram'),
      (label: 'Email', value: 'email_api'),
    ];

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Wrap(
        spacing: 6,
        children: canales
            .map(
              (c) => Button(
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.all(
                    canalActivo == c.value
                        ? FluentTheme.of(context).accentColor
                        : null,
                  ),
                ),
                onPressed: () => ref
                    .read(convFiltroCanal.notifier)
                    .state = c.value,
                child: Text(
                  c.label,
                  style: TextStyle(
                    color: canalActivo == c.value ? Colors.white : null,
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tile de conversación
// ---------------------------------------------------------------------------

class _ConvListTile extends ConsumerWidget {
  final ComConversacion conv;

  const _ConvListTile({required this.conv});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seleccionada = ref.watch(convSeleccionadaProvider) == conv.id;
    final meta = _canalMeta(conv.canal);
    final theme = FluentTheme.of(context);

    return ListTile.selectable(
      selected: seleccionada,
      onSelectionChange: (_) =>
          ref.read(convSeleccionadaProvider.notifier).state = conv.id,
      leading: CircleAvatar(
        backgroundColor: meta.color.withValues(alpha: 0.15),
        child: Icon(meta.icon, color: meta.color, size: 20),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              conv.displayName,
              style: theme.typography.body,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          _CanalBadge(canal: conv.canal, color: meta.color),
          const SizedBox(width: 4),
          // Indicador ventana WA
          if (conv.canal == 'whatsapp')
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: conv.ventanaWaActiva ? Colors.green : Colors.grey,
              ),
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (conv.ultimoMensajeEn != null)
            Row(
              children: [
                Expanded(
                  child: Text(
                    conv.canal == 'whatsapp'
                        ? 'WhatsApp · ${conv.destinatarioRef}'
                        : conv.destinatarioRef,
                    style: theme.typography.caption,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  _relativo(conv.ultimoMensajeEn),
                  style: theme.typography.caption?.copyWith(
                    color: theme.inactiveColor,
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
// Panel Detalle (derecho, desktop)
// ---------------------------------------------------------------------------

class _PanelDetalle extends ConsumerWidget {
  const _PanelDetalle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conv = ref.watch(convSeleccionadaDetalleProvider);
    if (conv == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(FluentIcons.chat, size: 64),
            const SizedBox(height: 16),
            Text(
              'Selecciona una conversación',
              style: FluentTheme.of(context).typography.subtitle,
            ),
          ],
        ),
      );
    }
    return _ThreadView(conv: conv);
  }
}

// ---------------------------------------------------------------------------
// Panel Detalle Móvil (con botón back)
// ---------------------------------------------------------------------------

class _PanelDetalleMovil extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conv = ref.watch(convSeleccionadaDetalleProvider);
    if (conv == null) return const SizedBox.shrink();
    return Column(
      children: [
        // Botón volver
        Padding(
          padding: const EdgeInsets.only(left: 8, top: 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(FluentIcons.back),
                onPressed: () =>
                    ref.read(convSeleccionadaProvider.notifier).state = null,
              ),
              Expanded(
                child: Text(
                  conv.displayName,
                  style: FluentTheme.of(context).typography.subtitle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        Expanded(child: _ThreadView(conv: conv)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// ThreadView — header + mensajes + input
// ---------------------------------------------------------------------------

class _ThreadView extends ConsumerStatefulWidget {
  final ComConversacion conv;

  const _ThreadView({required this.conv});

  @override
  ConsumerState<_ThreadView> createState() => _ThreadViewState();
}

class _ThreadViewState extends ConsumerState<_ThreadView> {
  bool _desvinculando = false;
  final _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients &&
          _scrollCtrl.position.maxScrollExtent > 0) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _mostrarDialogVincular() async {
    await showDialog<void>(
      context: context,
      builder: (_) => ChatterVincularDialog(
        conversacionId: widget.conv.id,
        onVincular: (entidadTipo, entidadId) {
          ref.invalidate(conversacionesProvider);
        },
      ),
    );
  }

  Future<void> _desvincularConversacion() async {
    setState(() => _desvinculando = true);
    try {
      await Supabase.instance.client.rpc('com_desvincular_conversacion',
          params: {'p_conversacion_id': widget.conv.id});
      if (mounted) {
        ref.invalidate(conversacionesProvider);
        await displayInfoBar(
          context,
          builder: (ctx, close) => InfoBar(
            title: const Text('Conversación desvinculada'),
            severity: InfoBarSeverity.success,
            action: IconButton(
                icon: const Icon(FluentIcons.clear), onPressed: close),
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
            action: IconButton(
                icon: const Icon(FluentIcons.clear), onPressed: close),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _desvinculando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mensajesAsync = ref.watch(mensajesProvider(widget.conv.id));
    final meta = _canalMeta(widget.conv.canal);
    final theme = FluentTheme.of(context);
    final conv = widget.conv;

    // Auto-scroll al fondo cuando llegan mensajes nuevos vía Realtime.
    ref.listen<AsyncValue<List<ComMensaje>>>(
      mensajesProvider(widget.conv.id),
      (_, next) { if (next.hasValue) _scrollToBottom(); },
    );

    return Column(
      children: [
        // ---- Header ----
        Container(
          padding: EdgeInsets.zero,
          color: theme.micaBackgroundColor,
          child: Row(
            children: [
              Expanded(
                child: UserCard(
                  nombre: conv.displayName,
                  email: conv.destinatarioRef,
                  leading: CircleAvatar(
                    backgroundColor: meta.color.withValues(alpha: 0.15),
                    child: Icon(meta.icon, color: meta.color, size: 18),
                  ),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                ),
              ),
              // Botón vincular / desvincular
              if (_desvinculando)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: ProgressRing(strokeWidth: 2),
                )
              else if (conv.entidadId == null)
                Button(
                  onPressed: _mostrarDialogVincular,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(FluentIcons.link, size: 14),
                      SizedBox(width: 6),
                      Text('Vincular a registro'),
                    ],
                  ),
                )
              else
                Button(
                  onPressed: _desvincularConversacion,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(FluentIcons.remove_link, size: 14),
                      const SizedBox(width: 6),
                      Text('Vinculada a ${conv.entidadTipo ?? ''}'),
                    ],
                  ),
                ),
              const SizedBox(width: 6),
              // Botón refrescar
              IconButton(
                icon: const Icon(FluentIcons.refresh),
                onPressed: () =>
                    ref.invalidate(mensajesProvider(conv.id)),
              ),
            ],
          ),
        ),

        // ---- Banner ventana WA vencida ----
        if (conv.canal == 'whatsapp' && !conv.ventanaWaActiva)
          const InfoBar(
            title: Text('Ventana de 24h vencida'),
            content: Text(
              'Solo puedes enviar plantillas de mensaje aprobadas por Meta.',
            ),
            severity: InfoBarSeverity.warning,
            isIconVisible: true,
          ),

        // ---- Thread de mensajes ----
        Expanded(
          child: mensajesAsync.when(
            loading: () => const Center(child: ProgressRing()),
            error: (e, _) => Center(
              child: InfoBar(
                title: const Text('Error cargando mensajes'),
                content: Text(e.toString()),
                severity: InfoBarSeverity.error,
              ),
            ),
            data: (mensajes) {
              if (mensajes.isEmpty) {
                return Center(
                  child: Text(
                    'Sin mensajes',
                    style: theme.typography.body
                        ?.copyWith(color: theme.inactiveColor),
                  ),
                );
              }
              return ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.all(12),
                itemCount: mensajes.length,
                itemBuilder: (ctx, i) => _MensajeBubble(msg: mensajes[i]),
              );
            },
          ),
        ),

        // ---- Barra de composición ----
        _ComposicionBar(conv: conv),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Badge de canal (WA / TG / Email)
// ---------------------------------------------------------------------------

class _CanalBadge extends StatelessWidget {
  final String canal;
  final Color color;

  const _CanalBadge({required this.canal, required this.color});

  @override
  Widget build(BuildContext context) {
    final label = switch (canal) {
      'whatsapp' => 'WA',
      'telegram' => 'TG',
      'email_api' || 'email_smtp' => 'Mail',
      _ => canal.substring(0, 2).toUpperCase(),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          color: color,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Burbuja de mensaje
// ---------------------------------------------------------------------------

class _MensajeBubble extends StatelessWidget {
  final ComMensaje msg;

  const _MensajeBubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    final esOutbound = msg.esOutbound;
    final theme = FluentTheme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Align(
        alignment:
            esOutbound ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.65,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: esOutbound
                ? theme.accentColor.withValues(alpha: 0.18)
                : theme.cardColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(12),
              topRight: const Radius.circular(12),
              bottomLeft: Radius.circular(esOutbound ? 12 : 2),
              bottomRight: Radius.circular(esOutbound ? 2 : 12),
            ),
            border: Border.all(
              color: theme.resources.controlStrokeColorDefault,
              width: 0.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: esOutbound
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              // Asunto (email)
              if (msg.asunto != null && msg.asunto!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(msg.asunto!, style: theme.typography.bodyStrong),
                ),
              // Media adjuntos
              if (msg.tieneMedia)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _MediaWidget(adjunto: msg.adjuntos.first),
                ),
              // Cuerpo (texto o caption)
              if (msg.cuerpo != null && msg.cuerpo!.isNotEmpty &&
                  !msg.cuerpo!.startsWith('📷') &&
                  !msg.cuerpo!.startsWith('🎥') &&
                  !msg.cuerpo!.startsWith('🎵') &&
                  !msg.cuerpo!.startsWith('🎤') &&
                  !msg.cuerpo!.startsWith('📎') &&
                  !msg.cuerpo!.startsWith('⭕') &&
                  !msg.cuerpo!.startsWith('🎭') &&
                  !msg.tieneMedia)
                Text(msg.cuerpo!),
              // Caption + texto cuando hay media
              if (msg.tieneMedia && msg.cuerpo != null && msg.cuerpo!.isNotEmpty)
                Text(msg.cuerpo!, style: theme.typography.caption),
              // Solo emoji/texto de display cuando no hay media real
              if (!msg.tieneMedia && (msg.cuerpo == null || msg.cuerpo!.isEmpty ||
                  msg.cuerpo!.startsWith('📷') || msg.cuerpo!.startsWith('🎥') ||
                  msg.cuerpo!.startsWith('🎵') || msg.cuerpo!.startsWith('🎤') ||
                  msg.cuerpo!.startsWith('📎') || msg.cuerpo!.startsWith('⭕') ||
                  msg.cuerpo!.startsWith('🎭')))
                Text(msg.cuerpo ?? '', style: theme.typography.body),
              const SizedBox(height: 4),
              // Footer: timestamp + estado
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _relativo(msg.enviadoEn ?? msg.creadoEn),
                    style: theme.typography.caption
                        ?.copyWith(color: theme.inactiveColor, fontSize: 10),
                  ),
                  if (esOutbound) ...[
                    const SizedBox(width: 4),
                    _EstadoIcon(estado: msg.estado, esFallido: msg.esFallido),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Widget de media (imagen, video, audio, documento)
// ---------------------------------------------------------------------------

class _MediaWidget extends StatelessWidget {
  final ComAdjunto adjunto;
  const _MediaWidget({required this.adjunto});

  @override
  Widget build(BuildContext context) {
    if (adjunto.esImagen) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          adjunto.url,
          width: 220,
          fit: BoxFit.cover,
          loadingBuilder: (_, child, progress) => progress == null
              ? child
              : const SizedBox(
                  width: 220, height: 140,
                  child: Center(child: ProgressRing()),
                ),
          errorBuilder: (_, __, ___) => const SizedBox(
            width: 220, height: 100,
            child: Center(child: Icon(FluentIcons.image_pixel, size: 40)),
          ),
        ),
      );
    }

    if (adjunto.esVideo) {
      return _MediaTile(
        icon: FluentIcons.my_movies_t_v,
        label: adjunto.nombre,
        url: adjunto.url,
      );
    }

    if (adjunto.esAudio) {
      return _MediaTile(
        icon: FluentIcons.volume3,
        label: adjunto.tipo == 'voz' ? 'Nota de voz' : adjunto.nombre,
        url: adjunto.url,
      );
    }

    // documento / sticker / otros
    return _MediaTile(
      icon: FluentIcons.page,
      label: adjunto.nombre,
      url: adjunto.url,
    );
  }
}

class _MediaTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String url;
  const _MediaTile({required this.icon, required this.label, required this.url});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return GestureDetector(
      onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: theme.resources.subtleFillColorSecondary,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.resources.controlStrokeColorDefault),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: theme.typography.caption,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(FluentIcons.download, size: 14),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ícono de estado del mensaje outbound
// ---------------------------------------------------------------------------

class _EstadoIcon extends StatelessWidget {
  final String estado;
  final bool esFallido;

  const _EstadoIcon({required this.estado, required this.esFallido});

  @override
  Widget build(BuildContext context) {
    if (esFallido) {
      return const Icon(FluentIcons.error_badge, size: 12, color: Colors.warningPrimaryColor);
    }
    return switch (estado) {
      'leido' => const Icon(FluentIcons.read, size: 12, color: Color(0xFF0078D4)),
      'entregado' => const Icon(FluentIcons.check_mark, size: 12),
      'enviado' => const Icon(FluentIcons.send, size: 12),
      _ => const SizedBox.shrink(),
    };
  }
}

// ---------------------------------------------------------------------------
// Barra de composición
// ---------------------------------------------------------------------------

class _ComposicionBar extends ConsumerStatefulWidget {
  final ComConversacion conv;

  const _ComposicionBar({required this.conv});

  @override
  ConsumerState<_ComposicionBar> createState() => _ComposicionBarState();
}

class _ComposicionBarState extends ConsumerState<_ComposicionBar> {
  final _ctrl = TextEditingController();
  bool _enviando = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    final texto = _ctrl.text.trim();
    if (texto.isEmpty || _enviando) return;

    final conv = widget.conv;
    final empresaId = ref.read(empresaActivaIdProvider);
    if (empresaId == null) return;

    setState(() => _enviando = true);
    try {
      await Supabase.instance.client.from('com_mensajes').insert({
        'empresa_id': empresaId,
        'cuenta_id': conv.cuentaId,
        'conversacion_id': conv.id,
        'tipo': 'outbound',
        'canal': conv.canal,
        'destinatario_ref': conv.destinatarioRef,
        'cuerpo': texto,
        'estado': 'pendiente',
      });
      _ctrl.clear();
      // Invocar el sender inmediatamente para envío en tiempo real.
      // Fire-and-forget: el cron es el fallback; no bloqueamos la UI.
      _invocarSender(conv.canal);
    } on Exception catch (e) {
      if (mounted) {
        await displayInfoBar(
          context,
          builder: (ctx, close) => InfoBar(
            title: const Text('Error al enviar'),
            content: Text(e.toString()),
            severity: InfoBarSeverity.error,
            action: IconButton(icon: const Icon(FluentIcons.clear), onPressed: close),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    final puedeEscribirLibre =
        widget.conv.ventanaWaActiva || widget.conv.canal != 'whatsapp';

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluentTheme.of(context).micaBackgroundColor,
        border: Border(
          top: BorderSide(
            color: FluentTheme.of(context).resources.controlStrokeColorDefault,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: puedeEscribirLibre
                ? TextBox(
                    controller: _ctrl,
                    placeholder: 'Escribe un mensaje...',
                    maxLines: null,
                    enabled: !_enviando,
                    onSubmitted: (_) => _enviar(),
                    textInputAction: TextInputAction.newline,
                  )
                : const Text(
                    'Ventana vencida — solo plantillas disponibles',
                    style: TextStyle(fontStyle: FontStyle.italic),
                  ),
          ),
          const SizedBox(width: 8),
          if (_enviando)
            const SizedBox(width: 36, height: 36, child: ProgressRing())
          else
            IconButton(
              icon: const Icon(FluentIcons.send),
              onPressed: puedeEscribirLibre ? _enviar : null,
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Diálogo: Nueva conversación outbound
// ---------------------------------------------------------------------------

class _NuevaConversacionDialog extends ConsumerStatefulWidget {
  const _NuevaConversacionDialog();

  @override
  ConsumerState<_NuevaConversacionDialog> createState() =>
      _NuevaConversacionDialogState();
}

class _NuevaConversacionDialogState
    extends ConsumerState<_NuevaConversacionDialog> {
  String _canal = 'whatsapp';
  String? _cuentaId;
  String? _contactoId;
  final _destCtrl = TextEditingController();
  final _nombreCtrl = TextEditingController();
  final _mensajeCtrl = TextEditingController();
  bool _enviando = false;

  @override
  void dispose() {
    _destCtrl.dispose();
    _nombreCtrl.dispose();
    _mensajeCtrl.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    final dest = _destCtrl.text.trim();
    final cuerpo = _mensajeCtrl.text.trim();
    if (_cuentaId == null || dest.isEmpty || cuerpo.isEmpty) {
      displayInfoBar(
        context,
        builder: (ctx, close) => InfoBar(
          title: const Text('Completa los campos requeridos'),
          content: const Text('Cuenta, destinatario y mensaje son obligatorios.'),
          severity: InfoBarSeverity.warning,
          action: IconButton(
            icon: const Icon(FluentIcons.clear),
            onPressed: close,
          ),
        ),
      );
      return;
    }

    final empresaId = ref.read(empresaActivaIdProvider);
    if (empresaId == null) return;

    setState(() => _enviando = true);
    try {
      // 1. UPSERT conversación (crea o reutiliza si ya existe para ese canal+cuenta+dest)
      final convData = await Supabase.instance.client
          .from('com_conversaciones')
          .upsert(
            {
              'empresa_id': empresaId,
              'cuenta_id': _cuentaId,
              'canal': _canal,
              'destinatario_ref': dest,
              if (_nombreCtrl.text.trim().isNotEmpty)
                'destinatario_nombre': _nombreCtrl.text.trim(),
              if (_contactoId != null) 'contacto_id': _contactoId,
              'activo': true,
              'ultimo_mensaje_en': DateTime.now().toIso8601String(),
            },
            onConflict: 'empresa_id,cuenta_id,destinatario_ref',
          )
          .select('id')
          .single();

      final convId = convData['id'] as String;

      // 2. INSERT mensaje outbound (estado pendiente → cron/sender lo envía)
      await Supabase.instance.client.from('com_mensajes').insert({
        'empresa_id': empresaId,
        'cuenta_id': _cuentaId,
        'conversacion_id': convId,
        'tipo': 'outbound',
        'canal': _canal,
        'destinatario_ref': dest,
        'cuerpo': cuerpo,
        'estado': 'pendiente',
      });

      // 3. Invocar sender inmediatamente (fire-and-forget)
      _invocarSender(_canal);

      // 4. Seleccionar la conversación recién creada
      ref.read(convSeleccionadaProvider.notifier).state = convId;
      ref.invalidate(conversacionesProvider);

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        displayInfoBar(
          context,
          builder: (ctx, close) => InfoBar(
            title: const Text('Error al enviar'),
            content: Text(e.toString()),
            severity: InfoBarSeverity.error,
            action: IconButton(
              icon: const Icon(FluentIcons.clear),
              onPressed: close,
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cuentasAsync = ref.watch(cuentasOutboundProvider);

    return ContentDialog(
      title: const Text('Nueva conversación'),
      constraints: const BoxConstraints(maxWidth: 460),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ---- Canal ----
            InfoLabel(
              label: 'Canal',
              child: Row(
                children: [
                  for (final c in [
                    (value: 'whatsapp', label: 'WhatsApp', icon: FluentIcons.chat_bot),
                    (value: 'telegram', label: 'Telegram', icon: FluentIcons.send),
                  ]) ...[
                    Button(
                      style: ButtonStyle(
                        backgroundColor: WidgetStateProperty.all(
                          _canal == c.value
                              ? FluentTheme.of(context).accentColor
                              : null,
                        ),
                      ),
                      onPressed: () => setState(() {
                        _canal = c.value;
                        _cuentaId = null;
                      }),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(c.icon, size: 14,
                              color: _canal == c.value ? Colors.white : null),
                          const SizedBox(width: 4),
                          Text(c.label,
                              style: TextStyle(
                                  color: _canal == c.value ? Colors.white : null)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ---- Cuenta ----
            InfoLabel(
              label: 'Cuenta *',
              child: cuentasAsync.when(
                loading: () => const SizedBox(
                  height: 32,
                  child: Center(child: ProgressRing(strokeWidth: 2)),
                ),
                error: (e, _) => Text('Error: $e'),
                data: (cuentas) {
                  final filtradas =
                      cuentas.where((c) => c.tipo == _canal).toList();
                  if (filtradas.isEmpty) {
                    return Text(
                      'No hay cuentas de ${_canal == 'whatsapp' ? 'WhatsApp' : 'Telegram'} configuradas.',
                      style: TextStyle(
                        color: FluentTheme.of(context).resources.systemFillColorCritical,
                      ),
                    );
                  }
                  // Auto-seleccionar si solo hay una
                  if (_cuentaId == null && filtradas.length == 1) {
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => setState(() => _cuentaId = filtradas.first.id),
                    );
                  }
                  return ComboBox<String>(
                    value: _cuentaId,
                    placeholder: const Text('Selecciona una cuenta'),
                    isExpanded: true,
                    onChanged: (v) => setState(() => _cuentaId = v),
                    items: filtradas
                        .map((c) => ComboBoxItem<String>(
                              value: c.id,
                              child: Text(c.nombre),
                            ))
                        .toList(),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),

            // ---- Contacto (opcional) ----
            InfoLabel(
              label: 'Contacto (opcional)',
              child: ContactoPicker(
                placeholder: 'Buscar en contactos...',
                onSelected: (c) => setState(() {
                  _contactoId = c['id'] as String?;
                  _nombreCtrl.text = c['razon_social'] as String? ?? '';
                }),
              ),
            ),
            const SizedBox(height: 12),

            // ---- Destinatario ----
            InfoLabel(
              label: _canal == 'whatsapp'
                  ? 'Número WhatsApp (E.164) *'
                  : 'Chat ID o @usuario *',
              child: TextBox(
                controller: _destCtrl,
                placeholder: _canal == 'whatsapp'
                    ? '+593XXXXXXXXX'
                    : '@usuario o 123456789',
              ),
            ),
            const SizedBox(height: 12),

            // ---- Nombre ----
            InfoLabel(
              label: 'Nombre del contacto',
              child: TextBox(
                controller: _nombreCtrl,
                placeholder: 'Nombre para mostrar (opcional)',
              ),
            ),
            const SizedBox(height: 12),

            // ---- Mensaje ----
            InfoLabel(
              label: 'Mensaje *',
              child: SizedBox(
                height: 88,
                child: TextBox(
                  controller: _mensajeCtrl,
                  placeholder: 'Escribe el mensaje...',
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                ),
              ),
            ),

            // ---- Aviso WhatsApp ----
            if (_canal == 'whatsapp') ...[
              const SizedBox(height: 8),
              InfoBar(
                title: const Text('WhatsApp Business'),
                content: const Text(
                  'Solo puedes iniciar conversaciones si el contacto te escribió en las últimas 24h, '
                  'o usando una plantilla aprobada por Meta.',
                ),
                severity: InfoBarSeverity.info,
                isLong: true,
              ),
            ],
          ],
        ),
      ),
      actions: [
        Button(
          onPressed: _enviando ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _enviando ? null : _enviar,
          child: _enviando
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: ProgressRing(strokeWidth: 2),
                )
              : const Text('Enviar'),
        ),
      ],
    );
  }
}
