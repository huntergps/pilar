# PILAR ERP — Matriz de Campos por Módulo (Field Ownership Matrix)

Análogo a `ir.model.fields` de Odoo. Documenta qué columnas añade cada módulo sobre las tablas de foundation, y el comportamiento al desactivar ese módulo.

**Consulta SQL equivalente:**
```sql
SELECT * FROM v_matriz_campos_modulos;
-- o filtrar por módulo:
SELECT * FROM v_matriz_campos_modulos WHERE modulo = '<modulo>';
-- o filtrar por tabla:
SELECT * FROM v_matriz_campos_modulos WHERE tabla = 'contactos';
```

---

## Tablas de Foundation extensibles por módulos

Las tablas de foundation que los módulos pueden extender son aquellas declaradas en `foundation/migrations/`. Cada módulo añade columnas propias a estas tablas mediante migraciones idempotentes.

---

## Tabla: `contactos`

### Campos BASE (siempre presentes — propietario: foundation)

| Campo | Tipo | Default | Nulo | Descripción |
|-------|------|---------|------|-------------|
| `id` | UUID | gen_random_uuid() | No | PK |
| `empresa_id` | UUID | — | No | FK empresas (multi-tenant) |
| `tipo_id` | VARCHAR(2) | `'04'` | No | Tipo de identificación |
| `numero_id` | VARCHAR(20) | — | No | Número de identificación |
| `razon_social` | VARCHAR(300) | — | No | Nombre legal |
| `nombre_comercial` | VARCHAR(200) | — | Sí | Nombre de fantasía |
| `es_cliente` | BOOLEAN | `false` | No | Rol cliente |
| `es_proveedor` | BOOLEAN | `false` | No | Rol proveedor |
| `es_empleado` | BOOLEAN | `false` | No | Rol empleado |
| `categoria_id` | UUID | — | Sí | FK categorias_contacto |
| `email` | VARCHAR(200) | — | Sí | Email principal |
| `telefono` | VARCHAR(20) | — | Sí | Teléfono fijo |
| `celular` | VARCHAR(20) | — | Sí | Celular |
| `direccion` | TEXT | — | Sí | Dirección |
| `provincia_id` | INTEGER | — | Sí | Soft ref a catálogos geográficos |
| `ciudad_id` | INTEGER | — | Sí | Soft ref a catálogos geográficos |
| `notas` | TEXT | — | Sí | Notas internas |
| `activo` | BOOLEAN | `true` | No | Registro activo |
| `created_at` | TIMESTAMPTZ | NOW() | No | Fecha creación |
| `updated_at` | TIMESTAMPTZ | NOW() | No | Fecha última modificación |

### Campos EXTENDIDOS por módulo

Los módulos que necesiten agregar campos a `contactos` deben:

1. Crear una migración en `<modulo>/migrations/NNN_extend_contactos.sql`
2. Usar `ADD COLUMN IF NOT EXISTS` (idempotente)
3. Registrar el campo en `modulo_campos_extension`
4. Documentar el campo en el `module.md` del módulo

Ejemplo de extensión genérica:

```sql
-- <modulo>/migrations/NNN_extend_contactos.sql
ALTER TABLE contactos
  ADD COLUMN IF NOT EXISTS <campo> <tipo> <constraints>;

INSERT INTO modulo_campos_extension
  (modulo_codigo, tabla_nombre, columna_nombre, tipo_dato, valor_defecto, nullable, descripcion)
VALUES
  ('<modulo>', 'contactos', '<campo>', '<tipo>', '<default>', <nullable>,
   '<descripcion del campo>')
ON CONFLICT (tabla_nombre, columna_nombre) DO NOTHING;
```

---

## Tabla: `productos`

### Campos BASE (siempre presentes — propietario: foundation)

| Campo | Tipo | Default | Nulo | Descripción |
|-------|------|---------|------|-------------|
| `id` | UUID | gen_random_uuid() | No | PK |
| `empresa_id` | UUID | — | No | FK empresas (multi-tenant) |
| `tipo` | VARCHAR(20) | `'PRODUCTO'` | No | Tipo: PRODUCTO / SERVICIO / etc. |
| `codigo` | VARCHAR(50) | — | No | Código interno único por empresa |
| `nombre` | VARCHAR(200) | — | No | Nombre del producto |
| `descripcion` | TEXT | — | Sí | Descripción detallada |
| `categoria_id` | UUID | — | Sí | FK categorias_producto |
| `unidad_medida_id` | UUID | — | Sí | FK unidades_medida |
| `codigo_principal_barras` | VARCHAR(50) | — | Sí | Código de barras rápido |
| `precio_venta` | DECIMAL(18,6) | `0` | No | Precio base de venta |
| `precio_costo` | DECIMAL(18,6) | `0` | No | Costo de adquisición |
| `notas` | TEXT | — | Sí | Notas internas |
| `activo` | BOOLEAN | `true` | No | Registro activo |
| `created_at` | TIMESTAMPTZ | NOW() | No | Fecha creación |
| `updated_at` | TIMESTAMPTZ | NOW() | No | Fecha última modificación |

### Campos EXTENDIDOS por módulo

Los módulos que necesiten agregar campos a `productos` siguen el mismo patrón que `contactos` (ver arriba). Cada módulo documenta sus campos extendidos en su propio `module.md`.

---

## Extensión de tablas propietarias de módulos

Las tablas propietarias de un módulo (ej: tabla del módulo A) pueden ser extendidas por otro módulo (módulo B) bajo las siguientes reglas:

- El módulo B NO crea la tabla; solo añade columnas mediante `ADD COLUMN IF NOT EXISTS`
- Los campos son soft references (UUID nullable, sin FK constraint) para evitar dependencia circular
- Al desactivar el módulo B, los datos se preservan (nunca DROP automático)
- El módulo B documenta la extensión en su propio `module.md`

Consultar la sección **Extensiones entre módulos** en `foundation/arquitectura-modular.md` para el patrón completo.

---

## Reglas del Sistema

### 1. Patrón idempotente (ADD COLUMN IF NOT EXISTS)
```sql
-- Módulo instala: si no existe, crea; si existe, no-op
ALTER TABLE contactos
  ADD COLUMN IF NOT EXISTS <campo> <tipo> <constraints>;

-- Registro en matriz (idempotente también)
INSERT INTO modulo_campos_extension (...) ON CONFLICT DO NOTHING;
```

### 2. NO DROP al desactivar (como Odoo)
```sql
-- ✅ Correcto: marcar módulo inactivo, datos preservados
UPDATE modulos_empresa SET activo = false WHERE modulo_codigo = '<modulo>';

-- ❌ Incorrecto: nunca hacer esto automáticamente
-- ALTER TABLE contactos DROP COLUMN <campo>;  -- PROHIBIDO
```

### 3. Verificar módulo activo antes de usar campos extendidos
```sql
-- Desde la app (Flutter) o desde otras funciones SQL:
-- Solo acceder a campos extendidos si el módulo está activo

CREATE OR REPLACE FUNCTION <nombre_funcion>(p_entidad_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
  v_modulo_activo BOOLEAN;
BEGIN
  SELECT EXISTS(
    SELECT 1 FROM modulos_empresa
    WHERE empresa_id = (SELECT private.get_empresa_id())
      AND modulo_codigo = '<modulo>'
      AND activo = true
  ) INTO v_modulo_activo;

  IF NOT v_modulo_activo THEN
    RETURN true;  -- Sin módulo, comportamiento por defecto
  END IF;

  -- Acceder al campo extendido por el módulo
  RETURN (
    SELECT <campo_extendido> FROM <tabla> WHERE id = p_entidad_id
  );
END;
$$ LANGUAGE plpgsql;
```

### 4. Agregar un campo extendido nuevo
Si un módulo necesita extender una tabla de foundation:

1. En la migración del módulo (`<modulo>/migrations/NNN_extend_<tabla>.sql`):
```sql
ALTER TABLE <tabla_foundation>
  ADD COLUMN IF NOT EXISTS <campo> <tipo> <constraints>;

INSERT INTO modulo_campos_extension
  (modulo_codigo, tabla_nombre, columna_nombre, tipo_dato, valor_defecto, nullable, descripcion)
VALUES
  ('<modulo>', '<tabla>', '<campo>', '<tipo>', '<default>', <nullable>, '<descripcion>')
ON CONFLICT (tabla_nombre, columna_nombre) DO NOTHING;
```

2. Documentar la extensión en el `module.md` del módulo correspondiente.

---

## Cómo Odoo maneja esto vs PILAR

| Aspecto | Odoo | PILAR |
|---------|------|-------|
| **Tabla de registro** | `ir.model.fields` (toda la metadata ORM) | `modulo_campos_extension` (solo campos extendidos) |
| **Propietario del campo** | `ir.model.fields.module` (FK a ir.module.module) | `modulo_campos_extension.modulo_codigo` (soft ref) |
| **Idempotencia** | ORM de Python detecta cambios automáticamente | `ADD COLUMN IF NOT EXISTS` explícito en SQL |
| **DROP al desactivar** | NO automático (solo si el campo desaparece del código Python) | NUNCA automático |
| **state='base' vs 'manual'** | `base`=Python, `manual`=Studio/UI | Solo PRESERVE (equivalente a `base`) |
| **Herencia de modelos** | `_inherit = 'sale.order'` en Python | `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` en SQL |
| **Actualización de módulo** | `odoo-bin -u modulo` re-sync ORM ↔ DB | Re-ejecutar migraciones (idempotentes) |
