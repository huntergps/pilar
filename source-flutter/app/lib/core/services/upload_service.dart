// Servicio de adjuntos con uploads resumables (TUS) para Supabase Storage.
//
// Esta clase es un wrapper fino sobre el paquete `supabase_tus`.
// Responsabilidades propias de PILAR:
//   · Selección de archivo via file_picker
//   · Obtención de la sesión activa (Supabase.instance)
//   · Construcción del storagePath: {empresaId}/{tipo}/{entidadId}/{ts}_{nombre}
//   · Signed URLs y eliminación de archivos (supabase_flutter Storage API)

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:supabase_tus/supabase_tus.dart';

import '../config/supabase_config.dart';

// Re-exportar los tipos del paquete para que el código existente no cambie.
export 'package:supabase_tus/supabase_tus.dart'
    show
        UploadProgress,
        UploadCancelToken,
        UploadResult,
        UploadException,
        guessMime,
        sanitizeName;

const String _kBucket = 'adjuntos';

/// Servicio de adjuntos con TUS resumable uploads para Supabase Storage.
///
/// Uso típico:
/// ```dart
/// final file = await UploadService.pickFile();
/// if (file == null) return;
///
/// final cancelToken = UploadCancelToken();
/// final progressCtrl = StreamController<UploadProgress>();
///
/// final result = await UploadService.uploadResumable(
///   file: file,
///   empresaId: empresaId,
///   entidadTipo: 'factura',
///   entidadId: facturaId,
///   progressController: progressCtrl,
///   cancelToken: cancelToken,
/// );
/// ```
abstract final class UploadService {
  static SupabaseTusUploader _uploader = SupabaseTusUploader();

  /// Reemplaza el uploader por uno con MockClient (solo para tests).
  @visibleForTesting
  static void useTestClient(http.Client client) {
    _uploader = SupabaseTusUploader(client: TusClient(httpClient: client));
  }

  /// Restaura el uploader por defecto.
  @visibleForTesting
  static void resetClient() => _uploader = SupabaseTusUploader();

  // -------------------------------------------------------------------------
  // Selección de archivo
  // -------------------------------------------------------------------------

  /// Abre el file picker y devuelve el archivo seleccionado.
  static Future<PlatformFile?> pickFile({
    List<String>? allowedExtensions,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: allowedExtensions != null ? FileType.custom : FileType.any,
      allowedExtensions: allowedExtensions,
      withData: true,
    );
    return result?.files.firstOrNull;
  }

  // -------------------------------------------------------------------------
  // Upload TUS (resumable) — producción
  // -------------------------------------------------------------------------

  /// Sube [file] al bucket "adjuntos" usando el protocolo TUS.
  ///
  /// **Path en Storage:**
  /// `{empresaId}/{entidadTipo}/{entidadId}/{timestamp}_{nombreSanitizado}`
  ///
  /// **Resume automático:** reanuda desde el último offset exitoso si el
  /// upload fue interrumpido en las últimas 24h.
  static Future<UploadResult> uploadResumable({
    required PlatformFile file,
    required String empresaId,
    required String entidadTipo,
    required String entidadId,
    StreamController<UploadProgress>? progressController,
    UploadCancelToken? cancelToken,
  }) async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) throw const UploadException('Sin sesión activa');

    final config = await SupabaseConfigService.load();

    return _uploadCore(
      file: file,
      empresaId: empresaId,
      entidadTipo: entidadTipo,
      entidadId: entidadId,
      token: session.accessToken,
      supabaseUrl: config.url,
      progressController: progressController,
      cancelToken: cancelToken,
    );
  }

  // -------------------------------------------------------------------------
  // Upload TUS — punto de entrada para tests (sin Supabase.instance)
  // -------------------------------------------------------------------------

  /// Igual que [uploadResumable] pero recibe token y URL directamente.
  @visibleForTesting
  static Future<UploadResult> uploadResumableRaw({
    required PlatformFile file,
    required String empresaId,
    required String entidadTipo,
    required String entidadId,
    required String token,
    required String supabaseUrl,
    StreamController<UploadProgress>? progressController,
    UploadCancelToken? cancelToken,
  }) =>
      _uploadCore(
        file: file,
        empresaId: empresaId,
        entidadTipo: entidadTipo,
        entidadId: entidadId,
        token: token,
        supabaseUrl: supabaseUrl,
        progressController: progressController,
        cancelToken: cancelToken,
      );

  static Future<UploadResult> _uploadCore({
    required PlatformFile file,
    required String empresaId,
    required String entidadTipo,
    required String entidadId,
    required String token,
    required String supabaseUrl,
    StreamController<UploadProgress>? progressController,
    UploadCancelToken? cancelToken,
  }) async {
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw const UploadException('Archivo vacío o no se pudo leer');
    }

    final ts = DateTime.now().millisecondsSinceEpoch;
    final safeName = sanitizeName(file.name);
    final storagePath = '$empresaId/$entidadTipo/$entidadId/${ts}_$safeName';

    return _uploader.upload(
      bytes: bytes,
      fileName: file.name,
      storagePath: storagePath,
      supabaseUrl: supabaseUrl,
      accessToken: token,
      bucket: _kBucket,
      progress: progressController,
      cancelToken: cancelToken,
    );
  }

  // -------------------------------------------------------------------------
  // URL firmada y eliminación
  // -------------------------------------------------------------------------

  /// Genera una URL firmada temporal para acceder al archivo.
  static Future<String?> createSignedUrl(
    String storagePath, {
    int expiresInSeconds = 3600,
  }) async {
    try {
      return await Supabase.instance.client.storage
          .from(_kBucket)
          .createSignedUrl(storagePath, expiresInSeconds);
    } catch (_) {
      return null;
    }
  }

  /// Elimina el archivo físico del bucket Storage.
  static Future<void> deleteFromStorage(String storagePath) async {
    await Supabase.instance.client.storage.from(_kBucket).remove([storagePath]);
  }
}
