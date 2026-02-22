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

/// Session activa. Null si el usuario no esta autenticado.
final sessionProvider = Provider<Session?>((ref) {
  return ref.watch(authStateProvider).valueOrNull?.session;
});

/// true cuando hay una sesion valida.
final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(sessionProvider) != null;
});
