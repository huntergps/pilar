# Módulo Comunicación (Infraestructura #3)

Módulo de **Infraestructura siempre activo** (no desactivable). Provee la capa de mensajería multi-canal, chat interno en tiempo real y push notifications a todos los demás módulos del sistema PILAR ERP. Ningún módulo gestiona sus propios envíos: siempre llaman a `module_bus.comunicacion.notify()` o a la función RPC `send_notification()`.

---

## Canales Soportados

| Canal | Proveedor | Tipo | Destinatario |
|-------|-----------|------|--------------|
| Email | Resend API | Transaccional / Marketing | contacto.email |
| WhatsApp | Meta Cloud API | Transaccional | contacto.telefono (E.164) |
| Telegram | Bot API | Transaccional | contacto.telegram_chat_id |
| Push (FCM) | Firebase Cloud Messaging | Push móvil | device_tokens |
| Chat interno | Supabase Realtime (Broadcast) | Tiempo real | usuarios del ERP |

---

## Eventos de Notificación Registrados

Cualquier módulo puede registrar un tipo de evento. Los eventos estándar del sistema son:

| tipo_evento | Módulo Origen | Descripción |
|-------------|--------------|-------------|
| `factura_autorizada` | Facturación | Factura autorizada por el SRI |
| `factura_rechazada` | Facturación | Factura rechazada por el SRI |
| `cobro_registrado` | Ventas/Tesorería | Se registró un cobro a una factura |
| `cotizacion_enviada` | Ventas | Proforma enviada al cliente |
| `orden_venta_confirmada` | Ventas | OV confirmada y en preparación |
| `pago_proveedor_programado` | Tesorería | Pago a proveedor programado |
| `stock_bajo_minimo` | Inventario | Producto por debajo de stock mínimo |
| `documento_sri_firmado` | Facturación | XML firmado y enviado al SRI |
| `retencion_generada` | Compras | Comprobante de retención generado |
| `cita_confirmada` | Citas | Cita confirmada al cliente |
| `cita_recordatorio_24h` | Citas | Recordatorio 24h antes de la cita |
| `cita_recordatorio_2h` | Citas | Recordatorio 2h antes de la cita |
| `orden_campo_asignada` | Servicio de Campo | Orden de campo asignada a técnico |
| `nomina_lista` | RRHH | Rol de pagos listo para aprobación |
| `suscripcion_vence` | Suscripciones | Contrato próximo a vencer |
| `mensaje_chat` | Comunicación | Nuevo mensaje en canal de chat |
| `alerta_credito` | Ventas | Cliente supera límite de crédito |
| `rma_aprobado` | Garantías/RMA | Solicitud RMA aprobada |
| `custom` | Cualquier módulo | Evento personalizado de la empresa |

---

## Navegación (Flutter)

```
comunicacion/
  ├── chat/
  │     ├── listado-canales/        # Lista canales y conversaciones (con badge de no leídos)
  │     ├── canal/                  # Vista de mensajes de un canal (Realtime)
  │     │     ├── mensajes/         # SfChat o ListView con burbujas
  │     │     ├── miembros/         # Panel lateral de miembros
  │     │     └── archivos/         # Adjuntos del canal
  │     └── nuevo-canal/            # Crear canal GENERAL/GRUPO/DIRECTO
  ├── notificaciones/
  │     ├── historial/              # Log de notificaciones enviadas (SfDataGrid)
  │     ├── plantillas/             # CRUD de plantillas por tipo_evento y canal
  │     └── configuracion/          # Config por contacto (canales activos)
  └── configuracion/
        ├── canales-globales/       # Credenciales Resend, Meta, FCM, Telegram
        └── preferencias-usuario/   # Push on/off, horario silencio
```

---

## Modelo de Datos

### configuracion_notificaciones

Canales habilitados por contacto. Un contacto puede tener múltiples filas (uno por canal).

```sql
CREATE TABLE configuracion_notificaciones (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id    UUID NOT NULL REFERENCES empresas(id),
  contacto_id   UUID NOT NULL REFERENCES contactos(id) ON DELETE CASCADE,
  canal         VARCHAR(20) NOT NULL,
    -- EMAIL | WHATSAPP | TELEGRAM | PUSH
  activo        BOOLEAN NOT NULL DEFAULT true,
  -- Datos de contacto para el canal (desnormalizados para rapidez)
  datos_contacto JSONB NOT NULL DEFAULT '{}',
    -- EMAIL:    {"email": "ana@empresa.com"}
    -- WHATSAPP: {"telefono": "+593991234567"}   (formato E.164)
    -- TELEGRAM: {"chat_id": "123456789"}
    -- PUSH:     {"user_id": "uuid"}             (referencia a device_tokens)
  -- Horario de silencio (no enviar fuera de este rango)
  hora_inicio_silencio TIME DEFAULT NULL,  -- ej: '22:00' → desde las 10pm
  hora_fin_silencio    TIME DEFAULT NULL,  -- ej: '08:00' → hasta las 8am
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (empresa_id, contacto_id, canal)
);

ALTER TABLE configuracion_notificaciones ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON configuracion_notificaciones
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE INDEX idx_config_notif_contacto
  ON configuracion_notificaciones(empresa_id, contacto_id);
CREATE INDEX idx_config_notif_canal
  ON configuracion_notificaciones(empresa_id, canal) WHERE activo = true;
```

### plantillas_notificacion

Plantillas de mensajes reutilizables por tipo de evento y canal.

```sql
CREATE TABLE plantillas_notificacion (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id    UUID NOT NULL REFERENCES empresas(id),
  tipo_evento   VARCHAR(60) NOT NULL,   -- 'factura_autorizada', 'cobro_registrado', etc.
  canal         VARCHAR(20) NOT NULL,   -- EMAIL | WHATSAPP | TELEGRAM | PUSH
  asunto        VARCHAR(300),           -- Solo para EMAIL y PUSH
  -- Cuerpo con variables: {{cliente_nombre}}, {{factura_numero}}, {{total}}, etc.
  cuerpo_html   TEXT,                   -- Solo para EMAIL (HTML completo)
  cuerpo_texto  TEXT NOT NULL,          -- Texto plano para WhatsApp, Telegram y fallback
  -- Variables soportadas por esta plantilla
  variables     JSONB NOT NULL DEFAULT '[]',
    -- [{"nombre": "cliente_nombre", "descripcion": "Nombre completo del cliente"},
    --  {"nombre": "factura_numero", "descripcion": "Número de la factura (ej: 001-001-000000123)"},
    --  {"nombre": "total", "descripcion": "Total de la factura con IVA"}]
  activo        BOOLEAN NOT NULL DEFAULT true,
  -- Solo una plantilla activa por (empresa, tipo_evento, canal)
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (empresa_id, tipo_evento, canal)
);

ALTER TABLE plantillas_notificacion ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON plantillas_notificacion
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE INDEX idx_plantillas_evento_canal
  ON plantillas_notificacion(empresa_id, tipo_evento, canal) WHERE activo = true;
```

### cola_notificaciones

Cola de envío asíncrono con reintentos. Desacopla el sistema del envío efectivo.

```sql
CREATE TABLE cola_notificaciones (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id          UUID NOT NULL REFERENCES empresas(id),
  canal               VARCHAR(20) NOT NULL,   -- EMAIL | WHATSAPP | TELEGRAM | PUSH
  destinatario        VARCHAR(300) NOT NULL,  -- email, teléfono E.164, chat_id, user_id
  -- Payload completo listo para enviar (ya con variables sustituidas)
  payload             JSONB NOT NULL,
    -- EMAIL:    {"asunto": "...", "html": "...", "texto": "...", "reply_to": "..."}
    -- WHATSAPP: {"template_name": "...", "language": "es", "components": [...]}
    --           o {"type": "text", "body": "..."}
    -- TELEGRAM: {"chat_id": "...", "text": "...", "parse_mode": "HTML"}
    -- PUSH:     {"title": "...", "body": "...", "data": {...}, "tokens": [...]}
  prioridad           INTEGER NOT NULL DEFAULT 5,
    -- 1 = urgente (documentos SRI), 5 = normal (recordatorios), 10 = baja (marketing)
  intentos            INTEGER NOT NULL DEFAULT 0,
  max_intentos        INTEGER NOT NULL DEFAULT 3,
  siguiente_intento_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  estado              VARCHAR(20) NOT NULL DEFAULT 'PENDIENTE',
    -- PENDIENTE | PROCESANDO | ENVIADO | FALLIDO | CANCELADO
  error               TEXT,                  -- Detalle del último error
  -- Metadatos de trazabilidad
  notificacion_log_id UUID,                  -- FK a notificaciones_log (se llena al completar)
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Sin RLS (tabla interna del sistema, no expuesta a usuarios finales)
-- Solo accesible por Edge Functions y funciones SECURITY DEFINER

CREATE INDEX idx_cola_notif_pendiente
  ON cola_notificaciones(siguiente_intento_at, prioridad)
  WHERE estado IN ('PENDIENTE', 'PROCESANDO');
CREATE INDEX idx_cola_notif_empresa
  ON cola_notificaciones(empresa_id, estado, created_at DESC);
```

### notificaciones_log

Historial completo de notificaciones enviadas. Permite auditoría y diagnóstico.

```sql
CREATE TABLE notificaciones_log (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  contacto_id     UUID REFERENCES contactos(id),
  canal           VARCHAR(20) NOT NULL,
  tipo_evento     VARCHAR(60) NOT NULL,
  asunto          VARCHAR(300),
  cuerpo          TEXT NOT NULL,           -- Texto enviado (sin HTML)
  estado          VARCHAR(20) NOT NULL DEFAULT 'PENDIENTE',
    -- PENDIENTE | ENVIADO | FALLIDO | LEIDO | REBOTADO
  intentos        INTEGER NOT NULL DEFAULT 0,
  enviado_at      TIMESTAMPTZ,
  leido_at        TIMESTAMPTZ,             -- Solo cuando hay tracking (email pixel)
  error_detalle   TEXT,
  -- Referencia al documento origen (factura, OV, cita, etc.)
  referencia_id   UUID,
  referencia_tipo VARCHAR(50),             -- 'facturas', 'ordenes_venta', 'citas', etc.
  -- Proveedor externo
  proveedor_message_id VARCHAR(200),       -- ID del mensaje en Resend/Meta/Telegram/FCM
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE notificaciones_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON notificaciones_log
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE INDEX idx_notif_log_empresa_fecha
  ON notificaciones_log(empresa_id, created_at DESC);
CREATE INDEX idx_notif_log_contacto
  ON notificaciones_log(empresa_id, contacto_id, created_at DESC);
CREATE INDEX idx_notif_log_referencia
  ON notificaciones_log(empresa_id, referencia_tipo, referencia_id);
CREATE INDEX idx_notif_log_estado
  ON notificaciones_log(empresa_id, estado) WHERE estado IN ('PENDIENTE', 'FALLIDO');
```

### chat_canales

Canales de chat interno entre usuarios de la misma empresa.

```sql
CREATE TABLE chat_canales (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id        UUID NOT NULL REFERENCES empresas(id),
  nombre            VARCHAR(100),
    -- NULL para canales DIRECTO (1:1). Requerido para GENERAL, MODULO, GRUPO
  tipo              VARCHAR(20) NOT NULL DEFAULT 'GENERAL',
    -- GENERAL:  Canal de empresa (ej: #general, #anuncios)
    -- MODULO:   Atado a un módulo y registro específico (ej: OV-2026-001, Cita CT-001)
    -- DIRECTO:  Conversación 1:1 entre dos usuarios
    -- GRUPO:    Grupo de trabajo nombrado (ej: #equipo-ventas)
  -- Para tipo MODULO: referencia al registro del ERP
  modulo_referencia VARCHAR(50),           -- 'ordenes_venta', 'facturas', 'citas', etc.
  referencia_id     UUID,                  -- ID del registro referenciado
  creado_por        UUID NOT NULL REFERENCES auth.users(id),
  archivado         BOOLEAN NOT NULL DEFAULT false,
  -- Para DIRECTO: clave única para evitar duplicados
  par_usuarios      TEXT,                  -- 'uuid_menor:uuid_mayor' (generado por trigger)
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (empresa_id, par_usuarios)        -- Solo aplica para tipo DIRECTO
);

ALTER TABLE chat_canales ENABLE ROW LEVEL SECURITY;
-- Los canales son visibles a miembros de la empresa (se filtra más en chat_miembros)
CREATE POLICY "tenant_isolation" ON chat_canales
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE INDEX idx_chat_canales_empresa
  ON chat_canales(empresa_id, tipo) WHERE archivado = false;
CREATE INDEX idx_chat_canales_modulo
  ON chat_canales(empresa_id, modulo_referencia, referencia_id);
```

### chat_miembros

Control de membresía, roles y estado de lectura por canal.

```sql
CREATE TABLE chat_miembros (
  canal_id        UUID NOT NULL REFERENCES chat_canales(id) ON DELETE CASCADE,
  usuario_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  rol             VARCHAR(20) NOT NULL DEFAULT 'MIEMBRO',
    -- ADMIN | MIEMBRO
  silenciado      BOOLEAN NOT NULL DEFAULT false,
  ultimo_leido_at TIMESTAMPTZ,             -- Usado para calcular mensajes no leídos
  joined_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (canal_id, usuario_id)
);

ALTER TABLE chat_miembros ENABLE ROW LEVEL SECURITY;
-- Un usuario solo ve sus propias membresías dentro de su empresa
CREATE POLICY "miembro_propio" ON chat_miembros
  FOR ALL TO authenticated
  USING (
    empresa_id = (SELECT private.get_empresa_id())
    AND usuario_id = auth.uid()
  );

CREATE INDEX idx_chat_miembros_usuario
  ON chat_miembros(usuario_id, ultimo_leido_at);
CREATE INDEX idx_chat_miembros_canal
  ON chat_miembros(canal_id);
```

### chat_mensajes

Mensajes de los canales de chat con soporte para adjuntos y vínculos a documentos del ERP.

```sql
CREATE TABLE chat_mensajes (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  canal_id        UUID NOT NULL REFERENCES chat_canales(id) ON DELETE CASCADE,
  usuario_id      UUID REFERENCES auth.users(id),   -- NULL si es mensaje de sistema o IA
  contenido       TEXT NOT NULL,
  tipo            VARCHAR(20) NOT NULL DEFAULT 'TEXTO',
    -- TEXTO | ARCHIVO | IMAGEN | SISTEMA | IA_RESPUESTA
  -- Adjunto en Supabase Storage (bucket: chat-adjuntos)
  adjunto_url     TEXT,
  adjunto_nombre  VARCHAR(300),
  adjunto_mime    VARCHAR(100),
  adjunto_tamano  INTEGER,                          -- Bytes
  -- Enlace a documento del ERP
  enlace_tipo     VARCHAR(50),                      -- 'facturas', 'ordenes_venta', 'citas', etc.
  enlace_id       UUID,
  enlace_label    VARCHAR(200),                     -- 'Factura 001-001-000000123'
  -- Quiénes han leído este mensaje (JSONB para Realtime eficiente)
  leido_por       JSONB NOT NULL DEFAULT '{}',
    -- {"uuid-usuario-1": "2026-02-18T10:30:00Z", "uuid-usuario-2": "..."}
  -- Edición / eliminación suave
  editado_at      TIMESTAMPTZ,
  eliminado_at    TIMESTAMPTZ,
  -- IA
  ia_contexto     JSONB,                            -- Fuentes y datos usados por la IA
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE chat_mensajes ENABLE ROW LEVEL SECURITY;
-- Solo miembros activos del canal pueden ver mensajes
CREATE POLICY "solo_miembros_del_canal" ON chat_mensajes
  FOR ALL TO authenticated
  USING (
    empresa_id = (SELECT private.get_empresa_id())
    AND canal_id IN (
      SELECT canal_id FROM chat_miembros
      WHERE usuario_id = auth.uid()
    )
    AND eliminado_at IS NULL
  );

CREATE INDEX idx_chat_mensajes_canal_fecha
  ON chat_mensajes(canal_id, created_at DESC);
CREATE INDEX idx_chat_mensajes_usuario
  ON chat_mensajes(empresa_id, usuario_id, created_at DESC);
CREATE INDEX idx_chat_mensajes_enlace
  ON chat_mensajes(empresa_id, enlace_tipo, enlace_id)
  WHERE enlace_id IS NOT NULL;
```

### device_tokens

Tokens FCM para push notifications en iOS, Android y Web. Gestionados por el App Flutter.

```sql
CREATE TABLE device_tokens (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  empresa_id    UUID REFERENCES empresas(id),
  token         TEXT NOT NULL,
  plataforma    VARCHAR(10) NOT NULL,
    -- IOS | ANDROID | WEB
  flavor        VARCHAR(10) NOT NULL DEFAULT 'erp',
    -- erp | salon | cliente
  activo        BOOLEAN NOT NULL DEFAULT true,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, token)
);

ALTER TABLE device_tokens ENABLE ROW LEVEL SECURITY;
-- Cada usuario gestiona solo sus propios tokens
CREATE POLICY "user_own_tokens" ON device_tokens
  FOR ALL TO authenticated
  USING (user_id = auth.uid());

CREATE INDEX idx_device_tokens_user
  ON device_tokens(user_id) WHERE activo = true;
CREATE INDEX idx_device_tokens_empresa
  ON device_tokens(empresa_id) WHERE activo = true;
```

---

## Funciones RPC

### send_notification — Función principal de envío

Punto de entrada unificado. Busca canales activos del contacto, sustituye variables en la plantilla y encola en `cola_notificaciones`.

```sql
CREATE OR REPLACE FUNCTION comunicacion.send_notification(
  p_empresa_id    UUID,
  p_contacto_id   UUID,
  p_tipo_evento   VARCHAR,
  p_variables     JSONB DEFAULT '{}',
  p_referencia_id UUID DEFAULT NULL,
  p_referencia_tipo VARCHAR DEFAULT NULL,
  p_canales       TEXT[] DEFAULT NULL   -- NULL = todos los canales activos del contacto
) RETURNS JSONB   -- {encolados: N, canales: [...]}
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_canal     RECORD;
  v_plantilla RECORD;
  v_cuerpo    TEXT;
  v_asunto    TEXT;
  v_encolados INTEGER := 0;
  v_canales   TEXT[] := '{}';
  v_log_id    UUID;
BEGIN
  -- Para cada canal activo del contacto (o los especificados)
  FOR v_canal IN
    SELECT cn.canal, cn.datos_contacto
    FROM configuracion_notificaciones cn
    WHERE cn.empresa_id = p_empresa_id
      AND cn.contacto_id = p_contacto_id
      AND cn.activo = true
      AND (p_canales IS NULL OR cn.canal = ANY(p_canales))
  LOOP
    -- Buscar plantilla para este evento y canal
    SELECT * INTO v_plantilla
    FROM plantillas_notificacion
    WHERE empresa_id = p_empresa_id
      AND tipo_evento = p_tipo_evento
      AND canal = v_canal.canal
      AND activo = true
    LIMIT 1;

    -- Si no hay plantilla específica de la empresa, buscar plantilla global (empresa_id IS NULL)
    IF NOT FOUND THEN
      SELECT * INTO v_plantilla
      FROM plantillas_notificacion
      WHERE empresa_id IS NULL
        AND tipo_evento = p_tipo_evento
        AND canal = v_canal.canal
        AND activo = true
      LIMIT 1;
    END IF;

    -- Sin plantilla: omitir este canal
    CONTINUE WHEN NOT FOUND;

    -- Sustituir variables en cuerpo_texto y asunto
    v_cuerpo := v_plantilla.cuerpo_texto;
    v_asunto := v_plantilla.asunto;
    DECLARE
      v_var JSONB;
    BEGIN
      FOR v_var IN SELECT * FROM jsonb_each_text(p_variables)
      LOOP
        v_cuerpo := replace(v_cuerpo, '{{' || (v_var).key || '}}', (v_var).value);
        IF v_asunto IS NOT NULL THEN
          v_asunto := replace(v_asunto, '{{' || (v_var).key || '}}', (v_var).value);
        END IF;
      END LOOP;
    END;

    -- Registrar en log
    INSERT INTO notificaciones_log(
      empresa_id, contacto_id, canal, tipo_evento,
      asunto, cuerpo, estado, referencia_id, referencia_tipo
    ) VALUES (
      p_empresa_id, p_contacto_id, v_canal.canal, p_tipo_evento,
      v_asunto, v_cuerpo, 'PENDIENTE', p_referencia_id, p_referencia_tipo
    ) RETURNING id INTO v_log_id;

    -- Encolar para envío asíncrono
    INSERT INTO cola_notificaciones(
      empresa_id, canal, destinatario,
      payload, prioridad, notificacion_log_id
    ) VALUES (
      p_empresa_id,
      v_canal.canal,
      CASE v_canal.canal
        WHEN 'EMAIL'     THEN v_canal.datos_contacto->>'email'
        WHEN 'WHATSAPP'  THEN v_canal.datos_contacto->>'telefono'
        WHEN 'TELEGRAM'  THEN v_canal.datos_contacto->>'chat_id'
        WHEN 'PUSH'      THEN v_canal.datos_contacto->>'user_id'
      END,
      jsonb_build_object(
        'asunto',  v_asunto,
        'cuerpo',  v_cuerpo,
        'html',    v_plantilla.cuerpo_html,
        'log_id',  v_log_id
      ),
      CASE p_tipo_evento
        WHEN 'factura_autorizada' THEN 2
        WHEN 'documento_sri_firmado' THEN 1
        ELSE 5
      END,
      v_log_id
    );

    v_encolados := v_encolados + 1;
    v_canales   := array_append(v_canales, v_canal.canal);
  END LOOP;

  RETURN jsonb_build_object('encolados', v_encolados, 'canales', to_json(v_canales));
END;
$$;
```

### get_unread_count — Mensajes no leídos del usuario

```sql
CREATE OR REPLACE FUNCTION comunicacion.get_unread_count(
  p_usuario_id UUID
) RETURNS JSONB   -- [{canal_id, canal_nombre, no_leidos}]
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN (
    SELECT jsonb_agg(
      jsonb_build_object(
        'canal_id',   m.canal_id,
        'nombre',     c.nombre,
        'tipo',       c.tipo,
        'no_leidos',  COUNT(*)
      )
    )
    FROM chat_mensajes m
    JOIN chat_canales c ON c.id = m.canal_id
    JOIN chat_miembros mb ON mb.canal_id = m.canal_id AND mb.usuario_id = p_usuario_id
    WHERE m.usuario_id != p_usuario_id
      AND m.eliminado_at IS NULL
      AND (
        mb.ultimo_leido_at IS NULL
        OR m.created_at > mb.ultimo_leido_at
      )
    GROUP BY m.canal_id, c.nombre, c.tipo
  );
END;
$$;
```

### mark_messages_read — Marcar mensajes como leídos

```sql
CREATE OR REPLACE FUNCTION comunicacion.mark_messages_read(
  p_canal_id   UUID,
  p_usuario_id UUID
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  -- Actualizar timestamp de último leído en membresía
  UPDATE chat_miembros
  SET ultimo_leido_at = now()
  WHERE canal_id   = p_canal_id
    AND usuario_id = p_usuario_id;

  -- Actualizar leido_por en mensajes recientes no leídos
  UPDATE chat_mensajes
  SET leido_por = leido_por || jsonb_build_object(p_usuario_id::text, now()::text)
  WHERE canal_id = p_canal_id
    AND usuario_id != p_usuario_id
    AND eliminado_at IS NULL
    AND NOT (leido_por ? p_usuario_id::text);
END;
$$;
```

### get_or_create_direct_channel — Canal directo entre dos usuarios

```sql
CREATE OR REPLACE FUNCTION comunicacion.get_or_create_direct_channel(
  p_empresa_id  UUID,
  p_usuario_a   UUID,
  p_usuario_b   UUID
) RETURNS UUID   -- canal_id
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_canal_id UUID;
  v_par      TEXT;
BEGIN
  -- Clave canónica: menor UUID primero
  v_par := LEAST(p_usuario_a::text, p_usuario_b::text)
         || ':' ||
         GREATEST(p_usuario_a::text, p_usuario_b::text);

  -- Buscar existente
  SELECT id INTO v_canal_id
  FROM chat_canales
  WHERE empresa_id = p_empresa_id AND par_usuarios = v_par;

  IF FOUND THEN RETURN v_canal_id; END IF;

  -- Crear nuevo canal directo
  INSERT INTO chat_canales(empresa_id, tipo, creado_por, par_usuarios)
  VALUES (p_empresa_id, 'DIRECTO', p_usuario_a, v_par)
  RETURNING id INTO v_canal_id;

  -- Agregar ambos como miembros
  INSERT INTO chat_miembros(canal_id, usuario_id, empresa_id, rol)
  VALUES (v_canal_id, p_usuario_a, p_empresa_id, 'ADMIN'),
         (v_canal_id, p_usuario_b, p_empresa_id, 'MIEMBRO');

  RETURN v_canal_id;
END;
$$;
```

### get_notification_history — Historial de notificaciones

```sql
CREATE OR REPLACE FUNCTION comunicacion.get_notification_history(
  p_empresa_id      UUID,
  p_contacto_id     UUID DEFAULT NULL,
  p_tipo_evento     VARCHAR DEFAULT NULL,
  p_canal           VARCHAR DEFAULT NULL,
  p_desde           DATE DEFAULT (CURRENT_DATE - INTERVAL '30 days'),
  p_hasta           DATE DEFAULT CURRENT_DATE,
  p_limit           INTEGER DEFAULT 50,
  p_offset          INTEGER DEFAULT 0
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN (
    SELECT jsonb_build_object(
      'total', COUNT(*) OVER(),
      'items', jsonb_agg(
        jsonb_build_object(
          'id',           nl.id,
          'canal',        nl.canal,
          'tipo_evento',  nl.tipo_evento,
          'asunto',       nl.asunto,
          'estado',       nl.estado,
          'intentos',     nl.intentos,
          'enviado_at',   nl.enviado_at,
          'leido_at',     nl.leido_at,
          'error',        nl.error_detalle,
          'referencia_tipo', nl.referencia_tipo,
          'referencia_id',   nl.referencia_id
        )
      )
    )
    FROM notificaciones_log nl
    WHERE nl.empresa_id = p_empresa_id
      AND (p_contacto_id IS NULL OR nl.contacto_id = p_contacto_id)
      AND (p_tipo_evento IS NULL OR nl.tipo_evento = p_tipo_evento)
      AND (p_canal IS NULL OR nl.canal = p_canal)
      AND nl.created_at::date BETWEEN p_desde AND p_hasta
    ORDER BY nl.created_at DESC
    LIMIT p_limit OFFSET p_offset
  );
END;
$$;
```

---

## Triggers

### Trigger: par_usuarios para canales DIRECTO

```sql
CREATE OR REPLACE FUNCTION comunicacion.trg_chat_canales_par_fn()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  -- Validar que canales DIRECTO tengan par_usuarios
  IF NEW.tipo = 'DIRECTO' AND NEW.par_usuarios IS NULL THEN
    RAISE EXCEPTION 'Canales DIRECTO requieren par_usuarios';
  END IF;
  -- Canales no DIRECTO no deben tener par_usuarios
  IF NEW.tipo != 'DIRECTO' THEN
    NEW.par_usuarios := NULL;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_chat_canales_par
  BEFORE INSERT OR UPDATE ON chat_canales
  FOR EACH ROW EXECUTE FUNCTION comunicacion.trg_chat_canales_par_fn();
```

### Trigger: actualizar updated_at en chat_mensajes

```sql
CREATE OR REPLACE FUNCTION comunicacion.trg_updated_at_fn()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_chat_mensajes_updated_at
  BEFORE UPDATE ON chat_mensajes
  FOR EACH ROW EXECUTE FUNCTION comunicacion.trg_updated_at_fn();

CREATE TRIGGER trg_chat_canales_updated_at
  BEFORE UPDATE ON chat_canales
  FOR EACH ROW EXECUTE FUNCTION comunicacion.trg_updated_at_fn();
```

---

## Supabase Realtime

### Suscripciones por tabla

```
PILAR usa Supabase Realtime para mantener datos actualizados
en TODOS los dispositivos conectados simultáneamente.

Canales Realtime por tabla:
┌──────────────────────────────────────────────────────────────┐
│  TABLA                  │ EVENTO         │ ACCIÓN FLUTTER     │
├──────────────────────────────────────────────────────────────┤
│  chat_mensajes          │ INSERT         │ Nuevo mensaje      │
│  chat_miembros          │ UPDATE         │ Estado lectura     │
│  facturas               │ INSERT/UPDATE  │ Actualizar lista   │
│  inventario_stock       │ UPDATE         │ Actualizar stock   │
│  cola_documentos_electr.│ UPDATE         │ Estado SRI         │
│  ordenes_venta          │ INSERT/UPDATE  │ Nuevos pedidos     │
│  pedidos_ecommerce      │ INSERT         │ Pedido nuevo       │
│  ordenes_campo          │ UPDATE         │ Estado campo       │
│  notificaciones_log     │ INSERT         │ Badge notif.       │
└──────────────────────────────────────────────────────────────┘
```

### Implementación Flutter

```dart
// brick_offline_first_with_supabase integra Realtime automáticamente
final stream = Repository().subscribeToRealtime<Factura>();

// Para chat: canal Broadcast privado por empresa (no expone datos a otras empresas)
supabase.channel('chat:${empresaId}:${canalId}')
  .onBroadcast(
    event: 'new_message',
    callback: (payload) {
      ref.read(chatProvider(canalId).notifier).addMessage(payload);
    },
  )
  .subscribe();

// Para badge de notificaciones no leídas:
supabase
  .from('notificaciones_log')
  .stream(primaryKey: ['id'])
  .eq('empresa_id', empresaId)
  .order('created_at', ascending: false)
  .limit(50)
  .listen((data) {
    ref.read(notificacionesBadgeProvider.notifier).update(data);
  });
```

**Filtro por empresa:** Supabase Realtime respeta RLS. Cada suscripción solo recibe datos de su empresa. Los canales Broadcast usan el formato `chat:{empresa_id}:{canal_id}` para aislar conversaciones.

---

## Edge Functions

### send-email (Resend)

**Archivo:** `supabase/functions/send-email/index.ts`

```typescript
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

serve(async (req: Request) => {
  const { to, subject, html, text, reply_to, log_id } = await req.json();

  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${Deno.env.get("RESEND_API_KEY")}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: Deno.env.get("RESEND_FROM_EMAIL"),
      to: [to],
      subject,
      html,
      text,
      reply_to,
    }),
  });

  const data = await res.json();

  // Actualizar log con estado
  const supabase = createSupabaseClient(req);
  if (data.id) {
    await supabase.from("notificaciones_log").update({
      estado: "ENVIADO",
      enviado_at: new Date().toISOString(),
      proveedor_message_id: data.id,
    }).eq("id", log_id);
  } else {
    await supabase.from("notificaciones_log").update({
      estado: "FALLIDO",
      error_detalle: JSON.stringify(data),
    }).eq("id", log_id);
  }

  return new Response(JSON.stringify(data), {
    headers: { "Content-Type": "application/json" },
  });
});
```

### send-whatsapp (Meta Cloud API)

**Archivo:** `supabase/functions/send-whatsapp/index.ts`

Envía mensajes por Meta Cloud API. Soporta dos modos:
- **Template messages** (pre-aprobadas por Meta): para notificaciones transaccionales (facturas, OTP).
- **Text messages** (solo dentro de ventana de 24h): para respuestas en conversaciones activas.

```typescript
// Estructura payload para template
{
  "type": "template",
  "to": "+593991234567",
  "template_name": "factura_autorizada",
  "language": "es_EC",
  "components": [
    {"type": "body", "parameters": [
      {"type": "text", "text": "Juan Pérez"},
      {"type": "text", "text": "001-001-000000456"},
      {"type": "text", "text": "$287.50"}
    ]}
  ]
}

// Estructura payload para mensaje de texto libre
{
  "type": "text",
  "to": "+593991234567",
  "body": "Su cita está confirmada para mañana a las 10:00 AM"
}
```

Variables de entorno requeridas:
- `WHATSAPP_API_TOKEN`: Bearer token de Meta
- `WHATSAPP_PHONE_NUMBER_ID`: ID del número de WhatsApp Business

### send-telegram (Bot API)

**Archivo:** `supabase/functions/send-telegram/index.ts`

```typescript
// Envía mensaje de texto o documento PDF vía Telegram Bot API
// chat_id viene de configuracion_notificaciones.datos_contacto.chat_id
const url = `https://api.telegram.org/bot${BOT_TOKEN}/sendMessage`;
const body = {
  chat_id: payload.chat_id,
  text: payload.text,
  parse_mode: "HTML",  // Permite <b>, <i>, <code>
};
```

Variable de entorno: `TELEGRAM_BOT_TOKEN`

### push-notify (FCM)

**Archivo:** `supabase/functions/push-notify/index.ts`

Envía notificaciones push a uno o varios dispositivos. Soporta envío individual y multicast.

```typescript
// Payload de entrada
{
  "user_id": "uuid",         // Enviar a todos los tokens del usuario
  "empresa_id": "uuid",
  "title": "Factura autorizada",
  "body": "Factura 001-001-000000123 por $287.50 fue autorizada por el SRI",
  "data": {                  // Datos para abrir pantalla específica en Flutter
    "type": "factura",
    "id": "uuid-factura"
  }
}
```

La función busca todos los tokens activos del `user_id` en `device_tokens` y envía usando FCM v1 API (OAuth2 con Service Account).

### process-notification-queue (Cron)

**Archivo:** `supabase/functions/process-notification-queue/index.ts`

Ejecutado cada minuto por el scheduler de Supabase. Procesa registros `PENDIENTE` de `cola_notificaciones` ordenados por `prioridad ASC, siguiente_intento_at ASC`. Para cada registro llama a la Edge Function correspondiente (`send-email`, `send-whatsapp`, `send-telegram`, `push-notify`). Aplica backoff exponencial en reintentos: 2min → 10min → 30min.

---

## Module Service Bus

Todos los módulos llaman a `module_bus.comunicacion.notify()` en lugar de insertar directamente en `cola_notificaciones`. Esto permite que el módulo Comunicación aplique reglas de throttling, horarios de silencio y deduplicación.

```sql
-- Gateway: cualquier módulo puede notificar sin conocer los internos de Comunicación
CREATE OR REPLACE FUNCTION module_bus.comunicacion_notify(
  p_empresa_id      UUID,
  p_contacto_id     UUID,
  p_tipo_evento     VARCHAR,
  p_variables       JSONB DEFAULT '{}',
  p_referencia_id   UUID DEFAULT NULL,
  p_referencia_tipo VARCHAR DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  -- Comunicación es Infraestructura: siempre activo, sin verificación de módulo
  RETURN comunicacion.send_notification(
    p_empresa_id, p_contacto_id, p_tipo_evento,
    p_variables, p_referencia_id, p_referencia_tipo
  );
END;
$$;

-- Ejemplos de uso desde otros módulos:

-- Facturación al autorizar:
PERFORM module_bus.comunicacion_notify(
  p_empresa_id      := v_factura.empresa_id,
  p_contacto_id     := v_factura.cliente_id,
  p_tipo_evento     := 'factura_autorizada',
  p_variables       := jsonb_build_object(
    'cliente_nombre',   v_cliente.razon_social,
    'factura_numero',   v_factura.numero,
    'total',            v_factura.total::text,
    'fecha',            v_factura.fecha::text
  ),
  p_referencia_id   := v_factura.id,
  p_referencia_tipo := 'facturas'
);

-- Citas al confirmar:
PERFORM module_bus.comunicacion_notify(
  p_empresa_id      := v_cita.empresa_id,
  p_contacto_id     := v_cita.contacto_id,
  p_tipo_evento     := 'cita_confirmada',
  p_variables       := jsonb_build_object(
    'cliente_nombre',  v_contacto.nombre,
    'fecha',           v_cita.fecha::text,
    'hora',            v_cita.hora_inicio::text,
    'profesional',     v_profesional.nombre
  ),
  p_referencia_id   := v_cita.id,
  p_referencia_tipo := 'citas'
);
```

---

## Integraciones con Otros Módulos

| Módulo | Evento | Tipo evento |
|--------|--------|-------------|
| Facturación | Factura autorizada por SRI | `factura_autorizada` |
| Facturación | Factura rechazada por SRI | `factura_rechazada` |
| Ventas | Cotización enviada al cliente | `cotizacion_enviada` |
| Ventas | OV confirmada | `orden_venta_confirmada` |
| Ventas | Alerta de crédito | `alerta_credito` |
| Inventario | Stock bajo mínimo | `stock_bajo_minimo` |
| RRHH | Rol de pagos listo | `nomina_lista` |
| Citas | Cita confirmada | `cita_confirmada` |
| Citas | Recordatorio 24h | `cita_recordatorio_24h` |
| Citas | Recordatorio 2h | `cita_recordatorio_2h` |
| Servicio de Campo | Orden asignada a técnico | `orden_campo_asignada` |
| Garantías/RMA | Solicitud aprobada | `rma_aprobado` |
| Suscripciones | Contrato próximo a vencer | `suscripcion_vence` |
| Taller | Reparación lista para entrega | `reparacion_lista` |

---

## Documentos que se Envían por Multi-canal

```
Desde cualquier módulo, vía module_bus.comunicacion_notify(), se pueden enviar:

  Facturación:
    ✅ RIDE PDF (Factura, NC, ND, Retención, Guía de Remisión) — autorizado por SRI
  Ventas:
    ✅ Proformas/Cotizaciones — PDF generado con Syncfusion
    ✅ Estados de cuenta — PDF/Excel
    ✅ Comprobantes de cobro — PDF
  Compras:
    ✅ Órdenes de compra — PDF
    ✅ Comprobantes de retención — RIDE PDF
  Tesorería:
    ✅ Comprobantes de pago — PDF
    ✅ Cheques — PDF
  RRHH:
    ✅ Rol individual de pagos — PDF enviado al empleado
    ✅ Notificación de descuentos/préstamos
  Citas:
    ✅ Confirmación de cita — texto enriquecido
    ✅ Recordatorios automáticos (24h, 2h)
    ✅ Comprobante de servicio — PDF
```

---

## Chat con IA Integrado

Cada usuario tiene acceso a un canal de chat con la IA directamente desde PILAR:

```
1. El usuario escribe una pregunta en lenguaje natural
2. El mensaje se envía al Edge Function 'ai-query' (módulo IA/Chat)
3. ai-query busca contexto relevante en embeddings (pgvector)
4. LLM genera respuesta con datos del ERP de la empresa
5. La respuesta aparece como mensaje tipo IA_RESPUESTA en el chat
6. Si la IA sugiere una acción (crear factura, consultar stock):
   - Muestra botón "Ejecutar" con confirmación
   - Al confirmar, ejecuta la acción vía RPC/Edge Function
   - Registra resultado como nuevo mensaje

Ejemplo:
  Usuario: "¿Cuántas facturas emitimos en enero?"
  IA: "En enero 2026 se emitieron 145 facturas por $45,230.50.
       Las 5 principales son: [tabla con datos]"
  Usuario: "Crea una factura para ABC Corp con 10 unidades de Producto X"
  IA: "10x Producto X @ $25.00 = $250.00 + IVA 15% = $37.50. Total: $287.50. ¿Confirmar?"
  [Botón: Confirmar] [Botón: Cancelar]
```

Los mensajes de IA se guardan en `chat_mensajes` con `tipo = 'IA_RESPUESTA'` y `ia_contexto` JSONB con las fuentes consultadas.

---

## Índices Completos

```sql
-- configuracion_notificaciones
CREATE INDEX idx_config_notif_contacto ON configuracion_notificaciones(empresa_id, contacto_id);
CREATE INDEX idx_config_notif_canal ON configuracion_notificaciones(empresa_id, canal) WHERE activo = true;

-- plantillas_notificacion
CREATE INDEX idx_plantillas_evento_canal ON plantillas_notificacion(empresa_id, tipo_evento, canal) WHERE activo = true;

-- cola_notificaciones
CREATE INDEX idx_cola_notif_pendiente ON cola_notificaciones(siguiente_intento_at, prioridad) WHERE estado IN ('PENDIENTE', 'PROCESANDO');
CREATE INDEX idx_cola_notif_empresa ON cola_notificaciones(empresa_id, estado, created_at DESC);

-- notificaciones_log
CREATE INDEX idx_notif_log_empresa_fecha ON notificaciones_log(empresa_id, created_at DESC);
CREATE INDEX idx_notif_log_contacto ON notificaciones_log(empresa_id, contacto_id, created_at DESC);
CREATE INDEX idx_notif_log_referencia ON notificaciones_log(empresa_id, referencia_tipo, referencia_id);
CREATE INDEX idx_notif_log_estado ON notificaciones_log(empresa_id, estado) WHERE estado IN ('PENDIENTE', 'FALLIDO');

-- chat_canales
CREATE INDEX idx_chat_canales_empresa ON chat_canales(empresa_id, tipo) WHERE archivado = false;
CREATE INDEX idx_chat_canales_modulo ON chat_canales(empresa_id, modulo_referencia, referencia_id);

-- chat_miembros
CREATE INDEX idx_chat_miembros_usuario ON chat_miembros(usuario_id, ultimo_leido_at);
CREATE INDEX idx_chat_miembros_canal ON chat_miembros(canal_id);

-- chat_mensajes
CREATE INDEX idx_chat_mensajes_canal_fecha ON chat_mensajes(canal_id, created_at DESC);
CREATE INDEX idx_chat_mensajes_usuario ON chat_mensajes(empresa_id, usuario_id, created_at DESC);
CREATE INDEX idx_chat_mensajes_enlace ON chat_mensajes(empresa_id, enlace_tipo, enlace_id) WHERE enlace_id IS NOT NULL;

-- device_tokens
CREATE INDEX idx_device_tokens_user ON device_tokens(user_id) WHERE activo = true;
CREATE INDEX idx_device_tokens_empresa ON device_tokens(empresa_id) WHERE activo = true;
```

---

## UI/UX (Flutter)

### Chat — Pantalla Principal

```dart
// features/comunicacion/screens/chat_canales_screen.dart
// Lista de canales con badge de mensajes no leídos

class ChatCanalesScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canalesAsync = ref.watch(chatCanalesProvider);
    final unreadCounts = ref.watch(unreadCountsProvider);

    return canalesAsync.when(
      data: (canales) => ListView.builder(
        itemCount: canales.length,
        itemBuilder: (context, i) {
          final canal = canales[i];
          final noLeidos = unreadCounts[canal.id] ?? 0;
          return ListTile(
            leading: _buildCanalAvatar(canal),
            title: Text(canal.nombre ?? 'Chat directo'),
            subtitle: Text(canal.ultimoMensaje ?? ''),
            trailing: noLeidos > 0
                ? Badge(label: Text('$noLeidos'))
                : null,
            onTap: () => context.push('/chat/${canal.id}'),
          );
        },
      ),
      loading: (_) => const CircularProgressIndicator(),
      error: (e, _) => Text('Error: $e'),
    );
  }
}
```

### Historial de Notificaciones

Vista `SfDataGrid` con filtros por canal, tipo de evento, estado y rango de fechas. Columnas: Fecha, Canal (icono), Tipo de evento, Destinatario, Estado (chip de color), Acciones (reintentar si FALLIDO).

### Plantillas

Editor de plantillas con previsualización en tiempo real. Las variables `{{nombre_variable}}` se resaltan y se puede simular con valores de ejemplo.

---

## Configuración Global (Variables de Entorno Supabase)

| Variable | Descripción |
|----------|-------------|
| `RESEND_API_KEY` | API key de Resend para emails |
| `RESEND_FROM_EMAIL` | Dirección de origen (ej: `noreply@pilar.ec`) |
| `WHATSAPP_API_TOKEN` | Token Meta Business Cloud API |
| `WHATSAPP_PHONE_NUMBER_ID` | ID número WhatsApp Business |
| `TELEGRAM_BOT_TOKEN` | Token del bot de Telegram |
| `FCM_SERVICE_ACCOUNT_JSON` | JSON de Service Account de Firebase |
