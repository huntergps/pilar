# Conversión de Productos (Stock)

*Spec derivada del módulo `l10n_ec_stock_conversion` (Odoo 19.1 Ecuador — producción en csolish/tecnoh)*

---

## Descripción

Permite convertir unidades de un producto en unidades de otro producto diferente dentro del inventario. Casos de uso: cambiar presentación (caja → unidades sueltas), transformación de productos, re-empaque. Genera dos movimientos de stock inversos: salida del producto origen y entrada del producto destino. Admite lotes/series en el producto origen.

---

## Casos de Uso Ecuador

| Caso | Origen | Destino |
|---|---|---|
| Fraccionamiento | Caja × 24 unidades | Unidad suelta |
| Re-empaque | Bolsa 1kg | Bolsa 500g (×2) |
| Conversión de combo | Combo completo | Componentes individuales |
| Cambio de presentación | Galón | Litros (×4) |

---

## Modelo de Datos

### Tabla: `conversiones_stock`

```sql
CREATE TABLE conversiones_stock (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id        UUID NOT NULL REFERENCES empresas(id),
  nombre            TEXT NOT NULL,           -- "CONV-0001"
  fecha             DATE NOT NULL DEFAULT CURRENT_DATE,
  responsable_id    UUID REFERENCES usuarios(id),
  contacto_id       UUID REFERENCES contactos(id),   -- opcional
  estado            TEXT DEFAULT 'borrador'
                    CHECK (estado IN ('borrador','confirmado','cancelado')),
  -- Producto origen
  producto_origen_id   UUID NOT NULL REFERENCES productos(id),
  cantidad_origen      NUMERIC(16,4) NOT NULL,
  ubicacion_origen_id  UUID NOT NULL REFERENCES ubicaciones_stock(id),
  lote_origen_ids      UUID[],               -- lotes del producto a convertir
  -- Producto destino
  producto_destino_id  UUID NOT NULL REFERENCES productos(id),
  cantidad_destino     NUMERIC(16,4) NOT NULL,
  ubicacion_destino_id UUID NOT NULL REFERENCES ubicaciones_stock(id),
  -- Movimientos generados
  movimiento_salida_id UUID REFERENCES stock_moves(id),
  movimiento_entrada_id UUID REFERENCES stock_moves(id),
  -- Notas
  notas             TEXT
);

ALTER TABLE conversiones_stock ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON conversiones_stock FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));
```

---

## Flujo de Conversión

```
1. BORRADOR
   - Seleccionar producto origen + ubicación + cantidad + lotes
   - Seleccionar producto destino + ubicación + cantidad resultado
   - Sistema calcula ratio: cantidad_destino / cantidad_origen

2. CONFIRMAR
   - Validar stock disponible de producto origen en ubicación
   - Crear movimiento SALIDA: origen_prod → ubicacion_virtual_conversion
   - Crear movimiento ENTRADA: ubicacion_virtual_conversion → destino_prod
   - Validar ambos movimientos → estado 'hecho'
   - Conversión pasa a estado 'confirmado'

3. CANCELADO (solo desde borrador)
   - No genera movimientos
```

---

## Ratio de Conversión

El ratio se muestra informativo pero no se almacena:
```
ratio = cantidad_destino / cantidad_origen

Ejemplo: 1 caja → 24 unidades → ratio = 24
```

---

## Funciones RPC

```typescript
// Verificar stock disponible antes de convertir
verificar_stock_conversion(params: {
  producto_id: UUID
  ubicacion_id: UUID
  cantidad: number
  lote_ids?: UUID[]
}): {
  disponible: number
  suficiente: boolean
  deficit: number
}

// Confirmar conversión y generar movimientos
confirmar_conversion(params: {
  conversion_id: UUID
}): {
  conversion_id: UUID
  movimiento_salida_id: UUID
  movimiento_entrada_id: UUID
  estado: 'confirmado'
}

// Obtener historial de conversiones de un producto
get_conversiones_producto(params: {
  producto_id: UUID
  fecha_desde?: string
  fecha_hasta?: string
}): [{
  conversion_id: UUID
  nombre: string
  fecha: string
  como: 'origen' | 'destino'
  cantidad: number
  contraparte_producto: string
  estado: string
}]

// Calcular ratio automático
calcular_ratio(params: {
  producto_origen_id: UUID
  producto_destino_id: UUID
}): {
  ratio_sugerido: number
  uom_origen: string
  uom_destino: string
}
```

---

## Configuración por Empresa

```sql
-- Ubicación virtual de tránsito para conversiones
-- Se configura una ubicación interna especial (virtual) que actúa como intermediaria
INSERT INTO ubicaciones_stock (nombre, tipo, empresa_id)
VALUES ('Conversión Virtual', 'virtual', :empresa_id);
```

```json
{
  "conversion_stock": {
    "ubicacion_virtual_conversion_id": "uuid",
    "requiere_aprobacion": false,
    "permitir_lotes_origen": true
  }
}
```

---

## Validaciones de Negocio

- Producto origen y destino deben ser distintos
- `cantidad_origen > 0` y `cantidad_destino > 0`
- Stock disponible en ubicación origen debe ser ≥ `cantidad_origen`
- Si se especifican lotes, deben pertenecer al producto origen
- No se puede cancelar una conversión confirmada (movimientos ya ejecutados)
- El producto debe ser de tipo `consu` o `combo` (no servicios)

---

## Pantallas Flutter

### Formulario de Conversión

```
┌────────────────────────────────────────────────────────┐
│ CONVERSIÓN DE STOCK — CONV-0001                        │
├────────────────────────────────────────────────────────┤
│ PRODUCTO ORIGEN                                        │
│ Producto:  [Caja Cerámica 60×60 ▼]                    │
│ Cantidad:  [1.000]                                     │
│ Ubicación: [Bodega Principal ▼]                        │
│ Lotes:     [LOT-2024-001, LOT-2024-002]               │
│ Stock disponible: 15 cajas                             │
├────────────────────────────────────────────────────────┤
│ PRODUCTO DESTINO                                       │
│ Producto:  [Cerámica 60×60 Unidad ▼]                  │
│ Cantidad:  [12.000]  (ratio: 12 und/caja)              │
│ Ubicación: [Bodega Principal ▼]                        │
├────────────────────────────────────────────────────────┤
│ Notas: [Fraccionamiento para venta al detalle   ]      │
├────────────────────────────────────────────────────────┤
│ [Guardar Borrador]  [Confirmar Conversión]             │
└────────────────────────────────────────────────────────┘
```

### Lista de Conversiones

- `CrudScaffold<ConversionStock>` filtros: estado, producto, período
- Columnas: nombre, fecha, prod_origen, cant_origen, prod_destino, cant_destino, ratio, estado

---

## Modelo de Datos Completo

La tabla existente `conversiones_stock` (en el modelo de datos anterior) usa la estructura de Odoo. La tabla PILAR nativa agrega campos de costo y estados adicionales:

```sql
CREATE TABLE conversiones_stock (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  nombre                TEXT NOT NULL,              -- "CONV-0001" (secuencial)
  producto_origen_id    UUID NOT NULL REFERENCES productos(id),
  producto_destino_id   UUID NOT NULL REFERENCES productos(id),
  bodega_id             UUID NOT NULL REFERENCES bodegas(id),
  cantidad_origen       DECIMAL(18,6) NOT NULL CHECK (cantidad_origen > 0),
  cantidad_destino      DECIMAL(18,6) NOT NULL CHECK (cantidad_destino > 0),
  factor_conversion     DECIMAL(18,6) GENERATED ALWAYS AS
                          (cantidad_destino / cantidad_origen) STORED,
  costo_conversion      DECIMAL(14,2) DEFAULT 0,   -- Costo del proceso (mano de obra, etc.)
  fecha                 DATE NOT NULL DEFAULT CURRENT_DATE,
  estado                VARCHAR(15) DEFAULT 'BORRADOR'
                        CHECK (estado IN ('BORRADOR','CONFIRMADO','ANULADO')),
  movimiento_salida_id  UUID REFERENCES movimientos_inventario(id),
  movimiento_entrada_id UUID REFERENCES movimientos_inventario(id),
  asiento_id            UUID,                       -- Referencia al asiento contable (soft)
  responsable_id        UUID REFERENCES auth.users(id),
  notas                 TEXT,
  created_at            TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE conversiones_stock ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON conversiones_stock FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));
```

**Campo `factor_conversion`**: generado automáticamente como `cantidad_destino / cantidad_origen`. Permite consultas como "todas las conversiones con factor > 10" sin cálculo extra.

**Campo `costo_conversion`**: costo adicional del proceso de conversión (p.ej., mano de obra, energía). Se distribuye proporcionalmente al calcular el CPP del producto destino.

---

## Funciones RPC Adicionales

### `create_stock_conversion` — Crear y validar disponibilidad

```sql
CREATE OR REPLACE FUNCTION create_stock_conversion(
  p_origen_id         UUID,
  p_destino_id        UUID,
  p_bodega_id         UUID,
  p_cantidad_origen   DECIMAL(18,6),
  p_cantidad_destino  DECIMAL(18,6),
  p_costo_conversion  DECIMAL(14,2) DEFAULT 0,
  p_notas             TEXT          DEFAULT NULL
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_empresa_id   UUID;
  v_stock_actual DECIMAL(18,6);
  v_conv_id      UUID;
  v_secuencial   TEXT;
BEGIN
  v_empresa_id := (SELECT private.get_empresa_id());

  -- Validar que origen != destino
  IF p_origen_id = p_destino_id THEN
    RAISE EXCEPTION 'El producto origen y destino deben ser diferentes';
  END IF;

  -- Verificar stock disponible en bodega
  SELECT COALESCE(cantidad, 0) INTO v_stock_actual
  FROM inventario_stock
  WHERE empresa_id = v_empresa_id
    AND producto_id = p_origen_id
    AND bodega_id = p_bodega_id;

  IF v_stock_actual < p_cantidad_origen THEN
    RAISE EXCEPTION 'Stock insuficiente: disponible=%, requerido=%',
      v_stock_actual, p_cantidad_origen;
  END IF;

  -- Generar nombre secuencial
  SELECT 'CONV-' || LPAD(
    (COUNT(*) + 1)::TEXT, 4, '0'
  ) INTO v_secuencial
  FROM conversiones_stock WHERE empresa_id = v_empresa_id;

  INSERT INTO conversiones_stock (
    empresa_id, nombre,
    producto_origen_id, producto_destino_id, bodega_id,
    cantidad_origen, cantidad_destino, costo_conversion,
    fecha, notas
  ) VALUES (
    v_empresa_id, v_secuencial,
    p_origen_id, p_destino_id, p_bodega_id,
    p_cantidad_origen, p_cantidad_destino, p_costo_conversion,
    CURRENT_DATE, p_notas
  ) RETURNING id INTO v_conv_id;

  RETURN v_conv_id;
END;
$$;
```

### `process_stock_conversion` — Confirmar y generar movimientos

```sql
CREATE OR REPLACE FUNCTION process_stock_conversion(p_conversion_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_conv          RECORD;
  v_costo_origen  DECIMAL(14,6);   -- CPP del producto origen
  v_costo_destino DECIMAL(14,6);   -- CPP calculado para producto destino
  v_mov_salida_id UUID;
  v_mov_entrada_id UUID;
BEGIN
  SELECT c.*, p.costo_promedio AS cpp_origen
  INTO v_conv
  FROM conversiones_stock c
  JOIN productos p ON p.id = c.producto_origen_id
  WHERE c.id = p_conversion_id
    AND c.empresa_id = (SELECT private.get_empresa_id())
    AND c.estado = 'BORRADOR';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Conversión no encontrada o ya fue procesada';
  END IF;

  -- Calcular costo del producto destino:
  -- costo_unitario_destino = (costo_origen_total + costo_conversion) / cantidad_destino
  v_costo_origen  := v_conv.cpp_origen * v_conv.cantidad_origen;
  v_costo_destino := ROUND(
    (v_costo_origen + v_conv.costo_conversion) / v_conv.cantidad_destino, 6
  );

  -- Movimiento SALIDA del producto origen
  INSERT INTO movimientos_inventario (
    empresa_id, producto_id, bodega_id,
    tipo_movimiento, cantidad, costo_unitario,
    referencia, estado, fecha
  ) VALUES (
    v_conv.empresa_id, v_conv.producto_origen_id, v_conv.bodega_id,
    'CONVERSION_SALIDA', v_conv.cantidad_origen, v_conv.cpp_origen,
    v_conv.nombre, 'CONFIRMADO', v_conv.fecha
  ) RETURNING id INTO v_mov_salida_id;

  -- Movimiento ENTRADA del producto destino
  INSERT INTO movimientos_inventario (
    empresa_id, producto_id, bodega_id,
    tipo_movimiento, cantidad, costo_unitario,
    referencia, estado, fecha
  ) VALUES (
    v_conv.empresa_id, v_conv.producto_destino_id, v_conv.bodega_id,
    'CONVERSION_ENTRADA', v_conv.cantidad_destino, v_costo_destino,
    v_conv.nombre, 'CONFIRMADO', v_conv.fecha
  ) RETURNING id INTO v_mov_entrada_id;

  -- Actualizar stock
  UPDATE inventario_stock
  SET cantidad = cantidad - v_conv.cantidad_origen
  WHERE empresa_id = v_conv.empresa_id
    AND producto_id = v_conv.producto_origen_id
    AND bodega_id = v_conv.bodega_id;

  INSERT INTO inventario_stock (empresa_id, producto_id, bodega_id, cantidad)
  VALUES (v_conv.empresa_id, v_conv.producto_destino_id, v_conv.bodega_id, v_conv.cantidad_destino)
  ON CONFLICT (empresa_id, producto_id, bodega_id)
  DO UPDATE SET cantidad = inventario_stock.cantidad + EXCLUDED.cantidad;

  -- Recalcular CPP del producto destino (promedio ponderado)
  UPDATE productos
  SET costo_promedio = ROUND(
    (COALESCE(costo_promedio, 0) * COALESCE(
      (SELECT cantidad FROM inventario_stock
       WHERE empresa_id = v_conv.empresa_id
         AND producto_id = v_conv.producto_destino_id
         AND bodega_id = v_conv.bodega_id), 0
    ) + v_costo_destino * v_conv.cantidad_destino)
    /
    NULLIF(COALESCE(
      (SELECT cantidad FROM inventario_stock
       WHERE empresa_id = v_conv.empresa_id
         AND producto_id = v_conv.producto_destino_id
         AND bodega_id = v_conv.bodega_id), 0
    ) + v_conv.cantidad_destino, 0), 6
  )
  WHERE id = v_conv.producto_destino_id;

  -- Actualizar conversión
  UPDATE conversiones_stock SET
    estado = 'CONFIRMADO',
    movimiento_salida_id  = v_mov_salida_id,
    movimiento_entrada_id = v_mov_entrada_id
  WHERE id = p_conversion_id;
END;
$$;
```

---

## Casos de Uso Ecuador (Ejemplos Reales)

### Ferretería: Rollo de alambre → Piezas individuales

```
Producto origen:  Rollo alambre galvanizado #14 (100m)   CPP: $25.00/rollo
Producto destino: Alambre galvanizado #14 metro (1m)      CPP: ?

Conversión: 1 rollo → 100 metros
  factor_conversion = 100 / 1 = 100

Cálculo CPP destino:
  costo_origen = 1 × $25.00 = $25.00
  costo_conversion = $0.50 (corte manual)
  costo_total = $25.00 + $0.50 = $25.50
  CPP metro = $25.50 / 100 = $0.255/metro

Movimientos:
  CONVERSION_SALIDA: 1 rollo @ $25.00
  CONVERSION_ENTRADA: 100 metros @ $0.255
```

### Distribuidora: Funda grande → Fundas pequeñas

```
Producto origen:  Azúcar morena 5kg         CPP: $3.20/funda
Producto destino: Azúcar morena 500g        CPP: ?

Conversión: 1 funda 5kg → 10 fundas 500g
  factor_conversion = 10

Cálculo CPP destino:
  costo_origen = 1 × $3.20 = $3.20
  costo_conversion = $0.30 (bolsas + sellado)
  CPP 500g = ($3.20 + $0.30) / 10 = $0.35/funda

Precio de venta 500g recomendado:
  Margen 40% → $0.35 × 1.40 = $0.49 → precio venta $0.50
```

### Panadería: Harina en sacos → Kilos para producción

```
Producto origen:  Harina 50kg (saco)   CPP: $18.00/saco
Producto destino: Harina por kilo      CPP: ?

Conversión: 1 saco 50kg → 50 kg sueltos
  factor_conversion = 50

CPP por kg = $18.00 / 50 = $0.36/kg

Nota: Para la panadería que consume múltiples ingredientes (harina + azúcar + mantequilla)
para producir pan, usar BOM/Ensamblaje del inventario en lugar de esta función.
Esta función aplica solo para conversiones simples 1-producto → N-unidades del mismo material.
```

---

## Relación con BOM/Ensamblaje

```
Conversión de Stock (este módulo)          BOM/Ensamblaje (Inventario)
──────────────────────────────             ─────────────────────────────
1 producto origen → 1 producto destino     N insumos → 1 producto terminado
Fraccionamiento / re-empaque               Manufactura / ensamblaje
Sin consumo de otros insumos               Consume varios materiales
Sin órdenes de producción                  Con órdenes de producción
Instantáneo                                Multi-etapa con operaciones
```

Usar **Conversión de Stock** cuando: cambio de presentación del mismo material (caja→unidades, saco→kilos, galón→litros).

Usar **BOM/Ensamblaje** cuando: producción real que combina múltiples insumos para crear un producto distinto (pan, mueble, equipo electrónico).

---

## RLS e Índices

```sql
-- Índice principal para búsqueda por empresa y estado
CREATE INDEX idx_conv_stock_empresa_estado
  ON conversiones_stock (empresa_id, estado);

-- Para historial de conversiones de un producto (como origen o destino)
CREATE INDEX idx_conv_stock_origen
  ON conversiones_stock (empresa_id, producto_origen_id, fecha DESC);
CREATE INDEX idx_conv_stock_destino
  ON conversiones_stock (empresa_id, producto_destino_id, fecha DESC);

-- Para búsqueda por bodega
CREATE INDEX idx_conv_stock_bodega
  ON conversiones_stock (empresa_id, bodega_id, fecha DESC);
```
