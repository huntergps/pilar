# Módulo: Entidades Compartidas (core)

## Descripción

Entidades maestras compartidas por todos los módulos: Contactos (clientes, proveedores, empleados) y Productos (artículos, servicios, presentaciones, precios, familias). Estos modelos son el núcleo del ERP y son consumidos por todos los módulos Core y Auxiliares.

## Funcionalidades

### Contactos
- Clientes, proveedores, empleados, empresas, personas naturales
- Multi-dirección (fiscal en contactos.direccion, adicionales en contacto_direcciones)
- Identificación SRI: RUC, cédula, pasaporte
- Crédito: límite, plazo, días crédito
- Portal access_token para autoservicio
- Notificaciones: canales preferidos (email/WhatsApp/Telegram)

### Productos
- Artículos físicos y servicios
- Multi-presentación: presentaciones con factor de conversión
- Multi-código de barras por presentación
- Unidades de medida con conversión
- Series y lotes para trazabilidad
- Listas de precios por empresa/segmento/fecha

### Familias y Atributos Descriptivos
- **Familias**: agrupan productos relacionados (ej: "Camiseta Deportiva") sin complejidad de variantes. Cada SKU sigue siendo un producto independiente con su propio stock, barcode y precio.
- **Atributos descriptivos (EAV)**: etiquetas clave-valor por producto (`talla=M`, `color=Rojo`, `material=Algodón`). Permiten filtrar en POS/búsqueda y construir vistas de grilla (filas=tallas × columnas=colores).
- Sin auto-generación de combinaciones: los productos se crean manualmente o via importación masiva.

## Dependencias (módulos requeridos)

- `foundation` — Core foundation únicamente

## Tablas Principales

- `contactos` — Clientes, proveedores, personas
- `contacto_direcciones` — Direcciones adicionales (ENTREGA/SUCURSAL/BODEGA)
- `productos` — Catálogo unificado artículos + servicios (campo `familia_id` nullable)
- `producto_presentaciones` — Multi-empaque con factor_conversion
- `producto_codigos_barras` — N códigos por presentación
- `producto_familias` — Agrupación visual de SKUs relacionados
- `producto_atributos_desc` — Atributos EAV: talla, color, material, voltaje, etc.
- `listas_precios` — Precios por segmento y vigencia
- `listas_precios_lineas` — Precio por producto/presentación
- `unidades_medida` — UoM con factor de conversión entre sí
- `series_lotes` — Trazabilidad de artículos serializados

## Module Service Bus

```sql
-- Obtener precio vigente de producto
SELECT module_bus.entidades.get_precio_producto(
  p_producto_id UUID,
  p_lista_precios_id UUID,
  p_fecha DATE
) RETURNS DECIMAL;

-- Verificar stock disponible (delega a Inventario)
SELECT module_bus.inventario.get_stock_disponible(
  p_producto_id UUID,
  p_bodega_id UUID
) RETURNS DECIMAL;
```

## Validaciones y Restricciones de Negocio

- RUC/cédula validados con algoritmo de dígito verificador
- No se puede eliminar un contacto con transacciones activas
- Precio sin lista de precios asignada = precio base del producto
- Series/lotes únicos por empresa

## Flujos Principales

1. Crear contacto → validar identificación SRI → asignar portal_token
2. Crear producto simple → definir UoM → añadir presentaciones → asignar precios
3. Crear familia (ej: "Camiseta Deportiva") → crear SKUs hijos (uno por talla/color) → asignar `familia_id` + atributos en `producto_atributos_desc`
4. Actualizar precio → nueva línea en lista_precios_lineas con fecha vigencia

## Sub-docs

- `migrations/001_tables.sql` — DDL contactos, productos, listas_precios + RLS + índices
- `migrations/002_familias_atributos.sql` — Familias de producto + atributos descriptivos EAV + RPCs de grilla

## RPCs

### `search_contact(p_empresa_id, p_identificacion)` — Buscar contacto por RUC/cédula

```sql
CREATE OR REPLACE FUNCTION search_contact(
  p_empresa_id UUID,
  p_identificacion TEXT
) RETURNS SETOF contactos
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT * FROM contactos
  WHERE empresa_id = p_empresa_id
    AND identificacion LIKE p_identificacion || '%'
    AND activo = true
  LIMIT 20;
$$;
```

### `get_account_statement(p_empresa_id, p_contacto_id, p_tipo)` — Estado de cuenta de un contacto

```sql
CREATE OR REPLACE FUNCTION get_account_statement(
  p_empresa_id UUID,
  p_contacto_id UUID,
  p_tipo TEXT DEFAULT 'cliente'  -- 'cliente' o 'proveedor'
) RETURNS TABLE (
  fecha DATE, tipo_doc VARCHAR, numero VARCHAR,
  debe DECIMAL, haber DECIMAL, saldo DECIMAL
)
LANGUAGE sql SECURITY DEFINER AS $$
  -- Facturas emitidas (cuentas por cobrar) o recibidas (cuentas por pagar)
  SELECT f.fecha_emision, '01', de.establecimiento||'-'||de.punto_emision||'-'||de.secuencial,
    CASE WHEN p_tipo = 'cliente' THEN f.importe_total ELSE 0 END,
    CASE WHEN p_tipo = 'proveedor' THEN f.importe_total ELSE 0 END,
    0::DECIMAL -- calculado con window function
  FROM facturas f
  JOIN documentos_electronicos de ON de.id = f.documento_id
  WHERE f.empresa_id = p_empresa_id AND f.contacto_id = p_contacto_id
  ORDER BY f.fecha_emision;
$$;
```

### `search_products(p_empresa_id, p_termino, p_bodega_id)` — Buscar productos con stock

```sql
CREATE OR REPLACE FUNCTION search_products(
  p_empresa_id UUID,
  p_termino TEXT,
  p_bodega_id UUID DEFAULT NULL
) RETURNS TABLE (
  id UUID, codigo_principal VARCHAR, descripcion VARCHAR,
  precio_unitario DECIMAL, tarifa_iva DECIMAL, stock DECIMAL
)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT p.id, p.codigo_principal, p.descripcion,
    p.precio_unitario, p.tarifa_iva,
    COALESCE(s.cantidad, 0) as stock
  FROM productos p
  LEFT JOIN inventario_stock s ON s.producto_id = p.id
    AND (p_bodega_id IS NULL OR s.bodega_id = p_bodega_id)
  WHERE p.empresa_id = p_empresa_id
    AND p.activo = true
    AND (p.descripcion ILIKE '%' || p_termino || '%'
      OR p.codigo_principal ILIKE '%' || p_termino || '%')
  LIMIT 50;
$$;
```

### `search_familias(p_empresa_id, p_query, p_limit)` — Buscar familias de producto

```sql
-- Retorna familias que coinciden con el query (NULL = todas)
SELECT * FROM search_familias('empresa-uuid', 'camiseta');
-- → [{ id, nombre:'Camiseta Deportiva', imagen_url, activo, ... }]
```

### `get_familia_productos(p_empresa_id, p_familia_id)` — Productos de una familia con atributos

```sql
-- Retorna todos los SKUs de la familia con sus atributos como JSONB
SELECT * FROM get_familia_productos('empresa-uuid', 'familia-uuid');
-- → [
--     { producto_id, codigo:'CAM-RJ-M', nombre:'Camiseta Rojo M',
--       precio_unitario:25.00, activo:true,
--       atributos:{'talla':'M','color':'Rojo'} },
--     ...
--   ]
```

### `get_familia_grid(p_empresa_id, p_familia_id, p_eje_x, p_eje_y)` — Vista de grilla talla×color

```sql
-- Retorna el producto cartesiano de los valores de dos atributos.
-- Celdas sin producto_id = combinación que no existe en el catálogo.
SELECT * FROM get_familia_grid('empresa-uuid', 'familia-uuid', 'talla', 'color');
-- → [
--     { eje_x_valor:'S', eje_y_valor:'Rojo',  producto_id:'...', precio:25.00, activo:true },
--     { eje_x_valor:'S', eje_y_valor:'Azul',  producto_id:NULL,  precio:NULL,  activo:NULL },
--     { eje_x_valor:'M', eje_y_valor:'Rojo',  producto_id:'...', precio:25.00, activo:true },
--     { eje_x_valor:'M', eje_y_valor:'Azul',  producto_id:'...', precio:27.00, activo:true },
--   ]
-- Flutter usa esto para pintar la grilla: filas=tallas, columnas=colores
```

### PostgREST (automático)

**Contactos:**
- `GET /rest/v1/contactos?es_cliente=eq.true` — Listar clientes
- `GET /rest/v1/contactos?es_proveedor=eq.true` — Listar proveedores
- `POST /rest/v1/contactos` — Crear contacto
- `PATCH /rest/v1/contactos?id=eq.<uuid>` — Actualizar contacto

**Productos:**
- `GET /rest/v1/productos?activo=eq.true` — Listar productos
- `POST /rest/v1/productos` — Crear producto
- `GET /rest/v1/inventario_stock?producto_id=eq.<uuid>` — Stock por producto
