# IA Asistente - Chat Inteligente


## Descripcion Funcional

PILAR ya tiene planificado un chat IA (seccion 11.8 Agentes Autonomos). Esta seccion define los **skills concretos**, la tabla de skills, el flujo de interpretacion NLP-a-SQL/accion y la arquitectura del asistente conversacional.

Capacidades del asistente:

1. **Consultas en lenguaje natural:** El usuario pregunta en espanol y el asistente genera SQL seguro contra vistas/funciones predefinidas, ejecuta y formatea la respuesta.

2. **Acciones via chat:** El asistente puede crear borradores de documentos (cotizaciones, OC, citas), cambiar estados (aprobar OC, cerrar oportunidad) y agendar recordatorios. Siempre requiere confirmacion del usuario antes de ejecutar.

3. **Resumenes ejecutivos:** "Dame un resumen del dia/semana/mes" genera un reporte con KPIs principales de ventas, cobros, stock bajo, citas del dia y alertas pendientes.

## Modelo de Datos - Chat IA

```sql
-- ============================================================
-- TABLA: Skills del asistente IA (capacidades registradas)
-- ============================================================

CREATE TABLE ia_skills (
  id              VARCHAR(50) PRIMARY KEY,
    -- 'query_ventas', 'query_stock', 'create_cotizacion', 'resumen_dia', etc.
  nombre          VARCHAR(100) NOT NULL,
  descripcion     TEXT NOT NULL,
    -- Descripcion usada como contexto para el LLM
  categoria       VARCHAR(20) NOT NULL,
    -- CONSULTA, ACCION, RESUMEN, REPORTE
  modulo          VARCHAR(30) NOT NULL,
    -- VENTAS, INVENTARIO, CONTABILIDAD, CRM, RRHH, GENERAL
  requiere_confirmacion BOOLEAN DEFAULT false,
    -- true para acciones que modifican datos
  sql_template    TEXT,
    -- Template SQL para consultas (con placeholders $1, $2, etc.)
  rpc_function    VARCHAR(100),
    -- Nombre de la funcion RPC para acciones
  parametros      JSONB NOT NULL DEFAULT '[]',
    -- [{nombre, tipo, descripcion, requerido, default}]
  ejemplos_input  JSONB NOT NULL DEFAULT '[]',
    -- ["Cuanto vendimos ayer?", "Ventas del mes", ...]
  activo          BOOLEAN DEFAULT true,
  permisos        JSONB DEFAULT '["authenticated"]'
    -- Roles requeridos para usar este skill
);

-- Seed de skills fundamentales
INSERT INTO ia_skills (id, nombre, descripcion, categoria, modulo,
  requiere_confirmacion, sql_template, parametros, ejemplos_input) VALUES

-- CONSULTAS DE VENTAS
('query_ventas_periodo', 'Consultar ventas por periodo',
 'Consulta el total de ventas (facturas autorizadas/pagadas) para un periodo dado. Retorna total_facturas, revenue_total, ticket_promedio.',
 'CONSULTA', 'VENTAS', false,
 'SELECT COUNT(*) AS total_facturas, COALESCE(SUM(total), 0) AS revenue_total,
    COALESCE(AVG(total), 0) AS ticket_promedio
  FROM facturas
  WHERE empresa_id = $1 AND tipo_documento = ''01'' AND es_compra = false
    AND estado IN (''AUTORIZADA'', ''PAGADA'')
    AND fecha_emision >= $2 AND fecha_emision < $3',
 '[{"nombre":"fecha_inicio","tipo":"DATE","descripcion":"Inicio del periodo","requerido":true},
   {"nombre":"fecha_fin","tipo":"DATE","descripcion":"Fin del periodo","requerido":true}]',
 '["Cuanto vendimos ayer?", "Ventas de hoy", "Ventas de esta semana", "Cuanto facturamos en enero?", "Revenue del mes pasado"]'),

('query_producto_mas_vendido', 'Producto mas vendido',
 'Consulta el producto con mayor cantidad vendida o mayor revenue en un periodo.',
 'CONSULTA', 'VENTAS', false,
 'SELECT p.nombre, SUM(fl.cantidad) AS cantidad_vendida, SUM(fl.subtotal) AS revenue
  FROM factura_lineas fl
  JOIN facturas f ON f.id = fl.factura_id
  JOIN productos p ON p.id = fl.producto_id
  WHERE f.empresa_id = $1 AND f.tipo_documento = ''01'' AND f.es_compra = false
    AND f.estado IN (''AUTORIZADA'', ''PAGADA'')
    AND f.fecha_emision >= $2 AND f.fecha_emision < $3
  GROUP BY p.nombre ORDER BY SUM(fl.subtotal) DESC LIMIT $4',
 '[{"nombre":"fecha_inicio","tipo":"DATE","requerido":true},
   {"nombre":"fecha_fin","tipo":"DATE","requerido":true},
   {"nombre":"limit","tipo":"INTEGER","requerido":false,"default":5}]',
 '["Cual es el producto mas vendido este mes?", "Top 10 productos de hoy", "Que se vendio mas ayer?"]'),

-- CONSULTAS DE STOCK
('query_stock_producto', 'Consultar stock de un producto',
 'Consulta el stock disponible de un producto especifico, buscando por nombre parcial.',
 'CONSULTA', 'INVENTARIO', false,
 'SELECT p.nombre, p.codigo, COALESCE(SUM(sm.cantidad), 0) AS stock_actual,
    p.stock_minimo, p.stock_maximo,
    CASE WHEN COALESCE(SUM(sm.cantidad), 0) <= p.stock_minimo THEN ''BAJO''
         WHEN COALESCE(SUM(sm.cantidad), 0) >= p.stock_maximo THEN ''EXCESO''
         ELSE ''NORMAL'' END AS estado_stock
  FROM productos p
  LEFT JOIN stock_movimientos sm ON sm.producto_id = p.id AND sm.empresa_id = p.empresa_id
  WHERE p.empresa_id = $1 AND p.nombre ILIKE ''%'' || $2 || ''%''
  GROUP BY p.id, p.nombre, p.codigo, p.stock_minimo, p.stock_maximo
  LIMIT 5',
 '[{"nombre":"busqueda","tipo":"TEXT","descripcion":"Nombre parcial del producto","requerido":true}]',
 '["Tenemos stock de cemento?", "Cuantas unidades hay de tornillos?", "Stock de arroz"]'),

-- CONSULTAS CXC
('query_deuda_cliente', 'Consultar deuda de un cliente',
 'Consulta el saldo pendiente de un cliente especifico en CxC.',
 'CONSULTA', 'VENTAS', false,
 'SELECT c.nombre, COUNT(cxc.id) AS facturas_pendientes,
    SUM(cxc.saldo_pendiente) AS deuda_total,
    MIN(cxc.fecha_vencimiento) AS factura_mas_antigua,
    SUM(CASE WHEN cxc.fecha_vencimiento < CURRENT_DATE THEN cxc.saldo_pendiente ELSE 0 END) AS deuda_vencida
  FROM cuentas_por_cobrar cxc
  JOIN contactos c ON c.id = cxc.contacto_id
  WHERE cxc.empresa_id = $1 AND cxc.estado = ''PENDIENTE''
    AND c.nombre ILIKE ''%'' || $2 || ''%''
  GROUP BY c.id, c.nombre',
 '[{"nombre":"cliente","tipo":"TEXT","descripcion":"Nombre parcial del cliente","requerido":true}]',
 '["Cuanto nos debe Distribuidora ABC?", "Deuda de Juan Perez", "Saldo pendiente de cliente Lopez"]'),

-- ACCIONES
('create_cotizacion', 'Crear cotizacion',
 'Crea un borrador de cotizacion para un cliente con uno o mas productos.',
 'ACCION', 'VENTAS', true,
 NULL, -- Usa RPC, no SQL directo
 '[{"nombre":"cliente","tipo":"TEXT","descripcion":"Nombre del cliente","requerido":true},
   {"nombre":"items","tipo":"JSONB","descripcion":"[{producto, cantidad, precio}]","requerido":true}]',
 '["Crea una cotizacion para cliente X con 10 unidades de producto Y", "Genera proforma para Lopez"]'),

('aprobar_oc', 'Aprobar orden de compra',
 'Cambia el estado de una OC de BORRADOR a CONFIRMADA.',
 'ACCION', 'INVENTARIO', true,
 NULL,
 '[{"nombre":"oc_numero","tipo":"TEXT","descripcion":"Numero de la OC","requerido":true}]',
 '["Aprueba la OC 123", "Confirma la orden de compra numero 456"]'),

-- RESUMENES
('resumen_dia', 'Resumen del dia',
 'Genera un resumen ejecutivo del dia con: ventas totales, facturas emitidas, cobros, pagos, productos bajo stock, citas del dia, alertas pendientes.',
 'RESUMEN', 'GENERAL', false,
 NULL, -- Ejecuta multiples queries y compone respuesta
 '[]',
 '["Dame un resumen del dia", "Como va el dia?", "Resumen de hoy"]'),

('resumen_mes', 'Resumen del mes',
 'Resumen comparativo del mes actual vs anterior: ventas, gastos, margen, CxC/CxP.',
 'RESUMEN', 'GENERAL', false,
 NULL,
 '[]',
 '["Como va el mes?", "Resumen mensual", "Comparativo del mes"]);

-- ============================================================
-- TABLA: Conversaciones IA (extiende seccion 11.8)
-- ============================================================

-- Las tablas ai_conversations y ai_messages ya existen (seccion 11.8).
-- Se agregan campos adicionales:

ALTER TABLE ai_conversations
  ADD COLUMN IF NOT EXISTS titulo VARCHAR(200),
  ADD COLUMN IF NOT EXISTS contexto_modulo VARCHAR(30),
    -- Modulo desde donde se abrio el chat (VENTAS, INVENTARIO, etc.)
  ADD COLUMN IF NOT EXISTS metadata JSONB DEFAULT '{}';

ALTER TABLE ai_messages
  ADD COLUMN IF NOT EXISTS skill_id VARCHAR(50) REFERENCES ia_skills(id),
  ADD COLUMN IF NOT EXISTS sql_ejecutado TEXT,
  ADD COLUMN IF NOT EXISTS resultado_data JSONB,
  ADD COLUMN IF NOT EXISTS tokens_input INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS tokens_output INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS latencia_ms INTEGER;

-- ============================================================
-- TABLA: Mapeo de intents para NLP (ayuda al LLM a clasificar)
-- ============================================================

CREATE TABLE ia_intent_examples (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  skill_id        VARCHAR(50) NOT NULL REFERENCES ia_skills(id),
  ejemplo_input   TEXT NOT NULL,
  parametros_extraidos JSONB,
    -- Ejemplo de extraccion: {"fecha_inicio": "2026-02-14", "fecha_fin": "2026-02-15"}
  created_at      TIMESTAMPTZ DEFAULT now()
);

-- Seed de ejemplos adicionales para mejorar clasificacion
INSERT INTO ia_intent_examples (skill_id, ejemplo_input, parametros_extraidos) VALUES
  ('query_ventas_periodo', 'cuanto se vendio ayer', '{"fecha_inicio":"YESTERDAY","fecha_fin":"TODAY"}'),
  ('query_ventas_periodo', 'ventas de la semana pasada', '{"fecha_inicio":"LAST_WEEK_START","fecha_fin":"LAST_WEEK_END"}'),
  ('query_ventas_periodo', 'facturacion de febrero', '{"fecha_inicio":"2026-02-01","fecha_fin":"2026-03-01"}'),
  ('query_stock_producto', 'hay cemento holcim', '{"busqueda":"cemento holcim"}'),
  ('query_stock_producto', 'cuantos cables HDMI quedan', '{"busqueda":"cable HDMI"}'),
  ('query_deuda_cliente', 'cuanto debe distribuidora oriente', '{"cliente":"distribuidora oriente"}'),
  ('resumen_dia', 'que tal va el negocio hoy', '{}'),
  ('resumen_dia', 'como estamos', '{}');
```

## Edge Function: ai-chat

```typescript
// Edge Function: ai-chat
// Endpoint: POST /functions/v1/ai-chat
// Chat conversacional con NLP → SQL/Accion → Respuesta

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface ChatRequest {
  conversation_id?: string;
  message: string;
  empresa_id: string;
  contexto_modulo?: string;
  confirmar_accion?: boolean;
  accion_pendiente_id?: string;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization")!;
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      { global: { headers: { Authorization: authHeader } } }
    );

    const body: ChatRequest = await req.json();
    const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
    if (!apiKey) throw new Error("ANTHROPIC_API_KEY not configured");

    // 1. Obtener/crear conversacion
    let conversationId = body.conversation_id;
    if (!conversationId) {
      const { data: conv } = await supabase
        .from("ai_conversations")
        .insert({
          empresa_id: body.empresa_id,
          contexto_modulo: body.contexto_modulo,
        })
        .select("id")
        .single();
      conversationId = conv!.id;
    }

    // 2. Guardar mensaje del usuario
    await supabase.from("ai_messages").insert({
      conversation_id: conversationId,
      role: "USER",
      content: body.message,
    });

    // 3. Obtener skills disponibles
    const { data: skills } = await supabase
      .from("ia_skills")
      .select("id, nombre, descripcion, categoria, modulo, parametros, ejemplos_input, requiere_confirmacion")
      .eq("activo", true);

    // 4. Obtener historial reciente de la conversacion
    const { data: history } = await supabase
      .from("ai_messages")
      .select("role, content")
      .eq("conversation_id", conversationId)
      .order("created_at", { ascending: true })
      .limit(20);

    // 5. Construir prompt para Claude
    const systemPrompt = `Eres PILAR AI, el asistente inteligente del ERP PILAR para Ecuador.
Tu trabajo es interpretar preguntas en espanol sobre el negocio y ejecutar el skill correcto.

SKILLS DISPONIBLES:
${JSON.stringify(skills, null, 2)}

REGLAS:
1. Siempre responde en espanol.
2. Identifica el skill_id que mejor corresponde a la pregunta del usuario.
3. Extrae los parametros necesarios del mensaje.
4. Para fechas relativas: "ayer"=fecha de ayer, "hoy"=fecha de hoy, "este mes"=primer dia del mes actual hasta hoy, "semana pasada"=lunes a domingo anteriores.
5. Si necesitas mas informacion, pregunta al usuario.
6. NUNCA inventes datos. Si no hay un skill para la pregunta, dilo honestamente.
7. Para acciones (categoria ACCION), siempre pide confirmacion antes de ejecutar.
8. Para resumenes, ejecuta multiples skills y compila la respuesta.
9. Formatea montos con $ y 2 decimales. Usa formato ecuatoriano (dd/mm/yyyy).

RESPONDE en formato JSON:
{
  "tipo": "CONSULTA" | "ACCION_CONFIRMAR" | "ACCION_EJECUTAR" | "TEXTO" | "RESUMEN",
  "skill_id": "id del skill o null",
  "parametros": { ... parametros extraidos ... },
  "respuesta_texto": "Texto para mostrar al usuario",
  "sql_params": ["param1", "param2"] // parametros posicionales para el SQL template
}`;

    const messages = [
      ...(history || []).map((m: any) => ({
        role: m.role === "USER" ? "user" : "assistant",
        content: m.content,
      })),
    ];

    // 6. Llamar a Claude
    const startTime = Date.now();
    const llmResponse = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: "claude-sonnet-4-20250514",
        max_tokens: 1000,
        system: systemPrompt,
        messages: messages,
      }),
    });

    const llmData = await llmResponse.json();
    const latencyMs = Date.now() - startTime;
    const aiText = llmData.content?.[0]?.text ?? "";

    // 7. Parsear respuesta del LLM
    let parsedResponse: any;
    try {
      // Extraer JSON de la respuesta
      const jsonMatch = aiText.match(/\{[\s\S]*\}/);
      parsedResponse = jsonMatch ? JSON.parse(jsonMatch[0]) : null;
    } catch {
      parsedResponse = { tipo: "TEXTO", respuesta_texto: aiText };
    }

    let finalResponse: any = {
      conversation_id: conversationId,
      respuesta: parsedResponse?.respuesta_texto ?? aiText,
    };

    // 8. Si es CONSULTA, ejecutar SQL
    if (parsedResponse?.tipo === "CONSULTA" && parsedResponse?.skill_id) {
      const skill = skills?.find((s: any) => s.id === parsedResponse.skill_id);
      if (skill?.sql_template) {
        const sqlParams = [body.empresa_id, ...(parsedResponse.sql_params || [])];
        const { data: queryResult, error: queryError } = await supabase
          .rpc("execute_ai_query", {
            p_sql: skill.sql_template,
            p_params: sqlParams,
            p_empresa_id: body.empresa_id,
          });

        if (!queryError && queryResult) {
          // Pedir a Claude que formatee los resultados
          const formatResponse = await fetch("https://api.anthropic.com/v1/messages", {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              "x-api-key": apiKey,
              "anthropic-version": "2023-06-01",
            },
            body: JSON.stringify({
              model: "claude-sonnet-4-20250514",
              max_tokens: 500,
              messages: [{
                role: "user",
                content: `El usuario pregunto: "${body.message}". Los datos obtenidos son: ${JSON.stringify(queryResult)}. Formatea una respuesta clara en espanol con montos en $ y fechas en dd/mm/yyyy. Se conciso.`,
              }],
            }),
          });
          const formatData = await formatResponse.json();
          finalResponse.respuesta = formatData.content?.[0]?.text ?? JSON.stringify(queryResult);
          finalResponse.datos = queryResult;
        }
      }
    }

    // 9. Si es ACCION_CONFIRMAR, pedir confirmacion
    if (parsedResponse?.tipo === "ACCION_CONFIRMAR") {
      finalResponse.requiere_confirmacion = true;
      finalResponse.accion = parsedResponse.skill_id;
      finalResponse.parametros = parsedResponse.parametros;
    }

    // 10. Guardar respuesta del asistente
    await supabase.from("ai_messages").insert({
      conversation_id: conversationId,
      role: "ASSISTANT",
      content: finalResponse.respuesta,
      skill_id: parsedResponse?.skill_id,
      resultado_data: finalResponse.datos,
      tokens_input: llmData.usage?.input_tokens ?? 0,
      tokens_output: llmData.usage?.output_tokens ?? 0,
      latencia_ms: latencyMs,
    });

    // 11. Registrar uso de tokens
    await supabase.from("ia_token_usage").insert({
      empresa_id: body.empresa_id,
      edge_function: "ai-chat",
      provider: "ANTHROPIC",
      model: "claude-sonnet-4-20250514",
      tokens_input: llmData.usage?.input_tokens ?? 0,
      tokens_output: llmData.usage?.output_tokens ?? 0,
      costo_estimado: ((llmData.usage?.input_tokens ?? 0) * 0.003 +
        (llmData.usage?.output_tokens ?? 0) * 0.015) / 1000,
    });

    return new Response(JSON.stringify(finalResponse), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err: any) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
```

```sql
-- ============================================================
-- FUNCION HELPER: Ejecutar SQL del chat IA (con sandbox de seguridad)
-- ============================================================

CREATE OR REPLACE FUNCTION execute_ai_query(
  p_sql TEXT,
  p_params TEXT[],
  p_empresa_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_result JSONB;
BEGIN
  -- Validaciones de seguridad
  IF p_sql ILIKE '%DROP%' OR p_sql ILIKE '%DELETE%' OR p_sql ILIKE '%UPDATE%'
     OR p_sql ILIKE '%INSERT%' OR p_sql ILIKE '%ALTER%' OR p_sql ILIKE '%CREATE%'
     OR p_sql ILIKE '%TRUNCATE%' OR p_sql ILIKE '%GRANT%' THEN
    RAISE EXCEPTION 'Operacion no permitida en consultas IA';
  END IF;

  -- El primer parametro siempre es empresa_id (inyectado, no del usuario)
  -- Esto garantiza multi-tenancy
  EXECUTE FORMAT('SELECT jsonb_agg(row_to_json(t)) FROM (%s) t', p_sql)
    INTO v_result
    USING p_empresa_id,
      COALESCE(p_params[1], ''),
      COALESCE(p_params[2], ''),
      COALESCE(p_params[3], ''),
      COALESCE(p_params[4], '');

  RETURN COALESCE(v_result, '[]'::JSONB);
END;
$$;
```

## Flujo UI/UX - Chat IA

```
WIDGET: Chat IA (Panel lateral o floating, accesible desde cualquier modulo)
├── Header
│   ├── Icono PILAR AI + titulo "Asistente PILAR"
│   ├── Selector: [Nueva conversacion v] | [Historial v]
│   └── Boton minimizar/cerrar
│
├── Area de mensajes (scroll)
│   ├── Burbuja USUARIO: texto plano
│   ├── Burbuja ASISTENTE: texto formateado markdown
│   │   ├── Si hay datos tabulares: SfDataGrid inline
│   │   ├── Si hay montos: resaltados en negrita
│   │   └── Si hay accion pendiente: botones [Confirmar] [Cancelar]
│   └── Indicador "PILAR AI esta escribiendo..."
│
├── Input
│   ├── TextField con hint "Pregunta algo..."
│   ├── Boton enviar (o Enter)
│   ├── Boton microfono (speech-to-text, futuro P3)
│   └── Sugerencias rapidas (chips):
│       "Resumen del dia" | "Ventas de hoy" | "Stock bajo" | "Cobros pendientes"
│
└── Footer
    └── Texto: "IA puede cometer errores. Verifica datos criticos."

COMPORTAMIENTO:
- Se abre como panel lateral (desktop) o bottom sheet (mobile)
- Contexto automatico: si esta en modulo Ventas, prioriza skills de ventas
- Historial por usuario, persistido en ai_conversations + ai_messages
- Keyboard shortcut: Ctrl+J (desktop) para abrir/cerrar
- Accesible desde cualquier pantalla via FAB o icono en header
```

---

