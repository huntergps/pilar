import 'dart:typed_data';

enum PrintFormat { escpos, zpl, pdf, escp, texto }

class PrintDocument {
  final PrintFormat format;
  final Uint8List? rawBytes;
  final Uint8List? pdfBytes;

  const PrintDocument._({
    required this.format,
    this.rawBytes,
    this.pdfBytes,
  });

  factory PrintDocument.escpos(Uint8List bytes) =>
      PrintDocument._(format: PrintFormat.escpos, rawBytes: bytes);

  factory PrintDocument.zpl(Uint8List bytes) =>
      PrintDocument._(format: PrintFormat.zpl, rawBytes: bytes);

  factory PrintDocument.pdf(Uint8List bytes) =>
      PrintDocument._(format: PrintFormat.pdf, pdfBytes: bytes);

  /// Documento ESC/P para impresoras matriciales (dot-matrix).
  factory PrintDocument.escp(Uint8List bytes) =>
      PrintDocument._(format: PrintFormat.escp, rawBytes: bytes);

  /// Texto plano ASCII — impresoras que solo aceptan CR/LF.
  factory PrintDocument.texto(Uint8List bytes) =>
      PrintDocument._(format: PrintFormat.texto, rawBytes: bytes);
}
