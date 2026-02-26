import 'package:brick_gen/brick_gen.dart';
import 'package:brick_offline_first/brick_offline_first.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../offline/connectivity_service.dart';
import 'repository_provider.dart';

// ---------------------------------------------------------------------------
// Modelo
// ---------------------------------------------------------------------------

class PerfilUsuario {
  final String usuarioId;
  final String empresaId;
  final String? nombreDisplay;
  final String? avatarUrl;
  final String? telefono;
  final String? emailContacto;
  final String emailLogin;
  final String? nombreGlobal;
  final String zonaHoraria;

  const PerfilUsuario({
    required this.usuarioId,
    required this.empresaId,
    this.nombreDisplay,
    this.avatarUrl,
    this.telefono,
    this.emailContacto,
    required this.emailLogin,
    this.nombreGlobal,
    this.zonaHoraria = 'America/Guayaquil',
  });

  /// Nombre para mostrar en UI: override por empresa → nombre global → email.
  String get displayName => nombreDisplay ?? nombreGlobal ?? emailLogin;

  /// Inicial para el avatar cuando no hay imagen.
  String get initial => displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

  factory PerfilUsuario.fromJson(Map<String, dynamic> json) {
    return PerfilUsuario(
      usuarioId: json['usuario_id'] as String? ?? '',
      empresaId: json['empresa_id'] as String? ?? '',
      nombreDisplay: json['nombre_display'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      telefono: json['telefono'] as String?,
      emailContacto: json['email_contacto'] as String?,
      emailLogin: json['email_login'] as String? ?? '',
      nombreGlobal: json['nombre_global'] as String?,
      zonaHoraria: json['zona_horaria'] as String? ?? 'America/Guayaquil',
    );
  }

  PerfilUsuario copyWith({
    String? nombreDisplay,
    String? avatarUrl,
    String? telefono,
    String? emailContacto,
    String? zonaHoraria,
  }) {
    return PerfilUsuario(
      usuarioId: usuarioId,
      empresaId: empresaId,
      nombreDisplay: nombreDisplay ?? this.nombreDisplay,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      telefono: telefono ?? this.telefono,
      emailContacto: emailContacto ?? this.emailContacto,
      emailLogin: emailLogin,
      nombreGlobal: nombreGlobal,
      zonaHoraria: zonaHoraria ?? this.zonaHoraria,
    );
  }
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class PerfilUsuarioNotifier extends AsyncNotifier<PerfilUsuario?> {
  @override
  Future<PerfilUsuario?> build() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return null;

    // Web: siempre RPC
    if (kIsWeb) {
      final data = await Supabase.instance.client.rpc('get_mi_perfil');
      if (data == null || (data as Map).isEmpty) return null;
      return PerfilUsuario.fromJson(Map<String, dynamic>.from(data));
    }

    // Native: intenta RPC primero (datos ricos: emailLogin, nombreGlobal).
    // Si falla por falta de red, cae en SQLite via Brick.
    try {
      final data = await Supabase.instance.client.rpc('get_mi_perfil');
      if (data != null && (data as Map).isNotEmpty) {
        return PerfilUsuario.fromJson(Map<String, dynamic>.from(data));
      }
    } catch (e) {
      if (!isOfflineError(e)) rethrow;
      ref.read(connectivityProvider.notifier).reportOffline();
    }

    // Offline fallback: leer UsuarioEmpresaPerfil de SQLite
    final repo = ref.read(repositoryProvider);
    if (repo == null) return null;

    final empresaId = session.user.appMetadata['empresa_id'] as String?;
    if (empresaId == null) return null;

    final results = await repo.get<UsuarioEmpresaPerfil>(
      policy: OfflineFirstGetPolicy.localOnly,
      query: Query(where: [
        Where.exact('usuarioId', session.user.id),
        Where.exact('empresaId', empresaId),
      ]),
    );

    if (results.isEmpty) return null;
    final p = results.first;

    return PerfilUsuario(
      usuarioId: p.usuarioId,
      empresaId: p.empresaId,
      nombreDisplay: p.nombreDisplay,
      avatarUrl: p.avatarUrl,
      telefono: p.telefono,
      emailContacto: p.emailContacto,
      emailLogin: session.user.email ?? '',
      nombreGlobal: null,
      zonaHoraria: p.zonaHoraria ?? 'America/Guayaquil',
    );
  }

  /// Persiste cambios de perfil y actualiza el estado local.
  /// Retorna null si tuvo éxito, o el mensaje de error si falló.
  Future<String?> saveChanges({
    String? nombreDisplay,
    String? avatarUrl,
    String? telefono,
    String? emailContacto,
    String? zonaHoraria,
  }) async {
    // Verificar conectividad antes de intentar el RPC
    if (!kIsWeb && !ref.read(connectivityProvider)) {
      return 'Sin conexión. Reconéctate para guardar cambios.';
    }

    final payload = <String, dynamic>{};
    if (nombreDisplay != null) payload['nombre_display'] = nombreDisplay;
    if (avatarUrl != null) payload['avatar_url'] = avatarUrl;
    if (telefono != null) payload['telefono'] = telefono;
    if (emailContacto != null) payload['email_contacto'] = emailContacto;
    if (zonaHoraria != null) payload['zona_horaria'] = zonaHoraria;

    try {
      final result = await Supabase.instance.client
          .rpc('update_mi_perfil', params: {'p_data': payload});

      final map = Map<String, dynamic>.from(result as Map);
      if (map['ok'] != true) {
        return map['error'] as String? ?? 'Error desconocido';
      }
    } catch (e) {
      if (isOfflineError(e)) {
        ref.read(connectivityProvider.notifier).reportOffline();
        return 'Sin conexión. Reconéctate para guardar cambios.';
      }
      rethrow;
    }

    // Actualizar estado local sin rellamar al servidor
    state = state.whenData((perfil) => perfil?.copyWith(
          nombreDisplay: nombreDisplay ?? perfil.nombreDisplay,
          avatarUrl: avatarUrl ?? perfil.avatarUrl,
          telefono: telefono ?? perfil.telefono,
          emailContacto: emailContacto ?? perfil.emailContacto,
          zonaHoraria: zonaHoraria ?? perfil.zonaHoraria,
        ));

    return null; // null = éxito
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final perfilUsuarioProvider =
    AsyncNotifierProvider<PerfilUsuarioNotifier, PerfilUsuario?>(
  PerfilUsuarioNotifier.new,
);
