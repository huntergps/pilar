// ignore: unused_import, unused_shown_name, unnecessary_import
import 'package:brick_core/query.dart';
// ignore: unused_import, unused_shown_name, unnecessary_import
import 'package:brick_sqlite/db.dart';
// ignore: unused_import, unused_shown_name, unnecessary_import
import 'package:brick_offline_first_with_supabase/brick_offline_first_with_supabase.dart';
// ignore: unused_import, unused_shown_name, unnecessary_import
import 'package:brick_supabase/brick_supabase.dart';// GENERATED CODE DO NOT EDIT
// ignore: unused_import
import 'dart:convert';
import 'package:brick_sqlite/brick_sqlite.dart' show SqliteModel, SqliteAdapter, SqliteModelDictionary, RuntimeSqliteColumnDefinition, SqliteProvider;
import 'package:brick_supabase/brick_supabase.dart' show SupabaseProvider, SupabaseModel, SupabaseAdapter, SupabaseModelDictionary;
// ignore: unused_import, unused_shown_name
import 'package:brick_offline_first/brick_offline_first.dart' show RuntimeOfflineFirstDefinition;
// ignore: unused_import, unused_shown_name
import 'package:sqflite_common/sqlite_api.dart' show DatabaseExecutor;

import '../models/alerta_empresa.model.dart';
import '../models/empresa.model.dart';
import '../models/modulo.model.dart';
import '../models/modulo_empresa.model.dart';
import '../models/notificacion.model.dart';
import '../models/usuario_empresa_perfil.model.dart';

part 'adapters/alerta_empresa_adapter.g.dart';
part 'adapters/empresa_adapter.g.dart';
part 'adapters/modulo_adapter.g.dart';
part 'adapters/modulo_empresa_adapter.g.dart';
part 'adapters/notificacion_adapter.g.dart';
part 'adapters/usuario_empresa_perfil_adapter.g.dart';

/// Supabase mappings should only be used when initializing a [SupabaseProvider]
final Map<Type, SupabaseAdapter<SupabaseModel>> supabaseMappings = {
  AlertaEmpresa: AlertaEmpresaAdapter(),
  Empresa: EmpresaAdapter(),
  Modulo: ModuloAdapter(),
  ModuloEmpresa: ModuloEmpresaAdapter(),
  Notificacion: NotificacionAdapter(),
  UsuarioEmpresaPerfil: UsuarioEmpresaPerfilAdapter()
};
final supabaseModelDictionary = SupabaseModelDictionary(supabaseMappings);

/// Sqlite mappings should only be used when initializing a [SqliteProvider]
final Map<Type, SqliteAdapter<SqliteModel>> sqliteMappings = {
  AlertaEmpresa: AlertaEmpresaAdapter(),
  Empresa: EmpresaAdapter(),
  Modulo: ModuloAdapter(),
  ModuloEmpresa: ModuloEmpresaAdapter(),
  Notificacion: NotificacionAdapter(),
  UsuarioEmpresaPerfil: UsuarioEmpresaPerfilAdapter()
};
final sqliteModelDictionary = SqliteModelDictionary(sqliteMappings);
