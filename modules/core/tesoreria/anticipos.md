# Anticipos (Tesorería)

*Spec derivada del módulo `l10n_ec_advances` (Odoo 19.1 Ecuador — producción en csolish/tecnoh)*

---

## Descripción

Gestión completa de anticipos de clientes y proveedores con soporte para múltiples formas de pago, control de vencimientos, alertas automáticas y generación de asientos contables.

---

## Tipos de Anticipo

| Tipo | Dirección | Cuenta contable |
|---|---|---|
| `CLIENTE` (inbound) | Cliente paga por adelantado | Pasivo — anticipos de clientes (por pagar) |
| `PROVEEDOR` (outbound) | Empresa paga al proveedor adelantado | Activo — anticipos a proveedores (prepagos) |

---

## Estados del Ciclo de Vida

```
BORRADOR → PROCESADO → EN_USO → USADO
                   ↘          ↗
                   VENCIDO
         ↓
      CANCELADO / RECHAZADO
```

| Estado | Descripción | Transición |
|---|---|---|
| `BORRADOR` | Creado, sin confirmar | → PROCESADO (action_post) |
| `PROCESADO` | Confirmado, crea asientos | → EN_USO (cuando se usa parcialmente) |
| `EN_USO` | Parcialmente aplicado | → USADO (amount_available ≤ 0) |
| `USADO` | Completamente aplicado | — terminal |
| `VENCIDO` | Pasó fecha_vencimiento con saldo > 0 | — terminal, cron automático |
| `CANCELADO` | Anulado manualmente | Solo si no tiene pagos procesados |
| `RECHAZADO` | Rechazado por aprobador | Solo si no tiene pagos procesados |

---

## Modelo de Datos

### Tabla principal: `anticipos`

```sql
CREATE TABLE anticipos (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  nombre          TEXT,                          -- Secuencia: ANTP-0001 / ANTC-0001
  fecha           DATE NOT NULL DEFAULT CURRENT_DATE,
  fecha_estimada  DATE NOT NULL,                 -- fecha + dias_default (config empresa)
  fecha_vencimiento DATE,                        -- fecha_estimada + dias_default
  estado          TEXT NOT NULL DEFAULT 'borrador'
                  CHECK (estado IN ('borrador','procesado','en_uso','usado','vencido','cancelado','rechazado')),
  tipo_anticipo   TEXT NOT NULL CHECK (tipo_anticipo IN ('cliente','proveedor')),
  contacto_id     UUID NOT NULL REFERENCES contactos(id),
  cajero_id       UUID REFERENCES usuarios(id),
  glosa           TEXT NOT NULL,                 -- min 30 chars (configurable)
  monto           NUMERIC(15,2) GENERATED ALWAYS AS (
                    SELECT COALESCE(SUM(monto), 0) FROM anticipo_formas_pago WHERE anticipo_id = id
                  ) VIRTUAL,
  monto_usado     NUMERIC(15,2) DEFAULT 0,
  monto_disponible NUMERIC(15,2) DEFAULT 0,
  monto_devuelto  NUMERIC(15,2) DEFAULT 0,
  porcentaje_uso  NUMERIC(5,2) DEFAULT 0,
  prioridad       TEXT DEFAULT 'normal' CHECK (prioridad IN ('normal','alta','urgente')),
  -- Auditoría
  creado_en       TIMESTAMPTZ DEFAULT now(),
  actualizado_en  TIMESTAMPTZ DEFAULT now()
);

-- RLS
ALTER TABLE anticipos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON anticipos FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));
```

### Tabla: `anticipo_formas_pago` (líneas de métodos de pago)

```sql
CREATE TABLE anticipo_formas_pago (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  anticipo_id         UUID NOT NULL REFERENCES anticipos(id) ON DELETE CASCADE,
  empresa_id          UUID NOT NULL REFERENCES empresas(id),
  secuencia           INT DEFAULT 10,
  descripcion         TEXT,
  diario_id           UUID REFERENCES diarios_contables(id),    -- caja, banco, tarjeta
  metodo_pago         TEXT,                                      -- efectivo, cheque, transferencia, tarjeta
  monto               NUMERIC(15,2) NOT NULL CHECK (monto > 0),
  -- Datos del medio de pago
  nro_documento       TEXT,                -- # cheque / # transferencia / # voucher
  fecha_documento     DATE,
  banco_id            UUID REFERENCES catalogo_bancos(id),
  fecha_vencimiento_cheque DATE,
  marca_tarjeta_id    UUID,                -- referencia a marcas de tarjeta
  -- Estado
  asiento_id          UUID REFERENCES asientos_contables(id)
);
```

### Tabla: `anticipo_aplicaciones` (relación anticipo ↔ factura)

```sql
CREATE TABLE anticipo_aplicaciones (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  anticipo_id     UUID NOT NULL REFERENCES anticipos(id),
  factura_id      UUID NOT NULL REFERENCES facturas(id),
  monto_aplicado  NUMERIC(15,2) NOT NULL CHECK (monto_aplicado > 0),
  fecha_aplicacion DATE NOT NULL DEFAULT CURRENT_DATE,
  asiento_id      UUID REFERENCES asientos_contables(id)
);
```

---

## Lógica de Asientos Contables

### Anticipo de Cliente (inbound)

```
Al confirmar:
  DEBE: Caja/Banco  (diario seleccionado)       monto
  HABER: 2.1.1 Anticipos Clientes por Pagar      monto

Al aplicar contra factura:
  DEBE: 2.1.1 Anticipos Clientes por Pagar       monto_aplicado
  HABER: 1.1.2 Cuentas por Cobrar               monto_aplicado
```

### Anticipo a Proveedor (outbound)

```
Al confirmar:
  DEBE: 1.1.3 Anticipos Proveedores (prepago)    monto
  HABER: Caja/Banco (diario seleccionado)        monto

Al aplicar contra factura proveedor:
  DEBE: 2.1.2 Cuentas por Pagar                 monto_aplicado
  HABER: 1.1.3 Anticipos Proveedores            monto_aplicado
```

---

## Funciones RPC

```typescript
// Crear anticipo
create_anticipo(params: {
  tipo: 'cliente' | 'proveedor'
  contacto_id: UUID
  fecha: string
  glosa: string                // min 30 chars
  formas_pago: [{
    diario_id: UUID
    metodo_pago: string
    monto: number
    nro_documento?: string
    fecha_documento?: string
    banco_id?: UUID
    fecha_vencimiento_cheque?: string
  }]
}): { anticipo_id: UUID, nombre: string }

// Procesar (confirma y crea asientos)
procesar_anticipo(anticipo_id: UUID): { estado: string, asientos: UUID[] }

// Aplicar anticipo a factura
aplicar_anticipo(params: {
  anticipo_id: UUID
  factura_id: UUID
  monto_aplicado: number
}): { aplicacion_id: UUID, saldo_restante: number }

// Devolver saldo no usado
devolver_anticipo(params: {
  anticipo_id: UUID
  monto_devolucion: number
  diario_id: UUID
}): { asiento_id: UUID }

// Consultar anticipos disponibles de un contacto
get_anticipos_disponibles(params: {
  contacto_id: UUID
  tipo: 'cliente' | 'proveedor'
}): Anticipo[]
```

---

## Edge Functions

| Función | Trigger | Descripción |
|---|---|---|
| `check-expired-advances` | Cron diario | Marca como VENCIDO anticipos donde fecha_vencimiento < hoy y monto_disponible > 0 |
| `notify-expiring-advances` | Cron diario | Alerta N días antes del vencimiento (configurable) |

---

## Configuración por Empresa (`configuracion_empresa`)

```json
{
  "anticipos": {
    "dias_vencimiento_default": 30,
    "dias_alerta_vencimiento": 7,
    "min_chars_glosa": 30,
    "diario_anticipos_clientes_id": "uuid",
    "diario_anticipos_proveedores_id": "uuid",
    "cuenta_anticipos_clientes_id": "uuid",
    "cuenta_anticipos_proveedores_id": "uuid"
  }
}
```

---

## Validaciones de Negocio

- Glosa mínimo 30 caracteres (configurable)
- Monto total de formas de pago debe ser igual al monto del anticipo
- Fecha estimada debe ser ≥ fecha de registro
- No se puede cancelar si tiene pagos/aplicaciones procesados
- No se puede eliminar si tiene asientos contables
- Prioridad automática: monto ≥ $10.000 → Alta, ≥ $50.000 → Urgente

---

## Pantallas Flutter

### Lista de Anticipos
- `CrudScaffold<Anticipo>` con filtros: tipo, estado, contacto, rango fechas
- Columnas: nombre, fecha, contacto, tipo, monto, disponible, estado, vencimiento
- Badge de estado con color (verde=procesado, amarillo=en_uso, rojo=vencido)
- Indicador "días para vencer"

### Formulario de Anticipo
- `FormScaffold<Anticipo>` con secciones:
  1. **Encabezado**: tipo (cliente/proveedor), contacto, fecha, glosa
  2. **Formas de Pago**: tabla editable con diario, método, monto, datos adicionales
  3. **Aplicaciones**: lista de facturas donde se ha aplicado (readonly)
  4. **Totales**: monto total, usado, disponible, devuelto
- Botones: Procesar, Rechazar, Cancelar, Devolver saldo, Imprimir recibo

### Selector de Anticipos en Cobro/Pago
- Widget `AnticipoPicker` que aparece al registrar cobro/pago si el contacto tiene anticipos disponibles
- Muestra lista de anticipos con saldo disponible
- Permite aplicar total o parcialmente

---

## Modelo de Datos Extendido

Las tablas a continuación complementan y reemplazan las definiciones iniciales con el esquema completo listo para migración.

### Tabla: `anticipos` (esquema completo)

```sql
CREATE TABLE anticipos (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id          UUID NOT NULL REFERENCES empresas(id),
  tipo                VARCHAR(10) NOT NULL CHECK (tipo IN ('CLIENTE','PROVEEDOR')),
  contacto_id         UUID NOT NULL REFERENCES contactos(id),
  numero              VARCHAR(20) NOT NULL,          -- "ANT-001-001-000001"
  fecha               DATE NOT NULL,
  monto_total         DECIMAL(14,2) NOT NULL,
  monto_disponible    DECIMAL(14,2) NOT NULL,
  moneda_id           VARCHAR(3) DEFAULT 'USD',
  forma_pago          VARCHAR(2) REFERENCES catalogo_formas_pago(codigo),
  cuenta_bancaria_id  UUID REFERENCES cuentas_bancarias(id),
  estado              VARCHAR(15) DEFAULT 'BORRADOR'
                      CHECK (estado IN ('BORRADOR','PROCESADO','EN_USO','USADO','VENCIDO','CANCELADO','RECHAZADO')),
  fecha_vencimiento   DATE,
  referencia_sri      VARCHAR(49),                   -- clave acceso NC si se genera NC por anticipo vencido
  asiento_id          UUID,                          -- asiento contable generado
  aprobador_id        UUID REFERENCES auth.users(id),
  fecha_aprobacion    TIMESTAMPTZ,
  notas               TEXT,
  empresa_id_destino  UUID,                          -- Para intercompany
  version             INTEGER DEFAULT 1,
  created_at          TIMESTAMPTZ DEFAULT NOW(),
  updated_at          TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(empresa_id, numero)
);

ALTER TABLE anticipos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON anticipos FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE INDEX idx_anticipos_empresa_tipo ON anticipos(empresa_id, tipo, estado);
CREATE INDEX idx_anticipos_contacto     ON anticipos(contacto_id, estado);
```

### Tabla: `anticipo_aplicaciones` (esquema completo)

```sql
CREATE TABLE anticipo_aplicaciones (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  anticipo_id     UUID NOT NULL REFERENCES anticipos(id),
  documento_tipo  VARCHAR(20) NOT NULL,  -- 'FACTURA','ORDEN_COMPRA'
  documento_id    UUID NOT NULL,
  monto_aplicado  DECIMAL(14,2) NOT NULL,
  fecha           DATE NOT NULL,
  asiento_id      UUID,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE anticipo_aplicaciones ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation_apps" ON anticipo_aplicaciones FOR ALL TO authenticated
  USING (anticipo_id IN (
    SELECT id FROM anticipos
    WHERE empresa_id = (SELECT private.get_empresa_id())
  ));
```

---

## Funciones RPC Adicionales

### `apply_advance_to_invoice`

Aplica un anticipo (parcial o total) a una factura. Crea el asiento contable
(débito Anticipos de Clientes / crédito CxC), actualiza `monto_disponible` y
cambia el estado del anticipo.

```sql
CREATE OR REPLACE FUNCTION apply_advance_to_invoice(
  p_anticipo_id UUID,
  p_factura_id  UUID,
  p_monto       DECIMAL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_anticipo    anticipos%ROWTYPE;
  v_asiento_id  UUID;
  v_nuevo_disp  DECIMAL(14,2);
  v_nuevo_est   VARCHAR(15);
BEGIN
  -- 1. Leer y bloquear anticipo (bloqueo optimista)
  SELECT * INTO v_anticipo FROM anticipos WHERE id = p_anticipo_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Anticipo no encontrado: %', p_anticipo_id;
  END IF;

  IF v_anticipo.estado NOT IN ('PROCESADO','EN_USO') THEN
    RAISE EXCEPTION 'El anticipo no está disponible para aplicar (estado: %)', v_anticipo.estado;
  END IF;

  IF p_monto <= 0 OR p_monto > v_anticipo.monto_disponible THEN
    RAISE EXCEPTION 'Monto inválido: % (disponible: %)', p_monto, v_anticipo.monto_disponible;
  END IF;

  -- 2. Insertar aplicación
  INSERT INTO anticipo_aplicaciones(anticipo_id, documento_tipo, documento_id, monto_aplicado, fecha)
  VALUES (p_anticipo_id, 'FACTURA', p_factura_id, p_monto, CURRENT_DATE);

  -- 3. Crear asiento contable vía Module Service Bus
  SELECT module_bus.contabilidad.create_journal_entry(jsonb_build_object(
    'descripcion', FORMAT('Aplicación anticipo %s a factura', v_anticipo.numero),
    'fecha',       CURRENT_DATE,
    'lineas', jsonb_build_array(
      jsonb_build_object('cuenta_codigo','2.1.1', 'debe', p_monto, 'haber', 0),
      jsonb_build_object('cuenta_codigo','1.1.2', 'debe', 0,       'haber', p_monto)
    )
  )) INTO v_asiento_id;

  -- 4. Actualizar monto disponible y estado
  v_nuevo_disp := v_anticipo.monto_disponible - p_monto;
  v_nuevo_est  := CASE WHEN v_nuevo_disp <= 0 THEN 'USADO' ELSE 'EN_USO' END;

  UPDATE anticipos
  SET monto_disponible = v_nuevo_disp,
      estado           = v_nuevo_est,
      version          = version + 1,
      updated_at       = NOW()
  WHERE id = p_anticipo_id;

  -- 5. Actualizar saldo factura
  UPDATE facturas SET saldo_pendiente = saldo_pendiente - p_monto WHERE id = p_factura_id;

  RETURN jsonb_build_object(
    'aplicacion_id',   (SELECT id FROM anticipo_aplicaciones WHERE anticipo_id = p_anticipo_id AND documento_id = p_factura_id ORDER BY created_at DESC LIMIT 1),
    'asiento_id',      v_asiento_id,
    'saldo_restante',  v_nuevo_disp,
    'estado',          v_nuevo_est
  );
END;
$$;
```

### `expire_overdue_advances`

Cron job diario: marca como VENCIDO los anticipos con `fecha_vencimiento < TODAY`
y `monto_disponible > 0`. Opcionalmente genera una NC SRI para devolver el saldo
al cliente (vía `module_bus.facturacion.create_nota_credito`).

```sql
CREATE OR REPLACE FUNCTION expire_overdue_advances()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_anticipo  anticipos%ROWTYPE;
  v_count     INTEGER := 0;
BEGIN
  FOR v_anticipo IN
    SELECT * FROM anticipos
    WHERE estado IN ('PROCESADO','EN_USO')
      AND fecha_vencimiento < CURRENT_DATE
      AND monto_disponible > 0
    FOR UPDATE SKIP LOCKED
  LOOP
    -- Marcar como vencido
    UPDATE anticipos
    SET estado     = 'VENCIDO',
        updated_at = NOW()
    WHERE id = v_anticipo.id;

    -- Para anticipos de CLIENTE con saldo, generar NC automática
    IF v_anticipo.tipo = 'CLIENTE' AND v_anticipo.monto_disponible > 0 THEN
      PERFORM module_bus.facturacion.create_nota_credito(jsonb_build_object(
        'empresa_id',    v_anticipo.empresa_id,
        'contacto_id',   v_anticipo.contacto_id,
        'monto',         v_anticipo.monto_disponible,
        'motivo',        FORMAT('Devolución anticipo vencido %s', v_anticipo.numero),
        'referencia_id', v_anticipo.id
      ));
    END IF;

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;
```

### `get_advance_balance`

Retorna el saldo total de anticipos disponibles para un contacto dado.

```sql
CREATE OR REPLACE FUNCTION get_advance_balance(
  p_contacto_id UUID,
  p_tipo        VARCHAR
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_saldo  DECIMAL(14,2);
  v_cant   INTEGER;
BEGIN
  SELECT COALESCE(SUM(monto_disponible), 0),
         COUNT(*)
  INTO   v_saldo, v_cant
  FROM   anticipos
  WHERE  contacto_id = p_contacto_id
    AND  tipo        = p_tipo
    AND  estado      IN ('PROCESADO','EN_USO')
    AND  empresa_id  = (SELECT private.get_empresa_id());

  RETURN jsonb_build_object(
    'contacto_id',        p_contacto_id,
    'tipo',               p_tipo,
    'saldo_disponible',   v_saldo,
    'cantidad_anticipos', v_cant
  );
END;
$$;
```

---

## Cumplimiento SRI Ecuador

| Escenario | Tratamiento SRI |
|---|---|
| **Anticipo CLIENTE — recepción** | Empresa recibe pago, registra pasivo (Anticipos de Clientes). No emite comprobante SRI en este momento. |
| **Anticipo CLIENTE — aplicación** | Al aplicar contra una factura se cruzan las cuentas (débito Anticipos / crédito CxC). La factura ya tiene clave acceso SRI. |
| **Anticipo CLIENTE — vencimiento** | Si vence sin usarse, el cron `expire_overdue_advances` genera automáticamente una Nota de Crédito SRI (tipo 04) vía `module_bus.facturacion.create_nota_credito`. La NC obtiene su propia clave acceso (49 dígitos) que se almacena en `anticipos.referencia_sri`. |
| **Anticipo PROVEEDOR — pago** | Empresa paga anticipado al proveedor. Se registra activo (Anticipos a Proveedores). No genera comprobante SRI propio porque el proveedor emite la factura. |
| **Anticipo PROVEEDOR — aplicación** | Al recibir la factura del proveedor, se descuenta el anticipo (débito CxP / crédito Anticipos a Proveedores). |
