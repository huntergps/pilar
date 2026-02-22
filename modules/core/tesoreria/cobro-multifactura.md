# Cobro / Pago Multi-Factura (Tesorería)

*Spec derivada del módulo `l10n_ec_multiinvoice_payment` (Odoo 19.1 Ecuador — producción en csolish/tecnoh)*

---

## Descripción

Permite saldar múltiples facturas de un mismo contacto en una sola operación de cobro o pago. El monto total se distribuye entre las facturas seleccionadas, con soporte de pago parcial por factura. Muy común en Ecuador donde los clientes hacen abonos acumulados.

---

## Casos de Uso

| Caso | Actor | Descripción |
|---|---|---|
| Cobro masivo cliente | Vendedor/Cajero | Cliente paga varias facturas de una vez |
| Pago masivo proveedor | Contador | Pagar varias facturas proveedor en un solo cheque/transferencia |
| Abono parcial distribuido | Cajero | Cliente paga $500, se distribuye en facturas más antiguas primero |

---

## Modelo de Datos

### Tabla: `pagos` (extendida)

La tabla base `pagos` se extiende con:

```sql
-- Relación 1:N pago → facturas cubiertas
CREATE TABLE pago_facturas (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  pago_id         UUID NOT NULL REFERENCES pagos(id) ON DELETE CASCADE,
  factura_id      UUID NOT NULL REFERENCES facturas(id),
  monto_aplicado  NUMERIC(15,2) NOT NULL DEFAULT 0 CHECK (monto_aplicado >= 0),
  -- Campos derivados (desnormalizados para UI)
  fecha_factura   DATE,
  fecha_vencimiento DATE,
  monto_total     NUMERIC(15,2),
  saldo_pendiente NUMERIC(15,2),
  saldo_despues   NUMERIC(15,2) GENERATED ALWAYS AS (saldo_pendiente - monto_aplicado) STORED
);

ALTER TABLE pago_facturas ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON pago_facturas FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));
```

---

## Lógica de Distribución

### Distribución automática (más antigua primero — FIFO)

```
Dada una lista de facturas ordenadas por fecha_vencimiento ASC:

remaining = monto_pago
Para cada factura en orden:
  a_aplicar = MIN(saldo_pendiente_factura, remaining)
  pago_facturas[factura] = a_aplicar
  remaining -= a_aplicar
  if remaining <= 0: break
```

### Distribución manual

El usuario puede modificar `monto_aplicado` por factura. Restricciones:
- `monto_aplicado` ≤ `saldo_pendiente` de la factura
- Suma de todos los `monto_aplicado` ≤ `monto_pago`

---

## Funciones RPC

```typescript
// Obtener facturas pendientes de un contacto
get_facturas_pendientes(params: {
  contacto_id: UUID
  tipo: 'cobro' | 'pago'   // cobro=facturas emitidas, pago=facturas recibidas
  moneda_id?: UUID
}): {
  facturas: [{
    factura_id: UUID
    numero: string
    fecha: string
    fecha_vencimiento: string
    monto_total: number
    saldo_pendiente: number
  }]
  total_deuda: number
}

// Crear cobro/pago multi-factura
create_pago_multifactura(params: {
  contacto_id: UUID
  tipo: 'cobro' | 'pago'
  fecha: string
  monto_total: number
  diario_id: UUID
  metodo_pago: string
  facturas: [{
    factura_id: UUID
    monto_aplicado: number
  }]
  referencia?: string
  nota?: string
}): {
  pago_id: UUID
  asiento_id: UUID
  facturas_saldadas: UUID[]      // facturas que quedaron en $0
  facturas_parciales: UUID[]     // facturas con pago parcial
}

// Distribuir automáticamente (FIFO)
distribuir_pago_automatico(params: {
  monto: number
  facturas: [{ factura_id: UUID, saldo_pendiente: number, fecha: string }]
}): [{ factura_id: UUID, monto_aplicado: number }]

// Marcar "pagar todo" (llena monto_aplicado = saldo_pendiente en todas)
pagar_todo(pago_id: UUID): void

// Limpiar distribución (pone monto_aplicado = 0 en todas)
limpiar_distribucion(pago_id: UUID): void
```

---

## Validaciones de Negocio

- Todas las facturas deben ser del mismo contacto
- Todas las facturas deben estar en estado `AUTORIZADA` / `PUBLICADA` (no borrador)
- `monto_aplicado` nunca puede exceder `saldo_pendiente` de la factura
- Suma de `monto_aplicado` ≤ monto total del pago
- No se puede aplicar $0 a ninguna factura (si se selecciona, debe tener monto > 0)

---

## Pantallas Flutter

### Pantalla de Cobro Multi-Factura

```
┌─────────────────────────────────────────────────┐
│ COBRO DE CLIENTE           [Fecha] [Método Pago]│
│ Cliente: [selector contacto]                    │
├─────────────────────────────────────────────────┤
│ FACTURAS PENDIENTES                             │
│ ┌──────┬──────────┬─────────┬──────────┬──────┐│
│ │ #    │ Fecha    │ Total   │ Saldo    │ Pago ││
│ ├──────┼──────────┼─────────┼──────────┼──────┤│
│ │FAC-1 │ 01/01/26 │ $500    │ $500     │ $500 ││
│ │FAC-2 │ 15/01/26 │ $300    │ $300     │ $200 ││
│ │FAC-3 │ 01/02/26 │ $200    │ $200     │ $0   ││
│ └──────┴──────────┴─────────┴──────────┴──────┘│
│           [Cargar Deudas] [Pagar Todo] [Limpiar]│
├─────────────────────────────────────────────────┤
│ TOTAL DEUDA: $1,000    TOTAL A PAGAR: $700      │
│ [Registrar Cobro]                               │
└─────────────────────────────────────────────────┘
```

### Componente `MultiFacturaPicker`

Widget reutilizable usado en:
- Pantalla de cobros (Tesorería)
- Pantalla de pagos a proveedores (Tesorería)
- POS (para cobros con facturas pendientes del cliente)

### Acciones disponibles

| Botón | Acción |
|---|---|
| **Cargar Deudas** | Carga todas las facturas pendientes del contacto |
| **Pagar Todo** | monto_aplicado = saldo_pendiente en todas |
| **Limpiar** | monto_aplicado = 0 en todas |
| **[↕ Saldo]** (por línea) | Alterna entre 0 y saldo_pendiente |
| **Registrar Cobro/Pago** | Valida y crea el pago con reconciliaciones |

### Integración con método de pago mixto

El `MultiFacturaPicker` puede combinarse con el widget de `FormasPagoMixtas` para:
- Pagar $700 en deuda: $400 efectivo + $300 tarjeta
- Cada forma de pago se divide proporcionalmente entre las facturas

---

## Modelo de Datos Extendido

Las tablas a continuación formalizan el esquema completo listo para migración,
reemplazando la extensión sobre `pagos` con entidades dedicadas para cobros/pagos
multi-factura.

### Tabla: `cobros_multi`

```sql
CREATE TABLE cobros_multi (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id          UUID NOT NULL REFERENCES empresas(id),
  contacto_id         UUID NOT NULL REFERENCES contactos(id),
  tipo                VARCHAR(5) NOT NULL CHECK (tipo IN ('COBRO','PAGO')),
  fecha               DATE NOT NULL,
  monto_total         DECIMAL(14,2) NOT NULL CHECK (monto_total > 0),
  -- Distribución por método de pago (puede ser mix de métodos)
  efectivo            DECIMAL(14,2) DEFAULT 0,
  transferencia       DECIMAL(14,2) DEFAULT 0,
  cheque              DECIMAL(14,2) DEFAULT 0,
  tarjeta             DECIMAL(14,2) DEFAULT 0,
  anticipo            DECIMAL(14,2) DEFAULT 0,    -- Desde anticipo disponible del contacto
  nota_credito        DECIMAL(14,2) DEFAULT 0,    -- Desde NC disponible
  retencion           DECIMAL(14,2) DEFAULT 0,
  cuenta_bancaria_id  UUID REFERENCES cuentas_bancarias(id),
  cheque_id           UUID REFERENCES cheques(id),
  anticipo_id         UUID REFERENCES anticipos(id),
  asiento_id          UUID,
  referencia          VARCHAR(100),
  notas               TEXT,
  creado_por          UUID REFERENCES auth.users(id),
  created_at          TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE cobros_multi ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON cobros_multi FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE INDEX idx_cobros_multi_empresa_tipo ON cobros_multi(empresa_id, tipo, fecha DESC);
CREATE INDEX idx_cobros_multi_contacto     ON cobros_multi(contacto_id, tipo);
```

### Tabla: `cobros_multi_facturas`

```sql
CREATE TABLE cobros_multi_facturas (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cobro_id        UUID NOT NULL REFERENCES cobros_multi(id) ON DELETE CASCADE,
  factura_id      UUID NOT NULL REFERENCES facturas(id),
  monto_aplicado  DECIMAL(14,2) NOT NULL CHECK (monto_aplicado > 0),
  saldo_anterior  DECIMAL(14,2) NOT NULL,
  saldo_despues   DECIMAL(14,2) NOT NULL
);

ALTER TABLE cobros_multi_facturas ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation_lineas" ON cobros_multi_facturas FOR ALL TO authenticated
  USING (cobro_id IN (
    SELECT id FROM cobros_multi
    WHERE empresa_id = (SELECT private.get_empresa_id())
  ));

CREATE INDEX idx_cobros_multi_facturas_cobro    ON cobros_multi_facturas(cobro_id);
CREATE INDEX idx_cobros_multi_facturas_factura  ON cobros_multi_facturas(factura_id);
```

---

## Funciones RPC Adicionales

### `create_multi_payment`

Crea un cobro/pago multi-factura con distribución FIFO (factura más antigua
primero). Valida que solo se use USD (Ecuador dolarizado), genera el asiento
contable y actualiza el saldo de cada factura.

```sql
CREATE OR REPLACE FUNCTION create_multi_payment(params JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_cobro_id      UUID;
  v_asiento_id    UUID;
  v_factura       RECORD;
  v_linea         JSONB;
  v_restante      DECIMAL(14,2);
  v_a_aplicar     DECIMAL(14,2);
  v_saldadas      UUID[] := '{}';
  v_parciales     UUID[] := '{}';
BEGIN
  -- 1. Validar moneda (Ecuador solo USD)
  IF (params->>'moneda_id') IS NOT NULL AND (params->>'moneda_id') <> 'USD' THEN
    RAISE EXCEPTION 'Solo se permite USD en Ecuador (dollarización desde 2000)';
  END IF;

  -- 2. Validar distribución de métodos de pago
  PERFORM validate_payment_distribution(params);

  -- 3. Insertar cobro cabecera
  INSERT INTO cobros_multi(
    empresa_id, contacto_id, tipo, fecha, monto_total,
    efectivo, transferencia, cheque, tarjeta, anticipo, nota_credito, retencion,
    cuenta_bancaria_id, cheque_id, anticipo_id, referencia, notas, creado_por
  )
  VALUES (
    (SELECT private.get_empresa_id()),
    (params->>'contacto_id')::UUID,
    params->>'tipo',
    (params->>'fecha')::DATE,
    (params->>'monto_total')::DECIMAL,
    COALESCE((params->>'efectivo')::DECIMAL, 0),
    COALESCE((params->>'transferencia')::DECIMAL, 0),
    COALESCE((params->>'cheque')::DECIMAL, 0),
    COALESCE((params->>'tarjeta')::DECIMAL, 0),
    COALESCE((params->>'anticipo')::DECIMAL, 0),
    COALESCE((params->>'nota_credito')::DECIMAL, 0),
    COALESCE((params->>'retencion')::DECIMAL, 0),
    (params->>'cuenta_bancaria_id')::UUID,
    (params->>'cheque_id')::UUID,
    (params->>'anticipo_id')::UUID,
    params->>'referencia',
    params->>'notas',
    auth.uid()
  )
  RETURNING id INTO v_cobro_id;

  -- 4. Distribuir FIFO entre facturas (ordenadas por fecha_vencimiento ASC)
  v_restante := (params->>'monto_total')::DECIMAL;

  FOR v_factura IN
    SELECT f.id, f.saldo_pendiente
    FROM facturas f
    JOIN jsonb_array_elements(params->'facturas') AS lf ON (lf->>'factura_id')::UUID = f.id
    WHERE f.empresa_id = (SELECT private.get_empresa_id())
    ORDER BY f.fecha_vencimiento ASC
  LOOP
    EXIT WHEN v_restante <= 0;

    v_a_aplicar := LEAST(v_factura.saldo_pendiente, v_restante);

    INSERT INTO cobros_multi_facturas(cobro_id, factura_id, monto_aplicado, saldo_anterior, saldo_despues)
    VALUES (v_cobro_id, v_factura.id, v_a_aplicar, v_factura.saldo_pendiente, v_factura.saldo_pendiente - v_a_aplicar);

    UPDATE facturas
    SET saldo_pendiente = saldo_pendiente - v_a_aplicar,
        estado = CASE WHEN saldo_pendiente - v_a_aplicar <= 0 THEN 'PAGADA' ELSE estado END
    WHERE id = v_factura.id;

    IF v_factura.saldo_pendiente - v_a_aplicar <= 0 THEN
      v_saldadas := array_append(v_saldadas, v_factura.id);
    ELSE
      v_parciales := array_append(v_parciales, v_factura.id);
    END IF;

    v_restante := v_restante - v_a_aplicar;
  END LOOP;

  -- 5. Crear asiento contable vía Module Service Bus
  SELECT module_bus.contabilidad.create_journal_entry(jsonb_build_object(
    'descripcion', FORMAT('Cobro multi-factura — %s', params->>'referencia'),
    'fecha',       params->>'fecha',
    'lineas', jsonb_build_array(
      jsonb_build_object('cuenta_codigo','1.1.1', 'debe', params->>'monto_total', 'haber', 0),
      jsonb_build_object('cuenta_codigo','1.1.2', 'debe', 0, 'haber', params->>'monto_total')
    )
  )) INTO v_asiento_id;

  UPDATE cobros_multi SET asiento_id = v_asiento_id WHERE id = v_cobro_id;

  RETURN jsonb_build_object(
    'cobro_id',          v_cobro_id,
    'asiento_id',        v_asiento_id,
    'facturas_saldadas', v_saldadas,
    'facturas_parciales', v_parciales,
    'restante_sin_aplicar', v_restante
  );
END;
$$;
```

### `get_outstanding_invoices`

Retorna las facturas pendientes de un contacto ordenadas por fecha de
vencimiento (más antigua primero), listas para el selector de la UI.

```sql
CREATE OR REPLACE FUNCTION get_outstanding_invoices(
  p_contacto_id UUID,
  p_tipo        VARCHAR   -- 'COBRO' = facturas emitidas; 'PAGO' = facturas proveedor
)
RETURNS TABLE (
  factura_id        UUID,
  numero            VARCHAR,
  fecha             DATE,
  fecha_vencimiento DATE,
  monto_total       DECIMAL,
  saldo_pendiente   DECIMAL,
  dias_vencido      INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT
    f.id,
    f.numero,
    f.fecha::DATE,
    f.fecha_vencimiento::DATE,
    f.total::DECIMAL(14,2),
    f.saldo_pendiente::DECIMAL(14,2),
    (CURRENT_DATE - f.fecha_vencimiento)::INTEGER AS dias_vencido
  FROM facturas f
  WHERE f.empresa_id  = (SELECT private.get_empresa_id())
    AND f.contacto_id = p_contacto_id
    AND f.saldo_pendiente > 0
    AND f.estado IN ('AUTORIZADA','PUBLICADA')
    AND (
      (p_tipo = 'COBRO' AND f.tipo_documento IN ('01','04','05'))  -- facturas emitidas
      OR
      (p_tipo = 'PAGO'  AND f.tipo_documento IN ('01','03'))       -- facturas proveedor
    )
  ORDER BY f.fecha_vencimiento ASC;
END;
$$;
```

### `validate_payment_distribution`

Verifica que el total distribuido en métodos de pago sea igual al
`monto_total`, y que ninguna factura tenga `monto_aplicado` mayor a su saldo
pendiente. Lanza excepción si hay inconsistencias.

```sql
CREATE OR REPLACE FUNCTION validate_payment_distribution(params JSONB)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_suma_metodos  DECIMAL(14,2);
  v_monto_total   DECIMAL(14,2);
  v_suma_facturas DECIMAL(14,2);
  v_linea         JSONB;
  v_saldo         DECIMAL(14,2);
BEGIN
  v_monto_total := (params->>'monto_total')::DECIMAL;

  -- Suma de métodos de pago
  v_suma_metodos :=
    COALESCE((params->>'efectivo')::DECIMAL,     0) +
    COALESCE((params->>'transferencia')::DECIMAL, 0) +
    COALESCE((params->>'cheque')::DECIMAL,        0) +
    COALESCE((params->>'tarjeta')::DECIMAL,       0) +
    COALESCE((params->>'anticipo')::DECIMAL,      0) +
    COALESCE((params->>'nota_credito')::DECIMAL,  0) +
    COALESCE((params->>'retencion')::DECIMAL,     0);

  IF ABS(v_suma_metodos - v_monto_total) > 0.01 THEN
    RAISE EXCEPTION 'Distribución de métodos de pago (%) no coincide con monto total (%)',
      v_suma_metodos, v_monto_total;
  END IF;

  -- Verificar que ninguna factura reciba más que su saldo
  FOR v_linea IN SELECT * FROM jsonb_array_elements(params->'facturas') LOOP
    SELECT saldo_pendiente INTO v_saldo
    FROM facturas
    WHERE id = (v_linea->>'factura_id')::UUID
      AND empresa_id = (SELECT private.get_empresa_id());

    IF (v_linea->>'monto_aplicado')::DECIMAL > v_saldo THEN
      RAISE EXCEPTION 'monto_aplicado (%) excede saldo_pendiente (%) en factura %',
        (v_linea->>'monto_aplicado')::DECIMAL, v_saldo, v_linea->>'factura_id';
    END IF;
  END LOOP;
END;
$$;
```

### `convert_to_functional`

Convierte un monto de cualquier moneda a USD (moneda funcional de Ecuador)
usando la tasa de cambio del día. Para documentos de importación con moneda
distinta.

```sql
CREATE OR REPLACE FUNCTION convert_to_functional(
  p_monto  DECIMAL,
  p_moneda VARCHAR,
  p_fecha  DATE
)
RETURNS DECIMAL(14,2)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_tasa DECIMAL(18,6);
BEGIN
  -- Ecuador está dolarizado: si ya es USD, retornar directo
  IF p_moneda = 'USD' THEN
    RETURN p_monto;
  END IF;

  SELECT tasa_usd INTO v_tasa
  FROM tasas_cambio
  WHERE moneda_id = p_moneda
    AND fecha     = p_fecha
  ORDER BY created_at DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No existe tasa de cambio para % en fecha %', p_moneda, p_fecha;
  END IF;

  -- Redondeo SOLO al final (convención del proyecto)
  RETURN ROUND(p_monto / v_tasa, 2);
END;
$$;
```

---

## Consideraciones de Moneda — Ecuador Dolarizado

Ecuador adoptó el dólar estadounidense (USD) como moneda de curso legal el
**13 de marzo de 2000** (Ley de Transformación Económica). Por ello:

| Regla | Detalle |
|---|---|
| **Moneda funcional** | Siempre USD. El sistema rechaza cobros en otra moneda vía `validate_payment_distribution`. |
| **Facturas de importación** | Pueden originarse en EUR/CNY/etc. Se convierten a USD al tipo de cambio del día de la factura usando `convert_to_functional`. |
| **Tasas de cambio** | Tabla `tasas_cambio` alimentada por cron desde el Banco Central del Ecuador (BCE) o referencial SRI. |
| **Precisión** | `DECIMAL(14,2)` para montos finales. Redondeo solo al final del cálculo (nunca en intermedios). |
| **Retenciones** | Se calculan sobre el subtotal en USD. Si la factura de importación está en otra moneda, se convierte primero. |
