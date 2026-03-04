import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pilar_print/pilar_print.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------------------
// Read provider — movido desde impresoras_screen.dart
// ---------------------------------------------------------------------------

/// Lista de impresoras virtuales de la empresa (reloadable).
///
/// Provider público para poder hacer override en tests:
/// ```dart
/// impresorasScreenProvider.overrideWith((_) async => [...]);
/// ```
final impresorasScreenProvider =
    FutureProvider.autoDispose<List<ImpresoraVirtual>>((ref) async {
  final rows = await Supabase.instance.client
      .rpc('impresoras_get_catalogo')
      .then((data) => (data as List).cast<Map<String, dynamic>>());
  return rows.map(ImpresoraVirtual.fromJson).toList();
});

// ---------------------------------------------------------------------------
// ImpresorasAdminNotifier
//
// Wraps all write/mutation Supabase operations from impresoras_screen.dart.
// ---------------------------------------------------------------------------

class ImpresorasAdminNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  // ── Crear impresora virtual ───────────────────────────────────────────────

  Future<({bool ok, String? error})> crearImpresora({
    required String nombre,
    String? descripcion,
    required String tipoDoc,
  }) async {
    try {
      final empresaId = Supabase.instance.client.auth.currentSession
          ?.user.appMetadata['empresa_id'] as String?;
      if (empresaId == null) {
        return (ok: false, error: 'No hay empresa activa');
      }
      await Supabase.instance.client.from('impresoras_virtuales').insert({
        'empresa_id': empresaId,
        'nombre': nombre,
        'descripcion': descripcion,
        'tipo_doc': tipoDoc,
      });
      return (ok: true, error: null);
    } catch (e) {
      return (ok: false, error: e.toString());
    }
  }

  // ── Desactivar (soft-delete) impresora ────────────────────────────────────

  Future<({bool ok, String? error})> desactivarImpresora({
    required String impresoraId,
  }) async {
    try {
      await Supabase.instance.client
          .from('impresoras_virtuales')
          .update({'activo': false}).eq('id', impresoraId);
      return (ok: true, error: null);
    } catch (e) {
      return (ok: false, error: e.toString());
    }
  }
}

final impresorasAdminProvider =
    AsyncNotifierProvider<ImpresorasAdminNotifier, void>(
        ImpresorasAdminNotifier.new);
