// GENERATED CODE DO NOT EDIT
part of '../brick.g.dart';

Future<Notificacion> _$NotificacionFromSupabase(
  Map<String, dynamic> data, {
  required SupabaseProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return Notificacion(
    id: data['id'] as String,
    empresaId: data['empresa_id'] as String,
    usuarioId: data['usuario_id'] as String,
    tipo: data['tipo'] as String,
    titulo: data['titulo'] as String,
    cuerpo: data['cuerpo'] == null ? null : data['cuerpo'] as String?,
    icono: data['icono'] == null ? null : data['icono'] as String?,
    accionUrl: data['accion_url'] == null
        ? null
        : data['accion_url'] as String?,
    leida: data['leida'] as bool,
    createdAt: data['created_at'] == null
        ? null
        : data['created_at'] == null
        ? null
        : DateTime.tryParse(data['created_at'] as String),
    version: data['version'] as int ?? 1,
  );
}

Future<Map<String, dynamic>> _$NotificacionToSupabase(
  Notificacion instance, {
  required SupabaseProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return {
    'id': instance.id,
    'empresa_id': instance.empresaId,
    'usuario_id': instance.usuarioId,
    'tipo': instance.tipo,
    'titulo': instance.titulo,
    'cuerpo': instance.cuerpo,
    'icono': instance.icono,
    'accion_url': instance.accionUrl,
    'leida': instance.leida,
    'created_at': instance.createdAt?.toIso8601String(),
    'version': instance.version,
  };
}

Future<Notificacion> _$NotificacionFromSqlite(
  Map<String, dynamic> data, {
  required SqliteProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return Notificacion(
    id: data['id'] as String,
    empresaId: data['empresa_id'] as String,
    usuarioId: data['usuario_id'] as String,
    tipo: data['tipo'] as String,
    titulo: data['titulo'] as String,
    cuerpo: data['cuerpo'] == null ? null : data['cuerpo'] as String?,
    icono: data['icono'] == null ? null : data['icono'] as String?,
    accionUrl: data['accion_url'] == null
        ? null
        : data['accion_url'] as String?,
    leida: data['leida'] == 1,
    createdAt: data['created_at'] == null
        ? null
        : data['created_at'] == null
        ? null
        : DateTime.tryParse(data['created_at'] as String),
    version: data['version'] as int ?? 1,
  )..primaryKey = data['_brick_id'] as int;
}

Future<Map<String, dynamic>> _$NotificacionToSqlite(
  Notificacion instance, {
  required SqliteProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return {
    'id': instance.id,
    'empresa_id': instance.empresaId,
    'usuario_id': instance.usuarioId,
    'tipo': instance.tipo,
    'titulo': instance.titulo,
    'cuerpo': instance.cuerpo,
    'icono': instance.icono,
    'accion_url': instance.accionUrl,
    'leida': instance.leida ? 1 : 0,
    'created_at': instance.createdAt?.toIso8601String(),
    'version': instance.version,
  };
}

/// Construct a [Notificacion]
class NotificacionAdapter
    extends OfflineFirstWithSupabaseAdapter<Notificacion> {
  NotificacionAdapter();

  @override
  final supabaseTableName = 'notificaciones_usuario';
  @override
  final defaultToNull = true;
  @override
  final fieldsToSupabaseColumns = {
    'id': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'id',
    ),
    'empresaId': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'empresa_id',
    ),
    'usuarioId': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'usuario_id',
    ),
    'tipo': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'tipo',
    ),
    'titulo': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'titulo',
    ),
    'cuerpo': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'cuerpo',
    ),
    'icono': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'icono',
    ),
    'accionUrl': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'accion_url',
    ),
    'leida': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'leida',
    ),
    'createdAt': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'created_at',
    ),
    'version': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'version',
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
    'empresaId': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'empresa_id',
      iterable: false,
      type: String,
    ),
    'usuarioId': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'usuario_id',
      iterable: false,
      type: String,
    ),
    'tipo': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'tipo',
      iterable: false,
      type: String,
    ),
    'titulo': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'titulo',
      iterable: false,
      type: String,
    ),
    'cuerpo': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'cuerpo',
      iterable: false,
      type: String,
    ),
    'icono': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'icono',
      iterable: false,
      type: String,
    ),
    'accionUrl': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'accion_url',
      iterable: false,
      type: String,
    ),
    'leida': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'leida',
      iterable: false,
      type: bool,
    ),
    'createdAt': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'created_at',
      iterable: false,
      type: DateTime,
    ),
    'version': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'version',
      iterable: false,
      type: int,
    ),
  };
  @override
  Future<int?> primaryKeyByUniqueColumns(
    Notificacion instance,
    DatabaseExecutor executor,
  ) async => instance.primaryKey;
  @override
  final String tableName = 'Notificacion';

  @override
  Future<Notificacion> fromSupabase(
    Map<String, dynamic> input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$NotificacionFromSupabase(
    input,
    provider: provider,
    repository: repository,
  );
  @override
  Future<Map<String, dynamic>> toSupabase(
    Notificacion input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$NotificacionToSupabase(
    input,
    provider: provider,
    repository: repository,
  );
  @override
  Future<Notificacion> fromSqlite(
    Map<String, dynamic> input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$NotificacionFromSqlite(
    input,
    provider: provider,
    repository: repository,
  );
  @override
  Future<Map<String, dynamic>> toSqlite(
    Notificacion input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$NotificacionToSqlite(
    input,
    provider: provider,
    repository: repository,
  );
}
