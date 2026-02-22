# Solicitudes de Cotización (RFQ)


### Descripcion Funcional

Las Solicitudes de Cotizacion (RFQ) permiten al departamento de compras enviar una solicitud formal a multiples proveedores simultaneamente para obtener cotizaciones sobre productos o servicios requeridos. El sistema facilita la comparacion objetiva de las respuestas recibidas y la adjudicacion total o parcial a uno o varios proveedores, generando automaticamente las ordenes de compra correspondientes.

**Flujo completo:**

```
Necesidad de compra (manual o desde requisicion)
  |
  v
Crear RFQ (seleccionar productos + cantidades)
  |
  v
Agregar proveedores invitados (N proveedores)
  |
  v
Enviar RFQ (email multi-canal: email/WhatsApp/Telegram)
  |
  v
Registrar respuestas de proveedores (precio, plazo, condiciones)
  |
  v
Generar cuadro comparativo automatico
  |
  v
Adjudicar (total a 1 proveedor O parcial a N proveedores)
  |
  v
Generar OC(s) automaticamente desde adjudicacion
  |
  v
Cerrar RFQ
```

**Reglas de negocio:**

1. Una RFQ puede originarse desde una requisicion aprobada o crearse independientemente
2. Minimo 1 proveedor invitado (recomendado 3+ para comparacion efectiva)
3. El cuadro comparativo muestra precio unitario, precio total, plazo de entrega y condiciones por proveedor
4. La adjudicacion parcial permite asignar diferentes productos a diferentes proveedores
5. Al adjudicar, se generan OCs automaticamente con precios de la cotizacion ganadora
6. Los proveedores no adjudicados reciben notificacion de rechazo (opcional, configurable)
7. El tiempo de respuesta de cada proveedor se registra para alimentar el scoring
8. La fecha limite de respuesta es obligatoria; pasada la fecha, las respuestas se marcan como extemporaneas
9. Se puede reabrir una RFQ cerrada para solicitar nuevas cotizaciones
10. Integracion con evaluacion de proveedores: priorizar invitacion a proveedores con mejor score

### Modelo de Datos SQL

```sql
-- ============================================
-- SOLICITUDES DE COTIZACION (RFQ) - AMPLIACION
-- Extiende las tablas base definidas en seccion 8 del INFORME
-- ============================================

-- NOTA: Las tablas solicitudes_cotizacion, solicitud_cotizacion_proveedores
-- y solicitud_cotizacion_lineas ya existen en el INFORME (seccion 8).
-- Aqui se amplian con campos adicionales y se agregan tablas complementarias.

-- Campos adicionales para solicitudes_cotizacion (ALTER TABLE)
ALTER TABLE solicitudes_cotizacion
  ADD COLUMN titulo              VARCHAR(200),
  ADD COLUMN tipo_adjudicacion   VARCHAR(20) DEFAULT 'TOTAL',
    -- TOTAL: se adjudica todo a un solo proveedor
    -- PARCIAL: se puede adjudicar cada producto a un proveedor diferente
  ADD COLUMN criterio_seleccion  VARCHAR(20) DEFAULT 'PRECIO',
    -- PRECIO: menor precio total
    -- SCORE: mejor score del proveedor (requiere modulo evaluacion)
    -- MANUAL: decision manual del comprador
  ADD COLUMN moneda              VARCHAR(10) DEFAULT 'USD',
  ADD COLUMN notas_internas      TEXT,
  ADD COLUMN adjudicado_por      UUID REFERENCES auth.users(id),
  ADD COLUMN fecha_adjudicacion  TIMESTAMPTZ,
  ADD COLUMN notificar_rechazo   BOOLEAN DEFAULT false,
  ADD COLUMN updated_at          TIMESTAMPTZ DEFAULT now();

-- Campos adicionales para solicitud_cotizacion_proveedores
ALTER TABLE solicitud_cotizacion_proveedores
  ADD COLUMN fecha_envio         TIMESTAMPTZ,
  ADD COLUMN metodo_envio        VARCHAR(20) DEFAULT 'EMAIL',
    -- EMAIL, WHATSAPP, TELEGRAM, MANUAL
  ADD COLUMN tiempo_respuesta_horas DECIMAL(10,2),
  ADD COLUMN es_extemporanea     BOOLEAN DEFAULT false,
  ADD COLUMN motivo_rechazo      TEXT,
  ADD COLUMN score_proveedor     DECIMAL(5,2);  -- Score al momento de la solicitud (snapshot)

-- Campos adicionales para solicitud_cotizacion_lineas
ALTER TABLE solicitud_cotizacion_lineas
  ADD COLUMN descuento           DECIMAL(5,2) DEFAULT 0,
  ADD COLUMN subtotal            DECIMAL(14,2),
  ADD COLUMN presentacion_id     UUID REFERENCES producto_presentaciones(id),
  ADD COLUMN unidad_medida_id    UUID REFERENCES unidades_medida(id);

-- ============================================
-- PRODUCTOS SOLICITADOS EN LA RFQ (lista maestra)
-- Lista unica de productos que se solicitan en la RFQ.
-- Cada proveedor cotiza sobre estos mismos productos.
-- ============================================

CREATE TABLE solicitud_cotizacion_productos (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  solicitud_id    UUID NOT NULL REFERENCES solicitudes_cotizacion(id) ON DELETE CASCADE,
  producto_id     UUID NOT NULL REFERENCES productos(id),
  cantidad        DECIMAL(18,6) NOT NULL,
  presentacion_id UUID REFERENCES producto_presentaciones(id),
  unidad_medida_id UUID REFERENCES unidades_medida(id),
  especificaciones TEXT,                           -- Requisitos especificos para este producto
  orden           INTEGER DEFAULT 0,
  UNIQUE(solicitud_id, producto_id)
);

-- ============================================
-- ADJUDICACION DE RFQ
-- Registra que proveedor gano cada producto (adjudicacion parcial)
-- ============================================

CREATE TABLE solicitud_cotizacion_adjudicaciones (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  solicitud_id    UUID NOT NULL REFERENCES solicitudes_cotizacion(id) ON DELETE CASCADE,
  producto_id     UUID NOT NULL REFERENCES productos(id),
  proveedor_id    UUID NOT NULL REFERENCES contactos(id),
  solicitud_proveedor_id UUID NOT NULL REFERENCES solicitud_cotizacion_proveedores(id),
  linea_cotizacion_id    UUID NOT NULL REFERENCES solicitud_cotizacion_lineas(id),
  cantidad        DECIMAL(18,6) NOT NULL,
  precio_unitario DECIMAL(14,6) NOT NULL,
  descuento       DECIMAL(5,2) DEFAULT 0,
  subtotal        DECIMAL(14,2) NOT NULL,
  plazo_entrega_dias INTEGER,
  orden_compra_id UUID REFERENCES ordenes_compra(id),  -- OC generada
  motivo          TEXT,                                  -- Justificacion de la adjudicacion
  adjudicado_por  UUID NOT NULL REFERENCES auth.users(id),
  fecha           TIMESTAMPTZ DEFAULT now(),
  UNIQUE(solicitud_id, producto_id)                     -- Un producto solo se adjudica una vez
);

-- Indices
CREATE INDEX idx_rfq_productos_solicitud ON solicitud_cotizacion_productos(solicitud_id);
CREATE INDEX idx_rfq_adjudicaciones_solicitud ON solicitud_cotizacion_adjudicaciones(solicitud_id);
CREATE INDEX idx_rfq_adjudicaciones_proveedor ON solicitud_cotizacion_adjudicaciones(proveedor_id);
CREATE INDEX idx_rfq_adjudicaciones_oc ON solicitud_cotizacion_adjudicaciones(orden_compra_id);

-- RLS
ALTER TABLE solicitud_cotizacion_productos ENABLE ROW LEVEL SECURITY;
ALTER TABLE solicitud_cotizacion_adjudicaciones ENABLE ROW LEVEL SECURITY;

-- RLS via JOIN al padre (solicitudes_cotizacion tiene empresa_id)
CREATE POLICY "tenant_via_solicitud" ON solicitud_cotizacion_productos
  FOR ALL TO authenticated
  USING (solicitud_id IN (
    SELECT id FROM solicitudes_cotizacion
    WHERE empresa_id = (SELECT private.get_empresa_id())
  ));

CREATE POLICY "tenant_via_solicitud" ON solicitud_cotizacion_adjudicaciones
  FOR ALL TO authenticated
  USING (solicitud_id IN (
    SELECT id FROM solicitudes_cotizacion
    WHERE empresa_id = (SELECT private.get_empresa_id())
  ));
```

### Funciones PostgreSQL Principales

```sql
-- ============================================
-- ENVIAR RFQ A PROVEEDORES
-- Marca la solicitud como ENVIADA y notifica a cada proveedor
-- ============================================
CREATE OR REPLACE FUNCTION send_rfq(
  p_solicitud_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_sol RECORD;
  v_prov RECORD;
  v_productos JSONB;
  v_resultado JSONB := '{"enviados": 0, "errores": []}'::JSONB;
  v_count INTEGER := 0;
BEGIN
  -- 1. Validar estado
  SELECT * INTO v_sol FROM solicitudes_cotizacion WHERE id = p_solicitud_id;
  IF v_sol IS NULL THEN
    RAISE EXCEPTION 'Solicitud no encontrada';
  END IF;
  IF v_sol.estado NOT IN ('BORRADOR', 'ENVIADA') THEN
    RAISE EXCEPTION 'Solo se pueden enviar solicitudes en estado BORRADOR o ENVIADA';
  END IF;

  -- 2. Validar que hay productos
  IF NOT EXISTS (SELECT 1 FROM solicitud_cotizacion_productos WHERE solicitud_id = p_solicitud_id) THEN
    RAISE EXCEPTION 'La solicitud no tiene productos';
  END IF;

  -- 3. Validar que hay proveedores
  IF NOT EXISTS (SELECT 1 FROM solicitud_cotizacion_proveedores WHERE solicitud_id = p_solicitud_id) THEN
    RAISE EXCEPTION 'La solicitud no tiene proveedores invitados';
  END IF;

  -- 4. Construir lista de productos para la notificacion
  SELECT jsonb_agg(jsonb_build_object(
    'producto', p.descripcion,
    'cantidad', sp.cantidad,
    'especificaciones', sp.especificaciones
  ))
  INTO v_productos
  FROM solicitud_cotizacion_productos sp
  JOIN productos p ON p.id = sp.producto_id
  WHERE sp.solicitud_id = p_solicitud_id;

  -- 5. Marcar cada proveedor como enviado y notificar via Module Bus
  FOR v_prov IN
    SELECT scp.*, c.razon_social, c.email, c.whatsapp, c.telegram_chat_id
    FROM solicitud_cotizacion_proveedores scp
    JOIN contactos c ON c.id = scp.proveedor_id
    WHERE scp.solicitud_id = p_solicitud_id
      AND scp.estado = 'PENDIENTE'
  LOOP
    UPDATE solicitud_cotizacion_proveedores
    SET fecha_envio = now(), estado = 'PENDIENTE'
    WHERE id = v_prov.id;

    -- Notificar via Module Service Bus
    PERFORM module_bus.send_notification(
      p_empresa_id := v_sol.empresa_id,
      p_tipo := 'RFQ_ENVIADA',
      p_destinatario_email := v_prov.email,
      p_destinatario_whatsapp := v_prov.whatsapp,
      p_destinatario_telegram := v_prov.telegram_chat_id,
      p_datos := jsonb_build_object(
        'solicitud_numero', v_sol.numero,
        'fecha_limite', v_sol.fecha_limite,
        'productos', v_productos
      )
    );

    v_count := v_count + 1;
  END LOOP;

  -- 6. Actualizar estado de la solicitud
  UPDATE solicitudes_cotizacion
  SET estado = 'ENVIADA', updated_at = now()
  WHERE id = p_solicitud_id;

  -- 7. Log de auditoria
  PERFORM module_bus.log_activity(
    p_empresa_id := v_sol.empresa_id,
    p_entidad_tipo := 'solicitudes_cotizacion',
    p_entidad_id := p_solicitud_id,
    p_accion := 'RFQ_ENVIADA',
    p_detalle := jsonb_build_object('proveedores_notificados', v_count)
  );

  RETURN jsonb_build_object('enviados', v_count);
END;
$$;

-- ============================================
-- REGISTRAR RESPUESTA DE PROVEEDOR
-- Registra precios y condiciones cotizados por un proveedor
-- ============================================
CREATE OR REPLACE FUNCTION register_rfq_response(
  p_solicitud_proveedor_id UUID,
  p_lineas JSONB,           -- [{producto_id, precio_unitario, descuento, plazo_entrega_dias, observaciones}]
  p_total DECIMAL DEFAULT NULL,
  p_plazo_entrega_dias INTEGER DEFAULT NULL,
  p_condiciones_pago TEXT DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_sp RECORD;
  v_sol RECORD;
  v_linea JSONB;
  v_es_extemporanea BOOLEAN := false;
  v_horas DECIMAL;
BEGIN
  -- 1. Obtener datos del proveedor en la solicitud
  SELECT * INTO v_sp FROM solicitud_cotizacion_proveedores WHERE id = p_solicitud_proveedor_id;
  IF v_sp IS NULL THEN
    RAISE EXCEPTION 'Proveedor no encontrado en la solicitud';
  END IF;

  SELECT * INTO v_sol FROM solicitudes_cotizacion WHERE id = v_sp.solicitud_id;

  -- 2. Verificar si es extemporanea
  IF v_sol.fecha_limite < CURRENT_DATE THEN
    v_es_extemporanea := true;
  END IF;

  -- 3. Calcular tiempo de respuesta
  IF v_sp.fecha_envio IS NOT NULL THEN
    v_horas := EXTRACT(EPOCH FROM (now() - v_sp.fecha_envio)) / 3600.0;
  END IF;

  -- 4. Actualizar cabecera del proveedor
  UPDATE solicitud_cotizacion_proveedores SET
    fecha_respuesta = now(),
    total = p_total,
    plazo_entrega_dias = p_plazo_entrega_dias,
    condiciones_pago = p_condiciones_pago,
    estado = 'RECIBIDA',
    es_extemporanea = v_es_extemporanea,
    tiempo_respuesta_horas = v_horas
  WHERE id = p_solicitud_proveedor_id;

  -- 5. Insertar lineas de cotizacion
  FOR v_linea IN SELECT * FROM jsonb_array_elements(p_lineas)
  LOOP
    INSERT INTO solicitud_cotizacion_lineas (
      solicitud_proveedor_id, producto_id, cantidad,
      precio_unitario, descuento, plazo_entrega_dias, observaciones, subtotal
    ) VALUES (
      p_solicitud_proveedor_id,
      (v_linea->>'producto_id')::UUID,
      COALESCE(
        (v_linea->>'cantidad')::DECIMAL,
        (SELECT cantidad FROM solicitud_cotizacion_productos
         WHERE solicitud_id = v_sp.solicitud_id
           AND producto_id = (v_linea->>'producto_id')::UUID)
      ),
      (v_linea->>'precio_unitario')::DECIMAL,
      COALESCE((v_linea->>'descuento')::DECIMAL, 0),
      (v_linea->>'plazo_entrega_dias')::INTEGER,
      v_linea->>'observaciones',
      ROUND(
        (v_linea->>'cantidad')::DECIMAL *
        (v_linea->>'precio_unitario')::DECIMAL *
        (1 - COALESCE((v_linea->>'descuento')::DECIMAL, 0) / 100), 2
      )
    );
  END LOOP;

  -- 6. Recalcular total si no se proporciono
  IF p_total IS NULL THEN
    UPDATE solicitud_cotizacion_proveedores SET
      total = (SELECT COALESCE(SUM(subtotal), 0)
               FROM solicitud_cotizacion_lineas
               WHERE solicitud_proveedor_id = p_solicitud_proveedor_id)
    WHERE id = p_solicitud_proveedor_id;
  END IF;

  RETURN p_solicitud_proveedor_id;
END;
$$;

-- ============================================
-- CUADRO COMPARATIVO DE COTIZACIONES (AMPLIADO)
-- Reemplaza la funcion placeholder del INFORME
-- ============================================
CREATE OR REPLACE FUNCTION compare_rfq_responses(
  p_solicitud_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_productos JSONB := '[]'::JSONB;
  v_resumen JSONB := '[]'::JSONB;
  v_prod RECORD;
  v_provs JSONB;
  v_mejor_precio UUID;
  v_mejor_plazo UUID;
BEGIN
  -- Construir matriz comparativa producto x proveedor
  FOR v_prod IN
    SELECT sp.producto_id, p.descripcion AS nombre, sp.cantidad
    FROM solicitud_cotizacion_productos sp
    JOIN productos p ON p.id = sp.producto_id
    WHERE sp.solicitud_id = p_solicitud_id
    ORDER BY sp.orden
  LOOP
    -- Obtener cotizaciones de todos los proveedores para este producto
    SELECT jsonb_agg(
      jsonb_build_object(
        'proveedor_id', scp.proveedor_id,
        'razon_social', c.razon_social,
        'score', scp.score_proveedor,
        'precio_unitario', scl.precio_unitario,
        'descuento', scl.descuento,
        'precio_neto', ROUND(scl.precio_unitario * (1 - COALESCE(scl.descuento, 0) / 100), 6),
        'subtotal', scl.subtotal,
        'plazo_dias', COALESCE(scl.plazo_entrega_dias, scp.plazo_entrega_dias),
        'tiempo_respuesta_horas', scp.tiempo_respuesta_horas,
        'es_extemporanea', scp.es_extemporanea,
        'observaciones', scl.observaciones
      ) ORDER BY scl.precio_unitario ASC NULLS LAST
    )
    INTO v_provs
    FROM solicitud_cotizacion_proveedores scp
    JOIN solicitud_cotizacion_lineas scl ON scl.solicitud_proveedor_id = scp.id
    JOIN contactos c ON c.id = scp.proveedor_id
    WHERE scp.solicitud_id = p_solicitud_id
      AND scp.estado = 'RECIBIDA'
      AND scl.producto_id = v_prod.producto_id;

    -- Determinar mejor precio y mejor plazo
    SELECT scp.proveedor_id INTO v_mejor_precio
    FROM solicitud_cotizacion_proveedores scp
    JOIN solicitud_cotizacion_lineas scl ON scl.solicitud_proveedor_id = scp.id
    WHERE scp.solicitud_id = p_solicitud_id AND scp.estado = 'RECIBIDA'
      AND scl.producto_id = v_prod.producto_id AND scl.precio_unitario IS NOT NULL
    ORDER BY scl.precio_unitario * (1 - COALESCE(scl.descuento, 0) / 100) ASC
    LIMIT 1;

    SELECT scp.proveedor_id INTO v_mejor_plazo
    FROM solicitud_cotizacion_proveedores scp
    JOIN solicitud_cotizacion_lineas scl ON scl.solicitud_proveedor_id = scp.id
    WHERE scp.solicitud_id = p_solicitud_id AND scp.estado = 'RECIBIDA'
      AND scl.producto_id = v_prod.producto_id
      AND COALESCE(scl.plazo_entrega_dias, scp.plazo_entrega_dias) IS NOT NULL
    ORDER BY COALESCE(scl.plazo_entrega_dias, scp.plazo_entrega_dias) ASC
    LIMIT 1;

    v_productos := v_productos || jsonb_build_object(
      'producto_id', v_prod.producto_id,
      'nombre', v_prod.nombre,
      'cantidad', v_prod.cantidad,
      'proveedores', COALESCE(v_provs, '[]'::JSONB),
      'mejor_precio_proveedor_id', v_mejor_precio,
      'mejor_plazo_proveedor_id', v_mejor_plazo
    );
  END LOOP;

  -- Resumen por proveedor (totales)
  SELECT jsonb_agg(
    jsonb_build_object(
      'proveedor_id', scp.proveedor_id,
      'razon_social', c.razon_social,
      'total_general', scp.total,
      'plazo_max', scp.plazo_entrega_dias,
      'score', scp.score_proveedor,
      'tiempo_respuesta_horas', scp.tiempo_respuesta_horas,
      'condiciones_pago', scp.condiciones_pago,
      'productos_cotizados', (
        SELECT COUNT(*) FROM solicitud_cotizacion_lineas scl
        WHERE scl.solicitud_proveedor_id = scp.id AND scl.precio_unitario IS NOT NULL
      )
    ) ORDER BY scp.total ASC NULLS LAST
  )
  INTO v_resumen
  FROM solicitud_cotizacion_proveedores scp
  JOIN contactos c ON c.id = scp.proveedor_id
  WHERE scp.solicitud_id = p_solicitud_id AND scp.estado = 'RECIBIDA';

  RETURN jsonb_build_object(
    'solicitud_id', p_solicitud_id,
    'productos', v_productos,
    'resumen_proveedores', COALESCE(v_resumen, '[]'::JSONB),
    'total_productos', jsonb_array_length(v_productos),
    'total_proveedores_respondieron', jsonb_array_length(COALESCE(v_resumen, '[]'::JSONB))
  );
END;
$$;

-- ============================================
-- ADJUDICAR RFQ (TOTAL O PARCIAL)
-- Crea adjudicaciones y genera OC(s) automaticamente
-- ============================================
CREATE OR REPLACE FUNCTION adjudicate_rfq(
  p_solicitud_id UUID,
  p_adjudicaciones JSONB,  -- [{producto_id, proveedor_id, cantidad, precio_unitario, descuento, motivo}]
  p_adjudicado_por UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_sol RECORD;
  v_adj JSONB;
  v_sp_id UUID;
  v_linea_id UUID;
  v_ocs_creadas UUID[] := '{}';
  v_proveedor_id UUID;
  v_oc_id UUID;
  v_prov_ids UUID[];
  v_adj_id UUID;
BEGIN
  -- 1. Validar solicitud
  SELECT * INTO v_sol FROM solicitudes_cotizacion WHERE id = p_solicitud_id;
  IF v_sol.estado NOT IN ('ENVIADA', 'CERRADA') THEN
    RAISE EXCEPTION 'La solicitud debe estar ENVIADA o CERRADA para adjudicar';
  END IF;

  -- 2. Registrar cada adjudicacion
  FOR v_adj IN SELECT * FROM jsonb_array_elements(p_adjudicaciones)
  LOOP
    v_proveedor_id := (v_adj->>'proveedor_id')::UUID;

    -- Buscar solicitud_proveedor_id
    SELECT id INTO v_sp_id
    FROM solicitud_cotizacion_proveedores
    WHERE solicitud_id = p_solicitud_id AND proveedor_id = v_proveedor_id;

    -- Buscar linea de cotizacion
    SELECT scl.id INTO v_linea_id
    FROM solicitud_cotizacion_lineas scl
    WHERE scl.solicitud_proveedor_id = v_sp_id
      AND scl.producto_id = (v_adj->>'producto_id')::UUID;

    INSERT INTO solicitud_cotizacion_adjudicaciones (
      solicitud_id, producto_id, proveedor_id,
      solicitud_proveedor_id, linea_cotizacion_id,
      cantidad, precio_unitario, descuento, subtotal,
      plazo_entrega_dias, motivo, adjudicado_por
    ) VALUES (
      p_solicitud_id,
      (v_adj->>'producto_id')::UUID,
      v_proveedor_id,
      v_sp_id,
      v_linea_id,
      (v_adj->>'cantidad')::DECIMAL,
      (v_adj->>'precio_unitario')::DECIMAL,
      COALESCE((v_adj->>'descuento')::DECIMAL, 0),
      ROUND(
        (v_adj->>'cantidad')::DECIMAL *
        (v_adj->>'precio_unitario')::DECIMAL *
        (1 - COALESCE((v_adj->>'descuento')::DECIMAL, 0) / 100), 2
      ),
      (v_adj->>'plazo_entrega_dias')::INTEGER,
      v_adj->>'motivo',
      p_adjudicado_por
    )
    RETURNING id INTO v_adj_id;

    -- Marcar proveedor como SELECCIONADA
    UPDATE solicitud_cotizacion_proveedores
    SET estado = 'SELECCIONADA'
    WHERE id = v_sp_id AND estado != 'SELECCIONADA';
  END LOOP;

  -- 3. Marcar proveedores no adjudicados como RECHAZADA
  UPDATE solicitud_cotizacion_proveedores
  SET estado = 'RECHAZADA'
  WHERE solicitud_id = p_solicitud_id
    AND estado = 'RECIBIDA'
    AND id NOT IN (
      SELECT DISTINCT solicitud_proveedor_id
      FROM solicitud_cotizacion_adjudicaciones
      WHERE solicitud_id = p_solicitud_id
    );

  -- 4. Generar OC por cada proveedor adjudicado
  SELECT ARRAY_AGG(DISTINCT proveedor_id) INTO v_prov_ids
  FROM solicitud_cotizacion_adjudicaciones
  WHERE solicitud_id = p_solicitud_id;

  FOREACH v_proveedor_id IN ARRAY v_prov_ids
  LOOP
    v_oc_id := generate_po_from_rfq(p_solicitud_id, v_proveedor_id);
    v_ocs_creadas := v_ocs_creadas || v_oc_id;
  END LOOP;

  -- 5. Cerrar la solicitud
  UPDATE solicitudes_cotizacion SET
    estado = 'CERRADA',
    adjudicado_por = p_adjudicado_por,
    fecha_adjudicacion = now(),
    updated_at = now()
  WHERE id = p_solicitud_id;

  -- 6. Log de auditoria
  PERFORM module_bus.log_activity(
    p_empresa_id := v_sol.empresa_id,
    p_entidad_tipo := 'solicitudes_cotizacion',
    p_entidad_id := p_solicitud_id,
    p_accion := 'RFQ_ADJUDICADA',
    p_detalle := jsonb_build_object(
      'ocs_generadas', v_ocs_creadas,
      'proveedores_adjudicados', v_prov_ids
    )
  );

  RETURN jsonb_build_object(
    'solicitud_id', p_solicitud_id,
    'ordenes_compra', to_jsonb(v_ocs_creadas),
    'proveedores_adjudicados', array_length(v_prov_ids, 1)
  );
END;
$$;

-- ============================================
-- GENERAR OC DESDE ADJUDICACION RFQ
-- Crea una OC para un proveedor especifico con los productos adjudicados
-- ============================================
CREATE OR REPLACE FUNCTION generate_po_from_rfq(
  p_solicitud_id UUID,
  p_proveedor_id UUID
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_sol RECORD;
  v_oc_id UUID;
  v_adj RECORD;
  v_subtotal_0 DECIMAL(14,2) := 0;
  v_subtotal_iva DECIMAL(14,2) := 0;
  v_total_iva DECIMAL(14,2) := 0;
  v_total DECIMAL(14,2) := 0;
  v_num VARCHAR(20);
  v_linea_subtotal DECIMAL(14,2);
  v_tarifa DECIMAL(4,2);
  v_iva_linea DECIMAL(14,2);
BEGIN
  SELECT * INTO v_sol FROM solicitudes_cotizacion WHERE id = p_solicitud_id;

  -- Generar numero de OC (secuencial por empresa)
  SELECT 'OC-' || LPAD((COALESCE(MAX(CAST(SUBSTRING(numero FROM 4) AS INTEGER)), 0) + 1)::TEXT, 6, '0')
  INTO v_num
  FROM ordenes_compra
  WHERE empresa_id = v_sol.empresa_id;

  -- Crear cabecera OC
  INSERT INTO ordenes_compra (
    empresa_id, contacto_id, numero, fecha,
    fecha_entrega_esperada, estado, notas, moneda
  ) VALUES (
    v_sol.empresa_id, p_proveedor_id, v_num, CURRENT_DATE,
    CURRENT_DATE + COALESCE(
      (SELECT MAX(plazo_entrega_dias) FROM solicitud_cotizacion_adjudicaciones
       WHERE solicitud_id = p_solicitud_id AND proveedor_id = p_proveedor_id),
      15
    ),
    'BORRADOR',
    'Generada desde RFQ ' || v_sol.numero,
    v_sol.moneda
  )
  RETURNING id INTO v_oc_id;

  -- Crear lineas de OC desde adjudicaciones
  FOR v_adj IN
    SELECT a.*, p.codigo_iva, p.tarifa_iva, p.descripcion AS producto_desc
    FROM solicitud_cotizacion_adjudicaciones a
    JOIN productos p ON p.id = a.producto_id
    WHERE a.solicitud_id = p_solicitud_id AND a.proveedor_id = p_proveedor_id
  LOOP
    v_linea_subtotal := v_adj.subtotal;
    v_tarifa := COALESCE(v_adj.tarifa_iva, 15.00);
    v_iva_linea := CASE WHEN v_adj.codigo_iva IN ('0', '6', '7') THEN 0
                        ELSE ROUND(v_linea_subtotal * v_tarifa / 100, 2) END;

    INSERT INTO orden_compra_detalles (
      orden_compra_id, producto_id, descripcion,
      cantidad, cantidad_base, precio_unitario, descuento,
      subtotal, total_impuestos, total_linea
    ) VALUES (
      v_oc_id, v_adj.producto_id, v_adj.producto_desc,
      v_adj.cantidad, v_adj.cantidad, v_adj.precio_unitario, v_adj.descuento,
      v_linea_subtotal, v_iva_linea, v_linea_subtotal + v_iva_linea
    );

    IF v_adj.codigo_iva IN ('0', '6', '7') THEN
      v_subtotal_0 := v_subtotal_0 + v_linea_subtotal;
    ELSE
      v_subtotal_iva := v_subtotal_iva + v_linea_subtotal;
      v_total_iva := v_total_iva + v_iva_linea;
    END IF;
  END LOOP;

  v_total := v_subtotal_0 + v_subtotal_iva + v_total_iva;

  -- Actualizar totales de la OC
  UPDATE ordenes_compra SET
    subtotal_0 = v_subtotal_0,
    subtotal_iva = v_subtotal_iva,
    total_iva = v_total_iva,
    total = v_total
  WHERE id = v_oc_id;

  -- Vincular adjudicaciones con la OC
  UPDATE solicitud_cotizacion_adjudicaciones
  SET orden_compra_id = v_oc_id
  WHERE solicitud_id = p_solicitud_id AND proveedor_id = p_proveedor_id;

  RETURN v_oc_id;
END;
$$;

-- ============================================
-- AUTO-SELECCION: Sugerir mejor proveedor por producto
-- ============================================
CREATE OR REPLACE FUNCTION suggest_rfq_adjudication(
  p_solicitud_id UUID,
  p_criterio VARCHAR DEFAULT 'PRECIO'  -- PRECIO | SCORE | BALANCED
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_sugerencias JSONB := '[]'::JSONB;
  v_prod RECORD;
  v_mejor RECORD;
BEGIN
  FOR v_prod IN
    SELECT producto_id, cantidad
    FROM solicitud_cotizacion_productos
    WHERE solicitud_id = p_solicitud_id
  LOOP
    IF p_criterio = 'PRECIO' THEN
      SELECT scp.proveedor_id, c.razon_social,
             scl.precio_unitario, scl.descuento, scl.subtotal,
             COALESCE(scl.plazo_entrega_dias, scp.plazo_entrega_dias) AS plazo
      INTO v_mejor
      FROM solicitud_cotizacion_lineas scl
      JOIN solicitud_cotizacion_proveedores scp ON scp.id = scl.solicitud_proveedor_id
      JOIN contactos c ON c.id = scp.proveedor_id
      WHERE scp.solicitud_id = p_solicitud_id
        AND scp.estado = 'RECIBIDA'
        AND scl.producto_id = v_prod.producto_id
        AND scl.precio_unitario IS NOT NULL
      ORDER BY scl.precio_unitario * (1 - COALESCE(scl.descuento, 0) / 100) ASC
      LIMIT 1;
    ELSIF p_criterio = 'SCORE' THEN
      SELECT scp.proveedor_id, c.razon_social,
             scl.precio_unitario, scl.descuento, scl.subtotal,
             COALESCE(scl.plazo_entrega_dias, scp.plazo_entrega_dias) AS plazo
      INTO v_mejor
      FROM solicitud_cotizacion_lineas scl
      JOIN solicitud_cotizacion_proveedores scp ON scp.id = scl.solicitud_proveedor_id
      JOIN contactos c ON c.id = scp.proveedor_id
      WHERE scp.solicitud_id = p_solicitud_id
        AND scp.estado = 'RECIBIDA'
        AND scl.producto_id = v_prod.producto_id
      ORDER BY COALESCE(scp.score_proveedor, 0) DESC, scl.precio_unitario ASC
      LIMIT 1;
    ELSE -- BALANCED: 50% precio + 50% score
      SELECT scp.proveedor_id, c.razon_social,
             scl.precio_unitario, scl.descuento, scl.subtotal,
             COALESCE(scl.plazo_entrega_dias, scp.plazo_entrega_dias) AS plazo
      INTO v_mejor
      FROM solicitud_cotizacion_lineas scl
      JOIN solicitud_cotizacion_proveedores scp ON scp.id = scl.solicitud_proveedor_id
      JOIN contactos c ON c.id = scp.proveedor_id
      WHERE scp.solicitud_id = p_solicitud_id
        AND scp.estado = 'RECIBIDA'
        AND scl.producto_id = v_prod.producto_id
        AND scl.precio_unitario IS NOT NULL
      ORDER BY (
        -- Normalizar: precio menor = mejor (invertir), score mayor = mejor
        (1 - scl.precio_unitario / NULLIF(
          (SELECT MAX(scl2.precio_unitario) FROM solicitud_cotizacion_lineas scl2
           JOIN solicitud_cotizacion_proveedores scp2 ON scp2.id = scl2.solicitud_proveedor_id
           WHERE scp2.solicitud_id = p_solicitud_id AND scl2.producto_id = v_prod.producto_id), 0
        )) * 50 +
        COALESCE(scp.score_proveedor, 50) / 100.0 * 50
      ) DESC
      LIMIT 1;
    END IF;

    IF v_mejor IS NOT NULL THEN
      v_sugerencias := v_sugerencias || jsonb_build_object(
        'producto_id', v_prod.producto_id,
        'proveedor_id', v_mejor.proveedor_id,
        'razon_social', v_mejor.razon_social,
        'precio_unitario', v_mejor.precio_unitario,
        'descuento', v_mejor.descuento,
        'cantidad', v_prod.cantidad,
        'plazo_dias', v_mejor.plazo
      );
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'criterio', p_criterio,
    'sugerencias', v_sugerencias
  );
END;
$$;
```

### Triggers

```sql
-- Actualizar updated_at automaticamente
CREATE OR REPLACE FUNCTION tr_rfq_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tr_solicitud_cotizacion_updated
  BEFORE UPDATE ON solicitudes_cotizacion
  FOR EACH ROW EXECUTE FUNCTION tr_rfq_updated_at();

-- Validar que el proveedor invitado sea un contacto con es_proveedor=true
CREATE OR REPLACE FUNCTION tr_validate_rfq_proveedor()
RETURNS TRIGGER AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM contactos WHERE id = NEW.proveedor_id AND es_proveedor = true AND activo = true
  ) THEN
    RAISE EXCEPTION 'El contacto % no es un proveedor activo', NEW.proveedor_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tr_validate_rfq_proveedor
  BEFORE INSERT OR UPDATE ON solicitud_cotizacion_proveedores
  FOR EACH ROW EXECUTE FUNCTION tr_validate_rfq_proveedor();

-- Snapshot del score del proveedor al invitarlo
CREATE OR REPLACE FUNCTION tr_snapshot_proveedor_score()
RETURNS TRIGGER AS $$
BEGIN
  SELECT puntaje_total INTO NEW.score_proveedor
  FROM evaluaciones_proveedor
  WHERE proveedor_id = NEW.proveedor_id
    AND empresa_id = (SELECT empresa_id FROM solicitudes_cotizacion WHERE id = NEW.solicitud_id)
  ORDER BY fecha DESC
  LIMIT 1;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tr_snapshot_score_on_rfq_invite
  BEFORE INSERT ON solicitud_cotizacion_proveedores
  FOR EACH ROW EXECUTE FUNCTION tr_snapshot_proveedor_score();
```

### Vistas para Reportes

```sql
-- Vista: Resumen de RFQs con metricas
CREATE OR REPLACE VIEW v_rfq_resumen AS
SELECT
  sc.id,
  sc.empresa_id,
  sc.numero,
  sc.titulo,
  sc.fecha_emision,
  sc.fecha_limite,
  sc.estado,
  sc.tipo_adjudicacion,
  (SELECT COUNT(*) FROM solicitud_cotizacion_productos WHERE solicitud_id = sc.id) AS total_productos,
  (SELECT COUNT(*) FROM solicitud_cotizacion_proveedores WHERE solicitud_id = sc.id) AS total_proveedores_invitados,
  (SELECT COUNT(*) FROM solicitud_cotizacion_proveedores WHERE solicitud_id = sc.id AND estado = 'RECIBIDA') AS total_respondieron,
  (SELECT COUNT(*) FROM solicitud_cotizacion_proveedores WHERE solicitud_id = sc.id AND es_extemporanea = true) AS total_extemporaneas,
  (SELECT MIN(total) FROM solicitud_cotizacion_proveedores WHERE solicitud_id = sc.id AND estado = 'RECIBIDA') AS mejor_oferta,
  (SELECT MAX(total) FROM solicitud_cotizacion_proveedores WHERE solicitud_id = sc.id AND estado = 'RECIBIDA') AS peor_oferta,
  (SELECT AVG(tiempo_respuesta_horas) FROM solicitud_cotizacion_proveedores WHERE solicitud_id = sc.id AND estado = 'RECIBIDA') AS tiempo_respuesta_promedio_horas,
  sc.fecha_adjudicacion,
  sc.created_at
FROM solicitudes_cotizacion sc;

-- Vista: Efectividad de proveedores en RFQs
CREATE OR REPLACE VIEW v_rfq_efectividad_proveedor AS
SELECT
  scp.proveedor_id,
  c.razon_social,
  sc.empresa_id,
  COUNT(*) AS total_invitaciones,
  COUNT(*) FILTER (WHERE scp.estado = 'RECIBIDA' OR scp.estado = 'SELECCIONADA') AS total_respuestas,
  COUNT(*) FILTER (WHERE scp.estado = 'SELECCIONADA') AS total_adjudicaciones,
  ROUND(
    COUNT(*) FILTER (WHERE scp.estado IN ('RECIBIDA', 'SELECCIONADA'))::DECIMAL /
    NULLIF(COUNT(*), 0) * 100, 2
  ) AS tasa_respuesta_pct,
  ROUND(
    COUNT(*) FILTER (WHERE scp.estado = 'SELECCIONADA')::DECIMAL /
    NULLIF(COUNT(*) FILTER (WHERE scp.estado IN ('RECIBIDA', 'SELECCIONADA')), 0) * 100, 2
  ) AS tasa_adjudicacion_pct,
  AVG(scp.tiempo_respuesta_horas) AS tiempo_respuesta_promedio_horas
FROM solicitud_cotizacion_proveedores scp
JOIN solicitudes_cotizacion sc ON sc.id = scp.solicitud_id
JOIN contactos c ON c.id = scp.proveedor_id
GROUP BY scp.proveedor_id, c.razon_social, sc.empresa_id;
```

### Integracion Module Service Bus

```sql
-- Gateway: Solicitar creacion de RFQ desde otros modulos
CREATE OR REPLACE FUNCTION module_bus.request_rfq(
  p_empresa_id UUID,
  p_productos JSONB,          -- [{producto_id, cantidad}]
  p_proveedor_ids UUID[] DEFAULT NULL,
  p_fecha_limite DATE DEFAULT NULL,
  p_origen VARCHAR DEFAULT NULL,
  p_referencia_id UUID DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_activo BOOLEAN;
  v_rfq_id UUID;
BEGIN
  -- Verificar si modulo Compras esta activo
  SELECT EXISTS (
    SELECT 1 FROM modulos_empresa me
    JOIN modulos m ON m.id = me.modulo_id
    WHERE me.empresa_id = p_empresa_id AND m.codigo = 'compras' AND me.activo = true
  ) INTO v_activo;

  IF NOT v_activo THEN
    RETURN jsonb_build_object('executed', false, 'reason', 'Modulo Compras inactivo');
  END IF;

  -- Crear la solicitud de cotizacion
  INSERT INTO solicitudes_cotizacion (
    empresa_id, requisicion_id, fecha_emision,
    fecha_limite, descripcion, estado
  ) VALUES (
    p_empresa_id,
    p_referencia_id,
    CURRENT_DATE,
    COALESCE(p_fecha_limite, CURRENT_DATE + 7),
    'Generada automaticamente desde ' || COALESCE(p_origen, 'sistema'),
    'BORRADOR'
  ) RETURNING id INTO v_rfq_id;

  -- Insertar productos
  INSERT INTO solicitud_cotizacion_productos (solicitud_id, producto_id, cantidad)
  SELECT v_rfq_id, (p->>'producto_id')::UUID, (p->>'cantidad')::DECIMAL
  FROM jsonb_array_elements(p_productos) p;

  -- Insertar proveedores si se proporcionaron
  IF p_proveedor_ids IS NOT NULL THEN
    INSERT INTO solicitud_cotizacion_proveedores (solicitud_id, proveedor_id)
    SELECT v_rfq_id, unnest(p_proveedor_ids);
  END IF;

  RETURN jsonb_build_object(
    'executed', true,
    'rfq_id', v_rfq_id
  );
END;
$$;
```

### RLS Policies

Las policies RLS se definieron en la seccion 24.1.2. Resumen:

| Tabla | Policy | Tipo |
|-------|--------|------|
| `solicitudes_cotizacion` | `tenant_isolation` (ya existe) | Directa: `empresa_id = get_empresa_id()` |
| `solicitud_cotizacion_proveedores` | Via JOIN a `solicitudes_cotizacion` | Heredada |
| `solicitud_cotizacion_lineas` | Via JOIN a `solicitud_cotizacion_proveedores` | Heredada |
| `solicitud_cotizacion_productos` | `tenant_via_solicitud` | Via JOIN |
| `solicitud_cotizacion_adjudicaciones` | `tenant_via_solicitud` | Via JOIN |

### Flujo UI/UX

```
PANTALLA LISTADO RFQ:
  SfDataGrid con columnas: Numero | Titulo | Fecha | Fecha Limite | Estado | Proveedores | Productos
  Filtros: estado, rango fechas
  Boton [+ Nueva RFQ]

PANTALLA CREAR/EDITAR RFQ:
  Tab 1 - General:
    - Titulo, Fecha limite, Tipo adjudicacion (TOTAL/PARCIAL), Criterio seleccion
    - Notas internas
    - Origen: Requisicion (selector, si aplica)

  Tab 2 - Productos:
    - SfDataGrid editable: Producto | Cantidad | UoM | Especificaciones
    - Boton [+ Agregar producto]
    - Boton [Importar desde Requisicion]

  Tab 3 - Proveedores:
    - SfDataGrid: Proveedor | Score | Estado | Fecha Respuesta | Total
    - Boton [+ Invitar proveedor]
    - Sugerencia automatica: proveedores con mejor score para los productos seleccionados
    - Boton [Enviar RFQ] -> confirma y envia a todos los proveedores pendientes

  Tab 4 - Comparativo (solo si estado >= ENVIADA):
    - Matriz comparativa (tabla pivotada): Productos en filas, Proveedores en columnas
    - Cada celda: precio unitario, descuento, subtotal (color verde=mejor, rojo=peor)
    - Resumen inferior: total por proveedor, plazo maximo, score
    - Boton [Sugerir adjudicacion] -> marca automaticamente mejores opciones
    - Boton [Adjudicar] -> genera OCs

  Tab 5 - OCs Generadas (solo si estado = CERRADA):
    - Lista de OCs creadas con link a cada una

RESPONSIVE:
  - COMPACT: tabs verticales, comparativo en cards apiladas
  - MEDIUM: tabs horizontales, comparativo scrollable
  - EXPANDED/LARGE: comparativo completo visible sin scroll
```

---

