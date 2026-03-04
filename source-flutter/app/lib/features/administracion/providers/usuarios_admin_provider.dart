import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------------------
// UsuariosAdminNotifier
//
// Wraps all write/mutation Supabase operations from usuarios_screen.dart.
// Read operations (SELECT) remain in FutureProvider in admin_providers.dart.
// ---------------------------------------------------------------------------

class UsuariosAdminNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  // ── Toggle usuario activo/inactivo ────────────────────────────────────────

  Future<({bool ok, String? error})> toggleActivo({
    required String userId,
    required bool activo,
  }) async {
    try {
      final result = await Supabase.instance.client.rpc(
        'admin_toggle_usuario_activo',
        params: {'p_usuario_id': userId, 'p_activo': activo},
      );
      if (result is Map && result['ok'] == true) {
        return (ok: true, error: null);
      }
      final err = result is Map ? result['error'] as String? : null;
      return (ok: false, error: err ?? 'Error desconocido');
    } catch (e) {
      return (ok: false, error: e.toString());
    }
  }

  // ── Cancelar invitación ───────────────────────────────────────────────────

  Future<({bool ok, String? error})> cancelarInvitacion({
    required String email,
  }) async {
    try {
      final result = await Supabase.instance.client.rpc(
        'admin_cancel_invitacion',
        params: {'p_email': email},
      );
      final map = result is Map
          ? Map<String, dynamic>.from(result)
          : <String, dynamic>{};
      if (map['ok'] == true) {
        return (ok: true, error: null);
      }
      return (ok: false, error: map['error'] as String?);
    } catch (e) {
      return (ok: false, error: e.toString());
    }
  }

  // ── Quitar usuario de empresa ─────────────────────────────────────────────

  /// Returns `{ok, orphan, error}`.
  Future<({bool ok, bool orphan, String? error})> removeFromEmpresa({
    required String userId,
  }) async {
    try {
      final result = await Supabase.instance.client.rpc(
        'admin_remove_user_from_empresa',
        params: {'p_usuario_id': userId},
      );
      final map = Map<String, dynamic>.from(result as Map);
      if (map['ok'] == true) {
        return (ok: true, orphan: map['orphan'] == true, error: null);
      }
      return (
        ok: false,
        orphan: false,
        error: map['error'] as String? ?? 'Error desconocido',
      );
    } catch (e) {
      return (ok: false, orphan: false, error: e.toString());
    }
  }

  // ── Eliminar usuario de auth ──────────────────────────────────────────────

  /// Returns `{ok, mensajes, adjuntos, error}`.
  Future<({bool ok, int mensajes, int adjuntos, String? error})>
      deleteFromAuth({
    required String userId,
  }) async {
    try {
      final result = await Supabase.instance.client.rpc(
        'admin_delete_user_from_auth',
        params: {'p_usuario_id': userId},
      );
      final map = result is Map
          ? Map<String, dynamic>.from(result)
          : <String, dynamic>{};
      return (
        ok: map['ok'] == true,
        mensajes: (map['mensajes'] as num?)?.toInt() ?? 0,
        adjuntos: (map['adjuntos'] as num?)?.toInt() ?? 0,
        error: map['error'] as String?,
      );
    } catch (e) {
      return (ok: false, mensajes: 0, adjuntos: 0, error: e.toString());
    }
  }

  // ── Guardar perfil de un usuario (admin) ──────────────────────────────────

  Future<({bool ok, String? error})> updatePerfil({
    required String userId,
    required Map<String, dynamic> data,
  }) async {
    try {
      final result = await Supabase.instance.client.rpc(
        'admin_update_perfil_usuario',
        params: {
          'p_usuario_id': userId,
          'p_data': data,
        },
      );
      final map = Map<String, dynamic>.from(result as Map);
      if (map['ok'] == true) return (ok: true, error: null);
      return (ok: false, error: map['error'] as String?);
    } catch (e) {
      return (ok: false, error: e.toString());
    }
  }

  // ── Cambiar email de acceso ───────────────────────────────────────────────

  Future<({bool ok, String? error})> changeEmail({
    required String userId,
    required String newEmail,
  }) async {
    try {
      final result = await Supabase.instance.client.rpc(
        'change_email_usuario',
        params: {'p_usuario_id': userId, 'p_new_email': newEmail},
      );
      final map = Map<String, dynamic>.from(result as Map);
      if (map['ok'] == true) return (ok: true, error: null);
      return (ok: false, error: map['error'] as String?);
    } catch (e) {
      return (ok: false, error: e.toString());
    }
  }

  // ── Establecer roles ──────────────────────────────────────────────────────

  Future<({bool ok, String? error})> setRoles({
    required String userId,
    required List<String> rolIds,
  }) async {
    try {
      final result = await Supabase.instance.client.rpc(
        'admin_set_roles_usuario',
        params: {
          'p_usuario_id': userId,
          'p_rol_ids': rolIds,
        },
      );
      final map = Map<String, dynamic>.from(result as Map);
      if (map['ok'] == true) return (ok: true, error: null);
      return (ok: false, error: map['error'] as String?);
    } catch (e) {
      return (ok: false, error: e.toString());
    }
  }

  // ── Establecer contraseña ─────────────────────────────────────────────────

  Future<({bool ok, String? error})> setPassword({
    required String userId,
    required String password,
  }) async {
    try {
      final result = await Supabase.instance.client.rpc(
        'admin_set_user_password',
        params: {
          'p_user_id': userId,
          'p_password': password,
        },
      );
      final map = Map<String, dynamic>.from(result as Map);
      if (map['ok'] == true) return (ok: true, error: null);
      return (ok: false, error: map['error'] as String?);
    } catch (e) {
      return (ok: false, error: e.toString());
    }
  }

  // ── Cargar perfil de un usuario (admin read) ──────────────────────────────

  Future<({Map<String, dynamic>? data, String? error})> getPerfil({
    required String userId,
  }) async {
    try {
      final data = await Supabase.instance.client.rpc(
        'admin_get_perfil_usuario',
        params: {'p_usuario_id': userId},
      );
      final map = Map<String, dynamic>.from(data as Map);
      if (map.containsKey('error')) {
        return (data: null, error: map['error'] as String? ?? 'Error');
      }
      return (data: map, error: null);
    } catch (e) {
      return (data: null, error: e.toString());
    }
  }

  // ── Subir avatar ──────────────────────────────────────────────────────────

  Future<({String? url, String? error})> uploadAvatar({
    required String userId,
    required List<int> bytes,
  }) async {
    try {
      final empresaId = Supabase.instance.client.auth.currentSession
              ?.user.appMetadata['empresa_id'] as String? ??
          'default';
      final path = '$userId/$empresaId/avatar.jpg';

      await Supabase.instance.client.storage
          .from('avatares')
          .uploadBinary(
            path,
            Uint8List.fromList(bytes),
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );

      final url = Supabase.instance.client.storage
          .from('avatares')
          .getPublicUrl(path);
      final urlWithBust = '$url?t=${DateTime.now().millisecondsSinceEpoch}';

      // Persist avatar_url in profile
      await Supabase.instance.client.rpc(
        'admin_update_perfil_usuario',
        params: {
          'p_usuario_id': userId,
          'p_data': {'avatar_url': urlWithBust},
        },
      );

      return (url: urlWithBust, error: null);
    } catch (e) {
      return (url: null, error: e.toString());
    }
  }

  // ── Invitar usuario (Edge Function) ──────────────────────────────────────

  Future<({bool ok, String? tipo, String? message})> invitarUsuario({
    required String email,
    required String rolId,
  }) async {
    Future<FunctionResponse> doInvoke() =>
        Supabase.instance.client.functions.invoke(
          'invite-user',
          body: {'email': email, 'rol_id': rolId},
        );

    try {
      FunctionResponse response;
      try {
        response = await doInvoke();
      } on FunctionException catch (fe) {
        // JWT inválido/revocado → refrescar sesión y reintentar una vez
        if (fe.status == 401) {
          await Supabase.instance.client.auth.refreshSession();
          response = await doInvoke();
        } else {
          rethrow;
        }
      }

      final data = response.data as Map<String, dynamic>?;
      if (response.status != 200 || data?['ok'] != true) {
        return (
          ok: false,
          tipo: null,
          message: data?['message'] as String? ??
              'Error al enviar invitación (${response.status})',
        );
      }
      return (ok: true, tipo: data!['tipo'] as String?, message: null);
    } catch (e) {
      return (
        ok: false,
        tipo: null,
        message: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  // ── Gestionar roles rápido (dialog) ──────────────────────────────────────

  Future<({bool ok, String? error})> toggleRolUsuario({
    required String userId,
    required String rolId,
    required bool asignar,
  }) async {
    try {
      final result = await Supabase.instance.client.rpc(
        'admin_toggle_usuario_rol',
        params: {
          'p_usuario_id': userId,
          'p_rol_id': rolId,
          'p_asignar': asignar,
        },
      );
      if (result is Map && result['ok'] == true) {
        return (ok: true, error: null);
      }
      final err = result is Map ? result['error'] as String? : null;
      return (ok: false, error: err ?? 'Error desconocido');
    } catch (e) {
      return (ok: false, error: e.toString());
    }
  }
}

final usuariosAdminProvider =
    AsyncNotifierProvider<UsuariosAdminNotifier, void>(
        UsuariosAdminNotifier.new);
