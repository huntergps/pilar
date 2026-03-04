// GENERATED CODE EDIT WITH CAUTION
// THIS FILE **WILL NOT** BE REGENERATED
// This file should be version controlled and can be manually edited.
part of 'schema.g.dart';

// Adds new columns to Contacto (cargo, website, direccion, notas),
// new column to Producto (codigo_principal_barras),
// and new table ProductoFamilia.

const List<MigrationCommand> _migration_20260303000100_up = [
  // Contacto: new fields
  InsertColumn('cargo', Column.varchar, onTable: 'Contacto'),
  InsertColumn('website', Column.varchar, onTable: 'Contacto'),
  InsertColumn('direccion', Column.varchar, onTable: 'Contacto'),
  InsertColumn('notas', Column.varchar, onTable: 'Contacto'),
  // Producto: new field
  InsertColumn('codigo_principal_barras', Column.varchar, onTable: 'Producto'),
  // ProductoFamilia: new table
  InsertTable('ProductoFamilia'),
  InsertColumn('id', Column.varchar, onTable: 'ProductoFamilia'),
  InsertColumn('nombre', Column.varchar, onTable: 'ProductoFamilia'),
  InsertColumn('descripcion', Column.varchar, onTable: 'ProductoFamilia'),
  InsertColumn('activo', Column.boolean, onTable: 'ProductoFamilia'),
];

const List<MigrationCommand> _migration_20260303000100_down = [
  DropColumn('cargo', onTable: 'Contacto'),
  DropColumn('website', onTable: 'Contacto'),
  DropColumn('direccion', onTable: 'Contacto'),
  DropColumn('notas', onTable: 'Contacto'),
  DropColumn('codigo_principal_barras', onTable: 'Producto'),
  DropTable('ProductoFamilia'),
];

//
// DO NOT EDIT BELOW THIS LINE
//

@Migratable(
  version: '20260303000100',
  up: _migration_20260303000100_up,
  down: _migration_20260303000100_down,
)
class Migration20260303000100 extends Migration {
  const Migration20260303000100()
    : super(
        version: 20260303000100,
        up: _migration_20260303000100_up,
        down: _migration_20260303000100_down,
      );
}
