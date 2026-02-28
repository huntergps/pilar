import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/empresa_provider.dart';
import '../../../core/providers/usuario_provider.dart';
import '../../../core/theme/pilar_breakpoints.dart';
import '../../../core/widgets/user_card.dart';
import '../providers/chat_provider.dart';

// ---------------------------------------------------------------------------
// ChatScope — controla qué secciones se muestran en el panel de canales
// ---------------------------------------------------------------------------

/// Define qué secciones del panel de canales mostrar en [ChatTab].
///
/// - [empresa]: solo canales grupales (`tipo != 'directo'`), oculta DMs.
/// - [personal]: solo mensajes directos (`tipo == 'directo'`), oculta canales.
/// - [todos]: muestra ambas secciones (comportamiento original).
enum ChatScope { empresa, personal, todos }

// ---------------------------------------------------------------------------
// ChatTab — chat interno entre usuarios ERP
// ---------------------------------------------------------------------------

class ChatTab extends ConsumerWidget {
  /// Controla qué secciones se muestran en el panel de canales.
  /// Ver [ChatScope] para los valores disponibles.
  final ChatScope scope;

  const ChatTab({super.key, this.scope = ChatScope.todos});

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
            child: _PanelCanales(scope: scope),
          ),
          const Divider(direction: Axis.vertical),
          const Expanded(child: _PanelMensajes()),
        ],
      );
    }

    // Móvil: stack
    return canalSel == null
        ? _PanelCanales(scope: scope)
        : _PanelMensajesMovil();
  }
}

// ---------------------------------------------------------------------------
// Panel Canales (izquierdo) — secciones: Canales de empresa + Mensajes directos
// ---------------------------------------------------------------------------

class _PanelCanales extends ConsumerStatefulWidget {
  final ChatScope scope;

  const _PanelCanales({this.scope = ChatScope.todos});

  @override
  ConsumerState<_PanelCanales> createState() => _PanelCanalesState();
}

class _PanelCanalesState extends ConsumerState<_PanelCanales> {
  bool _canalesExpandido = true;
  bool _directosExpandido = true;

  @override
  Widget build(BuildContext context) {
    final canalesAsync = ref.watch(chatCanalesProvider);
    final theme = FluentTheme.of(context);
    final scope = widget.scope;

    // Determinar etiqueta del header y tooltip según scope
    final headerLabel = switch (scope) {
      ChatScope.empresa => 'Canales',
      ChatScope.personal => 'Mis DMs',
      ChatScope.todos => 'Chat interno',
    };
    final tooltipLabel = switch (scope) {
      ChatScope.empresa => 'Nuevo canal',
      ChatScope.personal || ChatScope.todos => 'Nuevo mensaje directo',
    };

    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Text(headerLabel, style: theme.typography.subtitle),
              const Spacer(),
              Tooltip(
                message: tooltipLabel,
                child: IconButton(
                  icon: const Icon(FluentIcons.add, size: 16),
                  onPressed: () => _mostrarNuevoCanal(context),
                ),
              ),
            ],
          ),
        ),
        const Divider(),
        // Contenido
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
              final grupos = canales
                  .where((c) => (c['tipo'] as String? ?? 'group') != 'directo')
                  .toList();
              final directos = canales
                  .where((c) => (c['tipo'] as String? ?? 'group') == 'directo')
                  .toList();

              // Mostrar vacío según scope
              final hayContenido = switch (scope) {
                ChatScope.empresa => grupos.isNotEmpty,
                ChatScope.personal => directos.isNotEmpty,
                ChatScope.todos => canales.isNotEmpty,
              };

              if (!hayContenido) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        scope == ChatScope.personal
                            ? FluentIcons.contact
                            : FluentIcons.people,
                        size: 40,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        scope == ChatScope.personal
                            ? 'Sin mensajes directos'
                            : 'Sin canales',
                        style: theme.typography.body,
                      ),
                    ],
                  ),
                );
              }

              return ListView(
                children: [
                  // ---- Sección: Canales de empresa (ocultar en scope personal) ----
                  if (scope != ChatScope.personal) ...[
                    _SeccionHeader(
                      label: 'Canales',
                      expandido: _canalesExpandido,
                      onTap: () => setState(
                          () => _canalesExpandido = !_canalesExpandido),
                    ),
                    if (_canalesExpandido)
                      ...grupos.map((c) => _CanalTile(canal: c)),
                    const SizedBox(height: 4),
                  ],

                  // ---- Sección: Mensajes directos (ocultar en scope empresa) ----
                  if (scope != ChatScope.empresa) ...[
                    _SeccionHeader(
                      label: 'Mensajes directos',
                      expandido: _directosExpandido,
                      onTap: () => setState(
                          () => _directosExpandido = !_directosExpandido),
                    ),
                    if (_directosExpandido)
                      ...directos.map((c) => _CanalTile(canal: c)),
                    if (_directosExpandido && directos.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6),
                        child: Text(
                          'Sin mensajes directos',
                          style: theme.typography.caption?.copyWith(
                              color: theme.inactiveColor),
                        ),
                      ),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  void _mostrarNuevoCanal(BuildContext context) {
    if (widget.scope == ChatScope.empresa) {
      // Canal grupal — por implementar
      showDialog<void>(
        context: context,
        builder: (ctx) => ContentDialog(
          title: const Text('Nuevo canal'),
          content: const Text('Funcionalidad disponible en la próxima versión.'),
          actions: [
            Button(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
          ],
        ),
      );
      return;
    }
    showDialog<void>(
      context: context,
      builder: (_) => _NuevoDmDialog(parentRef: ref),
    );
  }
}

// ---------------------------------------------------------------------------
// Dialog: Nuevo mensaje directo
// ---------------------------------------------------------------------------

class _NuevoDmDialog extends ConsumerStatefulWidget {
  /// Referencia al `WidgetRef` del padre para poder leer providers de sesión.
  final WidgetRef parentRef;

  const _NuevoDmDialog({required this.parentRef});

  @override
  ConsumerState<_NuevoDmDialog> createState() => _NuevoDmDialogState();
}

class _NuevoDmDialogState extends ConsumerState<_NuevoDmDialog> {
  final _searchCtrl = TextEditingController();
  String _busqueda = '';
  bool _creando = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final miembrosAsync = ref.watch(empresaMiembrosProvider);
    final theme = FluentTheme.of(context);

    return ContentDialog(
      title: const Text('Nuevo mensaje directo'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextBox(
              controller: _searchCtrl,
              placeholder: 'Buscar usuario...',
              onChanged: (v) => setState(() => _busqueda = v.toLowerCase()),
              prefix: const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(FluentIcons.search, size: 14),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 280,
              child: miembrosAsync.when(
                loading: () => const Center(child: ProgressRing()),
                error: (e, _) => Center(
                  child: InfoBar(
                    title: const Text('Error'),
                    content: Text(e.toString()),
                    severity: InfoBarSeverity.error,
                  ),
                ),
                data: (miembros) {
                  final filtrados = _busqueda.isEmpty
                      ? miembros
                      : miembros.where((m) {
                          final nombre = (m['nombre_display'] as String? ?? '')
                              .toLowerCase();
                          final email =
                              (m['email'] as String? ?? '').toLowerCase();
                          return nombre.contains(_busqueda) ||
                              email.contains(_busqueda);
                        }).toList();

                  if (filtrados.isEmpty) {
                    return Center(
                      child: Text(
                        _busqueda.isEmpty ? 'Sin otros usuarios' : 'Sin resultados',
                        style: theme.typography.body
                            ?.copyWith(color: theme.inactiveColor),
                      ),
                    );
                  }

                  return ListView.separated(
                    itemCount: filtrados.length,
                    separatorBuilder: (_, __) => const Divider(size: 1),
                    itemBuilder: (_, i) {
                      final m = filtrados[i];
                      final nombreDisplay =
                          (m['nombre_display'] as String?)?.trim();
                      final email = m['email'] as String? ?? '';
                      final displayName =
                          nombreDisplay?.isNotEmpty == true
                              ? nombreDisplay!
                              : email;
                      final uid = m['usuario_id'] as String;
                      final avatarUrl = m['avatar_url'] as String?;

                      return UserCard(
                        nombre: displayName,
                        email: nombreDisplay?.isNotEmpty == true ? email : null,
                        avatarUrl: avatarUrl,
                        avatarRadius: 24,
                        onTap: _creando ? null : () => _abrirDm(uid),
                      );
                    },
                  );
                },
              ),
            ),
            if (_creando) ...[
              const SizedBox(height: 8),
              const Center(child: ProgressRing()),
            ],
          ],
        ),
      ),
      actions: [
        Button(
          onPressed: _creando ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }

  Future<void> _abrirDm(String otroUsuarioId) async {
    setState(() => _creando = true);
    try {
      final canalId = await _getOrCreateDm(otroUsuarioId);
      if (mounted) Navigator.pop(context);
      widget.parentRef.read(canalSeleccionadoProvider.notifier).state = canalId;
      widget.parentRef.invalidate(chatCanalesProvider);
    } catch (e) {
      if (mounted) {
        displayInfoBar(
          context,
          builder: (ctx, close) => InfoBar(
            title: const Text('Error al crear mensaje directo'),
            content: Text(e.toString()),
            severity: InfoBarSeverity.error,
            action: IconButton(
                icon: const Icon(FluentIcons.clear), onPressed: close),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _creando = false);
    }
  }

  /// Devuelve el [canal_id] del DM existente o crea uno nuevo vía RPC.
  Future<String> _getOrCreateDm(String otroId) async {
    final result = await Supabase.instance.client.rpc(
      'get_or_create_dm_canal',
      params: {'p_otro_usuario_id': otroId},
    ) as Map<String, dynamic>;
    return result['canal_id'] as String;
  }
}

// ---------------------------------------------------------------------------
// Header de sección colapsable
// ---------------------------------------------------------------------------

class _SeccionHeader extends StatelessWidget {
  final String label;
  final bool expandido;
  final VoidCallback onTap;

  const _SeccionHeader({
    required this.label,
    required this.expandido,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Icon(
              expandido
                  ? FluentIcons.chevron_down_small
                  : FluentIcons.chevron_right_small,
              size: 12,
              color: theme.inactiveColor,
            ),
            const SizedBox(width: 4),
            Text(
              label.toUpperCase(),
              style: theme.typography.caption?.copyWith(
                color: theme.inactiveColor,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tile de un canal (grupo o directo)
// ---------------------------------------------------------------------------

class _CanalTile extends ConsumerWidget {
  final Map<String, dynamic> canal;

  const _CanalTile({required this.canal});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = canal['canal_id'] as String? ?? '';
    final nombre = canal['nombre'] as String? ?? 'Canal';
    final tipo = canal['tipo'] as String? ?? 'group';
    final noLeidos = canal['no_leidos'] as int? ?? 0;
    final canalSel = ref.watch(canalSeleccionadoProvider);
    final seleccionado = canalSel == id;
    final theme = FluentTheme.of(context);

    return ListTile.selectable(
      selected: seleccionado,
      onSelectionChange: (_) async {
        ref.read(canalSeleccionadoProvider.notifier).state = id;
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
        tipo == 'directo' ? FluentIcons.contact : FluentIcons.people,
        size: 16,
      ),
      title: Text(
        tipo == 'group' ? '# $nombre' : nombre,
        overflow: TextOverflow.ellipsis,
        style: theme.typography.body,
      ),
      trailing: noLeidos > 0
          ? InfoBadge(source: Text('$noLeidos'))
          : null,
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
    final theme = FluentTheme.of(context);

    // Obtener nombre y tipo del canal desde el provider cacheado
    final canalesAsync = ref.watch(chatCanalesProvider);
    final canalInfo = canalesAsync.valueOrNull?.firstWhere(
      (c) => c['canal_id'] == canalId,
      orElse: () => const {},
    );
    final nombre = canalInfo?['nombre'] as String? ?? 'Canal';
    final tipo = canalInfo?['tipo'] as String? ?? 'group';
    final esDirecto = tipo == 'directo';

    return Column(
      children: [
        // ---- Header canal ----
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: theme.micaBackgroundColor,
          child: Row(
            children: [
              Icon(
                esDirecto ? FluentIcons.contact : FluentIcons.people,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                esDirecto ? nombre : '# $nombre',
                style: theme.typography.bodyStrong,
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
                      style: theme.typography.caption
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
