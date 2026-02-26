// GENERATED CODE DO NOT EDIT
part of '../brick.g.dart';

Future<UsuarioEmpresaPerfil> _$UsuarioEmpresaPerfilFromSupabase(
  Map<String, dynamic> data, {
  required SupabaseProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return UsuarioEmpresaPerfil(
    id: data['id'] as String,
    usuarioId: data['usuario_id'] as String,
    empresaId: data['empresa_id'] as String,
    activo: data['activo'] as bool,
    nombreDisplay: data['nombre_display'] == null
        ? null
        : data['nombre_display'] as String?,
    avatarUrl: data['avatar_url'] == null
        ? null
        : data['avatar_url'] as String?,
    telefono: data['telefono'] == null ? null : data['telefono'] as String?,
    emailContacto: data['email_contacto'] == null
        ? null
        : data['email_contacto'] as String?,
    zonaHoraria: data['zona_horaria'] == null
        ? null
        : data['zona_horaria'] as String?,
  );
}

Future<Map<String, dynamic>> _$UsuarioEmpresaPerfilToSupabase(
  UsuarioEmpresaPerfil instance, {
  required SupabaseProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return {
    'id': instance.id,
    'usuario_id': instance.usuarioId,
    'empresa_id': instance.empresaId,
    'activo': instance.activo,
    'nombre_display': instance.nombreDisplay,
    'avatar_url': instance.avatarUrl,
    'telefono': instance.telefono,
    'email_contacto': instance.emailContacto,
    'zona_horaria': instance.zonaHoraria,
  };
}

Future<UsuarioEmpresaPerfil> _$UsuarioEmpresaPerfilFromSqlite(
  Map<String, dynamic> data, {
  required SqliteProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return UsuarioEmpresaPerfil(
    id: data['id'] as String,
    usuarioId: data['usuario_id'] as String,
    empresaId: data['empresa_id'] as String,
    activo: data['activo'] == 1,
    nombreDisplay: data['nombre_display'] == null
        ? null
        : data['nombre_display'] as String?,
    avatarUrl: data['avatar_url'] == null
        ? null
        : data['avatar_url'] as String?,
    telefono: data['telefono'] == null ? null : data['telefono'] as String?,
    emailContacto: data['email_contacto'] == null
        ? null
        : data['email_contacto'] as String?,
    zonaHoraria: data['zona_horaria'] == null
        ? null
        : data['zona_horaria'] as String?,
  )..primaryKey = data['_brick_id'] as int;
}

Future<Map<String, dynamic>> _$UsuarioEmpresaPerfilToSqlite(
  UsuarioEmpresaPerfil instance, {
  required SqliteProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return {
    'id': instance.id,
    'usuario_id': instance.usuarioId,
    'empresa_id': instance.empresaId,
    'activo': instance.activo ? 1 : 0,
    'nombre_display': instance.nombreDisplay,
    'avatar_url': instance.avatarUrl,
    'telefono': instance.telefono,
    'email_contacto': instance.emailContacto,
    'zona_horaria': instance.zonaHoraria,
  };
}

/// Construct a [UsuarioEmpresaPerfil]
class UsuarioEmpresaPerfilAdapter
    extends OfflineFirstWithSupabaseAdapter<UsuarioEmpresaPerfil> {
  UsuarioEmpresaPerfilAdapter();

  @override
  final supabaseTableName = 'usuarios_empresa';
  @override
  final defaultToNull = true;
  @override
  final fieldsToSupabaseColumns = {
    'id': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'id',
    ),
    'usuarioId': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'usuario_id',
    ),
    'empresaId': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'empresa_id',
    ),
    'activo': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'activo',
    ),
    'nombreDisplay': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'nombre_display',
    ),
    'avatarUrl': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'avatar_url',
    ),
    'telefono': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'telefono',
    ),
    'emailContacto': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'email_contacto',
    ),
    'zonaHoraria': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'zona_horaria',
    ),
  };
  @override
  final ignoreDuplicates = false;
  @override
  final uniqueFields = {'id'};
  @override
  final Map<String, RuntimeSqliteColumnDefinition> fieldsToSqliteColumns = {
    'primaryKey': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: '_brick_id',
      iterable: false,
      type: int,
    ),
    'id': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'id',
      iterable: false,
      type: String,
    ),
    'usuarioId': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'usuario_id',
      iterable: false,
      type: String,
    ),
    'empresaId': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'empresa_id',
      iterable: false,
      type: String,
    ),
    'activo': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'activo',
      iterable: false,
      type: bool,
    ),
    'nombreDisplay': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'nombre_display',
      iterable: false,
      type: String,
    ),
    'avatarUrl': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'avatar_url',
      iterable: false,
      type: String,
    ),
    'telefono': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'telefono',
      iterable: false,
      type: String,
    ),
    'emailContacto': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'email_contacto',
      iterable: false,
      type: String,
    ),
    'zonaHoraria': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'zona_horaria',
      iterable: false,
      type: String,
    ),
  };
  @override
  Future<int?> primaryKeyByUniqueColumns(
    UsuarioEmpresaPerfil instance,
    DatabaseExecutor executor,
  ) async => instance.primaryKey;
  @override
  final String tableName = 'UsuarioEmpresaPerfil';

  @override
  Future<UsuarioEmpresaPerfil> fromSupabase(
    Map<String, dynamic> input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$UsuarioEmpresaPerfilFromSupabase(
    input,
    provider: provider,
    repository: repository,
  );
  @override
  Future<Map<String, dynamic>> toSupabase(
    UsuarioEmpresaPerfil input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$UsuarioEmpresaPerfilToSupabase(
    input,
    provider: provider,
    repository: repository,
  );
  @override
  Future<UsuarioEmpresaPerfil> fromSqlite(
    Map<String, dynamic> input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$UsuarioEmpresaPerfilFromSqlite(
    input,
    provider: provider,
    repository: repository,
  );
  @override
  Future<Map<String, dynamic>> toSqlite(
    UsuarioEmpresaPerfil input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$UsuarioEmpresaPerfilToSqlite(
    input,
    provider: provider,
    repository: repository,
  );
}
