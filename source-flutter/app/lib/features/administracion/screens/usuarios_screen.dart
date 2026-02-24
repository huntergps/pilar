import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluent_ui_reactive/fluent_ui_reactive.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/admin_providers.dart';

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

/// Gestión de usuarios de la empresa activa.
///
/// Muestra un listado de tarjetas con todos los usuarios, obtenidos vía
/// [adminUsuariosProvider]. Cada tarjeta incluye acciones para cambiar el
/// rol y activar/desactivar al usuario.
class UsuariosScreen extends ConsumerWidget {
  const UsuariosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              onPressed: () => _showInviteDialog(context, ref),
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
              Icon(FluentIcons.people, size: 48,
                  color: FluentTheme.of(context).inactiveColor),
              const SizedBox(height: 16),
              const Text('No hay usuarios en esta empresa'),
            ],
          ),
        ),
        builder: (context, usuarios) => ListView.separated(
          padding: const EdgeInsets.all(24),
          itemCount: usuarios.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) =>
              _UsuarioCard(usuario: usuarios[i]),
        ),
      ),
    );
  }

  void _showInviteDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (_) => _InviteDialog(
        onInvited: () => ref.invalidate(adminUsuariosProvider),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _UsuarioCard
// ---------------------------------------------------------------------------

class _UsuarioCard extends ConsumerStatefulWidget {
  final Map<String, dynamic> usuario;
  const _UsuarioCard({required this.usuario});

  @override
  ConsumerState<_UsuarioCard> createState() => _UsuarioCardState();
}

class _UsuarioCardState extends ConsumerState<_UsuarioCard> {
  bool _toggling = false;

  String get _usuarioId => widget.usuario['usuario_id'] as String? ?? '';
  String get _email => widget.usuario['email'] as String? ?? '';
  String get _nombre => widget.usuario['nombre'] as String? ?? _email;
  String get _rolId => widget.usuario['rol_id'] as String? ?? '';
  String get _rolNombre => widget.usuario['rol_nombre'] as String? ?? '';
  bool get _activo => widget.usuario['activo'] as bool? ?? true;
  String? get _ultimoAcceso => widget.usuario['ultimo_acceso'] as String?;

  // Is this the authenticated user themselves?
  bool get _esYo =>
      _usuarioId == Supabase.instance.client.auth.currentUser?.id;

  Future<void> _toggleActivo(bool value) async {
    if (_toggling) return;
    setState(() => _toggling = true);
    try {
      final result = await Supabase.instance.client.rpc(
        'admin_toggle_usuario_activo',
        params: {'p_usuario_id': _usuarioId, 'p_activo': value},
      );
      if (result is Map && result['ok'] == true) {
        ref.invalidate(adminUsuariosProvider);
      } else {
        final err = result is Map ? result['error'] : null;
        if (mounted) _showError(_toggleErrorMsg(err?.toString()));
      }
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  void _showChangeRolDialog() {
    showDialog<void>(
      context: context,
      builder: (_) => _CambiarRolDialog(
        usuarioId: _usuarioId,
        rolActualId: _rolId,
        email: _email,
        onChanged: () => ref.invalidate(adminUsuariosProvider),
      ),
    );
  }

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

  String _toggleErrorMsg(String? code) => switch (code) {
        'PERMISSION_DENIED' => 'Sin permiso para gestionar usuarios.',
        'CANNOT_CHANGE_OWN_STATUS' => 'No puedes cambiar tu propio estado.',
        _ => code ?? 'Error desconocido',
      };

  String _formatAcceso(String? iso) {
    if (iso == null) return 'Nunca';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return DateFormat('dd/MM/yyyy HH:mm').format(dt);
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final initial = _nombre.isNotEmpty ? _nombre[0].toUpperCase() : '?';

    return Card(
      child: Row(
        children: [
          // ---- Avatar ----
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _activo
                  ? theme.accentColor.withValues(alpha: 0.15)
                  : theme.resources.subtleFillColorSecondary,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: theme.typography.bodyStrong?.copyWith(
                color: _activo ? theme.accentColor : theme.inactiveColor,
              ),
            ),
          ),
          const SizedBox(width: 16),

          // ---- Info ----
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _nombre,
                        style: theme.typography.bodyStrong,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_esYo) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: theme.accentColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Tú',
                          style: TextStyle(
                            fontSize: 10,
                            color: theme.accentColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _email,
                  style: theme.typography.caption
                      ?.copyWith(color: theme.inactiveColor),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: theme.accentColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _rolNombre,
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.accentColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(FluentIcons.clock,
                        size: 11, color: theme.inactiveColor),
                    const SizedBox(width: 3),
                    Text(
                      _formatAcceso(_ultimoAcceso),
                      style: TextStyle(
                          fontSize: 11, color: theme.inactiveColor),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // ---- Actions ----
          if (!_esYo) ...[
            Tooltip(
              message: 'Cambiar rol',
              child: IconButton(
                icon: const Icon(FluentIcons.people_add, size: 16),
                onPressed: _showChangeRolDialog,
              ),
            ),
            const SizedBox(width: 4),
            _toggling
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: ProgressRing(strokeWidth: 2),
                  )
                : Tooltip(
                    message: _activo ? 'Desactivar usuario' : 'Activar usuario',
                    child: ToggleSwitch(
                      checked: _activo,
                      onChanged: _toggleActivo,
                    ),
                  ),
          ] else
            const SizedBox(width: 40),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _CambiarRolDialog
// ---------------------------------------------------------------------------

class _CambiarRolDialog extends ConsumerStatefulWidget {
  final String usuarioId;
  final String rolActualId;
  final String email;
  final VoidCallback onChanged;

  const _CambiarRolDialog({
    required this.usuarioId,
    required this.rolActualId,
    required this.email,
    required this.onChanged,
  });

  @override
  ConsumerState<_CambiarRolDialog> createState() => _CambiarRolDialogState();
}

class _CambiarRolDialogState extends ConsumerState<_CambiarRolDialog> {
  late String _selectedRolId;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedRolId = widget.rolActualId;
  }

  Future<void> _save() async {
    if (_selectedRolId == widget.rolActualId) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await Supabase.instance.client.rpc(
        'admin_cambiar_rol_usuario',
        params: {
          'p_usuario_id': widget.usuarioId,
          'p_rol_id': _selectedRolId,
        },
      );
      if (result is Map && result['ok'] == true) {
        widget.onChanged();
        if (mounted) Navigator.pop(context);
      } else {
        final err = result is Map ? result['error'] : null;
        setState(() => _error = _errorMsg(err?.toString()));
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _errorMsg(String? code) => switch (code) {
        'PERMISSION_DENIED' => 'Sin permiso para gestionar usuarios.',
        'CANNOT_CHANGE_OWN_ROLE' => 'No puedes cambiar tu propio rol.',
        'ROLE_NOT_FOUND' => 'Rol no encontrado.',
        _ => code ?? 'Error desconocido',
      };

  @override
  Widget build(BuildContext context) {
    final rolesAsync = ref.watch(rolesProvider);

    return ContentDialog(
      title: Text('Cambiar rol — ${widget.email}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InfoLabel(
            label: 'Nuevo rol',
            child: rolesAsync.when(
              data: (roles) => ComboBox<String>(
                value: _selectedRolId.isNotEmpty ? _selectedRolId : null,
                placeholder: const Text('Seleccionar rol'),
                isExpanded: true,
                items: roles
                    .map((r) => ComboBoxItem<String>(
                          value: r.id,
                          child: Text(r.nombre),
                        ))
                    .toList(),
                onChanged:
                    _loading ? null : (v) => setState(() => _selectedRolId = v ?? _selectedRolId),
              ),
              loading: () => const SizedBox(
                height: 32,
                child: Center(child: ProgressRing(strokeWidth: 2)),
              ),
              error: (e, _) => Text('Error cargando roles',
                  style: TextStyle(
                      color: FluentTheme.of(context)
                          .resources
                          .systemFillColorCritical)),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
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
              ? const SizedBox(
                  width: 16, height: 16, child: ProgressRing(strokeWidth: 2))
              : const Text('Guardar'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _InviteDialog (unchanged from original)
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

    setState(() {
      _loading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final response = await Supabase.instance.client.functions.invoke(
        'invite-user',
        body: {'email': email, 'rol_id': _selectedRolId},
      );

      final data = response.data as Map<String, dynamic>?;

      if (response.status != 200 || data?['ok'] != true) {
        throw Exception(
            data?['message'] ?? 'Error al enviar invitación (${response.status})');
      }

      final tipo = data!['tipo'] as String?;

      if (tipo == 'USUARIO_EXISTENTE') {
        widget.onInvited();
        if (mounted) Navigator.pop(context);
        return;
      }

      setState(() {
        _successMessage =
            'Se envió una invitación a $email. El usuario recibirá un correo para activar su cuenta.';
        _loading = false;
      });
      widget.onInvited();
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
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
          const SizedBox(height: 16),
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
          const SizedBox(height: 12),
          InfoLabel(
            label: 'Rol *',
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
                  child: Center(child: ProgressRing(strokeWidth: 2))),
              error: (e, _) => const Text('Error cargando roles'),
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            InfoBar(
              title: const Text('Error'),
              content: Text(_errorMessage!),
              severity: InfoBarSeverity.error,
            ),
          ],
          if (_successMessage != null) ...[
            const SizedBox(height: 12),
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
            onPressed: (_loading || !_emailValido || _selectedRolId == null)
                ? null
                : _submit,
            child: _loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: ProgressRing(strokeWidth: 2))
                : const Text('Enviar invitación'),
          ),
      ],
    );
  }
}
