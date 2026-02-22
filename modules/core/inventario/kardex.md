# Kardex Valorado de Inventario

*Spec derivada del módulo `l10n_ec_stock_kardex` (Odoo 19.1 Ecuador — producción en csolish/tecnoh)*

---

## Descripción

Reporte de kardex valorado que muestra el movimiento cronológico de stock de cada producto, con columnas de ENTRADAS, SALIDAS y SALDOS (cantidad + costo unitario + costo total). Obligatorio para control de inventario según normativa ecuatoriana. Filtrable por producto, categoría, ubicación y rango de fechas.

---

## Estructura del Reporte

### Encabezado de columnas

```
┌─────────┬───────────────────────────────────┬──────────────────────────────────────────────────────────────────────────────────┐
│         │   (Información del movimiento)    │   ENTRADAS        │    SALIDAS        │    SALDOS          │
├──────────┬────────┬────────┬──────┬─────────┬───────────────────────────────────────────────────────────────────────────────────┤
│ Tipo Mov │ Desde/ │Entidad │Fecha │Referenc.│ Cantidad │ C.U.  │ Total │ Cantidad │ C.U.  │ Total │ Cantidad │ C.U.  │ Total    │
│          │ Hasta  │       │      │ Docum.  │          │       │       │          │       │       │          │       │          │
```

### Tipos de movimiento

| Tipo | Descripción |
|---|---|
| `INGRESO` | Compra/recepción de proveedor |
| `EGRESO` | Venta/despacho a cliente |
| `AJUSTE ENTRADA` | Ajuste de inventario (suma) |
| `AJUSTE SALIDA` | Ajuste de inventario (resta) |
| `PRODUCCIÓN` | Entrada desde producción |
| `CONSUMO` | Consumo en proceso de producción |
| `TRANSFERENCIA` | Movimiento entre ubicaciones |
| `Saldo Inicial` | Resumen de stock antes del período |
| `Saldo Final` | Resumen de stock al fin del período |

---

## Modelo de Datos

El kardex no tiene tabla propia — es un reporte calculado en tiempo real desde `stock_moves` con estado `done`. Usa el campo `value` (de `stock_account`) para los costos.

### Vista para consultas frecuentes

```sql
CREATE VIEW vista_kardex AS
SELECT
  sm.id,
  sm.company_id,
  sm.product_id,
  sm.date,
  sm.reference,
  sm.origin,
  sm.picking_id,
  sm.partner_id,
  sl_from.usage AS usage_from,
  sl_to.usage   AS usage_to,
  sl_from.name  AS ubicacion_desde,
  sl_to.name    AS ubicacion_hasta,
  pt.name       AS picking_type,
  -- Cantidades
  CASE WHEN sl_from.usage IN ('supplier','production','inventory') AND sl_to.usage = 'internal'
       THEN sm.quantity ELSE 0 END AS cantidad_entrada,
  CASE WHEN sl_from.usage = 'internal' AND sl_to.usage IN ('customer','production','inventory')
       THEN sm.quantity ELSE 0 END AS cantidad_salida,
  -- Costos (requiere módulo stock_account)
  sm.value AS costo_total
FROM stock_move sm
JOIN stock_location sl_from ON sl_from.id = sm.location_id
JOIN stock_location sl_to   ON sl_to.id   = sm.location_dest_id
LEFT JOIN stock_picking_type pt ON pt.id = sm.picking_type_id
WHERE sm.state = 'done';
```

---

## Funciones RPC

```typescript
// Generar kardex para un rango
get_kardex(params: {
  fecha_desde: string
  fecha_hasta: string
  producto_ids?: UUID[]
  categoria_ids?: UUID[]
  ubicacion_ids?: UUID[]
}): {
  lineas: [{
    tipo_mov: string
    desde_hasta: string
    entidad: string
    fecha: string
    referencia: string
    documento: string
    uom: string
    // Entradas
    entrada_cantidad: number
    entrada_costo_unitario: number
    entrada_costo_total: number
    // Salidas
    salida_cantidad: number
    salida_costo_unitario: number
    salida_costo_total: number
    // Saldos
    saldo_cantidad: number
    saldo_costo_unitario: number
    saldo_costo_total: number
    producto_id: UUID
  }]
  saldo_inicial: { cantidad: number, valor: number }
  saldo_final: { cantidad: number, valor: number }
}

// Exportar a Excel/PDF
export_kardex(params: {
  fecha_desde: string
  fecha_hasta: string
  producto_ids?: UUID[]
  formato: 'pdf' | 'xlsx'
}): { url: string }

// Métricas de rotación (opcional)
get_rotacion_producto(params: {
  producto_id: UUID
  fecha_desde: string
  fecha_hasta: string
}): {
  inventario_promedio: number
  rotacion: number          // veces por período
  dias_en_inventario: number
  costo_ventas: number
}
```

---

## Configuración por Empresa

```json
{
  "kardex": {
    "decimales": 3,
    "formato_fecha": "dmy",          // dmy=DD/MM/YYYY, mdy=MM/DD/YYYY, ymd=YYYY-MM-DD
    "mostrar_categorias": true,
    "seleccion_multiple_productos": true,
    "seleccion_multiple_categorias": false,
    "mostrar_metricas_rotacion": false
  }
}
```

---

## Validaciones

- Rango máximo del reporte: 365 días
- Se requiere seleccionar al menos un producto o categoría (reporte vacío si no)
- Stock negativo genera alerta visual (no bloquea)

---

## Pantalla Flutter

### Filtros del Kardex

```
┌────────────────────────────────────────────────────────────────┐
│ KARDEX VALORADO DE INVENTARIO                                  │
│ Producto: [selector multi-producto ▼]                          │
│ Categoría: [selector ▼]    Ubicación: [todas ▼]               │
│ Desde: [2026-01-01]  Hasta: [2026-01-31]  [Generar]           │
├────────────────────────────────────────────────────────────────┤
│ Laptop ASUS X15 (und)                                          │
│ Saldo Inicial: 5.000 unid | $4,750.000                         │
├───────────┬────────────┬────────┬────────┬──────┬─────────────┤
│ Tipo Mov  │ Desde/Hasta│ Fecha  │ Ref.   │ ENTRADAS  │ SALIDAS │
├───────────┼────────────┼────────┼────────┼───────────┼─────────┤
│ INGRESO   │ Proveedor  │ 05/01  │ REC-1  │ 10│950│9500│      0│
│ EGRESO    │ Cliente    │ 08/01  │ DEP-2  │          0│  3│950│2850│
│ TRANSFERENCIA│ Bod.2→1│ 15/01  │ INT-5  │  2│950│1900│      0│
├───────────┴────────────┴────────┴────────┼───────────┼─────────┤
│ SALDO FINAL                              │ 14│950│13300        │
└──────────────────────────────────────────┴───────────┴─────────┘
│ [Exportar PDF]  [Exportar Excel]                               │
```

---

## Vista Materializada para Reportes de Alto Volumen

Para empresas con más de 50.000 movimientos, el kardex calculado en tiempo real puede ser lento. Se usa una vista materializada refrescada periódicamente:

```sql
-- Vista materializada para reportes de kardex (performance)
CREATE MATERIALIZED VIEW mv_kardex_valorado AS
SELECT
  m.empresa_id,
  m.producto_id,
  m.bodega_id,
  m.fecha,
  m.tipo_movimiento,
  m.cantidad,
  m.costo_unitario,
  m.cantidad * m.costo_unitario AS valor_movimiento,
  SUM(CASE WHEN m.tipo_movimiento IN ('COMPRA','AJUSTE_POSITIVO','ENSAMBLE_ENTRADA','TRANSFERENCIA_ENTRADA','DEVOLUCION_VENTA')
       THEN m.cantidad ELSE -m.cantidad END)
    OVER (PARTITION BY m.producto_id, m.bodega_id ORDER BY m.fecha, m.id) AS saldo_unidades,
  SUM(CASE WHEN m.tipo_movimiento IN ('COMPRA','AJUSTE_POSITIVO','ENSAMBLE_ENTRADA','TRANSFERENCIA_ENTRADA','DEVOLUCION_VENTA')
       THEN m.cantidad * m.costo_unitario ELSE -(m.cantidad * m.costo_unitario) END)
    OVER (PARTITION BY m.producto_id, m.bodega_id ORDER BY m.fecha, m.id) AS saldo_valor
FROM movimientos_inventario m
WHERE m.estado = 'CONFIRMADO'
WITH DATA;

-- Índice principal para filtros de kardex
CREATE INDEX ON mv_kardex_valorado (empresa_id, producto_id, bodega_id, fecha);

-- Índices de soporte para filtros adicionales
CREATE INDEX ON mv_kardex_valorado (empresa_id, fecha);
CREATE INDEX ON mv_kardex_valorado (empresa_id, producto_id, fecha);
```

---

## Funciones RPC Adicionales

### `get_kardex_report` — Kardex con saldo acumulado y CPP

```sql
CREATE OR REPLACE FUNCTION get_kardex_report(
  p_empresa_id    UUID,
  p_producto_id   UUID,
  p_bodega_id     UUID    DEFAULT NULL,
  p_fecha_desde   DATE,
  p_fecha_hasta   DATE
)
RETURNS TABLE (
  fecha             DATE,
  tipo_movimiento   TEXT,
  referencia        TEXT,
  entidad           TEXT,
  cantidad_entrada  DECIMAL(18,6),
  cantidad_salida   DECIMAL(18,6),
  costo_unitario    DECIMAL(14,6),
  valor_entrada     DECIMAL(14,2),
  valor_salida      DECIMAL(14,2),
  saldo_unidades    DECIMAL(18,6),
  saldo_valor       DECIMAL(14,2),
  costo_promedio    DECIMAL(14,6)
) LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_mv_fresca BOOLEAN;
BEGIN
  -- Verificar si la vista materializada está fresca (< 1 hora)
  SELECT (NOW() - pg_stat_user_tables.last_autovacuum) < INTERVAL '1 hour'
  INTO v_mv_fresca
  FROM pg_stat_user_tables
  WHERE relname = 'mv_kardex_valorado';

  IF v_mv_fresca AND p_bodega_id IS NOT NULL THEN
    -- Usar vista materializada para performance
    RETURN QUERY
    SELECT
      k.fecha,
      k.tipo_movimiento,
      m.referencia,
      c.nombre AS entidad,
      CASE WHEN k.tipo_movimiento IN ('COMPRA','AJUSTE_POSITIVO','ENSAMBLE_ENTRADA',
           'TRANSFERENCIA_ENTRADA','DEVOLUCION_VENTA') THEN k.cantidad ELSE 0 END,
      CASE WHEN k.tipo_movimiento NOT IN ('COMPRA','AJUSTE_POSITIVO','ENSAMBLE_ENTRADA',
           'TRANSFERENCIA_ENTRADA','DEVOLUCION_VENTA') THEN k.cantidad ELSE 0 END,
      k.costo_unitario,
      CASE WHEN k.tipo_movimiento IN ('COMPRA','AJUSTE_POSITIVO','ENSAMBLE_ENTRADA',
           'TRANSFERENCIA_ENTRADA','DEVOLUCION_VENTA') THEN k.valor_movimiento ELSE 0 END,
      CASE WHEN k.tipo_movimiento NOT IN ('COMPRA','AJUSTE_POSITIVO','ENSAMBLE_ENTRADA',
           'TRANSFERENCIA_ENTRADA','DEVOLUCION_VENTA') THEN k.valor_movimiento ELSE 0 END,
      k.saldo_unidades,
      k.saldo_valor,
      CASE WHEN k.saldo_unidades > 0 THEN ROUND(k.saldo_valor / k.saldo_unidades, 6) ELSE 0 END
    FROM mv_kardex_valorado k
    JOIN movimientos_inventario m ON m.id = k.empresa_id   -- join referencia
    LEFT JOIN contactos c ON c.id = m.contacto_id
    WHERE k.empresa_id = p_empresa_id
      AND k.producto_id = p_producto_id
      AND (p_bodega_id IS NULL OR k.bodega_id = p_bodega_id)
      AND k.fecha BETWEEN p_fecha_desde AND p_fecha_hasta
    ORDER BY k.fecha ASC, k.saldo_unidades;
  ELSE
    -- Calcular en tiempo real desde movimientos_inventario
    RETURN QUERY
    SELECT
      m.fecha,
      m.tipo_movimiento,
      m.referencia,
      c.nombre AS entidad,
      CASE WHEN m.tipo_movimiento IN ('COMPRA','AJUSTE_POSITIVO','ENSAMBLE_ENTRADA',
           'TRANSFERENCIA_ENTRADA','DEVOLUCION_VENTA') THEN m.cantidad ELSE 0 END,
      CASE WHEN m.tipo_movimiento NOT IN ('COMPRA','AJUSTE_POSITIVO','ENSAMBLE_ENTRADA',
           'TRANSFERENCIA_ENTRADA','DEVOLUCION_VENTA') THEN m.cantidad ELSE 0 END,
      m.costo_unitario,
      CASE WHEN m.tipo_movimiento IN ('COMPRA','AJUSTE_POSITIVO','ENSAMBLE_ENTRADA',
           'TRANSFERENCIA_ENTRADA','DEVOLUCION_VENTA') THEN m.cantidad * m.costo_unitario ELSE 0 END,
      CASE WHEN m.tipo_movimiento NOT IN ('COMPRA','AJUSTE_POSITIVO','ENSAMBLE_ENTRADA',
           'TRANSFERENCIA_ENTRADA','DEVOLUCION_VENTA') THEN m.cantidad * m.costo_unitario ELSE 0 END,
      SUM(CASE WHEN m.tipo_movimiento IN ('COMPRA','AJUSTE_POSITIVO','ENSAMBLE_ENTRADA',
               'TRANSFERENCIA_ENTRADA','DEVOLUCION_VENTA') THEN m.cantidad ELSE -m.cantidad END)
        OVER (PARTITION BY m.producto_id, m.bodega_id ORDER BY m.fecha, m.id),
      SUM(CASE WHEN m.tipo_movimiento IN ('COMPRA','AJUSTE_POSITIVO','ENSAMBLE_ENTRADA',
               'TRANSFERENCIA_ENTRADA','DEVOLUCION_VENTA')
               THEN m.cantidad * m.costo_unitario ELSE -(m.cantidad * m.costo_unitario) END)
        OVER (PARTITION BY m.producto_id, m.bodega_id ORDER BY m.fecha, m.id),
      CASE WHEN SUM(CASE WHEN m.tipo_movimiento IN ('COMPRA','AJUSTE_POSITIVO','ENSAMBLE_ENTRADA',
               'TRANSFERENCIA_ENTRADA','DEVOLUCION_VENTA') THEN m.cantidad ELSE -m.cantidad END)
               OVER (PARTITION BY m.producto_id, m.bodega_id ORDER BY m.fecha, m.id) > 0
           THEN ROUND(
             SUM(CASE WHEN m.tipo_movimiento IN ('COMPRA','AJUSTE_POSITIVO','ENSAMBLE_ENTRADA',
               'TRANSFERENCIA_ENTRADA','DEVOLUCION_VENTA')
               THEN m.cantidad * m.costo_unitario ELSE -(m.cantidad * m.costo_unitario) END)
               OVER (PARTITION BY m.producto_id, m.bodega_id ORDER BY m.fecha, m.id)
             /
             SUM(CASE WHEN m.tipo_movimiento IN ('COMPRA','AJUSTE_POSITIVO','ENSAMBLE_ENTRADA',
               'TRANSFERENCIA_ENTRADA','DEVOLUCION_VENTA') THEN m.cantidad ELSE -m.cantidad END)
               OVER (PARTITION BY m.producto_id, m.bodega_id ORDER BY m.fecha, m.id), 6)
           ELSE 0 END
    FROM movimientos_inventario m
    LEFT JOIN contactos c ON c.id = m.contacto_id
    WHERE m.empresa_id = p_empresa_id
      AND m.producto_id = p_producto_id
      AND (p_bodega_id IS NULL OR m.bodega_id = p_bodega_id)
      AND m.fecha BETWEEN p_fecha_desde AND p_fecha_hasta
      AND m.estado = 'CONFIRMADO'
    ORDER BY m.fecha ASC, m.id;
  END IF;
END;
$$;
```

### `get_stock_valuation_by_date` — Valorización a fecha de cierre

```sql
CREATE OR REPLACE FUNCTION get_stock_valuation_by_date(
  p_empresa_id  UUID,
  p_fecha       DATE
)
RETURNS TABLE (
  producto_id       UUID,
  producto_nombre   TEXT,
  bodega_id         UUID,
  bodega_nombre     TEXT,
  saldo_unidades    DECIMAL(18,6),
  costo_promedio    DECIMAL(14,6),
  valor_total       DECIMAL(14,2)
) LANGUAGE sql SECURITY DEFINER AS $$
  SELECT
    p.id            AS producto_id,
    p.nombre        AS producto_nombre,
    b.id            AS bodega_id,
    b.nombre        AS bodega_nombre,
    SUM(CASE WHEN m.tipo_movimiento IN ('COMPRA','AJUSTE_POSITIVO','ENSAMBLE_ENTRADA',
             'TRANSFERENCIA_ENTRADA','DEVOLUCION_VENTA') THEN m.cantidad ELSE -m.cantidad END)
      AS saldo_unidades,
    CASE WHEN SUM(CASE WHEN m.tipo_movimiento IN ('COMPRA','AJUSTE_POSITIVO','ENSAMBLE_ENTRADA',
                       'TRANSFERENCIA_ENTRADA','DEVOLUCION_VENTA') THEN m.cantidad ELSE -m.cantidad END) > 0
         THEN ROUND(
           SUM(CASE WHEN m.tipo_movimiento IN ('COMPRA','AJUSTE_POSITIVO','ENSAMBLE_ENTRADA',
               'TRANSFERENCIA_ENTRADA','DEVOLUCION_VENTA')
               THEN m.cantidad * m.costo_unitario ELSE -(m.cantidad * m.costo_unitario) END)
           /
           SUM(CASE WHEN m.tipo_movimiento IN ('COMPRA','AJUSTE_POSITIVO','ENSAMBLE_ENTRADA',
               'TRANSFERENCIA_ENTRADA','DEVOLUCION_VENTA') THEN m.cantidad ELSE -m.cantidad END), 6)
         ELSE 0 END AS costo_promedio,
    ROUND(
      SUM(CASE WHEN m.tipo_movimiento IN ('COMPRA','AJUSTE_POSITIVO','ENSAMBLE_ENTRADA',
               'TRANSFERENCIA_ENTRADA','DEVOLUCION_VENTA')
               THEN m.cantidad * m.costo_unitario ELSE -(m.cantidad * m.costo_unitario) END), 2)
      AS valor_total
  FROM movimientos_inventario m
  JOIN productos p ON p.id = m.producto_id
  JOIN bodegas b ON b.id = m.bodega_id
  WHERE m.empresa_id = p_empresa_id
    AND m.fecha <= p_fecha
    AND m.estado = 'CONFIRMADO'
  GROUP BY p.id, p.nombre, b.id, b.nombre
  HAVING SUM(CASE WHEN m.tipo_movimiento IN ('COMPRA','AJUSTE_POSITIVO','ENSAMBLE_ENTRADA',
             'TRANSFERENCIA_ENTRADA','DEVOLUCION_VENTA') THEN m.cantidad ELSE -m.cantidad END) > 0;
$$;
```

### `refresh_kardex_view` — Cron para refrescar vista materializada

```sql
CREATE OR REPLACE FUNCTION refresh_kardex_view()
RETURNS void LANGUAGE sql SECURITY DEFINER AS $$
  REFRESH MATERIALIZED VIEW CONCURRENTLY mv_kardex_valorado;
$$;

-- Programar con pg_cron (ejecutar cada hora)
-- SELECT cron.schedule('refresh-kardex', '0 * * * *', 'SELECT refresh_kardex_view()');
```

---

## Métodos de Valoración Ecuador

Ecuador bajo NIIF PYMES admite tres métodos de valoración de inventario:

### CPP — Costo Promedio Ponderado (el más usado)

Es el método predominante en Ecuador por su simplicidad contable y aceptación del SRI. El costo promedio se recalcula en cada compra:

```
costo_promedio_nuevo = (valor_stock_anterior + valor_compra_nueva)
                       / (qty_anterior + qty_nueva)
```

**Ejemplo con cálculo paso a paso:**

```
Producto: Harina 50kg
─────────────────────────────────────────────────────────────────
COMPRA 1: 100 sacos @ $12.00
  Stock:       100 sacos
  Valor total: $1,200.00
  CPP:         $12.00

COMPRA 2: 50 sacos @ $14.00
  CPP nuevo = (100×$12.00 + 50×$14.00) / (100+50)
            = ($1,200.00 + $700.00) / 150
            = $1,900.00 / 150
            = $12.67 (redondeado)
  Stock:       150 sacos
  Valor total: $1,900.00

VENTA: 80 sacos
  Costo de venta = 80 × $12.67 = $1,013.33 (→ asiento contable)
  Stock restante: 70 sacos
  Valor restante: $1,900.00 - $1,013.33 = $886.67
  CPP actual:     $886.67 / 70 = $12.67 (sin variación porque CPP no cambia por salidas)

SALDO FINAL:
  70 sacos × $12.67 = $886.90  ← pequeña diferencia por redondeo
  (ajuste de redondeo: $0.23 se registra en cuenta diferencia de inventario)
```

**Regla de redondeo**: el CPP se almacena con 6 decimales internamente (`DECIMAL(14,6)`) y se muestra con 2 en reportes. El redondeo se aplica SOLO al calcular el asiento contable final, nunca en intermedios.

### FIFO — First In, First Out

Permitido bajo NIIF completas. Las salidas se valúan al costo del lote más antiguo:

```
Lote 1: 100 und @ $10.00 (entrada: 01/01)
Lote 2:  50 und @ $12.00 (entrada: 15/01)

Venta de 120 und:
  → 100 und × $10.00 = $1,000.00  (del Lote 1, se agota)
  →  20 und × $12.00 =   $240.00  (del Lote 2)
  Total costo de venta: $1,240.00
  Stock restante: 30 und del Lote 2 @ $12.00
```

En PILAR, FIFO se implementa a través de `series_lotes` con campo `fecha_entrada` para ordenar las salidas.

### Costo Estándar

Para empresas manufactureras. Se define un costo estándar por producto y las variaciones (favorable/desfavorable) se registran en cuentas separadas:

```
Costo estándar: $15.00/und
Costo real de producción: $16.50/und
Variación desfavorable: $1.50/und → cuenta 5204 Variaciones de Costo
```

---

## Índices Adicionales para Performance

```sql
-- Para filtros por tipo de movimiento (reportes de compras vs ventas)
CREATE INDEX idx_mov_inv_empresa_tipo_fecha
  ON movimientos_inventario (empresa_id, tipo_movimiento, fecha)
  WHERE estado = 'CONFIRMADO';

-- Para filtros por bodega + producto (kardex por bodega)
CREATE INDEX idx_mov_inv_bodega_producto
  ON movimientos_inventario (empresa_id, bodega_id, producto_id, fecha)
  WHERE estado = 'CONFIRMADO';

-- Para cálculo de saldo inicial (fecha < fecha_desde)
CREATE INDEX idx_mov_inv_producto_fecha_estado
  ON movimientos_inventario (producto_id, fecha, estado);

-- En mv_kardex_valorado para rango de fechas
CREATE INDEX ON mv_kardex_valorado (empresa_id, bodega_id, fecha);
CREATE INDEX ON mv_kardex_valorado (empresa_id, producto_id, saldo_unidades)
  WHERE saldo_unidades > 0;
```
