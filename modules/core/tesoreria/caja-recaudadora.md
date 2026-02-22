# Caja Recaudadora / Punto de Cobro (Tesorería)

*Spec derivada del módulo `l10n_ec_collection_box` (Odoo 19.1 Ecuador — producción en csolish/tecnoh)*

---

## Descripción

Sistema de sesiones de cobro para empresas que tienen múltiples puntos de recaudación (cajeros, ventanillas, agencias). Similar a POS pero para cobro de facturas ya emitidas (servicios, cuotas, etc.) en lugar de ventas nuevas. Soporta múltiples métodos de pago, depósitos a banco, y cuadre de caja al cierre.

---

## Casos de Uso

| Caso | Descripción |
|---|---|
| ISP / Cable | Cajero cobra cuotas de contratos de internet/cable |
| Cooperativa | Ventanilla recauda pagos de socios |
| Empresa servicios | Agencia cobra facturas pendientes de clientes |
| Cobro mixto | Efectivo + tarjeta + cheque en un mismo cobro |

---

## Diferencias vs POS

| Característica | POS | Caja Recaudadora |
|---|---|---|
| Genera nueva venta | Sí | No |
| Cobra facturas existentes | No | Sí |
| Necesita inventario | Sí | No |
| Requiere impresora fiscal | Sí (recomendado) | No |
| Retenciones en cobro | No | Sí |
| Anticipos en cobro | No | Sí |

---

## Modelo de Datos

### Tabla: `config_punto_cobro`

```sql
CREATE TABLE config_punto_cobro (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id          UUID NOT NULL REFERENCES empresas(id),
  nombre              TEXT NOT NULL,
  diario_efectivo_id  UUID REFERENCES diarios_contables(id),
  activo              BOOLEAN DEFAULT TRUE,
  -- Límites
  monto_max_cobro     NUMERIC(15,2),
  -- Usuarios autorizados a abrir sesión
  usuario_ids         UUID[]
);
```

### Tabla: `sesiones_cobro`

```sql
CREATE TABLE sesiones_cobro (
  id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id                  UUID NOT NULL REFERENCES empresas(id),
  nombre                      TEXT NOT NULL,
  config_id                   UUID NOT NULL REFERENCES config_punto_cobro(id),
  cajero_id                   UUID NOT NULL REFERENCES usuarios(id),
  -- Fechas
  apertura_en                 TIMESTAMPTZ,
  cierre_en                   TIMESTAMPTZ,
  pausada_en                  TIMESTAMPTZ,
  tiempo_pausado_min          NUMERIC(8,2) DEFAULT 0,
  -- Estado
  estado                      TEXT NOT NULL DEFAULT 'apertura'
                              CHECK (estado IN ('apertura','abierta','pausada',
                                'cierre_control','cerrada')),
  -- Efectivo
  saldo_inicial               NUMERIC(15,2) DEFAULT 0,
  saldo_final_real            NUMERIC(15,2),    -- contado físicamente
  saldo_final_teorico         NUMERIC(15,2),    -- calculado por sistema
  diferencia_caja             NUMERIC(15,2),    -- real - teórico
  -- Totales de la sesión
  total_cobrado               NUMERIC(15,2) DEFAULT 0,
  total_efectivo              NUMERIC(15,2) DEFAULT 0,
  total_tarjeta               NUMERIC(15,2) DEFAULT 0,
  total_transferencia         NUMERIC(15,2) DEFAULT 0,
  total_cheque                NUMERIC(15,2) DEFAULT 0,
  total_anticipos_aplicados   NUMERIC(15,2) DEFAULT 0,
  total_depositos             NUMERIC(15,2) DEFAULT 0
);

ALTER TABLE sesiones_cobro ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON sesiones_cobro FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));
```

### Tabla: `sesion_cobro_pagos` (cobros realizados en la sesión)

```sql
CREATE TABLE sesion_cobro_pagos (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id          UUID NOT NULL REFERENCES empresas(id),
  sesion_id           UUID NOT NULL REFERENCES sesiones_cobro(id) ON DELETE CASCADE,
  pago_id             UUID REFERENCES pagos(id),
  contacto_id         UUID NOT NULL REFERENCES contactos(id),
  fecha               TIMESTAMPTZ DEFAULT now(),
  monto_total         NUMERIC(15,2) NOT NULL,
  -- Formas de pago
  efectivo            NUMERIC(15,2) DEFAULT 0,
  tarjeta             NUMERIC(15,2) DEFAULT 0,
  transferencia       NUMERIC(15,2) DEFAULT 0,
  cheque              NUMERIC(15,2) DEFAULT 0,
  anticipo_aplicado   NUMERIC(15,2) DEFAULT 0,
  -- Facturas cobradas
  factura_ids         UUID[]
);
```

### Tabla: `sesion_cobro_depositos`

```sql
CREATE TABLE sesion_cobro_depositos (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sesion_id       UUID NOT NULL REFERENCES sesiones_cobro(id),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  fecha           DATE NOT NULL DEFAULT CURRENT_DATE,
  banco_id        UUID REFERENCES catalogo_bancos(id),
  monto           NUMERIC(15,2) NOT NULL,
  referencia      TEXT,
  asiento_id      UUID REFERENCES asientos_contables(id)
);
```

### Tabla: `sesion_cobro_pausas` (historial de pausas)

```sql
CREATE TABLE sesion_cobro_pausas (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sesion_id       UUID NOT NULL REFERENCES sesiones_cobro(id) ON DELETE CASCADE,
  pausada_en      TIMESTAMPTZ NOT NULL,
  reanudada_en    TIMESTAMPTZ,
  duracion_min    NUMERIC(8,2)
);
```

---

## Flujo de Sesión

```
1. APERTURA — cajero selecciona punto de cobro, ingresa saldo inicial efectivo
2. ABIERTA — cobra facturas con múltiples métodos de pago
   - Busca cliente → carga facturas pendientes → registra cobro
   - Puede aplicar anticipos disponibles del cliente
   - Puede registrar retenciones recibidas
3. PAUSA — suspende sesión (almuerzo, turno)
4. CIERRE CONTROL — cajero cuenta efectivo físico, compara vs teórico
5. CERRADA — registro de diferencia, depósito bancario
```

---

## Funciones RPC

```typescript
// Abrir sesión
abrir_sesion(params: {
  config_id: UUID
  saldo_inicial: number
}): { sesion_id: UUID, nombre: string }

// Registrar cobro en sesión
registrar_cobro_sesion(params: {
  sesion_id: UUID
  contacto_id: UUID
  facturas: [{ factura_id: UUID, monto_aplicado: number }]
  formas_pago: [{
    tipo: 'efectivo' | 'tarjeta' | 'transferencia' | 'cheque'
    monto: number
    referencia?: string
    marca_tarjeta_id?: UUID
  }]
  anticipo_id?: UUID
  anticipo_monto?: number
}): { cobro_id: UUID, pago_id: UUID }

// Pausar sesión
pausar_sesion(sesion_id: UUID): { estado: 'pausada' }

// Reanudar sesión
reanudar_sesion(sesion_id: UUID): { estado: 'abierta' }

// Registrar depósito a banco
registrar_deposito(params: {
  sesion_id: UUID
  banco_id: UUID
  monto: number
  referencia?: string
}): { deposito_id: UUID, asiento_id: UUID }

// Cerrar sesión
cerrar_sesion(params: {
  sesion_id: UUID
  saldo_final_real: number
}): {
  sesion_id: UUID
  diferencia: number
  total_cobrado: number
  reporte_url: string
}

// Resumen de sesión activa
get_sesion_activa(config_id: UUID): {
  sesion_id: UUID
  cajero: string
  apertura: string
  total_cobrado: number
  cobros_count: number
}
```

---

## Validaciones de Negocio

- Solo puede haber una sesión abierta por punto de cobro a la vez
- El cajero debe estar autorizado en `config_punto_cobro.usuario_ids`
- No se puede cobrar más del saldo de la factura
- Al cerrar, se registra automáticamente la diferencia de caja en contabilidad
- No se puede reabrir una sesión cerrada

---

## Pantallas Flutter

### Dashboard de Puntos de Cobro
- Lista de configuraciones con estado de sesión (abierta/cerrada)
- Total cobrado en el día, diferencia de caja promedio

### Pantalla de Sesión Activa

```
┌────────────────────────────────────────────────────────┐
│ CAJA NORTE - Cajero: Juan Pérez           SESION-0042 │
│ Apertura: 08:30  │  Total cobrado: $2,450.00           │
├────────────────────────────────────────────────────────┤
│ COBRO DE CLIENTE                                       │
│ Cliente: [selector contacto]           [Cargar Deudas]│
│                                                        │
│ FACTURAS PENDIENTES                                    │
│ ┌──────┬──────────┬─────────┬──────────┬─────────────┐ │
│ │ #    │ Fecha    │ Total   │ Saldo    │ Cobrar      │ │
│ ├──────┼──────────┼─────────┼──────────┼─────────────┤ │
│ │FAC-1 │ 01/01/26 │ $150.00 │ $150.00  │  $150.00    │ │
│ │FAC-2 │ 15/01/26 │ $200.00 │ $200.00  │  $100.00    │ │
│ └──────┴──────────┴─────────┴──────────┴─────────────┘ │
├────────────────────────────────────────────────────────┤
│ FORMA DE PAGO                                          │
│ Efectivo: [$150]  Tarjeta: [$100]  Total: $250         │
├────────────────────────────────────────────────────────┤
│ [Registrar Cobro]  [Pausar Sesión]  [Cerrar Caja]     │
└────────────────────────────────────────────────────────┘
```

### Cierre de Caja
- Ingreso del efectivo contado físicamente
- Comparación vs teórico con diferencia destacada
- Registro de depósito bancario
- Impresión del reporte Z de la sesión

---

## Modelo de Datos Completo (Ampliado)

Las tablas siguientes complementan el modelo anterior con control de sesiones, registro de cobros por punto de recaudación e integración con el módulo POS vía Module Service Bus.

### Tabla: `cajas_recaudadoras`

```sql
CREATE TABLE cajas_recaudadoras (
  id                        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id                UUID NOT NULL REFERENCES empresas(id),
  establecimiento_id        UUID NOT NULL REFERENCES establecimientos(id),
  nombre                    VARCHAR(100) NOT NULL,       -- "Caja Recaudadora Quito #1"
  responsable_id            UUID REFERENCES auth.users(id),
  punto_emision_id          UUID REFERENCES puntos_emision(id), -- Vinculada a punto de emisión SRI
  cuenta_bancaria_deposito  UUID REFERENCES cuentas_bancarias(id), -- Banco donde se deposita
  monto_inicial             DECIMAL(14,2) DEFAULT 0,    -- Fondo cambio
  activa                    BOOLEAN DEFAULT true,
  created_at                TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(empresa_id, nombre)
);

ALTER TABLE cajas_recaudadoras ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON cajas_recaudadoras FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));
```

### Tabla: `sesiones_caja_rec`

```sql
CREATE TABLE sesiones_caja_rec (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  caja_id               UUID NOT NULL REFERENCES cajas_recaudadoras(id),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  cajero_id             UUID NOT NULL REFERENCES auth.users(id),
  fecha_apertura        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  fecha_cierre          TIMESTAMPTZ,
  monto_apertura        DECIMAL(14,2) NOT NULL,  -- Efectivo inicial (fondo cambio)
  -- Totales por método de cobro (actualizados en cada register_collection)
  total_efectivo        DECIMAL(14,2) DEFAULT 0,
  total_tarjeta         DECIMAL(14,2) DEFAULT 0,
  total_transferencia   DECIMAL(14,2) DEFAULT 0,
  total_cheque          DECIMAL(14,2) DEFAULT 0,
  total_nc              DECIMAL(14,2) DEFAULT 0, -- Notas de crédito aplicadas
  total_anticipos       DECIMAL(14,2) DEFAULT 0,
  total_cobrado         DECIMAL(14,2) DEFAULT 0, -- Suma de todos los métodos
  -- Cuadre al cierre
  efectivo_contado      DECIMAL(14,2),           -- Llenado manualmente al cierre
  diferencia_caja       DECIMAL(14,2) GENERATED ALWAYS AS (
    COALESCE(efectivo_contado, 0) - (monto_apertura + total_efectivo)
  ) STORED,
  deposito_id           UUID,                    -- Referencia al depósito bancario
  estado                VARCHAR(15) DEFAULT 'ABIERTA'
                        CHECK (estado IN ('ABIERTA','CERRADA','CUADRADA')),
  created_at            TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE sesiones_caja_rec ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON sesiones_caja_rec FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE INDEX idx_sesiones_caja_rec_caja   ON sesiones_caja_rec(caja_id, estado);
CREATE INDEX idx_sesiones_caja_rec_cajero ON sesiones_caja_rec(cajero_id);
```

### Tabla: `cobros_caja_rec`

```sql
CREATE TABLE cobros_caja_rec (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sesion_id       UUID NOT NULL REFERENCES sesiones_caja_rec(id),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  contacto_id     UUID REFERENCES contactos(id),
  factura_ids     JSONB DEFAULT '[]',     -- Array de { factura_id, monto_aplicado }
  monto_total     DECIMAL(14,2) NOT NULL,
  efectivo        DECIMAL(14,2) DEFAULT 0,
  tarjeta         DECIMAL(14,2) DEFAULT 0,
  transferencia   DECIMAL(14,2) DEFAULT 0,
  cheque          DECIMAL(14,2) DEFAULT 0,
  nc              DECIMAL(14,2) DEFAULT 0,
  vuelto          DECIMAL(14,2) DEFAULT 0,
  asiento_id      UUID,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE cobros_caja_rec ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON cobros_caja_rec FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE INDEX idx_cobros_caja_rec_sesion   ON cobros_caja_rec(sesion_id);
CREATE INDEX idx_cobros_caja_rec_contacto ON cobros_caja_rec(contacto_id);
```

---

## RPCs Ampliadas

```sql
-- Abre sesión de caja recaudadora.
-- Verifica que no haya sesión ABIERTA previa para la misma caja.
SELECT open_collection_session(
  p_caja_id        => 'uuid',
  p_monto_apertura => 50.00
);
-- Retorna: { sesion_id: UUID, caja_nombre: TEXT, cajero: TEXT, fecha_apertura: TIMESTAMPTZ }

-- Registra un cobro en la sesión activa.
-- Actualiza los totales de la sesión, genera asiento contable,
-- y marca las facturas incluidas como pagadas (total o parcialmente).
SELECT register_collection(
  p_sesion_id      => 'uuid',
  p_contacto_id    => 'uuid',
  p_facturas       => '[{"factura_id":"uuid","monto_aplicado":150.00}]'::jsonb,
  p_metodos_pago   => '[{"tipo":"efectivo","monto":100.00},{"tipo":"tarjeta","monto":50.00}]'::jsonb
);
-- Retorna: { cobro_id: UUID, asiento_id: UUID, vuelto: DECIMAL }

-- Cierra la sesión con cuadre de efectivo.
-- Si efectivo_contado != (monto_apertura + total_efectivo), genera asiento de diferencia.
-- Crea solicitud de depósito bancario por el total de efectivo.
SELECT close_collection_session(
  p_sesion_id        => 'uuid',
  p_efectivo_contado => 320.00
);
-- Retorna: { diferencia_caja: DECIMAL, total_cobrado: DECIMAL, deposito_pendiente: DECIMAL }

-- Resumen de sesión activa o cerrada: totales por método, número de cobros, diferencia.
SELECT get_session_summary(p_sesion_id => 'uuid');
-- Retorna: {
--   sesion_id, caja_nombre, cajero, fecha_apertura, fecha_cierre,
--   total_cobrado, total_efectivo, total_tarjeta, total_transferencia,
--   total_cheque, total_nc, total_anticipos, efectivo_contado,
--   diferencia_caja, cobros_count, estado
-- }
```

---

## Integración con POS (Module Service Bus)

Cuando el módulo POS registra un cobro en un terminal vinculado a un `punto_emision_id` que también corresponde a una `caja_recaudadora` activa, el flujo es:

```
POS registra cobro
  → llama module_bus.tesoreria.register_pos_collection(p_punto_emision_id, p_cobro_data)
    → verifica si existe sesión ABIERTA en cajas_recaudadoras para ese punto_emision_id
      → SI existe: redirige a register_collection() en la sesión activa
                   (el cobro POS queda registrado dentro de la sesión de caja recaudadora)
      → NO existe: POS maneja el cobro directamente en su propia sesión POS
```

Esta integración permite que una empresa ISP, por ejemplo, use el módulo POS para cobros físicos en agencia y simultáneamente tenga abierta una sesión de Caja Recaudadora — todos los cobros quedan consolidados en un solo cuadre de cierre.

---

## Asientos Contables Generados

### Al registrar cobro mixto (register_collection)

```
DEBE:  1.1.2.x  Banco / Efectivo en Caja              efectivo
DEBE:  1.1.2.x  Tarjetas por Cobrar                   tarjeta
DEBE:  1.1.2.x  Transferencias por Acreditar           transferencia
DEBE:  1.1.3.x  Cheques por Depositar                  cheque
DEBE:  2.x.x.x  NC Clientes (reducción pasivo)         nc
HABER: 1.1.3.x  Cuentas por Cobrar (facturas cubiertas) monto_total
```

### Al cerrar sesión con diferencia

```
-- Si hay FALTANTE (efectivo_contado < saldo teórico):
DEBE:  6.x.x.x  Pérdida / Faltante de Caja            |diferencia_caja|
HABER: 1.1.2.x  Efectivo en Caja                       |diferencia_caja|

-- Si hay SOBRANTE:
DEBE:  1.1.2.x  Efectivo en Caja                       |diferencia_caja|
HABER: 4.x.x.x  Sobrante de Caja                       |diferencia_caja|
```
