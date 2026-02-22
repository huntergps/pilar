# Edge Functions IA Consolidadas

## Resumen de Edge Functions

Resumen de todas las Edge Functions del subsistema IA:

| Edge Function | Endpoint | Tipo | Descripcion |
|---------------|----------|------|-------------|
| `ai-gateway` | POST /functions/v1/ai-gateway | Router | Gateway principal: auth, rate limiting, routing a funciones especializadas |
| `ai-forecast` | POST /functions/v1/ai-forecast | Cron + On-demand | Forecast ventas, scoring CRM, deteccion churn, precios sugeridos |
| `ai-anomaly` | POST /functions/v1/ai-anomaly | Cron semanal | Deteccion de anomalias (stock, gastos, duplicados, descuentos) |
| `ai-chat` | POST /functions/v1/ai-chat | On-demand | Chat conversacional NLP → SQL/Acciones |
| `ai-cashflow` | POST /functions/v1/ai-cashflow | On-demand + Cron | Proyeccion de flujo de caja |
| `ai-hr` | POST /functions/v1/ai-hr | Cron mensual | Prediccion ausentismo, HE anomalas |
| `ai-embed` | POST /functions/v1/ai-embed | Trigger | Genera embeddings (ya existente, seccion 11.4) |
| `ai-query` | POST /functions/v1/ai-query | On-demand | Consultas RAG (ya existente, seccion 11.3) |
| `ai-refresh-mv` | POST /functions/v1/ai-refresh-mv | Cron diario 02:00 | Refresh de vistas materializadas IA |

## Cron Jobs (pg_cron o Supabase Scheduled Functions)

```sql
-- Refresh diario de vistas materializadas (02:00 AM Ecuador = 07:00 UTC)
SELECT cron.schedule('ai_refresh_mv_ventas', '0 7 * * *',
  'REFRESH MATERIALIZED VIEW CONCURRENTLY mv_ventas_diarias');
SELECT cron.schedule('ai_refresh_mv_demanda', '5 7 * * *',
  'REFRESH MATERIALIZED VIEW CONCURRENTLY mv_demanda_producto');
SELECT cron.schedule('ai_refresh_mv_customers', '10 7 * * *',
  'REFRESH MATERIALIZED VIEW CONCURRENTLY mv_customer_metrics');
SELECT cron.schedule('ai_refresh_mv_gastos', '15 7 * * *',
  'REFRESH MATERIALIZED VIEW CONCURRENTLY mv_gastos_historico');
SELECT cron.schedule('ai_refresh_mv_cashflow', '20 7 * * *',
  'REFRESH MATERIALIZED VIEW CONCURRENTLY mv_cashflow_projection');
SELECT cron.schedule('ai_refresh_mv_hr', '25 7 * * *',
  'REFRESH MATERIALIZED VIEW CONCURRENTLY mv_hr_attendance_patterns');
SELECT cron.schedule('ai_refresh_mv_overtime', '30 7 * * *',
  'REFRESH MATERIALIZED VIEW CONCURRENTLY mv_hr_overtime');

-- Refresh mensual de ABC (primer dia del mes)
SELECT cron.schedule('ai_refresh_mv_abc', '0 8 1 * *',
  'REFRESH MATERIALIZED VIEW CONCURRENTLY mv_abc_classification');

-- Deteccion de anomalias semanal (lunes 06:00 AM Ecuador)
SELECT cron.schedule('ai_detect_anomalies', '0 11 * * 1',
  $$SELECT fn_detectar_anomalias_stock(e.id), fn_detectar_anomalias_gastos(e.id)
    FROM empresas e WHERE e.activo = true$$);

-- Scoring CRM semanal (lunes 07:00 AM Ecuador)
SELECT cron.schedule('ai_scoring_crm', '0 12 * * 1',
  $$SELECT fn_scoring_crm(e.id) FROM empresas e WHERE e.activo = true$$);

-- Deteccion churn quincenal (dia 1 y 15 de cada mes)
SELECT cron.schedule('ai_detect_churn', '0 12 1,15 * *',
  $$SELECT fn_detectar_churn(e.id) FROM empresas e WHERE e.activo = true$$);

-- RRHH mensual (dia 1)
SELECT cron.schedule('ai_hr_monthly', '0 13 1 * *',
  $$SELECT fn_prediccion_ausentismo(e.id), fn_detectar_horas_extras_anomalas(e.id)
    FROM empresas e WHERE e.activo = true$$);

-- Reset de tokens diario
SELECT cron.schedule('ai_reset_tokens', '0 5 * * *',
  $$UPDATE ia_model_config SET tokens_usados_hoy = 0,
    fecha_reset_tokens = CURRENT_DATE
    WHERE fecha_reset_tokens < CURRENT_DATE$$);
```

---

## Integracion Module Service Bus

Todas las funciones IA se integran via Module Service Bus para respetar la arquitectura modular de PILAR. El modulo IA (id: `ia_chat`) es un modulo **auxiliar**: funciona independientemente de que otros modulos esten activos.

```sql
-- ============================================================
-- MODULE BUS: Servicios IA
-- ============================================================

-- Gateway IA: otros modulos solicitan analisis IA
CREATE OR REPLACE FUNCTION module_bus.request_ia_analysis(
  p_empresa_id UUID,
  p_tipo VARCHAR(30),
    -- FORECAST_VENTAS, SCORING_CRM, CHURN, REABASTECIMIENTO,
    -- ANOMALIA_STOCK, ANOMALIA_GASTOS, CASHFLOW, AUSENTISMO, HE_ANOMALAS
  p_parametros JSONB DEFAULT '{}'
) RETURNS module_bus.bus_response
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_result module_bus.bus_response;
  v_data JSONB;
BEGIN
  IF NOT module_bus.is_module_active(p_empresa_id, 'ia_chat') THEN
    v_result.executed := false;
    v_result.reason := 'module_inactive';
    v_result.module := 'ia_chat';
    v_result.data := null;
    RETURN v_result;
  END IF;

  -- Verificar que la empresa tenga IA habilitada
  IF NOT EXISTS (SELECT 1 FROM ia_model_config WHERE empresa_id = p_empresa_id) THEN
    v_result.executed := false;
    v_result.reason := 'ia_not_configured';
    v_result.module := 'ia_chat';
    RETURN v_result;
  END IF;

  -- Despachar al analisis correspondiente
  CASE p_tipo
    WHEN 'FORECAST_VENTAS' THEN
      v_data := fn_forecast_ventas(p_empresa_id,
        (p_parametros->>'producto_id')::UUID,
        (p_parametros->>'categoria_id')::UUID,
        COALESCE((p_parametros->>'horizonte')::INTEGER, 30),
        COALESCE(p_parametros->>'granularidad', 'DIARIO'));
    WHEN 'SCORING_CRM' THEN
      v_data := fn_scoring_crm(p_empresa_id, (p_parametros->>'oportunidad_id')::UUID);
    WHEN 'CHURN' THEN
      v_data := fn_detectar_churn(p_empresa_id);
    WHEN 'REABASTECIMIENTO' THEN
      v_data := fn_reabastecimiento_inteligente(p_empresa_id,
        (p_parametros->>'producto_id')::UUID);
    WHEN 'ANOMALIA_STOCK' THEN
      v_data := fn_detectar_anomalias_stock(p_empresa_id);
    WHEN 'ANOMALIA_GASTOS' THEN
      v_data := fn_detectar_anomalias_gastos(p_empresa_id);
    WHEN 'CASHFLOW' THEN
      v_data := fn_proyeccion_flujo_caja(p_empresa_id,
        COALESCE((p_parametros->>'horizonte')::INTEGER, 90));
    WHEN 'AUSENTISMO' THEN
      v_data := fn_prediccion_ausentismo(p_empresa_id);
    WHEN 'HE_ANOMALAS' THEN
      v_data := fn_detectar_horas_extras_anomalas(p_empresa_id);
    ELSE
      v_result.executed := false;
      v_result.reason := 'tipo_no_soportado';
      v_result.module := 'ia_chat';
      RETURN v_result;
  END CASE;

  v_result.executed := true;
  v_result.reason := null;
  v_result.module := 'ia_chat';
  v_result.data := v_data;
  RETURN v_result;
END;
$$;

-- ============================================================
-- Ejemplo de uso desde otros modulos:
-- ============================================================

-- Desde modulo Dashboard al cargar pantalla principal:
-- SELECT module_bus.request_ia_analysis(empresa_id, 'FORECAST_VENTAS', '{"horizonte": 7}');
-- SELECT module_bus.request_ia_analysis(empresa_id, 'CHURN', '{}');

-- Desde modulo Inventario al revisar stock bajo:
-- SELECT module_bus.request_ia_analysis(empresa_id, 'REABASTECIMIENTO', '{"producto_id": "uuid"}');

-- Desde modulo Contabilidad al abrir conciliacion:
-- SELECT module_bus.request_ia_analysis(empresa_id, 'CASHFLOW', '{"horizonte": 30}');

-- Desde modulo RRHH al revisar asistencia:
-- SELECT module_bus.request_ia_analysis(empresa_id, 'AUSENTISMO', '{}');
```

---

