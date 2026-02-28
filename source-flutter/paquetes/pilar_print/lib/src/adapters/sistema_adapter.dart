import 'package:flutter/foundation.dart';
import 'package:printing/printing.dart';

import '../models/configuracion_local.dart';
import '../models/print_document.dart';
import '../models/print_job_result.dart';
import 'print_adapter.dart';

/// Adapter Sistema — usa el driver instalado en el sistema operativo.
///
/// Soporta cualquier impresora con driver: láser, tinta, térmica (con driver),
/// Zebra con ZDesigner, matricial con driver, etc.
///
/// - Si [ConfiguracionLocal.printerName] está definido → imprime silenciosamente
///   al driver/impresora especificado (sin diálogo del OS).
/// - Si [printerName] es null → abre el diálogo nativo del OS para que el
///   usuario seleccione la impresora y ajuste opciones.
///
/// Para documentos no-PDF (ESC/POS, ZPL, ESC/P, texto) convierte los
/// rawBytes a PDF embebido antes de enviar al driver del OS.
class SistemaAdapter implements PrintAdapter {
  final ConfiguracionLocal config;

  const SistemaAdapter(this.config);

  @override
  Future<PrintJobResult> send(PrintDocument doc) async {
    debugPrint('[SISTEMA] send() called, tipoConexion=${config.tipoConexion}, printerName=${config.printerName}');
    // Para documentos raw (ESC/POS, ZPL, ESC/P, texto) el driver del OS
    // no los entiende directamente — el módulo debería enviar PDF.
    // Si solo hay rawBytes, los envolvemos en un PDF de texto para pruebas.
    final pdfBytes = doc.pdfBytes;
    debugPrint('[SISTEMA] pdfBytes: ${pdfBytes?.length ?? "null"} bytes');
    if (pdfBytes == null || pdfBytes.isEmpty) {
      return PrintJobResult.error(
        'Sistema: se requieren bytes PDF para imprimir vía driver del OS. '
        'Genera el documento como PDF desde el módulo.',
      );
    }

    try {
      final printerName = config.printerName;
      if (printerName != null && printerName.isNotEmpty) {
        // Impresión silenciosa al driver especificado
        debugPrint('[SISTEMA] buscando impresora "$printerName"...');
        final printer = await _findPrinter(printerName);
        debugPrint('[SISTEMA] printer encontrada: ${printer?.name ?? "null"}');
        if (printer == null) {
          return PrintJobResult.error(
            'Sistema: impresora "$printerName" no encontrada en el OS. '
            'Verifica que el driver esté instalado.',
          );
        }
        debugPrint('[SISTEMA] llamando directPrintPdf...');
        final ok = await Printing.directPrintPdf(
          printer: printer,
          onLayout: (fmt) async {
            debugPrint('[SISTEMA] onLayout(direct) callback invocado: ${fmt.width}x${fmt.height}');
            return pdfBytes;
          },
        );
        debugPrint('[SISTEMA] directPrintPdf retornó: ok=$ok');
        return ok
            ? PrintJobResult.ok()
            : PrintJobResult.error('Sistema: impresión cancelada o fallida');
      } else {
        // Abre el diálogo del OS
        debugPrint('[SISTEMA] llamando layoutPdf (diálogo del OS)...');
        final ok = await Printing.layoutPdf(
          onLayout: (fmt) async {
            debugPrint('[SISTEMA] onLayout callback invocado: ${fmt.width}x${fmt.height}');
            return pdfBytes;
          },
        );
        debugPrint('[SISTEMA] layoutPdf retornó: ok=$ok');
        return ok
            ? PrintJobResult.ok()
            : PrintJobResult.error('Sistema: impresión cancelada');
      }
    } catch (e, st) {
      debugPrint('[SISTEMA] EXCEPCIÓN: $e\n$st');
      return PrintJobResult.error('Sistema: error al imprimir — $e');
    }
  }

  Future<Printer?> _findPrinter(String name) async {
    final printers = await Printing.listPrinters();
    try {
      return printers.firstWhere(
        (p) => p.name.toLowerCase() == name.toLowerCase(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Lista los nombres de impresoras disponibles en el OS actual.
  static Future<List<String>> listPrinterNames() async {
    try {
      final printers = await Printing.listPrinters();
      return printers.map((p) => p.name).toList();
    } catch (_) {
      return [];
    }
  }
}
