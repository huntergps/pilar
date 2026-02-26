// StorageService — gestión de archivos con Supabase Storage.
//
// Responsabilidades:
//   · logos    → bucket público (CDN, image transforms, 2 MB)
//   · avatares → bucket privado (signed URL 24 h, 2 MB)
//   · adjuntos → signed URL genérica (delegado al bucket adjuntos de UploadService)
//
// Image transforms (solo buckets públicos):
//   {supabaseUrl}/storage/v1/render/image/public/{bucket}/{path}?width=W&quality=Q&format=webp
//
// Paths:
//   logos:    {empresa_id}/logo.{ext}     (upsert — sobreescribe el anterior)
//   avatares: {user_id}/avatar.{ext}      (upsert)

import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

const _kBucketLogos    = 'logos';
const _kBucketAvatares = 'avatares';

/// Detecta el MIME type por extensión. Solo image types necesarios aquí.
String _mimeForImage(String fileName) {
  final ext = fileName.split('.').last.toLowerCase();
  const map = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'svg': 'image/svg+xml',
  };
  return map[ext] ?? 'application/octet-stream';
}

/// Excepción tipada para errores de Storage.
class StorageException implements Exception {
  final String message;
  const StorageException(this.message);
  @override
  String toString() => 'StorageException: $message';
}

abstract final class StorageService {
  // URL base cacheada — se carga una vez con SupabaseConfigService.load()
  static String? _baseUrl;

  static Future<String> _getBaseUrl() async =>
      _baseUrl ??= (await SupabaseConfigService.load()).url;

  // ---------------------------------------------------------------------------
  // Logos de empresa — públicos, CDN, image transforms
  // ---------------------------------------------------------------------------

  /// Sube el logo de [empresaId] al bucket `logos`.
  ///
  /// Path: `{empresaId}/logo.{ext}` (upsert — sobreescribe el logo anterior).
  /// Actualiza `empresas.logo_url` via RPC y devuelve la URL pública CDN.
  ///
  /// Lanza [StorageException] si el archivo no es una imagen válida.
  static Future<String> uploadLogo({
    required PlatformFile file,
    required String empresaId,
  }) async {
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw const StorageException('Archivo vacío o no se pudo leer');
    }

    final ext = file.name.split('.').last.toLowerCase();
    if (!{'jpg', 'jpeg', 'png', 'webp', 'svg'}.contains(ext)) {
      throw const StorageException(
          'Solo se permiten imágenes: JPG, PNG, WebP o SVG');
    }

    final path = '$empresaId/logo.$ext';
    final mime = _mimeForImage(file.name);

    await Supabase.instance.client.storage.from(_kBucketLogos).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mime, upsert: true),
        );

    final publicUrl = Supabase.instance.client.storage
        .from(_kBucketLogos)
        .getPublicUrl(path);

    // Guardar logo_url en la tabla empresas
    await Supabase.instance.client.rpc('set_logo_empresa', params: {
      'p_empresa_id': empresaId,
      'p_logo_url': publicUrl,
    });

    return publicUrl;
  }

  /// Construye la URL de image transform (resize + compresión) para un logo.
  ///
  /// Supabase CDN transforma la imagen on-the-fly: solo funciona para el
  /// bucket `logos` (público). Devuelve null si [logoUrl] es nulo/vacío.
  static Future<String?> logoTransformUrl(
    String? logoUrl, {
    int width = 200,
    int quality = 85,
    String format = 'webp',
  }) async {
    if (logoUrl == null || logoUrl.isEmpty) return null;

    // Extraer el storagePath de la URL completa
    final marker = '/public/$_kBucketLogos/';
    final idx = logoUrl.indexOf(marker);
    if (idx == -1) return logoUrl; // URL externa, devolver sin modificar

    final storagePath = logoUrl.substring(idx + marker.length);
    final base = await _getBaseUrl();
    return '$base/storage/v1/render/image/public/$_kBucketLogos/$storagePath'
        '?width=$width&quality=$quality&format=$format';
  }

  // ---------------------------------------------------------------------------
  // Avatares de usuario — privados, signed URL
  // ---------------------------------------------------------------------------

  /// Sube el avatar de [userId] al bucket `avatares`.
  ///
  /// Path: `{userId}/avatar.{ext}` (upsert).
  /// Devuelve una signed URL válida por 24 horas.
  static Future<String> uploadAvatar({
    required PlatformFile file,
    required String userId,
  }) async {
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw const StorageException('Archivo vacío o no se pudo leer');
    }

    final ext = file.name.split('.').last.toLowerCase();
    if (!{'jpg', 'jpeg', 'png', 'webp'}.contains(ext)) {
      throw const StorageException('Solo se permiten JPG, PNG o WebP');
    }

    final path = '$userId/avatar.$ext';
    final mime = _mimeForImage(file.name);

    await Supabase.instance.client.storage.from(_kBucketAvatares).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mime, upsert: true),
        );

    return Supabase.instance.client.storage
        .from(_kBucketAvatares)
        .createSignedUrl(path, 86400); // 24 horas
  }

  /// Obtiene la signed URL del avatar del [userId].
  ///
  /// Intenta recuperar el archivo listando el directorio del usuario.
  /// Devuelve null si no tiene avatar o hay un error.
  static Future<String?> avatarSignedUrl(
    String userId, {
    int expiresInSeconds = 3600,
  }) async {
    try {
      final files = await Supabase.instance.client.storage
          .from(_kBucketAvatares)
          .list(path: userId);

      if (files.isEmpty) return null;

      // El directorio del usuario tiene un único archivo (avatar)
      final fileName = files.first.name;
      return await Supabase.instance.client.storage
          .from(_kBucketAvatares)
          .createSignedUrl('$userId/$fileName', expiresInSeconds);
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Signed URL genérica — adjuntos privados u otros buckets
  // ---------------------------------------------------------------------------

  /// Genera una signed URL temporal para [storagePath] en [bucket].
  ///
  /// Delega en Supabase Storage. Devuelve null si hay error.
  static Future<String?> signedUrl(
    String storagePath, {
    String bucket = 'adjuntos',
    int expiresInSeconds = 3600,
  }) async {
    try {
      return await Supabase.instance.client.storage
          .from(bucket)
          .createSignedUrl(storagePath, expiresInSeconds);
    } catch (_) {
      return null;
    }
  }
}
