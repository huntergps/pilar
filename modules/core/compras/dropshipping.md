# Dropshipping


### Descripcion Funcional

El dropshipping permite vender productos que no se almacenan en bodega propia. Cuando un cliente compra un producto marcado como dropship, el sistema genera automaticamente una orden de compra al proveedor con la direccion de entrega del cliente. El proveedor envia directamente al cliente, eliminando la necesidad de inventario propio para esos productos.

**Caracteristicas principales:**

1. **Configuracion por producto-proveedor:** Un producto puede ser dropship con un proveedor especifico (tabla `dropship_config`). Un producto puede tener multiples proveedores dropship, con uno preferido.

2. **Deteccion automatica:** Al confirmar una orden de venta o factura, el sistema detecta productos configurados como dropship y genera la OC automaticamente.

3. **Direccion del cliente:** La OC de dropship incluye la direccion de entrega del cliente (de `contacto_direcciones`), no la de la empresa.

4. **Sin movimiento de inventario propio:** El producto nunca ingresa ni sale de bodegas propias. No genera kardex ni afecta stock. La bodega virtual `DROPSHIP` se usa solo como referencia contable.

5. **Tracking de estado:** Se rastrea el progreso desde la OC hasta la entrega al cliente.

6. **Margen:** Se calcula como precio de venta - costo proveedor, sin costos logisticos propios.

7. **Integracion eCommerce:** Productos dropship son vendibles en WooCommerce con stock "infinito" (o stock del proveedor si se sincroniza).

**Flujo:**

```
Cliente compra producto dropship (OV/Factura/POS/Ecommerce)
  |
  v
Sistema detecta producto en dropship_config
  |
  v
Seleccionar proveedor (preferido o manual)
  |
  v
Auto-generar OC al proveedor
  |-- Direccion entrega = direccion del cliente
  |-- Precio = precio de compra del dropship_config
  |-- Referencia a OV/Factura original
  |
  v
Enviar OC al proveedor (email/WhatsApp)
  |
  v
Proveedor confirma -> estado: CONFIRMADA_PROVEEDOR
  |
  v
Proveedor envia -> estado: EN_TRANSITO (tracking si disponible)
  |
  v
Entrega confirmada -> estado: ENTREGADA
  |
  v
Registrar factura del proveedor -> CxP
  |
  v
NO hay movimiento de inventario propio
```

### Modelo de Datos SQL

```sql
-- ============================================
-- DROPSHIPPING (AMPLIACION de G-INV-04)
-- Extiende la tabla basica dropship_config del INFORME
-- ============================================

-- Eliminar tabla basica y recrear con estructura completa
DROP TABLE IF EXISTS dropship_config;

CREATE TABLE dropship_config (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  producto_id     UUID NOT NULL REFERENCES productos(id),
  proveedor_id    UUID NOT NULL REFERENCES contactos(id),
  -- Precios y condiciones
  precio_compra   DECIMAL(14,6) NOT NULL,              -- Costo del proveedor dropship
  moneda          VARCHAR(10) DEFAULT 'USD',
  plazo_entrega_dias INTEGER DEFAULT 7,                -- Plazo estimado de entrega
  cantidad_minima DECIMAL(18,6) DEFAULT 1,              -- Cantidad minima por pedido
  -- Configuracion
  es_preferido    BOOLEAN DEFAULT false,                -- Proveedor preferido para este producto
  auto_generar_oc BOOLEAN DEFAULT true,                 -- Generar OC automaticamente al confirmar venta
  stock_proveedor DECIMAL(18,6),                        -- Stock disponible del proveedor (si se sincroniza)
  fecha_ultimo_sync TIMESTAMPTZ,                        -- Ultima sincronizacion de stock
  -- Metadatos
  activo          BOOLEAN DEFAULT true,
  notas           TEXT,
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now(),
  UNIQUE(empresa_id, producto_id, proveedor_id)
);

-- Ordenes de dropship (tracking del envio directo)
CREATE TABLE ordenes_dropship (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  -- Referencias
  orden_venta_id  UUID REFERENCES ordenes_venta(id),    -- OV que origino el dropship
  factura_id      UUID REFERENCES facturas(id),          -- Factura al cliente
  orden_compra_id UUID NOT NULL REFERENCES ordenes_compra(id), -- OC al proveedor
  -- Partes
  cliente_id      UUID NOT NULL REFERENCES contactos(id),
  proveedor_id    UUID NOT NULL REFERENCES contactos(id),
  -- Direccion de entrega (del cliente)
  direccion_entrega_id UUID REFERENCES contacto_direcciones(id),
  direccion_entrega_texto TEXT,                           -- Snapshot de la direccion
  -- Estado del envio
  estado          VARCHAR(25) DEFAULT 'OC_GENERADA',
    -- OC_GENERADA: OC creada y pendiente de envio al proveedor
    -- OC_ENVIADA: OC enviada al proveedor
    -- CONFIRMADA_PROVEEDOR: proveedor confirmo que procesara el pedido
    -- EN_PREPARACION: proveedor esta preparando el envio
    -- EN_TRANSITO: producto en camino al cliente
    -- ENTREGADA: producto entregado al cliente
    -- DEVUELTA: producto devuelto (problema de entrega)
    -- CANCELADA: orden cancelada
  -- Tracking
  tracking_number VARCHAR(100),
  tracking_url    TEXT,
  transportista   VARCHAR(100),
  fecha_envio_estimada DATE,
  fecha_envio_real     TIMESTAMPTZ,
  fecha_entrega_estimada DATE,
  fecha_entrega_real     TIMESTAMPTZ,
  -- Costos y margen
  costo_proveedor DECIMAL(14,2) NOT NULL,
  precio_venta    DECIMAL(14,2) NOT NULL,
  margen          DECIMAL(14,2),                          -- precio_venta - costo_proveedor
  margen_porcentaje DECIMAL(5,2),
  -- Factura del proveedor
  factura_proveedor_recibida BOOLEAN DEFAULT false,
  cxp_id          UUID REFERENCES cuentas_por_pagar(id),
  -- Metadata
  notas           TEXT,
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now()
);

-- Lineas de dropship (productos enviados)
CREATE TABLE orden_dropship_lineas (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  orden_dropship_id UUID NOT NULL REFERENCES ordenes_dropship(id) ON DELETE CASCADE,
  producto_id     UUID NOT NULL REFERENCES productos(id),
  presentacion_id UUID REFERENCES producto_presentaciones(id),
  cantidad        DECIMAL(18,6) NOT NULL,
  precio_compra   DECIMAL(14,6) NOT NULL,
  precio_venta    DECIMAL(14,6) NOT NULL,
  subtotal_compra DECIMAL(14,2) NOT NULL,
  subtotal_venta  DECIMAL(14,2) NOT NULL,
  margen_linea    DECIMAL(14,2),
  orden           INTEGER DEFAULT 0
);

-- Campo adicional en ordenes_compra
ALTER TABLE ordenes_compra
  ADD COLUMN IF NOT EXISTS es_dropship BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS direccion_entrega_cliente TEXT;

-- Campo adicional en productos
ALTER TABLE productos
  ADD COLUMN IF NOT EXISTS es_dropship BOOLEAN DEFAULT false;

-- Indices
CREATE INDEX idx_dropship_config_producto ON dropship_config(empresa_id, producto_id, activo);
CREATE INDEX idx_dropship_config_proveedor ON dropship_config(empresa_id, proveedor_id);
CREATE INDEX idx_ordenes_dropship_empresa ON ordenes_dropship(empresa_id, estado);
CREATE INDEX idx_ordenes_dropship_cliente ON ordenes_dropship(cliente_id);
CREATE INDEX idx_ordenes_dropship_oc ON ordenes_dropship(orden_compra_id);

-- RLS
ALTER TABLE dropship_config ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON dropship_config FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

ALTER TABLE ordenes_dropship ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON ordenes_dropship FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

ALTER TABLE orden_dropship_lineas ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_via_orden" ON orden_dropship_lineas FOR ALL TO authenticated
  USING (orden_dropship_id IN (
    SELECT id FROM ordenes_dropship WHERE empresa_id = (SELECT private.get_empresa_id())
  ));
```

### Funciones PostgreSQL Principales

```sql
-- ============================================
-- DETECTAR Y PROCESAR PRODUCTOS DROPSHIP EN UNA VENTA
-- Llamada al confirmar OV o factura
-- ============================================
CREATE OR REPLACE FUNCTION process_dropship_items(
  p_empresa_id UUID,
  p_cliente_id UUID,
  p_lineas JSONB,           -- [{producto_id, cantidad, precio_venta, presentacion_id}]
  p_orden_venta_id UUID DEFAULT NULL,
  p_factura_id UUID DEFAULT NULL,
  p_direccion_entrega_id UUID DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_linea JSONB;
  v_config RECORD;
  v_oc_id UUID;
  v_dropship_id UUID;
  v_direccion TEXT;
  v_ocs_generadas UUID[] := '{}';
  v_dropships_creados UUID[] := '{}';
  v_items_dropship INTEGER := 0;
  v_proveedor_lineas JSONB := '{}'::JSONB;
  v_prov_id UUID;
  v_prov_key TEXT;
BEGIN
  -- 1. Obtener direccion de entrega del cliente
  IF p_direccion_entrega_id IS NOT NULL THEN
    SELECT direccion INTO v_direccion
    FROM contacto_direcciones WHERE id = p_direccion_entrega_id;
  ELSE
    SELECT direccion INTO v_direccion FROM contactos WHERE id = p_cliente_id;
  END IF;

  -- 2. Agrupar lineas dropship por proveedor
  FOR v_linea IN SELECT * FROM jsonb_array_elements(p_lineas)
  LOOP
    SELECT * INTO v_config
    FROM dropship_config
    WHERE empresa_id = p_empresa_id
      AND producto_id = (v_linea->>'producto_id')::UUID
      AND activo = true
    ORDER BY es_preferido DESC
    LIMIT 1;

    IF v_config IS NOT NULL THEN
      v_prov_key := v_config.proveedor_id::TEXT;
      IF v_proveedor_lineas ? v_prov_key THEN
        v_proveedor_lineas := jsonb_set(
          v_proveedor_lineas, ARRAY[v_prov_key],
          (v_proveedor_lineas->v_prov_key) || jsonb_build_array(
            v_linea || jsonb_build_object(
              'precio_compra', v_config.precio_compra,
              'config_id', v_config.id
            )
          )
        );
      ELSE
        v_proveedor_lineas := v_proveedor_lineas || jsonb_build_object(
          v_prov_key, jsonb_build_array(
            v_linea || jsonb_build_object(
              'precio_compra', v_config.precio_compra,
              'config_id', v_config.id
            )
          )
        );
      END IF;
      v_items_dropship := v_items_dropship + 1;
    END IF;
  END LOOP;

  IF v_items_dropship = 0 THEN
    RETURN jsonb_build_object('dropship_items', 0);
  END IF;

  -- 3. Crear una OC + orden_dropship por cada proveedor
  FOR v_prov_key IN SELECT * FROM jsonb_object_keys(v_proveedor_lineas)
  LOOP
    v_prov_id := v_prov_key::UUID;

    -- Crear OC dropship
    v_oc_id := create_dropship_po(
      p_empresa_id, v_prov_id, p_cliente_id,
      v_proveedor_lineas->v_prov_key,
      v_direccion
    );
    v_ocs_generadas := v_ocs_generadas || v_oc_id;

    -- Crear orden dropship
    INSERT INTO ordenes_dropship (
      empresa_id, orden_venta_id, factura_id, orden_compra_id,
      cliente_id, proveedor_id,
      direccion_entrega_id, direccion_entrega_texto,
      estado,
      costo_proveedor, precio_venta, margen
    ) VALUES (
      p_empresa_id, p_orden_venta_id, p_factura_id, v_oc_id,
      p_cliente_id, v_prov_id,
      p_direccion_entrega_id, v_direccion,
      'OC_GENERADA',
      (SELECT SUM((l->>'precio_compra')::DECIMAL * (l->>'cantidad')::DECIMAL)
       FROM jsonb_array_elements(v_proveedor_lineas->v_prov_key) l),
      (SELECT SUM((l->>'precio_venta')::DECIMAL * (l->>'cantidad')::DECIMAL)
       FROM jsonb_array_elements(v_proveedor_lineas->v_prov_key) l),
      (SELECT SUM(((l->>'precio_venta')::DECIMAL - (l->>'precio_compra')::DECIMAL) * (l->>'cantidad')::DECIMAL)
       FROM jsonb_array_elements(v_proveedor_lineas->v_prov_key) l)
    )
    RETURNING id INTO v_dropship_id;

    -- Crear lineas de dropship
    INSERT INTO orden_dropship_lineas (
      orden_dropship_id, producto_id, cantidad,
      precio_compra, precio_venta,
      subtotal_compra, subtotal_venta, margen_linea
    )
    SELECT
      v_dropship_id,
      (l->>'producto_id')::UUID,
      (l->>'cantidad')::DECIMAL,
      (l->>'precio_compra')::DECIMAL,
      (l->>'precio_venta')::DECIMAL,
      ROUND((l->>'precio_compra')::DECIMAL * (l->>'cantidad')::DECIMAL, 2),
      ROUND((l->>'precio_venta')::DECIMAL * (l->>'cantidad')::DECIMAL, 2),
      ROUND(((l->>'precio_venta')::DECIMAL - (l->>'precio_compra')::DECIMAL) * (l->>'cantidad')::DECIMAL, 2)
    FROM jsonb_array_elements(v_proveedor_lineas->v_prov_key) l;

    -- Calcular margen porcentaje
    UPDATE ordenes_dropship SET
      margen_porcentaje = CASE WHEN precio_venta > 0
        THEN ROUND(margen / precio_venta * 100, 2) ELSE 0 END
    WHERE id = v_dropship_id;

    v_dropships_creados := v_dropships_creados || v_dropship_id;
  END LOOP;

  -- 4. Log de auditoria
  PERFORM module_bus.log_activity(
    p_empresa_id := p_empresa_id,
    p_entidad_tipo := 'ordenes_dropship',
    p_entidad_id := v_dropships_creados[1],
    p_accion := 'DROPSHIP_CREADO',
    p_detalle := jsonb_build_object(
      'ocs_generadas', v_ocs_generadas,
      'items_dropship', v_items_dropship,
      'cliente_id', p_cliente_id
    )
  );

  RETURN jsonb_build_object(
    'dropship_items', v_items_dropship,
    'ordenes_dropship', to_jsonb(v_dropships_creados),
    'ordenes_compra', to_jsonb(v_ocs_generadas)
  );
END;
$$;

-- Crear OC de dropship
CREATE OR REPLACE FUNCTION create_dropship_po(
  p_empresa_id UUID,
  p_proveedor_id UUID,
  p_cliente_id UUID,
  p_lineas JSONB,
  p_direccion_cliente TEXT
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_oc_id UUID;
  v_num VARCHAR(20);
  v_linea JSONB;
  v_subtotal DECIMAL(14,2) := 0;
  v_total DECIMAL(14,2) := 0;
BEGIN
  SELECT 'OC-DS-' || LPAD((COALESCE(MAX(CAST(SUBSTRING(numero FROM 7) AS INTEGER)), 0) + 1)::TEXT, 6, '0')
  INTO v_num FROM ordenes_compra WHERE empresa_id = p_empresa_id AND es_dropship = true;

  INSERT INTO ordenes_compra (
    empresa_id, contacto_id, numero, fecha,
    estado, es_dropship, direccion_entrega_cliente,
    notas
  ) VALUES (
    p_empresa_id, p_proveedor_id, v_num, CURRENT_DATE,
    'BORRADOR', true, p_direccion_cliente,
    'Dropship - Entrega directa al cliente'
  )
  RETURNING id INTO v_oc_id;

  FOR v_linea IN SELECT * FROM jsonb_array_elements(p_lineas)
  LOOP
    v_subtotal := ROUND((v_linea->>'precio_compra')::DECIMAL * (v_linea->>'cantidad')::DECIMAL, 2);

    INSERT INTO orden_compra_detalles (
      orden_compra_id, producto_id, cantidad, cantidad_base,
      precio_unitario, subtotal, total_impuestos, total_linea
    ) VALUES (
      v_oc_id, (v_linea->>'producto_id')::UUID,
      (v_linea->>'cantidad')::DECIMAL, (v_linea->>'cantidad')::DECIMAL,
      (v_linea->>'precio_compra')::DECIMAL,
      v_subtotal, 0, v_subtotal
    );

    v_total := v_total + v_subtotal;
  END LOOP;

  UPDATE ordenes_compra SET total = v_total WHERE id = v_oc_id;
  RETURN v_oc_id;
END;
$$;

-- Actualizar estado del dropship
CREATE OR REPLACE FUNCTION update_dropship_status(
  p_dropship_id UUID,
  p_estado VARCHAR,
  p_tracking_number VARCHAR DEFAULT NULL,
  p_tracking_url TEXT DEFAULT NULL,
  p_transportista VARCHAR DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_ds RECORD;
BEGIN
  SELECT * INTO v_ds FROM ordenes_dropship WHERE id = p_dropship_id;

  UPDATE ordenes_dropship SET
    estado = p_estado,
    tracking_number = COALESCE(p_tracking_number, tracking_number),
    tracking_url = COALESCE(p_tracking_url, tracking_url),
    transportista = COALESCE(p_transportista, transportista),
    fecha_envio_real = CASE WHEN p_estado = 'EN_TRANSITO' THEN now() ELSE fecha_envio_real END,
    fecha_entrega_real = CASE WHEN p_estado = 'ENTREGADA' THEN now() ELSE fecha_entrega_real END,
    updated_at = now()
  WHERE id = p_dropship_id;

  -- Notificar al cliente si esta en transito
  IF p_estado = 'EN_TRANSITO' THEN
    PERFORM module_bus.send_notification(
      p_empresa_id := v_ds.empresa_id,
      p_tipo := 'DROPSHIP_EN_TRANSITO',
      p_datos := jsonb_build_object(
        'cliente_id', v_ds.cliente_id,
        'tracking_number', p_tracking_number,
        'tracking_url', p_tracking_url,
        'transportista', p_transportista
      )
    );
  END IF;
END;
$$;
```

### Triggers

```sql
-- Validar que el proveedor tenga es_proveedor=true en dropship_config
CREATE OR REPLACE FUNCTION tr_validate_dropship_config()
RETURNS TRIGGER AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM contactos WHERE id = NEW.proveedor_id AND es_proveedor = true) THEN
    RAISE EXCEPTION 'El contacto no es un proveedor activo';
  END IF;
  -- Marcar producto como dropship
  UPDATE productos SET es_dropship = true WHERE id = NEW.producto_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tr_validate_dropship
  BEFORE INSERT ON dropship_config
  FOR EACH ROW EXECUTE FUNCTION tr_validate_dropship_config();

-- Calcular margen en ordenes_dropship al actualizar costos
CREATE OR REPLACE FUNCTION tr_dropship_margin()
RETURNS TRIGGER AS $$
BEGIN
  NEW.margen := NEW.precio_venta - NEW.costo_proveedor;
  NEW.margen_porcentaje := CASE WHEN NEW.precio_venta > 0
    THEN ROUND(NEW.margen / NEW.precio_venta * 100, 2) ELSE 0 END;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tr_calc_dropship_margin
  BEFORE INSERT OR UPDATE OF precio_venta, costo_proveedor ON ordenes_dropship
  FOR EACH ROW EXECUTE FUNCTION tr_dropship_margin();
```

### Vistas para Reportes

```sql
-- Vista: Ordenes dropship con detalle
CREATE OR REPLACE VIEW v_ordenes_dropship AS
SELECT
  od.id,
  od.empresa_id,
  od.estado,
  od.cliente_id,
  cc.razon_social AS cliente,
  od.proveedor_id,
  cp.razon_social AS proveedor,
  od.orden_compra_id,
  oc.numero AS oc_numero,
  od.orden_venta_id,
  od.factura_id,
  od.costo_proveedor,
  od.precio_venta,
  od.margen,
  od.margen_porcentaje,
  od.tracking_number,
  od.transportista,
  od.fecha_envio_real,
  od.fecha_entrega_real,
  od.factura_proveedor_recibida,
  od.created_at
FROM ordenes_dropship od
JOIN contactos cc ON cc.id = od.cliente_id
JOIN contactos cp ON cp.id = od.proveedor_id
JOIN ordenes_compra oc ON oc.id = od.orden_compra_id;

-- Reporte de margenes dropship
CREATE OR REPLACE VIEW v_dropship_margenes AS
SELECT
  od.empresa_id,
  od.proveedor_id,
  cp.razon_social AS proveedor,
  COUNT(*) AS total_ordenes,
  SUM(od.costo_proveedor) AS total_costo,
  SUM(od.precio_venta) AS total_venta,
  SUM(od.margen) AS total_margen,
  ROUND(AVG(od.margen_porcentaje), 2) AS margen_promedio_pct,
  COUNT(*) FILTER (WHERE od.estado = 'ENTREGADA') AS entregadas,
  COUNT(*) FILTER (WHERE od.estado = 'DEVUELTA') AS devueltas
FROM ordenes_dropship od
JOIN contactos cp ON cp.id = od.proveedor_id
GROUP BY od.empresa_id, od.proveedor_id, cp.razon_social;
```

### Integracion Module Service Bus

```sql
-- Gateway: Procesar dropship desde modulos de ventas/ecommerce
CREATE OR REPLACE FUNCTION module_bus.process_dropship(
  p_empresa_id UUID,
  p_cliente_id UUID,
  p_lineas JSONB,
  p_orden_venta_id UUID DEFAULT NULL,
  p_factura_id UUID DEFAULT NULL,
  p_direccion_entrega_id UUID DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_activo BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM modulos_empresa me JOIN modulos m ON m.id = me.modulo_id
    WHERE me.empresa_id = p_empresa_id AND m.codigo = 'compras' AND me.activo = true
  ) INTO v_activo;

  IF NOT v_activo THEN
    RETURN jsonb_build_object('executed', false, 'reason', 'Modulo Compras inactivo');
  END IF;

  RETURN process_dropship_items(
    p_empresa_id, p_cliente_id, p_lineas,
    p_orden_venta_id, p_factura_id, p_direccion_entrega_id
  ) || jsonb_build_object('executed', true);
END;
$$;
```

### RLS Policies

| Tabla | Policy | Tipo |
|-------|--------|------|
| `dropship_config` | `tenant_isolation` | Directa: `empresa_id` |
| `ordenes_dropship` | `tenant_isolation` | Directa: `empresa_id` |
| `orden_dropship_lineas` | `tenant_via_orden` | Via JOIN |

### Flujo UI/UX

```
PANTALLA LISTADO DROPSHIP:
  SfDataGrid: Estado | Cliente | Proveedor | OC# | Costo | Venta | Margen% | Tracking | Fecha
  Filtros: estado, proveedor, rango fechas
  Color-coded por estado (azul=en transito, verde=entregada, rojo=devuelta)
  Badge con conteo por estado en la cabecera

PANTALLA DETALLE DROPSHIP:
  - Info general: cliente, proveedor, direccion entrega
  - Timeline visual de estados (OC_GENERADA -> CONFIRMADA -> EN_TRANSITO -> ENTREGADA)
  - Lineas: producto, cantidad, precio compra/venta, margen
  - Tracking: numero, URL (link externo), transportista
  - Boton [Actualizar estado] con opciones contextuales

PANTALLA CONFIG DROPSHIP (en ficha del producto):
  - Tab "Dropship" en producto:
    - Toggle [Es producto dropship]
    - Tabla proveedores dropship: Proveedor | Precio | Plazo | Qty Min | Preferido
    - Boton [+ Agregar proveedor dropship]

INTEGRACION EN OV:
  - Al agregar producto dropship a OV, mostrar badge "DROPSHIP" en la linea
  - Al confirmar OV, popup: "Se generaran OCs dropship para N productos. Confirmar?"
  - Despues de confirmar, mostrar link a las ordenes dropship generadas

RESPONSIVE:
  - COMPACT: timeline vertical, cards apiladas
  - MEDIUM: timeline horizontal, tabla compacta
  - EXPANDED/LARGE: detalle completo con timeline + tabla + mapa de tracking
```

---

