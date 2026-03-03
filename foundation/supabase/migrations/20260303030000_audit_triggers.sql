-- =============================================================================
-- PILAR ERP — Foundation Gap: Audit Triggers
-- =============================================================================
-- audit_log table already exists (from modelo-datos-auditoria migration).
-- This migration adds:
--   1. private.audit_trigger() function
--   2. Triggers on critical foundation tables
--   3. pg_cron cleanup job (90-day retention)
--
-- Existing audit_log columns: id, empresa_id, tabla, registro_id, accion,
--   datos_anteriores, datos_nuevos, usuario_id, created_at
-- =============================================================================

-- ─── 1. Add ip_address column if missing ────────────────────────────────────
ALTER TABLE public.audit_log
  ADD COLUMN IF NOT EXISTS ip_address INET;

-- ─── 2. Additional indexes ──────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_audit_log_empresa_created
  ON public.audit_log(empresa_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_audit_log_tabla_registro
  ON public.audit_log(tabla, registro_id);

-- ─── 3. Audit trigger function ──────────────────────────────────────────────
-- Uses the existing column names: accion, datos_anteriores, datos_nuevos
CREATE OR REPLACE FUNCTION private.audit_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_old_json JSONB;
  v_new_json JSONB;
  v_empresa  UUID;
  v_reg_id   UUID;
BEGIN
  -- Build JSON representations
  IF TG_OP IN ('UPDATE', 'DELETE') THEN
    v_old_json := row_to_json(OLD)::JSONB;
  END IF;
  IF TG_OP IN ('INSERT', 'UPDATE') THEN
    v_new_json := row_to_json(NEW)::JSONB;
  END IF;

  -- Extract empresa_id from the row (prefer NEW, fallback to OLD)
  v_empresa := COALESCE(
    (v_new_json ->> 'empresa_id')::UUID,
    (v_old_json ->> 'empresa_id')::UUID
  );

  -- Extract record id
  v_reg_id := COALESCE(
    (v_new_json ->> 'id')::UUID,
    (v_old_json ->> 'id')::UUID
  );

  -- Skip if no empresa_id (system tables without tenant isolation)
  IF v_empresa IS NOT NULL THEN
    INSERT INTO public.audit_log(
      empresa_id, tabla, registro_id, accion,
      usuario_id, datos_anteriores, datos_nuevos
    )
    VALUES (
      v_empresa,
      TG_TABLE_NAME,
      v_reg_id,
      TG_OP,
      auth.uid(),
      v_old_json,
      v_new_json
    );
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  ELSE
    RETURN NEW;
  END IF;
END;
$$;

COMMENT ON FUNCTION private.audit_trigger() IS
  'Generic audit trigger that logs INSERT/UPDATE/DELETE to audit_log. '
  'Installed on critical foundation tables. Skips rows without empresa_id.';

-- ─── 4. Install triggers on critical tables ─────────────────────────────────
DO $block$
DECLARE
  v_tabla TEXT;
BEGIN
  FOREACH v_tabla IN ARRAY ARRAY[
    'empresas',
    'usuarios_empresa',
    'roles',
    'permisos',
    'configuracion_empresa',
    'modulos_empresa'
  ] LOOP
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.triggers
      WHERE trigger_name = 'trg_audit_' || v_tabla
        AND event_object_table = v_tabla
    ) THEN
      EXECUTE format(
        'CREATE TRIGGER trg_audit_%I
         AFTER INSERT OR UPDATE OR DELETE ON public.%I
         FOR EACH ROW EXECUTE FUNCTION private.audit_trigger()',
        v_tabla, v_tabla
      );
    END IF;
  END LOOP;
END $block$;

-- ─── 5. pg_cron cleanup job: 90-day retention ──────────────────────────────
DO $cron$
DECLARE
  v_sql TEXT;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('cleanup-audit-log')
    FROM cron.job WHERE jobname = 'cleanup-audit-log';

    v_sql := 'DELETE FROM public.audit_log WHERE created_at < now() - INTERVAL ''90 days''';
    PERFORM cron.schedule('cleanup-audit-log', '0 3 * * *', v_sql);
  END IF;
END $cron$;
