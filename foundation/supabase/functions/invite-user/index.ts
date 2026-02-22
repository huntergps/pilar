/**
 * PILAR ERP — Edge Function: invite-user
 *
 * Envía invitaciones de usuarios a una empresa usando Supabase Auth Admin API.
 * Mantiene un registro de auditoría en `invitaciones_pendientes`.
 *
 * Flujo:
 *   1. Llama admin_invite_user(email, rol_id):
 *      - USUARIO_EXISTENTE → crea membresía directamente en BD (sin email). Done.
 *      - NECESITA_INVITACION → continúa al paso 2.
 *   2. Llama crear_invitacion(email, rol_id) → crea registro de auditoría,
 *      retorna { invitacion_id, empresa_id, rol_id }.
 *   3. Llama Supabase Auth Admin inviteUserByEmail(email, { data: app_metadata })
 *      → Supabase envía el email con el magic link de invitación.
 *   4. Llama marcar_invitacion_enviada(invitacion_id, ok, error?) → actualiza estado.
 *
 * Cuando el usuario acepta:
 *   - Supabase Auth crea/confirma el usuario en auth.users.
 *   - El trigger on_auth_user_created lee app_metadata { empresa_id, invitacion_rol_id }
 *     y crea la membresía en usuarios_empresa + marca la invitación ACEPTADA.
 *   - pg_notify('pilar_auth_setup') debe estar conectado a un Database Webhook
 *     que llame a auth-setup-handler para actualizar app_metadata del JWT.
 *
 * Método:   POST
 * Auth:     Authorization: Bearer <JWT_del_usuario> (rol con plataforma.usuarios.gestionar)
 * Body:     { email: string, rol_id: string, dias_vigencia?: number }
 *
 * Respuestas:
 *   { ok: true,  tipo: 'USUARIO_EXISTENTE',   email }
 *   { ok: true,  tipo: 'INVITACION_ENVIADA',  email, invitacion_id, vence_en }
 *   { ok: false, error: string, message: string }
 */

import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import { createClient, SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders, handleCors } from '../_shared/cors.ts';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

// ---------------------------------------------------------------------------
// Handler principal
// ---------------------------------------------------------------------------

Deno.serve(async (req: Request): Promise<Response> => {
  // 1. CORS preflight
  const corsResponse = handleCors(req);
  if (corsResponse) return corsResponse;

  if (req.method !== 'POST') {
    return jsonResponse({ ok: false, error: 'METHOD_NOT_ALLOWED' }, 405);
  }

  // 2. Extraer JWT del usuario
  const authHeader = req.headers.get('Authorization');
  if (!authHeader?.startsWith('Bearer ')) {
    return jsonResponse(
      { ok: false, error: 'UNAUTHORIZED', message: 'Se requiere Authorization: Bearer <jwt>' },
      401,
    );
  }

  // 3. Parsear body
  let email: string, rol_id: string, dias_vigencia: number | undefined;
  try {
    const body = await req.json();
    email = body.email;
    rol_id = body.rol_id;
    dias_vigencia = body.dias_vigencia;
  } catch {
    return jsonResponse({ ok: false, error: 'INVALID_JSON', message: 'Body debe ser JSON válido' });
  }

  if (!email || !rol_id) {
    return jsonResponse({
      ok: false,
      error: 'CAMPOS_REQUERIDOS',
      message: 'Se requieren: email, rol_id',
    });
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

  // Cliente con JWT del usuario — para RPCs que verifican permisos via RLS
  const userClient: SupabaseClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // Cliente admin — para Supabase Auth Admin API y marcar_invitacion_enviada
  const adminClient: SupabaseClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  try {
    // 4. Verificar si el usuario ya tiene cuenta (USUARIO_EXISTENTE vs NECESITA_INVITACION)
    const { data: inviteCheck, error: inviteCheckErr } = await userClient.rpc(
      'admin_invite_user',
      { p_email: email, p_rol_id: rol_id },
    );

    if (inviteCheckErr) {
      console.error('[invite-user] Error en admin_invite_user:', inviteCheckErr);
      return jsonResponse({
        ok: false,
        error: 'RPC_ERROR',
        message: inviteCheckErr.message,
      });
    }

    // Caso A: usuario ya existe — membresía creada directamente, sin email
    if (inviteCheck?.tipo === 'USUARIO_EXISTENTE') {
      console.log(`[invite-user] Usuario existente añadido a empresa: ${email}`);
      return jsonResponse({ ok: true, tipo: 'USUARIO_EXISTENTE', email });
    }

    // Caso B: nuevo usuario — crear registro de auditoría y enviar por Supabase Auth
    if (inviteCheck?.tipo === 'NECESITA_INVITACION') {
      // 5. Crear registro en invitaciones_pendientes (valida duplicados y permisos)
      const rpcParams: Record<string, unknown> = { p_email: email, p_rol_id: rol_id };
      if (dias_vigencia) rpcParams.p_dias_vigencia = dias_vigencia;

      const { data: invData, error: invErr } = await userClient.rpc(
        'crear_invitacion',
        rpcParams,
      );

      if (invErr) {
        console.error('[invite-user] Error en crear_invitacion:', invErr);
        return jsonResponse({
          ok: false,
          error: 'INVITACION_CREATE_ERROR',
          message: invErr.message,
        });
      }

      const invitacion_id: string = invData.invitacion_id;
      const empresa_id: string = invData.empresa_id;
      const invitado_por: string = invData.invitado_por;

      // 6. Enviar invitación vía Supabase Auth Admin API
      //    Los campos en `data` se escriben en app_metadata (solo service_role puede escribirlos),
      //    por lo que son confiables para el trigger on_auth_user_created y para RLS.
      const { error: authErr } = await adminClient.auth.admin.inviteUserByEmail(email, {
        data: {
          empresa_id,
          invitacion_rol_id: rol_id,   // leído por on_auth_user_created como v_rol_id
          invitado_por,
          invitacion_id,               // útil para trazabilidad; no obligatorio para el trigger
        },
      });

      if (authErr) {
        console.error('[invite-user] Error en inviteUserByEmail:', authErr);
        // Marcar como fallida en auditoría
        await adminClient.rpc('marcar_invitacion_enviada', {
          p_invitacion_id: invitacion_id,
          p_ok: false,
          p_error: authErr.message,
        });
        return jsonResponse({
          ok: false,
          error: 'AUTH_INVITE_ERROR',
          message: authErr.message,
        });
      }

      // 7. Marcar como enviada exitosamente
      await adminClient.rpc('marcar_invitacion_enviada', {
        p_invitacion_id: invitacion_id,
        p_ok: true,
      });

      console.log(
        `[invite-user] Invitación enviada: email=${email}, empresa=${empresa_id}, inv=${invitacion_id}`,
      );

      return jsonResponse({
        ok: true,
        tipo: 'INVITACION_ENVIADA',
        email,
        invitacion_id,
        vence_en: invData.vence_en,
      });
    }

    // Respuesta inesperada del RPC
    console.error('[invite-user] Respuesta inesperada de admin_invite_user:', inviteCheck);
    return jsonResponse({
      ok: false,
      error: 'RPC_UNEXPECTED',
      message: 'Respuesta inesperada de admin_invite_user',
    });
  } catch (err) {
    console.error('[invite-user] Error inesperado:', err);
    return jsonResponse({
      ok: false,
      error: 'INTERNAL_ERROR',
      message: 'Error interno procesando la solicitud',
    });
  }
});
