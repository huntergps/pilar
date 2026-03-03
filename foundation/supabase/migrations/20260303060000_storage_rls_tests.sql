-- =============================================================================
-- PILAR ERP — Foundation Gap: Storage RLS pgTAP Tests
-- =============================================================================
-- Verifies that storage.objects policies exist and are correctly configured.
-- Based on actual policies discovered in the database:
--   - adjuntos_storage: leer/subir/actualizar/eliminar propios
--   - avatares_storage: leer/escribir/actualizar/eliminar propio
--   - avatares_authenticated_insert/update, avatares_public_read
--   - avatares_tenant_upload
--   - com_media_insert/select
--   - logos_public_read, logos_storage: escribir/actualizar/eliminar empresa
--   - logos_tenant_upload
-- =============================================================================

BEGIN;

SELECT plan(12);

-- ─── Test 1: storage.objects table exists ────────────────────────────────────
SELECT has_table('storage', 'objects', 'storage.objects table exists');

-- ─── Test 2: RLS is enabled on storage.objects ──────────────────────────────
SELECT is(
  (SELECT relrowsecurity FROM pg_class
   WHERE oid = 'storage.objects'::regclass),
  true,
  'RLS is enabled on storage.objects'
);

-- ─── Test 3-5: Adjuntos bucket policies ─────────────────────────────────────
SELECT has_policy(
  'storage', 'objects',
  'adjuntos_storage: leer propios',
  'Policy: adjuntos read own files exists'
);

SELECT has_policy(
  'storage', 'objects',
  'adjuntos_storage: subir en propia empresa',
  'Policy: adjuntos upload in own company exists'
);

SELECT has_policy(
  'storage', 'objects',
  'adjuntos_storage: eliminar propios',
  'Policy: adjuntos delete own files exists'
);

-- ─── Test 6-8: Avatares bucket policies ─────────────────────────────────────
SELECT has_policy(
  'storage', 'objects',
  'avatares_storage: leer propio',
  'Policy: avatares read own exists'
);

SELECT has_policy(
  'storage', 'objects',
  'avatares_storage: escribir propio',
  'Policy: avatares write own exists'
);

SELECT has_policy(
  'storage', 'objects',
  'avatares_public_read',
  'Policy: avatares public read exists'
);

-- ─── Test 9-10: Logos bucket policies ───────────────────────────────────────
SELECT has_policy(
  'storage', 'objects',
  'logos_public_read',
  'Policy: logos public read exists'
);

SELECT has_policy(
  'storage', 'objects',
  'logos_storage: escribir empresa',
  'Policy: logos write for company exists'
);

-- ─── Test 11-12: Communication media bucket policies ────────────────────────
SELECT has_policy(
  'storage', 'objects',
  'com_media_insert',
  'Policy: com_media insert exists'
);

SELECT has_policy(
  'storage', 'objects',
  'com_media_select',
  'Policy: com_media select exists'
);

SELECT * FROM finish();
ROLLBACK;
