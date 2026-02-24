import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_provider.dart';

// ---------------------------------------------------------------------------
// Data models
// ---------------------------------------------------------------------------

/// Resumen liviano de una empresa en la que el usuario tiene membresia.
/// Usado en la pantalla de seleccion de empresa.
class EmpresaResumen {
  const EmpresaResumen({
    required this.empresaId,
    required this.nombre,
    this.ruc,
    this.logoUrl,
    required this.rolCodigo,
    required this.rolNombre,
    required this.esActiva,
  });

  final String empresaId;
  final String nombre;
  final String? ruc;
  final String? logoUrl;
  final String rolCodigo;
  final String rolNombre;
  final bool esActiva;

  factory EmpresaResumen.fromJson(Map<String, dynamic> json) {
    return EmpresaResumen(
      empresaId: json['empresa_id'] as String,
      nombre: json['nombre'] as String,
      ruc: json['ruc'] as String?,
      logoUrl: json['logo_url'] as String?,
      rolCodigo: json['rol_codigo'] as String? ?? 'LECTURA',
      rolNombre: json['rol_nombre'] as String? ?? 'Lectura',
      esActiva: json['es_activa'] as bool? ?? true,
    );
  }
}

/// Configuracion completa de la empresa activa.
/// Incluye datos de contacto, branding y moneda funcional.
class EmpresaConfig {
  const EmpresaConfig({
    required this.empresaId,
    required this.nombre,
    this.nombreComercial,
    this.ruc,
    this.tipoRuc,
    this.provinciaId,
    this.ciudadId,
    this.direccion,
    this.telefono,
    this.email,
    this.web,
    this.logoUrl,
    this.colorPrimario,
    this.colorSecundario,
    this.loginTitulo,
    required this.monedaFuncional,
  });

  final String empresaId;
  final String nombre;
  final String? nombreComercial;
  final String? ruc;
  final String? tipoRuc;
  final int? provinciaId;
  final int? ciudadId;
  final String? direccion;
  final String? telefono;
  final String? email;
  final String? web;
  final String? logoUrl;

  /// Color primario en formato hex, p.ej. "#0078D4".
  final String? colorPrimario;

  /// Color secundario en formato hex.
  final String? colorSecundario;

  /// Titulo personalizado que se muestra en la pantalla de login.
  final String? loginTitulo;

  /// Codigo ISO de la moneda funcional, por defecto 'USD'.
  final String monedaFuncional;

  factory EmpresaConfig.fromJson(Map<String, dynamic> json) {
    return EmpresaConfig(
      empresaId: json['empresa_id'] as String,
      nombre: json['nombre'] as String,
      nombreComercial: json['nombre_comercial'] as String?,
      ruc: json['ruc'] as String?,
      tipoRuc: json['tipo_ruc'] as String?,
      provinciaId: json['provincia_id'] as int?,
      ciudadId: json['ciudad_id'] as int?,
      direccion: json['direccion'] as String?,
      telefono: json['telefono'] as String?,
      email: json['email'] as String?,
      web: json['web'] as String?,
      logoUrl: json['logo_url'] as String?,
      colorPrimario: json['color_primario'] as String?,
      colorSecundario: json['color_secundario'] as String?,
      loginTitulo: json['login_titulo'] as String?,
      monedaFuncional: json['moneda_funcional'] as String? ?? 'USD',
    );
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

/// Lista de empresas a las que pertenece el usuario autenticado.
/// Se invalida automaticamente al cambiar la sesion.
final misEmpresasProvider = FutureProvider<List<EmpresaResumen>>((ref) async {
  // Se suscribe a authStateProvider para que el provider se invalide
  // cuando el usuario hace login / logout / refresh de sesion.
  ref.watch(authStateProvider);

  final client = ref.watch(supabaseClientProvider);
  try {
    final data = await client.rpc('get_mis_empresas');
    return (data as List)
        .map((e) => EmpresaResumen.fromJson(e as Map<String, dynamic>))
        .toList();
  } catch (_) {
    // RPC no existe aún (migraciones no aplicadas): mostrar empty state.
    return const <EmpresaResumen>[];
  }
});

/// ID de la empresa activa extraido del JWT (appMetadata).
/// Null cuando no hay sesion o cuando el JWT aun no tiene empresa asignada.
final empresaActivaIdProvider = Provider<String?>((ref) {
  final session = ref.watch(sessionProvider);
  return session?.user.appMetadata['empresa_id'] as String?;
});

/// Configuracion completa de la empresa activa.
/// Null cuando no hay empresa seleccionada.
final empresaConfigProvider = FutureProvider<EmpresaConfig?>((ref) async {
  final empresaId = ref.watch(empresaActivaIdProvider);
  if (empresaId == null) return null;

  // Tambien se invalida al cambiar la sesion.
  ref.watch(authStateProvider);

  final client = ref.watch(supabaseClientProvider);
  final data = await client
      .rpc('get_company_config', params: {'p_empresa_id': empresaId});
  if (data == null) return null;
  return EmpresaConfig.fromJson(data as Map<String, dynamic>);
});

/// Funcion para cambiar la empresa activa del usuario.
///
/// Llama al RPC `set_empresa_activa`, refresca la sesion para que el JWT
/// incluya el nuevo `empresa_id`, e invalida los providers dependientes.
///
/// Uso:
/// ```dart
/// final switchEmpresa = ref.read(switchEmpresaProvider);
/// await switchEmpresa('uuid-de-la-empresa');
/// ```
final switchEmpresaProvider =
    Provider<Future<void> Function(String empresaId)>((ref) {
  return (String empresaId) async {
    final client = ref.read(supabaseClientProvider);
    await client.rpc(
      'set_empresa_activa',
      params: {'p_empresa_id': empresaId},
    );
    await client.auth.refreshSession();
    ref.invalidate(empresaConfigProvider);
    ref.invalidate(misEmpresasProvider);
  };
});
