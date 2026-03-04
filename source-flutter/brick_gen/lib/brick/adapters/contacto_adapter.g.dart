// GENERATED CODE DO NOT EDIT
part of '../brick.g.dart';

Future<Contacto> _$ContactoFromSupabase(
  Map<String, dynamic> data, {
  required SupabaseProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return Contacto(
    id: data['id'] as String,
    empresaId: data['empresa_id'] == null
        ? null
        : data['empresa_id'] as String?,
    razonSocial: data['razon_social'] as String,
    nombreComercial: data['nombre_comercial'] == null
        ? null
        : data['nombre_comercial'] as String?,
    numeroId: data['numero_id'] == null ? null : data['numero_id'] as String?,
    tipoEntidad: data['tipo_entidad'] as String,
    tipoIdentificacion: data['tipo_identificacion'] as String,
    esCliente: data['es_cliente'] as bool,
    esProveedor: data['es_proveedor'] as bool,
    esEmpleado: data['es_empleado'] as bool,
    email: data['email'] == null ? null : data['email'] as String?,
    telefono: data['telefono'] == null ? null : data['telefono'] as String?,
    celular: data['celular'] == null ? null : data['celular'] as String?,
    activo: data['activo'] as bool,
  );
}

Future<Map<String, dynamic>> _$ContactoToSupabase(
  Contacto instance, {
  required SupabaseProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return {
    'id': instance.id,
    'empresa_id': instance.empresaId,
    'razon_social': instance.razonSocial,
    'nombre_comercial': instance.nombreComercial,
    'numero_id': instance.numeroId,
    'tipo_entidad': instance.tipoEntidad,
    'tipo_identificacion': instance.tipoIdentificacion,
    'es_cliente': instance.esCliente,
    'es_proveedor': instance.esProveedor,
    'es_empleado': instance.esEmpleado,
    'email': instance.email,
    'telefono': instance.telefono,
    'celular': instance.celular,
    'activo': instance.activo,
  };
}

Future<Contacto> _$ContactoFromSqlite(
  Map<String, dynamic> data, {
  required SqliteProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return Contacto(
    id: data['id'] as String,
    razonSocial: data['razon_social'] as String,
    nombreComercial: data['nombre_comercial'] == null
        ? null
        : data['nombre_comercial'] as String?,
    numeroId: data['numero_id'] == null ? null : data['numero_id'] as String?,
    tipoEntidad: data['tipo_entidad'] as String,
    tipoIdentificacion: data['tipo_identificacion'] as String,
    esCliente: data['es_cliente'] == 1,
    esProveedor: data['es_proveedor'] == 1,
    esEmpleado: data['es_empleado'] == 1,
    email: data['email'] == null ? null : data['email'] as String?,
    telefono: data['telefono'] == null ? null : data['telefono'] as String?,
    celular: data['celular'] == null ? null : data['celular'] as String?,
    activo: data['activo'] == 1,
  )..primaryKey = data['_brick_id'] as int;
}

Future<Map<String, dynamic>> _$ContactoToSqlite(
  Contacto instance, {
  required SqliteProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return {
    'id': instance.id,
    'razon_social': instance.razonSocial,
    'nombre_comercial': instance.nombreComercial,
    'numero_id': instance.numeroId,
    'tipo_entidad': instance.tipoEntidad,
    'tipo_identificacion': instance.tipoIdentificacion,
    'es_cliente': instance.esCliente ? 1 : 0,
    'es_proveedor': instance.esProveedor ? 1 : 0,
    'es_empleado': instance.esEmpleado ? 1 : 0,
    'email': instance.email,
    'telefono': instance.telefono,
    'celular': instance.celular,
    'activo': instance.activo ? 1 : 0,
  };
}

/// Construct a [Contacto]
class ContactoAdapter extends OfflineFirstWithSupabaseAdapter<Contacto> {
  ContactoAdapter();

  @override
  final supabaseTableName = 'contactos';
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
    'razonSocial': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'razon_social',
    ),
    'nombreComercial': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'nombre_comercial',
    ),
    'numeroId': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'numero_id',
    ),
    'tipoEntidad': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'tipo_entidad',
    ),
    'tipoIdentificacion': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'tipo_identificacion',
    ),
    'esCliente': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'es_cliente',
    ),
    'esProveedor': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'es_proveedor',
    ),
    'esEmpleado': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'es_empleado',
    ),
    'email': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'email',
    ),
    'telefono': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'telefono',
    ),
    'celular': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'celular',
    ),
    'activo': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'activo',
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
    'razonSocial': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'razon_social',
      iterable: false,
      type: String,
    ),
    'nombreComercial': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'nombre_comercial',
      iterable: false,
      type: String,
    ),
    'numeroId': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'numero_id',
      iterable: false,
      type: String,
    ),
    'tipoEntidad': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'tipo_entidad',
      iterable: false,
      type: String,
    ),
    'tipoIdentificacion': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'tipo_identificacion',
      iterable: false,
      type: String,
    ),
    'esCliente': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'es_cliente',
      iterable: false,
      type: bool,
    ),
    'esProveedor': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'es_proveedor',
      iterable: false,
      type: bool,
    ),
    'esEmpleado': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'es_empleado',
      iterable: false,
      type: bool,
    ),
    'email': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'email',
      iterable: false,
      type: String,
    ),
    'telefono': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'telefono',
      iterable: false,
      type: String,
    ),
    'celular': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'celular',
      iterable: false,
      type: String,
    ),
    'activo': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'activo',
      iterable: false,
      type: bool,
    ),
  };
  @override
  Future<int?> primaryKeyByUniqueColumns(
    Contacto instance,
    DatabaseExecutor executor,
  ) async => instance.primaryKey;
  @override
  final String tableName = 'Contacto';

  @override
  Future<Contacto> fromSupabase(
    Map<String, dynamic> input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$ContactoFromSupabase(
    input,
    provider: provider,
    repository: repository,
  );
  @override
  Future<Map<String, dynamic>> toSupabase(
    Contacto input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$ContactoToSupabase(
    input,
    provider: provider,
    repository: repository,
  );
  @override
  Future<Contacto> fromSqlite(
    Map<String, dynamic> input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$ContactoFromSqlite(
    input,
    provider: provider,
    repository: repository,
  );
  @override
  Future<Map<String, dynamic>> toSqlite(
    Contacto input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$ContactoToSqlite(
    input,
    provider: provider,
    repository: repository,
  );
}
