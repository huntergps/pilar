# IA para Contabilidad y Finanzas

> **Nota**: Las funciones IA de Contabilidad leen directamente desde tablas del módulo Contabilidad.
> Para proyecciones que requieren datos de otros módulos (CxC de Ventas, CxP de Compras),
> se verifican activaciones en `modulos_empresa` antes de acceder a esas tablas (nunca JOINs sin guard).
> Los modelos predictivos avanzados (`alertas_anomalias`, `ia_predictions`) residen en el módulo **IA/Chat**.

## Descripcion Funcional

El subsistema de IA para Contabilidad y Finanzas complementa las capacidades existentes (seccion 11.6 Auto-categorizacion contable y 11.7 Conciliacion bancaria) con tres capacidades adicionales:

1. **Deteccion de anomalias en gastos:** Identificacion de gastos inusualmente altos respecto al promedio historico, facturas potencialmente duplicadas (mismo proveedor, monto similar, fechas cercanas) y patrones sospechosos (descuentos excesivos, horarios inusuales).

2. **Categorizacion automatica de transacciones:** Ampliacion de la auto-categorizacion existente (11.6). Sugerencia de cuenta contable basada en descripcion, proveedor y monto, con aprendizaje continuo de las correcciones del usuario.

3. **Proyeccion de flujo de caja:** Calculo prospectivo de ingresos y egresos basado en CxC pendientes (con probabilidad de cobro por historial del cliente), CxP comprometidas, nomina futura, impuestos y gastos recurrentes. Output visual a 30/60/90 dias con alertas de deficit.

> **Dependencias externas:**
> - `alertas_anomalias`: definida en el módulo **IA/Chat** — tabla central de alertas del sistema.
> - `ia_predictions`: definida en el módulo **IA/Chat** — historial de predicciones ML.
> - Las funciones de este archivo insertan en esas tablas vía acceso directo (misma base de datos).
> - Si el módulo IA/Chat no está activo, los INSERT fallarán silenciosamente con ON CONFLICT DO NOTHING.

## Modelo de Datos - Contabilidad IA

```sql
-- ============================================================
-- VISTA MATERIALIZADA: Gastos por proveedor/cuenta (base para anomalias)
-- ============================================================

CREATE MATERIALIZED VIEW mv_gastos_historico AS
SELECT
  al.empresa_id,
  a.contacto_id,
  c.nombre AS proveedor_nombre,
  al.cuenta_id,
  cc.codigo AS cuenta_codigo,
  cc.nombre AS cuenta_nombre,
  DATE(a.fecha) AS fecha,
  EXTRACT(MONTH FROM a.fecha) AS mes,
  EXTRACT(YEAR FROM a.fecha) AS anio,
  SUM(al.debe) AS total_debe,
  COUNT(*) AS num_lineas,
  AVG(al.debe) AS promedio_linea,
  STDDEV(al.debe) AS stddev_linea,
  a.descripcion
FROM asiento_lineas al
JOIN asientos_contables a ON a.id = al.asiento_id
JOIN cuentas_contables cc ON cc.id = al.cuenta_id
LEFT JOIN contactos c ON c.id = a.contacto_id
WHERE al.debe > 0
  AND cc.tipo IN ('GASTO', 'COSTO')
GROUP BY al.empresa_id, a.contacto_id, c.nombre, al.cuenta_id,
         cc.codigo, cc.nombre, DATE(a.fecha),
         EXTRACT(MONTH FROM a.fecha), EXTRACT(YEAR FROM a.fecha),
         a.descripcion
WITH DATA;

CREATE INDEX idx_mv_gastos_historico_empresa
  ON mv_gastos_historico(empresa_id, cuenta_id, fecha);
CREATE INDEX idx_mv_gastos_historico_proveedor
  ON mv_gastos_historico(empresa_id, contacto_id, fecha);

-- ============================================================
-- FUNCIÓN: Proyeccion de flujo de caja (con module_bus guards)
-- ============================================================
-- ANTES era MATERIALIZED VIEW — convertida a función para evitar dependencias rígidas de schema
-- La función verifica dinámicamente qué módulos están activos antes de acceder a sus tablas
CREATE OR REPLACE FUNCTION get_cashflow_projection(
  p_empresa_id UUID,
  p_dias       INTEGER DEFAULT 90
) RETURNS TABLE (
  fecha                  DATE,
  ingresos_proyectados   DECIMAL(14,2),
  egresos_proyectados    DECIMAL(14,2),
  saldo_neto_dia         DECIMAL(14,2)
) LANGUAGE plpgsql SECURITY DEFINER AS $
DECLARE
  v_ventas_active  BOOLEAN;
  v_compras_active BOOLEAN;
BEGIN
  -- Verificar módulos activos (nunca asumir — siempre verificar)
  SELECT EXISTS (
    SELECT 1 FROM modulos_empresa
    WHERE empresa_id = p_empresa_id AND modulo_id = 'ventas' AND activo = true
  ) INTO v_ventas_active;

  SELECT EXISTS (
    SELECT 1 FROM modulos_empresa
    WHERE empresa_id = p_empresa_id AND modulo_id = 'compras' AND activo = true
  ) INTO v_compras_active;

  RETURN QUERY
  WITH dias AS (
    SELECT generate_series(
      CURRENT_DATE,
      CURRENT_DATE + p_dias,
      '1 day'::interval
    )::DATE AS fecha
  ),
  flujos_cxc AS (
    -- Ingresos proyectados desde CxC (solo si Ventas activo)
    SELECT
      fecha_vencimiento::DATE AS fecha,
      monto_pendiente         AS monto
    FROM cuentas_por_cobrar
    WHERE empresa_id = p_empresa_id
      AND estado IN ('PENDIENTE', 'PARCIAL')
      AND fecha_vencimiento BETWEEN CURRENT_DATE AND CURRENT_DATE + p_dias
      AND v_ventas_active  -- Guard: si Ventas no activo, esta CTE retorna vacío
  ),
  flujos_cxp AS (
    -- Egresos proyectados desde CxP (solo si Compras activo)
    SELECT
      fecha_vencimiento::DATE AS fecha,
      monto_pendiente         AS monto
    FROM cuentas_por_pagar
    WHERE empresa_id = p_empresa_id
      AND estado IN ('PENDIENTE', 'PARCIAL')
      AND fecha_vencimiento BETWEEN CURRENT_DATE AND CURRENT_DATE + p_dias
      AND v_compras_active  -- Guard: si Compras no activo, esta CTE retorna vacío
  )
  SELECT
    d.fecha,
    COALESCE(SUM(cxc.monto), 0)::DECIMAL(14,2) AS ingresos_proyectados,
    COALESCE(SUM(cxp.monto), 0)::DECIMAL(14,2) AS egresos_proyectados,
    (COALESCE(SUM(cxc.monto), 0) - COALESCE(SUM(cxp.monto), 0))::DECIMAL(14,2) AS saldo_neto_dia
  FROM dias d
  LEFT JOIN flujos_cxc cxc ON cxc.fecha = d.fecha
  LEFT JOIN flujos_cxp cxp ON cxp.fecha = d.fecha
  GROUP BY d.fecha
  ORDER BY d.fecha;
END;
$;

-- ============================================================
-- TABLA: Patrones de gasto recurrente (detectados por IA)
-- ============================================================

CREATE TABLE ia_gastos_recurrentes (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  contacto_id     UUID REFERENCES contactos(id),
  cuenta_id       UUID REFERENCES cuentas_contables(id),
  descripcion     VARCHAR(200),
  monto_promedio  DECIMAL(14,2) NOT NULL,
  frecuencia_dias INTEGER NOT NULL,
  proximo_esperado DATE,
  confianza       DECIMAL(5,4),
  activo          BOOLEAN DEFAULT true,
  created_at      TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE ia_gastos_recurrentes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON ia_gastos_recurrentes
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));
```

## Funciones PostgreSQL - Contabilidad IA

```sql
-- ============================================================
-- FN_DETECTAR_ANOMALIAS_GASTOS
-- ============================================================

CREATE OR REPLACE FUNCTION fn_detectar_anomalias_gastos(
  p_empresa_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_count INTEGER := 0;
BEGIN
  -- ANOMALIA 1: Gasto inusualmente alto (>3 stddev sobre promedio por cuenta)
  INSERT INTO alertas_anomalias
    (empresa_id, tipo, severidad, descripcion, datos, modulo, subtipo, accion_sugerida)
  SELECT
    p_empresa_id,
    'MONTO_INUSUAL',
    CASE
      WHEN g.total_debe > stats.avg_gasto * 5 THEN 'ALTA'
      WHEN g.total_debe > stats.avg_gasto * 3 THEN 'MEDIA'
      ELSE 'BAJA'
    END,
    FORMAT('Gasto inusual en cuenta %s (%s): $%s vs promedio $%s (%sx)',
      g.cuenta_codigo, g.cuenta_nombre, ROUND(g.total_debe, 2),
      ROUND(stats.avg_gasto, 2), ROUND(g.total_debe / NULLIF(stats.avg_gasto, 0), 1)),
    jsonb_build_object(
      'cuenta_id', g.cuenta_id, 'cuenta_codigo', g.cuenta_codigo,
      'monto', g.total_debe, 'promedio', ROUND(stats.avg_gasto, 2),
      'fecha', g.fecha, 'proveedor', g.proveedor_nombre),
    'CONTABILIDAD', 'GASTO_INUSUAL',
    FORMAT('Revisar gasto de $%s en %s. Es %sx el promedio.',
      ROUND(g.total_debe, 2), g.cuenta_nombre,
      ROUND(g.total_debe / NULLIF(stats.avg_gasto, 0), 1))
  FROM mv_gastos_historico g
  JOIN (
    SELECT empresa_id, cuenta_id,
      AVG(total_debe) AS avg_gasto,
      STDDEV(total_debe) AS stddev_gasto
    FROM mv_gastos_historico
    WHERE empresa_id = p_empresa_id AND fecha >= CURRENT_DATE - 365
    GROUP BY empresa_id, cuenta_id
    HAVING COUNT(*) >= 5
  ) stats ON stats.empresa_id = g.empresa_id AND stats.cuenta_id = g.cuenta_id
  WHERE g.empresa_id = p_empresa_id
    AND g.fecha >= CURRENT_DATE - 7
    AND g.total_debe > stats.avg_gasto + (3 * stats.stddev_gasto)
  ON CONFLICT DO NOTHING;

  -- ANOMALIA 2: Facturas potencialmente duplicadas
  -- Solo ejecuta si el módulo Compras está activo (lee de facturas_proveedor)
  IF EXISTS (
    SELECT 1 FROM modulos_empresa
    WHERE empresa_id = p_empresa_id AND modulo_id = 'compras' AND activo = true
  ) THEN
    INSERT INTO alertas_anomalias
      (empresa_id, tipo, severidad, descripcion, datos, modulo, subtipo, accion_sugerida)
    SELECT
      p_empresa_id,
      'FACTURA_DUPLICADA',
      'ALTA',
      FORMAT('Posible duplicado: proveedor %s, monto $%s, fechas %s y %s',
        c.nombre, ROUND(f1.total, 2), f1.fecha_emision::DATE, f2.fecha_emision::DATE),
      jsonb_build_object(
        'factura_1_id', f1.id, 'factura_1_num', f1.numero_documento,
        'factura_2_id', f2.id, 'factura_2_num', f2.numero_documento,
        'proveedor', c.nombre, 'monto', f1.total),
      'CONTABILIDAD', 'DUPLICADO_POTENCIAL',
      FORMAT('Verificar facturas proveedor %s y %s de %s por $%s.',
        f1.numero_documento, f2.numero_documento, c.nombre, ROUND(f1.total, 2))
    FROM facturas_proveedor f1
    JOIN facturas_proveedor f2 ON f1.proveedor_id = f2.proveedor_id
      AND f1.empresa_id = f2.empresa_id
      AND f1.id < f2.id
      AND ABS(f1.total - f2.total) < 0.01
      AND ABS(EXTRACT(EPOCH FROM (f1.fecha_emision - f2.fecha_emision))) < 86400 * 5
    JOIN contactos c ON c.id = f1.proveedor_id
    WHERE f1.empresa_id = p_empresa_id
      AND f1.estado NOT IN ('ANULADA')
      AND f2.estado NOT IN ('ANULADA')
      AND f1.fecha_emision >= CURRENT_DATE - 30
    ON CONFLICT DO NOTHING;
  END IF;

  -- ANOMALIA 3: Descuentos excesivos (>30%) en facturas de ventas
  -- Solo ejecuta si el módulo Facturación está activo
  IF EXISTS (
    SELECT 1 FROM modulos_empresa
    WHERE empresa_id = p_empresa_id AND modulo_id = 'facturacion' AND activo = true
  ) THEN
    INSERT INTO alertas_anomalias
      (empresa_id, tipo, severidad, descripcion, datos, modulo, subtipo, accion_sugerida)
    SELECT
      p_empresa_id,
      'DESCUENTO_EXCESIVO',
      'MEDIA',
      FORMAT('Descuento del %s%% en factura %s para %s',
        ROUND(f.descuento_total / NULLIF(f.subtotal, 0) * 100, 1),
        f.numero_documento, c.nombre),
      jsonb_build_object(
        'factura_id', f.id, 'numero', f.numero_documento,
        'subtotal', f.subtotal, 'descuento', f.descuento_total,
        'pct', ROUND(f.descuento_total / NULLIF(f.subtotal, 0) * 100, 1)),
      'CONTABILIDAD', 'DESCUENTO_EXCESIVO',
      FORMAT('Revisar factura %s con descuento del %s%%.',
        f.numero_documento,
        ROUND(f.descuento_total / NULLIF(f.subtotal, 0) * 100, 1))
    FROM facturas f
    JOIN contactos c ON c.id = f.cliente_id  -- facturas de ventas usan cliente_id
    WHERE f.empresa_id = p_empresa_id
      -- facturas tabla es siempre ventas: no necesita filtro es_compra ni tipo_documento
      AND f.estado = 'AUTORIZADA'
      AND f.fecha_emision >= CURRENT_DATE - 7
      AND f.descuento_total > 0
      AND f.descuento_total / NULLIF(f.subtotal, 0) > 0.30
    ON CONFLICT DO NOTHING;
  END IF;

  GET DIAGNOSTICS v_count = ROW_COUNT;

  RETURN jsonb_build_object('anomalias_detectadas', v_count);
END;
$$;

-- ============================================================
-- FN_PROYECCION_FLUJO_CAJA
-- ============================================================

CREATE OR REPLACE FUNCTION fn_proyeccion_flujo_caja(
  p_empresa_id UUID,
  p_horizonte_dias INTEGER DEFAULT 90
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_resultado JSONB := '[]'::JSONB;
  v_dia DATE;
  v_ingresos_dia DECIMAL;
  v_egresos_dia DECIMAL;
  v_saldo_acumulado DECIMAL := 0;
  v_saldo_banco_actual DECIMAL;
  v_nomina_mensual DECIMAL;
  v_gastos_recurrentes DECIMAL;
  v_alerta_deficit BOOLEAN := false;
  v_fecha_deficit DATE;
  i INTEGER;
BEGIN
  -- Saldo bancario actual (solo si Tesorería activo)
  v_saldo_banco_actual := 0;
  IF EXISTS (
    SELECT 1 FROM modulos_empresa
    WHERE empresa_id = p_empresa_id AND modulo_id = 'tesoreria' AND activo = true
  ) THEN
    SELECT COALESCE(SUM(saldo_actual), 0) INTO v_saldo_banco_actual
    FROM cuentas_bancarias
    WHERE empresa_id = p_empresa_id AND activa = true;
  END IF;

  v_saldo_acumulado := v_saldo_banco_actual;

  -- Nómina mensual estimada (solo si RRHH activo)
  v_nomina_mensual := 0;
  IF EXISTS (
    SELECT 1 FROM modulos_empresa
    WHERE empresa_id = p_empresa_id AND modulo_id = 'rrhh' AND activo = true
  ) THEN
    SELECT COALESCE(AVG(total_nomina), 0) INTO v_nomina_mensual
    FROM (
      SELECT SUM(total_pagar) AS total_nomina
      FROM roles_pago
      WHERE empresa_id = p_empresa_id AND fecha >= CURRENT_DATE - 90
      GROUP BY EXTRACT(MONTH FROM fecha), EXTRACT(YEAR FROM fecha)
    ) sub;
  END IF;

  -- Gastos recurrentes detectados
  SELECT COALESCE(SUM(monto_promedio * 30.0 / NULLIF(frecuencia_dias, 0)), 0)
  INTO v_gastos_recurrentes
  FROM ia_gastos_recurrentes
  WHERE empresa_id = p_empresa_id AND activo = true;

  -- Materializar proyección una sola vez (evita recalcular en cada iteración del loop)
  CREATE TEMP TABLE _cashflow_dias ON COMMIT DROP AS
    SELECT fecha, ingresos_proyectados, egresos_proyectados
    FROM get_cashflow_projection(p_empresa_id, p_horizonte_dias);

  -- Proyectar dia a dia
  FOR i IN 0..p_horizonte_dias LOOP
    v_dia := CURRENT_DATE + i;

    SELECT COALESCE(ingresos_proyectados, 0) INTO v_ingresos_dia
    FROM _cashflow_dias WHERE fecha = v_dia;

    SELECT COALESCE(egresos_proyectados, 0) INTO v_egresos_dia
    FROM _cashflow_dias WHERE fecha = v_dia;

    v_egresos_dia := v_egresos_dia + (v_nomina_mensual / 30.0) + (v_gastos_recurrentes / 30.0);
    v_saldo_acumulado := v_saldo_acumulado + v_ingresos_dia - v_egresos_dia;

    IF v_saldo_acumulado < 0 AND NOT v_alerta_deficit THEN
      v_alerta_deficit := true;
      v_fecha_deficit := v_dia;

      INSERT INTO alertas_anomalias
        (empresa_id, tipo, severidad, descripcion, datos, modulo, subtipo, accion_sugerida)
      VALUES
        (p_empresa_id, 'MONTO_INUSUAL', 'ALTA',
         FORMAT('Deficit de caja proyectado: $%s el %s (en %s dias)',
           ROUND(ABS(v_saldo_acumulado), 2), v_dia, i),
         jsonb_build_object('fecha', v_dia, 'deficit', ROUND(ABS(v_saldo_acumulado), 2), 'dias', i),
         'CONTABILIDAD', 'DEFICIT_CASHFLOW',
         FORMAT('En %s dias el flujo sera negativo. Acelerar cobros o diferir pagos.', i))
      ON CONFLICT DO NOTHING;
    END IF;

    IF i <= 30 OR EXTRACT(DOW FROM v_dia) = 1 OR i = p_horizonte_dias THEN
      v_resultado := v_resultado || jsonb_build_object(
        'fecha', v_dia, 'dia', i,
        'ingresos', ROUND(v_ingresos_dia, 2),
        'egresos', ROUND(v_egresos_dia, 2),
        'neto', ROUND(v_ingresos_dia - v_egresos_dia, 2),
        'saldo_acumulado', ROUND(v_saldo_acumulado, 2)
      );
    END IF;
  END LOOP;

  INSERT INTO ia_predictions
    (empresa_id, tipo, source_table, source_id, valor_predicho,
     intervalo_bajo, intervalo_alto, confianza, metadata)
  VALUES
    (p_empresa_id, 'CASHFLOW', 'empresa', p_empresa_id,
     v_saldo_acumulado, v_saldo_acumulado * 0.80, v_saldo_acumulado * 1.20, 0.65,
     jsonb_build_object('horizonte', p_horizonte_dias, 'saldo_inicial', v_saldo_banco_actual,
       'nomina', ROUND(v_nomina_mensual, 2), 'deficit', v_alerta_deficit));

  RETURN jsonb_build_object(
    'proyeccion', v_resultado,
    'resumen', jsonb_build_object(
      'saldo_actual', ROUND(v_saldo_banco_actual, 2),
      'saldo_final', ROUND(v_saldo_acumulado, 2),
      'deficit_proyectado', v_alerta_deficit,
      'fecha_deficit', v_fecha_deficit,
      'nomina_mensual', ROUND(v_nomina_mensual, 2),
      'gastos_recurrentes', ROUND(v_gastos_recurrentes, 2)
    )
  );
END;
$$;
```

## Flujo UI/UX - Contabilidad IA

```
PANTALLA: Dashboard IA Finanzas (dentro del modulo Contabilidad/Tesoreria)
├── Tab: Anomalias Gastos
│   ├── Panel de alertas tipo "inbox" con badges por severidad
│   ├── Cada alerta: Tipo | Descripcion | Monto | Proveedor | Accion
│   ├── Acciones: "Revisar" (abre asiento) | "Descartar" | "Confirmar fraude"
│   ├── Filtros: [Tipo: Gasto inusual / Duplicado / Descuento excesivo] [Periodo]
│   └── KPI: Total alertas | Monto potencialmente fraudulento
│
├── Tab: Categorizacion
│   ├── Lista de transacciones sin cuenta asignada
│   ├── Cada item: Descripcion | Proveedor | Monto | Top 3 sugerencias IA
│   ├── Click sugerencia → asigna cuenta (feedback positivo)
│   ├── Click "Otra cuenta" → selector manual (feedback corrector)
│   └── Indicador: % acierto historico del modelo
│
└── Tab: Flujo de Caja
    ├── Grafico area (Syncfusion SfCartesianChart):
    │   - Area verde: ingresos proyectados (CxC ponderados)
    │   - Area roja: egresos proyectados (CxP + nomina + recurrentes)
    │   - Linea negra: saldo acumulado
    │   - Linea roja horizontal: $0 (zona deficit)
    │   - Marcador: punto de deficit (si existe)
    ├── KPI cards: Saldo actual | Saldo 30d | Saldo 60d | Saldo 90d
    ├── Semaforo: Verde (positivo 90d) | Amarillo (deficit >60d) | Rojo (deficit <30d)
    └── Boton: "Interpretar con IA" → resumen ejecutivo LLM
```

---

