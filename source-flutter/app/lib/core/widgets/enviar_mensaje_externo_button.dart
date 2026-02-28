// EnviarMensajeExternoButton — widget embeddable en cualquier pantalla de
// detalle de registro para enviar un mensaje externo (WhatsApp/Telegram/Email)
// vinculado automáticamente al registro mediante RPC `com_send_desde_entidad`.
//
// Uso básico:
//   EnviarMensajeExternoButton(
//     entidadTipo: 'facturas',
//     entidadId: facturaId,
//     contactoTelefono: '+593987654321',
//     contactoNombre: 'Juan Pérez',
//   )
//
// Uso compacto (solo icono):
//   EnviarMensajeExternoButton(
//     entidadTipo: 'contactos',
//     entidadId: contactoId,
//     compact: true,
//   )

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------------------
// Widget principal (botón)
// ---------------------------------------------------------------------------

/// Botón con dialog para enviar un mensaje externo (WhatsApp/Telegram/Email)
/// desde el contexto de un registro de negocio.
/// Al enviar, crea/vincula la conversación con entidad_tipo+entidad_id.
class EnviarMensajeExternoButton extends ConsumerStatefulWidget {
  final String entidadTipo;
  final String entidadId;

  /// Número en formato E.164 para WhatsApp (ej: '+593987654321').
  final String? contactoTelefono;

  /// Dirección de email del contacto.
  final String? contactoEmail;

  /// Chat ID de Telegram del contacto.
  final String? contactoTelegramId;

  /// Nombre legible del contacto (para pre-fill del campo nombre).
  final String? contactoNombre;

  /// UUID del registro en tabla `contactos` para vincular.
  final String? contactoId;

  /// true = solo ícono; false = ícono + texto "Enviar mensaje".
  final bool compact;

  const EnviarMensajeExternoButton({
    required this.entidadTipo,
    required this.entidadId,
    this.contactoTelefono,
    this.contactoEmail,
    this.contactoTelegramId,
    this.contactoNombre,
    this.contactoId,
    this.compact = false,
    super.key,
  });

  @override
  ConsumerState<EnviarMensajeExternoButton> createState() =>
      _EnviarMensajeExternoButtonState();
}

class _EnviarMensajeExternoButtonState
    extends ConsumerState<EnviarMensajeExternoButton> {
  void _mostrarDialog() {
    showDialog<void>(
      context: context,
      builder: (_) => _EnviarMensajeExternoDialog(config: widget),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.compact) {
      return Tooltip(
        message: 'Enviar mensaje externo',
        child: IconButton(
          icon: const Icon(FluentIcons.send, size: 16),
          onPressed: _mostrarDialog,
        ),
      );
    }

    return Button(
      onPressed: _mostrarDialog,
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(FluentIcons.send, size: 14),
          SizedBox(width: 8),
          Text('Enviar mensaje'),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dialog interno de envío
// ---------------------------------------------------------------------------

class _EnviarMensajeExternoDialog extends ConsumerStatefulWidget {
  final EnviarMensajeExternoButton config;

  const _EnviarMensajeExternoDialog({required this.config});

  @override
  ConsumerState<_EnviarMensajeExternoDialog> createState() =>
      _EnviarMensajeExternoDialogState();
}

class _EnviarMensajeExternoDialogState
    extends ConsumerState<_EnviarMensajeExternoDialog> {
  String _canal = 'whatsapp';
  String? _cuentaId;
  bool _enviando = false;
  bool _cargandoCuentas = false;
  String? _error;
  List<Map<String, dynamic>> _cuentas = [];

  late final TextEditingController _destinatarioCtrl;
  late final TextEditingController _nombreCtrl;
  late final TextEditingController _cuerpoCtrl;

  @override
  void initState() {
    super.initState();
    _destinatarioCtrl = TextEditingController(
      text: widget.config.contactoTelefono ?? '',
    );
    _nombreCtrl = TextEditingController(
      text: widget.config.contactoNombre ?? '',
    );
    _cuerpoCtrl = TextEditingController();
    _cargarCuentas();
  }

  @override
  void dispose() {
    _destinatarioCtrl.dispose();
    _nombreCtrl.dispose();
    _cuerpoCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Carga de cuentas de comunicación
  // ---------------------------------------------------------------------------

  Future<void> _cargarCuentas() async {
    if (!mounted) return;
    setState(() => _cargandoCuentas = true);
    try {
      // El tipo en DB puede ser 'whatsapp', 'telegram', 'email_smtp', 'email_api'
      final tipoFiltro = switch (_canal) {
        'email' => null, // email puede ser smtp o api: cargamos todos
        _ => _canal,
      };

      final query = Supabase.instance.client
          .from('com_cuentas')
          .select('id, nombre, tipo')
          .eq('activo', true);

      final rows = tipoFiltro != null
          ? await query.eq('tipo', tipoFiltro)
          : await query.inFilter('tipo', ['email_smtp', 'email_api']);

      if (!mounted) return;
      setState(() {
        _cuentas = List<Map<String, dynamic>>.from(rows as List);
        _cuentaId =
            _cuentas.isNotEmpty ? _cuentas.first['id'] as String : null;
        _cargandoCuentas = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cuentas = [];
        _cuentaId = null;
        _cargandoCuentas = false;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Cambio de canal
  // ---------------------------------------------------------------------------

  void _onCanalChanged(String canal) {
    if (canal == _canal) return;
    setState(() {
      _canal = canal;
      _cuentaId = null;
      _cuentas = [];
      _error = null;
    });

    // Pre-fill del destinatario según el canal seleccionado
    final tel = widget.config.contactoTelefono ?? '';
    final email = widget.config.contactoEmail ?? '';
    final tg = widget.config.contactoTelegramId ?? '';

    _destinatarioCtrl.text = switch (canal) {
      'whatsapp' => tel,
      'telegram' => tg,
      _ => email, // email / email_smtp / email_api
    };

    _cargarCuentas();
  }

  // ---------------------------------------------------------------------------
  // Enviar mensaje
  // ---------------------------------------------------------------------------

  Future<void> _enviar() async {
    final cuentaId = _cuentaId;
    final destinatario = _destinatarioCtrl.text.trim();
    final cuerpo = _cuerpoCtrl.text.trim();

    if (cuentaId == null) {
      setState(() => _error = 'Selecciona una cuenta de envío');
      return;
    }
    if (destinatario.isEmpty) {
      setState(() => _error = 'Ingresa el destinatario');
      return;
    }
    if (cuerpo.isEmpty) {
      setState(() => _error = 'El mensaje no puede estar vacío');
      return;
    }

    setState(() {
      _enviando = true;
      _error = null;
    });

    try {
      // Normalizar canal para la RPC:
      // UI usa 'whatsapp' | 'telegram' | 'email'; RPC espera valor de la columna tipo
      final canalRpc = switch (_canal) {
        'email' => 'email_smtp',
        _ => _canal,
      };

      await Supabase.instance.client.rpc(
        'com_send_desde_entidad',
        params: {
          'p_entidad_tipo': widget.config.entidadTipo,
          'p_entidad_id': widget.config.entidadId,
          'p_canal': canalRpc,
          'p_cuenta_id': cuentaId,
          'p_destinatario_ref': destinatario,
          'p_cuerpo': cuerpo,
          if (_nombreCtrl.text.trim().isNotEmpty)
            'p_destinatario_nombre': _nombreCtrl.text.trim(),
          if (widget.config.contactoId != null)
            'p_contacto_id': widget.config.contactoId,
        },
      );

      if (mounted) {
        Navigator.of(context).pop();
        displayInfoBar(
          context,
          builder: (ctx, close) => InfoBar(
            title: const Text('Mensaje enviado'),
            severity: InfoBarSeverity.success,
            action: IconButton(
              icon: const Icon(FluentIcons.clear),
              onPressed: close,
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _enviando = false;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return ContentDialog(
      title: const Text('Enviar mensaje externo'),
      constraints: const BoxConstraints(maxWidth: 500),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Error
          if (_error != null) ...[
            InfoBar(
              title: Text(_error!),
              severity: InfoBarSeverity.error,
            ),
            const SizedBox(height: 10),
          ],

          // Selector de canal
          Text('Canal', style: theme.typography.bodyStrong),
          const SizedBox(height: 6),
          _CanalSelector(
            canal: _canal,
            onChanged: _onCanalChanged,
          ),
          const SizedBox(height: 14),

          // Cuenta de envío
          Text('Cuenta de envío', style: theme.typography.bodyStrong),
          const SizedBox(height: 4),
          _buildCuentaSelector(theme),
          const SizedBox(height: 12),

          // Destinatario
          Text('Destinatario', style: theme.typography.bodyStrong),
          const SizedBox(height: 4),
          TextBox(
            controller: _destinatarioCtrl,
            placeholder: switch (_canal) {
              'whatsapp' => '+593987654321',
              'telegram' => 'Chat ID de Telegram',
              _ => 'correo@ejemplo.com',
            },
          ),
          const SizedBox(height: 12),

          // Nombre (opcional)
          Text(
            'Nombre (opcional)',
            style: theme.typography.bodyStrong,
          ),
          const SizedBox(height: 4),
          TextBox(
            controller: _nombreCtrl,
            placeholder: 'Nombre del destinatario',
          ),
          const SizedBox(height: 12),

          // Cuerpo del mensaje
          Text('Mensaje', style: theme.typography.bodyStrong),
          const SizedBox(height: 4),
          TextBox(
            controller: _cuerpoCtrl,
            placeholder: 'Escribe el mensaje...',
            maxLines: 5,
            minLines: 3,
            expands: false,
          ),
          const SizedBox(height: 10),

          // InfoBar informativo
          const InfoBar(
            title: Text('El mensaje quedará vinculado a este registro'),
            content: Text(
              'Aparecerá automáticamente en el chatter.',
            ),
            severity: InfoBarSeverity.info,
          ),
        ],
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
                  width: 14,
                  height: 14,
                  child: ProgressRing(strokeWidth: 2),
                )
              : const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Enviar'),
                    SizedBox(width: 6),
                    Icon(FluentIcons.send, size: 12),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildCuentaSelector(FluentThemeData theme) {
    if (_cargandoCuentas) {
      return const SizedBox(
        height: 20,
        width: 20,
        child: ProgressRing(strokeWidth: 2),
      );
    }

    if (_cuentas.isEmpty) {
      return Text(
        'No hay cuentas configuradas para este canal',
        style: theme.typography.caption?.copyWith(
          color: theme.resources.textFillColorSecondary,
        ),
      );
    }

    return ComboBox<String>(
      value: _cuentaId,
      isExpanded: true,
      items: _cuentas
          .map(
            (c) => ComboBoxItem<String>(
              value: c['id'] as String,
              child: Text(c['nombre'] as String? ?? c['id'] as String),
            ),
          )
          .toList(),
      onChanged: (v) => setState(() => _cuentaId = v),
    );
  }
}

// ---------------------------------------------------------------------------
// Selector de canal (toggle buttons)
// ---------------------------------------------------------------------------

class _CanalSelector extends StatelessWidget {
  final String canal;
  final void Function(String) onChanged;

  const _CanalSelector({required this.canal, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _CanalButton(
          label: 'WhatsApp',
          icon: FluentIcons.chat_bot,
          color: const Color(0xFF25D366),
          valor: 'whatsapp',
          seleccionado: canal == 'whatsapp',
          onTap: () => onChanged('whatsapp'),
        ),
        const SizedBox(width: 8),
        _CanalButton(
          label: 'Telegram',
          icon: FluentIcons.send,
          color: const Color(0xFF0088CC),
          valor: 'telegram',
          seleccionado: canal == 'telegram',
          onTap: () => onChanged('telegram'),
        ),
        const SizedBox(width: 8),
        _CanalButton(
          label: 'Email',
          icon: FluentIcons.mail,
          color: const Color(0xFF0078D4),
          valor: 'email',
          seleccionado: canal == 'email',
          onTap: () => onChanged('email'),
        ),
      ],
    );
  }
}

class _CanalButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final String valor;
  final bool seleccionado;
  final VoidCallback onTap;

  const _CanalButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.valor,
    required this.seleccionado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: seleccionado
              ? color.withValues(alpha: 0.12)
              : theme.resources.cardBackgroundFillColorDefault,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: seleccionado
                ? color.withValues(alpha: 0.7)
                : theme.resources.cardStrokeColorDefault,
            width: seleccionado ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: seleccionado
                  ? color
                  : theme.resources.textFillColorSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.typography.caption?.copyWith(
                color: seleccionado
                    ? color
                    : theme.resources.textFillColorSecondary,
                fontWeight:
                    seleccionado ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
