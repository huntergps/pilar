# Ensamblaje en Ventas (Rutas por Sección)

*Spec derivada del módulo `l10n_ec_sale_assemble` (Odoo 19.1 Ecuador — producción en csolish/tecnoh)*

---

## Descripción

Extensión del módulo de ventas que permite asignar rutas de stock (taller, ensamblaje, MTO, etc.) a grupos de productos organizados por secciones en una orden de venta. Facilita órdenes mixtas donde algunos productos se despachan desde bodega y otros van al taller para ensamblaje o fabricación previa.

---

## Casos de Uso

| Caso | Descripción |
|---|---|
| Mueblería | Sección "Bodega": sillas, mesas estándar. Sección "Taller": mueble a medida |
| Ferretería | Sección "Stock": tornillos, pintura. Sección "Importar": producto especial bajo pedido |
| Tecnología | Sección "Bodega": accesorios. Sección "Ensamblar": PC personalizada |

---

## Modelo de Datos

### Extensión de `ordenes_venta_lineas`

```sql
-- El campo is_for_workshop es calculado (no almacenado)
-- is_for_workshop = true si la línea tiene la ruta 'route_assembly_workshop' asignada
-- Las rutas estándar de Odoo se usan sin modificación
ALTER TABLE ordenes_venta_lineas ADD COLUMN es_para_taller BOOLEAN DEFAULT FALSE;  -- calculado
```

### Ruta de Ensamblaje Taller

Se configura una ruta especial en inventario:
```sql
INSERT INTO rutas_stock (nombre, empresa_id, activo)
VALUES ('Ensamblaje Taller', :empresa_id, true);
```

---

## Funcionamiento

### Organización por Secciones en OV

Una OV con secciones:
```
─── SECCIÓN: Productos de Bodega ───────────
 • Silla ejecutiva ×5       → ruta: Bodega
 • Mesa reuniones ×2        → ruta: Bodega
─── SECCIÓN: Ensamblaje Taller ─────────────
 • Escritorio a medida ×3   → ruta: Taller
 • Mueble esquinero ×1      → ruta: Taller
```

### Asignación Masiva de Ruta por Sección

Desde la sección (header), el usuario puede:
1. **Asignar ruta**: selecciona una ruta → se aplica a todos los productos de esa sección
2. **Quitar rutas**: elimina todas las rutas de los productos de la sección

```
Línea tipo 'sección' → acción → Wizard selecciona ruta
  → loop en productos de la sección (hasta siguiente sección)
  → write({ route_ids: [(4, ruta_id)] })
```

### Validación MTO con Proveedor

Si se asigna ruta MTO (Make-to-Order / Compra bajo pedido):
- Se verifica que el producto tenga al menos un proveedor configurado
- Si no tiene proveedor → `UserError` con instrucciones para configurarlo

---

## Funciones RPC

```typescript
// Asignar ruta a todos los productos de una sección
asignar_ruta_seccion(params: {
  linea_seccion_id: UUID
  ruta_id: UUID
}): {
  productos_actualizados: number
  es_para_taller: boolean
}

// Quitar rutas de todos los productos de una sección
quitar_rutas_seccion(linea_seccion_id: UUID): {
  productos_actualizados: number
}

// Obtener rutas disponibles
get_rutas_disponibles(empresa_id: UUID): [{
  id: UUID
  nombre: string
  es_taller: boolean
  es_mto: boolean
  es_mts: boolean   // Make-to-Stock
}]

// Verificar si productos de OV tienen rutas incompletas
verificar_rutas_ov(orden_venta_id: UUID): {
  completo: boolean
  lineas_sin_ruta: [{
    linea_id: UUID
    producto: string
  }]
  lineas_para_taller: [{
    linea_id: UUID
    producto: string
    cantidad: number
  }]
}
```

---

## Validaciones de Negocio

- Solo líneas de tipo `producto` reciben rutas (no secciones, no notas)
- Productos con ruta MTO deben tener proveedor configurado
- Al confirmar la OV, las rutas ya están asignadas → Odoo genera las órdenes de compra/fabricación correspondientes automáticamente
- Si `is_for_workshop = true` → la línea genera una orden de producción (si existe módulo fabricación) o una tarea de taller

---

## Pantallas Flutter

### OV con Secciones y Rutas

```
┌────────────────────────────────────────────────────────┐
│ ORDEN DE VENTA OV-0089                                 │
├────────────────────────────────────────────────────────┤
│ ▶ BODEGA [Asignar ruta] [Quitar rutas]                 │
│   Silla Ejecutiva    ×5   $150   [Bodega ▼]            │
│   Mesa Reuniones     ×2   $480   [Bodega ▼]            │
├────────────────────────────────────────────────────────┤
│ ▶ TALLER [Asignar ruta] [Quitar rutas]       🔨        │
│   Escritorio medida  ×3  $320   [Taller ▼]  🔨         │
│   Mueble esquinero   ×1  $580   [Taller ▼]  🔨         │
├────────────────────────────────────────────────────────┤
│ Total: $3,490.00          [Confirmar Orden]             │
└────────────────────────────────────────────────────────┘
```

Icono 🔨 indica productos que irán al taller (`is_for_workshop = true`).

---

## Modelo de Datos SQL Completo

### Tabla: `rutas_stock`

Catálogo de rutas disponibles por empresa. Cada empresa define sus propias rutas (bodega local, taller, importación, MTO, MTS, etc.).

```sql
CREATE TABLE rutas_stock (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id        UUID NOT NULL REFERENCES empresas(id),
  nombre            TEXT NOT NULL,
  codigo            TEXT,                              -- código corto identificador
  tipo              TEXT NOT NULL DEFAULT 'MTS'
                    CHECK (tipo IN (
                      'MTS',        -- Make-to-Stock: despacha desde bodega existente
                      'MTO',        -- Make-to-Order: compra/fabricación bajo pedido
                      'ENSAMBLAJE', -- Ensamblar antes de despachar
                      'IMPORTACION',-- Requiere importación
                      'TALLER',     -- Trabajo en taller (reparación/fabricación)
                      'OTRO'
                    )),
  es_para_taller    BOOLEAN NOT NULL DEFAULT FALSE,   -- genera orden de taller
  es_mto            BOOLEAN NOT NULL DEFAULT FALSE,   -- requiere compra previa
  requiere_proveedor BOOLEAN NOT NULL DEFAULT FALSE,  -- validar proveedor en producto
  requiere_bom      BOOLEAN NOT NULL DEFAULT FALSE,   -- validar BOM antes de confirmar
  bodega_origen_id  UUID REFERENCES bodegas(id),     -- bodega de despacho predeterminada
  secuencia         INT NOT NULL DEFAULT 10,
  activo            BOOLEAN NOT NULL DEFAULT TRUE,
  notas             TEXT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE rutas_stock ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON rutas_stock FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE INDEX idx_rutas_stock_empresa    ON rutas_stock(empresa_id);
CREATE INDEX idx_rutas_stock_tipo       ON rutas_stock(empresa_id, tipo) WHERE activo = TRUE;
CREATE UNIQUE INDEX idx_rutas_stock_codigo ON rutas_stock(empresa_id, codigo)
  WHERE codigo IS NOT NULL AND activo = TRUE;
```

### Tabla: `ordenes_venta_secciones`

Agrupa líneas de una OV bajo un encabezado de sección. Una sección puede tener una ruta asignada globalmente que se propaga a todas sus líneas.

```sql
CREATE TABLE ordenes_venta_secciones (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id       UUID NOT NULL REFERENCES empresas(id),
  orden_venta_id   UUID NOT NULL REFERENCES ordenes_venta(id) ON DELETE CASCADE,
  nombre           TEXT NOT NULL,                     -- ej: "Bodega", "Taller", "Importados"
  secuencia        INT NOT NULL DEFAULT 10,           -- orden de aparición en la OV
  ruta_id          UUID REFERENCES rutas_stock(id),  -- ruta asignada a toda la sección
  es_para_taller   BOOLEAN NOT NULL DEFAULT FALSE,   -- calculado: ruta.es_para_taller
  color            TEXT,                              -- color de encabezado en UI (hex)
  notas            TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE ordenes_venta_secciones ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON ordenes_venta_secciones FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE INDEX idx_ordenes_venta_secciones_orden   ON ordenes_venta_secciones(orden_venta_id);
CREATE INDEX idx_ordenes_venta_secciones_empresa ON ordenes_venta_secciones(empresa_id);
```

### Extensión de `ordenes_venta_lineas` (referencia a sección)

```sql
ALTER TABLE ordenes_venta_lineas
  ADD COLUMN seccion_id      UUID REFERENCES ordenes_venta_secciones(id),
  ADD COLUMN ruta_id         UUID REFERENCES rutas_stock(id),
  ADD COLUMN es_para_taller  BOOLEAN NOT NULL DEFAULT FALSE;

CREATE INDEX idx_ov_lineas_seccion ON ordenes_venta_lineas(seccion_id);
CREATE INDEX idx_ov_lineas_ruta    ON ordenes_venta_lineas(ruta_id);
```

### Tabla: `ordenes_ensamblaje` (órdenes generadas al confirmar OV)

```sql
CREATE TABLE ordenes_ensamblaje (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id       UUID NOT NULL REFERENCES empresas(id),
  orden_venta_id   UUID NOT NULL REFERENCES ordenes_venta(id),
  linea_id         UUID NOT NULL REFERENCES ordenes_venta_lineas(id),
  producto_id      UUID NOT NULL REFERENCES productos(id),
  cantidad         DECIMAL(18,6) NOT NULL,
  unidad_medida_id UUID REFERENCES unidades_medida(id),
  bom_id           UUID REFERENCES boms(id),           -- BOM usado
  estado           TEXT NOT NULL DEFAULT 'PENDIENTE'
                   CHECK (estado IN ('PENDIENTE','EN_PROCESO','TERMINADO','CANCELADO')),
  fecha_inicio     TIMESTAMPTZ,
  fecha_fin_estimada TIMESTAMPTZ,
  fecha_fin_real   TIMESTAMPTZ,
  bodega_destino_id UUID REFERENCES bodegas(id),
  notas            TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE ordenes_ensamblaje ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON ordenes_ensamblaje FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE INDEX idx_ordenes_ensamblaje_ov      ON ordenes_ensamblaje(orden_venta_id);
CREATE INDEX idx_ordenes_ensamblaje_empresa ON ordenes_ensamblaje(empresa_id);
CREATE INDEX idx_ordenes_ensamblaje_estado  ON ordenes_ensamblaje(empresa_id, estado);
```

---

## Funciones RPC SQL Completas

### `assign_route_to_section(p_orden_id, p_seccion_id, p_ruta_id)`

Asigna una ruta de stock a todas las líneas de producto de una sección. Valida que líneas MTO tengan proveedor configurado.

```sql
CREATE OR REPLACE FUNCTION ventas.assign_route_to_section(
  p_orden_id   UUID,
  p_seccion_id UUID,
  p_ruta_id    UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_ruta          rutas_stock%ROWTYPE;
  v_empresa_id    UUID;
  v_count_updated INT := 0;
  v_count_sin_proveedor INT := 0;
  v_linea         RECORD;
BEGIN
  -- Obtener empresa del contexto
  v_empresa_id := (SELECT private.get_empresa_id());

  -- Validar que la ruta pertenezca a la empresa
  SELECT * INTO v_ruta
  FROM rutas_stock
  WHERE id = p_ruta_id AND empresa_id = v_empresa_id AND activo = TRUE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ruta no encontrada o no pertenece a la empresa';
  END IF;

  -- Validar que la OV pertenezca a la empresa
  IF NOT EXISTS (
    SELECT 1 FROM ordenes_venta
    WHERE id = p_orden_id AND empresa_id = v_empresa_id
  ) THEN
    RAISE EXCEPTION 'Orden de venta no encontrada';
  END IF;

  -- Validar que la sección pertenezca a la OV
  IF NOT EXISTS (
    SELECT 1 FROM ordenes_venta_secciones
    WHERE id = p_seccion_id AND orden_venta_id = p_orden_id AND empresa_id = v_empresa_id
  ) THEN
    RAISE EXCEPTION 'Sección no pertenece a la orden de venta indicada';
  END IF;

  -- Si es ruta MTO, verificar proveedores
  IF v_ruta.requiere_proveedor THEN
    SELECT COUNT(*) INTO v_count_sin_proveedor
    FROM ordenes_venta_lineas ovl
    WHERE ovl.seccion_id = p_seccion_id
      AND ovl.tipo_linea = 'producto'
      AND NOT EXISTS (
        SELECT 1 FROM producto_proveedores pp
        WHERE pp.producto_id = ovl.producto_id
          AND pp.activo = TRUE
      );

    IF v_count_sin_proveedor > 0 THEN
      RAISE EXCEPTION
        '% producto(s) no tienen proveedor configurado. Configure proveedores antes de asignar ruta MTO.',
        v_count_sin_proveedor;
    END IF;
  END IF;

  -- Actualizar líneas de la sección (solo tipo producto, no secciones ni notas)
  UPDATE ordenes_venta_lineas
  SET
    ruta_id        = p_ruta_id,
    es_para_taller = v_ruta.es_para_taller,
    updated_at     = NOW()
  WHERE seccion_id  = p_seccion_id
    AND tipo_linea  = 'producto';

  GET DIAGNOSTICS v_count_updated = ROW_COUNT;

  -- Actualizar el campo ruta en la sección
  UPDATE ordenes_venta_secciones
  SET
    ruta_id        = p_ruta_id,
    es_para_taller = v_ruta.es_para_taller,
    updated_at     = NOW()
  WHERE id = p_seccion_id;

  RETURN jsonb_build_object(
    'success',           TRUE,
    'productos_actualizados', v_count_updated,
    'ruta_nombre',       v_ruta.nombre,
    'es_para_taller',    v_ruta.es_para_taller,
    'es_mto',            v_ruta.es_mto
  );
END;
$$;
```

### `validate_assembly_bom(p_orden_id)`

Verifica que todas las líneas con ruta ENSAMBLAJE tengan una BOM (lista de materiales) activa disponible en el sistema.

```sql
CREATE OR REPLACE FUNCTION ventas.validate_assembly_bom(
  p_orden_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_empresa_id      UUID;
  v_lineas_sin_bom  JSONB := '[]'::JSONB;
  v_linea           RECORD;
  v_valido          BOOLEAN := TRUE;
BEGIN
  v_empresa_id := (SELECT private.get_empresa_id());

  -- Buscar líneas con ruta ENSAMBLAJE sin BOM disponible
  FOR v_linea IN
    SELECT
      ovl.id              AS linea_id,
      p.nombre            AS producto_nombre,
      p.codigo_interno    AS producto_codigo,
      ovl.cantidad,
      ovl.ruta_id,
      rs.nombre           AS ruta_nombre
    FROM ordenes_venta_lineas ovl
    JOIN ordenes_venta ov      ON ov.id = ovl.orden_venta_id
    JOIN productos p           ON p.id  = ovl.producto_id
    JOIN rutas_stock rs        ON rs.id = ovl.ruta_id
    WHERE ovl.orden_venta_id = p_orden_id
      AND ov.empresa_id      = v_empresa_id
      AND rs.tipo            = 'ENSAMBLAJE'
      AND ovl.tipo_linea     = 'producto'
      AND NOT EXISTS (
        SELECT 1 FROM boms b
        WHERE b.producto_id  = ovl.producto_id
          AND b.empresa_id   = v_empresa_id
          AND b.activo       = TRUE
      )
  LOOP
    v_valido := FALSE;
    v_lineas_sin_bom := v_lineas_sin_bom || jsonb_build_object(
      'linea_id',       v_linea.linea_id,
      'producto',       v_linea.producto_nombre,
      'codigo',         v_linea.producto_codigo,
      'cantidad',       v_linea.cantidad,
      'ruta',           v_linea.ruta_nombre
    );
  END LOOP;

  RETURN jsonb_build_object(
    'valido',          v_valido,
    'lineas_sin_bom',  v_lineas_sin_bom,
    'total_sin_bom',   jsonb_array_length(v_lineas_sin_bom)
  );
END;
$$;
```

### `process_assembly_order(p_orden_id)`

Al confirmar la OV, crea órdenes de ensamblaje en Inventario vía Module Service Bus para todas las líneas con ruta ENSAMBLAJE o TALLER.

```sql
CREATE OR REPLACE FUNCTION ventas.process_assembly_order(
  p_orden_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_empresa_id        UUID;
  v_ov                ordenes_venta%ROWTYPE;
  v_linea             RECORD;
  v_orden_ensamblaje  UUID;
  v_ordenes_creadas   INT := 0;
  v_errores           JSONB := '[]'::JSONB;
  v_bom_id            UUID;
  v_result            JSONB;
BEGIN
  v_empresa_id := (SELECT private.get_empresa_id());

  -- Obtener la OV
  SELECT * INTO v_ov
  FROM ordenes_venta
  WHERE id = p_orden_id AND empresa_id = v_empresa_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Orden de venta % no encontrada', p_orden_id;
  END IF;

  -- Validar estado: solo OVs confirmadas generan ensamblajes
  IF v_ov.estado NOT IN ('sale', 'confirmada') THEN
    RAISE EXCEPTION 'La OV debe estar confirmada para generar órdenes de ensamblaje';
  END IF;

  -- Procesar cada línea con ruta de ensamblaje o taller
  FOR v_linea IN
    SELECT
      ovl.id            AS linea_id,
      ovl.producto_id,
      ovl.cantidad,
      ovl.unidad_medida_id,
      ovl.ruta_id,
      rs.tipo           AS ruta_tipo,
      rs.bodega_origen_id
    FROM ordenes_venta_lineas ovl
    JOIN rutas_stock rs ON rs.id = ovl.ruta_id
    WHERE ovl.orden_venta_id = p_orden_id
      AND ovl.tipo_linea     = 'producto'
      AND rs.tipo            IN ('ENSAMBLAJE', 'TALLER')
      AND NOT EXISTS (
        -- No duplicar si ya existe orden creada
        SELECT 1 FROM ordenes_ensamblaje oe
        WHERE oe.linea_id = ovl.id AND oe.estado != 'CANCELADO'
      )
  LOOP
    -- Buscar BOM activa para el producto
    SELECT id INTO v_bom_id
    FROM boms
    WHERE producto_id = v_linea.producto_id
      AND empresa_id  = v_empresa_id
      AND activo      = TRUE
    ORDER BY fecha_inicio DESC NULLS LAST
    LIMIT 1;

    -- Llamar a module_bus para crear la orden de ensamblaje en Inventario
    v_result := module_bus.inventario.create_assembly_order(
      jsonb_build_object(
        'empresa_id',        v_empresa_id,
        'origen_ref',        v_ov.numero,
        'orden_venta_id',    p_orden_id,
        'linea_id',          v_linea.linea_id,
        'producto_id',       v_linea.producto_id,
        'cantidad',          v_linea.cantidad,
        'unidad_medida_id',  v_linea.unidad_medida_id,
        'bom_id',            v_bom_id,
        'bodega_destino_id', v_linea.bodega_origen_id,
        'fecha_estimada',    v_ov.fecha_entrega
      )
    );

    IF (v_result->>'success')::BOOLEAN THEN
      -- Registrar la orden localmente
      INSERT INTO ordenes_ensamblaje (
        empresa_id, orden_venta_id, linea_id, producto_id,
        cantidad, unidad_medida_id, bom_id, estado,
        bodega_destino_id, fecha_fin_estimada
      ) VALUES (
        v_empresa_id, p_orden_id, v_linea.linea_id, v_linea.producto_id,
        v_linea.cantidad, v_linea.unidad_medida_id, v_bom_id, 'PENDIENTE',
        v_linea.bodega_origen_id, v_ov.fecha_entrega
      );
      v_ordenes_creadas := v_ordenes_creadas + 1;
    ELSE
      v_errores := v_errores || jsonb_build_object(
        'linea_id', v_linea.linea_id,
        'error',    v_result->>'message'
      );
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'success',         v_ordenes_creadas > 0 OR jsonb_array_length(v_errores) = 0,
    'ordenes_creadas', v_ordenes_creadas,
    'errores',         v_errores
  );
END;
$$;
```

---

## Integración con Module Service Bus

Al confirmar una OV que contenga líneas de taller o ensamblaje:

```sql
-- Trigger en ordenes_venta al pasar a estado 'sale'
CREATE OR REPLACE FUNCTION ventas.trg_ov_confirmed_assembly()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Solo actuar cuando la OV pasa a confirmada
  IF NEW.estado IN ('sale', 'confirmada') AND OLD.estado != NEW.estado THEN
    -- Verificar si hay líneas de ensamblaje
    IF EXISTS (
      SELECT 1
      FROM ordenes_venta_lineas ovl
      JOIN rutas_stock rs ON rs.id = ovl.ruta_id
      WHERE ovl.orden_venta_id = NEW.id
        AND rs.tipo IN ('ENSAMBLAJE', 'TALLER')
    ) THEN
      -- Procesar asincrónicamente o sincrónicamente según configuración
      PERFORM ventas.process_assembly_order(NEW.id);
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_ov_confirmed_assembly
  AFTER UPDATE OF estado ON ordenes_venta
  FOR EACH ROW EXECUTE FUNCTION ventas.trg_ov_confirmed_assembly();
```

### Contrato module_bus.inventario.create_assembly_order()

```sql
-- Función gateway en module_bus que verifica si Inventario está activo
CREATE OR REPLACE FUNCTION module_bus.inventario.create_assembly_order(p_params JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Verificar módulo activo
  IF NOT EXISTS (
    SELECT 1 FROM modulos_empresa
    WHERE modulo_codigo = 'inventario'
      AND empresa_id    = (p_params->>'empresa_id')::UUID
      AND activo        = TRUE
  ) THEN
    RETURN jsonb_build_object('success', FALSE, 'message', 'Módulo Inventario no activo');
  END IF;

  -- Delegar a la función real de Inventario
  RETURN inventario.create_assembly_order_internal(p_params);
END;
$$;
```

---

## Índices Adicionales

```sql
-- Índices para consultas frecuentes de rutas por tipo
CREATE INDEX idx_rutas_stock_taller     ON rutas_stock(empresa_id) WHERE es_para_taller = TRUE AND activo = TRUE;
CREATE INDEX idx_rutas_stock_mto        ON rutas_stock(empresa_id) WHERE es_mto = TRUE AND activo = TRUE;

-- Índices para líneas con rutas asignadas
CREATE INDEX idx_ov_lineas_taller       ON ordenes_venta_lineas(orden_venta_id) WHERE es_para_taller = TRUE;
CREATE INDEX idx_ordenes_ensamblaje_linea ON ordenes_ensamblaje(linea_id);
```

---

## Seed Data: Rutas Estándar

```sql
-- Insertar rutas base al activar el módulo en una empresa
-- (ejecutar en migración o en función de activación de empresa)
INSERT INTO rutas_stock (empresa_id, nombre, codigo, tipo, es_para_taller, es_mto, requiere_proveedor, requiere_bom, secuencia)
VALUES
  (:empresa_id, 'Desde Bodega',    'MTS',         'MTS',        FALSE, FALSE, FALSE, FALSE, 10),
  (:empresa_id, 'Bajo Pedido',     'MTO',         'MTO',        FALSE, TRUE,  TRUE,  FALSE, 20),
  (:empresa_id, 'Ensamblaje',      'ENSAMBLAR',   'ENSAMBLAJE', FALSE, FALSE, FALSE, TRUE,  30),
  (:empresa_id, 'Taller',          'TALLER',      'TALLER',     TRUE,  FALSE, FALSE, FALSE, 40),
  (:empresa_id, 'Importación',     'IMPORTAR',    'IMPORTACION',FALSE, TRUE,  TRUE,  FALSE, 50);
```
