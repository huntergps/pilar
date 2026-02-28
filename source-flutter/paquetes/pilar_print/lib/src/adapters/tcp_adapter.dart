import 'dart:io';

import '../models/configuracion_local.dart';
import '../models/print_document.dart';
import '../models/print_job_result.dart';
import 'print_adapter.dart';

class TcpAdapter implements PrintAdapter {
  final ConfiguracionLocal config;

  const TcpAdapter(this.config);

  @override
  Future<PrintJobResult> send(PrintDocument doc) async {
    if (config.ip == null || config.puerto == null) {
      return PrintJobResult.error('TCP: IP o puerto no configurados');
    }
    try {
      final socket = await Socket.connect(
        config.ip!,
        config.puerto!,
        timeout: const Duration(seconds: 5),
      );
      final bytes = doc.rawBytes;
      if (bytes == null) {
        socket.close();
        return PrintJobResult.error('TCP: documento sin bytes raw');
      }
      socket.add(bytes);
      await socket.flush();
      await socket.close();
      return PrintJobResult.ok();
    } on SocketException catch (e) {
      return PrintJobResult.error('TCP: conexion fallida - ${e.message}');
    } catch (e) {
      return PrintJobResult.error('TCP: error inesperado - $e');
    }
  }
}
