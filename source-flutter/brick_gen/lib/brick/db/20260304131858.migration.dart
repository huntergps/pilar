// GENERATED CODE EDIT WITH CAUTION
// THIS FILE **WILL NOT** BE REGENERATED
// This file should be version controlled and can be manually edited.
part of 'schema.g.dart';

// While migrations are intelligently created, the difference between some commands, such as
// DropTable vs. RenameTable, cannot be determined. For this reason, please review migrations after
// they are created to ensure the correct inference was made.

// The migration version must **always** mirror the file name

const List<MigrationCommand> _migration_20260304131858_up = [
  InsertColumn('version', Column.integer, onTable: 'AlertaEmpresa'),
  InsertColumn('version', Column.integer, onTable: 'Contacto'),
  InsertColumn('version', Column.integer, onTable: 'Empresa'),
  InsertColumn('version', Column.integer, onTable: 'ModuloEmpresa'),
  InsertColumn('version', Column.integer, onTable: 'Producto'),
  InsertColumn('version', Column.integer, onTable: 'ProductoFamilia')
];

const List<MigrationCommand> _migration_20260304131858_down = [
  DropColumn('version', onTable: 'AlertaEmpresa'),
  DropColumn('version', onTable: 'Contacto'),
  DropColumn('version', onTable: 'Empresa'),
  DropColumn('version', onTable: 'ModuloEmpresa'),
  DropColumn('version', onTable: 'Producto'),
  DropColumn('version', onTable: 'ProductoFamilia')
];

//
// DO NOT EDIT BELOW THIS LINE
//

@Migratable(
  version: '20260304131858',
  up: _migration_20260304131858_up,
  down: _migration_20260304131858_down,
)
class Migration20260304131858 extends Migration {
  const Migration20260304131858()
    : super(
        version: 20260304131858,
        up: _migration_20260304131858_up,
        down: _migration_20260304131858_down,
      );
}
