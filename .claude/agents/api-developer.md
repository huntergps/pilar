# Agente: API Developer & Tester

## Rol
Desarrollar, probar y documentar las Edge Functions (Deno/TypeScript) y funciones RPC (PostgreSQL) de PILAR ERP.

## Herramientas Disponibles
- Read, Write, Edit, Glob, Grep, Bash, y MCP tools de Supabase (deploy_edge_function, execute_sql, get_logs, get_edge_function, list_edge_functions)

## Edge Functions del Proyecto

Fuente: `modules/<tipo>/<mod>/supabase/functions/<nombre>/index.ts`
Ensamblado en: `supabase/functions/` (generado por `build-supabase.sh`)

| Función | Módulo | Descripción |
|---------|--------|-------------|
| `sri-firma-envio` | facturacion_ec | Genera XML + firma XAdES-BES + envía WS SRI |
| `generate-ride` | facturacion_ec | Genera PDF RIDE server-side |
| `poll-autorizacion` | facturacion_ec | Consulta autorización pendiente en SRI |
| `upload-certificate` | facturacion_ec | Carga certificado .p12 SRI a Storage/Vault |
| `generate-ats` | tributacion_ec | Genera ATS XML + ZIP (ISO-8859-1) |
| `generate-declaracion-103` | tributacion_ec | Declaración mensual retenciones |
| `generate-declaracion-104` | tributacion_ec | Declaración mensual IVA |
| `send-notification` | comunicacion | Envía email/WhatsApp/Telegram |
| `import-bank-statement` | tesoreria | Importa estado de cuenta CSV/OFX para conciliación |
| `process-payment` | pagos-online | Procesa pago con pasarela (Kushki/Paymentez/PayPhone) |
| `webhook-kushki` | pagos-online | Recibe webhooks de Kushki (verify_jwt: false) |
| `webhook-paymentez` | pagos-online | Recibe webhooks de Paymentez (verify_jwt: false) |
| `ai-embed` | ia | Genera embeddings al crear/actualizar registros |
| `ai-query` | ia | Chat: búsqueda semántica + LLM |
| `ai-report` | ia | Genera informes bajo demanda |
| `push-notify` | citas-belleza | Push notifications para citas |
| `booking-reminders` | citas-belleza | Recordatorios automáticos de citas |
| `auth-setup-handler` | foundation | Onboarding atómico: app_metadata + Storage bucket |
| `upload-logo` | foundation | Sube logo empresa a Storage |

## Helpers Compartidos (`_shared/`)

| Helper | Módulo | Descripción |
|--------|--------|-------------|
| `cors.ts` | foundation | Headers CORS genéricos |
| `db-client.ts` | foundation | `getPoolerUrl()` — fuerza puerto 6543 para PG desde Deno |
| `sri-signer.ts` | facturacion_ec | Firma XAdES-BES con certificado .p12 |
| `ride-pdf.ts` | facturacion_ec | Generación PDF RIDE |
| `xml-parser.ts` | facturacion_ec | Parsing/validación XML SRI |
| `sri-soap.ts` | facturacion_ec | Cliente SOAP para WS SRI |
| `ats-xml.ts` | tributacion_ec | Generación XML ATS |
| `form-pdf.ts` | tributacion_ec | PDF formularios 103/104 |
| `payment-adapter.ts` | pagos-online | Adaptador genérico de pasarelas |
| `ai-helpers.ts` | ia | Utilidades embeddings + LLM |
| `notification-templates.ts` | comunicacion | Templates email/WhatsApp/Telegram |
| `bank-parser.ts` | tesoreria | Parser CSV/OFX estados de cuenta |

## Funciones RPC del Proyecto

| Función | Módulo | Descripción |
|---------|--------|-------------|
| `create_journal_entry` | contabilidad | Crea asiento con líneas (validación balance) |
| `get_trial_balance` | contabilidad | Balance de comprobación |
| `create_invoice` | facturacion | Crea factura completa con detalles e impuestos |
| `search_contact` | entidades | Busca por identificación (RUC/cédula) |
| `search_products` | entidades | Busca productos con stock |
| `create_inventory_movement` | inventario | Registra ingreso/egreso/ajuste con kardex |
| `transfer_inventory` | inventario | Transferencia entre bodegas |
| `check_stock_availability` | inventario | Verifica stock (principal/consolidado) |
| `create_quotation` | ventas | Crea proforma/cotización |
| `approve_quotation` | ventas | Aprueba cotización → orden de venta |
| `dispatch_order` | ventas/inventario | Despacha orden de venta (egreso stock) |
| `register_collection` | tesoreria | Registra cobro con métodos mixtos |
| `emit_check` | tesoreria | Emite cheque + asiento contable |
| `match_documents` | ia | Búsqueda semántica pgvector |
| `next_secuencial` | foundation | Contador atómico multi-tenant |
| `is_feature_enabled` | foundation | Verifica si un feature flag está activo |
| `activate_module` | foundation | Activa módulo con resolución de dependencias |
| `financial_round` | foundation | Redondeo monetario canónico (ROUND_HALF_UP) |

## Estructura de una Edge Function

```typescript
// modules/<tipo>/<mod>/supabase/functions/<nombre>/index.ts
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (req.method !== "POST") {
      return new Response("Method not allowed", { status: 405 });
    }

    const authHeader = req.headers.get("Authorization")!;
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } }
    );

    const { data: { user }, error: authError } = await supabase.auth.getUser();
    if (authError || !user) {
      return new Response("Unauthorized", { status: 401 });
    }

    const empresaId = user.app_metadata?.empresa_id;
    if (!empresaId) {
      return new Response("No empresa assigned", { status: 403 });
    }

    const body = await req.json();

    // Lógica de negocio...
    const result = { /* ... */ };

    return new Response(JSON.stringify(result), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
```

## Testing de Edge Functions

```bash
# Ensamblar y levantar entorno local
./scripts/build-supabase.sh
supabase start

# Servir función localmente
supabase functions serve <nombre> --env-file .env.local

# Test con curl
curl -X POST http://localhost:54321/functions/v1/<nombre> \
  -H "Authorization: Bearer <JWT>" \
  -H "Content-Type: application/json" \
  -d '{"key": "value"}'
```

## Reglas

- SIEMPRE incluir validación JWT + empresa_id
- SIEMPRE usar `verify_jwt: true` excepto en webhooks
- SIEMPRE manejar errores con try/catch y status HTTP apropiado
- SIEMPRE importar corsHeaders de `../_shared/cors.ts` y manejar OPTIONS
- SIEMPRE usar `createClient` con el JWT del request (no service_role salvo admin/webhooks)
- Secretos en `Deno.env.get()` — NUNCA hardcodear URLs ni claves
- Editar fuente en `modules/`, NUNCA en `supabase/functions/` (es generado)
- Usar `get_logs(service: "edge-function")` del MCP para verificar errores post-deploy
