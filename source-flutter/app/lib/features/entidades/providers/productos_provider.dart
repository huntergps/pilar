import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Proveedor de lista de productos activos de la empresa.
final productosProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>(
  (ref) async {
    final data = await Supabase.instance.client
        .from('productos')
        .select(
          'id, codigo, nombre, tipo, precio_venta, precio_costo, descripcion, activo',
        )
        .eq('activo', true)
        .order('nombre');

    return List<Map<String, dynamic>>.from(data as List);
  },
);
