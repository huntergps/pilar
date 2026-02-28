import 'package:flutter_test/flutter_test.dart';
import 'package:pilar_print/pilar_print.dart';

void main() {
  test('barrel exports all public classes', () {
    // TipoDocumento values
    expect(TipoDocumento.pdf, isNotNull);
    expect(TipoDocumento.escpos, isNotNull);
    expect(TipoDocumento.zpl, isNotNull);
    expect(TipoDocumento.escp, isNotNull);
    expect(TipoDocumento.texto, isNotNull);

    // TipoConexion values (refactored: gateway + sistema)
    expect(TipoConexion.tcp, isNotNull);
    expect(TipoConexion.bluetooth, isNotNull);
    expect(TipoConexion.gateway, isNotNull);
    expect(TipoConexion.sistema, isNotNull);

    // PrintFormat values
    expect(PrintFormat.escpos, isNotNull);
    expect(PrintFormat.zpl, isNotNull);
    expect(PrintFormat.pdf, isNotNull);
    expect(PrintFormat.escp, isNotNull);
    expect(PrintFormat.texto, isNotNull);

    // Classes accessible via barrel
    expect(PrintService.instance, isNotNull);
    expect(EscPosGenerator.init, isNotNull);
    expect(ZplGenerator.labelStart, isNotNull);
  });
}
