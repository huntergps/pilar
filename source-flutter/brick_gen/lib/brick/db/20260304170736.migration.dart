// GENERATED CODE EDIT WITH CAUTION
// THIS FILE **WILL NOT** BE REGENERATED
// This file should be version controlled and can be manually edited.
part of 'schema.g.dart';

// While migrations are intelligently created, the difference between some commands, such as
// DropTable vs. RenameTable, cannot be determined. For this reason, please review migrations after
// they are created to ensure the correct inference was made.

// The migration version must **always** mirror the file name

const List<MigrationCommand> _migration_20260304170736_up = [
  DropColumn('precio_venta', onTable: 'Producto'),
  DropColumn('precio_costo', onTable: 'Producto'),
  InsertColumn('precio_venta', Column.varchar, onTable: 'Producto'),
  InsertColumn('precio_costo', Column.varchar, onTable: 'Producto')
];

const List<MigrationCommand> _migration_20260304170736_down = [
  DropColumn('precio_venta', onTable: 'Producto'),
  DropColumn('precio_costo', onTable: 'Producto')
];

//
// DO NOT EDIT BELOW THIS LINE
//

@Migratable(
  version: '20260304170736',
  up: _migration_20260304170736_up,
  down: _migration_20260304170736_down,
)
class Migration20260304170736 extends Migration {
  const Migration20260304170736()
    : super(
        version: 20260304170736,
        up: _migration_20260304170736_up,
        down: _migration_20260304170736_down,
      );
}
