# Importador de Datos Genérico

> Migración: `022_data_importer.sql`
> Edge Function: `import-data`
> Módulo: Foundation (transversal — al estilo Odoo, data-driven)
> Última revisión: 2026-02-22

---

## Descripción

Importador genérico de datos desde archivos **CSV** o **Excel (XLSX/XLS)**. Basado en templates data-driven: cada módulo declara qué entidades puede importar, qué campos acepta y cómo se validan — sin tocar el código de la Edge Function.

**Inspiración:** El importador de Odoo (`base_import`) donde `ir.model.fields` define qué puede importarse. En PILAR, `import_templates` cumple ese rol.

**Casos de uso:**
- Migración desde Monica ERP, Siigo, Alegra (clientes, productos, saldos)
- Carga inicial de catálogos al activar una empresa
- Importación periódica desde Excel del cliente
- Migración desde cualquier sistema con export CSV

---

## Arquitectura

```
Flutter UI (ImportScreen)
    │
    │  multipart/form-data (file + template_id)
    ▼
Edge Function: import-data
    │
    ├─ 1. Verificar JWT
    ├─ 2. Obtener template de import_templates
    ├─ 3. Parsear CSV o XLSX → array de filas JSONB
    ├─ 4. Validar headers contra campos del template
    ├─ 5. Por cada fila:
    │      ├─ Mapear etiqueta → nombre interno
    │      ├─ Validar tipo, patron, max_longitud, valores_permitidos
    │      └─ Si válida: SELECT <rpc_destino>(empresa_id, fila::JSONB)
    ├─ 6. SELECT finalizar_import_job(...)
    └─ 7. Retornar resumen
```

---

## Tablas

### `import_templates`

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `id` | UUID PK | |
| `empresa_id` | UUID FK nullable | NULL = template global del sistema; NOT NULL = custom de empresa |
| `modulo` | TEXT | ej: `entidades`, `contabilidad` |
| `recurso` | TEXT | ej: `contactos`, `productos`, `saldos_iniciales` |
| `nombre` | TEXT | Nombre mostrado al usuario |
| `descripcion` | TEXT | Ayuda contextual |
| `campos` | JSONB | Definición declarativa de campos (ver abajo) |
| `rpc_destino` | TEXT | Nombre de la RPC que recibe cada fila procesada |
| `activo` | BOOLEAN | |

**Constraint UNIQUE NULLS NOT DISTINCT:** `(empresa_id, modulo, recurso)` — previene templates duplicados.

### `import_jobs`

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `id` | UUID PK | |
| `empresa_id` | UUID FK | Tenant |
| `template_id` | UUID FK | |
| `usuario_id` | UUID FK | Quién importó |
| `nombre_archivo` | TEXT | Nombre original del archivo |
| `estado` | TEXT | PENDIENTE · PROCESANDO · COMPLETADO · ERROR_PARCIAL · FALLIDO |
| `total_filas` | INTEGER | Total de filas de datos (sin header) |
| `filas_exitosas` | INTEGER | Importadas correctamente |
| `filas_con_error` | INTEGER | Filas con errores de validación o RPC |
| `errores` | JSONB | `[{ "fila": 3, "campo": "ruc_cedula", "error": "RUC inválido: 99999" }]` |
| `storage_path` | TEXT | Path en Storage (archivos grandes guardados antes de procesar) |

---

## Definición de campos (JSONB)

Cada elemento del array `campos` en `import_templates`:

```json
{
  "nombre":           "ruc_cedula",
  "etiqueta":         "RUC / Cédula",
  "tipo":             "text",
  "requerido":        true,
  "patron":           "^[0-9]{10,13}$",
  "max_longitud":     13,
  "valores_permitidos": ["cliente","proveedor","ambos"],
  "valor_defecto":    "UND",
  "formato":          "YYYY-MM-DD",
  "tabla_ref":        "contactos",
  "campo_busqueda":   "ruc"
}
```

| Atributo | Aplica a tipo | Descripción |
|----------|--------------|-------------|
| `nombre` | todos | Nombre interno del campo (clave en JSONB de la fila) |
| `etiqueta` | todos | Encabezado exacto esperado en CSV/Excel |
| `tipo` | todos | `text` · `integer` · `decimal` · `boolean` · `date` · `uuid_ref` |
| `requerido` | todos | Si la columna puede estar ausente o vacía |
| `patron` | text | Regex de validación (ej: RUC ecuatoriano) |
| `max_longitud` | text | Longitud máxima |
| `valores_permitidos` | text | Enum — rechaza cualquier otro valor |
| `valor_defecto` | todos | Valor si columna ausente y campo no requerido |
| `formato` | date | Formato de la fecha (default: YYYY-MM-DD) |
| `tabla_ref` | uuid_ref | Tabla donde buscar el UUID por `campo_busqueda` |
| `campo_busqueda` | uuid_ref | Campo de búsqueda en `tabla_ref` |

### Validación por tipo

| Tipo | Regla |
|------|-------|
| `text` | trim, max_longitud, patron (regex), valores_permitidos |
| `integer` | parseInt — error si NaN |
| `decimal` | parseFloat — error si NaN |
| `boolean` | `S/SI/Y/YES/TRUE/1` → true; `N/NO/FALSE/0` → false |
| `date` | Parsear con formato especificado — error si inválido |
| `uuid_ref` | UUID válido, o buscar en tabla_ref por campo_busqueda |

---

## API de la Edge Function

```
POST /functions/v1/import-data
Authorization: Bearer <user_jwt>
Content-Type: multipart/form-data
```

**Body (multipart):**

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `file` | File | Archivo CSV o XLSX (máx 10 MB) |
| `template_id` | string | UUID del template |
| `dry_run` | string | `"true"` para validar sin importar (default: `"false"`) |

**Respuesta exitosa:**
```json
{
  "ok": true,
  "job_id": "uuid-del-job",
  "total": 100,
  "exitosas": 95,
  "errores": 5,
  "estado": "ERROR_PARCIAL",
  "detalle_errores": [
    { "fila": 3,  "campo": "ruc_cedula",   "error": "No coincide con patrón ^[0-9]{10,13}$" },
    { "fila": 17, "campo": "email",        "error": "Formato de email inválido" },
    { "fila": 42, "campo": "precio_venta", "error": "Valor no es un decimal válido: '$45,00'" }
  ]
}
```

**Dry run** (solo validación):
```json
{
  "ok": true,
  "dry_run": true,
  "total": 100,
  "filas_validas": 97,
  "filas_con_error": 3,
  "detalle_errores": [...]
}
```

**Límites:**
- Tamaño máximo: 10 MB
- Filas máximas: 5,000 por importación

---

## Templates incluidos (seed del sistema)

### `entidades / contactos` — Importar Contactos

| Etiqueta CSV | Campo | Tipo | Req | Notas |
|-------------|-------|------|-----|-------|
| RUC / Cédula | `ruc_cedula` | text | ✅ | Regex `^[0-9]{10,13}$` |
| Nombre / Razón Social | `nombre_completo` | text | ✅ | Máx 300 chars |
| Tipo | `tipo` | text | ✅ | `cliente`, `proveedor`, `ambos` |
| Email | `email` | text | — | Validación formato email |
| Teléfono | `telefono` | text | — | Máx 20 chars |
| Dirección | `direccion` | text | — | Máx 500 chars |
| Ciudad | `ciudad` | text | — | |
| Límite de Crédito USD | `limite_credito` | decimal | — | |
| Días de Crédito | `dias_credito` | integer | — | |

**RPC destino:** `import_contacto(p_empresa_id, p_fila)`

### `entidades / productos` — Importar Productos / Servicios

| Etiqueta CSV | Campo | Tipo | Req | Notas |
|-------------|-------|------|-----|-------|
| Código / SKU | `codigo` | text | ✅ | Máx 100 chars |
| Nombre del Producto | `nombre` | text | ✅ | Máx 300 chars |
| Descripción | `descripcion` | text | — | |
| Tipo | `tipo` | text | ✅ | `producto`, `servicio`, `consumible` |
| Precio de Venta | `precio_venta` | decimal | ✅ | |
| Costo | `costo` | decimal | — | |
| IVA % | `iva_porcentaje` | decimal | — | Default: `15` |
| Unidad de Medida | `unidad_medida` | text | — | Default: `UND` |
| Código de Barras | `codigo_barras` | text | — | |
| Activo (S/N) | `activo` | boolean | — | Default: `S` |

**RPC destino:** `import_producto(p_empresa_id, p_fila)`

### `contabilidad / saldos_iniciales` — Importar Saldos de Apertura

| Etiqueta CSV | Campo | Tipo | Req | Notas |
|-------------|-------|------|-----|-------|
| Código Cuenta | `codigo_cuenta` | text | ✅ | |
| Nombre Cuenta | `nombre_cuenta` | text | — | |
| Saldo Débito | `saldo_debe` | decimal | — | Default: `0` |
| Saldo Crédito | `saldo_haber` | decimal | — | Default: `0` |
| Fecha Apertura | `fecha` | date | ✅ | Formato `YYYY-MM-DD` |

**RPC destino:** `import_saldo_inicial(p_empresa_id, p_fila)`

---

## RPCs de gestión

### `registrar_import_template(modulo, recurso, nombre, descripcion, campos, rpc_destino)`
Registra o actualiza un template global (empresa_id=NULL). **Idempotente** — segura para re-ejecutar en seeds.

```sql
-- Ejemplo: módulo RRHH registra su template de empleados
SELECT registrar_import_template(
    'rrhh',
    'empleados',
    'Importar Empleados',
    'Importa la nómina base de empleados.',
    '[
      {"nombre":"cedula",     "etiqueta":"Cédula",      "tipo":"text",    "requerido":true, "patron":"^[0-9]{10}$"},
      {"nombre":"nombre",     "etiqueta":"Nombre",      "tipo":"text",    "requerido":true},
      {"nombre":"fecha_ingreso","etiqueta":"Fecha Ingreso","tipo":"date",  "requerido":true, "formato":"YYYY-MM-DD"},
      {"nombre":"salario",    "etiqueta":"Salario Base", "tipo":"decimal", "requerido":true}
    ]'::JSONB,
    'import_empleado'
);
```

### `get_import_templates([modulo, recurso])`
Retorna templates disponibles para el usuario (globales + de su empresa).

### `get_import_jobs([modulo, recurso, limite=20])`
Historial de importaciones del usuario actual.

### `finalizar_import_job(job_id, filas_ok, filas_error, errores_json, estado)`
Llamada por la Edge Function al finalizar. No debe llamarse manualmente.

---

## Cómo añadir un template en un módulo nuevo

1. **Crear la RPC destino** en las migraciones del módulo:
```sql
-- modules/core/mi_modulo/supabase/migrations/NNN_import.sql
CREATE OR REPLACE FUNCTION import_mi_entidad(
    p_empresa_id UUID,
    p_fila       JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER AS $$
DECLARE v_id UUID;
BEGIN
    INSERT INTO mi_entidades (empresa_id, nombre, ...)
    VALUES (p_empresa_id, p_fila->>'nombre', ...)
    RETURNING id INTO v_id;

    RETURN jsonb_build_object('ok', true, 'id', v_id);
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLERRM);
END;
$$;
```

2. **Registrar el template** al final de la migración:
```sql
SELECT registrar_import_template(
    'mi_modulo',
    'mi_entidad',
    'Importar Mi Entidad',
    'Descripción del template.',
    '[{"nombre":"nombre","etiqueta":"Nombre","tipo":"text","requerido":true}]'::JSONB,
    'import_mi_entidad'
);
```

3. **Listo.** La Edge Function `import-data` lo detectará automáticamente al recibir ese `template_id`.

---

## Implementación Flutter

### Pantalla de importación sugerida

```
ImportScreen
├─ Selector de template (dropdown con get_import_templates())
├─ Botón "Descargar plantilla CSV" (genera CSV con encabezados del template)
├─ FilePicker (CSV o XLSX)
├─ Botón "Validar sin importar" (dry_run=true)
├─ Preview de errores (si los hay)
├─ Botón "Importar" (dry_run=false)
└─ Historial (get_import_jobs() con estado y errores descargables)
```

### Generar plantilla CSV desde Flutter

```dart
String generarPlantillaCSV(List<Map<String, dynamic>> campos) {
    final headers = campos
        .map((c) => '"${c['etiqueta']}"')
        .join(',');
    return headers + '\n'; // CSV vacío con encabezados
}
```

---

## Formatos de archivo soportados

| Formato | Extensión | Notas |
|---------|-----------|-------|
| CSV | `.csv` | Separador: coma o punto y coma (auto-detectado). Encoding: UTF-8 (BOM permitido) |
| Excel | `.xlsx` | Primera hoja. Encabezados en fila 1. Celdas con fórmulas: usa el valor calculado |
| Excel legacy | `.xls` | Soportado vía SheetJS |

**Tips para el usuario:**
- La primera fila debe tener los encabezados exactos del template
- Las filas vacías son ignoradas
- Los números con formato `$1,234.56` son parseados correctamente (se eliminan `$` y `,`)
- Las fechas deben estar en formato YYYY-MM-DD (no fechas Excel serializadas)

---

## Consideraciones de diseño

**¿Por qué data-driven y no hardcoded?**
Al estilo Odoo, los templates viven en la base de datos. Añadir soporte de importación para un módulo nuevo no requiere cambiar la Edge Function — solo registrar el template con `registrar_import_template()`.

**¿Por qué `rpc_destino` como string?**
La Edge Function llama dinámicamente `SELECT {rpc_destino}(empresa_id, fila)` — el módulo controla toda la lógica de inserción (validaciones de negocio, defaults, relaciones). La Edge Function solo se encarga del parsing y validación de tipos.

**¿Por qué guardar `errores` en JSONB y no en tabla separada?**
Para jobs pequeños-medianos (< 5,000 filas), el JSONB es más eficiente. Si se necesitan jobs de millones de filas, se puede añadir una tabla `import_job_errores` normalizada en el futuro.
