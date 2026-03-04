// ignore: unused_import, unused_shown_name, unnecessary_import
import 'package:brick_core/query.dart';
// ignore: unused_import, unused_shown_name, unnecessary_import
import 'package:brick_sqlite/db.dart';
// ignore: unused_import, unused_shown_name, unnecessary_import
import 'package:brick_offline_first_with_supabase/brick_offline_first_with_supabase.dart';
// ignore: unused_import, unused_shown_name, unnecessary_import
import 'package:brick_supabase/brick_supabase.dart';
// ignore: unused_import, unused_shown_name, unnecessary_import
import 'package:brick_sqlite/brick_sqlite.dart';// GENERATED CODE DO NOT EDIT
// ignore: unused_import
import 'dart:convert';
import 'package:brick_sqlite/brick_sqlite.dart' show SqliteModel, SqliteAdapter, SqliteModelDictionary, RuntimeSqliteColumnDefinition, SqliteProvider;
import 'package:brick_supabase/brick_supabase.dart' show SupabaseProvider, SupabaseModel, SupabaseAdapter, SupabaseModelDictionary;
// ignore: unused_import, unused_shown_name
import 'package:brick_offline_first/brick_offline_first.dart' show RuntimeOfflineFirstDefinition;
// ignore: unused_import, unused_shown_name
import 'package:sqflite_common/sqlite_api.dart' show DatabaseExecutor;

import '../models/adjunto.model.dart';
import '../models/alerta_empresa.model.dart';
import '../models/chat_mensaje.model.dart';
import '../models/chatter_mensaje.model.dart';
import '../models/com_conversacion.model.dart';
import '../models/com_mensaje.model.dart';
import '../models/contacto.model.dart';
import '../models/empresa.model.dart';
import '../models/modulo.model.dart';
import '../models/modulo_empresa.model.dart';
import '../models/notificacion.model.dart';
import '../models/producto.model.dart';
import '../models/producto_familia.model.dart';
import '../models/rol.model.dart';
import '../models/usuario_empresa_perfil.model.dart';

part 'adapters/adjunto_adapter.g.dart';
part 'adapters/alerta_empresa_adapter.g.dart';
part 'adapters/chat_mensaje_adapter.g.dart';
part 'adapters/chatter_mensaje_adapter.g.dart';
part 'adapters/com_conversacion_adapter.g.dart';
part 'adapters/com_mensaje_adapter.g.dart';
part 'adapters/contacto_adapter.g.dart';
part 'adapters/empresa_adapter.g.dart';
part 'adapters/modulo_adapter.g.dart';
part 'adapters/modulo_empresa_adapter.g.dart';
part 'adapters/notificacion_adapter.g.dart';
part 'adapters/producto_adapter.g.dart';
part 'adapters/producto_familia_adapter.g.dart';
part 'adapters/rol_adapter.g.dart';
part 'adapters/usuario_empresa_perfil_adapter.g.dart';

/// Supabase mappings should only be used when initializing a [SupabaseProvider]
final Map<Type, SupabaseAdapter<SupabaseModel>> supabaseMappings = {
  Adjunto: AdjuntoAdapter(),
  AlertaEmpresa: AlertaEmpresaAdapter(),
  ChatMensaje: ChatMensajeAdapter(),
  ChatterMensaje: ChatterMensajeAdapter(),
  ComConversacion: ComConversacionAdapter(),
  ComMensaje: ComMensajeAdapter(),
  Contacto: ContactoAdapter(),
  Empresa: EmpresaAdapter(),
  Modulo: ModuloAdapter(),
  ModuloEmpresa: ModuloEmpresaAdapter(),
  Notificacion: NotificacionAdapter(),
  Producto: ProductoAdapter(),
  ProductoFamilia: ProductoFamiliaAdapter(),
  Rol: RolAdapter(),
  UsuarioEmpresaPerfil: UsuarioEmpresaPerfilAdapter()
};
final supabaseModelDictionary = SupabaseModelDictionary(supabaseMappings);

/// Sqlite mappings should only be used when initializing a [SqliteProvider]
final Map<Type, SqliteAdapter<SqliteModel>> sqliteMappings = {
  Adjunto: AdjuntoAdapter(),
  AlertaEmpresa: AlertaEmpresaAdapter(),
  ChatMensaje: ChatMensajeAdapter(),
  ChatterMensaje: ChatterMensajeAdapter(),
  ComConversacion: ComConversacionAdapter(),
  ComMensaje: ComMensajeAdapter(),
  Contacto: ContactoAdapter(),
  Empresa: EmpresaAdapter(),
  Modulo: ModuloAdapter(),
  ModuloEmpresa: ModuloEmpresaAdapter(),
  Notificacion: NotificacionAdapter(),
  Producto: ProductoAdapter(),
  ProductoFamilia: ProductoFamiliaAdapter(),
  Rol: RolAdapter(),
  UsuarioEmpresaPerfil: UsuarioEmpresaPerfilAdapter()
};
final sqliteModelDictionary = SqliteModelDictionary(sqliteMappings);
