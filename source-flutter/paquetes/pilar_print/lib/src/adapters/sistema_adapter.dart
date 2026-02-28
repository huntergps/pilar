import 'dart:io';

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
    // Para documentos raw (ESC/POS, ZPL, ESC/P, texto) el driver del OS
    // no los entiende directamente — el módulo debe enviar PDF.
    final pdfBytes = doc.pdfBytes;
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
        final printer = await _findPrinter(printerName);
        if (printer == null) {
          return PrintJobResult.error(
            'Sistema: impresora "$printerName" no encontrada en el OS. '
            'Verifica que el driver esté instalado.',
          );
        }
        final ok = await Printing.directPrintPdf(
          printer: printer,
          onLayout: (_) async => pdfBytes,
        );
        return ok
            ? PrintJobResult.ok()
            : PrintJobResult.error('Sistema: impresión cancelada o fallida');
      } else {
        // Sin impresora fija → abrir en visor PDF del OS.
        // Printing.layoutPdf() muestra el sheet adjunto al title bar, pero
        // window_manager usa TitleBarStyle.hidden — el sheet queda invisible.
        // En macOS: escribir temp file y abrir con 'open' (Preview.app como
        // ventana separada, independiente del title bar).
        if (!Platform.isMacOS) {
          final ok = await Printing.layoutPdf(
            onLayout: (_) async => pdfBytes,
          );
          return ok
              ? PrintJobResult.ok()
              : PrintJobResult.error('Sistema: impresión cancelada');
        }
        // macOS: abrir en Preview.app
        final tempPath =
            '${Directory.systemTemp.path}/pilar_preview_${DateTime.now().millisecondsSinceEpoch}.pdf';
        await File(tempPath).writeAsBytes(pdfBytes);
        final result = await Process.run('open', [tempPath]);
        return result.exitCode == 0
            ? PrintJobResult.ok()
            : PrintJobResult.error(
                'Sistema: no se pudo abrir el visor PDF — ${result.stderr}');
      }
    } catch (e, st) {
      debugPrint('[pilar_print] SistemaAdapter error: $e\n$st');
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
