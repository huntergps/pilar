import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/empresa_provider.dart';
import '../../../core/providers/usuario_provider.dart';
import '../../../core/theme/pilar_breakpoints.dart';
import '../providers/chat_provider.dart';

// ---------------------------------------------------------------------------
// ChatTab — chat interno entre usuarios ERP
// ---------------------------------------------------------------------------

class ChatTab extends ConsumerWidget {
  const ChatTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Activar notifier de presencia cuando este tab está activo
    ref.watch(presenceNotifierProvider);

    final canalSel = ref.watch(canalSeleccionadoProvider);
    final isDesktop = context.isDesktop; // ≥ 900px

    if (isDesktop) {
      return Row(
        children: [
          SizedBox(
            width: 240,
            child: _PanelCanales(),
          ),
          const Divider(direction: Axis.vertical),
          const Expanded(child: _PanelMensajes()),
        ],
      );
    }

    // Móvil: stack
    return canalSel == null ? _PanelCanales() : _PanelMensajesMovil();
  }
}

// ---------------------------------------------------------------------------
// Panel Canales (izquierdo)
// ---------------------------------------------------------------------------

class _PanelCanales extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canalesAsync = ref.watch(chatCanalesProvider);
    final canalSel = ref.watch(canalSeleccionadoProvider);
    final theme = FluentTheme.of(context);

    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Text('Chat', style: theme.typography.subtitle),
              const Spacer(),
              IconButton(
                icon: const Icon(FluentIcons.add),
                onPressed: () => _mostrarNuevoCanal(context, ref),
              ),
            ],
          ),
        ),
        const Divider(),
        // Lista de canales
        Expanded(
          child: canalesAsync.when(
            loading: () => const Center(child: ProgressRing()),
            error: (e, _) => Center(
              child: InfoBar(
                title: const Text('Error'),
                content: Text(e.toString()),
                severity: InfoBarSeverity.error,
              ),
            ),
            data: (canales) {
              if (canales.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(FluentIcons.people, size: 40),
                      const SizedBox(height: 8),
                      Text('Sin canales', style: theme.typography.body),
                    ],
                  ),
                );
              }
              return ListView.builder(
                itemCount: canales.length,
                itemBuilder: (ctx, i) {
                  final c = canales[i];
                  final id = c['canal_id'] as String? ?? '';
                  final nombre = c['nombre'] as String? ?? 'Canal';
                  final tipo = c['tipo'] as String? ?? 'group';
                  final noLeidos = c['no_leidos'] as int? ?? 0;
                  final seleccionado = canalSel == id;

                  return ListTile.selectable(
                    selected: seleccionado,
                    onSelectionChange: (_) async {
                      ref.read(canalSeleccionadoProvider.notifier).state = id;
                      // Marcar leído
                      final usuarioId = ref.read(usuarioActualProvider)?.id;
                      if (usuarioId != null) {
                        await Supabase.instance.client.rpc(
                          'mark_messages_read',
                          params: {'canal_id': id, 'usuario_id': usuarioId},
                        );
                        ref.invalidate(chatCanalesProvider);
                      }
                    },
                    leading: Icon(
                      tipo == 'directo'
                          ? FluentIcons.contact
                          : FluentIcons.people,
                      size: 18,
                    ),
                    title: Text(
                      nombre,
                      overflow: TextOverflow.ellipsis,
                      style: theme.typography.body,
                    ),
                    trailing: noLeidos > 0
                        ? InfoBadge(
                            source: Text('$noLeidos'),
                          )
                        : null,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _mostrarNuevoCanal(BuildContext context, WidgetRef ref) {
    // Placeholder — crear nuevo canal DM/grupo (próxima iteración)
    showDialog<void>(
      context: context,
      builder: (ctx) => ContentDialog(
        title: const Text('Nuevo canal / Mensaje directo'),
        content: const Text(
          'Funcionalidad disponible en la próxima versión.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Panel Mensajes (derecho)
// ---------------------------------------------------------------------------

class _PanelMensajes extends ConsumerWidget {
  const _PanelMensajes();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canalId = ref.watch(canalSeleccionadoProvider);

    if (canalId == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(FluentIcons.people, size: 64),
            const SizedBox(height: 16),
            Text(
              'Selecciona un canal',
              style: FluentTheme.of(context).typography.subtitle,
            ),
          ],
        ),
      );
    }

    return _CanalMensajesView(canalId: canalId);
  }
}

class _PanelMensajesMovil extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canalId = ref.watch(canalSeleccionadoProvider);
    if (canalId == null) return const SizedBox.shrink();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, top: 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(FluentIcons.back),
                onPressed: () =>
                    ref.read(canalSeleccionadoProvider.notifier).state = null,
              ),
              const Expanded(child: Text('Chat')),
            ],
          ),
        ),
        Expanded(child: _CanalMensajesView(canalId: canalId)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Vista de mensajes de un canal
// ---------------------------------------------------------------------------

class _CanalMensajesView extends ConsumerWidget {
  final String canalId;

  const _CanalMensajesView({required this.canalId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mensajesAsync = ref.watch(chatMensajesProvider(canalId));
    final presencia = ref.watch(presenciaProvider);

    return Column(
      children: [
        // ---- Header canal ----
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: FluentTheme.of(context).micaBackgroundColor,
          child: Row(
            children: [
              const Icon(FluentIcons.people),
              const SizedBox(width: 8),
              Text(
                'Canal',
                style: FluentTheme.of(context).typography.bodyStrong,
              ),
              const Spacer(),
              // Indicador de presencia: "N online"
              if (presencia.isNotEmpty)
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.successPrimaryColor,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${presencia.length} online',
                      style: FluentTheme.of(context)
                          .typography
                          .caption
                          ?.copyWith(color: Colors.successPrimaryColor),
                    ),
                  ],
                ),
            ],
          ),
        ),

        // ---- Mensajes ----
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
                    style: FluentTheme.of(context)
                        .typography
                        .body
                        ?.copyWith(color: FluentTheme.of(context).inactiveColor),
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: mensajes.length,
                itemBuilder: (ctx, i) {
                  final msg = mensajes[i];
                  return _ChatMensajeTile(
                    msg: msg,
                    presencia: presencia,
                  );
                },
              );
            },
          ),
        ),

        // ---- Input ----
        _ChatInput(canalId: canalId),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tile de mensaje de chat interno
// ---------------------------------------------------------------------------

class _ChatMensajeTile extends ConsumerWidget {
  final Map<String, dynamic> msg;
  final Set<String> presencia;

  const _ChatMensajeTile({required this.msg, required this.presencia});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usuarioId = ref.read(usuarioActualProvider)?.id ?? '';
    final autorId = msg['user_id'] as String? ?? '';
    final esPropio = autorId == usuarioId;
    final tipo = msg['tipo'] as String? ?? 'texto';
    final cuerpo = msg['cuerpo'] as String? ?? '';
    final nombreAutor = msg['nombre_display'] as String? ??
        msg['autor_nombre'] as String? ??
        'Usuario';
    final estaOnline = presencia.contains(autorId);
    final theme = FluentTheme.of(context);

    // Mensajes de sistema — centrados, itálica
    if (tipo == 'sistema') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Text(
            cuerpo,
            style: theme.typography.caption?.copyWith(
              fontStyle: FontStyle.italic,
              color: theme.inactiveColor,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            esPropio ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!esPropio) ...[
            Stack(
              children: [
                CircleAvatar(
                  radius: 16,
                  child: Text(nombreAutor.isNotEmpty
                      ? nombreAutor[0].toUpperCase()
                      : '?'),
                ),
                if (estaOnline)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.successPrimaryColor,
                        border: Border.all(color: theme.cardColor, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  esPropio ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!esPropio)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          nombreAutor,
                          style: theme.typography.caption
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        if (estaOnline) ...[
                          const SizedBox(width: 4),
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.successPrimaryColor,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: esPropio
                        ? theme.accentColor.withValues(alpha: 0.15)
                        : theme.cardColor,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(12),
                      topRight: const Radius.circular(12),
                      bottomLeft: Radius.circular(esPropio ? 12 : 2),
                      bottomRight: Radius.circular(esPropio ? 2 : 12),
                    ),
                    border: Border.all(
                      color: theme.resources.controlStrokeColorDefault,
                      width: 0.5,
                    ),
                  ),
                  child: tipo == 'ia_respuesta'
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(FluentIcons.lightbulb, size: 14),
                            const SizedBox(width: 4),
                            Flexible(child: Text(cuerpo)),
                          ],
                        )
                      : Text(cuerpo),
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
// Input de chat
// ---------------------------------------------------------------------------

class _ChatInput extends ConsumerStatefulWidget {
  final String canalId;

  const _ChatInput({required this.canalId});

  @override
  ConsumerState<_ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends ConsumerState<_ChatInput> {
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

    final usuarioId = ref.read(usuarioActualProvider)?.id;
    final empresaId = ref.read(empresaActivaIdProvider);
    if (usuarioId == null || empresaId == null) return;

    setState(() => _enviando = true);
    try {
      await Supabase.instance.client.from('chat_mensajes').insert({
        'canal_id': widget.canalId,
        'user_id': usuarioId,
        'empresa_id': empresaId,
        'cuerpo': texto,
        'tipo': 'texto',
      });
      _ctrl.clear();
      ref.invalidate(chatMensajesProvider(widget.canalId));
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
            child: TextBox(
              controller: _ctrl,
              placeholder: 'Escribe un mensaje...',
              maxLines: null,
              enabled: !_enviando,
              onSubmitted: (_) => _enviar(),
              textInputAction: TextInputAction.newline,
            ),
          ),
          const SizedBox(width: 8),
          if (_enviando)
            const SizedBox(width: 36, height: 36, child: ProgressRing())
          else
            IconButton(
              icon: const Icon(FluentIcons.send),
              onPressed: _enviar,
            ),
        ],
      ),
    );
  }
}
