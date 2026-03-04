// GENERATED CODE EDIT WITH CAUTION
// THIS FILE **WILL NOT** BE REGENERATED
// This file should be version controlled and can be manually edited.
part of 'schema.g.dart';

// While migrations are intelligently created, the difference between some commands, such as
// DropTable vs. RenameTable, cannot be determined. For this reason, please review migrations after
// they are created to ensure the correct inference was made.

// The migration version must **always** mirror the file name

const List<MigrationCommand> _migration_20260304173319_up = [
  DropColumn('tags', onTable: 'Adjunto'),
  DropColumn('icon_category', onTable: 'Adjunto'),
  DropColumn('tamanio_label', onTable: 'Adjunto'),
  DropColumn('extension', onTable: 'Adjunto'),
  DropColumn('adjuntos_ids', onTable: 'ChatterMensaje'),
  DropColumn('metadatos', onTable: 'ChatterMensaje'),
  DropColumn('es_log', onTable: 'ChatterMensaje'),
  DropColumn('es_comentario', onTable: 'ChatterMensaje'),
  DropColumn('es_email', onTable: 'ChatterMensaje'),
  DropColumn('es_actividad', onTable: 'ChatterMensaje'),
  DropColumn('es_nota_interna', onTable: 'ChatterMensaje'),
  DropColumn('tiene_adjuntos', onTable: 'ChatterMensaje'),
  DropColumn('tiene_campos_trackeados', onTable: 'ChatterMensaje'),
  DropColumn('autor_inicial', onTable: 'ChatterMensaje'),
  DropColumn('ventana_wa_activa', onTable: 'ComConversacion'),
  DropColumn('display_name', onTable: 'ComConversacion'),
  DropColumn('meta_parsed', onTable: 'ComConversacion'),
  DropColumn('es_inbound', onTable: 'ComMensaje'),
  DropColumn('es_outbound', onTable: 'ComMensaje'),
  DropColumn('es_fallido', onTable: 'ComMensaje'),
  DropColumn('tiene_media', onTable: 'ComMensaje')
];

const List<MigrationCommand> _migration_20260304173319_down = [
  
];

//
// DO NOT EDIT BELOW THIS LINE
//

@Migratable(
  version: '20260304173319',
  up: _migration_20260304173319_up,
  down: _migration_20260304173319_down,
)
class Migration20260304173319 extends Migration {
  const Migration20260304173319()
    : super(
        version: 20260304173319,
        up: _migration_20260304173319_up,
        down: _migration_20260304173319_down,
      );
}
