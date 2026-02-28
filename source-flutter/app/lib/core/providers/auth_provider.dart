import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Singleton del cliente Supabase.
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// Stream del estado de autenticacion de Supabase.
/// Se emite un nuevo valor ante cualquier cambio (login, logout, refresh, etc.).
final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(supabaseClientProvider).auth.onAuthStateChange;
});

/// Session activa. Null solo cuando el usuario se deslogea explicitamente
/// o cuando el refresh token mismo expira.
///
/// Implementado como Provider reactivo (ref.watch) para evitar la race
/// condition del enfoque NotifierProvider + ref.listen:
///
/// Problema del enfoque anterior (_SessionNotifier con ref.listen):
///   - En build(), ref.read(authStateProvider).valueOrNull devuelve null
///     porque el StreamProvider aun esta en AsyncLoading cuando se
///     inicializa por primera vez.
///   - ref.listen solo dispara ante NUEVAS emisiones del stream. Si
///     authStateProvider ya tenia AsyncData(initialSession) cuando se
///     registro el listener, ese evento no se re-emite y la sesion
///     queda en null — haciendo que hasPermissionProvider devuelva false
///     aunque el JWT contenga todos los permisos correctos.
///
/// Solucion: ref.watch (reactivo) + fallback a currentSession del SDK.
///   - ref.watch(authStateProvider) reconstruye este provider ante CUALQUIER
///     cambio del stream, incluyendo el primer AsyncData.
///   - El fallback garantiza que, si el StreamProvider aun esta cargando,
///     usamos la sesion ya disponible en el SDK (sincronico, nunca null
///     si el usuario esta autenticado).
///   - signedOut: authState.session == null Y currentSession == null → null.
///   - Token refresh failure (offline): el evento trae session != null →
///     se retiene la sesion. Si trae session == null, currentSession
///     tambien sera null en ese punto — comportamiento correcto.
final sessionProvider = Provider<Session?>((ref) {
  final authState = ref.watch(authStateProvider);
  // Prioridad 1: el valor del stream (incluye el evento signedOut con session null).
  // Prioridad 2: fallback al SDK (sincronico) para el caso AsyncLoading inicial.
  final streamSession = authState.valueOrNull?.session;

  // Si el stream ya emitio algun valor (AsyncData o AsyncError), lo usamos.
  // Esto captura el signedOut (session == null) correctamente.
  if (authState is AsyncData<AuthState>) {
    return streamSession;
  }

  // Si el stream aun esta cargando (AsyncLoading) o tuvo error (AsyncError),
  // usamos la sesion del SDK como fallback sincronico.
  // Guard con try/catch para entornos de test donde Supabase no esta inicializado.
  try {
    return Supabase.instance.client.auth.currentSession;
  } catch (_) {
    return null;
  }
});

/// true cuando hay una sesion valida.
final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(sessionProvider) != null;
});
