// Tests para el paquete supabase_tus.
//
// Cubre:
//   · Tipos públicos (UploadProgress, UploadCancelToken, UploadException)
//   · Helpers (guessMime, sanitizeName, TusClient.buildMetadata)
//   · Protocolo TUS (TusClient.create, .patch, .head) via MockClient
//   · SupabaseTusUploader.upload — flujo completo con SharedPreferences mock

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:supabase_tus/supabase_tus.dart';

// ---------------------------------------------------------------------------
// Helpers de test
// ---------------------------------------------------------------------------

MockClient httpMock(Future<http.Response> Function(http.Request) handler) =>
    MockClient(handler);

Uint8List bytes1KB() => Uint8List(1024);
Uint8List bytes6MB() => Uint8List(6 * 1024 * 1024);
Uint8List bytes10MB() => Uint8List(10 * 1024 * 1024);

const kToken = 'test-bearer-token';
const kSupabaseUrl = 'https://testproject.supabase.co';
const kUploadBase = '$kSupabaseUrl/storage/v1/upload/resumable';
const kUploadId = 'abc123-upload-id';
const kUploadUrl = '$kUploadBase/$kUploadId';

/// MockClient que simula un servidor TUS exitoso.
/// POST  → 201 con Location: {kUploadUrl}
/// HEAD  → 200 con Upload-Offset: {currentOffset}
/// PATCH → 204 con Upload-Offset actualizado
MockClient tusServerMock({int initialOffset = 0}) {
  int serverOffset = initialOffset;
  return httpMock((req) async {
    switch (req.method) {
      case 'POST':
        return http.Response('', 201, headers: {'location': kUploadUrl});
      case 'HEAD':
        return http.Response('', 200,
            headers: {'upload-offset': '$serverOffset'});
      case 'PATCH':
        serverOffset += req.bodyBytes.length;
        return http.Response('', 204,
            headers: {'upload-offset': '$serverOffset'});
      default:
        return http.Response('Not found', 404);
    }
  });
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // ==========================================================================
  // 1. UploadProgress
  // ==========================================================================

  group('UploadProgress —', () {
    test('fraction = bytesUploaded / totalBytes', () {
      const p = UploadProgress(bytesUploaded: 3, totalBytes: 10);
      expect(p.fraction, closeTo(0.3, 0.001));
    });

    test('fraction = 0.0 cuando totalBytes = 0 (sin división por cero)', () {
      const p = UploadProgress(bytesUploaded: 0, totalBytes: 0);
      expect(p.fraction, 0.0);
    });

    test('fraction = 1.0 cuando está completo', () {
      const p = UploadProgress(bytesUploaded: 512, totalBytes: 512);
      expect(p.fraction, 1.0);
    });

    test('label formatea bytes < 1 KB', () {
      const p = UploadProgress(bytesUploaded: 512, totalBytes: 1000);
      expect(p.label, '512 B / 1000 B');
    });

    test('label formatea KB', () {
      const p = UploadProgress(bytesUploaded: 1024, totalBytes: 2048);
      expect(p.label, '1.0 KB / 2.0 KB');
    });

    test('label formatea MB', () {
      const p = UploadProgress(
        bytesUploaded: 1024 * 1024,
        totalBytes: 5 * 1024 * 1024,
      );
      expect(p.label, '1.0 MB / 5.0 MB');
    });
  });

  // ==========================================================================
  // 2. UploadCancelToken
  // ==========================================================================

  group('UploadCancelToken —', () {
    test('inicia sin cancelar', () {
      expect(UploadCancelToken().isCancelled, false);
    });

    test('cancel() establece isCancelled = true', () {
      final token = UploadCancelToken();
      token.cancel();
      expect(token.isCancelled, true);
    });

    test('cancel() es idempotente', () {
      final token = UploadCancelToken();
      token.cancel();
      token.cancel();
      expect(token.isCancelled, true);
    });
  });

  // ==========================================================================
  // 3. UploadException
  // ==========================================================================

  group('UploadException —', () {
    test('guarda el mensaje', () {
      const e = UploadException('error de red');
      expect(e.message, 'error de red');
    });

    test('toString incluye el mensaje', () {
      const e = UploadException('servidor no disponible');
      expect(e.toString(), contains('servidor no disponible'));
    });
  });

  // ==========================================================================
  // 4. guessMime
  // ==========================================================================

  group('guessMime —', () {
    test('jpg → image/jpeg', () => expect(guessMime('foto.jpg'), 'image/jpeg'));
    test('JPEG en mayúsculas → image/jpeg',
        () => expect(guessMime('foto.JPEG'), 'image/jpeg'));
    test('png → image/png', () => expect(guessMime('imagen.png'), 'image/png'));
    test('gif → image/gif', () => expect(guessMime('anim.gif'), 'image/gif'));
    test('pdf → application/pdf',
        () => expect(guessMime('factura.pdf'), 'application/pdf'));
    test('docx → MIME de Word',
        () => expect(guessMime('reporte.docx'), contains('wordprocessingml')));
    test('xlsx → MIME de Excel',
        () => expect(guessMime('datos.xlsx'), contains('spreadsheetml')));
    test('csv → text/csv',
        () => expect(guessMime('export.csv'), 'text/csv'));
    test('zip → application/zip',
        () => expect(guessMime('archivo.zip'), 'application/zip'));
    test('extensión desconocida → application/octet-stream',
        () => expect(guessMime('raro.xyz'), 'application/octet-stream'));
    test('sin extensión → application/octet-stream',
        () => expect(guessMime('archivo'), 'application/octet-stream'));
  });

  // ==========================================================================
  // 5. sanitizeName
  // ==========================================================================

  group('sanitizeName —', () {
    test('nombre limpio sin cambios',
        () => expect(sanitizeName('factura.pdf'), 'factura.pdf'));
    test('espacios → guión bajo',
        () => expect(sanitizeName('mi factura 2026.pdf'), 'mi_factura_2026.pdf'));
    test('caracteres especiales → guión bajo',
        () => expect(sanitizeName(r'a@b#c$d.pdf'), 'a_b_c_d.pdf'));
    test('guión y punto se conservan',
        () => expect(sanitizeName('doc-final.v2.pdf'), 'doc-final.v2.pdf'));
    test('tildes → guión bajo',
        () => expect(sanitizeName('cotización.pdf'), 'cotizaci_n.pdf'));
  });

  // ==========================================================================
  // 6. TusClient.buildMetadata
  // ==========================================================================

  group('TusClient.buildMetadata —', () {
    test('formato: "key base64(value)"', () {
      final meta = TusClient.buildMetadata({'filename': 'test.pdf'});
      final expected = 'filename ${base64.encode(utf8.encode('test.pdf'))}';
      expect(meta, expected);
    });

    test('múltiples campos separados por coma', () {
      final meta = TusClient.buildMetadata({
        'bucketName': 'adjuntos',
        'contentType': 'application/pdf',
      });
      expect(meta, contains(','));
      expect(meta, contains('bucketName '));
      expect(meta, contains('contentType '));
    });

    test('los valores son base64 decodificable', () {
      final meta = TusClient.buildMetadata({
        'objectName': 'empresa/factura/abc/file with spaces.pdf',
      });
      final b64 = meta.split(' ').last;
      expect(() => base64.decode(b64), returnsNormally);
      expect(
        utf8.decode(base64.decode(b64)),
        'empresa/factura/abc/file with spaces.pdf',
      );
    });

    test('campo vacío se codifica como base64 vacío', () {
      final meta = TusClient.buildMetadata({'descripcion': ''});
      final b64 = meta.split(' ').last;
      expect(utf8.decode(base64.decode(b64)), '');
    });
  });

  // ==========================================================================
  // 7. TusClient.create — POST
  // ==========================================================================

  group('TusClient.create —', () {
    test('envía Authorization, tus-resumable, upload-length, x-upsert', () async {
      late http.Request captured;
      final client = TusClient(
        httpClient: httpMock((req) async {
          captured = req;
          return http.Response('', 201, headers: {'location': kUploadUrl});
        }),
      );

      await client.create(
        endpoint: kUploadBase,
        token: kToken,
        bucket: 'adjuntos',
        objectName: 'e-001/factura/f-001/doc.pdf',
        mimeType: 'application/pdf',
        totalBytes: 4096,
      );

      expect(captured.headers['Authorization'], 'Bearer $kToken');
      expect(captured.headers['tus-resumable'], '1.0.0');
      expect(captured.headers['upload-length'], '4096');
      expect(captured.headers['x-upsert'], 'true');
      expect(captured.headers['upload-metadata'], isNotEmpty);
    });

    test('upload-metadata contiene filename, bucketName, objectName, contentType', () async {
      late http.Request captured;
      final client = TusClient(
        httpClient: httpMock((req) async {
          captured = req;
          return http.Response('', 201, headers: {'location': kUploadUrl});
        }),
      );

      await client.create(
        endpoint: kUploadBase,
        token: kToken,
        bucket: 'adjuntos',
        objectName: 'e-001/factura/f-001/factura.pdf',
        mimeType: 'application/pdf',
        totalBytes: 100,
      );

      final metaRaw = captured.headers['upload-metadata']!;
      final pairs = metaRaw.split(',').map((s) => s.trim());
      final decoded = {
        for (final p in pairs)
          p.split(' ').first: utf8.decode(base64.decode(p.split(' ').last)),
      };

      expect(decoded['bucketName'], 'adjuntos');
      expect(decoded['objectName'], 'e-001/factura/f-001/factura.pdf');
      expect(decoded['filename'], 'factura.pdf');
      expect(decoded['contentType'], 'application/pdf');
    });

    test('convierte Location relativa a URL absoluta', () async {
      final client = TusClient(
        httpClient: httpMock((_) async => http.Response('', 201,
            headers: {'location': '/storage/v1/upload/resumable/$kUploadId'})),
      );

      final url = await client.create(
        endpoint: kUploadBase,
        token: kToken,
        bucket: 'adjuntos',
        objectName: 'e/t/i/file.pdf',
        mimeType: 'application/pdf',
        totalBytes: 100,
      );

      expect(url, startsWith('https://testproject.supabase.co'));
      expect(url, contains(kUploadId));
    });

    test('retorna Location absoluta sin modificar', () async {
      final client = TusClient(
        httpClient: httpMock((_) async => http.Response('', 201,
            headers: {'location': 'https://cdn.example.com/upload/xyz'})),
      );

      final url = await client.create(
        endpoint: kUploadBase,
        token: kToken,
        bucket: 'b',
        objectName: 'o',
        mimeType: 'text/plain',
        totalBytes: 10,
      );

      expect(url, 'https://cdn.example.com/upload/xyz');
    });

    test('lanza UploadException en respuesta no-201', () {
      final client = TusClient(
        httpClient: httpMock((_) async =>
            http.Response('{"error":"bucket no existe"}', 400)),
      );

      expect(
        () => client.create(
          endpoint: kUploadBase,
          token: kToken,
          bucket: 'b',
          objectName: 'o',
          mimeType: 'text/plain',
          totalBytes: 10,
        ),
        throwsA(isA<UploadException>()),
      );
    });

    test('lanza UploadException cuando falta header Location', () {
      final client = TusClient(
        httpClient: httpMock((_) async => http.Response('', 201)),
      );

      expect(
        () => client.create(
          endpoint: kUploadBase,
          token: kToken,
          bucket: 'b',
          objectName: 'o',
          mimeType: 'text/plain',
          totalBytes: 10,
        ),
        throwsA(isA<UploadException>()),
      );
    });
  });

  // ==========================================================================
  // 8. TusClient.patch — PATCH de chunks
  // ==========================================================================

  group('TusClient.patch —', () {
    test('archivo pequeño: un único PATCH con offset=0', () async {
      final patches = <http.Request>[];
      int serverOffset = 0;

      final client = TusClient(
        httpClient: httpMock((req) async {
          patches.add(req);
          serverOffset += req.bodyBytes.length;
          return http.Response('', 204,
              headers: {'upload-offset': '$serverOffset'});
        }),
      );

      await client.patch(
        uploadUrl: kUploadUrl,
        token: kToken,
        bytes: bytes1KB(),
        startOffset: 0,
      );

      expect(patches.length, 1);
      expect(patches.first.headers['upload-offset'], '0');
      expect(patches.first.headers['tus-resumable'], '1.0.0');
      expect(patches.first.headers['content-type'],
          'application/offset+octet-stream');
      expect(patches.first.bodyBytes.length, 1024);
    });

    test('10 MB → exactamente 2 PATCHes (6 MB + 4 MB)', () async {
      final offsets = <int>[];
      int serverOffset = 0;

      final client = TusClient(
        httpClient: httpMock((req) async {
          offsets.add(int.parse(req.headers['upload-offset']!));
          serverOffset += req.bodyBytes.length;
          return http.Response('', 204,
              headers: {'upload-offset': '$serverOffset'});
        }),
      );

      await client.patch(
        uploadUrl: kUploadUrl,
        token: kToken,
        bytes: bytes10MB(),
        startOffset: 0,
      );

      expect(offsets.length, 2);
      expect(offsets[0], 0);
      expect(offsets[1], 6 * 1024 * 1024);
    });

    test('emite UploadProgress después de cada chunk', () async {
      int serverOffset = 0;
      final client = TusClient(
        httpClient: httpMock((req) async {
          serverOffset += req.bodyBytes.length;
          return http.Response('', 204,
              headers: {'upload-offset': '$serverOffset'});
        }),
      );

      final events = <UploadProgress>[];
      final ctrl = StreamController<UploadProgress>();
      ctrl.stream.listen(events.add);

      await client.patch(
        uploadUrl: kUploadUrl,
        token: kToken,
        bytes: bytes1KB(),
        startOffset: 0,
        progressController: ctrl,
      );
      await ctrl.close();

      expect(events, isNotEmpty);
      expect(events.last.bytesUploaded, 1024);
      expect(events.last.totalBytes, 1024);
      expect(events.last.fraction, 1.0);
    });

    test('emite evento inicial de progreso cuando reanuda (startOffset > 0)', () async {
      int serverOffset = 512;
      final client = TusClient(
        httpClient: httpMock((req) async {
          serverOffset += req.bodyBytes.length;
          return http.Response('', 204,
              headers: {'upload-offset': '$serverOffset'});
        }),
      );

      final events = <UploadProgress>[];
      final ctrl = StreamController<UploadProgress>();
      ctrl.stream.listen(events.add);

      await client.patch(
        uploadUrl: kUploadUrl,
        token: kToken,
        bytes: bytes1KB(),
        startOffset: 512,
        progressController: ctrl,
      );
      await ctrl.close();

      expect(events.first.bytesUploaded, 512);
      expect(events.last.bytesUploaded, 1024);
    });

    test('lanza UploadException si cancelToken ya está cancelado', () {
      final token = UploadCancelToken()..cancel();
      final client = TusClient(
        httpClient: httpMock((_) async => throw StateError('no debería llamarse')),
      );

      expect(
        () => client.patch(
          uploadUrl: kUploadUrl,
          token: kToken,
          bytes: bytes1KB(),
          startOffset: 0,
          cancelToken: token,
        ),
        throwsA(isA<UploadException>()),
      );
    });

    test('cancela entre chunks en archivo grande', () async {
      int chunksSent = 0;
      final cancelToken = UploadCancelToken();
      int serverOffset = 0;

      final client = TusClient(
        httpClient: httpMock((req) async {
          chunksSent++;
          serverOffset += req.bodyBytes.length;
          if (chunksSent == 1) cancelToken.cancel();
          return http.Response('', 204,
              headers: {'upload-offset': '$serverOffset'});
        }),
      );

      await expectLater(
        () => client.patch(
          uploadUrl: kUploadUrl,
          token: kToken,
          bytes: bytes10MB(),
          startOffset: 0,
          cancelToken: cancelToken,
        ),
        throwsA(isA<UploadException>()),
      );

      expect(chunksSent, 1);
    });

    test('lanza UploadException en respuesta no-204', () {
      final client = TusClient(
        httpClient: httpMock((_) async => http.Response('Internal error', 500)),
      );

      expect(
        () => client.patch(
          uploadUrl: kUploadUrl,
          token: kToken,
          bytes: bytes1KB(),
          startOffset: 0,
        ),
        throwsA(isA<UploadException>()),
      );
    });

    test('usa el Upload-Offset del response para el siguiente chunk', () async {
      const reportedOffset = 1024;
      final client = TusClient(
        httpClient: httpMock((_) async => http.Response('', 204,
            headers: {'upload-offset': '$reportedOffset'})),
      );

      final events = <UploadProgress>[];
      final ctrl = StreamController<UploadProgress>();
      ctrl.stream.listen(events.add);

      await client.patch(
        uploadUrl: kUploadUrl,
        token: kToken,
        bytes: bytes1KB(),
        startOffset: 0,
        progressController: ctrl,
      );
      await ctrl.close();

      expect(events.last.bytesUploaded, reportedOffset);
    });
  });

  // ==========================================================================
  // 9. TusClient.head — HEAD para check de offset
  // ==========================================================================

  group('TusClient.head —', () {
    test('retorna Upload-Offset del header', () async {
      final client = TusClient(
        httpClient: httpMock((_) async =>
            http.Response('', 200, headers: {'upload-offset': '6291456'})),
      );

      final offset = await client.head(kUploadUrl, kToken);
      expect(offset, 6291456);
    });

    test('retorna null en respuesta no-200 (upload expirado/no existe)', () async {
      final client = TusClient(
        httpClient: httpMock((_) async => http.Response('Not found', 404)),
      );

      final offset = await client.head(kUploadUrl, kToken);
      expect(offset, isNull);
    });

    test('retorna null cuando falta el header Upload-Offset', () async {
      final client = TusClient(
        httpClient: httpMock((_) async => http.Response('', 200)),
      );

      final offset = await client.head(kUploadUrl, kToken);
      expect(offset, isNull);
    });

    test('retorna null en error de red (no lanza excepción)', () async {
      final client = TusClient(
        httpClient: httpMock((_) async => throw Exception('timeout de red')),
      );

      final offset = await client.head(kUploadUrl, kToken);
      expect(offset, isNull);
    });

    test('envía headers Authorization y tus-resumable', () async {
      late http.Request captured;
      final client = TusClient(
        httpClient: httpMock((req) async {
          captured = req;
          return http.Response('', 200, headers: {'upload-offset': '0'});
        }),
      );

      await client.head(kUploadUrl, kToken);

      expect(captured.headers['Authorization'], 'Bearer $kToken');
      expect(captured.headers['tus-resumable'], '1.0.0');
    });
  });

  // ==========================================================================
  // 10. SupabaseTusUploader.upload — flujo completo
  // ==========================================================================

  group('SupabaseTusUploader.upload —', () {
    const kStoragePath = 'e-001/factura/f-001/1234_factura.pdf';

    test('flujo feliz: POST → HEAD → PATCH → resultado correcto', () async {
      final uploader = SupabaseTusUploader(
        client: TusClient(httpClient: tusServerMock()),
      );

      final result = await uploader.upload(
        bytes: bytes1KB(),
        fileName: 'factura.pdf',
        storagePath: kStoragePath,
        supabaseUrl: kSupabaseUrl,
        accessToken: kToken,
      );

      expect(result.nombreOriginal, 'factura.pdf');
      expect(result.mimeType, 'application/pdf');
      expect(result.tamanioBytes, 1024);
      expect(result.storagePath, kStoragePath);
    });

    test('limpia la caché de SharedPreferences tras upload exitoso', () async {
      final uploader = SupabaseTusUploader(
        client: TusClient(httpClient: tusServerMock()),
      );

      await uploader.upload(
        bytes: bytes1KB(),
        fileName: 'doc.pdf',
        storagePath: kStoragePath,
        supabaseUrl: kSupabaseUrl,
        accessToken: kToken,
      );

      final prefs = await SharedPreferences.getInstance();
      final tusKeys = prefs.getKeys().where((k) => k.startsWith('tus_url_'));
      expect(tusKeys, isEmpty);
    });

    test('lanza UploadException para archivo vacío', () {
      final uploader = SupabaseTusUploader(
        client: TusClient(httpClient: tusServerMock()),
      );

      expect(
        () => uploader.upload(
          bytes: Uint8List(0),
          fileName: 'vacio.pdf',
          storagePath: kStoragePath,
          supabaseUrl: kSupabaseUrl,
          accessToken: kToken,
        ),
        throwsA(isA<UploadException>()),
      );
    });

    test('HEAD reporta offset >= total → no hace PATCH (ya completado)', () async {
      final patches = <http.Request>[];

      final uploader = SupabaseTusUploader(
        client: TusClient(
          httpClient: httpMock((req) async {
            if (req.method == 'POST') {
              return http.Response('', 201, headers: {'location': kUploadUrl});
            }
            if (req.method == 'HEAD') {
              return http.Response('', 200,
                  headers: {'upload-offset': '1024'});
            }
            if (req.method == 'PATCH') {
              patches.add(req);
              return http.Response('', 204, headers: {'upload-offset': '1024'});
            }
            return http.Response('', 404);
          }),
        ),
      );

      final result = await uploader.upload(
        bytes: bytes1KB(),
        fileName: 'done.pdf',
        storagePath: kStoragePath,
        supabaseUrl: kSupabaseUrl,
        accessToken: kToken,
      );

      expect(patches, isEmpty);
      expect(result.tamanioBytes, 1024);
    });

    test('reanuda desde el offset que reporta el servidor (HEAD > 0)', () async {
      const total = 10 * 1024;
      const serverHas = 4 * 1024;

      final patchOffsets = <int>[];
      int serverOffset = serverHas;

      final uploader = SupabaseTusUploader(
        client: TusClient(
          httpClient: httpMock((req) async {
            if (req.method == 'POST') {
              return http.Response('', 201, headers: {'location': kUploadUrl});
            }
            if (req.method == 'HEAD') {
              return http.Response('', 200,
                  headers: {'upload-offset': '$serverOffset'});
            }
            if (req.method == 'PATCH') {
              patchOffsets.add(int.parse(req.headers['upload-offset']!));
              serverOffset += req.bodyBytes.length;
              return http.Response('', 204,
                  headers: {'upload-offset': '$serverOffset'});
            }
            return http.Response('', 404);
          }),
        ),
      );

      await uploader.upload(
        bytes: Uint8List(total),
        fileName: 'resume.txt',
        storagePath: 'e-001/contacto/c-001/1234_resume.txt',
        supabaseUrl: kSupabaseUrl,
        accessToken: kToken,
      );

      expect(patchOffsets.first, serverHas);
    });

    test('10 MB → emite múltiples eventos de progreso', () async {
      final uploader = SupabaseTusUploader(
        client: TusClient(httpClient: tusServerMock()),
      );

      final events = <UploadProgress>[];
      final ctrl = StreamController<UploadProgress>();
      ctrl.stream.listen(events.add);

      await uploader.upload(
        bytes: bytes10MB(),
        fileName: 'grande.zip',
        storagePath: 'e-001/empresa/e-001/1234_grande.zip',
        supabaseUrl: kSupabaseUrl,
        accessToken: kToken,
        progress: ctrl,
      );
      await ctrl.close();

      expect(events.length, greaterThanOrEqualTo(2));
      expect(events.last.fraction, 1.0);
    });
  });
}
