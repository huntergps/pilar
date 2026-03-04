import 'dart:async';

import 'package:brick_gen/brick_gen.dart';
import 'package:brick_offline_first/brick_offline_first.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../offline/connectivity_service.dart';
import 'auth_provider.dart';
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
    this.zonaHoraria = 'UTC',
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
      zonaHoraria: json['zona_horaria'] as String? ?? 'UTC',
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
    // Observar la sesión activa: cuando el token cambie (refresh automático,
    // switchEmpresa, sign-in), Riverpod reconstruye este provider y reintenta
    // la carga con el JWT actualizado. Esto elimina la condición de carrera
    // donde build() capturaba un JWT transitorio sin empresa_id.
    final session = ref.watch(sessionProvider);
    if (session == null) return null;

    // Realtime: re-cargar cuando el perfil del usuario se actualiza en su
    // empresa (ej.: cambio desde otro tab, desde panel de admin).
    final channel = Supabase.instance.client
        .channel('perfil_usuario_${session.user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'usuarios_empresa',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'usuario_id',
            value: session.user.id,
          ),
          callback: (_) => ref.invalidateSelf(),
        )
        .subscribe();
    ref.onDispose(() => channel.unsubscribe());

    // Web: RPC directa, sin cache local
    if (kIsWeb) {
      final data = await Supabase.instance.client.rpc('get_mi_perfil');
      if (data != null && (data as Map).isNotEmpty) {
        return PerfilUsuario.fromJson(Map<String, dynamic>.from(data));
      }
      // get_mi_perfil retornó {} → empresa_id aún no está en el JWT de esta
      // petición (ej.: el hook aún no corrió para este refresh de token).
      // Al próximo cambio de sesión, sessionProvider cambiará y este provider
      // se reconstruirá automáticamente con el JWT correcto.
      return null;
    }

    // Native: local-first + background refresh
    final local = await _getLocal(session);

    // Background sync desde RPC (tiene datos que Brick no tiene: emailLogin, nombreGlobal)
    unawaited(_refreshFromRpc());

    return local;
  }

  Future<PerfilUsuario?> _getLocal(Session session) async {
    final repo = ref.read(repositoryProvider);
    if (repo == null) return null;

    final empresaId = session.user.appMetadata['empresa_id'] as String?;
    if (empresaId == null) return null;

    try {
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
        zonaHoraria: p.zonaHoraria ?? 'UTC',
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _refreshFromRpc() async {
    try {
      final data = await Supabase.instance.client.rpc('get_mi_perfil');
      if (data != null && (data as Map).isNotEmpty) {
        state = AsyncData(
          PerfilUsuario.fromJson(Map<String, dynamic>.from(data)),
        );
      }
      ref.read(connectivityProvider.notifier).reportOnline();
      // Sincronizar Brick en background para futuras lecturas offline
      final session = Supabase.instance.client.auth.currentSession;
      final empresaId = session?.user.appMetadata['empresa_id'] as String?;
      if (empresaId != null) {
        final repo = ref.read(repositoryProvider);
        unawaited(repo?.get<UsuarioEmpresaPerfil>(
          policy: OfflineFirstGetPolicy.awaitRemote,
          query: Query(where: [
            Where.exact('usuarioId', session!.user.id),
            Where.exact('empresaId', empresaId),
          ]),
        ));
      }
    } catch (e) {
      if (isOfflineError(e)) {
        ref.read(connectivityProvider.notifier).reportOffline();
      }
    }
  }

  /// Persiste cambios de perfil y actualiza el estado local.
  /// Retorna null si tuvo éxito, o el mensaje de error si falló.
  /// Requiere conectividad — operación solo-online.
  Future<String?> saveChanges({
    String? nombreDisplay,
    String? avatarUrl,
    String? telefono,
    String? emailContacto,
    String? zonaHoraria,
  }) async {
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
