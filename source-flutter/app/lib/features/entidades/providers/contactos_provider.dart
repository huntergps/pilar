import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Proveedor de lista de contactos activos de la empresa.
final contactosProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>(
  (ref) async {
    final data = await Supabase.instance.client
        .from('contactos')
        .select(
          'id, razon_social, nombre_comercial, numero_id, tipo_entidad, '
          'tipo_id_sri, es_cliente, es_proveedor, email, telefono, celular, activo',
        )
        .eq('activo', true)
        .order('razon_social');

    return List<Map<String, dynamic>>.from(data as List);
  },
);
