# Dashboard de Inventario en Tiempo Real


## Descripcion Funcional

Dashboard dedicado al modulo de inventario que complementa el dashboard general existente (seccion 15.1.1). Muestra KPIs operativos en tiempo real, alertas visuales, y graficos analiticos. Se actualiza via Supabase Realtime (subscribeToRealtime) para reflejar cambios de stock instantaneamente.

**KPIs principales:**

| KPI | RPC | Visualizacion |
|-----|-----|---------------|
| Stock valorizado total | `dashboard_inv_total_value` | Card grande con sparkline |
| Rotacion promedio (indice) | `get_inventory_rotation` (existente) | Card con gauge |
| Productos bajo minimo | `get_low_stock_products` (existente) | Badge + lista |
| Productos agotados (stock=0 con demanda) | `dashboard_inv_out_of_stock` | Badge rojo |
| Transferencias en transito | `dashboard_inv_transfers_transit` | Badge + lista |
| Ordenes picking pendientes | `dashboard_inv_pending_picking` | Badge + lista |
| Lotes por vencer (30/60/90 dias) | `get_expiring_products` (existente) | Barras apiladas |
| Stock negativo (anomalias) | `dashboard_inv_negative_stock` | Badge rojo alerta |
| Productos sin movimiento (>90 dias) | `get_slow_moving_products` (existente) | Lista |
| Recepciones pendientes de OC | `dashboard_inv_pending_receipts` | Badge |

**Graficos:**

1. **ABC (Pareto):** Barras con curva acumulada. Eje X: productos (A, B, C). Eje Y izq: valor. Eje Y der: % acumulado.
2. **Top 10 por valor en stock:** Barras horizontales.
3. **Top 10 por rotacion:** Barras horizontales (productos que mas rotan).
4. **Top 10 por margen:** Barras horizontales (precio venta - costo).
5. **Movimientos por tipo y periodo:** Linea temporal (ingresos vs egresos vs ajustes).
6. **Valoracion por bodega:** Donut/Pie chart.

## Modelo de Datos SQL

```sql
-- No se requieren tablas nuevas para el dashboard.
-- Se crean RPCs que consultan tablas existentes:
--   inventario_stock, kardex, transferencias_inventario,
--   ordenes_picking, series_lotes, reglas_reabastecimiento,
--   forecast_resultados (del gap 23.3)

-- Tabla de configuracion de widgets del dashboard de inventario
-- (reutiliza dashboard_config_usuario existente con widgets tipo inventario)
```

## Funciones PostgreSQL

```sql
-- ============================================================
-- KPI: Stock valorizado total por bodega y general
-- ============================================================

CREATE OR REPLACE FUNCTION dashboard_inv_total_value(
  p_empresa_id UUID,
  p_bodega_id UUID DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER STABLE AS $$
DECLARE
  v_total DECIMAL(14,2);
  v_por_bodega JSONB;
BEGIN
  SELECT COALESCE(SUM(ist.cantidad * COALESCE(
    CASE p.metodo_valoracion
      WHEN 'ESTANDAR' THEN p.costo_estandar
      ELSE p.costo
    END, 0
  )), 0)
  INTO v_total
  FROM inventario_stock ist
  JOIN productos p ON p.id = ist.producto_id
  WHERE ist.empresa_id = p_empresa_id
    AND ist.cantidad > 0
    AND (p_bodega_id IS NULL OR ist.bodega_id = p_bodega_id);

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'bodega_id', b.id,
    'bodega_nombre', b.nombre,
    'valor', COALESCE(sub.valor, 0),
    'productos', COALESCE(sub.productos, 0)
  )), '[]'::JSONB)
  INTO v_por_bodega
  FROM bodegas b
  LEFT JOIN (
    SELECT ist.bodega_id,
      ROUND(SUM(ist.cantidad * COALESCE(p.costo, 0)), 2) AS valor,
      COUNT(DISTINCT ist.producto_id) AS productos
    FROM inventario_stock ist
    JOIN productos p ON p.id = ist.producto_id
    WHERE ist.empresa_id = p_empresa_id AND ist.cantidad > 0
    GROUP BY ist.bodega_id
  ) sub ON sub.bodega_id = b.id
  WHERE b.empresa_id = p_empresa_id AND b.activo = true;

  RETURN jsonb_build_object(
    'valor_total', ROUND(v_total, 2),
    'por_bodega', v_por_bodega,
    'drill_down_url', '/inventario/reportes/valoracion'
  );
END;
$$;

-- ============================================================
-- KPI: Productos agotados con demanda
-- ============================================================

CREATE OR REPLACE FUNCTION dashboard_inv_out_of_stock(
  p_empresa_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER STABLE AS $$
DECLARE
  v_count INTEGER;
  v_productos JSONB;
BEGIN
  SELECT COUNT(*), COALESCE(jsonb_agg(jsonb_build_object(
    'producto_id', sub.producto_id,
    'nombre', sub.nombre,
    'demanda_diaria', sub.demanda_diaria,
    'ultimo_movimiento', sub.ultimo_mov
  ) ORDER BY sub.demanda_diaria DESC) FILTER (WHERE sub.rn <= 10), '[]'::JSONB)
  INTO v_count, v_productos
  FROM (
    SELECT p.id AS producto_id, p.nombre,
      COALESCE(fr.demanda_promedio_diaria, 0) AS demanda_diaria,
      (SELECT MAX(fecha) FROM kardex WHERE producto_id = p.id) AS ultimo_mov,
      ROW_NUMBER() OVER (ORDER BY COALESCE(fr.demanda_promedio_diaria, 0) DESC) AS rn
    FROM productos p
    LEFT JOIN inventario_stock ist ON ist.producto_id = p.id AND ist.empresa_id = p_empresa_id
    LEFT JOIN forecast_resultados fr ON fr.producto_id = p.id AND fr.empresa_id = p_empresa_id
    WHERE p.empresa_id = p_empresa_id
      AND p.activo = true
      AND p.tipo IN ('PRODUCTO', 'ENSAMBLAJE')
      AND COALESCE(ist.cantidad, 0) <= 0
      AND COALESCE(fr.demanda_promedio_diaria, 0) > 0
  ) sub;

  RETURN jsonb_build_object(
    'count', v_count,
    'productos', v_productos,
    'drill_down_url', '/inventario/reportes/agotados'
  );
END;
$$;

-- ============================================================
-- KPI: Transferencias en transito
-- ============================================================

CREATE OR REPLACE FUNCTION dashboard_inv_transfers_transit(
  p_empresa_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER STABLE AS $$
BEGIN
  RETURN (
    SELECT jsonb_build_object(
      'count', COUNT(*),
      'transferencias', COALESCE(jsonb_agg(jsonb_build_object(
        'id', ti.id,
        'origen', bo.nombre,
        'destino', bd.nombre,
        'fecha_envio', ti.fecha_envio,
        'items', (SELECT COUNT(*) FROM transferencia_inventario_lineas WHERE transferencia_id = ti.id)
      ) ORDER BY ti.fecha_envio), '[]'::JSONB),
      'drill_down_url', '/inventario/transferencias?estado=EN_TRANSITO'
    )
    FROM transferencias_inventario ti
    JOIN bodegas bo ON bo.id = ti.bodega_origen_id
    JOIN bodegas bd ON bd.id = ti.bodega_destino_id
    WHERE ti.empresa_id = p_empresa_id AND ti.estado = 'EN_TRANSITO'
  );
END;
$$;

-- ============================================================
-- KPI: Picking pendiente
-- ============================================================

CREATE OR REPLACE FUNCTION dashboard_inv_pending_picking(
  p_empresa_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER STABLE AS $$
BEGIN
  RETURN (
    SELECT jsonb_build_object(
      'count', COUNT(*),
      'ordenes', COALESCE(jsonb_agg(jsonb_build_object(
        'id', op.id,
        'numero', op.numero,
        'bodega', b.nombre,
        'asignado_a', op.asignado_a,
        'fecha_creacion', op.created_at,
        'items', (SELECT COUNT(*) FROM orden_picking_lineas WHERE orden_picking_id = op.id)
      ) ORDER BY op.created_at), '[]'::JSONB),
      'drill_down_url', '/inventario/picking?estado=PENDIENTE'
    )
    FROM ordenes_picking op
    JOIN bodegas b ON b.id = op.bodega_id
    WHERE op.empresa_id = p_empresa_id AND op.estado IN ('PENDIENTE', 'EN_PROCESO')
  );
END;
$$;

-- ============================================================
-- KPI: Stock negativo (anomalias)
-- ============================================================

CREATE OR REPLACE FUNCTION dashboard_inv_negative_stock(
  p_empresa_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER STABLE AS $$
BEGIN
  RETURN (
    SELECT jsonb_build_object(
      'count', COUNT(*),
      'productos', COALESCE(jsonb_agg(jsonb_build_object(
        'producto_id', ist.producto_id,
        'nombre', p.nombre,
        'bodega', b.nombre,
        'cantidad', ist.cantidad
      )), '[]'::JSONB)
    )
    FROM inventario_stock ist
    JOIN productos p ON p.id = ist.producto_id
    JOIN bodegas b ON b.id = ist.bodega_id
    WHERE ist.empresa_id = p_empresa_id AND ist.cantidad < 0
  );
END;
$$;

-- ============================================================
-- GRAFICO: Analisis ABC (Pareto)
-- ============================================================

CREATE OR REPLACE FUNCTION dashboard_inv_abc_chart(
  p_empresa_id UUID,
  p_meses INTEGER DEFAULT 12
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER STABLE AS $$
BEGIN
  RETURN (
    WITH abc AS (
      SELECT p.clasificacion_abc AS clase,
        COUNT(*) AS productos,
        ROUND(SUM(ist.cantidad * COALESCE(p.costo, 0)), 2) AS valor_stock
      FROM productos p
      JOIN inventario_stock ist ON ist.producto_id = p.id
      WHERE p.empresa_id = p_empresa_id
        AND p.clasificacion_abc IS NOT NULL
        AND ist.cantidad > 0
      GROUP BY p.clasificacion_abc
    )
    SELECT jsonb_build_object(
      'data', COALESCE(jsonb_agg(jsonb_build_object(
        'clase', clase,
        'productos', productos,
        'valor_stock', valor_stock
      ) ORDER BY clase), '[]'::JSONB),
      'total_valor', (SELECT SUM(valor_stock) FROM abc)
    )
    FROM abc
  );
END;
$$;

-- ============================================================
-- GRAFICO: Top 10 productos por valor en stock
-- ============================================================

CREATE OR REPLACE FUNCTION dashboard_inv_top_by_value(
  p_empresa_id UUID,
  p_limite INTEGER DEFAULT 10,
  p_bodega_id UUID DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER STABLE AS $$
BEGIN
  RETURN (
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'producto_id', sub.producto_id,
      'nombre', sub.nombre,
      'cantidad', sub.cantidad,
      'valor', sub.valor
    )), '[]'::JSONB)
    FROM (
      SELECT ist.producto_id, p.nombre,
        SUM(ist.cantidad) AS cantidad,
        ROUND(SUM(ist.cantidad * COALESCE(p.costo, 0)), 2) AS valor
      FROM inventario_stock ist
      JOIN productos p ON p.id = ist.producto_id
      WHERE ist.empresa_id = p_empresa_id
        AND ist.cantidad > 0
        AND (p_bodega_id IS NULL OR ist.bodega_id = p_bodega_id)
      GROUP BY ist.producto_id, p.nombre
      ORDER BY valor DESC
      LIMIT p_limite
    ) sub
  );
END;
$$;
```

## Triggers

```sql
-- No se requieren triggers nuevos para el dashboard.
-- Los datos se consultan en tiempo real via RPCs.
-- Supabase Realtime se suscribe a cambios en:
--   inventario_stock, transferencias_inventario, ordenes_picking, series_lotes
-- Flutter BrickDataProvider se suscribe automaticamente via subscribeToRealtime.
```

## Vistas

```sql
-- Vista materializada para performance del dashboard (se refresca cada 5 min via cron)
CREATE MATERIALIZED VIEW mv_dashboard_inventario AS
SELECT
  ist.empresa_id,
  COUNT(DISTINCT ist.producto_id) AS total_productos_con_stock,
  ROUND(SUM(ist.cantidad * COALESCE(p.costo, 0)), 2) AS valor_total,
  COUNT(*) FILTER (WHERE ist.cantidad < 0) AS productos_stock_negativo,
  COUNT(*) FILTER (WHERE ist.cantidad <= COALESCE(p.stock_minimo, 0) AND p.stock_minimo > 0) AS productos_bajo_minimo,
  COUNT(*) FILTER (WHERE ist.cantidad = 0) AS productos_sin_stock
FROM inventario_stock ist
JOIN productos p ON p.id = ist.producto_id
WHERE ist.cantidad != 0 OR p.stock_minimo > 0
GROUP BY ist.empresa_id;

CREATE UNIQUE INDEX idx_mv_dashboard_inv ON mv_dashboard_inventario(empresa_id);

-- Refrescar via cron: REFRESH MATERIALIZED VIEW CONCURRENTLY mv_dashboard_inventario;
```

## Integracion Module Service Bus

```sql
-- BUS: Dashboard summary (ya cubierto por module_bus.get_forecast_summary en 23.3.6)
-- Los RPCs del dashboard son llamados directamente desde Flutter,
-- no requieren pasar por el bus porque son del mismo modulo inventario.
```

## RLS Policies

```sql
-- Los RPCs son SECURITY DEFINER y filtran por empresa_id internamente.
-- La vista materializada no tiene RLS (se consulta via RPCs que filtran).
```

## Flujo UI/UX

```
PANTALLA: Inventario > Dashboard

[Layout responsive en grid]

Fila 1 (Cards KPI):
  [Valor Total: $XXX,XXX] [Bajo Minimo: N] [Agotados: N] [Stock Negativo: N]

Fila 2 (Cards operativas):
  [Transferencias en transito: N] [Picking pendiente: N] [Recepciones pendientes: N]

Fila 3 (Graficos - 2 columnas):
  Col 1: Grafico ABC (Pareto) - SfCartesianChart con barras + linea acumulada
  Col 2: Donut valoracion por bodega - SfCircularChart

Fila 4 (Listas):
  Col 1: Top 10 por valor (barras horizontales)
  Col 2: Lotes por vencer 30/60/90 dias (barras apiladas por color)

Fila 5 (Alertas):
  [SfDataGrid] Lista de alertas activas:
    Icono urgencia | Producto | Tipo alerta | Mensaje | Accion

[Filtros globales en header]:
  Bodega (dropdown) | Categoria (dropdown) | Periodo (date range)

[Auto-refresh]: Supabase Realtime suscrito a inventario_stock, ordenes_picking

[Responsive]
  COMPACT: Cards en columna + scroll vertical, graficos ocultos
  MEDIUM: 2 columnas de cards, 1 grafico visible
  EXPANDED: Layout completo 2-3 columnas
  LARGE: 4 columnas, todos los graficos visibles
```

---

