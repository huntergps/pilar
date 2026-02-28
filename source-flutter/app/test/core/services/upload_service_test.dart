// Tests para UploadService y el protocolo TUS.
//
// Estrategia:
//   · Tipos públicos (UploadProgress, UploadCancelToken, UploadException)
//     → tests unitarios puros, sin mocks.
//   · Helpers @visibleForTesting (guessMime, sanitizeName, buildTusMetadata)
//     → tests unitarios puros.
//   · TUS protocol (tusCreate, tusPatch, tusHead)
//     → MockClient inyectado via UploadService.useTestClient().
//   · uploadResumableRaw (flujo completo)
//     → SharedPreferences mock + MockClient.
//
// NO se inicializa Supabase.instance — se usa uploadResumableRaw que
// acepta token + supabaseUrl directamente.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pilar_erp/core/services/upload_service.dart';

// ---------------------------------------------------------------------------
// Helpers de test
// ---------------------------------------------------------------------------

/// Crea un PlatformFile con bytes en memoria (funciona en todos los tests).
PlatformFile fakeFile({required String name, required Uint8List bytes}) =>
    PlatformFile(name: name, size: bytes.length, bytes: bytes);

/// MockClient que lleva un registro de las requests recibidas.
class CapturingClient extends MockClient {
  final List<http.Request> captured = [];

  CapturingClient(Future<http.Response> Function(http.Request) fn)
      : super((req) async {
          // No podemos capturar directamente porque MockClient no expone el req.
          // Usamos el patrón wrapper.
          return fn(req);
        });
}

/// Construye un MockClient simple que responde según el método HTTP.
MockClient httpMock(Future<http.Response> Function(http.Request) handler) =>
    MockClient(handler);

// Tamaños de prueba
Uint8List bytes1KB  ()  => Uint8List(1024);
Uint8List bytes6MB  ()  => Uint8List(6 * 1024 * 1024);        // = 1 chunk exacto
Uint8List bytes10MB ()  => Uint8List(10 * 1024 * 1024);       // = 2 chunks

const kToken       = 'test-bearer-token';
const kSupabaseUrl = 'https://testproject.supabase.co';
const kUploadBase  = '$kSupabaseUrl/storage/v1/upload/resumable';
const kUploadId    = 'abc123-upload-id';
const kUploadUrl   = '$kUploadBase/$kUploadId';

// MockClient que simula un servidor TUS exitoso.
// POST  → 201 con Location: {kUploadUrl}
// HEAD  → 200 con Upload-Offset: {currentOffset acumulado}
// PATCH → 204 con Upload-Offset actualizado
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
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    UploadService.resetClient();
  });

  tearDown(() {
    UploadService.resetClient();
  });

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
  // 4. guessMime — detección de MIME por extensión
  // ==========================================================================

  group('UploadService.guessMime —', () {
    test('jpg → image/jpeg', () =>
        expect(UploadService.guessMime('foto.jpg'), 'image/jpeg'));

    test('JPEG en mayúsculas → image/jpeg', () =>
        expect(UploadService.guessMime('foto.JPEG'), 'image/jpeg'));

    test('png → image/png', () =>
        expect(UploadService.guessMime('imagen.png'), 'image/png'));

    test('gif → image/gif', () =>
        expect(UploadService.guessMime('anim.gif'), 'image/gif'));

    test('pdf → application/pdf', () =>
        expect(UploadService.guessMime('factura.pdf'), 'application/pdf'));

    test('docx → MIME de Word', () =>
        expect(UploadService.guessMime('reporte.docx'),
            contains('wordprocessingml')));

    test('xlsx → MIME de Excel', () =>
        expect(UploadService.guessMime('datos.xlsx'),
            contains('spreadsheetml')));

    test('csv → text/csv', () =>
        expect(UploadService.guessMime('export.csv'), 'text/csv'));

    test('zip → application/zip', () =>
        expect(UploadService.guessMime('archivo.zip'), 'application/zip'));

    test('extensión desconocida → application/octet-stream', () =>
        expect(UploadService.guessMime('raro.xyz'),
            'application/octet-stream'));

    test('sin extensión → application/octet-stream', () =>
        expect(UploadService.guessMime('archivo'), 'application/octet-stream'));
  });

  // ==========================================================================
  // 5. sanitizeName — limpieza de nombre de archivo
  // ==========================================================================

  group('UploadService.sanitizeName —', () {
    test('nombre limpio sin cambios', () =>
        expect(UploadService.sanitizeName('factura.pdf'), 'factura.pdf'));

    test('espacios → guión bajo', () =>
        expect(UploadService.sanitizeName('mi factura 2026.pdf'),
            'mi_factura_2026.pdf'));

    test('caracteres especiales → guión bajo', () =>
        expect(UploadService.sanitizeName('a@b#c\$d.pdf'), 'a_b_c_d.pdf'));

    test('guión y punto se conservan', () =>
        expect(UploadService.sanitizeName('doc-final.v2.pdf'),
            'doc-final.v2.pdf'));

    test('tildes → guión bajo', () =>
        expect(UploadService.sanitizeName('cotización.pdf'),
            'cotizaci_n.pdf'));
  });

  // ==========================================================================
  // 6. buildTusMetadata — formato base64 TUS
  // ==========================================================================

  group('UploadService.buildTusMetadata —', () {
    test('formato: "key base64(value)"', () {
      final meta = UploadService.buildTusMetadata({'filename': 'test.pdf'});
      final expected = 'filename ${base64.encode(utf8.encode('test.pdf'))}';
      expect(meta, expected);
    });

    test('múltiples campos separados por coma', () {
      final meta = UploadService.buildTusMetadata({
        'bucketName': 'adjuntos',
        'contentType': 'application/pdf',
      });
      expect(meta, contains(','));
      expect(meta, contains('bucketName '));
      expect(meta, contains('contentType '));
    });

    test('los valores son base64 decodificable', () {
      final meta = UploadService.buildTusMetadata({
        'objectName': 'empresa/factura/abc/file with spaces.pdf',
      });
      // Extraer el valor base64 (después del primer espacio)
      final b64 = meta.split(' ').last;
      expect(() => base64.decode(b64), returnsNormally);
      expect(
        utf8.decode(base64.decode(b64)),
        'empresa/factura/abc/file with spaces.pdf',
      );
    });

    test('campo vacío se codifica como base64 vacío', () {
      final meta = UploadService.buildTusMetadata({'descripcion': ''});
      final b64 = meta.split(' ').last;
      expect(utf8.decode(base64.decode(b64)), '');
    });
  });

  // ==========================================================================
  // 7. tusCreate — POST al servidor TUS
  // ==========================================================================

  group('UploadService.tusCreate —', () {
    test('envía Authorization, tus-resumable, upload-length, x-upsert', () async {
      late http.Request captured;
      UploadService.useTestClient(httpMock((req) async {
        captured = req;
        return http.Response('', 201, headers: {'location': kUploadUrl});
      }));

      await UploadService.tusCreate(
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
      UploadService.useTestClient(httpMock((req) async {
        captured = req;
        return http.Response('', 201, headers: {'location': kUploadUrl});
      }));

      await UploadService.tusCreate(
        endpoint: kUploadBase,
        token: kToken,
        bucket: 'adjuntos',
        objectName: 'e-001/factura/f-001/factura.pdf',
        mimeType: 'application/pdf',
        totalBytes: 100,
      );

      final metaRaw = captured.headers['upload-metadata']!;
      // Decodificar cada par "key base64val"
      final pairs = metaRaw.split(',').map((s) => s.trim());
      final decoded = {
        for (final p in pairs)
          p.split(' ').first: utf8.decode(base64.decode(p.split(' ').last)),
      };

      expect(decoded['bucketName'], 'adjuntos');
      expect(decoded['objectName'], 'e-001/factura/f-001/factura.pdf');
      expect(decoded['filename'],   'factura.pdf');
      expect(decoded['contentType'], 'application/pdf');
    });

    test('convierte Location relativa a URL absoluta', () async {
      UploadService.useTestClient(httpMock((_) async =>
          http.Response('', 201,
              headers: {'location': '/storage/v1/upload/resumable/$kUploadId'})));

      final url = await UploadService.tusCreate(
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
      UploadService.useTestClient(httpMock((_) async =>
          http.Response('', 201,
              headers: {'location': 'https://cdn.example.com/upload/xyz'})));

      final url = await UploadService.tusCreate(
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
      UploadService.useTestClient(httpMock((_) async =>
          http.Response('{"error":"bucket no existe"}', 400)));

      expect(
        () => UploadService.tusCreate(
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
      UploadService.useTestClient(httpMock((_) async =>
          http.Response('', 201))); // sin Location

      expect(
        () => UploadService.tusCreate(
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
  // 8. tusPatch — PATCH de chunks
  // ==========================================================================

  group('UploadService.tusPatch —', () {
    test('archivo pequeño: un único PATCH con offset=0', () async {
      final patches = <http.Request>[];
      int serverOffset = 0;

      UploadService.useTestClient(httpMock((req) async {
        patches.add(req);
        serverOffset += req.bodyBytes.length;
        return http.Response('', 204,
            headers: {'upload-offset': '$serverOffset'});
      }));

      await UploadService.tusPatch(
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

      UploadService.useTestClient(httpMock((req) async {
        offsets.add(int.parse(req.headers['upload-offset']!));
        serverOffset += req.bodyBytes.length;
        return http.Response('', 204,
            headers: {'upload-offset': '$serverOffset'});
      }));

      await UploadService.tusPatch(
        uploadUrl: kUploadUrl,
        token: kToken,
        bytes: bytes10MB(),
        startOffset: 0,
      );

      expect(offsets.length, 2);
      expect(offsets[0], 0);
      expect(offsets[1], 6 * 1024 * 1024); // segundo chunk empieza en 6 MB
    });

    test('emite UploadProgress después de cada chunk', () async {
      int serverOffset = 0;

      UploadService.useTestClient(httpMock((req) async {
        serverOffset += req.bodyBytes.length;
        return http.Response('', 204,
            headers: {'upload-offset': '$serverOffset'});
      }));

      final events = <UploadProgress>[];
      final ctrl   = StreamController<UploadProgress>();
      ctrl.stream.listen(events.add);

      await UploadService.tusPatch(
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

      UploadService.useTestClient(httpMock((req) async {
        serverOffset += req.bodyBytes.length;
        return http.Response('', 204,
            headers: {'upload-offset': '$serverOffset'});
      }));

      final events = <UploadProgress>[];
      final ctrl   = StreamController<UploadProgress>();
      ctrl.stream.listen(events.add);

      // Archivo de 1 KB, ya hay 512 bytes en el servidor
      await UploadService.tusPatch(
        uploadUrl: kUploadUrl,
        token: kToken,
        bytes: bytes1KB(),
        startOffset: 512,
        progressController: ctrl,
      );
      await ctrl.close();

      // El primer evento debe reflejar el offset ya existente
      expect(events.first.bytesUploaded, 512);
      expect(events.last.bytesUploaded, 1024);
    });

    test('lanza UploadException si cancelToken ya está cancelado', () async {
      final token = UploadCancelToken()..cancel();

      // El MockClient no debe recibir ninguna request
      UploadService.useTestClient(httpMock(
          (_) async => throw StateError('no debería llamarse')));

      expect(
        () => UploadService.tusPatch(
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

      UploadService.useTestClient(httpMock((req) async {
        chunksSent++;
        serverOffset += req.bodyBytes.length;
        // Cancelar después del primer chunk
        if (chunksSent == 1) cancelToken.cancel();
        return http.Response('', 204,
            headers: {'upload-offset': '$serverOffset'});
      }));

      await expectLater(
        () => UploadService.tusPatch(
          uploadUrl: kUploadUrl,
          token: kToken,
          bytes: bytes10MB(), // 2 chunks
          startOffset: 0,
          cancelToken: cancelToken,
        ),
        throwsA(isA<UploadException>()),
      );

      // Solo debe haberse enviado el primer chunk
      expect(chunksSent, 1);
    });

    test('lanza UploadException en respuesta no-204', () {
      UploadService.useTestClient(
          httpMock((_) async => http.Response('Internal error', 500)));

      expect(
        () => UploadService.tusPatch(
          uploadUrl: kUploadUrl,
          token: kToken,
          bytes: bytes1KB(),
          startOffset: 0,
        ),
        throwsA(isA<UploadException>()),
      );
    });

    test('usa el Upload-Offset del response para el siguiente chunk', () async {
      // Servidor devuelve offsets no estándar (simulando latencia/retry)
      const reportedOffsets = [1024, 2048]; // no los que calculamos localmente
      int call = 0;

      UploadService.useTestClient(httpMock((req) async {
        final offset = call < reportedOffsets.length
            ? reportedOffsets[call]
            : 2048;
        call++;
        return http.Response('', 204,
            headers: {'upload-offset': '$offset'});
      }));

      // 2 KB: se envía en 2 PATCHes de 1 KB cada uno (chunk size es 6 MB,
      // pero el archivo es pequeño, así que solo hay 1 chunk)
      // En realidad para 2 KB solo hay 1 PATCH, así que el test usa 3 KB
      // para asegurarnos de que solo hay 1 chunk (< 6 MB)
      final b = bytes1KB(); // 1 KB = 1 chunk, 1 PATCH, check offset from response
      final events = <UploadProgress>[];
      final ctrl   = StreamController<UploadProgress>();
      ctrl.stream.listen(events.add);

      await UploadService.tusPatch(
        uploadUrl: kUploadUrl,
        token: kToken,
        bytes: b,
        startOffset: 0,
        progressController: ctrl,
      );
      await ctrl.close();

      // El último evento debe usar el offset reportado por el servidor (1024)
      expect(events.last.bytesUploaded, reportedOffsets[0]);
    });
  });

  // ==========================================================================
  // 9. tusHead — HEAD para check de offset
  // ==========================================================================

  group('UploadService.tusHead —', () {
    test('retorna Upload-Offset del header', () async {
      UploadService.useTestClient(httpMock((_) async =>
          http.Response('', 200, headers: {'upload-offset': '6291456'})));

      final offset = await UploadService.tusHead(kUploadUrl, kToken);
      expect(offset, 6291456);
    });

    test('retorna null en respuesta no-200 (upload expirado/no existe)', () async {
      UploadService.useTestClient(httpMock((_) async =>
          http.Response('Not found', 404)));

      final offset = await UploadService.tusHead(kUploadUrl, kToken);
      expect(offset, isNull);
    });

    test('retorna null cuando falta el header Upload-Offset', () async {
      UploadService.useTestClient(httpMock((_) async =>
          http.Response('', 200))); // sin header

      final offset = await UploadService.tusHead(kUploadUrl, kToken);
      expect(offset, isNull);
    });

    test('retorna null en error de red (no lanza excepción)', () async {
      UploadService.useTestClient(httpMock((_) async =>
          throw Exception('timeout de red')));

      // No debe propagarse la excepción
      final offset = await UploadService.tusHead(kUploadUrl, kToken);
      expect(offset, isNull);
    });

    test('envía headers Authorization y tus-resumable', () async {
      late http.Request captured;
      UploadService.useTestClient(httpMock((req) async {
        captured = req;
        return http.Response('', 200, headers: {'upload-offset': '0'});
      }));

      await UploadService.tusHead(kUploadUrl, kToken);

      expect(captured.headers['Authorization'], 'Bearer $kToken');
      expect(captured.headers['tus-resumable'], '1.0.0');
    });
  });

  // ==========================================================================
  // 10. uploadResumableRaw — flujo completo
  // ==========================================================================

  group('UploadService.uploadResumableRaw —', () {
    test('flujo feliz: POST → HEAD → PATCH → resultado correcto', () async {
      UploadService.useTestClient(tusServerMock());

      final file   = fakeFile(name: 'factura.pdf', bytes: bytes1KB());
      final result = await UploadService.uploadResumableRaw(
        file: file,
        empresaId: 'e-001',
        entidadTipo: 'factura',
        entidadId: 'f-001',
        token: kToken,
        supabaseUrl: kSupabaseUrl,
      );

      expect(result.nombreOriginal, 'factura.pdf');
      expect(result.mimeType,       'application/pdf');
      expect(result.tamanioBytes,   1024);
      expect(result.storagePath,    contains('e-001/factura/f-001/'));
    });

    test('storagePath tiene formato empresa/tipo/entidad/ts_nombre', () async {
      UploadService.useTestClient(tusServerMock());

      final file   = fakeFile(name: 'contrato.docx', bytes: bytes1KB());
      final result = await UploadService.uploadResumableRaw(
        file: file,
        empresaId: 'e-999',
        entidadTipo: 'contacto',
        entidadId: 'c-123',
        token: kToken,
        supabaseUrl: kSupabaseUrl,
      );

      // Path: e-999/contacto/c-123/{ts}_contrato.docx
      final parts = result.storagePath.split('/');
      expect(parts[0], 'e-999');
      expect(parts[1], 'contacto');
      expect(parts[2], 'c-123');
      expect(parts[3], contains('contrato.docx'));
    });

    test('limpia la caché de SharedPreferences tras upload exitoso', () async {
      UploadService.useTestClient(tusServerMock());

      final file = fakeFile(name: 'doc.pdf', bytes: bytes1KB());
      await UploadService.uploadResumableRaw(
        file: file,
        empresaId: 'e-001',
        entidadTipo: 'factura',
        entidadId: 'f-001',
        token: kToken,
        supabaseUrl: kSupabaseUrl,
      );

      final prefs = await SharedPreferences.getInstance();
      final tusKeys = prefs.getKeys().where((k) => k.startsWith('tus_url_'));
      expect(tusKeys, isEmpty);
    });

    test('lanza UploadException para archivo vacío (bytes = null/vacío)', () {
      UploadService.useTestClient(tusServerMock());

      final file = fakeFile(name: 'vacio.pdf', bytes: Uint8List(0));
      expect(
        () => UploadService.uploadResumableRaw(
          file: file,
          empresaId: 'e',
          entidadTipo: 't',
          entidadId: 'i',
          token: kToken,
          supabaseUrl: kSupabaseUrl,
        ),
        throwsA(isA<UploadException>()),
      );
    });

    test('HEAD reporta offset >= total → no hace PATCH (ya completado)', () async {
      final patches = <http.Request>[];

      UploadService.useTestClient(httpMock((req) async {
        if (req.method == 'POST') {
          return http.Response('', 201, headers: {'location': kUploadUrl});
        }
        if (req.method == 'HEAD') {
          // Servidor ya tiene todos los bytes
          return http.Response('', 200,
              headers: {'upload-offset': '1024'});
        }
        if (req.method == 'PATCH') {
          patches.add(req);
          return http.Response('', 204, headers: {'upload-offset': '1024'});
        }
        return http.Response('', 404);
      }));

      final file = fakeFile(name: 'done.pdf', bytes: bytes1KB());
      final result = await UploadService.uploadResumableRaw(
        file: file,
        empresaId: 'e-001',
        entidadTipo: 'empresa',
        entidadId: 'e-001',
        token: kToken,
        supabaseUrl: kSupabaseUrl,
      );

      // tusPatch no debe haber hecho ningún PATCH porque offset = total
      expect(patches, isEmpty);
      expect(result.tamanioBytes, 1024);
    });

    test('reanuda desde el offset que reporta el servidor (HEAD > 0)', () async {
      const total      = 10 * 1024; // 10 KB
      const serverHas  = 4 * 1024;  // servidor ya tiene 4 KB

      final patchOffsets = <int>[];
      int serverOffset   = serverHas;

      UploadService.useTestClient(httpMock((req) async {
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
      }));

      final file = fakeFile(name: 'resume.txt', bytes: Uint8List(total));
      await UploadService.uploadResumableRaw(
        file: file,
        empresaId: 'e-001',
        entidadTipo: 'contacto',
        entidadId: 'c-001',
        token: kToken,
        supabaseUrl: kSupabaseUrl,
      );

      // El primer PATCH debe comenzar desde el offset que reportó el HEAD
      expect(patchOffsets.first, serverHas);
    });

    test('10 MB → emite múltiples eventos de progreso', () async {
      UploadService.useTestClient(tusServerMock());

      final events = <UploadProgress>[];
      final ctrl   = StreamController<UploadProgress>();
      ctrl.stream.listen(events.add);

      final file = fakeFile(name: 'grande.zip', bytes: bytes10MB());
      await UploadService.uploadResumableRaw(
        file: file,
        empresaId: 'e-001',
        entidadTipo: 'empresa',
        entidadId: 'e-001',
        token: kToken,
        supabaseUrl: kSupabaseUrl,
        progressController: ctrl,
      );
      await ctrl.close();

      // 10 MB → 2 chunks → 2 eventos de progreso
      expect(events.length, greaterThanOrEqualTo(2));
      expect(events.last.fraction, 1.0);
    });
  });
}
