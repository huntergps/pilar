# Conciliación de Tarjetas de Crédito/Débito (Tesorería)

*Spec derivada del módulo `l10n_ec_card_reconciliation` (Odoo 19.1 Ecuador — producción en csolish/tecnoh)*

---

## Descripción

Proceso de reconciliar el estado de cuenta enviado por el banco emisor de tarjeta (Visa, Mastercard, Diners, etc.) contra los pagos con tarjeta registrados en PILAR. Cubre: comisiones del adquirente, IVA de comisiones, retenciones en la fuente, y generación del asiento de liquidación.

---

## Flujo General

```
1. Importar estado de cuenta del emisor (CSV)
     ↓
2. Auto-conciliar líneas con pagos registrados en PILAR
     ↓
3. Conciliar manualmente líneas no encontradas
     ↓
4. Generar asiento de liquidación (banco recibe neto)
     ↓
5. Marcar estado de cuenta como conciliado
```

---

## Modelo de Datos

### Tabla: `marcas_tarjeta` (catálogo)

```sql
CREATE TABLE marcas_tarjeta (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id              UUID NOT NULL REFERENCES empresas(id),
  nombre                  TEXT NOT NULL,          -- "Visa Banco Pichincha", "Mastercard Produbanco"
  codigo                  TEXT,                   -- código interno
  banco_id                UUID REFERENCES catalogo_bancos(id),
  cuenta_liquidacion_id   UUID REFERENCES cuentas_contables(id),  -- cuenta por cobrar al emisor
  tasa_comision_default   NUMERIC(8,4) DEFAULT 0,
  tasa_retencion_default  NUMERIC(8,4) DEFAULT 0,
  activa                  BOOLEAN DEFAULT TRUE
);
```

### Tabla: `estados_cuenta_tarjeta`

```sql
CREATE TABLE estados_cuenta_tarjeta (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id          UUID NOT NULL REFERENCES empresas(id),
  referencia          TEXT NOT NULL,
  fecha               DATE NOT NULL DEFAULT CURRENT_DATE,
  fecha_desde         DATE NOT NULL,
  fecha_hasta         DATE NOT NULL,
  marca_tarjeta_id    UUID NOT NULL REFERENCES marcas_tarjeta(id),
  diario_id           UUID NOT NULL REFERENCES diarios_contables(id),  -- diario bancario destino
  estado              TEXT DEFAULT 'borrador'
                      CHECK (estado IN ('borrador','confirmado','conciliado','cancelado')),
  -- Totales calculados
  total_ventas        NUMERIC(15,2) DEFAULT 0,
  total_comision      NUMERIC(15,2) DEFAULT 0,
  total_iva           NUMERIC(15,2) DEFAULT 0,
  total_retencion     NUMERIC(15,2) DEFAULT 0,
  total_a_recibir     NUMERIC(15,2) DEFAULT 0,  -- neto que deposita el emisor
  -- Contadores
  total_lineas        INT DEFAULT 0,
  lineas_conciliadas  INT DEFAULT 0,
  -- Notas
  notas               TEXT
);

ALTER TABLE estados_cuenta_tarjeta ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON estados_cuenta_tarjeta FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));
```

### Tabla: `estados_cuenta_tarjeta_lineas`

```sql
CREATE TABLE estados_cuenta_tarjeta_lineas (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  estado_cuenta_id      UUID NOT NULL REFERENCES estados_cuenta_tarjeta(id) ON DELETE CASCADE,
  secuencia             INT DEFAULT 10,
  fecha                 DATE NOT NULL,
  nro_lote              TEXT NOT NULL,
  nro_comprobante       TEXT NOT NULL,
  nro_autorizacion      TEXT,
  establecimiento       TEXT,
  -- Montos
  monto                 NUMERIC(15,2) NOT NULL,    -- monto de la venta
  tasa_comision         NUMERIC(8,4) DEFAULT 0,
  monto_comision        NUMERIC(15,2) DEFAULT 0,
  monto_iva             NUMERIC(15,2) DEFAULT 0,
  tasa_retencion        NUMERIC(8,4) DEFAULT 0,
  monto_retencion       NUMERIC(15,2) DEFAULT 0,
  monto_neto            NUMERIC(15,2),             -- monto - comision - retencion + iva
  -- Conciliación
  pago_id               UUID REFERENCES pagos(id),
  contacto_id           UUID REFERENCES contactos(id),
  conciliado            BOOLEAN DEFAULT FALSE,
  -- Anti-duplicados
  identificador_unico   TEXT,   -- MD5(marca_id|lote|comprobante|monto|fecha)
  -- Marca relacionada (desnormalizado para filtros)
  marca_tarjeta_id      UUID REFERENCES marcas_tarjeta(id)
);
```

---

## Importación de Estado de Cuenta

### Formato CSV (genérico — personalizable por banco)

```
Fecha,Lote,Comprobante,Autorización,Establecimiento,Monto,Comisión%,Comisión$,IVA,Retención%,Retención$,Neto
2026-01-15,00123,987654321,456789,SUCURSAL NORTE,250.00,3.5,8.75,1.05,1.0,2.50,239.80
```

### Edge Function: `import-card-statement`

```typescript
POST /functions/v1/import-card-statement
Body: {
  empresa_id: UUID
  estado_cuenta_id: UUID
  archivo_base64: string    // CSV en base64
  formato: 'pichincha' | 'produbanco' | 'pacifico' | 'generico'
}
Response: {
  lineas_importadas: number
  duplicados_omitidos: number
  errores: string[]
}
```

---

## Auto-Conciliación

Busca pagos que coincidan con: `nro_lote + nro_comprobante + monto + estado=PROCESADO + es_pago_tarjeta=true`

- Si hay **1 coincidencia exacta** → concilia automáticamente
- Si hay **múltiples coincidencias** → requiere selección manual
- Si hay **0 coincidencias** → marca como pendiente

---

## Asiento de Liquidación

Al conciliar el estado de cuenta completo, genera:

```
DEBE: 1.1.2.x Banco (donde deposita el emisor)    total_a_recibir
DEBE: 6.x.x.1 Comisiones Bancarias                total_comision
DEBE: 1.1.3.x IVA en Compras (si aplica)          total_iva
DEBE: 1.1.3.x Retenciones en la Fuente            total_retencion
HABER: 1.1.2.x Cuenta Emisor Tarjeta              total_ventas
```

---

## Funciones RPC

```typescript
// Crear estado de cuenta
create_estado_cuenta_tarjeta(params: {
  marca_tarjeta_id: UUID
  diario_id: UUID
  fecha: string
  fecha_desde: string
  fecha_hasta: string
}): { estado_cuenta_id: UUID, referencia: string }

// Confirmar (dispara auto-conciliación)
confirmar_estado_cuenta(estado_cuenta_id: UUID): {
  lineas_conciliadas: number
  lineas_pendientes: number
}

// Conciliar línea manualmente
conciliar_linea(params: {
  linea_id: UUID
  pago_id: UUID
}): { conciliado: boolean }

// Desconciliar línea
desconciliar_linea(linea_id: UUID): void

// Generar asiento de liquidación (estado → conciliado)
generar_liquidacion(estado_cuenta_id: UUID): {
  asiento_id: UUID
  estado: 'conciliado'
}

// Cancelar estado de cuenta
cancelar_estado_cuenta(estado_cuenta_id: UUID): void
```

---

## Validaciones de Negocio

- `fecha_desde` ≤ `fecha_hasta`
- No puede confirmarse sin líneas
- No puede conciliarse si no está confirmado
- `identificador_unico` es único → previene duplicados en importación
- No puede cancelarse si tiene asientos publicados

---

## Catálogo Bancario Ecuador (predefinido)

Los bancos emisores principales con sus tasas típicas:

| Banco | Tasa comisión típica | Retención |
|---|---|---|
| Visa Pichincha | 3.5% + IVA | 1% fuente |
| Mastercard Produbanco | 3.5% + IVA | 1% fuente |
| Diners Club | 5.5% + IVA | 0% |
| American Express | 5.0% + IVA | 0% |

> Las tasas se configuran por marca_tarjeta y pueden sobreescribirse línea a línea.

---

## Pantallas Flutter

### Lista de Estados de Cuenta
- `CrudScaffold<EstadoCuentaTarjeta>` con filtros: marca, fecha, estado
- Columnas: referencia, marca, período, total_ventas, comisiones, neto, estado, conciliadas/total

### Detalle del Estado de Cuenta

```
┌────────────────────────────────────────────────────────┐
│ ESTADO DE CUENTA TARJETA                               │
│ Visa Pichincha | 01/01/2026 - 31/01/2026              │
├────────────────────────────────────────────────────────┤
│ Resumen: Ventas $10,500 | Comisión $367 | Neto $9,981 │
├────────────────────────────────────────────────────────┤
│ LÍNEAS (127 total | 121 conciliadas | 6 pendientes)   │
│ [Solo pendientes ▼] [Auto-conciliar] [Importar CSV]   │
│ ┌─────┬────────┬──────────┬────────┬──────┬──────────┐│
│ │Fecha│Lote    │Comprob.  │ Monto  │Neto  │Estado    ││
│ ├─────┼────────┼──────────┼────────┼──────┼──────────┤│
│ │01/01│00123   │987654321 │$250.00 │$239.8│✓ Concil. ││
│ │02/01│00124   │987654322 │$180.00 │$172.7│⚠ Pend.   ││
│ └─────┴────────┴──────────┴────────┴──────┴──────────┘│
├────────────────────────────────────────────────────────┤
│ [Confirmar]  [Generar Liquidación]  [Cancelar]        │
└────────────────────────────────────────────────────────┘
```

### Conciliación Manual
- Tap en línea pendiente → abre buscador de pagos
- Filtros: fecha ±3 días, monto similar
- Botón "Crear Pago" si no existe

---

## Modelo de Datos Completo (Ampliado)

Las tablas siguientes complementan el modelo anterior con soporte para lotes por banco adquirente, transacciones individuales con match por voucher, y columnas generadas para comisiones e IVA.

### Tabla: `lotes_tarjeta`

```sql
CREATE TABLE lotes_tarjeta (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id           UUID NOT NULL REFERENCES empresas(id),
  cuenta_bancaria_id   UUID NOT NULL REFERENCES cuentas_bancarias(id),
  banco_adquirente     VARCHAR(50) NOT NULL,  -- 'PICHINCHA','PACIFICO','GUAYAQUIL','BOLIVARIANO','INTERNACIONAL'
  terminal_id          VARCHAR(20),           -- ID del datáfono/terminal POS
  numero_lote          VARCHAR(20),
  fecha_lote           DATE NOT NULL,
  total_bruto          DECIMAL(14,2) NOT NULL,
  comision_pct         DECIMAL(5,4) NOT NULL, -- Ej: 0.0350 = 3.5%
  comision_monto       DECIMAL(14,2) GENERATED ALWAYS AS (
                         ROUND(total_bruto * comision_pct, 2)
                       ) STORED,
  iva_comision         DECIMAL(14,2) GENERATED ALWAYS AS (
                         ROUND(total_bruto * comision_pct * 0.15, 2)
                       ) STORED,
  neto_a_acreditar     DECIMAL(14,2) GENERATED ALWAYS AS (
                         total_bruto
                         - ROUND(total_bruto * comision_pct, 2)
                         - ROUND(total_bruto * comision_pct * 0.15, 2)
                       ) STORED,
  fecha_acreditacion   DATE,                 -- Fecha en que el banco acredita el neto
  estado               VARCHAR(20) DEFAULT 'PENDIENTE'
                       CHECK (estado IN ('PENDIENTE','IMPORTADO','CONCILIADO','CON_DIFERENCIAS')),
  archivo_csv_url      TEXT,                 -- URL del archivo original en Supabase Storage
  asiento_id           UUID,
  created_at           TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(empresa_id, banco_adquirente, numero_lote, fecha_lote)
);

ALTER TABLE lotes_tarjeta ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON lotes_tarjeta FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE INDEX idx_lotes_tarjeta_empresa_fecha ON lotes_tarjeta(empresa_id, fecha_lote);
CREATE INDEX idx_lotes_tarjeta_banco_estado  ON lotes_tarjeta(banco_adquirente, estado);
```

### Tabla: `lote_tarjeta_transacciones`

```sql
CREATE TABLE lote_tarjeta_transacciones (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lote_id             UUID NOT NULL REFERENCES lotes_tarjeta(id) ON DELETE CASCADE,
  empresa_id          UUID NOT NULL REFERENCES empresas(id),
  tipo                VARCHAR(10) NOT NULL CHECK (tipo IN ('VENTA','DEVOLUCION','ANULACION')),
  numero_voucher      VARCHAR(20),
  tarjeta_ultimos_4   VARCHAR(4),
  monto               DECIMAL(14,2) NOT NULL,
  hora_transaccion    TIMESTAMPTZ,
  factura_id          UUID,                  -- Factura o cobro POS que originó la venta
  estado              VARCHAR(20) DEFAULT 'PENDIENTE'
                      CHECK (estado IN ('PENDIENTE','CONCILIADA','SIN_MATCH')),
  created_at          TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE lote_tarjeta_transacciones ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON lote_tarjeta_transacciones FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE INDEX idx_lote_tx_lote_estado    ON lote_tarjeta_transacciones(lote_id, estado);
CREATE INDEX idx_lote_tx_voucher        ON lote_tarjeta_transacciones(numero_voucher);
CREATE INDEX idx_lote_tx_factura        ON lote_tarjeta_transacciones(factura_id);
```

---

## RPCs Ampliadas

```sql
-- Parsea el contenido CSV del banco adquirente y crea las transacciones del lote.
-- Cada banco tiene su propio parser (ver sección Parsers por Banco).
-- Retorna resumen de importación.
SELECT import_card_settlement_csv(
  p_lote_id     => 'uuid',
  p_csv_content => '...contenido csv...',
  p_banco       => 'PICHINCHA'
);
-- Retorna: { importadas: INT, rechazadas: INT, errores: TEXT[] }

-- Auto-conciliación por número de voucher:
-- Para cada transacción PENDIENTE del lote, busca en cobros_caja_rec / sesion_cobro_pagos
-- la factura o cobro POS que coincida por numero_voucher.
-- Al finalizar, genera el asiento de liquidación del lote:
--   DB Banco (neto_a_acreditar) + DB Comisión + DB IVA Comisión → CR Tarjetas por Cobrar
SELECT auto_reconcile_card_batch(p_lote_id => 'uuid');
-- Retorna: { conciliadas: INT, sin_match: INT, asiento_id: UUID }

-- Resumen de conciliación por banco y período.
SELECT get_card_reconciliation_summary(
  p_empresa_id  => 'uuid',
  p_fecha_desde => '2026-01-01'::date,
  p_fecha_hasta => '2026-01-31'::date
);
-- Retorna por banco: {
--   banco_adquirente, lotes_count, total_bruto, total_comision,
--   total_iva_comision, total_neto, lotes_conciliados, lotes_pendientes
-- }
```

---

## Parsers por Banco Ecuador

Cada banco adquirente envía su archivo de liquidación en un formato distinto. La Edge Function `import-card-settlement` implementa un parser por banco:

| Banco | Separador | Formato | Columnas clave |
|---|---|---|---|
| Banco Pichincha | `;` | CSV con cabecera | `Fecha;Hora;Terminal;Voucher;Tarjeta;Monto;Tipo` |
| Banco Pacífico | `,` | CSV con cabecera | `date,time,terminal,auth_code,card,amount,type` |
| Banco Guayaquil | fixed-width | TXT 80 chars/fila | posiciones fijas por campo |
| Produbanco | `\|` | CSV con cabecera | `FECHA\|HORA\|TERMINAL\|VOUCHER\|TARJETA\|MONTO\|TIPO` |
| Bolivariano | `,` | CSV sin cabecera | orden: fecha,lote,voucher,tarjeta,monto,tipo |

El campo `p_banco` de `import_card_settlement_csv` selecciona el parser correspondiente. Formato `'GENERICO'` usa coma como separador e intenta detectar columnas por cabecera.

---

## IVA de Comisiones — Tratamiento Tributario Ecuador

La comisión cobrada por el banco adquirente lleva IVA 15% (Ecuador). Este IVA puede tratarse de dos formas según el tipo de contribuyente:

| Tipo de empresa | Tratamiento del IVA comisión |
|---|---|
| Contribuyente normal | Se registra como gasto (IVA no recuperable) |
| Contribuyente especial | Se recupera como crédito tributario (IVA en compras) |

La configuración por empresa en `parametros_sri` determina si `iva_comision` va a **Gasto IVA** o a **Crédito Tributario IVA**.

### Asiento de Liquidación de Lote

```
-- Escenario: empresa contribuyente especial (IVA recuperable)

DEBE:  1.1.2.x  Banco / cuenta bancaria              neto_a_acreditar
DEBE:  6.x.x.x  Gasto comisión bancaria               comision_monto
DEBE:  1.1.3.x  IVA Crédito Tributario (compras)      iva_comision
HABER: 1.1.3.x  Tarjetas por Cobrar (cta. transitoria) total_bruto

-- Escenario: empresa contribuyente normal (IVA como gasto)

DEBE:  1.1.2.x  Banco / cuenta bancaria              neto_a_acreditar
DEBE:  6.x.x.x  Gasto comisión bancaria (con IVA)     comision_monto + iva_comision
HABER: 1.1.3.x  Tarjetas por Cobrar (cta. transitoria) total_bruto
```
