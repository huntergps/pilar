// Servicio de uploads con protocolo TUS (resumable) para Supabase Storage.
//
// Supabase Storage v3 soporta TUS en /storage/v1/upload/resumable.
// El chunk size es fijo: 6MB (requerido por Supabase).
//
// Flujo de un upload nuevo:
//   POST /storage/v1/upload/resumable  →  Location: {uploadUrl}
//   PATCH {uploadUrl} (chunk 1, 6MB)  →  Upload-Offset: 6291456
//   PATCH {uploadUrl} (chunk 2, 6MB)  →  Upload-Offset: 12582912
//   ...hasta totalBytes
//
// Resume (upload interrumpido <24h):
//   HEAD {uploadUrl}  →  Upload-Offset: {offset}   (offset actual en el servidor)
//   PATCH {uploadUrl} desde ese offset
//
// El uploadUrl se guarda en SharedPreferences con clave hash(storagePath)
// para poder reanudar si la app se cierra.

import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

// TUS spec: chunk size fijo en 6MB para Supabase
const int _kChunkSize = 6 * 1024 * 1024;
const String _kBucket  = 'adjuntos';
const String _kTusVer  = '1.0.0';

// ---------------------------------------------------------------------------
// Tipos públicos
// ---------------------------------------------------------------------------

/// Progreso de un upload en curso.
class UploadProgress {
  final int bytesUploaded;
  final int totalBytes;

  const UploadProgress({
    required this.bytesUploaded,
    required this.totalBytes,
  });

  double get fraction => totalBytes > 0 ? bytesUploaded / totalBytes : 0.0;

  /// "1.4 MB / 8.0 MB"
  String get label => '${_fmt(bytesUploaded)} / ${_fmt(totalBytes)}';

  static String _fmt(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}

/// Token para cancelar un upload en progreso desde la UI.
class UploadCancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// Resultado de un upload exitoso.
/// Pasar estos valores a la RPC `registrar_adjunto`.
class UploadResult {
  final String storagePath;
  final String mimeType;
  final int tamanioBytes;
  final String nombreOriginal;

  const UploadResult({
    required this.storagePath,
    required this.mimeType,
    required this.tamanioBytes,
    required this.nombreOriginal,
  });
}

/// Excepción tipada para errores de upload.
class UploadException implements Exception {
  final String message;
  const UploadException(this.message);

  @override
  String toString() => 'UploadException: $message';
}

// ---------------------------------------------------------------------------
// UploadService
// ---------------------------------------------------------------------------

/// Servicio genérico de adjuntos con soporte de resumable uploads (TUS).
///
/// Uso típico desde un widget:
/// ```dart
/// final cancelToken = UploadCancelToken();
/// final progressCtrl = StreamController<UploadProgress>();
///
/// final file = await UploadService.pickFile();
/// if (file == null) return;
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
  // ---------------------------------------------------------------------------
  // HTTP client injectable (permite MockClient en tests)
  // ---------------------------------------------------------------------------

  static http.Client _client = http.Client();

  /// Reemplaza el cliente HTTP por uno de test (MockClient).
  /// Llamar en setUp() del test.
  @visibleForTesting
  static void useTestClient(http.Client client) => _client = client;

  /// Restaura el cliente HTTP por defecto.
  /// Llamar en tearDown() del test.
  @visibleForTesting
  static void resetClient() => _client = http.Client();

  // -------------------------------------------------------------------------
  // Selección de archivo
  // -------------------------------------------------------------------------

  /// Abre el file picker y devuelve el archivo seleccionado.
  ///
  /// [allowedExtensions] — lista de extensiones sin punto ('pdf', 'jpg').
  /// Si es null, permite cualquier tipo.
  static Future<PlatformFile?> pickFile({
    List<String>? allowedExtensions,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: allowedExtensions != null ? FileType.custom : FileType.any,
      allowedExtensions: allowedExtensions,
      withData: true, // bytes disponibles en todas las plataformas (web ✓)
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
  /// **Resume automático:** si el upload fue interrumpido (en las últimas 24h),
  /// reanuda desde el último offset exitoso sin necesidad de intervención.
  ///
  /// Lanza [UploadException] si falla irrecuperablemente.
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
  /// Permite testear sin inicializar Supabase.
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

  // -------------------------------------------------------------------------
  // Core — lógica compartida
  // -------------------------------------------------------------------------

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

    final mimeType    = guessMime(file.name);
    final ts          = DateTime.now().millisecondsSinceEpoch;
    final safeName    = sanitizeName(file.name);
    final storagePath = '$empresaId/$entidadTipo/$entidadId/${ts}_$safeName';
    final tusEndpoint = '$supabaseUrl/storage/v1/upload/resumable';

    // ----- Intentar reanudar -----
    final prefs    = await SharedPreferences.getInstance();
    final cacheKey = 'tus_url_${storagePath.hashCode}';
    String? uploadUrl = prefs.getString(cacheKey);

    if (uploadUrl != null) {
      final offset = await tusHead(uploadUrl, token);
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
          nombreOriginal: file.name,
        );
      }
    }

    // ----- Crear nuevo upload si no hay reanudable -----
    if (uploadUrl == null) {
      uploadUrl = await tusCreate(
        endpoint: tusEndpoint,
        token: token,
        bucket: _kBucket,
        objectName: storagePath,
        mimeType: mimeType,
        totalBytes: bytes.length,
      );
      await prefs.setString(cacheKey, uploadUrl);
    }

    // ----- Subir chunks (desde offset actual del servidor) -----
    final startOffset = await tusHead(uploadUrl, token) ?? 0;
    await tusPatch(
      uploadUrl: uploadUrl,
      token: token,
      bytes: bytes,
      startOffset: startOffset,
      progressController: progressController,
      cancelToken: cancelToken,
    );

    await prefs.remove(cacheKey);

    return UploadResult(
      storagePath: storagePath,
      mimeType: mimeType,
      tamanioBytes: bytes.length,
      nombreOriginal: file.name,
    );
  }

  // -------------------------------------------------------------------------
  // URL firmada para previsualizar/descargar
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

  // -------------------------------------------------------------------------
  // TUS — métodos con @visibleForTesting para tests directos
  // -------------------------------------------------------------------------

  /// POST: crea el upload TUS y devuelve la Location URL.
  @visibleForTesting
  static Future<String> tusCreate({
    required String endpoint,
    required String token,
    required String bucket,
    required String objectName,
    required String mimeType,
    required int totalBytes,
  }) async {
    final metadata = buildTusMetadata({
      'filename'    : objectName.split('/').last,
      'bucketName'  : bucket,
      'objectName'  : objectName,
      'contentType' : mimeType,
      'cacheControl': '3600',
    });

    final response = await _client.post(
      Uri.parse(endpoint),
      headers: {
        'Authorization'  : 'Bearer $token',
        'tus-resumable'  : _kTusVer,
        'upload-length'  : '$totalBytes',
        'upload-metadata': metadata,
        'x-upsert'       : 'true',
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

  /// PATCH: sube los bytes en chunks de 6MB desde [startOffset].
  @visibleForTesting
  static Future<void> tusPatch({
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

      final end   = (offset + _kChunkSize).clamp(0, total);
      final chunk = bytes.sublist(offset, end);

      final response = await _client.patch(
        Uri.parse(uploadUrl),
        headers: {
          'Authorization'  : 'Bearer $token',
          'tus-resumable'  : _kTusVer,
          'content-type'   : 'application/offset+octet-stream',
          'upload-offset'  : '$offset',
          'content-length' : '${chunk.length}',
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

  /// HEAD: obtiene el offset actual del servidor para reanudar.
  /// Retorna null si el upload no existe o expiró (>24h).
  @visibleForTesting
  static Future<int?> tusHead(String uploadUrl, String token) async {
    try {
      final response = await _client.head(
        Uri.parse(uploadUrl),
        headers: {
          'Authorization' : 'Bearer $token',
          'tus-resumable' : _kTusVer,
        },
      );
      if (response.statusCode != 200) return null;
      return int.tryParse(response.headers['upload-offset'] ?? '');
    } catch (_) {
      return null;
    }
  }

  // -------------------------------------------------------------------------
  // Helpers — @visibleForTesting para tests unitarios puros
  // -------------------------------------------------------------------------

  /// Construye el header `upload-metadata` TUS.
  /// Formato: `key base64(value), key2 base64(value2), ...`
  @visibleForTesting
  static String buildTusMetadata(Map<String, String> fields) => fields.entries
      .map((e) => '${e.key} ${base64.encode(utf8.encode(e.value))}')
      .join(',');

  /// Sanitiza el nombre del archivo eliminando caracteres no seguros para Storage.
  @visibleForTesting
  static String sanitizeName(String name) =>
      name.replaceAll(RegExp(r'[^\w.\-]'), '_');

  /// Detecta el MIME type por extensión del archivo.
  @visibleForTesting
  static String guessMime(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return _mimeMap[ext] ?? 'application/octet-stream';
  }

  static const _mimeMap = <String, String>{
    'jpg' : 'image/jpeg', 'jpeg': 'image/jpeg',
    'png' : 'image/png',  'gif' : 'image/gif',
    'webp': 'image/webp', 'svg' : 'image/svg+xml',
    'pdf' : 'application/pdf',
    'doc' : 'application/msword',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls' : 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt' : 'application/vnd.ms-powerpoint',
    'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'txt' : 'text/plain', 'csv': 'text/csv',
    'zip' : 'application/zip',
    'xml' : 'application/xml',
  };
}
