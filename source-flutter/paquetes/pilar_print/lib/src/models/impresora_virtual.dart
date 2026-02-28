enum TipoDocumento {
  /// Térmica de ticket — Epson ESC/POS
  escpos,
  /// Etiquetas Zebra — ZPL II
  zpl,
  /// Hoja A4/carta — diálogo nativo del OS o QZ Tray
  pdf,
  /// Matricial — ESC/P (Epson dot-matrix, formularios continuos)
  escp,
  /// Texto plano — impresoras que solo aceptan ASCII + CR/LF
  texto,
}

class ImpresoraVirtual {
  final String id;
  final String nombre;
  final TipoDocumento tipoDoc;
  final String? descripcion;

  const ImpresoraVirtual({
    required this.id,
    required this.nombre,
    required this.tipoDoc,
    this.descripcion,
  });

  factory ImpresoraVirtual.fromJson(Map<String, dynamic> json) {
    return ImpresoraVirtual(
      id: json['id'] as String,
      nombre: json['nombre'] as String,
      tipoDoc: TipoDocumento.values.firstWhere(
        (e) => e.name == (json['tipo_doc'] as String),
        orElse: () => TipoDocumento.pdf,
      ),
      descripcion: json['descripcion'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'nombre': nombre,
        'tipo_doc': tipoDoc.name,
        'descripcion': descripcion,
      };
}
