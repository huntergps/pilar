import 'package:brick_offline_first_with_supabase/brick_offline_first_with_supabase.dart';
import 'package:brick_supabase/brick_supabase.dart';
import 'package:brick_sqlite/brick_sqlite.dart';

@ConnectOfflineFirstWithSupabase(
  supabaseConfig: SupabaseSerializable(tableName: 'contactos'),
)
class Contacto extends OfflineFirstWithSupabaseModel {
  @Supabase(unique: true)
  final String id;

  /// empresa_id: solo en Supabase, no en SQLite.
  @Supabase(name: 'empresa_id')
  @Sqlite(ignore: true)
  final String? empresaId;

  final String razonSocial;
  final String? nombreComercial;
  final String? numeroId;
  final String tipoEntidad;
  final String tipoIdentificacion;
  final bool esCliente;
  final bool esProveedor;
  final bool esEmpleado;
  final String? email;
  final String? telefono;
  final String? celular;

  /// Cargo o puesto del contacto en su empresa.
  final String? cargo;

  /// Sitio web corporativo o personal.
  final String? website;

  /// Dirección fiscal principal.
  final String? direccion;

  /// Notas internas sobre el contacto.
  final String? notas;

  /// empresa_padre_id: solo en Supabase (UUID soft ref a otro contacto).
  @Supabase(name: 'empresa_padre_id')
  @Sqlite(ignore: true)
  final String? empresaPadreId;

  /// categoria_id: solo en Supabase (UUID soft ref a categorias_contacto).
  @Supabase(name: 'categoria_id')
  @Sqlite(ignore: true)
  final String? categoriaId;

  @Sqlite(index: true)
  final bool activo;

  /// Versión del registro — bloqueo optimista (LWW para maestros).
  /// Se incrementa en la BD con cada UPDATE. Brick lo sincroniza en SQLite.
  @Supabase(name: 'version', defaultValue: '1')
  @Sqlite(defaultValue: '1')
  final int version;

  Contacto({
    required this.id,
    this.empresaId,
    required this.razonSocial,
    this.nombreComercial,
    this.numeroId,
    required this.tipoEntidad,
    required this.tipoIdentificacion,
    required this.esCliente,
    required this.esProveedor,
    required this.esEmpleado,
    this.email,
    this.telefono,
    this.celular,
    this.cargo,
    this.website,
    this.direccion,
    this.notas,
    this.empresaPadreId,
    this.categoriaId,
    required this.activo,
    this.version = 1,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'razon_social': razonSocial,
        'nombre_comercial': nombreComercial,
        'numero_id': numeroId,
        'tipo_entidad': tipoEntidad,
        'tipo_identificacion': tipoIdentificacion,
        'es_cliente': esCliente,
        'es_proveedor': esProveedor,
        'es_empleado': esEmpleado,
        'email': email,
        'telefono': telefono,
        'celular': celular,
        'cargo': cargo,
        'website': website,
        'direccion': direccion,
        'notas': notas,
        'empresa_padre_id': empresaPadreId,
        'categoria_id': categoriaId,
        'activo': activo,
        'version': version,
      };
}
