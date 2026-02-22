/**
 * PILAR ERP — Edge Function: poll-autorizacion
 *
 * Job de fondo que consulta periódicamente al SRI por documentos electrónicos
 * en estado ENVIADO (enviados pero aún pendientes de autorización).
 *
 * Flujo:
 *   1. Obtiene hasta 50 items con estado = 'ENVIADO' y proximo_intento <= NOW()
 *      llamando al RPC get_cola_items_para_poll() — incluye poll_modo_autorizacion
 *      por empresa (LOTE | INDIVIDUAL).
 *   2. Agrupa items por (ambiente × poll_modo).
 *   3. Por cada grupo:
 *      - LOTE       → consultarAutorizacionLote() — 1 llamada SOAP para todo el grupo
 *      - INDIVIDUAL → consultarAutorizacion() por cada item, con delay entre llamadas
 *   4. Procesa cada item usando el resultado obtenido:
 *      - AUTORIZADO        → guarda XML en Storage, llama a update_cola_autorizado()
 *      - NO AUTORIZADO     → llama a update_cola_rechazado() (estado terminal)
 *      - ANULADO           → llama a marcar_factura_anulada_por_sri() + update_cola_rechazado()
 *      - PENDIENTE_ANULAR  → update_cola_poll_proximo_intento() para seguir pollando
 *      - EN PROCESO        → update_cola_poll_proximo_intento() para espaciar el próximo poll
 *   5. Si una llamada SOAP falla (lote o individual), el item se marca ERROR con backoff
 *      y es reintentado en el próximo ciclo de pg_cron. No hay fallback entre modos.
 *   6. Un error de BD por item NO interrumpe el loop (fallo aislado por item)
 *   7. Retorna un resumen JSON de los resultados del ciclo
 *
 * Llamado desde:
 *   - pg_cron cada 5 minutos: SELECT cron.schedule('poll-autorizacion-sri', '*/5 * * * *', ...)
 *   - Manualmente desde el dashboard de Supabase para debugging
 *
 * Método: POST
 * Body:   {} (vacío; la función no requiere parámetros)
 * Auth:   verify_jwt = true — el service_role key es un JWT válido de Supabase.
 *
 * Respuestas:
 *   200  → { ok: true, processed, autorizado, rechazado, en_proceso, error, results }
 *   405  → { error: 'METHOD_NOT_ALLOWED' }
 *   500  → { error: 'DB_ERROR', detail: string }
 *
 * Storage:
 *   Bucket: sri-documents
 *   Path:   {empresa_id}/{año}/{mes}/{clave_acceso}_autorizado.xml
 *
 * RPCs de BD utilizadas:
 *   - get_cola_items_para_poll(p_limit)            — 019_poll_config.sql
 *   - update_cola_poll_proximo_intento(id, delay)  — 008_poll_autorizacion_helpers.sql
 *   - update_cola_autorizado(...)                  — 006_cola_sri_helpers.sql
 *   - update_cola_rechazado(...)                   — 006_cola_sri_helpers.sql
 *   - update_cola_error(...)                       — 006_cola_sri_helpers.sql
 *   - marcar_factura_anulada_por_sri(...)          — 018_anulacion_electronica.sql
 *
 * Canal pg_notify emitido (vía update_cola_autorizado):
 *   'pilar_documento_autorizado' — dispara generate-ride para PDF RIDE + notificaciones
 */

import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import { createClient } from '@supabase/supabase-js';
import { corsHeaders, handleCors } from '../_shared/cors.ts';
import {
  consultarAutorizacion,
  consultarAutorizacionLote,
  type AmbienteSri,
  type RespuestaAutorizacion,
} from '../_shared/sri-soap.ts';

// ---------------------------------------------------------------------------
// Configuración del entorno
// ---------------------------------------------------------------------------

const SUPABASE_URL              = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

/** Delay en ms entre llamadas SOAP individuales consecutivas (modo INDIVIDUAL). */
const INTER_ITEM_DELAY_MS = 500;

/** Delay en segundos para items que siguen EN_PROCESO (5 minutos). */
const EN_PROCESO_DELAY_S = 300;

/** Timeout en ms para cada llamada SOAP al SRI. */
const SRI_TIMEOUT_MS = 15_000;

/** Número máximo de items a procesar por ciclo de poll. */
const POLL_LIMIT = 50;

// ---------------------------------------------------------------------------
// Tipos locales
// ---------------------------------------------------------------------------

type PollModo = 'INDIVIDUAL' | 'LOTE';

/**
 * Fila retornada por get_cola_items_para_poll().
 * poll_modo_autorizacion: configuración de la empresa en configuracion_facturacion_ec
 * (LOTE por defecto si la empresa no tiene fila en esa tabla).
 */
interface ColaItemParaPoll {
  cola_id:                string;
  empresa_id:             string;
  clave_acceso:           string;
  ambiente_sri:           number;       // 1=PRUEBAS, 2=PRODUCCION
  xml_firmado_path:       string;
  version:                number;
  intentos:               number;
  updated_at:             string;
  poll_modo_autorizacion: PollModo;
}

interface PollItemResult {
  cola_id:             string;
  clave_acceso_prefix: string;
  resultado:           'AUTORIZADO' | 'RECHAZADO' | 'EN_PROCESO' | 'ERROR';
  error?:              string;
}

interface PollSummary {
  ok:         true;
  processed:  number;
  autorizado: number;
  rechazado:  number;
  en_proceso: number;
  error:      number;
  results:    PollItemResult[];
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function resolverAmbiente(ambienteSri: number): AmbienteSri {
  return ambienteSri === 2 ? 'PRODUCCION' : 'PRUEBAS';
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/** Clave de agrupación: combina ambiente y modo para diferenciar los 4 grupos posibles. */
function grupoKey(ambiente: AmbienteSri, modo: PollModo): string {
  return `${ambiente}-${modo}`;
}

// ---------------------------------------------------------------------------
// Handler principal
// ---------------------------------------------------------------------------

Deno.serve(async (req: Request): Promise<Response> => {
  const corsResponse = handleCors(req);
  if (corsResponse) return corsResponse;

  if (req.method !== 'POST') {
    return jsonResponse(405, { error: 'METHOD_NOT_ALLOWED' });
  }

  const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  console.log('[poll-autorizacion] iniciando ciclo de poll');

  // -------------------------------------------------------------------------
  // PASO 1: Obtener batch de items ENVIADO con proximo_intento <= NOW()
  // -------------------------------------------------------------------------
  const { data: items, error: fetchError } = await supabaseAdmin
    .rpc('get_cola_items_para_poll', { p_limit: POLL_LIMIT });

  if (fetchError) {
    console.error('[poll-autorizacion] error obteniendo items del RPC:', fetchError.message);
    return jsonResponse(500, { error: 'DB_ERROR', detail: fetchError.message });
  }

  const colaItems = (items ?? []) as ColaItemParaPoll[];

  if (colaItems.length === 0) {
    console.log('[poll-autorizacion] no hay items ENVIADO pendientes de poll');
    return jsonResponse(200, {
      ok: true, processed: 0, autorizado: 0, rechazado: 0, en_proceso: 0, error: 0, results: [],
    } satisfies PollSummary);
  }

  console.log(`[poll-autorizacion] items a procesar: ${colaItems.length}`);

  // -------------------------------------------------------------------------
  // PASO 2: Consultar el SRI agrupando por (ambiente × poll_modo)
  //
  // Grupos posibles: PRODUCCION-LOTE, PRODUCCION-INDIVIDUAL,
  //                  PRUEBAS-LOTE, PRUEBAS-INDIVIDUAL
  //
  // LOTE       → 1 llamada SOAP por grupo (toda la lista de claves a la vez)
  // INDIVIDUAL → 1 llamada SOAP por item, con delay de 500ms entre llamadas
  //
  // Si una llamada SOAP falla → el item se marca ERROR con backoff.
  // No hay fallback entre modos: LOTE fallido = ERROR, no intenta INDIVIDUAL.
  // -------------------------------------------------------------------------

  // Agrupar por (ambiente, modo)
  const grupos = new Map<string, { ambiente: AmbienteSri; modo: PollModo; items: ColaItemParaPoll[] }>();
  for (const item of colaItems) {
    const ambiente = resolverAmbiente(item.ambiente_sri);
    const modo     = item.poll_modo_autorizacion;
    const key      = grupoKey(ambiente, modo);
    if (!grupos.has(key)) {
      grupos.set(key, { ambiente, modo, items: [] });
    }
    grupos.get(key)!.items.push(item);
  }

  // Mapa global clave_acceso → respuesta SRI
  const respuestas = new Map<string, RespuestaAutorizacion>();
  // Items cuya llamada SOAP falló → se marcarán ERROR en el paso 3
  const itemsConError = new Map<string, string>(); // clave_acceso → mensaje de error

  for (const [key, grupo] of grupos) {
    const { ambiente, modo, items: grupoItems } = grupo;

    if (modo === 'LOTE') {
      // -------------------------------------------------------------------
      // Modo LOTE: 1 llamada SOAP para todo el grupo
      // -------------------------------------------------------------------
      const claves = grupoItems.map((i) => i.clave_acceso);
      console.log(`[poll-autorizacion] lote ${key}: ${claves.length} items`);

      try {
        const resultados = await consultarAutorizacionLote(claves, ambiente, SRI_TIMEOUT_MS);
        for (const [clave, resp] of resultados) {
          respuestas.set(clave, resp);
        }
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        console.error(`[poll-autorizacion] fallo SOAP lote ${key}: ${msg}`);
        for (const item of grupoItems) {
          itemsConError.set(item.clave_acceso, msg);
        }
      }

    } else {
      // -------------------------------------------------------------------
      // Modo INDIVIDUAL: 1 llamada SOAP por item con delay entre llamadas
      // -------------------------------------------------------------------
      console.log(`[poll-autorizacion] individual ${key}: ${grupoItems.length} items`);

      for (let i = 0; i < grupoItems.length; i++) {
        const item     = grupoItems[i];
        const caPrefix = item.clave_acceso.substring(0, 10) + '...';

        if (i > 0) await sleep(INTER_ITEM_DELAY_MS);

        try {
          const resp = await consultarAutorizacion(item.clave_acceso, ambiente, SRI_TIMEOUT_MS);
          respuestas.set(item.clave_acceso, resp);
          console.log(`[poll-autorizacion] individual ${caPrefix} | estado: ${resp.estado}`);
        } catch (err) {
          const msg = err instanceof Error ? err.message : String(err);
          console.error(`[poll-autorizacion] fallo SOAP individual ${caPrefix}: ${msg}`);
          itemsConError.set(item.clave_acceso, msg);
        }
      }
    }
  }

  // -------------------------------------------------------------------------
  // PASO 3: Procesar cada item usando la respuesta obtenida
  // -------------------------------------------------------------------------
  const results: PollItemResult[] = [];

  for (const item of colaItems) {
    const caPrefix = item.clave_acceso.substring(0, 10) + '...';

    // -----------------------------------------------------------------------
    // Error SOAP: la llamada al SRI falló → marcar ERROR con backoff
    // -----------------------------------------------------------------------
    if (itemsConError.has(item.clave_acceso)) {
      const msg = itemsConError.get(item.clave_acceso)!;
      try {
        await supabaseAdmin.rpc('update_cola_error', {
          p_cola_item_id:  item.cola_id,
          p_error_message: `poll-autorizacion: ${msg}`,
          p_version:       item.version,
        });
      } catch (dbErr) {
        console.error(
          `[poll-autorizacion] no se pudo marcar ERROR en BD para ${caPrefix}:`,
          dbErr instanceof Error ? dbErr.message : String(dbErr),
        );
      }
      results.push({ cola_id: item.cola_id, clave_acceso_prefix: caPrefix, resultado: 'ERROR', error: msg });
      continue;
    }

    // Respuesta del SRI (fallback EN PROCESO si no vino en el lote — no debería ocurrir)
    const respuesta = respuestas.get(item.clave_acceso) ?? { estado: 'EN PROCESO' as const, mensajes: [] };

    console.log(
      `[poll-autorizacion] ${caPrefix} | modo: ${item.poll_modo_autorizacion} | estado: ${respuesta.estado} | intentos: ${item.intentos}`,
    );

    try {

      // ---------------------------------------------------------------------
      // Caso 1: AUTORIZADO
      // ---------------------------------------------------------------------
      if (respuesta.estado === 'AUTORIZADO') {
        let xmlAutorizadoPath = '';

        if (respuesta.xmlAutorizado) {
          const xmlBytes = new TextEncoder().encode(respuesta.xmlAutorizado);
          const now  = new Date();
          const anio = now.getFullYear();
          const mes  = String(now.getMonth() + 1).padStart(2, '0');
          const storagePath = `${item.empresa_id}/${anio}/${mes}/${item.clave_acceso}_autorizado.xml`;

          const { error: storageError } = await supabaseAdmin
            .storage.from('sri-documents')
            .upload(storagePath, xmlBytes, { contentType: 'application/xml', upsert: true });

          if (storageError) {
            console.warn(`[poll-autorizacion] fallo Storage (${caPrefix}):`, storageError.message);
          } else {
            xmlAutorizadoPath = storagePath;
          }
        }

        const fechaAuth = respuesta.fechaAutorizacion
          ? new Date(respuesta.fechaAutorizacion.replace(' ', 'T')).toISOString()
          : new Date().toISOString();

        const { data: updResult, error: updError } = await supabaseAdmin.rpc('update_cola_autorizado', {
          p_cola_item_id:        item.cola_id,
          p_numero_autorizacion: respuesta.numeroAutorizacion ?? '',
          p_fecha_autorizacion:  fechaAuth,
          p_xml_autorizado:      respuesta.xmlAutorizado ?? '',
          p_xml_autorizado_path: xmlAutorizadoPath,
          p_version:             item.version,
        });

        if (updError) {
          console.error(`[poll-autorizacion] error update_cola_autorizado (${caPrefix}):`, updError.message);
        } else if (updResult?.error === 'VERSION_CONFLICT') {
          console.warn(`[poll-autorizacion] VERSION_CONFLICT AUTORIZADO (${caPrefix})`);
        } else {
          console.log(`[poll-autorizacion] AUTORIZADO: ${caPrefix}`);
        }

        results.push({ cola_id: item.cola_id, clave_acceso_prefix: caPrefix, resultado: 'AUTORIZADO' });

      // ---------------------------------------------------------------------
      // Caso 2: NO AUTORIZADO — estado terminal
      // ---------------------------------------------------------------------
      } else if (respuesta.estado === 'NO AUTORIZADO') {
        const { error: rechazadoError } = await supabaseAdmin.rpc('update_cola_rechazado', {
          p_cola_item_id: item.cola_id,
          p_mensajes:     JSON.stringify(respuesta.mensajes ?? []),
          p_version:      item.version,
        });

        if (rechazadoError) {
          console.error(`[poll-autorizacion] error update_cola_rechazado (${caPrefix}):`, rechazadoError.message);
        } else {
          console.log(`[poll-autorizacion] RECHAZADO (terminal): ${caPrefix}`);
        }

        results.push({ cola_id: item.cola_id, clave_acceso_prefix: caPrefix, resultado: 'RECHAZADO' });

      // ---------------------------------------------------------------------
      // Caso 3: ANULADO — detectado vía portal SRI
      // ---------------------------------------------------------------------
      } else if (respuesta.estado === 'ANULADO') {
        const { error: anulError } = await supabaseAdmin.rpc('marcar_factura_anulada_por_sri', {
          p_clave_acceso:    item.clave_acceso,
          p_fecha_anulacion: new Date().toISOString(),
        });

        if (anulError) {
          console.warn(`[poll-autorizacion] error marcar_factura_anulada_por_sri (${caPrefix}):`, anulError.message);
        } else {
          console.log(`[poll-autorizacion] ANULADO via portal SRI: ${caPrefix}`);
        }

        await supabaseAdmin.rpc('update_cola_rechazado', {
          p_cola_item_id: item.cola_id,
          p_mensajes:     JSON.stringify([{ identificador: 'ANULADO', mensaje: 'Documento anulado vía portal SRI', tipo: 'INFORMATIVO' }]),
          p_version:      item.version,
        });

        results.push({ cola_id: item.cola_id, clave_acceso_prefix: caPrefix, resultado: 'RECHAZADO' });

      // ---------------------------------------------------------------------
      // Caso 4: PENDIENTE_DE_ANULAR — seguir pollando
      // ---------------------------------------------------------------------
      } else if (respuesta.estado === 'PENDIENTE_DE_ANULAR') {
        const { error: proxError } = await supabaseAdmin.rpc('update_cola_poll_proximo_intento', {
          p_cola_item_id:   item.cola_id,
          p_delay_segundos: EN_PROCESO_DELAY_S,
        });

        if (proxError) {
          console.warn(`[poll-autorizacion] error proximo_intento PENDIENTE_DE_ANULAR (${caPrefix}):`, proxError.message);
        } else {
          console.log(`[poll-autorizacion] PENDIENTE_DE_ANULAR: ${caPrefix} | próximo en ${EN_PROCESO_DELAY_S}s`);
        }

        results.push({ cola_id: item.cola_id, clave_acceso_prefix: caPrefix, resultado: 'EN_PROCESO' });

      // ---------------------------------------------------------------------
      // Caso 5: EN PROCESO (y cualquier estado no reconocido)
      // ---------------------------------------------------------------------
      } else {
        const { error: proxError } = await supabaseAdmin.rpc('update_cola_poll_proximo_intento', {
          p_cola_item_id:   item.cola_id,
          p_delay_segundos: EN_PROCESO_DELAY_S,
        });

        if (proxError) {
          console.warn(`[poll-autorizacion] error proximo_intento (${caPrefix}):`, proxError.message);
        } else {
          console.log(`[poll-autorizacion] EN_PROCESO: ${caPrefix} | próximo en ${EN_PROCESO_DELAY_S}s`);
        }

        results.push({ cola_id: item.cola_id, clave_acceso_prefix: caPrefix, resultado: 'EN_PROCESO' });
      }

    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      console.error(`[poll-autorizacion] error BD procesando ${caPrefix}:`, msg);

      try {
        await supabaseAdmin.rpc('update_cola_error', {
          p_cola_item_id:  item.cola_id,
          p_error_message: `poll-autorizacion: ${msg}`,
          p_version:       item.version,
        });
      } catch (dbErr) {
        console.error(
          `[poll-autorizacion] no se pudo marcar ERROR en BD para ${caPrefix}:`,
          dbErr instanceof Error ? dbErr.message : String(dbErr),
        );
      }

      results.push({ cola_id: item.cola_id, clave_acceso_prefix: caPrefix, resultado: 'ERROR', error: msg });
    }
  }

  // -------------------------------------------------------------------------
  // PASO 4: Resumen del ciclo
  // -------------------------------------------------------------------------
  const summary: PollSummary = {
    ok:         true,
    processed:  results.length,
    autorizado: results.filter((r) => r.resultado === 'AUTORIZADO').length,
    rechazado:  results.filter((r) => r.resultado === 'RECHAZADO').length,
    en_proceso: results.filter((r) => r.resultado === 'EN_PROCESO').length,
    error:      results.filter((r) => r.resultado === 'ERROR').length,
    results,
  };

  console.log('[poll-autorizacion] ciclo completado:', JSON.stringify({
    processed:  summary.processed,
    autorizado: summary.autorizado,
    rechazado:  summary.rechazado,
    en_proceso: summary.en_proceso,
    error:      summary.error,
  }));

  return jsonResponse(200, summary);
});
