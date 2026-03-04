import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/offline/connectivity_service.dart';
import '../../../core/providers/perfil_provider.dart';

// ---------------------------------------------------------------------------
// MFA Enroll Result
// ---------------------------------------------------------------------------

/// Resultado del enroll MFA — expone los datos necesarios para renderizar
/// el QR y el secreto TOTP en el diálogo de activación 2FA.
class MfaEnrollResult {
  final String factorId;
  final String? qrUri;
  final String? secret;

  const MfaEnrollResult({
    required this.factorId,
    this.qrUri,
    this.secret,
  });
}

// ---------------------------------------------------------------------------
// PerfilWriteNotifier
// ---------------------------------------------------------------------------

/// Notifier de escritura para operaciones de perfil de usuario:
/// cambio de contraseña, subida de avatar, cambio de email, y MFA.
///
/// A diferencia de [PerfilUsuarioNotifier], este notifier se ocupa
/// de las operaciones de escritura que antes llamaban directamente
/// a `Supabase.instance.client` desde los widgets.
///
/// ### Métodos disponibles
///
/// | Método | Operación |
/// |--------|-----------|
/// | [updatePassword] | `auth.updateUser(UserAttributes(password:))` |
/// | [uploadAvatar] | Storage upload + `saveChanges(avatarUrl:)` |
/// | [changeEmail] | RPC `change_email_usuario` |
/// | [enrollMfa] | `auth.mfa.enroll(...)` — retorna [MfaEnrollResult] |
/// | [verifyMfa] | `auth.mfa.challenge + verify` |
/// | [unenrollMfa] | `auth.mfa.unenroll(factorId)` |
///
/// ### Uso
///
/// ```dart
/// // Cambiar contraseña
/// await ref.read(perfilWriteProvider.notifier).updatePassword('nueva1234');
///
/// // Observar estado
/// final ws = ref.watch(perfilWriteProvider);
/// ws.when(data: (_) => ..., loading: () => const ProgressRing(), error: ...);
/// ```
class PerfilWriteNotifier extends AutoDisposeAsyncNotifier<void> {
  @override
  FutureOr<void> build() {
    // Estado inicial vacío; no hace nada al construirse.
  }

  // ── Contraseña ─────────────────────────────────────────────────────────────

  /// Cambia la contraseña del usuario autenticado.
  ///
  /// Lanza [AuthException] si Supabase rechaza el cambio.
  Future<void> updatePassword(String newPassword) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: newPassword),
      );
      ref.read(connectivityProvider.notifier).reportOnline();
    });
  }

  // ── Avatar ─────────────────────────────────────────────────────────────────

  /// Sube [bytes] al bucket `avatares` con extensión [ext] y actualiza el
  /// perfil del usuario con la nueva URL pública (con cache-busting).
  ///
  /// Path: `avatares/{usuario_id}/{empresa_id}/avatar.{ext}`
  ///
  /// Invalida [perfilUsuarioProvider] en éxito.
  /// Lanza [StorageException] o cualquier error de red.
  Future<void> uploadAvatar(Uint8List bytes, String ext) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) throw Exception('Sin sesión activa');

      final usuarioId = session.user.id;
      final empresaId =
          session.user.appMetadata['empresa_id'] as String? ?? '';
      if (empresaId.isEmpty) throw Exception('empresa_id no disponible en JWT');

      final contentType = ext == 'png' ? 'image/png' : 'image/jpeg';
      final path = '$usuarioId/$empresaId/avatar.$ext';

      await Supabase.instance.client.storage.from('avatares').uploadBinary(
            path,
            bytes,
            fileOptions:
                FileOptions(contentType: contentType, upsert: true),
          );

      final url = Supabase.instance.client.storage
          .from('avatares')
          .getPublicUrl(path);
      final urlBust = '$url?t=${DateTime.now().millisecondsSinceEpoch}';

      final error = await ref
          .read(perfilUsuarioProvider.notifier)
          .saveChanges(avatarUrl: urlBust);

      if (error != null) throw Exception(error);

      ref.read(connectivityProvider.notifier).reportOnline();
    });
  }

  // ── Email ──────────────────────────────────────────────────────────────────

  /// Cambia el email de login del usuario vía RPC `change_email_usuario`.
  ///
  /// Lanza [Exception] si el RPC retorna `ok: false` o si hay error de red.
  Future<void> changeEmail({
    required String usuarioId,
    required String newEmail,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      try {
        final result = await Supabase.instance.client.rpc(
          'change_email_usuario',
          params: {
            'p_usuario_id': usuarioId,
            'p_new_email': newEmail,
          },
        );
        final map = Map<String, dynamic>.from(result as Map);
        if (map['ok'] != true) {
          throw Exception(map['error']?.toString() ?? 'Error al cambiar email');
        }
        ref.read(connectivityProvider.notifier).reportOnline();
      } catch (e) {
        if (isOfflineError(e)) {
          ref.read(connectivityProvider.notifier).reportOffline();
        }
        rethrow;
      }
    });
  }

  // ── MFA: Enroll ────────────────────────────────────────────────────────────

  /// Inicia el proceso de enroll TOTP.
  ///
  /// Retorna [MfaEnrollResult] con el `factorId`, `qrUri` y `secret` TOTP.
  /// El resultado se almacena en el state como [AsyncData<MfaEnrollResult>]
  /// pero el notifier está tipado como `void`; usa el valor de retorno directo.
  ///
  /// Lanza [AuthException] si falla el enroll.
  Future<MfaEnrollResult> enrollMfa({
    required String issuer,
    required String friendlyName,
  }) async {
    final res = await Supabase.instance.client.auth.mfa.enroll(
      factorType: FactorType.totp,
      issuer: issuer,
      friendlyName: friendlyName,
    );
    ref.read(connectivityProvider.notifier).reportOnline();
    return MfaEnrollResult(
      factorId: res.id,
      qrUri: res.totp?.uri,
      secret: res.totp?.secret,
    );
  }

  // ── MFA: Verify ────────────────────────────────────────────────────────────

  /// Crea un challenge y verifica el código TOTP para completar el enroll.
  ///
  /// [factorId] es el ID del factor retornado por [enrollMfa].
  /// [code] es el código de 6 dígitos ingresado por el usuario.
  ///
  /// Lanza [AuthException] si el código es incorrecto.
  Future<void> verifyMfa({
    required String factorId,
    required String code,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final auth = Supabase.instance.client.auth;
      final challenge = await auth.mfa.challenge(factorId: factorId);
      await auth.mfa.verify(
        factorId: factorId,
        challengeId: challenge.id,
        code: code,
      );
      ref.read(connectivityProvider.notifier).reportOnline();
    });
  }

  // ── MFA: Unenroll ──────────────────────────────────────────────────────────

  /// Desactiva (unenroll) el factor TOTP identificado por [factorId].
  ///
  /// Lanza [AuthException] si falla.
  Future<void> unenrollMfa(String factorId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await Supabase.instance.client.auth.mfa.unenroll(factorId);
      ref.read(connectivityProvider.notifier).reportOnline();
    });
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Provider de escritura para operaciones de perfil de usuario.
///
/// Scope: autoDispose (se libera cuando no hay widgets escuchando).
final perfilWriteProvider =
    AsyncNotifierProvider.autoDispose<PerfilWriteNotifier, void>(
  PerfilWriteNotifier.new,
);
