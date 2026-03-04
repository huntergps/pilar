// GENERATED CODE DO NOT EDIT
part of '../brick.g.dart';

Future<Adjunto> _$AdjuntoFromSupabase(
  Map<String, dynamic> data, {
  required SupabaseProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return Adjunto(
    id: data['id'] as String,
    empresaId: data['empresa_id'] == null
        ? null
        : data['empresa_id'] as String?,
    entidadTipo: data['entidad_tipo'] as String,
    entidadId: data['entidad_id'] as String,
    nombre: data['nombre'] as String,
    nombreOriginal: data['nombre_original'] as String,
    mimeType: data['mime_type'] as String,
    tamanioBytes: data['tamanio_bytes'] as int,
    storagePath: data['storage_path'] as String,
    storageBucket: data['storage_bucket'] as String,
    descripcion: data['descripcion'] == null
        ? null
        : data['descripcion'] as String?,
    esPublico: data['es_publico'] as bool,
    subidoPor: data['subido_por'] == null
        ? null
        : data['subido_por'] as String?,
    createdAt: data['created_at'] == null
        ? null
        : data['created_at'] == null
        ? null
        : DateTime.tryParse(data['created_at'] as String),
    version: data['version'] as int ?? 1,
  );
}

Future<Map<String, dynamic>> _$AdjuntoToSupabase(
  Adjunto instance, {
  required SupabaseProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return {
    'id': instance.id,
    'empresa_id': instance.empresaId,
    'entidad_tipo': instance.entidadTipo,
    'entidad_id': instance.entidadId,
    'nombre': instance.nombre,
    'nombre_original': instance.nombreOriginal,
    'mime_type': instance.mimeType,
    'tamanio_bytes': instance.tamanioBytes,
    'storage_path': instance.storagePath,
    'storage_bucket': instance.storageBucket,
    'descripcion': instance.descripcion,
    'es_publico': instance.esPublico,
    'subido_por': instance.subidoPor,
    'created_at': instance.createdAt?.toIso8601String(),
    'version': instance.version,
  };
}

Future<Adjunto> _$AdjuntoFromSqlite(
  Map<String, dynamic> data, {
  required SqliteProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return Adjunto(
    id: data['id'] as String,
    entidadTipo: data['entidad_tipo'] as String,
    entidadId: data['entidad_id'] as String,
    nombre: data['nombre'] as String,
    nombreOriginal: data['nombre_original'] as String,
    mimeType: data['mime_type'] as String,
    tamanioBytes: data['tamanio_bytes'] as int,
    storagePath: data['storage_path'] as String,
    storageBucket: data['storage_bucket'] as String,
    descripcion: data['descripcion'] == null
        ? null
        : data['descripcion'] as String?,
    esPublico: data['es_publico'] == 1,
    createdAt: data['created_at'] == null
        ? null
        : data['created_at'] == null
        ? null
        : DateTime.tryParse(data['created_at'] as String),
    version: data['version'] as int ?? 1,
  )..primaryKey = data['_brick_id'] as int;
}

Future<Map<String, dynamic>> _$AdjuntoToSqlite(
  Adjunto instance, {
  required SqliteProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return {
    'id': instance.id,
    'entidad_tipo': instance.entidadTipo,
    'entidad_id': instance.entidadId,
    'nombre': instance.nombre,
    'nombre_original': instance.nombreOriginal,
    'mime_type': instance.mimeType,
    'tamanio_bytes': instance.tamanioBytes,
    'storage_path': instance.storagePath,
    'storage_bucket': instance.storageBucket,
    'descripcion': instance.descripcion,
    'es_publico': instance.esPublico ? 1 : 0,
    'created_at': instance.createdAt?.toIso8601String(),
    'version': instance.version,
  };
}

/// Construct a [Adjunto]
class AdjuntoAdapter extends OfflineFirstWithSupabaseAdapter<Adjunto> {
  AdjuntoAdapter();

  @override
  final supabaseTableName = 'adjuntos';
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
    'entidadTipo': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'entidad_tipo',
    ),
    'entidadId': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'entidad_id',
    ),
    'nombre': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'nombre',
    ),
    'nombreOriginal': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'nombre_original',
    ),
    'mimeType': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'mime_type',
    ),
    'tamanioBytes': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'tamanio_bytes',
    ),
    'storagePath': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'storage_path',
    ),
    'storageBucket': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'storage_bucket',
    ),
    'descripcion': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'descripcion',
    ),
    'esPublico': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'es_publico',
    ),
    'subidoPor': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'subido_por',
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
    'entidadTipo': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'entidad_tipo',
      iterable: false,
      type: String,
    ),
    'entidadId': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'entidad_id',
      iterable: false,
      type: String,
    ),
    'nombre': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'nombre',
      iterable: false,
      type: String,
    ),
    'nombreOriginal': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'nombre_original',
      iterable: false,
      type: String,
    ),
    'mimeType': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'mime_type',
      iterable: false,
      type: String,
    ),
    'tamanioBytes': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'tamanio_bytes',
      iterable: false,
      type: int,
    ),
    'storagePath': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'storage_path',
      iterable: false,
      type: String,
    ),
    'storageBucket': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'storage_bucket',
      iterable: false,
      type: String,
    ),
    'descripcion': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'descripcion',
      iterable: false,
      type: String,
    ),
    'esPublico': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'es_publico',
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
    Adjunto instance,
    DatabaseExecutor executor,
  ) async => instance.primaryKey;
  @override
  final String tableName = 'Adjunto';

  @override
  Future<Adjunto> fromSupabase(
    Map<String, dynamic> input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$AdjuntoFromSupabase(
    input,
    provider: provider,
    repository: repository,
  );
  @override
  Future<Map<String, dynamic>> toSupabase(
    Adjunto input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$AdjuntoToSupabase(
    input,
    provider: provider,
    repository: repository,
  );
  @override
  Future<Adjunto> fromSqlite(
    Map<String, dynamic> input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$AdjuntoFromSqlite(
    input,
    provider: provider,
    repository: repository,
  );
  @override
  Future<Map<String, dynamic>> toSqlite(
    Adjunto input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$AdjuntoToSqlite(
    input,
    provider: provider,
    repository: repository,
  );
}
