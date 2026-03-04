// Cliente TUS 1.0.0 de bajo nivel para Supabase Storage.
//
// Implementa los tres métodos del protocolo TUS:
//   POST  /storage/v1/upload/resumable  → obtener Location (upload URL)
//   PATCH {uploadUrl}                  → subir chunks
//   HEAD  {uploadUrl}                  → consultar offset actual
//
// Uso típico:
//   final client = TusClient();
//   final url = await client.create(endpoint: ..., token: ..., ...);
//   await client.patch(uploadUrl: url, token: ..., bytes: ..., startOffset: 0);
//
// Para tests, inyectar un MockClient:
//   final client = TusClient(httpClient: MockClient(...));

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import 'models.dart';

/// Tamaño de chunk para Supabase Storage (fijo en 6 MB por requerimiento del servidor).
const int kTusChunkSize = 6 * 1024 * 1024;

/// Versión del protocolo TUS implementada.
const String kTusVersion = '1.0.0';

/// Cliente TUS de bajo nivel con HTTP client inyectable.
///
/// Cada instancia mantiene su propio [http.Client]. Para inyectar un
/// [MockClient] en tests, usar el constructor con parámetro `httpClient`.
class TusClient {
  final http.Client _http;

  TusClient({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  // -------------------------------------------------------------------------
  // POST — crear sesión de upload
  // -------------------------------------------------------------------------

  /// Crea una nueva sesión TUS y devuelve la URL de upload (Location header).
  ///
  /// [endpoint] — `{supabaseUrl}/storage/v1/upload/resumable`
  /// [token] — JWT de acceso (Authorization: Bearer)
  /// [bucket] — nombre del bucket en Supabase Storage
  /// [objectName] — path del objeto dentro del bucket
  /// [mimeType] — Content-Type del archivo
  /// [totalBytes] — tamaño total del archivo en bytes
  ///
  /// Supabase puede devolver una Location relativa; esta función la convierte
  /// a URL absoluta automáticamente.
  Future<String> create({
    required String endpoint,
    required String token,
    required String bucket,
    required String objectName,
    required String mimeType,
    required int totalBytes,
  }) async {
    final metadata = buildMetadata({
      'filename': objectName.split('/').last,
      'bucketName': bucket,
      'objectName': objectName,
      'contentType': mimeType,
      'cacheControl': '3600',
    });

    final response = await _http.post(
      Uri.parse(endpoint),
      headers: {
        'Authorization': 'Bearer $token',
        'tus-resumable': kTusVersion,
        'upload-length': '$totalBytes',
        'upload-metadata': metadata,
        'x-upsert': 'true',
      },
    );

    if (response.statusCode != 201) {
      throw UploadException(
        'TUS create falló (${response.statusCode}): ${response.body}',
      );
    }

    final location = response.headers['location'];
    if (location == null) throw const UploadException('TUS: header Location ausente');

    // Supabase puede devolver path relativo → convertir a URL absoluta
    if (location.startsWith('http')) return location;
    final uri = Uri.parse(endpoint);
    return '${uri.scheme}://${uri.host}$location';
  }

  // -------------------------------------------------------------------------
  // PATCH — subir chunks
  // -------------------------------------------------------------------------

  /// Sube [bytes] en chunks de [kTusChunkSize] bytes comenzando desde [startOffset].
  ///
  /// Emite [UploadProgress] en [progressController] después de cada chunk.
  /// Si [cancelToken] está cancelado antes de un chunk, lanza [UploadException].
  Future<void> patch({
    required String uploadUrl,
    required String token,
    required Uint8List bytes,
    required int startOffset,
    StreamController<UploadProgress>? progressController,
    UploadCancelToken? cancelToken,
  }) async {
    int offset = startOffset;
    final total = bytes.length;

    // Emitir progreso inicial si estamos reanudando
    if (offset > 0) {
      progressController?.add(UploadProgress(bytesUploaded: offset, totalBytes: total));
    }

    while (offset < total) {
      if (cancelToken?.isCancelled == true) {
        throw const UploadException('Upload cancelado por el usuario');
      }

      final end = (offset + kTusChunkSize).clamp(0, total);
      final chunk = bytes.sublist(offset, end);

      final response = await _http.patch(
        Uri.parse(uploadUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'tus-resumable': kTusVersion,
          'content-type': 'application/offset+octet-stream',
          'upload-offset': '$offset',
          'content-length': '${chunk.length}',
        },
        body: chunk,
      );

      if (response.statusCode != 204) {
        throw UploadException(
          'TUS patch falló en offset $offset (${response.statusCode}): ${response.body}',
        );
      }

      offset = int.tryParse(response.headers['upload-offset'] ?? '') ?? end;

      progressController?.add(UploadProgress(bytesUploaded: offset, totalBytes: total));
    }
  }

  // -------------------------------------------------------------------------
  // HEAD — consultar offset actual
  // -------------------------------------------------------------------------

  /// Consulta el offset que tiene el servidor para [uploadUrl].
  ///
  /// Retorna `null` si el upload no existe, expiró (>24h), o hay error de red.
  /// Nunca lanza excepción.
  Future<int?> head(String uploadUrl, String token) async {
    try {
      final response = await _http.head(
        Uri.parse(uploadUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'tus-resumable': kTusVersion,
        },
      );
      if (response.statusCode != 200) return null;
      return int.tryParse(response.headers['upload-offset'] ?? '');
    } catch (_) {
      return null;
    }
  }

  // -------------------------------------------------------------------------
  // Helper estático
  // -------------------------------------------------------------------------

  /// Construye el header `upload-metadata` en formato TUS.
  ///
  /// Formato: `key base64(value), key2 base64(value2), ...`
  @visibleForTesting
  static String buildMetadata(Map<String, String> fields) => fields.entries
      .map((e) => '${e.key} ${base64.encode(utf8.encode(e.value))}')
      .join(',');
}
