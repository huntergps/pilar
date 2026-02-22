# ADR-007: Procesamiento Asíncrono con pg_cron y pgmq (Supabase-native)

**Estado**: Aceptado
**Fecha**: 2026-02
**Autores**: Arquitecto principal
**Tags**: backend, infraestructura, supabase, cron, colas, background-jobs

---

## Contexto

PILAR requiere dos categorías de procesamiento que no son síncronas con la petición del usuario:

**1. Tareas programadas** (cron jobs):
- Expirar registros vencidos (reservas, tokens, plazos)
- Refrescar vistas materializadas (dashboards, reportes pre-calculados)
- Enviar recordatorios programados (eventos proximos, vencimientos)
- Calcular agregados periodicos (cuotas, totales, planillas)
- Alertas de SLA y monitoreo de estados criticos
- Sincronizacion con sistemas externos (ecommerce, bancos)
- Procesamiento batch de IA (forecast, embeddings)

**2. Colas de mensajes con retry** (message queues):
- Pipeline de documentos electronicos: generar → firmar → enviar a autoridad → reintentar hasta 24h
- Notificaciones multicanal: email + WhatsApp + Telegram
- Procesamiento de pedidos entrantes desde canales externos
- Indexacion de documentos para embeddings vectoriales (IA)

Los requerimientos en tensión son:
- El pipeline de documentos electronicos **no puede bloquear** la respuesta al usuario (la autorización de la autoridad fiscal puede tardar segundos o fallar y requerir reintentos en horas)
- Las notificaciones deben enviarse post-autorizacion del documento, no en el mismo request
- Los jobs deben ejecutarse en horario Ecuador (UTC-5), no en UTC
- El sistema es multi-tenant: los jobs operan sobre **todos** los tenants simultáneamente
- El presupuesto de infraestructura es mínimo (Supabase Free/Pro, sin servicios adicionales de pago)

---

## Decision

Se adopta **pg_cron** para tareas programadas y **pgmq** para colas de mensajes con retry. Ambas extensiones se habilitan directamente en Supabase (PostgreSQL), eliminando la necesidad de servicios externos.

### pg_cron — Jobs Programados

`pg_cron` es una extensión PostgreSQL que permite programar jobs SQL/funciones directamente en la base de datos, usando sintaxis cron estándar.

**Habilitación en Supabase:**
```sql
-- Habilitado via Supabase Dashboard → Extensions → pg_cron
-- O via SQL:
CREATE EXTENSION IF NOT EXISTS pg_cron;
```

**Patrón para jobs multi-tenant** (SECURITY DEFINER para bypassar RLS):

```sql
CREATE OR REPLACE FUNCTION expire_overdue_records()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER  -- bypassar RLS: opera sobre todos los tenants
SET search_path = public
AS $$
BEGIN
  UPDATE <tabla>
  SET estado = 'VENCIDO',
      fecha_vencimiento_real = NOW()
  WHERE estado = 'ACTIVO'
    AND fecha_vencimiento < NOW();
END;
$$;
```

**Patrón para jobs que llaman Edge Functions** (via `pg_net`):

```sql
-- Jobs que requieren lógica compleja (firma digital, HTTP externos)
-- delegan a Edge Functions via pg_net.http_post()
SELECT cron.schedule(
  'pilar_process_<queue>',
  '*/2 * * * *',
  $$
  SELECT pg_net.http_post(
    url     := current_setting('app.supabase_url') || '/functions/v1/process-<queue>',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || current_setting('app.service_role_key'),
      'Content-Type',  'application/json'
    ),
    body    := '{}'::jsonb
  );
  $$
);
```

### pgmq — Colas de Mensajes con Retry

`pgmq` (Postgres Message Queue) es una extensión que implementa una cola de mensajes durable dentro de PostgreSQL, con soporte nativo para visibilidad de mensajes, reintento automático por timeout, y archivado.

**Las colas de PILAR** (una por tipo de procesamiento asincrono):

| Cola | Producida por | Consumida por | Prioridad | Retención |
|------|--------------|---------------|-----------|-----------|
| `pilar_documents_queue` | Trigger en tabla de documentos pendientes | Edge Function de procesamiento de documentos | Alta | 90 días |
| `pilar_notifications_queue` | RPCs post-procesamiento, cron de recordatorios | Edge Function de notificaciones | Media | 30 días |
| `pilar_integrations_queue` | Pull desde sistemas externos (ecommerce, bancos) | Edge Function de integraciones | Media | 14 días |
| `pilar_ai_queue` | Trigger en registros nuevos que requieren embeddings | Edge Function de IA | Baja | 7 días |

**Creación de colas:**

```sql
CREATE EXTENSION IF NOT EXISTS pgmq;

SELECT pgmq.create('pilar_documents_queue');
SELECT pgmq.create('pilar_notifications_queue');
SELECT pgmq.create('pilar_integrations_queue');
SELECT pgmq.create('pilar_ai_queue');
```

**Encolado automático via trigger** (patrón generico):

```sql
-- Al cambiar estado en una tabla de documentos pendientes → encolar en pgmq
CREATE OR REPLACE FUNCTION trg_queue_document()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER AS $$
BEGIN
  IF NEW.estado = 'PENDIENTE' AND (OLD.estado IS DISTINCT FROM 'PENDIENTE') THEN
    PERFORM pgmq.send(
      'pilar_documents_queue',
      jsonb_build_object(
        'documento_id', NEW.id,
        'empresa_id',   NEW.empresa_id,
        'tipo',         NEW.tipo,
        'prioridad',    NEW.prioridad
      )
    );
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_queue_document
AFTER INSERT OR UPDATE ON <tabla_documentos>
FOR EACH ROW EXECUTE FUNCTION trg_queue_document();
```

**Procesamiento en Edge Function** (patrón de consumo con visibility timeout):

```typescript
// Edge Function: process-documents-queue/index.ts
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const VISIBILITY_TIMEOUT_SEC = 30; // si no se ack en 30s → vuelve a la cola
const BATCH_SIZE = 5;

Deno.serve(async () => {
  const messages = await supabase.rpc('pgmq_read', {
    queue_name: 'pilar_documents_queue',
    vt: VISIBILITY_TIMEOUT_SEC,
    qty: BATCH_SIZE,
  });

  for (const msg of messages.data ?? []) {
    try {
      await processDocument(msg.message);
      // Ack: eliminar de la cola
      await supabase.rpc('pgmq_archive', {
        queue_name: 'pilar_documents_queue',
        msg_id: msg.msg_id,
      });
    } catch (err) {
      // No hacer ack → visibility timeout expira → vuelve a la cola (retry automático)
      console.error('Document processing failed:', err);
    }
  }

  return new Response(JSON.stringify({ processed: messages.data?.length ?? 0 }));
});
```

### Flujo Completo: Documento → Procesamiento Asincrono

```
Usuario confirma documento
    │
    ▼
INSERT <tabla_documentos> (estado=PENDIENTE)
    │
    ▼ trigger
pgmq.send('pilar_documents_queue', {documento_id, empresa_id, tipo})
    │
    ▼ pg_cron cada N min
pg_net.http_post → Edge Function process-documents-queue
    │
    ├─ Genera y valida el documento
    ├─ Procesa (logica especifica del modulo de extension del pais)
    ├─ Envia a sistema externo si aplica
    ├─ UPDATE <tabla_documentos> (estado=PROCESADO)
    ├─ Genera PDF/archivo → Supabase Storage
    ├─ pgmq.send('pilar_notifications_queue', {doc_id, canales=[email,whatsapp]})
    └─ pgmq.archive('pilar_documents_queue', msg_id)  -- ack
        │
        ▼ pg_cron cada N min
    Edge Function process-notifications-queue
        ├─ Email (con documento adjunto)
        └─ WhatsApp / Telegram
```

---

## Alternativas Rechazadas

### 1. n8n / Zapier / Make (automatización externa)

- Servicio adicional a mantener, con su propio uptime, versiones y costos
- Latencia de red extra entre n8n y Supabase en cada operación
- n8n requiere servidor dedicado (auto-hosted) o plan cloud de pago
- La lógica de negocio de PILAR tiene acceso directo a las tablas — ejecutarla en n8n requeriría exponer RPCs adicionales
- **Rechazado por**: complejidad operacional innecesaria; pg_cron ejecuta en el mismo proceso PostgreSQL

### 2. AWS EventBridge + Lambda / Google Cloud Scheduler + Cloud Functions

- Acoplamiento a un proveedor cloud específico (lock-in)
- Costo incremental mensual por invocaciones
- Autenticación y networking entre AWS/GCP y Supabase añaden latencia y configuración
- Contradice la decisión ADR-005 (Supabase como único backend, sin Firebase/AWS)
- **Rechazado por**: lock-in de vendor, costo adicional, complejidad de infraestructura

### 3. Redis + BullMQ / Celery + Redis (cola de tareas clásica)

- Redis es un servicio adicional a aprovisionar y mantener (RAM, persistencia, backups)
- BullMQ es excelente para Node.js pero PILAR usa Deno en Edge Functions — la integración no es directa
- Los mensajes en Redis no tienen la durabilidad transaccional de PostgreSQL (pgmq sí, al estar en la misma BD)
- Si Redis cae, se pierden mensajes en tránsito; pgmq al estar en PostgreSQL hereda durabilidad ACID
- **Rechazado por**: infraestructura adicional, pérdida de durabilidad transaccional, stack fuera del ecosistema Supabase

### 4. Supabase Edge Functions con `Deno.cron()` (Deno built-in cron)

- `Deno.cron()` requiere que la Edge Function esté en ejecución continua — incompatible con el modelo serverless de Supabase Edge Functions (invocación por request)
- No hay persistencia de estado entre invocaciones
- **Rechazado por**: modelo de ejecución incompatible con Supabase Edge Functions serverless

### 5. Polling desde Flutter (cliente inicia los reintentos de procesamiento)

- El cliente puede estar offline, con batería baja, o haber cerrado la app
- Un documento en cola de procesamiento no puede depender del cliente para ser procesado
- Viola el principio de que los documentos electronicos se procesan server-side
- **Rechazado por**: fiabilidad inaceptable para cumplimiento regulatorio

---

## Consecuencias

### Positivas

- **Zero infraestructura adicional**: pg_cron y pgmq son extensiones nativas de Supabase — no hay que aprovisionar ni mantener servicios adicionales
- **Durabilidad transaccional**: pgmq escribe en PostgreSQL; si la BD está disponible, los mensajes no se pierden. Un mensaje que falla vuelve automáticamente a la cola cuando expira el visibility timeout
- **Retry nativo**: pgmq reencola automáticamente si la Edge Function no hace `pgmq_archive` (ack) antes del timeout — sin código de retry manual
- **Observabilidad nativa**: `cron.job_run_details` registra cada ejecución de pg_cron (inicio, fin, estado, error). `pgmq.metrics()` expone profundidad de cola, mensajes muertos, etc.
- **Transaccionalidad**: el trigger que encola en pgmq corre en la misma transacción que el INSERT en la tabla de documentos — imposible enqueue sin el documento o viceversa
- **Multi-tenant transparente**: las funciones SECURITY DEFINER iteran sobre todos los tenants sin exponer datos entre empresas

### Negativas / Restricciones

- **pg_cron resolución mínima: 1 minuto** — no es posible ejecutar más frecuentemente. Para alertas que requieran sub-minuto (improbable en PILAR) se necesitaría otra solución
- **pg_cron no tiene reintentos automáticos**: si una función cron falla, no se reintenta hasta la siguiente ejecución programada. Para tareas críticas (ej: depreciaciones mensuales) se debe monitorear `cron.job_run_details`
- **Funciones SECURITY DEFINER** requieren cuidado: deben filtrar por `empresa_id` explícitamente para no procesar datos de empresas inactivas o en mora
- **pgmq dead letter queue**: mensajes que fallan repetidamente deben ser monitoreados. Se debe crear un job de limpieza que archive/elimine mensajes bloqueados con más de N intentos
- **Edge Function invocada por pg_net**: si la Edge Function está en cold start, el timeout de `pg_net.http_post` puede vencer antes de que procese. Se mitiga con visibility timeout de pgmq (el mensaje vuelve a la cola)
- **No hay garantía de orden estricto** en pgmq (es FIFO best-effort). Para el pipeline de documentos esto es aceptable (cada documento es independiente)

---

## Referencias

- [pg_cron en Supabase](https://supabase.com/docs/guides/database/extensions/pg_cron)
- [pgmq en Supabase](https://supabase.com/docs/guides/database/extensions/pgmq)
- [pg_net para HTTP desde PostgreSQL](https://supabase.com/docs/guides/database/extensions/pg_net)
- [pg_cron en Supabase](https://supabase.com/docs/guides/database/extensions/pg_cron)
- [pgmq en Supabase](https://supabase.com/docs/guides/database/extensions/pgmq)
- [pg_net para HTTP desde PostgreSQL](https://supabase.com/docs/guides/database/extensions/pg_net)
- ADR-005 — elección de Supabase como único backend (sin AWS/GCP adicionales)
- ADR-002 — Module Service Bus (las funciones de cron llaman a `module_bus.*` cuando tocan módulos Core)
