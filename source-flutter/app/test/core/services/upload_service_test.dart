// Tests para UploadService (wrapper de pilar_erp sobre supabase_tus).
//
// Los tests del protocolo TUS (tusCreate, tusPatch, tusHead, buildMetadata,
// guessMime, sanitizeName) viven en el paquete supabase_tus.
// Aquí se testea solo el comportamiento propio del wrapper:
//   · Construcción del storagePath (empresaId/tipo/entidadId/ts_nombre)
//   · uploadResumableRaw: flujo completo usando UploadService.useTestClient
//   · Limpieza de SharedPreferences tras upload exitoso
//   · Rechazo de archivo vacío
//
// NO se inicializa Supabase.instance — se usa uploadResumableRaw.

import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_tus/supabase_tus.dart';

import 'package:pilar_erp/core/services/upload_service.dart';

// ---------------------------------------------------------------------------
// Helpers de test
// ---------------------------------------------------------------------------

PlatformFile fakeFile({required String name, required Uint8List bytes}) =>
    PlatformFile(name: name, size: bytes.length, bytes: bytes);

MockClient httpMock(Future<http.Response> Function(http.Request) handler) =>
    MockClient(handler);

Uint8List bytes1KB() => Uint8List(1024);
Uint8List bytes10MB() => Uint8List(10 * 1024 * 1024);

const kToken = 'test-bearer-token';
const kSupabaseUrl = 'https://testproject.supabase.co';
const kUploadBase = '$kSupabaseUrl/storage/v1/upload/resumable';
const kUploadId = 'abc123-upload-id';
const kUploadUrl = '$kUploadBase/$kUploadId';

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

  tearDown(() => UploadService.resetClient());

  // ==========================================================================
  // 1. uploadResumableRaw — flujo completo del wrapper
  // ==========================================================================

  group('UploadService.uploadResumableRaw —', () {
    test('flujo feliz: POST → HEAD → PATCH → resultado correcto', () async {
      UploadService.useTestClient(tusServerMock());

      final file = fakeFile(name: 'factura.pdf', bytes: bytes1KB());
      final result = await UploadService.uploadResumableRaw(
        file: file,
        empresaId: 'e-001',
        entidadTipo: 'factura',
        entidadId: 'f-001',
        token: kToken,
        supabaseUrl: kSupabaseUrl,
      );

      expect(result.nombreOriginal, 'factura.pdf');
      expect(result.mimeType, 'application/pdf');
      expect(result.tamanioBytes, 1024);
      expect(result.storagePath, contains('e-001/factura/f-001/'));
    });

    test('storagePath tiene formato empresa/tipo/entidad/ts_nombre', () async {
      UploadService.useTestClient(tusServerMock());

      final file = fakeFile(name: 'contrato.docx', bytes: bytes1KB());
      final result = await UploadService.uploadResumableRaw(
        file: file,
        empresaId: 'e-999',
        entidadTipo: 'contacto',
        entidadId: 'c-123',
        token: kToken,
        supabaseUrl: kSupabaseUrl,
      );

      final parts = result.storagePath.split('/');
      expect(parts[0], 'e-999');
      expect(parts[1], 'contacto');
      expect(parts[2], 'c-123');
      expect(parts[3], contains('contrato.docx'));
    });

    test('limpia caché de SharedPreferences tras upload exitoso', () async {
      UploadService.useTestClient(tusServerMock());

      await UploadService.uploadResumableRaw(
        file: fakeFile(name: 'doc.pdf', bytes: bytes1KB()),
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

    test('lanza UploadException para archivo vacío', () {
      UploadService.useTestClient(tusServerMock());

      expect(
        () => UploadService.uploadResumableRaw(
          file: fakeFile(name: 'vacio.pdf', bytes: Uint8List(0)),
          empresaId: 'e',
          entidadTipo: 't',
          entidadId: 'i',
          token: kToken,
          supabaseUrl: kSupabaseUrl,
        ),
        throwsA(isA<UploadException>()),
      );
    });

    test('reanuda desde el offset que reporta el servidor (HEAD > 0)', () async {
      const total = 10 * 1024;
      const serverHas = 4 * 1024;

      final patchOffsets = <int>[];
      int serverOffset = serverHas;

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

      await UploadService.uploadResumableRaw(
        file: fakeFile(name: 'resume.txt', bytes: Uint8List(total)),
        empresaId: 'e-001',
        entidadTipo: 'contacto',
        entidadId: 'c-001',
        token: kToken,
        supabaseUrl: kSupabaseUrl,
      );

      expect(patchOffsets.first, serverHas);
    });

    test('10 MB → emite múltiples eventos de progreso', () async {
      UploadService.useTestClient(tusServerMock());

      final events = <UploadProgress>[];
      final ctrl = StreamController<UploadProgress>();
      ctrl.stream.listen(events.add);

      await UploadService.uploadResumableRaw(
        file: fakeFile(name: 'grande.zip', bytes: bytes10MB()),
        empresaId: 'e-001',
        entidadTipo: 'empresa',
        entidadId: 'e-001',
        token: kToken,
        supabaseUrl: kSupabaseUrl,
        progressController: ctrl,
      );
      await ctrl.close();

      expect(events.length, greaterThanOrEqualTo(2));
      expect(events.last.fraction, 1.0);
    });
  });
}
