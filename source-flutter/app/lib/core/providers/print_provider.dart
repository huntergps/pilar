import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pilar_print/pilar_print.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_provider.dart';

// ---------------------------------------------------------------------------
// Catálogo de impresoras virtuales
// ---------------------------------------------------------------------------

/// Carga el catálogo de impresoras activas de la empresa desde Supabase y
/// configura el [PrintService] singleton.
///
/// Se re-ejecuta automáticamente cuando cambia el estado de autenticación
/// (e.g., cambio de empresa).
final printCatalogoProvider = FutureProvider<List<ImpresoraVirtual>>((ref) async {
  ref.watch(authStateProvider);

  final client = Supabase.instance.client;
  final session = client.auth.currentSession;
  if (session == null) return const [];

  try {
    final rows = await client
        .rpc('impresoras_get_catalogo')
        .then((data) => (data as List).cast<Map<String, dynamic>>());

    final impresoras = rows.map(ImpresoraVirtual.fromJson).toList();
    PrintService.instance.configure(impresoras);
    return impresoras;
  } catch (_) {
    // Si la tabla no existe aún (antes de migración) retornar lista vacía.
    return const [];
  }
});

/// Expone el [PrintService] singleton.
///
/// Watchea [printCatalogoProvider] para asegurar que el catálogo se carga
/// antes de que cualquier módulo llame a [PrintService.instance.print].
final printServiceProvider = Provider<PrintService>((ref) {
  ref.watch(printCatalogoProvider);
  return PrintService.instance;
});
