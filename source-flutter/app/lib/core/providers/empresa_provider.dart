import 'dart:async';

import 'package:brick_gen/brick_gen.dart';
import 'package:brick_offline_first/brick_offline_first.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_provider.dart';
import '../offline/connectivity_service.dart';
import 'repository_provider.dart';

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
    this.colorForzadoEn,
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

  /// Timestamp en que el admin forzó el color a todos los usuarios.
  final DateTime? colorForzadoEn;

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
      colorForzadoEn: json['color_forzado_en'] != null
          ? DateTime.tryParse(json['color_forzado_en'] as String)
          : null,
    );
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

/// Lista de empresas a las que pertenece el usuario autenticado.
///
/// Patrón local-first + background sync:
/// 1. Emite datos de SQLite (Brick) inmediatamente.
/// 2. Sincroniza en background desde Supabase (RPC para datos completos con roles).
/// 3. Emite datos actualizados.
final misEmpresasProvider = StreamProvider<List<EmpresaResumen>>((ref) async* {
  ref.watch(authStateProvider);

  final client = ref.watch(supabaseClientProvider);

  // Web: RPC directa (sin Brick)
  if (kIsWeb) {
    try {
      final data = await client.rpc('get_mis_empresas');
      yield (data as List)
          .map((e) => EmpresaResumen.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      yield const <EmpresaResumen>[];
    }
    return;
  }

  // Native: local-first + background sync
  final repo = ref.read(repositoryProvider);
  if (repo == null) { yield const <EmpresaResumen>[]; return; }

  // 1. Local primero — unir UsuarioEmpresaPerfil + Empresa desde SQLite
  try {
    final results = await Future.wait<dynamic>([
      repo.get<UsuarioEmpresaPerfil>(policy: OfflineFirstGetPolicy.localOnly),
      repo.get<Empresa>(policy: OfflineFirstGetPolicy.localOnly),
    ]);
    final perfils  = results[0] as List<UsuarioEmpresaPerfil>;
    final empresas = results[1] as List<Empresa>;
    yield _joinEmpresasLocal(perfils, empresas);
  } catch (_) {
    yield const <EmpresaResumen>[];
  }

  // 2. Background sync: RPC retorna datos completos con roles
  try {
    final data = await client.rpc('get_mis_empresas');
    yield (data as List)
        .map((e) => EmpresaResumen.fromJson(e as Map<String, dynamic>))
        .toList();
    ref.read(connectivityProvider.notifier).reportOnline();
    // Sincronizar Brick en background para futuras lecturas offline
    unawaited(repo.get<UsuarioEmpresaPerfil>(
      policy: OfflineFirstGetPolicy.awaitRemote,
    ));
    unawaited(repo.get<Empresa>(
      policy: OfflineFirstGetPolicy.awaitRemote,
    ));
  } catch (e) {
    if (isOfflineError(e)) {
      ref.read(connectivityProvider.notifier).reportOffline();
    }
  }
});

/// Construye EmpresaResumen desde modelos Brick locales (sin info de rol).
List<EmpresaResumen> _joinEmpresasLocal(
  List<UsuarioEmpresaPerfil> perfils,
  List<Empresa> empresas,
) {
  final empresaMap = {for (final e in empresas) e.id: e};
  return perfils
      .where((p) => p.activo)
      .map((p) {
        final e = empresaMap[p.empresaId];
        if (e == null) return null;
        return EmpresaResumen(
          empresaId: p.empresaId,
          nombre: e.nombre,
          ruc: e.ruc,
          logoUrl: e.logoUrl,
          rolCodigo: 'MIEMBRO',
          rolNombre: 'Miembro',
          esActiva: p.activo,
        );
      })
      .whereType<EmpresaResumen>()
      .toList();
}

/// ID de la empresa activa extraido del JWT (appMetadata).
/// Null cuando no hay sesion o cuando el JWT aun no tiene empresa asignada.
final empresaActivaIdProvider = Provider<String?>((ref) {
  final session = ref.watch(sessionProvider);
  return session?.user.appMetadata['empresa_id'] as String?;
});

/// Configuracion completa de la empresa activa.
///
/// Patrón local-first + background sync:
/// 1. Emite datos básicos desde SQLite (Brick Empresa) inmediatamente.
/// 2. Sincroniza en background via RPC (datos completos: colores, moneda, etc.).
/// 3. Emite datos actualizados.
final empresaConfigProvider = StreamProvider<EmpresaConfig?>((ref) async* {
  final empresaId = ref.watch(empresaActivaIdProvider);
  if (empresaId == null) { yield null; return; }

  ref.watch(authStateProvider);

  // Web: RPC directa
  if (kIsWeb) {
    final client = ref.watch(supabaseClientProvider);
    try {
      final data = await client
          .rpc('get_company_config', params: {'p_empresa_id': empresaId});
      yield data == null
          ? null
          : EmpresaConfig.fromJson(data as Map<String, dynamic>);
    } catch (_) {
      yield null;
    }
    return;
  }

  // Native: local-first + background sync
  final repo = ref.read(repositoryProvider);
  if (repo == null) { yield null; return; }

  // 1. Local primero — datos básicos desde Brick SQLite
  try {
    final empresas = await repo.get<Empresa>(
      policy: OfflineFirstGetPolicy.localOnly,
      query: Query.where('id', empresaId),
    );
    if (empresas.isNotEmpty) {
      final e = empresas.first;
      yield EmpresaConfig(
        empresaId: e.id,
        nombre: e.nombre,
        nombreComercial: e.nombreComercial,
        ruc: e.ruc,
        logoUrl: e.logoUrl,
        colorPrimario: e.colorPrimario,
        colorSecundario: e.colorSecundario,
        monedaFuncional: 'USD',
      );
    }
  } catch (_) {}

  // 2. Background sync via RPC (datos completos: moneda, login_titulo, etc.)
  try {
    final client = ref.read(supabaseClientProvider);
    final data = await client
        .rpc('get_company_config', params: {'p_empresa_id': empresaId});
    if (data != null) {
      yield EmpresaConfig.fromJson(data as Map<String, dynamic>);
    }
    ref.read(connectivityProvider.notifier).reportOnline();
    // Sincronizar Brick en background
    unawaited(repo.get<Empresa>(
      policy: OfflineFirstGetPolicy.awaitRemote,
      query: Query.where('id', empresaId),
    ));
  } catch (e) {
    if (isOfflineError(e)) {
      ref.read(connectivityProvider.notifier).reportOffline();
    }
  }
});

/// Funcion para cambiar la empresa activa del usuario.
///
/// Requiere conectividad — actualiza JWT via `set_empresa_activa` + refreshSession.
/// Si no hay red, lanza excepción que el caller debe capturar.
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
