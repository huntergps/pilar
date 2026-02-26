-- =============================================================================
-- 046 · Adjuntos — refactor del schema existente + RPCs + bucket
--
-- La tabla adjuntos fue creada inicialmente en 007_shared_tables.sql con un
-- schema básico. Este archivo:
--   · Renombra columnas al naming convention final
--   · Agrega campos faltantes (nombre_original, eliminado_en, etc.)
--   · Reemplaza la policy ALL por policies específicas CRUD
--   · Agrega el bucket Storage "adjuntos" con RLS por empresa_id
--   · Crea 5 RPCs: registrar, get, count, renombrar, eliminar
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Renombrar columnas al naming convention final
-- ---------------------------------------------------------------------------

ALTER TABLE adjuntos RENAME COLUMN tabla_origen TO entidad_tipo;
ALTER TABLE adjuntos RENAME COLUMN registro_id  TO entidad_id;
ALTER TABLE adjuntos RENAME COLUMN nombre_archivo TO nombre;
ALTER TABLE adjuntos RENAME COLUMN tipo_mime     TO mime_type;
ALTER TABLE adjuntos RENAME COLUMN tamano_bytes  TO tamanio_bytes;

-- VARCHAR → TEXT y INTEGER → BIGINT
ALTER TABLE adjuntos ALTER COLUMN entidad_tipo   TYPE TEXT;
ALTER TABLE adjuntos ALTER COLUMN nombre         TYPE TEXT;
ALTER TABLE adjuntos ALTER COLUMN mime_type      TYPE TEXT;
ALTER TABLE adjuntos ALTER COLUMN tamanio_bytes  TYPE BIGINT;

-- ---------------------------------------------------------------------------
-- 2. Agregar columnas faltantes
-- ---------------------------------------------------------------------------

ALTER TABLE adjuntos
  ADD COLUMN IF NOT EXISTS nombre_original TEXT,
  ADD COLUMN IF NOT EXISTS storage_bucket  TEXT        NOT NULL DEFAULT 'adjuntos',
  ADD COLUMN IF NOT EXISTS descripcion     TEXT,
  ADD COLUMN IF NOT EXISTS es_publico      BOOLEAN     NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS eliminado_en    TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS eliminado_por   UUID        REFERENCES auth.users(id);

-- Backfill nombre_original con nombre (registros previos)
UPDATE adjuntos SET nombre_original = nombre WHERE nombre_original IS NULL;
ALTER TABLE adjuntos ALTER COLUMN nombre_original SET NOT NULL;

-- Eliminar url_publica: se obtiene bajo demanda con Storage.createSignedUrl
ALTER TABLE adjuntos DROP COLUMN IF EXISTS url_publica;

-- ---------------------------------------------------------------------------
-- 3. Constraint y NOT NULL
-- ---------------------------------------------------------------------------

ALTER TABLE adjuntos ADD CONSTRAINT adjuntos_tamanio_check
  CHECK (tamanio_bytes > 0) NOT VALID;

ALTER TABLE adjuntos ALTER COLUMN nombre       SET NOT NULL;
ALTER TABLE adjuntos ALTER COLUMN mime_type    SET NOT NULL;
ALTER TABLE adjuntos ALTER COLUMN tamanio_bytes SET NOT NULL;
ALTER TABLE adjuntos ALTER COLUMN storage_path SET NOT NULL;

-- ---------------------------------------------------------------------------
-- 4. Índices
-- ---------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_adjuntos_entidad
  ON adjuntos (empresa_id, entidad_tipo, entidad_id)
  WHERE eliminado_en IS NULL;

CREATE INDEX IF NOT EXISTS idx_adjuntos_subido_por
  ON adjuntos (subido_por)
  WHERE eliminado_en IS NULL;

-- ---------------------------------------------------------------------------
-- 5. RLS — reemplazar policy ALL por policies específicas
-- ---------------------------------------------------------------------------

ALTER TABLE adjuntos ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "adjuntos_tenant"     ON adjuntos;
DROP POLICY IF EXISTS "adjuntos_tenant_rw"  ON adjuntos;
DROP POLICY IF EXISTS "adjuntos: select"    ON adjuntos;
DROP POLICY IF EXISTS "adjuntos: insert"    ON adjuntos;
DROP POLICY IF EXISTS "adjuntos: update (soft-delete y rename)" ON adjuntos;

CREATE POLICY "adjuntos: select"
  ON adjuntos FOR SELECT TO authenticated
  USING (
    empresa_id = (SELECT private.get_empresa_id())
    AND eliminado_en IS NULL
  );

CREATE POLICY "adjuntos: insert"
  ON adjuntos FOR INSERT TO authenticated
  WITH CHECK (empresa_id = (SELECT private.get_empresa_id()));

CREATE POLICY "adjuntos: update"
  ON adjuntos FOR UPDATE TO authenticated
  USING  (empresa_id = (SELECT private.get_empresa_id()))
  WITH CHECK (empresa_id = (SELECT private.get_empresa_id()));

GRANT SELECT, INSERT, UPDATE ON TABLE adjuntos TO authenticated;

-- ---------------------------------------------------------------------------
-- 6. Bucket Storage "adjuntos"
-- path: {empresa_id}/{entidad_tipo}/{entidad_id}/{ts}_{uuid}.ext
-- ---------------------------------------------------------------------------

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'adjuntos',
  'adjuntos',
  FALSE,
  52428800, -- 50 MB
  ARRAY[
    'image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/svg+xml',
    'application/pdf',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/vnd.ms-powerpoint',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'text/plain', 'text/csv',
    'application/zip',
    'application/xml', 'text/xml'
  ]
)
ON CONFLICT (id) DO NOTHING;

-- Storage policies (un solo bucket "adjuntos", RLS por primer segmento = empresa_id)
DROP POLICY IF EXISTS "adjuntos_storage: leer propios"          ON storage.objects;
DROP POLICY IF EXISTS "adjuntos_storage: subir en propia empresa" ON storage.objects;
DROP POLICY IF EXISTS "adjuntos_storage: actualizar propios"    ON storage.objects;
DROP POLICY IF EXISTS "adjuntos_storage: eliminar propios"      ON storage.objects;
DROP POLICY IF EXISTS "adjuntos_tenant_rw"                      ON storage.objects;

CREATE POLICY "adjuntos_storage: leer propios"
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'adjuntos'
    AND (storage.foldername(name))[1] = (SELECT private.get_empresa_id())::TEXT
  );

CREATE POLICY "adjuntos_storage: subir en propia empresa"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'adjuntos'
    AND (storage.foldername(name))[1] = (SELECT private.get_empresa_id())::TEXT
  );

CREATE POLICY "adjuntos_storage: actualizar propios"
  ON storage.objects FOR UPDATE TO authenticated
  USING (
    bucket_id = 'adjuntos'
    AND (storage.foldername(name))[1] = (SELECT private.get_empresa_id())::TEXT
  );

CREATE POLICY "adjuntos_storage: eliminar propios"
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'adjuntos'
    AND (storage.foldername(name))[1] = (SELECT private.get_empresa_id())::TEXT
  );

-- ---------------------------------------------------------------------------
-- 7. RPCs
-- ---------------------------------------------------------------------------

-- 7a. registrar_adjunto — llama DESPUÉS de subir a Storage
CREATE OR REPLACE FUNCTION public.registrar_adjunto(
  p_empresa_id      UUID,
  p_entidad_tipo    TEXT,
  p_entidad_id      UUID,
  p_nombre          TEXT,
  p_nombre_original TEXT,
  p_mime_type       TEXT,
  p_tamanio_bytes   BIGINT,
  p_storage_path    TEXT,
  p_descripcion     TEXT DEFAULT NULL
)
RETURNS adjuntos
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_adj adjuntos;
BEGIN
  IF p_empresa_id != (SELECT private.get_empresa_id()) THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;

  IF p_storage_path NOT LIKE p_empresa_id::TEXT || '/%' THEN
    RAISE EXCEPTION 'storage_path debe comenzar con empresa_id';
  END IF;

  INSERT INTO adjuntos (
    empresa_id, entidad_tipo, entidad_id,
    nombre, nombre_original, mime_type, tamanio_bytes,
    storage_path, descripcion, subido_por
  ) VALUES (
    p_empresa_id, p_entidad_tipo, p_entidad_id,
    p_nombre, p_nombre_original, p_mime_type, p_tamanio_bytes,
    p_storage_path, p_descripcion, auth.uid()
  )
  RETURNING * INTO v_adj;

  RETURN v_adj;
END;
$$;

-- 7b. get_adjuntos — listar adjuntos activos de una entidad
CREATE OR REPLACE FUNCTION public.get_adjuntos(
  p_entidad_tipo TEXT,
  p_entidad_id   UUID
)
RETURNS SETOF adjuntos
LANGUAGE sql SECURITY DEFINER SET search_path = public
AS $$
  SELECT * FROM adjuntos
  WHERE empresa_id   = (SELECT private.get_empresa_id())
    AND entidad_tipo = p_entidad_tipo
    AND entidad_id   = p_entidad_id
    AND eliminado_en IS NULL
  ORDER BY created_at DESC;
$$;

-- 7c. get_adjuntos_count — badge rápido
CREATE OR REPLACE FUNCTION public.get_adjuntos_count(
  p_entidad_tipo TEXT,
  p_entidad_id   UUID
)
RETURNS BIGINT
LANGUAGE sql SECURITY DEFINER SET search_path = public
AS $$
  SELECT COUNT(*) FROM adjuntos
  WHERE empresa_id   = (SELECT private.get_empresa_id())
    AND entidad_tipo = p_entidad_tipo
    AND entidad_id   = p_entidad_id
    AND eliminado_en IS NULL;
$$;

-- 7d. renombrar_adjunto — editar nombre visible sin tocar Storage
CREATE OR REPLACE FUNCTION public.renombrar_adjunto(
  p_adjunto_id UUID,
  p_nombre     TEXT
)
RETURNS adjuntos
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_adj adjuntos;
BEGIN
  UPDATE adjuntos SET nombre = p_nombre
  WHERE id = p_adjunto_id
    AND empresa_id = (SELECT private.get_empresa_id())
    AND eliminado_en IS NULL
  RETURNING * INTO v_adj;

  IF NOT FOUND THEN RAISE EXCEPTION 'Adjunto no encontrado'; END IF;
  RETURN v_adj;
END;
$$;

-- 7e. eliminar_adjunto — soft delete (el archivo en Storage se limpia aparte)
CREATE OR REPLACE FUNCTION public.eliminar_adjunto(
  p_adjunto_id UUID
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  UPDATE adjuntos
  SET eliminado_en = NOW(), eliminado_por = auth.uid()
  WHERE id = p_adjunto_id
    AND empresa_id = (SELECT private.get_empresa_id())
    AND eliminado_en IS NULL;

  IF NOT FOUND THEN RAISE EXCEPTION 'Adjunto no encontrado o ya eliminado'; END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.registrar_adjunto   TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_adjuntos        TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_adjuntos_count  TO authenticated;
GRANT EXECUTE ON FUNCTION public.renombrar_adjunto   TO authenticated;
GRANT EXECUTE ON FUNCTION public.eliminar_adjunto    TO authenticated;

-- ---------------------------------------------------------------------------
-- 8. Vista para cleanup job (Edge Function cleanup-storage)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE VIEW public.v_adjuntos_para_limpiar AS
  SELECT id, empresa_id, storage_bucket, storage_path
  FROM adjuntos
  WHERE eliminado_en IS NOT NULL
    AND eliminado_en < NOW() - INTERVAL '30 days';

GRANT SELECT ON public.v_adjuntos_para_limpiar TO authenticated;
