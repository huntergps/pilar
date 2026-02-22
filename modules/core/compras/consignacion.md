# Consignación


### Descripcion Funcional

La consignacion permite gestionar mercaderia que permanece en bodega de una parte pero es propiedad de otra, hasta que se vende. PILAR soporta dos modalidades:

**a) Consignacion Recibida (Proveedor -> Empresa):**
El proveedor deja mercaderia en bodega de la empresa. La empresa vende los productos y liquida periodicamente al proveedor por lo vendido. Lo no vendido se puede devolver.

**b) Consignacion Entregada (Empresa -> Tercero):**
La empresa deja su mercaderia en un punto de venta de un tercero (ej: tienda, farmacia). El tercero reporta ventas y la empresa factura lo vendido. Lo no vendido se retorna.

**Diferencias clave con inventario regular:**
- Stock de consignacion NO forma parte del activo/inventario propio en reportes contables
- Bodegas separadas: `CONSIGNACION_RECIBIDA` y `EN_CONSIGNACION_TERCEROS`
- La valoracion de inventario excluye stock en consignacion
- La CxP/CxC solo se genera al liquidar (por lo vendido), no al recibir/entregar
- Contabilidad: cuentas de orden (al recibir), reconocimiento al vender

**Flujo Consignacion Recibida:**

```
Proveedor ofrece consignacion
  |
  v
Crear acuerdo de consignacion (proveedor, productos, precios, comision, periodo liquidacion)
  |
  v
Recibir mercaderia -> Ingreso a bodega CONSIGNACION_RECIBIDA
  |-- NO genera CxP (es propiedad del proveedor aun)
  |-- Registro en consignacion_lineas (cantidad_recibida)
  |
  v
Al vender producto en consignacion:
  |-- Egreso de bodega CONSIGNACION_RECIBIDA
  |-- Incrementar cantidad_vendida en consignacion_lineas
  |-- NO genera costo de venta aun
  |
  v
Liquidacion periodica (quincenal/mensual):
  |-- Generar OC por total vendido (precio de consignacion)
  |-- Generar CxP al proveedor
  |-- Generar asiento: reconocer costo de venta
  |-- Resetear contadores o cerrar periodo
  |
  v
Devolucion de no vendido:
  |-- Egreso de bodega CONSIGNACION_RECIBIDA
  |-- Proveedor recoge la mercaderia
  |-- Incrementar cantidad_devuelta
```

**Flujo Consignacion Entregada:**

```
Negociar con punto de venta tercero
  |
  v
Crear acuerdo de consignacion entregada (tercero, productos, precios venta, comision tercero)
  |
  v
Transferir mercaderia -> Egreso de bodega propia, ingreso a bodega EN_CONSIGNACION_TERCEROS
  |-- Producto sale del inventario disponible
  |-- Se registra en consignacion_lineas
  |
  v
Tercero reporta ventas (periodicamente):
  |-- Actualizar cantidad_vendida
  |
  v
Liquidacion periodica:
  |-- Facturar al tercero por lo vendido (precio venta - comision tercero)
  |-- Generar CxC
  |-- Reconocer ingreso
  |
  v
Retorno de no vendido:
  |-- Ingreso a bodega propia
  |-- Incrementar cantidad_devuelta
```

### Modelo de Datos SQL

```sql
-- ============================================
-- CONSIGNACION (AMPLIACION de G-INV-05)
-- Reemplaza las tablas basicas del INFORME
-- ============================================

DROP TABLE IF EXISTS consignacion_lineas;
DROP TABLE IF EXISTS consignaciones;

-- Tipos de bodega adicionales (conceptuales, se crean como bodegas regulares con tipo especial)
-- ALTER TABLE bodegas ADD COLUMN tipo_especial VARCHAR(30);
-- Valores: CONSIGNACION_RECIBIDA, EN_CONSIGNACION_TERCEROS, DROPSHIP, GARANTIAS, TALLER, etc.

CREATE TABLE consignaciones (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  numero          VARCHAR(20),                            -- CON-R-000001 / CON-E-000001
  tipo            VARCHAR(20) NOT NULL,
    -- RECIBIDA: mercaderia del proveedor en nuestra bodega
    -- ENTREGADA: nuestra mercaderia en bodega de tercero
  -- Partes
  proveedor_id    UUID REFERENCES contactos(id),          -- Solo tipo RECIBIDA
  tercero_id      UUID REFERENCES contactos(id),          -- Solo tipo ENTREGADA
  bodega_id       UUID NOT NULL REFERENCES bodegas(id),    -- Bodega de consignacion
  -- Condiciones
  comision_porcentaje DECIMAL(5,2) DEFAULT 0,             -- Comision por venta
  frecuencia_liquidacion VARCHAR(15) DEFAULT 'MENSUAL',
    -- QUINCENAL, MENSUAL, BIMENSUAL
  termino_pago_id UUID REFERENCES terminos_pago(id),
  -- Vigencia
  fecha_inicio    DATE NOT NULL,
  fecha_fin       DATE,                                    -- NULL = indefinido
  -- Estado
  estado          VARCHAR(20) DEFAULT 'ACTIVA',
    -- BORRADOR, ACTIVA, PAUSADA, LIQUIDADA, CERRADA
  -- Totales acumulados
  total_recibido  DECIMAL(14,2) DEFAULT 0,                 -- Valor total recibido/entregado
  total_vendido   DECIMAL(14,2) DEFAULT 0,                 -- Valor total vendido
  total_devuelto  DECIMAL(14,2) DEFAULT 0,                 -- Valor total devuelto
  total_liquidado DECIMAL(14,2) DEFAULT 0,                 -- Valor total liquidado (pagado/cobrado)
  total_pendiente_liquidar DECIMAL(14,2) DEFAULT 0,        -- Vendido - Liquidado
  -- Metadata
  notas           TEXT,
  documento_url   TEXT,                                    -- Contrato de consignacion
  creado_por      UUID REFERENCES auth.users(id),
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now()
);

-- Lineas de consignacion (productos con cantidades)
CREATE TABLE consignacion_lineas (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  consignacion_id UUID NOT NULL REFERENCES consignaciones(id) ON DELETE CASCADE,
  producto_id     UUID NOT NULL REFERENCES productos(id),
  presentacion_id UUID REFERENCES producto_presentaciones(id),
  -- Precio
  costo_unitario  DECIMAL(14,6) NOT NULL,                 -- Precio de costo/compra
  precio_venta    DECIMAL(14,6),                          -- Precio de venta sugerido (tipo ENTREGADA)
  -- Cantidades
  cantidad_recibida   DECIMAL(18,6) NOT NULL DEFAULT 0,   -- Total recibido/entregado
  cantidad_vendida    DECIMAL(18,6) DEFAULT 0,
  cantidad_devuelta   DECIMAL(18,6) DEFAULT 0,
  cantidad_disponible DECIMAL(18,6) DEFAULT 0,            -- recibida - vendida - devuelta
  -- Valores
  valor_recibido  DECIMAL(14,2) DEFAULT 0,
  valor_vendido   DECIMAL(14,2) DEFAULT 0,
  valor_devuelto  DECIMAL(14,2) DEFAULT 0,
  -- Metadata
  orden           INTEGER DEFAULT 0,
  UNIQUE(consignacion_id, producto_id)
);

-- Movimientos de consignacion (entradas, salidas por venta, devoluciones)
CREATE TABLE consignacion_movimientos (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  consignacion_id UUID NOT NULL REFERENCES consignaciones(id),
  linea_id        UUID NOT NULL REFERENCES consignacion_lineas(id),
  tipo            VARCHAR(20) NOT NULL,
    -- RECEPCION: ingreso de mercaderia en consignacion
    -- VENTA: salida por venta al cliente final
    -- DEVOLUCION: retorno al proveedor/regreso del tercero
    -- AJUSTE: ajuste por merma, dano, etc.
  cantidad        DECIMAL(18,6) NOT NULL,
  costo_unitario  DECIMAL(14,6) NOT NULL,
  valor_total     DECIMAL(14,2) NOT NULL,
  -- Referencias
  factura_id      UUID REFERENCES facturas(id),           -- Factura de venta al cliente (tipo VENTA)
  kardex_id       UUID REFERENCES kardex(id),             -- Movimiento de inventario asociado
  -- Metadata
  fecha           TIMESTAMPTZ DEFAULT now(),
  usuario_id      UUID REFERENCES auth.users(id),
  notas           TEXT
);

-- Liquidaciones de consignacion
CREATE TABLE consignacion_liquidaciones (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  consignacion_id UUID NOT NULL REFERENCES consignaciones(id),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  numero          VARCHAR(20),                             -- LIQ-000001
  fecha           DATE NOT NULL DEFAULT CURRENT_DATE,
  periodo_desde   DATE NOT NULL,
  periodo_hasta   DATE NOT NULL,
  -- Totales del periodo
  total_vendido   DECIMAL(14,2) NOT NULL,
  comision        DECIMAL(14,2) DEFAULT 0,
  total_a_pagar   DECIMAL(14,2) NOT NULL,                 -- total_vendido - comision (tipo RECIBIDA)
  total_a_cobrar  DECIMAL(14,2),                          -- Para tipo ENTREGADA
  -- Documentos generados
  orden_compra_id UUID REFERENCES ordenes_compra(id),     -- OC generada (tipo RECIBIDA)
  factura_id      UUID REFERENCES facturas(id),           -- Factura generada (tipo ENTREGADA)
  cxp_id          UUID REFERENCES cuentas_por_pagar(id),
  cxc_id          UUID REFERENCES cuentas_por_cobrar(id),
  asiento_id      UUID REFERENCES asientos_contables(id),
  -- Estado
  estado          VARCHAR(20) DEFAULT 'BORRADOR',
    -- BORRADOR, CONFIRMADA, PAGADA/COBRADA, ANULADA
  aprobado_por    UUID REFERENCES auth.users(id),
  notas           TEXT,
  created_at      TIMESTAMPTZ DEFAULT now()
);

-- Detalle de liquidacion (productos liquidados)
CREATE TABLE consignacion_liquidacion_lineas (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  liquidacion_id  UUID NOT NULL REFERENCES consignacion_liquidaciones(id) ON DELETE CASCADE,
  producto_id     UUID NOT NULL REFERENCES productos(id),
  cantidad_vendida DECIMAL(18,6) NOT NULL,
  costo_unitario  DECIMAL(14,6) NOT NULL,
  subtotal        DECIMAL(14,2) NOT NULL,
  comision_linea  DECIMAL(14,2) DEFAULT 0
);

-- Indices
CREATE INDEX idx_consignaciones_empresa ON consignaciones(empresa_id, estado);
CREATE INDEX idx_consignaciones_proveedor ON consignaciones(proveedor_id) WHERE tipo = 'RECIBIDA';
CREATE INDEX idx_consignaciones_tercero ON consignaciones(tercero_id) WHERE tipo = 'ENTREGADA';
CREATE INDEX idx_consignacion_lineas ON consignacion_lineas(consignacion_id);
CREATE INDEX idx_consignacion_movimientos ON consignacion_movimientos(consignacion_id, tipo);
CREATE INDEX idx_consignacion_liquidaciones ON consignacion_liquidaciones(consignacion_id, estado);

-- RLS
ALTER TABLE consignaciones ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON consignaciones FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

ALTER TABLE consignacion_lineas ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_via_consignacion" ON consignacion_lineas FOR ALL TO authenticated
  USING (consignacion_id IN (SELECT id FROM consignaciones WHERE empresa_id = (SELECT private.get_empresa_id())));

ALTER TABLE consignacion_movimientos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_via_consignacion" ON consignacion_movimientos FOR ALL TO authenticated
  USING (consignacion_id IN (SELECT id FROM consignaciones WHERE empresa_id = (SELECT private.get_empresa_id())));

ALTER TABLE consignacion_liquidaciones ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON consignacion_liquidaciones FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

ALTER TABLE consignacion_liquidacion_lineas ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_via_liquidacion" ON consignacion_liquidacion_lineas FOR ALL TO authenticated
  USING (liquidacion_id IN (
    SELECT id FROM consignacion_liquidaciones WHERE empresa_id = (SELECT private.get_empresa_id())
  ));
```

### Funciones PostgreSQL Principales

```sql
-- ============================================
-- RECIBIR MERCADERIA EN CONSIGNACION
-- ============================================
CREATE OR REPLACE FUNCTION receive_consignment(
  p_consignacion_id UUID,
  p_lineas JSONB  -- [{producto_id, cantidad, costo_unitario}]
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_con RECORD;
  v_linea JSONB;
  v_linea_id UUID;
  v_valor DECIMAL(14,2);
  v_total_valor DECIMAL(14,2) := 0;
BEGIN
  SELECT * INTO v_con FROM consignaciones WHERE id = p_consignacion_id;
  IF v_con.estado != 'ACTIVA' THEN
    RAISE EXCEPTION 'La consignacion debe estar ACTIVA para recibir mercaderia';
  END IF;

  FOR v_linea IN SELECT * FROM jsonb_array_elements(p_lineas)
  LOOP
    v_valor := ROUND((v_linea->>'cantidad')::DECIMAL * (v_linea->>'costo_unitario')::DECIMAL, 2);

    -- Insertar o actualizar linea
    INSERT INTO consignacion_lineas (
      consignacion_id, producto_id, costo_unitario,
      cantidad_recibida, cantidad_disponible, valor_recibido
    ) VALUES (
      p_consignacion_id,
      (v_linea->>'producto_id')::UUID,
      (v_linea->>'costo_unitario')::DECIMAL,
      (v_linea->>'cantidad')::DECIMAL,
      (v_linea->>'cantidad')::DECIMAL,
      v_valor
    )
    ON CONFLICT (consignacion_id, producto_id)
    DO UPDATE SET
      cantidad_recibida = consignacion_lineas.cantidad_recibida + (v_linea->>'cantidad')::DECIMAL,
      cantidad_disponible = consignacion_lineas.cantidad_disponible + (v_linea->>'cantidad')::DECIMAL,
      valor_recibido = consignacion_lineas.valor_recibido + v_valor
    RETURNING id INTO v_linea_id;

    -- Registrar movimiento
    INSERT INTO consignacion_movimientos (
      consignacion_id, linea_id, tipo,
      cantidad, costo_unitario, valor_total
    ) VALUES (
      p_consignacion_id, v_linea_id, 'RECEPCION',
      (v_linea->>'cantidad')::DECIMAL,
      (v_linea->>'costo_unitario')::DECIMAL,
      v_valor
    );

    -- Crear movimiento de inventario en bodega de consignacion (via Module Bus)
    PERFORM module_bus.request_inventory_movement(
      p_empresa_id := v_con.empresa_id,
      p_tipo := 'INGRESO',
      p_productos := jsonb_build_array(jsonb_build_object(
        'producto_id', (v_linea->>'producto_id'),
        'cantidad', (v_linea->>'cantidad')::DECIMAL,
        'costo_unitario', (v_linea->>'costo_unitario')::DECIMAL,
        'bodega_id', v_con.bodega_id
      )),
      p_origen := 'CONSIGNACION',
      p_referencia_id := p_consignacion_id
    );

    v_total_valor := v_total_valor + v_valor;
  END LOOP;

  -- Actualizar totales de la consignacion
  UPDATE consignaciones SET
    total_recibido = total_recibido + v_total_valor,
    updated_at = now()
  WHERE id = p_consignacion_id;

  RETURN jsonb_build_object(
    'consignacion_id', p_consignacion_id,
    'valor_recibido', v_total_valor,
    'lineas_procesadas', jsonb_array_length(p_lineas)
  );
END;
$$;

-- ============================================
-- REGISTRAR VENTA DE PRODUCTO EN CONSIGNACION
-- Llamada automaticamente al vender un producto de bodega CONSIGNACION
-- ============================================
CREATE OR REPLACE FUNCTION register_consignment_sale(
  p_consignacion_id UUID,
  p_producto_id UUID,
  p_cantidad DECIMAL,
  p_factura_id UUID DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_linea RECORD;
  v_valor DECIMAL(14,2);
BEGIN
  SELECT * INTO v_linea
  FROM consignacion_lineas
  WHERE consignacion_id = p_consignacion_id AND producto_id = p_producto_id;

  IF v_linea IS NULL THEN
    RAISE EXCEPTION 'Producto no encontrado en esta consignacion';
  END IF;

  IF p_cantidad > v_linea.cantidad_disponible THEN
    RAISE EXCEPTION 'Cantidad % excede disponible % en consignacion',
      p_cantidad, v_linea.cantidad_disponible;
  END IF;

  v_valor := ROUND(p_cantidad * v_linea.costo_unitario, 2);

  -- Actualizar linea
  UPDATE consignacion_lineas SET
    cantidad_vendida = cantidad_vendida + p_cantidad,
    cantidad_disponible = cantidad_disponible - p_cantidad,
    valor_vendido = valor_vendido + v_valor
  WHERE id = v_linea.id;

  -- Registrar movimiento
  INSERT INTO consignacion_movimientos (
    consignacion_id, linea_id, tipo,
    cantidad, costo_unitario, valor_total,
    factura_id
  ) VALUES (
    p_consignacion_id, v_linea.id, 'VENTA',
    p_cantidad, v_linea.costo_unitario, v_valor,
    p_factura_id
  );

  -- Actualizar totales
  UPDATE consignaciones SET
    total_vendido = total_vendido + v_valor,
    total_pendiente_liquidar = total_vendido + v_valor - total_liquidado,
    updated_at = now()
  WHERE id = p_consignacion_id;
END;
$$;

-- ============================================
-- GENERAR LIQUIDACION DE CONSIGNACION
-- ============================================
CREATE OR REPLACE FUNCTION generate_consignment_liquidation(
  p_consignacion_id UUID,
  p_periodo_desde DATE,
  p_periodo_hasta DATE
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_con RECORD;
  v_liq_id UUID;
  v_total_vendido DECIMAL(14,2) := 0;
  v_comision DECIMAL(14,2) := 0;
  v_total_pagar DECIMAL(14,2);
  v_mov RECORD;
  v_num VARCHAR(20);
BEGIN
  SELECT * INTO v_con FROM consignaciones WHERE id = p_consignacion_id;

  -- Generar numero
  SELECT 'LIQ-' || LPAD((COALESCE(MAX(CAST(SUBSTRING(numero FROM 5) AS INTEGER)), 0) + 1)::TEXT, 6, '0')
  INTO v_num FROM consignacion_liquidaciones WHERE empresa_id = v_con.empresa_id;

  -- Calcular vendido en el periodo
  SELECT COALESCE(SUM(valor_total), 0)
  INTO v_total_vendido
  FROM consignacion_movimientos
  WHERE consignacion_id = p_consignacion_id
    AND tipo = 'VENTA'
    AND fecha BETWEEN p_periodo_desde AND (p_periodo_hasta + INTERVAL '1 day');

  IF v_total_vendido = 0 THEN
    RAISE EXCEPTION 'No hay ventas en el periodo para liquidar';
  END IF;

  v_comision := ROUND(v_total_vendido * v_con.comision_porcentaje / 100, 2);
  v_total_pagar := v_total_vendido - v_comision;

  -- Crear liquidacion
  INSERT INTO consignacion_liquidaciones (
    consignacion_id, empresa_id, numero, fecha,
    periodo_desde, periodo_hasta,
    total_vendido, comision, total_a_pagar,
    estado
  ) VALUES (
    p_consignacion_id, v_con.empresa_id, v_num, CURRENT_DATE,
    p_periodo_desde, p_periodo_hasta,
    v_total_vendido, v_comision, v_total_pagar,
    'BORRADOR'
  )
  RETURNING id INTO v_liq_id;

  -- Detalle por producto
  INSERT INTO consignacion_liquidacion_lineas (
    liquidacion_id, producto_id, cantidad_vendida,
    costo_unitario, subtotal, comision_linea
  )
  SELECT
    v_liq_id,
    cl.producto_id,
    SUM(cm.cantidad),
    cl.costo_unitario,
    ROUND(SUM(cm.valor_total), 2),
    ROUND(SUM(cm.valor_total) * v_con.comision_porcentaje / 100, 2)
  FROM consignacion_movimientos cm
  JOIN consignacion_lineas cl ON cl.id = cm.linea_id
  WHERE cm.consignacion_id = p_consignacion_id
    AND cm.tipo = 'VENTA'
    AND cm.fecha BETWEEN p_periodo_desde AND (p_periodo_hasta + INTERVAL '1 day')
  GROUP BY cl.producto_id, cl.costo_unitario;

  -- Actualizar total liquidado en la consignacion
  UPDATE consignaciones SET
    total_liquidado = total_liquidado + v_total_pagar,
    total_pendiente_liquidar = total_vendido - (total_liquidado + v_total_pagar),
    updated_at = now()
  WHERE id = p_consignacion_id;

  RETURN v_liq_id;
END;
$$;

-- ============================================
-- CONFIRMAR LIQUIDACION (genera OC/Factura + CxP/CxC + asiento)
-- ============================================
CREATE OR REPLACE FUNCTION confirm_consignment_liquidation(
  p_liquidacion_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_liq RECORD;
  v_con RECORD;
  v_oc_id UUID;
  v_cxp_id UUID;
  v_asiento JSONB;
BEGIN
  SELECT * INTO v_liq FROM consignacion_liquidaciones WHERE id = p_liquidacion_id;
  SELECT * INTO v_con FROM consignaciones WHERE id = v_liq.consignacion_id;

  IF v_liq.estado != 'BORRADOR' THEN
    RAISE EXCEPTION 'La liquidacion debe estar en BORRADOR para confirmar';
  END IF;

  IF v_con.tipo = 'RECIBIDA' THEN
    -- Generar OC al proveedor por lo vendido
    v_oc_id := (module_bus.request_purchase_order(
      p_empresa_id := v_con.empresa_id,
      p_proveedor_id := v_con.proveedor_id,
      p_productos := (
        SELECT jsonb_agg(jsonb_build_object(
          'producto_id', producto_id,
          'cantidad', cantidad_vendida,
          'precio_unitario', costo_unitario
        ))
        FROM consignacion_liquidacion_lineas WHERE liquidacion_id = p_liquidacion_id
      ),
      p_origen := 'CONSIGNACION',
      p_referencia_id := p_liquidacion_id
    ))->>'orden_compra_id')::UUID;

    -- Generar CxP
    v_cxp_id := (module_bus.create_payable(
      p_empresa_id := v_con.empresa_id,
      p_contacto_id := v_con.proveedor_id,
      p_monto := v_liq.total_a_pagar,
      p_fecha := v_liq.fecha,
      p_descripcion := 'Liquidacion consignacion ' || v_liq.numero,
      p_tipo_origen := 'LIQUIDACION'
    ))->>'cxp_id')::UUID;

    UPDATE consignacion_liquidaciones SET
      orden_compra_id = v_oc_id,
      cxp_id = v_cxp_id,
      estado = 'CONFIRMADA'
    WHERE id = p_liquidacion_id;

  ELSIF v_con.tipo = 'ENTREGADA' THEN
    -- Para consignacion entregada: generar factura al tercero
    -- (Se implementaria usando module_bus.request_invoice)
    UPDATE consignacion_liquidaciones SET
      total_a_cobrar = v_liq.total_vendido,
      estado = 'CONFIRMADA'
    WHERE id = p_liquidacion_id;
  END IF;

  -- Asiento contable via Module Bus
  PERFORM module_bus.create_journal_entry(
    p_empresa_id := v_con.empresa_id,
    p_fecha := v_liq.fecha,
    p_descripcion := 'Liquidacion consignacion ' || v_liq.numero,
    p_tipo := 'AUTOMATICO',
    p_documento_tipo := 'CONSIGNACION',
    p_documento_id := p_liquidacion_id
  );

  RETURN jsonb_build_object(
    'liquidacion_id', p_liquidacion_id,
    'estado', 'CONFIRMADA',
    'oc_id', v_oc_id,
    'cxp_id', v_cxp_id
  );
END;
$$;

-- ============================================
-- DEVOLVER MERCADERIA DE CONSIGNACION
-- ============================================
CREATE OR REPLACE FUNCTION return_consignment_items(
  p_consignacion_id UUID,
  p_lineas JSONB  -- [{producto_id, cantidad}]
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_con RECORD;
  v_linea JSONB;
  v_cl RECORD;
  v_valor DECIMAL(14,2);
  v_total DECIMAL(14,2) := 0;
BEGIN
  SELECT * INTO v_con FROM consignaciones WHERE id = p_consignacion_id;

  FOR v_linea IN SELECT * FROM jsonb_array_elements(p_lineas)
  LOOP
    SELECT * INTO v_cl
    FROM consignacion_lineas
    WHERE consignacion_id = p_consignacion_id
      AND producto_id = (v_linea->>'producto_id')::UUID;

    IF (v_linea->>'cantidad')::DECIMAL > v_cl.cantidad_disponible THEN
      RAISE EXCEPTION 'Cantidad a devolver excede disponible para producto %', v_cl.producto_id;
    END IF;

    v_valor := ROUND((v_linea->>'cantidad')::DECIMAL * v_cl.costo_unitario, 2);

    UPDATE consignacion_lineas SET
      cantidad_devuelta = cantidad_devuelta + (v_linea->>'cantidad')::DECIMAL,
      cantidad_disponible = cantidad_disponible - (v_linea->>'cantidad')::DECIMAL,
      valor_devuelto = valor_devuelto + v_valor
    WHERE id = v_cl.id;

    INSERT INTO consignacion_movimientos (
      consignacion_id, linea_id, tipo,
      cantidad, costo_unitario, valor_total
    ) VALUES (
      p_consignacion_id, v_cl.id, 'DEVOLUCION',
      (v_linea->>'cantidad')::DECIMAL, v_cl.costo_unitario, v_valor
    );

    -- Egreso de bodega consignacion
    PERFORM module_bus.request_inventory_movement(
      p_empresa_id := v_con.empresa_id,
      p_tipo := 'EGRESO',
      p_productos := jsonb_build_array(jsonb_build_object(
        'producto_id', (v_linea->>'producto_id'),
        'cantidad', (v_linea->>'cantidad')::DECIMAL,
        'bodega_id', v_con.bodega_id
      )),
      p_origen := 'CONSIGNACION_DEVOLUCION',
      p_referencia_id := p_consignacion_id
    );

    v_total := v_total + v_valor;
  END LOOP;

  UPDATE consignaciones SET
    total_devuelto = total_devuelto + v_total,
    updated_at = now()
  WHERE id = p_consignacion_id;

  RETURN jsonb_build_object('valor_devuelto', v_total);
END;
$$;
```

### Triggers

```sql
-- Recalcular cantidad_disponible automaticamente
CREATE OR REPLACE FUNCTION tr_consignacion_linea_disponible()
RETURNS TRIGGER AS $$
BEGIN
  NEW.cantidad_disponible := NEW.cantidad_recibida - NEW.cantidad_vendida - NEW.cantidad_devuelta;
  IF NEW.cantidad_disponible < 0 THEN
    RAISE EXCEPTION 'Cantidad disponible no puede ser negativa';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tr_calc_disponible_consignacion
  BEFORE UPDATE OF cantidad_recibida, cantidad_vendida, cantidad_devuelta ON consignacion_lineas
  FOR EACH ROW EXECUTE FUNCTION tr_consignacion_linea_disponible();

-- Recalcular total_pendiente_liquidar
CREATE OR REPLACE FUNCTION tr_consignacion_pendiente()
RETURNS TRIGGER AS $$
BEGIN
  NEW.total_pendiente_liquidar := NEW.total_vendido - NEW.total_liquidado;
  NEW.updated_at := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tr_calc_pendiente_consignacion
  BEFORE UPDATE OF total_vendido, total_liquidado ON consignaciones
  FOR EACH ROW EXECUTE FUNCTION tr_consignacion_pendiente();
```

### Vistas para Reportes

```sql
-- Vista: Consignaciones activas con saldos
CREATE OR REPLACE VIEW v_consignaciones_activas AS
SELECT
  c.id,
  c.empresa_id,
  c.numero,
  c.tipo,
  CASE c.tipo
    WHEN 'RECIBIDA' THEN cp.razon_social
    WHEN 'ENTREGADA' THEN ct.razon_social
  END AS contraparte,
  c.proveedor_id,
  c.tercero_id,
  b.nombre AS bodega,
  c.fecha_inicio,
  c.estado,
  c.total_recibido,
  c.total_vendido,
  c.total_devuelto,
  c.total_liquidado,
  c.total_pendiente_liquidar,
  c.comision_porcentaje,
  c.frecuencia_liquidacion,
  (SELECT COUNT(*) FROM consignacion_lineas cl
   WHERE cl.consignacion_id = c.id AND cl.cantidad_disponible > 0) AS productos_disponibles,
  (SELECT COALESCE(SUM(cl.cantidad_disponible * cl.costo_unitario), 0)
   FROM consignacion_lineas cl
   WHERE cl.consignacion_id = c.id) AS valor_en_consignacion,
  c.created_at
FROM consignaciones c
LEFT JOIN contactos cp ON cp.id = c.proveedor_id
LEFT JOIN contactos ct ON ct.id = c.tercero_id
JOIN bodegas b ON b.id = c.bodega_id;

-- Vista: Productos en consignacion con rotacion
CREATE OR REPLACE VIEW v_productos_consignacion AS
SELECT
  cl.consignacion_id,
  c.empresa_id,
  c.tipo,
  c.numero AS consignacion_numero,
  cl.producto_id,
  p.descripcion AS producto,
  cl.costo_unitario,
  cl.cantidad_recibida,
  cl.cantidad_vendida,
  cl.cantidad_devuelta,
  cl.cantidad_disponible,
  ROUND(cl.cantidad_disponible * cl.costo_unitario, 2) AS valor_disponible,
  CASE WHEN cl.cantidad_recibida > 0
    THEN ROUND(cl.cantidad_vendida / cl.cantidad_recibida * 100, 2)
    ELSE 0 END AS rotacion_pct,
  -- Antiguedad: dias desde la primera recepcion
  (SELECT CURRENT_DATE - MIN(cm.fecha::DATE)
   FROM consignacion_movimientos cm
   WHERE cm.linea_id = cl.id AND cm.tipo = 'RECEPCION') AS dias_en_consignacion
FROM consignacion_lineas cl
JOIN consignaciones c ON c.id = cl.consignacion_id
JOIN productos p ON p.id = cl.producto_id
WHERE cl.cantidad_disponible > 0;

-- Reporte: Liquidaciones pendientes
CREATE OR REPLACE VIEW v_consignacion_liquidaciones_pendientes AS
SELECT
  c.id AS consignacion_id,
  c.empresa_id,
  c.numero,
  c.tipo,
  CASE c.tipo
    WHEN 'RECIBIDA' THEN cp.razon_social
    WHEN 'ENTREGADA' THEN ct.razon_social
  END AS contraparte,
  c.total_pendiente_liquidar,
  c.frecuencia_liquidacion,
  COALESCE(
    (SELECT MAX(periodo_hasta) FROM consignacion_liquidaciones
     WHERE consignacion_id = c.id AND estado != 'ANULADA'),
    c.fecha_inicio
  ) AS ultimo_periodo_liquidado
FROM consignaciones c
LEFT JOIN contactos cp ON cp.id = c.proveedor_id
LEFT JOIN contactos ct ON ct.id = c.tercero_id
WHERE c.estado = 'ACTIVA' AND c.total_pendiente_liquidar > 0;
```

### Integracion Module Service Bus

```sql
-- Gateway: Registrar venta de producto en consignacion
CREATE OR REPLACE FUNCTION module_bus.register_consignment_sale(
  p_empresa_id UUID,
  p_producto_id UUID,
  p_cantidad DECIMAL,
  p_bodega_id UUID,
  p_factura_id UUID DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_con RECORD;
BEGIN
  -- Buscar consignacion activa para este producto en esta bodega
  SELECT c.id INTO v_con
  FROM consignaciones c
  JOIN consignacion_lineas cl ON cl.consignacion_id = c.id
  WHERE c.empresa_id = p_empresa_id
    AND c.bodega_id = p_bodega_id
    AND c.estado = 'ACTIVA'
    AND cl.producto_id = p_producto_id
    AND cl.cantidad_disponible >= p_cantidad
  LIMIT 1;

  IF v_con IS NULL THEN
    RETURN jsonb_build_object('executed', false, 'reason', 'No hay consignacion activa para este producto');
  END IF;

  PERFORM register_consignment_sale(v_con.id, p_producto_id, p_cantidad, p_factura_id);
  RETURN jsonb_build_object('executed', true, 'consignacion_id', v_con.id);
END;
$$;
```

### RLS Policies

| Tabla | Policy | Tipo |
|-------|--------|------|
| `consignaciones` | `tenant_isolation` | Directa: `empresa_id` |
| `consignacion_lineas` | `tenant_via_consignacion` | Via JOIN |
| `consignacion_movimientos` | `tenant_via_consignacion` | Via JOIN |
| `consignacion_liquidaciones` | `tenant_isolation` | Directa: `empresa_id` |
| `consignacion_liquidacion_lineas` | `tenant_via_liquidacion` | Via JOIN |

### Flujo UI/UX

```
PANTALLA LISTADO CONSIGNACIONES:
  SfDataGrid: Numero | Tipo | Contraparte | Bodega | Estado | Valor en Consig. | Pend. Liquidar
  Tabs: [Recibidas] [Entregadas] [Todas]
  Filtros: estado, proveedor/tercero, rango fechas
  Badge alerta: consignaciones con liquidacion pendiente
  Boton [+ Nueva Consignacion]

PANTALLA DETALLE CONSIGNACION:
  Tab 1 - General:
    - Tipo (RECIBIDA/ENTREGADA), Contraparte, Bodega
    - Comision %, Frecuencia liquidacion, Vigencia
    - Cards resumen: Total Recibido | Vendido | Devuelto | Pendiente Liquidar

  Tab 2 - Productos:
    - SfDataGrid: Producto | Costo | Recibida | Vendida | Devuelta | Disponible | Rotacion%
    - ProgressBar visual por producto (recibida vs vendida)
    - Boton [Recibir mercaderia] -> formulario con productos y cantidades
    - Boton [Devolver mercaderia] -> seleccionar productos disponibles

  Tab 3 - Movimientos:
    - SfDataGrid cronologico: Fecha | Tipo | Producto | Cantidad | Valor | Referencia
    - Filtros: tipo movimiento, rango fechas

  Tab 4 - Liquidaciones:
    - SfDataGrid: Numero | Periodo | Total Vendido | Comision | A Pagar | Estado | OC#
    - Boton [Generar liquidacion] -> seleccionar periodo
    - Boton [Confirmar] -> genera OC + CxP

  Tab 5 - Reporte:
    - Grafico de rotacion por producto (barras)
    - Grafico de valor en consignacion vs vendido (pie)
    - Tabla de antiguedad de productos no vendidos

RESPONSIVE:
  - COMPACT: cards resumen + lista de productos scrollable
  - MEDIUM: tabs horizontales + tabla compacta
  - EXPANDED/LARGE: dashboard completo con graficos + tabla
```

---

## Resumen de Tablas Nuevas

| # | Tabla | Seccion | Tipo |
|---|-------|---------|------|
| 1 | `solicitud_cotizacion_productos` | 24.1 RFQ | Nueva |
| 2 | `solicitud_cotizacion_adjudicaciones` | 24.1 RFQ | Nueva |
| 3 | `evaluacion_criterios` | 24.2 Scoring | Nueva |
| 4 | `evaluacion_config` | 24.2 Scoring | Nueva |
| 5 | `evaluaciones_proveedor` | 24.2 Scoring | Reemplaza basica |
| 6 | `evaluacion_manual_detalle` | 24.2 Scoring | Nueva |
| 7 | `inspecciones_calidad` | 24.2 Scoring | Nueva |
| 8 | `acuerdos_marco` | 24.3 Acuerdos | Reemplaza basica |
| 9 | `acuerdo_marco_lineas` | 24.3 Acuerdos | Nueva |
| 10 | `acuerdo_marco_liberaciones` | 24.3 Acuerdos | Nueva |
| 11 | `acuerdo_marco_penalidades` | 24.3 Acuerdos | Nueva |
| 12 | `dropship_config` | 24.4 Dropship | Reemplaza basica |
| 13 | `ordenes_dropship` | 24.4 Dropship | Nueva |
| 14 | `orden_dropship_lineas` | 24.4 Dropship | Nueva |
| 15 | `consignaciones` | 24.5 Consignacion | Reemplaza basica |
| 16 | `consignacion_lineas` | 24.5 Consignacion | Reemplaza basica |
| 17 | `consignacion_movimientos` | 24.5 Consignacion | Nueva |
| 18 | `consignacion_liquidaciones` | 24.5 Consignacion | Nueva |
| 19 | `consignacion_liquidacion_lineas` | 24.5 Consignacion | Nueva |

## Resumen de Funciones RPC

| # | Funcion | Seccion | Tipo |
|---|---------|---------|------|
| 1 | `send_rfq` | 24.1 | Enviar RFQ a proveedores |
| 2 | `register_rfq_response` | 24.1 | Registrar respuesta proveedor |
| 3 | `compare_rfq_responses` | 24.1 | Cuadro comparativo (reemplaza) |
| 4 | `adjudicate_rfq` | 24.1 | Adjudicar total/parcial |
| 5 | `generate_po_from_rfq` | 24.1 | Generar OC desde RFQ |
| 6 | `suggest_rfq_adjudication` | 24.1 | Auto-sugerencia |
| 7 | `calculate_supplier_score` | 24.2 | Score individual |
| 8 | `calculate_all_supplier_scores` | 24.2 | Score masivo (cron) |
| 9 | `register_manual_evaluation` | 24.2 | Evaluacion manual |
| 10 | `calculate_composite_score` | 24.2 | Score compuesto |
| 11 | `find_active_agreement` | 24.3 | Buscar acuerdo vigente |
| 12 | `register_agreement_release` | 24.3 | Consumir acuerdo |
| 13 | `check_agreement_status` | 24.3 | Verificar estado |
| 14 | `renew_agreement` | 24.3 | Renovar acuerdo |
| 15 | `report_agreement_savings` | 24.3 | Reporte ahorro |
| 16 | `process_dropship_items` | 24.4 | Procesar dropship |
| 17 | `create_dropship_po` | 24.4 | Crear OC dropship |
| 18 | `update_dropship_status` | 24.4 | Actualizar estado |
| 19 | `receive_consignment` | 24.5 | Recibir consignacion |
| 20 | `register_consignment_sale` | 24.5 | Registrar venta |
| 21 | `generate_consignment_liquidation` | 24.5 | Generar liquidacion |
| 22 | `confirm_consignment_liquidation` | 24.5 | Confirmar liquidacion |
| 23 | `return_consignment_items` | 24.5 | Devolver mercaderia |

## Resumen de Servicios Module Bus

| # | Servicio | Seccion | Modulo Core | Si inactivo |
|---|----------|---------|-------------|-------------|
| 1 | `module_bus.request_rfq` | 24.1 | Compras | NO-OP |
| 2 | `module_bus.evaluate_supplier` | 24.2 | Compras | NO-OP |
| 3 | `module_bus.get_supplier_score` | 24.2 | Compras | retorna NULL |
| 4 | `module_bus.find_purchase_agreement` | 24.3 | Compras | NO-OP, found=false |
| 5 | `module_bus.process_dropship` | 24.4 | Compras | NO-OP |
| 6 | `module_bus.register_consignment_sale` | 24.5 | Compras | NO-OP |

## Ampliacion del Modulo de Compras (seccion 9.2 del INFORME)

```
compras/
  ├── proveedores/
  │     ├── listado/
  │     ├── ficha/
  │     └── evaluacion/            # NUEVO: scoring y evaluacion
  │           ├── ranking/          # Ranking de proveedores (SfDataGrid)
  │           ├── detalle/          # Detalle evaluacion con graficos
  │           ├── manual/           # Formulario evaluacion manual
  │           ├── configuracion/    # Criterios + pesos + umbrales
  │           └── inspecciones/     # Inspecciones de calidad
  ├── ordenes-compra/
  ├── facturas-recibidas/
  ├── liquidaciones/
  ├── retenciones/
  ├── cuentas-pagar/
  ├── pagos/
  ├── solicitudes-cotizacion/       # NUEVO (ampliado de existente)
  │     ├── listado/
  │     ├── crear/
  │     ├── comparativo/            # Cuadro comparativo lado a lado
  │     └── adjudicar/              # Adjudicacion total/parcial
  ├── acuerdos-marco/               # NUEVO
  │     ├── listado/
  │     ├── crear/
  │     ├── detalle/                # Con liberaciones y penalidades
  │     └── reporte-ahorro/
  ├── dropshipping/                 # NUEVO
  │     ├── configuracion/          # Productos y proveedores dropship
  │     ├── ordenes/                # Tracking de envios dropship
  │     └── margenes/               # Reporte de margenes
  ├── consignacion/                 # NUEVO
  │     ├── listado/
  │     ├── crear/
  │     ├── detalle/                # Productos, movimientos, liquidaciones
  │     ├── recibir/                # Formulario recepcion
  │     ├── devolver/               # Formulario devolucion
  │     └── liquidar/               # Generar y confirmar liquidaciones
  └── reportes/
        ├── compras-periodo/
        ├── cartera-por-pagar/
        ├── cxp-vs-pagos/
        ├── retenciones-emitidas/
        ├── ranking-proveedores/     # NUEVO
        ├── ahorro-acuerdos/         # NUEVO
        ├── dropship-margenes/       # NUEVO
        └── consignacion-rotacion/   # NUEVO
```


