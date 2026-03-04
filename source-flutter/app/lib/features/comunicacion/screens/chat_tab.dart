import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:brick_gen/brick_gen.dart';

import '../../../core/providers/presencia_provider.dart' show EstadoPresencia;
import '../../../core/providers/usuario_provider.dart';
import '../../../core/theme/pilar_breakpoints.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/loading_spinner.dart';
import '../../../core/widgets/user_card.dart';
import '../providers/chat_provider.dart';
import '../../../core/theme/pilar_spacing.dart';

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
          padding: const EdgeInsets.symmetric(horizontal: Spacing.ms, vertical: Spacing.ms),
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
            loading: () => const PilarLoadingCenter(),
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
                      const SizedBox(height: Spacing.sm),
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
                    const SizedBox(height: Spacing.xs),
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
                            horizontal: Spacing.md, vertical: Spacing.sm),
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
      showDialog<void>(
        context: context,
        builder: (_) => _NuevoCanalGrupalDialog(parentRef: ref),
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
// Dialog: Nuevo canal grupal
// ---------------------------------------------------------------------------

class _NuevoCanalGrupalDialog extends ConsumerStatefulWidget {
  final WidgetRef parentRef;
  const _NuevoCanalGrupalDialog({required this.parentRef});

  @override
  ConsumerState<_NuevoCanalGrupalDialog> createState() =>
      _NuevoCanalGrupalDialogState();
}

class _NuevoCanalGrupalDialogState
    extends ConsumerState<_NuevoCanalGrupalDialog> {
  final _nombreCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  String _busqueda = '';
  final Set<String> _seleccionados = {};
  bool _creando = false;
  String? _errorNombre;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _crear() async {
    final nombre = _nombreCtrl.text.trim();
    if (nombre.isEmpty) {
      setState(() => _errorNombre = 'El nombre es requerido');
      return;
    }
    setState(() {
      _creando = true;
      _errorNombre = null;
    });
    try {
      final canalId = await ref.read(chatActionsProvider.notifier).crearCanalGrupo(
        nombre: nombre,
        miembroIds: _seleccionados.toList(),
      );
      widget.parentRef.read(canalSeleccionadoProvider.notifier).state = canalId;
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        displayInfoBar(
          context,
          builder: (ctx, close) => InfoBar(
            title: const Text('Error al crear canal'),
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

  @override
  Widget build(BuildContext context) {
    final miembrosAsync = ref.watch(empresaMiembrosProvider);
    final theme = FluentTheme.of(context);

    return ContentDialog(
      title: const Text('Nuevo canal'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InfoLabel(
              label: 'Nombre del canal *',
              child: TextBox(
                controller: _nombreCtrl,
                placeholder: 'ej: ventas, proyectos, general',
                enabled: !_creando,
                onChanged: (_) => setState(() => _errorNombre = null),
                prefix: const Padding(
                  padding: EdgeInsets.only(left: Spacing.sm),
                  child: Text('#', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ),
            if (_errorNombre != null)
              Padding(
                padding: const EdgeInsets.only(top: Spacing.xs),
                child: Text(
                  _errorNombre!,
                  style: TextStyle(
                      color: Colors.red, fontSize: 12),
                ),
              ),
            const SizedBox(height: Spacing.ms),
            Text('Agregar miembros',
                style: theme.typography.bodyStrong),
            const SizedBox(height: Spacing.sm),
            TextBox(
              controller: _searchCtrl,
              placeholder: 'Buscar usuario...',
              enabled: !_creando,
              onChanged: (v) => setState(() => _busqueda = v.toLowerCase()),
              prefix: const Padding(
                padding: EdgeInsets.only(left: Spacing.sm),
                child: Icon(FluentIcons.search, size: 14),
              ),
            ),
            const SizedBox(height: Spacing.sm),
            SizedBox(
              height: 220,
              child: miembrosAsync.when(
                loading: () => const PilarLoadingCenter(),
                error: (e, _) => PilarErrorState(error: e),
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
                        _busqueda.isEmpty
                            ? 'Sin otros usuarios'
                            : 'Sin resultados',
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
                      final uid = m['usuario_id'] as String;
                      final nombreDisplay =
                          (m['nombre_display'] as String?)?.trim();
                      final email = m['email'] as String? ?? '';
                      final displayName =
                          nombreDisplay?.isNotEmpty == true
                              ? nombreDisplay!
                              : email;
                      final seleccionado = _seleccionados.contains(uid);

                      return ListTile.selectable(
                        selected: seleccionado,
                        onSelectionChange: (_) => setState(() {
                          if (seleccionado) {
                            _seleccionados.remove(uid);
                          } else {
                            _seleccionados.add(uid);
                          }
                        }),
                        leading: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            CircleAvatar(
                              radius: 14,
                              child: Text(
                                displayName.isNotEmpty
                                    ? displayName[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            if (seleccionado)
                              Positioned(
                                right: -2,
                                bottom: -2,
                                child: Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: theme.accentColor,
                                  ),
                                  child: const Icon(FluentIcons.check_mark,
                                      size: 10, color: Colors.white),
                                ),
                              ),
                          ],
                        ),
                        title: Text(displayName,
                            overflow: TextOverflow.ellipsis),
                        subtitle: nombreDisplay?.isNotEmpty == true
                            ? Text(email,
                                overflow: TextOverflow.ellipsis,
                                style: theme.typography.caption?.copyWith(
                                    color: theme.inactiveColor))
                            : null,
                      );
                    },
                  );
                },
              ),
            ),
            if (_seleccionados.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: Spacing.sm),
                child: Text(
                  '${_seleccionados.length} miembro${_seleccionados.length == 1 ? '' : 's'} seleccionado${_seleccionados.length == 1 ? '' : 's'}',
                  style: theme.typography.caption?.copyWith(
                    color: theme.accentColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        Button(
          onPressed: _creando ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _creando ? null : _crear,
          child: _creando
              ? const PilarProgressRing.small()
              : const Text('Crear canal'),
        ),
      ],
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
                padding: EdgeInsets.only(left: Spacing.sm),
                child: Icon(FluentIcons.search, size: 14),
              ),
            ),
            const SizedBox(height: Spacing.sm),
            SizedBox(
              height: 280,
              child: miembrosAsync.when(
                loading: () => const PilarLoadingCenter(),
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
              const SizedBox(height: Spacing.sm),
              const PilarLoadingCenter(),
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
      final canalId = await ref.read(chatActionsProvider.notifier).getOrCreateDm(otroUsuarioId);
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
        padding: const EdgeInsets.symmetric(horizontal: Spacing.ms, vertical: Spacing.sm),
        child: Row(
          children: [
            Icon(
              expandido
                  ? FluentIcons.chevron_down_small
                  : FluentIcons.chevron_right_small,
              size: 12,
              color: theme.inactiveColor,
            ),
            const SizedBox(width: Spacing.xs),
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
    final tipo = canal['tipo'] as String? ?? 'group';
    final noLeidos = canal['no_leidos'] as int? ?? 0;
    final esDirecto = tipo == 'directo';
    final canalSel = ref.watch(canalSeleccionadoProvider);
    final seleccionado = canalSel == id;
    final theme = FluentTheme.of(context);

    // Para DM: usar datos del otro usuario; para grupos: nombre del canal
    final otroNombre = canal['otro_usuario_nombre'] as String?;
    final otroAvatar = canal['otro_usuario_avatar'] as String?;
    final nombreGrupo = canal['nombre'] as String? ?? '';
    final displayName = esDirecto
        ? (otroNombre ?? 'Directo')
        : (nombreGrupo.isEmpty ? 'Canal' : nombreGrupo);

    return ListTile.selectable(
      selected: seleccionado,
      onSelectionChange: (_) async {
        ref.read(canalSeleccionadoProvider.notifier).state = id;
        await ref.read(chatActionsProvider.notifier).marcarLeido(id);
      },
      leading: esDirecto
          ? _AvatarMini(nombre: displayName, avatarUrl: otroAvatar)
          : const Icon(FluentIcons.people, size: 16),
      title: Text(
        esDirecto ? displayName : '# $displayName',
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
// Avatar pequeño para tiles y headers de DM
// ---------------------------------------------------------------------------

class _AvatarMini extends StatelessWidget {
  final String nombre;
  final String? avatarUrl;
  final double radius;

  const _AvatarMini({required this.nombre, this.avatarUrl, this.radius = 12});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage(avatarUrl!),
        backgroundColor: theme.accentColor.withValues(alpha: 0.2),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: theme.accentColor.withValues(alpha: 0.2),
      child: Text(
        nombre.isNotEmpty ? nombre[0].toUpperCase() : '?',
        style: TextStyle(fontSize: radius * 0.8, fontWeight: FontWeight.w600),
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
            const SizedBox(height: Spacing.md),
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
          padding: const EdgeInsets.only(left: Spacing.sm, top: Spacing.sm),
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
    final tipo = canalInfo?['tipo'] as String? ?? 'group';
    final esDirecto = tipo == 'directo';
    final otroNombre = canalInfo?['otro_usuario_nombre'] as String?;
    final otroAvatar = canalInfo?['otro_usuario_avatar'] as String?;
    final nombreGrupo = canalInfo?['nombre'] as String? ?? '';
    final nombre = esDirecto
        ? (otroNombre ?? 'Directo')
        : (nombreGrupo.isEmpty ? 'Canal' : nombreGrupo);

    return Column(
      children: [
        // ---- Header canal ----
        Container(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.ms),
          color: theme.micaBackgroundColor,
          child: Row(
            children: [
              if (esDirecto)
                _AvatarMini(nombre: nombre, avatarUrl: otroAvatar, radius: 14)
              else
                const Icon(FluentIcons.people, size: 18),
              const SizedBox(width: Spacing.sm),
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
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: EstadoPresencia.online.color,
                      ),
                    ),
                    const SizedBox(width: Spacing.xs),
                    Text(
                      '${presencia.length} online',
                      style: theme.typography.caption
                          ?.copyWith(color: EstadoPresencia.online.color),
                    ),
                  ],
                ),
            ],
          ),
        ),

        // ---- Mensajes ----
        Expanded(
          child: mensajesAsync.when(
            loading: () => const PilarLoadingCenter(),
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
                padding: const EdgeInsets.all(Spacing.ms),
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
  final ChatMensaje msg;
  final Map<String, EstadoPresencia> presencia;

  const _ChatMensajeTile({required this.msg, required this.presencia});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usuarioId = ref.read(usuarioActualProvider)?.id ?? '';
    final autorId = msg.usuarioId;
    final esPropio = autorId == usuarioId;
    const tipo = 'texto';
    final cuerpo = msg.cuerpo ?? '';
    final nombreAutor = msg.usuarioId.length > 6
        ? msg.usuarioId.substring(0, 6)
        : msg.usuarioId;
    final estadoAutor = presencia[autorId];
    final estaOnline = estadoAutor != null;
    final colorEstado = estadoAutor?.color ?? EstadoPresencia.online.color;
    final theme = FluentTheme.of(context);

    // Mensajes de sistema — centrados, itálica
    if (tipo == 'sistema') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
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
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
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
                    right: Spacing.none,
                    bottom: Spacing.none,
                    child: Tooltip(
                      message: estadoAutor.label,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colorEstado,
                          border: Border.all(color: theme.cardColor, width: 1.5),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: Spacing.sm),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  esPropio ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!esPropio)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Spacing.xxs),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          nombreAutor,
                          style: theme.typography.caption
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        if (estaOnline) ...[
                          const SizedBox(width: Spacing.xs),
                          Tooltip(
                            message: estadoAutor.label,
                            child: Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: colorEstado,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.ms, vertical: Spacing.sm),
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
                            const SizedBox(width: Spacing.xs),
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

    setState(() => _enviando = true);
    try {
      await ref.read(chatActionsProvider.notifier).enviarMensaje(
        canalId: widget.canalId,
        cuerpo: texto,
      );
      _ctrl.clear();
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
      padding: const EdgeInsets.all(Spacing.sm),
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
          const SizedBox(width: Spacing.sm),
          if (_enviando)
            const PilarProgressRing(size: Spacing.xl)
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
