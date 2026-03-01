import 'dart:math';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/empresa_provider.dart';
import '../../../core/providers/usuario_provider.dart';

// ---------------------------------------------------------------------------
// Providers de roles para cuentas
// ---------------------------------------------------------------------------

/// Roles asignados a una cuenta específica (acceso restringido por rol).
/// Retorna lista de maps con: rol_id, roles.nombre, roles.codigo.
final cuentaRolesProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
        (ref, cuentaId) async {
  final rows = await Supabase.instance.client
      .from('com_cuentas_roles')
      .select('rol_id, roles(nombre, codigo)')
      .eq('cuenta_id', cuentaId) as List;
  return rows.cast<Map<String, dynamic>>();
});

/// Todos los roles del sistema disponibles para asignar a cuentas.
final rolesEmpresaProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  ref.watch(authStateProvider);
  final rows = await Supabase.instance.client
      .from('roles')
      .select('id, nombre, codigo')
      .filter('empresa_id', 'is', null)
      .order('nombre') as List;
  return rows.cast<Map<String, dynamic>>();
});

// ---------------------------------------------------------------------------
// Helpers globales
// ---------------------------------------------------------------------------

/// Genera un secret aleatorio de 32 bytes (64 chars hex).
/// Solo contiene A-Z, a-z, 0-9 — compatible con el requisito de Telegram.
String _generateWebhookSecret() {
  final rng = Random.secure();
  return List.generate(
    32,
    (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

/// Llama a `com-telegram-setup` para registrar el webhook en Telegram.
/// Retorna el mensaje de resultado (vacío si éxito).
Future<String?> _callTelegramSetup(String accountId) async {
  try {
    await Supabase.instance.client.functions.invoke(
      'com-telegram-setup',
      body: {'account_id': accountId},
    );
    return null; // éxito
  } catch (e) {
    return e.toString();
  }
}

// ---------------------------------------------------------------------------
// Modelo
// ---------------------------------------------------------------------------

class CuentaItem {
  final String id;
  final String nombre;
  final String tipo;
  final bool activo;
  final bool esDefecto;
  final Map<String, dynamic> configJson;
  final Map<String, dynamic> metaJson;
  final String? usuarioId;
  final String? usuarioNombre;
  final bool esPersonal;

  const CuentaItem({
    required this.id,
    required this.nombre,
    required this.tipo,
    required this.activo,
    required this.esDefecto,
    required this.configJson,
    this.metaJson = const {},
    this.usuarioId,
    this.usuarioNombre,
    required this.esPersonal,
  });

  /// true si el webhook de Telegram fue registrado exitosamente.
  bool get telegramWebhookOk =>
      tipo == 'telegram' && (metaJson['webhook_ok'] as bool? ?? false);

  factory CuentaItem.fromMap(Map<String, dynamic> m) {
    final uid = m['usuario_id'] as String?;
    return CuentaItem(
      id: m['id'] as String,
      nombre: m['nombre'] as String? ?? '',
      tipo: m['tipo'] as String? ?? '',
      activo: m['activo'] as bool? ?? false,
      esDefecto: m['es_defecto'] as bool? ?? false,
      configJson: (m['config_json'] as Map?)?.cast<String, dynamic>() ?? {},
      metaJson: (m['meta_json'] as Map?)?.cast<String, dynamic>() ?? {},
      usuarioId: uid,
      usuarioNombre: m['usuario_nombre'] as String?,
      esPersonal: m['es_personal'] as bool? ?? (uid != null),
    );
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final comCuentasProvider =
    FutureProvider.autoDispose<List<CuentaItem>>((ref) async {
  ref.watch(authStateProvider);
  try {
    final data = await Supabase.instance.client
        .rpc('com_get_todas_cuentas') as List;
    return data
        .cast<Map<String, dynamic>>()
        .map(CuentaItem.fromMap)
        .toList();
  } catch (_) {
    // Fallback: query directa (no admin o RPC no disponible)
    final session = Supabase.instance.client.auth.currentSession;
    final empresaId = session?.user.appMetadata['empresa_id'] as String?;
    final query = Supabase.instance.client
        .from('com_cuentas')
        .select('id, nombre, tipo, activo, es_defecto, config_json, meta_json, usuario_id');
    final data = (empresaId != null
            ? await query.eq('empresa_id', empresaId).order('nombre')
            : await query.order('nombre')) as List;
    return data
        .cast<Map<String, dynamic>>()
        .map(CuentaItem.fromMap)
        .toList();
  }
});

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _tipoLabels = {
  'whatsapp': 'WhatsApp',
  'email_api': 'Email (API)',
  'email_smtp': 'Email (SMTP)',
  'telegram': 'Telegram',
};

const _tipoIcons = {
  'whatsapp': FluentIcons.chat,
  'email_api': FluentIcons.mail,
  'email_smtp': FluentIcons.mail_options,
  'telegram': FluentIcons.send,
};

const _tipoOrden = ['whatsapp', 'email_api', 'email_smtp', 'telegram'];

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class CuentasComunicacionScreen extends ConsumerStatefulWidget {
  const CuentasComunicacionScreen({super.key});

  @override
  ConsumerState<CuentasComunicacionScreen> createState() =>
      _CuentasComunicacionScreenState();
}

class _CuentasComunicacionScreenState
    extends ConsumerState<CuentasComunicacionScreen> {
  @override
  Widget build(BuildContext context) {
    final puedeCompartida =
        ref.watch(hasPermissionProvider('comunicacion.cuentas.compartida'));
    final cuentasAsync = ref.watch(comCuentasProvider);
    final theme = FluentTheme.of(context);

    return ScaffoldPage(
      header: PageHeader(
        title: const Text('Cuentas de Comunicación'),
        commandBar: CommandBar(
          mainAxisAlignment: MainAxisAlignment.end,
          primaryItems: [
            CommandBarButton(
              icon: const Icon(FluentIcons.add),
              label: const Text('Nueva cuenta'),
              onPressed: () => _showCuentaDialog(context),
            ),
          ],
        ),
      ),
      content: cuentasAsync.when(
        loading: () => const Center(child: ProgressRing()),
        error: (e, _) => Center(
          child: InfoBar(
            title: const Text('Error cargando cuentas'),
            content: Text(e.toString()),
            severity: InfoBarSeverity.error,
          ),
        ),
        data: (cuentas) {
          if (cuentas.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(FluentIcons.plug_connected, size: 48,
                      color: theme.accentColor),
                  const SizedBox(height: 16),
                  Text('Sin cuentas configuradas',
                      style: theme.typography.subtitle),
                  const SizedBox(height: 8),
                  Text(
                    'Agrega una cuenta de WhatsApp, Email o Telegram\npara enviar notificaciones a tus clientes.',
                    style: theme.typography.body,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    child: const Text('Agregar primera cuenta'),
                    onPressed: () => _showCuentaDialog(context),
                  ),
                ],
              ),
            );
          }

          // Separar en empresa vs personales
          String? uid;
          try {
            uid = Supabase.instance.client.auth.currentUser?.id;
          } catch (_) {
            uid = null; // Supabase no inicializado (tests)
          }
          final empresariales = cuentas.where((c) => !c.esPersonal).toList();
          final personales =
              cuentas.where((c) => c.esPersonal).toList();

          // Agrupar empresariales por tipo
          final porTipo = <String, List<CuentaItem>>{};
          for (final c in empresariales) {
            (porTipo[c.tipo] ??= []).add(c);
          }

          // Agrupar personales por tipo
          final porTipoPersonal = <String, List<CuentaItem>>{};
          for (final c in personales) {
            (porTipoPersonal[c.tipo] ??= []).add(c);
          }

          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              // ── Cuentas de la empresa ─────────────────────────────────────
              if (empresariales.isNotEmpty) ...[
                _GroupHeader(
                  icon: FluentIcons.people,
                  label: 'Cuentas de la empresa',
                  color: theme.accentColor,
                ),
                const SizedBox(height: 12),
                for (final tipo in _tipoOrden)
                  if (porTipo.containsKey(tipo)) ...[
                    _SectionHeader(
                      icon: _tipoIcons[tipo]!,
                      label: _tipoLabels[tipo]!,
                      onAdd: () =>
                          _showCuentaDialog(context, tipoInicial: tipo),
                    ),
                    const SizedBox(height: 8),
                    for (final cuenta in porTipo[tipo]!)
                      _CuentaCard(
                        cuenta: cuenta,
                        puedeCompartida: puedeCompartida,
                        onEdit: () =>
                            _showCuentaDialog(context, cuenta: cuenta),
                        onToggleActivo: () => _toggleActivo(cuenta),
                        onSetDefecto: () => _setDefecto(cuenta),
                        onEliminar: () => _confirmarEliminar(context, cuenta),
                        onCambiarOwnership: () =>
                            _cambiarOwnership(cuenta, uid),
                        onGestionarRoles: () =>
                            _showRolesDialog(context, cuenta),
                        onRegistrarWebhook: cuenta.tipo == 'telegram'
                            ? () => _registrarWebhook(cuenta)
                            : null,
                      ),
                    const SizedBox(height: 16),
                  ],
              ],

              // ── Mis cuentas personales ────────────────────────────────────
              _GroupHeader(
                icon: FluentIcons.contact,
                label: 'Mis cuentas personales',
                color: theme.resources.textFillColorPrimary,
              ),
              const SizedBox(height: 12),
              if (personales.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    'No tienes cuentas personales. '
                    'Usa "Nueva cuenta" y selecciona "Personal".',
                    style: theme.typography.body?.copyWith(
                        color: theme.inactiveColor),
                  ),
                )
              else
                for (final tipo in _tipoOrden)
                  if (porTipoPersonal.containsKey(tipo)) ...[
                    _SectionHeader(
                      icon: _tipoIcons[tipo]!,
                      label: _tipoLabels[tipo]!,
                      onAdd: () =>
                          _showCuentaDialog(context, tipoInicial: tipo),
                    ),
                    const SizedBox(height: 8),
                    for (final cuenta in porTipoPersonal[tipo]!)
                      _CuentaCard(
                        cuenta: cuenta,
                        puedeCompartida: puedeCompartida,
                        onEdit: () =>
                            _showCuentaDialog(context, cuenta: cuenta),
                        onToggleActivo: () => _toggleActivo(cuenta),
                        onSetDefecto: () => _setDefecto(cuenta),
                        onEliminar: () => _confirmarEliminar(context, cuenta),
                        onCambiarOwnership: () =>
                            _cambiarOwnership(cuenta, uid),
                        onGestionarRoles: () =>
                            _showRolesDialog(context, cuenta),
                        onRegistrarWebhook: cuenta.tipo == 'telegram'
                            ? () => _registrarWebhook(cuenta)
                            : null,
                      ),
                    const SizedBox(height: 16),
                  ],
              // Botón añadir cuenta personal
              Align(
                alignment: Alignment.centerLeft,
                child: Button(
                  onPressed: () => _showCuentaDialog(context,
                      forzarPersonal: true),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(FluentIcons.add, size: 14),
                      SizedBox(width: 6),
                      Text('Añadir cuenta personal'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Acciones
  // -------------------------------------------------------------------------

  Future<void> _toggleActivo(CuentaItem cuenta) async {
    try {
      await Supabase.instance.client
          .from('com_cuentas')
          .update({'activo': !cuenta.activo})
          .eq('id', cuenta.id);
      ref.invalidate(comCuentasProvider);
    } catch (e) {
      if (mounted) _showError(context, e.toString());
    }
  }

  Future<void> _setDefecto(CuentaItem cuenta) async {
    try {
      await Supabase.instance.client
          .from('com_cuentas')
          .update({'es_defecto': false})
          .eq('tipo', cuenta.tipo)
          .neq('id', cuenta.id);
      await Supabase.instance.client
          .from('com_cuentas')
          .update({'es_defecto': true, 'activo': true})
          .eq('id', cuenta.id);
      ref.invalidate(comCuentasProvider);
    } catch (e) {
      if (mounted) _showError(context, e.toString());
    }
  }

  Future<void> _cambiarOwnership(CuentaItem cuenta, String? uid) async {
    try {
      if (cuenta.esPersonal) {
        // Hacer compartida: pasar null
        await Supabase.instance.client.rpc('com_set_cuenta_usuario', params: {
          'p_cuenta_id': cuenta.id,
          'p_usuario_id': null,
        });
      } else {
        // Hacer personal del usuario actual
        if (uid == null) return;
        await Supabase.instance.client.rpc('com_set_cuenta_usuario', params: {
          'p_cuenta_id': cuenta.id,
          'p_usuario_id': uid,
        });
      }
      ref.invalidate(comCuentasProvider);
    } catch (e) {
      if (mounted) _showError(context, e.toString());
    }
  }

  Future<void> _confirmarEliminar(
      BuildContext context, CuentaItem cuenta) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => ContentDialog(
        title: const Text('Eliminar cuenta'),
        content: Text(
          '¿Eliminar "${cuenta.nombre}"?\n\n'
          'Los mensajes enviados con esta cuenta quedarán en el historial.',
        ),
        actions: [
          Button(
            child: const Text('Cancelar'),
            onPressed: () => Navigator.pop(context, false),
          ),
          FilledButton(
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.all(Colors.red),
            ),
            child: const Text('Eliminar'),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await Supabase.instance.client
            .from('com_cuentas')
            .delete()
            .eq('id', cuenta.id);
        ref.invalidate(comCuentasProvider);
      } catch (e) {
        if (mounted) _showError(this.context, e.toString());
      }
    }
  }

  Future<void> _registrarWebhook(CuentaItem cuenta) async {
    try {
      await Supabase.instance.client.functions.invoke(
        'com-telegram-setup',
        body: {'account_id': cuenta.id},
      );
      ref.invalidate(comCuentasProvider);
      if (!mounted) return;
      // ignore: use_build_context_synchronously
      displayInfoBar(
        context,
        builder: (_, close) => InfoBar(
          title: const Text('Webhook registrado'),
          content: Text('${cuenta.nombre} conectado a Telegram'),
          severity: InfoBarSeverity.success,
          onClose: close,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      // ignore: use_build_context_synchronously
      _showError(context, 'Error al registrar webhook:\n$e');
    }
  }

  void _showError(BuildContext context, String msg) {
    showDialog<void>(
      context: context,
      builder: (_) => ContentDialog(
        title: const Text('Error'),
        content: Text(msg),
        actions: [
          FilledButton(
            child: const Text('OK'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Future<void> _showCuentaDialog(
    BuildContext context, {
    CuentaItem? cuenta,
    String? tipoInicial,
    bool forzarPersonal = false,
  }) async {
    final puedeCompartida =
        ref.read(hasPermissionProvider('comunicacion.cuentas.compartida'));
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _CuentaDialog(
        cuenta: cuenta,
        tipoInicial: tipoInicial,
        forzarPersonal: forzarPersonal || !puedeCompartida,
        puedeCompartida: puedeCompartida,
      ),
    );
    if (saved == true) ref.invalidate(comCuentasProvider);
  }

  Future<void> _showRolesDialog(
      BuildContext context, CuentaItem cuenta) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _CuentaRolesDialog(cuenta: cuenta),
    );
    // Invalidar por si cambió algo relevante
    ref.invalidate(cuentaRolesProvider(cuenta.id));
  }
}

// ---------------------------------------------------------------------------
// Group header (Empresa / Personal)
// ---------------------------------------------------------------------------

class _GroupHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _GroupHeader({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(label, style: theme.typography.subtitle),
          const Expanded(child: Divider(style: DividerThemeData())),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section header (por tipo: WhatsApp / Email / Telegram)
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onAdd;

  const _SectionHeader({
    required this.icon,
    required this.label,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.accentColor),
        const SizedBox(width: 8),
        Text(label, style: theme.typography.bodyStrong),
        const Spacer(),
        IconButton(
          icon: const Icon(FluentIcons.add, size: 14),
          onPressed: onAdd,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Acceso chip
// ---------------------------------------------------------------------------

class _AccesoChip extends StatelessWidget {
  final bool esPersonal;
  final String? usuarioNombre;

  const _AccesoChip({required this.esPersonal, this.usuarioNombre});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    if (!esPersonal) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: theme.accentColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(FluentIcons.people, size: 11, color: theme.accentColor),
            const SizedBox(width: 4),
            Text(
              'Compartida',
              style: TextStyle(fontSize: 11, color: theme.accentColor),
            ),
          ],
        ),
      );
    }

    // Personal
    final label =
        'Personal${usuarioNombre != null ? ' — $usuarioNombre' : ''}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.resources.subtleFillColorSecondary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            FluentIcons.contact,
            size: 11,
            color: theme.resources.textFillColorSecondary,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: theme.resources.textFillColorSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cuenta card
// ---------------------------------------------------------------------------

class _CuentaCard extends StatefulWidget {
  final CuentaItem cuenta;
  final bool puedeCompartida;
  final VoidCallback onEdit;
  final VoidCallback onToggleActivo;
  final VoidCallback onSetDefecto;
  final VoidCallback onEliminar;
  final VoidCallback onCambiarOwnership;
  final VoidCallback onGestionarRoles;
  final VoidCallback? onRegistrarWebhook;

  const _CuentaCard({
    required this.cuenta,
    required this.puedeCompartida,
    required this.onEdit,
    required this.onToggleActivo,
    required this.onSetDefecto,
    required this.onEliminar,
    required this.onCambiarOwnership,
    required this.onGestionarRoles,
    this.onRegistrarWebhook,
  });

  @override
  State<_CuentaCard> createState() => _CuentaCardState();
}

class _CuentaCardState extends State<_CuentaCard> {
  final FlyoutController _flyoutController = FlyoutController();

  @override
  void dispose() {
    _flyoutController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cuenta = widget.cuenta;
    final theme = FluentTheme.of(context);
    final activo = cuenta.activo;
    final defecto = cuenta.esDefecto;
    final tipo = cuenta.tipo;
    final cfg = cuenta.configJson;

    String subtitle = '';
    switch (tipo) {
      case 'whatsapp':
        subtitle = cfg['phone_number'] as String? ?? '';
      case 'email_api':
        final prov = cfg['provider'] as String? ?? '';
        final from = cfg['from_email'] as String? ?? '';
        subtitle = '$prov · $from';
      case 'email_smtp':
        final host = cfg['host'] as String? ?? '';
        final from = cfg['from_email'] as String? ?? '';
        subtitle = '$host · $from';
      case 'telegram':
        final wh = cuenta.telegramWebhookOk ? ' · webhook ✓' : '';
        subtitle = '@${cfg['bot_username'] ?? ''}$wh';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Status indicator
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: activo ? Colors.green : Colors.grey[100],
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(cuenta.nombre,
                          style: theme.typography.bodyStrong),
                      if (defecto) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.accentColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('predeterminado',
                              style: theme.typography.caption?.copyWith(
                                  color: theme.accentColor)),
                        ),
                      ],
                      const SizedBox(width: 8),
                      _AccesoChip(
                        esPersonal: cuenta.esPersonal,
                        usuarioNombre: cuenta.usuarioNombre,
                      ),
                    ],
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subtitle, style: theme.typography.caption),
                  ],
                ],
              ),
            ),
            // Actions
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!defecto)
                  Tooltip(
                    message: 'Establecer como predeterminada',
                    child: IconButton(
                      icon: const Icon(FluentIcons.favorite_star, size: 16),
                      onPressed: widget.onSetDefecto,
                    ),
                  ),
                Tooltip(
                  message: activo ? 'Desactivar' : 'Activar',
                  child: IconButton(
                    icon: Icon(
                      activo
                          ? FluentIcons.toggle_right
                          : FluentIcons.toggle_left,
                      size: 16,
                    ),
                    onPressed: widget.onToggleActivo,
                  ),
                ),
                Tooltip(
                  message: 'Editar',
                  child: IconButton(
                    icon: const Icon(FluentIcons.edit, size: 16),
                    onPressed: widget.onEdit,
                  ),
                ),
                // Menú de más opciones (solo usuarios con permiso compartida)
                if (widget.puedeCompartida)
                  FlyoutTarget(
                    controller: _flyoutController,
                    child: Tooltip(
                      message: 'Más opciones',
                      child: IconButton(
                        icon: const Icon(FluentIcons.more, size: 16),
                        onPressed: () {
                          _flyoutController.showFlyout(
                            builder: (_) => MenuFlyout(
                              items: [
                                // Re-registrar webhook (solo Telegram)
                                if (tipo == 'telegram' &&
                                    widget.onRegistrarWebhook != null) ...[
                                  MenuFlyoutItem(
                                    leading: const Icon(
                                      FluentIcons.plug_connected,
                                      size: 16,
                                    ),
                                    text: const Text('Re-registrar webhook'),
                                    onPressed: widget.onRegistrarWebhook,
                                  ),
                                  const MenuFlyoutSeparator(),
                                ],
                                MenuFlyoutItem(
                                  leading: Icon(
                                    cuenta.esPersonal
                                        ? FluentIcons.people
                                        : FluentIcons.contact,
                                    size: 16,
                                  ),
                                  text: Text(cuenta.esPersonal
                                      ? 'Hacer compartida'
                                      : 'Hacer personal'),
                                  onPressed: widget.onCambiarOwnership,
                                ),
                                // Gestión de roles solo para cuentas compartidas
                                if (!cuenta.esPersonal) ...[
                                  const MenuFlyoutSeparator(),
                                  MenuFlyoutItem(
                                    leading: const Icon(
                                      FluentIcons.permissions,
                                      size: 16,
                                    ),
                                    text: const Text('Acceso por rol'),
                                    onPressed: widget.onGestionarRoles,
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                Tooltip(
                  message: 'Eliminar',
                  child: IconButton(
                    icon: Icon(FluentIcons.delete, size: 16,
                        color: Colors.red),
                    onPressed: widget.onEliminar,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Create / Edit dialog
// ---------------------------------------------------------------------------

class _CuentaDialog extends ConsumerStatefulWidget {
  final CuentaItem? cuenta;
  final String? tipoInicial;
  final bool forzarPersonal;
  final bool puedeCompartida;

  const _CuentaDialog({
    this.cuenta,
    this.tipoInicial,
    this.forzarPersonal = false,
    this.puedeCompartida = false,
  });

  @override
  ConsumerState<_CuentaDialog> createState() => _CuentaDialogState();
}

class _CuentaDialogState extends ConsumerState<_CuentaDialog> {
  final _nombreCtrl = TextEditingController();
  String _tipo = 'whatsapp';
  bool _activo = true;
  bool _esDefecto = false;
  bool _esPersonal = false;
  bool _saving = false;

  // WhatsApp fields
  final _waAppUidCtrl = TextEditingController();
  final _waAccountUidCtrl = TextEditingController();
  final _waPhoneUidCtrl = TextEditingController();
  final _waPhoneNumberCtrl = TextEditingController();
  final _waTokenCtrl = TextEditingController();
  final _waAppSecretCtrl = TextEditingController();
  final _waVerifyTokenCtrl = TextEditingController();

  // Email API fields
  String _emailProvider = 'resend';
  final _apiKeyCtrl = TextEditingController();
  final _fromNameCtrl = TextEditingController();
  final _fromEmailCtrl = TextEditingController();

  // Email SMTP fields
  final _smtpHostCtrl = TextEditingController();
  final _smtpPortCtrl = TextEditingController(text: '587');
  bool _smtpTls = true;
  final _smtpUserCtrl = TextEditingController();
  final _smtpPassCtrl = TextEditingController();
  // IMAP fields (para recibir correos)
  final _imapHostCtrl = TextEditingController();
  final _imapPortCtrl = TextEditingController(text: '993');
  bool _imapSsl = true;

  // Telegram fields
  final _tgTokenCtrl = TextEditingController();
  final _tgUsernameCtrl = TextEditingController();
  final _tgSecretCtrl = TextEditingController();

  bool get _isEditing => widget.cuenta != null;

  @override
  void initState() {
    super.initState();
    if (widget.tipoInicial != null) _tipo = widget.tipoInicial!;
    if (widget.forzarPersonal) _esPersonal = true;
    if (_isEditing) _loadFromCuenta(widget.cuenta!);
  }

  void _loadFromCuenta(CuentaItem c) {
    _nombreCtrl.text = c.nombre;
    _tipo = c.tipo;
    _activo = c.activo;
    _esDefecto = c.esDefecto;
    _esPersonal = c.esPersonal;

    final cfg = c.configJson;
    switch (_tipo) {
      case 'whatsapp':
        _waAppUidCtrl.text = cfg['app_uid'] as String? ?? '';
        _waAccountUidCtrl.text = cfg['account_uid'] as String? ?? '';
        _waPhoneUidCtrl.text = cfg['phone_uid'] as String? ?? '';
        _waPhoneNumberCtrl.text = cfg['phone_number'] as String? ?? '';
        _waTokenCtrl.text = cfg['token'] as String? ?? '';
        _waAppSecretCtrl.text = cfg['app_secret'] as String? ?? '';
        _waVerifyTokenCtrl.text =
            cfg['webhook_verify_token'] as String? ?? '';
      case 'email_api':
        _emailProvider = cfg['provider'] as String? ?? 'resend';
        _apiKeyCtrl.text = cfg['api_key'] as String? ?? '';
        _fromNameCtrl.text = cfg['from_name'] as String? ?? '';
        _fromEmailCtrl.text = cfg['from_email'] as String? ?? '';
      case 'email_smtp':
        _smtpHostCtrl.text = cfg['host'] as String? ?? '';
        _smtpPortCtrl.text = (cfg['port'] ?? 587).toString();
        _smtpTls = cfg['use_tls'] as bool? ?? true;
        _fromNameCtrl.text = cfg['from_name'] as String? ?? '';
        _fromEmailCtrl.text = cfg['from_email'] as String? ?? '';
        _smtpUserCtrl.text = cfg['username'] as String? ?? '';
        _smtpPassCtrl.text = cfg['password'] as String? ?? '';
        _imapHostCtrl.text = cfg['imap_host'] as String? ?? '';
        _imapPortCtrl.text = (cfg['imap_port'] ?? 993).toString();
        _imapSsl = cfg['imap_ssl'] as bool? ?? true;
      case 'telegram':
        _tgTokenCtrl.text = cfg['bot_token'] as String? ?? '';
        _tgUsernameCtrl.text = cfg['bot_username'] as String? ?? '';
        _tgSecretCtrl.text = cfg['webhook_secret'] as String? ?? '';
    }
  }

  Map<String, dynamic> _buildConfigJson() {
    switch (_tipo) {
      case 'whatsapp':
        return {
          'app_uid': _waAppUidCtrl.text.trim(),
          'account_uid': _waAccountUidCtrl.text.trim(),
          'phone_uid': _waPhoneUidCtrl.text.trim(),
          'phone_number': _waPhoneNumberCtrl.text.trim(),
          'token': _waTokenCtrl.text.trim(),
          'app_secret': _waAppSecretCtrl.text.trim(),
          'webhook_verify_token': _waVerifyTokenCtrl.text.trim(),
        };
      case 'email_api':
        return {
          'provider': _emailProvider,
          'api_key': _apiKeyCtrl.text.trim(),
          'from_name': _fromNameCtrl.text.trim(),
          'from_email': _fromEmailCtrl.text.trim(),
        };
      case 'email_smtp':
        return {
          'host': _smtpHostCtrl.text.trim(),
          'port': int.tryParse(_smtpPortCtrl.text) ?? 587,
          'use_tls': _smtpTls,
          'from_name': _fromNameCtrl.text.trim(),
          'from_email': _fromEmailCtrl.text.trim(),
          'username': _smtpUserCtrl.text.trim(),
          'password': _smtpPassCtrl.text.trim(),
          'imap_host': _imapHostCtrl.text.trim(),
          'imap_port': int.tryParse(_imapPortCtrl.text) ?? 993,
          'imap_ssl': _imapSsl,
        };
      case 'telegram':
        return {
          'bot_token': _tgTokenCtrl.text.trim(),
          'bot_username': _tgUsernameCtrl.text.trim(),
          'webhook_secret': _tgSecretCtrl.text.trim(),
        };
      default:
        return {};
    }
  }

  Future<void> _save() async {
    final nombre = _nombreCtrl.text.trim();
    if (nombre.isEmpty) return;

    // Auto-generar webhook secret para Telegram si está vacío.
    if (_tipo == 'telegram' && _tgSecretCtrl.text.trim().isEmpty) {
      setState(() => _tgSecretCtrl.text = _generateWebhookSecret());
    }

    setState(() => _saving = true);
    try {
      final uid = _esPersonal
          ? Supabase.instance.client.auth.currentUser?.id
          : null;

      final empresaId =
          Supabase.instance.client.auth.currentSession?.user.appMetadata['empresa_id'] as String?;

      final payload = <String, dynamic>{
        if (empresaId != null) 'empresa_id': empresaId,
        'nombre': nombre,
        'tipo': _tipo,
        'activo': _activo,
        'es_defecto': _esDefecto,
        'config_json': _buildConfigJson(),
        'usuario_id': uid,
      };

      String accountId;
      if (_isEditing) {
        accountId = widget.cuenta!.id;
        await Supabase.instance.client
            .from('com_cuentas')
            .update(payload)
            .eq('id', accountId);
      } else {
        final result = await Supabase.instance.client
            .from('com_cuentas')
            .insert(payload)
            .select('id')
            .single();
        accountId = result['id'] as String;
      }

      // Registrar webhook automáticamente para cuentas Telegram.
      if (_tipo == 'telegram') {
        final error = await _callTelegramSetup(accountId);
        if (error != null && mounted) {
          // El webhook falló pero el registro en DB fue exitoso.
          // Mostramos advertencia y dejamos al usuario decidir.
          final continuar = await showDialog<bool>(
            context: context,
            builder: (_) => ContentDialog(
              title: const Text('Cuenta guardada — webhook pendiente'),
              content: Text(
                'La cuenta fue guardada correctamente, pero el registro '
                'del webhook en Telegram falló:\n\n$error\n\n'
                'Puedes re-intentarlo desde el menú "··· → Re-registrar webhook".',
              ),
              actions: [
                FilledButton(
                  child: const Text('Entendido'),
                  onPressed: () => Navigator.pop(context, true),
                ),
              ],
            ),
          );
          if (continuar == true && mounted) Navigator.pop(context, true);
          return;
        }
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        showDialog<void>(
          context: context,
          builder: (_) => ContentDialog(
            title: const Text('Error'),
            content: Text(e.toString()),
            actions: [
              FilledButton(
                child: const Text('OK'),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    for (final c in [
      _nombreCtrl, _waAppUidCtrl, _waAccountUidCtrl, _waPhoneUidCtrl,
      _waPhoneNumberCtrl, _waTokenCtrl, _waAppSecretCtrl, _waVerifyTokenCtrl,
      _apiKeyCtrl, _fromNameCtrl, _fromEmailCtrl,
      _smtpHostCtrl, _smtpPortCtrl, _smtpUserCtrl, _smtpPassCtrl,
      _imapHostCtrl, _imapPortCtrl,
      _tgTokenCtrl, _tgUsernameCtrl, _tgSecretCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 520),
      title: Text(_isEditing ? 'Editar cuenta' : 'Nueva cuenta'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Nombre
            InfoLabel(
              label: 'Nombre de la cuenta',
              child: TextBox(
                controller: _nombreCtrl,
                placeholder: 'Ej: WhatsApp Empresa Principal',
              ),
            ),
            const SizedBox(height: 16),

            // Tipo (solo al crear)
            if (!_isEditing) ...[
              InfoLabel(
                label: 'Canal',
                child: ComboBox<String>(
                  value: _tipo,
                  items: _tipoOrden
                      .map((t) => ComboBoxItem(
                            value: t,
                            child: Row(children: [
                              Icon(_tipoIcons[t], size: 16),
                              const SizedBox(width: 8),
                              Text(_tipoLabels[t]!),
                            ]),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _tipo = v!),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Campos por tipo
            _buildTipoFields(),
            const SizedBox(height: 16),

            // Opciones
            Row(
              children: [
                Checkbox(
                  content: const Text('Activa'),
                  checked: _activo,
                  onChanged: (v) => setState(() => _activo = v ?? true),
                ),
                const SizedBox(width: 24),
                Checkbox(
                  content: const Text('Predeterminada'),
                  checked: _esDefecto,
                  onChanged: (v) => setState(() => _esDefecto = v ?? false),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── Acceso ───────────────────────────────────────────────────────
            if (widget.puedeCompartida) ...[
              Text('Acceso a esta cuenta',
                  style: theme.typography.bodyStrong),
              const SizedBox(height: 10),
              RadioGroup<bool>(
                groupValue: _esPersonal,
                onChanged: (v) =>
                    setState(() => _esPersonal = v ?? _esPersonal),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RadioButton<bool>(
                      value: false,
                      content: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Icon(FluentIcons.people, size: 14,
                                color: theme.accentColor),
                            const SizedBox(width: 6),
                            const Text('Compartida'),
                          ]),
                          Text(
                            'Todos los usuarios de la empresa pueden usar esta cuenta',
                            style: theme.typography.caption
                                ?.copyWith(color: theme.inactiveColor),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    RadioButton<bool>(
                      value: true,
                      content: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Icon(FluentIcons.contact, size: 14,
                                color:
                                    theme.resources.textFillColorSecondary),
                            const SizedBox(width: 6),
                            const Text('Personal'),
                          ]),
                          Text(
                            'Solo tú puedes ver y usar esta cuenta',
                            style: theme.typography.caption
                                ?.copyWith(color: theme.inactiveColor),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        Button(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: ProgressRing(strokeWidth: 2),
                )
              : Text(_isEditing ? 'Guardar' : 'Crear'),
        ),
      ],
    );
  }

  Widget _buildTipoFields() {
    switch (_tipo) {
      case 'whatsapp':
        return _buildWhatsAppFields();
      case 'email_api':
        return _buildEmailApiFields();
      case 'email_smtp':
        return _buildEmailSmtpFields();
      case 'telegram':
        return _buildTelegramFields();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildWhatsAppFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field('App UID (Facebook App ID)', _waAppUidCtrl),
        _field('Account UID (WABA ID)', _waAccountUidCtrl),
        _field('Phone Number ID', _waPhoneUidCtrl),
        _field('Número de teléfono', _waPhoneNumberCtrl,
            placeholder: '+593XXXXXXXXX'),
        _field('Access Token', _waTokenCtrl, obscure: true),
        _field('App Secret', _waAppSecretCtrl, obscure: true),
        _field('Webhook Verify Token', _waVerifyTokenCtrl,
            placeholder: 'Token secreto para verificar webhook Meta'),
      ],
    );
  }

  Widget _buildEmailApiFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InfoLabel(
          label: 'Proveedor',
          child: ComboBox<String>(
            value: _emailProvider,
            items: const [
              ComboBoxItem(value: 'resend', child: Text('Resend')),
              ComboBoxItem(
                  value: 'elasticmail', child: Text('ElasticMail')),
              ComboBoxItem(value: 'sendgrid', child: Text('SendGrid')),
            ],
            onChanged: (v) => setState(() => _emailProvider = v!),
          ),
        ),
        const SizedBox(height: 12),
        _field('API Key', _apiKeyCtrl, obscure: true),
        _field('Nombre del remitente', _fromNameCtrl,
            placeholder: 'Tu Empresa'),
        _field('Email remitente', _fromEmailCtrl,
            placeholder: 'noreply@tudominio.com'),
      ],
    );
  }

  // Presets de proveedores populares
  static const _smtpPresets = {
    'Gmail': {
      'smtp_host': 'smtp.gmail.com', 'smtp_port': '587', 'smtp_tls': true,
      'imap_host': 'imap.gmail.com', 'imap_port': '993', 'imap_ssl': true,
    },
    'Yahoo': {
      'smtp_host': 'smtp.mail.yahoo.com', 'smtp_port': '587', 'smtp_tls': true,
      'imap_host': 'imap.mail.yahoo.com', 'imap_port': '993', 'imap_ssl': true,
    },
    'Outlook': {
      'smtp_host': 'smtp.office365.com', 'smtp_port': '587', 'smtp_tls': true,
      'imap_host': 'outlook.office365.com', 'imap_port': '993', 'imap_ssl': true,
    },
  };

  void _applySmtpPreset(String provider) {
    final p = _smtpPresets[provider]!;
    setState(() {
      _smtpHostCtrl.text = p['smtp_host'] as String;
      _smtpPortCtrl.text = p['smtp_port'] as String;
      _smtpTls        = p['smtp_tls'] as bool;
      _imapHostCtrl.text = p['imap_host'] as String;
      _imapPortCtrl.text = p['imap_port'] as String;
      _imapSsl        = p['imap_ssl'] as bool;
    });
  }

  Widget _buildEmailSmtpFields() {
    final theme = FluentTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Presets ──────────────────────────────────────────────────────────
        Text('Configuración rápida', style: theme.typography.caption
            ?.copyWith(color: theme.inactiveColor)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: _smtpPresets.keys.map((name) => Button(
            child: Text(name),
            onPressed: () => _applySmtpPreset(name),
          )).toList(),
        ),
        const SizedBox(height: 16),

        // ── SMTP ─────────────────────────────────────────────────────────────
        Text('Servidor de envío (SMTP)', style: theme.typography.bodyStrong),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: _field('Host SMTP', _smtpHostCtrl,
                  placeholder: 'smtp.gmail.com'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _field('Puerto', _smtpPortCtrl, placeholder: '587'),
            ),
          ],
        ),
        Checkbox(
          content: const Text('Usar TLS / STARTTLS'),
          checked: _smtpTls,
          onChanged: (v) => setState(() => _smtpTls = v ?? true),
        ),
        const SizedBox(height: 12),
        _field('Nombre del remitente', _fromNameCtrl,
            placeholder: 'Tu Empresa'),
        _field('Email remitente', _fromEmailCtrl,
            placeholder: 'usuario@gmail.com'),
        _field('Usuario SMTP', _smtpUserCtrl,
            placeholder: 'usuario@gmail.com'),
        _field('Contraseña / App Password', _smtpPassCtrl, obscure: true,
            placeholder: 'Contraseña o App Password de 16 caracteres'),
        const SizedBox(height: 16),

        // ── IMAP ─────────────────────────────────────────────────────────────
        Text('Servidor de recepción (IMAP)', style: theme.typography.bodyStrong),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: _field('Host IMAP', _imapHostCtrl,
                  placeholder: 'imap.gmail.com'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _field('Puerto', _imapPortCtrl, placeholder: '993'),
            ),
          ],
        ),
        Checkbox(
          content: const Text('SSL/TLS'),
          checked: _imapSsl,
          onChanged: (v) => setState(() => _imapSsl = v ?? true),
        ),
        const SizedBox(height: 4),
        const InfoBar(
          title: Text('App Password requerida'),
          content: Text(
            'Gmail y Yahoo requieren una contraseña de aplicación (App Password), '
            'no la contraseña normal de la cuenta. '
            'Genérala en: Google Account → Seguridad → Contraseñas de aplicaciones.',
          ),
          severity: InfoBarSeverity.info,
        ),
      ],
    );
  }

  Widget _buildTelegramFields() {
    final theme = FluentTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Info: registro automático
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: theme.accentColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: theme.accentColor.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(FluentIcons.info, size: 14, color: theme.accentColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Al guardar, el webhook se registrará automáticamente '
                  'en Telegram. El secret se genera solo si lo dejas vacío.',
                  style: theme.typography.caption,
                ),
              ),
            ],
          ),
        ),
        _field('Bot Token', _tgTokenCtrl,
            placeholder: '123456:ABC-DEF...', obscure: true),
        _field('Username del bot', _tgUsernameCtrl,
            placeholder: 'mi_empresa_bot'),
        // Webhook Secret con botón "Generar"
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: InfoLabel(
            label: 'Webhook Secret',
            child: Row(
              children: [
                Expanded(
                  child: TextBox(
                    controller: _tgSecretCtrl,
                    placeholder: 'Se genera automáticamente al guardar',
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Generar secret aleatorio',
                  child: Button(
                    child: const Text('Generar'),
                    onPressed: () => setState(
                      () => _tgSecretCtrl.text = _generateWebhookSecret(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _field(
    String label,
    TextEditingController ctrl, {
    String? placeholder,
    bool obscure = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InfoLabel(
        label: label,
        child: TextBox(
          controller: ctrl,
          placeholder: placeholder,
          obscureText: obscure,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Diálogo de gestión de acceso por rol para una cuenta compartida
// ---------------------------------------------------------------------------

/// Muestra los roles que tienen acceso a una cuenta compartida y permite
/// agregar o quitar roles.
///
/// Comportamiento:
/// - Si la cuenta no tiene roles asignados → todos los usuarios la ven.
/// - Al asignar uno o más roles → solo usuarios con esos roles la verán.
class _CuentaRolesDialog extends ConsumerStatefulWidget {
  final CuentaItem cuenta;

  const _CuentaRolesDialog({required this.cuenta});

  @override
  ConsumerState<_CuentaRolesDialog> createState() => _CuentaRolesDialogState();
}

class _CuentaRolesDialogState extends ConsumerState<_CuentaRolesDialog> {
  bool _saving = false;

  Future<void> _toggleRol(
    Map<String, dynamic> rol,
    bool actualmente,
    String empresaId,
  ) async {
    setState(() => _saving = true);
    try {
      if (actualmente) {
        // Quitar rol
        await Supabase.instance.client
            .from('com_cuentas_roles')
            .delete()
            .eq('cuenta_id', widget.cuenta.id)
            .eq('rol_id', rol['id'] as String);
      } else {
        // Agregar rol
        await Supabase.instance.client.from('com_cuentas_roles').insert({
          'cuenta_id': widget.cuenta.id,
          'rol_id': rol['id'] as String,
          'empresa_id': empresaId,
        });
      }
      ref.invalidate(cuentaRolesProvider(widget.cuenta.id));
    } catch (e) {
      if (mounted) {
        await displayInfoBar(
          context,
          builder: (ctx, close) => InfoBar(
            title: const Text('Error al actualizar rol'),
            content: Text(e.toString()),
            severity: InfoBarSeverity.error,
            action: IconButton(
                icon: const Icon(FluentIcons.clear), onPressed: close),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final rolesAsync = ref.watch(rolesEmpresaProvider);
    final cuentaRolesAsync =
        ref.watch(cuentaRolesProvider(widget.cuenta.id));
    final empresaId = ref.watch(empresaActivaIdProvider) ?? '';

    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 480),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Acceso por rol — ${widget.cuenta.nombre}'),
          const SizedBox(height: 4),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const InfoBar(
            title: Text('Restricción de visibilidad'),
            content: Text(
              'Si no asignas ningún rol, la cuenta es visible para todos los usuarios. '
              'Al asignar roles, solo los usuarios con esos roles podrán ver y usar esta cuenta.',
            ),
            severity: InfoBarSeverity.info,
          ),
          const SizedBox(height: 16),
          Text('Roles con acceso:', style: theme.typography.bodyStrong),
          const SizedBox(height: 8),
          rolesAsync.when(
            loading: () => const Center(child: ProgressRing()),
            error: (e, _) => InfoBar(
              title: const Text('Error cargando roles'),
              content: Text(e.toString()),
              severity: InfoBarSeverity.error,
            ),
            data: (todos) => cuentaRolesAsync.when(
              loading: () => const Center(child: ProgressRing()),
              error: (e, _) => InfoBar(
                title: const Text('Error cargando roles de la cuenta'),
                content: Text(e.toString()),
                severity: InfoBarSeverity.error,
              ),
              data: (asignados) {
                // IDs de roles actualmente asignados
                final asignadosIds = asignados
                    .map((r) => r['rol_id'] as String)
                    .toSet();

                if (todos.isEmpty) {
                  return Text(
                    'No hay roles de sistema disponibles.',
                    style:
                        theme.typography.body?.copyWith(color: theme.inactiveColor),
                  );
                }

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: todos.map((rol) {
                    final rolId = rol['id'] as String;
                    final tieneAcceso = asignadosIds.contains(rolId);
                    final nombre = rol['nombre'] as String? ??
                        rol['codigo'] as String? ?? '';
                    final codigo = rol['codigo'] as String? ?? '';

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Checkbox(
                        checked: tieneAcceso,
                        onChanged: _saving
                            ? null
                            : (_) => _toggleRol(
                                  rol,
                                  tieneAcceso,
                                  empresaId,
                                ),
                        content: Row(
                          children: [
                            Expanded(child: Text(nombre)),
                            Text(
                              codigo,
                              style: theme.typography.caption?.copyWith(
                                  color: theme.inactiveColor),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}
