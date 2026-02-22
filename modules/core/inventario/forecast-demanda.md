# Pronóstico de Demanda (Forecasting)


## Descripcion Funcional

Sistema de pronostico de demanda que analiza datos historicos de ventas para predecir demanda futura, calcular stock de seguridad estadistico y generar alertas proactivas de desabastecimiento. Complementa el sistema de reabastecimiento automatico existente (tabla `reglas_reabastecimiento`) agregandole inteligencia predictiva.

**Metodos de pronostico implementados:**

1. **Media Movil Simple (SMA):** Promedio de los ultimos N periodos. Facil de entender, recomendado para productos con demanda estable.

2. **Suavizamiento Exponencial Simple (SES):** Pondera mas los datos recientes con factor alpha (0.1-0.9). Reacciona mas rapido a cambios de tendencia que SMA.

3. **Holt-Winters Basico (estacional):** Captura tendencia + estacionalidad. Usa tres parametros: alpha (nivel), beta (tendencia), gamma (estacionalidad). Ideal para productos con patron estacional predecible.

**Factores estacionales Ecuador:**

| Factor | Meses Pico | Impacto Tipico |
|--------|-----------|---------------|
| Navidad/Fin de Anio | Nov-Dic | +40-80% en retail |
| Dia de la Madre | May | +30-50% en regalos, electronica, ropa |
| Black Friday/Cyber Monday | Nov (4ta semana) | +20-40% general |
| Fiestas de Quito | Dic (1ra semana) | +15-25% local Quito |
| Carnaval | Feb-Mar (variable) | +10-20% alimentos, licores, turismo |
| Regreso a Clases Costa | Abr-May | +30% utiles, uniformes, mochilas |
| Regreso a Clases Sierra | Sep | +30% utiles, uniformes, mochilas |
| San Valentin | Feb | +20-30% en regalos |
| Dia del Padre | Jun (3er domingo) | +15-25% |

**Calculo de stock de seguridad estadistico:**

```
stock_seguridad = Z * sigma_d * sqrt(L) + Z * d_avg * sigma_L
```

Donde:
- Z = factor de servicio (1.28 para 90%, 1.65 para 95%, 2.33 para 99%)
- sigma_d = desviacion estandar de la demanda diaria
- L = lead time promedio en dias
- d_avg = demanda promedio diaria
- sigma_L = desviacion estandar del lead time

**Alertas proactivas:**

- "Producto X se agotara en Y dias al ritmo actual"
- "Producto X tiene demanda creciente (+Z% vs periodo anterior), considere aumentar pedido"
- "Producto X entra en temporada alta (factor estacional), stock insuficiente para cubrir pico"

## Modelo de Datos SQL

```sql
-- ============================================================
-- ENUMS para Forecasting
-- ============================================================

CREATE TYPE forecast_metodo AS ENUM ('SMA', 'SES', 'HOLT_WINTERS');
CREATE TYPE forecast_periodo AS ENUM ('DIARIO', 'SEMANAL', 'MENSUAL');

-- ============================================================
-- CONFIGURACION DE PRONOSTICO POR PRODUCTO
-- ============================================================

CREATE TABLE forecast_config (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  producto_id     UUID NOT NULL REFERENCES productos(id),
  bodega_id       UUID REFERENCES bodegas(id),            -- NULL = todas las bodegas
  metodo          forecast_metodo NOT NULL DEFAULT 'SES',
  periodo         forecast_periodo NOT NULL DEFAULT 'SEMANAL',
  -- Parametros SMA
  sma_periodos    INTEGER DEFAULT 12,                      -- Ultimos N periodos para media movil
  -- Parametros SES
  ses_alpha       DECIMAL(3,2) DEFAULT 0.3,                -- Factor suavizamiento (0.1-0.9)
  -- Parametros Holt-Winters
  hw_alpha        DECIMAL(3,2) DEFAULT 0.3,
  hw_beta         DECIMAL(3,2) DEFAULT 0.1,
  hw_gamma        DECIMAL(3,2) DEFAULT 0.3,
  hw_estaciones   INTEGER DEFAULT 12,                      -- Periodos por ciclo estacional (12 meses)
  -- Stock de seguridad
  nivel_servicio  DECIMAL(4,2) DEFAULT 95.00,              -- % nivel de servicio deseado (90, 95, 99)
  lead_time_dias  INTEGER DEFAULT 7,                       -- Dias promedio de reabastecimiento
  lead_time_desv  DECIMAL(8,2) DEFAULT 2,                  -- Desviacion estandar del lead time
  -- Alertas
  alerta_dias_stock INTEGER DEFAULT 14,                    -- Alertar si stock cubre menos de N dias
  activo          BOOLEAN DEFAULT true,
  version         INTEGER DEFAULT 1,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(empresa_id, producto_id, COALESCE(bodega_id, '00000000-0000-0000-0000-000000000000'))
);

ALTER TABLE forecast_config ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON forecast_config
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- ============================================================
-- FACTORES ESTACIONALES (configurables por empresa)
-- ============================================================

CREATE TABLE forecast_factores_estacionales (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  nombre          VARCHAR(50) NOT NULL,                    -- 'Navidad', 'Dia de la Madre'
  mes_inicio      INTEGER NOT NULL CHECK (mes_inicio BETWEEN 1 AND 12),
  mes_fin         INTEGER NOT NULL CHECK (mes_fin BETWEEN 1 AND 12),
  semana_inicio   INTEGER,                                 -- Semana del mes (1-5, NULL=mes completo)
  semana_fin      INTEGER,
  factor_ajuste   DECIMAL(5,2) NOT NULL DEFAULT 1.00,      -- 1.40 = +40%, 0.80 = -20%
  -- Aplica a:
  categoria_id    UUID REFERENCES categorias(id),          -- NULL = todos los productos
  activo          BOOLEAN DEFAULT true
);

ALTER TABLE forecast_factores_estacionales ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON forecast_factores_estacionales
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- ============================================================
-- RESULTADOS DE PRONOSTICO (cache, se recalcula periodicamente)
-- ============================================================

CREATE TABLE forecast_resultados (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  producto_id     UUID NOT NULL REFERENCES productos(id),
  bodega_id       UUID REFERENCES bodegas(id),
  fecha_calculo   TIMESTAMPTZ DEFAULT NOW(),
  metodo_usado    forecast_metodo NOT NULL,
  -- Resultados
  demanda_promedio_diaria DECIMAL(18,6) NOT NULL,
  desviacion_demanda      DECIMAL(18,6) NOT NULL,
  stock_seguridad         DECIMAL(18,6) NOT NULL,
  punto_reorden           DECIMAL(18,6) NOT NULL,          -- stock_seguridad + demanda * lead_time
  -- Pronostico por periodo
  forecast_periodos JSONB NOT NULL DEFAULT '[]',            -- [{periodo, demanda_pronosticada, limite_inferior, limite_superior}]
  -- Dias de stock
  stock_actual            DECIMAL(18,6),
  dias_stock_estimado     DECIMAL(8,2),                    -- stock_actual / demanda_promedio_diaria
  -- Tendencia
  tendencia_pct           DECIMAL(8,2),                    -- % cambio vs periodo anterior
  es_creciente            BOOLEAN,
  -- Factor estacional actual
  factor_estacional       DECIMAL(5,2) DEFAULT 1.00,
  -- Metadata
  datos_historicos_meses  INTEGER,                          -- Cuantos meses de data se usaron
  error_mape              DECIMAL(8,2),                    -- Mean Absolute Percentage Error
  UNIQUE(empresa_id, producto_id, COALESCE(bodega_id, '00000000-0000-0000-0000-000000000000'))
);

ALTER TABLE forecast_resultados ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON forecast_resultados
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE INDEX idx_forecast_alertas
  ON forecast_resultados(empresa_id, dias_stock_estimado)
  WHERE dias_stock_estimado IS NOT NULL;

-- ============================================================
-- SUGERENCIAS DE COMPRA BASADAS EN FORECAST
-- ============================================================

CREATE TABLE forecast_sugerencias_compra (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  producto_id     UUID NOT NULL REFERENCES productos(id),
  bodega_id       UUID REFERENCES bodegas(id),
  proveedor_id    UUID REFERENCES contactos(id),
  cantidad_sugerida DECIMAL(18,6) NOT NULL,
  motivo          VARCHAR(50) NOT NULL,                    -- 'BAJO_MINIMO', 'FORECAST_PICO', 'STOCK_SEGURIDAD'
  urgencia        VARCHAR(10) NOT NULL DEFAULT 'MEDIA',    -- 'ALTA', 'MEDIA', 'BAJA'
  estado          VARCHAR(20) DEFAULT 'PENDIENTE',         -- 'PENDIENTE', 'APROBADA', 'CONVERTIDA_OC', 'DESCARTADA'
  orden_compra_id UUID,                                    -- FK si se convirtio en OC
  fecha_sugerencia TIMESTAMPTZ DEFAULT NOW(),
  fecha_necesidad DATE,                                    -- Cuando se necesita (lead time)
  version         INTEGER DEFAULT 1,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE forecast_sugerencias_compra ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON forecast_sugerencias_compra
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));
```

## Funciones PostgreSQL

```sql
-- ============================================================
-- CALCULAR DEMANDA HISTORICA POR PERIODOS
-- ============================================================

CREATE OR REPLACE FUNCTION forecast_get_demand_history(
  p_empresa_id UUID,
  p_producto_id UUID,
  p_bodega_id UUID DEFAULT NULL,
  p_periodo forecast_periodo DEFAULT 'SEMANAL',
  p_meses_historia INTEGER DEFAULT 24
) RETURNS TABLE(
  periodo_inicio DATE,
  periodo_fin DATE,
  cantidad_vendida DECIMAL(18,6)
)
LANGUAGE plpgsql SECURITY DEFINER STABLE AS $$
BEGIN
  RETURN QUERY
  SELECT
    DATE_TRUNC(
      CASE p_periodo
        WHEN 'DIARIO' THEN 'day'
        WHEN 'SEMANAL' THEN 'week'
        WHEN 'MENSUAL' THEN 'month'
      END, k.fecha
    )::DATE AS periodo_inicio,
    (DATE_TRUNC(
      CASE p_periodo
        WHEN 'DIARIO' THEN 'day'
        WHEN 'SEMANAL' THEN 'week'
        WHEN 'MENSUAL' THEN 'month'
      END, k.fecha
    ) + CASE p_periodo
        WHEN 'DIARIO' THEN '1 day'::INTERVAL
        WHEN 'SEMANAL' THEN '1 week'::INTERVAL
        WHEN 'MENSUAL' THEN '1 month'::INTERVAL
      END - '1 day'::INTERVAL)::DATE AS periodo_fin,
    COALESCE(SUM(ABS(k.cantidad)), 0) AS cantidad_vendida
  FROM kardex k
  WHERE k.empresa_id = p_empresa_id
    AND k.producto_id = p_producto_id
    AND k.tipo_movimiento = 'EGRESO'
    AND k.fecha >= NOW() - (p_meses_historia || ' months')::INTERVAL
    AND (p_bodega_id IS NULL OR k.bodega_id = p_bodega_id)
  GROUP BY periodo_inicio, periodo_fin
  ORDER BY periodo_inicio;
END;
$$;

-- ============================================================
-- CALCULAR STOCK DE SEGURIDAD ESTADISTICO
-- ============================================================

CREATE OR REPLACE FUNCTION forecast_calculate_safety_stock(
  p_empresa_id UUID,
  p_producto_id UUID,
  p_bodega_id UUID DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_config RECORD;
  v_demanda_avg DECIMAL(18,6);
  v_demanda_stddev DECIMAL(18,6);
  v_z_factor DECIMAL(4,2);
  v_safety_stock DECIMAL(18,6);
  v_reorder_point DECIMAL(18,6);
  v_stock_actual DECIMAL(18,6);
  v_dias_stock DECIMAL(8,2);
BEGIN
  -- Obtener configuracion
  SELECT * INTO v_config FROM forecast_config
  WHERE empresa_id = p_empresa_id AND producto_id = p_producto_id
    AND (bodega_id = p_bodega_id OR (bodega_id IS NULL AND p_bodega_id IS NULL))
    AND activo = true
  LIMIT 1;

  IF v_config IS NULL THEN
    -- Usar defaults si no hay config
    v_config.nivel_servicio := 95.00;
    v_config.lead_time_dias := 7;
    v_config.lead_time_desv := 2;
  END IF;

  -- Factor Z segun nivel de servicio
  v_z_factor := CASE
    WHEN v_config.nivel_servicio >= 99 THEN 2.33
    WHEN v_config.nivel_servicio >= 97.5 THEN 1.96
    WHEN v_config.nivel_servicio >= 95 THEN 1.65
    WHEN v_config.nivel_servicio >= 90 THEN 1.28
    WHEN v_config.nivel_servicio >= 85 THEN 1.04
    ELSE 0.84
  END;

  -- Calcular demanda diaria promedio y desviacion (ultimos 6 meses)
  SELECT
    COALESCE(AVG(daily_qty), 0),
    COALESCE(STDDEV(daily_qty), 0)
  INTO v_demanda_avg, v_demanda_stddev
  FROM (
    SELECT DATE(k.fecha) AS dia, SUM(ABS(k.cantidad)) AS daily_qty
    FROM kardex k
    WHERE k.empresa_id = p_empresa_id
      AND k.producto_id = p_producto_id
      AND k.tipo_movimiento = 'EGRESO'
      AND k.fecha >= NOW() - INTERVAL '6 months'
      AND (p_bodega_id IS NULL OR k.bodega_id = p_bodega_id)
    GROUP BY DATE(k.fecha)
  ) daily_demand;

  -- Formula: SS = Z * sigma_d * sqrt(L) + Z * d_avg * sigma_L
  v_safety_stock := v_z_factor * v_demanda_stddev * SQRT(v_config.lead_time_dias)
    + v_z_factor * v_demanda_avg * v_config.lead_time_desv;

  -- Punto de reorden = SS + demanda durante lead time
  v_reorder_point := v_safety_stock + (v_demanda_avg * v_config.lead_time_dias);

  -- Stock actual
  SELECT COALESCE(SUM(cantidad), 0) INTO v_stock_actual
  FROM inventario_stock
  WHERE empresa_id = p_empresa_id AND producto_id = p_producto_id
    AND (p_bodega_id IS NULL OR bodega_id = p_bodega_id);

  -- Dias de stock
  v_dias_stock := CASE WHEN v_demanda_avg > 0
    THEN ROUND(v_stock_actual / v_demanda_avg, 2)
    ELSE NULL
  END;

  -- Guardar resultado
  INSERT INTO forecast_resultados (
    empresa_id, producto_id, bodega_id, metodo_usado,
    demanda_promedio_diaria, desviacion_demanda, stock_seguridad,
    punto_reorden, stock_actual, dias_stock_estimado
  ) VALUES (
    p_empresa_id, p_producto_id, p_bodega_id, 'SES',
    v_demanda_avg, v_demanda_stddev, ROUND(v_safety_stock, 2),
    ROUND(v_reorder_point, 2), v_stock_actual, v_dias_stock
  )
  ON CONFLICT (empresa_id, producto_id, COALESCE(bodega_id, '00000000-0000-0000-0000-000000000000'))
  DO UPDATE SET
    demanda_promedio_diaria = EXCLUDED.demanda_promedio_diaria,
    desviacion_demanda = EXCLUDED.desviacion_demanda,
    stock_seguridad = EXCLUDED.stock_seguridad,
    punto_reorden = EXCLUDED.punto_reorden,
    stock_actual = EXCLUDED.stock_actual,
    dias_stock_estimado = EXCLUDED.dias_stock_estimado,
    fecha_calculo = NOW();

  -- Actualizar campo en productos tambien
  UPDATE productos SET
    stock_seguridad = ROUND(v_safety_stock, 2),
    demanda_promedio_diaria = v_demanda_avg,
    lead_time_dias = v_config.lead_time_dias
  WHERE id = p_producto_id;

  RETURN jsonb_build_object(
    'producto_id', p_producto_id,
    'demanda_promedio_diaria', ROUND(v_demanda_avg, 4),
    'desviacion_demanda', ROUND(v_demanda_stddev, 4),
    'nivel_servicio', v_config.nivel_servicio,
    'z_factor', v_z_factor,
    'lead_time_dias', v_config.lead_time_dias,
    'stock_seguridad', ROUND(v_safety_stock, 2),
    'punto_reorden', ROUND(v_reorder_point, 2),
    'stock_actual', v_stock_actual,
    'dias_stock', v_dias_stock
  );
END;
$$;

-- ============================================================
-- GENERAR ALERTAS PROACTIVAS DE DESABASTECIMIENTO
-- ============================================================

CREATE OR REPLACE FUNCTION forecast_generate_alerts(
  p_empresa_id UUID,
  p_dias_umbral INTEGER DEFAULT 14
) RETURNS TABLE(
  producto_id UUID,
  nombre_producto VARCHAR,
  stock_actual DECIMAL(18,6),
  demanda_diaria DECIMAL(18,6),
  dias_stock DECIMAL(8,2),
  punto_reorden DECIMAL(18,6),
  urgencia VARCHAR(10),
  mensaje TEXT
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN QUERY
  SELECT
    fr.producto_id,
    p.nombre AS nombre_producto,
    fr.stock_actual,
    fr.demanda_promedio_diaria AS demanda_diaria,
    fr.dias_stock_estimado AS dias_stock,
    fr.punto_reorden,
    CASE
      WHEN fr.dias_stock_estimado <= 3 THEN 'CRITICA'
      WHEN fr.dias_stock_estimado <= 7 THEN 'ALTA'
      WHEN fr.dias_stock_estimado <= p_dias_umbral THEN 'MEDIA'
      ELSE 'BAJA'
    END AS urgencia,
    CASE
      WHEN fr.dias_stock_estimado <= 0 THEN
        'AGOTADO: ' || p.nombre || ' sin stock'
      WHEN fr.dias_stock_estimado <= 3 THEN
        'CRITICO: ' || p.nombre || ' se agota en ' || ROUND(fr.dias_stock_estimado,0) || ' dias'
      WHEN fr.dias_stock_estimado <= 7 THEN
        'URGENTE: ' || p.nombre || ' stock para ' || ROUND(fr.dias_stock_estimado,0) || ' dias'
      ELSE
        'ATENCION: ' || p.nombre || ' stock bajo (' || ROUND(fr.dias_stock_estimado,0) || ' dias)'
    END AS mensaje
  FROM forecast_resultados fr
  JOIN productos p ON p.id = fr.producto_id
  WHERE fr.empresa_id = p_empresa_id
    AND fr.demanda_promedio_diaria > 0
    AND (fr.dias_stock_estimado IS NULL OR fr.dias_stock_estimado <= p_dias_umbral)
  ORDER BY COALESCE(fr.dias_stock_estimado, 0);
END;
$$;

-- ============================================================
-- GENERAR SUGERENCIAS DE COMPRA
-- ============================================================

CREATE OR REPLACE FUNCTION forecast_suggest_purchases(
  p_empresa_id UUID
) RETURNS INTEGER  -- Numero de sugerencias generadas
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_count INTEGER := 0;
  v_rec RECORD;
  v_cantidad_sugerida DECIMAL(18,6);
  v_proveedor_id UUID;
  v_factor_estacional DECIMAL(5,2);
BEGIN
  FOR v_rec IN
    SELECT
      fr.producto_id, fr.bodega_id, fr.stock_actual,
      fr.demanda_promedio_diaria, fr.punto_reorden, fr.stock_seguridad,
      fr.dias_stock_estimado, fr.factor_estacional,
      rr.stock_maximo, rr.multiplo, rr.proveedor_id AS regla_proveedor_id
    FROM forecast_resultados fr
    LEFT JOIN reglas_reabastecimiento rr
      ON rr.producto_id = fr.producto_id AND rr.empresa_id = fr.empresa_id
         AND (rr.bodega_id = fr.bodega_id OR fr.bodega_id IS NULL)
    WHERE fr.empresa_id = p_empresa_id
      AND fr.demanda_promedio_diaria > 0
      AND fr.stock_actual < fr.punto_reorden
  LOOP
    -- Buscar proveedor preferido
    v_proveedor_id := v_rec.regla_proveedor_id;
    IF v_proveedor_id IS NULL THEN
      SELECT contacto_id INTO v_proveedor_id
      FROM producto_proveedores
      WHERE producto_id = v_rec.producto_id AND es_preferido = true
      LIMIT 1;
    END IF;

    -- Obtener factor estacional actual
    v_factor_estacional := COALESCE(v_rec.factor_estacional, 1.00);

    -- Cantidad sugerida: hasta stock maximo, ajustado por estacionalidad
    v_cantidad_sugerida := GREATEST(
      COALESCE(v_rec.stock_maximo, v_rec.punto_reorden * 2) * v_factor_estacional
        - v_rec.stock_actual,
      0
    );

    -- Ajustar a multiplo de compra
    IF COALESCE(v_rec.multiplo, 1) > 1 THEN
      v_cantidad_sugerida := CEIL(v_cantidad_sugerida / v_rec.multiplo) * v_rec.multiplo;
    END IF;

    IF v_cantidad_sugerida > 0 THEN
      INSERT INTO forecast_sugerencias_compra (
        empresa_id, producto_id, bodega_id, proveedor_id,
        cantidad_sugerida, motivo, urgencia, fecha_necesidad
      ) VALUES (
        p_empresa_id, v_rec.producto_id, v_rec.bodega_id, v_proveedor_id,
        v_cantidad_sugerida,
        CASE
          WHEN v_rec.stock_actual <= 0 THEN 'AGOTADO'
          WHEN COALESCE(v_rec.dias_stock_estimado, 0) <= 3 THEN 'BAJO_MINIMO'
          ELSE 'FORECAST_PICO'
        END,
        CASE
          WHEN COALESCE(v_rec.dias_stock_estimado, 0) <= 3 THEN 'ALTA'
          WHEN COALESCE(v_rec.dias_stock_estimado, 0) <= 7 THEN 'MEDIA'
          ELSE 'BAJA'
        END,
        CURRENT_DATE + COALESCE(v_rec.dias_stock_estimado, 0)::INTEGER
      )
      ON CONFLICT DO NOTHING;

      v_count := v_count + 1;
    END IF;
  END LOOP;

  RETURN v_count;
END;
$$;
```

## Triggers

```sql
-- Trigger: recalcular forecast cuando hay movimiento significativo de stock
-- (Se ejecuta via cron, no en cada movimiento para evitar overhead)
-- Cron recomendado: cada noche a las 2:00 AM

-- Para el cron, agregar en tareas_programadas:
-- ('Recalcular forecasts', 'RPC', 'forecast_recalculate_all', '0 2 * * *')

CREATE OR REPLACE FUNCTION forecast_recalculate_all(
  p_empresa_id UUID DEFAULT NULL
) RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_count INTEGER := 0;
  v_empresa RECORD;
  v_config RECORD;
BEGIN
  FOR v_empresa IN
    SELECT DISTINCT empresa_id FROM forecast_config WHERE activo = true
      AND (p_empresa_id IS NULL OR empresa_id = p_empresa_id)
  LOOP
    FOR v_config IN
      SELECT * FROM forecast_config
      WHERE empresa_id = v_empresa.empresa_id AND activo = true
    LOOP
      PERFORM forecast_calculate_safety_stock(
        v_empresa.empresa_id, v_config.producto_id, v_config.bodega_id
      );
      v_count := v_count + 1;
    END LOOP;

    -- Generar sugerencias de compra
    PERFORM forecast_suggest_purchases(v_empresa.empresa_id);
  END LOOP;

  RETURN v_count;
END;
$$;
```

## Vistas

```sql
-- Vista: Productos en riesgo de desabastecimiento
CREATE OR REPLACE VIEW v_forecast_riesgo_desabasto AS
SELECT
  fr.empresa_id,
  fr.producto_id,
  p.nombre AS producto_nombre,
  p.sku,
  p.clasificacion_abc,
  fr.stock_actual,
  fr.demanda_promedio_diaria,
  fr.dias_stock_estimado,
  fr.punto_reorden,
  fr.stock_seguridad,
  fr.tendencia_pct,
  fr.factor_estacional,
  CASE
    WHEN fr.dias_stock_estimado IS NULL OR fr.dias_stock_estimado <= 0 THEN 'AGOTADO'
    WHEN fr.dias_stock_estimado <= 3 THEN 'CRITICO'
    WHEN fr.dias_stock_estimado <= 7 THEN 'URGENTE'
    WHEN fr.dias_stock_estimado <= 14 THEN 'ATENCION'
    ELSE 'OK'
  END AS nivel_riesgo
FROM forecast_resultados fr
JOIN productos p ON p.id = fr.producto_id
WHERE fr.demanda_promedio_diaria > 0;

-- Vista: Sugerencias de compra pendientes agrupadas por proveedor
CREATE OR REPLACE VIEW v_forecast_compras_sugeridas AS
SELECT
  fsc.empresa_id,
  fsc.proveedor_id,
  c.nombre AS proveedor_nombre,
  COUNT(*) AS productos_a_comprar,
  SUM(fsc.cantidad_sugerida) AS total_unidades,
  MIN(fsc.fecha_necesidad) AS fecha_mas_urgente,
  MAX(fsc.urgencia) AS urgencia_maxima
FROM forecast_sugerencias_compra fsc
LEFT JOIN contactos c ON c.id = fsc.proveedor_id
WHERE fsc.estado = 'PENDIENTE'
GROUP BY fsc.empresa_id, fsc.proveedor_id, c.nombre
ORDER BY urgencia_maxima DESC, fecha_mas_urgente;
```

## Integracion Module Service Bus

```sql
-- BUS: Obtener dias de stock estimados (desde Dashboard u otros modulos)
CREATE OR REPLACE FUNCTION module_bus.get_forecast_summary(
  p_empresa_id UUID
) RETURNS module_bus.bus_response
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_result module_bus.bus_response;
  v_summary JSONB;
BEGIN
  IF NOT module_bus.is_module_active(p_empresa_id, 'inventario') THEN
    v_result := (false, 'module_inactive', 'inventario', null);
    RETURN v_result;
  END IF;

  SELECT jsonb_build_object(
    'productos_agotados', COUNT(*) FILTER (WHERE dias_stock_estimado <= 0),
    'productos_criticos', COUNT(*) FILTER (WHERE dias_stock_estimado > 0 AND dias_stock_estimado <= 3),
    'productos_urgentes', COUNT(*) FILTER (WHERE dias_stock_estimado > 3 AND dias_stock_estimado <= 7),
    'productos_atencion', COUNT(*) FILTER (WHERE dias_stock_estimado > 7 AND dias_stock_estimado <= 14),
    'sugerencias_compra_pendientes', (
      SELECT COUNT(*) FROM forecast_sugerencias_compra
      WHERE empresa_id = p_empresa_id AND estado = 'PENDIENTE'
    )
  ) INTO v_summary
  FROM forecast_resultados
  WHERE empresa_id = p_empresa_id AND demanda_promedio_diaria > 0;

  v_result := (true, null, 'inventario', v_summary);
  RETURN v_result;
END;
$$;
```

## RLS Policies

```sql
-- Ya definidas inline en la creacion de tablas (ver 23.3.2)
```

## Flujo UI/UX

```
PANTALLA: Inventario > Forecasting > Panel de Pronostico

[Dashboard Forecast]
  Cards superiores:
    [Agotados: N] [Criticos: N] [Urgentes: N] [Atencion: N] [OK: N]
  Grafico central (SfCartesianChart):
    Eje X: tiempo (ultimos 12 meses + 3 meses pronosticados)
    Eje Y: cantidad
    Serie 1: Demanda real (linea solida azul)
    Serie 2: Pronostico (linea punteada verde)
    Serie 3: Limites confianza (area sombreada)
    Selector de producto (dropdown con buscador)
  Lista de alertas (SfDataGrid):
    Producto | Stock | Demanda/dia | Dias stock | Urgencia | Accion sugerida

---

PANTALLA: Inventario > Forecasting > Sugerencias de Compra

[Lista por proveedor] (SfDataGrid agrupado)
  Proveedor | Productos | Unidades totales | Urgencia | [Convertir a OC]
  Expandir: detalle de productos con cantidad sugerida
  Boton: "Generar OC para seleccionados" -> crea borrador OC

---

PANTALLA: Inventario > Forecasting > Configuracion

[Lista productos con config] (SfDataGrid)
  Producto | Metodo | Periodo | Alpha | Nivel Servicio | Lead Time | Alerta dias
  Acciones: Editar config, Recalcular ahora, Copiar config a multiples productos

---

PANTALLA: Inventario > Forecasting > Factores Estacionales

[Lista factores] (SfDataGrid editable)
  Nombre | Mes inicio | Mes fin | Factor (%) | Categoria | Activo
  Preset: "Cargar factores Ecuador" (llena con tabla de factores EC)

[Responsive]
  COMPACT: Cards de alerta + lista simple
  MEDIUM: Grafico + lista side-by-side
  EXPANDED/LARGE: Dashboard completo con graficos interactivos
```

---

