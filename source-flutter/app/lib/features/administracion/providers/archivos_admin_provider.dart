import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------------------
// ArchivosAdminNotifier
//
// Wraps all write/mutation Supabase operations from archivos_screen.dart.
// ---------------------------------------------------------------------------

class ArchivosAdminNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  // ── Eliminar adjunto ──────────────────────────────────────────────────────

  Future<({bool ok, String? error})> eliminarAdjunto({
    required String adjuntoId,
  }) async {
    try {
      await Supabase.instance.client.rpc('eliminar_adjunto', params: {
        'p_adjunto_id': adjuntoId,
      });
      return (ok: true, error: null);
    } catch (e) {
      return (ok: false, error: e.toString());
    }
  }

  // ── Renombrar adjunto ─────────────────────────────────────────────────────

  Future<({bool ok, String? error})> renombrarAdjunto({
    required String adjuntoId,
    required String nombre,
  }) async {
    try {
      await Supabase.instance.client.rpc('renombrar_adjunto', params: {
        'p_adjunto_id': adjuntoId,
        'p_nombre': nombre,
      });
      return (ok: true, error: null);
    } catch (e) {
      return (ok: false, error: e.toString());
    }
  }

  // ── Agregar tag a adjunto ─────────────────────────────────────────────────

  Future<({bool ok, String? error})> agregarTag({
    required String adjuntoId,
    required String tag,
  }) async {
    try {
      await Supabase.instance.client.rpc('agregar_tag_adjunto', params: {
        'p_adjunto_id': adjuntoId,
        'p_tag': tag,
      });
      return (ok: true, error: null);
    } catch (e) {
      return (ok: false, error: e.toString());
    }
  }

  // ── Quitar tag de adjunto ─────────────────────────────────────────────────

  Future<({bool ok, String? error})> quitarTag({
    required String adjuntoId,
    required String tag,
  }) async {
    try {
      await Supabase.instance.client.rpc('quitar_tag_adjunto', params: {
        'p_adjunto_id': adjuntoId,
        'p_tag': tag,
      });
      return (ok: true, error: null);
    } catch (e) {
      return (ok: false, error: e.toString());
    }
  }

  // ── Actualizar descripción de adjunto ─────────────────────────────────────

  Future<({bool ok, String? error})> actualizarDescripcion({
    required String adjuntoId,
    required String? descripcion,
  }) async {
    try {
      await Supabase.instance.client
          .rpc('actualizar_descripcion_adjunto', params: {
        'p_adjunto_id': adjuntoId,
        'p_descripcion': descripcion,
      });
      return (ok: true, error: null);
    } catch (e) {
      return (ok: false, error: e.toString());
    }
  }

  // ── Registrar adjunto tras upload ─────────────────────────────────────────

  Future<({bool ok, String? error})> registrarAdjunto({
    required String empresaId,
    required String entidadTipo,
    required String entidadId,
    required String nombre,
    required String nombreOriginal,
    required String mimeType,
    required int tamanioBytes,
    required String storagePath,
  }) async {
    try {
      await Supabase.instance.client.rpc('registrar_adjunto', params: {
        'p_empresa_id': empresaId,
        'p_entidad_tipo': entidadTipo,
        'p_entidad_id': entidadId,
        'p_nombre': nombre,
        'p_nombre_original': nombreOriginal,
        'p_mime_type': mimeType,
        'p_tamanio_bytes': tamanioBytes,
        'p_storage_path': storagePath,
      });
      return (ok: true, error: null);
    } catch (e) {
      return (ok: false, error: e.toString());
    }
  }

  // ── Buscar entidad por tipo y query ───────────────────────────────────────

  Future<List<Map<String, dynamic>>> searchEntidad({
    required String tipo,
    required String query,
    required String empresaId,
  }) async {
    const tableMap = {
      'contacto': ('contactos', 'nombre_completo'),
      'producto': ('productos', 'nombre'),
      'factura': ('facturas', 'numero'),
      'orden_venta': ('ordenes_venta', 'numero'),
      'orden_compra': ('ordenes_compra', 'numero'),
      'empleado': ('empleados', 'nombre_completo'),
    };
    final info = tableMap[tipo];
    if (info == null) return [];
    final (tableName, nameField) = info;
    try {
      final rows = await Supabase.instance.client
          .from(tableName)
          .select('id, $nameField')
          .eq('empresa_id', empresaId)
          .ilike(nameField, '%$query%')
          .limit(10);
      return (rows as List)
          .map((r) => {
                'id': r['id'] as String,
                'nombre': r[nameField]?.toString() ?? r['id'] as String,
              })
          .toList();
    } catch (_) {
      return [];
    }
  }
}

final archivosAdminProvider =
    AsyncNotifierProvider<ArchivosAdminNotifier, void>(
        ArchivosAdminNotifier.new);
