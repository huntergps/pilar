// Tipos públicos del paquete supabase_tus.

/// Progreso de un upload en curso.
class UploadProgress {
  final int bytesUploaded;
  final int totalBytes;

  const UploadProgress({
    required this.bytesUploaded,
    required this.totalBytes,
  });

  double get fraction => totalBytes > 0 ? bytesUploaded / totalBytes : 0.0;

  /// Ejemplo: "1.4 MB / 8.0 MB"
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
class UploadResult {
  /// Path del objeto en Supabase Storage (relativo al bucket).
  final String storagePath;

  /// MIME type detectado por extensión.
  final String mimeType;

  /// Tamaño en bytes del archivo subido.
  final int tamanioBytes;

  /// Nombre original del archivo tal como lo seleccionó el usuario.
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
// Helpers de nombre y MIME
// ---------------------------------------------------------------------------

/// Sanitiza el nombre del archivo eliminando caracteres no seguros para
/// Supabase Storage (conserva letras, dígitos, `.` y `-`).
String sanitizeName(String name) => name.replaceAll(RegExp(r'[^\w.\-]'), '_');

/// Detecta el MIME type por extensión. Devuelve `application/octet-stream`
/// para extensiones desconocidas.
String guessMime(String fileName) {
  final ext = fileName.split('.').last.toLowerCase();
  return _mimeMap[ext] ?? 'application/octet-stream';
}

const _mimeMap = <String, String>{
  'jpg': 'image/jpeg', 'jpeg': 'image/jpeg',
  'png': 'image/png', 'gif': 'image/gif',
  'webp': 'image/webp', 'svg': 'image/svg+xml',
  'pdf': 'application/pdf',
  'doc': 'application/msword',
  'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'ppt': 'application/vnd.ms-powerpoint',
  'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'txt': 'text/plain', 'csv': 'text/csv',
  'zip': 'application/zip',
  'xml': 'application/xml',
};
