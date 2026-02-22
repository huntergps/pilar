# Gestión de Cheques (Tesorería)

*Spec derivada del módulo `l10n_ec_checks` (Odoo 19.1 Ecuador — producción en csolish/tecnoh)*

---

## Descripción

Control completo del ciclo de vida de cheques emitidos y recibidos conforme a la Ley de Cheques del Ecuador. Incluye chequeras, cheques post-fechados, certificación, alertas de vencimiento (20 días Art. 58) y reporte diario por correo.

---

## Estados del Ciclo de Vida (Cheque Emitido)

```
NUEVO → USADO → IMPRESO → ENTREGADO → COBRADO
                                    ↘ DEVUELTO
         ↓
      CANCELADO / PERDIDO / EN CUSTODIA
```

| Estado | Descripción |
|---|---|
| `nuevo` | Cheque en chequera, sin asignar |
| `usado` | Datos asignados (beneficiario, monto, fecha) |
| `impreso` | Físicamente impreso |
| `entregado` | Entregado al beneficiario |
| `cobrado` | Cheque cobrado por el beneficiario |
| `devuelto` | Rebotado o devuelto por el banco |
| `cancelado` | Anulado |
| `perdido` | Reportado como perdido (requiere denuncia policial) |
| `en_custodia` | En poder de la empresa como garantía |

---

## Modelo de Datos

### Tabla: `cheques_emitidos`

```sql
CREATE TABLE cheques_emitidos (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id              UUID NOT NULL REFERENCES empresas(id),
  nombre                  TEXT,                        -- Secuencia: CHQ-0001
  -- Datos del cheque (Art. 1 Ley de Cheques Ecuador)
  cheque_no               TEXT NOT NULL,               -- Número preimpreso
  diario_id               UUID NOT NULL REFERENCES diarios_contables(id), -- banco con chequera
  beneficiario_id         UUID REFERENCES contactos(id),
  nombre_en_cheque        TEXT,                        -- "Páguese a la orden de"
  monto                   NUMERIC(15,2) NOT NULL CHECK (monto > 0),
  monto_en_palabras       TEXT,                        -- generado automáticamente
  ciudad_emision          TEXT NOT NULL,               -- obligatorio Art. 1
  lugar_pago              TEXT,
  -- Fechas
  fecha_emision           DATE NOT NULL DEFAULT CURRENT_DATE,
  fecha_efectiva          DATE,                        -- post-fechado
  fecha_impresion         DATE,
  fecha_limite_cobro      DATE,                        -- fecha_emision + 20 días (Art. 58)
  fecha_cobro             DATE,
  fecha_devolucion        DATE,
  fecha_cancelacion       DATE,
  fecha_perdida           DATE,
  -- Certificación (Art. 2.12)
  es_certificado          BOOLEAN DEFAULT FALSE,
  fecha_certificacion     TIMESTAMPTZ,
  certificado_por_id      UUID REFERENCES usuarios(id),
  -- Tipo y estado
  tipo_movimiento         TEXT DEFAULT 'current'
                          CHECK (tipo_movimiento IN ('current','advance','other')),
  estado                  TEXT NOT NULL DEFAULT 'nuevo'
                          CHECK (estado IN ('nuevo','usado','impreso','entregado','cobrado','devuelto','cancelado','perdido','en_custodia')),
  -- Receptor (cuando se entrega)
  receptor_nombre         TEXT,
  receptor_cargo          TEXT,
  receptor_telefono       TEXT,
  -- Relacionados
  pago_id                 UUID REFERENCES pagos(id),
  nro_denuncia_policial   TEXT,
  comentarios             TEXT
);

ALTER TABLE cheques_emitidos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON cheques_emitidos FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- Unicidad cheque_no por diario bancario
CREATE UNIQUE INDEX uq_cheque_no_diario ON cheques_emitidos(empresa_id, cheque_no, diario_id);
```

### Tabla: `chequeras`

```sql
CREATE TABLE chequeras (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  diario_id       UUID NOT NULL REFERENCES diarios_contables(id),
  nro_desde       TEXT NOT NULL,
  nro_hasta       TEXT NOT NULL,
  fecha_recepcion DATE NOT NULL DEFAULT CURRENT_DATE,
  activa          BOOLEAN DEFAULT TRUE
);
```

---

## Validaciones Legales (Ley de Cheques Ecuador)

- **Art. 1**: beneficiario, ciudad de emisión y monto son obligatorios para usar un cheque
- **Art. 58**: plazo de presentación = 20 días desde fecha de emisión → `fecha_limite_cobro`
- El sistema alerta si se intenta imprimir/entregar un cheque vencido (wizard de confirmación)
- `cheque_no` es único por diario bancario

---

## Funciones RPC

```typescript
// Generar chequera (N cheques consecutivos)
generar_chequera(params: {
  diario_id: UUID
  nro_desde: string
  nro_hasta: string
  fecha_recepcion: string
}): { cheques_creados: number }

// Asignar cheque a un pago
asignar_cheque(params: {
  cheque_no: string
  diario_id: UUID
  pago_id: UUID
  beneficiario_id?: UUID
  monto: number
  fecha_efectiva?: string      // post-fechado
}): { cheque_id: UUID }

// Marcar como impreso
imprimir_cheque(cheque_id: UUID): { estado: 'impreso', fecha_impresion: string }

// Registrar entrega
entregar_cheque(params: {
  cheque_id: UUID
  receptor_nombre: string
  receptor_cargo?: string
}): { estado: 'entregado' }

// Cobrar (banco debita)
cobrar_cheque(params: {
  cheque_id: UUID
  fecha_cobro: string
}): { estado: 'cobrado', asiento_id: UUID }

// Devolver cheque
devolver_cheque(params: {
  cheque_id: UUID
  motivo: string
}): { estado: 'devuelto', asiento_reversion_id: UUID }

// Cancelar cheque
cancelar_cheque(params: {
  cheque_id: UUID
  motivo: string
}): { estado: 'cancelado' }

// Reportar perdido
reportar_perdido(params: {
  cheque_id: UUID
  nro_denuncia: string
}): { estado: 'perdido' }

// Dashboard de cheques
get_cheques_dashboard(): {
  por_cobrar: number
  vencidos: number
  por_vencer_5_dias: number
  total_monto_pendiente: number
}
```

---

## Edge Functions (Cron)

| Función | Trigger | Descripción |
|---|---|---|
| `check-expiring-checks` | Cron diario | Alerta a tesorero de cheques que vencen en N días (configurable) |
| `check-expired-checks` | Cron diario | Alerta de cheques ya vencidos (>20 días desde emisión) |
| `daily-check-report` | Cron diario (06:00) | Envía resumen al tesorero: emitidos hoy, pendientes, vencidos, por vencer |

---

## Configuración por Empresa

```json
{
  "cheques": {
    "dias_alerta_vencimiento": 5,
    "reporte_diario_activo": true,
    "emails_reporte_diario": ["tesorero@empresa.com"],
    "requiere_certificacion": false,
    "dias_plazo_cobro": 20
  }
}
```

---

## Validaciones de Negocio

- Solo se puede imprimir cheques en estado `usado`
- No se puede cancelar un cheque ya `cobrado`
- Cheques en estado `perdido` requieren número de denuncia policial
- `monto_en_palabras` se genera automáticamente en formato ecuatoriano: "DOSCIENTOS y 50/100"
- `fecha_limite_cobro = fecha_emision + 20 días` (automático)

---

## Pantallas Flutter

### Lista de Cheques
- `CrudScaffold<Cheque>` filtros: estado, diario, beneficiario, rango fechas
- Columnas: nro, beneficiario, banco, monto, fecha_emision, fecha_limite, estado
- Badge de color: verde (emitido/entregado), naranja (por vencer ≤5 días), rojo (vencido/devuelto)

### Formulario de Cheque

```
┌────────────────────────────────────────────────────────┐
│ CHEQUE EMITIDO                            [CHQ-00042]  │
│ Banco: [Banco Pichincha - Cta. Cte.]                   │
│ Nro Cheque: [003421]    Tipo: [Pago Ordinario ▼]       │
├────────────────────────────────────────────────────────┤
│ BENEFICIARIO (Art. 1 Ley Cheques)                      │
│ Páguese a: [selector contacto]                         │
│ Nombre en cheque: [___________]                        │
│ Monto: $[_______]  Ciudad: [Guayaquil]                 │
│ Monto en letras: MIL QUINIENTOS y 00/100              │
├────────────────────────────────────────────────────────┤
│ Fecha emisión: [2026-01-15]  Efectiva: [2026-02-01]   │
│ Vence: [2026-02-04]   ⚠️ Vence en 20 días             │
├────────────────────────────────────────────────────────┤
│ [Marcar Usado]  [Imprimir]  [Entregar]  [Cancelar]    │
└────────────────────────────────────────────────────────┘
```

### Gestión de Chequera
- Wizard para registrar recepción de nueva chequera (rango de números)
- Vista de cheques disponibles con indicador de uso

---

## Modelo de Datos Extendido

Las tablas a continuación reemplazan y amplían las definiciones iniciales con el esquema completo listo para migración, unificando cheques emitidos y recibidos en una sola tabla y formalizando la estructura de chequeras.

### Tabla: `chequeras` (esquema completo)

```sql
CREATE TABLE chequeras (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id          UUID NOT NULL REFERENCES empresas(id),
  cuenta_bancaria_id  UUID NOT NULL REFERENCES cuentas_bancarias(id),
  serie               VARCHAR(10) NOT NULL,           -- Prefijo SBS: "ART01"
  numero_desde        INTEGER NOT NULL,
  numero_hasta        INTEGER NOT NULL,
  numero_actual       INTEGER NOT NULL,               -- próximo número a usar
  estado              VARCHAR(15) DEFAULT 'ACTIVA'
                      CHECK (estado IN ('ACTIVA','AGOTADA','CANCELADA')),
  created_at          TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(empresa_id, serie, numero_desde)
);

ALTER TABLE chequeras ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON chequeras FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE INDEX idx_chequeras_empresa_cuenta ON chequeras(empresa_id, cuenta_bancaria_id, estado);
```

### Tabla: `cheques` (esquema unificado emitidos/recibidos)

```sql
CREATE TABLE cheques (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id          UUID NOT NULL REFERENCES empresas(id),
  chequera_id         UUID REFERENCES chequeras(id),
  tipo                VARCHAR(10) NOT NULL
                      CHECK (tipo IN ('EMITIDO','RECIBIDO','POSFECHADO')),
  numero              VARCHAR(20) NOT NULL,
  banco_id            UUID REFERENCES catalogo_bancos(id),
  cuenta_bancaria_id  UUID REFERENCES cuentas_bancarias(id),
  beneficiario        VARCHAR(300),                   -- Para cheques emitidos
  pagador             VARCHAR(300),                   -- Para cheques recibidos
  monto               DECIMAL(14,2) NOT NULL CHECK (monto > 0),
  fecha_emision       DATE NOT NULL,
  fecha_pago          DATE,                           -- NULL = a la vista; fecha = posfechado
  -- Vencimiento legal
  fecha_limite_cobro  DATE GENERATED ALWAYS AS (fecha_emision + INTERVAL '20 days') STORED,
  -- Estados
  estado              VARCHAR(15) DEFAULT 'CREADO'
                      CHECK (estado IN ('CREADO','ENTREGADO','DEPOSITADO','COBRADO','PROTESTADO','ANULADO','DEVUELTO')),
  referencia_pago_id  UUID,                           -- cobro/pago que originó el cheque
  asiento_id          UUID,
  motivo_protesto     TEXT,
  created_at          TIMESTAMPTZ DEFAULT NOW(),
  updated_at          TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(empresa_id, tipo, numero, banco_id)
);

ALTER TABLE cheques ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON cheques FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE INDEX idx_cheques_empresa_tipo   ON cheques(empresa_id, tipo, estado);
CREATE INDEX idx_cheques_fecha_limite   ON cheques(fecha_limite_cobro) WHERE estado NOT IN ('COBRADO','ANULADO','PROTESTADO');
CREATE INDEX idx_cheques_banco          ON cheques(banco_id, empresa_id);
```

---

## Funciones RPC Adicionales

### `create_check_from_payment`

Crea un cheque emitido a partir de un cobro/pago existente y asigna el número
siguiente de la chequera activa de la cuenta bancaria indicada.

```sql
CREATE OR REPLACE FUNCTION create_check_from_payment(
  p_cobro_id    UUID,
  p_numero      VARCHAR,
  p_fecha_pago  DATE        -- NULL = a la vista
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_cobro          RECORD;
  v_chequera       chequeras%ROWTYPE;
  v_cheque_id      UUID;
  v_tipo_cheque    VARCHAR(10);
BEGIN
  -- 1. Leer el cobro origen
  SELECT c.*, cb.cuenta_bancaria_id AS cta_id
  INTO   v_cobro
  FROM   cobros_multi c
  JOIN   cuentas_bancarias cb ON cb.id = c.cuenta_bancaria_id
  WHERE  c.id = p_cobro_id
    AND  c.empresa_id = (SELECT private.get_empresa_id());

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Cobro/pago no encontrado: %', p_cobro_id;
  END IF;

  -- 2. Tipo de cheque según operación
  v_tipo_cheque := CASE WHEN p_fecha_pago IS NOT NULL THEN 'POSFECHADO' ELSE 'EMITIDO' END;

  -- 3. Verificar y avanzar número de chequera
  SELECT * INTO v_chequera
  FROM chequeras
  WHERE cuenta_bancaria_id = v_cobro.cuenta_bancaria_id
    AND estado = 'ACTIVA'
    AND empresa_id = (SELECT private.get_empresa_id())
  ORDER BY created_at DESC
  LIMIT 1 FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No existe chequera activa para la cuenta bancaria';
  END IF;

  IF v_chequera.numero_actual > v_chequera.numero_hasta THEN
    UPDATE chequeras SET estado = 'AGOTADA' WHERE id = v_chequera.id;
    RAISE EXCEPTION 'Chequera agotada. Registre una nueva chequera.';
  END IF;

  -- 4. Insertar cheque
  INSERT INTO cheques(
    empresa_id, chequera_id, tipo, numero, banco_id,
    cuenta_bancaria_id, monto, fecha_emision, fecha_pago,
    estado, referencia_pago_id
  )
  VALUES (
    (SELECT private.get_empresa_id()), v_chequera.id, v_tipo_cheque,
    COALESCE(p_numero, v_chequera.serie || LPAD(v_chequera.numero_actual::TEXT,6,'0')),
    v_cobro.cta_id,   -- banco_id derivado de cuenta bancaria
    v_cobro.cuenta_bancaria_id,
    v_cobro.monto_total, CURRENT_DATE, p_fecha_pago,
    'CREADO', p_cobro_id
  )
  RETURNING id INTO v_cheque_id;

  -- 5. Avanzar número de chequera
  UPDATE chequeras
  SET numero_actual = numero_actual + 1,
      estado        = CASE WHEN numero_actual + 1 > numero_hasta THEN 'AGOTADA' ELSE 'ACTIVA' END
  WHERE id = v_chequera.id;

  RETURN jsonb_build_object(
    'cheque_id', v_cheque_id,
    'numero',    p_numero,
    'tipo',      v_tipo_cheque
  );
END;
$$;
```

### `process_check_protest`

Marca un cheque como PROTESTADO, crea el asiento de protesto (reversa el pago
original y carga intereses/gastos si los hay) y notifica al cliente vía
`module_bus`.

```sql
CREATE OR REPLACE FUNCTION process_check_protest(
  p_cheque_id UUID,
  p_motivo    TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_cheque      cheques%ROWTYPE;
  v_asiento_id  UUID;
BEGIN
  SELECT * INTO v_cheque FROM cheques WHERE id = p_cheque_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Cheque no encontrado: %', p_cheque_id;
  END IF;

  IF v_cheque.estado IN ('COBRADO','ANULADO','PROTESTADO') THEN
    RAISE EXCEPTION 'No se puede protestar un cheque en estado: %', v_cheque.estado;
  END IF;

  -- Asiento de protesto: reversa el ingreso original
  SELECT module_bus.contabilidad.create_journal_entry(jsonb_build_object(
    'descripcion', FORMAT('Protesto cheque %s — %s', v_cheque.numero, p_motivo),
    'fecha',       CURRENT_DATE,
    'lineas', jsonb_build_array(
      jsonb_build_object('cuenta_codigo','1.1.2', 'debe', v_cheque.monto, 'haber', 0),  -- CxC
      jsonb_build_object('cuenta_codigo','1.1.1', 'debe', 0, 'haber', v_cheque.monto)   -- Banco
    )
  )) INTO v_asiento_id;

  UPDATE cheques
  SET estado          = 'PROTESTADO',
      motivo_protesto = p_motivo,
      asiento_id      = v_asiento_id,
      updated_at      = NOW()
  WHERE id = p_cheque_id;

  -- Notificar al responsable (email + WhatsApp si está configurado)
  PERFORM module_bus.comunicacion.send_notification(jsonb_build_object(
    'tipo',      'CHEQUE_PROTESTADO',
    'cheque_id', p_cheque_id,
    'motivo',    p_motivo
  ));

  RETURN jsonb_build_object(
    'cheque_id',   p_cheque_id,
    'estado',      'PROTESTADO',
    'asiento_id',  v_asiento_id
  );
END;
$$;
```

### `get_checks_due_today`

Retorna los cheques posfechados cuya `fecha_pago` es hoy (listos para
depositar o cobrar). Usada por el cron job diario.

```sql
CREATE OR REPLACE FUNCTION get_checks_due_today(
  p_empresa_id UUID
)
RETURNS TABLE (
  cheque_id         UUID,
  numero            VARCHAR,
  tipo              VARCHAR,
  monto             DECIMAL,
  fecha_pago        DATE,
  fecha_limite_cobro DATE,
  beneficiario      VARCHAR,
  pagador           VARCHAR,
  cuenta_bancaria_id UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT
    c.id, c.numero, c.tipo, c.monto, c.fecha_pago,
    c.fecha_limite_cobro, c.beneficiario, c.pagador,
    c.cuenta_bancaria_id
  FROM cheques c
  WHERE c.empresa_id = p_empresa_id
    AND c.fecha_pago  = CURRENT_DATE
    AND c.estado      NOT IN ('COBRADO','ANULADO','PROTESTADO','DEPOSITADO')
  ORDER BY c.monto DESC;
END;
$$;
```

---

## Marco Legal Ecuador — Detalle

| Artículo | Disposición | Implementación en PILAR |
|---|---|---|
| **Art. 1 — Ley de Cheques** | El cheque debe indicar: orden incondicional de pago, nombre del banco, lugar y fecha de emisión, beneficiario y firma del librador | Campos obligatorios: `beneficiario`, `fecha_emision`, `banco_id`; validación antes de cambiar a estado ENTREGADO |
| **Art. 58 — Ley de Cheques** | Plazo de presentación: 20 días hábiles desde la fecha de emisión | `fecha_limite_cobro` calculada automáticamente; cron `check-expiring-checks` alerta 3 días antes; bloquea emisión si el cheque ya venció |
| **Art. 584 — COIP** | Giro de cheque sin fondos es delito penal (estafa) | Estado PROTESTADO registra `motivo_protesto`; notificación automática al área legal; reversa asiento contable |
| **Cheque cruzado (Art. 58 inc. 2)** | Solo puede depositarse en cuenta bancaria, no canjearse en ventanilla | Campo `tipo = 'RECIBIDO'` con flag `es_cruzado` (pendiente de añadir si se requiere en futuras iteraciones) |

### Alertas automáticas de vencimiento

El cron `check-expiring-checks` (diario, 07:00 ECT) alerta en los siguientes umbrales:

| Días restantes | Nivel | Canal |
|---|---|---|
| 5 días | Advertencia | Email al tesorero |
| 3 días | Alerta | Email + WhatsApp |
| Vencido (0 días) | Crítico | Email + WhatsApp + notificación in-app |
