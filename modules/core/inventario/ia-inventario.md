# IA para Inventario - Optimización


## Descripcion Funcional

El subsistema de IA para Inventario proporciona cuatro capacidades:

1. **Reabastecimiento inteligente:** Calculo de punto de reorden optimo basado en variabilidad de demanda, lead time del proveedor, nivel de servicio deseado y estacionalidad Ecuador. Formula: `ROP = d * LT + SS` donde `SS = Z * sigma_d * sqrt(LT)`.

2. **Deteccion de anomalias de stock:** Identificacion automatica de merma inusual (consumo sin documentos), sobre-stock cronico (sin rotacion >90 dias), stock negativo (error de proceso) y discrepancias entre stock fisico y teorico.

3. **Clasificacion ABC dinamica:** Recalculo periodico (mensual) basado en datos reales de rotacion y valor. Integracion con frecuencia de conteo por clase y con dashboard de inventario.

4. **Analisis what-if:** Simulacion de impacto de cambios en parametros de inventario (minimos, maximos, cambio de proveedor con diferente lead time) sobre capital de trabajo y riesgo de desabastecimiento.

## Modelo de Datos - Inventario IA

```sql
-- ============================================================
-- VISTA MATERIALIZADA: Demanda diaria por producto (base para forecast inventario)
-- ============================================================

CREATE MATERIALIZED VIEW mv_demanda_producto AS
SELECT
  f.empresa_id,
  fl.producto_id,
  p.nombre AS producto_nombre,
  p.categoria_id,
  p.stock_minimo,
  p.stock_maximo,
  p.lead_time_dias,
  DATE(f.fecha_emision AT TIME ZONE 'America/Guayaquil') AS fecha,
  EXTRACT(MONTH FROM f.fecha_emision) AS mes,
  EXTRACT(DOW FROM f.fecha_emision) AS dia_semana,
  SUM(fl.cantidad) AS cantidad_demandada,
  -- Demanda en unidad base (considerando multi-empaque)
  SUM(fl.cantidad * COALESCE(pp.factor_conversion, 1)) AS cantidad_unidad_base
FROM facturas f
JOIN factura_lineas fl ON fl.factura_id = f.id
JOIN productos p ON p.id = fl.producto_id
LEFT JOIN producto_presentaciones pp ON pp.id = fl.presentacion_id
WHERE f.estado IN ('AUTORIZADA', 'PAGADA')
  AND f.tipo_documento = '01'
GROUP BY f.empresa_id, fl.producto_id, p.nombre, p.categoria_id,
         p.stock_minimo, p.stock_maximo, p.lead_time_dias,
         DATE(f.fecha_emision AT TIME ZONE 'America/Guayaquil'),
         EXTRACT(MONTH FROM f.fecha_emision),
         EXTRACT(DOW FROM f.fecha_emision)
WITH DATA;

CREATE UNIQUE INDEX idx_mv_demanda_producto_pk
  ON mv_demanda_producto(empresa_id, producto_id, fecha);

-- ============================================================
-- VISTA MATERIALIZADA: Clasificacion ABC
-- ============================================================

CREATE MATERIALIZED VIEW mv_abc_classification AS
WITH producto_stats AS (
  SELECT
    empresa_id,
    producto_id,
    producto_nombre,
    categoria_id,
    SUM(cantidad_demandada) AS total_cantidad,
    SUM(cantidad_demandada * (
      SELECT COALESCE(p2.precio_venta, 0) FROM productos p2 WHERE p2.id = dp.producto_id
    )) AS total_valor_rotacion,
    COUNT(DISTINCT fecha) AS dias_con_venta,
    AVG(cantidad_demandada) AS demanda_promedio_diaria,
    STDDEV(cantidad_demandada) AS desviacion_demanda
  FROM mv_demanda_producto dp
  WHERE fecha >= CURRENT_DATE - INTERVAL '90 days'
  GROUP BY empresa_id, producto_id, producto_nombre, categoria_id
),
ranking AS (
  SELECT
    *,
    SUM(total_valor_rotacion) OVER (PARTITION BY empresa_id) AS valor_total_empresa,
    SUM(total_valor_rotacion) OVER (
      PARTITION BY empresa_id ORDER BY total_valor_rotacion DESC
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS valor_acumulado
  FROM producto_stats
)
SELECT
  r.*,
  CASE
    WHEN valor_acumulado <= valor_total_empresa * 0.80 THEN 'A'
    WHEN valor_acumulado <= valor_total_empresa * 0.95 THEN 'B'
    ELSE 'C'
  END AS clase_abc,
  ROUND(valor_acumulado / NULLIF(valor_total_empresa, 0) * 100, 2) AS pct_acumulado,
  CASE
    WHEN valor_acumulado <= valor_total_empresa * 0.80 THEN 'SEMANAL'
    WHEN valor_acumulado <= valor_total_empresa * 0.95 THEN 'MENSUAL'
    ELSE 'TRIMESTRAL'
  END AS frecuencia_conteo_sugerida
FROM ranking r
WITH DATA;

CREATE UNIQUE INDEX idx_mv_abc_pk
  ON mv_abc_classification(empresa_id, producto_id);

-- ============================================================
-- TABLA: Configuracion de reabastecimiento IA por producto
-- ============================================================

CREATE TABLE ia_reabastecimiento_config (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  producto_id     UUID NOT NULL REFERENCES productos(id),
  nivel_servicio  DECIMAL(5,4) NOT NULL DEFAULT 0.9500,
    -- 0.90 = 90%, 0.95 = 95%, 0.99 = 99%
    -- Determina Z-score: 0.90=1.28, 0.95=1.65, 0.99=2.33
  lead_time_proveedor_dias INTEGER,
    -- Override al lead_time del producto (si proveedor especifico)
  proveedor_preferido_id UUID REFERENCES contactos(id),
  metodo_forecast VARCHAR(20) DEFAULT 'MEDIA_MOVIL',
    -- MEDIA_MOVIL, MEDIA_PONDERADA, HOLT_WINTERS
  dias_media_movil INTEGER DEFAULT 30,
  auto_crear_oc BOOLEAN DEFAULT false,
    -- Si true, crea OC automatica al alcanzar punto de reorden
  activo BOOLEAN DEFAULT true,
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(empresa_id, producto_id)
);

ALTER TABLE ia_reabastecimiento_config ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON ia_reabastecimiento_config
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT (auth.jwt() -> 'app_metadata' ->> 'empresa_id')::uuid));

-- ============================================================
-- TABLA: Anomalias de stock detectadas
-- ============================================================

CREATE TABLE ia_anomalias_stock (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  producto_id     UUID NOT NULL REFERENCES productos(id),
  bodega_id       UUID REFERENCES bodegas(id),
  tipo_anomalia   VARCHAR(30) NOT NULL,
    -- MERMA_INUSUAL, SOBRESTOCK, STOCK_NEGATIVO, DISCREPANCIA_FISICO,
    -- SIN_ROTACION, CONSUMO_SIN_DOCUMENTO, LEAD_TIME_EXCEDIDO
  severidad       VARCHAR(5) NOT NULL CHECK (severidad IN ('BAJA','MEDIA','ALTA')),
  descripcion     TEXT NOT NULL,
  datos           JSONB DEFAULT '{}',
    -- {stock_actual, stock_esperado, diferencia, dias_sin_movimiento, etc.}
  estado          VARCHAR(15) DEFAULT 'PENDIENTE',
    -- PENDIENTE, INVESTIGADA, RESUELTA, DESCARTADA
  investigado_por UUID REFERENCES auth.users(id),
  resolucion      TEXT,
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_ia_anomalias_stock_empresa
  ON ia_anomalias_stock(empresa_id, estado, created_at DESC);

ALTER TABLE ia_anomalias_stock ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON ia_anomalias_stock
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT (auth.jwt() -> 'app_metadata' ->> 'empresa_id')::uuid));
```

## Funciones PostgreSQL - Inventario IA

```sql
-- ============================================================
-- FN_REABASTECIMIENTO_INTELIGENTE: Calculo de punto de reorden + stock seguridad
-- ============================================================

CREATE OR REPLACE FUNCTION fn_reabastecimiento_inteligente(
  p_empresa_id UUID,
  p_producto_id UUID DEFAULT NULL  -- NULL = todos los productos activos
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_resultado JSONB := '[]'::JSONB;
  v_prod RECORD;
  v_demanda_promedio DECIMAL(18,6);
  v_desviacion_demanda DECIMAL(18,6);
  v_lead_time INTEGER;
  v_z_score DECIMAL(5,2);
  v_stock_seguridad DECIMAL(18,6);
  v_punto_reorden DECIMAL(18,6);
  v_cantidad_sugerida DECIMAL(18,6);
  v_stock_actual DECIMAL(18,6);
  v_factor_est DECIMAL(5,2);
  v_dias_cobertura DECIMAL(10,2);
  v_fecha_desabastecimiento DATE;
BEGIN
  FOR v_prod IN
    SELECT
      p.id AS producto_id,
      p.nombre,
      p.stock_minimo,
      p.stock_maximo,
      p.lead_time_dias,
      p.categoria_id,
      cp.nombre AS categoria_nombre,
      COALESCE(rc.nivel_servicio, 0.95) AS nivel_servicio,
      COALESCE(rc.lead_time_proveedor_dias, p.lead_time_dias, 7) AS lead_time_efectivo,
      COALESCE(rc.metodo_forecast, 'MEDIA_MOVIL') AS metodo,
      COALESCE(rc.dias_media_movil, 30) AS dias_media,
      rc.auto_crear_oc,
      rc.proveedor_preferido_id,
      -- Stock actual total del producto
      COALESCE((
        SELECT SUM(sm.cantidad)
        FROM stock_movimientos sm
        WHERE sm.producto_id = p.id AND sm.empresa_id = p_empresa_id
      ), 0) AS stock_actual,
      -- Stock en transito (OC confirmadas no recibidas)
      COALESCE((
        SELECT SUM(ocl.cantidad - COALESCE(ocl.cantidad_recibida, 0))
        FROM orden_compra_lineas ocl
        JOIN ordenes_compra oc ON oc.id = ocl.orden_compra_id
        WHERE ocl.producto_id = p.id AND oc.empresa_id = p_empresa_id
          AND oc.estado IN ('CONFIRMADA', 'PARCIAL')
      ), 0) AS stock_en_transito
    FROM productos p
    LEFT JOIN categorias_producto cp ON cp.id = p.categoria_id
    LEFT JOIN ia_reabastecimiento_config rc
      ON rc.producto_id = p.id AND rc.empresa_id = p_empresa_id
    WHERE p.empresa_id = p_empresa_id
      AND p.activo = true
      AND p.tipo IN ('PRODUCTO', 'ENSAMBLAJE')
      AND (p_producto_id IS NULL OR p.id = p_producto_id)
      AND (rc.activo IS NULL OR rc.activo = true)
  LOOP
    -- 1. Calcular demanda promedio diaria y desviacion
    SELECT
      COALESCE(AVG(cantidad_unidad_base), 0),
      COALESCE(STDDEV(cantidad_unidad_base), 0)
    INTO v_demanda_promedio, v_desviacion_demanda
    FROM mv_demanda_producto
    WHERE empresa_id = p_empresa_id
      AND producto_id = v_prod.producto_id
      AND fecha >= CURRENT_DATE - (v_prod.dias_media || ' days')::INTERVAL;

    -- Si no hay demanda, skip
    IF v_demanda_promedio = 0 THEN
      CONTINUE;
    END IF;

    v_lead_time := v_prod.lead_time_efectivo;

    -- 2. Z-score segun nivel de servicio
    v_z_score := CASE
      WHEN v_prod.nivel_servicio >= 0.99 THEN 2.33
      WHEN v_prod.nivel_servicio >= 0.98 THEN 2.05
      WHEN v_prod.nivel_servicio >= 0.95 THEN 1.65
      WHEN v_prod.nivel_servicio >= 0.90 THEN 1.28
      WHEN v_prod.nivel_servicio >= 0.85 THEN 1.04
      ELSE 0.84
    END;

    -- 3. Stock de seguridad: SS = Z * sigma_d * sqrt(LT)
    v_stock_seguridad := v_z_score * v_desviacion_demanda * SQRT(v_lead_time);

    -- 4. Aplicar factor estacional del proximo mes
    v_factor_est := fn_factor_estacional(
      p_empresa_id,
      CURRENT_DATE + (v_lead_time || ' days')::INTERVAL,
      v_prod.categoria_nombre
    );
    v_stock_seguridad := v_stock_seguridad * v_factor_est;

    -- 5. Punto de reorden: ROP = d * LT + SS
    v_punto_reorden := (v_demanda_promedio * v_lead_time) + v_stock_seguridad;

    -- 6. Cantidad sugerida de compra (EOQ simplificado)
    -- Pedir para cubrir hasta stock_maximo o 30 dias de demanda
    v_cantidad_sugerida := GREATEST(
      v_punto_reorden - v_prod.stock_actual - v_prod.stock_en_transito,
      v_demanda_promedio * 30  -- minimo 30 dias de cobertura
    );

    -- 7. Dias de cobertura con stock actual
    v_dias_cobertura := CASE WHEN v_demanda_promedio > 0
      THEN (v_prod.stock_actual + v_prod.stock_en_transito) / v_demanda_promedio
      ELSE 9999
    END;

    v_fecha_desabastecimiento := CASE WHEN v_dias_cobertura < 9999
      THEN CURRENT_DATE + (v_dias_cobertura::INTEGER)
      ELSE NULL
    END;

    -- 8. Solo incluir si stock esta por debajo del punto de reorden
    IF (v_prod.stock_actual + v_prod.stock_en_transito) <= v_punto_reorden THEN
      v_resultado := v_resultado || jsonb_build_object(
        'producto_id', v_prod.producto_id,
        'nombre', v_prod.nombre,
        'categoria', v_prod.categoria_nombre,
        'stock_actual', ROUND(v_prod.stock_actual, 2),
        'stock_en_transito', ROUND(v_prod.stock_en_transito, 2),
        'stock_disponible', ROUND(v_prod.stock_actual + v_prod.stock_en_transito, 2),
        'demanda_promedio_diaria', ROUND(v_demanda_promedio, 2),
        'desviacion_demanda', ROUND(v_desviacion_demanda, 2),
        'lead_time_dias', v_lead_time,
        'nivel_servicio', v_prod.nivel_servicio,
        'stock_seguridad', ROUND(v_stock_seguridad, 2),
        'punto_reorden', ROUND(v_punto_reorden, 2),
        'cantidad_sugerida_compra', ROUND(v_cantidad_sugerida, 2),
        'dias_cobertura_actual', ROUND(v_dias_cobertura, 1),
        'fecha_desabastecimiento_estimada', v_fecha_desabastecimiento,
        'factor_estacional', ROUND(v_factor_est, 2),
        'proveedor_preferido_id', v_prod.proveedor_preferido_id,
        'urgencia', CASE
          WHEN v_dias_cobertura < v_lead_time THEN 'CRITICA'
          WHEN v_dias_cobertura < v_lead_time * 1.5 THEN 'ALTA'
          WHEN v_dias_cobertura < v_lead_time * 2 THEN 'MEDIA'
          ELSE 'BAJA'
        END,
        'sugerencia', FORMAT(
          'Pedir %s unidades de %s. Stock actual cubre %s dias. Lead time: %s dias. Llega aprox: %s.',
          ROUND(v_cantidad_sugerida, 0), v_prod.nombre,
          ROUND(v_dias_cobertura, 0), v_lead_time,
          (CURRENT_DATE + v_lead_time)::TEXT
        )
      );

      -- Crear alerta si urgencia CRITICA o ALTA
      IF v_dias_cobertura < v_lead_time * 1.5 THEN
        INSERT INTO alertas_anomalias
          (empresa_id, tipo, severidad, descripcion, datos, modulo, subtipo, accion_sugerida)
        VALUES
          (p_empresa_id, 'MONTO_INUSUAL',
           CASE WHEN v_dias_cobertura < v_lead_time THEN 'ALTA' ELSE 'MEDIA' END,
           FORMAT('Producto %s necesita reabastecimiento urgente. Stock cubre %s dias, lead time %s dias.',
             v_prod.nombre, ROUND(v_dias_cobertura, 0), v_lead_time),
           jsonb_build_object('producto_id', v_prod.producto_id,
             'stock_actual', v_prod.stock_actual,
             'punto_reorden', ROUND(v_punto_reorden, 2),
             'cantidad_sugerida', ROUND(v_cantidad_sugerida, 2)),
           'INVENTARIO', 'REABASTECIMIENTO',
           FORMAT('Crear OC por %s unidades de %s al proveedor.',
             ROUND(v_cantidad_sugerida, 0), v_prod.nombre))
        ON CONFLICT DO NOTHING;
      END IF;

      -- Persistir prediccion
      INSERT INTO ia_predictions
        (empresa_id, tipo, source_table, source_id, valor_predicho,
         intervalo_bajo, intervalo_alto, confianza, metadata)
      VALUES
        (p_empresa_id, 'REORDER_POINT', 'productos', v_prod.producto_id,
         ROUND(v_punto_reorden, 2),
         ROUND(v_punto_reorden - v_stock_seguridad, 2),
         ROUND(v_punto_reorden + v_stock_seguridad, 2),
         CASE v_prod.nivel_servicio
           WHEN 0.99 THEN 0.99 WHEN 0.95 THEN 0.95 ELSE 0.90 END,
         jsonb_build_object('lead_time', v_lead_time,
           'demanda_promedio', ROUND(v_demanda_promedio, 2),
           'stock_seguridad', ROUND(v_stock_seguridad, 2)));
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'productos_a_reabastecer', v_resultado,
    'total', jsonb_array_length(v_resultado),
    'fecha_calculo', CURRENT_DATE,
    'resumen', jsonb_build_object(
      'critica', (SELECT COUNT(*) FROM jsonb_array_elements(v_resultado) e WHERE e->>'urgencia' = 'CRITICA'),
      'alta', (SELECT COUNT(*) FROM jsonb_array_elements(v_resultado) e WHERE e->>'urgencia' = 'ALTA'),
      'media', (SELECT COUNT(*) FROM jsonb_array_elements(v_resultado) e WHERE e->>'urgencia' = 'MEDIA'),
      'baja', (SELECT COUNT(*) FROM jsonb_array_elements(v_resultado) e WHERE e->>'urgencia' = 'BAJA')
    )
  );
END;
$$;

-- ============================================================
-- FN_DETECTAR_ANOMALIAS_STOCK: Deteccion automatica de anomalias
-- ============================================================

CREATE OR REPLACE FUNCTION fn_detectar_anomalias_stock(
  p_empresa_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_resultado JSONB := '[]'::JSONB;
  v_anomalia RECORD;
  v_count INTEGER := 0;
BEGIN
  -- ANOMALIA 1: Stock negativo
  INSERT INTO ia_anomalias_stock
    (empresa_id, producto_id, tipo_anomalia, severidad, descripcion, datos)
  SELECT
    p_empresa_id,
    p.id,
    'STOCK_NEGATIVO',
    'ALTA',
    FORMAT('Producto %s tiene stock negativo: %s unidades', p.nombre, COALESCE(SUM(sm.cantidad), 0)),
    jsonb_build_object('stock_actual', COALESCE(SUM(sm.cantidad), 0))
  FROM productos p
  LEFT JOIN stock_movimientos sm ON sm.producto_id = p.id AND sm.empresa_id = p_empresa_id
  WHERE p.empresa_id = p_empresa_id AND p.activo = true
  GROUP BY p.id, p.nombre
  HAVING COALESCE(SUM(sm.cantidad), 0) < 0
  ON CONFLICT DO NOTHING;

  -- ANOMALIA 2: Sin rotacion >90 dias (productos con stock > 0 sin ventas en 90 dias)
  INSERT INTO ia_anomalias_stock
    (empresa_id, producto_id, tipo_anomalia, severidad, descripcion, datos)
  SELECT
    p_empresa_id,
    p.id,
    'SIN_ROTACION',
    'MEDIA',
    FORMAT('Producto %s sin ventas en 90+ dias. Stock actual: %s unidades valorizado en $%s',
      p.nombre, stock_qty.cantidad, ROUND(stock_qty.cantidad * COALESCE(p.costo_promedio, 0), 2)),
    jsonb_build_object(
      'stock_actual', stock_qty.cantidad,
      'valor_inmovilizado', ROUND(stock_qty.cantidad * COALESCE(p.costo_promedio, 0), 2),
      'ultima_venta', (SELECT MAX(fecha) FROM mv_ventas_diarias
        WHERE producto_id = p.id AND empresa_id = p_empresa_id),
      'dias_sin_venta', EXTRACT(DAY FROM NOW() - COALESCE(
        (SELECT MAX(fecha) FROM mv_ventas_diarias WHERE producto_id = p.id AND empresa_id = p_empresa_id),
        p.created_at::DATE))
    )
  FROM productos p
  JOIN (
    SELECT producto_id, SUM(cantidad) AS cantidad
    FROM stock_movimientos WHERE empresa_id = p_empresa_id
    GROUP BY producto_id HAVING SUM(cantidad) > 0
  ) stock_qty ON stock_qty.producto_id = p.id
  WHERE p.empresa_id = p_empresa_id
    AND p.activo = true
    AND p.tipo = 'PRODUCTO'
    AND NOT EXISTS (
      SELECT 1 FROM mv_ventas_diarias vd
      WHERE vd.producto_id = p.id AND vd.empresa_id = p_empresa_id
        AND vd.fecha >= CURRENT_DATE - 90
    )
  ON CONFLICT DO NOTHING;

  -- ANOMALIA 3: Sobrestock (stock actual > 3x demanda de 90 dias)
  INSERT INTO ia_anomalias_stock
    (empresa_id, producto_id, tipo_anomalia, severidad, descripcion, datos)
  SELECT
    p_empresa_id,
    abc.producto_id,
    'SOBRESTOCK',
    'BAJA',
    FORMAT('Producto %s tiene sobrestock: %s dias de inventario (promedio industria: 30-60 dias)',
      abc.producto_nombre,
      ROUND(CASE WHEN abc.demanda_promedio_diaria > 0
        THEN stock_qty.cantidad / abc.demanda_promedio_diaria ELSE 9999 END, 0)),
    jsonb_build_object(
      'stock_actual', stock_qty.cantidad,
      'demanda_promedio_diaria', ROUND(abc.demanda_promedio_diaria, 2),
      'dias_inventario', ROUND(CASE WHEN abc.demanda_promedio_diaria > 0
        THEN stock_qty.cantidad / abc.demanda_promedio_diaria ELSE 9999 END, 0),
      'valor_excedente', ROUND(
        (stock_qty.cantidad - abc.demanda_promedio_diaria * 60) *
        COALESCE(p.costo_promedio, 0), 2),
      'clase_abc', abc.clase_abc
    )
  FROM mv_abc_classification abc
  JOIN productos p ON p.id = abc.producto_id
  JOIN (
    SELECT producto_id, SUM(cantidad) AS cantidad
    FROM stock_movimientos WHERE empresa_id = p_empresa_id
    GROUP BY producto_id
  ) stock_qty ON stock_qty.producto_id = abc.producto_id
  WHERE abc.empresa_id = p_empresa_id
    AND abc.demanda_promedio_diaria > 0
    AND stock_qty.cantidad > abc.demanda_promedio_diaria * 90  -- >90 dias de stock
  ON CONFLICT DO NOTHING;

  -- ANOMALIA 4: Merma inusual (diferencia entre stock teorico y movimientos documentados)
  -- Se basa en ajustes de inventario tipo MERMA de los ultimos 30 dias
  INSERT INTO ia_anomalias_stock
    (empresa_id, producto_id, tipo_anomalia, severidad, descripcion, datos)
  SELECT
    p_empresa_id,
    sm.producto_id,
    'MERMA_INUSUAL',
    CASE
      WHEN ABS(SUM(sm.cantidad)) > abc.demanda_promedio_diaria * 7 THEN 'ALTA'
      ELSE 'MEDIA'
    END,
    FORMAT('Merma inusual detectada en %s: %s unidades en 30 dias (promedio historico: %s)',
      p.nombre, ABS(SUM(sm.cantidad)),
      ROUND(COALESCE(avg_merma.avg_merma, 0), 2)),
    jsonb_build_object(
      'merma_periodo', ABS(SUM(sm.cantidad)),
      'merma_promedio_mensual', ROUND(COALESCE(avg_merma.avg_merma, 0), 2),
      'ratio_vs_promedio', ROUND(ABS(SUM(sm.cantidad)) / NULLIF(avg_merma.avg_merma, 0), 2)
    )
  FROM stock_movimientos sm
  JOIN productos p ON p.id = sm.producto_id
  LEFT JOIN mv_abc_classification abc ON abc.producto_id = sm.producto_id AND abc.empresa_id = p_empresa_id
  LEFT JOIN (
    SELECT producto_id, AVG(ABS(cantidad)) AS avg_merma
    FROM stock_movimientos
    WHERE empresa_id = p_empresa_id AND tipo_movimiento = 'AJUSTE'
      AND motivo = 'MERMA' AND fecha >= CURRENT_DATE - 180
    GROUP BY producto_id
  ) avg_merma ON avg_merma.producto_id = sm.producto_id
  WHERE sm.empresa_id = p_empresa_id
    AND sm.tipo_movimiento = 'AJUSTE'
    AND sm.motivo = 'MERMA'
    AND sm.fecha >= CURRENT_DATE - 30
  GROUP BY sm.producto_id, p.nombre, abc.demanda_promedio_diaria, avg_merma.avg_merma
  HAVING ABS(SUM(sm.cantidad)) > COALESCE(avg_merma.avg_merma, 0) * 2  -- >2x promedio
  ON CONFLICT DO NOTHING;

  -- Contar anomalias nuevas
  SELECT COUNT(*) INTO v_count
  FROM ia_anomalias_stock
  WHERE empresa_id = p_empresa_id
    AND estado = 'PENDIENTE'
    AND created_at >= CURRENT_DATE;

  -- Construir resumen
  SELECT jsonb_build_object(
    'anomalias_nuevas', v_count,
    'por_tipo', jsonb_build_object(
      'stock_negativo', (SELECT COUNT(*) FROM ia_anomalias_stock
        WHERE empresa_id = p_empresa_id AND tipo_anomalia = 'STOCK_NEGATIVO' AND estado = 'PENDIENTE'),
      'sin_rotacion', (SELECT COUNT(*) FROM ia_anomalias_stock
        WHERE empresa_id = p_empresa_id AND tipo_anomalia = 'SIN_ROTACION' AND estado = 'PENDIENTE'),
      'sobrestock', (SELECT COUNT(*) FROM ia_anomalias_stock
        WHERE empresa_id = p_empresa_id AND tipo_anomalia = 'SOBRESTOCK' AND estado = 'PENDIENTE'),
      'merma_inusual', (SELECT COUNT(*) FROM ia_anomalias_stock
        WHERE empresa_id = p_empresa_id AND tipo_anomalia = 'MERMA_INUSUAL' AND estado = 'PENDIENTE')
    ),
    'valor_inmovilizado_total', (
      SELECT ROUND(COALESCE(SUM((datos->>'valor_inmovilizado')::DECIMAL), 0), 2)
      FROM ia_anomalias_stock
      WHERE empresa_id = p_empresa_id AND tipo_anomalia = 'SIN_ROTACION' AND estado = 'PENDIENTE'
    )
  ) INTO v_resultado;

  RETURN v_resultado;
END;
$$;

-- ============================================================
-- FN_WHAT_IF_INVENTARIO: Simulacion de escenarios
-- ============================================================

CREATE OR REPLACE FUNCTION fn_what_if_inventario(
  p_empresa_id UUID,
  p_producto_id UUID,
  p_escenario JSONB
    -- {"tipo": "CAMBIAR_MINIMO", "valor_nuevo": 50}
    -- {"tipo": "CAMBIAR_PROVEEDOR", "lead_time_nuevo": 14}
    -- {"tipo": "CAMBIAR_NIVEL_SERVICIO", "nivel_nuevo": 0.99}
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_tipo VARCHAR := p_escenario->>'tipo';
  v_demanda_promedio DECIMAL;
  v_desviacion DECIMAL;
  v_stock_actual DECIMAL;
  v_lead_time_actual INTEGER;
  v_lead_time_nuevo INTEGER;
  v_nivel_servicio DECIMAL;
  v_ss_actual DECIMAL;
  v_ss_nuevo DECIMAL;
  v_rop_actual DECIMAL;
  v_rop_nuevo DECIMAL;
  v_capital_actual DECIMAL;
  v_capital_nuevo DECIMAL;
  v_riesgo_actual DECIMAL;
  v_riesgo_nuevo DECIMAL;
  v_costo_producto DECIMAL;
  v_z_actual DECIMAL;
  v_z_nuevo DECIMAL;
BEGIN
  -- Obtener datos base del producto
  SELECT
    COALESCE(abc.demanda_promedio_diaria, 0),
    COALESCE(abc.desviacion_demanda, 0),
    COALESCE(p.lead_time_dias, 7),
    COALESCE(p.costo_promedio, 0),
    COALESCE(rc.nivel_servicio, 0.95)
  INTO v_demanda_promedio, v_desviacion, v_lead_time_actual, v_costo_producto, v_nivel_servicio
  FROM productos p
  LEFT JOIN mv_abc_classification abc ON abc.producto_id = p.id AND abc.empresa_id = p_empresa_id
  LEFT JOIN ia_reabastecimiento_config rc ON rc.producto_id = p.id AND rc.empresa_id = p_empresa_id
  WHERE p.id = p_producto_id AND p.empresa_id = p_empresa_id;

  SELECT COALESCE(SUM(cantidad), 0) INTO v_stock_actual
  FROM stock_movimientos WHERE producto_id = p_producto_id AND empresa_id = p_empresa_id;

  -- Z-scores
  v_z_actual := CASE
    WHEN v_nivel_servicio >= 0.99 THEN 2.33
    WHEN v_nivel_servicio >= 0.95 THEN 1.65
    WHEN v_nivel_servicio >= 0.90 THEN 1.28
    ELSE 0.84 END;

  -- Calcular situacion actual
  v_ss_actual := v_z_actual * v_desviacion * SQRT(v_lead_time_actual);
  v_rop_actual := v_demanda_promedio * v_lead_time_actual + v_ss_actual;
  v_capital_actual := v_rop_actual * v_costo_producto;

  -- Simular escenario
  CASE v_tipo
    WHEN 'CAMBIAR_MINIMO' THEN
      v_ss_nuevo := (p_escenario->>'valor_nuevo')::DECIMAL;
      v_rop_nuevo := v_demanda_promedio * v_lead_time_actual + v_ss_nuevo;

    WHEN 'CAMBIAR_PROVEEDOR' THEN
      v_lead_time_nuevo := (p_escenario->>'lead_time_nuevo')::INTEGER;
      v_ss_nuevo := v_z_actual * v_desviacion * SQRT(v_lead_time_nuevo);
      v_rop_nuevo := v_demanda_promedio * v_lead_time_nuevo + v_ss_nuevo;

    WHEN 'CAMBIAR_NIVEL_SERVICIO' THEN
      v_z_nuevo := CASE
        WHEN (p_escenario->>'nivel_nuevo')::DECIMAL >= 0.99 THEN 2.33
        WHEN (p_escenario->>'nivel_nuevo')::DECIMAL >= 0.95 THEN 1.65
        WHEN (p_escenario->>'nivel_nuevo')::DECIMAL >= 0.90 THEN 1.28
        ELSE 0.84 END;
      v_ss_nuevo := v_z_nuevo * v_desviacion * SQRT(v_lead_time_actual);
      v_rop_nuevo := v_demanda_promedio * v_lead_time_actual + v_ss_nuevo;

    ELSE
      RETURN jsonb_build_object('error', 'TIPO_ESCENARIO_NO_SOPORTADO');
  END CASE;

  v_capital_nuevo := v_rop_nuevo * v_costo_producto;

  RETURN jsonb_build_object(
    'producto_id', p_producto_id,
    'escenario', p_escenario,
    'situacion_actual', jsonb_build_object(
      'stock_seguridad', ROUND(v_ss_actual, 2),
      'punto_reorden', ROUND(v_rop_actual, 2),
      'capital_inmovilizado', ROUND(v_capital_actual, 2),
      'nivel_servicio', v_nivel_servicio,
      'lead_time', v_lead_time_actual
    ),
    'situacion_simulada', jsonb_build_object(
      'stock_seguridad', ROUND(v_ss_nuevo, 2),
      'punto_reorden', ROUND(v_rop_nuevo, 2),
      'capital_inmovilizado', ROUND(v_capital_nuevo, 2),
      'nivel_servicio', CASE v_tipo
        WHEN 'CAMBIAR_NIVEL_SERVICIO' THEN (p_escenario->>'nivel_nuevo')::DECIMAL
        ELSE v_nivel_servicio END,
      'lead_time', CASE v_tipo
        WHEN 'CAMBIAR_PROVEEDOR' THEN v_lead_time_nuevo
        ELSE v_lead_time_actual END
    ),
    'impacto', jsonb_build_object(
      'delta_capital', ROUND(v_capital_nuevo - v_capital_actual, 2),
      'delta_capital_pct', ROUND(
        (v_capital_nuevo - v_capital_actual) / NULLIF(v_capital_actual, 0) * 100, 1),
      'delta_stock_seguridad', ROUND(v_ss_nuevo - v_ss_actual, 2),
      'interpretacion', CASE
        WHEN v_capital_nuevo > v_capital_actual THEN
          FORMAT('Aumenta capital inmovilizado en $%s (%s%%) pero reduce riesgo de desabastecimiento.',
            ROUND(v_capital_nuevo - v_capital_actual, 2),
            ROUND((v_capital_nuevo - v_capital_actual) / NULLIF(v_capital_actual, 0) * 100, 1))
        WHEN v_capital_nuevo < v_capital_actual THEN
          FORMAT('Libera $%s de capital (%s%%) pero aumenta riesgo de desabastecimiento.',
            ROUND(v_capital_actual - v_capital_nuevo, 2),
            ROUND((v_capital_actual - v_capital_nuevo) / NULLIF(v_capital_actual, 0) * 100, 1))
        ELSE 'Sin impacto significativo.'
      END
    )
  );
END;
$$;
```

## Flujo UI/UX - Inventario IA

```
PANTALLA: Dashboard IA Inventario (dentro del modulo Inventario)
├── Tab: Reabastecimiento
│   ├── Filtros: [Urgencia v] [Categoria v] [Proveedor v]
│   ├── SfDataGrid: Producto | Stock | ROP | Sugerido | Urgencia | Dias cobertura | Accion
│   ├── Color-coded por urgencia: rojo CRITICA, naranja ALTA, amarillo MEDIA
│   ├── Boton por fila: "Crear OC" → abre wizard con datos pre-llenados
│   ├── Boton global: "Crear OC consolidada" → agrupa por proveedor
│   └── KPI cards: Productos bajo ROP | Capital comprometido | Dias promedio cobertura
│
├── Tab: Anomalias
│   ├── Filtros: [Tipo v] [Severidad v] [Estado v]
│   ├── Cards de anomalias con icono por tipo y color por severidad
│   ├── Cada card: Producto | Tipo | Descripcion | Valor afectado
│   ├── Acciones: "Investigar" | "Resolver" | "Descartar"
│   └── Click "Investigar" → detalle con historial de movimientos del producto
│
├── Tab: ABC
│   ├── Grafico de Pareto (Syncfusion): barras valor + linea % acumulado
│   ├── Tabla resumen: Clase | # Productos | % Valor | % Items | Frec. Conteo
│   ├── SfDataGrid detalle: Producto | Clase | Valor rotacion | Demanda | Sugerencia
│   └── Boton: "Generar plan de conteo" → crea inventario fisico ciclico
│
└── Tab: What-If
    ├── Selector de producto
    ├── Panel actual: SS | ROP | Capital | Lead time | Nivel servicio
    ├── Sliders de simulacion:
    │   - Stock minimo: [slider 0-1000]
    │   - Lead time proveedor: [slider 1-60 dias]
    │   - Nivel servicio: [slider 85%-99%]
    ├── Panel comparativo: Actual vs Simulado (barras lado a lado)
    └── Interpretacion automatica del impacto en texto
```

---

