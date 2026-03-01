import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Factores TOTP del usuario actual.
///
/// Retorna la lista de factores TOTP registrados (verificados o no).
/// Se invalida manualmente tras enroll/unenroll para refrescar el estado.
final mfaFactorsProvider = FutureProvider.autoDispose<List<Factor>>((ref) async {
  final factors = await Supabase.instance.client.auth.mfa.listFactors();
  return factors.totp;
});
