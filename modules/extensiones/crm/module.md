# Módulo CRM (Gestión de Relaciones con Clientes)

Módulo Auxiliar (#17 en tabla `modulos`). Gestiona el ciclo de vida del lead: desde la captación hasta la conversión en Orden de Venta. Se integra con Ventas (cotizaciones, OV), Comunicación (campañas, notificaciones) e IA/Chat (scoring automático). Los módulos auxiliares NUNCA insertan directamente en tablas de módulos Core: usan el **Module Service Bus**.

> **Módulo Auxiliar #17 — Requiere: Ventas (#5), Comunicación (#3 - Infraestructura)**
>
> Sub-módulos relacionados: [Lead Scoring IA](../ia/ia.md) · [Email Marketing](#email-marketing-integrado) · [Segmentación](#segmentación-de-clientes)

---

## Navegación (Flutter)

```
features/crm/
  ├── screens/
  │   ├── crm_dashboard_screen.dart         # KPIs: pipeline value, conversión, actividades
  │   ├── pipeline_screen.dart              # Tablero Kanban por etapas (drag-drop)
  │   ├── leads_screen.dart                 # Listado de oportunidades (SfDataGrid)
  │   ├── lead_form_screen.dart             # Formulario de oportunidad (crear/editar)
  │   ├── lead_detail_screen.dart           # Ficha 360 de la oportunidad + timeline
  │   ├── activities_screen.dart            # Todas las actividades pendientes del usuario
  │   ├── activity_calendar_screen.dart     # Calendario de actividades (SfCalendar)
  │   ├── campaigns_screen.dart             # Listado de campañas
  │   ├── campaign_form_screen.dart         # Crear/editar campaña
  │   ├── campaign_detail_screen.dart       # Contactos, estado envío, métricas
  │   ├── segments_screen.dart              # Segmentos de clientes
  │   └── customer_360_screen.dart          # Vista unificada del cliente
  ├── providers/
  │   ├── oportunidades_provider.dart       # AsyncNotifier: CRUD oportunidades
  │   ├── pipeline_provider.dart            # Estado del tablero Kanban por etapas
  │   ├── actividades_provider.dart         # Actividades del usuario autenticado
  │   ├── campanas_provider.dart            # CRUD campañas
  │   └── scoring_provider.dart            # Score y factores por oportunidad
  └── widgets/
        ├── kanban_board.dart               # Tablero Kanban con columnas por etapa
        ├── kanban_card.dart                # Card de oportunidad en Kanban
        ├── activity_timeline.dart          # Timeline vertical de actividades
        ├── lead_score_badge.dart           # Badge visual del score (0-100)
        └── campana_stats_card.dart         # Card de métricas de campaña
```

---

## Modelo de Datos

### etapas_pipeline

Configuración del pipeline de ventas. Cada empresa puede definir sus propias etapas.

```sql
CREATE TABLE etapas_pipeline (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  nombre                VARCHAR(100) NOT NULL,
    -- Ejemplos: 'Prospecto', 'Calificado', 'Propuesta', 'Negociación', 'Ganado', 'Perdido'
  orden                 INTEGER NOT NULL,             -- Posición en el pipeline (1, 2, 3...)
  probabilidad_default  DECIMAL(5,2) NOT NULL DEFAULT 0,
    -- % probabilidad de cierre asignado automáticamente al mover a esta etapa
  es_ganada             BOOLEAN NOT NULL DEFAULT false,  -- Etapa de cierre exitoso
  es_perdida            BOOLEAN NOT NULL DEFAULT false,  -- Etapa de cierre fallido
  color                 VARCHAR(7) DEFAULT '#2196F3',    -- Hex para columna Kanban
  activa                BOOLEAN NOT NULL DEFAULT true,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(empresa_id, nombre),
  UNIQUE(empresa_id, orden),
  -- No puede ser ganada Y perdida a la vez
  CONSTRAINT chk_etapa_estado
    CHECK (NOT (es_ganada = true AND es_perdida = true))
);

ALTER TABLE etapas_pipeline ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON etapas_pipeline
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE INDEX idx_etapas_pipeline_empresa
  ON etapas_pipeline(empresa_id, orden) WHERE activa = true;
```

#### Seed de etapas por defecto

```sql
-- Se inserta automáticamente al activar el módulo CRM en una empresa
-- via función crm.initialize_pipeline(p_empresa_id)
INSERT INTO etapas_pipeline(empresa_id, nombre, orden, probabilidad_default, color) VALUES
  (p_empresa_id, 'Prospecto',    1, 10.00, '#9E9E9E'),
  (p_empresa_id, 'Calificado',   2, 25.00, '#2196F3'),
  (p_empresa_id, 'Propuesta',    3, 50.00, '#FF9800'),
  (p_empresa_id, 'Negociación',  4, 75.00, '#8BC34A'),
  (p_empresa_id, 'Ganado',       5, 100.00, '#4CAF50'),
  (p_empresa_id, 'Perdido',      6, 0.00,  '#F44336');

UPDATE etapas_pipeline SET es_ganada = true WHERE nombre = 'Ganado' AND empresa_id = p_empresa_id;
UPDATE etapas_pipeline SET es_perdida = true WHERE nombre = 'Perdido' AND empresa_id = p_empresa_id;
```

### oportunidades

Registro central del pipeline de ventas.

```sql
CREATE TABLE oportunidades (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  nombre                VARCHAR(200) NOT NULL,
    -- Descripción del negocio (ej: 'Equipos de computo para ABC Corp')
  contacto_id           UUID NOT NULL REFERENCES contactos(id),
  responsable_id        UUID NOT NULL REFERENCES auth.users(id),
  etapa_id              UUID NOT NULL REFERENCES etapas_pipeline(id),
  -- Valores
  probabilidad          DECIMAL(5,2) NOT NULL DEFAULT 10.00,
    -- % probabilidad de cierre (se actualiza al cambiar de etapa)
  valor_estimado        DECIMAL(14,2) NOT NULL DEFAULT 0,
  valor_ponderado       DECIMAL(14,2) GENERATED ALWAYS AS
                          (valor_estimado * probabilidad / 100) STORED,
  moneda_id             UUID REFERENCES monedas(id),
  -- Fechas
  fecha_creacion        DATE NOT NULL DEFAULT CURRENT_DATE,
  fecha_cierre_esperada DATE,
  fecha_cierre_real     DATE,
  -- Origen del lead
  origen                VARCHAR(20) NOT NULL DEFAULT 'OTRO',
    -- WEBSITE | LLAMADA | EMAIL | REFERIDO | FERIA | ECOMMERCE | REDES | OTRO
  campana_id            UUID REFERENCES campanas_crm(id),
  -- Seguimiento
  ultimo_contacto_at    TIMESTAMPTZ,
  proximo_seguimiento_at TIMESTAMPTZ,
  -- Resultado (al perder)
  motivo_perdida        VARCHAR(200),
  competidor            VARCHAR(200),  -- Empresa que ganó el negocio
  -- Estado
  estado                VARCHAR(20) NOT NULL DEFAULT 'ACTIVA',
    -- ACTIVA | GANADA | PERDIDA | CANCELADA
  -- Vinculación con ventas (vía Module Service Bus)
  notas                 TEXT,
  -- Score calculado por IA
  score                 DECIMAL(5,2) DEFAULT 0,
  score_calculado_at    TIMESTAMPTZ,
  -- Control de concurrencia
  version               INTEGER NOT NULL DEFAULT 1,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by            UUID REFERENCES auth.users(id),
  updated_by            UUID REFERENCES auth.users(id)
);

ALTER TABLE oportunidades ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON oportunidades
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE INDEX idx_oportunidades_empresa_estado
  ON oportunidades(empresa_id, estado, etapa_id);
CREATE INDEX idx_oportunidades_responsable
  ON oportunidades(empresa_id, responsable_id, estado);
CREATE INDEX idx_oportunidades_contacto
  ON oportunidades(empresa_id, contacto_id);
CREATE INDEX idx_oportunidades_campana
  ON oportunidades(empresa_id, campana_id)
  WHERE campana_id IS NOT NULL;
CREATE INDEX idx_oportunidades_cierre
  ON oportunidades(empresa_id, fecha_cierre_esperada)
  WHERE estado = 'ACTIVA';
```

### oportunidad_cotizaciones

Relación N:N entre oportunidades y cotizaciones (una oportunidad puede tener múltiples versiones de propuesta).

```sql
CREATE TABLE oportunidad_cotizaciones (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  oportunidad_id  UUID NOT NULL REFERENCES oportunidades(id) ON DELETE CASCADE,
  cotizacion_id   UUID NOT NULL REFERENCES cotizaciones(id),
  version         INTEGER NOT NULL DEFAULT 1,
  es_ganadora     BOOLEAN NOT NULL DEFAULT false,
    -- Solo una es_ganadora=true por oportunidad
  notas           TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(oportunidad_id, cotizacion_id)
);

-- Garantiza solo una cotización ganadora por oportunidad
CREATE UNIQUE INDEX idx_oportunidad_cotizaciones_ganadora
  ON oportunidad_cotizaciones(oportunidad_id)
  WHERE es_ganadora = true;

ALTER TABLE oportunidad_cotizaciones ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON oportunidad_cotizaciones
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE INDEX idx_oportunidad_cotiz_oportunidad
  ON oportunidad_cotizaciones(oportunidad_id);
```

### actividades_crm

Registro de todas las interacciones con la oportunidad: llamadas, emails, reuniones, tareas, notas.

```sql
CREATE TABLE actividades_crm (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id        UUID NOT NULL REFERENCES empresas(id),
  oportunidad_id    UUID NOT NULL REFERENCES oportunidades(id) ON DELETE CASCADE,
  tipo              VARCHAR(20) NOT NULL,
    -- LLAMADA | EMAIL | REUNION | TAREA | NOTA | DEMO | VISITA
  asunto            VARCHAR(300) NOT NULL,
  descripcion       TEXT,
  responsable_id    UUID NOT NULL REFERENCES auth.users(id),
  contacto_id       UUID REFERENCES contactos(id),   -- Contacto específico en la reunión
  -- Fechas
  fecha_programada  TIMESTAMPTZ,
  fecha_realizada   TIMESTAMPTZ,
  duracion_minutos  INTEGER,                         -- Duración real (para llamadas/reuniones)
  -- Estado y resultado
  estado            VARCHAR(20) NOT NULL DEFAULT 'PENDIENTE',
    -- PENDIENTE | REALIZADA | CANCELADA
  resultado         TEXT,         -- Notas del resultado de la actividad
  -- Seguimiento automático
  crear_seguimiento BOOLEAN NOT NULL DEFAULT false,
    -- Si true, al marcar REALIZADA se crea automáticamente una nueva actividad
  seguimiento_tipo  VARCHAR(20),  -- Tipo de la actividad de seguimiento
  seguimiento_dias  INTEGER DEFAULT 3,
  -- Concurrencia
  version           INTEGER NOT NULL DEFAULT 1,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by        UUID REFERENCES auth.users(id)
);

ALTER TABLE actividades_crm ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON actividades_crm
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE INDEX idx_actividades_crm_oportunidad
  ON actividades_crm(empresa_id, oportunidad_id, fecha_programada);
CREATE INDEX idx_actividades_crm_responsable
  ON actividades_crm(empresa_id, responsable_id, estado, fecha_programada);
CREATE INDEX idx_actividades_crm_pendientes
  ON actividades_crm(empresa_id, responsable_id, fecha_programada)
  WHERE estado = 'PENDIENTE';
```

### campanas_crm

Campañas de marketing vinculadas al pipeline.

```sql
CREATE TABLE campanas_crm (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  nombre          VARCHAR(200) NOT NULL,
  tipo            VARCHAR(20) NOT NULL,
    -- EMAIL | WHATSAPP | TELEFONICA | MIXTA | EVENTO | REDES
  estado          VARCHAR(20) NOT NULL DEFAULT 'BORRADOR',
    -- BORRADOR | ACTIVA | PAUSADA | FINALIZADA | CANCELADA
  fecha_inicio    DATE,
  fecha_fin       DATE,
  presupuesto     DECIMAL(14,2) DEFAULT 0,
  costo_real      DECIMAL(14,2) DEFAULT 0,
  objetivo        TEXT,
  descripcion     TEXT,
  -- Métricas (actualizadas por triggers desde campana_contactos)
  total_contactos     INTEGER NOT NULL DEFAULT 0,
  total_enviados      INTEGER NOT NULL DEFAULT 0,
  total_abiertos      INTEGER NOT NULL DEFAULT 0,
  total_respondidos   INTEGER NOT NULL DEFAULT 0,
  total_convertidos   INTEGER NOT NULL DEFAULT 0,
  total_rebotados     INTEGER NOT NULL DEFAULT 0,
  -- Concurrencia
  version         INTEGER NOT NULL DEFAULT 1,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by      UUID REFERENCES auth.users(id)
);

ALTER TABLE campanas_crm ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON campanas_crm
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE INDEX idx_campanas_crm_empresa_estado
  ON campanas_crm(empresa_id, estado, fecha_inicio);
```

### campana_contactos

Contactos incluidos en una campaña y su estado de interacción.

```sql
CREATE TABLE campana_contactos (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  campana_id      UUID NOT NULL REFERENCES campanas_crm(id) ON DELETE CASCADE,
  contacto_id     UUID NOT NULL REFERENCES contactos(id),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  estado          VARCHAR(20) NOT NULL DEFAULT 'PENDIENTE',
    -- PENDIENTE | ENVIADO | ABIERTO | RESPONDIDO | CONVERTIDO | REBOTADO | CANCELADO
  enviado_at      TIMESTAMPTZ,
  abierto_at      TIMESTAMPTZ,
  respondido_at   TIMESTAMPTZ,
  convertido_at   TIMESTAMPTZ,
  -- Si se convirtió: referencia a la oportunidad generada
  oportunidad_id  UUID REFERENCES oportunidades(id),
  notas           TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(campana_id, contacto_id)
);

ALTER TABLE campana_contactos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON campana_contactos
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE INDEX idx_campana_contactos_campana
  ON campana_contactos(campana_id, estado);
CREATE INDEX idx_campana_contactos_contacto
  ON campana_contactos(empresa_id, contacto_id);
```

### crm_scoring

Scoring de leads calculado por IA (módulo IA/Chat). Un registro por contacto con el score actual y los factores que lo determinan.

```sql
CREATE TABLE crm_scoring (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  contacto_id           UUID NOT NULL REFERENCES contactos(id),
  -- Score principal (0-100)
  score                 DECIMAL(5,2) NOT NULL DEFAULT 0,
  -- Descomposición por factor
  factores              JSONB NOT NULL DEFAULT '{}',
    -- {
    --   "interacciones_recientes": {"valor": 30, "peso": 0.25, "puntos": 7.5},
    --   "valor_historico":        {"valor": 45000, "peso": 0.30, "puntos": 13.5},
    --   "frecuencia_compra":      {"valor": "mensual", "peso": 0.20, "puntos": 8.0},
    --   "dias_ultima_compra":     {"valor": 15, "peso": 0.15, "puntos": 6.0},
    --   "tickets_soporte":        {"valor": 0, "peso": 0.10, "puntos": 5.0}
    -- }
  fecha_calculo         TIMESTAMPTZ NOT NULL DEFAULT now(),
  modelo_version        VARCHAR(20) DEFAULT 'v1',
  proxima_accion_sugerida TEXT,
    -- IA sugiere: "Llamar esta semana, tiene consulta pendiente desde hace 5 días"
  UNIQUE(empresa_id, contacto_id)
);

ALTER TABLE crm_scoring ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON crm_scoring
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE INDEX idx_crm_scoring_empresa
  ON crm_scoring(empresa_id, score DESC);
CREATE INDEX idx_crm_scoring_contacto
  ON crm_scoring(empresa_id, contacto_id);
```

### criterios_scoring

Reglas configurables por empresa para el cálculo del score.

```sql
CREATE TABLE criterios_scoring (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id  UUID NOT NULL REFERENCES empresas(id),
  campo       VARCHAR(50) NOT NULL,
    -- 'industria', 'cargo', 'interacciones_mes', 'valor_historico', 'dias_sin_compra'
  operador    VARCHAR(10) NOT NULL,
    -- '=', '!=', '>', '<', '>=', '<=', 'CONTAINS', 'NOT_CONTAINS'
  valor       TEXT NOT NULL,
    -- 'TECNOLOGIA', 'GERENTE', '3', '50000'
  puntos      INTEGER NOT NULL,
    -- Positivo suma, negativo resta. Ej: +20, -10
  descripcion VARCHAR(200),
  activo      BOOLEAN NOT NULL DEFAULT true,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE criterios_scoring ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON criterios_scoring
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE INDEX idx_criterios_scoring_empresa
  ON criterios_scoring(empresa_id) WHERE activo = true;
```

### automatizaciones_crm

Reglas de automatización del pipeline: acciones automáticas basadas en eventos o condiciones.

```sql
CREATE TABLE automatizaciones_crm (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id    UUID NOT NULL REFERENCES empresas(id),
  nombre        VARCHAR(200) NOT NULL,
  trigger_type  VARCHAR(30) NOT NULL,
    -- ETAPA_CAMBIO | DIAS_SIN_ACTIVIDAD | MONTO_SUPERA | PROBABILIDAD_CAMBIA | SCORE_UMBRAL
  condicion     JSONB NOT NULL,
    -- ETAPA_CAMBIO:         {"etapa_origen_id": "uuid", "etapa_destino_id": "uuid"}
    -- DIAS_SIN_ACTIVIDAD:   {"dias": 7, "etapa_id": "uuid"}  (null=todas)
    -- MONTO_SUPERA:         {"monto": 5000}
    -- SCORE_UMBRAL:         {"score_min": 70}
  accion        JSONB NOT NULL,
    -- {"tipo": "NOTIFICAR", "destinatarios": ["responsable", "supervisor"]}
    -- {"tipo": "CREAR_TAREA", "asunto": "Seguimiento urgente", "dias": 1}
    -- {"tipo": "CAMBIAR_ETAPA", "etapa_id": "uuid"}
    -- {"tipo": "REASIGNAR", "usuario_id": "uuid"}
    -- Acciones: NOTIFICAR | CREAR_TAREA | CAMBIAR_ETAPA | REASIGNAR
  activa        BOOLEAN NOT NULL DEFAULT true,
  ultima_ejecucion_at TIMESTAMPTZ,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE automatizaciones_crm ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON automatizaciones_crm
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE INDEX idx_automatizaciones_crm_empresa
  ON automatizaciones_crm(empresa_id) WHERE activa = true;
```

### segmentos_clientes

Grupos dinámicos de contactos según criterios configurables.

```sql
CREATE TABLE segmentos_clientes (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id        UUID NOT NULL REFERENCES empresas(id),
  nombre            VARCHAR(200) NOT NULL,
  descripcion       TEXT,
  criterios         JSONB NOT NULL DEFAULT '[]',
    -- [
    --   {"campo": "compras_anual", "operador": ">",  "valor": "50000"},
    --   {"campo": "ultima_compra", "operador": "<",  "valor": "90"},   (dias)
    --   {"campo": "provincia",     "operador": "=",  "valor": "PICHINCHA"}
    -- ]
  auto_actualizar   BOOLEAN NOT NULL DEFAULT false,
    -- Si true, se recalcula diariamente via Edge Function cron
  total_contactos   INTEGER NOT NULL DEFAULT 0,
  ultima_actualizacion_at TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE segmento_miembros (
  segmento_id   UUID NOT NULL REFERENCES segmentos_clientes(id) ON DELETE CASCADE,
  contacto_id   UUID NOT NULL REFERENCES contactos(id),
  empresa_id    UUID NOT NULL REFERENCES empresas(id),
  fecha_ingreso DATE NOT NULL DEFAULT CURRENT_DATE,
  PRIMARY KEY(segmento_id, contacto_id)
);

ALTER TABLE segmentos_clientes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON segmentos_clientes
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

ALTER TABLE segmento_miembros ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON segmento_miembros
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE INDEX idx_segmento_miembros_segmento ON segmento_miembros(segmento_id);
CREATE INDEX idx_segmento_miembros_contacto ON segmento_miembros(empresa_id, contacto_id);
```

### plantillas_email y campanas_email (Email Marketing)

```sql
CREATE TABLE plantillas_email (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  nombre          VARCHAR(200) NOT NULL,
  contenido_html  TEXT NOT NULL,
  vista_previa    TEXT,
  variables       JSONB NOT NULL DEFAULT '[]',
    -- [{"nombre": "nombre_cliente", "descripcion": "Nombre completo del contacto"}]
  activa          BOOLEAN NOT NULL DEFAULT true,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE campanas_email (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id        UUID NOT NULL REFERENCES empresas(id),
  campana_crm_id    UUID REFERENCES campanas_crm(id),
  segmento_id       UUID REFERENCES segmentos_clientes(id),
  plantilla_id      UUID REFERENCES plantillas_email(id),
  asunto            VARCHAR(300) NOT NULL,
  contenido_html    TEXT,
  estado            VARCHAR(20) NOT NULL DEFAULT 'BORRADOR',
    -- BORRADOR | PROGRAMADA | ENVIANDO | ENVIADA | CANCELADA
  fecha_envio       TIMESTAMPTZ,  -- Programación futura (NULL = inmediato)
  total_enviados    INTEGER NOT NULL DEFAULT 0,
  total_abiertos    INTEGER NOT NULL DEFAULT 0,  -- Tracking por pixel 1x1
  total_clicks      INTEGER NOT NULL DEFAULT 0,  -- Tracking por link wrapping
  total_rebotados   INTEGER NOT NULL DEFAULT 0,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE plantillas_email ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON plantillas_email
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

ALTER TABLE campanas_email ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON campanas_email
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE INDEX idx_campanas_email_empresa ON campanas_email(empresa_id, estado);
```

---

## Funciones RPC

### get_pipeline_by_stage — Tablero Kanban

```sql
CREATE OR REPLACE FUNCTION crm.get_pipeline_by_stage(
  p_empresa_id    UUID,
  p_responsable_id UUID DEFAULT NULL,   -- NULL = todas las oportunidades del equipo
  p_estado        VARCHAR DEFAULT 'ACTIVA'
) RETURNS JSONB  -- [{etapa_id, etapa_nombre, color, total, monto, oportunidades: [...]}]
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN (
    SELECT jsonb_agg(
      jsonb_build_object(
        'etapa_id',     e.id,
        'etapa_nombre', e.nombre,
        'orden',        e.orden,
        'color',        e.color,
        'es_ganada',    e.es_ganada,
        'es_perdida',   e.es_perdida,
        'total',        COUNT(o.id),
        'monto_total',  COALESCE(SUM(o.valor_estimado), 0),
        'monto_pond',   COALESCE(SUM(o.valor_ponderado), 0),
        'oportunidades', (
          SELECT jsonb_agg(
            jsonb_build_object(
              'id',              o2.id,
              'nombre',          o2.nombre,
              'contacto',        c.razon_social,
              'responsable',     u.email,
              'valor_estimado',  o2.valor_estimado,
              'probabilidad',    o2.probabilidad,
              'score',           o2.score,
              'dias_en_etapa',   CURRENT_DATE - o2.updated_at::date,
              'fecha_cierre_esp', o2.fecha_cierre_esperada,
              'origen',          o2.origen,
              'proximo_seguim',  o2.proximo_seguimiento_at
            )
            ORDER BY o2.valor_estimado DESC
          )
          FROM oportunidades o2
          JOIN contactos c ON c.id = o2.contacto_id
          JOIN auth.users u ON u.id = o2.responsable_id
          WHERE o2.empresa_id = p_empresa_id
            AND o2.etapa_id = e.id
            AND o2.estado = p_estado
            AND (p_responsable_id IS NULL OR o2.responsable_id = p_responsable_id)
        )
      )
      ORDER BY e.orden
    )
    FROM etapas_pipeline e
    LEFT JOIN oportunidades o ON o.etapa_id = e.id
      AND o.empresa_id = p_empresa_id
      AND o.estado = p_estado
      AND (p_responsable_id IS NULL OR o.responsable_id = p_responsable_id)
    WHERE e.empresa_id = p_empresa_id AND e.activa = true
    GROUP BY e.id, e.nombre, e.orden, e.color, e.es_ganada, e.es_perdida
  );
END;
$$;
```

### convert_to_quotation — Convertir Oportunidad en Cotización

```sql
CREATE OR REPLACE FUNCTION crm.convert_to_quotation(
  p_empresa_id     UUID,
  p_oportunidad_id UUID,
  p_vendedor_id    UUID DEFAULT NULL
) RETURNS UUID  -- cotizacion_id
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_op          RECORD;
  v_cotizacion_id UUID;
  v_numero      VARCHAR;
BEGIN
  SELECT o.*, c.razon_social AS cliente_nombre
  INTO v_op
  FROM oportunidades o
  JOIN contactos c ON c.id = o.contacto_id
  WHERE o.id = p_oportunidad_id AND o.empresa_id = p_empresa_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Oportunidad % no encontrada', p_oportunidad_id;
  END IF;

  IF v_op.estado NOT IN ('ACTIVA') THEN
    RAISE EXCEPTION 'Solo se puede convertir oportunidades ACTIVAS (estado: %)', v_op.estado;
  END IF;

  -- Generar número de cotización (via secuencia del módulo Ventas)
  SELECT module_bus.ventas_next_cotizacion_number(p_empresa_id) INTO v_numero;

  -- Crear cotización en Ventas (via Module Service Bus)
  SELECT module_bus.ventas_create_cotizacion(
    p_empresa_id    := p_empresa_id,
    p_contacto_id   := v_op.contacto_id,
    p_vendedor_id   := COALESCE(p_vendedor_id, v_op.responsable_id),
    p_numero        := v_numero,
    p_oportunidad_id := p_oportunidad_id
  ) INTO v_cotizacion_id;

  -- Vincular cotización a la oportunidad
  INSERT INTO oportunidad_cotizaciones(
    empresa_id, oportunidad_id, cotizacion_id, version
  ) VALUES (
    p_empresa_id, p_oportunidad_id, v_cotizacion_id, 1
  );

  -- Registrar actividad automática
  INSERT INTO actividades_crm(
    empresa_id, oportunidad_id, tipo, asunto,
    responsable_id, estado, fecha_realizada
  ) VALUES (
    p_empresa_id, p_oportunidad_id, 'NOTA',
    'Cotización generada: ' || v_numero,
    COALESCE(p_vendedor_id, v_op.responsable_id),
    'REALIZADA', now()
  );

  RETURN v_cotizacion_id;
END;
$$;
```

### mark_won — Marcar oportunidad como ganada

```sql
CREATE OR REPLACE FUNCTION crm.mark_won(
  p_empresa_id     UUID,
  p_oportunidad_id UUID,
  p_orden_venta_id UUID DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_etapa_ganada UUID;
BEGIN
  SELECT id INTO v_etapa_ganada
  FROM etapas_pipeline
  WHERE empresa_id = p_empresa_id AND es_ganada = true
  LIMIT 1;

  UPDATE oportunidades
  SET estado = 'GANADA',
      etapa_id = v_etapa_ganada,
      probabilidad = 100.00,
      fecha_cierre_real = CURRENT_DATE,
      version = version + 1,
      updated_at = now()
  WHERE id = p_oportunidad_id AND empresa_id = p_empresa_id;

  -- Si hay OV asociada, marcar la cotización ganadora
  IF p_orden_venta_id IS NOT NULL THEN
    UPDATE oportunidad_cotizaciones
    SET es_ganadora = false
    WHERE oportunidad_id = p_oportunidad_id;
    -- La cotización ganadora se marca mediante el cotizacion_id de la OV
  END IF;
END;
$$;
```

### mark_lost — Marcar oportunidad como perdida

```sql
CREATE OR REPLACE FUNCTION crm.mark_lost(
  p_empresa_id     UUID,
  p_oportunidad_id UUID,
  p_motivo_perdida VARCHAR DEFAULT NULL,
  p_competidor     VARCHAR DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_etapa_perdida UUID;
BEGIN
  SELECT id INTO v_etapa_perdida
  FROM etapas_pipeline
  WHERE empresa_id = p_empresa_id AND es_perdida = true
  LIMIT 1;

  UPDATE oportunidades
  SET estado = 'PERDIDA',
      etapa_id = v_etapa_perdida,
      probabilidad = 0.00,
      fecha_cierre_real = CURRENT_DATE,
      motivo_perdida = p_motivo_perdida,
      competidor = p_competidor,
      version = version + 1,
      updated_at = now()
  WHERE id = p_oportunidad_id AND empresa_id = p_empresa_id;
END;
$$;
```

### get_activity_calendar — Calendario de actividades

```sql
CREATE OR REPLACE FUNCTION crm.get_activity_calendar(
  p_empresa_id     UUID,
  p_responsable_id UUID,
  p_fecha_inicio   DATE,
  p_fecha_fin      DATE
) RETURNS JSONB  -- [{id, tipo, asunto, fecha_programada, oportunidad, contacto, estado}]
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN (
    SELECT jsonb_agg(
      jsonb_build_object(
        'id',               a.id,
        'tipo',             a.tipo,
        'asunto',           a.asunto,
        'descripcion',      a.descripcion,
        'fecha_programada', a.fecha_programada,
        'duracion_minutos', a.duracion_minutos,
        'estado',           a.estado,
        'oportunidad_id',   a.oportunidad_id,
        'oportunidad_nombre', o.nombre,
        'contacto_id',      o.contacto_id,
        'contacto_nombre',  c.razon_social,
        'score',            o.score
      )
      ORDER BY a.fecha_programada ASC
    )
    FROM actividades_crm a
    JOIN oportunidades o ON o.id = a.oportunidad_id
    JOIN contactos c ON c.id = o.contacto_id
    WHERE a.empresa_id = p_empresa_id
      AND a.responsable_id = p_responsable_id
      AND a.fecha_programada::date BETWEEN p_fecha_inicio AND p_fecha_fin
      AND a.estado != 'CANCELADA'
  );
END;
$$;
```

### calculate_lead_score — Calcular score de un contacto

```sql
CREATE OR REPLACE FUNCTION crm.calculate_lead_score(
  p_empresa_id  UUID,
  p_contacto_id UUID
) RETURNS DECIMAL(5,2)  -- Score 0-100
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_score       DECIMAL(5,2) := 0;
  v_criterio    RECORD;
  v_valor_campo TEXT;
  v_factores    JSONB := '{}';
  v_sugerencia  TEXT;
BEGIN
  -- Evaluar cada criterio activo de la empresa
  FOR v_criterio IN
    SELECT * FROM criterios_scoring
    WHERE empresa_id = p_empresa_id AND activo = true
  LOOP
    -- La lógica real consulta el contacto + su historial en la BD
    -- Aquí se muestra el patrón; la implementación completa usa CASE dinámico
    -- según v_criterio.campo (industria, cargo, compras_ultimo_anio, etc.)
    CONTINUE;  -- Placeholder: la implementación real calcula v_valor_campo
  END LOOP;

  -- Normalizar a rango 0-100
  v_score := LEAST(GREATEST(v_score, 0), 100);

  -- Generar sugerencia basada en el score
  v_sugerencia := CASE
    WHEN v_score >= 80 THEN 'Lead caliente: contactar esta semana con propuesta concreta'
    WHEN v_score >= 60 THEN 'Lead tibio: programar demo o reunión de seguimiento'
    WHEN v_score >= 40 THEN 'Lead frío: incluir en campaña de nurturing automático'
    ELSE 'Lead muy frío: bajo prioridad, incluir en newsletter mensual'
  END;

  -- Actualizar o insertar en crm_scoring
  INSERT INTO crm_scoring(empresa_id, contacto_id, score, factores, proxima_accion_sugerida)
  VALUES (p_empresa_id, p_contacto_id, v_score, v_factores, v_sugerencia)
  ON CONFLICT (empresa_id, contacto_id) DO UPDATE
  SET score = EXCLUDED.score,
      factores = EXCLUDED.factores,
      proxima_accion_sugerida = EXCLUDED.proxima_accion_sugerida,
      fecha_calculo = now();

  RETURN v_score;
END;
$$;
```

### recalculate_all_scores — Recalcular scores de toda la empresa

```sql
CREATE OR REPLACE FUNCTION crm.recalculate_all_scores(
  p_empresa_id UUID
) RETURNS JSONB  -- {actualizadas: N, promedio_score: X}
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_contacto    RECORD;
  v_count       INTEGER := 0;
  v_total_score DECIMAL := 0;
BEGIN
  FOR v_contacto IN
    SELECT DISTINCT contacto_id
    FROM oportunidades
    WHERE empresa_id = p_empresa_id AND estado = 'ACTIVA'
  LOOP
    v_total_score := v_total_score + crm.calculate_lead_score(p_empresa_id, v_contacto.contacto_id);
    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'actualizadas', v_count,
    'promedio_score', CASE WHEN v_count > 0 THEN ROUND(v_total_score / v_count, 2) ELSE 0 END
  );
END;
$$;
```

### get_customer_360 — Ficha unificada del cliente

```sql
CREATE OR REPLACE FUNCTION crm.get_customer_360(
  p_empresa_id  UUID,
  p_contacto_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN jsonb_build_object(
    'datos_basicos', (
      SELECT row_to_json(c) FROM contactos c
      WHERE c.id = p_contacto_id AND c.empresa_id = p_empresa_id
    ),
    'scoring', (
      SELECT row_to_json(s) FROM crm_scoring s
      WHERE s.contacto_id = p_contacto_id AND s.empresa_id = p_empresa_id
    ),
    'oportunidades_activas', (
      SELECT jsonb_agg(row_to_json(o))
      FROM oportunidades o
      WHERE o.contacto_id = p_contacto_id
        AND o.empresa_id = p_empresa_id
        AND o.estado = 'ACTIVA'
    ),
    'facturas_recientes', (
      SELECT jsonb_agg(row_to_json(f))
      FROM (
        SELECT id, numero, fecha, total, estado_sri, estado_pago
        FROM facturas
        WHERE contacto_id = p_contacto_id AND empresa_id = p_empresa_id
        ORDER BY fecha DESC LIMIT 10
      ) f
    ),
    'cxc_pendientes', (
      SELECT jsonb_agg(
        jsonb_build_object(
          'factura_id', cxc.factura_id,
          'saldo_pendiente', cxc.saldo_pendiente,
          'fecha_vencimiento', cxc.fecha_vencimiento,
          'dias_vencido', GREATEST(0, CURRENT_DATE - cxc.fecha_vencimiento)
        )
      )
      FROM cuentas_por_cobrar cxc
      WHERE cxc.contacto_id = p_contacto_id
        AND cxc.empresa_id = p_empresa_id
        AND cxc.estado != 'PAGADA'
    ),
    'lifetime_value', (
      SELECT COALESCE(SUM(total), 0)
      FROM facturas
      WHERE contacto_id = p_contacto_id
        AND empresa_id = p_empresa_id
        AND estado_sri = 'AUTORIZADA'
    ),
    'ultima_compra', (
      SELECT MAX(fecha) FROM facturas
      WHERE contacto_id = p_contacto_id AND empresa_id = p_empresa_id
    ),
    'actividades_recientes', (
      SELECT jsonb_agg(row_to_json(a))
      FROM (
        SELECT a.tipo, a.asunto, a.fecha_realizada, a.estado, a.resultado
        FROM actividades_crm a
        JOIN oportunidades o ON o.id = a.oportunidad_id
        WHERE o.contacto_id = p_contacto_id AND a.empresa_id = p_empresa_id
        ORDER BY a.created_at DESC LIMIT 5
      ) a
    )
  );
END;
$$;
```

### refresh_segment — Recalcular miembros de un segmento

```sql
CREATE OR REPLACE FUNCTION crm.refresh_segment(
  p_empresa_id   UUID,
  p_segmento_id  UUID
) RETURNS JSONB  -- {agregados: N, removidos: N, total: N}
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_seg     RECORD;
  v_previos INTEGER;
  v_nuevos  INTEGER;
BEGIN
  SELECT * INTO v_seg FROM segmentos_clientes
  WHERE id = p_segmento_id AND empresa_id = p_empresa_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Segmento % no encontrado', p_segmento_id;
  END IF;

  -- Contar previos
  SELECT COUNT(*) INTO v_previos FROM segmento_miembros WHERE segmento_id = p_segmento_id;

  -- Limpiar y repoblar (la evaluación real de criterios JSONB requiere lógica dinámica)
  DELETE FROM segmento_miembros WHERE segmento_id = p_segmento_id;

  -- Insertar nuevos miembros según criterios del segmento
  -- (implementación real evalúa cada criterio del JSONB v_seg.criterios)
  -- INSERT INTO segmento_miembros ...

  SELECT COUNT(*) INTO v_nuevos FROM segmento_miembros WHERE segmento_id = p_segmento_id;

  -- Actualizar total en la tabla padre
  UPDATE segmentos_clientes
  SET total_contactos = v_nuevos,
      ultima_actualizacion_at = now()
  WHERE id = p_segmento_id;

  RETURN jsonb_build_object(
    'previos', v_previos,
    'nuevos', v_nuevos,
    'diferencia', v_nuevos - v_previos
  );
END;
$$;
```

---

## Triggers

### Trigger: actualizar updated_at y version en oportunidades

```sql
CREATE OR REPLACE FUNCTION crm.trg_oportunidades_update_fn()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  -- Bloqueo optimista
  IF NEW.version != OLD.version THEN
    RAISE EXCEPTION 'Conflicto de concurrencia: oportunidad % fue modificada por otro usuario', OLD.id;
  END IF;
  NEW.version := OLD.version + 1;
  NEW.updated_at := now();
  -- Sincronizar probabilidad desde etapa al cambiar de etapa
  IF NEW.etapa_id IS DISTINCT FROM OLD.etapa_id THEN
    SELECT probabilidad_default INTO NEW.probabilidad
    FROM etapas_pipeline WHERE id = NEW.etapa_id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_oportunidades_update
  BEFORE UPDATE ON oportunidades
  FOR EACH ROW EXECUTE FUNCTION crm.trg_oportunidades_update_fn();
```

### Trigger: crear actividad de seguimiento automático

```sql
CREATE OR REPLACE FUNCTION crm.trg_actividad_seguimiento_fn()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  -- Al completar una actividad con crear_seguimiento=true
  IF NEW.estado = 'REALIZADA' AND OLD.estado = 'PENDIENTE'
     AND NEW.crear_seguimiento = true
     AND NEW.seguimiento_tipo IS NOT NULL THEN
    INSERT INTO actividades_crm(
      empresa_id, oportunidad_id, tipo, asunto,
      responsable_id, fecha_programada, estado, created_by
    ) VALUES (
      NEW.empresa_id,
      NEW.oportunidad_id,
      NEW.seguimiento_tipo,
      'Seguimiento: ' || NEW.asunto,
      NEW.responsable_id,
      now() + (COALESCE(NEW.seguimiento_dias, 3) || ' days')::INTERVAL,
      'PENDIENTE',
      NEW.responsable_id
    );
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_actividad_seguimiento
  AFTER UPDATE ON actividades_crm
  FOR EACH ROW EXECUTE FUNCTION crm.trg_actividad_seguimiento_fn();
```

### Trigger: actualizar métricas de campaña

```sql
CREATE OR REPLACE FUNCTION crm.trg_campana_contactos_metricas_fn()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  UPDATE campanas_crm SET
    total_enviados   = (SELECT COUNT(*) FROM campana_contactos WHERE campana_id = NEW.campana_id AND estado != 'PENDIENTE'),
    total_abiertos   = (SELECT COUNT(*) FROM campana_contactos WHERE campana_id = NEW.campana_id AND estado IN ('ABIERTO', 'RESPONDIDO', 'CONVERTIDO')),
    total_respondidos = (SELECT COUNT(*) FROM campana_contactos WHERE campana_id = NEW.campana_id AND estado IN ('RESPONDIDO', 'CONVERTIDO')),
    total_convertidos = (SELECT COUNT(*) FROM campana_contactos WHERE campana_id = NEW.campana_id AND estado = 'CONVERTIDO'),
    total_rebotados  = (SELECT COUNT(*) FROM campana_contactos WHERE campana_id = NEW.campana_id AND estado = 'REBOTADO'),
    updated_at = now()
  WHERE id = NEW.campana_id;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_campana_contactos_metricas
  AFTER INSERT OR UPDATE ON campana_contactos
  FOR EACH ROW EXECUTE FUNCTION crm.trg_campana_contactos_metricas_fn();
```

---

## Row Level Security (Completo)

```sql
-- oportunidades
ALTER TABLE oportunidades ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON oportunidades
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- etapas_pipeline
ALTER TABLE etapas_pipeline ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON etapas_pipeline
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- actividades_crm
ALTER TABLE actividades_crm ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON actividades_crm
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- campanas_crm
ALTER TABLE campanas_crm ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON campanas_crm
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- campana_contactos
ALTER TABLE campana_contactos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON campana_contactos
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- crm_scoring
ALTER TABLE crm_scoring ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON crm_scoring
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- criterios_scoring
ALTER TABLE criterios_scoring ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON criterios_scoring
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- automatizaciones_crm
ALTER TABLE automatizaciones_crm ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON automatizaciones_crm
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- oportunidad_cotizaciones
ALTER TABLE oportunidad_cotizaciones ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON oportunidad_cotizaciones
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- segmentos_clientes + segmento_miembros (ya definidos arriba)
-- plantillas_email + campanas_email (ya definidos arriba)
```

---

## Module Service Bus

CRM es módulo **Auxiliar**: NUNCA inserta directamente en tablas de módulos Core.

```sql
-- CRM → Ventas: crear cotización desde oportunidad
-- CRM NUNCA inserta en `cotizaciones` directamente
CREATE OR REPLACE FUNCTION module_bus.ventas_create_cotizacion(
  p_empresa_id     UUID,
  p_contacto_id    UUID,
  p_vendedor_id    UUID,
  p_numero         VARCHAR,
  p_oportunidad_id UUID DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_cotizacion_id UUID;
BEGIN
  -- Verificar que módulo Ventas esté activo para esta empresa
  IF NOT EXISTS (
    SELECT 1 FROM modulos_empresa me
    JOIN modulos m ON m.id = me.modulo_id
    WHERE me.empresa_id = p_empresa_id AND m.codigo = 'VENTAS' AND me.activo = true
  ) THEN
    RAISE EXCEPTION 'Módulo Ventas no está activo para esta empresa';
  END IF;

  INSERT INTO cotizaciones(empresa_id, numero, contacto_id, vendedor_id, oportunidad_id)
  VALUES (p_empresa_id, p_numero, p_contacto_id, p_vendedor_id, p_oportunidad_id)
  RETURNING id INTO v_cotizacion_id;

  RETURN v_cotizacion_id;
END;
$$;

-- CRM → Comunicación: enviar campaña
CREATE OR REPLACE FUNCTION module_bus.crm_send_campaign(
  p_empresa_id  UUID,
  p_campana_id  UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_campana RECORD;
  v_contacto RECORD;
  v_encolados INTEGER := 0;
BEGIN
  SELECT * INTO v_campana FROM campanas_crm
  WHERE id = p_campana_id AND empresa_id = p_empresa_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Campaña % no encontrada', p_campana_id;
  END IF;

  -- Para cada contacto de la campaña
  FOR v_contacto IN
    SELECT cc.contacto_id FROM campana_contactos cc
    WHERE cc.campana_id = p_campana_id AND cc.estado = 'PENDIENTE'
  LOOP
    -- Delegar envío al módulo Comunicación (siempre activo)
    PERFORM module_bus.comunicacion_notify(
      p_empresa_id      := p_empresa_id,
      p_contacto_id     := v_contacto.contacto_id,
      p_tipo_evento     := 'custom',
      p_variables       := jsonb_build_object('campana_nombre', v_campana.nombre),
      p_referencia_id   := p_campana_id,
      p_referencia_tipo := 'campanas_crm'
    );

    UPDATE campana_contactos
    SET estado = 'ENVIADO', enviado_at = now()
    WHERE campana_id = p_campana_id AND contacto_id = v_contacto.contacto_id;

    v_encolados := v_encolados + 1;
  END LOOP;

  UPDATE campanas_crm SET estado = 'ACTIVA', updated_at = now()
  WHERE id = p_campana_id;

  RETURN jsonb_build_object('encolados', v_encolados);
END;
$$;

-- CRM → IA: solicitar scoring (si módulo IA activo)
CREATE OR REPLACE FUNCTION module_bus.crm_request_ai_scoring(
  p_empresa_id  UUID,
  p_contacto_id UUID
) RETURNS DECIMAL(5,2)
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  -- Si módulo IA está activo, usa scoring IA avanzado
  IF EXISTS (
    SELECT 1 FROM modulos_empresa me
    JOIN modulos m ON m.id = me.modulo_id
    WHERE me.empresa_id = p_empresa_id AND m.codigo = 'IA_CHAT' AND me.activo = true
  ) THEN
    -- Llamar a Edge Function ai-score-lead (asíncrono, actualiza crm_scoring)
    -- En la práctica se hace via pg_net o encola en cola_notificaciones
    RETURN NULL;  -- Score se actualiza asincrónamente
  ELSE
    -- Scoring básico por reglas (síncrono)
    RETURN crm.calculate_lead_score(p_empresa_id, p_contacto_id);
  END IF;
END;
$$;
```

---

## Pipeline Conversión: Oportunidad → Cotización → OV

```
Lead capturado (origen: WEBSITE/LLAMADA/REFERIDO/ECOMMERCE/FERIA)
  → Se crea en oportunidades (estado: ACTIVA, etapa: Prospecto)
  → Se asigna responsable (vendedor)
  ↓
Actividades de seguimiento (LLAMADA, REUNION, DEMO)
  → Se registran en actividades_crm
  → Si crear_seguimiento=true: genera actividad automática de seguimiento
  ↓
Avanzar etapas (Prospecto → Calificado → Propuesta)
  → probabilidad se actualiza automáticamente desde etapa_pipeline.probabilidad_default
  ↓
crm.convert_to_quotation(oportunidad_id)
  → Llama module_bus.ventas_create_cotizacion()
  → Se crea cotización en módulo Ventas con oportunidad_id
  → Se registra en oportunidad_cotizaciones (puede haber N versiones)
  ↓
Cliente aprueba cotización
  → En módulo Ventas: cotizacion.estado = APROBADA
  → Ventas crea Orden de Venta
  → Ventas llama module_bus.facturacion.create_invoice()
  ↓
CRM recibe evento vía Realtime (o webhook interno)
  → crm.mark_won(oportunidad_id, orden_venta_id)
  → oportunidades.estado = GANADA, etapa → Ganado
  → Se actualiza campana_contactos.estado = CONVERTIDO (si aplica)
```

---

## Integraciones con Otros Módulos

### CRM → Ventas

```sql
-- Cotización aprobada en Ventas actualiza oportunidad en CRM
-- (via trigger en cotizaciones o Realtime listener)
UPDATE oportunidades
SET estado = 'GANADA',
    fecha_cierre_real = CURRENT_DATE
WHERE id = cotizacion.oportunidad_id;
```

### CRM → Ecommerce

```
Pedido web creado en Ecommerce
  → module_bus.crm_create_opportunity_from_ecommerce(empresa_id, pedido_id)
  → Crea oportunidad con origen='ECOMMERCE', contacto del pedido
  → Crea actividad automática: tipo='TAREA', asunto='Dar seguimiento a pedido web'
```

### CRM → Comunicación

```
Campaña enviada → module_bus.crm_send_campaign(empresa_id, campana_id)
  → Para cada contacto: module_bus.comunicacion_notify(tipo_evento='custom')
  → Comunicación envía por canales activos del contacto (EMAIL/WHATSAPP/TELEGRAM)

Automatización disparada → module_bus.comunicacion_notify(
  tipo_evento='alerta_crm',
  variables={oportunidad_nombre, dias_sin_actividad, responsable}
)
```

### CRM → IA/Chat (si módulo activo)

```
Noche (cron Edge Function 'process-crm-automations'):
  → Para cada oportunidad activa:
    → module_bus.crm_request_ai_scoring(empresa_id, contacto_id)
    → Si score >= 70 y sin actividad en 3 días:
      → module_bus.comunicacion_notify(tipo_evento='alerta_credito')
    → Evalúa automatizaciones_crm activas
    → Ejecuta acciones (NOTIFICAR / CREAR_TAREA / CAMBIAR_ETAPA)
```

---

## Segmentación de Clientes

Ejemplos de segmentos predefinidos:

| Nombre | Criterios | Uso |
|--------|-----------|-----|
| **VIP** | `compras_anual > 50000` | Campaña de fidelización premium |
| **Dormidos** | `dias_ultima_compra > 90` | Re-activación con descuento |
| **Nuevos (último mes)** | `primera_compra >= hoy-30d` | Welcome campaign |
| **Alto score** | `crm_scoring.score >= 70` | Priorizar llamadas de ventas |
| **Crédito vencido** | `cxc_vencidas > 0` | Gestión de cobranza |
| **Pichincha** | `provincia = PICHINCHA` | Campaña regional |

---

## Email Marketing Integrado

Flujo de envío de campaña de email:

```
1. Configurar plantilla HTML en plantillas_email
2. Crear campaña en campanas_email:
   - Seleccionar segmento (segmento_id)
   - Asignar plantilla y asunto
   - Programar fecha_envio (o enviar inmediatamente)
3. Edge Function 'send-email-campaign':
   - Lee miembros del segmento
   - Para cada contacto: sustituye variables + llama send-email via Resend
   - Inserta pixel 1x1 en email (tracking de apertura)
   - Usa link wrapping para tracking de clicks
4. Webhooks de Resend → Edge Function 'resend-webhook':
   - event: 'email.opened' → campanas_email.total_abiertos++
   - event: 'email.clicked' → campanas_email.total_clicks++
   - event: 'email.bounced' → campanas_email.total_rebotados++, marcar contacto
```

---

## KPIs y Dashboard

### Métricas de Pipeline

| KPI | Fórmula | Widget Flutter |
|-----|---------|----------------|
| Pipeline Value | `SUM(valor_estimado)` oportunidades ACTIVAS | Card con monto total |
| Pipeline Ponderado | `SUM(valor_ponderado)` | Card con monto ponderado |
| Tasa de Conversión | `GANADAS / (GANADAS + PERDIDAS)` último trimestre | SfCircularChart |
| Tiempo Medio de Cierre | `AVG(fecha_cierre_real - fecha_creacion)` GANADAS | Card con días promedio |
| Actividades Vencidas | `COUNT(actividades)` PENDIENTE con `fecha_programada < now()` | Badge rojo en nav |

### Métricas de Campañas

| KPI | Fórmula |
|-----|---------|
| Open Rate | `total_abiertos / total_enviados * 100` |
| Click Rate | `total_clicks / total_abiertos * 100` |
| Conversion Rate | `total_convertidos / total_enviados * 100` |
| ROI Campaña | `(valor_negocios_convertidos - costo_real) / costo_real * 100` |

---

## UI/UX (Flutter + Material 3)

### Tablero Kanban

```dart
// features/crm/widgets/kanban_board.dart
// Columnas = etapas del pipeline, Cards = oportunidades
// Drag-and-drop en desktop/tablet: mover oportunidad entre etapas

class KanbanBoard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pipeline = ref.watch(pipelineProvider);
    return pipeline.when(
      data: (etapas) => Row(
        children: etapas.map((etapa) => KanbanColumn(
          etapa: etapa,
          oportunidades: etapa.oportunidades,
          onDropped: (opId) => ref.read(pipelineProvider.notifier)
              .moveToStage(opId, etapa.id),
        )).toList(),
      ),
      loading: (_) => const CircularProgressIndicator(),
      error: (e, _) => Text('Error: $e'),
    );
  }
}
```

### Lead Score Badge

```dart
// Badge visual: color depende del score
Color _scoreColor(double score) => switch (score) {
  >= 80 => Colors.green,
  >= 60 => Colors.orange,
  >= 40 => Colors.amber,
  _     => Colors.grey,
};
```

### Adaptación Responsive

| Elemento | COMPACT (<600px) | EXPANDED (>840px) |
|----------|-----------------|------------------|
| Pipeline | Lista vertical por etapa | Kanban horizontal con columnas |
| Detalle oportunidad | Full screen | Panel dividido 60/40 |
| Actividades | Tab dentro del detalle | Panel lateral |
| Calendario | Bottom sheet | SfCalendar completo |

---

## Edge Functions

| Función | Descripción | Trigger |
|---------|-------------|---------|
| `process-crm-automations/index.ts` | Evalúa automatizaciones activas, ejecuta acciones | Cron diario 08:00 |
| `refresh-segments/index.ts` | Recalcula miembros de segmentos con `auto_actualizar=true` | Cron diario 02:00 |
| `send-email-campaign/index.ts` | Envía campaña de email a segmento via Resend | Disparado por fecha_envio o manualmente |
| `resend-webhook/index.ts` | Recibe webhooks de Resend (opened, clicked, bounced) | Webhook Resend |
| `ai-score-leads/index.ts` | Calcula score IA para oportunidades activas (si módulo IA activo) | Cron nocturno o bajo demanda |
