-- =============================================================================
-- 029: Fix performance advisors — FK indexes + RLS multiple_permissive_policies
-- =============================================================================
-- Fixes dos categorías de advisors de Supabase:
--
-- 1. unindexed_foreign_keys (INFO):
--    25 índices nuevos sobre FKs que faltaban en las tablas de foundation.
--    Los FKs a auth.users (nullable) usan índices parciales WHERE IS NOT NULL.
--
-- 2. multiple_permissive_policies (WARN):
--    7 tablas tenían policies FOR ALL conviviendo con policies FOR SELECT,
--    generando múltiples policies permisivas en SELECT (OR lógico indeseado).
--    Fix: reemplazar FOR ALL → FOR INSERT + FOR UPDATE + FOR DELETE separadas.
--    Cuando había 2x FOR ALL (ej: roles, roles_permisos), se combinaron en una
--    sola política de escritura con OR para evitar duplicados.
--
-- Nota: todas las políticas usan DROP IF EXISTS + CREATE para ser idempotentes.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- PARTE 1: Índices sobre Foreign Keys sin índice
-- ---------------------------------------------------------------------------

-- adjuntos
CREATE INDEX IF NOT EXISTS idx_adjuntos_subido_por
  ON adjuntos(subido_por)
  WHERE subido_por IS NOT NULL;

-- aprobacion_votos
CREATE INDEX IF NOT EXISTS idx_aprobacion_votos_empresa_id
  ON aprobacion_votos(empresa_id);

CREATE INDEX IF NOT EXISTS idx_aprobacion_votos_aprobador_id
  ON aprobacion_votos(aprobador_id)
  WHERE aprobador_id IS NOT NULL;

-- feature_flags
CREATE INDEX IF NOT EXISTS idx_feature_flags_created_by
  ON feature_flags(created_by)
  WHERE created_by IS NOT NULL;

-- feature_flag_usuarios
CREATE INDEX IF NOT EXISTS idx_feature_flag_usuarios_usuario_id
  ON feature_flag_usuarios(usuario_id);

-- import_jobs
CREATE INDEX IF NOT EXISTS idx_import_jobs_template_id
  ON import_jobs(template_id);

CREATE INDEX IF NOT EXISTS idx_import_jobs_usuario_id
  ON import_jobs(usuario_id)
  WHERE usuario_id IS NOT NULL;

-- invitaciones_pendientes
CREATE INDEX IF NOT EXISTS idx_invitaciones_rol_id
  ON invitaciones_pendientes(rol_id);

CREATE INDEX IF NOT EXISTS idx_invitaciones_invitado_por
  ON invitaciones_pendientes(invitado_por)
  WHERE invitado_por IS NOT NULL;

-- mfa_configuracion
CREATE INDEX IF NOT EXISTS idx_mfa_configuracion_updated_by
  ON mfa_configuracion(updated_by)
  WHERE updated_by IS NOT NULL;

-- modulo_dependencias
CREATE INDEX IF NOT EXISTS idx_modulo_dependencias_depende_de
  ON modulo_dependencias(depende_de);

-- modulos_empresa
CREATE INDEX IF NOT EXISTS idx_modulos_empresa_modulo_id
  ON modulos_empresa(modulo_id);

CREATE INDEX IF NOT EXISTS idx_modulos_empresa_activado_por
  ON modulos_empresa(activado_por)
  WHERE activado_por IS NOT NULL;

-- notificaciones_usuario
CREATE INDEX IF NOT EXISTS idx_notificaciones_usuario_id
  ON notificaciones_usuario(usuario_id);

-- registro_actividad
CREATE INDEX IF NOT EXISTS idx_registro_actividad_usuario_id
  ON registro_actividad(usuario_id)
  WHERE usuario_id IS NOT NULL;

-- roles_permisos
CREATE INDEX IF NOT EXISTS idx_roles_permisos_permiso_id
  ON roles_permisos(permiso_id);

-- saml_configuracion
CREATE INDEX IF NOT EXISTS idx_saml_configuracion_created_by
  ON saml_configuracion(created_by)
  WHERE created_by IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_saml_configuracion_rol_jit_default
  ON saml_configuracion(rol_jit_default)
  WHERE rol_jit_default IS NOT NULL;

-- saml_sesiones_log
CREATE INDEX IF NOT EXISTS idx_saml_sesiones_log_usuario_id
  ON saml_sesiones_log(usuario_id)
  WHERE usuario_id IS NOT NULL;

-- sesiones_usuario
CREATE INDEX IF NOT EXISTS idx_sesiones_usuario_empresa_id
  ON sesiones_usuario(empresa_id)
  WHERE empresa_id IS NOT NULL;

-- solicitudes_aprobacion
CREATE INDEX IF NOT EXISTS idx_solicitudes_aprobacion_regla_id
  ON solicitudes_aprobacion(regla_id);

CREATE INDEX IF NOT EXISTS idx_solicitudes_aprobacion_resuelto_por
  ON solicitudes_aprobacion(resuelto_por)
  WHERE resuelto_por IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_solicitudes_aprobacion_solicitante_id
  ON solicitudes_aprobacion(solicitante_id);

-- usuarios_empresa
CREATE INDEX IF NOT EXISTS idx_usuarios_empresa_invitado_por
  ON usuarios_empresa(invitado_por)
  WHERE invitado_por IS NOT NULL;

-- usuarios_empresa_roles
CREATE INDEX IF NOT EXISTS idx_usuarios_empresa_roles_asignado_por
  ON usuarios_empresa_roles(asignado_por)
  WHERE asignado_por IS NOT NULL;

-- ---------------------------------------------------------------------------
-- PARTE 2: Eliminar multiple_permissive_policies
-- ---------------------------------------------------------------------------
-- Patrón: FOR ALL conviviendo con FOR SELECT → SELECT tenía 2 policies OR-eadas.
-- Fix: separar FOR ALL en INSERT + UPDATE + DELETE (SELECT queda como la única).
-- Todas las secciones son idempotentes: DROP IF EXISTS antes de cada CREATE.
-- ---------------------------------------------------------------------------

-- ---- feature_flags ---------------------------------------------------------
-- Tenía: feature_flags_read (SELECT) + feature_flags_gestionar (ALL)
-- Fix:   drop gestionar → INSERT/UPDATE/DELETE por separado

DROP POLICY IF EXISTS feature_flags_gestionar ON feature_flags;
DROP POLICY IF EXISTS feature_flags_insert    ON feature_flags;
DROP POLICY IF EXISTS feature_flags_update    ON feature_flags;
DROP POLICY IF EXISTS feature_flags_delete    ON feature_flags;

CREATE POLICY feature_flags_insert ON feature_flags
  FOR INSERT TO authenticated
  WITH CHECK (empresa_id = (SELECT private.get_empresa_id()));

CREATE POLICY feature_flags_update ON feature_flags
  FOR UPDATE TO authenticated
  USING  (empresa_id = (SELECT private.get_empresa_id()))
  WITH CHECK (empresa_id = (SELECT private.get_empresa_id()));

CREATE POLICY feature_flags_delete ON feature_flags
  FOR DELETE TO authenticated
  USING  (empresa_id = (SELECT private.get_empresa_id()));

-- ---- import_templates ------------------------------------------------------
-- Tenía: import_templates_select (SELECT) + import_templates_write (ALL)

DROP POLICY IF EXISTS import_templates_write  ON import_templates;
DROP POLICY IF EXISTS import_templates_insert ON import_templates;
DROP POLICY IF EXISTS import_templates_update ON import_templates;
DROP POLICY IF EXISTS import_templates_delete ON import_templates;

CREATE POLICY import_templates_insert ON import_templates
  FOR INSERT TO authenticated
  WITH CHECK (empresa_id = (SELECT private.get_empresa_id()));

CREATE POLICY import_templates_update ON import_templates
  FOR UPDATE TO authenticated
  USING  (empresa_id = (SELECT private.get_empresa_id()))
  WITH CHECK (empresa_id = (SELECT private.get_empresa_id()));

CREATE POLICY import_templates_delete ON import_templates
  FOR DELETE TO authenticated
  USING  (empresa_id = (SELECT private.get_empresa_id()));

-- ---- roles -----------------------------------------------------------------
-- Tenía: roles_select (SELECT) + roles_empresa_gestionar (ALL) + roles_saas_admin (ALL)
-- Fix:   drop ambas ALL → un set INSERT/UPDATE/DELETE con OR de ambas condiciones

DROP POLICY IF EXISTS roles_empresa_gestionar ON roles;
DROP POLICY IF EXISTS roles_saas_admin        ON roles;
DROP POLICY IF EXISTS roles_insert            ON roles;
DROP POLICY IF EXISTS roles_update            ON roles;
DROP POLICY IF EXISTS roles_delete            ON roles;

CREATE POLICY roles_insert ON roles
  FOR INSERT TO authenticated
  WITH CHECK (
    (SELECT private.is_saas_admin())
    OR (
      empresa_id IS NOT NULL
      AND empresa_id = (SELECT private.get_empresa_id())
      AND (SELECT private.has_permission('plataforma.roles.gestionar'))
    )
  );

CREATE POLICY roles_update ON roles
  FOR UPDATE TO authenticated
  USING (
    (SELECT private.is_saas_admin())
    OR (
      empresa_id IS NOT NULL
      AND empresa_id = (SELECT private.get_empresa_id())
      AND (SELECT private.has_permission('plataforma.roles.gestionar'))
    )
  )
  WITH CHECK (
    (SELECT private.is_saas_admin())
    OR (
      empresa_id IS NOT NULL
      AND empresa_id = (SELECT private.get_empresa_id())
      AND (SELECT private.has_permission('plataforma.roles.gestionar'))
    )
  );

CREATE POLICY roles_delete ON roles
  FOR DELETE TO authenticated
  USING (
    (SELECT private.is_saas_admin())
    OR (
      empresa_id IS NOT NULL
      AND empresa_id = (SELECT private.get_empresa_id())
      AND (SELECT private.has_permission('plataforma.roles.gestionar'))
    )
  );

-- ---- roles_permisos --------------------------------------------------------
-- Tenía: roles_permisos_select (SELECT) + roles_permisos_gestionar (ALL) + roles_permisos_saas_admin (ALL)

DROP POLICY IF EXISTS roles_permisos_gestionar  ON roles_permisos;
DROP POLICY IF EXISTS roles_permisos_saas_admin ON roles_permisos;
DROP POLICY IF EXISTS roles_permisos_insert     ON roles_permisos;
DROP POLICY IF EXISTS roles_permisos_update     ON roles_permisos;
DROP POLICY IF EXISTS roles_permisos_delete     ON roles_permisos;

CREATE POLICY roles_permisos_insert ON roles_permisos
  FOR INSERT TO authenticated
  WITH CHECK (
    (SELECT private.is_saas_admin())
    OR (
      (SELECT private.has_permission('plataforma.roles.gestionar'))
      AND EXISTS (
        SELECT 1 FROM roles r
        WHERE r.id = roles_permisos.rol_id
          AND r.empresa_id = (SELECT private.get_empresa_id())
      )
    )
  );

CREATE POLICY roles_permisos_update ON roles_permisos
  FOR UPDATE TO authenticated
  USING (
    (SELECT private.is_saas_admin())
    OR (
      (SELECT private.has_permission('plataforma.roles.gestionar'))
      AND EXISTS (
        SELECT 1 FROM roles r
        WHERE r.id = roles_permisos.rol_id
          AND r.empresa_id = (SELECT private.get_empresa_id())
      )
    )
  )
  WITH CHECK (
    (SELECT private.is_saas_admin())
    OR (
      (SELECT private.has_permission('plataforma.roles.gestionar'))
      AND EXISTS (
        SELECT 1 FROM roles r
        WHERE r.id = roles_permisos.rol_id
          AND r.empresa_id = (SELECT private.get_empresa_id())
      )
    )
  );

CREATE POLICY roles_permisos_delete ON roles_permisos
  FOR DELETE TO authenticated
  USING (
    (SELECT private.is_saas_admin())
    OR (
      (SELECT private.has_permission('plataforma.roles.gestionar'))
      AND EXISTS (
        SELECT 1 FROM roles r
        WHERE r.id = roles_permisos.rol_id
          AND r.empresa_id = (SELECT private.get_empresa_id())
      )
    )
  );

-- ---- sesiones_usuario -------------------------------------------------------
-- Tenía: sesiones_propias (ALL, usuario_id = uid) + sesiones_admin_ver (SELECT, con permiso)
-- Fix:   SELECT unificado (propio OR admin) + INSERT/UPDATE/DELETE solo propias

DROP POLICY IF EXISTS sesiones_propias   ON sesiones_usuario;
DROP POLICY IF EXISTS sesiones_admin_ver ON sesiones_usuario;
DROP POLICY IF EXISTS sesiones_select    ON sesiones_usuario;
DROP POLICY IF EXISTS sesiones_insert    ON sesiones_usuario;
DROP POLICY IF EXISTS sesiones_update    ON sesiones_usuario;
DROP POLICY IF EXISTS sesiones_delete    ON sesiones_usuario;

CREATE POLICY sesiones_select ON sesiones_usuario
  FOR SELECT TO authenticated
  USING (
    usuario_id = (SELECT auth.uid())
    OR (
      empresa_id = (SELECT private.get_empresa_id())
      AND (SELECT private.has_permission('plataforma.seguridad.ver'))
    )
  );

CREATE POLICY sesiones_insert ON sesiones_usuario
  FOR INSERT TO authenticated
  WITH CHECK (usuario_id = (SELECT auth.uid()));

CREATE POLICY sesiones_update ON sesiones_usuario
  FOR UPDATE TO authenticated
  USING  (usuario_id = (SELECT auth.uid()))
  WITH CHECK (usuario_id = (SELECT auth.uid()));

CREATE POLICY sesiones_delete ON sesiones_usuario
  FOR DELETE TO authenticated
  USING  (usuario_id = (SELECT auth.uid()));

-- ---- usuarios_empresa -------------------------------------------------------
-- Tenía: ue_ver (SELECT) + ue_gestionar (ALL) [nombres originales]
-- Fix:   SELECT unificado + INSERT/UPDATE/DELETE separados

DROP POLICY IF EXISTS ue_ver                  ON usuarios_empresa;
DROP POLICY IF EXISTS ue_gestionar            ON usuarios_empresa;
DROP POLICY IF EXISTS ue_admin                ON usuarios_empresa;
DROP POLICY IF EXISTS usuarios_empresa_ver      ON usuarios_empresa;
DROP POLICY IF EXISTS usuarios_empresa_gestionar ON usuarios_empresa;
DROP POLICY IF EXISTS usuarios_empresa_select  ON usuarios_empresa;
DROP POLICY IF EXISTS usuarios_empresa_insert  ON usuarios_empresa;
DROP POLICY IF EXISTS usuarios_empresa_update  ON usuarios_empresa;
DROP POLICY IF EXISTS usuarios_empresa_delete  ON usuarios_empresa;

CREATE POLICY usuarios_empresa_select ON usuarios_empresa
  FOR SELECT TO authenticated
  USING (
    usuario_id = (SELECT auth.uid())
    OR (
      empresa_id = (SELECT private.get_empresa_id())
      AND (SELECT private.has_permission('plataforma.usuarios.ver'))
    )
  );

CREATE POLICY usuarios_empresa_insert ON usuarios_empresa
  FOR INSERT TO authenticated
  WITH CHECK (
    empresa_id = (SELECT private.get_empresa_id())
    AND (SELECT private.has_permission('plataforma.usuarios.gestionar'))
  );

CREATE POLICY usuarios_empresa_update ON usuarios_empresa
  FOR UPDATE TO authenticated
  USING (
    empresa_id = (SELECT private.get_empresa_id())
    AND (SELECT private.has_permission('plataforma.usuarios.gestionar'))
  )
  WITH CHECK (
    empresa_id = (SELECT private.get_empresa_id())
    AND (SELECT private.has_permission('plataforma.usuarios.gestionar'))
  );

CREATE POLICY usuarios_empresa_delete ON usuarios_empresa
  FOR DELETE TO authenticated
  USING (
    empresa_id = (SELECT private.get_empresa_id())
    AND (SELECT private.has_permission('plataforma.usuarios.gestionar'))
  );

-- ---- usuarios_empresa_roles -------------------------------------------------
-- Tenía: uer_select (SELECT) + uer_gestionar (ALL)
-- Fix:   drop gestionar → INSERT/UPDATE/DELETE por separado

DROP POLICY IF EXISTS uer_gestionar ON usuarios_empresa_roles;
DROP POLICY IF EXISTS uer_insert    ON usuarios_empresa_roles;
DROP POLICY IF EXISTS uer_update    ON usuarios_empresa_roles;
DROP POLICY IF EXISTS uer_delete    ON usuarios_empresa_roles;

CREATE POLICY uer_insert ON usuarios_empresa_roles
  FOR INSERT TO authenticated
  WITH CHECK (
    (SELECT private.has_permission('plataforma.usuarios.gestionar'))
    AND EXISTS (
      SELECT 1 FROM usuarios_empresa ue
      WHERE ue.id = usuarios_empresa_roles.usuario_empresa_id
        AND ue.empresa_id = (SELECT private.get_empresa_id())
    )
  );

CREATE POLICY uer_update ON usuarios_empresa_roles
  FOR UPDATE TO authenticated
  USING (
    (SELECT private.has_permission('plataforma.usuarios.gestionar'))
    AND EXISTS (
      SELECT 1 FROM usuarios_empresa ue
      WHERE ue.id = usuarios_empresa_roles.usuario_empresa_id
        AND ue.empresa_id = (SELECT private.get_empresa_id())
    )
  )
  WITH CHECK (
    (SELECT private.has_permission('plataforma.usuarios.gestionar'))
    AND EXISTS (
      SELECT 1 FROM usuarios_empresa ue
      WHERE ue.id = usuarios_empresa_roles.usuario_empresa_id
        AND ue.empresa_id = (SELECT private.get_empresa_id())
    )
  );

CREATE POLICY uer_delete ON usuarios_empresa_roles
  FOR DELETE TO authenticated
  USING (
    (SELECT private.has_permission('plataforma.usuarios.gestionar'))
    AND EXISTS (
      SELECT 1 FROM usuarios_empresa ue
      WHERE ue.id = usuarios_empresa_roles.usuario_empresa_id
        AND ue.empresa_id = (SELECT private.get_empresa_id())
    )
  );
