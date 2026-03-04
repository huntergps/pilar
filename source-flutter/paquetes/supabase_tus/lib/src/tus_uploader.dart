// SupabaseTusUploader — uploader de alto nivel sobre TusClient.
//
// Maneja:
//   · Resume automático (SharedPreferences guarda la upload URL)
//   · Progress streaming (StreamController<UploadProgress>)
//   · Cancelación (UploadCancelToken)
//
// Responsabilidades del CALLER (no del paquete):
//   · Construir storagePath (ej: "empresaId/tipo/entidadId/ts_nombre")
//   · Obtener accessToken (Supabase session)
//   · Obtener supabaseUrl (SupabaseConfig)
//   · Gestionar file picker (PlatformFile → Uint8List)

import 'dart:async';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'tus_client.dart';

/// Uploader de alto nivel para Supabase Storage con soporte de resume.
///
/// Ejemplo de uso:
/// ```dart
/// final uploader = SupabaseTusUploader();
///
/// final result = await uploader.upload(
///   bytes: file.bytes!,
///   fileName: file.name,
///   storagePath: '$empresaId/$tipo/$entidadId/${ts}_${sanitizeName(file.name)}',
///   supabaseUrl: 'https://xxxx.supabase.co',
///   accessToken: session.accessToken,
///   bucket: 'adjuntos',
///   progress: progressCtrl,
///   cancelToken: cancelToken,
/// );
/// ```
class SupabaseTusUploader {
  final TusClient _client;

  SupabaseTusUploader({TusClient? client}) : _client = client ?? TusClient();

  /// Sube [bytes] al bucket de Supabase Storage usando TUS.
  ///
  /// **Resume automático**: si el upload fue interrumpido en las últimas 24h,
  /// reanuda desde el último offset exitoso guardado en SharedPreferences.
  ///
  /// Lanza [UploadException] si el upload falla irrecuperablemente o si
  /// [bytes] está vacío.
  Future<UploadResult> upload({
    required Uint8List bytes,
    required String fileName,
    required String storagePath,
    required String supabaseUrl,
    required String accessToken,
    String bucket = 'adjuntos',
    StreamController<UploadProgress>? progress,
    UploadCancelToken? cancelToken,
  }) async {
    if (bytes.isEmpty) {
      throw const UploadException('Archivo vacío o no se pudo leer');
    }

    final mimeType = guessMime(fileName);
    final tusEndpoint = '$supabaseUrl/storage/v1/upload/resumable';

    // ----- Intentar reanudar -----
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'tus_url_${storagePath.hashCode}';
    String? uploadUrl = prefs.getString(cacheKey);

    if (uploadUrl != null) {
      final offset = await _client.head(uploadUrl, accessToken);
      if (offset == null) {
        // Expiró (>24h) → crear de nuevo
        uploadUrl = null;
        await prefs.remove(cacheKey);
      } else if (offset >= bytes.length) {
        // Ya completado en un intento anterior
        await prefs.remove(cacheKey);
        return UploadResult(
          storagePath: storagePath,
          mimeType: mimeType,
          tamanioBytes: bytes.length,
          nombreOriginal: fileName,
        );
      }
    }

    // ----- Crear nuevo upload si no hay reanudable -----
    if (uploadUrl == null) {
      uploadUrl = await _client.create(
        endpoint: tusEndpoint,
        token: accessToken,
        bucket: bucket,
        objectName: storagePath,
        mimeType: mimeType,
        totalBytes: bytes.length,
      );
      await prefs.setString(cacheKey, uploadUrl);
    }

    // ----- Subir chunks desde el offset actual del servidor -----
    final startOffset = await _client.head(uploadUrl, accessToken) ?? 0;
    await _client.patch(
      uploadUrl: uploadUrl,
      token: accessToken,
      bytes: bytes,
      startOffset: startOffset,
      progressController: progress,
      cancelToken: cancelToken,
    );

    await prefs.remove(cacheKey);

    return UploadResult(
      storagePath: storagePath,
      mimeType: mimeType,
      tamanioBytes: bytes.length,
      nombreOriginal: fileName,
    );
  }
}
