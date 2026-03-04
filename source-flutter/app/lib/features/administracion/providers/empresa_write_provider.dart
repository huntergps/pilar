import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/offline/connectivity_service.dart';
import '../../../core/providers/brick_write_provider.dart';
import '../../../core/providers/empresa_provider.dart';

// ---------------------------------------------------------------------------
// EmpresaWriteNotifier
// ---------------------------------------------------------------------------

/// Notifier de escritura para datos de la empresa activa.
///
/// A diferencia de [BrickWriteNotifier], las escrituras van siempre por RPC
/// (no por INSERT directo a tabla), porque los RPCs validan permisos y aplican
/// lógica de negocio en el servidor (propagación de colores, etc.).
///
/// ### Métodos disponibles
///
/// | Método | RPC | Descripción |
/// |--------|-----|-------------|
/// | [updateEmpresa] | `admin_update_empresa` | Datos generales (nombre, dirección, logo, etc.) |
/// | [updateBranding] | `admin_update_branding` | Color de acento de empresa |
/// | [forceColorToAll] | `admin_force_empresa_color` | Propaga color a todos los usuarios de la empresa |
///
/// ### Uso en pantallas
///
/// ```dart
/// // Actualizar datos generales
/// await ref.read(empresaWriteProvider.notifier).updateEmpresa(
///   params: {'nombre': 'Mi Empresa S.A.', 'telefono': '099...'},
/// );
///
/// // Observar estado de escritura
/// final writeState = ref.watch(empresaWriteProvider);
/// writeState.when(
///   data: (_) => ...,
///   loading: () => const ProgressRing(),
///   error: (e, _) {
///     if (e is OfflineWriteException) { /* sin red */ }
///   },
/// );
/// ```
class EmpresaWriteNotifier extends AutoDisposeAsyncNotifier<void> {
  @override
  FutureOr<void> build() {
    // Estado inicial vacío; no hace nada al construirse.
  }

  // ── RPC: admin_update_empresa ──────────────────────────────────────────────

  /// Actualiza datos generales de la empresa activa.
  ///
  /// [params] es un mapa con los campos a actualizar (snake_case), p. ej.:
  /// ```dart
  /// {'nombre': 'Acme S.A.', 'telefono': '04-2345678', 'logo_url': '...'}
  /// ```
  /// Corresponde al RPC `admin_update_empresa(p_data JSONB)`.
  ///
  /// Invalida [empresaConfigProvider] y [misEmpresasProvider] en éxito.
  /// Lanza [OfflineWriteException] si no hay conectividad.
  Future<void> updateEmpresa({
    required Map<String, dynamic> params,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      try {
        final result = await Supabase.instance.client.rpc(
          'admin_update_empresa',
          params: {'p_data': params},
        );
        if (result is Map && result['ok'] != true) {
          throw Exception(result['error']?.toString() ?? 'Error en admin_update_empresa');
        }
        ref.read(connectivityProvider.notifier).reportOnline();
        _invalidateEmpresaProviders();
      } catch (e) {
        if (e is OfflineWriteException) rethrow;
        if (isOfflineError(e)) {
          ref.read(connectivityProvider.notifier).reportOffline();
          throw const OfflineWriteException(
            'Sin conexión: no se puede actualizar la empresa offline.',
          );
        }
        rethrow;
      }
    });
  }

  // ── RPC: admin_update_branding ─────────────────────────────────────────────

  /// Actualiza el branding (color de acento) de la empresa activa.
  ///
  /// [params] es un mapa con los campos de branding, p. ej.:
  /// ```dart
  /// {'color_primario': '#0078D4'}
  /// ```
  /// Corresponde al RPC `admin_update_branding(p_data JSONB)`.
  ///
  /// Invalida [empresaConfigProvider] en éxito.
  /// Lanza [OfflineWriteException] si no hay conectividad.
  Future<void> updateBranding({
    required Map<String, dynamic> params,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      try {
        final result = await Supabase.instance.client.rpc(
          'admin_update_branding',
          params: {'p_data': params},
        );
        if (result is Map && result['ok'] != true) {
          throw Exception(result['error']?.toString() ?? 'Error en admin_update_branding');
        }
        ref.read(connectivityProvider.notifier).reportOnline();
        _invalidateEmpresaProviders();
      } catch (e) {
        if (e is OfflineWriteException) rethrow;
        if (isOfflineError(e)) {
          ref.read(connectivityProvider.notifier).reportOffline();
          throw const OfflineWriteException(
            'Sin conexión: no se puede actualizar el branding offline.',
          );
        }
        rethrow;
      }
    });
  }

  // ── RPC: admin_force_empresa_color ─────────────────────────────────────────

  /// Propaga el color de acento de la empresa a todos sus usuarios.
  ///
  /// Descarta el color personalizado de cada usuario y les aplica [color]
  /// (hex, p. ej. `'#0078D4'`) en su próxima sesión.
  ///
  /// Corresponde al RPC `admin_force_empresa_color(p_color TEXT)`.
  ///
  /// No invalida providers locales (es una operación puramente de BD).
  /// Lanza [OfflineWriteException] si no hay conectividad.
  Future<void> forceColorToAll({required String color}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      try {
        final result = await Supabase.instance.client.rpc(
          'admin_force_empresa_color',
          params: {'p_color': color},
        );
        if (result is Map && result['ok'] != true) {
          throw Exception(result['error']?.toString() ?? 'Error en admin_force_empresa_color');
        }
        ref.read(connectivityProvider.notifier).reportOnline();
      } catch (e) {
        if (e is OfflineWriteException) rethrow;
        if (isOfflineError(e)) {
          ref.read(connectivityProvider.notifier).reportOffline();
          throw const OfflineWriteException(
            'Sin conexión: no se puede aplicar el color a todos offline.',
          );
        }
        rethrow;
      }
    });
  }

  // ── Storage: logos ─────────────────────────────────────────────────────────

  /// Sube el logo de la empresa al bucket `logos` y retorna la URL pública.
  ///
  /// Path en Storage: `{empresaId}/logo.{ext}`
  ///
  /// Usa `upsert: true` para sobreescribir el logo existente. La URL retornada
  /// es la URL canónica (sin cache-buster) — el caller puede agregar `?t=...`
  /// si necesita forzar recarga en `Image.network`.
  ///
  /// Lanza [StorageException] si falla el upload.
  Future<String> uploadLogo({
    required Uint8List bytes,
    required String ext,
    required String empresaId,
  }) async {
    state = const AsyncLoading();
    String publicUrl = '';
    state = await AsyncValue.guard(() async {
      final path = '$empresaId/logo.$ext';
      await Supabase.instance.client.storage
          .from('logos')
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(upsert: true, contentType: 'image/$ext'),
          );
      publicUrl = Supabase.instance.client.storage
          .from('logos')
          .getPublicUrl(path);
    });
    return publicUrl;
  }

  // ── RPC: admin_update_config_extra ─────────────────────────────────────────

  /// Actualiza la configuración extra de la empresa (campos adicionales).
  ///
  /// [params] es un mapa con los campos a actualizar, p. ej.:
  /// ```dart
  /// {'whatsapp_numero': '+593991234567', 'telegram_id': '@miempresa'}
  /// ```
  /// Corresponde al RPC `admin_update_config_extra(p_data JSONB)`.
  ///
  /// Invalida [empresaConfigProvider] en éxito.
  /// Lanza [OfflineWriteException] si no hay conectividad.
  Future<void> updateConfigExtra({required Map<String, dynamic> params}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      try {
        await Supabase.instance.client.rpc(
          'admin_update_config_extra',
          params: {'p_data': params},
        );
        ref.read(connectivityProvider.notifier).reportOnline();
        _invalidateEmpresaProviders();
      } catch (e) {
        if (e is OfflineWriteException) rethrow;
        if (isOfflineError(e)) {
          ref.read(connectivityProvider.notifier).reportOffline();
          throw const OfflineWriteException(
            'Sin conexión: no se puede actualizar la configuración extra offline.',
          );
        }
        rethrow;
      }
    });
  }

  // ── Edge Function: invite-user ─────────────────────────────────────────────

  /// Invita a un usuario como parte del setup inicial de la empresa.
  /// Llama a la Edge Function 'invite-user'.
  Future<void> inviteUser({required Map<String, dynamic> body}) async {
    await Supabase.instance.client.functions.invoke(
      'invite-user',
      body: body,
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _invalidateEmpresaProviders() {
    ref.invalidate(empresaConfigProvider);
    ref.invalidate(misEmpresasProvider);
  }
}

/// Provider de escritura para datos de la empresa activa.
///
/// Scope: autoDispose (se libera cuando no hay widgets escuchando).
final empresaWriteProvider =
    AsyncNotifierProvider.autoDispose<EmpresaWriteNotifier, void>(
  EmpresaWriteNotifier.new,
);
