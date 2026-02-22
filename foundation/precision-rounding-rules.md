# Reglas de Precisión y Redondeo

**Estado**: Referencia canónica — leer antes de implementar cualquier cálculo monetario
**Relacionado con**: `precision-supabase.md`, `modules/extensiones/facturacion_ec/flujos-sri.md`

---

## Tipos de datos obligatorios

La elección de tipos de datos numéricos en PILAR no es flexible: hay un tipo correcto para cada caso y usar cualquier otro es un bug latente.

| Contexto | Tipo PostgreSQL | Tipo Dart | Rango |
|----------|----------------|-----------|-------|
| Montos (totales, subtotales, impuestos) | `DECIMAL(14,2)` | `Decimal` | Hasta 999,999,999,999.99 |
| Cantidades y precios unitarios | `DECIMAL(18,6)` | `Decimal` | 6 decimales para cantidades fraccionarias |
| Tarifas de impuesto (porcentajes) | `DECIMAL(4,2)` | `Decimal` | Ej: 15.00, 5.00, 0.00 |
| Porcentajes de retención | `DECIMAL(5,2)` | `Decimal` | Ej: 100.00, 30.00, 10.00 |
| Tipos de cambio (monedas) | `DECIMAL(12,6)` | `Decimal` | 6 decimales para conversión |
| Pesos y medidas | `DECIMAL(12,4)` | `Decimal` | 4 decimales para unidades físicas |

### Tipos PROHIBIDOS para valores monetarios

| Tipo | Por qué prohibido | Error típico |
|------|------------------|--------------|
| `FLOAT` | Representación binaria — 0.1 + 0.2 ≠ 0.3 | Discrepancias de centavos en totales |
| `REAL` | Igual que FLOAT, menor precisión | Errores de redondeo acumulados |
| `DOUBLE PRECISION` | Mayor rango pero mismo problema binario | Difícil de reproducir, aparece en montos grandes |
| `double` (Dart) | Igual que FLOAT en aritmética | Totales que no cuadran en UI |
| `num` (Dart) | Puede ser int o double | Comportamiento inconsistente |

---

## Regla de oro: redondear solo al final

> **Nunca redondear valores intermedios de un cálculo. Solo redondear el resultado final de cada fase de cálculo.**

Cada "fase de cálculo" tiene un resultado que se presenta al usuario o se guarda en BD. Solo ese resultado final se redondea.

### Ejemplo: cálculo incorrecto vs correcto de un documento con IVA 15%

**INCORRECTO — redondeo en intermedios:**

```
Línea 1: 3 unidades × $10.333333 = $30.999999 → REDONDEAR → $31.00 (ERROR: se perdió precisión)
Línea 2: 5 unidades × $7.666666  = $38.333330 → REDONDEAR → $38.33 (ERROR)

Subtotal = $31.00 + $38.33 = $69.33
IVA 15%  = $69.33 × 0.15  = $10.3995 → REDONDEAR → $10.40
Total    = $69.33 + $10.40 = $79.73

-- RESULTADO INCORRECTO: $79.73
```

**CORRECTO — redondear solo al final:**

```
Línea 1: 3 × $10.333333 = $30.999999  (NO redondear)
Línea 2: 5 × $7.666666  = $38.333330  (NO redondear)

Subtotal acumulado = $30.999999 + $38.333330 = $69.333329  (NO redondear)
IVA 15%  = $69.333329 × 0.15 = $10.399999...   (NO redondear aún)
Total    = $69.333329 + $10.399999 = $79.733328

-- REDONDEAR SOLO AL FINAL:
Subtotal presentado = $69.33
IVA presentado      = $10.40
Total presentado    = $79.73

-- RESULTADO CORRECTO: $79.73
```

La diferencia es pequeña en este ejemplo, pero en documentos con muchas líneas y montos grandes, el redondeo temprano acumula errores que causan que el total no coincida con la sumatoria de líneas.

---

## Tabla de cuándo redondear por contexto

| Contexto | Fase | Redondear | Escala | Notas |
|----------|------|-----------|--------|-------|
| Precio unitario en catálogo | Al ingresar | Sí | 6 dec | Para compatibilidad con documentos electrónicos |
| Subtotal por línea (`cantidad × precio - descuento`) | Mostrar en UI | Sí | 2 dec | Solo para mostrar; guardar en BD con 6 dec |
| Suma de subtotales de líneas | Cálculo | No | — | Acumular con precisión completa |
| Base imponible por tarifa de IVA | Cálculo | No | — | Suma de líneas con esa tarifa |
| Impuesto por tarifa (`base × tarifa / 100`) | Guardar en BD | Sí | 2 dec | El SRI exige presentar impuesto redondeado por tarifa |
| Total de impuestos (suma de impuestos por tarifa) | Presentar | Sí | 2 dec | Suma de los impuestos ya redondeados por tarifa |
| Total del documento (`subtotal + impuestos`) | Presentar | Sí | 2 dec | Base de cobro al cliente |
| Tipo de cambio para conversión | Multiplicar primero | No | — | Multiplicar antes de redondear |
| Monto convertido a moneda local | Al guardar en BD | Sí | 2 dec | Resultado final de la conversión |
| Retención fuente (`base × %_retención / 100`) | Al guardar en BD | Sí | 2 dec | El SRI valida centavo a centavo |
| Retención IVA (`base_iva × %_retención_iva / 100`) | Al guardar en BD | Sí | 2 dec | Ídem |

---

## Función PostgreSQL `financial_round()`

Esta función es el único punto de redondeo permitido en SQL para valores monetarios:

```sql
-- Definida en foundation/migrations/001_core_foundation.sql
-- Se aplica ROUND_HALF_UP (el centavo 0.005 sube a 0.01)
-- Comportamiento idéntico al del SRI en sus validaciones

CREATE OR REPLACE FUNCTION financial_round(
    p_valor     DECIMAL,
    p_decimales INTEGER DEFAULT 2
)
RETURNS DECIMAL
LANGUAGE sql
IMMUTABLE   -- Sin efectos secundarios, cacheable por el planner
AS $$
    SELECT ROUND(p_valor::NUMERIC, p_decimales);
$$;

COMMENT ON FUNCTION financial_round IS
    'Redondea valores monetarios con ROUND_HALF_UP (0.005 → 0.01). '
    'Usar SOLO en valores finales, nunca en intermedios.';
```

### Uso correcto en una función de cálculo de IVA

```sql
CREATE OR REPLACE FUNCTION calcular_totales_documento(p_lineas JSONB)
RETURNS JSONB
LANGUAGE plpgsql AS $$
DECLARE
    v_linea          JSONB;
    v_subtotal_neto  DECIMAL := 0;
    v_base_iva_15    DECIMAL := 0;
    v_base_iva_0     DECIMAL := 0;
    v_iva_15         DECIMAL;
    v_total          DECIMAL;
BEGIN
    -- Acumular con precisión completa (SIN redondear)
    FOR v_linea IN SELECT * FROM jsonb_array_elements(p_lineas) LOOP
        DECLARE
            v_precio   DECIMAL := (v_linea->>'precio_unitario')::DECIMAL;
            v_cantidad DECIMAL := (v_linea->>'cantidad')::DECIMAL;
            v_desc     DECIMAL := COALESCE((v_linea->>'descuento')::DECIMAL, 0);
            v_tarifa   TEXT    := COALESCE(v_linea->>'tarifa_iva', '15');
            v_linea_subtotal DECIMAL;
        BEGIN
            -- Subtotal de línea: multiplicar primero, restar descuento (SIN redondear)
            v_linea_subtotal := (v_precio * v_cantidad) - v_desc;
            v_subtotal_neto  := v_subtotal_neto + v_linea_subtotal;

            -- Acumular base por tarifa (SIN redondear)
            IF v_tarifa = '15' THEN
                v_base_iva_15 := v_base_iva_15 + v_linea_subtotal;
            ELSE
                v_base_iva_0 := v_base_iva_0 + v_linea_subtotal;
            END IF;
        END;
    END LOOP;

    -- REDONDEAR AQUÍ: impuesto por tarifa (resultado final de cada tarifa)
    v_iva_15 := financial_round(v_base_iva_15 * 0.15);  -- 15% IVA Ecuador 2024

    -- REDONDEAR: total final
    v_total := financial_round(v_subtotal_neto + v_iva_15);

    RETURN jsonb_build_object(
        'subtotal_neto',   financial_round(v_subtotal_neto),  -- Para mostrar
        'base_iva_15',     financial_round(v_base_iva_15),
        'base_iva_0',      financial_round(v_base_iva_0),
        'iva_15',          v_iva_15,
        'total',           v_total
    );
END;
$$;
```

---

## Cómo manejar conversión de monedas

La regla es: **multiplicar primero, redondear al final**. Nunca redondear el tipo de cambio antes de usarlo.

```sql
-- INCORRECTO: redondear el tipo de cambio antes de multiplicar
UPDATE movimientos_bancarios
SET monto_usd = financial_round(monto_eur * financial_round(tipo_cambio, 2));
-- Si tipo_cambio = 1.08456 → financial_round = 1.08 → error de 0.00456 por cada unidad

-- CORRECTO: multiplicar con el tipo de cambio completo, redondear al final
UPDATE movimientos_bancarios
SET monto_usd = financial_round(monto_eur * tipo_cambio);
-- tipo_cambio = 1.08456 se usa completo, se redondea solo el resultado final
```

### Ejemplo con función de conversión

```sql
CREATE OR REPLACE FUNCTION convertir_moneda(
    p_monto         DECIMAL(18,6),
    p_tipo_cambio   DECIMAL(12,6),
    p_decimales     INTEGER DEFAULT 2
)
RETURNS DECIMAL
LANGUAGE sql IMMUTABLE AS $$
    -- Multiplicar con precisión completa, redondear solo al final
    SELECT financial_round(p_monto * p_tipo_cambio, p_decimales);
$$;

-- Uso:
SELECT convertir_moneda(1000.00, 1.08456);  -- Resultado: 1084.56
SELECT convertir_moneda(1000.00, 1.08456, 0);  -- Resultado: 1085 (para cálculos sin centavos)
```

---

## Por qué NUNCA usar `FLOAT` o `REAL` en valores monetarios

### Demostración del problema en PostgreSQL

```sql
-- FLOAT acumula errores de representación binaria:
SELECT (0.1::FLOAT + 0.2::FLOAT)::TEXT;
-- Resultado: '0.30000000000000004'  ← NO es 0.30

SELECT (100.10::FLOAT * 3::FLOAT)::TEXT;
-- Resultado: '300.30000000000001'   ← Centavo extra fantasma

-- DECIMAL es exacto:
SELECT (0.1::DECIMAL + 0.2::DECIMAL)::TEXT;
-- Resultado: '0.3'                  ← Correcto

SELECT (100.10::DECIMAL(14,2) * 3)::TEXT;
-- Resultado: '300.30'               ← Correcto
```

### En Dart: demostración del problema con `double`

```dart
// double tiene el mismo problema que FLOAT:
print(0.1 + 0.2);           // 0.30000000000000004
print(100.10 * 3);           // 300.29999999999995
print(1.005.toStringAsFixed(2));  // "1.00" (debería ser "1.01")

// Decimal (paquete decimal: ^2.3.3) es exacto:
import 'package:decimal/decimal.dart';

final a = Decimal.parse('0.1');
final b = Decimal.parse('0.2');
print((a + b).toString());   // "0.3"

final precio = Decimal.parse('100.10');
final cantidad = Decimal.parse('3');
print((precio * cantidad).toString());  // "300.30"
```

---

## Aritmética monetaria correcta en Dart

```dart
import 'package:decimal/decimal.dart';

class CalculadoraDocumento {
  /// Calcula el subtotal de una línea
  static Decimal subtotalLinea({
    required Decimal precioUnitario,
    required Decimal cantidad,
    required Decimal descuento,
  }) {
    // Multiplicar con precisión completa, NO redondear aquí
    return (precioUnitario * cantidad) - descuento;
  }

  /// Redondear solo cuando se va a mostrar o guardar
  static String formatearMonto(Decimal monto) {
    return monto.toStringAsFixed(2);
  }

  /// Calcular IVA: redondear al calcular el impuesto final
  static Decimal calcularIva(Decimal baseImponible, Decimal tarifaPorcentaje) {
    // tarifaPorcentaje: 15.00 para 15%, 0.00 para 0%
    final iva = baseImponible * (tarifaPorcentaje / Decimal.fromInt(100));
    // Redondear aquí: el IVA es un valor final que se presenta y guarda
    return iva.round(scale: 2);
  }

  /// Calcular totales completos de un documento
  static DocumentoTotales calcularTotales(List<LineaDocumento> lineas) {
    Decimal subtotalNeto = Decimal.zero;
    Decimal baseIva15 = Decimal.zero;
    Decimal baseIva0 = Decimal.zero;

    for (final linea in lineas) {
      // Acumular sin redondear
      final subtotal = subtotalLinea(
        precioUnitario: linea.precioUnitario,
        cantidad: linea.cantidad,
        descuento: linea.descuento,
      );
      subtotalNeto += subtotal;

      if (linea.tarifaIva == '15') {
        baseIva15 += subtotal;
      } else {
        baseIva0 += subtotal;
      }
    }

    // Redondear en este punto: resultados finales
    final iva15 = calcularIva(baseIva15, Decimal.parse('15'));
    final total = (subtotalNeto + iva15).round(scale: 2);

    return DocumentoTotales(
      subtotalNeto: subtotalNeto.round(scale: 2),
      baseIva15: baseIva15.round(scale: 2),
      baseIva0: baseIva0.round(scale: 2),
      iva15: iva15,
      total: total,
    );
  }
}
```

---

## Ejemplo completo: cálculo de IVA correcto vs incorrecto (Ecuador)

Documento de 5 líneas con IVA 15%:

| Línea | Cantidad | Precio Unitario | Subtotal exacto |
|-------|----------|----------------|-----------------|
| 1 | 3 | $10.333333 | $30.999999 |
| 2 | 5 | $7.666666 | $38.333330 |
| 3 | 2 | $15.555555 | $31.111110 |
| 4 | 4 | $22.777777 | $91.111108 |
| 5 | 1 | $8.999999 | $8.999999 |

### Cálculo INCORRECTO (redondeo en intermedios)

```
Línea 1: $30.999999 → $31.00
Línea 2: $38.333330 → $38.33
Línea 3: $31.111110 → $31.11
Línea 4: $91.111108 → $91.11
Línea 5: $8.999999  → $9.00

Subtotal = $31.00 + $38.33 + $31.11 + $91.11 + $9.00 = $200.55
IVA 15%  = $200.55 × 0.15 = $30.0825 → $30.08
Total    = $200.55 + $30.08 = $230.63
```

### Cálculo CORRECTO (redondear solo al final)

```
Suma exacta: $30.999999 + $38.333330 + $31.111110 + $91.111108 + $8.999999 = $200.555546

Subtotal presentado = financial_round($200.555546) = $200.56
IVA 15% = financial_round($200.555546 × 0.15) = financial_round($30.0833319) = $30.08
Total   = financial_round($200.555546 + $30.083332) = financial_round($230.638878) = $230.64
```

**Diferencia**: $230.63 vs $230.64 — un centavo que el SRI puede rechazar si el XML no cuadra.

---

## Validación de cuadre de centavo

```sql
-- Trigger para verificar que los totales del documento cuadren
-- Tolerancia: 0.01 (un centavo)
CREATE OR REPLACE FUNCTION validate_document_totals()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    v_suma_lineas      DECIMAL(14,2);
    v_suma_impuestos   DECIMAL(14,2);
    v_total_calculado  DECIMAL(14,2);
    v_diferencia       DECIMAL(14,2);
BEGIN
    -- Calcular suma de líneas
    SELECT financial_round(SUM(subtotal_linea))
    INTO v_suma_lineas
    FROM <tabla>_lineas
    WHERE documento_id = NEW.id;

    -- Calcular suma de impuestos
    SELECT financial_round(SUM(valor_impuesto))
    INTO v_suma_impuestos
    FROM <tabla>_impuestos
    WHERE documento_id = NEW.id;

    v_total_calculado := v_suma_lineas + v_suma_impuestos;
    v_diferencia := ABS(NEW.total - v_total_calculado);

    IF v_diferencia > 0.01 THEN
        RAISE EXCEPTION
            'Total del documento (%) no cuadra con suma de líneas + impuestos (%). Diferencia: %',
            NEW.total, v_total_calculado, v_diferencia;
    END IF;

    RETURN NEW;
END;
$$;
```

---

## Referencias

- `foundation/precision-supabase.md` — configuración de Supabase para precisión numérica
- `modules/extensiones/facturacion_ec/flujos-sri.md` — validaciones de cuadre exigidas por el SRI
- `modules/core/facturacion/module.md` — cálculos de factura
- Paquete Dart: `decimal: ^2.3.3` (ver `foundation/pubspec-referencia.md`)
