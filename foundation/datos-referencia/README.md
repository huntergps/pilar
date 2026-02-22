# Datos de Referencia — PILAR ERP

> Catálogos y tablas maestras que se cargan como seed data al inicializar el sistema o al crear una empresa.
> Estos datos son gestionados por Core Foundation y el módulo Administración.
> Última revisión: 2026-02-20

---

## Catálogos globales (country-agnostic)

Estos catálogos son genéricos y se cargan una sola vez para todas las empresas del sistema.

| Catálogo | Tabla SQL | Descripción |
|----------|-----------|-------------|
| Países | `paises` | ISO 3166-1 (249 países), incluye `codigo_iso2`, `codigo_iso3`, `nombre` |
| Monedas | `monedas` | ISO 4217; campo `es_funcional` indica la moneda funcional configurada |
| Unidades de medida | `unidades_medida` | UN/CEFACT: UND, KG, LT, M, M2, M3, CAJA, PAR, HRA, etc. |

> **Catálogos de localización** (formas de pago, tipos de identificación, divisiones administrativas,
> actividades económicas, tarifas impositivas, retenciones) →
> son responsabilidad del módulo de localización correspondiente.

---

## Qué son los seed data

Los seed data son datos de referencia que se cargan en la base de datos durante la inicialización del sistema o al crear una nueva empresa. Se distinguen de los datos transaccionales en que:

1. **Son relativamente estables** — cambian poco (catálogos de países, unidades de medida, etc.)
2. **Son comunes a todos los tenants** — aunque cada empresa puede tener su configuración específica
3. **Se cargan mediante migraciones SQL** — no mediante la UI de la aplicación
4. **Son mantenidos por el equipo PILAR** — no por los usuarios finales

---

## Cómo se cargan los seed data

### Al inicializar el sistema (una sola vez)

Estos datos se cargan en las migraciones iniciales y son compartidos por todas las empresas.
Se almacenan en tablas sin `empresa_id` o con `empresa_id IS NULL` para indicar que son globales:

```sql
-- Ejemplo: catálogo de países (global, sin empresa_id)
INSERT INTO paises (codigo_iso2, codigo_iso3, nombre, nombre_en)
VALUES
    ('US', 'USA', 'Estados Unidos', 'United States'),
    ('CO', 'COL', 'Colombia', 'Colombia'),
    -- ... 249 países total
ON CONFLICT (codigo_iso2) DO NOTHING;
```

### Al crear una nueva empresa (por empresa)

Estos datos se crean específicos para cada empresa. Se llaman desde `private.initialize_empresa(empresa_id)`:

```sql
CREATE OR REPLACE FUNCTION private.initialize_empresa(p_empresa_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    -- Crear bodega principal por defecto
    INSERT INTO bodegas (empresa_id, nombre, codigo, es_principal)
    VALUES (p_empresa_id, 'Bodega Principal', 'BP', TRUE);

    -- Crear diarios contables por defecto
    PERFORM seed_diarios_contables(p_empresa_id);

    -- Localización específica se carga desde el módulo correspondiente
    -- Los módulos de localización agregan sus propias llamadas a esta función
    -- vía su primera migración (seed de catálogos locales).
END;
$$;
```

### Al actualizar datos de referencia (evento externo)

Cuando un organismo regulador actualiza tarifas o catálogos, se crea una nueva migración.
**Nunca se modifican los datos históricos** — se agregan nuevos registros con `vigente_desde` / `vigente_hasta`:

```sql
-- Patrón genérico: actualizar una tarifa con vigencia
-- Migración: NNN_actualizar_tarifa_YYYY.sql
UPDATE [tabla_tarifas]
SET vigente_hasta = 'YYYY-MM-DD'
WHERE codigo = 'X' AND vigente_hasta IS NULL;

INSERT INTO [tabla_tarifas] (codigo, descripcion, valor, vigente_desde, vigente_hasta)
VALUES ('X', 'Nueva tarifa', 15.00, 'YYYY-MM-DD', NULL);
```

---

## Estructura de tablas de referencia

Las tablas de catálogo/referencia siguen este patrón:

```sql
-- Tabla de referencia global (sin empresa_id)
CREATE TABLE [catalogo_nombre] (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo          VARCHAR(20) NOT NULL UNIQUE,
    nombre          TEXT NOT NULL,
    descripcion     TEXT,
    activo          BOOLEAN NOT NULL DEFAULT TRUE,
    orden           INTEGER NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Tabla de referencia parametrizable por empresa (con vigencias)
CREATE TABLE [parametros_empresa] (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id      UUID NOT NULL REFERENCES empresas(id),
    codigo          VARCHAR(20) NOT NULL,
    valor           TEXT NOT NULL,
    vigente_desde   DATE NOT NULL,
    vigente_hasta   DATE,  -- NULL = vigente indefinidamente
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (empresa_id, codigo, vigente_desde)
);
```

---

## Responsables de mantenimiento

| Tipo de dato | Quién actualiza | Cuándo |
|-------------|-----------------|--------|
| Catálogos globales (países, monedas) | Equipo PILAR (migración SQL) | Cuando ISO publique nuevos códigos |
| Unidades de medida | Equipo PILAR (migración SQL) | Cuando se requiera nueva unidad de negocio |
| Catálogos de localización | Equipo PILAR (migración SQL en el módulo de localización correspondiente) | Cuando el organismo regulador emita actualización |
| Configuración empresa | Usuario Administrador | A través de la UI de Administración |

> Para los catálogos de localización específicos y sus responsables regulatorios,
> ver la documentación del módulo de localización correspondiente.

---

## Versionado y trazabilidad

Todos los cambios a datos de referencia deben:

1. Ir en una migración SQL numerada (`NNN_descripcion.sql`) en el directorio de migraciones del módulo correspondiente
2. Incluir comentario con la referencia normativa (resolución oficial, registro, etc.)
3. Nunca borrar datos históricos — usar `vigente_hasta` para desactivar
4. Nunca editar migraciones ya aplicadas — crear una nueva migración

```sql
-- Ejemplo de comentario normativo obligatorio
-- Migración: NNN_actualizar_tarifa_2026.sql
-- Referencia: [Organismo] — [Número de resolución/registro oficial]
-- Vigencia: a partir del [fecha]
```
