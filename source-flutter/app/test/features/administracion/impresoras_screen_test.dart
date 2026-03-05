// Tests de ImpresorasScreen
//
// Cubre:
//   · ImpresoraVirtual.fromJson — campos, defaults y TipoDocumento
//   · Estado de carga (ProgressRing)
//   · Estado de error (InfoBar "Error al cargar impresoras")
//   · Estado vacío — sin admin: sin botón "Crear primera impresora"
//   · Estado vacío — con admin: muestra botón "Crear primera impresora"
//   · Con impresoras: "Catálogo de empresa", nombre + tipo
//   · Con admin: botón delete visible en cada tarjeta
//   · Sin admin: botón delete NO visible
//   · Expandir tarjeta: muestra sección "Mi dispositivo"
//   · Nueva impresora: botón abre ContentDialog con campos y botones
//   · ContentDialog: Cancelar cierra el dialog
//   · Confirmar eliminar: abre dialog de confirmación
//
// NOTA: Las operaciones que llaman a Supabase (crear/eliminar, probar conexión)
// requieren Supabase real — solo se prueba el flujo de UI.

import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilar_print/pilar_print.dart';
import 'package:pilar_erp/core/providers/usuario_provider.dart';
import 'package:pilar_erp/features/administracion/screens/impresoras_screen.dart';
import 'package:pilar_erp/features/administracion/providers/impresoras_admin_provider.dart';

import '../../helpers/test_utils.dart';

// ---------------------------------------------------------------------------
// Datos fake
// ---------------------------------------------------------------------------

ImpresoraVirtual _fakeImpresora({
  String id = 'imp-001',
  String nombre = 'Ticket POS',
  TipoDocumento tipoDoc = TipoDocumento.escpos,
  String? descripcion = 'Impresora para tickets de venta',
}) =>
    ImpresoraVirtual(
      id: id,
      nombre: nombre,
      tipoDoc: tipoDoc,
      descripcion: descripcion,
    );

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Crea el ProviderOverride del proveedor de impresoras para tests.
Override _overrideImpresoras(Future<List<ImpresoraVirtual>> future) {
  return impresorasScreenProvider.overrideWith((_) => future);
}

Widget _buildApp({
  required Future<List<ImpresoraVirtual>> impresorasFuture,
  bool tieneAdmin = true,
}) {
  return ProviderScope(
    overrides: [
      ...baseOverrides(),
      hasPermissionProvider.overrideWith((ref, p) => tieneAdmin),
      _overrideImpresoras(impresorasFuture),
    ],
    child: const FluentApp(home: ImpresorasScreen()),
  );
}

// ===========================================================================
// UNIT TESTS — ImpresoraVirtual.fromJson
// ===========================================================================

void main() {
  group('ImpresoraVirtual.fromJson', () {
    test('parsea todos los campos de una impresora PDF', () {
      final json = {
        'id': 'imp-001',
        'nombre': 'Factura A4',
        'tipo_doc': 'pdf',
        'descripcion': 'Impresora de escritorio',
      };

      final imp = ImpresoraVirtual.fromJson(json);

      expect(imp.id, 'imp-001');
      expect(imp.nombre, 'Factura A4');
      expect(imp.tipoDoc, TipoDocumento.pdf);
      expect(imp.descripcion, 'Impresora de escritorio');
    });

    test('parsea una impresora ESC/POS sin descripción', () {
      final json = {
        'id': 'imp-002',
        'nombre': 'Ticket POS',
        'tipo_doc': 'escpos',
        'descripcion': null,
      };

      final imp = ImpresoraVirtual.fromJson(json);

      expect(imp.tipoDoc, TipoDocumento.escpos);
      expect(imp.descripcion, isNull);
    });

    test('parsea una impresora ZPL', () {
      final json = {
        'id': 'imp-003',
        'nombre': 'Etiqueta Zebra',
        'tipo_doc': 'zpl',
      };

      final imp = ImpresoraVirtual.fromJson(json);
      expect(imp.tipoDoc, TipoDocumento.zpl);
    });

    test('tipo_doc desconocido defaultea a pdf', () {
      final json = {
        'id': 'imp-004',
        'nombre': 'Desconocida',
        'tipo_doc': 'tipo_inventado',
      };

      final imp = ImpresoraVirtual.fromJson(json);
      expect(imp.tipoDoc, TipoDocumento.pdf);
    });

    test('descripcion puede ser null cuando no está en JSON', () {
      final json = {
        'id': 'imp-005',
        'nombre': 'Sin desc',
        'tipo_doc': 'escpos',
      };

      final imp = ImpresoraVirtual.fromJson(json);
      expect(imp.descripcion, isNull);
    });

    test('parsea tipo escp correctamente', () {
      final json = {
        'id': 'imp-006',
        'nombre': 'Matricial',
        'tipo_doc': 'escp',
      };

      final imp = ImpresoraVirtual.fromJson(json);
      expect(imp.tipoDoc, TipoDocumento.escp);
    });

    test('parsea tipo texto correctamente', () {
      final json = {
        'id': 'imp-007',
        'nombre': 'Plano',
        'tipo_doc': 'texto',
      };

      final imp = ImpresoraVirtual.fromJson(json);
      expect(imp.tipoDoc, TipoDocumento.texto);
    });
  });

  // ===========================================================================
  // WIDGET TESTS
  // ===========================================================================

  group('ImpresorasScreen — estado de carga', () {
    testWidgets('muestra ProgressRing mientras impresorasScreenProvider carga',
        (tester) async {
      final completer = Completer<List<ImpresoraVirtual>>();
      await tester.pumpWidget(
          _buildApp(impresorasFuture: completer.future));
      await tester.pump();

      expect(find.byType(ProgressRing), findsOneWidget);

      completer.complete([]);
    });
  });

  group('ImpresorasScreen — estado de error', () {
    testWidgets('muestra InfoBar cuando el provider lanza excepción',
        (tester) async {
      final app = ProviderScope(
        overrides: [
          ...baseOverrides(),
          hasPermissionProvider.overrideWith((ref, p) => true),
          impresorasScreenProvider
              .overrideWith((_) async => throw Exception('sin conexión')),
        ],
        child: const FluentApp(home: ImpresorasScreen()),
      );

      await tester.pumpWidget(app);
      await tester.pump();

      expect(find.textContaining('Error al cargar'), findsOneWidget);
    });
  });

  group('ImpresorasScreen — lista vacía', () {
    testWidgets('muestra "No hay impresoras configuradas"', (tester) async {
      await tester.pumpWidget(
          _buildApp(impresorasFuture: Future.value([])));
      await tester.pump();

      expect(find.text('No hay impresoras configuradas'), findsOneWidget);
    });

    testWidgets('con admin: muestra "Crear primera impresora"', (tester) async {
      await tester.pumpWidget(
          _buildApp(impresorasFuture: Future.value([]), tieneAdmin: true));
      await tester.pump();

      expect(find.text('Crear primera impresora'), findsOneWidget);
    });

    testWidgets('sin admin: NO muestra "Crear primera impresora"',
        (tester) async {
      await tester.pumpWidget(
          _buildApp(impresorasFuture: Future.value([]), tieneAdmin: false));
      await tester.pump();

      expect(find.text('Crear primera impresora'), findsNothing);
    });

    testWidgets('con admin: muestra "Nueva impresora" en CommandBar',
        (tester) async {
      await tester.pumpWidget(
          _buildApp(impresorasFuture: Future.value([]), tieneAdmin: true));
      await tester.pump();

      expect(find.text('Nueva impresora'), findsWidgets);
    });

    testWidgets('sin admin: NO muestra "Nueva impresora" en CommandBar',
        (tester) async {
      await tester.pumpWidget(
          _buildApp(impresorasFuture: Future.value([]), tieneAdmin: false));
      await tester.pump();

      expect(find.text('Nueva impresora'), findsNothing);
    });
  });

  group('ImpresorasScreen — con impresoras', () {
    testWidgets('muestra "Impresoras" en el PageHeader', (tester) async {
      await tester.pumpWidget(_buildApp(
        impresorasFuture: Future.value([_fakeImpresora()]),
      ));
      await tester.pump();

      expect(find.text('Impresoras'), findsOneWidget);
    });

    testWidgets('muestra "Catálogo de empresa" como encabezado de sección',
        (tester) async {
      await tester.pumpWidget(_buildApp(
        impresorasFuture: Future.value([_fakeImpresora()]),
      ));
      await tester.pump();

      expect(find.text('Catálogo de empresa'), findsOneWidget);
    });

    testWidgets('muestra el nombre de la impresora', (tester) async {
      await tester.pumpWidget(_buildApp(
        impresorasFuture:
            Future.value([_fakeImpresora(nombre: 'Mi Etiquetadora')]),
      ));
      await tester.pump();

      expect(find.text('Mi Etiquetadora'), findsOneWidget);
    });

    testWidgets('muestra la descripción de la impresora', (tester) async {
      await tester.pumpWidget(_buildApp(
        impresorasFuture:
            Future.value([_fakeImpresora(descripcion: 'Caja norte')]),
      ));
      await tester.pump();

      expect(find.text('Caja norte'), findsOneWidget);
    });

    testWidgets('muestra badge con tipo de documento en MAYÚSCULAS',
        (tester) async {
      await tester.pumpWidget(_buildApp(
        impresorasFuture:
            Future.value([_fakeImpresora(tipoDoc: TipoDocumento.escpos)]),
      ));
      await tester.pump();

      // TipoDocumento.escpos.name.toUpperCase() → 'ESCPOS'
      expect(find.text('ESCPOS'), findsOneWidget);
    });

    testWidgets('con admin: botón delete visible en la tarjeta', (tester) async {
      await tester.pumpWidget(_buildApp(
        impresorasFuture: Future.value([_fakeImpresora()]),
        tieneAdmin: true,
      ));
      await tester.pump();

      expect(find.byIcon(FluentIcons.delete), findsOneWidget);
    });

    testWidgets('sin admin: botón delete NO visible en la tarjeta',
        (tester) async {
      await tester.pumpWidget(_buildApp(
        impresorasFuture: Future.value([_fakeImpresora()]),
        tieneAdmin: false,
      ));
      await tester.pump();

      expect(find.byIcon(FluentIcons.delete), findsNothing);
    });

    testWidgets('muestra múltiples impresoras', (tester) async {
      await tester.pumpWidget(_buildApp(
        impresorasFuture: Future.value([
          _fakeImpresora(id: 'a', nombre: 'Ticket POS'),
          _fakeImpresora(
              id: 'b', nombre: 'Etiqueta Almacén', tipoDoc: TipoDocumento.zpl),
        ]),
      ));
      await tester.pump();

      expect(find.text('Ticket POS'), findsOneWidget);
      expect(find.text('Etiqueta Almacén'), findsOneWidget);
    });

    testWidgets('tap en chevron_down expande la tarjeta mostrando "Mi dispositivo"',
        (tester) async {
      await tester.pumpWidget(_buildApp(
        impresorasFuture: Future.value([_fakeImpresora()]),
      ));
      await tester.pump();

      // Antes de expandir no hay sección "Mi dispositivo"
      expect(find.text('Mi dispositivo'), findsNothing);

      await tester.tap(find.byIcon(FluentIcons.chevron_down));
      await tester.pumpAndSettle();

      expect(find.text('Mi dispositivo'), findsOneWidget);
    });

    testWidgets('segundo tap en chevron colapsa la tarjeta', (tester) async {
      await tester.pumpWidget(_buildApp(
        impresorasFuture: Future.value([_fakeImpresora()]),
      ));
      await tester.pump();

      await tester.tap(find.byIcon(FluentIcons.chevron_down));
      await tester.pumpAndSettle();
      expect(find.text('Mi dispositivo'), findsOneWidget);

      await tester.tap(find.byIcon(FluentIcons.chevron_up));
      await tester.pumpAndSettle();
      expect(find.text('Mi dispositivo'), findsNothing);
    });
  });

  group('ImpresorasScreen — diálogo nueva impresora', () {
    testWidgets('tap en "Nueva impresora" abre ContentDialog', (tester) async {
      await tester.pumpWidget(_buildApp(
        impresorasFuture: Future.value([]),
        tieneAdmin: true,
      ));
      await tester.pump();

      await tester.tap(find.text('Nueva impresora'));
      await tester.pumpAndSettle();

      expect(find.byType(ContentDialog), findsOneWidget);
    });

    testWidgets('ContentDialog muestra título "Nueva impresora virtual"',
        (tester) async {
      await tester.pumpWidget(_buildApp(
        impresorasFuture: Future.value([]),
        tieneAdmin: true,
      ));
      await tester.pump();

      await tester.tap(find.text('Nueva impresora'));
      await tester.pumpAndSettle();

      expect(find.text('Nueva impresora virtual'), findsOneWidget);
    });

    testWidgets('ContentDialog tiene botones Crear y Cancelar', (tester) async {
      await tester.pumpWidget(_buildApp(
        impresorasFuture: Future.value([]),
        tieneAdmin: true,
      ));
      await tester.pump();

      await tester.tap(find.text('Nueva impresora'));
      await tester.pumpAndSettle();

      final dialog = find.byType(ContentDialog);
      expect(find.descendant(of: dialog, matching: find.text('Crear')),
          findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);
    });

    testWidgets('tap en Cancelar cierra el ContentDialog', (tester) async {
      await tester.pumpWidget(_buildApp(
        impresorasFuture: Future.value([]),
        tieneAdmin: true,
      ));
      await tester.pump();

      await tester.tap(find.text('Nueva impresora'));
      await tester.pumpAndSettle();
      expect(find.byType(ContentDialog), findsOneWidget);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(find.byType(ContentDialog), findsNothing);
    });
  });

  group('ImpresorasScreen — confirmar eliminación', () {
    testWidgets('tap en delete abre diálogo "Eliminar impresora"',
        (tester) async {
      await tester.pumpWidget(_buildApp(
        impresorasFuture:
            Future.value([_fakeImpresora(nombre: 'Ticket Caja')]),
        tieneAdmin: true,
      ));
      await tester.pump();

      await tester.tap(find.byIcon(FluentIcons.delete));
      await tester.pumpAndSettle();

      expect(find.text('Eliminar impresora'), findsOneWidget);
    });

    testWidgets('diálogo eliminar muestra el nombre de la impresora',
        (tester) async {
      await tester.pumpWidget(_buildApp(
        impresorasFuture:
            Future.value([_fakeImpresora(nombre: 'Etiquetadora Lab')]),
        tieneAdmin: true,
      ));
      await tester.pump();

      await tester.tap(find.byIcon(FluentIcons.delete));
      await tester.pumpAndSettle();

      expect(find.textContaining('Etiquetadora Lab'), findsWidgets);
    });

    testWidgets('tap en Cancelar del diálogo eliminar cierra el dialog',
        (tester) async {
      await tester.pumpWidget(_buildApp(
        impresorasFuture: Future.value([_fakeImpresora()]),
        tieneAdmin: true,
      ));
      await tester.pump();

      await tester.tap(find.byIcon(FluentIcons.delete));
      await tester.pumpAndSettle();
      expect(find.byType(ContentDialog), findsOneWidget);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(find.byType(ContentDialog), findsNothing);
    });
  });
}
