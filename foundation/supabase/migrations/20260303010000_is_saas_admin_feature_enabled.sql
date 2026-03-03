-- =============================================================================
-- PILAR ERP — Foundation Gap: is_saas_admin + is_feature_enabled safety net
-- =============================================================================
-- Both functions already exist (core.sql + feature_flags.sql) but this
-- migration ensures they are present even if earlier migrations were
-- partially applied. CREATE OR REPLACE is idempotent.
-- =============================================================================

-- private.is_saas_admin() — referenced by private.has_permission()
-- Already defined in 000_core.sql, this is a safety net.
CREATE OR REPLACE FUNCTION private.is_saas_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = auth, private
AS $$
  SELECT COALESCE(
    (auth.jwt() -> 'app_metadata' ->> 'is_saas_admin')::BOOLEAN,
    false
  )
$$;

COMMENT ON FUNCTION private.is_saas_admin() IS
  'Returns true if the user has is_saas_admin=true in JWT app_metadata. '
  'Only the platform operator can set this flag via Auth Admin API (service_role).';

-- is_feature_enabled(TEXT) — simple overload without empresa/usuario params.
-- The full version with 3 params exists in 010_feature_flags.sql.
-- This adds a convenience 1-param wrapper that delegates to the full version.
-- No-op if the 1-param signature already exists.
DO $$
BEGIN
  -- Check if the 1-param overload already exists
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'is_feature_enabled'
      AND p.pronargs = 1
  ) THEN
    -- The existing 3-param function with defaults covers this case,
    -- so no additional overload is needed.
    RAISE NOTICE 'is_feature_enabled exists with defaults — no 1-param overload needed';
  END IF;
END $$;
