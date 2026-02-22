# Módulo de Tesorería

Gestión de cuentas bancarias, transferencias, conciliación bancaria, CxC/CxP, pagos online y flujo de caja. Centraliza todos los movimientos de dinero de la empresa.

> Sub-módulos detallados: [CxC/CxP](cxc-cxp.md) · [Anticipos](anticipos.md) · [Caja Chica](caja-chica.md) · [Cobro Multifactura](cobro-multifactura.md) · [Conciliación Tarjetas](conciliacion-tarjetas.md) · [Cheques](cheques.md) · [Caja Recaudadora](caja-recaudadora.md)

---

## Navegación

```
tesoreria/
  ├── cuentas-bancarias/
  │     ├── listado/            # CRUD cuentas bancarias de la empresa
  │     └── saldos/             # Saldo contable vs saldo bancario por cuenta
  ├── transferencias/
  │     ├── enviadas/           # Transferencias a proveedores (pago de OC/CxP)
  │     ├── recibidas/          # Transferencias de clientes (abono a CxC)
  │     └── internas/           # Entre cuentas propias de la empresa
  ├── cheques/                  # Ciclo de vida de cheques (ver cheques.md)
  │     ├── emitidos/
  │     ├── recibidos/
  │     ├── devueltos/
  │     └── pendientes/
  ├── cxc-cxp/                  # CxC y CxP unificadas (ver cxc-cxp.md)
  │     ├── cuentas-cobrar/     # Facturas vencidas/por vencer por cliente
  │     ├── cuentas-pagar/      # Facturas vencidas/por vencer por proveedor
  │     ├── cobros/             # Registro de cobros (mixto: efectivo/cheque/transf/tarjeta)
  │     └── pagos/              # Registro de pagos a proveedores
  ├── caja-chica/               # Fondos fijos y fondos a rendir (ver caja-chica.md)
  ├── caja-recaudadora/         # Sesiones de cobro por punto (ver caja-recaudadora.md)
  ├── pagos-online/             # Pagos con pasarela (Kushki/Paymentez/PayPhone)
  ├── conciliacion/
  │     ├── bancaria/           # Conciliación estado de cuenta vs sistema
  │     └── tarjetas/           # Importación y cruce de pagos tarjeta (ver conciliacion-tarjetas.md)
  └── reportes/
        ├── flujo-caja/         # Proyección de flujo por período
        ├── saldos-banco/       # Saldos por cuenta bancaria
        ├── aging-cobros/       # Cartera vencida por cliente (0-30, 31-60, 61-90, 90+ días)
        ├── aging-pagos/        # Vencimientos por proveedor
        └── cheques-pendientes/ # Cheques por cobrar/pagar
```

---

## Modelo de Datos

### Cuentas Bancarias

```sql
CREATE TABLE cuentas_bancarias (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  banco_id              UUID NOT NULL REFERENCES catalogo_bancos(id),
  numero_cuenta         VARCHAR(30) NOT NULL,
  tipo                  VARCHAR(20) NOT NULL DEFAULT 'CORRIENTE',
    -- CORRIENTE, AHORROS, INVERSION, OTRO
  moneda_id             VARCHAR(3) DEFAULT 'USD' REFERENCES monedas(id),
  -- Contabilidad
  cuenta_contable_id    UUID REFERENCES cuentas_contables(id),
  -- Saldos (se actualizan con cada movimiento bancario)
  saldo_contable        DECIMAL(14,2) DEFAULT 0,           -- Según sistema PILAR
  saldo_banco           DECIMAL(14,2) DEFAULT 0,           -- Último importado/conciliado
  fecha_ultimo_estado   DATE,                              -- Fecha del último estado de cuenta
  -- Configuración
  habilitada_pagos      BOOLEAN DEFAULT true,              -- Puede usarse para pagar
  habilitada_cobros     BOOLEAN DEFAULT true,              -- Puede usarse para cobrar
  activa                BOOLEAN DEFAULT true,
  created_at            TIMESTAMPTZ DEFAULT now(),
  UNIQUE(empresa_id, numero_cuenta)
);

-- Movimientos bancarios (importados del estado de cuenta o generados por el sistema)
CREATE TABLE movimientos_bancarios (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  cuenta_bancaria_id    UUID NOT NULL REFERENCES cuentas_bancarias(id),
  fecha                 DATE NOT NULL,
  tipo                  VARCHAR(15) NOT NULL,              -- CREDITO, DEBITO
  monto                 DECIMAL(14,2) NOT NULL,
  descripcion           VARCHAR(500),
  referencia            VARCHAR(100),                      -- Número de operación del banco
  -- Conciliación
  conciliado            BOOLEAN DEFAULT false,
  conciliacion_id       UUID REFERENCES conciliaciones_bancarias(id),
  -- Vinculación al documento contable
  documento_tipo        VARCHAR(30),                       -- COBRO, PAGO, TRANSFERENCIA, CHEQUE
  documento_id          UUID,
  -- Saldo acumulado (calculado al importar)
  saldo_acumulado       DECIMAL(14,2),
  created_at            TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_mov_bancario_cuenta ON movimientos_bancarios(cuenta_bancaria_id, fecha DESC);
CREATE INDEX idx_mov_bancario_conciliado ON movimientos_bancarios(conciliacion_id) WHERE conciliado = false;
```

### Transferencias Bancarias

```sql
-- Transferencias de dinero (entre cuentas propias o hacia/desde terceros)
CREATE TABLE transferencias_bancarias (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  numero                VARCHAR(30) NOT NULL,
  tipo                  VARCHAR(20) NOT NULL,
    -- INTERNA (entre cuentas propias)
    -- PAGO_PROVEEDOR (hacia un proveedor)
    -- COBRO_CLIENTE (desde un cliente)
  -- Origen
  cuenta_origen_id      UUID REFERENCES cuentas_bancarias(id),   -- NULL si es cobro externo
  -- Destino
  cuenta_destino_id     UUID REFERENCES cuentas_bancarias(id),   -- NULL si es pago externo
  contacto_id           UUID REFERENCES contactos(id),           -- Proveedor o cliente
  banco_destino_id      UUID REFERENCES catalogo_bancos(id),
  numero_cuenta_destino VARCHAR(30),
  -- Monto
  monto                 DECIMAL(14,2) NOT NULL,
  comision              DECIMAL(14,2) DEFAULT 0,                 -- Comisión bancaria
  monto_neto            DECIMAL(14,2),                           -- monto - comision
  -- Estado
  estado                VARCHAR(20) DEFAULT 'PENDIENTE',
    -- PENDIENTE, PROCESADA, CONCILIADA, ANULADA
  fecha_transferencia   DATE NOT NULL DEFAULT CURRENT_DATE,
  fecha_efectiva        DATE,                                     -- Cuando acreditó el banco
  referencia_banco      VARCHAR(100),                            -- Número de operación
  comprobante_url       TEXT,                                    -- PDF/imagen comprobante
  -- Vinculación con CxC/CxP
  cobros_ids            UUID[],                                  -- Cobros que cubre (CxC)
  pagos_ids             UUID[],                                  -- Pagos que cubre (CxP)
  -- Asiento contable
  asiento_id            UUID REFERENCES asientos_contables(id),
  notas                 TEXT,
  created_at            TIMESTAMPTZ DEFAULT now(),
  UNIQUE(empresa_id, numero)
);
```

### Conciliación Bancaria

```sql
-- Cabecera de una conciliación mensual por cuenta
CREATE TABLE conciliaciones_bancarias (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  cuenta_bancaria_id    UUID NOT NULL REFERENCES cuentas_bancarias(id),
  periodo               VARCHAR(7) NOT NULL,               -- 'YYYY-MM'
  -- Saldos
  saldo_inicial_banco   DECIMAL(14,2) NOT NULL,            -- Saldo apertura período (banco)
  saldo_final_banco     DECIMAL(14,2) NOT NULL,            -- Saldo cierre período (banco)
  saldo_contable        DECIMAL(14,2) NOT NULL,            -- Saldo sistema al cierre
  diferencia            DECIMAL(14,2) GENERATED ALWAYS AS (saldo_final_banco - saldo_contable) STORED,
  -- Estado
  estado                VARCHAR(20) DEFAULT 'ABIERTA',     -- ABIERTA, CERRADA
  cerrado_por           UUID REFERENCES auth.users(id),
  fecha_cierre          TIMESTAMPTZ,
  -- Importación
  archivo_url           TEXT,                              -- CSV/OFX/PDF importado
  created_at            TIMESTAMPTZ DEFAULT now(),
  UNIQUE(empresa_id, cuenta_bancaria_id, periodo)
);

-- Detalle de la conciliación (movimientos emparejados)
CREATE TABLE conciliacion_movimientos (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conciliacion_id       UUID NOT NULL REFERENCES conciliaciones_bancarias(id) ON DELETE CASCADE,
  movimiento_bancario_id UUID REFERENCES movimientos_bancarios(id),  -- Lado banco
  documento_tipo        VARCHAR(30),                       -- Lado sistema: COBRO, PAGO, CHEQUE
  documento_id          UUID,
  monto_banco           DECIMAL(14,2),
  monto_sistema         DECIMAL(14,2),
  diferencia            DECIMAL(14,2) GENERATED ALWAYS AS (
    COALESCE(monto_banco, 0) - COALESCE(monto_sistema, 0)
  ) STORED,
  tipo_matching         VARCHAR(15) DEFAULT 'MANUAL',      -- AUTO, MANUAL
  estado                VARCHAR(15) DEFAULT 'CONCILIADO'   -- CONCILIADO, PENDIENTE, DIFERENCIA
);
```

### Pagos Online (Kushki / Paymentez)

```sql
-- Configuración de pasarelas por empresa
CREATE TABLE config_pasarelas_pago (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  pasarela              VARCHAR(20) NOT NULL,              -- KUSHKI, PAYMENTEZ, PAYPHONE
  ambiente              VARCHAR(10) DEFAULT 'PRODUCCION',  -- PRUEBAS, PRODUCCION
  -- Credenciales cifradas (AES-256, nunca en texto plano)
  public_key_enc        TEXT NOT NULL,
  private_key_enc       TEXT NOT NULL,
  -- Cuenta bancaria destino para liquidaciones
  cuenta_bancaria_id    UUID REFERENCES cuentas_bancarias(id),
  activa                BOOLEAN DEFAULT true,
  UNIQUE(empresa_id, pasarela)
);

-- Transacciones de pago online
CREATE TABLE pagos_online (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  pasarela              VARCHAR(20) NOT NULL,
  transaction_id        VARCHAR(100) NOT NULL,             -- ID dado por la pasarela
  -- Documento origen
  factura_id            UUID REFERENCES facturas(id),
  contacto_id           UUID REFERENCES contactos(id),
  -- Monto
  monto                 DECIMAL(14,2) NOT NULL,
  comision_pasarela     DECIMAL(14,2) DEFAULT 0,
  monto_neto            DECIMAL(14,2),
  moneda                VARCHAR(3) DEFAULT 'USD',
  -- Estado
  estado                VARCHAR(20) NOT NULL DEFAULT 'INICIADO',
    -- INICIADO, APROBADO, RECHAZADO, REEMBOLSADO, ANULADO
  codigo_respuesta      VARCHAR(10),
  mensaje_respuesta     TEXT,
  -- Tarjeta/método
  metodo_pago           VARCHAR(30),                       -- TARJETA_CREDITO, TARJETA_DEBITO, PSE
  ultimos_4_digitos     VARCHAR(4),
  marca_tarjeta         VARCHAR(20),                       -- VISA, MASTERCARD, AMEX
  -- Fechas
  fecha_transaccion     TIMESTAMPTZ DEFAULT now(),
  fecha_aprobacion      TIMESTAMPTZ,
  -- Cobro vinculado (generado al aprobar)
  cobro_id              UUID REFERENCES cobros(id),
  created_at            TIMESTAMPTZ DEFAULT now(),
  UNIQUE(empresa_id, pasarela, transaction_id)
);

CREATE INDEX idx_pagos_online_factura ON pagos_online(factura_id);
CREATE INDEX idx_pagos_online_estado ON pagos_online(empresa_id, estado);
```

---

## Funciones RPC Clave

```sql
-- Registrar un cobro (aplicar dinero recibido a CxC)
-- Ver cxc-cxp.md para la versión completa con forma de pago mixta
CREATE OR REPLACE FUNCTION register_payment_received(
  p_empresa_id      UUID,
  p_contacto_id     UUID,
  p_fecha           DATE,
  p_monto           DECIMAL,
  p_forma_pago      VARCHAR,       -- EFECTIVO, CHEQUE, TRANSFERENCIA, TARJETA
  p_cuenta_id       UUID,          -- Cuenta bancaria destino
  p_referencia      VARCHAR DEFAULT NULL,
  p_cxc_ids         UUID[] DEFAULT ARRAY[]::UUID[]  -- CxC a aplicar
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_cobro_id UUID;
BEGIN
  -- Crear cabecera del cobro
  INSERT INTO cobros (
    empresa_id, contacto_id, fecha, monto_total,
    forma_pago, cuenta_bancaria_id, referencia
  ) VALUES (
    p_empresa_id, p_contacto_id, p_fecha, p_monto,
    p_forma_pago, p_cuenta_id, p_referencia
  ) RETURNING id INTO v_cobro_id;

  -- Aplicar a CxC (FIFO si no se especifican)
  IF array_length(p_cxc_ids, 1) > 0 THEN
    PERFORM apply_payment_to_cxc(v_cobro_id, p_cxc_ids, p_monto);
  ELSE
    PERFORM apply_payment_to_cxc_fifo(v_cobro_id, p_contacto_id, p_monto);
  END IF;

  -- Crear asiento contable
  PERFORM module_bus.contabilidad_create_journal_entry(
    p_empresa_id, 'COBRO', v_cobro_id
  );

  -- Actualizar saldo cuenta bancaria
  UPDATE cuentas_bancarias
  SET saldo_contable = saldo_contable + p_monto
  WHERE id = p_cuenta_id;

  RETURN v_cobro_id;
END;
$$;

-- Crear transferencia bancaria interna
CREATE OR REPLACE FUNCTION create_bank_transfer(
  p_empresa_id          UUID,
  p_cuenta_origen_id    UUID,
  p_cuenta_destino_id   UUID,
  p_monto               DECIMAL,
  p_fecha               DATE DEFAULT CURRENT_DATE,
  p_notas               VARCHAR DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_transfer_id UUID;
  v_numero VARCHAR;
BEGIN
  v_numero := 'TRF-' || to_char(now(), 'YYYYMMDD') || '-' ||
    lpad(nextval('transferencia_seq')::text, 4, '0');

  INSERT INTO transferencias_bancarias (
    empresa_id, numero, tipo, cuenta_origen_id, cuenta_destino_id,
    monto, monto_neto, fecha_transferencia, notas
  ) VALUES (
    p_empresa_id, v_numero, 'INTERNA', p_cuenta_origen_id, p_cuenta_destino_id,
    p_monto, p_monto, p_fecha, p_notas
  ) RETURNING id INTO v_transfer_id;

  -- Actualizar saldos contables
  UPDATE cuentas_bancarias SET saldo_contable = saldo_contable - p_monto
  WHERE id = p_cuenta_origen_id;
  UPDATE cuentas_bancarias SET saldo_contable = saldo_contable + p_monto
  WHERE id = p_cuenta_destino_id;

  -- Asiento contable: Db cuenta destino / Cr cuenta origen
  PERFORM module_bus.contabilidad_create_journal_entry(p_empresa_id, 'TRANSFERENCIA', v_transfer_id);

  RETURN v_transfer_id;
END;
$$;

-- Proyección de flujo de caja (próximos N días)
CREATE OR REPLACE FUNCTION get_cash_flow_projection(
  p_empresa_id      UUID,
  p_dias            INTEGER DEFAULT 30
) RETURNS TABLE (
  fecha DATE, tipo VARCHAR, descripcion TEXT,
  ingreso DECIMAL, egreso DECIMAL, saldo_proyectado DECIMAL
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_saldo_actual DECIMAL;
BEGIN
  -- Saldo actual en todas las cuentas bancarias activas
  SELECT COALESCE(SUM(saldo_contable), 0) INTO v_saldo_actual
  FROM cuentas_bancarias WHERE empresa_id = p_empresa_id AND activa = true;

  RETURN QUERY
  WITH flujos AS (
    -- CxC por vencer
    SELECT fecha_vencimiento as fecha, 'COBRO_ESPERADO' as tipo,
      'CxC - ' || c.nombre as descripcion,
      saldo_pendiente as ingreso, 0::DECIMAL as egreso
    FROM cuentas_por_cobrar cxc
    JOIN contactos c ON c.id = cxc.contacto_id
    WHERE cxc.empresa_id = p_empresa_id AND cxc.estado = 'PENDIENTE'
      AND fecha_vencimiento BETWEEN CURRENT_DATE AND CURRENT_DATE + p_dias

    UNION ALL

    -- CxP por vencer
    SELECT fecha_vencimiento, 'PAGO_ESPERADO',
      'CxP - ' || c.nombre,
      0, saldo_pendiente
    FROM cuentas_por_pagar cxp
    JOIN contactos c ON c.id = cxp.contacto_id
    WHERE cxp.empresa_id = p_empresa_id AND cxp.estado = 'PENDIENTE'
      AND fecha_vencimiento BETWEEN CURRENT_DATE AND CURRENT_DATE + p_dias

    UNION ALL

    -- Cheques por cobrar
    SELECT fecha_vencimiento, 'CHEQUE_COBRAR',
      'Cheque - ' || c.nombre,
      monto, 0
    FROM cheques ch
    JOIN contactos c ON c.id = ch.contacto_id
    WHERE ch.empresa_id = p_empresa_id AND ch.tipo = 'RECIBIDO'
      AND ch.estado IN ('RECIBIDO', 'DEPOSITADO')
      AND fecha_vencimiento BETWEEN CURRENT_DATE AND CURRENT_DATE + p_dias
  )
  SELECT f.fecha, f.tipo, f.descripcion, f.ingreso, f.egreso,
    v_saldo_actual + SUM(f.ingreso - f.egreso) OVER (ORDER BY f.fecha)
  FROM flujos f
  ORDER BY f.fecha;
END;
$$;

-- Conciliar movimiento bancario con documento del sistema
CREATE OR REPLACE FUNCTION reconcile_bank_movement(
  p_conciliacion_id         UUID,
  p_movimiento_bancario_id  UUID,
  p_documento_tipo          VARCHAR,
  p_documento_id            UUID,
  p_tipo_matching           VARCHAR DEFAULT 'MANUAL'
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_monto_banco DECIMAL;
  v_monto_sistema DECIMAL;
BEGIN
  SELECT monto INTO v_monto_banco FROM movimientos_bancarios WHERE id = p_movimiento_bancario_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Movimiento bancario % no encontrado', p_movimiento_bancario_id;
  END IF;

  -- Obtener monto del documento sistema
  v_monto_sistema := CASE p_documento_tipo
    WHEN 'COBRO' THEN (SELECT monto_total FROM cobros WHERE id = p_documento_id)
    WHEN 'PAGO' THEN (SELECT monto_total FROM pagos WHERE id = p_documento_id)
    WHEN 'CHEQUE' THEN (SELECT monto FROM cheques WHERE id = p_documento_id)
    WHEN 'TRANSFERENCIA' THEN (SELECT monto FROM transferencias_bancarias WHERE id = p_documento_id)
  END;

  INSERT INTO conciliacion_movimientos (
    conciliacion_id, movimiento_bancario_id, documento_tipo, documento_id,
    monto_banco, monto_sistema, tipo_matching
  ) VALUES (
    p_conciliacion_id, p_movimiento_bancario_id, p_documento_tipo, p_documento_id,
    v_monto_banco, v_monto_sistema, p_tipo_matching
  );

  -- Marcar como conciliado
  UPDATE movimientos_bancarios SET conciliado = true, conciliacion_id = p_conciliacion_id
  WHERE id = p_movimiento_bancario_id;
END;
$$;

-- Procesar pago online (webhook desde Kushki/Paymentez)
CREATE OR REPLACE FUNCTION process_online_payment(
  p_empresa_id      UUID,
  p_pasarela        VARCHAR,
  p_transaction_id  VARCHAR,
  p_estado          VARCHAR,   -- APROBADO, RECHAZADO
  p_monto           DECIMAL,
  p_factura_id      UUID
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_cobro_id UUID;
BEGIN
  UPDATE pagos_online SET
    estado = p_estado,
    fecha_aprobacion = CASE WHEN p_estado = 'APROBADO' THEN now() END
  WHERE empresa_id = p_empresa_id
    AND pasarela = p_pasarela
    AND transaction_id = p_transaction_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transacción % de pasarela % no encontrada', p_transaction_id, p_pasarela;
  END IF;

  IF p_estado = 'APROBADO' THEN
    -- Crear cobro y aplicar a la factura
    INSERT INTO cobros (
      empresa_id, contacto_id, fecha, monto_total, forma_pago
    )
    SELECT p_empresa_id, cliente_id, CURRENT_DATE, p_monto, 'PAGO_ONLINE'
    FROM facturas WHERE id = p_factura_id
    RETURNING id INTO v_cobro_id;

    -- Aplicar cobro a CxC de la factura
    UPDATE cuentas_por_cobrar
    SET saldo_pendiente = saldo_pendiente - p_monto,
        estado = CASE WHEN saldo_pendiente - p_monto <= 0 THEN 'PAGADA' ELSE 'PENDIENTE' END
    WHERE factura_id = p_factura_id;

    -- Asiento contable
    PERFORM module_bus.contabilidad_create_journal_entry(p_empresa_id, 'COBRO', v_cobro_id);
  END IF;

  RETURN v_cobro_id;
END;
$$;
```

---

## Row Level Security

```sql
ALTER TABLE cuentas_bancarias ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON cuentas_bancarias
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

ALTER TABLE movimientos_bancarios ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON movimientos_bancarios
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

ALTER TABLE transferencias_bancarias ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON transferencias_bancarias
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

ALTER TABLE conciliaciones_bancarias ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON conciliaciones_bancarias
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

ALTER TABLE pagos_online ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON pagos_online
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- Índices de soporte
CREATE INDEX idx_cuentas_bancarias_empresa ON cuentas_bancarias(empresa_id) WHERE activa = true;
CREATE INDEX idx_transferencias_empresa ON transferencias_bancarias(empresa_id, fecha_transferencia DESC);
CREATE INDEX idx_pagos_online_empresa ON pagos_online(empresa_id, estado);
```

---

## Integraciones con otros Módulos

| Evento | Origen | Acción en Tesorería |
|--------|--------|---------------------|
| Factura de venta confirmada | Ventas | Crea `cuentas_por_cobrar` (ver cxc-cxp.md) |
| Factura de compra registrada | Compras | Crea `cuentas_por_pagar` |
| Remuneración de nómina aprobada | RRHH | Crea CxP y plan de pago empleados |
| Cuota de préstamo vence | RRHH | Crea CxP de préstamo empleado |
| Pago de pasarela recibido | Portal/Ecommerce | `process_online_payment()` |
| Cobro registrado | Tesorería | Asiento Db Banco / Cr CxC via `module_bus.contabilidad_create_journal_entry` |
| Pago registrado | Tesorería | Asiento Db CxP / Cr Banco |

---

## Sub-módulos

| Sub-módulo | Descripción |
|------------|-------------|
| [CxC / CxP](cxc-cxp.md) | Cuentas por cobrar/pagar, cobros y pagos mixtos, aging reports, planes de pago |
| [Anticipos](anticipos.md) | Anticipos a clientes y proveedores, ciclo de vida, aplicación a facturas |
| [Caja Chica](caja-chica.md) | Fondos fijos y fondos a rendir con aprobación de 2 pasos |
| [Cobro Multifactura](cobro-multifactura.md) | Pago de N facturas en una operación con distribución FIFO |
| [Conciliación Tarjetas](conciliacion-tarjetas.md) | Importación CSV, auto-conciliación, asiento de liquidación |
| [Cheques](cheques.md) | Ciclo de vida cheques Art.1/Art.58, chequeras, crons de vencimiento |
| [Caja Recaudadora](caja-recaudadora.md) | Sesiones de cobro por punto, cuadre de caja, depósitos banco |

---

## Casos de Uso

### Actores

| Actor | Descripcion |
|-------|-------------|
| **Contador** | Gestiona cuentas bancarias, cheques, conciliación, CxC/CxP, pagos |
| **Administrador** | Registra y configura cuentas bancarias |
| **Gerente** | Consulta reportes de flujo de caja y saldos |
| **Sistema** | Procesa pagos online (pasarelas) y registra movimientos automáticos |

### Casos de Uso - Tesorería

| ID | Caso de Uso | Actor | Prioridad |
|----|-------------|-------|-----------|
| T01 | Registrar cuenta bancaria | Contador/Administrador | Alta |
| T02 | Emitir cheque a proveedor | Contador | Alta |
| T03 | Registrar cheque recibido de cliente | Contador | Alta |
| T04 | Marcar cheque como cobrado/depositado | Contador | Alta |
| T05 | Registrar cheque devuelto/protestado | Contador | Alta |
| T06 | Registrar transferencia bancaria enviada | Contador | Alta |
| T07 | Registrar transferencia bancaria recibida | Contador | Alta |
| T08 | Transferencia interna entre cuentas | Contador | Media |
| T09 | Importar estado de cuenta bancario (CSV/OFX) | Contador | Alta |
| T10 | Conciliacion bancaria mensual | Contador | **Critica** |
| T11 | Reporte de flujo de caja | Gerente | Alta |
| T12 | Reporte de cheques pendientes | Contador | Media |
| T13 | Procesar pago online (tarjeta) | Sistema | Alta |
