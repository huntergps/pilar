-- =============================================================================
-- PILAR ERP — Foundation Gap: Soft Delete + Optimistic Locking Version
-- =============================================================================
-- Adds is_deleted and version columns to foundation tables that lack them.
-- Creates bump_version() trigger function for optimistic locking.
-- =============================================================================

-- ─── 1. bump_version() trigger function ─────────────────────────────────────
CREATE OR REPLACE FUNCTION private.bump_version()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.version := OLD.version + 1;
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION private.bump_version() IS
  'Auto-increments the version column on UPDATE for optimistic locking. '
  'Used by SRI documents and critical master tables.';

-- ─── 2. is_deleted column ───────────────────────────────────────────────────
-- Tables: empresas, roles, permisos, modulos, configuracion_empresa
ALTER TABLE public.empresas
  ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE public.roles
  ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE public.permisos
  ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE public.modulos
  ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE public.configuracion_empresa
  ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN NOT NULL DEFAULT FALSE;

-- ─── 3. version column ─────────────────────────────────────────────────────
-- Tables: empresas, configuracion_empresa, usuarios_empresa
-- Note: modulos.version already exists (module version, different purpose).
ALTER TABLE public.empresas
  ADD COLUMN IF NOT EXISTS version INTEGER NOT NULL DEFAULT 1;

ALTER TABLE public.configuracion_empresa
  ADD COLUMN IF NOT EXISTS version INTEGER NOT NULL DEFAULT 1;

ALTER TABLE public.usuarios_empresa
  ADD COLUMN IF NOT EXISTS version INTEGER NOT NULL DEFAULT 1;

-- ─── 4. bump_version triggers ───────────────────────────────────────────────
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.triggers
    WHERE trigger_name = 'trg_bump_version_empresas'
      AND event_object_table = 'empresas'
  ) THEN
    CREATE TRIGGER trg_bump_version_empresas
      BEFORE UPDATE ON public.empresas
      FOR EACH ROW EXECUTE FUNCTION private.bump_version();
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.triggers
    WHERE trigger_name = 'trg_bump_version_configuracion_empresa'
      AND event_object_table = 'configuracion_empresa'
  ) THEN
    CREATE TRIGGER trg_bump_version_configuracion_empresa
      BEFORE UPDATE ON public.configuracion_empresa
      FOR EACH ROW EXECUTE FUNCTION private.bump_version();
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.triggers
    WHERE trigger_name = 'trg_bump_version_usuarios_empresa'
      AND event_object_table = 'usuarios_empresa'
  ) THEN
    CREATE TRIGGER trg_bump_version_usuarios_empresa
      BEFORE UPDATE ON public.usuarios_empresa
      FOR EACH ROW EXECUTE FUNCTION private.bump_version();
  END IF;
END $$;

-- ─── 5. Indexes for soft-delete filtering ───────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_empresas_not_deleted
  ON public.empresas(id) WHERE is_deleted = FALSE;

CREATE INDEX IF NOT EXISTS idx_roles_not_deleted
  ON public.roles(id) WHERE is_deleted = FALSE;

CREATE INDEX IF NOT EXISTS idx_permisos_not_deleted
  ON public.permisos(id) WHERE is_deleted = FALSE;

CREATE INDEX IF NOT EXISTS idx_modulos_not_deleted
  ON public.modulos(id) WHERE is_deleted = FALSE;
