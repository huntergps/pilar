-- Migration: dashboard_get_kpis
-- Returns key KPI counts for the authenticated user's empresa.
-- com_conversaciones is optional (module-gated) — checked dynamically.

CREATE OR REPLACE FUNCTION dashboard_get_kpis()
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_empresa UUID := private.get_empresa_id();
  v_conv    INTEGER := 0;
BEGIN
  -- com_conversaciones belongs to the comunicacion module; may not be installed
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'com_conversaciones'
  ) THEN
    EXECUTE format(
      'SELECT COUNT(*)::INTEGER FROM com_conversaciones
       WHERE empresa_id = %L AND activa = true', v_empresa
    ) INTO v_conv;
  END IF;

  RETURN jsonb_build_object(
    'contactos',              (SELECT COUNT(*)::INTEGER FROM contactos       WHERE empresa_id = v_empresa AND activo = true),
    'productos',              (SELECT COUNT(*)::INTEGER FROM productos        WHERE empresa_id = v_empresa AND activo = true),
    'conversaciones_activas', v_conv,
    'usuarios_activos',       (SELECT COUNT(*)::INTEGER FROM usuarios_empresa WHERE empresa_id = v_empresa AND activo = true),
    'modulos_activos',        (SELECT COUNT(*)::INTEGER FROM empresa_modulos  WHERE empresa_id = v_empresa AND activo = true)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION dashboard_get_kpis() TO authenticated;
