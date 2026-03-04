// Tests de ProductosScreen
//
// Cubre:
//   · Estado de carga → ProgressRing (dentro de la pestaña lista)
//   · Estado de error → InfoBar "Error al cargar datos"
//   · Estado vacío   → "Sin registros"
//   · Título de página: "Productos y Servicios" (tab + PageHeader)
//   · CommandBar: botón "Nuevo" presente
//   · Botón "Nuevo" abre pestaña "Nuevo producto/servicio"
//   · Pestaña tiene campos (tipo, código, nombre, precio venta, precio costo)
//   · "Cancelar" cierra la pestaña del formulario
//   · Toque en lista móvil abre pestaña "Editar producto/servicio"
//   · rowToMap: _labelTipo mapea correctamente los tipos de producto
//
// NOTA: SfDataGrid (≥600px) no renderiza celdas virtualizadas en test.
// Los tests de contenido fuerzan viewport <600px para activar el
// ListView/cards fallback (primer campo del map = codigo).
//
// NOTA: WorkspaceTabs abre la pestaña lista en addPostFrameCallback.
// Se necesita pumpWidget + pump() para que la pestaña sea visible.

import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilar_erp/features/entidades/screens/productos_screen.dart';
import 'package:pilar_erp/features/entidades/providers/productos_provider.dart';

import '../../helpers/test_utils.dart';

// ---------------------------------------------------------------------------
// Suprime errores de overflow de layout de fluent_ui en el entorno de test.
// ---------------------------------------------------------------------------
void _suppressOverflowErrors() {
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    if (details.exceptionAsString().contains('overflowed')) return;
    previousOnError?.call(details);
  };
  addTearDown(() => FlutterError.onError = previousOnError);
}

// ---------------------------------------------------------------------------
// Fake notifier — extiende la clase concreta para que el override sea válido
// ---------------------------------------------------------------------------

class _FakeProductosNotifier extends ProductosBrickNotifier {
  _FakeProductosNotifier(this._state);
  final AsyncValue<List<Map<String, dynamic>>> _state;

  @override
  String get supabaseTable => 'productos';

  @override
  Future<List<Map<String, dynamic>>> build() async {
    // No llamar super.build() para evitar conexión a Supabase/Realtime
    if (_state is AsyncLoading) {
      // Completer que nunca resuelve (sin timer pendiente)
      return Completer<List<Map<String, dynamic>>>().future;
    }
    if (_state is AsyncError) {
      throw (_state as AsyncError<List<Map<String, dynamic>>>).error;
    }
    return (_state as AsyncData<List<Map<String, dynamic>>>).value;
  }

  @override
  void refresh() {} // no-op en tests
}

Override _overrideProductos(
        AsyncValue<List<Map<String, dynamic>>> state) =>
    productosProvider.overrideWith(() => _FakeProductosNotifier(state));

// ---------------------------------------------------------------------------
// Datos fake
// ---------------------------------------------------------------------------

List<Map<String, dynamic>> _fakeProductos() => [
      {
        'id': 'p-001',
        'codigo': 'PROD-001',
        'nombre': 'Mesa de Oficina',
        'tipo': 'PRODUCTO',
        'precio_venta': 150.00,
        'precio_costo': 80.00,
        'descripcion': 'Mesa de madera para oficina',
        'activo': true,
      },
      {
        'id': 'p-002',
        'codigo': 'SERV-001',
        'nombre': 'Consultoría IT',
        'tipo': 'SERVICIO',
        'precio_venta': 75.00,
        'precio_costo': null,
        'descripcion': null,
        'activo': true,
      },
      {
        'id': 'p-003',
        'codigo': 'CONS-001',
        'nombre': 'Café de oficina',
        'tipo': 'CONSUMO',
        'precio_venta': null,
        'precio_costo': null,
        'descripcion': null,
        'activo': true,
      },
    ];

// ---------------------------------------------------------------------------
// Builder
// ---------------------------------------------------------------------------

Widget _buildScreen(AsyncValue<List<Map<String, dynamic>>> state) {
  return ProviderScope(
    overrides: [
      ...baseOverrides(),
      _overrideProductos(state),
    ],
    child: const FluentApp(home: ProductosScreen()),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ── Estado de carga ────────────────────────────────────────────────────────
  group('ProductosScreen — carga', () {
    testWidgets('muestra ProgressRing mientras carga', (tester) async {
      await tester.pumpWidget(_buildScreen(const AsyncLoading()));
      await tester.pump(); // frame 2: lista tab visible con CrudScaffold
      expect(find.byType(ProgressRing), findsOneWidget);
    });
  });

  // ── Estado de error ────────────────────────────────────────────────────────
  group('ProductosScreen — error', () {
    testWidgets('muestra InfoBar con mensaje de error', (tester) async {
      await tester.pumpWidget(
        _buildScreen(AsyncError(Exception('network'), StackTrace.empty)),
      );
      await tester.pump(); // lista tab visible
      await tester.pump(); // productosProvider AsyncLoading → AsyncError
      expect(find.text('Error al cargar datos'), findsOneWidget);
    });
  });

  // ── Estado vacío ───────────────────────────────────────────────────────────
  group('ProductosScreen — vacío', () {
    testWidgets('muestra "Sin registros" cuando la lista está vacía',
        (tester) async {
      await tester.pumpWidget(_buildScreen(const AsyncData([])));
      await tester.pump(); // lista tab visible
      await tester.pump(); // productosProvider AsyncLoading → AsyncData([])
      expect(find.text('Sin registros'), findsOneWidget);
    });
  });

  // ── Título y CommandBar ────────────────────────────────────────────────────
  group('ProductosScreen — título y CommandBar', () {
    testWidgets('muestra título "Productos y Servicios"', (tester) async {
      await tester.pumpWidget(_buildScreen(const AsyncData([])));
      await tester.pump();
      // Aparece en tab button Y en PageHeader de CrudScaffold
      expect(find.text('Productos y Servicios'), findsAtLeastNWidgets(1));
    });

    testWidgets('muestra botón "Nuevo" en CommandBar', (tester) async {
      await tester.pumpWidget(_buildScreen(const AsyncData([])));
      await tester.pump();
      expect(find.text('Nuevo'), findsOneWidget);
    });
  });

  // ── Pestaña "Nuevo producto/servicio" ─────────────────────────────────────
  //
  // Viewport amplio para que el botón "Nuevo" del CommandBar quede visible.
  group('ProductosScreen — pestaña nuevo', () {
    testWidgets('botón "Nuevo" abre pestaña con título correcto',
        (tester) async {
      _suppressOverflowErrors();
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_buildScreen(const AsyncData([])));
      await tester.pump();

      await tester.tap(find.text('Nuevo'));
      await tester.pumpAndSettle();

      // Aparece en el tab button Y en el FormScaffold PageHeader
      expect(find.text('Nuevo producto/servicio'), findsAtLeastNWidgets(1));
    });

    testWidgets('pestaña tiene campos TextBox (nombre, código, precios, desc)',
        (tester) async {
      _suppressOverflowErrors();
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_buildScreen(const AsyncData([])));
      await tester.pump();

      await tester.tap(find.text('Nuevo'));
      await tester.pumpAndSettle();

      // código, nombre, precio venta, precio costo, descripción
      expect(find.byType(TextBox), findsAtLeastNWidgets(4));
    });

    testWidgets('pestaña tiene ComboBox para tipo de producto', (tester) async {
      _suppressOverflowErrors();
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_buildScreen(const AsyncData([])));
      await tester.pump();

      await tester.tap(find.text('Nuevo'));
      await tester.pumpAndSettle();

      expect(find.byType(ComboBox<String>), findsOneWidget);
    });

    testWidgets('pestaña tiene botones "Cancelar" y "Crear"', (tester) async {
      _suppressOverflowErrors();
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_buildScreen(const AsyncData([])));
      await tester.pump();

      await tester.tap(find.text('Nuevo'));
      await tester.pumpAndSettle();

      expect(find.text('Cancelar'), findsOneWidget);
      expect(find.text('Crear'), findsOneWidget);
    });

    testWidgets('"Cancelar" cierra la pestaña del formulario', (tester) async {
      _suppressOverflowErrors();
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_buildScreen(const AsyncData([])));
      await tester.pump();

      await tester.tap(find.text('Nuevo'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      // Pestaña cerrada: "Nuevo producto/servicio" no aparece en ningún lado
      expect(find.text('Nuevo producto/servicio'), findsNothing);
    });
  });

  // ── Pestaña "Editar producto/servicio" ────────────────────────────────────
  group('ProductosScreen — pestaña editar', () {
    testWidgets(
        'toque en lista móvil abre pestaña con título "Editar producto/servicio"',
        (tester) async {
      _suppressOverflowErrors();
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_buildScreen(AsyncData(_fakeProductos())));
      await tester.pump(); // lista tab visible
      await tester.pump(); // productosProvider → AsyncData con productos

      // El primer card muestra el codigo (primer valor del rowToMap)
      await tester.tap(find.text('PROD-001'));
      await tester.pumpAndSettle();

      // FormScaffold PageHeader muestra "Editar producto/servicio"
      expect(find.text('Editar producto/servicio'), findsOneWidget);
      expect(find.text('Guardar'), findsOneWidget);
    });

    testWidgets('pestaña de edición pre-carga nombre del producto',
        (tester) async {
      _suppressOverflowErrors();
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_buildScreen(AsyncData(_fakeProductos())));
      await tester.pump(); // lista tab visible
      await tester.pump(); // productosProvider → AsyncData con productos

      await tester.tap(find.text('PROD-001'));
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(TextBox, 'Mesa de Oficina'),
        findsOneWidget,
      );
    });
  });

  // ── Datos en modo mobile (ListView fallback) ───────────────────────────────
  group('ProductosScreen — contenido móvil', () {
    testWidgets('muestra código de los productos', (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_buildScreen(AsyncData(_fakeProductos())));
      await tester.pump(); // lista tab visible
      await tester.pump(); // productosProvider → AsyncData con productos

      expect(find.text('PROD-001'), findsOneWidget);
      expect(find.text('SERV-001'), findsOneWidget);
    });

    testWidgets('muestra los tres productos sin errores', (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_buildScreen(AsyncData(_fakeProductos())));
      await tester.pump(); // lista tab visible
      await tester.pump(); // productosProvider → AsyncData con productos

      expect(find.text('PROD-001'), findsOneWidget);
      expect(find.text('SERV-001'), findsOneWidget);
      expect(find.text('CONS-001'), findsOneWidget);
    });
  });

  // ── rowToMap: _labelTipo ───────────────────────────────────────────────────
  group('ProductosScreen — labelTipo', () {
    testWidgets('tipo SERVICIO se pre-carga en la pestaña de edición',
        (tester) async {
      _suppressOverflowErrors();
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_buildScreen(AsyncData(_fakeProductos())));
      await tester.pump(); // lista tab visible
      await tester.pump(); // productosProvider → AsyncData con productos

      // SERV-001 es de tipo SERVICIO
      await tester.tap(find.text('SERV-001'));
      await tester.pumpAndSettle();

      expect(find.text('Servicio'), findsOneWidget);
    });

    testWidgets('tipo CONSUMO se pre-carga en la pestaña de edición',
        (tester) async {
      _suppressOverflowErrors();
      tester.view.physicalSize = const Size(500, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_buildScreen(AsyncData(_fakeProductos())));
      await tester.pump(); // lista tab visible
      await tester.pump(); // productosProvider → AsyncData con productos

      // CONS-001 es de tipo CONSUMO
      await tester.tap(find.text('CONS-001'));
      await tester.pumpAndSettle();

      expect(find.text('Consumo'), findsOneWidget);
    });
  });
}
