import 'package:brick_offline_first_with_supabase/brick_offline_first_with_supabase.dart';
import 'package:brick_supabase/brick_supabase.dart';
import 'package:brick_sqlite/brick_sqlite.dart';

@ConnectOfflineFirstWithSupabase(
  supabaseConfig: SupabaseSerializable(tableName: 'productos'),
)
class Producto extends OfflineFirstWithSupabaseModel {
  @Supabase(unique: true)
  final String id;

  /// empresa_id: solo en Supabase, no en SQLite.
  @Supabase(name: 'empresa_id')
  @Sqlite(ignore: true)
  final String? empresaId;

  final String? codigo;
  final String nombre;
  final String tipo;
  final double? precioVenta;
  final double? precioCosto;
  final String? descripcion;

  /// Código de barras principal (EAN13, UPC) — acceso rápido sin JOIN.
  @Supabase(name: 'codigo_principal_barras')
  final String? codigoPrincipalBarras;

  /// unidad_medida_id: solo en Supabase (UUID soft ref).
  @Supabase(name: 'unidad_medida_id')
  @Sqlite(ignore: true)
  final String? unidadMedidaId;

  /// familia_id: solo en Supabase (UUID ref a producto_familias).
  @Supabase(name: 'familia_id')
  @Sqlite(ignore: true)
  final String? familiaId;

  /// categoria_id: solo en Supabase (UUID soft ref a categorias_producto).
  @Supabase(name: 'categoria_id')
  @Sqlite(ignore: true)
  final String? categoriaId;

  final bool activo;

  Producto({
    required this.id,
    this.empresaId,
    this.codigo,
    required this.nombre,
    required this.tipo,
    this.precioVenta,
    this.precioCosto,
    this.descripcion,
    this.codigoPrincipalBarras,
    this.unidadMedidaId,
    this.familiaId,
    this.categoriaId,
    required this.activo,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'codigo': codigo,
        'nombre': nombre,
        'tipo': tipo,
        'precio_venta': precioVenta,
        'precio_costo': precioCosto,
        'descripcion': descripcion,
        'codigo_principal_barras': codigoPrincipalBarras,
        'unidad_medida_id': unidadMedidaId,
        'familia_id': familiaId,
        'categoria_id': categoriaId,
        'activo': activo,
      };
}
