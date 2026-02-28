# pilar_print

Virtual printer management for PILAR ERP.

## Overview

This package provides a platform-agnostic printing layer that decouples ERP modules from physical printers. Modules print to **virtual printers** (e.g., "POS Ticket", "Etiqueta Producto"); the local device maps each virtual printer to a physical output via configurable adapters.

## Adapters

| Adapter | Platform | Use Case |
|---------|----------|----------|
| `TcpAdapter` | Mobile/Desktop | Network printers via raw TCP socket |
| `BluetoothAdapter` | Android/iOS | Bluetooth SPP thermal printers |
| `QzTrayAdapter` | Web | Browser printing via QZ Tray WebSocket |
| `PdfAdapter` | All | System print dialog (PDF) |

## Generators

- `EscPosGenerator` -- ESC/POS byte commands for thermal receipt printers
- `ZplGenerator` -- ZPL II commands for Zebra label printers

## Usage

```dart
import 'package:pilar_print/pilar_print.dart';

// At app startup, configure with catalog from Supabase
PrintService.instance.configure(impresoras);

// From any module, print a document
final ticket = EscPosGenerator.buildTicket([
  EscPosGenerator.alignCenter,
  EscPosGenerator.boldOn,
  EscPosGenerator.textLine('MI EMPRESA'),
  EscPosGenerator.boldOff,
  EscPosGenerator.separator(),
  EscPosGenerator.textLine('Producto x1    \$10.00'),
  EscPosGenerator.separator(),
  EscPosGenerator.textLine('TOTAL:         \$10.00'),
]);

final result = await PrintService.instance.print(
  'POS Ticket',
  PrintDocument.escpos(ticket),
);

if (result.isError) {
  print('Error: ${result.errorMessage}');
}
```
