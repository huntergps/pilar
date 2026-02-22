# Workflows de Aprobación

> Migración: `021_approval_workflows.sql`
> Depende de: `020_notification_center.sql`
> Módulo: Foundation (transversal — cualquier módulo puede usar aprobaciones)
> Última revisión: 2026-02-22

---

## Descripción

Sistema de workflows de aprobación configurable por empresa, módulo y recurso. Permite que cualquier módulo requiera aprobación antes de confirmar una operación (orden de compra, cotización, pago, etc.).

**Características:**
- Reglas configurables con condiciones JSONB (ej: `monto >= 5000`)
- Aprobadores por rol o por usuario específico
- Dos modos: **simple** (cualquier aprobador resuelve) o **consenso** (todos deben votar)
- Notificación automática a aprobadores al solicitar
- Notificación automática al solicitante al resolver
- Expiración automática vía pg_cron (cada 30 minutos)
- Historial completo con snapshots del registro

---

## Ciclo de vida de una solicitud

```
          solicitar_aprobacion()
                   │
                   ▼
              [PENDIENTE] ──── pg_cron ──── [EXPIRADO]
                   │
        ┌──────────┴──────────────────┐
        │                             │
  cancelar()                   resolver_aprobacion()
        │                             │
   [CANCELADO]           ┌────────────┴────────────┐
                         │                          │
                    [APROBADO]               [RECHAZADO]
```

---

## Tablas

### `reglas_aprobacion`

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `id` | UUID PK | |
| `empresa_id` | UUID FK | Tenant (RLS) |
| `modulo` | TEXT | ej: `compras`, `ventas`, `tesoreria` |
| `recurso` | TEXT | ej: `orden_compra`, `cotizacion`, `pago` |
| `nombre` | TEXT | Nombre descriptivo de la regla |
| `orden` | INTEGER | Para priorizar cuando hay múltiples reglas del mismo módulo/recurso |
| `condicion` | JSONB | `{ "campo": "monto_total", "operador": ">=", "valor": 5000 }` |
| `aprobadores` | JSONB | Array de `{ tipo: "rol"/"usuario", valor: "GERENTE"/"uuid" }` |
| `requiere_todos` | BOOLEAN | `false`=simple, `true`=consenso |
| `timeout_horas` | INTEGER | Horas antes de expirar (1–8760) |
| `activa` | BOOLEAN | Permite desactivar sin borrar |

### `solicitudes_aprobacion`

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `id` | UUID PK | |
| `regla_id` | UUID FK | Regla que disparó la solicitud |
| `modulo` / `recurso` | TEXT | Para consultas sin JOIN |
| `registro_id` | UUID | ID del registro en la tabla del módulo |
| `estado` | TEXT | PENDIENTE · APROBADO · RECHAZADO · EXPIRADO · CANCELADO |
| `solicitante_id` | UUID | Usuario que creó la solicitud |
| `datos_snapshot` | JSONB | Estado del registro al solicitar (para que el aprobador vea qué aprueba) |
| `expira_at` | TIMESTAMPTZ | Calculado: `created_at + timeout_horas` |

### `aprobacion_votos`

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `solicitud_id` | UUID FK | |
| `aprobador_id` | UUID FK | |
| `voto` | TEXT | APROBADO · RECHAZADO |
| `comentario` | TEXT | Opcional |
| UNIQUE | `(solicitud_id, aprobador_id)` | Un voto por aprobador — el último sobreescribe |

---

## Condiciones soportadas

| Operador | Descripción | Ejemplo |
|----------|-------------|---------|
| `=` | Igual | `{"campo":"estado","operador":"=","valor":"BORRADOR"}` |
| `!=` | Diferente | `{"campo":"tipo","operador":"!=","valor":"interno"}` |
| `>` | Mayor que | `{"campo":"monto_total","operador":">","valor":1000}` |
| `>=` | Mayor o igual | `{"campo":"monto_total","operador":">=","valor":5000}` |
| `<` | Menor que | `{"campo":"dias_plazo","operador":"<","valor":30}` |
| `<=` | Menor o igual | `{"campo":"descuento_pct","operador":"<=","valor":20}` |
| `in` | Está en lista | `{"campo":"tipo_doc","operador":"in","valor":["factura","nota_debito"]}` |
| `contains` | Contiene texto | `{"campo":"proveedor_nombre","operador":"contains","valor":"IMPORTADORA"}` |

---

## RPCs

### `evaluar_reglas_aprobacion(modulo, recurso, datos_jsonb)`
Retorna las reglas que aplican a los datos. Úsala para saber si un registro requiere aprobación **antes** de solicitarla.

```sql
-- ¿Esta OC de $8,000 requiere aprobación?
SELECT * FROM evaluar_reglas_aprobacion(
    'compras',
    'orden_compra',
    '{"monto_total": 8000, "proveedor_tipo": "importacion"}'::JSONB
);
```

### `solicitar_aprobacion(modulo, recurso, registro_id, [datos, comentario])`
Crea la solicitud y notifica aprobadores. Retorna `UUID` de la solicitud.

```sql
SELECT solicitar_aprobacion(
    'compras',
    'orden_compra',
    'uuid-de-la-oc',
    '{"monto_total": 8000, "proveedor": "Importadora XYZ"}'::JSONB,
    'Compra urgente para proyecto cliente ABC'
);
```

**Excepciones:**
- `sin_regla_aplicable` — no hay regla activa para esos datos
- `solicitud_ya_pendiente` — ya existe una PENDIENTE para ese registro

### `resolver_aprobacion(solicitud_id, decision, [comentario])`
Registra el voto del usuario actual.

```sql
-- Aprobar
SELECT resolver_aprobacion('uuid-solicitud', 'APROBADO', 'Revisado y conforme');

-- Rechazar
SELECT resolver_aprobacion('uuid-solicitud', 'RECHAZADO', 'Proveedor no aprobado por tesorería');
```

**Retorno:**
```json
// Resolución inmediata
{ "estado": "APROBADO", "solicitud_id": "uuid" }

// Esperando más votos (requiere_todos=true)
{ "estado": "ESPERANDO_VOTOS", "votos_favor": 2, "total_needed": 3 }
```

### `cancelar_solicitud_aprobacion(solicitud_id)`
Solo el solicitante puede cancelar su propia solicitud PENDIENTE.

### `get_aprobaciones_pendientes_mias()`
Retorna las solicitudes donde el usuario actual puede votar y aún no ha votado.

---

## Configurar una regla de aprobación

### Ejemplo 1: Órdenes de compra > $5,000 requieren GERENTE

```sql
INSERT INTO reglas_aprobacion (
    empresa_id, modulo, recurso, nombre,
    condicion, aprobadores, requiere_todos, timeout_horas
) VALUES (
    private.get_empresa_id(),
    'compras', 'orden_compra',
    'OC mayores a $5,000 requieren aprobación gerencial',
    '{"campo": "monto_total", "operador": ">=", "valor": 5000}'::JSONB,
    '[{"tipo": "rol", "valor": "GERENTE"}]'::JSONB,
    false,
    48
);
```

### Ejemplo 2: Pagos > $10,000 requieren GERENTE + CONTADOR (consenso)

```sql
INSERT INTO reglas_aprobacion (
    empresa_id, modulo, recurso, nombre,
    condicion, aprobadores, requiere_todos, timeout_horas
) VALUES (
    private.get_empresa_id(),
    'tesoreria', 'pago',
    'Pagos > $10K requieren aprobación dual',
    '{"campo": "monto", "operador": ">=", "valor": 10000}'::JSONB,
    '[{"tipo": "rol", "valor": "GERENTE"}, {"tipo": "rol", "valor": "CONTADOR"}]'::JSONB,
    true,    -- todos deben aprobar
    24
);
```

### Ejemplo 3: Descuentos > 20% en cotizaciones requieren usuario específico

```sql
INSERT INTO reglas_aprobacion (
    empresa_id, modulo, recurso, nombre,
    condicion, aprobadores, requiere_todos, timeout_horas
) VALUES (
    private.get_empresa_id(),
    'ventas', 'cotizacion',
    'Descuentos > 20% requieren aprobación de Gerente Comercial',
    '{"campo": "descuento_pct", "operador": ">", "valor": 20}'::JSONB,
    '[{"tipo": "usuario", "valor": "uuid-gerente-comercial"}]'::JSONB,
    false,
    72
);
```

---

## Integración en módulos

### Patrón de integración en SQL de módulo

```sql
-- En la función de confirmación de una OC:
CREATE OR REPLACE FUNCTION confirmar_orden_compra(p_oc_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_oc   RECORD;
    v_regla RECORD;
BEGIN
    SELECT * INTO v_oc FROM ordenes_compra
    WHERE id = p_oc_id AND empresa_id = (SELECT private.get_empresa_id());

    -- 1. ¿Requiere aprobación?
    SELECT * INTO v_regla FROM evaluar_reglas_aprobacion(
        'compras', 'orden_compra',
        row_to_json(v_oc)::JSONB
    ) LIMIT 1;

    IF FOUND THEN
        -- 2. Solicitar aprobación y detener el flujo
        DECLARE v_sol_id UUID;
        BEGIN
            v_sol_id := solicitar_aprobacion(
                'compras', 'orden_compra', p_oc_id,
                row_to_json(v_oc)::JSONB,
                'Confirmación automática de OC'
            );
        END;

        -- Poner la OC en estado PENDIENTE_APROBACION
        UPDATE ordenes_compra SET estado = 'PENDIENTE_APROBACION' WHERE id = p_oc_id;

        RETURN jsonb_build_object('requiere_aprobacion', true, 'solicitud_id', v_sol_id);
    END IF;

    -- 3. Sin aprobación requerida — confirmar directamente
    UPDATE ordenes_compra SET estado = 'CONFIRMADA' WHERE id = p_oc_id;
    RETURN jsonb_build_object('confirmada', true);
END;
$$;
```

### Webhook: escuchar resolución desde Flutter

El módulo debe escuchar cambios en `solicitudes_aprobacion` para reaccionar cuando se resuelve:

```dart
// En el provider del módulo
supabase
    .from('solicitudes_aprobacion')
    .stream(primaryKey: ['id'])
    .eq('registro_id', ocId)
    .listen((rows) {
      final ultima = rows.firstOrNull;
      if (ultima?['estado'] == 'APROBADO') {
        // Refrescar datos de la OC
        ref.invalidate(ordenCompraProvider(ocId));
      }
    });
```

---

## pg_cron

| Job | Schedule | Descripción |
|-----|----------|-------------|
| `pilar_expire_approval_requests` | `*/30 * * * *` | Marca EXPIRADO las solicitudes vencidas (expira_at < NOW()) |

---

## Consideraciones de diseño

**¿Por qué no un motor de workflows completo (BPMN)?**
Los workflows complejos tipo Camunda/Flowable son excesivos para PYMEs. Este sistema cubre el 80% de los casos de uso con una tabla de reglas simple. Para workflows multi-paso (A aprueba → B valida → C confirma), se puede implementar una cadena de llamadas a `solicitar_aprobacion()` en el callback de resolución.

**¿Pueden haber múltiples reglas para el mismo módulo/recurso?**
Sí — se evalúan en orden (`orden ASC`) y se usa la primera que aplica. Útil para escalado: OC > $1K → JEFE_COMPRAS; OC > $10K → GERENTE.

**Snapshot de datos:**
`datos_snapshot` guarda el estado del registro en el momento de solicitar. Si el registro cambia mientras está pendiente, el aprobador igual ve los datos originales que generaron la solicitud.
