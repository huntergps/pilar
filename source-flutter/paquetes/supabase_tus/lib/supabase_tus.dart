/// TUS resumable upload client for Supabase Storage.
///
/// Exports:
/// - [TusClient]          — low-level TUS protocol (POST/PATCH/HEAD)
/// - [SupabaseTusUploader] — high-level uploader with resume + progress
/// - [UploadProgress]     — progress data (bytesUploaded, totalBytes, fraction, label)
/// - [UploadCancelToken]  — cancellation token
/// - [UploadResult]       — upload result (storagePath, mimeType, tamanioBytes, nombreOriginal)
/// - [UploadException]    — typed exception
/// - [guessMime]          — MIME type detection by file extension
/// - [sanitizeName]       — sanitize filename for Storage (removes unsafe chars)
/// - [kTusChunkSize]      — 6 MB chunk size constant
/// - [kTusVersion]        — TUS protocol version ('1.0.0')
library supabase_tus;

export 'src/models.dart';
export 'src/tus_client.dart';
export 'src/tus_uploader.dart';
