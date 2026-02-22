# Módulo de Compras

Gestión del ciclo de compra: proveedores, solicitudes (RFQ), órdenes de compra, recepción de mercadería, registro de facturas de proveedores, retenciones electrónicas (SRI tipo 07) y liquidaciones de compra (tipo 03). Incluye CxP y pagos a proveedores.

> Sub-módulos detallados: [RFQ](rfq.md) · [Scoring Proveedores](scoring-proveedores.md) · [Acuerdos Marco](acuerdos-marco.md) · [Dropshipping](dropshipping.md) · [Consignación](consignacion.md) · [Importaciones](importaciones.md) · [Importación XML SRI](importacion-xml-sri.md) · [Costos de Aterrizaje](costos-aterrizaje.md)

---

## Navegación

```
compras/
  ├── proveedores/
  │     ├── listado/            # SfDataGrid (es_proveedor=true)
  │     ├── nuevo/              # Formulario contacto + datos tributarios
  │     └── detalle/            # Ficha 360: OC, CxP, historial, scoring
  ├── solicitudes-cotizacion/   # RFQ: solicitar cotización a N proveedores (ver rfq.md)
  ├── ordenes-compra/
  │     ├── listado/            # Estado: BORRADOR/CONFIRMADA/RECIBIDA/FACTURADA
  │     ├── nueva/              # Formulario con líneas + bodega destino
  │     ├── detalle/            # OC + recepción parcial o total
  │     └── recibir/            # Registrar recepción → movimiento inventario
  ├── facturas-recibidas/
  │     ├── listado/
  │     ├── manual/             # Ingreso manual de datos de factura proveedor
  │     └── importar-xml/       # Importar desde XML SRI o clave de acceso
  ├── liquidaciones/            # Emisión liquidaciones de compra V1.1.0 (tipo 03)
  ├── retenciones/              # Emisión retenciones V2.0.0 (tipo 07)
  │     ├── listado/
  │     ├── crear/              # Selección doc sustento + retenciones IVA/Renta
  │     ├── firmar/
  │     └── enviar-sri/
  ├── cuentas-pagar/
  │     ├── listado/            # CxP con filtros (vencidas, por vencer, proveedor)
  │     ├── estado-cuenta/      # Estado de cuenta por proveedor
  │     └── planes-pago/        # Planes de pago aprobados
  ├── pagos/
  │     ├── nuevo/              # Seleccionar CxP + métodos (efectivo/cheque/transf/cruce ret)
  │     └── masivo/             # Pagos múltiples desde plan de pago
  ├── garantias-proveedor/
  │     ├── listado/        # SfDataGrid: producto + proveedor + duración + cobertura
  │     ├── nueva/          # Registrar garantía que da el proveedor
  │     └── detalle/        # Ver/editar términos de garantía
  └── reportes/
        ├── compras-periodo/    # Compras por período, proveedor, categoría
        ├── aging-proveedores/  # Cartera CxP: 0-30, 31-60, 61-90, 90+ días
        ├── cxp-vs-pagos/       # Deudas vs pagos por período
        └── retenciones-emitidas/ # Retenciones emitidas (para ATS)
```

---

## Modelo de Datos

### Órdenes de Compra

```sql
CREATE TABLE ordenes_compra (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  numero                VARCHAR(30) NOT NULL,               -- OC-2026-0001
  -- RFQ origen (si aplica)
  rfq_id                UUID,                               -- FK a solicitudes_cotizacion
  -- Proveedor
  contacto_id           UUID NOT NULL REFERENCES contactos(id),
  -- Fechas
  fecha                 DATE NOT NULL DEFAULT CURRENT_DATE,
  fecha_entrega_est     DATE,
  -- Bodega de recepción
  bodega_id             UUID NOT NULL REFERENCES bodegas(id),
  -- Estado
  estado                VARCHAR(20) DEFAULT 'BORRADOR',
    -- BORRADOR, CONFIRMADA, ENVIADA_PROVEEDOR, PARCIAL, RECIBIDA, FACTURADA, CANCELADA
  -- Totales
  subtotal              DECIMAL(14,2) DEFAULT 0,
  total_descuento       DECIMAL(14,2) DEFAULT 0,
  base_0                DECIMAL(14,2) DEFAULT 0,
  base_gravada          DECIMAL(14,2) DEFAULT 0,
  total_iva             DECIMAL(14,2) DEFAULT 0,
  total                 DECIMAL(14,2) DEFAULT 0,
  -- Términos
  termino_pago_id       UUID REFERENCES terminos_pago(id),
  -- Costos de aterrizaje (si importación)
  es_importacion        BOOLEAN DEFAULT false,
  -- Aprobación (si flujo de aprobación activo)
  aprobado_por          UUID REFERENCES auth.users(id),
  fecha_aprobacion      TIMESTAMPTZ,
  notas                 TEXT,
  created_at            TIMESTAMPTZ DEFAULT now(),
  UNIQUE(empresa_id, numero)
);

CREATE TABLE ordenes_compra_lineas (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  orden_compra_id       UUID NOT NULL REFERENCES ordenes_compra(id) ON DELETE CASCADE,
  orden                 INTEGER DEFAULT 0,
  producto_id           UUID NOT NULL REFERENCES productos(id),
  presentacion_id       UUID REFERENCES producto_presentaciones(id),
  descripcion           VARCHAR(300) NOT NULL,
  cantidad              DECIMAL(18,6) NOT NULL,
  cantidad_base         DECIMAL(18,6) NOT NULL,             -- En unidad base del producto
  cantidad_recibida     DECIMAL(18,6) DEFAULT 0,            -- Acumulado de recepciones
  cantidad_facturada    DECIMAL(18,6) DEFAULT 0,
  precio_unitario       DECIMAL(18,6) NOT NULL,             -- Sin IVA
  descuento_pct         DECIMAL(5,2) DEFAULT 0,
  descuento_monto       DECIMAL(14,2) DEFAULT 0,
  precio_total          DECIMAL(14,2) NOT NULL,             -- Sin IVA
  tarifa_iva_id         UUID REFERENCES catalogo_tarifas_iva(id),
  valor_iva             DECIMAL(14,2) DEFAULT 0,
  -- Cuenta contable (gasto/activo)
  cuenta_contable_id    UUID REFERENCES cuentas_contables(id),
  notas                 TEXT
);
```

### Recepciones de Mercadería

```sql
-- Registro de recepciones (puede ser parcial)
CREATE TABLE recepciones_compra (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  numero                VARCHAR(30) NOT NULL,               -- REC-2026-0001
  orden_compra_id       UUID NOT NULL REFERENCES ordenes_compra(id),
  contacto_id           UUID NOT NULL REFERENCES contactos(id),
  bodega_id             UUID NOT NULL REFERENCES bodegas(id),
  fecha                 DATE NOT NULL DEFAULT CURRENT_DATE,
  -- Documento proveedor
  guia_remision_proveedor VARCHAR(50),                      -- Guía del proveedor (opcional)
  -- Control de calidad
  estado_qc             VARCHAR(20) DEFAULT 'PENDIENTE',    -- PENDIENTE, APROBADO, RECHAZADO
  qc_id                 UUID,                               -- FK a control_calidad si activo
  -- Estado
  estado                VARCHAR(20) DEFAULT 'BORRADOR',     -- BORRADOR, CONFIRMADA, ANULADA
  -- Movimiento inventario generado
  movimiento_ids        UUID[],
  notas                 TEXT,
  created_at            TIMESTAMPTZ DEFAULT now(),
  UNIQUE(empresa_id, numero)
);

CREATE TABLE recepcion_lineas (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recepcion_id          UUID NOT NULL REFERENCES recepciones_compra(id) ON DELETE CASCADE,
  oc_linea_id           UUID REFERENCES ordenes_compra_lineas(id),
  producto_id           UUID NOT NULL REFERENCES productos(id),
  presentacion_id       UUID REFERENCES producto_presentaciones(id),
  cantidad_pedida       DECIMAL(18,6) NOT NULL,
  cantidad_recibida     DECIMAL(18,6) NOT NULL,
  cantidad_rechazada    DECIMAL(18,6) DEFAULT 0,            -- No conforme en QC
  costo_unitario        DECIMAL(18,6) NOT NULL,
  -- Trazabilidad
  numeros_serie         VARCHAR(100)[],                     -- Series ingresadas
  numero_lote           VARCHAR(100),
  fecha_vencimiento     DATE                                -- Para lotes con vencimiento
);
```

### Facturas de Proveedores

```sql
-- Facturas recibidas de proveedores (no emitidas por nosotros)
CREATE TABLE facturas_proveedor (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  -- Emisor (proveedor)
  contacto_id           UUID NOT NULL REFERENCES contactos(id),
  ruc_emisor            VARCHAR(13) NOT NULL,
  razon_social_emisor   VARCHAR(300) NOT NULL,
  -- Datos del documento recibido
  clave_acceso          VARCHAR(49),                        -- Si viene por XML/SRI
  numero_documento      VARCHAR(17),                        -- 001-001-000000001
  tipo_documento        VARCHAR(2) DEFAULT '01',            -- 01=Factura, 03=LC, 07=Retención
  -- Fechas
  fecha_emision         DATE NOT NULL,
  fecha_registro        DATE NOT NULL DEFAULT CURRENT_DATE,
  -- Totales (del documento del proveedor)
  base_0                DECIMAL(14,2) DEFAULT 0,
  base_gravada          DECIMAL(14,2) DEFAULT 0,
  total_iva             DECIMAL(14,2) DEFAULT 0,
  total_ice             DECIMAL(14,2) DEFAULT 0,
  total                 DECIMAL(14,2) DEFAULT 0,
  -- Retenciones que emitimos (FK a retenciones tabla)
  retencion_id          UUID,
  -- Código de sustento tributario (obligatorio para retenciones y ATS)
  codigo_sustento       VARCHAR(2) NOT NULL,                -- '01' a '15'
  -- OC vinculada
  orden_compra_id       UUID REFERENCES ordenes_compra(id),
  -- Estado del documento (ciclo de vida)
  estado                VARCHAR(20) DEFAULT 'BORRADOR',
    -- BORRADOR: recién creada / REGISTRADA: datos validados / CONTABILIZADA: asiento generado
  -- Estado de pago
  estado_pago           VARCHAR(20) DEFAULT 'PENDIENTE',    -- PENDIENTE, PARCIAL, PAGADA
  -- XML almacenado
  xml_url               TEXT,                               -- URL en Supabase Storage
  -- Importación
  metodo_importacion    VARCHAR(10),                        -- MANUAL, XML, SRI, SCAN
  created_at            TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE factura_proveedor_lineas (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  factura_proveedor_id  UUID NOT NULL REFERENCES facturas_proveedor(id) ON DELETE CASCADE,
  orden                 INTEGER DEFAULT 0,
  codigo                VARCHAR(50),
  descripcion           VARCHAR(300) NOT NULL,
  cantidad              DECIMAL(18,6) NOT NULL,
  precio_unitario       DECIMAL(18,6) NOT NULL,
  descuento             DECIMAL(14,2) DEFAULT 0,
  precio_total_sin_iva  DECIMAL(14,2) NOT NULL,
  porcentaje_iva        DECIMAL(5,2) NOT NULL,
  valor_iva             DECIMAL(14,2) NOT NULL,
  -- Vinculación interna
  producto_id           UUID REFERENCES productos(id),      -- Homologación de producto
  cuenta_contable_id    UUID REFERENCES cuentas_contables(id)
);
```

### Liquidaciones de Compra (SRI tipo 03)

```sql
-- Emitidas POR NOSOTROS cuando el proveedor es una persona natural sin RUC
CREATE TABLE liquidaciones_compra (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  establecimiento_id    UUID NOT NULL REFERENCES establecimientos(id),
  punto_emision_id      UUID NOT NULL REFERENCES puntos_emision(id),
  secuencial            VARCHAR(9),
  clave_acceso          VARCHAR(49),
  -- Proveedor (persona natural sin RUC)
  tipo_identificacion   VARCHAR(2) NOT NULL,               -- '05' cédula, '06' pasaporte
  identificacion        VARCHAR(20) NOT NULL,
  razon_social          VARCHAR(300) NOT NULL,
  direccion             VARCHAR(300),
  contacto_id           UUID REFERENCES contactos(id),
  -- Totales
  base_0                DECIMAL(14,2) DEFAULT 0,
  base_gravada          DECIMAL(14,2) DEFAULT 0,
  total_iva             DECIMAL(14,2) DEFAULT 0,
  total                 DECIMAL(14,2) DEFAULT 0,
  formas_pago           JSONB DEFAULT '[]',
  -- Estado SRI
  estado                VARCHAR(20) DEFAULT 'BORRADOR',
  fecha_autorizacion    TIMESTAMPTZ,
  numero_autorizacion   VARCHAR(49),
  xml_firmado_url       TEXT,
  ride_pdf_url          TEXT,
  -- Retención vinculada (normalmente se retiene al liquidar)
  retencion_id          UUID,
  version               INTEGER DEFAULT 1,
  created_at            TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE liquidacion_lineas (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  liquidacion_id        UUID NOT NULL REFERENCES liquidaciones_compra(id) ON DELETE CASCADE,
  orden                 INTEGER DEFAULT 0,
  codigo                VARCHAR(50),
  descripcion           VARCHAR(300) NOT NULL,
  cantidad              DECIMAL(18,6) NOT NULL,
  precio_unitario       DECIMAL(18,6) NOT NULL,
  descuento             DECIMAL(14,2) DEFAULT 0,
  precio_total_sin_iva  DECIMAL(14,2) NOT NULL,
  porcentaje_iva        DECIMAL(5,2) NOT NULL,
  valor_iva             DECIMAL(14,2) NOT NULL,
  producto_id           UUID REFERENCES productos(id)
);
```

### Comprobantes de Retención (SRI tipo 07)

```sql
-- Emitidos POR NOSOTROS a proveedores/clientes (cuando somos agente de retención)
CREATE TABLE retenciones (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  establecimiento_id    UUID NOT NULL REFERENCES establecimientos(id),
  punto_emision_id      UUID NOT NULL REFERENCES puntos_emision(id),
  secuencial            VARCHAR(9),
  clave_acceso          VARCHAR(49),
  -- Sujeto pasivo (a quien retenemos)
  tipo_identificacion   VARCHAR(2) NOT NULL,
  identificacion        VARCHAR(20) NOT NULL,
  razon_social          VARCHAR(300) NOT NULL,
  contacto_id           UUID REFERENCES contactos(id),
  -- Documento sustento
  tipo_doc_sustento     VARCHAR(2) NOT NULL,               -- '01', '03', '04', etc.
  numero_doc_sustento   VARCHAR(17) NOT NULL,              -- 001-001-000000001
  fecha_doc_sustento    DATE NOT NULL,
  -- Si sustento es factura proveedor o liquidación
  factura_proveedor_id  UUID REFERENCES facturas_proveedor(id),
  liquidacion_id        UUID REFERENCES liquidaciones_compra(id),
  -- Fecha de emisión (máx 5 días hábiles después del doc sustento)
  fecha                 DATE NOT NULL DEFAULT CURRENT_DATE,
  -- Totales retenidos
  total_iva_retenido    DECIMAL(14,2) DEFAULT 0,
  total_renta_retenido  DECIMAL(14,2) DEFAULT 0,
  -- Estado SRI
  estado                VARCHAR(20) DEFAULT 'BORRADOR',
  fecha_autorizacion    TIMESTAMPTZ,
  numero_autorizacion   VARCHAR(49),
  xml_firmado_url       TEXT,
  ride_pdf_url          TEXT,
  version               INTEGER DEFAULT 1,
  created_at            TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE retencion_lineas (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  retencion_id          UUID NOT NULL REFERENCES retenciones(id) ON DELETE CASCADE,
  tipo                  VARCHAR(5) NOT NULL,               -- IVA, RENTA
  -- Código de retención del catálogo SRI
  codigo_retencion      VARCHAR(10) NOT NULL,              -- '303','332' (renta) o '1','2','3' (iva)
  descripcion           VARCHAR(300) NOT NULL,
  base_imponible        DECIMAL(14,2) NOT NULL,
  porcentaje_retencion  DECIMAL(5,2) NOT NULL,
  valor_retenido        DECIMAL(14,2) NOT NULL,
  -- Código de sustento tributario (INC-REG-05)
  codigo_sustento       VARCHAR(2) NOT NULL
);

CREATE INDEX idx_retenciones_empresa ON retenciones(empresa_id, fecha DESC);
CREATE INDEX idx_retenciones_contacto ON retenciones(contacto_id, fecha DESC);
CREATE INDEX idx_retenciones_estado ON retenciones(empresa_id, estado) WHERE estado != 'BORRADOR';
```

### Garantías de Proveedor

```sql
-- ══════════════════════════════════════════════════════════════════
-- GARANTIAS DE PROVEEDOR
-- Define qué garantía otorga cada proveedor para cada producto.
-- Esta garantía puede ser transferida al cliente en Ventas.
-- ══════════════════════════════════════════════════════════════════

CREATE TABLE garantias_proveedor (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id              UUID NOT NULL REFERENCES empresas(id),
  producto_id             UUID NOT NULL REFERENCES productos(id),
  proveedor_id            UUID NOT NULL REFERENCES contactos(id),
  -- Duración de la garantía
  duracion                INTEGER NOT NULL,               -- Duración numérica
  unidad_duracion         VARCHAR(10) NOT NULL DEFAULT 'MESES',  -- DIAS, MESES, ANOS
  -- Cobertura
  cubre_mano_obra         BOOLEAN NOT NULL DEFAULT true,  -- Cubre costo de reparación
  cubre_repuestos         BOOLEAN NOT NULL DEFAULT true,  -- Cubre costo de repuestos
  condiciones             TEXT,                           -- Restricciones y exclusiones
  -- Garantía upstream (para reclamaciones al proveedor)
  contacto_garantia       VARCHAR(200),                   -- Email/teléfono soporte proveedor
  proceso_reclamo         TEXT,                           -- Procedimiento de reclamo al proveedor
  activo                  BOOLEAN NOT NULL DEFAULT true,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by              UUID REFERENCES auth.users(id),
  UNIQUE(empresa_id, producto_id, proveedor_id)
);

CREATE INDEX idx_garantias_proveedor_producto ON garantias_proveedor(empresa_id, producto_id);
CREATE INDEX idx_garantias_proveedor_proveedor ON garantias_proveedor(proveedor_id);

ALTER TABLE garantias_proveedor ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON garantias_proveedor
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));
```

> El módulo Auxiliar **Garantías/RMA** consulta `garantias_proveedor` vía `module_bus.compras.get_garantia_proveedor(producto_id, proveedor_id)` para determinar si aplica devolución al proveedor cuando se resuelve un RMA.

---

## Funciones RPC Clave

```sql
-- Confirmar recepción de OC (genera movimiento de inventario)
CREATE OR REPLACE FUNCTION confirm_purchase_receipt(
  p_recepcion_id UUID
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_rec RECORD; v_linea RECORD;
BEGIN
  SELECT r.*, oc.empresa_id, oc.bodega_id
  INTO v_rec
  FROM recepciones_compra r
  JOIN ordenes_compra oc ON oc.id = r.orden_compra_id
  WHERE r.id = p_recepcion_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Recepción % no encontrada', p_recepcion_id;
  END IF;

  IF v_rec.estado != 'BORRADOR' THEN
    RAISE EXCEPTION 'La recepción ya fue procesada';
  END IF;

  FOR v_linea IN
    SELECT * FROM recepcion_lineas WHERE recepcion_id = p_recepcion_id
  LOOP
    IF v_linea.cantidad_recibida > 0 THEN
      PERFORM create_stock_movement(
        v_rec.empresa_id, v_linea.producto_id, v_rec.bodega_id,
        'ENTRADA_COMPRA', v_linea.cantidad_recibida, v_linea.costo_unitario,
        'OC', v_rec.orden_compra_id
      );

      -- Actualizar cantidad recibida en la línea de OC
      UPDATE ordenes_compra_lineas
      SET cantidad_recibida = cantidad_recibida + v_linea.cantidad_recibida
      WHERE id = v_linea.oc_linea_id;
    END IF;
  END LOOP;

  -- Actualizar estado de la OC
  UPDATE ordenes_compra SET
    estado = CASE
      WHEN (
        SELECT bool_and(cantidad_recibida >= cantidad)
        FROM ordenes_compra_lineas WHERE orden_compra_id = v_rec.orden_compra_id
      ) THEN 'RECIBIDA' ELSE 'PARCIAL'
    END
  WHERE id = v_rec.orden_compra_id;

  UPDATE recepciones_compra SET estado = 'CONFIRMADA' WHERE id = p_recepcion_id;

  -- Crear CxP
  PERFORM module_bus.create_accounts_payable_from_receipt(p_recepcion_id);
END;
$$;

-- Emitir comprobante de retención
CREATE OR REPLACE FUNCTION create_retencion(
  p_empresa_id          UUID,
  p_establecimiento_id  UUID,
  p_contacto_id         UUID,
  p_doc_sustento_tipo   VARCHAR,
  p_doc_sustento_num    VARCHAR,
  p_fecha_doc_sustento  DATE,
  p_factura_proveedor_id UUID DEFAULT NULL,
  p_lineas              JSONB  -- [{tipo, codigo, descripcion, base, pct, valor, sustento}]
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_ret_id UUID; v_punto_emision RECORD; v_contacto RECORD;
BEGIN
  SELECT pe.* INTO v_punto_emision FROM puntos_emision pe
  WHERE pe.establecimiento_id = p_establecimiento_id
    AND pe.tipo_doc = '07' AND pe.activo = true LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No existe punto de emisión tipo 07 activo para el establecimiento %', p_establecimiento_id;
  END IF;

  SELECT tipo_identificacion, identificacion, nombre INTO v_contacto
  FROM contactos WHERE id = p_contacto_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Contacto % no encontrado', p_contacto_id;
  END IF;

  INSERT INTO retenciones (
    empresa_id, establecimiento_id, punto_emision_id,
    tipo_identificacion, identificacion, razon_social, contacto_id,
    tipo_doc_sustento, numero_doc_sustento, fecha_doc_sustento,
    factura_proveedor_id, fecha,
    total_iva_retenido, total_renta_retenido
  ) VALUES (
    p_empresa_id, p_establecimiento_id, v_punto_emision.id,
    v_contacto.tipo_identificacion, v_contacto.identificacion, v_contacto.nombre,
    p_contacto_id, p_doc_sustento_tipo, p_doc_sustento_num, p_fecha_doc_sustento,
    p_factura_proveedor_id, CURRENT_DATE,
    COALESCE((SELECT SUM((l->>'valor')::DECIMAL) FROM jsonb_array_elements(p_lineas) l WHERE l->>'tipo' = 'IVA'), 0),
    COALESCE((SELECT SUM((l->>'valor')::DECIMAL) FROM jsonb_array_elements(p_lineas) l WHERE l->>'tipo' = 'RENTA'), 0)
  ) RETURNING id INTO v_ret_id;

  INSERT INTO retencion_lineas (retencion_id, tipo, codigo_retencion, descripcion,
    base_imponible, porcentaje_retencion, valor_retenido, codigo_sustento)
  SELECT v_ret_id,
    l->>'tipo', l->>'codigo', l->>'descripcion',
    (l->>'base')::DECIMAL, (l->>'pct')::DECIMAL, (l->>'valor')::DECIMAL, l->>'sustento'
  FROM jsonb_array_elements(p_lineas) l;

  -- Asignar secuencial y encolar para SRI
  PERFORM assign_secuencial_and_queue(v_ret_id, '07');

  -- Asiento contable: Db IVA Pagado / Db Gasto Retención Renta / Cr CxP
  PERFORM module_bus.contabilidad_create_journal_entry(p_empresa_id, 'RETENCION_EMITIDA', v_ret_id);

  RETURN v_ret_id;
END;
$$;

-- Registrar factura de proveedor y generar CxP
CREATE OR REPLACE FUNCTION register_supplier_invoice(
  p_empresa_id          UUID,
  p_contacto_id         UUID,
  p_clave_acceso        VARCHAR DEFAULT NULL,
  p_numero_documento    VARCHAR DEFAULT NULL,
  p_fecha_emision       DATE DEFAULT NULL,
  p_codigo_sustento     VARCHAR DEFAULT '01',
  p_base_gravada        DECIMAL DEFAULT 0,
  p_base_0              DECIMAL DEFAULT 0,
  p_total_iva           DECIMAL DEFAULT 0,
  p_total               DECIMAL DEFAULT 0,
  p_lineas              JSONB DEFAULT '[]',
  p_orden_compra_id     UUID DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_fp_id UUID;
BEGIN
  INSERT INTO facturas_proveedor (
    empresa_id, contacto_id, clave_acceso, numero_documento,
    fecha_emision, codigo_sustento,
    base_0, base_gravada, total_iva, total,
    orden_compra_id, metodo_importacion
  ) VALUES (
    p_empresa_id, p_contacto_id, p_clave_acceso, p_numero_documento,
    COALESCE(p_fecha_emision, CURRENT_DATE), p_codigo_sustento,
    p_base_0, p_base_gravada, p_total_iva, p_total,
    p_orden_compra_id, CASE WHEN p_clave_acceso IS NOT NULL THEN 'SRI' ELSE 'MANUAL' END
  ) RETURNING id INTO v_fp_id;

  -- Insertar líneas
  INSERT INTO factura_proveedor_lineas (factura_proveedor_id, descripcion, cantidad,
    precio_unitario, precio_total_sin_iva, porcentaje_iva, valor_iva)
  SELECT v_fp_id,
    l->>'descripcion', (l->>'cantidad')::DECIMAL,
    (l->>'precio_unitario')::DECIMAL, (l->>'precio_total_sin_iva')::DECIMAL,
    (l->>'porcentaje_iva')::DECIMAL, (l->>'valor_iva')::DECIMAL
  FROM jsonb_array_elements(p_lineas) l;

  -- Crear CxP
  PERFORM module_bus.create_accounts_payable(p_empresa_id, 'FACTURA_PROVEEDOR', v_fp_id, p_total);

  -- Asiento contable: Db Gasto/Activo / Cr IVA Crédito Tributario / Cr CxP
  PERFORM module_bus.contabilidad_create_journal_entry(p_empresa_id, 'FACTURA_PROVEEDOR', v_fp_id);

  UPDATE facturas_proveedor SET estado = 'CONTABILIZADA' WHERE id = v_fp_id;

  RETURN v_fp_id;
END;
$$;

-- Convertir orden de compra a recepción de mercadería (permite recepción parcial)
CREATE OR REPLACE FUNCTION convert_po_to_receipt(
  p_orden_compra_id UUID,
  p_bodega_id UUID,
  p_lineas JSONB          -- [{producto_id, cantidad_recibida}] (permite parcial)
) RETURNS UUID AS $$
DECLARE
  v_orden RECORD;
  v_movimiento_id UUID;
  v_item JSONB;
  v_linea_oc RECORD;
  v_todas_completas BOOLEAN := true;
BEGIN
  SELECT * INTO v_orden FROM ordenes_compra WHERE id = p_orden_compra_id;

  IF v_orden.estado NOT IN ('CONFIRMADA', 'PARCIAL') THEN
    RAISE EXCEPTION 'Solo se pueden recibir ordenes confirmadas o parciales';
  END IF;

  -- Crear movimiento de inventario tipo INGRESO vinculado a la OC
  -- (usa create_inventory_movement internamente)
  v_movimiento_id := gen_random_uuid();

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_lineas)
  LOOP
    -- Buscar línea de la OC
    SELECT * INTO v_linea_oc FROM orden_compra_detalles
    WHERE orden_compra_id = p_orden_compra_id
      AND producto_id = (v_item->>'producto_id')::UUID;

    IF v_linea_oc.id IS NULL THEN
      RAISE EXCEPTION 'Producto % no encontrado en la orden de compra',
        v_item->>'producto_id';
    END IF;

    -- Validar que no se reciba más de lo pendiente
    IF (v_item->>'cantidad_recibida')::DECIMAL > (v_linea_oc.cantidad - COALESCE(v_linea_oc.cantidad_recibida, 0)) THEN
      RAISE EXCEPTION 'Cantidad recibida excede la cantidad pendiente del producto %',
        v_item->>'producto_id';
    END IF;

    -- Actualizar cantidad recibida en la línea de OC
    UPDATE orden_compra_detalles SET
      cantidad_recibida = COALESCE(cantidad_recibida, 0) + (v_item->>'cantidad_recibida')::DECIMAL,
      cantidad_pendiente = cantidad - (COALESCE(cantidad_recibida, 0) + (v_item->>'cantidad_recibida')::DECIMAL)
    WHERE id = v_linea_oc.id;

    -- Registrar ingreso de inventario (kardex + stock)
    PERFORM create_inventory_movement(
      v_orden.empresa_id, p_bodega_id, 'INGRESO',
      jsonb_build_array(jsonb_build_object(
        'producto_id', v_item->>'producto_id',
        'cantidad', v_item->>'cantidad_recibida',
        'costo_unitario', v_linea_oc.precio_unitario
      ))
    );
  END LOOP;

  -- Verificar si todas las líneas están completas
  SELECT bool_and(COALESCE(cantidad_recibida, 0) >= cantidad)
  INTO v_todas_completas
  FROM orden_compra_detalles
  WHERE orden_compra_id = p_orden_compra_id;

  -- Actualizar estado OC según cantidades
  IF v_todas_completas THEN
    UPDATE ordenes_compra SET estado = 'COMPLETA' WHERE id = p_orden_compra_id;
  ELSE
    UPDATE ordenes_compra SET estado = 'PARCIAL' WHERE id = p_orden_compra_id;
    -- Si quedan ítems pendientes, se genera backorder automático
    -- (el usuario puede crear otra recepción para los ítems faltantes)
  END IF;

  RETURN v_movimiento_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3-WAY MATCHING (OC vs Recepción vs Factura)
-- Verifica consistencia entre lo pedido, lo recibido y lo facturado por el proveedor.
-- Se ejecuta al registrar una factura de compra vinculada a una OC.
CREATE OR REPLACE FUNCTION verify_3way_match(
  p_factura_compra_id UUID
) RETURNS TABLE (
  producto_id UUID,
  cantidad_ordenada DECIMAL(18,6),
  cantidad_recibida DECIMAL(18,6),
  cantidad_facturada DECIMAL(18,6),
  precio_ordenado DECIMAL(14,6),
  precio_facturado DECIMAL(14,6),
  discrepancia_cantidad BOOLEAN,
  discrepancia_precio BOOLEAN
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    ocd.producto_id,
    ocd.cantidad AS cantidad_ordenada,
    COALESCE(ocd.cantidad_recibida, 0) AS cantidad_recibida,
    COALESCE(fd.cantidad, 0) AS cantidad_facturada,
    ocd.precio_unitario AS precio_ordenado,
    COALESCE(fd.precio_unitario, 0) AS precio_facturado,
    -- Discrepancia de cantidad: facturado > recibido
    (COALESCE(fd.cantidad, 0) > COALESCE(ocd.cantidad_recibida, 0)) AS discrepancia_cantidad,
    -- Discrepancia de precio: facturado > ordenado * 1.05 (5% tolerancia)
    (COALESCE(fd.precio_unitario, 0) > ocd.precio_unitario * 1.05) AS discrepancia_precio
  FROM orden_compra_detalles ocd
  -- Vincular con factura de compra via orden_compra_id
  JOIN facturas f ON f.id = p_factura_compra_id
  LEFT JOIN factura_detalles fd ON fd.factura_id = f.id
    AND fd.producto_id = ocd.producto_id
  WHERE ocd.orden_compra_id = (
    SELECT orden_compra_id FROM facturas WHERE id = p_factura_compra_id
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Estados del matching (para uso en UI):
-- MATCH_OK: Todo coincide (cantidad facturada <= recibida, precio dentro de tolerancia)
-- MATCH_QUANTITY: Discrepancia en cantidades (facturan más de lo recibido)
-- MATCH_PRICE: Discrepancia en precios (precio facturado excede tolerancia 5%)
-- MATCH_BOTH: Discrepancia en cantidades y precios
-- El usuario puede aprobar excepciones o rechazar la factura del proveedor
```

---

## Importación de Documentos XML del SRI

El sistema permite importar documentos electrónicos recibidos de tres formas:

| Documento recibido | Uso en PILAR |
|-------------------|--------------|
| Factura de compra | Registro como `factura_proveedor` |
| Liquidación de compra recibida | Compras a proveedores informales |
| Retención recibida de cliente | Aplicar a CxC como pago parcial |

**Método 1 — Archivo XML:** Usuario sube el `.xml` → Edge Function `import-xml` parsea → pre-llena formulario → usuario confirma.

**Método 2 — Clave de acceso (49 dígitos):** Edge Function consulta WS Autorización SRI → obtiene XML → pre-llena formulario → almacena en Storage.

**Método 3 — Escaneo de código de barras (mobile):** La cámara lee el código de barras del RIDE (que contiene la clave de acceso) → ejecuta automáticamente Método 2.

```typescript
// Edge Function POST /functions/v1/import-xml
// Retorna estructura normalizada:
{
  tipo_documento: "01",  // 01=Factura, 03=LC, 07=Retención
  emisor: { ruc, razon_social, direccion },
  receptor: { ruc, razon_social },
  fecha_emision: "2026-02-14",
  clave_acceso: "4902202601...",
  detalles: [{ descripcion, cantidad, precio, impuestos }],
  impuestos: { base_0, base_gravada, iva, ice },
  total: 115.00,
  formas_pago: [{ codigo: "01", total: 115.00 }],
  xml_url: "https://...supabase.co/storage/v1/..."
}
```

---

## Row Level Security

```sql
ALTER TABLE ordenes_compra ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON ordenes_compra
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

ALTER TABLE facturas_proveedor ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON facturas_proveedor
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

ALTER TABLE retenciones ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON retenciones
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

ALTER TABLE liquidaciones_compra ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON liquidaciones_compra
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- (aplicar patrón equivalente a recepciones, líneas y tablas relacionadas)

-- Índices de soporte
CREATE INDEX idx_oc_empresa ON ordenes_compra(empresa_id, fecha DESC);
CREATE INDEX idx_oc_proveedor ON ordenes_compra(contacto_id, fecha DESC);
CREATE INDEX idx_fp_empresa ON facturas_proveedor(empresa_id, fecha_emision DESC);
CREATE INDEX idx_ret_empresa ON retenciones(empresa_id, fecha DESC);
```

---

## Integraciones con otros Módulos

| Evento | Acción |
|--------|--------|
| OC recibida (mercadería) | `create_stock_movement` ENTRADA_COMPRA (Inventario) |
| Factura proveedor registrada | Crear `cuentas_por_pagar` (Tesorería) · Asiento Db Gasto/Cr CxP (Contabilidad) |
| Retención emitida | Asiento Db IVA/Cr CxP · Vincula en ATS (Regulatorio) |
| Pago a proveedor | Actualizar CxP · Asiento Db CxP/Cr Banco |
| OC con BOM | Consumir materiales de ensamblaje (Inventario/BOM) |
| Importación | Distribución de costos aduaneros (Costos de Aterrizaje) |

---

## Sub-módulos

| Sub-módulo | Descripción |
|------------|-------------|
| [RFQ](rfq.md) | Solicitudes de cotización a múltiples proveedores, comparación, adjudicación |
| [Scoring Proveedores](scoring-proveedores.md) | Calificación por plazo, precio, calidad y cumplimiento |
| [Acuerdos Marco](acuerdos-marco.md) | Contratos de suministro a largo plazo con precios pactados |
| [Dropshipping](dropshipping.md) | OC generada desde OV, envío directo proveedor → cliente |
| [Consignación](consignacion.md) | Mercadería en consignación: recepción, venta y liquidación |
| [Importaciones](importaciones.md) | Partidas arancelarias NANDINA, distribución de costos aduaneros |
| [Importación XML SRI](importacion-xml-sri.md) | Importar XML SRI por clave de acceso o archivo, homologación de productos |
| [Costos de Aterrizaje](costos-aterrizaje.md) | Estado provisional, costos locales vs internacionales, incoterms |

---

## Flujos Principales

### Orden de Compra → Factura Proveedor → Pago

```
┌──────────┐    ┌──────────┐    ┌──────────────┐    ┌──────────┐
│ Crear    │───>│ Aprobar  │───>│ Registrar    │───>│ Registrar│
│ Orden de │    │ Orden de │    │ Factura      │    │ Pago a   │
│ Compra   │    │ Compra   │    │ Proveedor    │    │Proveedor │
└──────────┘    └──────────┘    └──────────────┘    └────┬─────┘
                                                         │
                                ┌──────────────┐         │
                                │ Asiento      │<────────┘
                                │ Contable     │
                                │ Automatico   │
                                └──────────────┘
```

> **Integración SRI Ecuador**: Ver [`modules/extensiones/facturacion_ec/flujos-sri.md`](../../extensiones/facturacion_ec/flujos-sri.md) para el flujo de comprobantes de retención, validación de XML de proveedores e inclusión en ATS.

---

## Casos de Uso

### Actores

| Actor | Descripcion |
|-------|-------------|
| **Comprador** | Registra ordenes de compra, recibe facturas de proveedores |
| **Contador** | Emite retenciones, registra pagos, gestiona CxP |
| **Bodeguero** | Recibe mercadería y registra movimientos de inventario |
| **Gerente** | Consulta reportes y aprueba órdenes de compra |

### Casos de Uso - Compras

| ID | Caso de Uso | Actor | Prioridad |
|----|-------------|-------|-----------|
| C01 | Crear orden de compra | Comprador | Alta |
| C02 | Registrar factura de proveedor | Comprador/Contador | **Critica** |
| C03 | Emitir comprobante de retencion | Contador | **Critica** |
| C04 | Emitir liquidacion de compra | Contador | Alta |
| C05 | Registrar pago a proveedor | Contador | Alta |
| C06 | Consultar estado cuenta proveedor | Comprador | Media |
| C07 | Consultar reporte de compras | Gerente | Alta |

> **C02/C03/C04 Ecuador** (XML SRI, retenciones IVA+Renta, ATS compras): Ver [`modules/extensiones/facturacion_ec/flujos-sri.md`](../../extensiones/facturacion_ec/flujos-sri.md).
