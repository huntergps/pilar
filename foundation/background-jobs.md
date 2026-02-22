# Background Jobs: pg_cron y pgmq en PILAR ERP

Documentación de los jobs programados y colas de mensajes asíncronos que sostienen las operaciones automáticas del ERP. Cubre las dos extensiones nativas de PostgreSQL usadas en Supabase: `pg_cron` para tareas periódicas y `pgmq` para procesamiento asíncrono con reintentos.

---

## Resumen de Herramientas

| Herramienta | Cuándo usarla |
|-------------|---------------|
| **pg_cron** | Tareas periódicas simples sin estado, sin reintentos críticos |
| **pgmq** | Procesamiento asíncrono con reintentos, alta concurrencia, trazabilidad |
| **Edge Function directa** | Respuesta síncrona que el usuario espera en < 5 s |

> **Regla**: nunca bloquear al usuario esperando una respuesta de red externa (organismos fiscales, email, WhatsApp). Todo lo que implique llamadas HTTP a terceros va a una cola pgmq.

---

## Sección 1: pg_cron (Supabase Cron)

### Qué es

`pg_cron` es una extensión de PostgreSQL que ejecuta trabajos programados directamente dentro de la base de datos usando sintaxis cron estándar. Supabase la provee habilitada por defecto en todos los proyectos; no requiere instalación adicional.

Los jobs se registran en el schema `cron` y pueden llamar:
- Funciones SQL/PL/pgSQL del schema `public` o schemas privados
- Instrucciones SQL arbitrarias
- Funciones `net.http_post()` de `pg_net` para disparar Edge Functions

### Habilitar en Supabase

La extensión viene habilitada. Para verificar o activar desde el SQL Editor:

```sql
-- Verificar que pg_cron está activa
SELECT * FROM pg_extension WHERE extname = 'pg_cron';

-- Si no está activa (proyectos on-premise):
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Verificar jobs registrados
SELECT jobid, schedule, command, jobname, active
FROM cron.job
ORDER BY jobid;

-- Ver historial de ejecuciones (últimas 100)
SELECT *
FROM cron.job_run_details
ORDER BY start_time DESC
LIMIT 100;
```

### Sintaxis de schedule

```
┌────────────── minuto (0-59)
│ ┌──────────── hora (0-23)
│ │ ┌────────── día del mes (1-31)
│ │ │ ┌──────── mes (1-12)
│ │ │ │ ┌────── día de la semana (0-7, donde 0 y 7 = domingo)
│ │ │ │ │
* * * * *
```

---

### Jobs de foundation (infrastructure-level)

Los únicos jobs que registra foundation son los de mantenimiento de infraestructura (limpieza de sesiones, tokens OTP, y logs de cron). **Cada módulo define y documenta sus propios jobs en `<modulo>/migrations/` y `<modulo>/background-jobs.md`**.

```sql
-- ============================================================
-- Foundation — pg_cron Jobs de Infraestructura
-- Solo mantenimiento de tablas de foundation.
-- Los módulos definen sus propios jobs en sus migraciones.
-- ============================================================

-- ------------------------------------------------------------
-- Limpieza diaria: sesiones expiradas, tokens OTP y logs de cron
-- ------------------------------------------------------------
SELECT cron.schedule(
  'pilar_cleanup_expired_sessions',
  '0 3 * * *',   -- 3 AM UTC diario (ajustar según zona horaria local del tenant)
  $$
  DELETE FROM sesiones_usuario
  WHERE expira_en < now() - interval '7 days';

  DELETE FROM tokens_otp
  WHERE expira_en < now();

  DELETE FROM cron.job_run_details
  WHERE start_time < now() - interval '30 days';
  $$
);
```

### Template para jobs de módulos

Cada módulo que requiera un job periódico sigue este patrón en su propio archivo de migraciones:

```sql
-- Patrón: job periódico de un módulo
SELECT cron.schedule(
  'pilar_<modulo>_<descripcion>',           -- nombre único, prefijo 'pilar_'
  '<expresion_cron>',                        -- schedule estándar cron
  $$
  SELECT public.<funcion_del_modulo>();
  $$
);

CREATE OR REPLACE FUNCTION public.<funcion_del_modulo>()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER                             -- requerido: cron no tiene usuario
SET search_path = public
AS $$
BEGIN
  -- Lógica del módulo aquí
  -- IMPORTANTE: filtrar por empresa_id explícitamente cuando corresponda
END;
$$;
```

> **Nota de implementación**: Los jobs de módulos como alertas de vencimiento, sincronización de integraciones externas, cálculos periódicos y generación de embeddings se documentan en el `module.md` o `background-jobs.md` de cada módulo, y su SQL vive en las migraciones del módulo correspondiente.

### Convención de nombres de jobs

Todos los jobs del sistema siguen el patrón `pilar_<modulo>_<descripcion>` para facilitar monitoreo y filtrado:

| Patrón | Ejemplo | Descripción |
|--------|---------|-------------|
| `pilar_cleanup_*` | `pilar_cleanup_expired_sessions` | Mantenimiento periódico |
| `pilar_<modulo>_*` | `pilar_<modulo>_<funcion>` | Jobs propios de cada módulo |
| `pilar_integrations_*` | `pilar_integrations_<plataforma>` | Sync con sistemas externos |

Los jobs de cada módulo se listan en la documentación del módulo (`<modulo>/background-jobs.md`).

### Monitorear y administrar jobs

```sql
-- Ver estado de todos los jobs PILAR
SELECT
  j.jobname,
  j.schedule,
  j.active,
  r.status,
  r.start_time,
  r.end_time,
  r.return_message,
  EXTRACT(MILLISECONDS FROM (r.end_time - r.start_time))::int AS duracion_ms
FROM cron.job j
LEFT JOIN LATERAL (
  SELECT * FROM cron.job_run_details
  WHERE jobid = j.jobid
  ORDER BY start_time DESC
  LIMIT 1
) r ON true
WHERE j.jobname LIKE 'pilar_%'
ORDER BY j.jobname;

-- Desactivar un job temporalmente (ej: mantenimiento)
SELECT cron.unschedule('pilar_nombre_del_job');

-- Reactivar con el mismo schedule
SELECT cron.schedule(
  'pilar_nombre_del_job',
  '*/2 * * * *',
  $$ SELECT net.http_post(...); $$
);

-- Ver jobs fallidos en las últimas 24 horas
SELECT jobname, start_time, return_message
FROM cron.job_run_details jrd
JOIN cron.job j ON j.jobid = jrd.jobid
WHERE jrd.status = 'failed'
  AND jrd.start_time > now() - interval '24 hours'
  AND j.jobname LIKE 'pilar_%'
ORDER BY jrd.start_time DESC;
```

---

## Sección 2: pgmq (Message Queue)

### Qué es

`pgmq` (Postgres Message Queue) es una extensión de PostgreSQL que implementa una cola de mensajes ligera, persistente y con garantías de entrega, similar en concepto a AWS SQS pero completamente dentro de la base de datos. Supabase la incluye y expone via SQL.

Ventajas sobre pg_cron para tareas asíncronas:
- **Exactly-once delivery**: visibilidad temporal (VT) previene procesamiento duplicado
- **Reintentos automáticos**: mensajes no procesados se re-encolan al expirar VT
- **Trazabilidad**: log de todos los mensajes con estado
- **Backpressure**: workers controlan su propio ritmo de consumo

### Cuándo usar pgmq vs pg_cron

| Criterio | pg_cron | pgmq |
|----------|---------|------|
| Tarea periódica fija | Si | No |
| Procesamiento item por item | No | Si |
| Reintentos por ítem fallido | No (todo el batch) | Si (por mensaje) |
| Disparada por evento (trigger) | No | Si |
| Priorización por ítem | No | Si (ordenar cola) |
| Auditoría por mensaje | Limitada | Completa |
| Ejemplo PILAR | Refrescar vistas, alertas diarias | Enviar documento electrónico a organismo fiscal, notificar cliente |

### Habilitar pgmq

```sql
-- pgmq viene disponible en Supabase. Activar la extensión:
CREATE EXTENSION IF NOT EXISTS pgmq;

-- Verificar
SELECT * FROM pg_extension WHERE extname = 'pgmq';
```

### Colas PILAR ERP

```sql
-- ============================================================
-- Crear las 4 colas principales de PILAR ERP
-- ============================================================

-- Cola 1: Documentos electrónicos y procesamiento externo (máxima prioridad)
-- VT = 30 segundos (tiempo para procesar antes de re-encolar)
SELECT pgmq.create('pilar_docs_queue');

-- Cola 2: Notificaciones multi-canal (email/WhatsApp/Telegram)
-- VT = 60 segundos
SELECT pgmq.create('pilar_notifications_queue');

-- Cola 3: Integración con sistemas externos
-- VT = 120 segundos
SELECT pgmq.create('pilar_integrations_queue');

-- Cola 4: Generación de embeddings para búsqueda IA
-- VT = 300 segundos (procesamiento más pesado)
SELECT pgmq.create('pilar_ai_queue');

-- Ver colas existentes
SELECT queue_name, created_at FROM pgmq.list_queues();
```

### Operaciones básicas con pgmq

```sql
-- ENVIAR un mensaje a la cola de documentos electrónicos
SELECT pgmq.send(
  'pilar_docs_queue',
  jsonb_build_object(
    'documento_id',      'uuid-del-documento',
    'empresa_id',        'uuid-empresa',
    'tipo',              'FACTURA',
    'referencia_numero', 'DOC-2024-001',
    'intento',           1
  )
);
-- Retorna: msg_id (BIGINT) — ID único del mensaje

-- ENVIAR múltiples mensajes en batch
SELECT pgmq.send_batch(
  'pilar_notifications_queue',
  ARRAY[
    '{"tipo": "EMAIL", "destinatario": "cliente@email.com", "asunto": "Factura autorizada"}'::jsonb,
    '{"tipo": "WHATSAPP", "telefono": "+1999999999", "mensaje": "Su factura fue autorizada"}'::jsonb
  ]
);

-- LEER mensajes (sin eliminar, con visibilidad de 30 segundos)
SELECT * FROM pgmq.read(
  'pilar_docs_queue',
  vt     := 30,    -- visibilidad en segundos (VT)
  qty    := 5      -- máximo de mensajes a leer
);

-- ARCHIVAR mensaje después de procesarlo exitosamente
SELECT pgmq.archive('pilar_docs_queue', msg_id);

-- ELIMINAR mensaje (sin archivar)
SELECT pgmq.delete('pilar_docs_queue', msg_id);

-- VER mensajes en la cola (sin consumirlos)
SELECT * FROM pgmq.peek('pilar_docs_queue', qty := 10);

-- Ver mensajes archivados (historial)
SELECT * FROM pgmq.list_queue_metrics('pilar_docs_queue');
```

### Enviar desde triggers de PostgreSQL

Un patrón potente es encolar mensajes directamente desde triggers al insertar o actualizar registros:

```sql
-- Trigger: al confirmar un documento → encolar para procesamiento asíncrono
CREATE OR REPLACE FUNCTION public.trg_queue_document_for_processing()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Solo si el documento pasó a un estado que requiere procesamiento externo
  IF NEW.estado = 'PENDIENTE_ENVIO' AND OLD.estado != 'PENDIENTE_ENVIO' THEN
    PERFORM pgmq.send(
      'pilar_documents_queue',
      jsonb_build_object(
        'documento_id',  NEW.id,
        'empresa_id',    NEW.empresa_id,
        'tipo',          TG_TABLE_NAME,
        'prioridad',     1,
        'encolado_en',   now()
      )
    );
  END IF;
  RETURN NEW;
END;
$$;

-- Aplicar el trigger a cualquier tabla que requiera procesamiento asíncrono:
CREATE TRIGGER trg_<tabla>_queue_procesamiento
  AFTER UPDATE ON <tabla>
  FOR EACH ROW EXECUTE FUNCTION public.trg_queue_document_for_processing();
```

---

## Sección 3: Edge Functions — Procesadores de Cola

### Edge Function: procesador de cola de documentos electrónicos

El patrón genérico que sigue cualquier procesador de cola de documentos es:

### Edge Function: `process-notifications-queue`

Consume `pilar_notifications_queue` y despacha por el canal apropiado (email via Resend, WhatsApp via Cloud API, Telegram via Bot API).

```typescript
// supabase/functions/process-notifications-queue/index.ts
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

Deno.serve(async (_req: Request) => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  );

  const { data: mensajes } = await supabase.rpc("pgmq_read", {
    queue_name: "pilar_notifications_queue",
    vt: 60,
    qty: 25,
  });

  if (!mensajes?.length) {
    return new Response(JSON.stringify({ procesados: 0 }));
  }

  for (const { msg_id, message } of mensajes) {
    const { tipo, empresa_id, contacto_id } = message;

    try {
      // Obtener canales de notificación del contacto
      const { data: contacto } = await supabase
        .from("contactos")
        .select("email, telefono, notif_email, notif_whatsapp, notif_telegram, telegram_chat_id")
        .eq("id", contacto_id)
        .single();

      // Obtener plantilla según tipo de notificación y empresa
      const { data: plantilla } = await supabase
        .from("plantillas_notificacion")
        .select("*")
        .eq("empresa_id", empresa_id)
        .eq("tipo", tipo)
        .single();

      // Despachar por canal habilitado
      const promesas = [];

      if (contacto?.notif_email && contacto.email) {
        promesas.push(enviarEmail(contacto.email, plantilla, message));
      }
      if (contacto?.notif_whatsapp && contacto.telefono) {
        promesas.push(enviarWhatsApp(contacto.telefono, plantilla, message));
      }
      if (contacto?.notif_telegram && contacto.telegram_chat_id) {
        promesas.push(enviarTelegram(contacto.telegram_chat_id, plantilla, message));
      }

      await Promise.allSettled(promesas);

      // Archivar el mensaje procesado
      await supabase.rpc("pgmq_archive", {
        queue_name: "pilar_notifications_queue",
        msg_id: msg_id,
      });
    } catch (_err) {
      // Re-encolar automáticamente al expirar VT
    }
  }

  return new Response(JSON.stringify({ procesados: mensajes.length }));
});
```

### Conectar pg_cron → Edge Function via pg_net

Para que pg_cron dispare Edge Functions de Supabase, se usa la extensión `pg_net` (incluida en Supabase):

```sql
-- Habilitar pg_net (ya incluida en Supabase)
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Configurar parámetros de la aplicación (una vez por entorno)
-- Ejecutar en el SQL Editor de Supabase:
ALTER DATABASE postgres
  SET app.supabase_url = 'https://tu-proyecto.supabase.co';

ALTER DATABASE postgres
  SET app.service_role_key = 'tu-service-role-key-aqui';

-- Verificar la configuración
SELECT current_setting('app.supabase_url');

-- Ejemplo: job que dispara Edge Function cada 2 minutos
SELECT cron.schedule(
  'pilar_process_notifications',
  '*/2 * * * *',
  $$
  SELECT net.http_post(
    url     := current_setting('app.supabase_url') || '/functions/v1/process-notifications-queue',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || current_setting('app.service_role_key')
    ),
    body    := '{}'::jsonb
  ) AS request_id;
  $$
);
```

---

## Sección 4: Patrones y Mejores Prácticas

### Cuándo usar pg_cron

- Tareas periódicas sin estado que no necesitan reintentos por ítem: refrescar vistas materializadas, limpiar registros expirados en bulk, calcular agregaciones.
- Disparar Edge Functions en schedule fijo: sincronización con sistemas externos, cálculos periódicos.
- Alertas batch que se procesan en una sola pasada.

```sql
-- Patron: pg_cron para limpieza periódica de logs y tokens expirados
SELECT cron.schedule(
  'pilar_cleanup_expired_tokens',
  '0 3 * * *',   -- 3 AM UTC diario
  $$
  DELETE FROM sesiones_usuario
  WHERE expira_en < now() - interval '7 days';

  DELETE FROM tokens_otp
  WHERE expira_en < now();

  DELETE FROM cron.job_run_details
  WHERE start_time < now() - interval '30 days';
  $$
);
```

### Cuándo usar pgmq

- Procesamiento ítem por ítem donde el fallo de uno no debe afectar a los demás.
- Llamadas HTTP a terceros (organismos fiscales, Resend, WhatsApp Cloud API) con riesgo de timeout.
- Tareas disparadas por eventos de negocio (trigger en tabla → encolar tarea).
- Alta concurrencia: múltiples workers leyendo la misma cola sin colisiones.

```sql
-- Patrón: encolar desde trigger al insertar un registro con un origen externo
CREATE OR REPLACE FUNCTION public.trg_external_record_to_queue()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF NEW.origen = 'EXTERNO' THEN
    PERFORM pgmq.send(
      'pilar_integrations_queue',
      jsonb_build_object(
        'registro_id', NEW.id,
        'empresa_id',  NEW.empresa_id,
        'external_id', NEW.external_ref_id,
        'encolado_en', now()
      )
    );
  END IF;
  RETURN NEW;
END;
$$;
```

### Cuándo NO usar background jobs

- Operaciones síncronas que el usuario espera en la pantalla (validar sesión, calcular totales, consultar disponibilidad). Estas van en RPCs directas o funciones SQL.
- Actualizar un solo registro en respuesta a una acción del usuario: hacerlo directamente en la transacción.
- Cálculos de menos de 100 ms que no involucran llamadas a servicios externos.

### SECURITY DEFINER en funciones de jobs

Las funciones llamadas por pg_cron corren bajo el rol del scheduler, no del usuario. Para acceder a tablas con RLS deben ser `SECURITY DEFINER` y operar sobre todas las empresas:

```sql
CREATE OR REPLACE FUNCTION public.mi_funcion_cron()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER                     -- ejecuta como el dueño de la función
SET search_path = public             -- prevenir ataques de search_path injection
AS $$
BEGIN
  -- Aquí se puede acceder a TODAS las filas sin restricción de empresa_id
  -- porque SECURITY DEFINER bypasea RLS.
  -- IMPORTANTE: asegurarse de filtrar por empresa_id explícitamente
  -- para no cruzar datos entre tenants.
  DELETE FROM tokens_otp
  WHERE expira_en < now();
    -- Este job opera sobre TODOS los tenants, que es correcto en crons de mantenimiento.
    -- En jobs de módulos, filtrar por empresa_id cuando se procesen datos de negocio.
END;
$$;
```

### Monitoring y alertas de jobs

```sql
-- Vista resumen de salud de los jobs PILAR
CREATE OR REPLACE VIEW public.v_cron_job_health AS
SELECT
  j.jobname,
  j.schedule,
  j.active,
  COUNT(r.runid)                                         AS total_ejecuciones,
  COUNT(r.runid) FILTER (WHERE r.status = 'succeeded')  AS exitosas,
  COUNT(r.runid) FILTER (WHERE r.status = 'failed')     AS fallidas,
  MAX(r.start_time)                                      AS ultima_ejecucion,
  MAX(r.end_time) - MAX(r.start_time)                   AS ultima_duracion,
  ROUND(
    COUNT(r.runid) FILTER (WHERE r.status = 'failed')::numeric /
    NULLIF(COUNT(r.runid), 0) * 100, 2
  )                                                      AS pct_fallos
FROM cron.job j
LEFT JOIN cron.job_run_details r ON r.jobid = j.jobid
  AND r.start_time > now() - interval '7 days'
WHERE j.jobname LIKE 'pilar_%'
GROUP BY j.jobid, j.jobname, j.schedule, j.active
ORDER BY pct_fallos DESC NULLS LAST, j.jobname;

-- Ver la salud de todos los jobs
SELECT * FROM public.v_cron_job_health;

-- Ver métricas de las colas pgmq
SELECT
  queue_name,
  queue_length,
  newest_msg_age_sec,
  oldest_msg_age_sec,
  total_messages
FROM pgmq.metrics_all();
```

### Configuración de `app.settings` para URLs y keys

Los jobs que llaman Edge Functions necesitan acceso al URL de Supabase y la service role key. Almacenarlos como `app.settings` de PostgreSQL es el patrón recomendado:

```sql
-- Configurar una vez por entorno (desarrollo/producción)
-- Solo un superusuario puede hacer esto
ALTER DATABASE postgres SET app.supabase_url = 'https://abcdefgh.supabase.co';
ALTER DATABASE postgres SET app.service_role_key = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...';

-- En los jobs, acceder con:
-- current_setting('app.supabase_url')
-- current_setting('app.service_role_key')

-- ALTERNATIVA más segura: usar Vault de Supabase para las keys
SELECT vault.create_secret(
  'service_role_key',
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...',
  'Service role key para Edge Functions'
);

-- Leer desde Vault:
-- (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key')
```

### Tabla de auditoría de colas pgmq

Para trazabilidad en producción, archivar todos los mensajes procesados en lugar de eliminarlos:

```sql
-- Configurar retención de mensajes archivados en pgmq
-- Los mensajes archivados van a la tabla pgmq.a_{queue_name}
-- Por defecto se retienen indefinidamente. Limpiar periódicamente:

SELECT cron.schedule(
  'pilar_cleanup_pgmq_archive',
  '0 2 * * 0',   -- domingos a las 2 AM UTC
  $$
  -- Configurar retención por cola según criticidad del dato
  DELETE FROM pgmq.a_pilar_docs_queue
  WHERE archived_at < now() - interval '90 days';

  DELETE FROM pgmq.a_pilar_notifications_queue
  WHERE archived_at < now() - interval '30 days';

  DELETE FROM pgmq.a_pilar_integrations_queue
  WHERE archived_at < now() - interval '14 days';
  $$
);
```

---

## Referencia Rápida

| Necesitas | Solución |
|-----------|----------|
| Expirar registros automáticamente | pg_cron + función SQL |
| Refrescar vista materializada | pg_cron + `REFRESH MATERIALIZED VIEW CONCURRENTLY` |
| Enviar documento a procesamiento externo asíncrono | pgmq `pilar_docs_queue` + Edge Function procesadora |
| Notificar a usuario por email/WhatsApp | pgmq `pilar_notifications_queue` + Edge Function `process-notifications-queue` |
| Integrar con sistema externo | pgmq `pilar_integrations_queue` + Edge Function procesadora |
| Generar embedding IA para un documento | pgmq `pilar_ai_queue` + Edge Function `generate-embeddings` |
| Ver historial de ejecución de jobs | `SELECT * FROM cron.job_run_details` |
| Ver tamaño de colas pgmq | `SELECT * FROM pgmq.metrics_all()` |
| Disparar tarea desde evento de negocio | Trigger PostgreSQL + `pgmq.send()` |
| Disparar Edge Function periódicamente | pg_cron + `net.http_post()` |
