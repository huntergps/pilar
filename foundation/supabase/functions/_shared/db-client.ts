/**
 * PILAR ERP — Helper: cliente de base de datos para Edge Functions
 *
 * Para Edge Functions que necesitan conexión directa a PostgreSQL
 * (fuera del cliente supabase-js), siempre usar el pooler en puerto 6543.
 *
 * El cliente supabase-js (createClient con SUPABASE_URL) ya pasa por el
 * API Gateway y no necesita este fix. Solo aplica a drivers PG directos.
 *
 * Referencia: Carbon ERP pattern — getPostgresConnectionPool()
 * Ver: https://github.com/crbnos/carbon
 */

/**
 * Retorna la URL de conexión a PostgreSQL apuntando al pooler (puerto 6543).
 * Usar cuando se necesita un driver PG directo (ej: postgres.js, pg, Kysely).
 *
 * @example
 * import { postgres } from 'https://deno.land/x/postgres/mod.ts';
 * const db = new postgres(getPoolerUrl());
 */
export function getPoolerUrl(): string {
  const url = Deno.env.get('SUPABASE_DB_URL') ?? '';
  if (!url) {
    throw new Error('[db-client] SUPABASE_DB_URL no configurada');
  }
  // Forzar puerto 6543 (pooler) en lugar de 5432 (conexión directa)
  // Esto es crítico en Edge Functions: cada invocación abre una nueva conexión.
  // Con 5432 se agota el pool de PG bajo carga concurrente.
  return url.replace(':5432', ':6543');
}

/**
 * URL para conexiones en session mode del pooler (pgBouncer).
 * Usar cuando necesites: SET session, transaction isolation, cursores persistentes.
 * NOTA: Actualmente igual a getPoolerUrl(). En Supabase Pro se diferenciará
 * cuando session mode esté en un puerto separado.
 */
export function getSessionUrl(): string {
  // TODO: Supabase Pro — session mode estará en puerto 5432 (direct) o puerto diferente
  return getPoolerUrl();
}
