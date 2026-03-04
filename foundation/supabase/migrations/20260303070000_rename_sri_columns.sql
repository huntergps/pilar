-- Migration: rename Ecuador-specific column names to generic names
-- Foundation must be country-agnostic.
--
-- Changes:
--   contactos.tipo_id_sri      → tipo_identificacion  (default NULL, not '04'=RUC)
--   unidades_medida.codigo_sri → codigo_tributario
--   usuarios_empresa.zona_horaria DEFAULT 'America/Guayaquil' → 'UTC'

-- ── 1. contactos ─────────────────────────────────────────────────────────────

ALTER TABLE contactos RENAME COLUMN tipo_id_sri TO tipo_identificacion;

-- Drop old check constraint (named after the old column)
ALTER TABLE contactos DROP CONSTRAINT IF EXISTS contactos_tipo_id_sri_check;

-- Recreate with generic name and NULL default (country modules set their own default)
ALTER TABLE contactos ADD CONSTRAINT contactos_tipo_identificacion_check
  CHECK (tipo_identificacion IN ('04','05','06','07','08','20'));

ALTER TABLE contactos ALTER COLUMN tipo_identificacion DROP DEFAULT;

-- ── 2. unidades_medida ───────────────────────────────────────────────────────

ALTER TABLE unidades_medida RENAME COLUMN codigo_sri TO codigo_tributario;

-- ── 3. usuarios_empresa zona_horaria default ─────────────────────────────────

ALTER TABLE usuarios_empresa ALTER COLUMN zona_horaria SET DEFAULT 'UTC';

-- Update existing rows that still have the old EC default
-- (only rows where the value was never explicitly set by the user)
UPDATE usuarios_empresa
SET zona_horaria = 'UTC'
WHERE zona_horaria = 'America/Guayaquil';
