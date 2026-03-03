import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/empresa_provider.dart';

class DashboardKpis {
  final int contactos;
  final int productos;
  final int conversacionesActivas;
  final int usuariosActivos;
  final int modulosActivos;

  const DashboardKpis({
    required this.contactos,
    required this.productos,
    required this.conversacionesActivas,
    required this.usuariosActivos,
    required this.modulosActivos,
  });

  factory DashboardKpis.fromJson(Map<String, dynamic> json) => DashboardKpis(
        contactos: (json['contactos'] as num? ?? 0).toInt(),
        productos: (json['productos'] as num? ?? 0).toInt(),
        conversacionesActivas:
            (json['conversaciones_activas'] as num? ?? 0).toInt(),
        usuariosActivos: (json['usuarios_activos'] as num? ?? 0).toInt(),
        modulosActivos: (json['modulos_activos'] as num? ?? 0).toInt(),
      );

  static const empty = DashboardKpis(
    contactos: 0,
    productos: 0,
    conversacionesActivas: 0,
    usuariosActivos: 0,
    modulosActivos: 0,
  );
}

final dashboardKpisProvider =
    FutureProvider.autoDispose<DashboardKpis>((ref) async {
  final empresaId = ref.watch(empresaActivaIdProvider);
  if (empresaId == null) return DashboardKpis.empty;
  final data =
      await Supabase.instance.client.rpc('dashboard_get_kpis');
  return DashboardKpis.fromJson(data as Map<String, dynamic>);
});
