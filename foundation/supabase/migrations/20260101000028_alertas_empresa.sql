-- =============================================================================
-- 028: Sistema de alertas de empresa
-- =============================================================================
-- Alertas persistentes por empresa generadas por módulos o jobs del backend.
-- A diferencia de notificaciones_usuario (efímeras, por usuario), una alerta
-- permanece activa hasta que alguien la resuelva o ignore.
--
-- Ciclo de vida: activa → resuelta | ignorada
-- Deduplicación: índice único parcial en (empresa_id, codigo_alerta) WHERE activa
-- Visibilidad:   roles_destino NULL = todos; ['ADMIN','CONTADOR'] = solo esos roles
-- Realtime:      REPLICA IDENTITY FULL + publicación supabase_realtime
-- pg_cron:       expire horario (expira_at) + cleanup anual (resuelta/ignorada)
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Tabla principal
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS alertas_empresa (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID        NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,

  -- Origen
  origen_modulo   VARCHAR(50) NOT NULL DEFAULT 'sistema',
  codigo_alerta   VARCHAR(100),                -- Clave semántica para deduplicación
  registro_id     UUID,                        -- Soft ref (sin FK constraint)

  -- Contenido
  severidad       VARCHAR(20) NOT NULL DEFAULT 'warning',  -- info|warning|error|critical
  titulo          TEXT        NOT NULL,
  cuerpo          TEXT,
  datos           JSONB       NOT NULL DEFAULT '{}',
  accion_url      TEXT,

  -- Visibilidad por rol
  roles_destino   TEXT[],                      -- NULL = todos los roles

  -- Ciclo de vida
  estado          VARCHAR(20) NOT NULL DEFAULT 'activa',  -- activa|resuelta|ignorada
  expira_at       TIMESTAMPTZ,
  resuelta_at     TIMESTAMPTZ,
  resuelta_por    UUID REFERENCES auth.users(id),
  nota_resolucion TEXT,

  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ---------------------------------------------------------------------------
-- Índices
-- ---------------------------------------------------------------------------

-- Queries de alertas activas (ruta caliente)
CREATE INDEX IF NOT EXISTS idx_alertas_empresa_activas
  ON alertas_empresa(empresa_id, severidad, created_at DESC)
  WHERE estado = 'activa';

-- Deduplicación: una sola alerta activa por (empresa, codigo_alerta)
CREATE UNIQUE INDEX IF NOT EXISTS idx_alertas_dedup
  ON alertas_empresa(empresa_id, codigo_alerta)
  WHERE estado = 'activa' AND codigo_alerta IS NOT NULL;

-- FK resuelta_por → auth.users (parcial: solo filas ya resueltas)
CREATE INDEX IF NOT EXISTS idx_alertas_empresa_resuelta_por
  ON alertas_empresa(resuelta_por)
  WHERE resuelta_por IS NOT NULL;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

ALTER TABLE alertas_empresa ENABLE ROW LEVEL SECURITY;

-- Clientes solo pueden leer (filtrado por empresa + roles_destino).
-- auth.uid() envuelto en (SELECT ...) para evitar re-evaluación por fila (auth_rls_initplan).
CREATE POLICY alertas_select ON alertas_empresa
  FOR SELECT TO authenticated
  USING (
    empresa_id = (SELECT private.get_empresa_id())
    AND (
      roles_destino IS NULL
      OR EXISTS (
        SELECT 1
        FROM usuarios_empresa    ue
        JOIN usuarios_empresa_roles uer ON uer.usuario_empresa_id = ue.id
        JOIN roles               r   ON r.id = uer.rol_id
        WHERE ue.usuario_id = (SELECT auth.uid())
          AND ue.empresa_id = alertas_empresa.empresa_id
          AND ue.activo     = true
          AND r.codigo      = ANY(alertas_empresa.roles_destino)
      )
    )
  );

-- Bloquear cualquier escritura directa desde el cliente.
-- AS RESTRICTIVE + FOR ALL cubre INSERT/UPDATE/DELETE sin solaparse con alertas_select en SELECT.
CREATE POLICY alertas_no_client_write ON alertas_empresa
  AS RESTRICTIVE
  FOR ALL TO authenticated
  USING (false);

-- ---------------------------------------------------------------------------
-- Realtime
-- ---------------------------------------------------------------------------

ALTER TABLE alertas_empresa REPLICA IDENTITY FULL;
ALTER PUBLICATION supabase_realtime ADD TABLE alertas_empresa;

-- ---------------------------------------------------------------------------
-- RPCs
-- ---------------------------------------------------------------------------

-- ---- crear_alerta -----------------------------------------------------------
-- Solo invocable desde el backend (SECURITY DEFINER sin exposición al cliente).
-- Si p_codigo_alerta no es NULL hace upsert (deduplicación automática).

CREATE OR REPLACE FUNCTION public.crear_alerta(
  p_empresa_id    UUID,
  p_origen_modulo VARCHAR,
  p_severidad     VARCHAR,
  p_titulo        TEXT,
  p_cuerpo        TEXT         DEFAULT NULL,
  p_datos         JSONB        DEFAULT '{}',
  p_accion_url    TEXT         DEFAULT NULL,
  p_roles_destino TEXT[]       DEFAULT NULL,
  p_codigo_alerta VARCHAR      DEFAULT NULL,
  p_registro_id   UUID         DEFAULT NULL,
  p_expira_at     TIMESTAMPTZ  DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_id UUID;
BEGIN
  IF p_codigo_alerta IS NOT NULL THEN
    INSERT INTO alertas_empresa (
      empresa_id, origen_modulo, codigo_alerta, registro_id,
      severidad, titulo, cuerpo, datos, accion_url,
      roles_destino, expira_at
    ) VALUES (
      p_empresa_id, p_origen_modulo, p_codigo_alerta, p_registro_id,
      p_severidad, p_titulo, p_cuerpo, p_datos, p_accion_url,
      p_roles_destino, p_expira_at
    )
    ON CONFLICT (empresa_id, codigo_alerta)
    WHERE estado = 'activa' AND codigo_alerta IS NOT NULL
    DO UPDATE SET
      severidad  = EXCLUDED.severidad,
      titulo     = EXCLUDED.titulo,
      cuerpo     = EXCLUDED.cuerpo,
      datos      = EXCLUDED.datos,
      accion_url = EXCLUDED.accion_url,
      expira_at  = EXCLUDED.expira_at,
      updated_at = NOW()
    RETURNING id INTO v_id;
  ELSE
    INSERT INTO alertas_empresa (
      empresa_id, origen_modulo, registro_id,
      severidad, titulo, cuerpo, datos, accion_url,
      roles_destino, expira_at
    ) VALUES (
      p_empresa_id, p_origen_modulo, p_registro_id,
      p_severidad, p_titulo, p_cuerpo, p_datos, p_accion_url,
      p_roles_destino, p_expira_at
    )
    RETURNING id INTO v_id;
  END IF;

  RETURN v_id;
END;
$$;

-- ---- resolver_alerta --------------------------------------------------------

CREATE OR REPLACE FUNCTION public.resolver_alerta(
  p_alerta_id UUID,
  p_nota      TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
BEGIN
  IF NOT private.has_permission('administracion.empresa.editar') THEN
    RAISE EXCEPTION 'PERMISSION_DENIED';
  END IF;

  UPDATE alertas_empresa
  SET estado          = 'resuelta',
      resuelta_at     = NOW(),
      resuelta_por    = auth.uid(),
      nota_resolucion = p_nota,
      updated_at      = NOW()
  WHERE id         = p_alerta_id
    AND empresa_id = (SELECT private.get_empresa_id())
    AND estado     = 'activa';
END;
$$;

-- ---- ignorar_alerta ---------------------------------------------------------

CREATE OR REPLACE FUNCTION public.ignorar_alerta(
  p_alerta_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
BEGIN
  IF NOT private.has_permission('administracion.empresa.editar') THEN
    RAISE EXCEPTION 'PERMISSION_DENIED';
  END IF;

  UPDATE alertas_empresa
  SET estado     = 'ignorada',
      updated_at = NOW()
  WHERE id         = p_alerta_id
    AND empresa_id = (SELECT private.get_empresa_id())
    AND estado     = 'activa';
END;
$$;

-- ---- get_alertas_activas ----------------------------------------------------
-- Devuelve alertas activas visibles para el rol del usuario, ordenadas por
-- severidad (critical primero) y fecha de creación.

CREATE OR REPLACE FUNCTION public.get_alertas_activas(
  p_limite  INTEGER DEFAULT 50,
  p_offset  INTEGER DEFAULT 0
)
RETURNS TABLE (
  id            UUID,
  origen_modulo VARCHAR,
  codigo_alerta VARCHAR,
  registro_id   UUID,
  severidad     VARCHAR,
  titulo        TEXT,
  cuerpo        TEXT,
  datos         JSONB,
  accion_url    TEXT,
  roles_destino TEXT[],
  expira_at     TIMESTAMPTZ,
  created_at    TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public, private
AS $$
BEGIN
  RETURN QUERY
  SELECT
    a.id, a.origen_modulo, a.codigo_alerta, a.registro_id,
    a.severidad, a.titulo, a.cuerpo, a.datos, a.accion_url,
    a.roles_destino, a.expira_at, a.created_at
  FROM alertas_empresa a
  WHERE a.empresa_id = (SELECT private.get_empresa_id())
    AND a.estado = 'activa'
    AND (a.expira_at IS NULL OR a.expira_at > NOW())
    AND (
      a.roles_destino IS NULL
      OR EXISTS (
        SELECT 1
        FROM usuarios_empresa    ue
        JOIN usuarios_empresa_roles uer ON uer.usuario_empresa_id = ue.id
        JOIN roles               r   ON r.id = uer.rol_id
        WHERE ue.usuario_id = auth.uid()
          AND ue.empresa_id = a.empresa_id
          AND ue.activo     = true
          AND r.codigo      = ANY(a.roles_destino)
      )
    )
  ORDER BY
    CASE a.severidad
      WHEN 'critical' THEN 1
      WHEN 'error'    THEN 2
      WHEN 'warning'  THEN 3
      ELSE 4
    END,
    a.created_at DESC
  LIMIT p_limite OFFSET p_offset;
END;
$$;

-- ---- get_count_alertas_activas ----------------------------------------------
-- Conteo para el badge del header (sin paginación).

CREATE OR REPLACE FUNCTION public.get_count_alertas_activas()
RETURNS INTEGER
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM alertas_empresa a
  WHERE a.empresa_id = (SELECT private.get_empresa_id())
    AND a.estado = 'activa'
    AND (a.expira_at IS NULL OR a.expira_at > NOW())
    AND (
      a.roles_destino IS NULL
      OR EXISTS (
        SELECT 1
        FROM usuarios_empresa    ue
        JOIN usuarios_empresa_roles uer ON uer.usuario_empresa_id = ue.id
        JOIN roles               r   ON r.id = uer.rol_id
        WHERE ue.usuario_id = auth.uid()
          AND ue.empresa_id = a.empresa_id
          AND ue.activo     = true
          AND r.codigo      = ANY(a.roles_destino)
      )
    );

  RETURN COALESCE(v_count, 0);
END;
$$;

-- ---------------------------------------------------------------------------
-- pg_cron jobs
-- ---------------------------------------------------------------------------

-- Expirar alertas vencidas (cada hora)
SELECT cron.schedule(
  'pilar_expire_alertas',
  '0 * * * *',
  $$
    UPDATE alertas_empresa
    SET estado = 'ignorada', updated_at = NOW()
    WHERE estado   = 'activa'
      AND expira_at IS NOT NULL
      AND expira_at < NOW();
  $$
);

-- Limpiar alertas resueltas/ignoradas con más de 1 año (diario a las 03:30)
SELECT cron.schedule(
  'pilar_cleanup_old_alertas',
  '30 3 * * *',
  $$
    DELETE FROM alertas_empresa
    WHERE estado IN ('resuelta', 'ignorada')
      AND updated_at < NOW() - INTERVAL '1 year';
  $$
);
