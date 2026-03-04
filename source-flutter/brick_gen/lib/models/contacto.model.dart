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
  /// Cuando no se provee, la DB usa DEFAULT private.get_empresa_id().
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
  final bool activo;

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
    required this.activo,
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
        'activo': activo,
      };
}
