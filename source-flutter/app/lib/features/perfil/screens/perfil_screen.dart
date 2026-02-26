import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/perfil_provider.dart';

// Zonas horarias comunes (América Latina + globales)
const _zonasHorarias = [
  'America/Guayaquil',
  'America/Bogota',
  'America/Lima',
  'America/Santiago',
  'America/Buenos_Aires',
  'America/Caracas',
  'America/La_Paz',
  'America/Asuncion',
  'America/Montevideo',
  'America/Sao_Paulo',
  'America/Mexico_City',
  'America/New_York',
  'America/Chicago',
  'America/Denver',
  'America/Los_Angeles',
  'Europe/Madrid',
  'UTC',
];

class PerfilDialog extends ConsumerStatefulWidget {
  const PerfilDialog({super.key});

  @override
  ConsumerState<PerfilDialog> createState() => _PerfilDialogState();
}

class _PerfilDialogState extends ConsumerState<PerfilDialog> {
  final _nombreCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _emailLoginCtrl = TextEditingController();

  bool _initialized = false;
  bool _saving = false;
  bool _uploadingAvatar = false;
  String? _errorMsg;
  String? _zonaHoraria;
  String? _originalEmailLogin;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _telefonoCtrl.dispose();
    _emailLoginCtrl.dispose();
    super.dispose();
  }

  void _initFields(PerfilUsuario perfil) {
    if (_initialized) return;
    _initialized = true;
    _nombreCtrl.text = perfil.nombreDisplay ?? '';
    _telefonoCtrl.text = perfil.telefono ?? '';
    _zonaHoraria = perfil.zonaHoraria;
    _emailLoginCtrl.text = perfil.emailLogin;
    _originalEmailLogin = perfil.emailLogin;
  }

  String _errorLabel(String? code) => switch (code) {
        'EMAIL_EXISTS' => 'Este email ya está en uso por otro usuario.',
        'INVALID_EMAIL' => 'El email ingresado no es válido.',
        'PERMISSION_DENIED' => 'Sin permiso para realizar esta acción.',
        _ => code ?? 'Error desconocido',
      };

  Future<void> _pickAndUploadAvatar(PerfilUsuario perfil) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null || bytes.isEmpty) return;

    setState(() {
      _uploadingAvatar = true;
      _errorMsg = null;
    });

    try {
      final path = '${perfil.usuarioId}/${perfil.empresaId}/avatar.jpg';
      await Supabase.instance.client.storage.from('avatares').uploadBinary(
            path,
            Uint8List.fromList(bytes),
            fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
          );
      final url = Supabase.instance.client.storage
          .from('avatares')
          .getPublicUrl(path);
      final urlBust = '$url?t=${DateTime.now().millisecondsSinceEpoch}';
      final error = await ref
          .read(perfilUsuarioProvider.notifier)
          .saveChanges(avatarUrl: urlBust);
      if (mounted) {
        setState(() {
          _uploadingAvatar = false;
          if (error != null) _errorMsg = error;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _uploadingAvatar = false;
          _errorMsg = 'Error subiendo la imagen: $e';
        });
      }
    }
  }

  Future<void> _save(PerfilUsuario perfil) async {
    setState(() {
      _saving = true;
      _errorMsg = null;
    });

    // 1. Guardar campos de perfil
    final error = await ref.read(perfilUsuarioProvider.notifier).saveChanges(
          nombreDisplay: _nombreCtrl.text.trim().isEmpty
              ? null
              : _nombreCtrl.text.trim(),
          telefono: _telefonoCtrl.text.trim().isEmpty
              ? null
              : _telefonoCtrl.text.trim(),
          zonaHoraria: _zonaHoraria,
        );

    if (error != null) {
      if (mounted) {
        setState(() {
          _saving = false;
          _errorMsg = error;
        });
      }
      return;
    }

    // 2. Cambiar email de acceso si fue modificado
    final newEmail = _emailLoginCtrl.text.trim().toLowerCase();
    final currentEmail = (_originalEmailLogin ?? '').toLowerCase();
    if (newEmail.isNotEmpty && newEmail != currentEmail) {
      try {
        final result = await Supabase.instance.client.rpc(
          'change_email_usuario',
          params: {
            'p_usuario_id': perfil.usuarioId,
            'p_new_email': newEmail,
          },
        );
        final map = Map<String, dynamic>.from(result as Map);
        if (map['ok'] != true) {
          if (mounted) {
            setState(() {
              _saving = false;
              _errorMsg = _errorLabel(map['error']?.toString());
            });
          }
          return;
        }
        _originalEmailLogin = newEmail;
      } catch (e) {
        if (mounted) {
          setState(() {
            _saving = false;
            _errorMsg = e.toString();
          });
        }
        return;
      }
    }

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth >= 600;
    final perfilAsync = ref.watch(perfilUsuarioProvider);

    return ContentDialog(
      constraints: BoxConstraints(
        maxWidth: isWide ? 680 : 440,
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      title: Tooltip(
        message:
            'Datos visibles solo en esta empresa. Cada empresa tiene un perfil independiente.',
        child: const Text('Mi perfil'),
      ),
      content: perfilAsync.when(
        loading: () => const SizedBox(
          height: 120,
          child: Center(child: ProgressRing()),
        ),
        error: (e, _) => Text(
          'Error cargando perfil: $e',
          style: TextStyle(color: theme.resources.systemFillColorCritical),
        ),
        data: (perfil) {
          if (perfil == null) {
            return const Text('No se encontró el perfil.');
          }
          _initFields(perfil);
          return isWide
              ? _WideContent(
                  perfil: perfil,
                  nombreCtrl: _nombreCtrl,
                  telefonoCtrl: _telefonoCtrl,
                  emailLoginCtrl: _emailLoginCtrl,
                  zonaHoraria: _zonaHoraria,
                  saving: _saving,
                  uploadingAvatar: _uploadingAvatar,
                  errorMsg: _errorMsg,
                  onUpload: () => _pickAndUploadAvatar(perfil),
                  onZonaChanged: (v) => setState(() => _zonaHoraria = v),
                  onDismissError: () => setState(() => _errorMsg = null),
                  theme: theme,
                )
              : _NarrowContent(
                  perfil: perfil,
                  nombreCtrl: _nombreCtrl,
                  telefonoCtrl: _telefonoCtrl,
                  emailLoginCtrl: _emailLoginCtrl,
                  zonaHoraria: _zonaHoraria,
                  saving: _saving,
                  uploadingAvatar: _uploadingAvatar,
                  errorMsg: _errorMsg,
                  onUpload: () => _pickAndUploadAvatar(perfil),
                  onZonaChanged: (v) => setState(() => _zonaHoraria = v),
                  onDismissError: () => setState(() => _errorMsg = null),
                  theme: theme,
                );
        },
      ),
      actions: [
        Button(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving || perfilAsync.valueOrNull == null
              ? null
              : () => _save(perfilAsync.value!),
          child: _saving
              ? const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                        width: 14,
                        height: 14,
                        child: ProgressRing(strokeWidth: 2)),
                    SizedBox(width: 8),
                    Text('Guardando…'),
                  ],
                )
              : const Text('Guardar cambios'),
        ),
      ],
    );
  }
}

// ===========================================================================
// Layout ancho (≥ 600 px) — avatar izquierda, formulario derecha
// ===========================================================================

class _WideContent extends StatelessWidget {
  const _WideContent({
    required this.perfil,
    required this.nombreCtrl,
    required this.telefonoCtrl,
    required this.emailLoginCtrl,
    required this.zonaHoraria,
    required this.saving,
    required this.uploadingAvatar,
    required this.errorMsg,
    required this.onUpload,
    required this.onZonaChanged,
    required this.onDismissError,
    required this.theme,
  });

  final PerfilUsuario perfil;
  final TextEditingController nombreCtrl;
  final TextEditingController telefonoCtrl;
  final TextEditingController emailLoginCtrl;
  final String? zonaHoraria;
  final bool saving;
  final bool uploadingAvatar;
  final String? errorMsg;
  final VoidCallback onUpload;
  final ValueChanged<String?> onZonaChanged;
  final VoidCallback onDismissError;
  final FluentThemeData theme;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Columna avatar ──
            SizedBox(
              width: 160,
              child: Column(
                children: [
                  _AvatarCircle(
                    avatarUrl: perfil.avatarUrl,
                    initial: perfil.initial,
                    size: 120,
                    uploading: uploadingAvatar,
                    onTap: onUpload,
                    theme: theme,
                  ),
                  const SizedBox(height: 10),
                  uploadingAvatar
                      ? Text(
                          'Subiendo…',
                          style: theme.typography.caption
                              ?.copyWith(color: theme.inactiveColor),
                          textAlign: TextAlign.center,
                        )
                      : GestureDetector(
                          onTap: onUpload,
                          child: Text(
                            'Cambiar foto',
                            style: theme.typography.caption
                                ?.copyWith(color: theme.accentColor),
                            textAlign: TextAlign.center,
                          ),
                        ),
                  const SizedBox(height: 12),
                  Text(
                    perfil.displayName,
                    style: theme.typography.bodyStrong,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 24),

            // ── Columna formulario ──
            Expanded(
              child: _FormFields(
                perfil: perfil,
                nombreCtrl: nombreCtrl,
                telefonoCtrl: telefonoCtrl,
                emailLoginCtrl: emailLoginCtrl,
                zonaHoraria: zonaHoraria,
                saving: saving,
                errorMsg: errorMsg,
                onZonaChanged: onZonaChanged,
                onDismissError: onDismissError,
                theme: theme,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Layout estrecho (< 600 px) — avatar arriba, formulario abajo
// ===========================================================================

class _NarrowContent extends StatelessWidget {
  const _NarrowContent({
    required this.perfil,
    required this.nombreCtrl,
    required this.telefonoCtrl,
    required this.emailLoginCtrl,
    required this.zonaHoraria,
    required this.saving,
    required this.uploadingAvatar,
    required this.errorMsg,
    required this.onUpload,
    required this.onZonaChanged,
    required this.onDismissError,
    required this.theme,
  });

  final PerfilUsuario perfil;
  final TextEditingController nombreCtrl;
  final TextEditingController telefonoCtrl;
  final TextEditingController emailLoginCtrl;
  final String? zonaHoraria;
  final bool saving;
  final bool uploadingAvatar;
  final String? errorMsg;
  final VoidCallback onUpload;
  final ValueChanged<String?> onZonaChanged;
  final VoidCallback onDismissError;
  final FluentThemeData theme;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: _AvatarCircle(
              avatarUrl: perfil.avatarUrl,
              initial: perfil.initial,
              size: 80,
              uploading: uploadingAvatar,
              onTap: onUpload,
              theme: theme,
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: uploadingAvatar
                ? Text(
                    'Subiendo…',
                    style: theme.typography.caption
                        ?.copyWith(color: theme.inactiveColor),
                  )
                : GestureDetector(
                    onTap: onUpload,
                    child: Text(
                      'Cambiar foto',
                      style: theme.typography.caption
                          ?.copyWith(color: theme.accentColor),
                    ),
                  ),
          ),
          const SizedBox(height: 20),
          _FormFields(
            perfil: perfil,
            nombreCtrl: nombreCtrl,
            telefonoCtrl: telefonoCtrl,
            emailLoginCtrl: emailLoginCtrl,
            zonaHoraria: zonaHoraria,
            saving: saving,
            errorMsg: errorMsg,
            onZonaChanged: onZonaChanged,
            onDismissError: onDismissError,
            theme: theme,
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Campos del formulario (compartidos por ambos layouts)
// ===========================================================================

class _FormFields extends StatelessWidget {
  const _FormFields({
    required this.perfil,
    required this.nombreCtrl,
    required this.telefonoCtrl,
    required this.emailLoginCtrl,
    required this.zonaHoraria,
    required this.saving,
    required this.errorMsg,
    required this.onZonaChanged,
    required this.onDismissError,
    required this.theme,
  });

  final PerfilUsuario perfil;
  final TextEditingController nombreCtrl;
  final TextEditingController telefonoCtrl;
  final TextEditingController emailLoginCtrl;
  final String? zonaHoraria;
  final bool saving;
  final String? errorMsg;
  final ValueChanged<String?> onZonaChanged;
  final VoidCallback onDismissError;
  final FluentThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        InfoLabel(
          label: 'Nombre',
          child: TextBox(
            controller: nombreCtrl,
            placeholder: perfil.nombreGlobal ?? 'Tu nombre',
            enabled: !saving,
          ),
        ),
        const SizedBox(height: 14),
        InfoLabel(
          label: 'Teléfono',
          child: TextBox(
            controller: telefonoCtrl,
            placeholder: '+593 99 000 0000',
            enabled: !saving,
            keyboardType: TextInputType.phone,
          ),
        ),
        const SizedBox(height: 14),
        InfoLabel(
          label: 'Email de acceso',
          child: Tooltip(
            message: 'Email para iniciar sesión. El cambio aplica de inmediato.',
            child: TextBox(
              controller: emailLoginCtrl,
              placeholder: 'correo@empresa.com',
              enabled: !saving,
              keyboardType: TextInputType.emailAddress,
            ),
          ),
        ),
        const SizedBox(height: 14),
        InfoLabel(
          label: 'Zona horaria',
          child: ComboBox<String>(
            value: zonaHoraria,
            isExpanded: true,
            items: _zonasHorarias
                .map((z) => ComboBoxItem<String>(value: z, child: Text(z)))
                .toList(),
            onChanged: saving ? null : onZonaChanged,
          ),
        ),
        if (errorMsg != null) ...[
          const SizedBox(height: 14),
          InfoBar(
            title: const Text('Error'),
            content: Text(errorMsg!),
            severity: InfoBarSeverity.error,
            onClose: onDismissError,
          ),
        ],
      ],
    );
  }
}

// ===========================================================================
// Avatar reutilizable
// ===========================================================================

class _AvatarCircle extends StatelessWidget {
  const _AvatarCircle({
    required this.avatarUrl,
    required this.initial,
    required this.size,
    required this.uploading,
    required this.onTap,
    required this.theme,
  });

  final String? avatarUrl;
  final String initial;
  final double size;
  final bool uploading;
  final VoidCallback onTap;
  final FluentThemeData theme;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: uploading ? null : onTap,
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
            child: uploading
                ? Center(child: ProgressRing(strokeWidth: size * 0.035))
                : avatarUrl != null
                    ? Image.network(
                        avatarUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            _Initial(initial: initial, size: size, theme: theme),
                      )
                    : _Initial(initial: initial, size: size, theme: theme),
          ),
          Positioned(
            right: 0,
            bottom: 0,
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
  }
}

class _Initial extends StatelessWidget {
  const _Initial(
      {required this.initial, required this.size, required this.theme});
  final String initial;
  final double size;
  final FluentThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        initial,
        style: TextStyle(
          fontSize: size * 0.38,
          fontWeight: FontWeight.w600,
          color: theme.accentColor,
        ),
      ),
    );
  }
}
