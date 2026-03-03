import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'empresa_provider.dart';

/// Carga todos los codigos de permiso del usuario actual en esta empresa
/// via RPC `get_mis_permisos`.
///
/// Se invalida automaticamente al cambiar empresa (via [empresaActivaIdProvider]).
///
/// Nota: existe tambien [hasPermissionProvider] en `usuario_provider.dart` que
/// lee permisos directamente del JWT (sincronico, sin red). Este provider es
/// la version autoritativa que consulta la base de datos y puede usarse
/// cuando se necesita la lista completa actualizada.
final misPermisosProvider = FutureProvider.autoDispose<Set<String>>((ref) async {
  final empresaId = ref.watch(empresaActivaIdProvider);
  if (empresaId == null) return const {};

  final data = await Supabase.instance.client.rpc('get_mis_permisos');
  if (data == null) return const {};

  return Set<String>.from((data as List).map((e) => e.toString()));
});

/// Verifica si el usuario actual tiene un permiso especifico consultando
/// la base de datos (via [misPermisosProvider]).
///
/// Retorna `false` mientras carga o si hay error.
///
/// Para verificacion sincronico desde el JWT, usar
/// `hasPermissionProvider` de `usuario_provider.dart`.
final hasPermissionRpcProvider =
    Provider.family.autoDispose<bool, String>((ref, permiso) {
  return ref.watch(misPermisosProvider).maybeWhen(
        data: (permisos) => permisos.contains(permiso),
        orElse: () => false,
      );
});
