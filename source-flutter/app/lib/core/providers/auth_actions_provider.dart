import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------------------
// AuthActionsNotifier
// ---------------------------------------------------------------------------

/// Notifier de acciones de autenticación.
///
/// Centraliza todas las mutaciones de Auth para que los screens nunca
/// llamen directamente a [Supabase.instance.client.auth].
///
/// ### Uso
/// ```dart
/// await ref.read(authActionsProvider.notifier).signOut();
/// await ref.read(authActionsProvider.notifier).resendConfirmEmail(email);
/// await ref.read(authActionsProvider.notifier).updatePassword(newPassword);
/// ```
class AuthActionsNotifier extends AutoDisposeAsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  /// Cierra la sesión activa del usuario.
  Future<void> signOut() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => Supabase.instance.client.auth.signOut(),
    );
  }

  /// Reenvía el correo de confirmación de registro al [email] indicado.
  Future<void> resendConfirmEmail(String email) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => Supabase.instance.client.auth.resend(
        type: OtpType.signup,
        email: email,
      ),
    );
  }

  /// Actualiza la contraseña del usuario autenticado.
  Future<void> updatePassword(String newPassword) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => Supabase.instance.client.auth.updateUser(
        UserAttributes(password: newPassword),
      ),
    );
  }

  /// Establece la contraseña inicial y borra el flag [needs_password].
  ///
  /// Usado en [SetPasswordScreen] cuando el usuario accede por primera vez
  /// via invitación. Combina la actualización de contraseña y metadata
  /// en una sola llamada atómica.
  ///
  /// Retorna el [User] resultante o lanza [AuthException] en error.
  Future<User?> setInitialPassword(String newPassword) async {
    state = const AsyncLoading();
    User? result;
    state = await AsyncValue.guard(() async {
      final response = await Supabase.instance.client.auth.updateUser(
        UserAttributes(
          password: newPassword,
          data: {'needs_password': false},
        ),
      );
      result = response.user;
    });
    return result;
  }
}

/// Provider de acciones de autenticación (autoDispose).
final authActionsProvider =
    AsyncNotifierProvider.autoDispose<AuthActionsNotifier, void>(
  AuthActionsNotifier.new,
);

// ---------------------------------------------------------------------------
// MFA read providers
// ---------------------------------------------------------------------------

/// Nivel de garantía actual del autenticador (AAL1 / AAL2).
///
/// Usado en [MfaChallengeScreen] para detectar si ya se alcanzó AAL2.
final mfaAssuranceLevelProvider = FutureProvider.autoDispose(
  (_) => Supabase.instance.client.auth.mfa.getAuthenticatorAssuranceLevel(),
);

/// Lista de factores MFA registrados para el usuario actual.
///
/// Usado en [MfaChallengeScreen] para obtener el [factorId] TOTP verificado.
final mfaFactorsProvider = FutureProvider.autoDispose(
  (_) => Supabase.instance.client.auth.mfa.listFactors(),
);
