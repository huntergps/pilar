// GENERATED CODE EDIT WITH CAUTION
// THIS FILE **WILL NOT** BE REGENERATED
// This file should be version controlled and can be manually edited.
part of 'schema.g.dart';

// While migrations are intelligently created, the difference between some commands, such as
// DropTable vs. RenameTable, cannot be determined. For this reason, please review migrations after
// they are created to ensure the correct inference was made.

// The migration version must **always** mirror the file name

const List<MigrationCommand> _migration_20260302004206_up = [
  InsertTable('Contacto'),
  InsertTable('Producto'),
  InsertColumn('id', Column.varchar, onTable: 'Contacto'),
  InsertColumn('razon_social', Column.varchar, onTable: 'Contacto'),
  InsertColumn('nombre_comercial', Column.varchar, onTable: 'Contacto'),
  InsertColumn('numero_id', Column.varchar, onTable: 'Contacto'),
  InsertColumn('tipo_entidad', Column.varchar, onTable: 'Contacto'),
  InsertColumn('tipo_identificacion', Column.varchar, onTable: 'Contacto'),
  InsertColumn('es_cliente', Column.boolean, onTable: 'Contacto'),
  InsertColumn('es_proveedor', Column.boolean, onTable: 'Contacto'),
  InsertColumn('es_empleado', Column.boolean, onTable: 'Contacto'),
  InsertColumn('email', Column.varchar, onTable: 'Contacto'),
  InsertColumn('telefono', Column.varchar, onTable: 'Contacto'),
  InsertColumn('celular', Column.varchar, onTable: 'Contacto'),
  InsertColumn('activo', Column.boolean, onTable: 'Contacto'),
  InsertColumn('id', Column.varchar, onTable: 'Producto'),
  InsertColumn('codigo', Column.varchar, onTable: 'Producto'),
  InsertColumn('nombre', Column.varchar, onTable: 'Producto'),
  InsertColumn('tipo', Column.varchar, onTable: 'Producto'),
  InsertColumn('precio_venta', Column.Double, onTable: 'Producto'),
  InsertColumn('precio_costo', Column.Double, onTable: 'Producto'),
  InsertColumn('descripcion', Column.varchar, onTable: 'Producto'),
  InsertColumn('activo', Column.boolean, onTable: 'Producto')
];

const List<MigrationCommand> _migration_20260302004206_down = [
  DropTable('Contacto'),
  DropTable('Producto'),
  DropColumn('id', onTable: 'Contacto'),
  DropColumn('razon_social', onTable: 'Contacto'),
  DropColumn('nombre_comercial', onTable: 'Contacto'),
  DropColumn('numero_id', onTable: 'Contacto'),
  DropColumn('tipo_entidad', onTable: 'Contacto'),
  DropColumn('tipo_identificacion', onTable: 'Contacto'),
  DropColumn('es_cliente', onTable: 'Contacto'),
  DropColumn('es_proveedor', onTable: 'Contacto'),
  DropColumn('es_empleado', onTable: 'Contacto'),
  DropColumn('email', onTable: 'Contacto'),
  DropColumn('telefono', onTable: 'Contacto'),
  DropColumn('celular', onTable: 'Contacto'),
  DropColumn('activo', onTable: 'Contacto'),
  DropColumn('id', onTable: 'Producto'),
  DropColumn('codigo', onTable: 'Producto'),
  DropColumn('nombre', onTable: 'Producto'),
  DropColumn('tipo', onTable: 'Producto'),
  DropColumn('precio_venta', onTable: 'Producto'),
  DropColumn('precio_costo', onTable: 'Producto'),
  DropColumn('descripcion', onTable: 'Producto'),
  DropColumn('activo', onTable: 'Producto')
];

//
// DO NOT EDIT BELOW THIS LINE
//

@Migratable(
  version: '20260302004206',
  up: _migration_20260302004206_up,
  down: _migration_20260302004206_down,
)
class Migration20260302004206 extends Migration {
  const Migration20260302004206()
    : super(
        version: 20260302004206,
        up: _migration_20260302004206_up,
        down: _migration_20260302004206_down,
      );
}
