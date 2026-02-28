import 'package:flutter/services.dart';

import '../models/configuracion_local.dart';
import '../models/print_document.dart';
import '../models/print_job_result.dart';
import 'print_adapter.dart';

class BluetoothAdapter implements PrintAdapter {
  static const _channel = MethodChannel('tech.galapagos.pilar/print_bt');
  final ConfiguracionLocal config;

  const BluetoothAdapter(this.config);

  @override
  Future<PrintJobResult> send(PrintDocument doc) async {
    if (config.btAddress == null) {
      return PrintJobResult.error('Bluetooth: direccion no configurada');
    }
    final bytes = doc.rawBytes;
    if (bytes == null) {
      return PrintJobResult.error('Bluetooth: documento sin bytes raw');
    }
    try {
      final connected = await _channel.invokeMethod<bool>(
        'connect',
        {'address': config.btAddress},
      );
      if (connected != true) {
        return PrintJobResult.error('Bluetooth: no se pudo conectar');
      }
      await _channel.invokeMethod('send', {'data': bytes});
      await _channel.invokeMethod('disconnect');
      return PrintJobResult.ok();
    } on PlatformException catch (e) {
      return PrintJobResult.error('Bluetooth: ${e.message}');
    }
  }

  static Future<List<({String name, String address})>>
      getPairedDevices() async {
    try {
      final result = await _channel.invokeMethod<List>('getPairedDevices');
      if (result == null) return [];
      return result.map((item) {
        final m = Map<String, dynamic>.from(item as Map);
        return (name: m['name'] as String, address: m['address'] as String);
      }).toList();
    } on PlatformException {
      return [];
    }
  }
}
