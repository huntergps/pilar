import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/configuracion_local.dart';
import '../models/print_document.dart';
import '../models/print_job_result.dart';
import 'print_adapter.dart';

/// Adapter Gateway — envía el trabajo de impresión a un servidor intermediario.
///
/// Auto-detecta el protocolo por el esquema de la URL:
/// - `ws://` o `wss://` → QZ Tray (WebSocket, protocolo JSON estándar de QZ)
/// - `http://` o `https://` → HTTP POST con `{ printer, format, data: base64 }`
///
/// En ambos casos, [ConfiguracionLocal.printerName] es el nombre de la
/// impresora en el servidor intermediario (null = usar predeterminada).
class GatewayAdapter implements PrintAdapter {
  final ConfiguracionLocal config;

  const GatewayAdapter(this.config);

  @override
  Future<PrintJobResult> send(PrintDocument doc) async {
    final url = config.gatewayUrl;
    if (url == null || url.isEmpty) {
      return PrintJobResult.error('Gateway: URL no configurada');
    }

    final bytes = doc.pdfBytes ?? doc.rawBytes;
    if (bytes == null || bytes.isEmpty) {
      return PrintJobResult.error('Gateway: documento sin datos');
    }

    final lower = url.toLowerCase();
    if (lower.startsWith('ws://') || lower.startsWith('wss://')) {
      return _sendQzTray(url, doc, bytes);
    } else {
      return _sendHttp(url, doc, bytes);
    }
  }

  /// Protocolo QZ Tray via WebSocket.
  Future<PrintJobResult> _sendQzTray(
      String url, PrintDocument doc, List<int> bytes) async {
    try {
      final channel = WebSocketChannel.connect(Uri.parse(url));
      final base64Data = base64Encode(bytes);
      final isPdf = doc.pdfBytes != null;
      final payload = jsonEncode({
        'call': 'printers.print',
        'params': {
          'printer': config.printerName,
          'data': [
            {
              'type': isPdf ? 'pdf' : 'raw',
              'format': isPdf ? 'base64' : 'command',
              'flavor': 'base64',
              'data': base64Data,
            }
          ],
        },
      });
      channel.sink.add(payload);
      await channel.sink.close();
      return PrintJobResult.ok();
    } catch (e) {
      return PrintJobResult.error('Gateway (QZ Tray): error de conexión — $e');
    }
  }

  /// Protocolo HTTP POST JSON: `{ printer, format, data: base64 }`.
  Future<PrintJobResult> _sendHttp(
      String url, PrintDocument doc, List<int> bytes) async {
    try {
      final response = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'printer': config.printerName ?? 'default',
              'format': doc.format.name,
              'data': base64Encode(bytes),
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return PrintJobResult.ok();
      }
      return PrintJobResult.error(
        'Gateway (HTTP): respuesta ${response.statusCode} — ${response.body}',
      );
    } catch (e) {
      return PrintJobResult.error('Gateway (HTTP): error de conexión — $e');
    }
  }
}
