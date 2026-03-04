// GENERATED CODE DO NOT EDIT
part of '../brick.g.dart';

Future<ComMensaje> _$ComMensajeFromSupabase(
  Map<String, dynamic> data, {
  required SupabaseProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return ComMensaje(
    id: data['id'] as String,
    empresaId: data['empresa_id'] == null
        ? null
        : data['empresa_id'] as String?,
    cuentaId: data['cuenta_id'] as String,
    conversacionId: data['conversacion_id'] == null
        ? null
        : data['conversacion_id'] as String?,
    tipo: data['tipo'] as String,
    canal: data['canal'] as String,
    destinatarioRef: data['destinatario_ref'] as String,
    destinatarioNombre: data['destinatario_nombre'] == null
        ? null
        : data['destinatario_nombre'] as String?,
    asunto: data['asunto'] == null ? null : data['asunto'] as String?,
    cuerpo: data['cuerpo'] == null ? null : data['cuerpo'] as String?,
    estado: data['estado'] as String,
    mensajeUid: data['mensaje_uid'] == null
        ? null
        : data['mensaje_uid'] as String?,
    padreId: data['padre_id'] == null ? null : data['padre_id'] as String?,
    entidadTipo: data['entidad_tipo'] == null
        ? null
        : data['entidad_tipo'] as String?,
    entidadId: data['entidad_id'] == null
        ? null
        : data['entidad_id'] as String?,
    enviadoEn: data['enviado_en'] == null
        ? null
        : data['enviado_en'] == null
        ? null
        : DateTime.tryParse(data['enviado_en'] as String),
    entregadoEn: data['entregado_en'] == null
        ? null
        : data['entregado_en'] == null
        ? null
        : DateTime.tryParse(data['entregado_en'] as String),
    leidoEn: data['leido_en'] == null
        ? null
        : data['leido_en'] == null
        ? null
        : DateTime.tryParse(data['leido_en'] as String),
    creadoEn: data['creado_en'] == null
        ? null
        : data['creado_en'] == null
        ? null
        : DateTime.tryParse(data['creado_en'] as String),
    version: data['version'] as int ?? 1,
  );
}

Future<Map<String, dynamic>> _$ComMensajeToSupabase(
  ComMensaje instance, {
  required SupabaseProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return {
    'id': instance.id,
    'empresa_id': instance.empresaId,
    'cuenta_id': instance.cuentaId,
    'conversacion_id': instance.conversacionId,
    'tipo': instance.tipo,
    'canal': instance.canal,
    'destinatario_ref': instance.destinatarioRef,
    'destinatario_nombre': instance.destinatarioNombre,
    'asunto': instance.asunto,
    'cuerpo': instance.cuerpo,
    'estado': instance.estado,
    'mensaje_uid': instance.mensajeUid,
    'padre_id': instance.padreId,
    'entidad_tipo': instance.entidadTipo,
    'entidad_id': instance.entidadId,
    'enviado_en': instance.enviadoEn?.toIso8601String(),
    'entregado_en': instance.entregadoEn?.toIso8601String(),
    'leido_en': instance.leidoEn?.toIso8601String(),
    'creado_en': instance.creadoEn?.toIso8601String(),
    'version': instance.version,
  };
}

Future<ComMensaje> _$ComMensajeFromSqlite(
  Map<String, dynamic> data, {
  required SqliteProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return ComMensaje(
    id: data['id'] as String,
    cuentaId: data['cuenta_id'] as String,
    conversacionId: data['conversacion_id'] == null
        ? null
        : data['conversacion_id'] as String?,
    tipo: data['tipo'] as String,
    canal: data['canal'] as String,
    destinatarioRef: data['destinatario_ref'] as String,
    destinatarioNombre: data['destinatario_nombre'] == null
        ? null
        : data['destinatario_nombre'] as String?,
    asunto: data['asunto'] == null ? null : data['asunto'] as String?,
    cuerpo: data['cuerpo'] == null ? null : data['cuerpo'] as String?,
    estado: data['estado'] as String,
    mensajeUid: data['mensaje_uid'] == null
        ? null
        : data['mensaje_uid'] as String?,
    enviadoEn: data['enviado_en'] == null
        ? null
        : data['enviado_en'] == null
        ? null
        : DateTime.tryParse(data['enviado_en'] as String),
    entregadoEn: data['entregado_en'] == null
        ? null
        : data['entregado_en'] == null
        ? null
        : DateTime.tryParse(data['entregado_en'] as String),
    leidoEn: data['leido_en'] == null
        ? null
        : data['leido_en'] == null
        ? null
        : DateTime.tryParse(data['leido_en'] as String),
    creadoEn: data['creado_en'] == null
        ? null
        : data['creado_en'] == null
        ? null
        : DateTime.tryParse(data['creado_en'] as String),
    version: data['version'] as int ?? 1,
  )..primaryKey = data['_brick_id'] as int;
}

Future<Map<String, dynamic>> _$ComMensajeToSqlite(
  ComMensaje instance, {
  required SqliteProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return {
    'id': instance.id,
    'cuenta_id': instance.cuentaId,
    'conversacion_id': instance.conversacionId,
    'tipo': instance.tipo,
    'canal': instance.canal,
    'destinatario_ref': instance.destinatarioRef,
    'destinatario_nombre': instance.destinatarioNombre,
    'asunto': instance.asunto,
    'cuerpo': instance.cuerpo,
    'estado': instance.estado,
    'mensaje_uid': instance.mensajeUid,
    'enviado_en': instance.enviadoEn?.toIso8601String(),
    'entregado_en': instance.entregadoEn?.toIso8601String(),
    'leido_en': instance.leidoEn?.toIso8601String(),
    'creado_en': instance.creadoEn?.toIso8601String(),
    'version': instance.version,
  };
}

/// Construct a [ComMensaje]
class ComMensajeAdapter extends OfflineFirstWithSupabaseAdapter<ComMensaje> {
  ComMensajeAdapter();

  @override
  final supabaseTableName = 'com_mensajes';
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
    'conversacionId': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'conversacion_id',
    ),
    'tipo': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'tipo',
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
    'asunto': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'asunto',
    ),
    'cuerpo': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'cuerpo',
    ),
    'estado': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'estado',
    ),
    'mensajeUid': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'mensaje_uid',
    ),
    'padreId': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'padre_id',
    ),
    'entidadTipo': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'entidad_tipo',
    ),
    'entidadId': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'entidad_id',
    ),
    'enviadoEn': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'enviado_en',
    ),
    'entregadoEn': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'entregado_en',
    ),
    'leidoEn': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'leido_en',
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
    'conversacionId': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'conversacion_id',
      iterable: false,
      type: String,
    ),
    'tipo': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'tipo',
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
    'asunto': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'asunto',
      iterable: false,
      type: String,
    ),
    'cuerpo': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'cuerpo',
      iterable: false,
      type: String,
    ),
    'estado': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'estado',
      iterable: false,
      type: String,
    ),
    'mensajeUid': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'mensaje_uid',
      iterable: false,
      type: String,
    ),
    'enviadoEn': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'enviado_en',
      iterable: false,
      type: DateTime,
    ),
    'entregadoEn': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'entregado_en',
      iterable: false,
      type: DateTime,
    ),
    'leidoEn': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'leido_en',
      iterable: false,
      type: DateTime,
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
    ComMensaje instance,
    DatabaseExecutor executor,
  ) async => instance.primaryKey;
  @override
  final String tableName = 'ComMensaje';

  @override
  Future<ComMensaje> fromSupabase(
    Map<String, dynamic> input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$ComMensajeFromSupabase(
    input,
    provider: provider,
    repository: repository,
  );
  @override
  Future<Map<String, dynamic>> toSupabase(
    ComMensaje input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$ComMensajeToSupabase(
    input,
    provider: provider,
    repository: repository,
  );
  @override
  Future<ComMensaje> fromSqlite(
    Map<String, dynamic> input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$ComMensajeFromSqlite(
    input,
    provider: provider,
    repository: repository,
  );
  @override
  Future<Map<String, dynamic>> toSqlite(
    ComMensaje input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$ComMensajeToSqlite(
    input,
    provider: provider,
    repository: repository,
  );
}
