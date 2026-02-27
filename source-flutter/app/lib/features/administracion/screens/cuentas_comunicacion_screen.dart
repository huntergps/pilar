import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/auth_provider.dart';

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final comCuentasProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  ref.watch(authStateProvider);
  final data = await Supabase.instance.client
      .from('com_cuentas')
      .select()
      .order('tipo')
      .order('nombre');
  return (data as List).cast<Map<String, dynamic>>();
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

          // Agrupar por tipo
          final porTipo = <String, List<Map<String, dynamic>>>{};
          for (final c in cuentas) {
            final tipo = c['tipo'] as String;
            (porTipo[tipo] ??= []).add(c);
          }

          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              for (final tipo in _tipoOrden)
                if (porTipo.containsKey(tipo)) ...[
                  _SectionHeader(
                    icon: _tipoIcons[tipo]!,
                    label: _tipoLabels[tipo]!,
                    onAdd: () => _showCuentaDialog(context, tipoInicial: tipo),
                  ),
                  const SizedBox(height: 8),
                  for (final cuenta in porTipo[tipo]!)
                    _CuentaCard(
                      cuenta: cuenta,
                      onEdit: () =>
                          _showCuentaDialog(context, cuenta: cuenta),
                      onToggleActivo: () => _toggleActivo(cuenta),
                      onSetDefecto: () => _setDefecto(cuenta),
                      onEliminar: () => _confirmarEliminar(context, cuenta),
                    ),
                  const SizedBox(height: 24),
                ],
            ],
          );
        },
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Acciones
  // -------------------------------------------------------------------------

  Future<void> _toggleActivo(Map<String, dynamic> cuenta) async {
    try {
      await Supabase.instance.client
          .from('com_cuentas')
          .update({'activo': !(cuenta['activo'] as bool)})
          .eq('id', cuenta['id'] as String);
      ref.invalidate(comCuentasProvider);
    } catch (e) {
      if (mounted) _showError(context, e.toString());
    }
  }

  Future<void> _setDefecto(Map<String, dynamic> cuenta) async {
    try {
      // Quitar defecto de otras cuentas del mismo tipo
      await Supabase.instance.client
          .from('com_cuentas')
          .update({'es_defecto': false})
          .eq('tipo', cuenta['tipo'] as String)
          .neq('id', cuenta['id'] as String);
      // Activar defecto en esta cuenta
      await Supabase.instance.client
          .from('com_cuentas')
          .update({'es_defecto': true, 'activo': true})
          .eq('id', cuenta['id'] as String);
      ref.invalidate(comCuentasProvider);
    } catch (e) {
      if (mounted) _showError(context, e.toString());
    }
  }

  Future<void> _confirmarEliminar(
      BuildContext context, Map<String, dynamic> cuenta) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => ContentDialog(
        title: const Text('Eliminar cuenta'),
        content: Text(
          '¿Eliminar "${cuenta['nombre']}"?\n\n'
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
            .eq('id', cuenta['id'] as String);
        ref.invalidate(comCuentasProvider);
      } catch (e) {
        if (mounted) _showError(context, e.toString());
      }
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
    Map<String, dynamic>? cuenta,
    String? tipoInicial,
  }) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _CuentaDialog(
        cuenta: cuenta,
        tipoInicial: tipoInicial,
      ),
    );
    if (saved == true) ref.invalidate(comCuentasProvider);
  }
}

// ---------------------------------------------------------------------------
// Section header
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
// Cuenta card
// ---------------------------------------------------------------------------

class _CuentaCard extends StatelessWidget {
  final Map<String, dynamic> cuenta;
  final VoidCallback onEdit;
  final VoidCallback onToggleActivo;
  final VoidCallback onSetDefecto;
  final VoidCallback onEliminar;

  const _CuentaCard({
    required this.cuenta,
    required this.onEdit,
    required this.onToggleActivo,
    required this.onSetDefecto,
    required this.onEliminar,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final activo = cuenta['activo'] as bool? ?? false;
    final defecto = cuenta['es_defecto'] as bool? ?? false;
    final tipo = cuenta['tipo'] as String;
    final cfg = (cuenta['config_json'] as Map?)?.cast<String, dynamic>() ?? {};

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
        subtitle = '@${cfg['bot_username'] ?? ''}';
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
                      Text(cuenta['nombre'] as String? ?? '',
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
                      onPressed: onSetDefecto,
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
                    onPressed: onToggleActivo,
                  ),
                ),
                Tooltip(
                  message: 'Editar',
                  child: IconButton(
                    icon: const Icon(FluentIcons.edit, size: 16),
                    onPressed: onEdit,
                  ),
                ),
                Tooltip(
                  message: 'Eliminar',
                  child: IconButton(
                    icon: Icon(FluentIcons.delete, size: 16,
                        color: Colors.red),
                    onPressed: onEliminar,
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
  final Map<String, dynamic>? cuenta;
  final String? tipoInicial;

  const _CuentaDialog({this.cuenta, this.tipoInicial});

  @override
  ConsumerState<_CuentaDialog> createState() => _CuentaDialogState();
}

class _CuentaDialogState extends ConsumerState<_CuentaDialog> {
  final _nombreCtrl = TextEditingController();
  String _tipo = 'whatsapp';
  bool _activo = true;
  bool _esDefecto = false;
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

  // Telegram fields
  final _tgTokenCtrl = TextEditingController();
  final _tgUsernameCtrl = TextEditingController();
  final _tgSecretCtrl = TextEditingController();

  bool get _isEditing => widget.cuenta != null;

  @override
  void initState() {
    super.initState();
    if (widget.tipoInicial != null) _tipo = widget.tipoInicial!;
    if (_isEditing) _loadFromCuenta(widget.cuenta!);
  }

  void _loadFromCuenta(Map<String, dynamic> c) {
    _nombreCtrl.text = c['nombre'] as String? ?? '';
    _tipo = c['tipo'] as String? ?? 'whatsapp';
    _activo = c['activo'] as bool? ?? true;
    _esDefecto = c['es_defecto'] as bool? ?? false;

    final cfg = (c['config_json'] as Map?)?.cast<String, dynamic>() ?? {};
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

    setState(() => _saving = true);
    try {
      final payload = {
        'nombre': nombre,
        'tipo': _tipo,
        'activo': _activo,
        'es_defecto': _esDefecto,
        'config_json': _buildConfigJson(),
      };

      if (_isEditing) {
        await Supabase.instance.client
            .from('com_cuentas')
            .update(payload)
            .eq('id', widget.cuenta!['id'] as String);
      } else {
        await Supabase.instance.client.from('com_cuentas').insert(payload);
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
      _tgTokenCtrl, _tgUsernameCtrl, _tgSecretCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          ],
        ),
      ),
      actions: [
        Button(
          child: const Text('Cancelar'),
          onPressed: _saving ? null : () => Navigator.pop(context, false),
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

  Widget _buildEmailSmtpFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              flex: 3,
              child: _field('Host SMTP', _smtpHostCtrl,
                  placeholder: 'smtp.example.com'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child:
                  _field('Puerto', _smtpPortCtrl, placeholder: '587'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Checkbox(
          content: const Text('Usar TLS'),
          checked: _smtpTls,
          onChanged: (v) => setState(() => _smtpTls = v ?? true),
        ),
        const SizedBox(height: 8),
        _field('Nombre del remitente', _fromNameCtrl),
        _field('Email remitente', _fromEmailCtrl),
        _field('Usuario SMTP', _smtpUserCtrl),
        _field('Contraseña SMTP', _smtpPassCtrl, obscure: true),
      ],
    );
  }

  Widget _buildTelegramFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field('Bot Token', _tgTokenCtrl,
            placeholder: '123456:ABC-DEF...', obscure: true),
        _field('Username del bot', _tgUsernameCtrl,
            placeholder: 'mi_empresa_bot'),
        _field('Webhook Secret', _tgSecretCtrl,
            placeholder: 'Token secreto para verificar webhooks'),
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
