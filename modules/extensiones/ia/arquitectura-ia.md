# Arquitectura IA Extendida


## Vision General

### Contexto

PILAR ya tiene planificada la infraestructura base de IA (seccion 11 del INFORME):
- **pgvector** con tabla `embeddings` (vector 1536) e indice ivfflat
- **Edge Functions**: `ai-query`, `ai-create-doc`, `ai-report`, `ai-embed`
- **OCR** de comprobantes electronicos (seccion 11.5)
- **Auto-categorizacion contable** con similarity search (seccion 11.6)
- **Conciliacion bancaria** asistida (seccion 11.7)
- **Agentes autonomos** via chat (seccion 11.8, P3)
- **Prediccion de demanda** basica: media movil + estacionalidad (seccion 11.9, P2)
- **Deteccion de anomalias** basica: 4 reglas (seccion 11.10, P2)
- **RAG** sobre documentos propios (seccion 11.11, P2)

**Lo que falta:** Casos de uso concretos con modelos de datos, funciones PostgreSQL, Edge Functions, vistas materializadas y flujos UI/UX detallados para cada area del ERP.

### Arquitectura IA Extendida

```
┌─────────────────────────────────────────────────────────────────────┐
│                        FLUTTER APP                                   │
│  ┌───────────┐ ┌───────────┐ ┌───────────┐ ┌───────────────────┐   │
│  │ Dashboard │ │ Widgets   │ │ Chat IA   │ │ Alertas/Notif.    │   │
│  │ IA KPIs   │ │ Predictivo│ │ NLP       │ │ Anomalias/Churn   │   │
│  └─────┬─────┘ └─────┬─────┘ └─────┬─────┘ └────────┬──────────┘   │
└────────┼──────────────┼─────────────┼────────────────┼──────────────┘
         │              │             │                │
         ▼              ▼             ▼                ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    EDGE FUNCTIONS (Deno/TS)                          │
│                                                                      │
│  CAPA 1: Entrada                                                     │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │ ai-gateway  → Router principal, auth, rate limiting          │    │
│  └──────────────────────────┬───────────────────────────────────┘    │
│                              │                                       │
│  CAPA 2: Servicios especializados                                    │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐                 │
│  │ ai-forecast  │ │ ai-anomaly   │ │ ai-chat      │                 │
│  │ (prediccion) │ │ (deteccion)  │ │ (NLP+acciones│                 │
│  └──────┬───────┘ └──────┬───────┘ └──────┬───────┘                 │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐                 │
│  │ ai-scoring   │ │ ai-cashflow  │ │ ai-hr        │                 │
│  │ (CRM/churn)  │ │ (proyeccion) │ │ (rrhh)       │                 │
│  └──────┬───────┘ └──────┬───────┘ └──────┬───────┘                 │
│                              │                                       │
│  CAPA 3: LLM/Embeddings                                             │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │ Claude API (claude-sonnet-4-20250514)                        │    │
│  │   - NLP → SQL/acciones                                       │    │
│  │   - Resumen ejecutivo                                        │    │
│  │   - Interpretacion de resultados                             │    │
│  │ Embeddings API (text-embedding-3-small, 1536 dim)            │    │
│  │   - Vectorizacion de contenido                               │    │
│  └──────────────────────────────────────────────────────────────┘    │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
┌──────────────────────────────┼──────────────────────────────────────┐
│              POSTGRESQL + pgvector                                   │
│                                                                      │
│  CAPA A: Datos transaccionales (tablas existentes)                   │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │ facturas, ventas, productos, contactos, stock, asientos...   │    │
│  └──────────────────────────────────────────────────────────────┘    │
│                                                                      │
│  CAPA B: Vistas materializadas (pre-calculos IA)                    │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │ mv_ventas_diarias, mv_demanda_producto, mv_abc_classification│    │
│  │ mv_cashflow_projection, mv_customer_metrics, mv_hr_patterns  │    │
│  └──────────────────────────────────────────────────────────────┘    │
│                                                                      │
│  CAPA C: IA persistente                                              │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │ embeddings, ia_predictions, ia_alerts, ia_conversations      │    │
│  │ ia_skills, ia_model_config, ia_feedback                      │    │
│  └──────────────────────────────────────────────────────────────┘    │
│                                                                      │
│  CAPA D: Funciones PostgreSQL (calculos pesados)                    │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │ fn_forecast_*, fn_anomaly_*, fn_scoring_*, fn_abc_*, fn_hr_* │    │
│  └──────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────┘
```

### Principios de Diseno IA

1. **PostgreSQL-first**: Los calculos estadisticos (medias, desviaciones, regresiones) se ejecutan en PostgreSQL con funciones `plpgsql`. Solo se llama a LLM externo para NLP, interpretacion y generacion de texto.
2. **Vistas materializadas**: Los datos agregados se pre-calculan en vistas materializadas con refresh programado (cron). Los widgets leen de estas vistas, no de queries ad-hoc.
3. **Multi-tenancy**: Toda tabla IA tiene `empresa_id` + RLS. Ningun dato cruza empresas.
4. **Feedback loop**: Cada prediccion/sugerencia permite feedback del usuario (aceptar/rechazar/corregir). Esto mejora los modelos con el tiempo.
5. **Costos controlados**: Las llamadas a LLM externo se minimizan. Usar embeddings pre-calculados y funciones SQL siempre que sea posible.
6. **Graceful degradation**: Si la API de LLM falla o no esta configurada, las funciones estadisticas SQL siguen funcionando. La IA es un upgrade, no un requisito.

---

## Modelo de Datos Comun IA

Tablas compartidas por todos los subsistemas de IA. Se suman a las tablas existentes de la seccion 11.

```sql
-- ============================================================
-- 22.2.1 CONFIGURACION DE MODELOS IA POR EMPRESA
-- ============================================================

CREATE TABLE ia_model_config (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  provider        VARCHAR(20) NOT NULL DEFAULT 'ANTHROPIC',
    -- ANTHROPIC, OPENAI, LOCAL (futuro)
  model_chat      VARCHAR(50) NOT NULL DEFAULT 'claude-sonnet-4-20250514',
  model_embeddings VARCHAR(50) NOT NULL DEFAULT 'text-embedding-3-small',
  api_key_vault   VARCHAR(100),
    -- Referencia al secret en Supabase Vault, NUNCA la key directa
  max_tokens_dia  INTEGER NOT NULL DEFAULT 50000,
    -- Limite diario de tokens para controlar costos
  tokens_usados_hoy INTEGER NOT NULL DEFAULT 0,
  fecha_reset_tokens DATE NOT NULL DEFAULT CURRENT_DATE,
  embeddings_habilitados BOOLEAN DEFAULT true,
  chat_habilitado BOOLEAN DEFAULT true,
  forecast_habilitado BOOLEAN DEFAULT true,
  anomalias_habilitado BOOLEAN DEFAULT true,
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now(),
  UNIQUE(empresa_id)
);

-- ============================================================
-- 22.2.2 PREDICCIONES IA (historico de todas las predicciones)
-- ============================================================

CREATE TABLE ia_predictions (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  tipo            VARCHAR(30) NOT NULL,
    -- FORECAST_VENTAS, FORECAST_DEMANDA, SCORING_CRM, CHURN_RISK,
    -- PRECIO_SUGERIDO, REORDER_POINT, ABC_CLASS, CASHFLOW,
    -- ANOMALIA_GASTO, AUSENTISMO, TURNO_OPTIMO
  source_table    VARCHAR(50),          -- tabla origen (productos, contactos, etc.)
  source_id       UUID,                 -- ID del registro (producto_id, contacto_id, etc.)
  periodo         VARCHAR(10),          -- '2026-03', '2026-W12', '2026-03-15'
  valor_predicho  DECIMAL(18,6),
  intervalo_bajo  DECIMAL(18,6),        -- banda de confianza inferior
  intervalo_alto  DECIMAL(18,6),        -- banda de confianza superior
  confianza       DECIMAL(5,4),         -- 0.0000 a 1.0000
  valor_real      DECIMAL(18,6),        -- se llena despues para calcular accuracy
  metadata        JSONB DEFAULT '{}',   -- datos adicionales del modelo
  created_at      TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_ia_predictions_empresa_tipo
  ON ia_predictions(empresa_id, tipo, periodo);
CREATE INDEX idx_ia_predictions_source
  ON ia_predictions(empresa_id, source_table, source_id);

ALTER TABLE ia_predictions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON ia_predictions
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT (auth.jwt() -> 'app_metadata' ->> 'empresa_id')::uuid));

-- ============================================================
-- 22.2.3 ALERTAS IA (extiende alertas_anomalias de seccion 11.10)
-- ============================================================

-- La tabla alertas_anomalias ya existe (seccion 11.10).
-- Se agregan nuevos tipos y campos:

ALTER TABLE alertas_anomalias
  ADD COLUMN IF NOT EXISTS modulo VARCHAR(30),
    -- VENTAS, INVENTARIO, CONTABILIDAD, RRHH
  ADD COLUMN IF NOT EXISTS subtipo VARCHAR(50),
    -- Para tipos mas granulares: CHURN_WARNING, OVERSTOCK, EXPENSE_SPIKE, etc.
  ADD COLUMN IF NOT EXISTS accion_sugerida TEXT,
    -- "Contactar al cliente X antes del viernes"
  ADD COLUMN IF NOT EXISTS prediction_id UUID REFERENCES ia_predictions(id),
  ADD COLUMN IF NOT EXISTS notificado BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS feedback VARCHAR(20);
    -- UTIL, NO_UTIL, FALSO_POSITIVO (feedback del usuario)

-- ============================================================
-- 22.2.4 FEEDBACK DE USUARIO SOBRE PREDICCIONES IA
-- ============================================================

CREATE TABLE ia_feedback (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  usuario_id      UUID NOT NULL REFERENCES auth.users(id),
  prediction_id   UUID REFERENCES ia_predictions(id),
  alert_id        UUID REFERENCES alertas_anomalias(id),
  tipo_feedback   VARCHAR(20) NOT NULL,
    -- ACEPTADO, RECHAZADO, CORREGIDO, UTIL, NO_UTIL, FALSO_POSITIVO
  valor_corregido DECIMAL(18,6),        -- si el usuario corrigio la prediccion
  comentario      TEXT,
  created_at      TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE ia_feedback ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON ia_feedback
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT (auth.jwt() -> 'app_metadata' ->> 'empresa_id')::uuid));

-- ============================================================
-- 22.2.5 USO DE TOKENS IA (control de costos)
-- ============================================================

CREATE TABLE ia_token_usage (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  usuario_id      UUID REFERENCES auth.users(id),
  edge_function   VARCHAR(50) NOT NULL,   -- 'ai-forecast', 'ai-chat', etc.
  provider        VARCHAR(20) NOT NULL,    -- 'ANTHROPIC', 'OPENAI'
  model           VARCHAR(50) NOT NULL,
  tokens_input    INTEGER NOT NULL DEFAULT 0,
  tokens_output   INTEGER NOT NULL DEFAULT 0,
  costo_estimado  DECIMAL(10,6) DEFAULT 0, -- USD estimado
  created_at      TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_ia_token_usage_empresa_fecha
  ON ia_token_usage(empresa_id, created_at);

ALTER TABLE ia_token_usage ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON ia_token_usage
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT (auth.jwt() -> 'app_metadata' ->> 'empresa_id')::uuid));

-- ============================================================
-- 22.2.6 CALENDARIO ESTACIONAL ECUADOR
-- ============================================================

CREATE TABLE ia_calendario_estacional (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID REFERENCES empresas(id),
    -- NULL = global (aplica a todas las empresas)
  nombre          VARCHAR(80) NOT NULL,
  tipo            VARCHAR(20) NOT NULL,
    -- NACIONAL, REGIONAL, COMERCIAL, RELIGIOSO, ESCOLAR
  mes             SMALLINT NOT NULL CHECK (mes BETWEEN 1 AND 12),
  dia_inicio      SMALLINT,             -- NULL si aplica todo el mes
  dia_fin         SMALLINT,
  factor_demanda  DECIMAL(5,2) NOT NULL DEFAULT 1.00,
    -- 1.00 = normal, 1.50 = 50% mas demanda, 0.70 = 30% menos
  aplica_categorias JSONB,
    -- NULL = todas, o ["ELECTRONICA","ROPA","JUGUETES"]
  notas           TEXT
);

-- Seed de eventos estacionales Ecuador (datos globales, empresa_id = NULL)
INSERT INTO ia_calendario_estacional
  (empresa_id, nombre, tipo, mes, dia_inicio, dia_fin, factor_demanda, aplica_categorias) VALUES
  (NULL, 'Navidad y Fin de Anio',          'COMERCIAL', 12, 1,  31, 2.00, NULL),
  (NULL, 'Dia de la Madre',                'COMERCIAL',  5, 1,  15, 1.80, '["ROPA","COSMETICA","JOYERIA","ELECTRONICA","FLORES"]'),
  (NULL, 'Dia del Padre',                  'COMERCIAL',  6, 10, 20, 1.30, '["ELECTRONICA","ROPA","HERRAMIENTAS","LICORES"]'),
  (NULL, 'Dia del Nino',                   'COMERCIAL',  6, 1,  5,  1.50, '["JUGUETES","ROPA_INFANTIL"]'),
  (NULL, 'Black Friday / Cyber Monday',    'COMERCIAL', 11, 20, 30, 1.70, NULL),
  (NULL, 'Regreso a Clases Sierra',        'ESCOLAR',   8, 15, 31, 1.60, '["UTILES_ESCOLARES","UNIFORMES","MOCHILAS","TECNOLOGIA"]'),
  (NULL, 'Regreso a Clases Costa',         'ESCOLAR',   4, 1,  15, 1.60, '["UTILES_ESCOLARES","UNIFORMES","MOCHILAS","TECNOLOGIA"]'),
  (NULL, 'Carnaval',                       'RELIGIOSO', 2, NULL, NULL, 1.20, '["ALIMENTOS","BEBIDAS","TURISMO"]'),
  (NULL, 'San Valentin',                   'COMERCIAL', 2, 10, 15, 1.40, '["FLORES","CHOCOLATES","JOYERIA","ROPA"]'),
  (NULL, 'Fiestas de Quito',               'REGIONAL', 12, 1,  6,  1.20, NULL),
  (NULL, 'Fiestas de Guayaquil',           'REGIONAL', 10, 1,  12, 1.20, NULL),
  (NULL, 'Semana Santa',                   'RELIGIOSO', 3, NULL, NULL, 0.80, '["ELECTRONICA","HERRAMIENTAS"]'),
  (NULL, 'Enero (post-Navidad)',           'COMERCIAL', 1, 1,  31, 0.60, NULL);

-- ============================================================
-- 22.2.7 FUNCION HELPER: Factor estacional para fecha y categoria
-- ============================================================

CREATE OR REPLACE FUNCTION fn_factor_estacional(
  p_empresa_id UUID,
  p_fecha DATE,
  p_categoria VARCHAR DEFAULT NULL
) RETURNS DECIMAL(5,2)
LANGUAGE plpgsql STABLE SECURITY DEFINER AS $$
DECLARE
  v_factor DECIMAL(5,2) := 1.00;
  v_mes SMALLINT := EXTRACT(MONTH FROM p_fecha);
  v_dia SMALLINT := EXTRACT(DAY FROM p_fecha);
BEGIN
  SELECT COALESCE(MAX(factor_demanda), 1.00) INTO v_factor
  FROM ia_calendario_estacional
  WHERE (empresa_id IS NULL OR empresa_id = p_empresa_id)
    AND mes = v_mes
    AND (dia_inicio IS NULL OR v_dia >= dia_inicio)
    AND (dia_fin IS NULL OR v_dia <= dia_fin)
    AND (
      aplica_categorias IS NULL
      OR p_categoria IS NULL
      OR aplica_categorias ? p_categoria
    );

  RETURN v_factor;
END;
$$;
```

---

