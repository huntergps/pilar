import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/mfa_provider.dart';
import '../../../core/providers/perfil_provider.dart';
import '../../../core/config/pilar_constants.dart';
import '../../../core/theme/pilar_breakpoints.dart';
import '../../../core/utils/timezones.dart';
import '../../../core/theme/pilar_spacing.dart';
import '../../../core/widgets/loading_spinner.dart';
import '../providers/perfil_write_provider.dart';

/// Diálogo de perfil — solo lectura.
///
/// Muestra los datos del perfil del usuario en la empresa activa.
/// Para editar, navegar a la pantalla completa via [onVerPerfilCompleto].
class PerfilDialog extends ConsumerWidget {
  /// Callback: navega a la pantalla completa de perfil para editar.
  final VoidCallback? onVerPerfilCompleto;

  const PerfilDialog({super.key, this.onVerPerfilCompleto});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = FluentTheme.of(context);
    final perfilAsync = ref.watch(perfilUsuarioProvider);

    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 360),
      title: const Tooltip(
        message:
            'Datos visibles solo en esta empresa. Para editar, usa "Editar perfil".',
        child: Text('Mi perfil'),
      ),
      content: perfilAsync.when(
        loading: () => const SizedBox(
          height: 100,
          child: PilarLoadingCenter(),
        ),
        error: (e, _) => Text(
          'Error cargando perfil: $e',
          style: TextStyle(color: theme.resources.systemFillColorCritical),
        ),
        data: (perfil) {
          if (perfil == null) return const Text('No se encontró el perfil.');
          return _ReadOnlyPerfilContent(perfil: perfil, theme: theme);
        },
      ),
      actions: [
        if (onVerPerfilCompleto != null)
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              onVerPerfilCompleto!();
            },
            child: const Text('Editar perfil'),
          ),
        Button(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Contenido de solo lectura (PerfilDialog)
// ---------------------------------------------------------------------------

class _ReadOnlyPerfilContent extends StatelessWidget {
  final PerfilUsuario perfil;
  final FluentThemeData theme;
  const _ReadOnlyPerfilContent({required this.perfil, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: theme.accentColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            clipBehavior: Clip.antiAlias,
            child: perfil.avatarUrl != null
                ? Image.network(
                    perfil.avatarUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        _Initial(initial: perfil.initial, size: 80, theme: theme),
                  )
                : _Initial(initial: perfil.initial, size: 80, theme: theme),
          ),
        ),
        const SizedBox(height: Spacing.ms),
        Center(
          child: Text(
            perfil.displayName,
            style: theme.typography.bodyStrong,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: Spacing.md),
        const Divider(),
        const SizedBox(height: Spacing.ms),
        _InfoFila(label: 'Email', value: perfil.emailLogin, theme: theme),
        if (perfil.telefono?.isNotEmpty == true) ...[
          const SizedBox(height: Spacing.sm),
          _InfoFila(label: 'Teléfono', value: perfil.telefono!, theme: theme),
        ],
        const SizedBox(height: Spacing.sm),
        _InfoFila(
          label: 'Zona horaria',
          value: perfil.zonaHoraria,
          theme: theme,
        ),
      ],
    );
  }
}

class _InfoFila extends StatelessWidget {
  final String label;
  final String value;
  final FluentThemeData theme;
  const _InfoFila(
      {required this.label, required this.value, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: theme.typography.caption
                ?.copyWith(color: theme.inactiveColor),
          ),
        ),
        Expanded(child: Text(value, style: theme.typography.body)),
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
                  const SizedBox(height: Spacing.ms),
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
                  const SizedBox(height: Spacing.ms),
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
            const SizedBox(width: Spacing.lg),

            // ── Columna formulario ──
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Layout estrecho (< PilarBreakpoints.mobile) — avatar arriba, formulario abajo
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
          const SizedBox(height: Spacing.sm),
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
          const SizedBox(height: Spacing.ml),
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
        const SizedBox(height: Spacing.md),
        InfoLabel(
          label: 'Teléfono',
          child: TextBox(
            controller: telefonoCtrl,
            placeholder: '+593 99 000 0000',
            enabled: !saving,
            keyboardType: TextInputType.phone,
          ),
        ),
        const SizedBox(height: Spacing.md),
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
        const SizedBox(height: Spacing.md),
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
        if (errorMsg != null) ...[
          const SizedBox(height: Spacing.md),
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
// Diálogo de cambiar contraseña — accesible desde el menú del header
// ===========================================================================

/// Diálogo de cambio de contraseña.
///
/// Supabase permite cambiar la contraseña desde una sesión activa con
/// [auth.updateUser] sin requerir la contraseña actual.
class CambiarContrasenaDialog extends ConsumerStatefulWidget {
  const CambiarContrasenaDialog({super.key});

  @override
  ConsumerState<CambiarContrasenaDialog> createState() =>
      _CambiarContrasenaDialogState();
}

class _CambiarContrasenaDialogState
    extends ConsumerState<CambiarContrasenaDialog> {
  final _nuevaCtrl = TextEditingController();
  final _confirmarCtrl = TextEditingController();
  bool _obscureNueva = true;
  bool _obscureConfirmar = true;
  bool _changing = false;
  String? _error;
  bool _success = false;

  @override
  void dispose() {
    _nuevaCtrl.dispose();
    _confirmarCtrl.dispose();
    super.dispose();
  }

  Future<void> _cambiar() async {
    final nueva = _nuevaCtrl.text;
    final confirmar = _confirmarCtrl.text;

    if (nueva.isEmpty) {
      setState(() => _error = 'Ingresa la nueva contraseña');
      return;
    }
    if (nueva.length < 8) {
      setState(() => _error = 'Mínimo 8 caracteres');
      return;
    }
    if (nueva != confirmar) {
      setState(() => _error = 'Las contraseñas no coinciden');
      return;
    }

    setState(() {
      _changing = true;
      _error = null;
      _success = false;
    });

    try {
      await ref.read(perfilWriteProvider.notifier).updatePassword(nueva);
      if (mounted) {
        setState(() {
          _changing = false;
          _success = true;
          _nuevaCtrl.clear();
          _confirmarCtrl.clear();
        });
      }
    } on AuthException catch (e) {
      if (mounted) setState(() { _changing = false; _error = e.message; });
    } catch (e) {
      if (mounted) setState(() { _changing = false; _error = e.toString(); });
    }
  }

  Widget _eyeButton(bool obscure, VoidCallback onTap) => Button(
        style: ButtonStyle(
          padding: WidgetStateProperty.all(
              const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: Spacing.sm)),
        ),
        onPressed: _changing ? null : onTap,
        child: Icon(
          obscure ? FluentIcons.red_eye : FluentIcons.hide,
          size: 14,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 400),
      title: const Text('Cambiar contraseña'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoLabel(
            label: 'Nueva contraseña',
            child: TextBox(
              controller: _nuevaCtrl,
              obscureText: _obscureNueva,
              enabled: !_changing,
              placeholder: 'Mínimo 8 caracteres',
              suffix: _eyeButton(
                  _obscureNueva,
                  () => setState(() => _obscureNueva = !_obscureNueva)),
            ),
          ),
          const SizedBox(height: Spacing.ms),
          InfoLabel(
            label: 'Confirmar contraseña',
            child: TextBox(
              controller: _confirmarCtrl,
              obscureText: _obscureConfirmar,
              enabled: !_changing,
              placeholder: 'Repite la nueva contraseña',
              suffix: _eyeButton(
                  _obscureConfirmar,
                  () => setState(() => _obscureConfirmar = !_obscureConfirmar)),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: Spacing.ms),
            InfoBar(
              title: const Text('Error'),
              content: Text(_error!),
              severity: InfoBarSeverity.error,
              onClose: () => setState(() => _error = null),
            ),
          ],
          if (_success) ...[
            const SizedBox(height: Spacing.ms),
            InfoBar(
              title: const Text('Contraseña actualizada'),
              content: const Text('Tu contraseña fue cambiada correctamente.'),
              severity: InfoBarSeverity.success,
              onClose: () => setState(() => _success = false),
            ),
          ],
        ],
      ),
      actions: [
        Button(
          onPressed: _changing ? null : () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
        FilledButton(
          onPressed: _changing ? null : _cambiar,
          child: _changing
              ? const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const PilarProgressRing(size: 14),
                    SizedBox(width: Spacing.sm),
                    Text('Actualizando…'),
                  ],
                )
              : const Text('Actualizar contraseña'),
        ),
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

// ===========================================================================
// PerfilPage — pantalla completa de perfil (footer nav + ruta /perfil)
// ===========================================================================

/// Pantalla completa de perfil de usuario.
///
/// Misma funcionalidad que [PerfilDialog] pero integrada en una [ScaffoldPage]
/// con header propio. Accesible desde el footer de navegación (PaneItem "Mi
/// Perfil") y desde la ruta `/perfil`.
class PerfilPage extends ConsumerStatefulWidget {
  const PerfilPage({super.key});

  @override
  ConsumerState<PerfilPage> createState() => _PerfilPageState();
}

class _PerfilPageState extends ConsumerState<PerfilPage> {
  final _nombreCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _emailLoginCtrl = TextEditingController();

  bool _initialized = false;
  bool _saving = false;
  bool _uploadingAvatar = false;
  String? _successMsg;
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
      await ref
          .read(perfilWriteProvider.notifier)
          .uploadAvatar(Uint8List.fromList(bytes), 'jpg');
      if (mounted) {
        setState(() {
          _uploadingAvatar = false;
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
      _successMsg = null;
    });

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
      if (mounted) setState(() { _saving = false; _errorMsg = error; });
      return;
    }

    final newEmail = _emailLoginCtrl.text.trim().toLowerCase();
    final currentEmail = (_originalEmailLogin ?? '').toLowerCase();
    if (newEmail.isNotEmpty && newEmail != currentEmail) {
      try {
        await ref.read(perfilWriteProvider.notifier).changeEmail(
              usuarioId: perfil.usuarioId,
              newEmail: newEmail,
            );
        _originalEmailLogin = newEmail;
      } catch (e) {
        if (mounted) setState(() { _saving = false; _errorMsg = _errorLabel(e.toString()); });
        return;
      }
    }

    if (mounted) {
      setState(() {
        _saving = false;
        _successMsg = 'Perfil actualizado correctamente.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final perfilAsync = ref.watch(perfilUsuarioProvider);
    final perfil = perfilAsync.valueOrNull;

    return ScaffoldPage(
      header: PageHeader(
        title: const Text('Mi Perfil'),
        commandBar: perfil != null
            ? CommandBar(
                mainAxisAlignment: MainAxisAlignment.end,
                primaryItems: [
                  CommandBarButton(
                    icon: _saving
                        ? const PilarProgressRing(size: 16)
                        : const Icon(FluentIcons.save),
                    label: const Text('Guardar cambios'),
                    onPressed: _saving ? null : () => _save(perfil),
                  ),
                ],
              )
            : null,
      ),
      content: perfilAsync.when(
        loading: () => const PilarLoadingCenter(),
        error: (e, _) => Center(
          child: Text(
            'Error cargando perfil: $e',
            style: TextStyle(color: theme.resources.systemFillColorCritical),
          ),
        ),
        data: (perfil) {
          if (perfil == null) {
            return const Center(child: Text('No se encontró el perfil.'));
          }
          _initFields(perfil);
          return LayoutBuilder(
            builder: (ctx, constraints) {
              final isWide = constraints.maxWidth >= PilarBreakpoints.mobile;
              return SingleChildScrollView(
                padding: const EdgeInsets.all(Spacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_successMsg != null) ...[
                      InfoBar(
                        title: const Text('Cambios guardados'),
                        content: Text(_successMsg!),
                        severity: InfoBarSeverity.success,
                        onClose: () => setState(() => _successMsg = null),
                      ),
                      const SizedBox(height: Spacing.md),
                    ],
                    if (_errorMsg != null) ...[
                      InfoBar(
                        title: const Text('Error'),
                        content: Text(_errorMsg!),
                        severity: InfoBarSeverity.error,
                        onClose: () => setState(() => _errorMsg = null),
                      ),
                      const SizedBox(height: Spacing.md),
                    ],
                    isWide
                        ? _WideContent(
                            perfil: perfil,
                            nombreCtrl: _nombreCtrl,
                            telefonoCtrl: _telefonoCtrl,
                            emailLoginCtrl: _emailLoginCtrl,
                            zonaHoraria: _zonaHoraria,
                            saving: _saving,
                            uploadingAvatar: _uploadingAvatar,
                            errorMsg: null,
                            onUpload: () => _pickAndUploadAvatar(perfil),
                            onZonaChanged: (v) => setState(() => _zonaHoraria = v),
                            onDismissError: () {},
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
                            errorMsg: null,
                            onUpload: () => _pickAndUploadAvatar(perfil),
                            onZonaChanged: (v) => setState(() => _zonaHoraria = v),
                            onDismissError: () {},
                            theme: theme,
                          ),
                    const SizedBox(height: Spacing.xl),
                    const Divider(),
                    const SizedBox(height: Spacing.lg),
                    _SecuritySection(theme: theme),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ===========================================================================
// Seccion Seguridad — 2FA / TOTP
// ===========================================================================

class _SecuritySection extends ConsumerWidget {
  final FluentThemeData theme;
  const _SecuritySection({required this.theme});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final factorsAsync = ref.watch(mfaFactorsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Seguridad', style: theme.typography.subtitle),
        const SizedBox(height: Spacing.md),
        factorsAsync.when(
          loading: () => const Row(
            children: [
              const PilarProgressRing(size: Spacing.md),
              SizedBox(width: Spacing.sm),
              Text('Cargando estado 2FA...'),
            ],
          ),
          error: (e, _) => InfoBar(
            title: const Text('Error'),
            content: Text('No se pudo cargar el estado 2FA: $e'),
            severity: InfoBarSeverity.error,
          ),
          data: (factors) {
            final isEnabled = factors.isNotEmpty;
            return Card(
              padding: const EdgeInsets.all(Spacing.md),
              child: Row(
                children: [
                  Icon(
                    FluentIcons.lock,
                    size: 24,
                    color: isEnabled ? theme.accentColor : theme.inactiveColor,
                  ),
                  const SizedBox(width: Spacing.ms),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Autenticacion de dos factores (2FA)',
                          style: theme.typography.bodyStrong,
                        ),
                        const SizedBox(height: Spacing.xs),
                        Text(
                          isEnabled
                              ? 'Protegida con app autenticadora (TOTP)'
                              : 'Agrega una capa extra de seguridad a tu cuenta',
                          style: theme.typography.caption
                              ?.copyWith(color: theme.inactiveColor),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Spacing.ms),
                  if (isEnabled)
                    Button(
                      onPressed: () => _confirmDisable2FA(context, ref, factors.first),
                      child: const Text('Desactivar'),
                    )
                  else
                    FilledButton(
                      onPressed: () => _showEnrollDialog(context, ref),
                      child: const Text('Activar 2FA'),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  void _showEnrollDialog(BuildContext context, WidgetRef ref) {
    showDialog<bool>(
      context: context,
      builder: (dialogCtx) => _EnrollTotpDialog(
        onComplete: () {
          ref.invalidate(mfaFactorsProvider);
          Navigator.of(dialogCtx).pop(true);
        },
      ),
    );
  }

  void _confirmDisable2FA(BuildContext context, WidgetRef ref, Factor factor) {
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => _DisableTotpDialog(
        factor: factor,
        onComplete: () {
          ref.invalidate(mfaFactorsProvider);
          Navigator.of(dialogCtx).pop();
        },
      ),
    );
  }
}

// ===========================================================================
// Dialog — Activar 2FA (Enroll TOTP)
// ===========================================================================

class _EnrollTotpDialog extends ConsumerStatefulWidget {
  final VoidCallback onComplete;
  const _EnrollTotpDialog({required this.onComplete});

  @override
  ConsumerState<_EnrollTotpDialog> createState() => _EnrollTotpDialogState();
}

class _EnrollTotpDialogState extends ConsumerState<_EnrollTotpDialog> {
  final _codeCtrl = TextEditingController();
  bool _loading = true;
  bool _verifying = false;
  String? _error;
  String? _factorId;
  String? _qrUri;
  String? _secret;

  @override
  void initState() {
    super.initState();
    _enroll();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _enroll() async {
    try {
      final result = await ref.read(perfilWriteProvider.notifier).enrollMfa(
            issuer: kAppName,
            friendlyName: '$kAppName TOTP',
          );
      if (mounted) {
        setState(() {
          _loading = false;
          _factorId = result.factorId;
          _qrUri = result.qrUri;
          _secret = result.secret;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Error al registrar el factor: $e';
        });
      }
    }
  }

  Future<void> _verify() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Ingresa un codigo de 6 digitos');
      return;
    }

    setState(() {
      _verifying = true;
      _error = null;
    });

    try {
      await ref.read(perfilWriteProvider.notifier).verifyMfa(
            factorId: _factorId!,
            code: code,
          );
      widget.onComplete();
    } on AuthException catch (e) {
      if (mounted) setState(() { _verifying = false; _error = e.message; });
    } catch (e) {
      if (mounted) setState(() { _verifying = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 420),
      title: const Text('Activar autenticacion de dos factores'),
      content: _loading
          ? const SizedBox(
              height: 200,
              child: PilarLoadingCenter(),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Escanea este codigo QR con tu app autenticadora '
                  '(Google Authenticator, Authy, etc.):',
                  style: theme.typography.body,
                ),
                const SizedBox(height: Spacing.md),
                if (_qrUri != null)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(Spacing.ms),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: QrImageView(
                        data: _qrUri!,
                        version: QrVersions.auto,
                        size: 200,
                      ),
                    ),
                  ),
                const SizedBox(height: Spacing.ms),
                if (_secret != null) ...[
                  Text(
                    'O ingresa este codigo manualmente:',
                    style: theme.typography.caption
                        ?.copyWith(color: theme.inactiveColor),
                  ),
                  const SizedBox(height: Spacing.xs),
                  SelectableText(
                    _secret!,
                    style: theme.typography.bodyStrong?.copyWith(
                      fontFamily: 'monospace',
                      letterSpacing: 2,
                    ),
                  ),
                ],
                const SizedBox(height: Spacing.ml),
                InfoLabel(
                  label: 'Codigo de verificacion',
                  child: TextBox(
                    controller: _codeCtrl,
                    placeholder: '000000',
                    enabled: !_verifying,
                    maxLength: 6,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    onSubmitted: (_) => _verify(),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: Spacing.ms),
                  InfoBar(
                    title: const Text('Error'),
                    content: Text(_error!),
                    severity: InfoBarSeverity.error,
                    onClose: () => setState(() => _error = null),
                  ),
                ],
              ],
            ),
      actions: [
        Button(
          onPressed: _verifying ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        if (!_loading)
          FilledButton(
            onPressed: _verifying ? null : _verify,
            child: _verifying
                ? const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const PilarProgressRing(size: 14),
                      SizedBox(width: Spacing.sm),
                      Text('Verificando...'),
                    ],
                  )
                : const Text('Verificar y activar'),
          ),
      ],
    );
  }
}

// ===========================================================================
// Dialog — Desactivar 2FA
// ===========================================================================

class _DisableTotpDialog extends ConsumerStatefulWidget {
  final Factor factor;
  final VoidCallback onComplete;
  const _DisableTotpDialog({required this.factor, required this.onComplete});

  @override
  ConsumerState<_DisableTotpDialog> createState() => _DisableTotpDialogState();
}

class _DisableTotpDialogState extends ConsumerState<_DisableTotpDialog> {
  bool _removing = false;
  String? _error;

  Future<void> _unenroll() async {
    setState(() {
      _removing = true;
      _error = null;
    });

    try {
      await ref.read(perfilWriteProvider.notifier).unenrollMfa(widget.factor.id);
      widget.onComplete();
    } on AuthException catch (e) {
      if (mounted) setState(() { _removing = false; _error = e.message; });
    } catch (e) {
      if (mounted) setState(() { _removing = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 400),
      title: const Text('Desactivar autenticacion de dos factores'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Al desactivar 2FA, tu cuenta sera menos segura. '
            'Solo necesitaras tu correo y contrasena para iniciar sesion.',
          ),
          if (_error != null) ...[
            const SizedBox(height: Spacing.ms),
            InfoBar(
              title: const Text('Error'),
              content: Text(_error!),
              severity: InfoBarSeverity.error,
              onClose: () => setState(() => _error = null),
            ),
          ],
        ],
      ),
      actions: [
        Button(
          onPressed: _removing ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _removing ? null : _unenroll,
          child: _removing
              ? const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const PilarProgressRing(size: 14),
                    SizedBox(width: Spacing.sm),
                    Text('Desactivando...'),
                  ],
                )
              : const Text('Desactivar 2FA'),
        ),
      ],
    );
  }
}
