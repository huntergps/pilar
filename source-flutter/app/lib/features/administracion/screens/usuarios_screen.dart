import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluent_ui_reactive/fluent_ui_reactive.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:syncfusion_flutter_core/theme.dart';

import '../../../core/offline/connectivity_service.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/perfil_provider.dart';
import '../../../core/utils/timezones.dart';
import '../../../core/widgets/user_card.dart';
import '../../../core/widgets/loading_spinner.dart';
import '../../../core/theme/pilar_breakpoints.dart';
import '../providers/admin_providers.dart';
import '../providers/usuarios_admin_provider.dart';
import '../../../core/theme/pilar_spacing.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

List<Map<String, dynamic>> _parseRoles(dynamic raw) {
  if (raw is List) return raw.map((r) => Map<String, dynamic>.from(r as Map)).toList();
  return [];
}

String _formatAcceso(String? iso) {
  if (iso == null) return 'Nunca';
  try {
    return DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(iso).toLocal());
  } catch (_) {
    return iso;
  }
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class UsuariosScreen extends ConsumerStatefulWidget {
  const UsuariosScreen({super.key});

  @override
  ConsumerState<UsuariosScreen> createState() => _UsuariosScreenState();
}

class _UsuariosScreenState extends ConsumerState<UsuariosScreen> {
  String get _currentUserId => ref.read(sessionProvider)?.user.id ?? '';

  void _showInviteDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => _InviteDialog(
        onInvited: () => ref.invalidate(adminUsuariosProvider),
      ),
    );
  }

  // Abre el panel en modo diálogo — el panel mismo construye el ContentDialog
  void _showEditDialog(BuildContext context, Map<String, dynamic> u) {
    final id = u['usuario_id'] as String?;
    if (id == null) return;
    final esYo = id == _currentUserId;
    showDialog<void>(
      context: context,
      builder: (_) => _EditarUsuarioPanel(
        key: ValueKey(id),
        usuarioId: id,
        usuarioData: u,
        esYo: esYo,
        inDialog: true,
        onRefresh: () {
          ref.invalidate(adminUsuariosProvider);
          if (esYo) ref.invalidate(perfilUsuarioProvider);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Auto-refresh por Realtime
    ref.listen<AsyncValue<int>>(adminUsuariosRealtimeProvider, (_, next) {
      next.whenData((_) => ref.invalidate(adminUsuariosProvider));
    });

    final usuariosAsync = ref.watch(adminUsuariosProvider);

    return ScaffoldPage(
      header: PageHeader(
        title: const Text('Usuarios'),
        commandBar: CommandBar(
          mainAxisAlignment: MainAxisAlignment.end,
          primaryItems: [
            CommandBarButton(
              icon: const Icon(FluentIcons.add_friend),
              label: const Text('Invitar usuario'),
              onPressed: () => _showInviteDialog(context),
            ),
          ],
        ),
      ),
      content: PilarAsyncBuilder<List<Map<String, dynamic>>>(
        value: usuariosAsync,
        isEmpty: (list) => list.isEmpty,
        emptyWidget: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(FluentIcons.people,
                  size: 48, color: FluentTheme.of(context).inactiveColor),
              const SizedBox(height: Spacing.md),
              const Text('No hay usuarios en esta empresa'),
              const SizedBox(height: Spacing.ms),
              FilledButton(
                onPressed: () => _showInviteDialog(context),
                child: const Text('Invitar el primero'),
              ),
            ],
          ),
        ),
        builder: (context, usuarios) => LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;

            if (w < PilarBreakpoints.mobile) {
              // ── Móvil: cards ──
              return _MobileList(
                usuarios: usuarios,
                currentUserId: _currentUserId,
                onRefresh: () => ref.invalidate(adminUsuariosProvider),
                onEdit: (u) => _showEditDialog(context, u),
              );
            }

            return _DesktopGrid(
              usuarios: usuarios,
              currentUserId: _currentUserId,
              onRefresh: () => ref.invalidate(adminUsuariosProvider),
              onSelect: (u) => _showEditDialog(context, u),
            );
          },
        ),
      ),
    );
  }
}

// ===========================================================================
// SfDataGrid — pantalla grande (≥ 600 px)
// ===========================================================================

class _DesktopGrid extends ConsumerStatefulWidget {
  const _DesktopGrid({
    required this.usuarios,
    required this.currentUserId,
    required this.onRefresh,
    required this.onSelect,
  });

  final List<Map<String, dynamic>> usuarios;
  final String currentUserId;
  final VoidCallback onRefresh;
  final void Function(Map<String, dynamic>) onSelect;

  @override
  ConsumerState<_DesktopGrid> createState() => _DesktopGridState();
}

class _DesktopGridState extends ConsumerState<_DesktopGrid> {
  late _UsuariosDataSource _source;

  @override
  void initState() {
    super.initState();
    _source = _UsuariosDataSource(
      usuarios: widget.usuarios,
      currentUserId: widget.currentUserId,
      onToggle: _handleToggle,
      onGestionar: _showGestionarDialog,
      onSetPassword: _showSetPasswordDialog,
      onSelect: widget.onSelect,
      onCancelarInvitacion: _handleCancelarInvitacion,
      onDelete: _handleDelete,
    );
  }

  @override
  void didUpdateWidget(_DesktopGrid old) {
    super.didUpdateWidget(old);
    if (old.usuarios != widget.usuarios) {
      _source.update(widget.usuarios);
    }
  }

  Future<void> _handleToggle(String userId, bool value) async {
    if (!ref.read(connectivityProvider)) {
      _showError('Requiere conexión a internet');
      return;
    }
    _source.startToggling(userId);
    final result = await ref
        .read(usuariosAdminProvider.notifier)
        .toggleActivo(userId: userId, activo: value);
    _source.stopToggling(userId);
    if (result.ok) {
      widget.onRefresh();
    } else {
      if (mounted) _showError(_toggleErrorMsg(result.error));
    }
  }

  Future<void> _handleCancelarInvitacion(String email) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dlg) => ContentDialog(
        title: const Text('¿Cancelar invitación?'),
        content: Text(
          'Se cancelará la invitación enviada a "$email". '
          'El enlace de invitación dejará de funcionar.',
        ),
        actions: [
          Button(
            onPressed: () => Navigator.of(dlg).pop(false),
            child: const Text('No'),
          ),
          FilledButton(
            style: const ButtonStyle(
              backgroundColor: WidgetStatePropertyAll(Color(0xFFC42B1C)),
            ),
            onPressed: () => Navigator.of(dlg).pop(true),
            child: const Text('Cancelar invitación'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    final result = await ref
        .read(usuariosAdminProvider.notifier)
        .cancelarInvitacion(email: email);
    if (!mounted) return;
    if (result.ok) {
      widget.onRefresh();
      displayInfoBar(
        context,
        builder: (_, close) => InfoBar(
          title: const Text('Invitación cancelada'),
          severity: InfoBarSeverity.success,
          onClose: close,
        ),
      );
    } else {
      _showError(_cancelErrorMsg(result.error));
    }
  }

  String _cancelErrorMsg(String? code) => switch (code) {
        'PERMISSION_DENIED' => 'Sin permiso para cancelar invitaciones.',
        'INVITACION_NOT_FOUND' =>
          'Invitación no encontrada o ya fue procesada.',
        _ => code ?? 'Error desconocido',
      };

  Future<void> _handleDelete(Map<String, dynamic> usuario) async {
    final nombre = usuario['nombre'] as String? ??
        usuario['email'] as String? ??
        '';
    final userId = usuario['usuario_id'] as String? ?? '';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dlg) => ContentDialog(
        title: const Text('¿Quitar usuario de la empresa?'),
        content: Text(
          'Se desactivará el acceso de "$nombre" a esta empresa. '
          'Podrás reactivarlo en el futuro si es necesario.',
        ),
        actions: [
          Button(
            onPressed: () => Navigator.of(dlg).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: const ButtonStyle(
              backgroundColor: WidgetStatePropertyAll(Color(0xFFC42B1C)),
            ),
            onPressed: () => Navigator.of(dlg).pop(true),
            child: const Text('Quitar de empresa'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    final removeResult = await ref
        .read(usuariosAdminProvider.notifier)
        .removeFromEmpresa(userId: userId);

    if (!mounted) return;

    if (!removeResult.ok) {
      _showError(_deleteErrorMsg(removeResult.error));
      return;
    }

    widget.onRefresh();

    // ── Sin otras empresas → ofrecer eliminación completa ──
    if (removeResult.orphan && mounted) {
      final deleteAuth = await showDialog<bool>(
        context: context,
        builder: (dlg2) => ContentDialog(
          title: const Text('Usuario sin empresa'),
          content: Text(
            '"$nombre" ya no pertenece a ninguna empresa. '
            '¿Deseas eliminarlo completamente del sistema?',
          ),
          actions: [
            Button(
              onPressed: () => Navigator.of(dlg2).pop(false),
              child: const Text('Solo quitar'),
            ),
            FilledButton(
              style: const ButtonStyle(
                backgroundColor: WidgetStatePropertyAll(Color(0xFFC42B1C)),
              ),
              onPressed: () => Navigator.of(dlg2).pop(true),
              child: const Text('Eliminar del sistema'),
            ),
          ],
        ),
      );

      if (!mounted) return;

      if (deleteAuth == true) {
        final delResult = await ref
            .read(usuariosAdminProvider.notifier)
            .deleteFromAuth(userId: userId);
        if (!mounted) return;
        if (delResult.ok) {
          displayInfoBar(context,
              builder: (_, close) => InfoBar(
                    title: const Text('Usuario eliminado del sistema'),
                    severity: InfoBarSeverity.success,
                    onClose: close,
                  ));
        } else {
          final detalle = _buildTieneDatosMsg(delResult.mensajes, delResult.adjuntos);
          displayInfoBar(context,
              builder: (_, close) => InfoBar(
                    title: const Text('Quitado de empresa, no del sistema'),
                    content: Text(
                        'El usuario fue desactivado pero no se puede eliminar completamente.$detalle'),
                    severity: InfoBarSeverity.warning,
                    onClose: close,
                  ));
        }
      } else {
        // El admin eligió "Solo quitar"
        displayInfoBar(context,
            builder: (_, close) => InfoBar(
                  title: const Text('Usuario quitado de la empresa'),
                  severity: InfoBarSeverity.success,
                  onClose: close,
                ));
      }
    } else if (mounted) {
      displayInfoBar(context,
          builder: (_, close) => InfoBar(
                title: const Text('Usuario quitado de la empresa'),
                severity: InfoBarSeverity.success,
                onClose: close,
              ));
    }
  }


  String _deleteErrorMsg(String? code,
          {int? mensajes, int? adjuntos}) =>
      switch (code) {
        'PERMISSION_DENIED' => 'Sin permiso para eliminar usuarios.',
        'CANNOT_REMOVE_YOURSELF' => 'No puedes quitarte a ti mismo.',
        'USER_NOT_IN_EMPRESA' => 'El usuario no pertenece a esta empresa.',
        'USER_HAS_ACTIVE_MEMBERSHIPS' =>
          'El usuario aún tiene membresías activas en otras empresas.',
        'TIENE_DATOS' => 'No se puede eliminar: el usuario tiene '
            '${mensajes != null && mensajes > 0 ? '$mensajes mensaje(s)' : ''}'
            '${mensajes != null && mensajes > 0 && adjuntos != null && adjuntos > 0 ? ' y ' : ''}'
            '${adjuntos != null && adjuntos > 0 ? '$adjuntos archivo(s) subido(s)' : ''}'
            ' asociados.',
        _ => code ?? 'Error desconocido',
      };

  void _showGestionarDialog(Map<String, dynamic> usuario) {
    showDialog<void>(
      context: context,
      builder: (_) => _GestionarRolesDialog(
        usuario: usuario,
        onChanged: widget.onRefresh,
      ),
    );
  }

  void _showSetPasswordDialog(Map<String, dynamic> usuario) {
    showDialog<void>(
      context: context,
      builder: (_) => _SetPasswordDialog(
        userId: usuario['usuario_id'] as String? ?? '',
        email: usuario['email'] as String? ?? '',
      ),
    );
  }

  String _toggleErrorMsg(String? code) => switch (code) {
        'PERMISSION_DENIED' => 'Sin permiso para gestionar usuarios.',
        'CANNOT_CHANGE_OWN_STATUS' => 'No puedes cambiar tu propio estado.',
        _ => code ?? 'Error desconocido',
      };

  void _showError(String msg) {
    displayInfoBar(
      context,
      builder: (_, close) => InfoBar(
        title: const Text('Error'),
        content: Text(msg),
        severity: InfoBarSeverity.error,
        onClose: close,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final headerStyle = theme.typography.caption?.copyWith(
      fontWeight: FontWeight.w600,
      color: theme.resources.textFillColorSecondary,
    );

    Widget headerCell(String label, {Alignment align = Alignment.centerLeft}) =>
        Container(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.ms),
          alignment: align,
          child: Text(label, style: headerStyle),
        );

    return SfDataGridTheme(
      data: SfDataGridThemeData(
        headerColor: theme.accentColor.withValues(alpha: 0.08),
        gridLineColor: theme.resources.dividerStrokeColorDefault,
        gridLineStrokeWidth: 0.5,
        rowHoverColor: theme.accentColor.withValues(alpha: 0.04),
        selectionColor: Colors.transparent,
        headerHoverColor: theme.accentColor.withValues(alpha: 0.12),
      ),
      child: SfDataGrid(
        source: _source,
        columnWidthMode: ColumnWidthMode.fill,
        gridLinesVisibility: GridLinesVisibility.horizontal,
        headerGridLinesVisibility: GridLinesVisibility.horizontal,
        rowHeight: 64,
        headerRowHeight: 40,
        selectionMode: SelectionMode.none,
        columns: [
          GridColumn(
            columnName: 'usuario',
            minimumWidth: 200,
            label: headerCell('Usuario'),
          ),
          GridColumn(
            columnName: 'roles',
            minimumWidth: 120,
            label: headerCell('Roles'),
          ),
          GridColumn(
            columnName: 'acceso',
            width: 165,
            label: headerCell('Último acceso'),
          ),
          GridColumn(
            columnName: 'estado',
            width: 80,
            label: headerCell('Estado', align: Alignment.center),
          ),
          GridColumn(
            columnName: 'acciones',
            width: 140,
            label: const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// DataGridSource
// ---------------------------------------------------------------------------

class _UsuariosDataSource extends DataGridSource {
  _UsuariosDataSource({
    required List<Map<String, dynamic>> usuarios,
    required this.currentUserId,
    required this.onToggle,
    required this.onGestionar,
    required this.onSetPassword,
    required this.onSelect,
    required this.onCancelarInvitacion,
    required this.onDelete,
  }) : _usuarios = List.from(usuarios);

  List<Map<String, dynamic>> _usuarios;
  final String currentUserId;
  final Future<void> Function(String id, bool value) onToggle;
  final void Function(Map<String, dynamic> usuario) onGestionar;
  final void Function(Map<String, dynamic> usuario) onSetPassword;
  final void Function(Map<String, dynamic> usuario) onSelect;
  final Future<void> Function(String email) onCancelarInvitacion;
  final Future<void> Function(Map<String, dynamic> usuario) onDelete;
  final Set<String> _toggling = {};

  void update(List<Map<String, dynamic>> newList) {
    _usuarios = List.from(newList);
    notifyDataSourceListeners();
  }

  void startToggling(String id) {
    _toggling.add(id);
    notifyDataSourceListeners();
  }

  void stopToggling(String id) {
    _toggling.remove(id);
    notifyDataSourceListeners();
  }

  @override
  List<DataGridRow> get rows => _usuarios
      .map((u) => DataGridRow(cells: [
            DataGridCell<Map<String, dynamic>>(columnName: 'usuario', value: u),
            DataGridCell<Map<String, dynamic>>(columnName: 'roles', value: u),
            DataGridCell<Map<String, dynamic>>(columnName: 'acceso', value: u),
            DataGridCell<Map<String, dynamic>>(columnName: 'estado', value: u),
            DataGridCell<Map<String, dynamic>>(columnName: 'acciones', value: u),
          ]))
      .toList();

  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    final u = row.getCells()[0].value as Map<String, dynamic>;
    final userId = u['usuario_id'] as String? ?? '';
    final activo = u['activo'] as bool? ?? true;
    final nombre = u['nombre'] as String? ?? u['email'] as String? ?? '';
    final email = u['email'] as String? ?? '';
    final avatarUrl = u['avatar_url'] as String?;
    final roles = _parseRoles(u['roles']);
    final acceso = u['ultimo_acceso'] as String?;
    final invitacionEstado = u['invitacion_estado'] as String?;
    final esPendiente = invitacionEstado != null;
    final esYo = !esPendiente && userId == currentUserId;
    final isToggling = _toggling.contains(userId);

    return DataGridRowAdapter(
      color: activo ? null : const Color(0x08808080),
      cells: [
        // ---- Usuario ----
        _UsuarioCell(
          nombre: nombre,
          email: email,
          activo: activo,
          esYo: esYo,
          avatarUrl: avatarUrl,
        ),

        // ---- Roles ----
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.ms, vertical: Spacing.sm),
          child: roles.isEmpty
              ? const _GreyText('Sin rol')
              : Wrap(
                  spacing: Spacing.xs,
                  runSpacing: Spacing.xs,
                  children: roles
                      .map((r) => _RolBadge(nombre: r['nombre'] as String? ?? ''))
                      .toList(),
                ),
        ),

        // ---- Último acceso ----
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.ms),
          child: _AccesoCell(ultimoAcceso: acceso),
        ),

        // ---- Estado ----
        Center(
          child: esPendiente
              ? const _InvitadoBadge()
              : esYo
                  ? const SizedBox.shrink()
                  : isToggling
                      ? const PilarProgressRing(size: 20)
                      : ToggleSwitch(
                          checked: activo,
                          onChanged: (v) => onToggle(userId, v),
                        ),
        ),

        // ---- Acciones ----
        Center(
          child: esPendiente
              ? Tooltip(
                  message: 'Cancelar invitación',
                  child: IconButton(
                    icon: const Icon(FluentIcons.delete, size: 16),
                    onPressed: () => onCancelarInvitacion(email),
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Tooltip(
                      message: 'Editar',
                      child: IconButton(
                        icon: const Icon(FluentIcons.edit_contact, size: 16),
                        onPressed: () => onSelect(u),
                      ),
                    ),
                    if (!esYo) ...[
                      Tooltip(
                        message: 'Gestionar roles',
                        child: IconButton(
                          icon: const Icon(FluentIcons.people_add, size: 16),
                          onPressed: () => onGestionar(u),
                        ),
                      ),
                      Tooltip(
                        message: 'Establecer contraseña',
                        child: IconButton(
                          icon: const Icon(FluentIcons.password_field, size: 16),
                          onPressed: () => onSetPassword(u),
                        ),
                      ),
                      Tooltip(
                        message: 'Eliminar usuario',
                        child: IconButton(
                          icon: Icon(FluentIcons.delete,
                              size: 16,
                              color: Colors.red.normal),
                          onPressed: () => onDelete(u),
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Cells
// ---------------------------------------------------------------------------

class _UsuarioCell extends StatelessWidget {
  const _UsuarioCell({
    required this.nombre,
    required this.email,
    required this.activo,
    required this.esYo,
    this.avatarUrl,
  });

  final String nombre;
  final String email;
  final bool activo;
  final bool esYo;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    return UserCard(
      nombre: nombre,
      email: email,
      avatarUrl: avatarUrl,
      avatarRadius: 22,
      dimmed: !activo,
      trailing: esYo ? _TuChip() : null,
      padding: const EdgeInsets.symmetric(horizontal: Spacing.ms, vertical: Spacing.sm),
    );
  }
}

class _AccesoCell extends StatelessWidget {
  const _AccesoCell({required this.ultimoAcceso});
  final String? ultimoAcceso;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Row(
      children: [
        Icon(FluentIcons.clock, size: 12, color: theme.inactiveColor),
        const SizedBox(width: Spacing.xs),
        Flexible(
          child: Text(
            _formatAcceso(ultimoAcceso),
            style: theme.typography.caption?.copyWith(color: theme.inactiveColor),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _RolBadge extends StatelessWidget {
  const _RolBadge({required this.nombre});
  final String nombre;

  @override
  Widget build(BuildContext context) {
    final color = FluentTheme.of(context).accentColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: Spacing.xxs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        nombre,
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500),
      ),
    );
  }
}

class _TuChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final color = FluentTheme.of(context).accentColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.xs, vertical: Spacing.xxs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        'Tú',
        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _GreyText extends StatelessWidget {
  const _GreyText(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        color: FluentTheme.of(context).inactiveColor,
        fontStyle: FontStyle.italic,
      ),
    );
  }
}

class _InvitadoBadge extends StatelessWidget {
  const _InvitadoBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: Spacing.xxs),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.30),
          width: 0.5,
        ),
      ),
      child: const Text(
        'Pendiente',
        style: TextStyle(
          fontSize: 11,
          color: Color(0xFFF59E0B),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

// ===========================================================================
// Panel de edición de usuario (side panel ≥900px o dialog en tablet/móvil)
// ===========================================================================

class _EditarUsuarioPanel extends ConsumerStatefulWidget {
  const _EditarUsuarioPanel({
    super.key,
    required this.usuarioId,
    required this.usuarioData,
    required this.esYo,
    required this.inDialog,
    required this.onRefresh,
  });

  final String usuarioId;
  final Map<String, dynamic> usuarioData;
  final bool esYo;
  final bool inDialog;
  final VoidCallback onRefresh;

  @override
  ConsumerState<_EditarUsuarioPanel> createState() =>
      _EditarUsuarioPanelState();
}

class _EditarUsuarioPanelState extends ConsumerState<_EditarUsuarioPanel> {
  // --- Loading ---
  bool _loading = true;
  String? _loadError;

  // --- Perfil ---
  String? _avatarUrl;
  final _nombreCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _emailLoginCtrl = TextEditingController();
  String? _emailLogin;
  String? _originalEmailLogin;
  String? _nombreGlobal;
  String? _zonaHoraria;

  bool _savingPerfil = false;
  String? _perfilMsg;
  bool _perfilSuccess = false;

  // --- Roles ---
  Set<String> _selectedRoles = {};
  bool _savingRoles = false;
  String? _rolesMsg;
  bool _rolesSuccess = false;

  // --- Contraseña ---
  String _password = '';
  String _confirmPassword = '';
  bool _savingPassword = false;
  String? _passwordMsg;
  bool _passwordSuccess = false;

  // --- Avatar ---
  bool _uploadingAvatar = false;

  // --- Password section key (force widget recreation after successful save) ---
  int _passwordSectionKey = 0;

  // --- Remove from empresa ---
  bool _removingFromEmpresa = false;

  @override
  void initState() {
    super.initState();
    _loadPerfil();
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _telefonoCtrl.dispose();
    _emailCtrl.dispose();
    _emailLoginCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPerfil() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final result = await ref
        .read(usuariosAdminProvider.notifier)
        .getPerfil(userId: widget.usuarioId);

    if (result.error != null) {
      setState(() {
        _loading = false;
        _loadError = result.error;
      });
      return;
    }

    final map = result.data!;
    _avatarUrl = map['avatar_url'] as String?;
    _emailLogin = map['email_login'] as String?;
    _originalEmailLogin = _emailLogin;
    _emailLoginCtrl.text = _emailLogin ?? '';
    _nombreGlobal = map['nombre_global'] as String?;
    _nombreCtrl.text = map['nombre_display'] as String? ?? '';
    _telefonoCtrl.text = map['telefono'] as String? ?? '';
    _emailCtrl.text = map['email_contacto'] as String? ?? '';
    _zonaHoraria = map['zona_horaria'] as String? ?? 'America/Guayaquil';

    // Roles desde la lista
    _selectedRoles = _parseRoles(widget.usuarioData['roles'])
        .map((r) => r['id'] as String)
        .toSet();

    setState(() => _loading = false);
  }

  Future<void> _savePerfil() async {
    if (!ref.read(connectivityProvider)) {
      setState(() => _perfilMsg = 'Requiere conexión a internet');
      return;
    }
    setState(() {
      _savingPerfil = true;
      _perfilMsg = null;
      _perfilSuccess = false;
    });

    // 1. Guardar campos de perfil
    final result = await ref
        .read(usuariosAdminProvider.notifier)
        .updatePerfil(
          userId: widget.usuarioId,
          data: {
            'nombre_display': _nombreCtrl.text.trim(),
            'telefono': _telefonoCtrl.text.trim(),
            'email_contacto': _emailCtrl.text.trim(),
            if (_zonaHoraria != null) 'zona_horaria': _zonaHoraria!,
          },
        );

    if (!mounted) return;

    if (!result.ok) {
      setState(() {
        _perfilMsg = _errorLabel(result.error);
        _savingPerfil = false;
      });
      return;
    }

    // 2. Cambiar email de acceso si fue modificado
    final newEmail = _emailLoginCtrl.text.trim().toLowerCase();
    final currentEmail = (_originalEmailLogin ?? '').toLowerCase();
    if (newEmail.isNotEmpty && newEmail != currentEmail) {
      final emailResult = await ref
          .read(usuariosAdminProvider.notifier)
          .changeEmail(userId: widget.usuarioId, newEmail: newEmail);
      if (!mounted) return;
      if (!emailResult.ok) {
        setState(() {
          _perfilMsg = _errorLabel(emailResult.error);
          _savingPerfil = false;
        });
        return;
      }
      setState(() {
        _originalEmailLogin = newEmail;
        _emailLogin = newEmail;
      });
    }

    setState(() {
      _perfilSuccess = true;
      _perfilMsg = 'Datos guardados correctamente';
      _savingPerfil = false;
    });
    widget.onRefresh();
  }

  Future<void> _saveAll() async {
    await _savePerfil();
    if (!widget.esYo && mounted) await _saveRoles();
  }

  Future<void> _saveRoles() async {
    if (!ref.read(connectivityProvider)) {
      setState(() => _rolesMsg = 'Requiere conexión a internet');
      return;
    }
    setState(() {
      _savingRoles = true;
      _rolesMsg = null;
      _rolesSuccess = false;
    });
    final result = await ref
        .read(usuariosAdminProvider.notifier)
        .setRoles(userId: widget.usuarioId, rolIds: _selectedRoles.toList());
    if (!mounted) return;
    if (result.ok) {
      setState(() {
        _rolesSuccess = true;
        _rolesMsg = 'Roles actualizados';
        _savingRoles = false;
      });
      widget.onRefresh();
    } else {
      setState(() {
        _rolesMsg = _errorLabel(result.error);
        _savingRoles = false;
      });
    }
  }

  Future<void> _savePassword() async {
    if (!ref.read(connectivityProvider)) {
      setState(() {
        _passwordMsg = 'Requiere conexión a internet';
        _passwordSuccess = false;
      });
      return;
    }
    if (_password.length < 6) {
      setState(() {
        _passwordMsg = 'Mínimo 6 caracteres.';
        _passwordSuccess = false;
      });
      return;
    }
    if (_password != _confirmPassword) {
      setState(() {
        _passwordMsg = 'Las contraseñas no coinciden.';
        _passwordSuccess = false;
      });
      return;
    }
    setState(() {
      _savingPassword = true;
      _passwordMsg = null;
      _passwordSuccess = false;
    });
    final result = await ref
        .read(usuariosAdminProvider.notifier)
        .setPassword(userId: widget.usuarioId, password: _password);
    if (!mounted) return;
    if (result.ok) {
      setState(() {
        _passwordSuccess = true;
        _passwordMsg = 'Contraseña actualizada';
        _password = '';
        _confirmPassword = '';
        _passwordSectionKey++; // Fuerza recreación de los TextEditingControllers
        _savingPassword = false;
      });
    } else {
      setState(() {
        _passwordMsg = _errorLabel(result.error);
        _savingPassword = false;
      });
    }
  }

  Future<void> _removeFromEmpresa() async {
    final nombre = widget.usuarioData['nombre'] as String? ??
        widget.usuarioData['email'] as String? ??
        '';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => ContentDialog(
        title: const Text('¿Quitar usuario de la empresa?'),
        content: Text(
          'Se desactivará el acceso de "$nombre" a esta empresa. '
          'Podrás reactivarlo en el futuro si es necesario.',
        ),
        actions: [
          Button(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: const ButtonStyle(
              backgroundColor: WidgetStatePropertyAll(Color(0xFFC42B1C)),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    if (!ref.read(connectivityProvider)) {
      if (mounted) {
        displayInfoBar(context,
            builder: (_, close) => InfoBar(
                  title: const Text('Sin conexión'),
                  content: const Text('Requiere conexión a internet'),
                  severity: InfoBarSeverity.error,
                  onClose: close,
                ));
      }
      return;
    }

    setState(() => _removingFromEmpresa = true);
    final removeResult = await ref
        .read(usuariosAdminProvider.notifier)
        .removeFromEmpresa(userId: widget.usuarioId);

    if (!mounted) return;

    if (!removeResult.ok) {
      setState(() => _removingFromEmpresa = false);
      displayInfoBar(
        context,
        builder: (_, close) => InfoBar(
          title: const Text('Error'),
          content: Text(_errorLabel(removeResult.error)),
          severity: InfoBarSeverity.error,
          onClose: close,
        ),
      );
      return;
    }

    if (removeResult.orphan && mounted) {
      final deleteAuth = await showDialog<bool>(
        context: context,
        builder: (_) => ContentDialog(
          title: const Text('Usuario sin empresa'),
          content: Text(
            '"$nombre" ya no pertenece a ninguna empresa. '
            '¿Deseas eliminarlo completamente del sistema? '
            'Esta acción no se puede deshacer.',
          ),
          actions: [
            Button(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Solo quitar'),
            ),
            FilledButton(
              style: const ButtonStyle(
                backgroundColor: WidgetStatePropertyAll(Color(0xFFC42B1C)),
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Eliminar del sistema'),
            ),
          ],
        ),
      );

      if (deleteAuth == true && mounted) {
        final delResult = await ref
            .read(usuariosAdminProvider.notifier)
            .deleteFromAuth(userId: widget.usuarioId);
        if (!delResult.ok && mounted) {
          displayInfoBar(
            context,
            builder: (_, close) => InfoBar(
              title: const Text('No se pudo eliminar'),
              content: Text(_errorLabel(delResult.error)),
              severity: InfoBarSeverity.warning,
              onClose: close,
            ),
          );
        }
      }
    }

    if (mounted) {
      widget.onRefresh();
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null || bytes.isEmpty) return;

    setState(() => _uploadingAvatar = true);

    final uploadResult = await ref
        .read(usuariosAdminProvider.notifier)
        .uploadAvatar(userId: widget.usuarioId, bytes: bytes);

    if (!mounted) return;

    if (uploadResult.error != null) {
      setState(() => _uploadingAvatar = false);
      displayInfoBar(
        context,
        builder: (_, close) => InfoBar(
          title: const Text('Error'),
          content: Text('Error al subir la imagen: ${uploadResult.error}'),
          severity: InfoBarSeverity.error,
          onClose: close,
        ),
      );
    } else {
      setState(() {
        _avatarUrl = uploadResult.url;
        _uploadingAvatar = false;
      });
      widget.onRefresh();
    }
  }

  String _errorLabel(String? code) => switch (code) {
        'PERMISSION_DENIED' => 'Sin permiso para gestionar usuarios.',
        'CANNOT_CHANGE_OWN_ROLE' => 'No puedes cambiar tu propio rol.',
        'CANNOT_REMOVE_YOURSELF' => 'No puedes quitarte a ti mismo de la empresa.',
        'CANNOT_DELETE_YOURSELF' => 'No puedes eliminarte a ti mismo del sistema.',
        'USER_NOT_IN_EMPRESA' => 'El usuario no pertenece a esta empresa.',
        'USER_NOT_FOUND' => 'Usuario no encontrado.',
        'USER_HAS_ACTIVE_MEMBERSHIPS' => 'El usuario aún pertenece a otras empresas.',
        'USER_HAS_RELATED_RECORDS' =>
          'El usuario tiene registros relacionados y no puede ser eliminado.',
        'PASSWORD_TOO_SHORT' => 'Mínimo 6 caracteres.',
        'EMAIL_EXISTS' => 'Este email ya está en uso por otro usuario.',
        'INVALID_EMAIL' => 'El email ingresado no es válido.',
        _ => code ?? 'Error desconocido',
      };

  // ---- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final nombre = widget.usuarioData['nombre'] as String? ??
        widget.usuarioData['email'] as String? ??
        '';
    final email = widget.usuarioData['email'] as String? ?? '';
    final initial = nombre.isNotEmpty ? nombre[0].toUpperCase() : '?';

    // ---- Helper: error / loading states ----
    Widget errorWidget() => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(FluentIcons.error,
                  color: theme.resources.systemFillColorCritical),
              const SizedBox(height: Spacing.sm),
              Text(_loadError!,
                  style: TextStyle(
                      color: theme.resources.systemFillColorCritical)),
              const SizedBox(height: Spacing.ms),
              Button(onPressed: _loadPerfil, child: const Text('Reintentar')),
            ],
          ),
        );

    // ---- Secciones compartidas ----
    final datosSection = _DatosContactoSection(
      nombreCtrl: _nombreCtrl,
      telefonoCtrl: _telefonoCtrl,
      emailCtrl: _emailCtrl,
      emailLoginCtrl: _emailLoginCtrl,
      nombreGlobal: _nombreGlobal,
      zonaHoraria: _zonaHoraria,
      saving: _savingPerfil,
      msg: _perfilMsg,
      success: _perfilSuccess,
      onSave: _savePerfil,
      onDismiss: () => setState(() {
        _perfilMsg = null;
        _perfilSuccess = false;
      }),
      onZonaChanged: (v) => setState(() => _zonaHoraria = v),
      showSaveButton: !widget.inDialog,
    );

    final rolesSection = _RolesSection(
      selectedRoles: _selectedRoles,
      saving: _savingRoles,
      msg: _rolesMsg,
      success: _rolesSuccess,
      onToggleRole: (id, checked) => setState(() {
        if (checked) {
          _selectedRoles.add(id);
        } else {
          _selectedRoles.remove(id);
        }
      }),
      onSave: _saveRoles,
      onDismiss: () => setState(() {
        _rolesMsg = null;
        _rolesSuccess = false;
      }),
      showSaveButton: !widget.inDialog,
    );

    final passwordSection = _PasswordSection(
      key: ValueKey(_passwordSectionKey),
      saving: _savingPassword,
      msg: _passwordMsg,
      success: _passwordSuccess,
      onPasswordChanged: (v) => _password = v,
      onConfirmChanged: (v) => _confirmPassword = v,
      onSave: _savePassword,
      onDismiss: () => setState(() {
        _passwordMsg = null;
        _passwordSuccess = false;
      }),
    );

    // ==========================================================
    // DIALOG MODE — el panel construye su propio ContentDialog
    // ==========================================================
    if (widget.inDialog) {
      final screenWidth = MediaQuery.of(context).size.width;
      final isWide = screenWidth >= 680;
      final isSaving = _savingPerfil || _savingRoles || _removingFromEmpresa;

      // ---- Avatar circle reutilizable ----
      Widget avatarCircle(double size) => GestureDetector(
            onTap: _uploadingAvatar ? null : _pickAndUploadAvatar,
            child: Stack(
              children: [
                Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    color: theme.accentColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _uploadingAvatar
                      ? Center(child: ProgressRing(strokeWidth: size * 0.035))
                      : _avatarUrl != null
                          ? Image.network(
                              _avatarUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Center(
                                child: Text(
                                  initial,
                                  style: TextStyle(
                                    fontSize: size * 0.38,
                                    fontWeight: FontWeight.w600,
                                    color: theme.accentColor,
                                  ),
                                ),
                              ),
                            )
                          : Center(
                              child: Text(
                                initial,
                                style: TextStyle(
                                  fontSize: size * 0.38,
                                  fontWeight: FontWeight.w600,
                                  color: theme.accentColor,
                                ),
                              ),
                            ),
                ),
                Positioned(
                  right: Spacing.none,
                  bottom: Spacing.none,
                  child: Container(
                    width: size * 0.28,
                    height: size * 0.28,
                    decoration: BoxDecoration(
                      color: theme.resources.cardStrokeColorDefault,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: theme.resources.controlStrokeColorDefault),
                    ),
                    child: Icon(FluentIcons.camera,
                        size: size * 0.14, color: theme.inactiveColor),
                  ),
                ),
              ],
            ),
          );

      final cambiarContra = Button(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => _SetPasswordDialog(
            userId: widget.usuarioId,
            email: widget.usuarioData['email'] as String? ?? '',
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(FluentIcons.password_field, size: 16),
            SizedBox(width: Spacing.sm),
            Text('Cambiar contraseña'),
          ],
        ),
      );

      Widget dialogContent;
      if (_loading) {
        dialogContent = const SizedBox(
            height: 120, child: PilarLoadingCenter());
      } else if (_loadError != null) {
        dialogContent = errorWidget();
      } else if (isWide) {
        // ── Layout ancho: avatar izquierda, formulario derecha ──
        dialogContent = SingleChildScrollView(
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 150,
                  child: Column(
                    children: [
                      avatarCircle(110),
                      const SizedBox(height: Spacing.sm),
                      _uploadingAvatar
                          ? Text(
                              'Subiendo…',
                              style: theme.typography.caption
                                  ?.copyWith(color: theme.inactiveColor),
                              textAlign: TextAlign.center,
                            )
                          : GestureDetector(
                              onTap: _pickAndUploadAvatar,
                              child: Text(
                                'Cambiar foto',
                                style: theme.typography.caption
                                    ?.copyWith(color: theme.accentColor),
                                textAlign: TextAlign.center,
                              ),
                            ),
                      const SizedBox(height: Spacing.md),
                      Text(
                        nombre,
                        style: theme.typography.bodyStrong,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                      const SizedBox(height: Spacing.xs),
                      Text(
                        email,
                        style: theme.typography.caption
                            ?.copyWith(color: theme.inactiveColor),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Spacing.ml),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      datosSection,
                      if (!widget.esYo) ...[
                        const Divider(),
                        const SizedBox(height: Spacing.xs),
                        Text('Roles', style: theme.typography.bodyStrong),
                        const SizedBox(height: Spacing.sm),
                        rolesSection,
                      ],
                      const SizedBox(height: Spacing.ms),
                      cambiarContra,
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        // ── Layout estrecho: avatar arriba, formulario abajo ──
        dialogContent = SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: avatarCircle(80)),
              const SizedBox(height: Spacing.sm),
              Center(
                child: _uploadingAvatar
                    ? Text(
                        'Subiendo…',
                        style: theme.typography.caption
                            ?.copyWith(color: theme.inactiveColor),
                      )
                    : GestureDetector(
                        onTap: _pickAndUploadAvatar,
                        child: Text(
                          'Cambiar foto',
                          style: theme.typography.caption
                              ?.copyWith(color: theme.accentColor),
                        ),
                      ),
              ),
              const SizedBox(height: Spacing.ml),
              datosSection,
              if (!widget.esYo) ...[
                const Divider(),
                const SizedBox(height: Spacing.xs),
                Text('Roles', style: theme.typography.bodyStrong),
                const SizedBox(height: Spacing.sm),
                rolesSection,
              ],
              const SizedBox(height: Spacing.ms),
              cambiarContra,
            ],
          ),
        );
      }

      return ContentDialog(
        constraints: BoxConstraints(
          maxWidth: isWide ? 780 : 500,
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        title: Text(nombre, overflow: TextOverflow.ellipsis),
        content: dialogContent,
        actions: [
          // Single Row to allow left (danger) + right (main) button layout
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // ── Botón destructivo (solo para otros usuarios) ──
              if (!widget.esYo)
                Button(
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.pressed)) {
                        return const Color(0xFFC42B1C).withValues(alpha: 0.15);
                      }
                      if (states.contains(WidgetState.hovered)) {
                        return const Color(0xFFC42B1C).withValues(alpha: 0.08);
                      }
                      return Colors.transparent;
                    }),
                    foregroundColor:
                        const WidgetStatePropertyAll(Color(0xFFC42B1C)),
                  ),
                  onPressed: isSaving ? null : _removeFromEmpresa,
                  child: _removingFromEmpresa
                      ? const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            PilarProgressRing(size: 14),
                            SizedBox(width: Spacing.sm),
                            Text('Quitando…'),
                          ],
                        )
                      : const Text('Quitar de empresa'),
                )
              else
                const SizedBox.shrink(),

              // ── Botones principales ──
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Button(
                    onPressed: isSaving
                        ? null
                        : () => Navigator.of(context).maybePop(),
                    child: const Text('Cerrar'),
                  ),
                  const SizedBox(width: Spacing.sm),
                  FilledButton(
                    onPressed: isSaving || _loading ? null : _saveAll,
                    child: (_savingPerfil || _savingRoles)
                        ? const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              PilarProgressRing(size: 14),
                              SizedBox(width: Spacing.sm),
                              Text('Guardando…'),
                            ],
                          )
                        : const Text('Guardar'),
                  ),
                ],
              ),
            ],
          ),
        ],
      );
    }

    // ==========================================================
    // SIDE PANEL MODE — layout completo con Expanders
    // ==========================================================
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ---- Header ----
        _PanelHeader(
          avatarUrl: _avatarUrl,
          initial: initial,
          nombre: nombre,
          email: email,
          uploadingAvatar: _uploadingAvatar,
          onUpload: _pickAndUploadAvatar,
          onClose: null,
          theme: theme,
        ),

        const Divider(),

        // ---- Contenido scrollable ----
        Expanded(
          child: _loading
              ? const PilarLoadingCenter()
              : _loadError != null
                  ? errorWidget()
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(Spacing.ms),
                      child: Column(
                        children: [
                          // ── Datos de contacto ──
                          Expander(
                            initiallyExpanded: true,
                            header: const Text('Datos de contacto'),
                            content: datosSection,
                          ),
                          const SizedBox(height: Spacing.sm),

                          // ── Roles (solo admin y no para sí mismo) ──
                          if (!widget.esYo) ...[
                            Expander(
                              initiallyExpanded: true,
                              header: const Text('Roles'),
                              content: rolesSection,
                            ),
                            const SizedBox(height: Spacing.sm),
                          ],

                          // ── Contraseña ──
                          Expander(
                            initiallyExpanded: false,
                            header: const Text('Contraseña'),
                            content: passwordSection,
                          ),
                        ],
                      ),
                    ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Panel header with large avatar
// ---------------------------------------------------------------------------

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.avatarUrl,
    required this.initial,
    required this.nombre,
    required this.email,
    required this.uploadingAvatar,
    required this.onUpload,
    required this.onClose,
    required this.theme,
  });

  final String? avatarUrl;
  final String initial;
  final String nombre;
  final String email;
  final bool uploadingAvatar;
  final VoidCallback onUpload;
  final VoidCallback? onClose;
  final FluentThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.md, Spacing.ms, Spacing.sm, Spacing.ms),
      child: Row(
        children: [
          // Avatar 80px con cámara overlay
          GestureDetector(
            onTap: uploadingAvatar ? null : onUpload,
            child: Stack(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: theme.accentColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: uploadingAvatar
                      ? const PilarLoadingCenter()
                      : avatarUrl != null
                          ? Image.network(
                              avatarUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Center(
                                child: Text(
                                  initial,
                                  style: theme.typography.title
                                      ?.copyWith(color: theme.accentColor),
                                ),
                              ),
                            )
                          : Center(
                              child: Text(
                                initial,
                                style: theme.typography.title
                                    ?.copyWith(color: theme.accentColor),
                              ),
                            ),
                ),
                Positioned(
                  right: Spacing.none,
                  bottom: Spacing.none,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: theme.resources.cardStrokeColorDefault,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: theme.resources.controlStrokeColorDefault),
                    ),
                    child: Icon(FluentIcons.camera,
                        size: 12, color: theme.inactiveColor),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Spacing.ms),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nombre,
                    style: theme.typography.bodyStrong,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: Spacing.xxs),
                Text(email,
                    style: theme.typography.caption
                        ?.copyWith(color: theme.inactiveColor),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          if (onClose != null)
            IconButton(
              icon: const Icon(FluentIcons.chrome_close, size: 12),
              onPressed: onClose,
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sección: Datos de contacto
// ---------------------------------------------------------------------------

class _DatosContactoSection extends StatelessWidget {
  const _DatosContactoSection({
    required this.nombreCtrl,
    required this.telefonoCtrl,
    required this.emailCtrl,
    required this.emailLoginCtrl,
    required this.nombreGlobal,
    required this.zonaHoraria,
    required this.saving,
    required this.msg,
    required this.success,
    required this.onSave,
    required this.onDismiss,
    required this.onZonaChanged,
    this.showSaveButton = true,
  });

  final TextEditingController nombreCtrl;
  final TextEditingController telefonoCtrl;
  final TextEditingController emailCtrl;
  final TextEditingController emailLoginCtrl;
  final String? nombreGlobal;
  final String? zonaHoraria;
  final bool saving;
  final String? msg;
  final bool success;
  final VoidCallback onSave;
  final VoidCallback onDismiss;
  final ValueChanged<String?> onZonaChanged;
  final bool showSaveButton;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InfoLabel(
          label: 'Nombre para mostrar',
          child: TextBox(
            controller: nombreCtrl,
            placeholder: nombreGlobal ?? 'Nombre visible',
            enabled: !saving,
          ),
        ),
        const SizedBox(height: Spacing.ms),
        InfoLabel(
          label: 'Teléfono',
          child: TextBox(
            controller: telefonoCtrl,
            placeholder: 'Ej: +593 99 123 4567',
            enabled: !saving,
            keyboardType: TextInputType.phone,
          ),
        ),
        const SizedBox(height: Spacing.ms),
        InfoLabel(
          label: 'Email de contacto',
          child: TextBox(
            controller: emailCtrl,
            placeholder: 'Email para notificaciones',
            enabled: !saving,
            keyboardType: TextInputType.emailAddress,
          ),
        ),
        const SizedBox(height: Spacing.ms),
        InfoLabel(
          label: 'Email de acceso',
          child: Tooltip(
            message: 'Email con el que el usuario inicia sesión. '
                'Si lo cambia, el usuario deberá usar el nuevo email.',
            child: TextBox(
              controller: emailLoginCtrl,
              placeholder: 'correo@empresa.com',
              enabled: !saving,
              keyboardType: TextInputType.emailAddress,
            ),
          ),
        ),
        const SizedBox(height: Spacing.ms),
        InfoLabel(
          label: 'Zona horaria',
          child: ComboBox<String>(
            value: zonaHoraria,
            isExpanded: true,
            items: kZonasHorarias
                .map((z) => ComboBoxItem<String>(value: z.$1, child: Text(z.$2)))
                .toList(),
            onChanged: saving ? null : onZonaChanged,
          ),
        ),
        if (msg != null) ...[
          const SizedBox(height: Spacing.ms),
          InfoBar(
            title: Text(success ? 'Guardado' : 'Error'),
            content: Text(msg!),
            severity:
                success ? InfoBarSeverity.success : InfoBarSeverity.error,
            onClose: onDismiss,
          ),
        ],
        if (showSaveButton) ...[
          const SizedBox(height: Spacing.ms),
          FilledButton(
            onPressed: saving ? null : onSave,
            child: saving
                ? const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PilarProgressRing(size: 14),
                      SizedBox(width: Spacing.sm),
                      Text('Guardando…'),
                    ],
                  )
                : const Text('Guardar datos'),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sección: Roles
// ---------------------------------------------------------------------------

class _RolesSection extends ConsumerWidget {
  const _RolesSection({
    required this.selectedRoles,
    required this.saving,
    required this.msg,
    required this.success,
    required this.onToggleRole,
    required this.onSave,
    required this.onDismiss,
    this.showSaveButton = true,
  });

  final Set<String> selectedRoles;
  final bool saving;
  final String? msg;
  final bool success;
  final void Function(String id, bool checked) onToggleRole;
  final VoidCallback onSave;
  final VoidCallback onDismiss;
  final bool showSaveButton;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = FluentTheme.of(context);
    final rolesAsync = ref.watch(rolesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        rolesAsync.when(
          data: (roles) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: roles
                .map((r) => GestureDetector(
                      onTap: saving
                          ? null
                          : () => onToggleRole(r.id, !selectedRoles.contains(r.id)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: Spacing.xxs),
                        child: Row(
                          children: [
                            Checkbox(
                              checked: selectedRoles.contains(r.id),
                              onChanged: saving
                                  ? null
                                  : (v) => onToggleRole(r.id, v == true),
                            ),
                            const SizedBox(width: Spacing.sm),
                            Text(r.nombre, style: theme.typography.body),
                          ],
                        ),
                      ),
                    ))
                .toList(),
          ),
          loading: () => const Center(child: PilarProgressRing()),
          error: (e, _) => Text('Error cargando roles: $e',
              style: TextStyle(
                  color: theme.resources.systemFillColorCritical)),
        ),
        if (msg != null) ...[
          const SizedBox(height: Spacing.sm),
          InfoBar(
            title: Text(success ? 'Guardado' : 'Error'),
            content: Text(msg!),
            severity: success ? InfoBarSeverity.success : InfoBarSeverity.error,
            onClose: onDismiss,
          ),
        ],
        if (showSaveButton) ...[
          const SizedBox(height: Spacing.ms),
          FilledButton(
            onPressed: saving ? null : onSave,
            child: saving
                ? const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PilarProgressRing(size: 14),
                      SizedBox(width: Spacing.sm),
                      Text('Guardando…'),
                    ],
                  )
                : const Text('Guardar roles'),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sección: Contraseña
// ---------------------------------------------------------------------------

class _PasswordSection extends StatefulWidget {
  const _PasswordSection({
    super.key,
    required this.saving,
    required this.msg,
    required this.success,
    required this.onPasswordChanged,
    required this.onConfirmChanged,
    required this.onSave,
    required this.onDismiss,
  });

  final bool saving;
  final String? msg;
  final bool success;
  final ValueChanged<String> onPasswordChanged;
  final ValueChanged<String> onConfirmChanged;
  final VoidCallback onSave;
  final VoidCallback onDismiss;

  @override
  State<_PasswordSection> createState() => _PasswordSectionState();
}

class _PasswordSectionState extends State<_PasswordSection> {
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  @override
  void dispose() {
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InfoLabel(
          label: 'Nueva contraseña',
          child: PasswordBox(
            controller: _passCtrl,
            placeholder: 'Mínimo 6 caracteres',
            enabled: !widget.saving,
            onChanged: widget.onPasswordChanged,
          ),
        ),
        const SizedBox(height: Spacing.ms),
        InfoLabel(
          label: 'Confirmar contraseña',
          child: PasswordBox(
            controller: _confirmCtrl,
            placeholder: 'Repetir contraseña',
            enabled: !widget.saving,
            onChanged: widget.onConfirmChanged,
          ),
        ),
        if (widget.msg != null) ...[
          const SizedBox(height: Spacing.sm),
          InfoBar(
            title: Text(widget.success ? 'Guardado' : 'Error'),
            content: Text(widget.msg!),
            severity: widget.success
                ? InfoBarSeverity.success
                : InfoBarSeverity.error,
            onClose: widget.onDismiss,
          ),
        ],
        const SizedBox(height: Spacing.ms),
        Button(
          onPressed: widget.saving ? null : widget.onSave,
          child: widget.saving
              ? const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PilarProgressRing(size: 14),
                    SizedBox(width: Spacing.sm),
                    Text('Cambiando…'),
                  ],
                )
              : const Text('Cambiar contraseña'),
        ),
      ],
    );
  }
}

// ===========================================================================
// Mobile list (< PilarBreakpoints.mobile)
// ===========================================================================

class _MobileList extends StatelessWidget {
  const _MobileList({
    required this.usuarios,
    required this.currentUserId,
    required this.onRefresh,
    required this.onEdit,
  });

  final List<Map<String, dynamic>> usuarios;
  final String currentUserId;
  final VoidCallback onRefresh;
  final void Function(Map<String, dynamic>) onEdit;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(Spacing.md),
      itemCount: usuarios.length,
      separatorBuilder: (_, __) => const SizedBox(height: Spacing.sm),
      itemBuilder: (_, i) => _UsuarioCard(
        usuario: usuarios[i],
        currentUserId: currentUserId,
        onRefresh: onRefresh,
        onEdit: onEdit,
      ),
    );
  }
}

class _UsuarioCard extends ConsumerStatefulWidget {
  const _UsuarioCard({
    required this.usuario,
    required this.currentUserId,
    required this.onRefresh,
    required this.onEdit,
  });

  final Map<String, dynamic> usuario;
  final String currentUserId;
  final VoidCallback onRefresh;
  final void Function(Map<String, dynamic>) onEdit;

  @override
  ConsumerState<_UsuarioCard> createState() => _UsuarioCardState();
}

class _UsuarioCardState extends ConsumerState<_UsuarioCard> {
  bool _toggling = false;
  bool _canceling = false;

  String get _userId => widget.usuario['usuario_id'] as String? ?? '';
  String get _email => widget.usuario['email'] as String? ?? '';
  String get _nombre => widget.usuario['nombre'] as String? ?? _email;
  String? get _avatarUrl => widget.usuario['avatar_url'] as String?;
  bool get _activo => widget.usuario['activo'] as bool? ?? true;
  List<Map<String, dynamic>> get _roles => _parseRoles(widget.usuario['roles']);
  String? get _acceso => widget.usuario['ultimo_acceso'] as String?;
  bool get _esYo => _userId == widget.currentUserId;
  bool get _esPendiente => widget.usuario['invitacion_estado'] != null;

  Future<void> _toggle(bool v) async {
    if (_toggling) return;
    if (!ref.read(connectivityProvider)) {
      if (mounted) {
        displayInfoBar(context,
            builder: (_, close) => InfoBar(
                  title: const Text('Sin conexión'),
                  content: const Text('Requiere conexión a internet'),
                  severity: InfoBarSeverity.error,
                  onClose: close,
                ));
      }
      return;
    }
    setState(() => _toggling = true);
    final result = await ref
        .read(usuariosAdminProvider.notifier)
        .toggleActivo(userId: _userId, activo: v);
    if (!mounted) return;
    if (result.ok) {
      widget.onRefresh();
    } else {
      displayInfoBar(context,
          builder: (_, close) => InfoBar(
                title: const Text('Error'),
                content: Text(result.error ?? 'Error'),
                severity: InfoBarSeverity.error,
                onClose: close,
              ));
    }
    setState(() => _toggling = false);
  }

  bool _deleting = false;

  Future<void> _deleteUser() async {
    if (_deleting) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dlg) => ContentDialog(
        title: const Text('¿Quitar usuario de la empresa?'),
        content: Text(
          'Se desactivará el acceso de "$_nombre" a esta empresa.',
        ),
        actions: [
          Button(
            onPressed: () => Navigator.of(dlg).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: const ButtonStyle(
              backgroundColor: WidgetStatePropertyAll(Color(0xFFC42B1C)),
            ),
            onPressed: () => Navigator.of(dlg).pop(true),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;
    setState(() => _deleting = true);

    final removeResult = await ref
        .read(usuariosAdminProvider.notifier)
        .removeFromEmpresa(userId: _userId);

    if (!mounted) return;

    if (!removeResult.ok) {
      setState(() => _deleting = false);
      displayInfoBar(context,
          builder: (_, close) => InfoBar(
                title: const Text('Error'),
                content: Text(removeResult.error ?? 'Error'),
                severity: InfoBarSeverity.error,
                onClose: close,
              ));
      return;
    }

    widget.onRefresh();

    if (removeResult.orphan && mounted) {
      final deleteAuth = await showDialog<bool>(
        context: context,
        builder: (dlg2) => ContentDialog(
          title: const Text('Usuario sin empresa'),
          content: Text(
              '"$_nombre" ya no pertenece a ninguna empresa. ¿Eliminar del sistema?'),
          actions: [
            Button(
              onPressed: () => Navigator.of(dlg2).pop(false),
              child: const Text('Solo quitar'),
            ),
            FilledButton(
              style: const ButtonStyle(
                backgroundColor: WidgetStatePropertyAll(Color(0xFFC42B1C)),
              ),
              onPressed: () => Navigator.of(dlg2).pop(true),
              child: const Text('Eliminar del sistema'),
            ),
          ],
        ),
      );

      if (!mounted) return;

      if (deleteAuth == true) {
        final delResult = await ref
            .read(usuariosAdminProvider.notifier)
            .deleteFromAuth(userId: _userId);
        if (!mounted) return;
        if (delResult.ok) {
          displayInfoBar(context,
              builder: (_, close) => InfoBar(
                    title: const Text('Usuario eliminado del sistema'),
                    severity: InfoBarSeverity.success,
                    onClose: close,
                  ));
        } else {
          final detalle = _buildTieneDatosMsg(delResult.mensajes, delResult.adjuntos);
          displayInfoBar(context,
              builder: (_, close) => InfoBar(
                    title: const Text('Quitado de empresa, no del sistema'),
                    content: Text(
                        'El usuario fue desactivado pero no se puede eliminar completamente.$detalle'),
                    severity: InfoBarSeverity.warning,
                    onClose: close,
                  ));
        }
      } else {
        displayInfoBar(context,
            builder: (_, close) => InfoBar(
                  title: const Text('Usuario quitado de la empresa'),
                  severity: InfoBarSeverity.success,
                  onClose: close,
                ));
      }
      setState(() => _deleting = false);
      return;
    }

    if (mounted) {
      setState(() => _deleting = false);
      displayInfoBar(context,
          builder: (_, close) => InfoBar(
                title: const Text('Usuario quitado de la empresa'),
                severity: InfoBarSeverity.success,
                onClose: close,
              ));
    }
  }

  Future<void> _cancelInvitacion() async {
    if (_canceling) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dlg) => ContentDialog(
        title: const Text('¿Cancelar invitación?'),
        content: Text(
          'Se cancelará la invitación enviada a "$_email". '
          'El enlace de invitación dejará de funcionar.',
        ),
        actions: [
          Button(
            onPressed: () => Navigator.of(dlg).pop(false),
            child: const Text('No'),
          ),
          FilledButton(
            style: const ButtonStyle(
              backgroundColor: WidgetStatePropertyAll(Color(0xFFC42B1C)),
            ),
            onPressed: () => Navigator.of(dlg).pop(true),
            child: const Text('Cancelar invitación'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;
    setState(() => _canceling = true);

    final result = await ref
        .read(usuariosAdminProvider.notifier)
        .cancelarInvitacion(email: _email);

    if (!mounted) return;
    setState(() => _canceling = false);

    if (result.ok) {
      widget.onRefresh();
      displayInfoBar(context,
          builder: (_, close) => InfoBar(
                title: const Text('Invitación cancelada'),
                severity: InfoBarSeverity.success,
                onClose: close,
              ));
    } else {
      displayInfoBar(context,
          builder: (_, close) => InfoBar(
                title: const Text('Error'),
                content: Text(result.error ?? 'Error desconocido'),
                severity: InfoBarSeverity.error,
                onClose: close,
              ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final initial = _nombre.isNotEmpty ? _nombre[0].toUpperCase() : '?';

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Avatar 52px en mobile
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: _activo
                      ? theme.accentColor.withValues(alpha: 0.12)
                      : theme.resources.subtleFillColorSecondary,
                  shape: BoxShape.circle,
                ),
                clipBehavior: Clip.antiAlias,
                child: _avatarUrl != null
                    ? Image.network(
                        _avatarUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Center(
                            child: Text(initial,
                                style: theme.typography.bodyStrong?.copyWith(
                                    color: _activo
                                        ? theme.accentColor
                                        : theme.inactiveColor))),
                      )
                    : Center(
                        child: Text(
                          initial,
                          style: theme.typography.bodyStrong?.copyWith(
                            color: _activo
                                ? theme.accentColor
                                : theme.inactiveColor,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: Spacing.ms),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text(_nombre,
                            style: theme.typography.bodyStrong,
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (_esYo) ...[
                        const SizedBox(width: Spacing.sm),
                        _TuChip(),
                      ],
                    ]),
                    Text(_email,
                        style: theme.typography.caption
                            ?.copyWith(color: theme.inactiveColor),
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              if (!_esYo && !_esPendiente)
                _toggling
                    ? const PilarProgressRing(size: 20)
                    : ToggleSwitch(checked: _activo, onChanged: _toggle),
            ],
          ),
          if (_roles.isNotEmpty) ...[
            const SizedBox(height: Spacing.sm),
            Wrap(
              spacing: Spacing.xs,
              runSpacing: Spacing.xs,
              children: _roles
                  .map((r) => _RolBadge(nombre: r['nombre'] as String? ?? ''))
                  .toList(),
            ),
          ],
          const SizedBox(height: Spacing.sm),
          Row(children: [
            Icon(FluentIcons.clock, size: 11, color: theme.inactiveColor),
            const SizedBox(width: Spacing.xs),
            Text(_formatAcceso(_acceso),
                style: TextStyle(fontSize: 11, color: theme.inactiveColor)),
            const Spacer(),
            if (_esPendiente)
              Button(
                onPressed: _canceling ? null : _cancelInvitacion,
                style: const ButtonStyle(
                    padding: WidgetStatePropertyAll(
                        EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: Spacing.xs))),
                child: _canceling
                    ? const PilarProgressRing(size: 12)
                    : const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(FluentIcons.delete, size: 13),
                        SizedBox(width: Spacing.xs),
                        Text('Cancelar invitación',
                            style: TextStyle(fontSize: 12)),
                      ]),
              )
            else ...[
              Button(
                onPressed: () => widget.onEdit(widget.usuario),
                style: const ButtonStyle(
                    padding: WidgetStatePropertyAll(
                        EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: Spacing.xs))),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(FluentIcons.edit_contact, size: 13),
                  SizedBox(width: Spacing.xs),
                  Text('Editar', style: TextStyle(fontSize: 12)),
                ]),
              ),
              if (!_esYo) ...[
                const SizedBox(width: Spacing.xs),
                Button(
                  onPressed: _deleting ? null : _deleteUser,
                  style: const ButtonStyle(
                      padding: WidgetStatePropertyAll(
                          EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: Spacing.xs))),
                  child: _deleting
                      ? const PilarProgressRing(size: 12)
                      : Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(FluentIcons.delete,
                              size: 13, color: Colors.red.normal),
                          const SizedBox(width: Spacing.xs),
                          const Text('Eliminar',
                              style: TextStyle(fontSize: 12)),
                        ]),
                ),
              ],
            ],
          ]),
        ],
      ),
    );
  }
}

// ===========================================================================
// Dialogs (acciones rápidas — se mantienen)
// ===========================================================================

// ---------------------------------------------------------------------------
// _GestionarRolesDialog
// ---------------------------------------------------------------------------

class _GestionarRolesDialog extends ConsumerStatefulWidget {
  const _GestionarRolesDialog({
    required this.usuario,
    required this.onChanged,
  });

  final Map<String, dynamic> usuario;
  final VoidCallback onChanged;

  @override
  ConsumerState<_GestionarRolesDialog> createState() =>
      _GestionarRolesDialogState();
}

class _GestionarRolesDialogState extends ConsumerState<_GestionarRolesDialog> {
  late Set<String> _selected;
  bool _loading = false;
  String? _error;

  String get _userId => widget.usuario['usuario_id'] as String? ?? '';
  String get _email => widget.usuario['email'] as String? ?? '';

  @override
  void initState() {
    super.initState();
    _selected = _parseRoles(widget.usuario['roles'])
        .map((r) => r['id'] as String)
        .toSet();
  }

  Future<void> _save() async {
    if (!ref.read(connectivityProvider)) {
      setState(() => _error = 'Requiere conexión a internet');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await ref
        .read(usuariosAdminProvider.notifier)
        .setRoles(userId: _userId, rolIds: _selected.toList());
    if (!mounted) return;
    if (result.ok) {
      widget.onChanged();
      Navigator.pop(context);
    } else {
      setState(() {
        _error = _errorMsg(result.error);
        _loading = false;
      });
    }
  }

  String _errorMsg(String? code) => switch (code) {
        'PERMISSION_DENIED' => 'Sin permiso para gestionar usuarios.',
        'CANNOT_CHANGE_OWN_ROLE' => 'No puedes cambiar tu propio rol.',
        'USER_NOT_IN_EMPRESA' => 'El usuario no pertenece a esta empresa.',
        _ => code ?? 'Error desconocido',
      };

  @override
  Widget build(BuildContext context) {
    final rolesAsync = ref.watch(rolesProvider);
    final theme = FluentTheme.of(context);

    return ContentDialog(
      title: Text('Roles — $_email'),
      constraints: const BoxConstraints(maxWidth: 560),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Selecciona los roles que tendrá este usuario. '
            'Puede tener más de uno.',
            style: theme.typography.caption
                ?.copyWith(color: theme.inactiveColor),
          ),
          const SizedBox(height: Spacing.ms),
          rolesAsync.when(
            data: (roles) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: roles
                  .map((r) => GestureDetector(
                        onTap: _loading
                            ? null
                            : () => setState(() {
                                  if (_selected.contains(r.id)) {
                                    _selected.remove(r.id);
                                  } else {
                                    _selected.add(r.id);
                                  }
                                }),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
                          child: Row(
                            children: [
                              Checkbox(
                                checked: _selected.contains(r.id),
                                onChanged: _loading
                                    ? null
                                    : (v) => setState(() {
                                          if (v == true) {
                                            _selected.add(r.id);
                                          } else {
                                            _selected.remove(r.id);
                                          }
                                        }),
                              ),
                              const SizedBox(width: Spacing.sm),
                              Text(r.nombre, style: theme.typography.body),
                            ],
                          ),
                        ),
                      ))
                  .toList(),
            ),
            loading: () => const Center(child: PilarProgressRing()),
            error: (e, _) => Text(
              'Error cargando roles: $e',
              style: TextStyle(
                  color: theme.resources.systemFillColorCritical),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: Spacing.ms),
            InfoBar(
              title: const Text('Error'),
              content: Text(_error!),
              severity: InfoBarSeverity.error,
            ),
          ],
        ],
      ),
      actions: [
        Button(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _loading ? null : _save,
          child: _loading
              ? const PilarProgressRing.small()
              : const Text('Guardar'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _SetPasswordDialog
// ---------------------------------------------------------------------------

class _SetPasswordDialog extends ConsumerStatefulWidget {
  const _SetPasswordDialog({required this.userId, required this.email});
  final String userId;
  final String email;

  @override
  ConsumerState<_SetPasswordDialog> createState() => _SetPasswordDialogState();
}

class _SetPasswordDialogState extends ConsumerState<_SetPasswordDialog> {
  String _password = '';
  String _confirmPassword = '';
  bool _loading = false;
  String? _error;

  Future<void> _save() async {
    if (!ref.read(connectivityProvider)) {
      setState(() => _error = 'Requiere conexión a internet');
      return;
    }
    if (_password.length < 6) {
      setState(() => _error = 'Mínimo 6 caracteres.');
      return;
    }
    if (_password != _confirmPassword) {
      setState(() => _error = 'Las contraseñas no coinciden.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await ref
        .read(usuariosAdminProvider.notifier)
        .setPassword(userId: widget.userId, password: _password);
    if (!mounted) return;
    if (result.ok) {
      Navigator.pop(context);
    } else {
      setState(() {
        _error = _errorMsg(result.error);
        _loading = false;
      });
    }
  }

  String _errorMsg(String? c) => switch (c) {
        'PERMISSION_DENIED' => 'Sin permiso para gestionar usuarios.',
        'USER_NOT_FOUND' => 'El usuario no pertenece a esta empresa.',
        'PASSWORD_TOO_SHORT' => 'Mínimo 6 caracteres.',
        _ => c ?? 'Error desconocido',
      };

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return ContentDialog(
      title: Text('Contraseña — ${widget.email}'),
      constraints: const BoxConstraints(maxWidth: 480),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Nueva contraseña para este usuario. Mínimo 6 caracteres.',
            style:
                theme.typography.caption?.copyWith(color: theme.inactiveColor),
          ),
          const SizedBox(height: Spacing.md),
          InfoLabel(
            label: 'Nueva contraseña',
            child: PasswordBox(
              placeholder: 'Nueva contraseña',
              enabled: !_loading,
              onChanged: (v) => _password = v,
            ),
          ),
          const SizedBox(height: Spacing.ms),
          InfoLabel(
            label: 'Confirmar contraseña',
            child: PasswordBox(
              placeholder: 'Confirmar contraseña',
              enabled: !_loading,
              onChanged: (v) => _confirmPassword = v,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: Spacing.ms),
            InfoBar(
              title: const Text('Error'),
              content: Text(_error!),
              severity: InfoBarSeverity.error,
            ),
          ],
        ],
      ),
      actions: [
        Button(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _loading ? null : _save,
          child: _loading
              ? const PilarProgressRing.small()
              : const Text('Guardar'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _InviteDialog
// ---------------------------------------------------------------------------

class _InviteDialog extends ConsumerStatefulWidget {
  const _InviteDialog({required this.onInvited});
  final VoidCallback onInvited;

  @override
  ConsumerState<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends ConsumerState<_InviteDialog> {
  final _emailController = TextEditingController();
  String? _selectedRolId;
  bool _loading = false;
  String? _errorMessage;
  String? _successMessage;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  bool get _emailValido {
    final e = _emailController.text.trim();
    return e.isNotEmpty && e.contains('@') && e.contains('.');
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    if (!_emailValido || _selectedRolId == null) return;

    if (!ref.read(connectivityProvider)) {
      setState(() {
        _errorMessage = 'Requiere conexión a internet para enviar invitaciones';
        _loading = false;
      });
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    final result = await ref
        .read(usuariosAdminProvider.notifier)
        .invitarUsuario(email: email, rolId: _selectedRolId!);

    if (!mounted) return;

    if (!result.ok) {
      setState(() {
        _errorMessage = result.message;
        _loading = false;
      });
      return;
    }

    if (result.tipo == 'USUARIO_EXISTENTE') {
      widget.onInvited();
      Navigator.pop(context);
      return;
    }

    setState(() {
      _successMessage =
          'Invitación enviada a $email. El usuario recibirá un correo para activar su cuenta.';
      _loading = false;
    });
    widget.onInvited();
  }

  @override
  Widget build(BuildContext context) {
    final rolesAsync = ref.watch(rolesProvider);

    return ContentDialog(
      title: const Text('Invitar usuario'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Si el usuario ya tiene cuenta en PILAR se agregará directamente. '
            'Si no, recibirá un correo de invitación.',
          ),
          const SizedBox(height: Spacing.md),
          InfoLabel(
            label: 'Correo electrónico *',
            child: TextBox(
              controller: _emailController,
              placeholder: 'usuario@empresa.com',
              keyboardType: TextInputType.emailAddress,
              enabled: !_loading,
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: Spacing.ms),
          InfoLabel(
            label: 'Rol inicial *',
            child: rolesAsync.when(
              data: (roles) => ComboBox<String>(
                value: _selectedRolId,
                placeholder: const Text('Seleccionar rol'),
                isExpanded: true,
                items: roles
                    .map((r) => ComboBoxItem<String>(
                          value: r.id,
                          child: Text(r.nombre),
                        ))
                    .toList(),
                onChanged:
                    _loading ? null : (v) => setState(() => _selectedRolId = v),
              ),
              loading: () => const SizedBox(
                  height: 32,
                  child: PilarLoadingCenter()),
              error: (e, _) => Text(
                'Error cargando roles: $e',
                style: TextStyle(
                  color: FluentTheme.of(context)
                      .resources
                      .systemFillColorCritical,
                ),
              ),
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: Spacing.ms),
            InfoBar(
              title: const Text('Error'),
              content: Text(_errorMessage!),
              severity: InfoBarSeverity.error,
            ),
          ],
          if (_successMessage != null) ...[
            const SizedBox(height: Spacing.ms),
            InfoBar(
              title: const Text('Invitación enviada'),
              content: Text(_successMessage!),
              severity: InfoBarSeverity.success,
              isLong: true,
            ),
          ],
        ],
      ),
      actions: [
        Button(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: Text(_successMessage != null ? 'Cerrar' : 'Cancelar'),
        ),
        if (_successMessage == null)
          FilledButton(
            onPressed:
                (_loading || !_emailValido || _selectedRolId == null) ? null : _submit,
            child: _loading
                ? const PilarProgressRing.small()
                : const Text('Enviar invitación'),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers de nivel de archivo
// ---------------------------------------------------------------------------

String _buildTieneDatosMsg(int mensajes, int adjuntos) {
  final parts = <String>[];
  if (mensajes > 0) {
    parts.add('$mensajes mensaje${mensajes == 1 ? '' : 's'} de chat');
  }
  if (adjuntos > 0) {
    parts.add(
        '$adjuntos archivo${adjuntos == 1 ? '' : 's'} subido${adjuntos == 1 ? '' : 's'}');
  }
  if (parts.isEmpty) return ' Tiene datos relacionados en el sistema.';
  return ' Tiene: ${parts.join(' y ')}.';
}
