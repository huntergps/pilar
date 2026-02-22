# API Conventions — RPCs de Foundation

Referencia de patrones de API, convenciones de nomenclatura y RPCs pertenecientes a foundation.

> Las RPCs de cada módulo se documentan en el `module.md` del módulo correspondiente.
> PostgREST expone automáticamente endpoints CRUD en todas las tablas via REST.
> Las RPCs se llaman vía `supabase.rpc('nombre_funcion', params: {...})`.

---

## Convenciones de nomenclatura

### Patrón general

```
<verbo>_<entidad>            -- acción directa sobre una entidad
<verbo>_<entidad>_<campo>    -- acción sobre un campo específico
get_<entidad>_<atributo>     -- lectura de un atributo derivado
check_<condicion>            -- booleano: ¿se cumple la condición?
list_<entidades>_by_<campo>  -- listado filtrado
process_<proceso>            -- ejecuta un proceso de negocio
```

### Verbos estándar

| Verbo | Semántica |
|-------|-----------|
| `get_` | Lectura de dato derivado o calculado (no tabla directa) |
| `create_` | Creación transaccional (múltiples tablas o lógica compleja) |
| `update_` | Actualización con validaciones de negocio |
| `delete_` | Eliminación con validaciones de integridad |
| `check_` | Verifica condición, retorna `BOOLEAN` |
| `list_` | Listado con filtros o joins complejos |
| `process_` | Ejecuta un proceso que cambia estado (transición de estado, cola, etc.) |
| `activate_` | Activa un recurso o módulo |
| `deactivate_` | Desactiva un recurso o módulo |

### Parámetros

- Prefijo `p_` en todos los parámetros de entrada: `p_empresa_id`, `p_usuario_id`
- Prefijo `v_` en variables locales dentro de funciones PL/pgSQL
- UUIDs siempre como tipo `UUID`, nunca `TEXT`
- Montos siempre como `DECIMAL(14,2)`, cantidades como `DECIMAL(18,6)`

---

## Patrón de respuesta estándar

### RPC que retorna registro único

```sql
-- Retorna JSONB con el registro o error estructurado
CREATE OR REPLACE FUNCTION <nombre_rpc>(
  p_param_1 UUID,
  p_param_2 TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result JSONB;
BEGIN
  -- Validaciones de negocio primero
  IF p_param_1 IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'PARAM_REQUERIDO');
  END IF;

  -- Lógica principal
  SELECT to_jsonb(t) INTO v_result
  FROM <tabla> t
  WHERE t.id = p_param_1
    AND t.empresa_id = (SELECT private.get_empresa_id());

  IF v_result IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'NOT_FOUND');
  END IF;

  RETURN jsonb_build_object('ok', true, 'data', v_result);
END;
$$;
```

### RPC que retorna lista

```sql
-- Retorna SETOF (tabla virtual) para que PostgREST la trate como colección
CREATE OR REPLACE FUNCTION list_<entidades>(
  p_filtro TEXT DEFAULT NULL
)
RETURNS TABLE (
  id UUID,
  campo_1 TEXT,
  campo_2 DECIMAL
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT id, campo_1, campo_2
  FROM <tabla>
  WHERE empresa_id = (SELECT private.get_empresa_id())
    AND (p_filtro IS NULL OR nombre ILIKE '%' || p_filtro || '%')
  ORDER BY created_at DESC;
$$;
```

### RPC de acción (mutation)

```sql
-- Retorna BOOLEAN o JSONB con resultado de la operación
CREATE OR REPLACE FUNCTION process_<accion>(
  p_entidad_id UUID,
  p_parametro  TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Verificar que el recurso pertenece a la empresa del JWT
  IF NOT EXISTS (
    SELECT 1 FROM <tabla>
    WHERE id = p_entidad_id
      AND empresa_id = (SELECT private.get_empresa_id())
  ) THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  -- Ejecutar acción
  UPDATE <tabla>
  SET estado = p_parametro, updated_at = NOW()
  WHERE id = p_entidad_id;

  RETURN true;
END;
$$;
```

---

## Seguridad obligatoria en RPCs

```sql
-- SIEMPRE en RPCs que acceden a datos de empresa:
SECURITY DEFINER          -- ejecuta con permisos del owner (no del caller)
SET search_path = public  -- evita ataques de search_path injection

-- SIEMPRE filtrar por empresa_id usando la función cacheada:
WHERE empresa_id = (SELECT private.get_empresa_id())
-- NUNCA: WHERE empresa_id = auth.jwt()->>'empresa_id'  (se evalúa por fila)

-- Para RPCs de solo lectura: usar STABLE (permite caché del planner)
-- Para RPCs que modifican datos: usar VOLATILE (default)
```

---

## Cómo cada módulo documenta sus RPCs

Cada módulo define sus RPCs en `<modulo>/module.md`, sección **RPCs**. El formato estándar es:

```markdown
## RPCs

### `nombre_de_la_rpc`
- **Descripción**: Qué hace la función
- **Parámetros**: `p_param_1 UUID` — descripción; `p_param_2 TEXT` — descripción
- **Retorna**: `BOOLEAN` / `JSONB` / `TABLE (...)` — descripción del resultado
- **Permisos**: permiso requerido (`modulo.entidad.accion`)
- **Migración**: `NNN_<nombre>.sql`
```

---

## RPCs de Foundation

Las siguientes RPCs pertenecen a foundation y están disponibles para todos los módulos.

### Gestión de empresa

| RPC | Descripción | Retorna |
|-----|-------------|---------|
| `initialize_empresa(p_ruc, p_razon_social, p_plan_id)` | Provisiona una nueva empresa con seed data inicial | `UUID` (empresa_id) |
| `update_empresa_logo(p_empresa_id, p_tipo, p_url)` | Actualiza URL de logo en `configuracion_empresa` | `BOOLEAN` |
| `get_empresa_config()` | Retorna configuración completa de la empresa del JWT | `JSONB` |

### Gestión de usuarios y roles

| RPC | Descripción | Retorna |
|-----|-------------|---------|
| `invite_usuario(p_email, p_rol_id, p_establecimiento_id)` | Invita usuario a la empresa con rol asignado | `JSONB` |
| `assign_rol(p_usuario_id, p_rol_id)` | Asigna rol a usuario dentro de la empresa | `BOOLEAN` |
| `check_permission(p_permiso)` | Verifica si el usuario JWT tiene el permiso dado | `BOOLEAN` |
| `get_mis_permisos()` | Retorna lista de permisos del usuario JWT | `TEXT[]` |

### Gestión de módulos

| RPC | Descripción | Retorna |
|-----|-------------|---------|
| `activate_module(p_modulo_codigo)` | Activa módulo para la empresa (con dependencias recursivas) | `BOOLEAN` |
| `deactivate_module(p_modulo_codigo)` | Desactiva módulo para la empresa | `BOOLEAN` |
| `get_modulos_activos()` | Lista módulos activos para la empresa del JWT | `TABLE` |
| `check_module_active(p_modulo_codigo)` | Verifica si un módulo está activo para la empresa | `BOOLEAN` |

### Utilidades

| RPC | Descripción | Retorna |
|-----|-------------|---------|
| `financial_round(p_valor, p_decimales)` | Redondeo bancario ROUND_HALF_UP | `DECIMAL` |
| `to_local_time(p_utc_timestamp, p_establecimiento_id)` | Convierte UTC a hora local del establecimiento | `TIMESTAMP` |
| `get_local_date(p_establecimiento_id)` | Fecha de hoy en zona horaria del establecimiento | `DATE` |
| `convert_to_functional_currency(p_monto, p_moneda_id, p_fecha)` | Convierte monto a moneda funcional usando tasa de cambio | `DECIMAL` |

---

## Multi-tenancy

Todas las RPCs respetan multi-tenancy vía RLS (`empresa_id` del JWT):

```sql
-- Patrón obligatorio (usa función cacheada, NO inline JWT parsing):
WHERE empresa_id = (SELECT private.get_empresa_id())
```

El `empresa_id` se obtiene de `auth.jwt() -> 'app_metadata' ->> 'empresa_id'` y se cachea una vez por consulta mediante la función `private.get_empresa_id()`.
