import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------------------
// Modelos — movidos desde gestor_permisos_screen.dart
// ---------------------------------------------------------------------------

class RolItem {
  final String id;
  final String codigo;
  final String nombre;
  final String? descripcion;
  final bool esSistema;
  final String? empresaId;
  final bool activo;

  const RolItem({
    required this.id,
    required this.codigo,
    required this.nombre,
    this.descripcion,
    required this.esSistema,
    this.empresaId,
    required this.activo,
  });

  factory RolItem.fromJson(Map<String, dynamic> json) => RolItem(
        id: json['id'] as String,
        codigo: json['codigo'] as String,
        nombre: json['nombre'] as String,
        descripcion: json['descripcion'] as String?,
        esSistema: json['es_sistema'] as bool? ?? false,
        empresaId: json['empresa_id'] as String?,
        activo: json['activo'] as bool? ?? true,
      );
}

class PermisoEstado {
  final String id;
  final String codigo;
  final String modulo;
  final String recurso;
  final String accion;
  final String? descripcion;
  final int nivel;     // 0=menu, 1=tabla CRUD, 2=sub-acción
  final String? parentId;
  bool tienePermiso;

  PermisoEstado({
    required this.id,
    required this.codigo,
    required this.modulo,
    required this.recurso,
    required this.accion,
    this.descripcion,
    this.nivel = 1,
    this.parentId,
    required this.tienePermiso,
  });

  factory PermisoEstado.fromJson(Map<String, dynamic> json) => PermisoEstado(
        id: json['id'] as String,
        codigo: json['codigo'] as String,
        modulo: json['modulo'] as String,
        recurso: json['recurso'] as String,
        accion: json['accion'] as String,
        descripcion: json['descripcion'] as String?,
        nivel: (json['nivel'] as num?)?.toInt() ?? 1,
        parentId: json['parent_id'] as String?,
        tienePermiso: json['tiene_permiso'] as bool? ?? false,
      );
}

class UsuarioRolItem {
  final String usuarioId;
  final String email;
  final String nombreDisplay;
  final String? avatarUrl;
  final bool activo;

  const UsuarioRolItem({
    required this.usuarioId,
    required this.email,
    required this.nombreDisplay,
    this.avatarUrl,
    required this.activo,
  });

  factory UsuarioRolItem.fromJson(Map<String, dynamic> json) => UsuarioRolItem(
        usuarioId: json['usuario_id'] as String,
        email: json['email'] as String,
        nombreDisplay:
            json['nombre_display'] as String? ?? json['email'] as String,
        avatarUrl: json['avatar_url'] as String?,
        activo: json['activo'] as bool? ?? true,
      );
}

// ---------------------------------------------------------------------------
// Read providers — movidos desde gestor_permisos_screen.dart
// ---------------------------------------------------------------------------

/// Carga todos los roles de la empresa (sistema + personalizados).
final rolesAdminProvider = FutureProvider<List<RolItem>>((ref) async {
  final data = await Supabase.instance.client.rpc('admin_get_roles');
  return (data as List)
      .map((e) => RolItem.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Carga los permisos (con estado asignado/no asignado) para un rol dado.
final permisosRolProvider =
    FutureProvider.family<List<PermisoEstado>, String>((ref, rolId) async {
  final data = await Supabase.instance.client
      .rpc('admin_get_permisos_rol', params: {'p_rol_id': rolId});
  return (data as List)
      .map((e) => PermisoEstado.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Carga los usuarios asignados a un rol dado.
final usuariosRolProvider =
    FutureProvider.family<List<UsuarioRolItem>, String>((ref, rolId) async {
  final data = await Supabase.instance.client
      .rpc('admin_get_usuarios_rol', params: {'p_rol_id': rolId});
  return (data as List)
      .map((e) => UsuarioRolItem.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ---------------------------------------------------------------------------
// GestorPermisosNotifier
//
// Wraps all write/mutation Supabase operations from gestor_permisos_screen.dart.
// ---------------------------------------------------------------------------

class GestorPermisosNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  // ── Toggle permiso en un rol ──────────────────────────────────────────────

  Future<({bool ok, String? error})> togglePermisoRol({
    required String rolId,
    required String permisoId,
    required bool conceder,
  }) async {
    try {
      await Supabase.instance.client.rpc('admin_toggle_permiso_rol', params: {
        'p_rol_id': rolId,
        'p_permiso_id': permisoId,
        'p_conceder': conceder,
      });
      return (ok: true, error: null);
    } catch (e) {
      return (ok: false, error: e.toString());
    }
  }

  // ── Toggle usuario en un rol (asignar / quitar) ───────────────────────────

  Future<({bool ok, String? error})> toggleUsuarioRol({
    required String userId,
    required String rolId,
    required bool asignar,
  }) async {
    try {
      await Supabase.instance.client.rpc('admin_toggle_usuario_rol', params: {
        'p_usuario_id': userId,
        'p_rol_id': rolId,
        'p_asignar': asignar,
      });
      return (ok: true, error: null);
    } catch (e) {
      return (ok: false, error: e.toString());
    }
  }

  // ── Crear rol ─────────────────────────────────────────────────────────────

  Future<({bool ok, String? error})> crearRol({
    required String codigo,
    required String nombre,
    String? descripcion,
  }) async {
    try {
      await Supabase.instance.client.rpc('admin_crear_rol', params: {
        'p_codigo': codigo,
        'p_nombre': nombre,
        'p_descripcion': descripcion,
      });
      return (ok: true, error: null);
    } catch (e) {
      return (ok: false, error: e.toString());
    }
  }

  // ── Eliminar rol ──────────────────────────────────────────────────────────

  Future<({bool ok, String? error})> eliminarRol({
    required String rolId,
  }) async {
    try {
      await Supabase.instance.client
          .rpc('admin_eliminar_rol', params: {'p_rol_id': rolId});
      return (ok: true, error: null);
    } catch (e) {
      final msg = e.toString().contains('tiene_usuarios_asignados')
          ? 'No se puede eliminar: el rol tiene usuarios asignados'
          : e.toString();
      return (ok: false, error: msg);
    }
  }

  // ── Obtener todos los usuarios (para el diálogo de asignación) ────────────

  Future<({List<Map<String, dynamic>>? data, String? error})>
      getAllUsuarios() async {
    try {
      final data = await Supabase.instance.client.rpc('admin_get_usuarios');
      return (
        data: (data as List).cast<Map<String, dynamic>>(),
        error: null,
      );
    } catch (e) {
      return (data: null, error: e.toString());
    }
  }
}

final gestorPermisosProvider =
    AsyncNotifierProvider<GestorPermisosNotifier, void>(
        GestorPermisosNotifier.new);
