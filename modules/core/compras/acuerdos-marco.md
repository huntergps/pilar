# Acuerdos Marco de Compra


### Descripcion Funcional

Los Acuerdos Marco son contratos pre-negociados con proveedores que fijan precios, cantidades y/o montos durante un periodo determinado. Permiten a la empresa asegurar condiciones favorables de compra y simplificar la gestion de ordenes recurrentes mediante "liberaciones" (ordenes de compra parciales que descuentan del acuerdo).

**Tipos de acuerdos:**

1. **Por cantidad total:** Se acuerda comprar N unidades de un producto a precio fijo durante el periodo. Cada OC descuenta del saldo de cantidad pendiente.

2. **Por monto total:** Se acuerda un monto total de compra ($X) durante el periodo. Cada OC descuenta del saldo monetario pendiente.

3. **Por periodo (abierto):** Se acuerda un precio fijo durante un periodo, sin limite de cantidad ni monto. Toda compra al proveedor durante el periodo usa el precio del acuerdo.

**Flujo completo:**

```
Negociar condiciones con proveedor
  |
  v
Crear Acuerdo Marco (tipo, productos, precios, vigencia)
  |
  v
Aprobar acuerdo (requiere firma/aprobacion gerencia)
  |
  v
Crear OC referenciando el acuerdo (liberacion)
  |-- Auto-pricing: precio del acuerdo prevalece
  |-- Control: no exceder cantidad/monto del acuerdo
  |
  v
Seguimiento: % consumido, alertas de vencimiento/agotamiento
  |
  v
Al vencer: renovar o cerrar el acuerdo
  |
  v
Reporte: ahorro vs compra spot, cumplimiento
```

**Reglas de negocio:**

1. Un acuerdo puede cubrir uno o multiples productos del mismo proveedor
2. Los precios del acuerdo prevalecen sobre listas de precios y precios de producto_proveedores
3. Al crear una OC, el sistema sugiere automaticamente acuerdos vigentes para el proveedor/producto
4. No se puede exceder la cantidad/monto total del acuerdo (alerta al 80%, bloqueo al 100%)
5. Los acuerdos requieren aprobacion antes de ser usados
6. Se pueden registrar penalidades por incumplimiento (tracking, no bloqueo automatico)
7. Renovacion manual o automatica (clon del acuerdo con nuevas fechas)
8. El acuerdo se puede cancelar anticipadamente con motivo registrado
9. Multi-moneda: el acuerdo puede estar en moneda diferente a USD (conversion al facturar)

### Modelo de Datos SQL

```sql
-- ============================================
-- ACUERDOS MARCO DE COMPRA (REEMPLAZA tabla basica del INFORME)
-- ============================================

-- Eliminar tabla basica existente y recrear con estructura completa
DROP TABLE IF EXISTS acuerdos_marco;

CREATE TABLE acuerdos_marco (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id        UUID NOT NULL REFERENCES empresas(id),
  proveedor_id      UUID NOT NULL REFERENCES contactos(id),
  numero            VARCHAR(20),                        -- Secuencial: AM-000001
  nombre            VARCHAR(200) NOT NULL,              -- 'Acuerdo Ferreteria Central 2026'
  tipo              VARCHAR(20) NOT NULL DEFAULT 'CANTIDAD',
    -- CANTIDAD: por cantidad total de producto
    -- MONTO: por monto total monetario
    -- PERIODO: precio fijo sin limites de volumen
  -- Vigencia
  vigencia_desde    DATE NOT NULL,
  vigencia_hasta    DATE NOT NULL,
  -- Limites (segun tipo)
  monto_total       DECIMAL(14,2),                      -- Solo tipo MONTO
  monto_consumido   DECIMAL(14,2) DEFAULT 0,
  monto_pendiente   DECIMAL(14,2),                      -- monto_total - monto_consumido
  -- Terminos
  termino_pago_id   UUID REFERENCES terminos_pago(id),
  moneda            VARCHAR(10) DEFAULT 'USD',
  -- Estado
  estado            VARCHAR(20) DEFAULT 'BORRADOR',
    -- BORRADOR: en negociacion
    -- PENDIENTE_APROBACION: enviado para aprobacion
    -- ACTIVO: aprobado y vigente
    -- PAUSADO: temporalmente suspendido
    -- VENCIDO: paso la fecha de vigencia
    -- AGOTADO: cantidad/monto totalmente consumido
    -- CANCELADO: cancelado anticipadamente
    -- RENOVADO: reemplazado por nuevo acuerdo
  -- Aprobacion
  aprobado_por      UUID REFERENCES auth.users(id),
  fecha_aprobacion  TIMESTAMPTZ,
  -- Renovacion
  acuerdo_anterior_id UUID REFERENCES acuerdos_marco(id), -- Acuerdo que reemplaza
  renovacion_automatica BOOLEAN DEFAULT false,
  dias_aviso_vencimiento INTEGER DEFAULT 30,             -- Dias antes de vencer para alertar
  -- Penalidades
  tiene_penalidades BOOLEAN DEFAULT false,
  condiciones_penalidad TEXT,
  -- Porcentaje de alerta
  porcentaje_alerta DECIMAL(5,2) DEFAULT 80.00,         -- Alertar al X% de consumo
  alerta_enviada    BOOLEAN DEFAULT false,
  -- Metadata
  notas             TEXT,
  documento_url     TEXT,                                -- PDF del contrato en Storage
  creado_por        UUID REFERENCES auth.users(id),
  cancelado_por     UUID REFERENCES auth.users(id),
  motivo_cancelacion TEXT,
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now()
);

-- Lineas del acuerdo marco (productos con precios acordados)
CREATE TABLE acuerdo_marco_lineas (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  acuerdo_id        UUID NOT NULL REFERENCES acuerdos_marco(id) ON DELETE CASCADE,
  producto_id       UUID NOT NULL REFERENCES productos(id),
  presentacion_id   UUID REFERENCES producto_presentaciones(id),
  precio_acordado   DECIMAL(14,6) NOT NULL,
  -- Limites por producto (tipo CANTIDAD)
  cantidad_total    DECIMAL(18,6),                      -- Cantidad maxima a comprar
  cantidad_consumida DECIMAL(18,6) DEFAULT 0,
  cantidad_pendiente DECIMAL(18,6),                     -- cantidad_total - cantidad_consumida
  -- Limites por producto (tipo MONTO)
  monto_linea_total DECIMAL(14,2),
  monto_linea_consumido DECIMAL(14,2) DEFAULT 0,
  -- Condiciones
  cantidad_minima_liberacion DECIMAL(18,6) DEFAULT 1,   -- Qty minima por OC
  descuento         DECIMAL(5,2) DEFAULT 0,
  notas             TEXT,
  orden             INTEGER DEFAULT 0,
  UNIQUE(acuerdo_id, producto_id)
);

-- Liberaciones (OCs vinculadas al acuerdo)
CREATE TABLE acuerdo_marco_liberaciones (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  acuerdo_id        UUID NOT NULL REFERENCES acuerdos_marco(id),
  acuerdo_linea_id  UUID NOT NULL REFERENCES acuerdo_marco_lineas(id),
  orden_compra_id   UUID NOT NULL REFERENCES ordenes_compra(id),
  producto_id       UUID NOT NULL REFERENCES productos(id),
  cantidad          DECIMAL(18,6) NOT NULL,
  precio_unitario   DECIMAL(14,6) NOT NULL,
  monto             DECIMAL(14,2) NOT NULL,
  fecha             DATE NOT NULL DEFAULT CURRENT_DATE,
  created_at        TIMESTAMPTZ DEFAULT now()
);

-- Penalidades registradas
CREATE TABLE acuerdo_marco_penalidades (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  acuerdo_id        UUID NOT NULL REFERENCES acuerdos_marco(id),
  tipo              VARCHAR(30) NOT NULL,
    -- INCUMPLIMIENTO_ENTREGA: proveedor no entrego a tiempo
    -- INCUMPLIMIENTO_CALIDAD: productos no cumplen calidad acordada
    -- INCUMPLIMIENTO_CANTIDAD: no alcanzo cantidad minima
    -- VARIACION_PRECIO: intento cobrar precio diferente al acordado
    -- OTRO
  descripcion       TEXT NOT NULL,
  monto_penalidad   DECIMAL(14,2),
  estado            VARCHAR(20) DEFAULT 'REGISTRADA',
    -- REGISTRADA, APLICADA, CONDONADA
  fecha             DATE NOT NULL DEFAULT CURRENT_DATE,
  registrado_por    UUID REFERENCES auth.users(id),
  notas             TEXT
);

-- Campo adicional en ordenes_compra para vincular con acuerdo
ALTER TABLE ordenes_compra
  ADD COLUMN IF NOT EXISTS acuerdo_marco_id UUID REFERENCES acuerdos_marco(id);

-- Indices
CREATE INDEX idx_acuerdos_marco_empresa ON acuerdos_marco(empresa_id, estado);
CREATE INDEX idx_acuerdos_marco_proveedor ON acuerdos_marco(proveedor_id, estado);
CREATE INDEX idx_acuerdos_marco_vigencia ON acuerdos_marco(empresa_id, vigencia_desde, vigencia_hasta)
  WHERE estado = 'ACTIVO';
CREATE INDEX idx_acuerdo_lineas_acuerdo ON acuerdo_marco_lineas(acuerdo_id);
CREATE INDEX idx_acuerdo_lineas_producto ON acuerdo_marco_lineas(producto_id);
CREATE INDEX idx_acuerdo_liberaciones_acuerdo ON acuerdo_marco_liberaciones(acuerdo_id);
CREATE INDEX idx_acuerdo_liberaciones_oc ON acuerdo_marco_liberaciones(orden_compra_id);

-- RLS
ALTER TABLE acuerdos_marco ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON acuerdos_marco FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

ALTER TABLE acuerdo_marco_lineas ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_via_acuerdo" ON acuerdo_marco_lineas FOR ALL TO authenticated
  USING (acuerdo_id IN (SELECT id FROM acuerdos_marco WHERE empresa_id = (SELECT private.get_empresa_id())));

ALTER TABLE acuerdo_marco_liberaciones ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_via_acuerdo" ON acuerdo_marco_liberaciones FOR ALL TO authenticated
  USING (acuerdo_id IN (SELECT id FROM acuerdos_marco WHERE empresa_id = (SELECT private.get_empresa_id())));

ALTER TABLE acuerdo_marco_penalidades ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_via_acuerdo" ON acuerdo_marco_penalidades FOR ALL TO authenticated
  USING (acuerdo_id IN (SELECT id FROM acuerdos_marco WHERE empresa_id = (SELECT private.get_empresa_id())));
```

### Funciones PostgreSQL Principales

```sql
-- ============================================
-- BUSCAR ACUERDO VIGENTE PARA PROVEEDOR + PRODUCTO
-- Usado al crear OC para auto-pricing
-- ============================================
CREATE OR REPLACE FUNCTION find_active_agreement(
  p_empresa_id UUID,
  p_proveedor_id UUID,
  p_producto_id UUID,
  p_cantidad DECIMAL DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_acuerdo RECORD;
  v_linea RECORD;
BEGIN
  SELECT am.*, aml.id AS linea_id, aml.precio_acordado, aml.descuento,
         aml.cantidad_total, aml.cantidad_consumida, aml.cantidad_pendiente,
         aml.cantidad_minima_liberacion
  INTO v_acuerdo
  FROM acuerdos_marco am
  JOIN acuerdo_marco_lineas aml ON aml.acuerdo_id = am.id
  WHERE am.empresa_id = p_empresa_id
    AND am.proveedor_id = p_proveedor_id
    AND aml.producto_id = p_producto_id
    AND am.estado = 'ACTIVO'
    AND CURRENT_DATE BETWEEN am.vigencia_desde AND am.vigencia_hasta
    AND (am.tipo = 'PERIODO'
         OR (am.tipo = 'CANTIDAD' AND aml.cantidad_pendiente > 0)
         OR (am.tipo = 'MONTO' AND am.monto_pendiente > 0))
  ORDER BY am.vigencia_desde DESC  -- Mas reciente primero
  LIMIT 1;

  IF v_acuerdo IS NULL THEN
    RETURN jsonb_build_object('found', false);
  END IF;

  RETURN jsonb_build_object(
    'found', true,
    'acuerdo_id', v_acuerdo.id,
    'linea_id', v_acuerdo.linea_id,
    'numero', v_acuerdo.numero,
    'nombre', v_acuerdo.nombre,
    'tipo', v_acuerdo.tipo,
    'precio_acordado', v_acuerdo.precio_acordado,
    'descuento', v_acuerdo.descuento,
    'vigencia_hasta', v_acuerdo.vigencia_hasta,
    'cantidad_pendiente', v_acuerdo.cantidad_pendiente,
    'monto_pendiente', v_acuerdo.monto_pendiente,
    'cantidad_minima', v_acuerdo.cantidad_minima_liberacion,
    'excederia', CASE
      WHEN v_acuerdo.tipo = 'CANTIDAD' AND p_cantidad IS NOT NULL
           AND p_cantidad > COALESCE(v_acuerdo.cantidad_pendiente, 999999)
      THEN true ELSE false END
  );
END;
$$;

-- ============================================
-- REGISTRAR LIBERACION (CONSUMO DEL ACUERDO)
-- Llamada al confirmar una OC vinculada a un acuerdo
-- ============================================
CREATE OR REPLACE FUNCTION register_agreement_release(
  p_orden_compra_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_oc RECORD;
  v_acuerdo RECORD;
  v_linea_oc RECORD;
  v_linea_am RECORD;
  v_total_monto DECIMAL(14,2) := 0;
  v_liberaciones INTEGER := 0;
BEGIN
  SELECT * INTO v_oc FROM ordenes_compra WHERE id = p_orden_compra_id;
  IF v_oc.acuerdo_marco_id IS NULL THEN
    RETURN jsonb_build_object('executed', false, 'reason', 'OC no vinculada a acuerdo');
  END IF;

  SELECT * INTO v_acuerdo FROM acuerdos_marco WHERE id = v_oc.acuerdo_marco_id;
  IF v_acuerdo.estado != 'ACTIVO' THEN
    RAISE EXCEPTION 'Acuerdo marco % no esta activo', v_acuerdo.numero;
  END IF;

  -- Procesar cada linea de la OC
  FOR v_linea_oc IN
    SELECT * FROM orden_compra_detalles WHERE orden_compra_id = p_orden_compra_id
  LOOP
    -- Buscar linea correspondiente en el acuerdo
    SELECT * INTO v_linea_am
    FROM acuerdo_marco_lineas
    WHERE acuerdo_id = v_acuerdo.id AND producto_id = v_linea_oc.producto_id;

    IF v_linea_am IS NOT NULL THEN
      -- Validar disponibilidad
      IF v_acuerdo.tipo = 'CANTIDAD' AND v_linea_am.cantidad_pendiente IS NOT NULL THEN
        IF v_linea_oc.cantidad > v_linea_am.cantidad_pendiente THEN
          RAISE EXCEPTION 'Cantidad % excede disponible % en acuerdo % para producto %',
            v_linea_oc.cantidad, v_linea_am.cantidad_pendiente,
            v_acuerdo.numero, v_linea_oc.producto_id;
        END IF;
      END IF;

      -- Registrar liberacion
      INSERT INTO acuerdo_marco_liberaciones (
        acuerdo_id, acuerdo_linea_id, orden_compra_id,
        producto_id, cantidad, precio_unitario, monto, fecha
      ) VALUES (
        v_acuerdo.id, v_linea_am.id, p_orden_compra_id,
        v_linea_oc.producto_id, v_linea_oc.cantidad,
        v_linea_oc.precio_unitario, v_linea_oc.subtotal, CURRENT_DATE
      );

      -- Actualizar consumo en la linea del acuerdo
      UPDATE acuerdo_marco_lineas SET
        cantidad_consumida = COALESCE(cantidad_consumida, 0) + v_linea_oc.cantidad,
        cantidad_pendiente = COALESCE(cantidad_total, 0) - (COALESCE(cantidad_consumida, 0) + v_linea_oc.cantidad),
        monto_linea_consumido = COALESCE(monto_linea_consumido, 0) + v_linea_oc.subtotal
      WHERE id = v_linea_am.id;

      v_total_monto := v_total_monto + v_linea_oc.subtotal;
      v_liberaciones := v_liberaciones + 1;
    END IF;
  END LOOP;

  -- Actualizar consumo global del acuerdo
  UPDATE acuerdos_marco SET
    monto_consumido = COALESCE(monto_consumido, 0) + v_total_monto,
    monto_pendiente = COALESCE(monto_total, 0) - (COALESCE(monto_consumido, 0) + v_total_monto),
    updated_at = now()
  WHERE id = v_acuerdo.id;

  -- Verificar si se agoto
  PERFORM check_agreement_status(v_acuerdo.id);

  RETURN jsonb_build_object(
    'executed', true,
    'liberaciones', v_liberaciones,
    'monto_liberado', v_total_monto
  );
END;
$$;

-- ============================================
-- VERIFICAR ESTADO DEL ACUERDO (vencimiento, agotamiento, alertas)
-- ============================================
CREATE OR REPLACE FUNCTION check_agreement_status(
  p_acuerdo_id UUID
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_am RECORD;
  v_porcentaje DECIMAL(5,2);
  v_agotado BOOLEAN := false;
BEGIN
  SELECT * INTO v_am FROM acuerdos_marco WHERE id = p_acuerdo_id;

  -- Verificar vencimiento
  IF v_am.estado = 'ACTIVO' AND v_am.vigencia_hasta < CURRENT_DATE THEN
    UPDATE acuerdos_marco SET estado = 'VENCIDO', updated_at = now()
    WHERE id = p_acuerdo_id;

    IF v_am.renovacion_automatica THEN
      PERFORM renew_agreement(p_acuerdo_id);
    END IF;
    RETURN;
  END IF;

  -- Verificar agotamiento (tipo CANTIDAD)
  IF v_am.tipo = 'CANTIDAD' THEN
    IF NOT EXISTS (
      SELECT 1 FROM acuerdo_marco_lineas
      WHERE acuerdo_id = p_acuerdo_id AND cantidad_pendiente > 0
    ) THEN
      v_agotado := true;
    END IF;
  END IF;

  -- Verificar agotamiento (tipo MONTO)
  IF v_am.tipo = 'MONTO' AND COALESCE(v_am.monto_pendiente, 0) <= 0 THEN
    v_agotado := true;
  END IF;

  IF v_agotado THEN
    UPDATE acuerdos_marco SET estado = 'AGOTADO', updated_at = now()
    WHERE id = p_acuerdo_id;
    RETURN;
  END IF;

  -- Verificar alerta de consumo
  IF v_am.tipo = 'MONTO' AND v_am.monto_total > 0 THEN
    v_porcentaje := v_am.monto_consumido / v_am.monto_total * 100;
  ELSIF v_am.tipo = 'CANTIDAD' THEN
    SELECT ROUND(
      SUM(cantidad_consumida) / NULLIF(SUM(cantidad_total), 0) * 100, 2
    ) INTO v_porcentaje
    FROM acuerdo_marco_lineas WHERE acuerdo_id = p_acuerdo_id;
  END IF;

  IF v_porcentaje >= v_am.porcentaje_alerta AND NOT v_am.alerta_enviada THEN
    UPDATE acuerdos_marco SET alerta_enviada = true, updated_at = now()
    WHERE id = p_acuerdo_id;

    PERFORM module_bus.send_notification(
      p_empresa_id := v_am.empresa_id,
      p_tipo := 'ACUERDO_MARCO_ALERTA_CONSUMO',
      p_datos := jsonb_build_object(
        'acuerdo_numero', v_am.numero,
        'proveedor_id', v_am.proveedor_id,
        'porcentaje_consumido', v_porcentaje,
        'vigencia_hasta', v_am.vigencia_hasta
      )
    );
  END IF;

  -- Verificar proximidad de vencimiento
  IF v_am.estado = 'ACTIVO'
     AND v_am.vigencia_hasta - CURRENT_DATE <= v_am.dias_aviso_vencimiento
     AND v_am.vigencia_hasta >= CURRENT_DATE
  THEN
    PERFORM module_bus.send_notification(
      p_empresa_id := v_am.empresa_id,
      p_tipo := 'ACUERDO_MARCO_POR_VENCER',
      p_datos := jsonb_build_object(
        'acuerdo_numero', v_am.numero,
        'proveedor_id', v_am.proveedor_id,
        'dias_restantes', v_am.vigencia_hasta - CURRENT_DATE,
        'vigencia_hasta', v_am.vigencia_hasta
      )
    );
  END IF;
END;
$$;

-- ============================================
-- RENOVAR ACUERDO MARCO
-- Crea un clon del acuerdo con nuevas fechas de vigencia
-- ============================================
CREATE OR REPLACE FUNCTION renew_agreement(
  p_acuerdo_id UUID,
  p_vigencia_desde DATE DEFAULT NULL,
  p_vigencia_hasta DATE DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_am RECORD;
  v_nuevo_id UUID;
  v_duracion INTEGER;
  v_num VARCHAR(20);
BEGIN
  SELECT * INTO v_am FROM acuerdos_marco WHERE id = p_acuerdo_id;

  v_duracion := v_am.vigencia_hasta - v_am.vigencia_desde;

  SELECT 'AM-' || LPAD((COALESCE(MAX(CAST(SUBSTRING(numero FROM 4) AS INTEGER)), 0) + 1)::TEXT, 6, '0')
  INTO v_num FROM acuerdos_marco WHERE empresa_id = v_am.empresa_id;

  INSERT INTO acuerdos_marco (
    empresa_id, proveedor_id, numero, nombre, tipo,
    vigencia_desde, vigencia_hasta,
    monto_total, termino_pago_id, moneda,
    estado, renovacion_automatica, dias_aviso_vencimiento,
    tiene_penalidades, condiciones_penalidad,
    porcentaje_alerta, acuerdo_anterior_id,
    notas, creado_por
  ) VALUES (
    v_am.empresa_id, v_am.proveedor_id, v_num,
    v_am.nombre || ' (Renovacion)',
    v_am.tipo,
    COALESCE(p_vigencia_desde, v_am.vigencia_hasta + 1),
    COALESCE(p_vigencia_hasta, v_am.vigencia_hasta + 1 + v_duracion),
    v_am.monto_total, v_am.termino_pago_id, v_am.moneda,
    'BORRADOR', v_am.renovacion_automatica, v_am.dias_aviso_vencimiento,
    v_am.tiene_penalidades, v_am.condiciones_penalidad,
    v_am.porcentaje_alerta, p_acuerdo_id,
    'Renovacion automatica de ' || v_am.numero,
    v_am.creado_por
  )
  RETURNING id INTO v_nuevo_id;

  -- Copiar lineas (reseteando consumos)
  INSERT INTO acuerdo_marco_lineas (
    acuerdo_id, producto_id, presentacion_id, precio_acordado,
    cantidad_total, cantidad_consumida, cantidad_pendiente,
    monto_linea_total, cantidad_minima_liberacion, descuento, notas, orden
  )
  SELECT
    v_nuevo_id, producto_id, presentacion_id, precio_acordado,
    cantidad_total, 0, cantidad_total,
    monto_linea_total, cantidad_minima_liberacion, descuento, notas, orden
  FROM acuerdo_marco_lineas WHERE acuerdo_id = p_acuerdo_id;

  -- Marcar original como renovado
  UPDATE acuerdos_marco SET estado = 'RENOVADO', updated_at = now()
  WHERE id = p_acuerdo_id AND estado NOT IN ('RENOVADO');

  RETURN v_nuevo_id;
END;
$$;

-- ============================================
-- REPORTE: Ahorro vs compra spot
-- ============================================
CREATE OR REPLACE FUNCTION report_agreement_savings(
  p_empresa_id UUID,
  p_fecha_desde DATE,
  p_fecha_hasta DATE
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN (
    WITH liberaciones AS (
      SELECT
        aml.acuerdo_id,
        am.nombre AS acuerdo,
        am.proveedor_id,
        c.razon_social AS proveedor,
        aml2.producto_id,
        p.descripcion AS producto,
        aml2.cantidad,
        aml2.precio_unitario AS precio_acuerdo,
        aml2.monto AS monto_acuerdo,
        -- Precio spot: promedio de OCs NO vinculadas a acuerdos para el mismo producto
        COALESCE(
          (SELECT AVG(ocd.precio_unitario)
           FROM orden_compra_detalles ocd
           JOIN ordenes_compra oc ON oc.id = ocd.orden_compra_id
           WHERE oc.empresa_id = p_empresa_id
             AND ocd.producto_id = aml2.producto_id
             AND oc.acuerdo_marco_id IS NULL
             AND oc.fecha BETWEEN p_fecha_desde AND p_fecha_hasta
             AND oc.estado NOT IN ('BORRADOR', 'CANCELADA')),
          aml2.precio_unitario  -- Si no hay spot, usa precio acuerdo (ahorro = 0)
        ) AS precio_spot
      FROM acuerdo_marco_liberaciones aml2
      JOIN acuerdos_marco am ON am.id = aml2.acuerdo_id
      JOIN acuerdo_marco_lineas aml ON aml.id = aml2.acuerdo_linea_id
      JOIN contactos c ON c.id = am.proveedor_id
      JOIN productos p ON p.id = aml2.producto_id
      WHERE am.empresa_id = p_empresa_id
        AND aml2.fecha BETWEEN p_fecha_desde AND p_fecha_hasta
    )
    SELECT jsonb_build_object(
      'periodo', jsonb_build_object('desde', p_fecha_desde, 'hasta', p_fecha_hasta),
      'total_compras_acuerdo', SUM(monto_acuerdo),
      'total_costo_spot_estimado', SUM(cantidad * precio_spot),
      'ahorro_estimado', SUM(cantidad * precio_spot) - SUM(monto_acuerdo),
      'porcentaje_ahorro', ROUND(
        (1 - SUM(monto_acuerdo) / NULLIF(SUM(cantidad * precio_spot), 0)) * 100, 2
      ),
      'detalle', jsonb_agg(
        jsonb_build_object(
          'acuerdo', acuerdo,
          'proveedor', proveedor,
          'producto', producto,
          'cantidad', cantidad,
          'precio_acuerdo', precio_acuerdo,
          'precio_spot', precio_spot,
          'ahorro_linea', ROUND((precio_spot - precio_acuerdo) * cantidad, 2)
        )
      )
    )
    FROM liberaciones
  );
END;
$$;
```

### Triggers

```sql
-- Actualizar monto_pendiente automaticamente
CREATE OR REPLACE FUNCTION tr_acuerdo_marco_pendiente()
RETURNS TRIGGER AS $$
BEGIN
  NEW.monto_pendiente := COALESCE(NEW.monto_total, 0) - COALESCE(NEW.monto_consumido, 0);
  NEW.updated_at := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tr_acuerdo_marco_calc_pendiente
  BEFORE INSERT OR UPDATE OF monto_consumido ON acuerdos_marco
  FOR EACH ROW EXECUTE FUNCTION tr_acuerdo_marco_pendiente();

-- Actualizar cantidad_pendiente en lineas
CREATE OR REPLACE FUNCTION tr_acuerdo_linea_pendiente()
RETURNS TRIGGER AS $$
BEGIN
  NEW.cantidad_pendiente := COALESCE(NEW.cantidad_total, 0) - COALESCE(NEW.cantidad_consumida, 0);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tr_acuerdo_linea_calc_pendiente
  BEFORE INSERT OR UPDATE OF cantidad_consumida ON acuerdo_marco_lineas
  FOR EACH ROW EXECUTE FUNCTION tr_acuerdo_linea_pendiente();

-- Cron: verificar acuerdos vencidos y por vencer
CREATE OR REPLACE FUNCTION cron_check_agreements()
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_acuerdo RECORD;
BEGIN
  FOR v_acuerdo IN
    SELECT id FROM acuerdos_marco WHERE estado = 'ACTIVO'
  LOOP
    PERFORM check_agreement_status(v_acuerdo.id);
  END LOOP;
END;
$$;
-- Ejecutar diariamente via pg_cron o Edge Function cron
```

### Vistas para Reportes

```sql
-- Vista: Acuerdos marco con progreso
CREATE OR REPLACE VIEW v_acuerdos_marco_progreso AS
SELECT
  am.id,
  am.empresa_id,
  am.numero,
  am.nombre,
  am.tipo,
  am.proveedor_id,
  c.razon_social AS proveedor,
  am.vigencia_desde,
  am.vigencia_hasta,
  am.estado,
  am.monto_total,
  am.monto_consumido,
  am.monto_pendiente,
  CASE WHEN am.monto_total > 0
    THEN ROUND(am.monto_consumido / am.monto_total * 100, 2) ELSE 0 END AS porcentaje_monto_consumido,
  (SELECT COUNT(*) FROM acuerdo_marco_lineas WHERE acuerdo_id = am.id) AS total_productos,
  (SELECT COUNT(*) FROM acuerdo_marco_liberaciones WHERE acuerdo_id = am.id) AS total_liberaciones,
  am.vigencia_hasta - CURRENT_DATE AS dias_restantes,
  am.renovacion_automatica,
  am.created_at
FROM acuerdos_marco am
JOIN contactos c ON c.id = am.proveedor_id;
```

### Integracion Module Service Bus

```sql
-- Gateway: Buscar acuerdo vigente al crear OC
CREATE OR REPLACE FUNCTION module_bus.find_purchase_agreement(
  p_empresa_id UUID,
  p_proveedor_id UUID,
  p_producto_id UUID,
  p_cantidad DECIMAL DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_activo BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM modulos_empresa me JOIN modulos m ON m.id = me.modulo_id
    WHERE me.empresa_id = p_empresa_id AND m.codigo = 'compras' AND me.activo = true
  ) INTO v_activo;

  IF NOT v_activo THEN
    RETURN jsonb_build_object('executed', false, 'found', false);
  END IF;

  RETURN find_active_agreement(p_empresa_id, p_proveedor_id, p_producto_id, p_cantidad)
    || jsonb_build_object('executed', true);
END;
$$;
```

### RLS Policies

| Tabla | Policy | Tipo |
|-------|--------|------|
| `acuerdos_marco` | `tenant_isolation` | Directa: `empresa_id` |
| `acuerdo_marco_lineas` | `tenant_via_acuerdo` | Via JOIN |
| `acuerdo_marco_liberaciones` | `tenant_via_acuerdo` | Via JOIN |
| `acuerdo_marco_penalidades` | `tenant_via_acuerdo` | Via JOIN |

### Flujo UI/UX

```
PANTALLA LISTADO ACUERDOS MARCO:
  SfDataGrid: Numero | Proveedor | Tipo | Vigencia | Estado | % Consumido | Monto | Dias Rest.
  ProgressBar visual en columna % Consumido (verde/amarillo/rojo)
  Filtros: estado, proveedor, tipo, vigente/vencido
  Boton [+ Nuevo Acuerdo]

PANTALLA CREAR/EDITAR ACUERDO:
  Tab 1 - General:
    - Proveedor (autocomplete), Nombre, Tipo (radio: CANTIDAD/MONTO/PERIODO)
    - Vigencia desde/hasta, Moneda, Termino de pago
    - Monto total (si tipo MONTO), Renovacion automatica (toggle)
    - Upload documento PDF del contrato

  Tab 2 - Productos:
    - SfDataGrid editable: Producto | Precio Acordado | Cantidad Total | Descuento | Min Liberacion
    - Boton [+ Agregar producto]
    - Boton [Importar desde producto_proveedores]

  Tab 3 - Liberaciones (readonly):
    - SfDataGrid: OC # | Producto | Cantidad | Precio | Monto | Fecha
    - Total liberado vs total acuerdo (gauge)

  Tab 4 - Penalidades:
    - SfDataGrid: Tipo | Descripcion | Monto | Estado | Fecha
    - Boton [+ Registrar penalidad]

  Acciones: [Enviar a Aprobacion] [Aprobar] [Pausar] [Cancelar] [Renovar]

RESPONSIVE:
  - COMPACT: wizard step-by-step para crear
  - MEDIUM: tabs horizontales
  - EXPANDED/LARGE: panel lateral con resumen de consumo
```

---

