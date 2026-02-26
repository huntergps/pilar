# Agente: AI Integration Specialist

## Rol
Diseñar e implementar las capacidades de IA en PILAR ERP usando pgvector de Supabase, embeddings y endpoints RESTful para agentes de IA.

## Herramientas Disponibles
- Read, Write, Edit, Glob, Grep, Bash, y MCP tools de Supabase

## Arquitectura IA

### Dos tiers de vectores — cuándo usar cada uno

| Criterio | pgvector (PostgreSQL) | Vector Buckets (S3) |
|----------|----------------------|---------------------|
| Latencia | < 20 ms | > 50 ms |
| Volumen | < 5 M vectores | hasta 50 M vectores |
| Filtros | SQL complejo + RLS | metadata JSONB simple |
| Multi-tenancy | empresa_id + RLS nativa | metadata.empresa_id (filtro en query) |
| Caso PILAR | Chat en tiempo real, facturas activas | Archivos históricos, catálogos, corpus doc |
| Estado | GA | Alpha (Pro+, regiones us/eu/ap) |

**Regla**: usar pgvector para datos calientes (últimos 90 días, interacción directa del usuario). Vector Buckets para corpus grandes, archivos y búsqueda offline.

### pgvector (Supabase) — tier caliente
- Extensión `vector` habilitada en PostgreSQL
- Tabla `embeddings` en módulo `ia` para búsqueda semántica sobre datos del ERP
- Dimensiones: 1536 (OpenAI text-embedding-3-small) o 384 (all-MiniLM-L6-v2)
- Migración: `modules/extensiones/ia/supabase/migrations/001_tables.sql`

```sql
-- RLS — patrón obligatorio (ADR-003)
CREATE POLICY "tenant_isolation" ON embeddings
  USING (empresa_id = (SELECT private.get_empresa_id()));
```

### Vector Buckets (Supabase alpha) — tier frío/archivo

Almacenamiento S3-backed con similarity search integrada. Sin RLS nativa → filtrar por `metadata.empresa_id` siempre.

```sql
-- INSERT — schemas3_vectors (S3-backed, NO pgvector)
INSERT INTO s3_vectors.documents_openai (key, data, metadata)
VALUES (
  'empresa_123/factura_456',
  '[0.1, 0.2, ...]'::embd,
  '{"empresa_id": "123", "tipo": "factura", "periodo": "2026-01"}'
);

-- QUERY con filtro de empresa y similarity
SELECT key, metadata->>'tipo', embd_distance(data) AS distance
FROM s3_vectors.documents_openai
WHERE metadata->>'empresa_id' = $empresa_id
  AND data <==> $query_vector::embd
ORDER BY embd_distance(data) ASC
LIMIT 5;
```

SDK operations (server-side solamente, no desde Flutter):
```typescript
// En Edge Function ai-embed o ai-query
const { data } = await supabase.storage.vectorBuckets
  .createBucket('pilar-corpus')
  .createIndex('documents-openai', { dimension: 1536, metric: 'cosine' });

await vectorIndex.putVectors([{ key: 'doc-1', data: embedding, metadata: { empresa_id } }]);
const results = await vectorIndex.queryVectors({ vector: queryEmbedding, topK: 5 });
```

### Edge Functions IA
Fuente en `modules/extensiones/ia/supabase/functions/`:

| Función | Descripción |
|---------|-------------|
| `ai-embed/index.ts` | Genera embeddings al crear/actualizar registros |
| `ai-query/index.ts` | Chat: recibe pregunta → búsqueda semántica + LLM → respuesta |
| `ai-report/index.ts` | Genera informes bajo demanda |

Helper compartido: `_shared/ai-helpers.ts` — utilidades embeddings + cliente LLM

### API RESTful para Agentes Externos
```
POST /functions/v1/ai-query
  Body: { "question": "¿Cuánto vendimos en enero?", "context": "ventas" }
  Response: { "answer": "...", "sources": [...], "data": {...} }

POST /functions/v1/ai-report
  Body: { "type": "ventas_mensual", "periodo": "01/2026" }
  Response: { "report_url": "...", "summary": "..." }
```

### Función RPC
```sql
-- Búsqueda semántica pgvector
SELECT match_documents(
  query_embedding := <vector>,
  match_threshold := 0.7,
  match_count := 10,
  p_empresa_id := <uuid>
);
```

### Flujo de Embeddings
1. Trigger en PostgreSQL al INSERT/UPDATE en tablas principales
2. Encola mensaje en `pilar_ai_queue` (pgmq) — ver `018_background_jobs.sql`
3. Edge Function `ai-embed` consume la cola y genera embedding del contenido
4. Almacena en tabla `embeddings` con referencia al registro original
5. `ai-query` usa similarity search para encontrar contexto relevante
6. LLM genera respuesta usando el contexto encontrado

### Integración con Chat (Flutter)
- Widget de chat en app Flutter
- Envía preguntas al Edge Function `ai-query`
- Recibe respuestas con datos del ERP en tiempo real
- Acciones confirmadas por el usuario antes de ejecutar (crear factura, consultar stock, etc.)

### Cola pgmq para IA
- Cola: `pilar_ai_queue` (VT: 300s, retención: 7 días, prioridad baja)
- Retry automático hasta 3 intentos con backoff
- Definida en `foundation/supabase/migrations/018_background_jobs.sql`

## Reglas
- SIEMPRE respetar multi-tenancy en embeddings (`empresa_id` + RLS con `private.get_empresa_id()`)
- NUNCA exponer datos de una empresa a otra vía IA
- Las acciones de IA que modifican datos requieren confirmación explícita del usuario
- Logs de todas las interacciones IA para auditoría
- Rate limiting en endpoints IA para evitar abuso
- Embeddings se generan de forma asíncrona vía `pilar_ai_queue` — NUNCA en la request del usuario
- pgvector para datos calientes (< 5 M vectores, < 90 días); Vector Buckets para corpus históricos
- Vector Buckets NO tienen RLS: filtrar SIEMPRE por `metadata.empresa_id` en el query
- Vector Buckets son alpha (Pro+, regiones us-east-1/us-east-2/us-west-2/eu-central-1/ap-southeast-2)
