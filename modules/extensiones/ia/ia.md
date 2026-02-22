# Módulo IA/Chat — Inteligencia Artificial

**Tipo:** Auxiliar #13
**Activable por empresa:** Si
**Depende de:** Core Foundation (siempre); Ventas, Compras, Inventario, Contabilidad, Tesorería, RRHH (guards por modulos_empresa)
**Provee servicios a:** Todos los módulos via `module_bus.request_ia_analysis()`

---

## 1. Descripción del Módulo

IA/Chat activa capacidades de inteligencia artificial en toda la plataforma PILAR. Cuando está habilitado por una empresa, los demás módulos pueden solicitar análisis predictivos, detección de anomalías y búsqueda semántica a través del Module Service Bus. El módulo también expone un widget de Chat NLP accesible desde cualquier pantalla.

### Capacidades principales

| Capacidad | Descripción | Módulos que se benefician |
|-----------|-------------|--------------------------|
| **Chat NLP** | Preguntas en lenguaje natural, acciones via chat | Todos |
| **Forecasting de ventas** | Media móvil + estacionalidad Ecuador, horizonte configurable | Dashboard, Ventas, Inventario |
| **Reabastecimiento inteligente** | ROP óptimo con stock de seguridad y lead time | Inventario |
| **Clasificación ABC dinámica** | Recalculo mensual por valor de rotación real | Inventario |
| **Detección de anomalías contables** | Gastos inusuales, duplicados, descuentos excesivos | Contabilidad, Compras |
| **Detección de anomalías de stock** | Stock negativo, sobrestock, merma inusual, sin rotación | Inventario |
| **Scoring CRM** | Probabilidad de cierre de oportunidades (ML + reglas) | CRM, Ventas |
| **Detección de churn** | Clientes con riesgo de abandono | Ventas, CRM |
| **Proyección de flujo de caja** | Horizonte 30/60/90 días con alertas de déficit | Tesorería, Contabilidad |
| **Categorización contable** | Sugerencia de cuenta contable por similaridad semántica | Contabilidad |
| **Conciliación bancaria asistida** | Matching automático líneas bancarias vs movimientos ERP | Tesorería |
| **OCR de comprobantes** | Extracción estructurada de RIDEs y facturas físicas | Compras |
| **Predicción de ausentismo RRHH** | Patrones históricos por empleado/departamento | RRHH |
| **Búsqueda semántica** | Embeddings vectoriales sobre documentos, productos, contactos | Todos |
| **RAG sobre documentos propios** | Plan de cuentas, catálogos, normativas SRI | Contabilidad, Chat |

### Principios de diseño

1. **PostgreSQL-first:** Los cálculos estadísticos (medias, desviaciones, regresiones, clasificación ABC) se ejecutan en PostgreSQL con funciones `plpgsql`. Solo se llama a LLM externo para NLP, interpretación y generación de texto.
2. **Vistas materializadas:** Los datos agregados se pre-calculan con refresh programado (pg_cron). Los widgets leen de estas vistas, no de queries ad-hoc sobre tablas transaccionales.
3. **Multi-tenancy estricto:** Toda tabla IA tiene `empresa_id` + RLS con `private.get_empresa_id()`. Ningún dato cruza entre empresas.
4. **Feedback loop:** Cada predicción/sugerencia permite feedback del usuario (aceptar/rechazar/corregir). El campo `valor_real` en `ia_predictions` se llena después para calcular accuracy.
5. **Costos controlados:** Las llamadas a LLM se minimizan. Límite diario configurable por empresa. Embeddings en batch nocturno, no en tiempo real.
6. **Graceful degradation:** Si la API LLM falla o no está configurada, las funciones estadísticas SQL siguen funcionando. La IA es un upgrade, no un requisito.
7. **Confirmación obligatoria:** Cualquier acción que modifique datos requiere confirmación explícita del usuario. El chat nunca ejecuta acciones destructivas automáticamente.

---

## 2. Arquitectura

```
┌─────────────────────────────────────────────────────────────────────┐
│                        FLUTTER APP                                   │
│  ┌───────────┐ ┌───────────┐ ┌───────────┐ ┌───────────────────┐   │
│  │ Dashboard │ │ Widgets   │ │ Chat IA   │ │ Alertas/Notif.    │   │
│  │ IA KPIs   │ │ Predictivo│ │ NLP       │ │ Anomalías/Churn   │   │
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
│  │ ai-chat      │ │ ai-forecast  │ │ ai-anomaly   │                 │
│  │ (NLP+acciones│ │ (ventas/CRM) │ │ (stock/gastos│                 │
│  └──────────────┘ └──────────────┘ └──────────────┘                 │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐                 │
│  │ ai-cashflow  │ │ ai-hr        │ │ ai-embed     │                 │
│  │ (tesorería)  │ │ (rrhh)       │ │ (vectores)   │                 │
│  └──────────────┘ └──────────────┘ └──────────────┘                 │
│                                                                      │
│  CAPA 3: LLM/Embeddings                                             │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │ Anthropic Claude (claude-sonnet-4-20250514)                   │    │
│  │   - NLP → SQL/acciones                                        │    │
│  │   - Resumen ejecutivo                                         │    │
│  │   - Interpretación de resultados                              │    │
│  │ OpenAI Embeddings (text-embedding-3-small, 1536 dim)          │    │
│  │   - Vectorización de contenido                                │    │
│  └──────────────────────────────────────────────────────────────┘    │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
┌──────────────────────────────┼──────────────────────────────────────┐
│              POSTGRESQL + pgvector                                   │
│                                                                      │
│  CAPA A: Datos transaccionales (tablas existentes de otros módulos)  │
│  facturas, ventas, productos, contactos, stock, asientos...          │
│                                                                      │
│  CAPA B: Vistas materializadas (pre-cálculos IA, refresh diario)    │
│  mv_ventas_diarias, mv_demanda_producto, mv_abc_classification       │
│  mv_gastos_historico, mv_customer_metrics, mv_hr_attendance_patterns │
│                                                                      │
│  CAPA C: Tablas IA propias                                           │
│  ia_embeddings, ia_conversaciones, ia_mensajes, ia_predictions       │
│  alertas_anomalias, ia_feedback, ia_agentes, ia_model_config         │
│  ia_token_usage, ia_skills, ia_calendario_estacional                 │
│  ia_reabastecimiento_config, ia_anomalias_stock, ia_gastos_recurrentes│
│                                                                      │
│  CAPA D: Funciones PostgreSQL (cálculos pesados, sin LLM)           │
│  fn_forecast_ventas, fn_scoring_crm, fn_detectar_churn               │
│  fn_reabastecimiento_inteligente, fn_detectar_anomalias_stock        │
│  fn_detectar_anomalias_gastos, fn_proyeccion_flujo_caja              │
│  fn_prediccion_ausentismo, fn_factor_estacional                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 3. Modelo de Datos SQL Completo

### 3.1 Extensión pgvector y configuración

```sql
-- Extensión requerida (habilitar en Supabase dashboard o migration)
CREATE EXTENSION IF NOT EXISTS vector;
```

### 3.2 Configuración de modelos IA por empresa

```sql
CREATE TABLE ia_model_config (
  id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id             UUID NOT NULL REFERENCES empresas(id),
  provider               VARCHAR(20) NOT NULL DEFAULT 'ANTHROPIC',
    -- ANTHROPIC, OPENAI, LOCAL (futuro)
  model_chat             VARCHAR(50) NOT NULL DEFAULT 'claude-sonnet-4-20250514',
  model_embeddings       VARCHAR(50) NOT NULL DEFAULT 'text-embedding-3-small',
  api_key_vault          VARCHAR(100),
    -- Referencia al secret en Supabase Vault. NUNCA la API key directa en esta tabla.
  max_tokens_dia         INTEGER NOT NULL DEFAULT 50000,
    -- Límite diario de tokens para controlar costos
  tokens_usados_hoy      INTEGER NOT NULL DEFAULT 0,
  fecha_reset_tokens     DATE NOT NULL DEFAULT CURRENT_DATE,
  embeddings_habilitados BOOLEAN DEFAULT true,
  chat_habilitado        BOOLEAN DEFAULT true,
  forecast_habilitado    BOOLEAN DEFAULT true,
  anomalias_habilitado   BOOLEAN DEFAULT true,
  created_at             TIMESTAMPTZ DEFAULT now(),
  updated_at             TIMESTAMPTZ DEFAULT now(),
  UNIQUE(empresa_id)
);

ALTER TABLE ia_model_config ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON ia_model_config
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));
```

### 3.3 Embeddings vectoriales para búsqueda semántica

```sql
CREATE TABLE ia_embeddings (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id    UUID NOT NULL REFERENCES empresas(id),
  tabla_origen  VARCHAR(50) NOT NULL,
    -- 'productos', 'facturas', 'contactos', 'asiento_lineas', 'rag_documents', etc.
  registro_id   UUID NOT NULL,
    -- FK lógica al registro original (no FK física para flexibilidad)
  campo_origen  VARCHAR(50) NOT NULL DEFAULT 'contenido',
    -- Campo que fue vectorizado: 'nombre', 'descripcion', 'descripcion_asiento', etc.
  contenido     TEXT NOT NULL,
    -- Texto original que fue vectorizado (para mostrar en resultados)
  embedding     vector(1536) NOT NULL,
    -- Vector OpenAI text-embedding-3-small (1536 dimensiones)
  modelo        VARCHAR(50) NOT NULL DEFAULT 'text-embedding-3-small',
  metadata      JSONB DEFAULT '{}',
    -- {categoria, proveedor_nombre, fecha, cuenta_codigo, etc.}
  created_at    TIMESTAMPTZ DEFAULT now(),
  updated_at    TIMESTAMPTZ DEFAULT now()
);

-- Índice HNSW para búsqueda aproximada rápida (mejor que IVFFlat para datasets < 1M)
CREATE INDEX idx_ia_embeddings_hnsw ON ia_embeddings
  USING hnsw (embedding vector_cosine_ops)
  WITH (m = 16, ef_construction = 64);

-- Índice para filtrado por empresa y tabla (siempre filtrar primero por empresa_id)
CREATE INDEX idx_ia_embeddings_empresa_tabla
  ON ia_embeddings(empresa_id, tabla_origen);

-- Índice para actualización incremental por registro
CREATE UNIQUE INDEX idx_ia_embeddings_registro
  ON ia_embeddings(empresa_id, tabla_origen, registro_id, campo_origen);

ALTER TABLE ia_embeddings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON ia_embeddings
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));
```

### 3.4 Conversaciones del chat NLP

```sql
CREATE TABLE ia_conversaciones (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id       UUID NOT NULL REFERENCES empresas(id),
  usuario_id       UUID NOT NULL REFERENCES auth.users(id),
  titulo           VARCHAR(200),
    -- Generado automáticamente del primer mensaje o manual
  estado           VARCHAR(10) NOT NULL DEFAULT 'ACTIVA'
    CHECK (estado IN ('ACTIVA', 'ARCHIVADA')),
  contexto_modulo  VARCHAR(30),
    -- Módulo desde donde se abrió el chat: 'VENTAS', 'INVENTARIO', 'CONTABILIDAD', etc.
  metadata         JSONB DEFAULT '{}',
    -- {device, screen_path, filtros_activos, etc.}
  created_at       TIMESTAMPTZ DEFAULT now(),
  updated_at       TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_ia_conversaciones_usuario
  ON ia_conversaciones(empresa_id, usuario_id, estado, created_at DESC);

ALTER TABLE ia_conversaciones ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON ia_conversaciones
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- ---

CREATE TABLE ia_mensajes (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id       UUID NOT NULL REFERENCES empresas(id),
  conversacion_id  UUID NOT NULL REFERENCES ia_conversaciones(id) ON DELETE CASCADE,
  rol              VARCHAR(10) NOT NULL
    CHECK (rol IN ('USUARIO', 'ASISTENTE', 'SISTEMA')),
  contenido        TEXT NOT NULL,
  skill_id         VARCHAR(50) REFERENCES ia_skills(id),
    -- Skill ejecutado por este mensaje (si aplica)
  sql_ejecutado    TEXT,
    -- SQL que fue ejecutado (para auditoría)
  resultado_data   JSONB,
    -- Datos devueltos por la consulta SQL o RPC
  tokens_usados    INTEGER DEFAULT 0,
    -- tokens_input + tokens_output combinados
  tokens_input     INTEGER DEFAULT 0,
  tokens_output    INTEGER DEFAULT 0,
  modelo           VARCHAR(50),
  latencia_ms      INTEGER,
  metadata         JSONB DEFAULT '{}',
  created_at       TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_ia_mensajes_conversacion
  ON ia_mensajes(conversacion_id, created_at ASC);

ALTER TABLE ia_mensajes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON ia_mensajes
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));
```

### 3.5 Predicciones IA (histórico unificado)

```sql
CREATE TABLE ia_predictions (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  tipo            VARCHAR(30) NOT NULL,
    -- FORECAST_VENTAS, FORECAST_DEMANDA, SCORING_CRM, CHURN_RISK,
    -- PRECIO_SUGERIDO, REORDER_POINT, ABC_CLASS, CASHFLOW,
    -- ANOMALIA_GASTO, AUSENTISMO, TURNO_OPTIMO, CLASIFICACION_DOC
  referencia_tipo VARCHAR(50),
    -- Tabla del registro referenciado: 'productos', 'contactos', 'empresa', etc.
  referencia_id   UUID,
    -- ID del registro (producto_id, contacto_id, etc.)
  periodo         VARCHAR(10),
    -- '2026-03', '2026-W12', '2026-03-15' — periodo al que aplica la predicción
  valor_predicho  DECIMAL(18,6),
  intervalo_bajo  DECIMAL(18,6),
    -- Banda de confianza inferior
  intervalo_alto  DECIMAL(18,6),
    -- Banda de confianza superior
  confianza       DECIMAL(5,4),
    -- 0.0000 a 1.0000
  valor_real      DECIMAL(18,6),
    -- Se llena después para calcular accuracy del modelo
  modelo_version  VARCHAR(20) DEFAULT 'v1',
  metadata        JSONB DEFAULT '{}',
    -- Datos adicionales del modelo (hiperparámetros, datos usados, etc.)
  calculado_at    TIMESTAMPTZ DEFAULT now(),
  valido_hasta    TIMESTAMPTZ
    -- Expiración de la predicción (NULL = vigente indefinidamente)
);

CREATE INDEX idx_ia_predictions_empresa_tipo
  ON ia_predictions(empresa_id, tipo, periodo);
CREATE INDEX idx_ia_predictions_referencia
  ON ia_predictions(empresa_id, referencia_tipo, referencia_id);
CREATE INDEX idx_ia_predictions_calculado
  ON ia_predictions(empresa_id, calculado_at DESC);

ALTER TABLE ia_predictions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON ia_predictions
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));
```

### 3.6 Alertas de anomalías

```sql
CREATE TABLE alertas_anomalias (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id       UUID NOT NULL REFERENCES empresas(id),
  tipo             VARCHAR(50) NOT NULL,
    -- FACTURA_DUPLICADA, MONTO_INUSUAL, DESCUENTO_EXCESIVO, HORARIO_INUSUAL,
    -- STOCK_NEGATIVO, SIN_ROTACION, SOBRESTOCK, MERMA_INUSUAL, REABASTECIMIENTO,
    -- CHURN_WARNING, DEFICIT_CASHFLOW, GASTO_INUSUAL, DUPLICADO_POTENCIAL,
    -- HE_ANOMALAS (horas extras anómalas)
  severidad        VARCHAR(10) NOT NULL
    CHECK (severidad IN ('INFO', 'BAJA', 'MEDIA', 'ALTA', 'CRITICAL')),
  modulo           VARCHAR(30),
    -- VENTAS, INVENTARIO, CONTABILIDAD, RRHH, TESORERIA, CRM
  subtipo          VARCHAR(50),
    -- Subtipo más granular: CHURN_WARNING, OVERSTOCK, EXPENSE_SPIKE, etc.
  descripcion      TEXT NOT NULL,
  datos            JSONB DEFAULT '{}',
    -- Datos específicos: {documento_id, contacto_id, monto, umbral, etc.}
  accion_sugerida  TEXT,
    -- "Contactar al cliente X antes del viernes"
  referencia_id    UUID,
    -- ID del registro afectado (factura, producto, empleado, etc.)
  referencia_tipo  VARCHAR(50),
    -- Tabla del registro: 'facturas', 'productos', 'empleados'
  prediction_id    UUID REFERENCES ia_predictions(id),
  estado           VARCHAR(15) DEFAULT 'NUEVA'
    CHECK (estado IN ('NUEVA', 'REVISADA', 'RESUELTA', 'FALSO_POSITIVO')),
  revisado_por     UUID REFERENCES auth.users(id),
  feedback         VARCHAR(20),
    -- UTIL, NO_UTIL, FALSO_POSITIVO (feedback del usuario sobre la alerta)
  notificado       BOOLEAN DEFAULT false,
    -- Si ya fue enviada por email/WhatsApp via Comunicación
  created_at       TIMESTAMPTZ DEFAULT now(),
  updated_at       TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_alertas_empresa_estado
  ON alertas_anomalias(empresa_id, estado, created_at DESC);
CREATE INDEX idx_alertas_empresa_modulo
  ON alertas_anomalias(empresa_id, modulo, severidad);

ALTER TABLE alertas_anomalias ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON alertas_anomalias
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));
```

### 3.7 Feedback del usuario sobre predicciones

```sql
CREATE TABLE ia_feedback (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  usuario_id      UUID NOT NULL REFERENCES auth.users(id),
  prediction_id   UUID REFERENCES ia_predictions(id),
  alert_id        UUID REFERENCES alertas_anomalias(id),
  tipo_feedback   VARCHAR(20) NOT NULL
    CHECK (tipo_feedback IN ('ACEPTADO', 'RECHAZADO', 'CORREGIDO', 'UTIL', 'NO_UTIL', 'FALSO_POSITIVO')),
  valor_corregido DECIMAL(18,6),
    -- Si el usuario corrigió la predicción, valor real que ingresó
  comentario      TEXT,
  created_at      TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_ia_feedback_prediction
  ON ia_feedback(empresa_id, prediction_id);

ALTER TABLE ia_feedback ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON ia_feedback
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));
```

### 3.8 Agentes de IA (tareas automáticas)

```sql
CREATE TABLE ia_agentes (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id          UUID NOT NULL REFERENCES empresas(id),
  nombre              VARCHAR(100) NOT NULL,
  tipo                VARCHAR(30) NOT NULL
    CHECK (tipo IN ('CLASIFICADOR', 'FORECASTER', 'CHAT', 'ANOMALIA_DETECTOR', 'EMBEDDER')),
  configuracion       JSONB DEFAULT '{}',
    -- Parámetros específicos del agente: modelo, umbrales, módulos objetivo
  activo              BOOLEAN DEFAULT true,
  ultima_ejecucion    TIMESTAMPTZ,
  proxima_ejecucion   TIMESTAMPTZ,
    -- Para agentes con cron propio (además de pg_cron global)
  total_ejecuciones   INTEGER DEFAULT 0,
  errores_consecutivos INTEGER DEFAULT 0,
  created_at          TIMESTAMPTZ DEFAULT now(),
  updated_at          TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE ia_agentes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON ia_agentes
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));
```

### 3.9 Control de consumo de tokens

```sql
CREATE TABLE ia_token_usage (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  usuario_id      UUID REFERENCES auth.users(id),
  edge_function   VARCHAR(50) NOT NULL,
    -- 'ai-chat', 'ai-forecast', 'ai-anomaly', 'ai-embed', etc.
  provider        VARCHAR(20) NOT NULL,
    -- 'ANTHROPIC', 'OPENAI'
  model           VARCHAR(50) NOT NULL,
  tokens_input    INTEGER NOT NULL DEFAULT 0,
  tokens_output   INTEGER NOT NULL DEFAULT 0,
  costo_estimado  DECIMAL(10,6) DEFAULT 0,
    -- USD estimado según pricing del provider
  created_at      TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_ia_token_usage_empresa_fecha
  ON ia_token_usage(empresa_id, created_at DESC);

ALTER TABLE ia_token_usage ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON ia_token_usage
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));
```

### 3.10 Skills del chat IA

```sql
CREATE TABLE ia_skills (
  id                    VARCHAR(50) PRIMARY KEY,
    -- 'query_ventas', 'query_stock', 'create_cotizacion', 'resumen_dia', etc.
  nombre                VARCHAR(100) NOT NULL,
  descripcion           TEXT NOT NULL,
    -- Descripción usada como contexto para el LLM al clasificar intents
  categoria             VARCHAR(20) NOT NULL
    CHECK (categoria IN ('CONSULTA', 'ACCION', 'RESUMEN', 'REPORTE')),
  modulo                VARCHAR(30) NOT NULL,
    -- VENTAS, INVENTARIO, CONTABILIDAD, CRM, RRHH, GENERAL
  requiere_confirmacion BOOLEAN DEFAULT false,
    -- true para acciones que modifican datos (crear, aprobar, etc.)
  sql_template          TEXT,
    -- Template SQL con placeholders $1, $2... ($1 siempre = empresa_id)
  rpc_function          VARCHAR(100),
    -- Nombre de la función RPC para acciones (cuando no usa sql_template)
  parametros            JSONB NOT NULL DEFAULT '[]',
    -- [{nombre, tipo, descripcion, requerido, default}]
  ejemplos_input        JSONB NOT NULL DEFAULT '[]',
    -- ["Cuánto vendimos ayer?", "Ventas del mes", ...]
  activo                BOOLEAN DEFAULT true,
  permisos              JSONB DEFAULT '["authenticated"]'
    -- Roles requeridos para usar este skill
);

-- (Ver chat-nlp.md para el seed completo de skills)
```

### 3.11 Calendario estacional Ecuador

```sql
CREATE TABLE ia_calendario_estacional (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id        UUID REFERENCES empresas(id),
    -- NULL = global (aplica a todas las empresas)
  nombre            VARCHAR(80) NOT NULL,
  tipo              VARCHAR(20) NOT NULL
    CHECK (tipo IN ('NACIONAL', 'REGIONAL', 'COMERCIAL', 'RELIGIOSO', 'ESCOLAR')),
  mes               SMALLINT NOT NULL CHECK (mes BETWEEN 1 AND 12),
  dia_inicio        SMALLINT,
    -- NULL si aplica todo el mes
  dia_fin           SMALLINT,
  factor_demanda    DECIMAL(5,2) NOT NULL DEFAULT 1.00,
    -- 1.00=normal, 1.50=50% más demanda, 0.70=30% menos
  aplica_categorias JSONB,
    -- NULL=todas, o ["ELECTRONICA","ROPA","JUGUETES"]
  notas             TEXT
);

-- Seed de eventos estacionales Ecuador (empresa_id = NULL = globales)
INSERT INTO ia_calendario_estacional
  (empresa_id, nombre, tipo, mes, dia_inicio, dia_fin, factor_demanda, aplica_categorias) VALUES
  (NULL, 'Navidad y Fin de Año',       'COMERCIAL', 12, 1,  31, 2.00, NULL),
  (NULL, 'Día de la Madre',            'COMERCIAL',  5, 1,  15, 1.80, '["ROPA","COSMETICA","JOYERIA","ELECTRONICA","FLORES"]'),
  (NULL, 'Día del Padre',              'COMERCIAL',  6, 10, 20, 1.30, '["ELECTRONICA","ROPA","HERRAMIENTAS","LICORES"]'),
  (NULL, 'Día del Niño',               'COMERCIAL',  6, 1,   5, 1.50, '["JUGUETES","ROPA_INFANTIL"]'),
  (NULL, 'Black Friday / Cyber Monday','COMERCIAL', 11, 20, 30, 1.70, NULL),
  (NULL, 'Regreso a Clases Sierra',    'ESCOLAR',    8, 15, 31, 1.60, '["UTILES_ESCOLARES","UNIFORMES","MOCHILAS","TECNOLOGIA"]'),
  (NULL, 'Regreso a Clases Costa',     'ESCOLAR',    4, 1,  15, 1.60, '["UTILES_ESCOLARES","UNIFORMES","MOCHILAS","TECNOLOGIA"]'),
  (NULL, 'Carnaval',                   'RELIGIOSO',  2, NULL,NULL,1.20,'["ALIMENTOS","BEBIDAS","TURISMO"]'),
  (NULL, 'San Valentín',               'COMERCIAL',  2, 10, 15, 1.40, '["FLORES","CHOCOLATES","JOYERIA","ROPA"]'),
  (NULL, 'Fiestas de Quito',           'REGIONAL',  12, 1,   6, 1.20, NULL),
  (NULL, 'Fiestas de Guayaquil',       'REGIONAL',  10, 1,  12, 1.20, NULL),
  (NULL, 'Semana Santa',               'RELIGIOSO',  3, NULL,NULL,0.80,'["ELECTRONICA","HERRAMIENTAS"]'),
  (NULL, 'Enero (post-Navidad)',        'COMERCIAL',  1, 1,  31, 0.60, NULL);
```

### 3.12 Tablas auxiliares de inventario IA

```sql
-- Configuración de reabastecimiento por producto (ver ia-inventario.md para detalles)
CREATE TABLE ia_reabastecimiento_config (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id              UUID NOT NULL REFERENCES empresas(id),
  producto_id             UUID NOT NULL REFERENCES productos(id),
  nivel_servicio          DECIMAL(5,4) NOT NULL DEFAULT 0.9500,
    -- Z-score: 0.90=1.28, 0.95=1.65, 0.99=2.33
  lead_time_proveedor_dias INTEGER,
  proveedor_preferido_id  UUID REFERENCES contactos(id),
  metodo_forecast         VARCHAR(20) DEFAULT 'MEDIA_MOVIL',
    -- MEDIA_MOVIL, MEDIA_PONDERADA, HOLT_WINTERS
  dias_media_movil        INTEGER DEFAULT 30,
  auto_crear_oc           BOOLEAN DEFAULT false,
  activo                  BOOLEAN DEFAULT true,
  updated_at              TIMESTAMPTZ DEFAULT now(),
  UNIQUE(empresa_id, producto_id)
);

ALTER TABLE ia_reabastecimiento_config ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON ia_reabastecimiento_config
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- ---

-- Anomalías de stock detectadas (tabla especializada, además de alertas_anomalias)
CREATE TABLE ia_anomalias_stock (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  producto_id     UUID NOT NULL REFERENCES productos(id),
  bodega_id       UUID REFERENCES bodegas(id),
  tipo_anomalia   VARCHAR(30) NOT NULL
    CHECK (tipo_anomalia IN (
      'MERMA_INUSUAL', 'SOBRESTOCK', 'STOCK_NEGATIVO', 'DISCREPANCIA_FISICO',
      'SIN_ROTACION', 'CONSUMO_SIN_DOCUMENTO', 'LEAD_TIME_EXCEDIDO'
    )),
  severidad       VARCHAR(5) NOT NULL CHECK (severidad IN ('BAJA','MEDIA','ALTA')),
  descripcion     TEXT NOT NULL,
  datos           JSONB DEFAULT '{}',
    -- {stock_actual, stock_esperado, diferencia, dias_sin_movimiento, valor_inmovilizado}
  estado          VARCHAR(15) DEFAULT 'PENDIENTE'
    CHECK (estado IN ('PENDIENTE', 'INVESTIGADA', 'RESUELTA', 'DESCARTADA')),
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
  USING (empresa_id = (SELECT private.get_empresa_id()));
```

### 3.13 Tablas auxiliares de contabilidad IA

```sql
-- Patrones de gasto recurrente detectados por IA
CREATE TABLE ia_gastos_recurrentes (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id       UUID NOT NULL REFERENCES empresas(id),
  contacto_id      UUID REFERENCES contactos(id),
  cuenta_id        UUID REFERENCES cuentas_contables(id),
  descripcion      VARCHAR(200),
  monto_promedio   DECIMAL(14,2) NOT NULL,
  frecuencia_dias  INTEGER NOT NULL,
  proximo_esperado DATE,
  confianza        DECIMAL(5,4),
  activo           BOOLEAN DEFAULT true,
  created_at       TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE ia_gastos_recurrentes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON ia_gastos_recurrentes
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));
```

### 3.14 RAG — documentos propios indexados

```sql
CREATE TABLE ia_rag_documents (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id  UUID NOT NULL REFERENCES empresas(id),
  tipo        VARCHAR(20) NOT NULL
    CHECK (tipo IN ('PLAN_CUENTAS', 'CATALOGO', 'NORMATIVA', 'POLITICA', 'MANUAL')),
    -- PLAN_CUENTAS: cuenta.codigo+nombre+descripcion → sugerencia de cuentas
    -- CATALOGO: producto.nombre+descripcion+categoria → búsqueda semántica
    -- NORMATIVA: regulaciones SRI (IVA, retenciones, plazos) → Q&A cumplimiento
    -- POLITICA: políticas internas de la empresa → Q&A empleados
  contenido   TEXT NOT NULL,
  embedding   vector(1536),
  metadata    JSONB DEFAULT '{}',
    -- {fuente, fecha_indexacion, version, cuenta_id, producto_id, etc.}
  created_at  TIMESTAMPTZ DEFAULT now(),
  updated_at  TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_ia_rag_documents_hnsw ON ia_rag_documents
  USING hnsw (embedding vector_cosine_ops)
  WITH (m = 16, ef_construction = 64);

CREATE INDEX idx_ia_rag_documents_tipo
  ON ia_rag_documents(empresa_id, tipo);

ALTER TABLE ia_rag_documents ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON ia_rag_documents
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));
```

### 3.15 Vistas materializadas

```sql
-- Vista materializada: ventas diarias por producto
-- (Base para forecast de ventas e inventario)
CREATE MATERIALIZED VIEW mv_ventas_diarias AS
SELECT
  f.empresa_id,
  fl.producto_id,
  p.nombre AS producto_nombre,
  p.categoria_id,
  DATE(f.fecha_emision AT TIME ZONE 'America/Guayaquil') AS fecha,
  EXTRACT(MONTH FROM f.fecha_emision) AS mes,
  EXTRACT(DOW FROM f.fecha_emision)   AS dia_semana,
  SUM(fl.cantidad)                    AS cantidad_vendida,
  SUM(fl.subtotal)                    AS revenue,
  COUNT(DISTINCT f.id)                AS num_facturas
FROM facturas f
JOIN factura_lineas fl ON fl.factura_id = f.id
JOIN productos p ON p.id = fl.producto_id
WHERE f.estado IN ('AUTORIZADA', 'PAGADA')
GROUP BY f.empresa_id, fl.producto_id, p.nombre, p.categoria_id,
         DATE(f.fecha_emision AT TIME ZONE 'America/Guayaquil'),
         EXTRACT(MONTH FROM f.fecha_emision),
         EXTRACT(DOW FROM f.fecha_emision)
WITH DATA;

CREATE UNIQUE INDEX idx_mv_ventas_diarias_pk
  ON mv_ventas_diarias(empresa_id, producto_id, fecha);

-- Vista materializada: demanda diaria por producto (para reabastecimiento)
-- (Ver ia-inventario.md para DDL completo incluyendo multi-empaque)

-- Vista materializada: clasificación ABC
-- (Ver ia-inventario.md para DDL completo)

-- Vista materializada: métricas por cliente (para scoring CRM y churn)
CREATE MATERIALIZED VIEW mv_customer_metrics AS
SELECT
  c.empresa_id,
  c.id AS contacto_id,
  c.nombre,
  COUNT(DISTINCT f.id)                            AS total_facturas,
  COALESCE(SUM(f.total), 0)                       AS revenue_total,
  COALESCE(AVG(f.total), 0)                       AS ticket_promedio,
  MAX(f.fecha_emision)                            AS ultima_compra,
  MIN(f.fecha_emision)                            AS primera_compra,
  EXTRACT(DAY FROM NOW() - MAX(f.fecha_emision))  AS dias_desde_ultima_compra,
  COUNT(DISTINCT DATE_TRUNC('month', f.fecha_emision)) AS meses_activos,
  COALESCE(SUM(CASE WHEN f.fecha_emision >= NOW() - INTERVAL '90 days'
                    THEN f.total ELSE 0 END), 0)  AS revenue_90d,
  COALESCE(SUM(CASE WHEN f.fecha_emision >= NOW() - INTERVAL '180 days'
                    AND f.fecha_emision < NOW() - INTERVAL '90 days'
                    THEN f.total ELSE 0 END), 0)  AS revenue_90d_anterior
FROM contactos c
LEFT JOIN facturas f ON f.cliente_id = c.id
  AND f.empresa_id = c.empresa_id
  AND f.estado IN ('AUTORIZADA', 'PAGADA')
WHERE c.empresa_id IS NOT NULL
GROUP BY c.empresa_id, c.id, c.nombre
WITH DATA;

CREATE UNIQUE INDEX idx_mv_customer_metrics_pk
  ON mv_customer_metrics(empresa_id, contacto_id);

-- Vista materializada: gastos históricos por cuenta/proveedor
-- (Base para detección de anomalías contables — ver ia-contabilidad.md)

-- Vista materializada: patrones de asistencia RRHH
-- (Base para predicción de ausentismo — ver ia-rrhh.md)
```

---

## 4. RPCs Principales

```sql
-- ============================================================
-- BÚSQUEDA SEMÁNTICA (similarity search con filtros)
-- ============================================================

CREATE OR REPLACE FUNCTION ia_semantic_search(
  p_empresa_id  UUID,
  p_query       TEXT,
  p_tabla_origen VARCHAR(50) DEFAULT NULL,  -- NULL = todas las tablas
  p_limit        INTEGER DEFAULT 10,
  p_threshold    FLOAT DEFAULT 0.70
) RETURNS TABLE (
  registro_id   UUID,
  tabla_origen  VARCHAR,
  contenido     TEXT,
  metadata      JSONB,
  similarity    FLOAT
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_query_embedding vector(1536);
BEGIN
  -- El embedding del query se genera desde la Edge Function antes de llamar esta función.
  -- Este RPC recibe el vector ya computado para evitar latencia adicional en PostgreSQL.
  -- La Edge Function ai-embed genera el vector y luego llama a este RPC.
  RAISE EXCEPTION 'Usar ia_semantic_search_with_embedding() directamente.';
END;
$$;

-- Versión que recibe el embedding ya generado
CREATE OR REPLACE FUNCTION ia_semantic_search_with_embedding(
  p_empresa_id       UUID,
  p_query_embedding  vector(1536),
  p_tabla_origen     VARCHAR(50) DEFAULT NULL,
  p_limit            INTEGER DEFAULT 10,
  p_threshold        FLOAT DEFAULT 0.70
) RETURNS TABLE (
  registro_id  UUID,
  tabla_origen VARCHAR,
  contenido    TEXT,
  metadata     JSONB,
  similarity   FLOAT
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN QUERY
  SELECT
    e.registro_id,
    e.tabla_origen,
    e.contenido,
    e.metadata,
    1 - (e.embedding <=> p_query_embedding) AS similarity
  FROM ia_embeddings e
  WHERE e.empresa_id = p_empresa_id
    AND (p_tabla_origen IS NULL OR e.tabla_origen = p_tabla_origen)
    AND 1 - (e.embedding <=> p_query_embedding) > p_threshold
  ORDER BY e.embedding <=> p_query_embedding
  LIMIT p_limit;
END;
$$;

-- ============================================================
-- SCORING CRM (probabilidad de cierre de oportunidad)
-- ============================================================

CREATE OR REPLACE FUNCTION fn_scoring_crm(
  p_empresa_id    UUID,
  p_oportunidad_id UUID DEFAULT NULL  -- NULL = recalcula todas las activas
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_resultado JSONB := '[]'::JSONB;
  v_op RECORD;
  v_score DECIMAL(5,4);
  v_factores JSONB;
BEGIN
  FOR v_op IN
    SELECT
      o.id,
      o.nombre,
      o.monto_esperado,
      o.probabilidad,
      o.etapa_id,
      o.contacto_id,
      ep.nombre AS etapa_nombre,
      ep.probabilidad AS etapa_probabilidad,
      EXTRACT(DAY FROM NOW() - o.created_at) AS dias_en_pipeline,
      EXTRACT(DAY FROM o.fecha_cierre_esperada - NOW()) AS dias_hasta_cierre,
      cm.revenue_total AS historial_cliente,
      cm.ticket_promedio,
      cm.dias_desde_ultima_compra,
      cm.meses_activos
    FROM oportunidades o
    JOIN etapas_pipeline ep ON ep.id = o.etapa_id
    LEFT JOIN mv_customer_metrics cm ON cm.contacto_id = o.contacto_id
      AND cm.empresa_id = p_empresa_id
    WHERE o.empresa_id = p_empresa_id
      AND o.estado = 'ACTIVA'
      AND (p_oportunidad_id IS NULL OR o.id = p_oportunidad_id)
  LOOP
    -- Fórmula de scoring compuesto
    v_score := LEAST(1.0, GREATEST(0.0,
      -- Peso de la etapa del pipeline (40%)
      (v_op.etapa_probabilidad / 100.0) * 0.40
      -- Historial del cliente (25%): clientes recurrentes son más fáciles de cerrar
      + CASE
          WHEN v_op.meses_activos >= 12 THEN 0.25
          WHEN v_op.meses_activos >= 6  THEN 0.20
          WHEN v_op.meses_activos >= 3  THEN 0.15
          WHEN v_op.historial_cliente IS NOT NULL THEN 0.10
          ELSE 0.05
        END
      -- Urgencia de cierre (20%): más cerca de la fecha, mayor presión
      + CASE
          WHEN v_op.dias_hasta_cierre <= 7  THEN 0.20
          WHEN v_op.dias_hasta_cierre <= 30 THEN 0.15
          WHEN v_op.dias_hasta_cierre <= 60 THEN 0.10
          ELSE 0.05
        END
      -- Actividad reciente del cliente (15%)
      + CASE
          WHEN v_op.dias_desde_ultima_compra <= 30  THEN 0.15
          WHEN v_op.dias_desde_ultima_compra <= 90  THEN 0.10
          WHEN v_op.dias_desde_ultima_compra <= 180 THEN 0.07
          ELSE 0.03
        END
    ));

    v_factores := jsonb_build_object(
      'etapa_peso', v_op.etapa_probabilidad,
      'historial_cliente_meses', v_op.meses_activos,
      'dias_hasta_cierre', v_op.dias_hasta_cierre,
      'dias_desde_ultima_compra', COALESCE(v_op.dias_desde_ultima_compra, 999)
    );

    -- Guardar predicción
    INSERT INTO ia_predictions
      (empresa_id, tipo, referencia_tipo, referencia_id, valor_predicho,
       intervalo_bajo, intervalo_alto, confianza, metadata)
    VALUES
      (p_empresa_id, 'SCORING_CRM', 'oportunidades', v_op.id,
       ROUND(v_score, 4), ROUND(v_score * 0.85, 4), ROUND(LEAST(v_score * 1.15, 1.0), 4),
       0.70, v_factores)
    ON CONFLICT DO NOTHING;

    v_resultado := v_resultado || jsonb_build_object(
      'oportunidad_id', v_op.id,
      'nombre', v_op.nombre,
      'score', ROUND(v_score, 4),
      'monto_esperado', v_op.monto_esperado,
      'monto_ponderado', ROUND(v_op.monto_esperado * v_score, 2),
      'factores', v_factores
    );
  END LOOP;

  RETURN jsonb_build_object('scoring', v_resultado, 'total', jsonb_array_length(v_resultado));
END;
$$;

-- ============================================================
-- DETECCIÓN DE CHURN (clientes en riesgo de abandono)
-- ============================================================

CREATE OR REPLACE FUNCTION fn_detectar_churn(
  p_empresa_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_resultado JSONB := '[]'::JSONB;
  v_cliente RECORD;
  v_churn_score DECIMAL(5,4);
BEGIN
  FOR v_cliente IN
    SELECT *
    FROM mv_customer_metrics
    WHERE empresa_id = p_empresa_id
      AND total_facturas >= 3          -- Mínimo 3 compras para ser significativo
      AND dias_desde_ultima_compra > 60
  LOOP
    -- Score de churn: más alto = mayor riesgo de abandono
    v_churn_score := LEAST(1.0,
      -- Tiempo desde última compra (factor principal)
      CASE
        WHEN v_cliente.dias_desde_ultima_compra > 365 THEN 0.95
        WHEN v_cliente.dias_desde_ultima_compra > 180 THEN 0.75
        WHEN v_cliente.dias_desde_ultima_compra > 90  THEN 0.50
        ELSE 0.30
      END
      -- Caída en revenue reciente vs periodo anterior
      + CASE
          WHEN v_cliente.revenue_90d_anterior > 0
            AND v_cliente.revenue_90d < v_cliente.revenue_90d_anterior * 0.3 THEN 0.25
          WHEN v_cliente.revenue_90d = 0
            AND v_cliente.revenue_90d_anterior > 0 THEN 0.30
          ELSE 0
        END
    );

    -- Crear alerta si score >= 0.60
    IF v_churn_score >= 0.60 THEN
      INSERT INTO alertas_anomalias
        (empresa_id, tipo, severidad, modulo, descripcion, datos,
         referencia_id, referencia_tipo, accion_sugerida)
      VALUES
        (p_empresa_id, 'CHURN_WARNING',
         CASE WHEN v_churn_score >= 0.85 THEN 'ALTA'
              WHEN v_churn_score >= 0.70 THEN 'MEDIA'
              ELSE 'BAJA' END,
         'CRM',
         FORMAT('Cliente %s en riesgo de abandono (score: %s). Sin compras en %s días.',
           v_cliente.nombre, ROUND(v_churn_score, 2), v_cliente.dias_desde_ultima_compra),
         jsonb_build_object(
           'contacto_id', v_cliente.contacto_id,
           'dias_sin_compra', v_cliente.dias_desde_ultima_compra,
           'revenue_historico', ROUND(v_cliente.revenue_total, 2),
           'churn_score', ROUND(v_churn_score, 4)),
         v_cliente.contacto_id,
         'contactos',
         FORMAT('Contactar a %s. Última compra hace %s días. Revenue histórico: $%s.',
           v_cliente.nombre, v_cliente.dias_desde_ultima_compra,
           ROUND(v_cliente.revenue_total, 2)))
      ON CONFLICT DO NOTHING;
    END IF;

    v_resultado := v_resultado || jsonb_build_object(
      'contacto_id', v_cliente.contacto_id,
      'nombre', v_cliente.nombre,
      'churn_score', ROUND(v_churn_score, 4),
      'dias_sin_compra', v_cliente.dias_desde_ultima_compra,
      'revenue_historico', ROUND(v_cliente.revenue_total, 2)
    );
  END LOOP;

  RETURN jsonb_build_object(
    'clientes_riesgo', v_resultado,
    'total', jsonb_array_length(v_resultado),
    'fecha', CURRENT_DATE
  );
END;
$$;

-- ============================================================
-- FORECAST DE VENTAS (media móvil + estacionalidad Ecuador)
-- ============================================================

CREATE OR REPLACE FUNCTION fn_forecast_ventas(
  p_empresa_id   UUID,
  p_producto_id  UUID DEFAULT NULL,      -- NULL = todos los productos
  p_categoria_id UUID DEFAULT NULL,
  p_horizonte    INTEGER DEFAULT 30,     -- días a predecir
  p_granularidad VARCHAR DEFAULT 'DIARIO' -- DIARIO, SEMANAL, MENSUAL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_resultado JSONB := '[]'::JSONB;
  v_prod RECORD;
  v_demanda_base DECIMAL;
  v_desviacion DECIMAL;
  v_factor_est DECIMAL;
  v_prediccion DECIMAL;
  v_categoria_nombre VARCHAR;
BEGIN
  FOR v_prod IN
    SELECT DISTINCT
      dp.producto_id,
      dp.producto_nombre,
      dp.categoria_id,
      COALESCE(cp.nombre, '') AS categoria_nombre,
      AVG(dp.cantidad_vendida) AS demanda_promedio,
      STDDEV(dp.cantidad_vendida) AS desviacion
    FROM mv_ventas_diarias dp
    LEFT JOIN categorias_producto cp ON cp.id = dp.categoria_id
    WHERE dp.empresa_id = p_empresa_id
      AND dp.fecha >= CURRENT_DATE - 90
      AND (p_producto_id IS NULL OR dp.producto_id = p_producto_id)
      AND (p_categoria_id IS NULL OR dp.categoria_id = p_categoria_id)
    GROUP BY dp.producto_id, dp.producto_nombre, dp.categoria_id, cp.nombre
    HAVING COUNT(*) >= 14  -- mínimo 2 semanas de datos
  LOOP
    v_factor_est := fn_factor_estacional(
      p_empresa_id,
      CURRENT_DATE + (p_horizonte / 2),
      v_prod.categoria_nombre
    );

    v_prediccion := v_prod.demanda_promedio * v_factor_est * p_horizonte;

    INSERT INTO ia_predictions
      (empresa_id, tipo, referencia_tipo, referencia_id, valor_predicho,
       intervalo_bajo, intervalo_alto, confianza, metadata)
    VALUES
      (p_empresa_id, 'FORECAST_VENTAS', 'productos', v_prod.producto_id,
       ROUND(v_prediccion, 2),
       ROUND(v_prediccion - 1.65 * COALESCE(v_prod.desviacion, 0) * SQRT(p_horizonte), 2),
       ROUND(v_prediccion + 1.65 * COALESCE(v_prod.desviacion, 0) * SQRT(p_horizonte), 2),
       0.75,
       jsonb_build_object(
         'horizonte_dias', p_horizonte,
         'demanda_promedio_diaria', ROUND(v_prod.demanda_promedio, 2),
         'factor_estacional', ROUND(v_factor_est, 2),
         'granularidad', p_granularidad
       ))
    ON CONFLICT DO NOTHING;

    v_resultado := v_resultado || jsonb_build_object(
      'producto_id', v_prod.producto_id,
      'nombre', v_prod.producto_nombre,
      'demanda_promedio_diaria', ROUND(v_prod.demanda_promedio, 2),
      'prediccion_periodo', ROUND(v_prediccion, 2),
      'intervalo_bajo', ROUND(v_prediccion - 1.65 * COALESCE(v_prod.desviacion, 0) * SQRT(p_horizonte), 2),
      'intervalo_alto', ROUND(v_prediccion + 1.65 * COALESCE(v_prod.desviacion, 0) * SQRT(p_horizonte), 2),
      'factor_estacional', ROUND(v_factor_est, 2),
      'horizonte_dias', p_horizonte
    );
  END LOOP;

  RETURN jsonb_build_object('forecast', v_resultado, 'total', jsonb_array_length(v_resultado));
END;
$$;

-- ============================================================
-- FACTOR ESTACIONAL ECUADOR (helper para todos los forecasts)
-- ============================================================

CREATE OR REPLACE FUNCTION fn_factor_estacional(
  p_empresa_id UUID,
  p_fecha      DATE,
  p_categoria  VARCHAR DEFAULT NULL
) RETURNS DECIMAL(5,2)
LANGUAGE plpgsql STABLE SECURITY DEFINER AS $$
DECLARE
  v_factor DECIMAL(5,2) := 1.00;
  v_mes    SMALLINT := EXTRACT(MONTH FROM p_fecha);
  v_dia    SMALLINT := EXTRACT(DAY FROM p_fecha);
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
  RETURN COALESCE(v_factor, 1.00);
END;
$$;

-- ============================================================
-- ACTUALIZACIÓN DE EMBEDDINGS (llamada por triggers y Edge Functions)
-- ============================================================

CREATE OR REPLACE FUNCTION ia_queue_embedding_update(
  p_tabla_origen VARCHAR(50),
  p_registro_id  UUID
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  -- Marca el registro para regeneración de embedding en el siguiente ciclo nocturno.
  -- La Edge Function generate-embeddings procesa esta cola.
  INSERT INTO ia_embedding_queue (tabla_origen, registro_id, empresa_id, created_at)
  SELECT p_tabla_origen, p_registro_id, empresa_id, now()
  FROM empresas WHERE id = (
    -- Resolución del empresa_id desde la tabla origen (simplificado)
    SELECT empresa_id FROM productos WHERE id = p_registro_id
    UNION ALL
    SELECT empresa_id FROM contactos WHERE id = p_registro_id
    UNION ALL
    SELECT empresa_id FROM facturas WHERE id = p_registro_id
    LIMIT 1
  )
  ON CONFLICT (tabla_origen, registro_id) DO UPDATE
    SET created_at = now();
END;
$$;
```

---

## 5. Module Service Bus

El módulo IA/Chat expone su funcionalidad al resto de PILAR a través del Module Service Bus. Ningún módulo llama directamente a funciones `fn_*` de IA — siempre pasan por `module_bus.request_ia_analysis()`.

```sql
-- ============================================================
-- GATEWAY IA: Punto de entrada para todos los módulos
-- ============================================================

CREATE OR REPLACE FUNCTION module_bus.request_ia_analysis(
  p_empresa_id UUID,
  p_tipo       VARCHAR(30),
    -- FORECAST_VENTAS, SCORING_CRM, CHURN, REABASTECIMIENTO,
    -- ANOMALIA_STOCK, ANOMALIA_GASTOS, CASHFLOW, AUSENTISMO, HE_ANOMALAS
  p_parametros JSONB DEFAULT '{}'
) RETURNS module_bus.bus_response
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_result module_bus.bus_response;
  v_data   JSONB;
BEGIN
  -- Guard 1: Módulo IA activo para esta empresa
  IF NOT module_bus.is_module_active(p_empresa_id, 'ia_chat') THEN
    v_result.executed := false;
    v_result.reason   := 'module_inactive';
    v_result.module   := 'ia_chat';
    v_result.data     := null;
    RETURN v_result;
  END IF;

  -- Guard 2: Empresa tiene IA configurada
  IF NOT EXISTS (SELECT 1 FROM ia_model_config WHERE empresa_id = p_empresa_id) THEN
    v_result.executed := false;
    v_result.reason   := 'ia_not_configured';
    v_result.module   := 'ia_chat';
    RETURN v_result;
  END IF;

  -- Despacho por tipo
  CASE p_tipo
    WHEN 'FORECAST_VENTAS' THEN
      v_data := fn_forecast_ventas(p_empresa_id,
        (p_parametros->>'producto_id')::UUID,
        (p_parametros->>'categoria_id')::UUID,
        COALESCE((p_parametros->>'horizonte')::INTEGER, 30),
        COALESCE(p_parametros->>'granularidad', 'DIARIO'));

    WHEN 'SCORING_CRM' THEN
      v_data := fn_scoring_crm(p_empresa_id,
        (p_parametros->>'oportunidad_id')::UUID);

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
      v_result.reason   := 'tipo_no_soportado';
      v_result.module   := 'ia_chat';
      RETURN v_result;
  END CASE;

  v_result.executed := true;
  v_result.reason   := null;
  v_result.module   := 'ia_chat';
  v_result.data     := v_data;
  RETURN v_result;
END;
$$;

-- ============================================================
-- FUNCIONES ESPECÍFICAS del bus para consumo por otros módulos
-- ============================================================

-- Usado por CRM y Ventas: score de un contacto
CREATE OR REPLACE FUNCTION module_bus.ia.get_contact_score(
  p_empresa_id UUID,
  p_contacto_id UUID
) RETURNS DECIMAL(5,4)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_score DECIMAL(5,4) := 0.50;
BEGIN
  IF NOT module_bus.is_module_active(p_empresa_id, 'ia_chat') THEN
    RETURN v_score;  -- Default neutral si IA no activa
  END IF;
  SELECT COALESCE(valor_predicho, 0.50) INTO v_score
  FROM ia_predictions
  WHERE empresa_id = p_empresa_id
    AND referencia_id = p_contacto_id
    AND tipo = 'SCORING_CRM'
  ORDER BY calculado_at DESC
  LIMIT 1;
  RETURN COALESCE(v_score, 0.50);
END;
$$;

-- Usado por Inventario: forecast de demanda de un producto
CREATE OR REPLACE FUNCTION module_bus.ia.get_product_forecast(
  p_empresa_id UUID,
  p_producto_id UUID,
  p_dias        INTEGER DEFAULT 30
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NOT module_bus.is_module_active(p_empresa_id, 'ia_chat') THEN
    RETURN '{"disponible": false}'::JSONB;
  END IF;
  RETURN fn_forecast_ventas(p_empresa_id, p_producto_id, NULL, p_dias, 'DIARIO');
END;
$$;

-- Llamado por triggers de otros módulos para encolar actualización de embeddings
CREATE OR REPLACE FUNCTION module_bus.ia.create_embedding(
  p_tabla    VARCHAR(50),
  p_id       UUID,
  p_contenido TEXT
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM modulos_empresa me
    JOIN empresas e ON e.id = me.empresa_id
    WHERE me.modulo_id = 'ia_chat' AND me.activo = true
  ) THEN
    RETURN;  -- NO-OP si ninguna empresa tiene IA activa
  END IF;
  PERFORM ia_queue_embedding_update(p_tabla, p_id);
END;
$$;
```

### Ejemplos de uso desde otros módulos

```sql
-- Desde Dashboard al cargar pantalla principal:
SELECT module_bus.request_ia_analysis(empresa_id, 'FORECAST_VENTAS', '{"horizonte": 7}');
SELECT module_bus.request_ia_analysis(empresa_id, 'CHURN', '{}');

-- Desde Inventario al revisar stock bajo:
SELECT module_bus.request_ia_analysis(empresa_id, 'REABASTECIMIENTO', '{"producto_id": "uuid"}');

-- Desde Contabilidad al abrir conciliación:
SELECT module_bus.request_ia_analysis(empresa_id, 'CASHFLOW', '{"horizonte": 30}');

-- Desde RRHH al revisar asistencia:
SELECT module_bus.request_ia_analysis(empresa_id, 'AUSENTISMO', '{}');

-- Desde CRM al abrir oportunidad (score de contacto):
SELECT module_bus.ia.get_contact_score(empresa_id, contacto_id);
```

---

## 6. Edge Functions

| Edge Function | Endpoint | Trigger | Descripción |
|---------------|----------|---------|-------------|
| `ai-gateway` | POST /functions/v1/ai-gateway | On-demand | Router principal: auth JWT, rate limiting, routing a funciones especializadas |
| `ai-chat` | POST /functions/v1/ai-chat | On-demand | Chat NLP conversacional: interpreta mensaje, ejecuta skill, formatea respuesta |
| `ai-forecast` | POST /functions/v1/ai-forecast | Cron + On-demand | Ejecuta fn_forecast_ventas, fn_scoring_crm, fn_detectar_churn |
| `ai-anomaly` | POST /functions/v1/ai-anomaly | Cron semanal | Ejecuta fn_detectar_anomalias_stock, fn_detectar_anomalias_gastos |
| `ai-cashflow` | POST /functions/v1/ai-cashflow | On-demand + Cron | Ejecuta fn_proyeccion_flujo_caja, genera resumen LLM |
| `ai-hr` | POST /functions/v1/ai-hr | Cron mensual | Ejecuta fn_prediccion_ausentismo, fn_detectar_horas_extras_anomalas |
| `generate-embeddings` | POST /functions/v1/generate-embeddings | Cron nocturno | Procesa cola `ia_embedding_queue`, llama OpenAI, guarda en `ia_embeddings` |
| `ai-query` | POST /functions/v1/ai-query | On-demand | RAG: embedding query → similarity search → Claude → respuesta con fuentes |
| `ocr-document` | POST /functions/v1/ocr-document | On-demand | OCR de RIDEs y facturas físicas via Claude vision API |
| `suggest-account` | POST /functions/v1/suggest-account | On-demand | Sugerencia de cuenta contable por similaridad semántica (top 3) |
| `suggest-bank-reconciliation` | POST /functions/v1/suggest-bank-reconciliation | On-demand | Matching líneas bancarias vs movimientos ERP (exact + fuzzy + rule-based) |
| `ai-refresh-mv` | POST /functions/v1/ai-refresh-mv | Cron diario 02:00 | REFRESH MATERIALIZED VIEW de todas las vistas IA |

### Cron Jobs (pg_cron)

```sql
-- Refresh diario de vistas materializadas (02:00 AM Ecuador = 07:00 UTC)
SELECT cron.schedule('ai_refresh_mv_ventas',    '0 7 * * *', 'REFRESH MATERIALIZED VIEW CONCURRENTLY mv_ventas_diarias');
SELECT cron.schedule('ai_refresh_mv_demanda',   '5 7 * * *', 'REFRESH MATERIALIZED VIEW CONCURRENTLY mv_demanda_producto');
SELECT cron.schedule('ai_refresh_mv_customers', '10 7 * * *', 'REFRESH MATERIALIZED VIEW CONCURRENTLY mv_customer_metrics');
SELECT cron.schedule('ai_refresh_mv_gastos',    '15 7 * * *', 'REFRESH MATERIALIZED VIEW CONCURRENTLY mv_gastos_historico');

-- Refresh mensual de ABC (primer día del mes)
SELECT cron.schedule('ai_refresh_mv_abc', '0 8 1 * *',
  'REFRESH MATERIALIZED VIEW CONCURRENTLY mv_abc_classification');

-- Detección de anomalías semanal (lunes 06:00 AM Ecuador = 11:00 UTC)
SELECT cron.schedule('ai_detect_anomalies', '0 11 * * 1',
  $$SELECT fn_detectar_anomalias_stock(e.id), fn_detectar_anomalias_gastos(e.id)
    FROM empresas e WHERE e.activo = true$$);

-- Scoring CRM semanal (lunes 07:00 AM Ecuador)
SELECT cron.schedule('ai_scoring_crm', '0 12 * * 1',
  $$SELECT fn_scoring_crm(e.id) FROM empresas e WHERE e.activo = true$$);

-- Detección churn quincenal (días 1 y 15 de cada mes)
SELECT cron.schedule('ai_detect_churn', '0 12 1,15 * *',
  $$SELECT fn_detectar_churn(e.id) FROM empresas e WHERE e.activo = true$$);

-- RRHH mensual (día 1)
SELECT cron.schedule('ai_hr_monthly', '0 13 1 * *',
  $$SELECT fn_prediccion_ausentismo(e.id), fn_detectar_horas_extras_anomalas(e.id)
    FROM empresas e WHERE e.activo = true$$);

-- Generación de embeddings en batch (03:00 AM Ecuador)
SELECT cron.schedule('ai_generate_embeddings', '0 8 * * *',
  $$SELECT net.http_post('https://[proyecto].supabase.co/functions/v1/generate-embeddings',
    '{}', 'application/json')$$);

-- Reset de tokens diario
SELECT cron.schedule('ai_reset_tokens', '0 5 * * *',
  $$UPDATE ia_model_config SET tokens_usados_hoy = 0, fecha_reset_tokens = CURRENT_DATE
    WHERE fecha_reset_tokens < CURRENT_DATE$$);
```

---

## 7. Chat NLP — Flujo y UI

### Flujo completo de una consulta

```
1. Usuario escribe: "¿Cuánto vendimos esta semana?"

2. Flutter → POST /functions/v1/ai-chat
   { conversation_id, message, empresa_id, contexto_modulo: "VENTAS" }

3. Edge Function ai-chat:
   a. Obtiene/crea conversación en ia_conversaciones
   b. Guarda mensaje en ia_mensajes (rol: USUARIO)
   c. Carga ia_skills activos
   d. Carga historial reciente (últimos 20 mensajes)
   e. Llama a Claude con prompt que incluye skills disponibles
   f. Claude identifica skill: 'query_ventas_periodo', extrae fechas
   g. Si skill.tipo = CONSULTA: ejecuta sql_template via execute_ai_query()
   h. Llama a Claude de nuevo para formatear resultados en español
   i. Si skill.tipo = ACCION: retorna requiere_confirmacion: true
   j. Guarda respuesta en ia_mensajes (rol: ASISTENTE)
   k. Registra uso en ia_token_usage
   l. Retorna { conversation_id, respuesta, datos? }

4. Flutter renderiza respuesta:
   - Texto: burbuja ASISTENTE con markdown
   - Datos tabulares: SfDataGrid inline
   - Confirmación pendiente: botones [Confirmar] [Cancelar]
```

### Widget Chat IA (Flutter)

```
Panel lateral (desktop) / Bottom sheet (mobile)
├── Header
│   ├── Ícono PILAR AI + título "Asistente PILAR"
│   ├── Selector: [Nueva conversación ▼] | [Historial ▼]
│   └── Botón minimizar/cerrar
│
├── Área de mensajes (scroll)
│   ├── Burbuja USUARIO: texto plano, alineado derecha
│   ├── Burbuja ASISTENTE: markdown renderizado, alineado izquierda
│   │   ├── Datos tabulares → SfDataGrid inline (max 10 filas)
│   │   ├── Montos → negrita con formato $X,XXX.XX
│   │   ├── Acción pendiente → botones [Confirmar] [Cancelar]
│   │   └── Fuentes RAG → chips clickeables con referencias
│   └── Indicador "PILAR AI está escribiendo..." (pulsante)
│
├── Sugerencias rápidas (chips contextuales por módulo):
│   VENTAS: "Resumen del día" | "Ventas de hoy" | "Top productos"
│   INVENTARIO: "Stock bajo" | "Anomalías detectadas"
│   CONTABILIDAD: "Gastos inusuales" | "Flujo de caja"
│
├── Input
│   ├── TextField con hint "Pregunta algo..."
│   ├── Botón enviar (o Enter)
│   └── Botón micrófono (speech-to-text, P3)
│
└── Footer
    └── "IA puede cometer errores. Verifica datos críticos."

Atajos de teclado (desktop):
  Ctrl+J → abrir/cerrar chat
  Ctrl+N → nueva conversación
  Escape → cerrar
```

---

## 8. Seguridad y Multi-tenancy

### Principios de seguridad

1. **Multi-tenancy:** Toda tabla IA tiene `empresa_id` + RLS con `private.get_empresa_id()`. Las funciones usan `SECURITY DEFINER` con verificación explícita de `empresa_id` en todos los WHERE.

2. **SQL Injection:** La función `execute_ai_query()` rechaza cualquier operación DDL o DML. Solo permite SELECT. Los parámetros se pasan posicionalmente, nunca concatenados.

3. **API Keys:** Se almacenan en Supabase Vault, nunca en tablas regulares. La columna `api_key_vault` en `ia_model_config` contiene solo la referencia al secret (`secret_name`), nunca la key directa.

4. **Audit trail:** Todas las interacciones del chat se registran en `ia_mensajes`. Todas las acciones ejecutadas vía IA se marcan con `origen = 'AI_AGENT'` en `registro_actividad` (Core Foundation).

5. **Confirmación obligatoria:** Skills con `requiere_confirmacion = true` siempre retornan `tipo: ACCION_CONFIRMAR` — la Edge Function nunca ejecuta acciones DML automáticamente sin confirmación del usuario.

6. **Rate limiting:** Máximo 60 requests/minuto por usuario, implementado en `ai-gateway`. Límite diario de tokens por empresa en `ia_model_config.max_tokens_dia`.

7. **Permisos de Skills:** Campo `ia_skills.permisos` (JSONB) lista los roles autorizados. El gateway verifica el rol del JWT antes de ejecutar el skill.

```sql
-- Función sandbox: ejecuta solo SELECT, nunca DDL/DML
CREATE OR REPLACE FUNCTION execute_ai_query(
  p_sql        TEXT,
  p_params     TEXT[],
  p_empresa_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_result JSONB;
BEGIN
  -- Whitelist: solo operaciones de lectura
  IF p_sql ~* '\y(DROP|DELETE|UPDATE|INSERT|ALTER|CREATE|TRUNCATE|GRANT|REVOKE)\y' THEN
    RAISE EXCEPTION 'Operación no permitida en consultas IA: solo SELECT';
  END IF;

  -- El primer parámetro siempre es empresa_id (inyectado por el servidor, no del usuario)
  -- Esto garantiza multi-tenancy aun si el LLM genera SQL malicioso
  EXECUTE FORMAT('SELECT jsonb_agg(row_to_json(t)) FROM (%s) t', p_sql)
    INTO v_result
    USING p_empresa_id,
      COALESCE(p_params[1], ''),
      COALESCE(p_params[2], ''),
      COALESCE(p_params[3], ''),
      COALESCE(p_params[4], '');

  RETURN COALESCE(v_result, '[]'::JSONB);
END;
$$;
```

---

## 9. Integraciones

### pgvector (extensión PostgreSQL)
- Dimensión: 1536 (compatible con OpenAI text-embedding-3-small y ada-002)
- Índice: HNSW (`m=16, ef_construction=64`) para búsqueda aproximada en datasets < 1M
- Operador de distancia: `<=>` (cosine distance), equivale a `1 - cosine_similarity`
- Alternativa para datasets grandes (>1M): IVFFlat con `lists=SQRT(n_registros)`

### LLM (Claude API)
- Chat y NLP: `claude-sonnet-4-20250514` (rápido, equilibrio costo/calidad)
- Análisis complejo (bajo demanda explícita del usuario): `claude-opus-4-6`
- Sistema de prompts en español con contexto de empresa y skills disponibles
- Context window: 200K tokens (adecuado para incluir historial + skills + datos)

### OpenAI Embeddings
- Modelo: `text-embedding-3-small` (1536 dim, $0.02/1M tokens)
- Uso: vectorización de productos, documentos, asientos contables, contactos
- Generación en batch nocturno (cron), no en tiempo real por INSERT

### Módulo Comunicación (alertas)
- Las alertas en `alertas_anomalias` con `notificado = false` son procesadas por el módulo Comunicación
- Canales: email (Resend), WhatsApp (Cloud API), notificaciones push (FCM)
- Prioridad de notificación: severidad `ALTA`/`CRITICAL` → inmediata; resto → resumen diario

### Supabase Storage
- Los embeddings se almacenan en PostgreSQL (no en Storage)
- Storage se usa para: modelos ML serializable (futuro P3), exports de análisis PDF

---

## 10. Costos y Límites

| Parámetro | Valor | Razón |
|-----------|-------|-------|
| Modelo embeddings | text-embedding-3-small | $0.02/1M tokens (~$0.00002/embedding) |
| Modelo chat | claude-sonnet-4-20250514 | $3 input / $15 output por 1M tokens |
| Max tokens/día por empresa | 50,000 (configurable) | Control de costos (~$0.20/día) |
| Max mensajes/conversación | 100 | Performance |
| Max conversaciones activas/usuario | 10 | Storage |
| Histórico de predicciones | 365 días (luego purge) | Storage |
| Refresh MV mínimo | 1 vez/día | Performance DB |
| Max resultados query IA | 100 filas | Tokens LLM |
| Mín. datos para forecast | 90 días histórico | Precisión estadística |
| Mín. compras para churn | 3 compras del cliente | Significancia estadística |
| Timeout Edge Function | 25 segundos | Límite Supabase |

**Estimación para empresa mediana (1,000 productos, 5,000 clientes, 500 facturas/mes):**
- Embeddings iniciales: ~6,500 registros × $0.00002 = ~$0.13 (único)
- Embeddings mensuales (nuevos registros): ~$0.01/mes
- Chat NLP: ~200 consultas/mes = ~$4.06/mes LLM
- **Total IA mensual: ~$4.20/mes por empresa**

---

## 11. Roadmap de Implementación

### Fase 1 — Infraestructura (P2, semanas 1-2)
- Crear tablas comunes IA (ia_model_config, ia_predictions, alertas_anomalias, ia_feedback, ia_token_usage)
- Crear `ia_embeddings` + índice HNSW
- Crear vistas materializadas (mv_ventas_diarias, mv_customer_metrics)
- Configurar pg_cron para refresh y cron jobs
- Seed calendario estacional Ecuador
- Edge Function `ai-gateway` (auth + rate limiting + routing)

### Fase 2 — Funciones Estadísticas (P2, semanas 3-5)
- `fn_factor_estacional`
- `fn_forecast_ventas` (media móvil + estacionalidad)
- `fn_scoring_crm` + `fn_detectar_churn`
- `fn_reabastecimiento_inteligente` (ROP + stock de seguridad)
- `fn_detectar_anomalias_stock`
- `fn_detectar_anomalias_gastos`
- `fn_proyeccion_flujo_caja`
- `fn_prediccion_ausentismo` + `fn_detectar_horas_extras_anomalas`
- `module_bus.request_ia_analysis()` y funciones específicas del bus

### Fase 3 — Edge Functions + LLM (P2, semanas 6-8)
- `generate-embeddings` (batch nocturno, OpenAI API)
- `ai-chat` con skills completos y NLP conversacional
- `ai-forecast`, `ai-anomaly`, `ai-cashflow`, `ai-hr`
- `ai-query` (RAG), `ocr-document`, `suggest-account`, `suggest-bank-reconciliation`
- Seed de `ia_skills` fundamentales

### Fase 4 — Flutter UI (P2, semanas 9-12)
- Widget Chat IA (panel lateral + bottom sheet mobile)
- Dashboard IA Ventas (forecast + churn + scoring CRM)
- Dashboard IA Inventario (reabastecimiento + anomalías + ABC + what-if)
- Dashboard IA Finanzas (anomalías contables + categorización + cashflow)
- Integración con sistema de notificaciones (alertas → push/email)

### Fase 5 — Refinamiento (P2, semanas 13-16)
- Feedback loop (ia_feedback → ajuste de umbrales)
- Backfill de `valor_real` en ia_predictions (accuracy tracking)
- Dashboard de precisión del modelo (% acierto por tipo de predicción)
- Optimización de queries (EXPLAIN ANALYZE en todas las fn_*)
- Testing con datos reales de empresa piloto

---

## 12. Inventario de Artefactos

### Tablas nuevas (13)
1. `ia_model_config` — configuración de modelos IA por empresa
2. `ia_embeddings` — vectores pgvector (1536 dim)
3. `ia_conversaciones` — sesiones de chat NLP
4. `ia_mensajes` — mensajes de cada conversación
5. `ia_predictions` — histórico unificado de predicciones
6. `alertas_anomalias` — alertas de anomalías detectadas
7. `ia_feedback` — feedback de usuarios sobre predicciones
8. `ia_agentes` — agentes de IA configurados por empresa
9. `ia_token_usage` — control de consumo de tokens
10. `ia_skills` — capacidades registradas del chat IA
11. `ia_calendario_estacional` — eventos estacionales Ecuador
12. `ia_reabastecimiento_config` — config de reabastecimiento por producto
13. `ia_anomalias_stock` — anomalías de inventario (detalle)
14. `ia_gastos_recurrentes` — patrones de gasto recurrente
15. `ia_rag_documents` — documentos indexados para RAG

### Vistas materializadas (6)
1. `mv_ventas_diarias` — ventas diarias por producto (base forecast ventas)
2. `mv_demanda_producto` — demanda diaria + multi-empaque (base forecast inventario)
3. `mv_abc_classification` — clasificación ABC dinámica
4. `mv_customer_metrics` — métricas por cliente (base scoring/churn)
5. `mv_gastos_historico` — gastos por cuenta/proveedor (base anomalías contables)
6. `mv_hr_attendance_patterns` — patrones de asistencia (base predicción ausentismo)

### Funciones PostgreSQL (12)
1. `fn_factor_estacional` — helper de estacionalidad Ecuador
2. `fn_forecast_ventas` — predicción de ventas por producto/categoría
3. `fn_scoring_crm` — scoring de oportunidades CRM
4. `fn_detectar_churn` — detección de abandono de clientes
5. `fn_reabastecimiento_inteligente` — ROP óptimo con stock de seguridad
6. `fn_detectar_anomalias_stock` — anomalías de inventario
7. `fn_what_if_inventario` — simulación de escenarios de inventario
8. `fn_detectar_anomalias_gastos` — anomalías contables (3 tipos)
9. `fn_proyeccion_flujo_caja` — proyección cashflow 30/60/90 días
10. `fn_prediccion_ausentismo` — predicción RRHH
11. `fn_detectar_horas_extras_anomalas` — HE anómalas RRHH
12. `execute_ai_query` — sandbox SQL de solo lectura para chat IA

### RPCs (4)
1. `ia_semantic_search_with_embedding` — búsqueda vectorial con filtros
2. `fn_scoring_crm` — RPC pública de scoring
3. `module_bus.request_ia_analysis` — gateway Module Bus
4. `module_bus.ia.get_contact_score` / `get_product_forecast` / `create_embedding`

### Edge Functions (11)
1. `ai-gateway` — router + auth + rate limiting
2. `ai-chat` — chat NLP conversacional completo
3. `ai-forecast` — predicciones ventas/CRM/churn
4. `ai-anomaly` — detección de anomalías
5. `ai-cashflow` — proyección flujo de caja
6. `ai-hr` — análisis RRHH
7. `generate-embeddings` — batch nocturno de embeddings
8. `ai-query` — RAG sobre documentos propios
9. `ocr-document` — OCR de comprobantes (Claude vision)
10. `suggest-account` — sugerencia cuenta contable
11. `suggest-bank-reconciliation` — conciliación bancaria asistida

### Cron Jobs (11)
- 6 refresh de MVs diarios (02:00-02:30 AM Ecuador)
- 1 refresh ABC mensual (día 1)
- 1 generación de embeddings batch nocturna (03:00 AM Ecuador)
- 1 detección de anomalías semanal (lunes)
- 1 scoring CRM semanal (lunes)
- 1 churn quincenal (días 1 y 15)
- 1 análisis RRHH mensual (día 1)
- 1 reset de tokens diario

---

## 13. Sub-documentos

| Archivo | Contenido |
|---------|-----------|
| `arquitectura-ia.md` | Arquitectura extendida, tablas comunes IA, configuración de modelos, calendario estacional Ecuador |
| `chat-nlp.md` | Skills del chat, tablas `ia_skills` + `ia_intent_examples`, Edge Function `ai-chat` completa (TS), flujo UI/UX |
| `edge-functions.md` | Inventario de Edge Functions, cron jobs, Module Service Bus completo |
| `roadmap-ia.md` | Costos/latencia/límites, roadmap de implementación por fases, resumen de artefactos |
| `docs/modulos/contabilidad/ia-contabilidad.md` | MV `mv_gastos_historico`, `fn_detectar_anomalias_gastos`, `fn_proyeccion_flujo_caja`, flujo UI finanzas |
| `docs/modulos/inventario/ia-inventario.md` | MV `mv_demanda_producto` + `mv_abc_classification`, `fn_reabastecimiento_inteligente`, `fn_detectar_anomalias_stock`, `fn_what_if_inventario`, flujo UI inventario |
