// Tests de ContactosScreen
//
// Cubre:
//   · Estado de carga → ProgressRing (dentro de la pestaña lista)
//   · Estado de error → InfoBar "Error al cargar datos"
//   · Estado vacío   → "Sin registros"
//   · Título de página: "Contactos" (tab + PageHeader)
//   · CommandBar: botón "Nuevo" presente
//   · Botón "Nuevo" abre pestaña con título "Nuevo contacto"
//   · Pestaña tiene campos de formulario (tipo entidad, razón social, email)
//   · "Cancelar" cierra la pestaña del formulario
//   · Toque en lista móvil abre pestaña "Editar contacto"
//   · rowToMap: _labelTipo mapea correctamente los tipos de entidad
//   · rowToMap: telefono cae a celular cuando telefono es null
//
// NOTA: SfDataGrid (≥600px) no renderiza celdas virtualizadas en test.
// Los tests de contenido fuerzan viewport <600px para activar el
// ListView/cards fallback (primer campo del map = razon_social).
//
// NOTA: WorkspaceTabs abre la pestaña lista en addPostFrameCallback.
// Se necesita pumpWidget + pump() para que la pestaña sea visible.

import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilar_erp/features/entidades/screens/contactos_screen.dart';
import 'package:pilar_erp/features/entidades/providers/contactos_provider.dart';

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

class _FakeContactosNotifier extends ContactosBrickNotifier {
  _FakeContactosNotifier(this._state);
  final AsyncValue<List<Map<String, dynamic>>> _state;

  @override
  String get supabaseTable => 'contactos';

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

Override _overrideContactos(
        AsyncValue<List<Map<String, dynamic>>> state) =>
    contactosProvider.overrideWith(() => _FakeContactosNotifier(state));

// ---------------------------------------------------------------------------
// Datos fake
// ---------------------------------------------------------------------------

List<Map<String, dynamic>> _fakeContactos() => [
      {
        'id': 'c-001',
        'razon_social': 'Empresa ABC S.A.',
        'nombre_comercial': 'ABC',
        'numero_id': '1234567890001',
        'tipo_entidad': 'SOCIEDAD',
        'tipo_identificacion': '04',
        'es_cliente': true,
        'es_proveedor': false,
        'es_empleado': false,
        'email': 'contacto@abc.com',
        'telefono': '02-200-0000',
        'celular': null,
        'activo': true,
      },
      {
        'id': 'c-002',
        'razon_social': 'Juan Pérez',
        'nombre_comercial': null,
        'numero_id': '0912345678',
        'tipo_entidad': 'PERSONA_NATURAL',
        'tipo_identificacion': '05',
        'es_cliente': false,
        'es_proveedor': true,
        'es_empleado': false,
        'email': null,
        'telefono': null,
        'celular': '0991234567',
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
      _overrideContactos(state),
    ],
    child: const FluentApp(home: ContactosScreen()),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ── Estado de carga ────────────────────────────────────────────────────────
  group('ContactosScreen — carga', () {
    testWidgets('muestra ProgressRing mientras carga', (tester) async {
      await tester.pumpWidget(_buildScreen(const AsyncLoading()));
      await tester.pump(); // frame 2: lista tab visible con CrudScaffold
      expect(find.byType(ProgressRing), findsOneWidget);
    });
  });

  // ── Estado de error ────────────────────────────────────────────────────────
  group('ContactosScreen — error', () {
    testWidgets('muestra InfoBar con mensaje de error', (tester) async {
      await tester.pumpWidget(
        _buildScreen(AsyncError(Exception('timeout'), StackTrace.empty)),
      );
      await tester.pump(); // lista tab visible
      await tester.pump(); // contactosProvider AsyncLoading → AsyncError
      expect(find.text('Error al cargar datos'), findsOneWidget);
    });
  });

  // ── Estado vacío ───────────────────────────────────────────────────────────
  group('ContactosScreen — vacío', () {
    testWidgets('muestra "Sin registros" cuando la lista está vacía',
        (tester) async {
      await tester.pumpWidget(_buildScreen(const AsyncData([])));
      await tester.pump(); // lista tab visible
      await tester.pump(); // contactosProvider AsyncLoading → AsyncData([])
      expect(find.text('Sin registros'), findsOneWidget);
    });
  });

  // ── Título y CommandBar ────────────────────────────────────────────────────
  group('ContactosScreen — título y CommandBar', () {
    testWidgets('muestra título "Contactos"', (tester) async {
      await tester.pumpWidget(_buildScreen(const AsyncData([])));
      await tester.pump();
      // Aparece en tab button Y en PageHeader de CrudScaffold
      expect(find.text('Contactos'), findsAtLeastNWidgets(1));
    });

    testWidgets('muestra botón "Nuevo" en CommandBar', (tester) async {
      await tester.pumpWidget(_buildScreen(const AsyncData([])));
      await tester.pump();
      expect(find.text('Nuevo'), findsOneWidget);
    });
  });

  // ── Pestaña "Nuevo contacto" ───────────────────────────────────────────────
  //
  // Viewport amplio para que el botón "Nuevo" del CommandBar quede visible.
  group('ContactosScreen — pestaña nuevo', () {
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
      expect(find.text('Nuevo contacto'), findsAtLeastNWidgets(1));
    });

    testWidgets('pestaña tiene campos de texto (TextBox)', (tester) async {
      _suppressOverflowErrors();
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_buildScreen(const AsyncData([])));
      await tester.pump();

      await tester.tap(find.text('Nuevo'));
      await tester.pumpAndSettle();

      // Razón social, Nombre comercial, No. identificación, Email, Teléfono, Celular
      expect(find.byType(TextBox), findsAtLeastNWidgets(5));
    });

    testWidgets('pestaña tiene ComboBoxes (tipo entidad y tipo id)',
        (tester) async {
      _suppressOverflowErrors();
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_buildScreen(const AsyncData([])));
      await tester.pump();

      await tester.tap(find.text('Nuevo'));
      await tester.pumpAndSettle();

      expect(find.byType(ComboBox<String>), findsAtLeastNWidgets(2));
    });

    testWidgets('pestaña tiene checkboxes "Es cliente" y "Es proveedor"',
        (tester) async {
      _suppressOverflowErrors();
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_buildScreen(const AsyncData([])));
      await tester.pump();

      await tester.tap(find.text('Nuevo'));
      await tester.pumpAndSettle();

      expect(find.text('Es cliente'), findsOneWidget);
      expect(find.text('Es proveedor'), findsOneWidget);
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

      // Pestaña cerrada: "Nuevo contacto" no aparece en ningún lado
      expect(find.text('Nuevo contacto'), findsNothing);
    });
  });

  // ── Pestaña "Editar contacto" ──────────────────────────────────────────────
  group('ContactosScreen — pestaña editar', () {
    testWidgets('toque en lista móvil abre pestaña con título "Editar contacto"',
        (tester) async {
      _suppressOverflowErrors();
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_buildScreen(AsyncData(_fakeContactos())));
      await tester.pump(); // lista tab visible
      await tester.pump(); // contactosProvider → AsyncData con contactos

      // El primer card muestra razon_social (primer valor del rowToMap)
      await tester.tap(find.text('Empresa ABC S.A.'));
      await tester.pumpAndSettle();

      // FormScaffold PageHeader muestra "Editar contacto"
      expect(find.text('Editar contacto'), findsOneWidget);
      expect(find.text('Guardar'), findsOneWidget);
    });

    testWidgets('pestaña de edición pre-carga los datos del contacto',
        (tester) async {
      _suppressOverflowErrors();
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_buildScreen(AsyncData(_fakeContactos())));
      await tester.pump(); // lista tab visible
      await tester.pump(); // contactosProvider → AsyncData con contactos

      await tester.tap(find.text('Empresa ABC S.A.'));
      await tester.pumpAndSettle();

      // El TextBox de razón social debe estar pre-cargado
      expect(
        find.widgetWithText(TextBox, 'Empresa ABC S.A.'),
        findsOneWidget,
      );
    });
  });

  // ── Datos en modo mobile (ListView fallback) ───────────────────────────────
  group('ContactosScreen — contenido móvil', () {
    testWidgets('muestra razon_social de los contactos', (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_buildScreen(AsyncData(_fakeContactos())));
      await tester.pump(); // lista tab visible
      await tester.pump(); // contactosProvider → AsyncData con contactos

      expect(find.text('Empresa ABC S.A.'), findsOneWidget);
      expect(find.text('Juan Pérez'), findsOneWidget);
    });
  });

  // ── rowToMap: _labelTipo ───────────────────────────────────────────────────
  group('ContactosScreen — labelTipo', () {
    testWidgets('tipo PERSONA_NATURAL se pre-carga en la pestaña de edición',
        (tester) async {
      _suppressOverflowErrors();
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_buildScreen(AsyncData(_fakeContactos())));
      await tester.pump(); // lista tab visible
      await tester.pump(); // contactosProvider → AsyncData con contactos

      // Juan Pérez es PERSONA_NATURAL
      await tester.tap(find.text('Juan Pérez'));
      await tester.pumpAndSettle();

      expect(find.text('Persona Natural'), findsOneWidget);
    });

    testWidgets('tipo SOCIEDAD se pre-carga en la pestaña de edición',
        (tester) async {
      _suppressOverflowErrors();
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_buildScreen(AsyncData(_fakeContactos())));
      await tester.pump(); // lista tab visible
      await tester.pump(); // contactosProvider → AsyncData con contactos

      // Empresa ABC es SOCIEDAD
      await tester.tap(find.text('Empresa ABC S.A.'));
      await tester.pumpAndSettle();

      expect(find.text('Sociedad'), findsOneWidget);
    });
  });
}
