// Providers de adjuntos (Foundation layer).
//
// Todos los providers son family por (entidadTipo, entidadId).
// No usa Brick: adjuntos se cargan on-demand cuando se abre la entidad.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/adjunto_model.dart';
import '../services/upload_service.dart';

// ---------------------------------------------------------------------------
// Providers de lectura
// ---------------------------------------------------------------------------

/// Lista de adjuntos activos para una entidad.
///
/// Uso: `ref.watch(adjuntosProvider(('factura', facturaId)))`
final adjuntosProvider = FutureProvider.family<List<AdjuntoItem>, (String, String)>(
  (ref, args) async {
    final (entidadTipo, entidadId) = args;
    final rows = await Supabase.instance.client
        .rpc('get_adjuntos', params: {
          'p_entidad_tipo': entidadTipo,
          'p_entidad_id': entidadId,
        })
        .select();

    return (rows as List<dynamic>)
        .map((r) => AdjuntoItem.fromJson(r as Map<String, dynamic>))
        .toList();
  },
);

/// Conteo de adjuntos — para badges sin cargar toda la lista.
///
/// Uso: `ref.watch(adjuntosCountProvider(('factura', facturaId)))`
final adjuntosCountProvider = FutureProvider.family<int, (String, String)>(
  (ref, args) async {
    final (entidadTipo, entidadId) = args;
    final result = await Supabase.instance.client
        .rpc('get_adjuntos_count', params: {
          'p_entidad_tipo': entidadTipo,
          'p_entidad_id': entidadId,
        });
    return (result as num?)?.toInt() ?? 0;
  },
);

// ---------------------------------------------------------------------------
// Notifier de operaciones (upload + eliminar + renombrar)
// ---------------------------------------------------------------------------

/// Estado del panel de adjuntos.
class AdjuntosState {
  final List<AdjuntoItem> items;
  final bool isLoading;
  final bool isUploading;
  final UploadProgress? uploadProgress;
  final String? error;

  const AdjuntosState({
    this.items = const [],
    this.isLoading = false,
    this.isUploading = false,
    this.uploadProgress,
    this.error,
  });

  AdjuntosState copyWith({
    List<AdjuntoItem>? items,
    bool? isLoading,
    bool? isUploading,
    UploadProgress? uploadProgress,
    Object? error = _sentinel,
  }) =>
      AdjuntosState(
        items: items ?? this.items,
        isLoading: isLoading ?? this.isLoading,
        isUploading: isUploading ?? this.isUploading,
        uploadProgress: uploadProgress,
        error: error == _sentinel ? this.error : error as String?,
      );
}

const _sentinel = Object();

/// Notifier para el panel de adjuntos de una entidad concreta.
///
/// Uso:
/// ```dart
/// final notifier = ref.read(
///   adjuntosNotifierProvider(('factura', facturaId)).notifier
/// );
/// await notifier.upload(empresaId: ..., cancelToken: ...);
/// await notifier.eliminar(adjuntoId: ...);
/// ```
class AdjuntosNotifier
    extends FamilyAsyncNotifier<AdjuntosState, (String, String)> {
  late String _entidadTipo;
  late String _entidadId;

  @override
  Future<AdjuntosState> build((String, String) arg) async {
    _entidadTipo = arg.$1;
    _entidadId   = arg.$2;
    return AdjuntosState(items: await _fetchItems(), isLoading: false);
  }

  // -------------------------------------------------------------------------
  // Upload
  // -------------------------------------------------------------------------

  /// Abre el picker, sube el archivo con TUS y registra en DB.
  /// Actualiza el estado con progreso en tiempo real.
  Future<void> upload({
    required String empresaId,
    List<String>? allowedExtensions,
    UploadCancelToken? cancelToken,
  }) async {
    final file = await UploadService.pickFile(
      allowedExtensions: allowedExtensions,
    );
    if (file == null) return;

    state = AsyncData(
      state.valueOrNull?.copyWith(isUploading: true, error: null) ??
          const AdjuntosState(isUploading: true),
    );

    try {
      final progressCtrl = StreamController<UploadProgress>();
      progressCtrl.stream.listen((p) {
        state = AsyncData(
          state.valueOrNull?.copyWith(
                isUploading: true,
                uploadProgress: p,
              ) ??
              AdjuntosState(isUploading: true, uploadProgress: p),
        );
      });

      final result = await UploadService.uploadResumable(
        file: file,
        empresaId: empresaId,
        entidadTipo: _entidadTipo,
        entidadId: _entidadId,
        progressController: progressCtrl,
        cancelToken: cancelToken,
      );

      await progressCtrl.close();

      // Registrar en DB
      await Supabase.instance.client.rpc('registrar_adjunto', params: {
        'p_empresa_id'      : empresaId,
        'p_entidad_tipo'    : _entidadTipo,
        'p_entidad_id'      : _entidadId,
        'p_nombre'          : result.nombreOriginal,
        'p_nombre_original' : result.nombreOriginal,
        'p_mime_type'       : result.mimeType,
        'p_tamanio_bytes'   : result.tamanioBytes,
        'p_storage_path'    : result.storagePath,
      });

      final updated = await _fetchItems();
      state = AsyncData(AdjuntosState(items: updated));
    } on UploadException catch (e) {
      state = AsyncData(
        state.valueOrNull?.copyWith(isUploading: false, error: e.message) ??
            AdjuntosState(error: e.message),
      );
    } catch (e) {
      state = AsyncData(
        state.valueOrNull?.copyWith(isUploading: false, error: e.toString()) ??
            AdjuntosState(error: e.toString()),
      );
    }
  }

  // -------------------------------------------------------------------------
  // Eliminar
  // -------------------------------------------------------------------------

  /// Soft delete en DB + elimina el archivo físico en Storage.
  Future<void> eliminar(String adjuntoId) async {
    final current = state.valueOrNull;
    if (current == null) return;

    final adjunto = current.items.firstWhere((a) => a.id == adjuntoId);

    // Soft delete en DB
    await Supabase.instance.client.rpc('eliminar_adjunto', params: {
      'p_adjunto_id': adjuntoId,
    });

    // Eliminar físico en Storage (best-effort)
    UploadService.deleteFromStorage(adjunto.storagePath).ignore();

    state = AsyncData(
      current.copyWith(
        items: current.items.where((a) => a.id != adjuntoId).toList(),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Renombrar
  // -------------------------------------------------------------------------

  /// Cambia el nombre visible sin afectar el archivo en Storage.
  Future<void> renombrar(String adjuntoId, String nuevoNombre) async {
    final current = state.valueOrNull;
    if (current == null) return;

    await Supabase.instance.client.rpc('renombrar_adjunto', params: {
      'p_adjunto_id': adjuntoId,
      'p_nombre'    : nuevoNombre,
    });

    state = AsyncData(
      current.copyWith(
        items: current.items
            .map((a) => a.id == adjuntoId
                ? AdjuntoItem(
                    id: a.id,
                    empresaId: a.empresaId,
                    entidadTipo: a.entidadTipo,
                    entidadId: a.entidadId,
                    nombre: nuevoNombre,
                    nombreOriginal: a.nombreOriginal,
                    mimeType: a.mimeType,
                    tamanioBytes: a.tamanioBytes,
                    storagePath: a.storagePath,
                    storageBucket: a.storageBucket,
                    descripcion: a.descripcion,
                    esPublico: a.esPublico,
                    subidoPor: a.subidoPor,
                    createdAt: a.createdAt,
                  )
                : a)
            .toList(),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Refresh
  // -------------------------------------------------------------------------

  Future<void> refresh() async {
    state = AsyncData(
      state.valueOrNull?.copyWith(isLoading: true) ??
          const AdjuntosState(isLoading: true),
    );
    final items = await _fetchItems();
    state = AsyncData(AdjuntosState(items: items));
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  Future<List<AdjuntoItem>> _fetchItems() async {
    final rows = await Supabase.instance.client
        .rpc('get_adjuntos', params: {
          'p_entidad_tipo': _entidadTipo,
          'p_entidad_id'  : _entidadId,
        })
        .select();

    return (rows as List<dynamic>)
        .map((r) => AdjuntoItem.fromJson(r as Map<String, dynamic>))
        .toList();
  }
}

/// Provider con operaciones completas (upload, eliminar, renombrar).
final adjuntosNotifierProvider = AsyncNotifierProvider.family<
    AdjuntosNotifier, AdjuntosState, (String, String)>(
  AdjuntosNotifier.new,
);
