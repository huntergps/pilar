# Crédito a Clientes y Control de Límites (Ventas)

*Spec derivada del módulo `l10n_ec_sale_credit` (Odoo 19.1 Ecuador — producción en csolish/tecnoh)*

---

## Descripción

Control de límite de crédito por cliente en órdenes de venta. Bloquea o pone en espera de aprobación las ventas que superan el cupo de crédito asignado. Integrado con seguimiento de cartera (cobranza) y aprobaciones.

---

## Flujo de Control de Crédito

```
OV creada
  ↓
¿Es venta a crédito?
  ├── No (contado) → confirmar normal
  └── Sí → verificar límite
        ├── Dentro del límite → confirmar normal
        └── Excede límite
              ├── allow_over_credit=True → confirmar con advertencia
              └── allow_over_credit=False
                    ├── Bloquear → mostrar error
                    └── Crear solicitud de aprobación → estado 'waiting'
```

---

## Modelo de Datos

### Extensión de `contactos` (campos de crédito por cliente)

```sql
ALTER TABLE contactos ADD COLUMN limite_credito     NUMERIC(15,2) DEFAULT 0;
ALTER TABLE contactos ADD COLUMN credito_disponible NUMERIC(15,2) DEFAULT 0;   -- calculado
ALTER TABLE contactos ADD COLUMN permite_sobre_credito BOOLEAN DEFAULT FALSE;
ALTER TABLE contactos ADD COLUMN followup_status    TEXT;                        -- al_dia, riesgo, bloqueado
ALTER TABLE contactos ADD COLUMN followup_proxima_accion DATE;
ALTER TABLE contactos ADD COLUMN facturas_vencidas_count INT DEFAULT 0;
```

### Tabla: `solicitudes_aprobacion` (approval requests)

```sql
CREATE TABLE solicitudes_aprobacion (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id          UUID NOT NULL REFERENCES empresas(id),
  nombre              TEXT NOT NULL,
  tipo                TEXT NOT NULL DEFAULT 'credito_venta',
  orden_venta_id      UUID REFERENCES ordenes_venta(id),
  solicitante_id      UUID REFERENCES usuarios(id),
  aprobador_id        UUID REFERENCES usuarios(id),
  estado              TEXT DEFAULT 'pendiente'
                      CHECK (estado IN ('pendiente','aprobado','rechazado')),
  motivo_rechazo      TEXT,
  fecha_solicitud     TIMESTAMPTZ DEFAULT now(),
  fecha_resolucion    TIMESTAMPTZ,
  -- Datos al momento de la solicitud
  monto_ov            NUMERIC(15,2),
  limite_credito      NUMERIC(15,2),
  credito_disponible  NUMERIC(15,2),
  excedente           NUMERIC(15,2)
);

ALTER TABLE solicitudes_aprobacion ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON solicitudes_aprobacion FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));
```

### Extensión de `ordenes_venta`

```sql
ALTER TABLE ordenes_venta ADD COLUMN credito_excedido          BOOLEAN DEFAULT FALSE;
ALTER TABLE ordenes_venta ADD COLUMN verificacion_bypasseada   BOOLEAN DEFAULT FALSE;
ALTER TABLE ordenes_venta ADD COLUMN aprobacion_id             UUID REFERENCES solicitudes_aprobacion(id);
-- El campo 'estado' se extiende con 'waiting' (espera aprobación)
```

---

## Estados de OV con Control de Crédito

```
BORRADOR → WAITING (espera aprobación) → APROBADO → CONFIRMADO (sale)
                                       ↘ RECHAZADO
BORRADOR → CONFIRMADO (si dentro del límite o es contado)
```

---

## Indicadores de Crédito en Cliente

| Campo | Descripción |
|---|---|
| `limite_credito` | Cupo máximo de crédito asignado |
| `credito_disponible` | límite - (facturas vencidas + OVs activas) |
| `permite_sobre_credito` | Si puede vender aun excediendo el límite |
| `followup_status` | Estado de cobranza: al_dia / en_riesgo / bloqueado |
| `facturas_vencidas_count` | Número de facturas impagas vencidas |

---

## Funciones RPC

```typescript
// Verificar crédito antes de confirmar OV
verificar_credito(params: {
  contacto_id: UUID
  monto_ov: number
}): {
  tiene_credito: boolean
  limite: number
  disponible: number
  excedente: number
  permite_sobre_credito: boolean
  facturas_vencidas: number
  recomendacion: 'aprobar' | 'solicitar_aprobacion' | 'bloquear'
}

// Solicitar aprobación de crédito
solicitar_aprobacion_credito(params: {
  orden_venta_id: UUID
  aprobador_id?: UUID
  nota?: string
}): { solicitud_id: UUID }

// Aprobar solicitud
aprobar_credito(params: {
  solicitud_id: UUID
  nota?: string
}): { orden_venta_id: UUID, estado: 'sale' }

// Rechazar solicitud
rechazar_credito(params: {
  solicitud_id: UUID
  motivo: string
}): { orden_venta_id: UUID, estado: 'cancel' }

// Actualizar límite de crédito
actualizar_limite_credito(params: {
  contacto_id: UUID
  nuevo_limite: number
  permite_sobre_credito?: boolean
}): { contacto_id: UUID }

// Consultar crédito de un cliente
get_credito_cliente(contacto_id: UUID): {
  limite: number
  usado: number
  disponible: number
  facturas_vencidas: Factura[]
  ov_en_curso: OrdenVenta[]
}
```

---

## Validaciones de Negocio

- Si `is_credit = true` (plazo de pago es a crédito), se activa la verificación
- OV en `waiting` no puede despacharse ni facturarse hasta ser aprobada
- El aprobador no puede aprobar sus propias solicitudes
- Al aprobar → OV pasa automáticamente a estado `sale` (confirmada)
- Al rechazar → OV puede volver a borrador para edición

---

## Configuración por Empresa

```json
{
  "credito_clientes": {
    "requiere_aprobacion_excedente": true,
    "bloquea_sin_aprobacion": false,
    "aprobador_default_id": "uuid",
    "notificacion_aprobacion": true,
    "dias_cache_cartera": 1
  }
}
```

---

## Pantallas Flutter

### Indicador de Crédito en Formulario de OV

```
┌────────────────────────────────────────────────┐
│ CRÉDITO DEL CLIENTE                            │
│ Límite:     $5,000.00                          │
│ Disponible: $1,200.00  [████████░░] 76% usado  │
│ ⚠️ Esta OV ($1,500) excede el disponible $300  │
│ [Solicitar Aprobación]  [Confirmar de todas formas]│
└────────────────────────────────────────────────┘
```

### Lista de Aprobaciones Pendientes
- `CrudScaffold<SolicitudAprobacion>` filtros: estado, vendedor, aprobador, rango fechas
- Columnas: OV, cliente, monto, límite, excedente, solicitado_por, fecha, estado
- Acciones rápidas: Aprobar / Rechazar desde la lista

---

## Modelo de Datos SQL Completo

### Tabla: `solicitudes_credito`

Historial de solicitudes de asignación o cambio de límite de crédito para un cliente.

```sql
CREATE TABLE solicitudes_credito (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id         UUID NOT NULL REFERENCES empresas(id),
  contacto_id        UUID NOT NULL REFERENCES contactos(id),
  limite_actual      DECIMAL(14,2) NOT NULL DEFAULT 0,      -- límite vigente al solicitar
  limite_solicitado  DECIMAL(14,2) NOT NULL,                -- límite pedido
  estado             TEXT NOT NULL DEFAULT 'PENDIENTE'
                     CHECK (estado IN ('PENDIENTE','APROBADO','RECHAZADO','CANCELADO')),
  solicitante_id     UUID NOT NULL REFERENCES usuarios(id),
  aprobador_id       UUID REFERENCES usuarios(id),          -- asignado al crear, puede ser null
  justificacion      TEXT,                                   -- razón del aumento solicitado
  notas_aprobador    TEXT,
  fecha_solicitud    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  fecha_aprobacion   TIMESTAMPTZ,
  -- Documentos de soporte
  documentos         JSONB DEFAULT '[]',                    -- [{nombre, url, tipo}]
  -- Auditoría
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE solicitudes_credito ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON solicitudes_credito FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE INDEX idx_solicitudes_credito_empresa   ON solicitudes_credito(empresa_id);
CREATE INDEX idx_solicitudes_credito_contacto  ON solicitudes_credito(contacto_id);
CREATE INDEX idx_solicitudes_credito_estado    ON solicitudes_credito(empresa_id, estado)
  WHERE estado = 'PENDIENTE';
CREATE INDEX idx_solicitudes_credito_aprobador ON solicitudes_credito(aprobador_id)
  WHERE estado = 'PENDIENTE';
```

### Tabla: `excepciones_credito`

Registro de excepciones temporales que permiten confirmar una OV aunque exceda el límite de crédito del cliente.

```sql
CREATE TABLE excepciones_credito (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id          UUID NOT NULL REFERENCES empresas(id),
  contacto_id         UUID NOT NULL REFERENCES contactos(id),
  orden_venta_id      UUID NOT NULL REFERENCES ordenes_venta(id),
  -- Montos al momento de la excepción
  limite_credito      DECIMAL(14,2) NOT NULL,
  credito_usado       DECIMAL(14,2) NOT NULL,
  monto_ov            DECIMAL(14,2) NOT NULL,
  monto_exceso        DECIMAL(14,2) NOT NULL,              -- monto_ov + credito_usado - limite
  -- Aprobación
  solicitante_id      UUID NOT NULL REFERENCES usuarios(id),
  aprobador_id        UUID REFERENCES usuarios(id),
  justificacion       TEXT NOT NULL,
  notas_aprobador     TEXT,
  estado              TEXT NOT NULL DEFAULT 'PENDIENTE'
                      CHECK (estado IN ('PENDIENTE','APROBADO','RECHAZADO','EXPIRADO')),
  -- Vigencia de la excepción aprobada
  fecha_solicitud     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  fecha_aprobacion    TIMESTAMPTZ,
  fecha_vencimiento_excepcion TIMESTAMPTZ,                 -- cuándo expira la excepción (24-48h)
  -- Resultado
  ov_confirmada       BOOLEAN NOT NULL DEFAULT FALSE,      -- TRUE si la OV se confirmó con excepción
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE excepciones_credito ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON excepciones_credito FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE INDEX idx_excepciones_credito_empresa   ON excepciones_credito(empresa_id);
CREATE INDEX idx_excepciones_credito_contacto  ON excepciones_credito(contacto_id);
CREATE INDEX idx_excepciones_credito_orden     ON excepciones_credito(orden_venta_id);
CREATE INDEX idx_excepciones_credito_pendientes ON excepciones_credito(empresa_id, estado, aprobador_id)
  WHERE estado = 'PENDIENTE';
CREATE INDEX idx_excepciones_credito_vigentes  ON excepciones_credito(empresa_id, fecha_vencimiento_excepcion)
  WHERE estado = 'APROBADO' AND ov_confirmada = FALSE;
```

---

## Funciones RPC SQL Completas

### `check_credit_limit(p_contacto_id, p_monto_adicional)`

Verifica si un cliente puede comprar el monto adicional indicado. Retorna el estado completo del crédito: disponible, facturas vencidas, días de atraso máximo y recomendación de acción.

```sql
CREATE OR REPLACE FUNCTION ventas.check_credit_limit(
  p_contacto_id      UUID,
  p_monto_adicional  DECIMAL(14,2)
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_empresa_id         UUID;
  v_contacto           RECORD;
  v_saldo_cxc          DECIMAL(14,2) := 0;  -- facturas emitidas pendientes
  v_ovs_activas        DECIMAL(14,2) := 0;  -- OVs confirmadas sin facturar
  v_credito_usado      DECIMAL(14,2);
  v_credito_disponible DECIMAL(14,2);
  v_facturas_vencidas  INT := 0;
  v_monto_vencido      DECIMAL(14,2) := 0;
  v_dias_max_vencido   INT := 0;
  v_permitido          BOOLEAN;
  v_recomendacion      TEXT;
  v_config             JSONB;
BEGIN
  v_empresa_id := (SELECT private.get_empresa_id());

  -- Obtener datos del cliente
  SELECT
    c.id, c.nombre, c.limite_credito,
    c.permite_sobre_credito, c.followup_status
  INTO v_contacto
  FROM contactos c
  WHERE c.id = p_contacto_id AND c.empresa_id = v_empresa_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Cliente no encontrado';
  END IF;

  -- Calcular saldo CxC pendiente (facturas emitidas no pagadas)
  SELECT
    COALESCE(SUM(cxc.monto_pendiente), 0),
    COUNT(*) FILTER (WHERE cxc.fecha_vencimiento < CURRENT_DATE),
    COALESCE(SUM(cxc.monto_pendiente) FILTER (WHERE cxc.fecha_vencimiento < CURRENT_DATE), 0),
    COALESCE(MAX(CURRENT_DATE - cxc.fecha_vencimiento) FILTER (WHERE cxc.fecha_vencimiento < CURRENT_DATE), 0)
  INTO v_saldo_cxc, v_facturas_vencidas, v_monto_vencido, v_dias_max_vencido
  FROM cuentas_por_cobrar cxc
  WHERE cxc.contacto_id = p_contacto_id
    AND cxc.empresa_id  = v_empresa_id
    AND cxc.estado      IN ('PENDIENTE', 'PARCIAL');

  -- Calcular OVs confirmadas sin facturar (comprometidas)
  SELECT COALESCE(SUM(ov.total_con_impuestos), 0)
  INTO v_ovs_activas
  FROM ordenes_venta ov
  WHERE ov.contacto_id = p_contacto_id
    AND ov.empresa_id  = v_empresa_id
    AND ov.estado      IN ('sale', 'confirmada')
    AND NOT EXISTS (
      SELECT 1 FROM facturas f
      WHERE f.orden_venta_id = ov.id
        AND f.estado NOT IN ('cancel', 'cancelada')
    );

  v_credito_usado      := v_saldo_cxc + v_ovs_activas;
  v_credito_disponible := v_contacto.limite_credito - v_credito_usado;

  -- Obtener config de crédito de la empresa
  SELECT configuracion->'credito_clientes' INTO v_config
  FROM empresas WHERE id = v_empresa_id;

  -- Determinar si la compra está permitida
  IF v_contacto.followup_status = 'bloqueado' THEN
    v_permitido      := FALSE;
    v_recomendacion  := 'BLOQUEAR';
  ELSIF v_facturas_vencidas > 0 AND COALESCE((v_config->>'bloquea_con_vencidas')::BOOLEAN, FALSE) THEN
    v_permitido      := FALSE;
    v_recomendacion  := 'BLOQUEAR';
  ELSIF (v_credito_disponible - p_monto_adicional) >= 0 THEN
    v_permitido      := TRUE;
    v_recomendacion  := 'APROBAR';
  ELSIF v_contacto.permite_sobre_credito THEN
    v_permitido      := TRUE;
    v_recomendacion  := 'APROBAR_CON_ADVERTENCIA';
  ELSIF COALESCE((v_config->>'requiere_aprobacion_excedente')::BOOLEAN, TRUE) THEN
    v_permitido      := FALSE;
    v_recomendacion  := 'SOLICITAR_APROBACION';
  ELSE
    v_permitido      := FALSE;
    v_recomendacion  := 'BLOQUEAR';
  END IF;

  RETURN jsonb_build_object(
    'permitido',          v_permitido,
    'limite',             v_contacto.limite_credito,
    'usado',              v_credito_usado,
    'disponible',         v_credito_disponible,
    'monto_adicional',    p_monto_adicional,
    'saldo_tras_compra',  v_credito_disponible - p_monto_adicional,
    'facturas_vencidas',  v_facturas_vencidas,
    'monto_vencido',      v_monto_vencido,
    'dias_vencimiento_max', v_dias_max_vencido,
    'followup_status',    v_contacto.followup_status,
    'recomendacion',      v_recomendacion
  );
END;
$$;
```

### `request_credit_exception(p_orden_id, p_justificacion)`

Crea una solicitud de excepción de crédito para que un supervisor pueda aprobar la OV que excede el límite.

```sql
CREATE OR REPLACE FUNCTION ventas.request_credit_exception(
  p_orden_id      UUID,
  p_justificacion TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_empresa_id      UUID;
  v_usuario_id      UUID;
  v_ov              RECORD;
  v_check           JSONB;
  v_aprobador_id    UUID;
  v_excepcion_id    UUID;
  v_horas_vigencia  INT;
BEGIN
  v_empresa_id := (SELECT private.get_empresa_id());
  v_usuario_id := auth.uid();

  -- Obtener datos de la OV
  SELECT ov.id, ov.contacto_id, ov.total_con_impuestos, ov.numero, ov.estado
  INTO v_ov
  FROM ordenes_venta ov
  WHERE ov.id = p_orden_id AND ov.empresa_id = v_empresa_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Orden de venta % no encontrada', p_orden_id;
  END IF;

  IF v_ov.estado NOT IN ('draft', 'borrador', 'sent', 'waiting') THEN
    RAISE EXCEPTION 'La OV debe estar en borrador o espera para solicitar excepción';
  END IF;

  -- Calcular situación de crédito
  v_check := ventas.check_credit_limit(v_ov.contacto_id, v_ov.total_con_impuestos);

  IF (v_check->>'permitido')::BOOLEAN THEN
    RAISE EXCEPTION 'El cliente está dentro de su límite. No requiere excepción';
  END IF;

  -- Obtener aprobador por defecto de la empresa
  SELECT (configuracion->'credito_clientes'->>'aprobador_default_id')::UUID
  INTO v_aprobador_id
  FROM empresas WHERE id = v_empresa_id;

  -- Vigencia de excepción (configurable, default 48h)
  v_horas_vigencia := COALESCE(
    (SELECT (configuracion->'credito_clientes'->>'horas_vigencia_excepcion')::INT
     FROM empresas WHERE id = v_empresa_id),
    48
  );

  -- Crear excepción
  INSERT INTO excepciones_credito (
    empresa_id, contacto_id, orden_venta_id,
    limite_credito, credito_usado, monto_ov, monto_exceso,
    solicitante_id, aprobador_id, justificacion, estado,
    fecha_solicitud,
    fecha_vencimiento_excepcion
  ) VALUES (
    v_empresa_id, v_ov.contacto_id, p_orden_id,
    (v_check->>'limite')::DECIMAL,
    (v_check->>'usado')::DECIMAL,
    v_ov.total_con_impuestos,
    ABS((v_check->>'saldo_tras_compra')::DECIMAL),
    v_usuario_id, v_aprobador_id, p_justificacion, 'PENDIENTE',
    NOW(),
    NOW() + (v_horas_vigencia || ' hours')::INTERVAL
  ) RETURNING id INTO v_excepcion_id;

  -- Actualizar OV a estado 'waiting'
  UPDATE ordenes_venta
  SET estado      = 'waiting',
      aprobacion_id = v_excepcion_id,
      credito_excedido = TRUE,
      updated_at  = NOW()
  WHERE id = p_orden_id;

  -- Notificar al supervisor via module_bus.comunicacion
  PERFORM module_bus.comunicacion.send_notification(
    jsonb_build_object(
      'empresa_id',   v_empresa_id,
      'usuario_id',   v_aprobador_id,
      'tipo',         'EXCEPCION_CREDITO',
      'titulo',       'Excepción de crédito pendiente - ' || v_ov.numero,
      'mensaje',      'El vendedor solicita excepción de crédito por $' ||
                      ABS((v_check->>'saldo_tras_compra')::DECIMAL) ||
                      ' sobre el límite del cliente. Justificación: ' || p_justificacion,
      'canales',      '["email","whatsapp"]',
      'referencia_id', v_excepcion_id,
      'referencia_tipo', 'excepcion_credito'
    )
  );

  RETURN jsonb_build_object(
    'success',       TRUE,
    'excepcion_id',  v_excepcion_id,
    'orden_id',      p_orden_id,
    'estado_ov',     'waiting',
    'aprobador_id',  v_aprobador_id,
    'monto_exceso',  ABS((v_check->>'saldo_tras_compra')::DECIMAL),
    'vigencia_horas', v_horas_vigencia
  );
END;
$$;
```

### `approve_credit_exception(p_excepcion_id, p_aprobador_id)`

Aprueba una excepción de crédito y desbloquea la OV para su confirmación. La excepción tiene vigencia temporal (24-48h configurables).

```sql
CREATE OR REPLACE FUNCTION ventas.approve_credit_exception(
  p_excepcion_id UUID,
  p_aprobador_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_empresa_id     UUID;
  v_aprobador_real UUID;
  v_excepcion      excepciones_credito%ROWTYPE;
  v_ov_numero      TEXT;
BEGIN
  v_empresa_id     := (SELECT private.get_empresa_id());
  v_aprobador_real := COALESCE(p_aprobador_id, auth.uid());

  -- Obtener excepción
  SELECT * INTO v_excepcion
  FROM excepciones_credito
  WHERE id = p_excepcion_id AND empresa_id = v_empresa_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Excepción de crédito no encontrada';
  END IF;

  IF v_excepcion.estado != 'PENDIENTE' THEN
    RAISE EXCEPTION 'La excepción ya fue procesada (estado: %)', v_excepcion.estado;
  END IF;

  -- El aprobador no puede ser el mismo que el solicitante
  IF v_aprobador_real = v_excepcion.solicitante_id THEN
    RAISE EXCEPTION 'El aprobador no puede ser el mismo usuario que solicitó la excepción';
  END IF;

  -- Verificar vigencia (no expirada)
  IF v_excepcion.fecha_vencimiento_excepcion < NOW() THEN
    UPDATE excepciones_credito
    SET estado = 'EXPIRADO', updated_at = NOW()
    WHERE id = p_excepcion_id;
    RAISE EXCEPTION 'La excepción ha expirado. Solicite una nueva';
  END IF;

  -- Aprobar excepción
  UPDATE excepciones_credito
  SET
    estado           = 'APROBADO',
    aprobador_id     = v_aprobador_real,
    fecha_aprobacion = NOW(),
    updated_at       = NOW()
  WHERE id = p_excepcion_id;

  -- Liberar la OV: pasar de 'waiting' a 'sale' (confirmada)
  UPDATE ordenes_venta
  SET
    estado                  = 'sale',
    verificacion_bypasseada = TRUE,
    updated_at              = NOW()
  WHERE id         = v_excepcion.orden_venta_id
    AND empresa_id = v_empresa_id
  RETURNING numero INTO v_ov_numero;

  -- Notificar al vendedor
  PERFORM module_bus.comunicacion.send_notification(
    jsonb_build_object(
      'empresa_id',   v_empresa_id,
      'usuario_id',   v_excepcion.solicitante_id,
      'tipo',         'EXCEPCION_APROBADA',
      'titulo',       'Excepción aprobada - OV ' || COALESCE(v_ov_numero, ''),
      'mensaje',      'Tu solicitud de excepción de crédito fue aprobada. La orden de venta ha sido confirmada.',
      'canales',      '["email"]',
      'referencia_id', p_excepcion_id,
      'referencia_tipo', 'excepcion_credito'
    )
  );

  RETURN jsonb_build_object(
    'success',         TRUE,
    'excepcion_id',    p_excepcion_id,
    'orden_venta_id',  v_excepcion.orden_venta_id,
    'estado_ov',       'sale',
    'aprobado_por',    v_aprobador_real,
    'vigente_hasta',   v_excepcion.fecha_vencimiento_excepcion
  );
END;
$$;
```

---

## Workflow Completo: OV con Exceso de Crédito

```
1. VENDEDOR crea OV → elige plazo_pago.es_credito = TRUE
                            ↓
2. SISTEMA llama check_credit_limit(contacto_id, monto_ov)
     ├── recomendacion = 'APROBAR'      → OV se confirma directamente
     ├── recomendacion = 'APROBAR_CON_ADVERTENCIA'
     │     → OV se confirma con flag credito_excedido = TRUE
     └── recomendacion = 'SOLICITAR_APROBACION'
           ↓
3. VENDEDOR llama request_credit_exception(orden_id, justificacion)
     → OV pasa a estado 'waiting'
     → INSERT INTO excepciones_credito (PENDIENTE, vigente 48h)
     → Notificación WhatsApp + Email al SUPERVISOR
           ↓
4. SUPERVISOR revisa excepciones_credito pendientes en su bandeja
     ├── approve_credit_exception(excepcion_id)
     │     → excepcion.estado = 'APROBADO'
     │     → OV.estado = 'sale' (confirmada)
     │     → Notificación al vendedor
     │     → Despacho / Facturación proceden normalmente
     └── rechazar_excepcion_credito(excepcion_id, motivo)
           → excepcion.estado = 'RECHAZADO'
           → OV vuelve a 'draft' para edición
           → Notificación al vendedor con motivo
```

### Cron: expirar excepciones vencidas

```sql
-- Ejecutar con pg_cron cada hora
CREATE OR REPLACE FUNCTION ventas.expire_credit_exceptions()
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE excepciones_credito
  SET estado     = 'EXPIRADO',
      updated_at = NOW()
  WHERE estado              = 'PENDIENTE'
    AND fecha_vencimiento_excepcion < NOW();

  -- Regresar OVs en waiting con excepción expirada a borrador
  UPDATE ordenes_venta ov
  SET estado     = 'draft',
      updated_at = NOW()
  FROM excepciones_credito ec
  WHERE ec.orden_venta_id = ov.id
    AND ec.estado         = 'EXPIRADO'
    AND ov.estado         = 'waiting';
END;
$$;
```

---

## Integración con Módulo Comunicación

Al crear una excepción, se notifica al supervisor vía `module_bus.comunicacion.send_notification()`:

```
Canal email  → asunto: "Excepción crédito pendiente - OV-XXXX"
               cuerpo: cliente, límite, exceso, justificación, link OV
Canal WhatsApp → mensaje corto: "Excepción crédito $XXX — OV-XXXX — [Ver →]"
```

El módulo Comunicación (Infraestructura) maneja el envío efectivo. Solo se activa si la empresa tiene configurados los canales de notificación.

---

## Índices Adicionales

```sql
-- Índice para consultas de cartera vencida por cliente
CREATE INDEX idx_cxc_vencidas_cliente ON cuentas_por_cobrar(contacto_id, empresa_id, fecha_vencimiento)
  WHERE estado IN ('PENDIENTE','PARCIAL') AND fecha_vencimiento < CURRENT_DATE;

-- Índice para buscar OVs comprometidas (sin facturar) por cliente
CREATE INDEX idx_ov_activas_contacto ON ordenes_venta(contacto_id, empresa_id)
  WHERE estado IN ('sale','confirmada');

-- Índice para panel de aprobaciones del supervisor
CREATE INDEX idx_excepciones_aprobador ON excepciones_credito(aprobador_id, empresa_id, fecha_solicitud DESC)
  WHERE estado = 'PENDIENTE';
```
