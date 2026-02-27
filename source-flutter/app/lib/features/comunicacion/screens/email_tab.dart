import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/empresa_provider.dart';
import '../models/com_mensaje.dart';
import '../models/email_thread.dart';
import '../providers/email_provider.dart';

// ============================================================================
// HELPERS
// ============================================================================

String _formatFecha(DateTime? dt) {
  if (dt == null) return '';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final dtDay = DateTime(dt.year, dt.month, dt.day);
  const meses = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic'
  ];
  if (dtDay == today) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  } else if (dt.year == now.year) {
    return '${dt.day} ${meses[dt.month - 1]}';
  } else {
    return '${dt.day}/${dt.month}/${dt.year.toString().substring(2)}';
  }
}

String _formatFechaLarga(DateTime dt) {
  const meses = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
    'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'
  ];
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final dtDay = DateTime(dt.year, dt.month, dt.day);
  final hora =
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  if (dtDay == today) return 'Hoy, $hora';
  final anio = dt.year != now.year ? ' de ${dt.year}' : '';
  return '${dt.day} de ${meses[dt.month - 1]}$anio, $hora';
}

String _initial(String name) =>
    name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

Widget _vertDiv(BuildContext context) => Container(
      width: 1,
      color: FluentTheme.of(context).resources.dividerStrokeColorDefault,
    );

// ============================================================================
// ROOT: EmailTab
// ============================================================================

class EmailTab extends ConsumerStatefulWidget {
  const EmailTab({super.key});

  @override
  ConsumerState<EmailTab> createState() => _EmailTabState();
}

class _EmailTabState extends ConsumerState<EmailTab> {
  void _openCompose({EmailThread? replyTo}) {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _ComposeDialog(
        replyTo: replyTo,
        onSent: () => ref.invalidate(emailThreadsProvider),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final w = constraints.maxWidth;
        if (w >= 900) {
          return _EmailDesktopLayout(
            isLarge: w >= 1200,
            onCompose: _openCompose,
          );
        }
        return _EmailMobileLayout(onCompose: _openCompose);
      },
    );
  }
}

// ============================================================================
// DESKTOP LAYOUT (≥900px)
// ============================================================================

class _EmailDesktopLayout extends ConsumerWidget {
  final bool isLarge;
  final void Function({EmailThread? replyTo}) onCompose;

  const _EmailDesktopLayout({required this.isLarge, required this.onCompose});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId = ref.watch(emailSeleccionadoProvider);
    final hasSelection = selectedId != null;

    return Row(
      children: [
        // ── Sidebar (carpetas) ──────────────────────────────────────────────
        SizedBox(
          width: 200,
          child: _EmailSidebar(onCompose: () => onCompose()),
        ),
        _vertDiv(context),

        // ── Lista de correos ─────────────────────────────────────────────────
        if (isLarge)
          SizedBox(
            width: 380,
            child: _EmailList(),
          )
        else if (!hasSelection)
          Expanded(child: _EmailList())
        else
          SizedBox(
            width: 320,
            child: _EmailList(),
          ),

        // ── Lector (solo si hay selección, siempre en large) ─────────────────
        if (isLarge || hasSelection) ...[
          _vertDiv(context),
          Expanded(
            child: _EmailReader(
              onReply: (t) => onCompose(replyTo: t),
            ),
          ),
        ],
      ],
    );
  }
}

// ============================================================================
// MOBILE LAYOUT (<900px)
// ============================================================================

enum _EmailView { lista, lector }

class _EmailMobileLayout extends ConsumerStatefulWidget {
  final void Function({EmailThread? replyTo}) onCompose;

  const _EmailMobileLayout({required this.onCompose});

  @override
  ConsumerState<_EmailMobileLayout> createState() => _EmailMobileLayoutState();
}

class _EmailMobileLayoutState extends ConsumerState<_EmailMobileLayout> {
  _EmailView _view = _EmailView.lista;

  @override
  Widget build(BuildContext context) {
    final selectedId = ref.watch(emailSeleccionadoProvider);
    final theme = FluentTheme.of(context);

    // Navega automáticamente al lector cuando se selecciona un correo
    if (selectedId != null && _view == _EmailView.lista) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => setState(() => _view = _EmailView.lector),
      );
    }

    return Column(
      children: [
        // Barra de carpetas + botón redactar
        Container(
          color: theme.resources.layerFillColorDefault,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: _CarpetaComboBox(),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(FluentIcons.new_mail),
                onPressed: () => widget.onCompose(),
              ),
            ],
          ),
        ),

        Expanded(
          child: _view == _EmailView.lista
              ? _EmailList()
              : Column(
                  children: [
                    // Botón volver
                    GestureDetector(
                      onTap: () {
                        ref.read(emailSeleccionadoProvider.notifier).state =
                            null;
                        setState(() => _view = _EmailView.lista);
                      },
                      child: Container(
                        color: theme.resources.layerFillColorDefault,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              FluentIcons.back,
                              size: 14,
                              color: theme.accentColor,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Volver a la lista',
                              style: theme.typography.body
                                  ?.copyWith(color: theme.accentColor),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: _EmailReader(
                        onReply: (t) => widget.onCompose(replyTo: t),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

// ============================================================================
// SIDEBAR (escritorio)
// ============================================================================

class _EmailSidebar extends ConsumerWidget {
  final VoidCallback onCompose;

  const _EmailSidebar({required this.onCompose});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = FluentTheme.of(context);
    final carpeta = ref.watch(emailCarpetaProvider);

    return Container(
      color: theme.resources.layerFillColorDefault,
      child: Column(
        children: [
          // Botón Redactar
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onCompose,
                style: ButtonStyle(
                  padding: WidgetStateProperty.all(
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(FluentIcons.new_mail, size: 15),
                    SizedBox(width: 8),
                    Text('Redactar'),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Carpetas
          for (final c in EmailCarpeta.values)
            _FolderTile(
              carpeta: c,
              isSelected: carpeta == c,
              onTap: () {
                ref.read(emailCarpetaProvider.notifier).state = c;
                ref.read(emailSeleccionadoProvider.notifier).state = null;
              },
            ),
        ],
      ),
    );
  }
}

// ── Tile de carpeta ──────────────────────────────────────────────────────────

class _FolderTile extends ConsumerWidget {
  final EmailCarpeta carpeta;
  final bool isSelected;
  final VoidCallback onTap;

  const _FolderTile({
    required this.carpeta,
    required this.isSelected,
    required this.onTap,
  });

  IconData get _icon => switch (carpeta) {
        EmailCarpeta.recibidos => FluentIcons.inbox,
        EmailCarpeta.enviados => FluentIcons.send,
        EmailCarpeta.borradores => FluentIcons.edit,
        EmailCarpeta.fallidos => FluentIcons.error_badge,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = FluentTheme.of(context);
    final count =
        ref.watch(emailThreadsProvider(carpeta)).valueOrNull?.length ?? 0;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.accentColor.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            Icon(
              _icon,
              size: 16,
              color: isSelected
                  ? theme.accentColor
                  : theme.resources.textFillColorPrimary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                carpeta.label,
                style: theme.typography.body?.copyWith(
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? theme.accentColor : null,
                ),
              ),
            ),
            if (count > 0)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected
                      ? theme.accentColor.withValues(alpha: 0.20)
                      : theme.resources.subtleFillColorSecondary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: theme.typography.caption?.copyWith(
                    color: isSelected
                        ? theme.accentColor
                        : theme.resources.textFillColorSecondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── ComboBox de carpetas (móvil) ─────────────────────────────────────────────

class _CarpetaComboBox extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final carpeta = ref.watch(emailCarpetaProvider);
    return ComboBox<EmailCarpeta>(
      value: carpeta,
      isExpanded: true,
      items: EmailCarpeta.values
          .map(
            (c) => ComboBoxItem(value: c, child: Text(c.label)),
          )
          .toList(),
      onChanged: (v) {
        if (v == null) return;
        ref.read(emailCarpetaProvider.notifier).state = v;
        ref.read(emailSeleccionadoProvider.notifier).state = null;
      },
    );
  }
}

// ============================================================================
// EMAIL LIST (lista de hilos)
// ============================================================================

class _EmailList extends ConsumerStatefulWidget {
  @override
  ConsumerState<_EmailList> createState() => _EmailListState();
}

class _EmailListState extends ConsumerState<_EmailList> {
  final _ctrl = TextEditingController();
  Timer? _debounce;

  void _onCtrlChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onCtrlChanged);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onCtrlChanged);
    _ctrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      ref.read(emailBusquedaProvider.notifier).state =
          v.trim().isEmpty ? null : v.trim();
    });
  }

  @override
  Widget build(BuildContext context) {
    final carpeta = ref.watch(emailCarpetaProvider);
    final threadsAsync = ref.watch(emailThreadsProvider(carpeta));
    final selectedId = ref.watch(emailSeleccionadoProvider);
    final theme = FluentTheme.of(context);

    return Column(
      children: [
        // Barra de búsqueda
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextBox(
            controller: _ctrl,
            placeholder: 'Buscar en ${carpeta.label.toLowerCase()}...',
            prefix: const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(FluentIcons.search, size: 14),
            ),
            onChanged: _onSearch,
            suffix: _ctrl.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(FluentIcons.clear, size: 12),
                    onPressed: () {
                      _ctrl.clear();
                      ref.read(emailBusquedaProvider.notifier).state = null;
                    },
                  )
                : null,
          ),
        ),

        Expanded(
          child: threadsAsync.when(
            loading: () => const Center(child: ProgressRing()),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: InfoBar(
                title: const Text('Error al cargar correos'),
                content: Text('$e'),
                severity: InfoBarSeverity.error,
              ),
            ),
            data: (threads) {
              if (threads.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        FluentIcons.inbox,
                        size: 48,
                        color: theme.resources.textFillColorTertiary,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Sin correos en ${carpeta.label.toLowerCase()}',
                        style: theme.typography.body?.copyWith(
                          color: theme.resources.textFillColorTertiary,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                itemCount: threads.length,
                itemBuilder: (ctx, i) {
                  final t = threads[i];
                  return _EmailListItem(
                    thread: t,
                    isSelected: selectedId == t.conversacionId,
                    onTap: () {
                      ref.read(emailSeleccionadoProvider.notifier).state =
                          t.conversacionId;
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Ítem de email en la lista ────────────────────────────────────────────────

class _EmailListItem extends StatefulWidget {
  final EmailThread thread;
  final bool isSelected;
  final VoidCallback onTap;

  const _EmailListItem({
    required this.thread,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_EmailListItem> createState() => _EmailListItemState();
}

class _EmailListItemState extends State<_EmailListItem> {
  bool _starred = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final t = widget.thread;
    final isUnread = !t.esLeido;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? theme.accentColor.withValues(alpha: 0.10)
                : _hovered
                    ? theme.resources.subtleFillColorSecondary
                    : isUnread
                        ? theme.resources.layerFillColorDefault
                        : Colors.transparent,
            border: Border(
              bottom: BorderSide(
                color: theme.resources.dividerStrokeColorDefault,
                width: 0.5,
              ),
              left: widget.isSelected
                  ? BorderSide(color: theme.accentColor, width: 3)
                  : BorderSide.none,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(
              children: [
                // Estrella (local, sin persistir)
                GestureDetector(
                  onTap: () => setState(() => _starred = !_starred),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      _starred
                          ? FluentIcons.favorite_star_fill
                          : FluentIcons.favorite_star,
                      size: 14,
                      color: _starred
                          ? const Color(0xFFF6BF26)
                          : theme.resources.textFillColorTertiary,
                    ),
                  ),
                ),

                const SizedBox(width: 2),

                // Nombre del remitente
                SizedBox(
                  width: 140,
                  child: Text(
                    t.deNombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.typography.body?.copyWith(
                      fontWeight:
                          isUnread ? FontWeight.w700 : FontWeight.normal,
                    ),
                  ),
                ),

                const SizedBox(width: 8),

                // Asunto + preview (flex)
                Expanded(
                  child: RichText(
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: t.asunto,
                          style: theme.typography.body?.copyWith(
                            fontWeight: isUnread
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                        if (t.preview.isNotEmpty)
                          TextSpan(
                            text: '  ·  ${t.preview}',
                            style: theme.typography.body?.copyWith(
                              color:
                                  theme.resources.textFillColorSecondary,
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(width: 8),

                // Indicador de adjuntos
                if (t.tieneAdjuntos)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      FluentIcons.attach,
                      size: 12,
                      color: theme.resources.textFillColorTertiary,
                    ),
                  ),

                // Fecha
                Text(
                  _formatFecha(t.fecha),
                  style: theme.typography.caption?.copyWith(
                    fontWeight:
                        isUnread ? FontWeight.w600 : FontWeight.normal,
                    color: isUnread
                        ? null
                        : theme.resources.textFillColorSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// EMAIL READER (panel derecho / lector completo)
// ============================================================================

class _EmailReader extends ConsumerWidget {
  final void Function(EmailThread thread) onReply;

  const _EmailReader({required this.onReply});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId = ref.watch(emailSeleccionadoProvider);
    final theme = FluentTheme.of(context);

    if (selectedId == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FluentIcons.mail,
              size: 56,
              color: theme.resources.textFillColorTertiary,
            ),
            const SizedBox(height: 16),
            Text(
              'Selecciona un correo para leerlo',
              style: theme.typography.body?.copyWith(
                color: theme.resources.textFillColorTertiary,
              ),
            ),
          ],
        ),
      );
    }

    // Busca el hilo en la carpeta activa
    final carpeta = ref.watch(emailCarpetaProvider);
    final allThreads =
        ref.watch(emailThreadsProvider(carpeta)).valueOrNull ?? [];
    final thread = allThreads.isNotEmpty
        ? allThreads.where((t) => t.conversacionId == selectedId).fold<EmailThread?>(
            null,
            (prev, e) => prev ?? e,
          )
        : null;

    final mensajesAsync = ref.watch(emailMensajesProvider(selectedId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Barra de acciones ────────────────────────────────────────────────
        Container(
          color: theme.resources.layerFillColorDefault,
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              if (thread != null) ...[
                Button(
                  onPressed: () => onReply(thread),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(FluentIcons.reply, size: 13),
                      SizedBox(width: 6),
                      Text('Responder'),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Button(
                  onPressed: () => onReply(thread),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(FluentIcons.forward, size: 13),
                      SizedBox(width: 6),
                      Text('Reenviar'),
                    ],
                  ),
                ),
              ],
              const Spacer(),
              Tooltip(
                message: 'Cerrar',
                child: IconButton(
                  icon: const Icon(FluentIcons.chrome_close, size: 13),
                  onPressed: () {
                    ref.read(emailSeleccionadoProvider.notifier).state =
                        null;
                  },
                ),
              ),
            ],
          ),
        ),

        Container(
          height: 1,
          color: theme.resources.dividerStrokeColorDefault,
        ),

        // ── Contenido del hilo ───────────────────────────────────────────────
        Expanded(
          child: mensajesAsync.when(
            loading: () => const Center(child: ProgressRing()),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: InfoBar(
                title: const Text('Error al cargar mensajes'),
                content: Text('$e'),
                severity: InfoBarSeverity.error,
              ),
            ),
            data: (mensajes) {
              if (mensajes.isEmpty) {
                return Center(
                  child: Text(
                    'Sin mensajes en este hilo',
                    style: theme.typography.body?.copyWith(
                      color: theme.resources.textFillColorTertiary,
                    ),
                  ),
                );
              }

              final asunto = thread?.asunto ??
                  mensajes.first.asunto ??
                  '(Sin asunto)';

              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // Asunto del hilo
                  Text(
                    asunto,
                    style: theme.typography.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${mensajes.length} ${mensajes.length == 1 ? 'mensaje' : 'mensajes'}',
                    style: theme.typography.caption?.copyWith(
                      color: theme.resources.textFillColorSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Mensajes del hilo
                  for (int i = 0; i < mensajes.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _EmailMessageCard(
                        mensaje: mensajes[i],
                        isLast: i == mensajes.length - 1,
                      ),
                    ),

                  const SizedBox(height: 24),

                  // Botones de acción al pie del hilo
                  if (thread != null)
                    Row(
                      children: [
                        Button(
                          onPressed: () => onReply(thread),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(FluentIcons.reply, size: 13),
                              SizedBox(width: 6),
                              Text('Responder'),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Button(
                          onPressed: () => onReply(thread),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(FluentIcons.forward, size: 13),
                              SizedBox(width: 6),
                              Text('Reenviar'),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Tarjeta de mensaje en el hilo ────────────────────────────────────────────

class _EmailMessageCard extends StatefulWidget {
  final ComMensaje mensaje;
  final bool isLast;

  const _EmailMessageCard({required this.mensaje, required this.isLast});

  @override
  State<_EmailMessageCard> createState() => _EmailMessageCardState();
}

class _EmailMessageCardState extends State<_EmailMessageCard> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.isLast; // El último mensaje se expande automáticamente
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final m = widget.mensaje;
    final isOutbound = m.esOutbound;
    final displayName = isOutbound ? 'Yo' : m.destinatarioRef;

    return Card(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Cabecera ─────────────────────────────────────────────────────
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: _expanded
                    ? Colors.transparent
                    : theme.resources.subtleFillColorSecondary,
                borderRadius: _expanded
                    ? const BorderRadius.vertical(top: Radius.circular(4))
                    : BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  // Avatar inicial
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: isOutbound
                          ? theme.accentColor.withValues(alpha: 0.15)
                          : theme.resources.subtleFillColorTertiary,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _initial(displayName),
                      style: theme.typography.bodyStrong?.copyWith(
                        color: isOutbound ? theme.accentColor : null,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                displayName,
                                style: theme.typography.bodyStrong,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _formatFechaLarga(m.creadoEn),
                              style: theme.typography.caption?.copyWith(
                                color:
                                    theme.resources.textFillColorSecondary,
                              ),
                            ),
                          ],
                        ),
                        if (!_expanded && m.cuerpo != null)
                          Text(
                            m.cuerpo!.length > 80
                                ? '${m.cuerpo!.substring(0, 80)}...'
                                : m.cuerpo!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.typography.caption?.copyWith(
                              color:
                                  theme.resources.textFillColorTertiary,
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 8),
                  Icon(
                    _expanded
                        ? FluentIcons.chevron_up_small
                        : FluentIcons.chevron_down_small,
                    size: 12,
                    color: theme.resources.textFillColorTertiary,
                  ),
                ],
              ),
            ),
          ),

          // ── Cuerpo expandido ─────────────────────────────────────────────
          if (_expanded) ...[
            Container(
              height: 1,
              color: theme.resources.dividerStrokeColorDefault,
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                m.cuerpo ?? '(Sin contenido)',
                style: theme.typography.body,
              ),
            ),

            // Estado del mensaje
            if (m.estado != 'recibido')
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  children: [
                    _EstadoBadge(estado: m.estado),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ── Badge de estado ──────────────────────────────────────────────────────────

class _EstadoBadge extends StatelessWidget {
  final String estado;

  const _EstadoBadge({required this.estado});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    final (color, label) = switch (estado) {
      'enviado' => (Colors.green, 'Enviado'),
      'entregado' => (Colors.green, 'Entregado'),
      'leido' => (Colors.green, 'Leído'),
      'fallido' => (Colors.red, 'Fallido'),
      'rebotado' => (Colors.red, 'Rebotado'),
      'pendiente' => (Colors.orange, 'Borrador'),
      'encolado' => (Colors.orange, 'En cola'),
      'cancelado' => (
          theme.resources.textFillColorTertiary,
          'Cancelado'
        ),
      _ => (theme.resources.textFillColorSecondary, estado),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Text(
        label,
        style: theme.typography.caption?.copyWith(color: color),
      ),
    );
  }
}

// ============================================================================
// DIALOG DE REDACTAR
// ============================================================================

class _ComposeDialog extends ConsumerStatefulWidget {
  final EmailThread? replyTo;
  final VoidCallback onSent;

  const _ComposeDialog({this.replyTo, required this.onSent});

  @override
  ConsumerState<_ComposeDialog> createState() => _ComposeDialogState();
}

class _ComposeDialogState extends ConsumerState<_ComposeDialog> {
  final _toCtrl = TextEditingController();
  final _subjectCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  String? _cuentaId;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final r = widget.replyTo;
    if (r != null) {
      _toCtrl.text = r.deRef;
      _subjectCtrl.text = 'Re: ${r.asunto}';
      _cuentaId = r.cuentaId;
    }
  }

  @override
  void dispose() {
    _toCtrl.dispose();
    _subjectCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final to = _toCtrl.text.trim();
    final subject = _subjectCtrl.text.trim();
    final body = _bodyCtrl.text.trim();

    if (to.isEmpty) {
      setState(() => _error = 'Ingresa un destinatario');
      return;
    }
    if (subject.isEmpty) {
      setState(() => _error = 'Ingresa un asunto');
      return;
    }
    if (_cuentaId == null) {
      setState(() => _error = 'Selecciona una cuenta de email');
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      final empresaId = ref.read(empresaActivaIdProvider);

      await Supabase.instance.client.from('com_mensajes').insert({
        'empresa_id': empresaId,
        'cuenta_id': _cuentaId,
        'canal': 'email_api',
        'tipo': 'outbound',
        'destinatario_ref': to,
        'asunto': subject,
        'cuerpo': body,
        if (widget.replyTo != null)
          'conversacion_id': widget.replyTo!.conversacionId,
      });

      widget.onSent();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _sending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final cuentasAsync = ref.watch(emailCuentasProvider);
    final title =
        widget.replyTo != null ? 'Responder correo' : 'Nuevo correo';

    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 560),
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Cuenta de envío ─────────────────────────────────────────────
            cuentasAsync.when(
              loading: () =>
                  const Center(child: ProgressRing()),
              error: (e, _) => InfoBar(
                title: const Text('Error al cargar cuentas'),
                content: Text('$e'),
                severity: InfoBarSeverity.error,
              ),
              data: (cuentas) {
                if (cuentas.isEmpty) {
                  return const InfoBar(
                    title: Text('Sin cuentas de email configuradas'),
                    content: Text(
                      'Configura una cuenta en Administración → Comunicación',
                    ),
                    severity: InfoBarSeverity.warning,
                  );
                }
                _cuentaId ??= cuentas.first['id'] as String;
                return ComboBox<String>(
                  isExpanded: true,
                  value: _cuentaId,
                  placeholder: const Text('Desde (cuenta de envío)...'),
                  items: cuentas
                      .map(
                        (c) => ComboBoxItem(
                          value: c['id'] as String,
                          child: Text(c['nombre'] as String),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _cuentaId = v),
                );
              },
            ),

            const Divider(),

            // ── Para ────────────────────────────────────────────────────────
            InfoLabel(
              label: 'Para',
              child: TextBox(
                controller: _toCtrl,
                placeholder: 'correo@ejemplo.com',
                keyboardType: TextInputType.emailAddress,
              ),
            ),
            const SizedBox(height: 10),

            // ── Asunto ──────────────────────────────────────────────────────
            InfoLabel(
              label: 'Asunto',
              child: TextBox(
                controller: _subjectCtrl,
                placeholder: 'Asunto del correo',
              ),
            ),
            const SizedBox(height: 10),

            // ── Cuerpo ──────────────────────────────────────────────────────
            InfoLabel(
              label: 'Mensaje',
              child: TextBox(
                controller: _bodyCtrl,
                placeholder: 'Escribe tu mensaje aquí...',
                maxLines: 10,
                minLines: 7,
              ),
            ),

            // ── Texto de respuesta (cita) ────────────────────────────────
            if (widget.replyTo != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.resources.subtleFillColorSecondary,
                  border: Border(
                    left: BorderSide(
                      color: theme.resources.dividerStrokeColorDefault,
                      width: 3,
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'En respuesta a: ${widget.replyTo!.asunto}',
                      style: theme.typography.caption?.copyWith(
                        color: theme.resources.textFillColorSecondary,
                      ),
                    ),
                    Text(
                      'De: ${widget.replyTo!.deNombre} <${widget.replyTo!.deRef}>',
                      style: theme.typography.caption?.copyWith(
                        color: theme.resources.textFillColorTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ── Error ────────────────────────────────────────────────────────
            if (_error != null) ...[
              const SizedBox(height: 8),
              InfoBar(
                title: Text(_error!),
                severity: InfoBarSeverity.error,
              ),
            ],
          ],
        ),
      ),
      actions: [
        Button(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _sending ? null : _send,
          child: _sending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: ProgressRing(strokeWidth: 2),
                )
              : const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(FluentIcons.send, size: 13),
                    SizedBox(width: 6),
                    Text('Enviar'),
                  ],
                ),
        ),
      ],
    );
  }
}
