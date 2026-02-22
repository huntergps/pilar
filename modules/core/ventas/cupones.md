# Cupones y Códigos Promocionales


#### Descripcion Funcional

Sistema de cupones y codigos promocionales que permite crear campanas de descuento con restricciones configurables. Los cupones pueden distribuirse por multiples canales y validarse en POS (escaneo QR/codigo), ecommerce y ventas de mostrador.

**Flujo principal:**

```
CREACION CAMPANA:
  Admin crea campana → tipo (% descuento, monto fijo, 2x1, etc.)
  → restricciones (minimo compra, productos, categorias, fechas)
  → genera codigos (manual, masivo, o QR)

DISTRIBUCION:
  Codigos se distribuyen via: email masivo, WhatsApp, impresion fisica, QR en tienda

VALIDACION (en POS, Ecommerce o mostrador):
  Cliente presenta codigo → sistema valida:
    1. Codigo existe y esta activo
    2. Dentro de fecha vigencia
    3. No excede limite usos (total y por cliente)
    4. Cumple monto minimo de compra
    5. Productos/categorias aplican
  → Si valido: aplica descuento
  → Si invalido: muestra motivo del rechazo

TRACKING:
  Cada uso se registra → reportes de ROI por campana
```

#### Modelo de Datos SQL

```sql
-- ══════════════════════════════════════════════════════════════════
-- CUPONES Y CODIGOS PROMOCIONALES (22.2)
-- ══════════════════════════════════════════════════════════════════

-- Campana promocional (agrupador de cupones)
CREATE TABLE cupones_campanas (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id          UUID NOT NULL REFERENCES empresas(id),
  nombre              VARCHAR(200) NOT NULL,
  codigo_campana      VARCHAR(30) NOT NULL,
  descripcion         TEXT,
  -- Tipo de promocion
  tipo_descuento      VARCHAR(30) NOT NULL,
    -- PORCENTAJE: descuento porcentual (ej: 10% off)
    -- MONTO_FIJO: descuento monto fijo (ej: $5 off)
    -- ENVIO_GRATIS: envio sin costo (ecommerce)
    -- COMPRA_X_LLEVA_Y: compra X unidades, lleva Y gratis (ej: 2x1, 3x2)
    -- PRODUCTO_GRATIS: producto especifico gratis con la compra
  -- Valor del descuento
  valor_descuento     DECIMAL(14,2),                     -- % o monto segun tipo
  max_descuento       DECIMAL(14,2),                     -- Tope maximo de descuento (para %)
  -- Para tipo COMPRA_X_LLEVA_Y
  compra_cantidad     INTEGER,                           -- X (compra)
  lleva_cantidad      INTEGER,                           -- Y (lleva gratis)
  -- Para tipo PRODUCTO_GRATIS
  producto_gratis_id  UUID REFERENCES productos(id),
  -- Restricciones de compra
  compra_minima       DECIMAL(14,2) DEFAULT 0,           -- Monto minimo de la compra
  -- Restricciones de aplicabilidad
  aplica_a            VARCHAR(20) DEFAULT 'TODO',
    -- TODO: aplica a toda la compra
    -- PRODUCTOS: solo a productos especificos (tabla cupones_campana_productos)
    -- CATEGORIAS: solo a categorias especificas (tabla cupones_campana_categorias)
  -- Limites de uso
  max_usos_total      INTEGER,                           -- NULL = ilimitado
  max_usos_cliente    INTEGER DEFAULT 1,                 -- Usos por cliente
  usos_actuales       INTEGER DEFAULT 0,                 -- Contador de usos
  -- Vigencia
  fecha_inicio        TIMESTAMPTZ NOT NULL,
  fecha_fin           TIMESTAMPTZ,                       -- NULL = sin fecha fin
  -- Canales
  canales             JSONB DEFAULT '["POS","ECOMMERCE","MOSTRADOR"]',
  -- Generacion de codigos
  tipo_codigo         VARCHAR(20) DEFAULT 'UNICO',
    -- UNICO: un solo codigo para toda la campana
    -- INDIVIDUAL: codigos unicos por destinatario (generacion masiva)
  codigo_unico        VARCHAR(30),                       -- El codigo si tipo_codigo = UNICO
  prefijo_codigos     VARCHAR(10),                       -- Prefijo para generacion masiva
  longitud_codigo     INTEGER DEFAULT 8,                 -- Longitud del codigo generado
  -- Combinacion con otras promociones
  acumulable          BOOLEAN DEFAULT false,             -- Se puede combinar con otros cupones?
  -- Estado
  estado              VARCHAR(20) DEFAULT 'BORRADOR',
    -- BORRADOR, ACTIVA, PAUSADA, FINALIZADA
  activo              BOOLEAN DEFAULT true,
  version             INTEGER DEFAULT 1,
  created_by          UUID REFERENCES auth.users(id),
  created_at          TIMESTAMPTZ DEFAULT now(),
  updated_at          TIMESTAMPTZ DEFAULT now(),
  UNIQUE(empresa_id, codigo_campana)
);

-- Productos elegibles para la campana (si aplica_a = 'PRODUCTOS')
CREATE TABLE cupones_campana_productos (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  campana_id          UUID NOT NULL REFERENCES cupones_campanas(id) ON DELETE CASCADE,
  empresa_id          UUID NOT NULL REFERENCES empresas(id),
  producto_id         UUID NOT NULL REFERENCES productos(id),
  UNIQUE(campana_id, producto_id)
);

-- Categorias elegibles para la campana (si aplica_a = 'CATEGORIAS')
CREATE TABLE cupones_campana_categorias (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  campana_id          UUID NOT NULL REFERENCES cupones_campanas(id) ON DELETE CASCADE,
  empresa_id          UUID NOT NULL REFERENCES empresas(id),
  categoria_id        UUID NOT NULL REFERENCES categorias_producto(id),
  UNIQUE(campana_id, categoria_id)
);

-- Codigos individuales (para generacion masiva)
CREATE TABLE cupones_codigos (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id          UUID NOT NULL REFERENCES empresas(id),
  campana_id          UUID NOT NULL REFERENCES cupones_campanas(id) ON DELETE CASCADE,
  codigo              VARCHAR(30) NOT NULL,
  -- Destinatario (opcional, para codigos personalizados)
  contacto_id         UUID REFERENCES contactos(id),
  email_destino       VARCHAR(200),
  -- Estado del codigo individual
  estado              VARCHAR(20) DEFAULT 'ACTIVO',
    -- ACTIVO, USADO, VENCIDO, CANCELADO
  usos_actuales       INTEGER DEFAULT 0,
  max_usos            INTEGER DEFAULT 1,                 -- Usos permitidos de este codigo
  -- Distribucion
  canal_distribucion  VARCHAR(20),
    -- EMAIL, WHATSAPP, IMPRESO, QR, MANUAL
  fecha_envio         TIMESTAMPTZ,                       -- Cuando se envio al destinatario
  -- QR
  qr_data             TEXT,                              -- Datos codificados en QR
  created_at          TIMESTAMPTZ DEFAULT now(),
  UNIQUE(empresa_id, codigo)
);

-- Registro de uso de cupones (historial append-only)
CREATE TABLE cupones_usos (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id          UUID NOT NULL REFERENCES empresas(id),
  campana_id          UUID NOT NULL REFERENCES cupones_campanas(id),
  codigo_id           UUID REFERENCES cupones_codigos(id), -- NULL si es codigo unico de campana
  codigo_usado        VARCHAR(30) NOT NULL,
  contacto_id         UUID REFERENCES contactos(id),
  -- Documento donde se aplico
  factura_id          UUID REFERENCES facturas(id),
  pos_venta_id        UUID,
  -- Detalle del descuento aplicado
  tipo_descuento      VARCHAR(30) NOT NULL,
  monto_compra        DECIMAL(14,2) NOT NULL,            -- Monto de la compra antes del descuento
  monto_descuento     DECIMAL(14,2) NOT NULL,            -- Descuento efectivamente aplicado
  -- Canal
  canal               VARCHAR(20) NOT NULL,              -- POS, ECOMMERCE, MOSTRADOR
  registrado_por      UUID REFERENCES auth.users(id),
  created_at          TIMESTAMPTZ DEFAULT now()
);

-- Indices
CREATE INDEX idx_cupones_codigos_campana ON cupones_codigos(campana_id, estado);
CREATE INDEX idx_cupones_codigos_codigo ON cupones_codigos(empresa_id, codigo);
CREATE INDEX idx_cupones_codigos_contacto ON cupones_codigos(contacto_id) WHERE contacto_id IS NOT NULL;
CREATE INDEX idx_cupones_usos_campana ON cupones_usos(campana_id, created_at DESC);
CREATE INDEX idx_cupones_usos_contacto ON cupones_usos(contacto_id, campana_id);
CREATE INDEX idx_cupones_campanas_estado ON cupones_campanas(empresa_id, estado, fecha_inicio, fecha_fin);
```

#### Funciones PostgreSQL Principales

```sql
-- Validar un codigo de cupon
CREATE OR REPLACE FUNCTION cupones_validar_codigo(
  p_empresa_id    UUID,
  p_codigo        VARCHAR,
  p_contacto_id   UUID DEFAULT NULL,
  p_monto_compra  DECIMAL DEFAULT 0,
  p_productos     JSONB DEFAULT NULL,   -- [{producto_id, categoria_id, cantidad, subtotal}]
  p_canal         VARCHAR DEFAULT 'POS'
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_campana cupones_campanas%ROWTYPE;
  v_codigo cupones_codigos%ROWTYPE;
  v_es_codigo_unico BOOLEAN;
  v_usos_cliente INTEGER;
  v_monto_elegible DECIMAL(14,2) := 0;
  v_monto_descuento DECIMAL(14,2) := 0;
  v_producto JSONB;
BEGIN
  -- 1. Buscar campana por codigo unico
  SELECT * INTO v_campana FROM cupones_campanas
  WHERE empresa_id = p_empresa_id AND codigo_unico = p_codigo
    AND estado = 'ACTIVA' AND activo = true;

  IF FOUND THEN
    v_es_codigo_unico := true;
  ELSE
    -- 2. Buscar en codigos individuales
    SELECT * INTO v_codigo FROM cupones_codigos
    WHERE empresa_id = p_empresa_id AND codigo = p_codigo AND estado = 'ACTIVO';
    IF NOT FOUND THEN
      RETURN jsonb_build_object('valido', false, 'motivo', 'Codigo no encontrado o inactivo');
    END IF;

    SELECT * INTO v_campana FROM cupones_campanas
    WHERE id = v_codigo.campana_id AND estado = 'ACTIVA' AND activo = true;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('valido', false, 'motivo', 'Campana no activa');
    END IF;

    v_es_codigo_unico := false;

    -- Validar usos del codigo individual
    IF v_codigo.usos_actuales >= v_codigo.max_usos THEN
      RETURN jsonb_build_object('valido', false, 'motivo', 'Codigo ya utilizado');
    END IF;
  END IF;

  -- 3. Validar vigencia
  IF v_campana.fecha_inicio > now() THEN
    RETURN jsonb_build_object('valido', false, 'motivo', 'Promocion aun no inicia');
  END IF;
  IF v_campana.fecha_fin IS NOT NULL AND v_campana.fecha_fin < now() THEN
    RETURN jsonb_build_object('valido', false, 'motivo', 'Promocion vencida');
  END IF;

  -- 4. Validar usos totales
  IF v_campana.max_usos_total IS NOT NULL AND v_campana.usos_actuales >= v_campana.max_usos_total THEN
    RETURN jsonb_build_object('valido', false, 'motivo', 'Promocion agotada');
  END IF;

  -- 5. Validar canal
  IF NOT (v_campana.canales ? p_canal) THEN
    RETURN jsonb_build_object('valido', false, 'motivo', format('Cupon no valido en canal %s', p_canal));
  END IF;

  -- 6. Validar usos por cliente
  IF p_contacto_id IS NOT NULL AND v_campana.max_usos_cliente IS NOT NULL THEN
    SELECT COUNT(*) INTO v_usos_cliente FROM cupones_usos
    WHERE campana_id = v_campana.id AND contacto_id = p_contacto_id;
    IF v_usos_cliente >= v_campana.max_usos_cliente THEN
      RETURN jsonb_build_object('valido', false, 'motivo', 'Limite de uso por cliente alcanzado');
    END IF;
  END IF;

  -- 7. Calcular monto elegible segun restriccion de productos/categorias
  IF v_campana.aplica_a = 'TODO' THEN
    v_monto_elegible := p_monto_compra;
  ELSIF v_campana.aplica_a = 'PRODUCTOS' AND p_productos IS NOT NULL THEN
    FOR v_producto IN SELECT * FROM jsonb_array_elements(p_productos) LOOP
      IF EXISTS (
        SELECT 1 FROM cupones_campana_productos
        WHERE campana_id = v_campana.id AND producto_id = (v_producto->>'producto_id')::UUID
      ) THEN
        v_monto_elegible := v_monto_elegible + (v_producto->>'subtotal')::DECIMAL;
      END IF;
    END LOOP;
  ELSIF v_campana.aplica_a = 'CATEGORIAS' AND p_productos IS NOT NULL THEN
    FOR v_producto IN SELECT * FROM jsonb_array_elements(p_productos) LOOP
      IF EXISTS (
        SELECT 1 FROM cupones_campana_categorias
        WHERE campana_id = v_campana.id AND categoria_id = (v_producto->>'categoria_id')::UUID
      ) THEN
        v_monto_elegible := v_monto_elegible + (v_producto->>'subtotal')::DECIMAL;
      END IF;
    END LOOP;
  END IF;

  -- 8. Validar monto minimo
  IF p_monto_compra < v_campana.compra_minima THEN
    RETURN jsonb_build_object('valido', false, 'motivo',
      format('Compra minima requerida: $%s', v_campana.compra_minima));
  END IF;

  -- 9. Calcular descuento
  CASE v_campana.tipo_descuento
    WHEN 'PORCENTAJE' THEN
      v_monto_descuento := ROUND(v_monto_elegible * v_campana.valor_descuento / 100, 2);
      IF v_campana.max_descuento IS NOT NULL AND v_monto_descuento > v_campana.max_descuento THEN
        v_monto_descuento := v_campana.max_descuento;
      END IF;
    WHEN 'MONTO_FIJO' THEN
      v_monto_descuento := LEAST(v_campana.valor_descuento, v_monto_elegible);
    WHEN 'ENVIO_GRATIS' THEN
      v_monto_descuento := 0; -- El descuento se aplica al envio, no al monto
    WHEN 'COMPRA_X_LLEVA_Y' THEN
      v_monto_descuento := 0; -- Se calcula al aplicar sobre lineas especificas
    WHEN 'PRODUCTO_GRATIS' THEN
      v_monto_descuento := 0; -- Se agrega producto gratis a la venta
    ELSE
      v_monto_descuento := 0;
  END CASE;

  RETURN jsonb_build_object(
    'valido', true,
    'campana_id', v_campana.id,
    'codigo_id', v_codigo.id,
    'nombre_campana', v_campana.nombre,
    'tipo_descuento', v_campana.tipo_descuento,
    'valor_descuento', v_campana.valor_descuento,
    'monto_descuento', v_monto_descuento,
    'monto_elegible', v_monto_elegible,
    'producto_gratis_id', v_campana.producto_gratis_id,
    'compra_cantidad', v_campana.compra_cantidad,
    'lleva_cantidad', v_campana.lleva_cantidad,
    'acumulable', v_campana.acumulable
  );
END;
$$;

-- Aplicar cupon (registrar uso)
CREATE OR REPLACE FUNCTION cupones_aplicar(
  p_empresa_id    UUID,
  p_codigo        VARCHAR,
  p_contacto_id   UUID,
  p_monto_compra  DECIMAL,
  p_monto_descuento DECIMAL,
  p_factura_id    UUID DEFAULT NULL,
  p_pos_venta_id  UUID DEFAULT NULL,
  p_canal         VARCHAR DEFAULT 'POS',
  p_usuario_id    UUID DEFAULT NULL
) RETURNS UUID -- ID del uso registrado
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_campana_id UUID;
  v_codigo_id UUID;
  v_tipo_descuento VARCHAR(30);
  v_uso_id UUID;
BEGIN
  -- Obtener campana y codigo
  SELECT id, tipo_descuento INTO v_campana_id, v_tipo_descuento
  FROM cupones_campanas
  WHERE empresa_id = p_empresa_id AND codigo_unico = p_codigo AND estado = 'ACTIVA';

  IF FOUND THEN
    v_codigo_id := NULL;
  ELSE
    SELECT cc.id, c.id, c.tipo_descuento INTO v_codigo_id, v_campana_id, v_tipo_descuento
    FROM cupones_codigos cc
    JOIN cupones_campanas c ON c.id = cc.campana_id
    WHERE cc.empresa_id = p_empresa_id AND cc.codigo = p_codigo AND cc.estado = 'ACTIVO';
  END IF;

  IF v_campana_id IS NULL THEN
    RAISE EXCEPTION 'Codigo de cupon no valido';
  END IF;

  -- Registrar uso
  INSERT INTO cupones_usos (
    empresa_id, campana_id, codigo_id, codigo_usado, contacto_id,
    factura_id, pos_venta_id, tipo_descuento,
    monto_compra, monto_descuento, canal, registrado_por
  ) VALUES (
    p_empresa_id, v_campana_id, v_codigo_id, p_codigo, p_contacto_id,
    p_factura_id, p_pos_venta_id, v_tipo_descuento,
    p_monto_compra, p_monto_descuento, p_canal, p_usuario_id
  ) RETURNING id INTO v_uso_id;

  -- Incrementar contadores
  UPDATE cupones_campanas SET usos_actuales = usos_actuales + 1, updated_at = now()
  WHERE id = v_campana_id;

  IF v_codigo_id IS NOT NULL THEN
    UPDATE cupones_codigos SET usos_actuales = usos_actuales + 1
    WHERE id = v_codigo_id;

    -- Si alcanzo max_usos, marcar como USADO
    UPDATE cupones_codigos SET estado = 'USADO'
    WHERE id = v_codigo_id AND usos_actuales >= max_usos;
  END IF;

  -- Si campana alcanzo max_usos_total, finalizar
  UPDATE cupones_campanas SET estado = 'FINALIZADA'
  WHERE id = v_campana_id AND max_usos_total IS NOT NULL AND usos_actuales >= max_usos_total;

  RETURN v_uso_id;
END;
$$;

-- Generar codigos masivos para una campana
CREATE OR REPLACE FUNCTION cupones_generar_codigos(
  p_empresa_id    UUID,
  p_campana_id    UUID,
  p_cantidad      INTEGER,
  p_contactos_ids UUID[] DEFAULT NULL,  -- Si se pasa, genera uno por contacto
  p_canal_distribucion VARCHAR DEFAULT 'EMAIL'
) RETURNS INTEGER -- cantidad generada
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_campana cupones_campanas%ROWTYPE;
  v_codigo VARCHAR;
  v_generados INTEGER := 0;
  i INTEGER;
  v_contacto_id UUID;
BEGIN
  SELECT * INTO v_campana FROM cupones_campanas
  WHERE id = p_campana_id AND empresa_id = p_empresa_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Campana no encontrada';
  END IF;

  IF p_contactos_ids IS NOT NULL THEN
    -- Generar uno por contacto
    FOREACH v_contacto_id IN ARRAY p_contactos_ids LOOP
      v_codigo := COALESCE(v_campana.prefijo_codigos, '') ||
        upper(substring(md5(random()::text || clock_timestamp()::text) from 1 for v_campana.longitud_codigo));

      INSERT INTO cupones_codigos (
        empresa_id, campana_id, codigo, contacto_id, canal_distribucion
      ) VALUES (
        p_empresa_id, p_campana_id, v_codigo, v_contacto_id, p_canal_distribucion
      ) ON CONFLICT DO NOTHING;

      v_generados := v_generados + 1;
    END LOOP;
  ELSE
    -- Generar cantidad especificada
    FOR i IN 1..p_cantidad LOOP
      v_codigo := COALESCE(v_campana.prefijo_codigos, '') ||
        upper(substring(md5(random()::text || clock_timestamp()::text || i::text) from 1 for v_campana.longitud_codigo));

      INSERT INTO cupones_codigos (
        empresa_id, campana_id, codigo, canal_distribucion
      ) VALUES (
        p_empresa_id, p_campana_id, v_codigo, p_canal_distribucion
      ) ON CONFLICT DO NOTHING;

      v_generados := v_generados + 1;
    END LOOP;
  END IF;

  RETURN v_generados;
END;
$$;

-- Reporte ROI de campana
CREATE OR REPLACE FUNCTION cupones_reporte_campana(
  p_empresa_id  UUID,
  p_campana_id  UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_result JSONB;
BEGIN
  SELECT jsonb_build_object(
    'campana', c.nombre,
    'tipo_descuento', c.tipo_descuento,
    'estado', c.estado,
    'fecha_inicio', c.fecha_inicio,
    'fecha_fin', c.fecha_fin,
    'usos_totales', c.usos_actuales,
    'max_usos', c.max_usos_total,
    'codigos_generados', (SELECT COUNT(*) FROM cupones_codigos WHERE campana_id = c.id),
    'codigos_usados', (SELECT COUNT(*) FROM cupones_codigos WHERE campana_id = c.id AND estado = 'USADO'),
    'tasa_uso', CASE WHEN (SELECT COUNT(*) FROM cupones_codigos WHERE campana_id = c.id) > 0
      THEN ROUND((SELECT COUNT(*) FROM cupones_codigos WHERE campana_id = c.id AND estado = 'USADO')::DECIMAL /
        (SELECT COUNT(*) FROM cupones_codigos WHERE campana_id = c.id) * 100, 2)
      ELSE 0 END,
    'monto_total_descuento', COALESCE((SELECT SUM(monto_descuento) FROM cupones_usos WHERE campana_id = c.id), 0),
    'monto_total_compras', COALESCE((SELECT SUM(monto_compra) FROM cupones_usos WHERE campana_id = c.id), 0),
    'ticket_promedio', COALESCE((SELECT AVG(monto_compra) FROM cupones_usos WHERE campana_id = c.id), 0),
    'clientes_unicos', (SELECT COUNT(DISTINCT contacto_id) FROM cupones_usos WHERE campana_id = c.id),
    'canales_uso', (SELECT jsonb_object_agg(canal, cnt) FROM (
      SELECT canal, COUNT(*) AS cnt FROM cupones_usos WHERE campana_id = c.id GROUP BY canal
    ) sub)
  ) INTO v_result
  FROM cupones_campanas c
  WHERE c.id = p_campana_id AND c.empresa_id = p_empresa_id;

  RETURN COALESCE(v_result, '{}'::JSONB);
END;
$$;
```

#### Triggers

```sql
-- Expirar codigos y campanas automaticamente
CREATE OR REPLACE FUNCTION trg_cupones_actualizar_estado()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  -- Si la campana llega a su fecha fin, marcar como FINALIZADA
  IF NEW.fecha_fin IS NOT NULL AND NEW.fecha_fin < now() AND NEW.estado = 'ACTIVA' THEN
    NEW.estado := 'FINALIZADA';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER tr_cupones_estado
  BEFORE UPDATE ON cupones_campanas
  FOR EACH ROW
  EXECUTE FUNCTION trg_cupones_actualizar_estado();
```

#### Vistas para Reportes

```sql
-- Vista: resumen de campanas activas
CREATE OR REPLACE VIEW v_cupones_campanas_resumen AS
SELECT
  c.empresa_id,
  c.id AS campana_id,
  c.nombre,
  c.tipo_descuento,
  c.valor_descuento,
  c.estado,
  c.fecha_inicio,
  c.fecha_fin,
  c.usos_actuales,
  c.max_usos_total,
  COALESCE(SUM(u.monto_descuento), 0) AS total_descuento_otorgado,
  COALESCE(SUM(u.monto_compra), 0) AS total_ventas_con_cupon,
  COUNT(DISTINCT u.contacto_id) AS clientes_unicos,
  (SELECT COUNT(*) FROM cupones_codigos cc WHERE cc.campana_id = c.id) AS codigos_generados,
  (SELECT COUNT(*) FROM cupones_codigos cc WHERE cc.campana_id = c.id AND cc.estado = 'USADO') AS codigos_usados
FROM cupones_campanas c
LEFT JOIN cupones_usos u ON u.campana_id = c.id
GROUP BY c.id;
```

#### Integracion Module Service Bus

```sql
-- Validar cupon desde POS o Ecommerce
CREATE OR REPLACE FUNCTION module_bus.validate_coupon(
  p_empresa_id    UUID,
  p_codigo        VARCHAR,
  p_contacto_id   UUID DEFAULT NULL,
  p_monto_compra  DECIMAL DEFAULT 0,
  p_productos     JSONB DEFAULT NULL,
  p_canal         VARCHAR DEFAULT 'POS'
) RETURNS module_bus.bus_response
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_result module_bus.bus_response;
  v_data JSONB;
BEGIN
  IF NOT module_bus.is_module_active(p_empresa_id, 'ventas') THEN
    v_result := (false, 'module_inactive', 'ventas', null);
    RETURN v_result;
  END IF;

  v_data := cupones_validar_codigo(p_empresa_id, p_codigo, p_contacto_id, p_monto_compra, p_productos, p_canal);

  v_result := (true, null, 'ventas', v_data);
  RETURN v_result;
END;
$$;

-- Aplicar cupon desde POS o Ecommerce
CREATE OR REPLACE FUNCTION module_bus.apply_coupon(
  p_empresa_id    UUID,
  p_codigo        VARCHAR,
  p_contacto_id   UUID,
  p_monto_compra  DECIMAL,
  p_monto_descuento DECIMAL,
  p_factura_id    UUID DEFAULT NULL,
  p_pos_venta_id  UUID DEFAULT NULL,
  p_canal         VARCHAR DEFAULT 'POS',
  p_usuario_id    UUID DEFAULT NULL
) RETURNS module_bus.bus_response
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_result module_bus.bus_response;
  v_uso_id UUID;
BEGIN
  IF NOT module_bus.is_module_active(p_empresa_id, 'ventas') THEN
    v_result := (false, 'module_inactive', 'ventas', null);
    RETURN v_result;
  END IF;

  v_uso_id := cupones_aplicar(
    p_empresa_id, p_codigo, p_contacto_id, p_monto_compra,
    p_monto_descuento, p_factura_id, p_pos_venta_id, p_canal, p_usuario_id
  );

  v_result := (true, null, 'ventas', jsonb_build_object('uso_id', v_uso_id));
  RETURN v_result;
END;
$$;
```

#### RLS Policies

```sql
ALTER TABLE cupones_campanas ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON cupones_campanas FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

ALTER TABLE cupones_campana_productos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON cupones_campana_productos FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

ALTER TABLE cupones_campana_categorias ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON cupones_campana_categorias FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

ALTER TABLE cupones_codigos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON cupones_codigos FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

ALTER TABLE cupones_usos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON cupones_usos FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));
```

#### Flujo UI/UX

```
features/ventas/cupones/
  screens/
    coupon_campaigns_screen.dart        # Lista de campanas (SfDataGrid)
    coupon_campaign_form_screen.dart    # Crear/editar campana + restricciones
    coupon_codes_screen.dart            # Lista de codigos por campana
    coupon_generate_dialog.dart         # Dialog generacion masiva
    coupon_usage_screen.dart            # Historial de usos con filtros
    coupon_report_screen.dart           # ROI: tasa uso, ticket promedio, descuento total
  widgets/
    coupon_validator_widget.dart        # Input de codigo con validacion en vivo
    coupon_applied_badge.dart           # Badge "CUPON APLICADO: -$X" en factura/POS
    coupon_qr_scanner.dart              # Escaner QR para POS mobile

Integracion en POS:
  - Campo de ingreso de codigo sobre la lista de items
  - Boton camara para escanear QR (mobile_scanner)
  - Al ingresar codigo valido: muestra badge con descuento calculado
  - Descuento se aplica como linea con precio negativo o descuento global
  - Al finalizar venta: cupones_aplicar() registra el uso

Integracion en Ecommerce (WooCommerce):
  - Campo de cupon en checkout sincronizado via Edge Function
  - Edge Function valida codigo → retorna descuento → WooCommerce aplica

Responsive:
  COMPACT: campo codigo + QR scanner, badge compacto
  MEDIUM: campo codigo con preview de descuento
  EXPANDED/LARGE: panel lateral con detalle campana + descuento + restricciones
```

---

