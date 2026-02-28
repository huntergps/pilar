import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/configuracion_local.dart';

class PrintConfigStore {
  static const _prefix = 'pilar_print_config_';

  Future<ConfiguracionLocal?> load(String virtualNombre) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix$virtualNombre');
    if (raw == null) return null;
    try {
      return ConfiguracionLocal.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save(ConfiguracionLocal config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_prefix${config.virtualNombre}',
      jsonEncode(config.toJson()),
    );
  }

  Future<void> delete(String virtualNombre) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$virtualNombre');
  }

  Future<List<String>> savedNombres() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs
        .getKeys()
        .where((k) => k.startsWith(_prefix))
        .map((k) => k.substring(_prefix.length))
        .toList();
  }
}
