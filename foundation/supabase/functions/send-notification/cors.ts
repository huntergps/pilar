/**
 * PILAR ERP — Supabase Edge Functions
 * Shared CORS headers and preflight handler.
 *
 * Usage:
 *   import { corsHeaders, handleCors } from '../_shared/cors.ts'
 *
 *   const corsResponse = handleCors(req)
 *   if (corsResponse) return corsResponse
 */

export const corsHeaders: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

/**
 * Handles CORS preflight (OPTIONS) requests.
 * Returns a Response for OPTIONS, or null for all other methods
 * (meaning the caller should continue processing).
 */
export function handleCors(req: Request): Response | null {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  return null;
}
