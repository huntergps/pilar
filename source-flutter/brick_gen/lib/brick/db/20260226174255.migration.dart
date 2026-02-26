// GENERATED CODE EDIT WITH CAUTION
// THIS FILE **WILL NOT** BE REGENERATED
// This file should be version controlled and can be manually edited.
part of 'schema.g.dart';

// While migrations are intelligently created, the difference between some commands, such as
// DropTable vs. RenameTable, cannot be determined. For this reason, please review migrations after
// they are created to ensure the correct inference was made.

// The migration version must **always** mirror the file name

const List<MigrationCommand> _migration_20260226174255_up = [
  InsertTable('AlertaEmpresa'),
  InsertTable('Empresa'),
  InsertTable('Modulo'),
  InsertTable('ModuloEmpresa'),
  InsertTable('Notificacion'),
  InsertTable('UsuarioEmpresaPerfil'),
  InsertColumn('id', Column.varchar, onTable: 'AlertaEmpresa'),
  InsertColumn('empresa_id', Column.varchar, onTable: 'AlertaEmpresa'),
  InsertColumn('origen_modulo', Column.varchar, onTable: 'AlertaEmpresa'),
  InsertColumn('codigo_alerta', Column.varchar, onTable: 'AlertaEmpresa'),
  InsertColumn('severidad', Column.varchar, onTable: 'AlertaEmpresa'),
  InsertColumn('titulo', Column.varchar, onTable: 'AlertaEmpresa'),
  InsertColumn('cuerpo', Column.varchar, onTable: 'AlertaEmpresa'),
  InsertColumn('accion_url', Column.varchar, onTable: 'AlertaEmpresa'),
  InsertColumn('estado', Column.varchar, onTable: 'AlertaEmpresa'),
  InsertColumn('created_at', Column.datetime, onTable: 'AlertaEmpresa'),
  InsertColumn('id', Column.varchar, onTable: 'Empresa'),
  InsertColumn('nombre', Column.varchar, onTable: 'Empresa'),
  InsertColumn('nombre_comercial', Column.varchar, onTable: 'Empresa'),
  InsertColumn('ruc', Column.varchar, onTable: 'Empresa'),
  InsertColumn('logo_url', Column.varchar, onTable: 'Empresa'),
  InsertColumn('color_primario', Column.varchar, onTable: 'Empresa'),
  InsertColumn('color_secundario', Column.varchar, onTable: 'Empresa'),
  InsertColumn('estado', Column.varchar, onTable: 'Empresa'),
  InsertColumn('id', Column.varchar, onTable: 'Modulo'),
  InsertColumn('nombre', Column.varchar, onTable: 'Modulo'),
  InsertColumn('descripcion', Column.varchar, onTable: 'Modulo'),
  InsertColumn('tipo', Column.varchar, onTable: 'Modulo'),
  InsertColumn('icono', Column.varchar, onTable: 'Modulo'),
  InsertColumn('orden', Column.integer, onTable: 'Modulo'),
  InsertColumn('activo', Column.boolean, onTable: 'Modulo'),
  InsertColumn('id', Column.varchar, onTable: 'ModuloEmpresa'),
  InsertColumn('empresa_id', Column.varchar, onTable: 'ModuloEmpresa'),
  InsertColumn('modulo_id', Column.varchar, onTable: 'ModuloEmpresa'),
  InsertColumn('habilitado', Column.boolean, onTable: 'ModuloEmpresa'),
  InsertColumn('id', Column.varchar, onTable: 'Notificacion'),
  InsertColumn('empresa_id', Column.varchar, onTable: 'Notificacion'),
  InsertColumn('usuario_id', Column.varchar, onTable: 'Notificacion'),
  InsertColumn('tipo', Column.varchar, onTable: 'Notificacion'),
  InsertColumn('titulo', Column.varchar, onTable: 'Notificacion'),
  InsertColumn('cuerpo', Column.varchar, onTable: 'Notificacion'),
  InsertColumn('icono', Column.varchar, onTable: 'Notificacion'),
  InsertColumn('accion_url', Column.varchar, onTable: 'Notificacion'),
  InsertColumn('leida', Column.boolean, onTable: 'Notificacion'),
  InsertColumn('created_at', Column.datetime, onTable: 'Notificacion'),
  InsertColumn('id', Column.varchar, onTable: 'UsuarioEmpresaPerfil'),
  InsertColumn('usuario_id', Column.varchar, onTable: 'UsuarioEmpresaPerfil'),
  InsertColumn('empresa_id', Column.varchar, onTable: 'UsuarioEmpresaPerfil'),
  InsertColumn('activo', Column.boolean, onTable: 'UsuarioEmpresaPerfil'),
  InsertColumn('nombre_display', Column.varchar, onTable: 'UsuarioEmpresaPerfil'),
  InsertColumn('avatar_url', Column.varchar, onTable: 'UsuarioEmpresaPerfil'),
  InsertColumn('telefono', Column.varchar, onTable: 'UsuarioEmpresaPerfil'),
  InsertColumn('email_contacto', Column.varchar, onTable: 'UsuarioEmpresaPerfil'),
  InsertColumn('zona_horaria', Column.varchar, onTable: 'UsuarioEmpresaPerfil')
];

const List<MigrationCommand> _migration_20260226174255_down = [
  DropTable('AlertaEmpresa'),
  DropTable('Empresa'),
  DropTable('Modulo'),
  DropTable('ModuloEmpresa'),
  DropTable('Notificacion'),
  DropTable('UsuarioEmpresaPerfil'),
  DropColumn('id', onTable: 'AlertaEmpresa'),
  DropColumn('empresa_id', onTable: 'AlertaEmpresa'),
  DropColumn('origen_modulo', onTable: 'AlertaEmpresa'),
  DropColumn('codigo_alerta', onTable: 'AlertaEmpresa'),
  DropColumn('severidad', onTable: 'AlertaEmpresa'),
  DropColumn('titulo', onTable: 'AlertaEmpresa'),
  DropColumn('cuerpo', onTable: 'AlertaEmpresa'),
  DropColumn('accion_url', onTable: 'AlertaEmpresa'),
  DropColumn('estado', onTable: 'AlertaEmpresa'),
  DropColumn('created_at', onTable: 'AlertaEmpresa'),
  DropColumn('id', onTable: 'Empresa'),
  DropColumn('nombre', onTable: 'Empresa'),
  DropColumn('nombre_comercial', onTable: 'Empresa'),
  DropColumn('ruc', onTable: 'Empresa'),
  DropColumn('logo_url', onTable: 'Empresa'),
  DropColumn('color_primario', onTable: 'Empresa'),
  DropColumn('color_secundario', onTable: 'Empresa'),
  DropColumn('estado', onTable: 'Empresa'),
  DropColumn('id', onTable: 'Modulo'),
  DropColumn('nombre', onTable: 'Modulo'),
  DropColumn('descripcion', onTable: 'Modulo'),
  DropColumn('tipo', onTable: 'Modulo'),
  DropColumn('icono', onTable: 'Modulo'),
  DropColumn('orden', onTable: 'Modulo'),
  DropColumn('activo', onTable: 'Modulo'),
  DropColumn('id', onTable: 'ModuloEmpresa'),
  DropColumn('empresa_id', onTable: 'ModuloEmpresa'),
  DropColumn('modulo_id', onTable: 'ModuloEmpresa'),
  DropColumn('habilitado', onTable: 'ModuloEmpresa'),
  DropColumn('id', onTable: 'Notificacion'),
  DropColumn('empresa_id', onTable: 'Notificacion'),
  DropColumn('usuario_id', onTable: 'Notificacion'),
  DropColumn('tipo', onTable: 'Notificacion'),
  DropColumn('titulo', onTable: 'Notificacion'),
  DropColumn('cuerpo', onTable: 'Notificacion'),
  DropColumn('icono', onTable: 'Notificacion'),
  DropColumn('accion_url', onTable: 'Notificacion'),
  DropColumn('leida', onTable: 'Notificacion'),
  DropColumn('created_at', onTable: 'Notificacion'),
  DropColumn('id', onTable: 'UsuarioEmpresaPerfil'),
  DropColumn('usuario_id', onTable: 'UsuarioEmpresaPerfil'),
  DropColumn('empresa_id', onTable: 'UsuarioEmpresaPerfil'),
  DropColumn('activo', onTable: 'UsuarioEmpresaPerfil'),
  DropColumn('nombre_display', onTable: 'UsuarioEmpresaPerfil'),
  DropColumn('avatar_url', onTable: 'UsuarioEmpresaPerfil'),
  DropColumn('telefono', onTable: 'UsuarioEmpresaPerfil'),
  DropColumn('email_contacto', onTable: 'UsuarioEmpresaPerfil'),
  DropColumn('zona_horaria', onTable: 'UsuarioEmpresaPerfil')
];

//
// DO NOT EDIT BELOW THIS LINE
//

@Migratable(
  version: '20260226174255',
  up: _migration_20260226174255_up,
  down: _migration_20260226174255_down,
)
class Migration20260226174255 extends Migration {
  const Migration20260226174255()
    : super(
        version: 20260226174255,
        up: _migration_20260226174255_up,
        down: _migration_20260226174255_down,
      );
}
