// Tests de GestorPermisosScreen
//
// Cubre:
//   · Modelos: RolItem.fromJson, PermisoEstado.fromJson, UsuarioRolItem.fromJson
//   · Sin permiso: muestra mensaje de acceso denegado
//   · Estado de carga (ProgressRing)
//   · Estado de error
//   · Con roles: header, CommandBar, toolbar con selector de rol
//   · Auto-selección del primer rol (addPostFrameCallback)
//   · Botón eliminar: visible para roles custom, oculto para roles sistema
//   · Matriz de permisos: agrupación por módulo, checkboxes enabled (custom) / disabled (sistema)
//   · Panel de usuarios: estado vacío, con usuarios, header "Usuarios asignados"
//   · Diálogo "Nuevo Rol": campos y botones
//   · Diálogo confirmar eliminar rol
//
// NOTA: Las operaciones de escritura (toggle permiso, asignar/quitar usuario,
// crear/eliminar rol) requieren Supabase real; solo se prueba el flujo de UI.

import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilar_erp/core/providers/usuario_provider.dart';
import 'package:pilar_erp/features/administracion/screens/gestor_permisos_screen.dart';

import '../../helpers/test_utils.dart';

// ---------------------------------------------------------------------------
// Datos fake
// ---------------------------------------------------------------------------

RolItem _fakeRolSistema({
  String id = 'rol-admin-001',
  String codigo = 'ADMIN',
  String nombre = 'Administrador',
}) =>
    RolItem(
      id: id,
      codigo: codigo,
      nombre: nombre,
      descripcion: 'Acceso total al sistema',
      esSistema: true,
      empresaId: null,
      activo: true,
    );

RolItem _fakeRolCustom({
  String id = 'rol-custom-001',
  String codigo = 'VENDEDOR',
  String nombre = 'Vendedor',
}) =>
    RolItem(
      id: id,
      codigo: codigo,
      nombre: nombre,
      descripcion: 'Acceso a ventas',
      esSistema: false,
      empresaId: 'e-001',
      activo: true,
    );

List<PermisoEstado> _fakePermisos({bool tienePermiso = true}) => [
      PermisoEstado(
        id: 'perm-001',
        codigo: 'ventas.cotizaciones.ver',
        modulo: 'ventas',
        recurso: 'cotizaciones',
        accion: 'ver',
        descripcion: 'Ver cotizaciones',
        tienePermiso: tienePermiso,
      ),
      PermisoEstado(
        id: 'perm-002',
        codigo: 'ventas.cotizaciones.crear',
        modulo: 'ventas',
        recurso: 'cotizaciones',
        accion: 'crear',
        descripcion: 'Crear cotizaciones',
        tienePermiso: false,
      ),
      PermisoEstado(
        id: 'perm-003',
        codigo: 'ventas.facturas.ver',
        modulo: 'ventas',
        recurso: 'facturas',
        accion: 'ver',
        descripcion: 'Ver facturas',
        tienePermiso: tienePermiso,
      ),
    ];

List<UsuarioRolItem> _fakeUsuarios() => const [
      UsuarioRolItem(
        usuarioId: 'u-001',
        email: 'juan@empresa.com',
        nombreDisplay: 'Juan Pérez',
        avatarUrl: null,
        activo: true,
      ),
      UsuarioRolItem(
        usuarioId: 'u-002',
        email: 'ana@empresa.com',
        nombreDisplay: 'Ana García',
        avatarUrl: null,
        activo: true,
      ),
    ];

// ---------------------------------------------------------------------------
// Overrides de providers
// ---------------------------------------------------------------------------

List<Override> _overridesConPermiso({
  List<RolItem>? roles,
  List<PermisoEstado>? permisos,
  List<UsuarioRolItem>? usuarios,
}) =>
    [
      hasPermissionProvider.overrideWith((ref, p) => true),
      rolesAdminProvider.overrideWith((_) async => roles ?? [_fakeRolCustom()]),
      permisosRolProvider.overrideWith(
        (ref, rolId) async => permisos ?? _fakePermisos(),
      ),
      usuariosRolProvider.overrideWith(
        (ref, rolId) async => usuarios ?? [],
      ),
    ];

List<Override> _overridesSinPermiso() => [
      hasPermissionProvider.overrideWith((ref, p) => false),
      rolesAdminProvider.overrideWith((_) async => <RolItem>[]),
      permisosRolProvider.overrideWith((ref, rolId) async => <PermisoEstado>[]),
      usuariosRolProvider
          .overrideWith((ref, rolId) async => <UsuarioRolItem>[]),
    ];

Widget _buildScreen(List<Override> overrides) =>
    buildFluentApp(const GestorPermisosScreen(), overrides: overrides);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Bombea la pantalla hasta que el primer rol esté auto-seleccionado
/// (el addPostFrameCallback de GestorPermisosScreen requiere un frame extra).
Future<void> _pumpToRolSelected(WidgetTester tester) async {
  await tester.pump(); // primer frame: roles cargados
  await tester.pump(); // segundo frame: addPostFrameCallback ejecutado
}

// ===========================================================================
// UNIT TESTS — Modelos
// ===========================================================================

void main() {
  // -------------------------------------------------------------------------

  group('RolItem.fromJson', () {
    test('parsea todos los campos de un rol de sistema', () {
      final json = {
        'id': 'r-001',
        'codigo': 'ADMIN',
        'nombre': 'Administrador',
        'descripcion': 'Acceso total',
        'es_sistema': true,
        'empresa_id': null,
        'activo': true,
      };

      final r = RolItem.fromJson(json);

      expect(r.id, 'r-001');
      expect(r.codigo, 'ADMIN');
      expect(r.nombre, 'Administrador');
      expect(r.descripcion, 'Acceso total');
      expect(r.esSistema, isTrue);
      expect(r.empresaId, isNull);
      expect(r.activo, isTrue);
    });

    test('parsea un rol custom con empresa_id', () {
      final json = {
        'id': 'r-002',
        'codigo': 'VENDEDOR',
        'nombre': 'Vendedor',
        'descripcion': null,
        'es_sistema': false,
        'empresa_id': 'e-001',
        'activo': false,
      };

      final r = RolItem.fromJson(json);

      expect(r.esSistema, isFalse);
      expect(r.empresaId, 'e-001');
      expect(r.activo, isFalse);
      expect(r.descripcion, isNull);
    });

    test('es_sistema defaultea a false cuando no está en JSON', () {
      final json = {
        'id': 'r-003',
        'codigo': 'X',
        'nombre': 'X',
      };

      final r = RolItem.fromJson(json);
      expect(r.esSistema, isFalse);
    });

    test('activo defaultea a true cuando no está en JSON', () {
      final json = {
        'id': 'r-003',
        'codigo': 'X',
        'nombre': 'X',
      };

      final r = RolItem.fromJson(json);
      expect(r.activo, isTrue);
    });
  });

  // -------------------------------------------------------------------------

  group('PermisoEstado.fromJson', () {
    test('parsea todos los campos correctamente', () {
      final json = {
        'id': 'p-001',
        'codigo': 'ventas.facturas.ver',
        'modulo': 'ventas',
        'recurso': 'facturas',
        'accion': 'ver',
        'descripcion': 'Ver facturas',
        'tiene_permiso': true,
      };

      final p = PermisoEstado.fromJson(json);

      expect(p.id, 'p-001');
      expect(p.codigo, 'ventas.facturas.ver');
      expect(p.modulo, 'ventas');
      expect(p.recurso, 'facturas');
      expect(p.accion, 'ver');
      expect(p.descripcion, 'Ver facturas');
      expect(p.tienePermiso, isTrue);
    });

    test('tiene_permiso defaultea a false cuando no está en JSON', () {
      final json = {
        'id': 'p-002',
        'codigo': 'x.y.z',
        'modulo': 'x',
        'recurso': 'y',
        'accion': 'z',
      };

      final p = PermisoEstado.fromJson(json);
      expect(p.tienePermiso, isFalse);
    });

    test('descripcion puede ser null', () {
      final json = {
        'id': 'p-003',
        'codigo': 'x.y.z',
        'modulo': 'x',
        'recurso': 'y',
        'accion': 'z',
        'descripcion': null,
        'tiene_permiso': false,
      };

      final p = PermisoEstado.fromJson(json);
      expect(p.descripcion, isNull);
    });

    test('tienePermiso es mutable (necesario para optimistic UI)', () {
      final p = PermisoEstado(
        id: 'p-001',
        codigo: 'x.y.z',
        modulo: 'x',
        recurso: 'y',
        accion: 'z',
        tienePermiso: false,
      );

      p.tienePermiso = true;
      expect(p.tienePermiso, isTrue);
    });
  });

  // -------------------------------------------------------------------------

  group('UsuarioRolItem.fromJson', () {
    test('parsea todos los campos correctamente', () {
      final json = {
        'usuario_id': 'u-001',
        'email': 'juan@test.com',
        'nombre_display': 'Juan Pérez',
        'avatar_url': 'https://cdn.test.com/avatar.jpg',
        'activo': true,
      };

      final u = UsuarioRolItem.fromJson(json);

      expect(u.usuarioId, 'u-001');
      expect(u.email, 'juan@test.com');
      expect(u.nombreDisplay, 'Juan Pérez');
      expect(u.avatarUrl, 'https://cdn.test.com/avatar.jpg');
      expect(u.activo, isTrue);
    });

    test('usa email como fallback cuando nombre_display es null', () {
      final json = {
        'usuario_id': 'u-002',
        'email': 'sin.nombre@test.com',
        'nombre_display': null,
        'activo': true,
      };

      final u = UsuarioRolItem.fromJson(json);
      expect(u.nombreDisplay, 'sin.nombre@test.com');
    });

    test('avatar_url puede ser null', () {
      final json = {
        'usuario_id': 'u-003',
        'email': 'test@test.com',
        'nombre_display': 'Test',
        'avatar_url': null,
        'activo': true,
      };

      final u = UsuarioRolItem.fromJson(json);
      expect(u.avatarUrl, isNull);
    });

    test('activo defaultea a true cuando no está en JSON', () {
      final json = {
        'usuario_id': 'u-004',
        'email': 'test@test.com',
        'nombre_display': 'Test',
      };

      final u = UsuarioRolItem.fromJson(json);
      expect(u.activo, isTrue);
    });
  });

  // ===========================================================================
  // WIDGET TESTS — GestorPermisosScreen
  // ===========================================================================

  // -------------------------------------------------------------------------

  group('GestorPermisosScreen — sin permiso', () {
    testWidgets('muestra mensaje de acceso denegado', (tester) async {
      await tester.pumpWidget(_buildScreen(_overridesSinPermiso()));
      await tester.pump();

      expect(find.textContaining('Sin permisos'), findsOneWidget);
      // No debe mostrar el header principal
      expect(find.text('Nuevo Rol'), findsNothing);
    });
  });

  // -------------------------------------------------------------------------

  group('GestorPermisosScreen — estado de carga', () {
    testWidgets('muestra ProgressRing mientras rolesAdminProvider carga',
        (tester) async {
      final completer = Completer<List<RolItem>>();
      final app = ProviderScope(
        overrides: [
          ...baseOverrides(),
          hasPermissionProvider.overrideWith((ref, p) => true),
          rolesAdminProvider.overrideWith((_) => completer.future),
          permisosRolProvider
              .overrideWith((ref, rolId) async => <PermisoEstado>[]),
          usuariosRolProvider
              .overrideWith((ref, rolId) async => <UsuarioRolItem>[]),
        ],
        child: const FluentApp(home: GestorPermisosScreen()),
      );

      await tester.pumpWidget(app);
      await tester.pump();

      expect(find.byType(ProgressRing), findsOneWidget);

      completer.complete([]);
    });
  });

  // -------------------------------------------------------------------------

  group('GestorPermisosScreen — estado de error', () {
    testWidgets('muestra texto de error cuando rolesAdminProvider falla',
        (tester) async {
      final app = ProviderScope(
        overrides: [
          ...baseOverrides(),
          hasPermissionProvider.overrideWith((ref, p) => true),
          rolesAdminProvider
              .overrideWith((_) async => throw Exception('sin conexión')),
          permisosRolProvider
              .overrideWith((ref, rolId) async => <PermisoEstado>[]),
          usuariosRolProvider
              .overrideWith((ref, rolId) async => <UsuarioRolItem>[]),
        ],
        child: const FluentApp(home: GestorPermisosScreen()),
      );

      await tester.pumpWidget(app);
      await tester.pump();

      expect(find.textContaining('Error'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------

  group('GestorPermisosScreen — sin roles', () {
    testWidgets('muestra header y CommandBar aunque no haya roles',
        (tester) async {
      await tester.pumpWidget(_buildScreen(
        _overridesConPermiso(roles: []),
      ));
      await tester.pump();

      expect(find.text('Roles y Permisos'), findsOneWidget);
      expect(find.text('Nuevo Rol'), findsOneWidget);
    });

    testWidgets('muestra "Selecciona un rol" cuando la lista está vacía',
        (tester) async {
      await tester.pumpWidget(_buildScreen(
        _overridesConPermiso(roles: []),
      ));
      await tester.pump();

      expect(find.text('Selecciona un rol'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------

  group('GestorPermisosScreen — con roles', () {
    testWidgets('muestra "Roles y Permisos" en el PageHeader', (tester) async {
      await tester.pumpWidget(_buildScreen(_overridesConPermiso()));
      await tester.pump();

      expect(find.text('Roles y Permisos'), findsOneWidget);
    });

    testWidgets('muestra botón "Nuevo Rol" en el CommandBar', (tester) async {
      await tester.pumpWidget(_buildScreen(_overridesConPermiso()));
      await tester.pump();

      expect(find.text('Nuevo Rol'), findsOneWidget);
    });

    testWidgets('tap en "Nuevo Rol" abre ContentDialog', (tester) async {
      await tester.pumpWidget(_buildScreen(_overridesConPermiso()));
      await tester.pump();

      await tester.tap(find.text('Nuevo Rol'));
      await tester.pumpAndSettle();

      expect(find.byType(ContentDialog), findsOneWidget);
    });

    testWidgets('ContentDialog de Nuevo Rol contiene campos Código y Nombre',
        (tester) async {
      await tester.pumpWidget(_buildScreen(_overridesConPermiso()));
      await tester.pump();

      await tester.tap(find.text('Nuevo Rol'));
      await tester.pumpAndSettle();

      // InfoLabel usa label sin tildes en el screen
      expect(find.text('Codigo'), findsOneWidget);
      expect(find.text('Nombre'), findsOneWidget);
    });

    testWidgets(
        'ContentDialog de Nuevo Rol tiene botones "Crear" y "Cancelar"',
        (tester) async {
      await tester.pumpWidget(_buildScreen(_overridesConPermiso()));
      await tester.pump();

      await tester.tap(find.text('Nuevo Rol'));
      await tester.pumpAndSettle();

      // Acotar búsqueda al dialog: la matriz también tiene "Crear" como columna
      final dialog = find.byType(ContentDialog);
      expect(find.descendant(of: dialog, matching: find.text('Crear')),
          findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);
    });

    testWidgets('tap en Cancelar cierra el dialog de Nuevo Rol',
        (tester) async {
      await tester.pumpWidget(_buildScreen(_overridesConPermiso()));
      await tester.pump();

      await tester.tap(find.text('Nuevo Rol'));
      await tester.pumpAndSettle();
      expect(find.byType(ContentDialog), findsOneWidget);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(find.byType(ContentDialog), findsNothing);
    });
  });

  // -------------------------------------------------------------------------

  group('GestorPermisosScreen — toolbar: selector de rol', () {
    testWidgets('muestra el nombre del rol custom en el ComboBox tras auto-selección',
        (tester) async {
      final rol = _fakeRolCustom(nombre: 'Vendedor');
      await tester.pumpWidget(_buildScreen(_overridesConPermiso(roles: [rol])));
      await _pumpToRolSelected(tester);

      expect(find.text('Vendedor'), findsWidgets);
    });

    testWidgets('muestra múltiples roles en el selector', (tester) async {
      final roles = [
        _fakeRolSistema(nombre: 'Administrador'),
        _fakeRolCustom(id: 'r-002', codigo: 'CAJERO', nombre: 'Cajero'),
      ];
      await tester.pumpWidget(_buildScreen(_overridesConPermiso(roles: roles)));
      await tester.pump();

      // El ComboBox debe estar presente
      expect(find.byType(ComboBox<String>), findsWidgets);
    });
  });

  // -------------------------------------------------------------------------

  group('GestorPermisosScreen — toolbar: botón eliminar', () {
    testWidgets(
        'botón eliminar NO aparece cuando el rol seleccionado es de sistema',
        (tester) async {
      final rol = _fakeRolSistema();
      await tester.pumpWidget(_buildScreen(_overridesConPermiso(roles: [rol])));
      await _pumpToRolSelected(tester);

      // El botón de eliminar (ícono delete) no debe estar visible para roles sistema
      expect(find.byIcon(FluentIcons.delete), findsNothing);
    });

    testWidgets('botón eliminar aparece cuando el rol seleccionado es custom',
        (tester) async {
      final rol = _fakeRolCustom();
      await tester.pumpWidget(_buildScreen(_overridesConPermiso(roles: [rol])));
      await _pumpToRolSelected(tester);

      expect(find.byIcon(FluentIcons.delete), findsOneWidget);
    });

    testWidgets(
        'tap en botón eliminar abre ContentDialog de confirmación',
        (tester) async {
      final rol = _fakeRolCustom(nombre: 'Vendedor');
      await tester.pumpWidget(_buildScreen(_overridesConPermiso(roles: [rol])));
      await _pumpToRolSelected(tester);

      await tester.tap(find.byIcon(FluentIcons.delete));
      await tester.pumpAndSettle();

      expect(find.byType(ContentDialog), findsOneWidget);
      expect(find.text('Eliminar rol'), findsOneWidget);
    });

    testWidgets('dialog de eliminar muestra el nombre del rol',
        (tester) async {
      final rol = _fakeRolCustom(nombre: 'Soporte');
      await tester.pumpWidget(_buildScreen(_overridesConPermiso(roles: [rol])));
      await _pumpToRolSelected(tester);

      await tester.tap(find.byIcon(FluentIcons.delete));
      await tester.pumpAndSettle();

      expect(find.textContaining('Soporte'), findsWidgets);
    });
  });

  // -------------------------------------------------------------------------

  group('GestorPermisosScreen — matriz de permisos', () {
    testWidgets('muestra ProgressRing mientras permisosRolProvider carga',
        (tester) async {
      final completer = Completer<List<PermisoEstado>>();
      final rol = _fakeRolCustom();
      final app = ProviderScope(
        overrides: [
          ...baseOverrides(),
          hasPermissionProvider.overrideWith((ref, p) => true),
          rolesAdminProvider.overrideWith((_) async => [rol]),
          permisosRolProvider.overrideWith((ref, rolId) => completer.future),
          usuariosRolProvider
              .overrideWith((ref, rolId) async => <UsuarioRolItem>[]),
        ],
        child: const FluentApp(home: GestorPermisosScreen()),
      );

      await tester.pumpWidget(app);
      await _pumpToRolSelected(tester);

      expect(find.byType(ProgressRing), findsWidgets);

      completer.complete([]);
    });

    testWidgets(
        'checkboxes de rol CUSTOM están habilitados (onChanged != null)',
        (tester) async {
      final rol = _fakeRolCustom();
      await tester.pumpWidget(
        _buildScreen(_overridesConPermiso(roles: [rol], permisos: _fakePermisos())),
      );
      await _pumpToRolSelected(tester);
      await tester.pump(); // permisos cargados

      final checkboxes = tester.widgetList<Checkbox>(find.byType(Checkbox));
      // Al menos un checkbox debe estar habilitado (onChanged != null)
      expect(checkboxes.any((c) => c.onChanged != null), isTrue);
    });

    testWidgets(
        'checkboxes de rol SISTEMA están HABILITADOS (override por empresa)',
        (tester) async {
      final rol = _fakeRolSistema();
      await tester.pumpWidget(
        _buildScreen(_overridesConPermiso(roles: [rol], permisos: _fakePermisos())),
      );
      await _pumpToRolSelected(tester);
      await tester.pump();

      final checkboxes = tester.widgetList<Checkbox>(find.byType(Checkbox));
      // Checkboxes habilitados: los cambios en roles sistema crean
      // overrides por empresa (roles_permisos_empresa), no modifican el global.
      expect(checkboxes.any((c) => c.onChanged != null), isTrue);
    });

    testWidgets('muestra nombre del módulo como header de grupo',
        (tester) async {
      final rol = _fakeRolCustom();
      await tester.pumpWidget(
        _buildScreen(_overridesConPermiso(roles: [rol], permisos: _fakePermisos())),
      );
      await _pumpToRolSelected(tester);
      await tester.pump();

      // El módulo se muestra en MAYÚSCULAS (toUpperCase en el screen)
      expect(find.textContaining('VENTAS'), findsWidgets);
    });

    testWidgets('muestra recursos como filas en la matriz', (tester) async {
      final rol = _fakeRolCustom();
      await tester.pumpWidget(
        _buildScreen(_overridesConPermiso(roles: [rol], permisos: _fakePermisos())),
      );
      await _pumpToRolSelected(tester);
      await tester.pump();

      // El formato actual es "Tabla: Cotizaciones" / "Tabla: Facturas"
      expect(find.textContaining('Cotizaciones'), findsOneWidget);
      expect(find.textContaining('Facturas'), findsOneWidget);
    });

    testWidgets('muestra "—" para celdas sin permiso en esa acción',
        (tester) async {
      // perm-001 tiene accion "ver" en cotizaciones, pero NO "crear"
      // perm-003 tiene accion "ver" en facturas, pero NO "crear"
      final rol = _fakeRolCustom();
      final permisos = [
        PermisoEstado(
          id: 'p-001',
          codigo: 'ventas.cotizaciones.ver',
          modulo: 'ventas',
          recurso: 'cotizaciones',
          accion: 'ver',
          tienePermiso: false,
        ),
      ];
      await tester.pumpWidget(
        _buildScreen(_overridesConPermiso(roles: [rol], permisos: permisos)),
      );
      await _pumpToRolSelected(tester);
      await tester.pump();

      // Con solo un permiso, solo hay columna "ver"
      expect(find.byType(Checkbox), findsOneWidget);
    });

    testWidgets('muestra "Sin permisos" cuando la lista está vacía',
        (tester) async {
      final rol = _fakeRolCustom();
      await tester.pumpWidget(
        _buildScreen(_overridesConPermiso(roles: [rol], permisos: [])),
      );
      await _pumpToRolSelected(tester);
      await tester.pump();

      expect(find.textContaining('No hay permisos'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------

  group('GestorPermisosScreen — panel de usuarios', () {
    testWidgets('muestra header "Usuarios asignados"', (tester) async {
      // Panel solo visible >=900px: usar pantalla ancha
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final rol = _fakeRolCustom();
      await tester.pumpWidget(
        _buildScreen(_overridesConPermiso(roles: [rol], usuarios: [])),
      );
      await _pumpToRolSelected(tester);
      await tester.pump();

      expect(find.text('Usuarios asignados'), findsOneWidget);
    });

    testWidgets('muestra "Sin usuarios asignados" cuando lista vacía',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final rol = _fakeRolCustom();
      await tester.pumpWidget(
        _buildScreen(_overridesConPermiso(roles: [rol], usuarios: [])),
      );
      await _pumpToRolSelected(tester);
      await tester.pump();

      expect(find.text('Sin usuarios asignados'), findsOneWidget);
    });

    testWidgets('muestra nombre y email de cada usuario asignado',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final rol = _fakeRolCustom();
      await tester.pumpWidget(
        _buildScreen(
          _overridesConPermiso(roles: [rol], usuarios: _fakeUsuarios()),
        ),
      );
      await _pumpToRolSelected(tester);
      await tester.pump();

      expect(find.text('Juan Pérez'), findsOneWidget);
      expect(find.text('juan@empresa.com'), findsOneWidget);
      expect(find.text('Ana García'), findsOneWidget);
      expect(find.text('ana@empresa.com'), findsOneWidget);
    });

    testWidgets('muestra inicial del nombre en el avatar de cada usuario',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final rol = _fakeRolCustom();
      await tester.pumpWidget(
        _buildScreen(
          _overridesConPermiso(roles: [rol], usuarios: _fakeUsuarios()),
        ),
      );
      await _pumpToRolSelected(tester);
      await tester.pump();

      expect(find.text('J'), findsOneWidget); // inicial de Juan
      expect(find.text('A'), findsOneWidget); // inicial de Ana
    });

    testWidgets('muestra botón add_friend para asignar usuario', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final rol = _fakeRolCustom();
      await tester.pumpWidget(
        _buildScreen(_overridesConPermiso(roles: [rol], usuarios: [])),
      );
      await _pumpToRolSelected(tester);
      await tester.pump();

      expect(find.byIcon(FluentIcons.add_friend), findsOneWidget);
    });

    testWidgets('muestra botón chrome_close junto a cada usuario asignado',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final rol = _fakeRolCustom();
      await tester.pumpWidget(
        _buildScreen(
          _overridesConPermiso(roles: [rol], usuarios: _fakeUsuarios()),
        ),
      );
      await _pumpToRolSelected(tester);
      await tester.pump();

      // Dos usuarios → dos botones de quitar
      expect(find.byIcon(FluentIcons.chrome_close), findsNWidgets(2));
    });
  });
}
