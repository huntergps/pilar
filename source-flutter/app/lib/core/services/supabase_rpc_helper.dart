import 'package:supabase_flutter/supabase_flutter.dart';

/// Ejecuta una RPC con auto-refresh de sesion si expira.
/// Reintenta UNA vez tras refrescar el token.
Future<dynamic> callRpc(
  String function, {
  Map<String, dynamic>? params,
}) async {
  try {
    return await Supabase.instance.client.rpc(function, params: params);
  } on AuthException catch (e) {
    if (e.statusCode == '401') {
      await Supabase.instance.client.auth.refreshSession();
      return await Supabase.instance.client.rpc(function, params: params);
    }
    rethrow;
  } on PostgrestException catch (e) {
    if (e.code == 'PGRST301' || e.message.contains('JWT')) {
      await Supabase.instance.client.auth.refreshSession();
      return await Supabase.instance.client.rpc(function, params: params);
    }
    rethrow;
  }
}
