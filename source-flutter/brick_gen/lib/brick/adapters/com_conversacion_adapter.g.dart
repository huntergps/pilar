// GENERATED CODE DO NOT EDIT
part of '../brick.g.dart';

Future<ComConversacion> _$ComConversacionFromSupabase(
  Map<String, dynamic> data, {
  required SupabaseProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return ComConversacion(
    id: data['id'] as String,
    empresaId: data['empresa_id'] == null
        ? null
        : data['empresa_id'] as String?,
    cuentaId: data['cuenta_id'] as String,
    canal: data['canal'] as String,
    destinatarioRef: data['destinatario_ref'] as String,
    destinatarioNombre: data['destinatario_nombre'] == null
        ? null
        : data['destinatario_nombre'] as String?,
    contactoId: data['contacto_id'] == null
        ? null
        : data['contacto_id'] as String?,
    ultimoMensajeEn: data['ultimo_mensaje_en'] == null
        ? null
        : data['ultimo_mensaje_en'] == null
        ? null
        : DateTime.tryParse(data['ultimo_mensaje_en'] as String),
    validaHasta: data['valida_hasta'] == null
        ? null
        : data['valida_hasta'] == null
        ? null
        : DateTime.tryParse(data['valida_hasta'] as String),
    activa: data['activa'] as bool,
    metaJson: data['meta_json'] == null ? null : data['meta_json'],
    entidadTipo: data['entidad_tipo'] == null
        ? null
        : data['entidad_tipo'] as String?,
    entidadId: data['entidad_id'] == null
        ? null
        : data['entidad_id'] as String?,
    creadoEn: data['creado_en'] == null
        ? null
        : data['creado_en'] == null
        ? null
        : DateTime.tryParse(data['creado_en'] as String),
    version: data['version'] as int ?? 1,
  );
}

Future<Map<String, dynamic>> _$ComConversacionToSupabase(
  ComConversacion instance, {
  required SupabaseProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return {
    'id': instance.id,
    'empresa_id': instance.empresaId,
    'cuenta_id': instance.cuentaId,
    'canal': instance.canal,
    'destinatario_ref': instance.destinatarioRef,
    'destinatario_nombre': instance.destinatarioNombre,
    'contacto_id': instance.contactoId,
    'ultimo_mensaje_en': instance.ultimoMensajeEn?.toIso8601String(),
    'valida_hasta': instance.validaHasta?.toIso8601String(),
    'activa': instance.activa,
    'meta_json': instance.metaJson,
    'entidad_tipo': instance.entidadTipo,
    'entidad_id': instance.entidadId,
    'creado_en': instance.creadoEn?.toIso8601String(),
    'version': instance.version,
  };
}

Future<ComConversacion> _$ComConversacionFromSqlite(
  Map<String, dynamic> data, {
  required SqliteProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return ComConversacion(
    id: data['id'] as String,
    cuentaId: data['cuenta_id'] as String,
    canal: data['canal'] as String,
    destinatarioRef: data['destinatario_ref'] as String,
    destinatarioNombre: data['destinatario_nombre'] == null
        ? null
        : data['destinatario_nombre'] as String?,
    ultimoMensajeEn: data['ultimo_mensaje_en'] == null
        ? null
        : data['ultimo_mensaje_en'] == null
        ? null
        : DateTime.tryParse(data['ultimo_mensaje_en'] as String),
    validaHasta: data['valida_hasta'] == null
        ? null
        : data['valida_hasta'] == null
        ? null
        : DateTime.tryParse(data['valida_hasta'] as String),
    activa: data['activa'] == 1,
    creadoEn: data['creado_en'] == null
        ? null
        : data['creado_en'] == null
        ? null
        : DateTime.tryParse(data['creado_en'] as String),
    version: data['version'] as int ?? 1,
  )..primaryKey = data['_brick_id'] as int;
}

Future<Map<String, dynamic>> _$ComConversacionToSqlite(
  ComConversacion instance, {
  required SqliteProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return {
    'id': instance.id,
    'cuenta_id': instance.cuentaId,
    'canal': instance.canal,
    'destinatario_ref': instance.destinatarioRef,
    'destinatario_nombre': instance.destinatarioNombre,
    'ultimo_mensaje_en': instance.ultimoMensajeEn?.toIso8601String(),
    'valida_hasta': instance.validaHasta?.toIso8601String(),
    'activa': instance.activa ? 1 : 0,
    'creado_en': instance.creadoEn?.toIso8601String(),
    'version': instance.version,
  };
}

/// Construct a [ComConversacion]
class ComConversacionAdapter
    extends OfflineFirstWithSupabaseAdapter<ComConversacion> {
  ComConversacionAdapter();

  @override
  final supabaseTableName = 'com_conversaciones';
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
    'cuentaId': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'cuenta_id',
    ),
    'canal': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'canal',
    ),
    'destinatarioRef': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'destinatario_ref',
    ),
    'destinatarioNombre': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'destinatario_nombre',
    ),
    'contactoId': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'contacto_id',
    ),
    'ultimoMensajeEn': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'ultimo_mensaje_en',
    ),
    'validaHasta': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'valida_hasta',
    ),
    'activa': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'activa',
    ),
    'metaJson': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'meta_json',
    ),
    'entidadTipo': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'entidad_tipo',
    ),
    'entidadId': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'entidad_id',
    ),
    'creadoEn': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'creado_en',
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
    'cuentaId': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'cuenta_id',
      iterable: false,
      type: String,
    ),
    'canal': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'canal',
      iterable: false,
      type: String,
    ),
    'destinatarioRef': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'destinatario_ref',
      iterable: false,
      type: String,
    ),
    'destinatarioNombre': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'destinatario_nombre',
      iterable: false,
      type: String,
    ),
    'ultimoMensajeEn': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'ultimo_mensaje_en',
      iterable: false,
      type: DateTime,
    ),
    'validaHasta': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'valida_hasta',
      iterable: false,
      type: DateTime,
    ),
    'activa': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'activa',
      iterable: false,
      type: bool,
    ),
    'creadoEn': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'creado_en',
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
    ComConversacion instance,
    DatabaseExecutor executor,
  ) async => instance.primaryKey;
  @override
  final String tableName = 'ComConversacion';

  @override
  Future<ComConversacion> fromSupabase(
    Map<String, dynamic> input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$ComConversacionFromSupabase(
    input,
    provider: provider,
    repository: repository,
  );
  @override
  Future<Map<String, dynamic>> toSupabase(
    ComConversacion input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$ComConversacionToSupabase(
    input,
    provider: provider,
    repository: repository,
  );
  @override
  Future<ComConversacion> fromSqlite(
    Map<String, dynamic> input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$ComConversacionFromSqlite(
    input,
    provider: provider,
    repository: repository,
  );
  @override
  Future<Map<String, dynamic>> toSqlite(
    ComConversacion input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$ComConversacionToSqlite(
    input,
    provider: provider,
    repository: repository,
  );
}
