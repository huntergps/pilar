import 'package:flutter/foundation.dart';

import 'adapters/bluetooth_adapter.dart';
import 'adapters/gateway_adapter.dart';
import 'adapters/print_adapter.dart';
import 'adapters/sistema_adapter.dart';
import 'adapters/tcp_adapter.dart';
import 'config/print_config_store.dart';
import 'models/configuracion_local.dart';
import 'models/impresora_virtual.dart';
import 'models/print_document.dart';
import 'models/print_job_result.dart';

class PrintService {
  PrintService._();
  static final PrintService instance = PrintService._();

  List<ImpresoraVirtual> _catalogo = [];
  final _store = PrintConfigStore();

  /// Called by Foundation at app startup with catalog from Supabase.
  void configure(List<ImpresoraVirtual> impresoras) {
    _catalogo = List.unmodifiable(impresoras);
  }

  List<ImpresoraVirtual> get catalogo => _catalogo;

  /// Prints a document to the virtual printer identified by [nombreVirtual].
  /// Modules call this without knowing about the physical printer.
  Future<PrintJobResult> print(String nombreVirtual, PrintDocument doc) async {
    final virtual = _catalogo.cast<ImpresoraVirtual?>().firstWhere(
          (v) => v!.nombre == nombreVirtual,
          orElse: () => null,
        );
    if (virtual == null) {
      return PrintJobResult.error(
        'Impresora virtual "$nombreVirtual" no encontrada en el catalogo',
      );
    }
    final config = await _store.load(nombreVirtual);
    if (config == null) {
      return PrintJobResult.error(
        'Impresora "$nombreVirtual" no configurada en este dispositivo',
      );
    }
    final adapter = _resolveAdapter(config);
    return adapter.send(doc);
  }

  PrintAdapter _resolveAdapter(ConfiguracionLocal config) {
    if (kIsWeb) {
      // Web: solo Gateway (QZ Tray via ws://) o Sistema (diálogo PDF)
      return config.tipoConexion == TipoConexion.sistema
          ? SistemaAdapter(config)
          : GatewayAdapter(config);
    }
    return switch (config.tipoConexion) {
      TipoConexion.tcp       => TcpAdapter(config),
      TipoConexion.bluetooth => BluetoothAdapter(config),
      TipoConexion.gateway   => GatewayAdapter(config),
      TipoConexion.sistema   => SistemaAdapter(config),
    };
  }

  Future<List<({String name, String address})>> getPairedBluetoothDevices() {
    return BluetoothAdapter.getPairedDevices();
  }

  /// Lista impresoras instaladas en el OS actual (para TipoConexion.sistema).
  Future<List<String>> getSystemPrinterNames() {
    return SistemaAdapter.listPrinterNames();
  }

  Future<void> saveConfig(ConfiguracionLocal config) => _store.save(config);
  Future<void> deleteConfig(String nombreVirtual) =>
      _store.delete(nombreVirtual);
  Future<ConfiguracionLocal?> loadConfig(String nombreVirtual) =>
      _store.load(nombreVirtual);
}
