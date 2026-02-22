# IA para Ventas - Análisis Predictivo


### Descripcion Funcional

El subsistema de IA para Ventas proporciona cuatro capacidades:

1. **Prediccion de ventas (forecast):** Proyeccion de revenue por producto, categoria o total empresa, con bandas de confianza y ajuste estacional Ecuador. Granularidad diaria, semanal y mensual.

2. **Scoring de oportunidades CRM:** Calculo de probabilidad de cierre para cada oportunidad del pipeline, basado en features del historial. Alertas de oportunidades calientes.

3. **Deteccion de churn (abandono de clientes):** Identificacion proactiva de clientes con patron de compra decreciente. Alertas con tiempo estimado para actuar.

4. **Precios dinamicos sugeridos:** Analisis de elasticidad precio-volumen para sugerir ajustes de precio que maximicen margen sin perder volumen.

### Modelo de Datos - Ventas IA

```sql
-- ============================================================
-- VISTA MATERIALIZADA: Ventas diarias por producto
-- Base para forecast y analisis de tendencia
-- ============================================================

CREATE MATERIALIZED VIEW mv_ventas_diarias AS
SELECT
  f.empresa_id,
  fl.producto_id,
  p.nombre AS producto_nombre,
  p.categoria_id,
  cp.nombre AS categoria_nombre,
  DATE(f.fecha_emision AT TIME ZONE 'America/Guayaquil') AS fecha,
  EXTRACT(DOW FROM f.fecha_emision) AS dia_semana,  -- 0=dom, 6=sab
  EXTRACT(MONTH FROM f.fecha_emision) AS mes,
  EXTRACT(YEAR FROM f.fecha_emision) AS anio,
  SUM(fl.cantidad) AS cantidad_vendida,
  SUM(fl.subtotal) AS revenue,
  SUM(fl.descuento_valor) AS descuento_total,
  COUNT(DISTINCT f.id) AS num_facturas,
  COUNT(DISTINCT f.contacto_id) AS num_clientes,
  AVG(fl.precio_unitario) AS precio_promedio
FROM facturas f
JOIN factura_lineas fl ON fl.factura_id = f.id
JOIN productos p ON p.id = fl.producto_id
LEFT JOIN categorias_producto cp ON cp.id = p.categoria_id
WHERE f.estado IN ('AUTORIZADA', 'PAGADA')
  AND f.tipo_documento = '01'  -- Solo facturas de venta
GROUP BY f.empresa_id, fl.producto_id, p.nombre, p.categoria_id,
         cp.nombre, DATE(f.fecha_emision AT TIME ZONE 'America/Guayaquil'),
         EXTRACT(DOW FROM f.fecha_emision),
         EXTRACT(MONTH FROM f.fecha_emision),
         EXTRACT(YEAR FROM f.fecha_emision)
WITH DATA;

CREATE UNIQUE INDEX idx_mv_ventas_diarias_pk
  ON mv_ventas_diarias(empresa_id, producto_id, fecha);
CREATE INDEX idx_mv_ventas_diarias_cat
  ON mv_ventas_diarias(empresa_id, categoria_id, fecha);

-- Refresh: cron diario a las 02:00 AM hora Ecuador
-- SELECT cron.schedule('refresh_mv_ventas_diarias', '0 7 * * *',
--   'REFRESH MATERIALIZED VIEW CONCURRENTLY mv_ventas_diarias');

-- ============================================================
-- VISTA MATERIALIZADA: Metricas por cliente (para churn + scoring)
-- ============================================================

CREATE MATERIALIZED VIEW mv_customer_metrics AS
SELECT
  f.empresa_id,
  f.contacto_id,
  c.nombre AS cliente_nombre,
  c.tipo_contacto,
  COUNT(f.id) AS total_facturas,
  SUM(f.total) AS revenue_total,
  AVG(f.total) AS ticket_promedio,
  MIN(f.fecha_emision) AS primera_compra,
  MAX(f.fecha_emision) AS ultima_compra,
  NOW() - MAX(f.fecha_emision) AS dias_sin_compra,
  -- Frecuencia promedio entre compras (en dias)
  CASE WHEN COUNT(f.id) > 1
    THEN EXTRACT(EPOCH FROM (MAX(f.fecha_emision) - MIN(f.fecha_emision)))
         / (COUNT(f.id) - 1) / 86400
    ELSE NULL
  END AS frecuencia_dias,
  -- Tendencia de ticket (ultimas 5 vs anteriores 5)
  (SELECT AVG(sub.total) FROM (
    SELECT total FROM facturas
    WHERE contacto_id = f.contacto_id AND empresa_id = f.empresa_id
      AND estado IN ('AUTORIZADA','PAGADA') AND tipo_documento = '01'
    ORDER BY fecha_emision DESC LIMIT 5
  ) sub) AS ticket_promedio_reciente,
  (SELECT AVG(sub.total) FROM (
    SELECT total FROM facturas
    WHERE contacto_id = f.contacto_id AND empresa_id = f.empresa_id
      AND estado IN ('AUTORIZADA','PAGADA') AND tipo_documento = '01'
    ORDER BY fecha_emision DESC LIMIT 10 OFFSET 5
  ) sub) AS ticket_promedio_anterior,
  -- Cantidad de productos distintos comprados
  (SELECT COUNT(DISTINCT fl2.producto_id) FROM factura_lineas fl2
   JOIN facturas f2 ON f2.id = fl2.factura_id
   WHERE f2.contacto_id = f.contacto_id AND f2.empresa_id = f.empresa_id
     AND f2.estado IN ('AUTORIZADA','PAGADA')) AS productos_distintos,
  -- Revenue ultimos 30, 60, 90 dias
  COALESCE((SELECT SUM(f3.total) FROM facturas f3
   WHERE f3.contacto_id = f.contacto_id AND f3.empresa_id = f.empresa_id
     AND f3.estado IN ('AUTORIZADA','PAGADA') AND f3.tipo_documento = '01'
     AND f3.fecha_emision >= NOW() - INTERVAL '30 days'), 0) AS revenue_30d,
  COALESCE((SELECT SUM(f3.total) FROM facturas f3
   WHERE f3.contacto_id = f.contacto_id AND f3.empresa_id = f.empresa_id
     AND f3.estado IN ('AUTORIZADA','PAGADA') AND f3.tipo_documento = '01'
     AND f3.fecha_emision >= NOW() - INTERVAL '60 days'), 0) AS revenue_60d,
  COALESCE((SELECT SUM(f3.total) FROM facturas f3
   WHERE f3.contacto_id = f.contacto_id AND f3.empresa_id = f.empresa_id
     AND f3.estado IN ('AUTORIZADA','PAGADA') AND f3.tipo_documento = '01'
     AND f3.fecha_emision >= NOW() - INTERVAL '90 days'), 0) AS revenue_90d
FROM facturas f
JOIN contactos c ON c.id = f.contacto_id
WHERE f.estado IN ('AUTORIZADA', 'PAGADA')
  AND f.tipo_documento = '01'
GROUP BY f.empresa_id, f.contacto_id, c.nombre, c.tipo_contacto
WITH DATA;

CREATE UNIQUE INDEX idx_mv_customer_metrics_pk
  ON mv_customer_metrics(empresa_id, contacto_id);

-- ============================================================
-- TABLA: Historial de precios (para analisis de elasticidad)
-- ============================================================

CREATE TABLE ia_historial_precios (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  producto_id     UUID NOT NULL REFERENCES productos(id),
  precio_anterior DECIMAL(14,2) NOT NULL,
  precio_nuevo    DECIMAL(14,2) NOT NULL,
  fecha_cambio    DATE NOT NULL,
  origen          VARCHAR(20) DEFAULT 'MANUAL',
    -- MANUAL, LISTA_PRECIOS, PROMOCION, IA_SUGERIDO
  volumen_pre_cambio  DECIMAL(18,6), -- volumen semanal antes del cambio
  volumen_post_cambio DECIMAL(18,6), -- volumen semanal despues del cambio (llenado posterior)
  elasticidad_calculada DECIMAL(8,4), -- llenado posterior por fn_calcular_elasticidad
  created_at      TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_ia_historial_precios
  ON ia_historial_precios(empresa_id, producto_id, fecha_cambio);

ALTER TABLE ia_historial_precios ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON ia_historial_precios
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT (auth.jwt() -> 'app_metadata' ->> 'empresa_id')::uuid));
```

### Funciones PostgreSQL - Ventas IA

```sql
-- ============================================================
-- FN_FORECAST_VENTAS: Prediccion de ventas con estacionalidad
-- ============================================================

CREATE OR REPLACE FUNCTION fn_forecast_ventas(
  p_empresa_id    UUID,
  p_producto_id   UUID DEFAULT NULL,     -- NULL = total empresa
  p_categoria_id  UUID DEFAULT NULL,     -- Filtro por categoria
  p_horizonte     INTEGER DEFAULT 30,    -- Dias a predecir
  p_granularidad  VARCHAR DEFAULT 'DIARIO' -- DIARIO, SEMANAL, MENSUAL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_datos RECORD;
  v_resultado JSONB := '[]'::JSONB;
  v_media DECIMAL(18,6);
  v_stddev DECIMAL(18,6);
  v_dias_historico INTEGER;
  v_factor_estacional DECIMAL(5,2);
  v_tendencia DECIMAL(18,6);  -- pendiente de regresion lineal
  v_fecha_pred DATE;
  v_pred_valor DECIMAL(18,6);
  v_pred_bajo DECIMAL(18,6);
  v_pred_alto DECIMAL(18,6);
  v_z DECIMAL := 1.96;  -- 95% intervalo confianza
  -- Promedios mensuales para estacionalidad
  v_promedios_mes DECIMAL(18,6)[];
  v_promedio_global DECIMAL(18,6);
  v_indices_estacional DECIMAL(5,2)[];
  i INTEGER;
BEGIN
  -- 1. Verificar datos suficientes (minimo 90 dias)
  SELECT COUNT(DISTINCT fecha), AVG(revenue), STDDEV(revenue)
  INTO v_dias_historico, v_media, v_stddev
  FROM mv_ventas_diarias
  WHERE empresa_id = p_empresa_id
    AND (p_producto_id IS NULL OR producto_id = p_producto_id)
    AND (p_categoria_id IS NULL OR categoria_id = p_categoria_id)
    AND fecha >= CURRENT_DATE - INTERVAL '365 days';

  IF v_dias_historico < 90 THEN
    RETURN jsonb_build_object(
      'error', 'DATOS_INSUFICIENTES',
      'dias_disponibles', v_dias_historico,
      'minimo_requerido', 90,
      'mensaje', 'Se necesitan al menos 90 dias de datos historicos'
    );
  END IF;

  -- 2. Calcular indices estacionales por mes
  FOR i IN 1..12 LOOP
    SELECT COALESCE(AVG(revenue), 0) INTO v_promedios_mes[i]
    FROM mv_ventas_diarias
    WHERE empresa_id = p_empresa_id
      AND (p_producto_id IS NULL OR producto_id = p_producto_id)
      AND (p_categoria_id IS NULL OR categoria_id = p_categoria_id)
      AND mes = i
      AND fecha >= CURRENT_DATE - INTERVAL '365 days';
  END LOOP;

  v_promedio_global := v_media;

  FOR i IN 1..12 LOOP
    IF v_promedio_global > 0 THEN
      v_indices_estacional[i] := v_promedios_mes[i] / v_promedio_global;
    ELSE
      v_indices_estacional[i] := 1.00;
    END IF;
  END LOOP;

  -- 3. Calcular tendencia (regresion lineal simple: revenue vs dia)
  SELECT COALESCE(
    regr_slope(revenue, EXTRACT(EPOCH FROM fecha - (CURRENT_DATE - 365))::INTEGER),
    0
  ) INTO v_tendencia
  FROM mv_ventas_diarias
  WHERE empresa_id = p_empresa_id
    AND (p_producto_id IS NULL OR producto_id = p_producto_id)
    AND (p_categoria_id IS NULL OR categoria_id = p_categoria_id)
    AND fecha >= CURRENT_DATE - INTERVAL '365 days';

  -- 4. Generar predicciones
  FOR i IN 1..p_horizonte LOOP
    v_fecha_pred := CURRENT_DATE + i;

    -- Prediccion = media + tendencia * dia + estacionalidad
    v_factor_estacional := v_indices_estacional[EXTRACT(MONTH FROM v_fecha_pred)::INTEGER];

    -- Tambien aplicar factor del calendario estacional Ecuador
    v_factor_estacional := v_factor_estacional *
      fn_factor_estacional(p_empresa_id, v_fecha_pred, NULL);

    v_pred_valor := (v_media + v_tendencia * i) * v_factor_estacional;

    -- Bandas de confianza
    v_pred_bajo := GREATEST(0, v_pred_valor - v_z * COALESCE(v_stddev, 0));
    v_pred_alto := v_pred_valor + v_z * COALESCE(v_stddev, 0);

    -- Agrupar segun granularidad
    IF p_granularidad = 'DIARIO' OR
       (p_granularidad = 'SEMANAL' AND EXTRACT(DOW FROM v_fecha_pred) = 1) OR
       (p_granularidad = 'MENSUAL' AND EXTRACT(DAY FROM v_fecha_pred) = 1) THEN

      v_resultado := v_resultado || jsonb_build_object(
        'fecha', v_fecha_pred,
        'valor_predicho', ROUND(v_pred_valor, 2),
        'intervalo_bajo', ROUND(v_pred_bajo, 2),
        'intervalo_alto', ROUND(v_pred_alto, 2),
        'factor_estacional', ROUND(v_factor_estacional, 2)
      );

      -- Persistir prediccion
      INSERT INTO ia_predictions
        (empresa_id, tipo, source_table, source_id, periodo,
         valor_predicho, intervalo_bajo, intervalo_alto,
         confianza, metadata)
      VALUES
        (p_empresa_id, 'FORECAST_VENTAS',
         CASE WHEN p_producto_id IS NOT NULL THEN 'productos' ELSE 'empresa' END,
         COALESCE(p_producto_id, p_empresa_id),
         TO_CHAR(v_fecha_pred, 'YYYY-MM-DD'),
         ROUND(v_pred_valor, 2),
         ROUND(v_pred_bajo, 2),
         ROUND(v_pred_alto, 2),
         CASE WHEN v_dias_historico > 180 THEN 0.85
              WHEN v_dias_historico > 90 THEN 0.70
              ELSE 0.55 END,
         jsonb_build_object('granularidad', p_granularidad,
           'tendencia_diaria', ROUND(v_tendencia, 4),
           'factor_estacional', ROUND(v_factor_estacional, 2)));
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'predicciones', v_resultado,
    'metadata', jsonb_build_object(
      'dias_historico', v_dias_historico,
      'media_diaria', ROUND(v_media, 2),
      'tendencia_diaria', ROUND(v_tendencia, 4),
      'horizonte_dias', p_horizonte,
      'granularidad', p_granularidad,
      'modelo', 'regresion_lineal_estacional_v1'
    )
  );
END;
$$;

-- ============================================================
-- FN_SCORING_CRM: Scoring de oportunidades
-- ============================================================

CREATE OR REPLACE FUNCTION fn_scoring_crm(
  p_empresa_id UUID,
  p_oportunidad_id UUID DEFAULT NULL  -- NULL = todas las activas
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_resultado JSONB := '[]'::JSONB;
  v_opp RECORD;
  v_score DECIMAL(5,2);
  v_factores JSONB;
BEGIN
  FOR v_opp IN
    SELECT
      o.id,
      o.nombre,
      o.valor_estimado,
      o.etapa,
      o.contacto_id,
      o.usuario_id,
      o.created_at,
      o.fecha_cierre_estimada,
      -- Dias desde creacion
      EXTRACT(DAY FROM NOW() - o.created_at) AS dias_abierta,
      -- Dias desde ultima interaccion
      COALESCE(
        EXTRACT(DAY FROM NOW() - (
          SELECT MAX(ra.created_at) FROM registro_actividad ra
          WHERE ra.registro_id = o.id AND ra.tabla = 'oportunidades_crm'
        )),
        EXTRACT(DAY FROM NOW() - o.created_at)
      ) AS dias_sin_interaccion,
      -- Numero de interacciones
      (SELECT COUNT(*) FROM registro_actividad ra
       WHERE ra.registro_id = o.id AND ra.tabla = 'oportunidades_crm'
      ) AS num_interacciones,
      -- Historial del cliente (si ha comprado antes)
      COALESCE(cm.total_facturas, 0) AS compras_previas_cliente,
      COALESCE(cm.revenue_total, 0) AS revenue_historico_cliente,
      -- Tasa de cierre del vendedor
      COALESCE((
        SELECT COUNT(*)::DECIMAL / NULLIF(COUNT(*) FILTER (WHERE etapa != 'CERRADA'), 0)
        FROM oportunidades_crm o2
        WHERE o2.usuario_id = o.usuario_id
          AND o2.empresa_id = p_empresa_id
          AND o2.etapa = 'GANADA'
      ), 0) AS tasa_cierre_vendedor
    FROM oportunidades_crm o
    LEFT JOIN mv_customer_metrics cm ON cm.contacto_id = o.contacto_id
      AND cm.empresa_id = o.empresa_id
    WHERE o.empresa_id = p_empresa_id
      AND o.etapa NOT IN ('GANADA', 'PERDIDA')
      AND (p_oportunidad_id IS NULL OR o.id = p_oportunidad_id)
  LOOP
    -- Calcular score (0-100) basado en multiples factores
    v_score := 0;
    v_factores := '{}'::JSONB;

    -- Factor 1: Etapa del pipeline (peso 25%)
    v_score := v_score + CASE v_opp.etapa
      WHEN 'PROSPECTO' THEN 5
      WHEN 'CALIFICADO' THEN 15
      WHEN 'PROPUESTA' THEN 40
      WHEN 'NEGOCIACION' THEN 65
      WHEN 'CIERRE' THEN 85
      ELSE 10
    END * 0.25;
    v_factores := v_factores || jsonb_build_object(
      'etapa', jsonb_build_object('valor', v_opp.etapa, 'peso', 0.25));

    -- Factor 2: Interacciones recientes (peso 20%)
    v_score := v_score + CASE
      WHEN v_opp.dias_sin_interaccion < 3 THEN 100
      WHEN v_opp.dias_sin_interaccion < 7 THEN 80
      WHEN v_opp.dias_sin_interaccion < 14 THEN 50
      WHEN v_opp.dias_sin_interaccion < 30 THEN 20
      ELSE 5
    END * 0.20;
    v_factores := v_factores || jsonb_build_object(
      'interaccion_reciente', jsonb_build_object(
        'dias_sin_contacto', v_opp.dias_sin_interaccion, 'peso', 0.20));

    -- Factor 3: Historial del cliente (peso 20%)
    v_score := v_score + CASE
      WHEN v_opp.compras_previas_cliente > 10 THEN 100
      WHEN v_opp.compras_previas_cliente > 5 THEN 80
      WHEN v_opp.compras_previas_cliente > 0 THEN 60
      ELSE 20  -- cliente nuevo, menor probabilidad
    END * 0.20;
    v_factores := v_factores || jsonb_build_object(
      'historial_cliente', jsonb_build_object(
        'compras_previas', v_opp.compras_previas_cliente, 'peso', 0.20));

    -- Factor 4: Valor de la oportunidad vs historial (peso 15%)
    v_score := v_score + CASE
      WHEN v_opp.revenue_historico_cliente > 0 AND
           v_opp.valor_estimado <= v_opp.revenue_historico_cliente * 0.5 THEN 90
      WHEN v_opp.revenue_historico_cliente > 0 AND
           v_opp.valor_estimado <= v_opp.revenue_historico_cliente THEN 70
      WHEN v_opp.valor_estimado < 1000 THEN 60
      ELSE 40
    END * 0.15;

    -- Factor 5: Tasa de cierre del vendedor (peso 10%)
    v_score := v_score + LEAST(v_opp.tasa_cierre_vendedor * 100, 100) * 0.10;

    -- Factor 6: Proximidad a fecha de cierre (peso 10%)
    v_score := v_score + CASE
      WHEN v_opp.fecha_cierre_estimada IS NULL THEN 30
      WHEN v_opp.fecha_cierre_estimada < CURRENT_DATE THEN 10  -- vencida
      WHEN v_opp.fecha_cierre_estimada <= CURRENT_DATE + 7 THEN 90
      WHEN v_opp.fecha_cierre_estimada <= CURRENT_DATE + 30 THEN 70
      ELSE 40
    END * 0.10;

    v_score := ROUND(LEAST(v_score, 100), 1);

    -- Generar alerta si score alto + interaccion pendiente
    IF v_score >= 70 AND v_opp.dias_sin_interaccion >= 3 THEN
      INSERT INTO alertas_anomalias
        (empresa_id, tipo, severidad, descripcion, datos, modulo, subtipo, accion_sugerida)
      VALUES
        (p_empresa_id, 'MONTO_INUSUAL', 'MEDIA',
         FORMAT('Oportunidad "%s" tiene %s%% probabilidad de cierre pero %s dias sin contacto',
           v_opp.nombre, v_score, v_opp.dias_sin_interaccion),
         jsonb_build_object('oportunidad_id', v_opp.id, 'score', v_score,
           'dias_sin_interaccion', v_opp.dias_sin_interaccion,
           'valor_estimado', v_opp.valor_estimado),
         'VENTAS', 'OPORTUNIDAD_CALIENTE',
         FORMAT('Contactar al cliente hoy. Oportunidad de $%s con %s%% de cierre.',
           v_opp.valor_estimado, v_score))
      ON CONFLICT DO NOTHING;
    END IF;

    v_resultado := v_resultado || jsonb_build_object(
      'oportunidad_id', v_opp.id,
      'nombre', v_opp.nombre,
      'valor_estimado', v_opp.valor_estimado,
      'score', v_score,
      'factores', v_factores,
      'accion_sugerida', CASE
        WHEN v_score >= 80 THEN 'CERRAR_AHORA'
        WHEN v_score >= 60 THEN 'CONTACTAR_PRONTO'
        WHEN v_score >= 40 THEN 'SEGUIMIENTO_NORMAL'
        ELSE 'RECALIFICAR'
      END
    );

    -- Persistir prediccion
    INSERT INTO ia_predictions
      (empresa_id, tipo, source_table, source_id, valor_predicho, confianza, metadata)
    VALUES
      (p_empresa_id, 'SCORING_CRM', 'oportunidades_crm', v_opp.id, v_score,
       0.75, v_factores);
  END LOOP;

  RETURN jsonb_build_object('scoring', v_resultado, 'total', jsonb_array_length(v_resultado));
END;
$$;

-- ============================================================
-- FN_DETECTAR_CHURN: Clientes en riesgo de abandono
-- ============================================================

CREATE OR REPLACE FUNCTION fn_detectar_churn(
  p_empresa_id UUID,
  p_umbral_dias DECIMAL DEFAULT NULL  -- NULL = auto-calcular
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_resultado JSONB := '[]'::JSONB;
  v_cliente RECORD;
  v_riesgo VARCHAR(10);
  v_score DECIMAL(5,2);
BEGIN
  FOR v_cliente IN
    SELECT
      cm.*,
      -- Ratio de caida en ticket promedio
      CASE WHEN cm.ticket_promedio_anterior > 0 AND cm.ticket_promedio_reciente IS NOT NULL
        THEN (cm.ticket_promedio_reciente - cm.ticket_promedio_anterior) / cm.ticket_promedio_anterior
        ELSE 0
      END AS tendencia_ticket,
      -- Ratio de caida en frecuencia reciente vs historica
      CASE WHEN cm.revenue_90d > 0 AND cm.revenue_total > 0
        THEN (cm.revenue_30d * 3) / (cm.revenue_90d)
        ELSE 1
      END AS tendencia_frecuencia
    FROM mv_customer_metrics cm
    WHERE cm.empresa_id = p_empresa_id
      AND cm.total_facturas >= 3  -- Solo clientes con historial minimo
      AND cm.frecuencia_dias IS NOT NULL
    ORDER BY
      EXTRACT(EPOCH FROM cm.dias_sin_compra) / NULLIF(cm.frecuencia_dias * 86400, 0) DESC
  LOOP
    -- Calcular score de churn (0 = seguro, 100 = alto riesgo)
    v_score := 0;

    -- Factor 1: Dias sin compra vs frecuencia historica (peso 40%)
    IF v_cliente.frecuencia_dias > 0 THEN
      v_score := v_score + LEAST(
        (EXTRACT(EPOCH FROM v_cliente.dias_sin_compra) / 86400) /
        v_cliente.frecuencia_dias * 25,
        100
      ) * 0.40;
    END IF;

    -- Factor 2: Tendencia de ticket promedio (peso 25%)
    IF v_cliente.tendencia_ticket < -0.30 THEN
      v_score := v_score + 90 * 0.25;  -- Caida >30%
    ELSIF v_cliente.tendencia_ticket < -0.15 THEN
      v_score := v_score + 60 * 0.25;  -- Caida 15-30%
    ELSIF v_cliente.tendencia_ticket < 0 THEN
      v_score := v_score + 30 * 0.25;  -- Caida <15%
    ELSE
      v_score := v_score + 5 * 0.25;   -- Estable o creciente
    END IF;

    -- Factor 3: Tendencia de frecuencia reciente (peso 25%)
    IF v_cliente.tendencia_frecuencia < 0.5 THEN
      v_score := v_score + 90 * 0.25;  -- Compra <50% de lo esperado
    ELSIF v_cliente.tendencia_frecuencia < 0.8 THEN
      v_score := v_score + 50 * 0.25;
    ELSE
      v_score := v_score + 10 * 0.25;
    END IF;

    -- Factor 4: Revenue historico (peso 10%) - clientes grandes = mas preocupante
    IF v_cliente.revenue_total > 10000 THEN
      v_score := v_score + 30 * 0.10;  -- boost para clientes valiosos
    END IF;

    v_score := ROUND(LEAST(v_score, 100), 1);

    -- Clasificar riesgo
    v_riesgo := CASE
      WHEN v_score >= 75 THEN 'CRITICO'
      WHEN v_score >= 50 THEN 'ALTO'
      WHEN v_score >= 30 THEN 'MEDIO'
      ELSE 'BAJO'
    END;

    -- Solo reportar riesgo MEDIO o superior
    IF v_score >= 30 THEN
      v_resultado := v_resultado || jsonb_build_object(
        'contacto_id', v_cliente.contacto_id,
        'nombre', v_cliente.cliente_nombre,
        'riesgo', v_riesgo,
        'score_churn', v_score,
        'dias_sin_compra', ROUND(EXTRACT(EPOCH FROM v_cliente.dias_sin_compra) / 86400),
        'frecuencia_habitual_dias', ROUND(v_cliente.frecuencia_dias),
        'ticket_promedio', ROUND(v_cliente.ticket_promedio, 2),
        'tendencia_ticket', ROUND(v_cliente.tendencia_ticket * 100, 1),
        'revenue_total', ROUND(v_cliente.revenue_total, 2),
        'revenue_30d', ROUND(v_cliente.revenue_30d, 2),
        'accion_sugerida', CASE
          WHEN v_score >= 75 THEN FORMAT(
            'URGENTE: Cliente %s no compra hace %s dias (su promedio es %s dias). Revenue historico: $%s. Contactar inmediatamente.',
            v_cliente.cliente_nombre,
            ROUND(EXTRACT(EPOCH FROM v_cliente.dias_sin_compra) / 86400),
            ROUND(v_cliente.frecuencia_dias),
            ROUND(v_cliente.revenue_total, 2))
          WHEN v_score >= 50 THEN FORMAT(
            'Cliente %s muestra patron de abandono. Ticket promedio cayo %s%%. Programar visita esta semana.',
            v_cliente.cliente_nombre,
            ROUND(ABS(v_cliente.tendencia_ticket) * 100, 1))
          ELSE FORMAT(
            'Monitorear: %s tiene actividad decreciente. Considerar oferta de retencion.',
            v_cliente.cliente_nombre)
        END
      );

      -- Crear alerta si es CRITICO o ALTO
      IF v_score >= 50 THEN
        INSERT INTO alertas_anomalias
          (empresa_id, tipo, severidad, descripcion, datos, modulo, subtipo, accion_sugerida)
        VALUES
          (p_empresa_id,
           'MONTO_INUSUAL',
           CASE WHEN v_score >= 75 THEN 'ALTA' ELSE 'MEDIA' END,
           FORMAT('Cliente %s en riesgo de abandono (score: %s%%)', v_cliente.cliente_nombre, v_score),
           jsonb_build_object('contacto_id', v_cliente.contacto_id, 'score', v_score,
             'dias_sin_compra', ROUND(EXTRACT(EPOCH FROM v_cliente.dias_sin_compra) / 86400),
             'frecuencia_habitual', ROUND(v_cliente.frecuencia_dias),
             'revenue_total', v_cliente.revenue_total),
           'VENTAS', 'CHURN_WARNING',
           FORMAT('Contactar a %s. No compra hace %s dias.',
             v_cliente.cliente_nombre,
             ROUND(EXTRACT(EPOCH FROM v_cliente.dias_sin_compra) / 86400)))
        ON CONFLICT DO NOTHING;
      END IF;

      -- Persistir prediccion
      INSERT INTO ia_predictions
        (empresa_id, tipo, source_table, source_id, valor_predicho, confianza)
      VALUES
        (p_empresa_id, 'CHURN_RISK', 'contactos', v_cliente.contacto_id,
         v_score, 0.70);
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'clientes_en_riesgo', v_resultado,
    'total', jsonb_array_length(v_resultado),
    'resumen', jsonb_build_object(
      'critico', (SELECT COUNT(*) FROM jsonb_array_elements(v_resultado) e WHERE e->>'riesgo' = 'CRITICO'),
      'alto', (SELECT COUNT(*) FROM jsonb_array_elements(v_resultado) e WHERE e->>'riesgo' = 'ALTO'),
      'medio', (SELECT COUNT(*) FROM jsonb_array_elements(v_resultado) e WHERE e->>'riesgo' = 'MEDIO')
    )
  );
END;
$$;

-- ============================================================
-- FN_PRECIO_SUGERIDO: Analisis de elasticidad y sugerencia de precio
-- ============================================================

CREATE OR REPLACE FUNCTION fn_precio_sugerido(
  p_empresa_id UUID,
  p_producto_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_precio_actual DECIMAL(14,2);
  v_costo DECIMAL(14,2);
  v_margen_actual DECIMAL(5,2);
  v_volumen_actual DECIMAL(18,6);
  v_elasticidad DECIMAL(8,4);
  v_num_cambios INTEGER;
  v_sugerencia JSONB;
BEGIN
  -- 1. Obtener precio y costo actual
  SELECT precio_venta, costo_promedio
  INTO v_precio_actual, v_costo
  FROM productos WHERE id = p_producto_id AND empresa_id = p_empresa_id;

  IF v_precio_actual IS NULL OR v_precio_actual = 0 THEN
    RETURN jsonb_build_object('error', 'PRODUCTO_SIN_PRECIO');
  END IF;

  v_margen_actual := (v_precio_actual - COALESCE(v_costo, 0)) / v_precio_actual;

  -- 2. Volumen actual (ultimos 30 dias)
  SELECT COALESCE(SUM(cantidad_vendida), 0)
  INTO v_volumen_actual
  FROM mv_ventas_diarias
  WHERE empresa_id = p_empresa_id AND producto_id = p_producto_id
    AND fecha >= CURRENT_DATE - 30;

  -- 3. Calcular elasticidad desde historial de precios
  SELECT COUNT(*), AVG(elasticidad_calculada)
  INTO v_num_cambios, v_elasticidad
  FROM ia_historial_precios
  WHERE empresa_id = p_empresa_id AND producto_id = p_producto_id
    AND elasticidad_calculada IS NOT NULL;

  IF v_num_cambios < 2 OR v_elasticidad IS NULL THEN
    -- Sin datos suficientes, usar elasticidad estimada conservadora
    v_elasticidad := -1.0;  -- Elasticidad unitaria por defecto
  END IF;

  -- 4. Simular escenarios de precio (+5%, +10%, -5%, -10%)
  v_sugerencia := jsonb_build_object(
    'producto_id', p_producto_id,
    'precio_actual', v_precio_actual,
    'costo', v_costo,
    'margen_actual_pct', ROUND(v_margen_actual * 100, 1),
    'volumen_30d', v_volumen_actual,
    'elasticidad_estimada', ROUND(v_elasticidad, 2),
    'datos_historicos', v_num_cambios,
    'escenarios', jsonb_build_array(
      -- Escenario +5%
      jsonb_build_object(
        'cambio_pct', 5,
        'precio_nuevo', ROUND(v_precio_actual * 1.05, 2),
        'volumen_estimado', ROUND(v_volumen_actual * (1 + v_elasticidad * 0.05), 0),
        'revenue_estimado', ROUND(
          v_precio_actual * 1.05 * v_volumen_actual * (1 + v_elasticidad * 0.05), 2),
        'margen_estimado', ROUND(
          (v_precio_actual * 1.05 - COALESCE(v_costo, 0)) *
          v_volumen_actual * (1 + v_elasticidad * 0.05), 2),
        'delta_margen', ROUND(
          (v_precio_actual * 1.05 - COALESCE(v_costo, 0)) *
          v_volumen_actual * (1 + v_elasticidad * 0.05) -
          (v_precio_actual - COALESCE(v_costo, 0)) * v_volumen_actual, 2)
      ),
      -- Escenario +10%
      jsonb_build_object(
        'cambio_pct', 10,
        'precio_nuevo', ROUND(v_precio_actual * 1.10, 2),
        'volumen_estimado', ROUND(v_volumen_actual * (1 + v_elasticidad * 0.10), 0),
        'revenue_estimado', ROUND(
          v_precio_actual * 1.10 * v_volumen_actual * (1 + v_elasticidad * 0.10), 2),
        'margen_estimado', ROUND(
          (v_precio_actual * 1.10 - COALESCE(v_costo, 0)) *
          v_volumen_actual * (1 + v_elasticidad * 0.10), 2),
        'delta_margen', ROUND(
          (v_precio_actual * 1.10 - COALESCE(v_costo, 0)) *
          v_volumen_actual * (1 + v_elasticidad * 0.10) -
          (v_precio_actual - COALESCE(v_costo, 0)) * v_volumen_actual, 2)
      ),
      -- Escenario -5%
      jsonb_build_object(
        'cambio_pct', -5,
        'precio_nuevo', ROUND(v_precio_actual * 0.95, 2),
        'volumen_estimado', ROUND(v_volumen_actual * (1 + v_elasticidad * (-0.05)), 0),
        'revenue_estimado', ROUND(
          v_precio_actual * 0.95 * v_volumen_actual * (1 + v_elasticidad * (-0.05)), 2),
        'margen_estimado', ROUND(
          (v_precio_actual * 0.95 - COALESCE(v_costo, 0)) *
          v_volumen_actual * (1 + v_elasticidad * (-0.05)), 2),
        'delta_margen', ROUND(
          (v_precio_actual * 0.95 - COALESCE(v_costo, 0)) *
          v_volumen_actual * (1 + v_elasticidad * (-0.05)) -
          (v_precio_actual - COALESCE(v_costo, 0)) * v_volumen_actual, 2)
      ),
      -- Escenario -10%
      jsonb_build_object(
        'cambio_pct', -10,
        'precio_nuevo', ROUND(v_precio_actual * 0.90, 2),
        'volumen_estimado', ROUND(v_volumen_actual * (1 + v_elasticidad * (-0.10)), 0),
        'revenue_estimado', ROUND(
          v_precio_actual * 0.90 * v_volumen_actual * (1 + v_elasticidad * (-0.10)), 2),
        'margen_estimado', ROUND(
          (v_precio_actual * 0.90 - COALESCE(v_costo, 0)) *
          v_volumen_actual * (1 + v_elasticidad * (-0.10)), 2),
        'delta_margen', ROUND(
          (v_precio_actual * 0.90 - COALESCE(v_costo, 0)) *
          v_volumen_actual * (1 + v_elasticidad * (-0.10)) -
          (v_precio_actual - COALESCE(v_costo, 0)) * v_volumen_actual, 2)
      )
    ),
    'recomendacion', CASE
      WHEN v_margen_actual > 0.40 AND v_elasticidad > -0.5 THEN
        'SUBIR_PRECIO: Margen alto y demanda inelastica. Subir 5-10% con bajo riesgo.'
      WHEN v_margen_actual < 0.15 THEN
        'SUBIR_PRECIO: Margen muy bajo. Considerar aumento para sostenibilidad.'
      WHEN v_elasticidad < -2.0 THEN
        'MANTENER: Demanda muy elastica. Cambios de precio afectan significativamente el volumen.'
      ELSE
        'ANALIZAR: Revisar escenarios y decidir segun estrategia comercial.'
    END
  );

  -- Persistir
  INSERT INTO ia_predictions
    (empresa_id, tipo, source_table, source_id, valor_predicho, metadata)
  VALUES
    (p_empresa_id, 'PRECIO_SUGERIDO', 'productos', p_producto_id,
     v_precio_actual, v_sugerencia);

  RETURN v_sugerencia;
END;
$$;
```

### Edge Function: ai-forecast

```typescript
// Edge Function: ai-forecast
// Endpoint: POST /functions/v1/ai-forecast
// Maneja: forecast ventas, scoring CRM, deteccion churn, precios sugeridos

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface ForecastRequest {
  action: "forecast_ventas" | "scoring_crm" | "detectar_churn" | "precio_sugerido";
  empresa_id: string;
  producto_id?: string;
  categoria_id?: string;
  oportunidad_id?: string;
  horizonte?: number;
  granularidad?: "DIARIO" | "SEMANAL" | "MENSUAL";
  interpretar?: boolean; // Si true, usa LLM para interpretar resultados
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "No authorization header" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      { global: { headers: { Authorization: authHeader } } }
    );

    const body: ForecastRequest = await req.json();

    let result: any;

    switch (body.action) {
      case "forecast_ventas": {
        const { data, error } = await supabase.rpc("fn_forecast_ventas", {
          p_empresa_id: body.empresa_id,
          p_producto_id: body.producto_id ?? null,
          p_categoria_id: body.categoria_id ?? null,
          p_horizonte: body.horizonte ?? 30,
          p_granularidad: body.granularidad ?? "DIARIO",
        });
        if (error) throw error;
        result = data;
        break;
      }
      case "scoring_crm": {
        const { data, error } = await supabase.rpc("fn_scoring_crm", {
          p_empresa_id: body.empresa_id,
          p_oportunidad_id: body.oportunidad_id ?? null,
        });
        if (error) throw error;
        result = data;
        break;
      }
      case "detectar_churn": {
        const { data, error } = await supabase.rpc("fn_detectar_churn", {
          p_empresa_id: body.empresa_id,
        });
        if (error) throw error;
        result = data;
        break;
      }
      case "precio_sugerido": {
        if (!body.producto_id) throw new Error("producto_id requerido");
        const { data, error } = await supabase.rpc("fn_precio_sugerido", {
          p_empresa_id: body.empresa_id,
          p_producto_id: body.producto_id,
        });
        if (error) throw error;
        result = data;
        break;
      }
      default:
        throw new Error(`Accion no soportada: ${body.action}`);
    }

    // Interpretacion con LLM (opcional)
    if (body.interpretar && result && !result.error) {
      const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
      if (apiKey) {
        const llmResponse = await fetch("https://api.anthropic.com/v1/messages", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "x-api-key": apiKey,
            "anthropic-version": "2023-06-01",
          },
          body: JSON.stringify({
            model: "claude-sonnet-4-20250514",
            max_tokens: 500,
            messages: [{
              role: "user",
              content: `Eres un analista de negocios de un ERP ecuatoriano. Interpreta estos resultados de ${body.action} en espanol, de forma concisa (3-5 oraciones). Datos: ${JSON.stringify(result).substring(0, 3000)}`
            }],
          }),
        });
        const llmData = await llmResponse.json();
        result.interpretacion = llmData.content?.[0]?.text ?? null;

        // Registrar uso de tokens
        await supabase.from("ia_token_usage").insert({
          empresa_id: body.empresa_id,
          edge_function: "ai-forecast",
          provider: "ANTHROPIC",
          model: "claude-sonnet-4-20250514",
          tokens_input: llmData.usage?.input_tokens ?? 0,
          tokens_output: llmData.usage?.output_tokens ?? 0,
          costo_estimado: ((llmData.usage?.input_tokens ?? 0) * 0.003 +
            (llmData.usage?.output_tokens ?? 0) * 0.015) / 1000,
        });
      }
    }

    return new Response(JSON.stringify(result), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
```

### Flujo UI/UX - Ventas IA

```
PANTALLA: Dashboard IA Ventas (dentro del modulo Ventas)
├── Tab: Forecast
│   ├── Filtros: [Producto v] [Categoria v] [Horizonte: 30/60/90 dias] [Granularidad v]
│   ├── Grafico de lineas (Syncfusion SfCartesianChart):
│   │   - Linea solida: valor predicho
│   │   - Area sombreada: banda de confianza (bajo-alto)
│   │   - Linea punteada: valor real historico
│   │   - Marcadores: eventos estacionales Ecuador
│   ├── KPI cards: Revenue proyectado mes | Tendencia % | Confianza modelo
│   └── Boton: "Interpretar con IA" → muestra texto resumen LLM
│
├── Tab: CRM Scoring
│   ├── SfDataGrid con columnas: Oportunidad | Valor | Score | Etapa | Accion
│   ├── Color-coded: verde >80, amarillo 60-80, naranja 40-60, rojo <40
│   ├── Click en fila → detalle con factores del score (barras horizontales)
│   └── Boton "Contactar" → abre registro CRM
│
├── Tab: Riesgo Churn
│   ├── Cards de clientes en riesgo ordenados por score (CRITICO primero)
│   │   Cada card: Nombre | Score | Dias sin compra | Ticket promedio | Tendencia
│   ├── Filtros: [Riesgo: Todos/Critico/Alto/Medio]
│   ├── Click card → historial de compras del cliente
│   └── Accion rapida: "Enviar oferta" | "Agendar llamada"
│
└── Tab: Precios Dinamicos
    ├── Selector de producto
    ├── Info actual: Precio | Costo | Margen | Volumen 30d
    ├── Tabla de escenarios con semaforo de impacto
    ├── Elasticidad estimada con indicador visual
    └── Boton: "Aplicar precio sugerido" (requiere confirmacion)
```

---

