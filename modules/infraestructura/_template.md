# [FILL: Nombre del Módulo]

> [FILL: Una línea describiendo el propósito del módulo.]
> Tipo: [FILL: Infraestructura | Core | Auxiliar]
> Última revisión: [FILL: YYYY-MM-DD]

---

## Descripción

[FILL: 3-5 líneas explicando qué hace el módulo, a quién sirve y cuál es su valor de negocio principal. Incluir si es activable por empresa y bajo qué plan SaaS.]

---

## Dependencias

### Requiere (módulos que deben estar activos)
- [FILL: ej. Inventario — para consumo de materiales]
- [FILL: ej. Facturación — para emitir documentos electrónicos]

### Expone servicios a (módulos que consumen este módulo)
- [FILL: ej. Garantías/RMA — consume `module_bus.taller.create_repair_order()`]

> Si el módulo es **Auxiliar**: indicar qué funciones de `module_bus.*` consume de módulos Core.
> Si el módulo es **Core**: indicar qué funciones expone en `module_bus.<modulo>.*`.

---

## Navegación (go_router)

```
/[modulo]/                        → [FILL: Pantalla principal / lista]
/[modulo]/nuevo                   → [FILL: Formulario creación]
/[modulo]/:id                     → [FILL: Detalle / edición]
/[modulo]/:id/sub-seccion         → [FILL: Sub-sección si aplica]
/[modulo]/reportes                → [FILL: Pantalla de reportes, si aplica]
/[modulo]/configuracion           → [FILL: Configuración del módulo, si aplica]
```

Estructura Flutter:
```
lib/features/[modulo]/
├── screens/
│   ├── [modulo]_list_screen.dart      # Lista con DataGrid
│   ├── [modulo]_form_screen.dart      # Formulario crear/editar
│   ├── [modulo]_detail_screen.dart    # Vista detalle (si aplica)
│   └── [modulo]_config_screen.dart    # Configuración (si aplica)
├── providers/
│   ├── [modulo]_provider.dart         # StateNotifier principal
│   └── [modulo]_form_provider.dart    # Estado del formulario
└── widgets/
    └── [modulo]_card.dart             # Widget de tarjeta para listas
```

---

## Modelo de Datos SQL

> Convención de nombres: todas las tablas en `snake_case`, prefijo del módulo donde sea necesario para evitar colisiones. `empresa_id UUID NOT NULL` en todas las tablas. `created_at` y `updated_at TIMESTAMPTZ` en todas las tablas. Montos en `DECIMAL(14,2)`, cantidades en `DECIMAL(18,6)`.

### Tabla principal: `[FILL: nombre_tabla]`

```sql
CREATE TABLE [nombre_tabla] (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id      UUID NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,

    -- [FILL: Campos de identificación del negocio]
    -- Ejemplo:
    -- numero          VARCHAR(20)     NOT NULL,
    -- estado          VARCHAR(20)     NOT NULL DEFAULT 'BORRADOR'
    --                 CHECK (estado IN ('BORRADOR','CONFIRMADO','CANCELADO')),

    -- [FILL: Campos de relaciones / FKs]
    -- contacto_id     UUID            REFERENCES contactos(id),

    -- [FILL: Campos de valores / montos]
    -- subtotal        DECIMAL(14,2)   NOT NULL DEFAULT 0,
    -- total           DECIMAL(14,2)   NOT NULL DEFAULT 0,

    -- [FILL: Campos de control]
    version         INTEGER         NOT NULL DEFAULT 1,  -- bloqueo optimista (obligatorio en docs SRI)

    -- Auditoría
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    created_by      UUID            REFERENCES auth.users(id),
    updated_by      UUID            REFERENCES auth.users(id),

    -- Constraints
    CONSTRAINT [nombre_tabla]_[campo]_unique UNIQUE (empresa_id, [FILL: campo_unico])
);

-- [FILL: Comentario de la tabla]
COMMENT ON TABLE [nombre_tabla] IS '[FILL: Descripción en una línea]';
```

### Tabla de líneas: `[FILL: nombre_tabla_lineas]` (si aplica)

```sql
CREATE TABLE [nombre_tabla_lineas] (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id      UUID NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
    [cabecera_id]   UUID NOT NULL REFERENCES [nombre_tabla](id) ON DELETE CASCADE,

    -- [FILL: Campos de la línea]
    -- producto_id     UUID            REFERENCES productos(id),
    -- descripcion     TEXT,
    -- cantidad        DECIMAL(18,6)   NOT NULL DEFAULT 1,
    -- precio_unitario DECIMAL(14,2)   NOT NULL DEFAULT 0,
    -- subtotal        DECIMAL(14,2)   NOT NULL DEFAULT 0,

    -- Posición para ordenamiento
    secuencia       INTEGER         NOT NULL DEFAULT 10,

    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);
```

### [FILL: Tabla adicional N] (si aplica)

```sql
-- [FILL: CREATE TABLE para tablas de configuración, logs, etc.]
```

---

## Funciones RPC Principales

> Todas las RPCs viven en el schema `public` o en `module_bus.[modulo]`. Se llaman desde Flutter vía `supabase.rpc('nombre_funcion', params: {...})` o desde Edge Functions.

### `[FILL: nombre_funcion]`

```sql
CREATE OR REPLACE FUNCTION [nombre_funcion](
    p_empresa_id    UUID,
    -- [FILL: parámetros adicionales]
    p_param1        [tipo],
    p_param2        [tipo]
)
RETURNS [tipo_retorno]  -- UUID | JSONB | TABLE(...) | VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
    v_empresa_id UUID := (SELECT private.get_empresa_id());
    -- [FILL: variables locales]
BEGIN
    -- [FILL: Validaciones de negocio]

    -- [FILL: Lógica principal]

    -- [FILL: Retorno]
    RETURN [resultado];
END;
$$;

COMMENT ON FUNCTION [nombre_funcion] IS '[FILL: Qué hace, cuándo se usa, qué retorna]';
```

### `[FILL: nombre_funcion_2]` (repetir para cada RPC principal)

```sql
-- [FILL: Firma y cuerpo]
```

---

## Module Service Bus

### Funciones que este módulo EXPONE (solo módulos Core)

> Si este módulo es **Auxiliar**, omitir esta sección.

```sql
-- Schema: module_bus.[modulo]
-- Las funciones gateway verifican si el módulo destino está activo
-- antes de ejecutar. Si no está activo, retornan un NO-OP seguro.

CREATE OR REPLACE FUNCTION module_bus.[modulo].[nombre_funcion](
    p_empresa_id    UUID,
    -- [FILL: parámetros]
)
RETURNS [tipo_retorno]
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Verificar si este módulo está activo para la empresa
    IF NOT EXISTS (
        SELECT 1 FROM modulos_empresa
        WHERE empresa_id = p_empresa_id
          AND modulo_codigo = '[FILL: codigo_modulo]'
          AND activo = TRUE
    ) THEN
        -- NO-OP: retornar valor neutro según el tipo
        RETURN NULL;  -- o RETURN 0; o RETURN '{}'; según contexto
    END IF;

    -- [FILL: Lógica real]
END;
$$;
```

### Funciones que este módulo CONSUME (módulos Auxiliares o Core que dependen de otros Core)

```
module_bus.[modulo_destino].[funcion]()  →  [FILL: Propósito]
module_bus.[modulo_destino].[funcion]()  →  [FILL: Propósito]
```

---

## Políticas RLS

> Patrón obligatorio: usar `(SELECT private.get_empresa_id())` — nunca parsing inline del JWT.
> Aplicar `TO authenticated` en todas las políticas.

```sql
-- Habilitar RLS en cada tabla
ALTER TABLE [nombre_tabla] ENABLE ROW LEVEL SECURITY;

-- SELECT: leer solo datos de la empresa propia
CREATE POLICY "[nombre_tabla]_select"
    ON [nombre_tabla] FOR SELECT
    TO authenticated
    USING (empresa_id = (SELECT private.get_empresa_id()));

-- INSERT: solo insertar en la empresa propia
CREATE POLICY "[nombre_tabla]_insert"
    ON [nombre_tabla] FOR INSERT
    TO authenticated
    WITH CHECK (empresa_id = (SELECT private.get_empresa_id()));

-- UPDATE: solo modificar registros de la empresa propia
-- [FILL: Agregar condición de estado si aplica, ej: AND estado != 'CANCELADO']
CREATE POLICY "[nombre_tabla]_update"
    ON [nombre_tabla] FOR UPDATE
    TO authenticated
    USING (empresa_id = (SELECT private.get_empresa_id()))
    WITH CHECK (empresa_id = (SELECT private.get_empresa_id()));

-- DELETE: [FILL: evaluar si se permite borrado o solo cancelación lógica]
-- Opción 1: permitir borrado solo en borrador
CREATE POLICY "[nombre_tabla]_delete"
    ON [nombre_tabla] FOR DELETE
    TO authenticated
    USING (
        empresa_id = (SELECT private.get_empresa_id())
        AND estado = 'BORRADOR'  -- [FILL: ajustar según estados del módulo]
    );

-- [FILL: Repetir para cada tabla del módulo]
```

---

## Índices

```sql
-- Índice de empresa (siempre presente para filtros RLS)
CREATE INDEX idx_[tabla]_empresa ON [nombre_tabla](empresa_id);

-- [FILL: Índices de búsqueda frecuente]
-- CREATE INDEX idx_[tabla]_[campo] ON [nombre_tabla](empresa_id, [campo]);

-- [FILL: Índice de texto si hay búsqueda por nombre/descripción]
-- CREATE INDEX idx_[tabla]_nombre ON [nombre_tabla] USING gin(to_tsvector('spanish', nombre));

-- [FILL: Índice de fecha para rangos temporales frecuentes]
-- CREATE INDEX idx_[tabla]_fecha ON [nombre_tabla](empresa_id, fecha DESC);

-- [FILL: Índice parcial para estados activos si los queries filtran por estado]
-- CREATE INDEX idx_[tabla]_activo ON [nombre_tabla](empresa_id, created_at)
--     WHERE estado NOT IN ('CANCELADO', 'CERRADO');
```

---

## Triggers

```sql
-- Trigger para updated_at automático (aplicar a todas las tablas)
CREATE TRIGGER tr_[nombre_tabla]_updated_at
    BEFORE UPDATE ON [nombre_tabla]
    FOR EACH ROW
    EXECUTE FUNCTION private.set_updated_at();

-- [FILL: Trigger de numeración secuencial (si el módulo asigna números)]
-- CREATE OR REPLACE FUNCTION tr_[tabla]_numero_fn()
-- RETURNS TRIGGER LANGUAGE plpgsql AS $$
-- BEGIN
--     IF NEW.estado = 'CONFIRMADO' AND OLD.estado = 'BORRADOR' THEN
--         NEW.numero := private.next_sequence(NEW.empresa_id, '[FILL: prefijo]');
--     END IF;
--     RETURN NEW;
-- END;
-- $$;
--
-- CREATE TRIGGER tr_[tabla]_numero
--     BEFORE UPDATE ON [nombre_tabla]
--     FOR EACH ROW EXECUTE FUNCTION tr_[tabla]_numero_fn();

-- [FILL: Trigger de bloqueo optimista (obligatorio para documentos SRI)]
-- CREATE OR REPLACE FUNCTION tr_[tabla]_version_fn()
-- RETURNS TRIGGER LANGUAGE plpgsql AS $$
-- BEGIN
--     IF NEW.version != OLD.version + 1 THEN
--         RAISE EXCEPTION 'Conflicto de versión: registro modificado por otro proceso';
--     END IF;
--     NEW.version := OLD.version + 1;
--     RETURN NEW;
-- END;
-- $$;

-- [FILL: Otros triggers de validación de negocio]
```

---

## Edge Functions (si aplica)

> Solo si el módulo requiere procesamiento server-side que no puede hacerse en PostgreSQL: firma digital, SOAP, generación de archivos, integración con APIs externas, IA.

### `[FILL: nombre-edge-function]`

```typescript
// supabase/functions/[nombre-edge-function]/index.ts
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

// [FILL: Descripción de qué hace esta Edge Function]
// Disparador: [FILL: ej. "llamada desde la app al confirmar una factura"]
// Input: { empresa_id, [FILL: parámetros] }
// Output: { success: boolean, [FILL: resultado] }

Deno.serve(async (req: Request) => {
    // [FILL: Implementación]
    const { empresa_id } = await req.json();

    // [FILL: Lógica principal]

    return new Response(
        JSON.stringify({ success: true }),
        { headers: { "Content-Type": "application/json" } }
    );
});
```

**Variables de entorno requeridas:**
- `[FILL: NOMBRE_VAR]` — [FILL: para qué se usa]

---

## Integraciones con otros módulos

| Módulo | Tipo de integración | Descripción |
|--------|---------------------|-------------|
| [FILL: Facturación] | Consume vía module_bus | [FILL: ej. Emite facturas al confirmar OV] |
| [FILL: Inventario] | Consume vía module_bus | [FILL: ej. Reserva stock al confirmar OV] |
| [FILL: Contabilidad] | Consume vía module_bus | [FILL: ej. Genera asiento al cobrar] |
| [FILL: Comunicación] | Servicio de plataforma | [FILL: ej. Envía email/WhatsApp al cliente] |

---

## Sub-módulos relacionados

| Sub-módulo | Archivo | Descripción |
|-----------|---------|-------------|
| [FILL: nombre] | [FILL: ruta/archivo.md] | [FILL: Descripción breve] |

---

## Notas de implementación

- [FILL: Particularidades o decisiones de diseño importantes para este módulo]
- [FILL: Casos borde conocidos]
- [FILL: Limitaciones o restricciones conocidas]
- [FILL: Referencias a documentación externa: normativa SRI, especificación técnica, etc.]
