# Módulo de Ventas

Gestión del ciclo de venta completo: cotizaciones, órdenes de venta, cobros y CxC. Las facturas, notas de crédito y notas de débito se emiten a través del módulo **[Facturación](../facturacion/module.md)** vía Module Service Bus.

> **Módulo Core #5 — Requiere: Facturación (#4)**
>
> Las facturas, notas de crédito y notas de débito se gestionan en el módulo **[Facturación](../facturacion/module.md)**. Ventas consume ese módulo vía Module Service Bus para emitir documentos SRI. El pipeline completo es: Cotización → Orden de Venta → `module_bus.facturacion.create_invoice()` → Factura autorizada SRI.

> Sub-módulos detallados: [Lealtad](lealtad.md) · [Cupones](cupones.md) · [Suscripciones](suscripciones.md) · [Pronto Pago](pronto-pago.md) · [Crédito Clientes](credito-clientes.md) · [Descuentos](descuentos.md) · [Plazos de Pago](plazos-pago.md) · [Ensamblaje](ensamblaje.md) · [Intercompany Ventas](intercompany-ventas.md) · [IA Ventas](ia-ventas.md)

---

## Navegación

```
ventas/
  ├── clientes/
  │     ├── listado/            # SfDataGrid con filtros (tipo, crédito, cartera)
  │     ├── nuevo/              # Formulario contacto (es_cliente=true)
  │     ├── detalle/            # Ficha 360: facturas, CxC, historial, crédito
  │     └── credito/            # Config crédito: límite, días, política bloqueo
  ├── cotizaciones/
  │     ├── listado/
  │     ├── nueva/              # Formulario con líneas + términos + forma de pago
  │     ├── detalle/            # Ver/editar + enviar por email/WhatsApp
  │     └── aprobar/            # Flujo de aprobación → generar OV
  ├── ordenes-venta/
  │     ├── listado/
  │     ├── nueva/
  │     ├── detalle/            # Estado: BORRADOR/CONFIRMADA/DESPACHADA/FACTURADA
  │     └── despacho/           # Generar despacho desde OV
  ├── facturas/                 ← PROXY: muestra facturas con orden_venta_id = este módulo
  │     └── (muestra DataGrid de facturas filtradas por OV, navega a /facturacion/facturas/:id)
  ├── cobros/
  │     ├── nuevo/              # Seleccionar CxC + métodos de pago mixto
  │     ├── masivo/             # Cobro rápido de múltiples facturas
  │     └── cruce/              # Cruzar con retenciones y NC no aplicadas
  ├── cuentas-cobrar/
  │     ├── listado/            # CxC con filtros (vencidas, por vencer, estado)
  │     ├── cuotas/             # Plan de cuotas por factura a crédito
  │     └── estado-cuenta/      # Estado de cuenta por cliente
  ├── garantias/
  │     ├── listado/        # SfDataGrid: producto + tipo + duración + cobertura
  │     ├── nueva/          # Definir garantía de venta (propia/transferida/mixta)
  │     └── detalle/        # Ver/editar términos de garantía al cliente
  └── reportes/
        ├── ventas-periodo/     # Ventas por período, vendedor, producto, categoría
        ├── cartera-vencida/    # Aging: 0-30, 31-60, 61-90, 90+ días
        ├── cxc-vs-cobros/      # Deudas vs cobros por período
        ├── comisiones/         # Comisiones por vendedor
        └── credito-clientes/   # Clientes con crédito, uso, disponible
```

---

## Modelo de Datos

### Cotizaciones

```sql
CREATE TABLE cotizaciones (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  numero                VARCHAR(30) NOT NULL,               -- COT-2026-0001
  contacto_id           UUID NOT NULL REFERENCES contactos(id),
  vendedor_id           UUID REFERENCES auth.users(id),
  -- Fechas
  fecha                 DATE NOT NULL DEFAULT CURRENT_DATE,
  fecha_vencimiento     DATE,                               -- Validez de la cotización
  -- Estado
  estado                VARCHAR(20) DEFAULT 'BORRADOR',
    -- BORRADOR, ENVIADA, APROBADA, RECHAZADA, VENCIDA, CONVERTIDA
  -- Términos
  termino_pago_id       UUID REFERENCES terminos_pago(id),
  notas                 TEXT,
  condiciones           TEXT,                               -- Condiciones comerciales
  -- Totales
  subtotal              DECIMAL(14,2) DEFAULT 0,
  total_descuento       DECIMAL(14,2) DEFAULT 0,
  base_0                DECIMAL(14,2) DEFAULT 0,
  base_gravada          DECIMAL(14,2) DEFAULT 0,
  total_iva             DECIMAL(14,2) DEFAULT 0,
  total                 DECIMAL(14,2) DEFAULT 0,
  -- Conversión
  orden_venta_id        UUID REFERENCES ordenes_venta(id),
  oportunidad_id        UUID,                               -- FK a CRM (si módulo activo)
  created_at            TIMESTAMPTZ DEFAULT now(),
  UNIQUE(empresa_id, numero)
);

CREATE TABLE cotizacion_lineas (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cotizacion_id         UUID NOT NULL REFERENCES cotizaciones(id) ON DELETE CASCADE,
  orden                 INTEGER DEFAULT 0,
  producto_id           UUID REFERENCES productos(id),
  presentacion_id       UUID REFERENCES producto_presentaciones(id),
  descripcion           VARCHAR(300) NOT NULL,
  cantidad              DECIMAL(18,6) NOT NULL,
  precio_unitario       DECIMAL(18,6) NOT NULL,
  descuento_pct         DECIMAL(5,2) DEFAULT 0,
  descuento_monto       DECIMAL(14,2) DEFAULT 0,
  precio_total          DECIMAL(14,2) NOT NULL,
  tarifa_iva_id         UUID REFERENCES catalogo_tarifas_iva(id),
  subtotal_sin_desc     DECIMAL(14,2),                      -- Para descuentos.md
  notas                 TEXT
);
```

### Órdenes de Venta

```sql
CREATE TABLE ordenes_venta (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  establecimiento_id    UUID REFERENCES establecimientos(id),
  numero                VARCHAR(30) NOT NULL,               -- OV-2026-0001
  cotizacion_id         UUID REFERENCES cotizaciones(id),
  contacto_id           UUID NOT NULL REFERENCES contactos(id),
  vendedor_id           UUID REFERENCES auth.users(id),
  -- Fechas
  fecha                 DATE NOT NULL DEFAULT CURRENT_DATE,
  fecha_entrega_est     DATE,
  -- Estado
  estado                VARCHAR(20) DEFAULT 'BORRADOR',
    -- BORRADOR, CONFIRMADA, EN_PREPARACION, PARCIAL, DESPACHADA, FACTURADA, CANCELADA
  -- Crédito (si aplica)
  es_credito            BOOLEAN DEFAULT false,
  termino_pago_id       UUID REFERENCES terminos_pago(id),
  fecha_vencimiento     DATE,
  -- Control stock
  modo_stock            VARCHAR(20) DEFAULT 'PRINCIPAL',    -- PRINCIPAL, CONSOLIDADO, SIN_CONTROL
  auto_transferencia    BOOLEAN DEFAULT false,
  -- Totales
  subtotal              DECIMAL(14,2) DEFAULT 0,
  total_descuento       DECIMAL(14,2) DEFAULT 0,
  base_0                DECIMAL(14,2) DEFAULT 0,
  base_gravada          DECIMAL(14,2) DEFAULT 0,
  total_iva             DECIMAL(14,2) DEFAULT 0,
  total                 DECIMAL(14,2) DEFAULT 0,
  -- Intercompany
  es_intercompany       BOOLEAN DEFAULT false,
  empresa_destino_id    UUID REFERENCES empresas(id),
  notas                 TEXT,
  created_at            TIMESTAMPTZ DEFAULT now(),
  UNIQUE(empresa_id, numero)
);

CREATE TABLE ordenes_venta_lineas (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  orden_venta_id        UUID NOT NULL REFERENCES ordenes_venta(id) ON DELETE CASCADE,
  orden                 INTEGER DEFAULT 0,
  producto_id           UUID NOT NULL REFERENCES productos(id),
  presentacion_id       UUID REFERENCES producto_presentaciones(id),
  descripcion           VARCHAR(300) NOT NULL,
  cantidad              DECIMAL(18,6) NOT NULL,
  cantidad_base         DECIMAL(18,6) NOT NULL,             -- En unidad base del producto
  cantidad_despachada   DECIMAL(18,6) DEFAULT 0,
  cantidad_facturada    DECIMAL(18,6) DEFAULT 0,
  precio_unitario       DECIMAL(18,6) NOT NULL,
  descuento_pct         DECIMAL(5,2) DEFAULT 0,
  descuento_monto       DECIMAL(14,2) DEFAULT 0,
  precio_total          DECIMAL(14,2) NOT NULL,
  tarifa_iva_id         UUID REFERENCES catalogo_tarifas_iva(id),
  bodega_id             UUID REFERENCES bodegas(id),        -- Bodega de despacho
  -- BOM (si es ensamblaje)
  es_ensamblaje         BOOLEAN DEFAULT false,
  bom_id                UUID                                -- FK a bom_cabecera si activo
);
```

### Garantías de Venta

```sql
-- ══════════════════════════════════════════════════════════════════
-- GARANTIAS DE VENTA
-- Define qué garantía otorga la empresa al cliente al vender.
-- Referencia garantias_proveedor de Compras si es transferida/mixta.
-- ══════════════════════════════════════════════════════════════════

CREATE TABLE garantias_venta (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id              UUID NOT NULL REFERENCES empresas(id),
  producto_id             UUID NOT NULL REFERENCES productos(id),
  -- Tipo de garantía
  tipo                    VARCHAR(20) NOT NULL,
  -- PROPIA:       La empresa da su propia garantía (independiente del proveedor)
  -- TRANSFERIDA:  Se transfiere exactamente la garantía del proveedor al cliente
  -- MIXTA:        Empresa extiende la garantía del proveedor (mayor duración o cobertura)
  garantia_proveedor_id   UUID REFERENCES garantias_proveedor(id),  -- Si TRANSFERIDA o MIXTA
  -- Duración propia de la empresa (solo aplica en PROPIA o MIXTA)
  duracion_propia         INTEGER,
  unidad_duracion         VARCHAR(10) DEFAULT 'MESES',  -- DIAS, MESES, ANOS
  -- Cobertura que da la empresa al cliente
  cubre_mano_obra         BOOLEAN NOT NULL DEFAULT true,
  cubre_repuestos         BOOLEAN NOT NULL DEFAULT true,
  condiciones             TEXT,                         -- Qué cubre y qué excluye
  activo                  BOOLEAN NOT NULL DEFAULT true,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by              UUID REFERENCES auth.users(id),
  UNIQUE(empresa_id, producto_id),
  -- Validación: si TRANSFERIDA o MIXTA, debe referenciar garantia_proveedor
  CONSTRAINT chk_garantia_proveedor_requerido
    CHECK (tipo = 'PROPIA' OR garantia_proveedor_id IS NOT NULL)
);

-- Vista: duración efectiva de garantía por producto
CREATE VIEW v_garantia_efectiva AS
SELECT
  gv.id,
  gv.empresa_id,
  gv.producto_id,
  gv.tipo,
  CASE gv.tipo
    WHEN 'PROPIA'       THEN gv.duracion_propia
    WHEN 'TRANSFERIDA'  THEN gp.duracion
    WHEN 'MIXTA'        THEN GREATEST(gv.duracion_propia, gp.duracion)
  END AS duracion_efectiva,
  CASE gv.tipo
    WHEN 'PROPIA'       THEN gv.unidad_duracion
    WHEN 'TRANSFERIDA'  THEN gp.unidad_duracion
    WHEN 'MIXTA'        THEN gv.unidad_duracion
  END AS unidad_efectiva,
  gv.cubre_mano_obra,
  gv.cubre_repuestos
FROM garantias_venta gv
LEFT JOIN garantias_proveedor gp ON gv.garantia_proveedor_id = gp.id;

CREATE INDEX idx_garantias_venta_producto ON garantias_venta(empresa_id, producto_id);

ALTER TABLE garantias_venta ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON garantias_venta
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));
```

> Al confirmar una factura (vía `module_bus.facturacion.create_invoice()`), el módulo Facturación consulta `garantias_venta` por `producto_id` y registra `garantia_venta_id`, `fecha_inicio_garantia` y `fecha_fin_garantia` en cada línea de `factura_lineas`. El módulo Auxiliar **Garantías/RMA** consulta estos campos vía `module_bus.ventas.get_garantia_factura(factura_linea_id)` para validar vigencia al recibir un reclamo.

---

## Funciones RPC Clave

```sql
-- Confirmar Orden de Venta y emitir factura vía Facturación
-- Ventas NUNCA inserta directamente en la tabla `facturas`.
CREATE OR REPLACE FUNCTION ventas.confirm_order_and_invoice(
  p_empresa_id      UUID,
  p_orden_venta_id  UUID,
  p_forma_pago      JSONB,   -- [{codigo_sri, descripcion, total, plazo, unidad_tiempo}]
  p_plazo_dias      INTEGER DEFAULT 0
) RETURNS UUID   -- Retorna factura_id
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_ov        RECORD;
  v_factura_id UUID;
BEGIN
  SELECT ov.*, c.tipo_identificacion, c.identificacion, c.razon_social,
    c.id AS cliente_id, c.email, c.telefono
  INTO v_ov
  FROM ordenes_venta ov
  JOIN contactos c ON c.id = ov.contacto_id
  WHERE ov.id = p_orden_venta_id AND ov.empresa_id = p_empresa_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Orden de venta % no encontrada para empresa %', p_orden_venta_id, p_empresa_id;
  END IF;

  IF v_ov.estado != 'CONFIRMADA' THEN
    RAISE EXCEPTION 'La OV debe estar CONFIRMADA para facturar (estado: %)', v_ov.estado;
  END IF;

  -- Verificar límite de crédito si aplica
  IF v_ov.es_credito THEN
    PERFORM ventas.check_credit_limit(p_empresa_id, v_ov.contacto_id, v_ov.total);
  END IF;

  -- Emitir factura a través del Module Service Bus → Facturación
  SELECT module_bus.facturacion.create_invoice(
    p_empresa_id        := p_empresa_id,
    p_orden_venta_id    := p_orden_venta_id,
    p_cliente_id        := v_ov.cliente_id,
    p_lineas            := (
      SELECT jsonb_agg(row_to_json(l)) FROM ordenes_venta_lineas l
      WHERE l.orden_venta_id = p_orden_venta_id
    ),
    p_forma_pago        := p_forma_pago,
    p_plazo_dias        := p_plazo_dias
  ) INTO v_factura_id;
  -- Retorna factura_id

  UPDATE ordenes_venta SET estado = 'FACTURADA' WHERE id = p_orden_venta_id;

  RETURN v_factura_id;
END;
$$;

-- Aplicar cobro a una factura (CxC es propiedad de Ventas/Tesorería)
CREATE OR REPLACE FUNCTION ventas.apply_cobro_to_invoice(
  p_empresa_id    UUID,
  p_factura_id    UUID,
  p_monto         DECIMAL,
  p_forma_pago    VARCHAR,       -- EFECTIVO, CHEQUE, TRANSFERENCIA, TARJETA, RETENCION, NC
  p_referencia    VARCHAR DEFAULT NULL,
  p_cuenta_id     UUID DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_cobro_id UUID; v_saldo DECIMAL;
BEGIN
  SELECT saldo_pendiente INTO v_saldo FROM cuentas_por_cobrar WHERE factura_id = p_factura_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No existe CxC para la factura %', p_factura_id;
  END IF;

  IF p_monto > v_saldo THEN
    RAISE EXCEPTION 'El monto % supera el saldo pendiente %', p_monto, v_saldo;
  END IF;

  INSERT INTO cobros (empresa_id, factura_id, monto, forma_pago, referencia, cuenta_bancaria_id, fecha)
  VALUES (p_empresa_id, p_factura_id, p_monto, p_forma_pago, p_referencia, p_cuenta_id, CURRENT_DATE)
  RETURNING id INTO v_cobro_id;

  UPDATE cuentas_por_cobrar
  SET saldo_pendiente = saldo_pendiente - p_monto,
      estado = CASE WHEN saldo_pendiente - p_monto <= 0 THEN 'PAGADA' ELSE 'PARCIAL' END
  WHERE factura_id = p_factura_id;

  -- Notificar a Facturación para actualizar estado_pago en la factura
  PERFORM module_bus.facturacion.update_payment_status(p_factura_id);

  PERFORM module_bus.contabilidad_create_journal_entry(p_empresa_id, 'COBRO', v_cobro_id);
  RETURN v_cobro_id;
END;
$$;

-- Verificar límite de crédito antes de facturar
CREATE OR REPLACE FUNCTION ventas.check_credit_limit(
  p_empresa_id    UUID,
  p_contacto_id   UUID,
  p_monto_nuevo   DECIMAL
) RETURNS JSONB  -- {permitido: bool, limite: N, usado: N, disponible: N, motivo: '...'}
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_config RECORD; v_usado DECIMAL; v_vencido DECIMAL; v_facturas_vencidas INT;
BEGIN
  SELECT * INTO v_config FROM config_credito_cliente
  WHERE empresa_id = p_empresa_id AND contacto_id = p_contacto_id;

  IF NOT FOUND OR NOT v_config.credito_habilitado THEN
    RETURN jsonb_build_object('permitido', false, 'motivo', 'Crédito no habilitado');
  END IF;

  -- Cartera actual
  SELECT COALESCE(SUM(saldo_pendiente), 0), COUNT(*) FILTER (WHERE fecha_vencimiento < CURRENT_DATE),
    COALESCE(SUM(saldo_pendiente) FILTER (WHERE fecha_vencimiento < CURRENT_DATE), 0)
  INTO v_usado, v_facturas_vencidas, v_vencido
  FROM cuentas_por_cobrar
  WHERE empresa_id = p_empresa_id AND contacto_id = p_contacto_id AND estado != 'PAGADA';

  -- Verificar bloqueo por facturas vencidas
  IF v_facturas_vencidas > v_config.max_facturas_vencidas THEN
    RETURN jsonb_build_object('permitido', false, 'motivo',
      format('%s facturas vencidas (máx: %s)', v_facturas_vencidas, v_config.max_facturas_vencidas),
      'usado', v_usado, 'vencido', v_vencido);
  END IF;

  RETURN jsonb_build_object(
    'permitido', (v_usado + p_monto_nuevo) <= v_config.limite_credito,
    'limite', v_config.limite_credito,
    'usado', v_usado,
    'disponible', v_config.limite_credito - v_usado,
    'motivo', CASE WHEN (v_usado + p_monto_nuevo) > v_config.limite_credito
      THEN 'Límite de crédito excedido' ELSE 'OK' END
  );
END;
$$;

-- Convertir cotización aprobada a orden de venta
CREATE OR REPLACE FUNCTION convert_quotation_to_order(
  p_cotizacion_id UUID
) RETURNS UUID AS $$
DECLARE
  v_cotizacion RECORD;
  v_orden_id UUID;
BEGIN
  -- Obtener cotización con sus detalles
  SELECT * INTO v_cotizacion FROM cotizaciones WHERE id = p_cotizacion_id;

  IF v_cotizacion.estado != 'APROBADA' THEN
    RAISE EXCEPTION 'Solo se pueden convertir cotizaciones aprobadas';
  END IF;

  -- Crear orden de venta
  INSERT INTO ordenes_venta (empresa_id, contacto_id, vendedor_id, termino_pago_id,
    cotizacion_id, fecha, numero, estado)
  VALUES (v_cotizacion.empresa_id, v_cotizacion.contacto_id, v_cotizacion.vendedor_id,
    v_cotizacion.termino_pago_id, p_cotizacion_id, CURRENT_DATE,
    nextval('seq_ordenes_venta'), 'CONFIRMADA')
  RETURNING id INTO v_orden_id;

  -- Copiar líneas de detalle
  INSERT INTO orden_venta_detalles (orden_venta_id, producto_id, presentacion_id,
    descripcion, cantidad, cantidad_base, precio_unitario, descuento, subtotal,
    total_impuestos, total_linea)
  SELECT v_orden_id, producto_id, presentacion_id, descripcion, cantidad,
    cantidad_base, precio_unitario, descuento, subtotal, total_impuestos, total_linea
  FROM cotizacion_detalles WHERE cotizacion_id = p_cotizacion_id;

  -- Actualizar estado cotización
  UPDATE cotizaciones SET estado = 'CONVERTIDA' WHERE id = p_cotizacion_id;

  RETURN v_orden_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Convertir orden de venta a factura
CREATE OR REPLACE FUNCTION convert_order_to_invoice(
  p_orden_venta_id UUID
) RETURNS UUID AS $$
DECLARE
  v_orden RECORD;
  v_factura_id UUID;
  v_documento_id UUID;
  v_termino RECORD;
  v_linea RECORD;
BEGIN
  SELECT * INTO v_orden FROM ordenes_venta WHERE id = p_orden_venta_id;

  IF v_orden.estado NOT IN ('CONFIRMADA', 'PARCIAL') THEN
    RAISE EXCEPTION 'Solo se pueden facturar ordenes confirmadas o parciales';
  END IF;

  -- Crear documento electronico (tipo 01 = Factura)
  INSERT INTO documentos_electronicos (empresa_id, tipo_documento, fecha_emision,
    contacto_id, estado_sri)
  VALUES (v_orden.empresa_id, '01', CURRENT_DATE, v_orden.contacto_id, 'PENDIENTE')
  RETURNING id INTO v_documento_id;

  -- Crear factura vinculada a la OV
  INSERT INTO facturas (empresa_id, documento_id, contacto_id, vendedor_id,
    termino_pago_id, orden_venta_id, total_sin_impuestos, importe_total, estado)
  VALUES (v_orden.empresa_id, v_documento_id, v_orden.contacto_id, v_orden.vendedor_id,
    v_orden.termino_pago_id, p_orden_venta_id, v_orden.total - v_orden.total_iva,
    v_orden.total, 'BORRADOR')
  RETURNING id INTO v_factura_id;

  -- Copiar líneas pendientes de la OV a factura_detalles
  INSERT INTO factura_detalles (factura_id, producto_id, presentacion_id,
    descripcion, cantidad, cantidad_base, precio_unitario, descuento,
    precio_total_sin_impuesto)
  SELECT v_factura_id, producto_id, presentacion_id, descripcion,
    cantidad - cantidad_despachada, cantidad_base, precio_unitario, descuento,
    subtotal
  FROM orden_venta_detalles
  WHERE orden_venta_id = p_orden_venta_id
    AND (cantidad - COALESCE(cantidad_despachada, 0)) > 0;

  -- Generar cuotas CxC según término de pago (si es crédito)
  IF v_orden.termino_pago_id IS NOT NULL THEN
    FOR v_termino IN
      SELECT * FROM terminos_pago_lineas
      WHERE termino_pago_id = v_orden.termino_pago_id
      ORDER BY secuencia
    LOOP
      -- Crear cuotas en factura_pagos (SRI) y cuotas_credito
      -- según tipo PORCENTAJE/MONTO_FIJO/BALANCE y días
      NULL; -- Implementación: calcula monto por cuota y fecha vencimiento
    END LOOP;
  END IF;

  -- Actualizar cantidades despachadas en la OV
  UPDATE orden_venta_detalles SET
    cantidad_despachada = cantidad,
    cantidad_pendiente = 0
  WHERE orden_venta_id = p_orden_venta_id;

  -- Actualizar estado OV
  UPDATE ordenes_venta SET estado = 'COMPLETA' WHERE id = p_orden_venta_id;

  RETURN v_factura_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

---

## Row Level Security

```sql
ALTER TABLE cotizaciones ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON cotizaciones
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

ALTER TABLE ordenes_venta ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON ordenes_venta
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

ALTER TABLE garantias_venta ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON garantias_venta
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- (aplicar patrón equivalente a cotizacion_lineas, ordenes_venta_lineas)
```

---

## Pipeline Ventas → Facturación

```
Cotización aprobada
  ↓
Crear Orden de Venta (estado: CONFIRMADA)
  ↓
ventas.confirm_order_and_invoice()
  ↓
module_bus.facturacion.create_invoice()   ← Ventas NUNCA escribe en `facturas` directamente
  ↓
[Módulo Facturación toma el control]
  → Asignar secuencial + generar clave acceso 49 dígitos
  → Encolar en cola_documentos_electronicos (prioridad alta)
  → Edge Function sign-document → XML XAdES-BES
  → Edge Function send-to-sri (SOAP) → AUTORIZADA/RECHAZADA
  → Guardar XML + RIDE PDF en Supabase Storage
  → Notificar cliente (email Resend + WhatsApp + Telegram)
  ↓
Ventas recibe factura_id y actualiza OV → estado = FACTURADA
```

---

## Integraciones con otros Módulos

| Evento | Acción |
|--------|--------|
| OV confirmada → `module_bus.facturacion.create_invoice()` | Facturación emite el documento SRI; Inventario descuenta stock; Contabilidad crea asiento; Tesorería crea CxC |
| Factura AUTORIZADA (evento desde Facturación) | Ventas actualiza OV estado=FACTURADA; Lealtad acumula puntos (si activo) |
| Cobro registrado | Actualizar CxC · Asiento Db Banco/Cr CxC |
| NC emitida (vía `module_bus.facturacion.create_credit_note()`) | Reingresar stock si aplica · Ajustar CxC · Asiento reverso |
| Pedido ecommerce | Crear cotización automática con origen=ECOMMERCE |
| Oportunidad ganada CRM | Crear cotización automática con datos del lead |
| **Facturación** (requerido) | Ventas emite facturas vía `module_bus.facturacion.create_invoice()`. El módulo Ventas NUNCA inserta directamente en la tabla `facturas`. |

---

## Sub-módulos

| Sub-módulo | Descripción |
|------------|-------------|
| [Crédito Clientes](credito-clientes.md) | Límite de crédito, bloqueo, excepción supervisor, historial |
| [Descuentos](descuentos.md) | Descuento por monto y porcentaje, template tax_totals Ecuador |
| [Plazos de Pago](plazos-pago.md) | Términos is_cash/is_credit, cuotas por OV |
| [Ensamblaje](ensamblaje.md) | Rutas por sección en OV, asignación masiva, validación MTO |
| [Lealtad](lealtad.md) | Programa de puntos, niveles (Bronce/Plata/Oro/Platino), canje |
| [Cupones](cupones.md) | Campañas promocionales, generación masiva, QR |
| [Suscripciones](suscripciones.md) | Planes de suscripción recurrente, facturación automática |
| [Pronto Pago](pronto-pago.md) | Descuentos por pago anticipado antes de vencimiento |
| [Intercompany Ventas](intercompany-ventas.md) | Transacciones entre empresas del mismo grupo |
| [IA Ventas](ia-ventas.md) | Forecast de ventas, scoring clientes, recomendaciones |

---

## Flujos Principales

### Cotización → Orden de Venta → Factura

```
┌─────────┐    ┌──────────┐    ┌──────────────┐    ┌──────────┐
│ Crear   │───>│ Aprobar  │───>│ Generar      │───>│ Registrar│
│ Cotiza- │    │ Pedido   │    │ Factura /    │    │ Cobro    │
│ cion    │    │ Venta    │    │ Documento    │    │          │
└─────────┘    └──────────┘    └──────────────┘    └────┬─────┘
                                                        │
                                ┌──────────────┐        │
                                │ Asiento      │<───────┘
                                │ Contable     │
                                │ Automatico   │
                                └──────────────┘
```

> **Integración SRI Ecuador**: Ver [`modules/extensiones/facturacion_ec/flujos-sri.md`](../../extensiones/facturacion_ec/flujos-sri.md) para el pipeline XAdES-BES, SOAP y generación RIDE.

### Flujo de Nota de Crédito

```
┌──────────┐    ┌──────────┐    ┌──────────────┐    ┌──────────┐
│ Seleccio-│───>│ Indicar  │───>│ Generar Nota │───>│ Actualiz.│
│ nar      │    │ Items a  │    │ de Credito   │    │Inventario│
│ Factura  │    │ Devolver │    │ (devolucion) │    │(devol.)  │
│ Original │    │ + Motivo │    │              │    └────┬─────┘
└──────────┘    └──────────┘    └──────────────┘         │
                                ┌──────────────┐         │
                                │ Asiento      │<────────┘
                                │ Contable     │
                                │ Reverso      │
                                └──────────────┘
```

> **Integración SRI Ecuador**: Ver [`modules/extensiones/facturacion_ec/flujos-sri.md`](../../extensiones/facturacion_ec/flujos-sri.md) para el flujo de firma XAdES-BES y envío al SRI de la nota de crédito electrónica.

---

## Casos de Uso

### Actores

| Actor | Descripcion |
|-------|-------------|
| **Vendedor** | Crea cotizaciones, pedidos de venta |
| **Facturador** | Emite facturas y documentos de venta |
| **Contador** | Registra cobros, genera reportes financieros |
| **Gerente** | Consulta reportes y dashboards |
| **Sistema Externo** | Plataforma externa (ecommerce, pasarela de pagos) que envía pedidos al ERP |

### Casos de Uso - Ventas

| ID | Caso de Uso | Actor | Prioridad |
|----|-------------|-------|-----------|
| V01 | Crear cotizacion | Vendedor | Alta |
| V02 | Aprobar cotizacion como pedido de venta | Vendedor/Gerente | Alta |
| V03 | Emitir factura / documento de venta | Facturador | **Critica** |
| V04 | Emitir nota de credito | Facturador | **Critica** |
| V05 | Emitir nota de debito | Facturador | Alta |
| V06 | Registrar cobro | Facturador/Contador | Alta |
| V07 | Consultar estado cuenta cliente | Vendedor | Media |
| V08 | Reenviar comprobante por email | Facturador | Media |
| V09 | Anular comprobante | Facturador | Alta |
| V10 | Consultar reporte de ventas | Gerente | Alta |
| V11 | Facturar desde proforma/cotizacion | Facturador | Alta |
| V12 | Facturar desde despacho de inventario | Facturador/Bodeguero | Alta |
| V16 | Recibir pedido de ecommerce | Sistema | Alta |

> **Casos de uso con firma electrónica SRI** (V03, V04, V05, V09, V11, V12): Ver [`modules/extensiones/facturacion_ec/flujos-sri.md`](../../extensiones/facturacion_ec/flujos-sri.md).

### Casos de Uso - Integraciones Ecommerce

| ID | Caso de Uso | Actor | Prioridad |
|----|-------------|-------|-----------|
| EC01 | Sincronizar catalogo de productos a WooCommerce | Sistema | Alta |
| EC02 | Recibir pedido desde WooCommerce | Sistema | Alta |
| EC03 | Actualizar stock en WooCommerce al facturar | Sistema | Alta |
| EC04 | Confirmar pago y generar factura electronica | Sistema | Alta |
| EC05 | Notificar envio al cliente (tracking) | Sistema | Media |
| EC06 | Sincronizar con otras plataformas (Shopify, MercadoLibre) | Sistema | Media |
