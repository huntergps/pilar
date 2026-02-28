enum TipoConexion {
  /// Socket TCP directo — impresoras en red local (puerto 9100).
  tcp,

  /// Bluetooth SPP — impresoras portátiles.
  bluetooth,

  /// Servidor intermediario: auto-detecta protocolo por la URL.
  ///   ws://localhost:8182  → QZ Tray (WebSocket)
  ///   http://host:port/... → Servidor HTTP personalizado
  gateway,

  /// Driver instalado en el sistema operativo.
  /// Soporta cualquier impresora con driver: láser, tinta, térmica, Zebra, etc.
  /// Si [printerName] está definido imprime silenciosamente;
  /// si no, abre el diálogo nativo del OS.
  sistema,
}

class ConfiguracionLocal {
  final String virtualNombre;
  final TipoConexion tipoConexion;

  /// TCP: dirección IP de la impresora.
  final String? ip;

  /// TCP: puerto de la impresora (default: 9100).
  final int? puerto;

  /// Bluetooth: MAC (Android) o número de serie (iOS).
  final String? btAddress;

  /// Gateway: URL completa del servidor intermediario.
  ///   ws://localhost:8182        → QZ Tray local
  ///   http://192.168.1.50:3000/print → Servidor HTTP
  final String? gatewayUrl;

  /// Gateway: nombre de la impresora en el servidor intermediario.
  /// Sistema: nombre exacto del driver/impresora en el OS.
  /// Null en ambos casos = usar predeterminada / mostrar diálogo.
  final String? printerName;

  const ConfiguracionLocal({
    required this.virtualNombre,
    required this.tipoConexion,
    this.ip,
    this.puerto,
    this.btAddress,
    this.gatewayUrl,
    this.printerName,
  });

  factory ConfiguracionLocal.fromJson(Map<String, dynamic> json) {
    // Migración de tipos legacy guardados en SharedPreferences
    final rawTipo = json['tipo_conexion'] as String? ?? 'sistema';
    final tipoConexion = switch (rawTipo) {
      'qztray' => TipoConexion.gateway, // legacy → gateway
      'pdf'    => TipoConexion.sistema, // legacy → sistema
      _        => TipoConexion.values.firstWhere(
                    (e) => e.name == rawTipo,
                    orElse: () => TipoConexion.sistema,
                  ),
    };

    return ConfiguracionLocal(
      virtualNombre: json['virtual_nombre'] as String,
      tipoConexion: tipoConexion,
      ip: json['ip'] as String?,
      puerto: json['puerto'] as int?,
      btAddress: json['bt_address'] as String?,
      gatewayUrl: json['gateway_url'] as String?,
      // Migración: qz_printer_name → printer_name
      printerName: (json['printer_name'] ?? json['qz_printer_name']) as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'virtual_nombre': virtualNombre,
        'tipo_conexion': tipoConexion.name,
        'ip': ip,
        'puerto': puerto,
        'bt_address': btAddress,
        'gateway_url': gatewayUrl,
        'printer_name': printerName,
      };
}
