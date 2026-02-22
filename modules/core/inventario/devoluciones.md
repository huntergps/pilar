# Devoluciones de Inventario

*Spec derivada del módulo `l10n_ec_stock_return` (Odoo 19.1 Ecuador — producción en csolish/tecnoh)*

---

## Descripción

Extensión del flujo de devoluciones de inventario (stock.picking). Agrega validación de disponibilidad de series/lotes antes de confirmar una devolución, bloqueo optimista para evitar validaciones simultáneas, y registro automático de series procesadas en el chatter del picking. Mejora el control de devolutivas en Ecuador donde los números de serie son críticos para trazabilidad.

---

## Modelo de Datos

### Extensión de `movimientos_inventario` (pickings)

```sql
ALTER TABLE movimientos_inventario ADD COLUMN es_devolucion  BOOLEAN DEFAULT FALSE;  -- calculado
ALTER TABLE movimientos_inventario ADD COLUMN puede_devolver BOOLEAN DEFAULT FALSE;  -- calculado
-- es_devolucion = true si picking.return_id IS NOT NULL o si origin contiene 'Return'
-- puede_devolver = true si estado IN ('confirmado','asignado','hecho') AND NOT es_devolucion
```

### Vista: Devoluciones Activas

```sql
CREATE VIEW vista_devoluciones_activas AS
SELECT
  m.id,
  m.empresa_id,
  m.nombre,
  m.estado,
  m.fecha_programada,
  m.origen_id,      -- picking original del que deriva esta devolucion
  m.contacto_id,
  SUM(ml.cantidad) AS cantidad_total,
  COUNT(DISTINCT ml.producto_id) AS productos_distintos
FROM movimientos_inventario m
JOIN movimiento_lineas ml ON ml.movimiento_id = m.id
WHERE m.es_devolucion = TRUE
  AND m.estado != 'cancelado'
GROUP BY m.id;
```

---

## Flujo de Devolución

```
1. Picking original (compra/venta) en estado 'hecho'
   ↓
2. Usuario selecciona cantidades a devolver (wizard Devolver)
   ↓
3. Se crea nuevo picking de tipo devolución (return_id = picking_original)
   ↓
4. Validar disponibilidad de series:
   - Verificar que ninguna serie seleccionada esté en otro picking
     de devolución pendiente (duplicados en cola)
5. Bloqueo optimista: lock_for_update() antes de validar
   ↓
6. Confirmar devolución → picking pasa a 'hecho'
   ↓
7. Registro automático en chatter: listado de series devueltas
   ↓
8. Ajuste de stock en ubicaciones (invert: destino → origen del original)
```

---

## Validaciones Específicas Ecuador

### Series en Devoluciones

La regla central: **no pueden existir dos pickings de devolución pendientes para la misma serie**.

```
Al validar picking de devolución:
  Para cada movimiento:
    Para cada serie (lot_id) en move_lines:
      Buscar otros pickings de devolución en estado 'assigned'/'confirmed'
      que también incluyan la misma serie
      → Si existe → UserError: "Serie X ya está en devolución pendiente"
```

### Bloqueo Optimista

```
1. Verificar estado (no en 'confirmed'/'assigned' → error)
2. lock_for_update() → bloqueo de fila en PostgreSQL
3. Invalidar caché y re-verificar estado
4. Si estado cambió durante bloqueo → error "recargue la página"
5. Proceder con validación
```

---

## Funciones RPC

```typescript
// Verificar si un picking puede ser devuelto
verificar_devolucion(picking_id: UUID): {
  puede_devolver: boolean
  motivo?: string
  series_en_uso: string[]   // series que ya están en otras devoluciones
}

// Crear picking de devolución
crear_devolucion(params: {
  picking_id: UUID
  lineas: [{
    move_id: UUID
    cantidad: number
    lot_ids?: UUID[]
  }]
  motivo?: string
}): {
  devolucion_id: UUID
  nombre: string
}

// Validar devolución (con bloqueo y verificación de series)
validar_devolucion(picking_id: UUID): {
  estado: 'hecho'
  series_registradas: string[]
  asiento_id?: UUID
}

// Obtener historial de devoluciones de un picking
get_devoluciones_picking(picking_id: UUID): [{
  devolucion_id: UUID
  nombre: string
  fecha: string
  estado: string
  cantidad_total: number
  motivo: string
}]

// Consultar series en devoluciones activas
get_series_en_devolucion(empresa_id: UUID): [{
  serie: string
  producto_id: UUID
  producto: string
  picking_devolucion_id: UUID
  picking_nombre: string
  estado: string
}]
```

---

## Validaciones de Negocio

- Solo pickings en estado `confirmado` o `asignado` pueden validarse
- No se puede crear una devolución de otra devolución (`can_return = false` si `is_return = true`)
- Si el picking original tiene series rastreadas, la devolución debe especificar qué series retornan
- El chatter registra automáticamente las series devueltas para trazabilidad
- Bloqueo de fila evita validaciones simultáneas del mismo picking

---

## Configuración por Empresa

```json
{
  "devoluciones": {
    "requiere_motivo": true,
    "validar_series_duplicadas": true,
    "registrar_series_en_chatter": true,
    "generar_nota_credito_automatica": false
  }
}
```

---

## Pantallas Flutter

### Wizard de Devolución

```
┌────────────────────────────────────────────────────────┐
│ DEVOLVER PRODUCTOS — REC-0042                          │
│ Picking original: REC-0042 (Laptop ASUS, Mouse USB)    │
├────────────────────────────────────────────────────────┤
│ Producto         │ Recibido │ A Devolver │ Series      │
├──────────────────┼──────────┼────────────┼─────────────┤
│ Laptop ASUS X15  │    3     │    [2]     │ SN-001, 002 │
│ Mouse USB        │    5     │    [3]     │ (sin serie) │
├────────────────────────────────────────────────────────┤
│ Motivo: [Producto defectuoso                     ]     │
│ [Confirmar Devolución]  [Cancelar]                     │
└────────────────────────────────────────────────────────┘
```

### Lista de Devoluciones

- `CrudScaffold<Devolucion>` filtros: estado, tipo (cliente/proveedor), período
- Columnas: nombre, picking_origen, fecha, productos, cantidad, estado
- Acción: Ver picking → Ver asiento contable

---

## Devoluciones de Venta (Módulo Facturación + Inventario)

Las devoluciones de venta son distintas a las devoluciones de inventario: tienen implicaciones SRI (Nota de Crédito) y flujo de aprobación. Se manejan con tablas propias:

### Tablas SQL

```sql
CREATE TABLE devoluciones_venta (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id        UUID NOT NULL REFERENCES empresas(id),
  factura_origen_id UUID NOT NULL REFERENCES facturas(id),
  contacto_id       UUID NOT NULL REFERENCES contactos(id),
  fecha             DATE NOT NULL,
  motivo            VARCHAR(200) NOT NULL,
  tipo_resolucion   VARCHAR(20) DEFAULT 'NC'
                    CHECK (tipo_resolucion IN ('NC','CAMBIO','CREDITO','SCRAP')),
  estado            VARCHAR(20) DEFAULT 'PENDIENTE'
                    CHECK (estado IN ('PENDIENTE','APROBADA','PROCESADA','RECHAZADA')),
  nc_id             UUID,                              -- NC SRI generada (si tipo=NC)
  bodega_destino_id UUID REFERENCES bodegas(id),
  aprobador_id      UUID REFERENCES auth.users(id),
  notas             TEXT,
  created_at        TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE devoluciones_venta ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON devoluciones_venta FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE TABLE devolucion_venta_lineas (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  devolucion_id       UUID NOT NULL REFERENCES devoluciones_venta(id) ON DELETE CASCADE,
  producto_id         UUID NOT NULL REFERENCES productos(id),
  presentacion_id     UUID REFERENCES producto_presentaciones(id),
  cantidad_devuelta   DECIMAL(18,6) NOT NULL,
  cantidad_base       DECIMAL(18,6) NOT NULL,   -- en unidad base del producto
  precio_unitario     DECIMAL(14,6) NOT NULL,
  subtotal            DECIMAL(14,2) NOT NULL,
  serie_lote_ids      JSONB DEFAULT '[]',        -- Series/lotes devueltos
  estado_producto     VARCHAR(20) DEFAULT 'BUENO'
                      CHECK (estado_producto IN ('BUENO','DAÑADO','VENCIDO'))
);

ALTER TABLE devolucion_venta_lineas ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON devolucion_venta_lineas FOR ALL TO authenticated
  USING (EXISTS (
    SELECT 1 FROM devoluciones_venta dv
    WHERE dv.id = devolucion_id AND dv.empresa_id = (SELECT private.get_empresa_id())
  ));
```

### Tipos de Resolución

| Tipo | Descripción | Genera NC SRI | Entra a Inventario |
|------|-------------|:---:|:---:|
| `NC` | Nota de Crédito al cliente | Si | Si |
| `CAMBIO` | Producto defectuoso → reponer igual | No | Si (DEVOLUCIONES) |
| `CREDITO` | Nota crédito interna (saldo a favor) | Si | No siempre |
| `SCRAP` | Producto no recuperable, destrucción | Si | No (baja directa) |

---

## Funciones RPC para Devoluciones de Venta

### `create_sale_return` — Crear devolución con validaciones SRI

```sql
CREATE OR REPLACE FUNCTION create_sale_return(
  p_factura_id       UUID,
  p_lineas           JSONB,         -- [{producto_id, cantidad, serie_lote_ids, estado_producto}]
  p_motivo           TEXT,
  p_tipo_resolucion  VARCHAR(20)
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_factura         RECORD;
  v_devolucion_id   UUID;
  v_linea           JSONB;
  v_cant_orig       DECIMAL(18,6);
  v_cant_devuelta   DECIMAL(18,6);
BEGIN
  -- Obtener datos de la factura
  SELECT * INTO v_factura FROM facturas WHERE id = p_factura_id
    AND empresa_id = (SELECT private.get_empresa_id());
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Factura no encontrada';
  END IF;

  -- Validar plazo de devolución: máx 5 años (plazo NC Ecuador)
  IF v_factura.fecha_emision < CURRENT_DATE - INTERVAL '5 years' THEN
    RAISE EXCEPTION 'No se puede devolver: la factura supera el plazo de 5 años para NC';
  END IF;

  -- Validar que la factura esté autorizada por SRI
  IF v_factura.estado_sri != 'AUTORIZADO' THEN
    RAISE EXCEPTION 'Solo se pueden devolver facturas autorizadas por el SRI';
  END IF;

  -- Crear encabezado de devolución
  INSERT INTO devoluciones_venta (
    empresa_id, factura_origen_id, contacto_id, fecha,
    motivo, tipo_resolucion, bodega_destino_id
  )
  SELECT
    v_factura.empresa_id,
    p_factura_id,
    v_factura.contacto_id,
    CURRENT_DATE,
    p_motivo,
    p_tipo_resolucion,
    (SELECT id FROM bodegas WHERE empresa_id = v_factura.empresa_id
       AND tipo = 'DEVOLUCIONES' LIMIT 1)
  RETURNING id INTO v_devolucion_id;

  -- Validar y crear líneas
  FOR v_linea IN SELECT * FROM jsonb_array_elements(p_lineas) LOOP
    -- Verificar que cantidad no supera original
    SELECT COALESCE(SUM(fl.cantidad), 0) INTO v_cant_orig
    FROM factura_lineas fl
    WHERE fl.factura_id = p_factura_id
      AND fl.producto_id = (v_linea->>'producto_id')::UUID;

    SELECT COALESCE(SUM(dvl.cantidad_devuelta), 0) INTO v_cant_devuelta
    FROM devolucion_venta_lineas dvl
    JOIN devoluciones_venta dv ON dv.id = dvl.devolucion_id
    WHERE dv.factura_origen_id = p_factura_id
      AND dvl.producto_id = (v_linea->>'producto_id')::UUID
      AND dv.estado != 'RECHAZADA';

    IF (v_cant_devuelta + (v_linea->>'cantidad')::DECIMAL) > v_cant_orig THEN
      RAISE EXCEPTION 'Cantidad a devolver supera la cantidad original facturada para producto %',
        v_linea->>'producto_id';
    END IF;

    INSERT INTO devolucion_venta_lineas (
      devolucion_id, producto_id, cantidad_devuelta, cantidad_base,
      precio_unitario, subtotal, serie_lote_ids, estado_producto
    )
    SELECT
      v_devolucion_id,
      (v_linea->>'producto_id')::UUID,
      (v_linea->>'cantidad')::DECIMAL,
      (v_linea->>'cantidad')::DECIMAL,   -- asume misma UoM base por ahora
      fl.precio_unitario,
      ROUND(fl.precio_unitario * (v_linea->>'cantidad')::DECIMAL, 2),
      COALESCE(v_linea->'serie_lote_ids', '[]'),
      COALESCE(v_linea->>'estado_producto', 'BUENO')
    FROM factura_lineas fl
    WHERE fl.factura_id = p_factura_id
      AND fl.producto_id = (v_linea->>'producto_id')::UUID
    LIMIT 1;
  END LOOP;

  RETURN v_devolucion_id;
END;
$$;
```

### `process_return_inventory` — Entrada de stock en bodega de devoluciones

```sql
CREATE OR REPLACE FUNCTION process_return_inventory(p_devolucion_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_dev    RECORD;
  v_linea  RECORD;
BEGIN
  SELECT * INTO v_dev FROM devoluciones_venta
  WHERE id = p_devolucion_id
    AND empresa_id = (SELECT private.get_empresa_id())
    AND estado = 'APROBADA';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Devolución no encontrada o no está aprobada';
  END IF;

  FOR v_linea IN
    SELECT * FROM devolucion_venta_lineas WHERE devolucion_id = p_devolucion_id
  LOOP
    -- Crear movimiento de inventario tipo DEVOLUCION_VENTA
    INSERT INTO movimientos_inventario (
      empresa_id, producto_id, bodega_id,
      tipo_movimiento, cantidad, costo_unitario,
      referencia, estado, fecha
    ) VALUES (
      v_dev.empresa_id,
      v_linea.producto_id,
      v_dev.bodega_destino_id,
      'DEVOLUCION_VENTA',
      v_linea.cantidad_base,
      v_linea.precio_unitario,
      'DEV-' || p_devolucion_id::TEXT,
      -- Producto dañado/vencido entra en CUARENTENA, bueno en DISPONIBLE
      CASE WHEN v_linea.estado_producto = 'BUENO' THEN 'CONFIRMADO' ELSE 'CUARENTENA' END,
      CURRENT_DATE
    );

    -- Actualizar stock en inventario_stock
    INSERT INTO inventario_stock (empresa_id, producto_id, bodega_id, cantidad)
    VALUES (v_dev.empresa_id, v_linea.producto_id, v_dev.bodega_destino_id, v_linea.cantidad_base)
    ON CONFLICT (empresa_id, producto_id, bodega_id)
    DO UPDATE SET cantidad = inventario_stock.cantidad + EXCLUDED.cantidad;
  END LOOP;

  -- Crear asiento contable via module_bus
  PERFORM module_bus.contabilidad.create_journal_entry(
    p_empresa_id    => v_dev.empresa_id,
    p_referencia    => 'DEV-VENTA-' || p_devolucion_id::TEXT,
    p_descripcion   => 'Devolución de venta - ingreso inventario',
    p_fecha         => CURRENT_DATE
  );

  UPDATE devoluciones_venta SET estado = 'PROCESADA' WHERE id = p_devolucion_id;
END;
$$;
```

### `process_return_nc` — Genera Nota de Crédito SRI

```sql
CREATE OR REPLACE FUNCTION process_return_nc(p_devolucion_id UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_dev   RECORD;
  v_nc_id UUID;
BEGIN
  SELECT * INTO v_dev FROM devoluciones_venta
  WHERE id = p_devolucion_id
    AND empresa_id = (SELECT private.get_empresa_id())
    AND tipo_resolucion IN ('NC','CREDITO')
    AND estado IN ('APROBADA','PROCESADA');
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Devolución no aplica para NC o no está aprobada';
  END IF;

  -- Generar NC via Module Service Bus de Facturación
  v_nc_id := module_bus.facturacion.create_nota_credito(
    p_factura_id  => v_dev.factura_origen_id,
    p_motivo      => 'Devolución de venta: ' || v_dev.motivo,
    p_empresa_id  => v_dev.empresa_id
  );

  UPDATE devoluciones_venta SET nc_id = v_nc_id WHERE id = p_devolucion_id;
  RETURN v_nc_id;
END;
$$;
```

---

## Casos Especiales de Devolución

### Producto con Serie

```
Venta original:  Laptop ASUS X15 — SN: ABC-001
Al devolver:     Validar que SN ABC-001 fue la vendida en esa factura
                 JOIN serie_lotes s ON s.producto_id = linea.producto_id
                       AND s.serie = 'ABC-001'
                       AND s.factura_origen_id = p_factura_id
Si no coincide → RAISE EXCEPTION 'Serie ABC-001 no corresponde a esta factura'
```

### Producto Dañado (estado_producto = 'DAÑADO')

```
1. Entrada a bodega DEVOLUCIONES con estado CUARENTENA
2. No incrementa stock disponible para venta
3. Inspector de calidad debe revisar y decidir:
   - APROBADO → traslado a bodega principal (DISPONIBLE)
   - RECHAZADO → baja de inventario (SCRAP) o devolución al proveedor
4. Se requiere orden de inspección antes de reclasificar
```

### Sin Serie (productos genéricos)

```
Validación simplificada:
  - Verificar que la factura incluye el producto
  - Verificar que la cantidad devuelta <= cantidad facturada
  - Aplicar FIFO de devolución: la salida más reciente se devuelve primero
  - No se valida lote específico (salvo que el producto sea rastreable por lotes)
```

---

## Integración con Módulo Garantías/RMA

Cuando el módulo auxiliar Garantías/RMA está activo, las devoluciones de venta pueden originarse desde una solicitud de garantía o RMA:

```
solicitudes_rma.devolucion_venta_id = devoluciones_venta.id

Flujo:
  Solicitud RMA (cliente) → Aprobación RMA → create_sale_return() → devolución_venta
  La solicitud RMA hereda el estado de la devolución de venta.

Nota: Si el módulo Garantías/RMA NO está activo, las devoluciones se crean
directamente desde la factura sin pasar por RMA.
```

---

## RLS e Índices

```sql
-- Índices para devoluciones_venta
CREATE INDEX idx_dev_venta_empresa_estado
  ON devoluciones_venta (empresa_id, estado);
CREATE INDEX idx_dev_venta_factura
  ON devoluciones_venta (factura_origen_id);
CREATE INDEX idx_dev_venta_contacto
  ON devoluciones_venta (empresa_id, contacto_id);
CREATE INDEX idx_dev_venta_fecha
  ON devoluciones_venta (empresa_id, fecha DESC);

-- Índices para devolucion_venta_lineas
CREATE INDEX idx_dev_venta_lineas_devolucion
  ON devolucion_venta_lineas (devolucion_id);
CREATE INDEX idx_dev_venta_lineas_producto
  ON devolucion_venta_lineas (producto_id);
```
