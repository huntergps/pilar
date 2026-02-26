// GENERATED CODE DO NOT EDIT
// This file should be version controlled
import 'package:brick_sqlite/db.dart';
part '20260226174255.migration.dart';

/// All intelligently-generated migrations from all `@Migratable` classes on disk
final migrations = <Migration>{
  const Migration20260226174255(),};

/// A consumable database structure including the latest generated migration.
final schema = Schema(
  0,
  generatorVersion: 1,
  tables: <SchemaTable>{
    SchemaTable(
      'AlertaEmpresa',
      columns: <SchemaColumn>{
        SchemaColumn(
          '_brick_id',
          Column.integer,
          autoincrement: true,
          nullable: false,
          isPrimaryKey: true,
        ),
        SchemaColumn('id', Column.varchar),
        SchemaColumn('empresa_id', Column.varchar),
        SchemaColumn('origen_modulo', Column.varchar),
        SchemaColumn('codigo_alerta', Column.varchar),
        SchemaColumn('severidad', Column.varchar),
        SchemaColumn('titulo', Column.varchar),
        SchemaColumn('cuerpo', Column.varchar),
        SchemaColumn('accion_url', Column.varchar),
        SchemaColumn('estado', Column.varchar),
        SchemaColumn('created_at', Column.datetime),
      },
      indices: <SchemaIndex>{},
    ),
    SchemaTable(
      'Empresa',
      columns: <SchemaColumn>{
        SchemaColumn(
          '_brick_id',
          Column.integer,
          autoincrement: true,
          nullable: false,
          isPrimaryKey: true,
        ),
        SchemaColumn('id', Column.varchar),
        SchemaColumn('nombre', Column.varchar),
        SchemaColumn('nombre_comercial', Column.varchar),
        SchemaColumn('ruc', Column.varchar),
        SchemaColumn('logo_url', Column.varchar),
        SchemaColumn('color_primario', Column.varchar),
        SchemaColumn('color_secundario', Column.varchar),
        SchemaColumn('estado', Column.varchar),
      },
      indices: <SchemaIndex>{},
    ),
    SchemaTable(
      'Modulo',
      columns: <SchemaColumn>{
        SchemaColumn(
          '_brick_id',
          Column.integer,
          autoincrement: true,
          nullable: false,
          isPrimaryKey: true,
        ),
        SchemaColumn('id', Column.varchar),
        SchemaColumn('nombre', Column.varchar),
        SchemaColumn('descripcion', Column.varchar),
        SchemaColumn('tipo', Column.varchar),
        SchemaColumn('icono', Column.varchar),
        SchemaColumn('orden', Column.integer),
        SchemaColumn('activo', Column.boolean),
      },
      indices: <SchemaIndex>{},
    ),
    SchemaTable(
      'ModuloEmpresa',
      columns: <SchemaColumn>{
        SchemaColumn(
          '_brick_id',
          Column.integer,
          autoincrement: true,
          nullable: false,
          isPrimaryKey: true,
        ),
        SchemaColumn('id', Column.varchar),
        SchemaColumn('empresa_id', Column.varchar),
        SchemaColumn('modulo_id', Column.varchar),
        SchemaColumn('habilitado', Column.boolean),
      },
      indices: <SchemaIndex>{},
    ),
    SchemaTable(
      'Notificacion',
      columns: <SchemaColumn>{
        SchemaColumn(
          '_brick_id',
          Column.integer,
          autoincrement: true,
          nullable: false,
          isPrimaryKey: true,
        ),
        SchemaColumn('id', Column.varchar),
        SchemaColumn('empresa_id', Column.varchar),
        SchemaColumn('usuario_id', Column.varchar),
        SchemaColumn('tipo', Column.varchar),
        SchemaColumn('titulo', Column.varchar),
        SchemaColumn('cuerpo', Column.varchar),
        SchemaColumn('icono', Column.varchar),
        SchemaColumn('accion_url', Column.varchar),
        SchemaColumn('leida', Column.boolean),
        SchemaColumn('created_at', Column.datetime),
      },
      indices: <SchemaIndex>{},
    ),
    SchemaTable(
      'UsuarioEmpresaPerfil',
      columns: <SchemaColumn>{
        SchemaColumn(
          '_brick_id',
          Column.integer,
          autoincrement: true,
          nullable: false,
          isPrimaryKey: true,
        ),
        SchemaColumn('id', Column.varchar),
        SchemaColumn('usuario_id', Column.varchar),
        SchemaColumn('empresa_id', Column.varchar),
        SchemaColumn('activo', Column.boolean),
        SchemaColumn('nombre_display', Column.varchar),
        SchemaColumn('avatar_url', Column.varchar),
        SchemaColumn('telefono', Column.varchar),
        SchemaColumn('email_contacto', Column.varchar),
        SchemaColumn('zona_horaria', Column.varchar),
      },
      indices: <SchemaIndex>{},
    ),
  },
);
