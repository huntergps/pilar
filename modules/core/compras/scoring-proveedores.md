# Evaluación y Scoring de Proveedores


### Descripcion Funcional

El sistema de evaluacion de proveedores permite calificar de manera objetiva y sistematica el desempeno de cada proveedor mediante criterios configurables y ponderados por empresa. Combina evaluacion automatica (basada en datos historicos de ordenes de compra, recepciones, calidad e inspecciones) con evaluacion manual periodica (encuestas al equipo de compras).

**Componentes del sistema:**

1. **Criterios de evaluacion configurables:** Cada empresa define sus propios criterios con ponderaciones (ej: calidad 30%, precio 25%, cumplimiento entregas 25%, servicio 10%, condiciones pago 10%).

2. **Evaluacion automatica:** El sistema calcula puntajes basados en datos reales:
   - **Cumplimiento de entregas:** % de recepciones dentro de la fecha prometida en la OC
   - **Calidad:** % de productos recibidos sin rechazo en inspecciones de calidad
   - **Competitividad de precios:** comparacion del precio promedio del proveedor vs promedio del mercado (otros proveedores del mismo producto)
   - **Tiempo de respuesta:** promedio de horas entre envio de RFQ y respuesta del proveedor
   - **Volumen de cumplimiento:** % de la cantidad ordenada vs cantidad efectivamente recibida

3. **Evaluacion manual periodica:** Encuesta configurable que el equipo de compras completa periodicamente (mensual, trimestral o anual) para evaluar aspectos subjetivos: servicio post-venta, comunicacion, flexibilidad, soporte tecnico.

4. **Scoring compuesto:** Puntaje final de 0-100 con clasificacion automatica:
   - A (90-100): Proveedor estrategico
   - B (75-89): Proveedor confiable
   - C (60-74): Proveedor aceptable
   - D (40-59): Proveedor en observacion
   - F (0-39): Proveedor bloqueado

5. **Acciones automaticas:**
   - Alertas cuando un proveedor cae por debajo del umbral configurado
   - Bloqueo automatico de proveedores con clasificacion F (configurable)
   - Priorizacion en invitaciones a RFQ segun score
   - Notificacion al responsable de compras cuando un proveedor mejora/empeora significativamente

**Flujo:**

```
Configurar criterios y ponderaciones (una vez por empresa)
  |
  v
Datos se acumulan automaticamente (OC, recepciones, RFQs)
  |
  v
Cron mensual/trimestral: calcular puntajes automaticos
  |
  v
Evaluacion manual periodica (encuesta al equipo)
  |
  v
Score compuesto = (automatico * peso_auto + manual * peso_manual) / 100
  |
  v
Clasificacion A/B/C/D/F -> alertas y acciones automaticas
  |
  v
Reportes comparativos + historial de tendencia
```

### Modelo de Datos SQL

```sql
-- ============================================
-- EVALUACION Y SCORING DE PROVEEDORES (AMPLIACION)
-- Reemplaza la tabla basica evaluaciones_proveedor del INFORME
-- ============================================

-- Criterios de evaluacion configurables por empresa
CREATE TABLE evaluacion_criterios (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  codigo          VARCHAR(30) NOT NULL,
  nombre          VARCHAR(100) NOT NULL,
  descripcion     TEXT,
  tipo_calculo    VARCHAR(20) NOT NULL DEFAULT 'AUTOMATICO',
    -- AUTOMATICO: calculado desde datos historicos
    -- MANUAL: evaluacion subjetiva del equipo
    -- MIXTO: promedio de automatico + manual
  peso            DECIMAL(5,2) NOT NULL,           -- Ponderacion (ej: 25.00 = 25%)
  metrica         VARCHAR(30),                     -- Metrica para calculo automatico
    -- ENTREGAS_A_TIEMPO: % recepciones <= fecha_entrega_esperada
    -- CALIDAD_PRODUCTOS: % inspecciones aprobadas
    -- COMPETITIVIDAD_PRECIO: ranking de precio vs promedio mercado
    -- TIEMPO_RESPUESTA_RFQ: velocidad de respuesta a cotizaciones
    -- CUMPLIMIENTO_CANTIDAD: % cantidad recibida vs cantidad ordenada
    -- TASA_DEVOLUCION: % de devoluciones/reclamos
  umbral_minimo   DECIMAL(5,2) DEFAULT 0,          -- Puntaje minimo aceptable (0-100)
  activo          BOOLEAN DEFAULT true,
  orden           INTEGER DEFAULT 0,
  created_at      TIMESTAMPTZ DEFAULT now(),
  UNIQUE(empresa_id, codigo)
);

ALTER TABLE evaluacion_criterios ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON evaluacion_criterios FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- Configuracion general de evaluacion por empresa
CREATE TABLE evaluacion_config (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id) UNIQUE,
  frecuencia_auto VARCHAR(15) DEFAULT 'MENSUAL',
    -- MENSUAL, TRIMESTRAL, SEMESTRAL, ANUAL
  frecuencia_manual VARCHAR(15) DEFAULT 'TRIMESTRAL',
  peso_automatico DECIMAL(5,2) DEFAULT 70.00,       -- % peso de evaluacion automatica
  peso_manual     DECIMAL(5,2) DEFAULT 30.00,        -- % peso de evaluacion manual
  umbral_alerta   DECIMAL(5,2) DEFAULT 50.00,        -- Score debajo del cual se genera alerta
  umbral_bloqueo  DECIMAL(5,2) DEFAULT 30.00,        -- Score debajo del cual se bloquea proveedor
  bloqueo_automatico BOOLEAN DEFAULT false,           -- Bloquear automaticamente proveedores bajo umbral
  meses_historico INTEGER DEFAULT 12,                 -- Meses de datos historicos para calculo
  notificar_caida BOOLEAN DEFAULT true,               -- Notificar cuando un proveedor baja de clasificacion
  notificar_mejora BOOLEAN DEFAULT false,              -- Notificar cuando un proveedor sube
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE evaluacion_config ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON evaluacion_config FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- Evaluaciones de proveedor (REEMPLAZA la tabla basica del INFORME)
-- Ahora con criterios desglosados y mas detalle
DROP TABLE IF EXISTS evaluaciones_proveedor;

CREATE TABLE evaluaciones_proveedor (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  proveedor_id          UUID NOT NULL REFERENCES contactos(id),
  periodo               VARCHAR(10) NOT NULL,           -- '2026-Q1', '2026-01', etc.
  tipo                  VARCHAR(15) NOT NULL DEFAULT 'AUTOMATICA',
    -- AUTOMATICA: calculada por el sistema
    -- MANUAL: evaluacion subjetiva del equipo
    -- COMPUESTA: combinacion de automatica + manual
  -- Puntajes por criterio (0-100 cada uno)
  puntajes_criterios    JSONB NOT NULL DEFAULT '{}',
    -- { "criterio_id": {"codigo": "ENTREGAS_A_TIEMPO", "puntaje": 85.5, "peso": 25, "datos": {...}} }
  -- Puntaje final ponderado
  puntaje_total         DECIMAL(5,2) NOT NULL DEFAULT 0,
  clasificacion         VARCHAR(1) NOT NULL DEFAULT 'C',
    -- A (90-100), B (75-89), C (60-74), D (40-59), F (0-39)
  clasificacion_anterior VARCHAR(1),                    -- Para detectar cambios
  -- Datos de referencia (snapshot al momento de la evaluacion)
  total_ocs_periodo     INTEGER DEFAULT 0,
  total_recepciones     INTEGER DEFAULT 0,
  monto_comprado        DECIMAL(14,2) DEFAULT 0,
  -- Evaluacion manual
  evaluador_id          UUID REFERENCES auth.users(id),
  comentarios           TEXT,
  -- Metadatos
  fecha                 DATE NOT NULL DEFAULT CURRENT_DATE,
  created_at            TIMESTAMPTZ DEFAULT now(),
  UNIQUE(empresa_id, proveedor_id, periodo, tipo)
);

ALTER TABLE evaluaciones_proveedor ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON evaluaciones_proveedor FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- Detalle de evaluacion manual (respuestas de encuesta)
CREATE TABLE evaluacion_manual_detalle (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  evaluacion_id   UUID NOT NULL REFERENCES evaluaciones_proveedor(id) ON DELETE CASCADE,
  criterio_id     UUID NOT NULL REFERENCES evaluacion_criterios(id),
  puntaje         DECIMAL(5,2) NOT NULL CHECK (puntaje >= 0 AND puntaje <= 100),
  comentario      TEXT,
  evaluador_id    UUID NOT NULL REFERENCES auth.users(id),
  fecha           TIMESTAMPTZ DEFAULT now()
);

-- Inspecciones de calidad en recepciones (alimenta el scoring)
CREATE TABLE inspecciones_calidad (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  orden_compra_id UUID NOT NULL REFERENCES ordenes_compra(id),
  proveedor_id    UUID NOT NULL REFERENCES contactos(id),
  producto_id     UUID NOT NULL REFERENCES productos(id),
  cantidad_recibida   DECIMAL(18,6) NOT NULL,
  cantidad_aceptada   DECIMAL(18,6) NOT NULL,
  cantidad_rechazada  DECIMAL(18,6) DEFAULT 0,
  motivo_rechazo      VARCHAR(30),
    -- DANADO, DEFECTUOSO, INCOMPLETO, VENCIDO, NO_CONFORME, OTRO
  descripcion_rechazo TEXT,
  resultado       VARCHAR(15) NOT NULL DEFAULT 'APROBADA',
    -- APROBADA: todo OK
    -- PARCIAL: parte rechazada
    -- RECHAZADA: todo rechazado
  inspector_id    UUID REFERENCES auth.users(id),
  fecha           TIMESTAMPTZ DEFAULT now(),
  evidencia_urls  JSONB DEFAULT '[]',                   -- URLs de fotos en Supabase Storage
  notas           TEXT
);

ALTER TABLE inspecciones_calidad ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON inspecciones_calidad FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- Campo adicional en contactos para score actual
ALTER TABLE contactos
  ADD COLUMN IF NOT EXISTS score_proveedor     DECIMAL(5,2) DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS clasificacion_proveedor VARCHAR(1) DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS fecha_ultima_evaluacion DATE DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS proveedor_bloqueado_score BOOLEAN DEFAULT false;

-- Indices
CREATE INDEX idx_eval_criterios_empresa ON evaluacion_criterios(empresa_id, activo);
CREATE INDEX idx_evaluaciones_proveedor_empresa ON evaluaciones_proveedor(empresa_id, proveedor_id, periodo);
CREATE INDEX idx_evaluaciones_proveedor_fecha ON evaluaciones_proveedor(empresa_id, fecha DESC);
CREATE INDEX idx_inspecciones_calidad_oc ON inspecciones_calidad(orden_compra_id);
CREATE INDEX idx_inspecciones_calidad_proveedor ON inspecciones_calidad(empresa_id, proveedor_id, fecha);
```

### Funciones PostgreSQL Principales

```sql
-- ============================================
-- CALCULAR EVALUACION AUTOMATICA DE UN PROVEEDOR
-- Analiza datos historicos y calcula puntaje por criterio
-- ============================================
CREATE OR REPLACE FUNCTION calculate_supplier_score(
  p_empresa_id UUID,
  p_proveedor_id UUID,
  p_periodo VARCHAR DEFAULT NULL  -- Si NULL, calcula para el periodo actual
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_config RECORD;
  v_criterio RECORD;
  v_puntajes JSONB := '{}'::JSONB;
  v_puntaje_total DECIMAL(5,2) := 0;
  v_peso_acumulado DECIMAL(5,2) := 0;
  v_puntaje DECIMAL(5,2);
  v_datos JSONB;
  v_periodo VARCHAR;
  v_fecha_desde DATE;
  v_fecha_hasta DATE;
  v_clasificacion VARCHAR(1);
  v_eval_id UUID;
  v_clasificacion_ant VARCHAR(1);
BEGIN
  -- 1. Obtener configuracion
  SELECT * INTO v_config FROM evaluacion_config WHERE empresa_id = p_empresa_id;
  IF v_config IS NULL THEN
    RAISE EXCEPTION 'No hay configuracion de evaluacion para esta empresa';
  END IF;

  -- 2. Determinar periodo
  IF p_periodo IS NULL THEN
    v_periodo := TO_CHAR(CURRENT_DATE, 'YYYY-MM');
  ELSE
    v_periodo := p_periodo;
  END IF;

  v_fecha_hasta := CURRENT_DATE;
  v_fecha_desde := v_fecha_hasta - (v_config.meses_historico || ' months')::INTERVAL;

  -- 3. Obtener clasificacion anterior
  SELECT clasificacion INTO v_clasificacion_ant
  FROM evaluaciones_proveedor
  WHERE empresa_id = p_empresa_id AND proveedor_id = p_proveedor_id AND tipo = 'AUTOMATICA'
  ORDER BY fecha DESC LIMIT 1;

  -- 4. Calcular cada criterio automatico
  FOR v_criterio IN
    SELECT * FROM evaluacion_criterios
    WHERE empresa_id = p_empresa_id AND activo = true
      AND tipo_calculo IN ('AUTOMATICO', 'MIXTO')
    ORDER BY orden
  LOOP
    v_puntaje := 0;
    v_datos := '{}'::JSONB;

    CASE v_criterio.metrica
      -- ENTREGAS A TIEMPO
      WHEN 'ENTREGAS_A_TIEMPO' THEN
        SELECT
          COALESCE(
            ROUND(
              COUNT(*) FILTER (WHERE k.fecha::DATE <= oc.fecha_entrega_esperada)::DECIMAL /
              NULLIF(COUNT(*), 0) * 100, 2
            ), 0
          ),
          jsonb_build_object(
            'total_recepciones', COUNT(*),
            'a_tiempo', COUNT(*) FILTER (WHERE k.fecha::DATE <= oc.fecha_entrega_esperada),
            'tardias', COUNT(*) FILTER (WHERE k.fecha::DATE > oc.fecha_entrega_esperada)
          )
        INTO v_puntaje, v_datos
        FROM ordenes_compra oc
        JOIN kardex k ON k.documento_id = oc.id AND k.tipo_movimiento = 'INGRESO'
        WHERE oc.empresa_id = p_empresa_id
          AND oc.contacto_id = p_proveedor_id
          AND oc.fecha BETWEEN v_fecha_desde AND v_fecha_hasta
          AND oc.estado IN ('COMPLETA', 'PARCIAL');

      -- CALIDAD DE PRODUCTOS
      WHEN 'CALIDAD_PRODUCTOS' THEN
        SELECT
          COALESCE(
            ROUND(
              SUM(cantidad_aceptada)::DECIMAL /
              NULLIF(SUM(cantidad_recibida), 0) * 100, 2
            ), 100
          ),
          jsonb_build_object(
            'total_inspecciones', COUNT(*),
            'aprobadas', COUNT(*) FILTER (WHERE resultado = 'APROBADA'),
            'parciales', COUNT(*) FILTER (WHERE resultado = 'PARCIAL'),
            'rechazadas', COUNT(*) FILTER (WHERE resultado = 'RECHAZADA')
          )
        INTO v_puntaje, v_datos
        FROM inspecciones_calidad
        WHERE empresa_id = p_empresa_id
          AND proveedor_id = p_proveedor_id
          AND fecha BETWEEN v_fecha_desde AND v_fecha_hasta;

      -- COMPETITIVIDAD DE PRECIOS
      WHEN 'COMPETITIVIDAD_PRECIO' THEN
        WITH precios_proveedor AS (
          SELECT ocd.producto_id,
                 AVG(ocd.precio_unitario) AS precio_prov
          FROM orden_compra_detalles ocd
          JOIN ordenes_compra oc ON oc.id = ocd.orden_compra_id
          WHERE oc.empresa_id = p_empresa_id
            AND oc.contacto_id = p_proveedor_id
            AND oc.fecha BETWEEN v_fecha_desde AND v_fecha_hasta
            AND oc.estado NOT IN ('BORRADOR', 'CANCELADA')
          GROUP BY ocd.producto_id
        ),
        precios_mercado AS (
          SELECT ocd.producto_id,
                 AVG(ocd.precio_unitario) AS precio_mercado
          FROM orden_compra_detalles ocd
          JOIN ordenes_compra oc ON oc.id = ocd.orden_compra_id
          WHERE oc.empresa_id = p_empresa_id
            AND oc.contacto_id != p_proveedor_id
            AND oc.fecha BETWEEN v_fecha_desde AND v_fecha_hasta
            AND oc.estado NOT IN ('BORRADOR', 'CANCELADA')
            AND ocd.producto_id IN (SELECT producto_id FROM precios_proveedor)
          GROUP BY ocd.producto_id
        )
        SELECT
          COALESCE(
            ROUND(AVG(
              CASE
                WHEN pm.precio_mercado > 0 THEN
                  LEAST(100, GREATEST(0, (1 - (pp.precio_prov - pm.precio_mercado) / pm.precio_mercado) * 100))
                ELSE 50
              END
            ), 2),
            50  -- Sin datos = neutral
          ),
          jsonb_build_object(
            'productos_comparados', COUNT(*),
            'mas_baratos', COUNT(*) FILTER (WHERE pp.precio_prov < pm.precio_mercado),
            'mas_caros', COUNT(*) FILTER (WHERE pp.precio_prov > pm.precio_mercado)
          )
        INTO v_puntaje, v_datos
        FROM precios_proveedor pp
        LEFT JOIN precios_mercado pm ON pm.producto_id = pp.producto_id;

      -- TIEMPO DE RESPUESTA A RFQ
      WHEN 'TIEMPO_RESPUESTA_RFQ' THEN
        WITH tiempos AS (
          SELECT tiempo_respuesta_horas
          FROM solicitud_cotizacion_proveedores scp
          JOIN solicitudes_cotizacion sc ON sc.id = scp.solicitud_id
          WHERE sc.empresa_id = p_empresa_id
            AND scp.proveedor_id = p_proveedor_id
            AND scp.fecha_respuesta IS NOT NULL
            AND sc.fecha_emision BETWEEN v_fecha_desde AND v_fecha_hasta
        )
        SELECT
          COALESCE(
            ROUND(GREATEST(0, LEAST(100,
              100 - (AVG(tiempo_respuesta_horas) - 4) * 2  -- 4h = 100pts, cada 2h mas = -2pts
            )), 2),
            50
          ),
          jsonb_build_object(
            'rfqs_respondidas', COUNT(*),
            'promedio_horas', ROUND(AVG(tiempo_respuesta_horas)::DECIMAL, 2),
            'minimo_horas', ROUND(MIN(tiempo_respuesta_horas)::DECIMAL, 2),
            'maximo_horas', ROUND(MAX(tiempo_respuesta_horas)::DECIMAL, 2)
          )
        INTO v_puntaje, v_datos
        FROM tiempos;

      -- CUMPLIMIENTO DE CANTIDAD
      WHEN 'CUMPLIMIENTO_CANTIDAD' THEN
        SELECT
          COALESCE(
            ROUND(
              AVG(
                LEAST(100, ocd.cantidad_recibida / NULLIF(ocd.cantidad, 0) * 100)
              ), 2
            ), 100
          ),
          jsonb_build_object(
            'lineas_evaluadas', COUNT(*),
            'completas', COUNT(*) FILTER (WHERE ocd.cantidad_recibida >= ocd.cantidad),
            'parciales', COUNT(*) FILTER (WHERE ocd.cantidad_recibida > 0 AND ocd.cantidad_recibida < ocd.cantidad),
            'sin_recibir', COUNT(*) FILTER (WHERE ocd.cantidad_recibida = 0)
          )
        INTO v_puntaje, v_datos
        FROM orden_compra_detalles ocd
        JOIN ordenes_compra oc ON oc.id = ocd.orden_compra_id
        WHERE oc.empresa_id = p_empresa_id
          AND oc.contacto_id = p_proveedor_id
          AND oc.fecha BETWEEN v_fecha_desde AND v_fecha_hasta
          AND oc.estado IN ('COMPLETA', 'PARCIAL');

      -- TASA DE DEVOLUCION (menos devoluciones = mejor)
      WHEN 'TASA_DEVOLUCION' THEN
        SELECT
          COALESCE(
            ROUND(100 - (
              COUNT(*) FILTER (WHERE resultado IN ('PARCIAL', 'RECHAZADA'))::DECIMAL /
              NULLIF(COUNT(*), 0) * 100
            ), 2),
            100
          ),
          jsonb_build_object(
            'total_inspecciones', COUNT(*),
            'con_rechazo', COUNT(*) FILTER (WHERE resultado IN ('PARCIAL', 'RECHAZADA'))
          )
        INTO v_puntaje, v_datos
        FROM inspecciones_calidad
        WHERE empresa_id = p_empresa_id
          AND proveedor_id = p_proveedor_id
          AND fecha BETWEEN v_fecha_desde AND v_fecha_hasta;

      ELSE
        v_puntaje := 50; -- Metrica no reconocida = neutral
    END CASE;

    -- Acumular puntaje ponderado
    v_puntajes := v_puntajes || jsonb_build_object(
      v_criterio.id::TEXT, jsonb_build_object(
        'codigo', v_criterio.codigo,
        'nombre', v_criterio.nombre,
        'puntaje', v_puntaje,
        'peso', v_criterio.peso,
        'ponderado', ROUND(v_puntaje * v_criterio.peso / 100, 2),
        'datos', v_datos
      )
    );

    v_puntaje_total := v_puntaje_total + (v_puntaje * v_criterio.peso / 100);
    v_peso_acumulado := v_peso_acumulado + v_criterio.peso;
  END LOOP;

  -- Normalizar si pesos no suman 100
  IF v_peso_acumulado > 0 AND v_peso_acumulado != 100 THEN
    v_puntaje_total := v_puntaje_total * 100 / v_peso_acumulado;
  END IF;

  -- 5. Clasificacion
  v_clasificacion := CASE
    WHEN v_puntaje_total >= 90 THEN 'A'
    WHEN v_puntaje_total >= 75 THEN 'B'
    WHEN v_puntaje_total >= 60 THEN 'C'
    WHEN v_puntaje_total >= 40 THEN 'D'
    ELSE 'F'
  END;

  -- 6. Guardar evaluacion
  INSERT INTO evaluaciones_proveedor (
    empresa_id, proveedor_id, periodo, tipo,
    puntajes_criterios, puntaje_total, clasificacion,
    clasificacion_anterior,
    total_ocs_periodo, monto_comprado, fecha
  ) VALUES (
    p_empresa_id, p_proveedor_id, v_periodo, 'AUTOMATICA',
    v_puntajes, ROUND(v_puntaje_total, 2), v_clasificacion,
    v_clasificacion_ant,
    (SELECT COUNT(*) FROM ordenes_compra WHERE empresa_id = p_empresa_id
     AND contacto_id = p_proveedor_id AND fecha BETWEEN v_fecha_desde AND v_fecha_hasta
     AND estado NOT IN ('BORRADOR', 'CANCELADA')),
    (SELECT COALESCE(SUM(total), 0) FROM ordenes_compra WHERE empresa_id = p_empresa_id
     AND contacto_id = p_proveedor_id AND fecha BETWEEN v_fecha_desde AND v_fecha_hasta
     AND estado NOT IN ('BORRADOR', 'CANCELADA')),
    CURRENT_DATE
  )
  ON CONFLICT (empresa_id, proveedor_id, periodo, tipo)
  DO UPDATE SET
    puntajes_criterios = EXCLUDED.puntajes_criterios,
    puntaje_total = EXCLUDED.puntaje_total,
    clasificacion = EXCLUDED.clasificacion,
    clasificacion_anterior = EXCLUDED.clasificacion_anterior,
    total_ocs_periodo = EXCLUDED.total_ocs_periodo,
    monto_comprado = EXCLUDED.monto_comprado,
    fecha = EXCLUDED.fecha
  RETURNING id INTO v_eval_id;

  -- 7. Actualizar score en contacto
  UPDATE contactos SET
    score_proveedor = ROUND(v_puntaje_total, 2),
    clasificacion_proveedor = v_clasificacion,
    fecha_ultima_evaluacion = CURRENT_DATE
  WHERE id = p_proveedor_id;

  -- 8. Bloqueo automatico si aplica
  IF v_config.bloqueo_automatico AND v_puntaje_total < v_config.umbral_bloqueo THEN
    UPDATE contactos SET
      proveedor_bloqueado_score = true,
      motivo_bloqueo = 'Score de evaluacion por debajo del umbral (' ||
        ROUND(v_puntaje_total, 2)::TEXT || ' < ' || v_config.umbral_bloqueo::TEXT || ')'
    WHERE id = p_proveedor_id AND proveedor_bloqueado_score = false;
  ELSIF v_puntaje_total >= v_config.umbral_bloqueo THEN
    UPDATE contactos SET
      proveedor_bloqueado_score = false,
      motivo_bloqueo = NULL
    WHERE id = p_proveedor_id AND proveedor_bloqueado_score = true;
  END IF;

  -- 9. Alertas si cambio de clasificacion
  IF v_clasificacion_ant IS NOT NULL AND v_clasificacion != v_clasificacion_ant THEN
    IF v_config.notificar_caida AND v_clasificacion > v_clasificacion_ant THEN -- A < B < C < D < F (orden ASCII)
      PERFORM module_bus.send_notification(
        p_empresa_id := p_empresa_id,
        p_tipo := 'PROVEEDOR_CAIDA_SCORE',
        p_datos := jsonb_build_object(
          'proveedor_id', p_proveedor_id,
          'anterior', v_clasificacion_ant,
          'actual', v_clasificacion,
          'score', v_puntaje_total
        )
      );
    END IF;
    IF v_config.notificar_mejora AND v_clasificacion < v_clasificacion_ant THEN
      PERFORM module_bus.send_notification(
        p_empresa_id := p_empresa_id,
        p_tipo := 'PROVEEDOR_MEJORA_SCORE',
        p_datos := jsonb_build_object(
          'proveedor_id', p_proveedor_id,
          'anterior', v_clasificacion_ant,
          'actual', v_clasificacion,
          'score', v_puntaje_total
        )
      );
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'evaluacion_id', v_eval_id,
    'proveedor_id', p_proveedor_id,
    'periodo', v_periodo,
    'puntaje_total', ROUND(v_puntaje_total, 2),
    'clasificacion', v_clasificacion,
    'clasificacion_anterior', v_clasificacion_ant,
    'criterios', v_puntajes,
    'bloqueado', v_puntaje_total < v_config.umbral_bloqueo AND v_config.bloqueo_automatico
  );
END;
$$;

-- ============================================
-- EVALUACION MASIVA: Calcular score para TODOS los proveedores activos
-- Invocada por cron periodico
-- ============================================
CREATE OR REPLACE FUNCTION calculate_all_supplier_scores(
  p_empresa_id UUID,
  p_periodo VARCHAR DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_prov RECORD;
  v_resultados JSONB := '[]'::JSONB;
  v_resultado JSONB;
  v_count INTEGER := 0;
  v_errores INTEGER := 0;
BEGIN
  FOR v_prov IN
    SELECT id, razon_social
    FROM contactos
    WHERE empresa_id = p_empresa_id
      AND es_proveedor = true
      AND activo = true
  LOOP
    BEGIN
      v_resultado := calculate_supplier_score(p_empresa_id, v_prov.id, p_periodo);
      v_resultados := v_resultados || jsonb_build_object(
        'proveedor_id', v_prov.id,
        'razon_social', v_prov.razon_social,
        'score', v_resultado->>'puntaje_total',
        'clasificacion', v_resultado->>'clasificacion'
      );
      v_count := v_count + 1;
    EXCEPTION WHEN OTHERS THEN
      v_errores := v_errores + 1;
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'evaluados', v_count,
    'errores', v_errores,
    'resultados', v_resultados
  );
END;
$$;

-- ============================================
-- REGISTRAR EVALUACION MANUAL
-- ============================================
CREATE OR REPLACE FUNCTION register_manual_evaluation(
  p_empresa_id UUID,
  p_proveedor_id UUID,
  p_periodo VARCHAR,
  p_evaluaciones JSONB,  -- [{criterio_id, puntaje, comentario}]
  p_evaluador_id UUID,
  p_comentarios TEXT DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_eval JSONB;
  v_puntajes JSONB := '{}'::JSONB;
  v_puntaje_total DECIMAL(5,2) := 0;
  v_peso_total DECIMAL(5,2) := 0;
  v_criterio RECORD;
  v_eval_id UUID;
  v_clasificacion VARCHAR(1);
BEGIN
  -- Procesar cada criterio
  FOR v_eval IN SELECT * FROM jsonb_array_elements(p_evaluaciones)
  LOOP
    SELECT * INTO v_criterio FROM evaluacion_criterios
    WHERE id = (v_eval->>'criterio_id')::UUID AND empresa_id = p_empresa_id;

    IF v_criterio IS NOT NULL THEN
      v_puntajes := v_puntajes || jsonb_build_object(
        v_criterio.id::TEXT, jsonb_build_object(
          'codigo', v_criterio.codigo,
          'nombre', v_criterio.nombre,
          'puntaje', (v_eval->>'puntaje')::DECIMAL,
          'peso', v_criterio.peso,
          'ponderado', ROUND((v_eval->>'puntaje')::DECIMAL * v_criterio.peso / 100, 2),
          'comentario', v_eval->>'comentario'
        )
      );
      v_puntaje_total := v_puntaje_total + ((v_eval->>'puntaje')::DECIMAL * v_criterio.peso / 100);
      v_peso_total := v_peso_total + v_criterio.peso;
    END IF;
  END LOOP;

  -- Normalizar
  IF v_peso_total > 0 AND v_peso_total != 100 THEN
    v_puntaje_total := v_puntaje_total * 100 / v_peso_total;
  END IF;

  v_clasificacion := CASE
    WHEN v_puntaje_total >= 90 THEN 'A'
    WHEN v_puntaje_total >= 75 THEN 'B'
    WHEN v_puntaje_total >= 60 THEN 'C'
    WHEN v_puntaje_total >= 40 THEN 'D'
    ELSE 'F'
  END;

  -- Guardar evaluacion manual
  INSERT INTO evaluaciones_proveedor (
    empresa_id, proveedor_id, periodo, tipo,
    puntajes_criterios, puntaje_total, clasificacion,
    evaluador_id, comentarios, fecha
  ) VALUES (
    p_empresa_id, p_proveedor_id, p_periodo, 'MANUAL',
    v_puntajes, ROUND(v_puntaje_total, 2), v_clasificacion,
    p_evaluador_id, p_comentarios, CURRENT_DATE
  )
  ON CONFLICT (empresa_id, proveedor_id, periodo, tipo)
  DO UPDATE SET
    puntajes_criterios = EXCLUDED.puntajes_criterios,
    puntaje_total = EXCLUDED.puntaje_total,
    clasificacion = EXCLUDED.clasificacion,
    evaluador_id = EXCLUDED.evaluador_id,
    comentarios = EXCLUDED.comentarios
  RETURNING id INTO v_eval_id;

  -- Guardar detalle
  FOR v_eval IN SELECT * FROM jsonb_array_elements(p_evaluaciones)
  LOOP
    INSERT INTO evaluacion_manual_detalle (
      evaluacion_id, criterio_id, puntaje, comentario, evaluador_id
    ) VALUES (
      v_eval_id, (v_eval->>'criterio_id')::UUID,
      (v_eval->>'puntaje')::DECIMAL, v_eval->>'comentario', p_evaluador_id
    );
  END LOOP;

  -- Calcular score compuesto (automatico + manual)
  PERFORM calculate_composite_score(p_empresa_id, p_proveedor_id, p_periodo);

  RETURN v_eval_id;
END;
$$;

-- ============================================
-- SCORE COMPUESTO: Combina automatico + manual segun pesos configurados
-- ============================================
CREATE OR REPLACE FUNCTION calculate_composite_score(
  p_empresa_id UUID,
  p_proveedor_id UUID,
  p_periodo VARCHAR
) RETURNS DECIMAL
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_config RECORD;
  v_auto DECIMAL;
  v_manual DECIMAL;
  v_compuesto DECIMAL;
  v_clasificacion VARCHAR(1);
BEGIN
  SELECT * INTO v_config FROM evaluacion_config WHERE empresa_id = p_empresa_id;

  SELECT puntaje_total INTO v_auto
  FROM evaluaciones_proveedor
  WHERE empresa_id = p_empresa_id AND proveedor_id = p_proveedor_id
    AND periodo = p_periodo AND tipo = 'AUTOMATICA';

  SELECT puntaje_total INTO v_manual
  FROM evaluaciones_proveedor
  WHERE empresa_id = p_empresa_id AND proveedor_id = p_proveedor_id
    AND periodo = p_periodo AND tipo = 'MANUAL';

  IF v_auto IS NOT NULL AND v_manual IS NOT NULL THEN
    v_compuesto := (v_auto * v_config.peso_automatico + v_manual * v_config.peso_manual) / 100;
  ELSIF v_auto IS NOT NULL THEN
    v_compuesto := v_auto;
  ELSIF v_manual IS NOT NULL THEN
    v_compuesto := v_manual;
  ELSE
    RETURN NULL;
  END IF;

  v_clasificacion := CASE
    WHEN v_compuesto >= 90 THEN 'A'
    WHEN v_compuesto >= 75 THEN 'B'
    WHEN v_compuesto >= 60 THEN 'C'
    WHEN v_compuesto >= 40 THEN 'D'
    ELSE 'F'
  END;

  -- Guardar evaluacion compuesta
  INSERT INTO evaluaciones_proveedor (
    empresa_id, proveedor_id, periodo, tipo,
    puntajes_criterios, puntaje_total, clasificacion, fecha
  ) VALUES (
    p_empresa_id, p_proveedor_id, p_periodo, 'COMPUESTA',
    jsonb_build_object('automatico', v_auto, 'manual', v_manual,
      'peso_auto', v_config.peso_automatico, 'peso_manual', v_config.peso_manual),
    ROUND(v_compuesto, 2), v_clasificacion, CURRENT_DATE
  )
  ON CONFLICT (empresa_id, proveedor_id, periodo, tipo)
  DO UPDATE SET
    puntajes_criterios = EXCLUDED.puntajes_criterios,
    puntaje_total = EXCLUDED.puntaje_total,
    clasificacion = EXCLUDED.clasificacion;

  -- Actualizar contacto con score compuesto
  UPDATE contactos SET
    score_proveedor = ROUND(v_compuesto, 2),
    clasificacion_proveedor = v_clasificacion,
    fecha_ultima_evaluacion = CURRENT_DATE
  WHERE id = p_proveedor_id;

  RETURN v_compuesto;
END;
$$;
```

### Triggers

```sql
-- Al confirmar una OC, registrar fecha de entrega esperada (para calcular cumplimiento)
CREATE OR REPLACE FUNCTION tr_oc_track_delivery()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.estado = 'CONFIRMADA' AND OLD.estado = 'BORRADOR' THEN
    IF NEW.fecha_entrega_esperada IS NULL THEN
      NEW.fecha_entrega_esperada := NEW.fecha + 15; -- Default 15 dias
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tr_oc_set_delivery_date
  BEFORE UPDATE ON ordenes_compra
  FOR EACH ROW EXECUTE FUNCTION tr_oc_track_delivery();

-- Validar que proveedor no este bloqueado por score al crear OC
CREATE OR REPLACE FUNCTION tr_validate_proveedor_score()
RETURNS TRIGGER AS $$
DECLARE
  v_bloqueado BOOLEAN;
  v_razon TEXT;
BEGIN
  SELECT proveedor_bloqueado_score, motivo_bloqueo
  INTO v_bloqueado, v_razon
  FROM contactos WHERE id = NEW.contacto_id;

  IF v_bloqueado = true AND NEW.estado != 'CANCELADA' THEN
    RAISE EXCEPTION 'Proveedor bloqueado por score de evaluacion: %', COALESCE(v_razon, 'Score bajo');
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tr_validate_proveedor_score_on_oc
  BEFORE INSERT OR UPDATE ON ordenes_compra
  FOR EACH ROW EXECUTE FUNCTION tr_validate_proveedor_score();
```

### Vistas para Reportes

```sql
-- Ranking de proveedores con score actual
CREATE OR REPLACE VIEW v_ranking_proveedores AS
SELECT
  c.id AS proveedor_id,
  c.empresa_id,
  c.razon_social,
  c.identificacion,
  c.score_proveedor,
  c.clasificacion_proveedor,
  c.fecha_ultima_evaluacion,
  c.proveedor_bloqueado_score,
  (SELECT COUNT(*) FROM ordenes_compra oc
   WHERE oc.contacto_id = c.id AND oc.estado NOT IN ('BORRADOR', 'CANCELADA')
   AND oc.fecha >= CURRENT_DATE - INTERVAL '12 months') AS ocs_12_meses,
  (SELECT COALESCE(SUM(total), 0) FROM ordenes_compra oc
   WHERE oc.contacto_id = c.id AND oc.estado NOT IN ('BORRADOR', 'CANCELADA')
   AND oc.fecha >= CURRENT_DATE - INTERVAL '12 months') AS monto_12_meses
FROM contactos c
WHERE c.es_proveedor = true AND c.activo = true;

-- Historial de scores de un proveedor (para grafico de tendencia)
CREATE OR REPLACE VIEW v_historial_score_proveedor AS
SELECT
  ep.empresa_id,
  ep.proveedor_id,
  c.razon_social,
  ep.periodo,
  ep.tipo,
  ep.puntaje_total,
  ep.clasificacion,
  ep.clasificacion_anterior,
  ep.total_ocs_periodo,
  ep.monto_comprado,
  ep.fecha,
  ep.puntajes_criterios
FROM evaluaciones_proveedor ep
JOIN contactos c ON c.id = ep.proveedor_id
ORDER BY ep.fecha DESC;

-- Comparativo de proveedores por producto/categoria
CREATE OR REPLACE VIEW v_comparativo_proveedores_producto AS
SELECT
  pp.empresa_id,
  pp.producto_id,
  p.descripcion AS producto,
  p.categoria_id,
  cat.nombre AS categoria,
  pp.proveedor_id,
  c.razon_social AS proveedor,
  c.score_proveedor,
  c.clasificacion_proveedor,
  pp.precio_compra,
  pp.plazo_entrega,
  pp.es_preferido,
  pp.cantidad_minima
FROM producto_proveedores pp
JOIN productos p ON p.id = pp.producto_id
JOIN categorias cat ON cat.id = p.categoria_id
JOIN contactos c ON c.id = pp.proveedor_id
WHERE c.activo = true AND c.es_proveedor = true;
```

### Integracion Module Service Bus

```sql
-- Gateway: Solicitar evaluacion de proveedor desde otros modulos
CREATE OR REPLACE FUNCTION module_bus.evaluate_supplier(
  p_empresa_id UUID,
  p_proveedor_id UUID,
  p_periodo VARCHAR DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_activo BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM modulos_empresa me
    JOIN modulos m ON m.id = me.modulo_id
    WHERE me.empresa_id = p_empresa_id AND m.codigo = 'compras' AND me.activo = true
  ) INTO v_activo;

  IF NOT v_activo THEN
    RETURN jsonb_build_object('executed', false, 'reason', 'Modulo Compras inactivo');
  END IF;

  RETURN calculate_supplier_score(p_empresa_id, p_proveedor_id, p_periodo);
END;
$$;

-- Gateway: Consultar score de proveedor (read-only)
CREATE OR REPLACE FUNCTION module_bus.get_supplier_score(
  p_empresa_id UUID,
  p_proveedor_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN (
    SELECT jsonb_build_object(
      'score', score_proveedor,
      'clasificacion', clasificacion_proveedor,
      'bloqueado', proveedor_bloqueado_score,
      'fecha_evaluacion', fecha_ultima_evaluacion
    )
    FROM contactos
    WHERE id = p_proveedor_id AND empresa_id = p_empresa_id
  );
END;
$$;
```

### RLS Policies

| Tabla | Policy | Tipo |
|-------|--------|------|
| `evaluacion_criterios` | `tenant_isolation` | Directa: `empresa_id` |
| `evaluacion_config` | `tenant_isolation` | Directa: `empresa_id` |
| `evaluaciones_proveedor` | `tenant_isolation` | Directa: `empresa_id` |
| `inspecciones_calidad` | `tenant_isolation` | Directa: `empresa_id` |
| `evaluacion_manual_detalle` | Via JOIN a `evaluaciones_proveedor` | Heredada |

### Flujo UI/UX

```
PANTALLA RANKING PROVEEDORES:
  SfDataGrid: Proveedor | Score | Clasificacion | OCs 12m | Monto 12m | Ultima Eval | Estado
  Filtros: clasificacion (A/B/C/D/F), categoria producto, rango score
  Boton [Recalcular todos] -> ejecuta calculate_all_supplier_scores
  Color-coded: A=verde, B=azul, C=amarillo, D=naranja, F=rojo

PANTALLA DETALLE PROVEEDOR (tab Evaluacion):
  - Score gauge (0-100) con clasificacion prominente
  - Grafico radar (SfRadarChart) con puntaje por criterio
  - Grafico linea (SfCartesianChart) tendencia historica de score
  - Tabla criterios: Criterio | Peso | Puntaje | Ponderado | Datos
  - Boton [Evaluar manualmente] -> formulario con sliders 0-100 por criterio

PANTALLA CONFIGURACION EVALUACION:
  - Frecuencia automatica/manual (dropdowns)
  - Pesos automatico vs manual (sliders)
  - Umbrales de alerta y bloqueo
  - Toggle bloqueo automatico
  - Tabla de criterios con CRUD: Codigo | Nombre | Tipo | Metrica | Peso | Umbral | Activo

PANTALLA INSPECCIONES CALIDAD:
  SfDataGrid: OC | Proveedor | Producto | Cantidad | Aceptada | Rechazada | Resultado
  Formulario: seleccionar OC -> registrar cantidades aceptadas/rechazadas por producto

RESPONSIVE:
  - COMPACT: cards apiladas con gauge, sin radar
  - MEDIUM: radar + tendencia lado a lado
  - EXPANDED/LARGE: vista completa con todas las secciones
```

---

