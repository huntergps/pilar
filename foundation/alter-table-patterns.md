# Patrones para ALTER TABLE Cross-Módulo

**Estado**: Referencia canónica — leer antes de agregar columnas a tablas de otros módulos
**Relacionado con**: `field-ownership-matrix.md`, ADR-009, `arquitectura-modular.md`

---

## Principio general

Cuando un módulo necesita añadir datos sobre una entidad que pertenece a otro módulo (por ejemplo, RRHH necesita datos extra en `contactos`, o Inventario necesita marcar si un producto tiene control de lotes), tiene tres opciones ordenadas por preferencia:

| Opción | Cuándo usar | Ejemplo |
|--------|-------------|---------|
| **1. Tabla propia del módulo** | Relación 1:N o datos complejos | `empleados` para RRHH |
| **2. ALTER TABLE con columna nullable** | Datos simples 1:1 en tabla compartida | `contactos.rrhh_tipo_contrato` |
| **3. Soft reference UUID nullable** | Referencia a entidad del otro módulo sin FK constraint | `facturas.rrhh_empleado_id` |

Antes de hacer un `ALTER TABLE`, pregúntate: ¿este dato podría ser una tabla propia? Si el dato tiene 3 o más campos, probablemente merece su propia tabla.

---

## Convención de naming para columnas cross-módulo

Las columnas que un módulo añade a tablas de otro módulo llevan el prefijo `<modulo>_`:

```
<modulo>_<campo_descriptivo>
```

### Ejemplos correctos

| Módulo que extiende | Tabla que extiende | Columna añadida |
|--------------------|-------------------|-----------------|
| `rrhh` | `contactos` | `rrhh_tipo_contrato`, `rrhh_fecha_ingreso`, `rrhh_cargo` |
| `inventario` | `productos` | `inventario_control_lotes`, `inventario_peso_kg`, `inventario_requiere_serie` |
| `facturacion` | `contactos` | `facturacion_limite_credito`, `facturacion_dias_credito` |
| `ventas` | `contactos` | `ventas_descuento_especial`, `ventas_vendedor_id` |
| `ecommerce` | `productos` | `ecommerce_slug`, `ecommerce_publicado`, `ecommerce_precio_web` |
| `citas_belleza` | `contactos` | `citas_notas_preferencias`, `citas_historial_servicios` |

### Ejemplos incorrectos (no hacer)

```sql
-- MAL: nombre genérico sin prefijo de módulo
ALTER TABLE contactos ADD COLUMN tipo_contrato TEXT;

-- MAL: prefijo de tabla en lugar de módulo
ALTER TABLE contactos ADD COLUMN contactos_rrhh_cargo TEXT;

-- MAL: columna sin indicar el módulo propietario
ALTER TABLE productos ADD COLUMN peso DECIMAL(10,3);
```

---

## Patrón idempotente obligatorio

Toda migración que extienda una tabla de otro módulo DEBE ser completamente idempotente. Usar `ADD COLUMN IF NOT EXISTS` y el bloque `DO $$` para la inserción en el registro de extensiones:

```sql
-- ============================================================
-- modules/rrhh/migrations/002_extend_contactos.sql
-- Módulo: RRHH — Extiende la tabla contactos de Foundation
-- ============================================================

-- 1. Añadir columnas con IF NOT EXISTS (idempotente)
ALTER TABLE contactos
    ADD COLUMN IF NOT EXISTS rrhh_tipo_contrato     VARCHAR(20)     DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS rrhh_fecha_ingreso      DATE            DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS rrhh_fecha_salida        DATE            DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS rrhh_cargo              VARCHAR(100)    DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS rrhh_departamento_id    UUID            DEFAULT NULL,  -- soft ref
    ADD COLUMN IF NOT EXISTS rrhh_salario_base        DECIMAL(14,2)   DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS rrhh_numero_iess         VARCHAR(20)     DEFAULT NULL;

-- 2. Restricción CHECK idempotente
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE table_name       = 'contactos'
          AND constraint_name  = 'contactos_rrhh_tipo_contrato_check'
    ) THEN
        ALTER TABLE contactos
            ADD CONSTRAINT contactos_rrhh_tipo_contrato_check
            CHECK (rrhh_tipo_contrato IN ('indefinido', 'fijo', 'obra', 'servicios', NULL));
    END IF;
END;
$$;

-- 3. Índice idempotente
CREATE INDEX IF NOT EXISTS idx_contactos_rrhh_departamento
    ON contactos (empresa_id, rrhh_departamento_id)
    WHERE rrhh_departamento_id IS NOT NULL;

-- 4. Registrar extensión en el catálogo del sistema
INSERT INTO modulo_campos_extension
    (modulo_codigo, tabla_nombre, columna_nombre, tipo_dato, nullable, descripcion)
VALUES
    ('rrhh', 'contactos', 'rrhh_tipo_contrato',  'VARCHAR(20)',   TRUE, 'Tipo de contrato laboral'),
    ('rrhh', 'contactos', 'rrhh_fecha_ingreso',   'DATE',          TRUE, 'Fecha de ingreso a la empresa'),
    ('rrhh', 'contactos', 'rrhh_fecha_salida',     'DATE',          TRUE, 'Fecha de salida (NULL si activo)'),
    ('rrhh', 'contactos', 'rrhh_cargo',            'VARCHAR(100)',  TRUE, 'Cargo o puesto del empleado'),
    ('rrhh', 'contactos', 'rrhh_departamento_id',  'UUID',          TRUE, 'Soft ref a rrhh_departamentos'),
    ('rrhh', 'contactos', 'rrhh_salario_base',     'DECIMAL(14,2)', TRUE, 'Salario mensual base'),
    ('rrhh', 'contactos', 'rrhh_numero_iess',       'VARCHAR(20)',   TRUE, 'Número de afiliación IESS')
ON CONFLICT (tabla_nombre, columna_nombre) DO UPDATE SET
    descripcion = EXCLUDED.descripcion;
```

---

## Cuándo usar cada estrategia

### Estrategia 1: Tabla propia del módulo (preferida para datos complejos)

Usar cuando:
- El módulo necesita almacenar 3 o más campos relacionados
- Los datos tienen su propio ciclo de vida (pueden crearse/eliminarse independientemente)
- Se necesitan queries frecuentes sobre esos datos con filtros propios

```sql
-- BIEN: tabla propia para datos de empleado (muchos campos, ciclo de vida propio)
CREATE TABLE rrhh_empleados (
    id              UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id      UUID    NOT NULL,
    contacto_id     UUID    NOT NULL,  -- soft ref a contactos (sin FK constraint)
    tipo_contrato   VARCHAR(20),
    fecha_ingreso   DATE,
    cargo           VARCHAR(100),
    salario_base    DECIMAL(14,2),
    created_at      TIMESTAMPTZ DEFAULT NOW()
);
```

### Estrategia 2: ALTER TABLE con columna nullable (para datos simples 1:1)

Usar cuando:
- El módulo añade 1-2 campos simples a una entidad compartida
- Los campos son usados frecuentemente en búsquedas junto con otros campos de la tabla base
- No vale la pena el JOIN adicional de una tabla separada

```sql
-- BIEN: columna nullable para dato simple de uso frecuente
ALTER TABLE productos
    ADD COLUMN IF NOT EXISTS inventario_control_lotes BOOLEAN DEFAULT FALSE;
```

### Estrategia 3: Soft reference UUID nullable (para referencias cross-módulo sin FK)

Las referencias a tablas de otros módulos NUNCA usan FK constraints. Usar UUID nullable sin constraint:

```sql
-- BIEN: soft reference sin FK constraint
ALTER TABLE facturas
    ADD COLUMN IF NOT EXISTS ventas_orden_venta_id UUID DEFAULT NULL;
    -- Sin: REFERENCES ordenes_venta(id) — el módulo Ventas puede no estar activo

-- BIEN: referencia desde módulo Auxiliar hacia Core sin FK
ALTER TABLE pos_ordenes
    ADD COLUMN IF NOT EXISTS facturacion_factura_id UUID DEFAULT NULL;
    -- La factura se crea vía MSB, no con FK directo
```

**Razón**: si el módulo referenciado no está activo, la tabla referenciada puede no tener datos o puede no existir en el schema del módulo. Los FK constraints causarían errores de integridad en contextos inesperados.

---

## Cómo agregar FK constraints de forma segura (si son necesarios)

Los FK constraints hacia tablas de Foundation (que siempre existen) son seguros y obligatorios. Los FK hacia tablas de otros módulos Core o Auxiliares deben ser condicionales:

```sql
-- FK seguro hacia Foundation (siempre existe)
ALTER TABLE rrhh_empleados
    ADD CONSTRAINT fk_rrhh_empleados_empresa
    FOREIGN KEY (empresa_id) REFERENCES empresas(id) ON DELETE CASCADE;

-- FK condicional hacia otro módulo (verificar si la tabla existe)
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public'
          AND table_name   = 'departamentos'
    ) AND NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE table_name       = 'rrhh_empleados'
          AND constraint_name  = 'fk_rrhh_empleados_departamento'
    ) THEN
        ALTER TABLE rrhh_empleados
            ADD CONSTRAINT fk_rrhh_empleados_departamento
            FOREIGN KEY (departamento_id) REFERENCES departamentos(id) ON DELETE SET NULL;
    END IF;
END;
$$;
```

---

## Cómo registrar la extensión en `modulo_campos_extension`

La tabla `modulo_campos_extension` documenta qué módulo añadió qué columna, lo que permite:
- Saber qué columnas eliminar si se desinstala un módulo
- Auditoría del schema
- Generación automática de documentación

```sql
-- Tabla modulo_campos_extension (definida en foundation/migrations/)
-- Columnas: modulo_codigo, tabla_nombre, columna_nombre, tipo_dato,
--            valor_defecto, nullable, descripcion

INSERT INTO modulo_campos_extension
    (modulo_codigo, tabla_nombre, columna_nombre, tipo_dato, valor_defecto, nullable, descripcion)
VALUES
    ('ecommerce', 'productos', 'ecommerce_slug',       'VARCHAR(200)', NULL,    TRUE,  'URL slug para la tienda web'),
    ('ecommerce', 'productos', 'ecommerce_publicado',   'BOOLEAN',      'false', FALSE, 'Si el producto aparece en la tienda'),
    ('ecommerce', 'productos', 'ecommerce_precio_web',  'DECIMAL(14,2)', NULL,   TRUE,  'Precio especial para web (NULL=usa precio_venta)')
ON CONFLICT (tabla_nombre, columna_nombre) DO UPDATE SET
    descripcion = EXCLUDED.descripcion,
    tipo_dato   = EXCLUDED.tipo_dato;
```

---

## Ejemplo completo: `extend_contactos.sql` del módulo Ventas

```sql
-- ============================================================
-- modules/core/ventas/migrations/003_extend_contactos.sql
-- Módulo: Ventas — Extiende tabla contactos con datos comerciales
-- ============================================================
-- Este archivo es idempotente: puede ejecutarse múltiples veces sin error

-- 1. Columnas de extensión
ALTER TABLE contactos
    ADD COLUMN IF NOT EXISTS ventas_limite_credito       DECIMAL(14,2)   DEFAULT 0,
    ADD COLUMN IF NOT EXISTS ventas_dias_credito          SMALLINT        DEFAULT 0,
    ADD COLUMN IF NOT EXISTS ventas_descuento_global      DECIMAL(5,2)    DEFAULT 0
        CHECK (ventas_descuento_global BETWEEN 0 AND 100),
    ADD COLUMN IF NOT EXISTS ventas_lista_precio_id       UUID            DEFAULT NULL,  -- soft ref
    ADD COLUMN IF NOT EXISTS ventas_vendedor_id           UUID            DEFAULT NULL,  -- soft ref a usuarios
    ADD COLUMN IF NOT EXISTS ventas_requiere_aprobacion   BOOLEAN         DEFAULT FALSE;

-- 2. Índice para consultas frecuentes (clientes con crédito activo)
CREATE INDEX IF NOT EXISTS idx_contactos_ventas_vendedor
    ON contactos (empresa_id, ventas_vendedor_id)
    WHERE ventas_vendedor_id IS NOT NULL AND es_cliente = TRUE;

-- 3. Registro en catálogo
INSERT INTO modulo_campos_extension
    (modulo_codigo, tabla_nombre, columna_nombre, tipo_dato, nullable, descripcion)
VALUES
    ('ventas', 'contactos', 'ventas_limite_credito',      'DECIMAL(14,2)', FALSE, 'Monto máximo de crédito aprobado'),
    ('ventas', 'contactos', 'ventas_dias_credito',         'SMALLINT',      FALSE, 'Plazo de pago en días (0=contado)'),
    ('ventas', 'contactos', 'ventas_descuento_global',     'DECIMAL(5,2)',  FALSE, 'Descuento comercial permanente en %'),
    ('ventas', 'contactos', 'ventas_lista_precio_id',      'UUID',          TRUE,  'Lista de precios asignada al cliente'),
    ('ventas', 'contactos', 'ventas_vendedor_id',          'UUID',          TRUE,  'Vendedor asignado por defecto'),
    ('ventas', 'contactos', 'ventas_requiere_aprobacion',  'BOOLEAN',       FALSE, 'Si las OV de este cliente requieren aprobación')
ON CONFLICT (tabla_nombre, columna_nombre) DO UPDATE SET
    descripcion = EXCLUDED.descripcion;

-- 4. Comentario en columnas (opcional pero recomendado)
COMMENT ON COLUMN contactos.ventas_limite_credito IS
    '[ventas] Monto máximo de crédito aprobado. 0 = sin crédito (contado).';
COMMENT ON COLUMN contactos.ventas_dias_credito IS
    '[ventas] Días de plazo para pago. 0 = contado inmediato.';
```

---

## Lo que NUNCA se debe hacer

### Prohibido: DROP COLUMN en tablas de otros módulos

```sql
-- NUNCA HACER ESTO en una migración de desinstalación:
ALTER TABLE contactos DROP COLUMN rrhh_tipo_contrato;

-- La política es archivar datos, no eliminarlos.
-- Si el módulo RRHH se desinstala, las columnas permanecen con sus datos.
-- La aplicación simplemente deja de mostrarlos al no tener el módulo activo.
```

### Prohibido: RENAME COLUMN en tablas de otros módulos

```sql
-- NUNCA HACER ESTO:
ALTER TABLE contactos RENAME COLUMN rrhh_cargo TO rrhh_puesto;

-- Renombrar rompe silenciosamente todas las queries que usan el nombre antiguo.
-- En su lugar, añadir la columna nueva y deprecar la antigua (marcándola en el catálogo).
```

### Prohibido: ALTER COLUMN TYPE en tablas compartidas sin consenso

```sql
-- NUNCA HACER ESTO sin coordinación con el módulo propietario:
ALTER TABLE productos ALTER COLUMN precio_venta TYPE DECIMAL(18,6);

-- Cambiar el tipo de una columna de foundation afecta TODOS los módulos que la usan.
-- Requiere una ADR y migración coordinada en foundation/.
```

### Prohibido: FK constraints hacia tablas de módulos activables sin verificación

```sql
-- MAL: FK directo sin verificar existencia del módulo
ALTER TABLE pos_ordenes
    ADD CONSTRAINT fk_pos_factura FOREIGN KEY (factura_id) REFERENCES facturas(id);
-- Si facturación no está activo, esto puede causar errores de FK violation.

-- BIEN: usar soft reference UUID nullable (ver Estrategia 3)
ALTER TABLE pos_ordenes
    ADD COLUMN IF NOT EXISTS facturacion_factura_id UUID DEFAULT NULL;
```

### Prohibido: columnas sin prefijo de módulo en tablas ajenas

```sql
-- MAL: no se sabe qué módulo añadió esta columna
ALTER TABLE productos ADD COLUMN publicado BOOLEAN;

-- BIEN: prefijo claro del módulo propietario
ALTER TABLE productos ADD COLUMN IF NOT EXISTS ecommerce_publicado BOOLEAN DEFAULT FALSE;
```

---

## Checklist para una migración de extensión

Antes de hacer merge de una migración `extend_*.sql`, verificar:

- [ ] Todas las columnas tienen prefijo `<modulo>_`
- [ ] Se usa `ADD COLUMN IF NOT EXISTS` (nunca sin `IF NOT EXISTS`)
- [ ] Los `CHECK` constraints están dentro de `DO $$ BEGIN IF NOT EXISTS ... END $$`
- [ ] Los índices usan `CREATE INDEX IF NOT EXISTS`
- [ ] Los FK hacia módulos no-Foundation son soft references UUID nullable
- [ ] Hay registro en `modulo_campos_extension` con `ON CONFLICT DO UPDATE`
- [ ] No hay `DROP COLUMN`, `RENAME COLUMN` ni `ALTER COLUMN TYPE` en tablas ajenas
- [ ] La migración se puede ejecutar dos veces sin error (idempotencia verificada en local)
- [ ] El campo está documentado en el `module.md` del módulo

---

## Referencias

- `foundation/field-ownership-matrix.md` — qué módulo posee cada campo
- `foundation/arquitectura-modular.md` — ciclo de vida de módulos
- `foundation/adrs/ADR-009_sistema-modular.md` — independencia entre módulos
- `foundation/migrations/001_core_foundation.sql` — definición de `modulo_campos_extension`
