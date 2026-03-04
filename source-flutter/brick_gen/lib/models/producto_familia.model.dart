import 'package:brick_offline_first_with_supabase/brick_offline_first_with_supabase.dart';
import 'package:brick_supabase/brick_supabase.dart';
import 'package:brick_sqlite/brick_sqlite.dart';

@ConnectOfflineFirstWithSupabase(
  supabaseConfig: SupabaseSerializable(tableName: 'producto_familias'),
)
class ProductoFamilia extends OfflineFirstWithSupabaseModel {
  @Supabase(unique: true)
  final String id;

  @Supabase(name: 'empresa_id')
  @Sqlite(ignore: true)
  final String? empresaId;

  final String nombre;
  final String? descripcion;

  @Supabase(name: 'imagen_url')
  @Sqlite(ignore: true)
  final String? imagenUrl;

  /// categoria_id: UUID soft ref a categorias_producto.
  @Supabase(name: 'categoria_id')
  @Sqlite(ignore: true)
  final String? categoriaId;

  final bool activo;

  /// Versión del registro — bloqueo optimista (LWW para maestros).
  /// Se incrementa en la BD con cada UPDATE. Brick lo sincroniza en SQLite.
  @Supabase(name: 'version', defaultValue: '1')
  @Sqlite(defaultValue: '1')
  final int version;

  ProductoFamilia({
    required this.id,
    this.empresaId,
    required this.nombre,
    this.descripcion,
    this.imagenUrl,
    this.categoriaId,
    required this.activo,
    this.version = 1,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'nombre': nombre,
        'descripcion': descripcion,
        'imagen_url': imagenUrl,
        'categoria_id': categoriaId,
        'activo': activo,
        'version': version,
      };
}
