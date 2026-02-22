# Transacciones Intercompany


Funcionalidad para grupos empresariales que manejan multiples empresas en PILAR. Ventas, transferencias y prestamos entre empresas del mismo grupo con eliminacion para consolidacion.

## Transacciones Intercompany - Modelo General

### Descripcion Funcional

Las transacciones intercompany permiten a **grupos empresariales** (varias empresas juridicas bajo control comun) realizar operaciones comerciales entre si dentro de PILAR. Un usuario que administra N empresas puede iniciar una venta en Empresa A hacia Empresa B, y el sistema genera automaticamente los documentos espejo en ambas empresas.

**Escenarios tipicos en Ecuador:**
- Holding con distribuidora + puntos de venta (cada uno con RUC propio)
- Grupo con empresa importadora + comercializadora
- Matriz con sucursales juridicamente independientes (ej: franquicias)
- Empresa de servicios + empresa de personal (tercerizacion)

**Principios de diseno:**
1. Cada empresa mantiene su contabilidad independiente (RUC propio, SRI propio)
2. Las transacciones intercompany generan documentos SRI reales (factura real de A para B)
3. El precio de transferencia es configurable y auditable
4. La consolidacion elimina transacciones intercompany para reportes de grupo
5. Solo empresas del mismo grupo pueden operar entre si

**Tipos de transacciones soportadas:**

| Tipo | Empresa Origen | Empresa Destino | Documentos Generados |
|------|---------------|-----------------|---------------------|
| Venta IC | Factura de venta | Factura de compra + Retencion auto | Factura SRI (01) + Retencion (07) |
| Transferencia inventario | Guia de remision | Recepcion de mercaderia | Guia remision SRI (06) |
| Prestamo monetario | CxC | CxP | Asientos contables |
| Prestamo mercaderia | Salida inventario | Entrada inventario | Guia remision + NI |
| Nota de credito IC | NC emitida | NC recibida (ajuste compra) | NC SRI (04) |

### Modelo de Datos - Grupos Empresariales

```sql
-- ============================================================
-- MIGRACION: 026_create_intercompany.sql
-- ============================================================

-- 1. Grupos empresariales
CREATE TABLE grupos_empresariales (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre          VARCHAR(200) NOT NULL,
  descripcion     TEXT,
  empresa_holding_id UUID REFERENCES empresas(id),
  moneda_consolidacion VARCHAR(3) DEFAULT 'USD',
  activo          BOOLEAN DEFAULT true,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- No tiene empresa_id porque es transversal a multiples empresas.
-- El acceso se controla via grupo_empresas + usuarios_empresa.

-- 2. Empresas que pertenecen a un grupo
CREATE TABLE grupo_empresas (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  grupo_id        UUID NOT NULL REFERENCES grupos_empresariales(id) ON DELETE CASCADE,
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  porcentaje_participacion DECIMAL(5,2) DEFAULT 100.00,
  fecha_ingreso   DATE DEFAULT CURRENT_DATE,
  fecha_salida    DATE,
  activo          BOOLEAN DEFAULT true,
  UNIQUE(grupo_id, empresa_id)
);

CREATE INDEX idx_grupo_empresas_grupo ON grupo_empresas(grupo_id);
CREATE INDEX idx_grupo_empresas_empresa ON grupo_empresas(empresa_id);

-- 3. Configuracion de precios de transferencia entre pares de empresas
CREATE TABLE intercompany_config (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  grupo_id            UUID NOT NULL REFERENCES grupos_empresariales(id) ON DELETE CASCADE,
  empresa_origen_id   UUID NOT NULL REFERENCES empresas(id),
  empresa_destino_id  UUID NOT NULL REFERENCES empresas(id),
  metodo_precio       VARCHAR(30) NOT NULL DEFAULT 'COSTO_MAS_MARGEN',
    -- COSTO_MAS_MARGEN: costo + margen fijo o %
    -- LISTA_INTERCOMPANY: lista de precios especial
    -- PRECIO_MERCADO: precio de venta al publico
    -- COSTO_PURO: al costo sin margen
  margen_fijo         DECIMAL(14,2),
  margen_porcentaje   DECIMAL(5,2),
  lista_precios_id    UUID REFERENCES listas_precios(id),
  posicion_fiscal_id  UUID REFERENCES posiciones_fiscales(id),
  plazo_pago_dias     INTEGER DEFAULT 30,
  auto_generar_oc     BOOLEAN DEFAULT true,
  auto_generar_retencion BOOLEAN DEFAULT true,
  requiere_aprobacion BOOLEAN DEFAULT false,
  umbral_aprobacion   DECIMAL(14,2),
  activo              BOOLEAN DEFAULT true,
  created_at          TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(empresa_origen_id, empresa_destino_id),
  CHECK(empresa_origen_id != empresa_destino_id)
);

-- 4. Transacciones intercompany (registro maestro)
CREATE TABLE intercompany_transacciones (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  grupo_id            UUID NOT NULL REFERENCES grupos_empresariales(id),
  empresa_origen_id   UUID NOT NULL REFERENCES empresas(id),
  empresa_destino_id  UUID NOT NULL REFERENCES empresas(id),
  tipo                VARCHAR(30) NOT NULL,
    -- VENTA, TRANSFERENCIA_INVENTARIO, PRESTAMO_DINERO,
    -- PRESTAMO_MERCADERIA, NOTA_CREDITO, COMPENSACION
  estado              VARCHAR(20) NOT NULL DEFAULT 'BORRADOR',
    -- BORRADOR, PENDIENTE_APROBACION, APROBADA, EN_PROCESO,
    -- COMPLETADA, RECHAZADA, ANULADA
  monto_total         DECIMAL(14,2),
  moneda              VARCHAR(3) DEFAULT 'USD',
  doc_origen_tipo     VARCHAR(30),
  doc_origen_id       UUID,
  doc_destino_tipo    VARCHAR(30),
  doc_destino_id      UUID,
  aprobado_por        UUID REFERENCES auth.users(id),
  fecha_aprobacion    TIMESTAMPTZ,
  motivo_rechazo      TEXT,
  notas               TEXT,
  created_by          UUID NOT NULL REFERENCES auth.users(id),
  created_at          TIMESTAMPTZ DEFAULT NOW(),
  updated_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_ic_trans_grupo ON intercompany_transacciones(grupo_id);
CREATE INDEX idx_ic_trans_origen ON intercompany_transacciones(empresa_origen_id);
CREATE INDEX idx_ic_trans_destino ON intercompany_transacciones(empresa_destino_id);
CREATE INDEX idx_ic_trans_estado ON intercompany_transacciones(estado);

-- 5. Detalle de items en transaccion intercompany
CREATE TABLE intercompany_transaccion_lineas (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  transaccion_id      UUID NOT NULL REFERENCES intercompany_transacciones(id) ON DELETE CASCADE,
  producto_id         UUID NOT NULL REFERENCES productos(id),
  descripcion         TEXT,
  cantidad            DECIMAL(18,6) NOT NULL,
  precio_unitario     DECIMAL(14,2) NOT NULL,
  descuento           DECIMAL(14,2) DEFAULT 0,
  subtotal            DECIMAL(14,2) NOT NULL,
  iva_tarifa          DECIMAL(5,2) DEFAULT 15.00,
  iva_monto           DECIMAL(14,2) DEFAULT 0,
  total_linea         DECIMAL(14,2) NOT NULL,
  costo_unitario      DECIMAL(14,2),
  producto_destino_id UUID REFERENCES productos(id),
  created_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_ic_lineas_trans ON intercompany_transaccion_lineas(transaccion_id);

-- 6. Saldos cruzados entre empresas del grupo
CREATE TABLE intercompany_saldos (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  grupo_id            UUID NOT NULL REFERENCES grupos_empresariales(id),
  empresa_deudora_id  UUID NOT NULL REFERENCES empresas(id),
  empresa_acreedora_id UUID NOT NULL REFERENCES empresas(id),
  saldo               DECIMAL(14,2) NOT NULL DEFAULT 0,
  moneda              VARCHAR(3) DEFAULT 'USD',
  ultima_actualizacion TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(grupo_id, empresa_deudora_id, empresa_acreedora_id),
  CHECK(empresa_deudora_id != empresa_acreedora_id)
);

-- 7. Mapeo de productos entre empresas del grupo
CREATE TABLE intercompany_mapeo_productos (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  grupo_id            UUID NOT NULL REFERENCES grupos_empresariales(id) ON DELETE CASCADE,
  producto_empresa_a  UUID NOT NULL REFERENCES productos(id),
  empresa_a_id        UUID NOT NULL REFERENCES empresas(id),
  producto_empresa_b  UUID NOT NULL REFERENCES productos(id),
  empresa_b_id        UUID NOT NULL REFERENCES empresas(id),
  factor_conversion   DECIMAL(18,6) DEFAULT 1.000000,
  created_at          TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(producto_empresa_a, producto_empresa_b)
);

-- 8. Mapeo de cuentas contables entre empresas (para consolidacion)
CREATE TABLE intercompany_mapeo_cuentas (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  grupo_id            UUID NOT NULL REFERENCES grupos_empresariales(id) ON DELETE CASCADE,
  cuenta_empresa_id   UUID NOT NULL REFERENCES plan_cuentas(id),
  empresa_id          UUID NOT NULL REFERENCES empresas(id),
  cuenta_consolidada  VARCHAR(20) NOT NULL,
  naturaleza          VARCHAR(10),
  created_at          TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(cuenta_empresa_id, grupo_id)
);

-- Agregar columnas a contactos para IC
ALTER TABLE contactos
  ADD COLUMN IF NOT EXISTS es_intercompany BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS empresa_vinculada_id UUID REFERENCES empresas(id);
```

### RLS Policies - Intercompany

```sql
-- Las tablas intercompany son especiales: NO usan empresa_id simple.
-- Un usuario puede ver transacciones de cualquier empresa a la que pertenezca
-- dentro de un grupo al que tenga acceso.

-- Funcion helper: obtener grupos a los que el usuario tiene acceso
CREATE OR REPLACE FUNCTION private.get_user_grupo_ids()
RETURNS UUID[]
LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT ARRAY_AGG(DISTINCT ge.grupo_id)
  FROM grupo_empresas ge
  JOIN usuarios_empresa ue ON ue.empresa_id = ge.empresa_id
  WHERE ue.usuario_id = auth.uid()
    AND ue.activo = true
    AND ge.activo = true;
$$;

-- Funcion helper: verificar si usuario pertenece a empresa del grupo
CREATE OR REPLACE FUNCTION private.user_in_grupo(p_grupo_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT EXISTS (
    SELECT 1 FROM grupo_empresas ge
    JOIN usuarios_empresa ue ON ue.empresa_id = ge.empresa_id
    WHERE ge.grupo_id = p_grupo_id
      AND ue.usuario_id = auth.uid()
      AND ue.activo = true
      AND ge.activo = true
  );
$$;

-- RLS para todas las tablas IC
ALTER TABLE grupos_empresariales ENABLE ROW LEVEL SECURITY;
CREATE POLICY "user_in_grupo" ON grupos_empresariales
  FOR ALL TO authenticated
  USING (id = ANY(COALESCE((SELECT private.get_user_grupo_ids()), '{}'::UUID[])));

ALTER TABLE grupo_empresas ENABLE ROW LEVEL SECURITY;
CREATE POLICY "user_in_grupo" ON grupo_empresas
  FOR ALL TO authenticated
  USING ((SELECT private.user_in_grupo(grupo_id)));

ALTER TABLE intercompany_config ENABLE ROW LEVEL SECURITY;
CREATE POLICY "user_in_grupo" ON intercompany_config
  FOR ALL TO authenticated
  USING ((SELECT private.user_in_grupo(grupo_id)));

ALTER TABLE intercompany_transacciones ENABLE ROW LEVEL SECURITY;
CREATE POLICY "user_in_grupo" ON intercompany_transacciones
  FOR ALL TO authenticated
  USING ((SELECT private.user_in_grupo(grupo_id)));

ALTER TABLE intercompany_transaccion_lineas ENABLE ROW LEVEL SECURITY;
CREATE POLICY "user_in_grupo" ON intercompany_transaccion_lineas
  FOR ALL TO authenticated
  USING (
    (SELECT private.user_in_grupo(
      (SELECT grupo_id FROM intercompany_transacciones WHERE id = transaccion_id)
    ))
  );

ALTER TABLE intercompany_saldos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "user_in_grupo" ON intercompany_saldos
  FOR ALL TO authenticated
  USING ((SELECT private.user_in_grupo(grupo_id)));

ALTER TABLE intercompany_mapeo_productos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "user_in_grupo" ON intercompany_mapeo_productos
  FOR ALL TO authenticated
  USING ((SELECT private.user_in_grupo(grupo_id)));

ALTER TABLE intercompany_mapeo_cuentas ENABLE ROW LEVEL SECURITY;
CREATE POLICY "user_in_grupo" ON intercompany_mapeo_cuentas
  FOR ALL TO authenticated
  USING ((SELECT private.user_in_grupo(grupo_id)));
```

---

## Ventas Intercompany

### Descripcion Funcional

Empresa A vende a Empresa B. Al confirmar la venta en A, se genera automaticamente:
- **En Empresa A:** Factura de venta electronica SRI (con RUC de B como comprador)
- **En Empresa B:** Factura de compra (registro de proveedor) + Retencion electronica SRI

**Flujo detallado:**

```
EMPRESA A (Vendedora)                    EMPRESA B (Compradora)
---------------------                    ---------------------
1. Crear venta IC
   (seleccionar empresa destino,
    productos, cantidades)
        |
2. Calcular precios de transferencia
   (segun intercompany_config)
        |
3. Confirmar venta IC
   (requiere aprobacion si > umbral)
        |
4. Generar factura electronica ---------> 5. Crear factura de compra
   (firma XAdES, SRI, RIDE)                 (mirror de la factura de A)
        |                                         |
        |                                6. Auto-generar retencion SRI
        |                                   (segun reglas de B)
        |                                         |
        |                                7. Enviar retencion a A
        |                                         |
8. Recibir retencion <----------------------------+
   (registrar en CxC de A)
        |                                         |
9. CxC en A por el monto neto           8. CxP en B por el monto neto
        |                                         |
       [Compensacion de saldos cruzados opcional]
```

### Funciones PostgreSQL

```sql
-- ============================================================
-- RPC: Crear venta intercompany
-- ============================================================
CREATE OR REPLACE FUNCTION create_intercompany_sale(
  p_grupo_id          UUID,
  p_empresa_origen_id UUID,
  p_empresa_destino_id UUID,
  p_lineas            JSONB,
  p_notas             TEXT DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_config RECORD;
  v_trans_id UUID;
  v_linea JSONB;
  v_producto RECORD;
  v_precio DECIMAL(14,2);
  v_costo DECIMAL(14,2);
  v_subtotal DECIMAL(14,2);
  v_iva DECIMAL(14,2);
  v_total DECIMAL(14,2) := 0;
  v_producto_destino_id UUID;
BEGIN
  -- 1. Validar que ambas empresas pertenecen al grupo
  IF NOT EXISTS (SELECT 1 FROM grupo_empresas
                 WHERE grupo_id = p_grupo_id AND empresa_id = p_empresa_origen_id AND activo = true) THEN
    RAISE EXCEPTION 'Empresa origen no pertenece al grupo';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM grupo_empresas
                 WHERE grupo_id = p_grupo_id AND empresa_id = p_empresa_destino_id AND activo = true) THEN
    RAISE EXCEPTION 'Empresa destino no pertenece al grupo';
  END IF;

  -- 2. Obtener configuracion IC
  SELECT * INTO v_config FROM intercompany_config
  WHERE empresa_origen_id = p_empresa_origen_id
    AND empresa_destino_id = p_empresa_destino_id
    AND activo = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No existe configuracion intercompany entre estas empresas';
  END IF;

  -- 3. Crear transaccion IC
  INSERT INTO intercompany_transacciones (
    grupo_id, empresa_origen_id, empresa_destino_id,
    tipo, estado, created_by
  ) VALUES (
    p_grupo_id, p_empresa_origen_id, p_empresa_destino_id,
    'VENTA', 'BORRADOR', auth.uid()
  ) RETURNING id INTO v_trans_id;

  -- 4. Procesar lineas
  FOR v_linea IN SELECT * FROM jsonb_array_elements(p_lineas) LOOP
    SELECT * INTO v_producto FROM productos
    WHERE id = (v_linea ->> 'producto_id')::UUID
      AND empresa_id = p_empresa_origen_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Producto % no encontrado en empresa origen', v_linea ->> 'producto_id';
    END IF;

    v_costo := COALESCE(v_producto.costo_promedio, v_producto.precio_costo, 0);

    -- Calcular precio de transferencia
    v_precio := calculate_transfer_price(
      v_config.metodo_precio, v_costo, v_producto.precio_venta,
      v_config.margen_fijo, v_config.margen_porcentaje,
      v_config.lista_precios_id, (v_linea ->> 'producto_id')::UUID,
      (v_linea ->> 'precio_override')::DECIMAL
    );

    v_subtotal := v_precio * (v_linea ->> 'cantidad')::DECIMAL;
    v_iva := ROUND(v_subtotal * 0.15, 2);

    SELECT producto_empresa_b INTO v_producto_destino_id
    FROM intercompany_mapeo_productos
    WHERE grupo_id = p_grupo_id
      AND producto_empresa_a = v_producto.id
      AND empresa_a_id = p_empresa_origen_id
      AND empresa_b_id = p_empresa_destino_id;

    INSERT INTO intercompany_transaccion_lineas (
      transaccion_id, producto_id, descripcion, cantidad,
      precio_unitario, subtotal, iva_tarifa, iva_monto,
      total_linea, costo_unitario, producto_destino_id
    ) VALUES (
      v_trans_id, v_producto.id, v_producto.nombre,
      (v_linea ->> 'cantidad')::DECIMAL,
      v_precio, v_subtotal, 15.00, v_iva,
      v_subtotal + v_iva, v_costo, v_producto_destino_id
    );

    v_total := v_total + v_subtotal + v_iva;
  END LOOP;

  UPDATE intercompany_transacciones SET monto_total = v_total WHERE id = v_trans_id;

  IF v_config.requiere_aprobacion AND v_total >= COALESCE(v_config.umbral_aprobacion, 0) THEN
    UPDATE intercompany_transacciones
    SET estado = 'PENDIENTE_APROBACION' WHERE id = v_trans_id;
  END IF;

  RETURN v_trans_id;
END;
$$;

-- ============================================================
-- RPC: Calcular precio de transferencia
-- ============================================================
CREATE OR REPLACE FUNCTION calculate_transfer_price(
  p_metodo          VARCHAR(30),
  p_costo           DECIMAL(14,2),
  p_precio_venta    DECIMAL(14,2),
  p_margen_fijo     DECIMAL(14,2),
  p_margen_pct      DECIMAL(5,2),
  p_lista_precios_id UUID,
  p_producto_id     UUID,
  p_precio_override DECIMAL(14,2)
) RETURNS DECIMAL(14,2)
LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
  IF p_precio_override IS NOT NULL THEN RETURN p_precio_override; END IF;

  CASE p_metodo
    WHEN 'COSTO_PURO' THEN RETURN p_costo;
    WHEN 'COSTO_MAS_MARGEN' THEN
      IF p_margen_fijo IS NOT NULL THEN RETURN p_costo + p_margen_fijo;
      ELSIF p_margen_pct IS NOT NULL THEN RETURN ROUND(p_costo * (1 + p_margen_pct / 100), 2);
      ELSE RETURN p_costo;
      END IF;
    WHEN 'LISTA_INTERCOMPANY' THEN
      RETURN COALESCE(
        (SELECT precio FROM lista_precios_items
         WHERE lista_id = p_lista_precios_id AND producto_id = p_producto_id
           AND (vigencia_desde IS NULL OR vigencia_desde <= CURRENT_DATE)
           AND (vigencia_hasta IS NULL OR vigencia_hasta >= CURRENT_DATE) LIMIT 1),
        p_costo);
    WHEN 'PRECIO_MERCADO' THEN RETURN p_precio_venta;
    ELSE RETURN p_costo;
  END CASE;
END;
$$;

-- ============================================================
-- RPC: Confirmar venta intercompany (genera documentos en ambas empresas)
-- ============================================================
CREATE OR REPLACE FUNCTION confirm_intercompany_sale(
  p_transaccion_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_trans RECORD;
  v_config RECORD;
  v_factura_origen_id UUID;
  v_factura_destino_id UUID;
  v_retencion_id UUID;
  v_contacto_destino_id UUID;
  v_contacto_origen_id UUID;
BEGIN
  SELECT * INTO v_trans FROM intercompany_transacciones
  WHERE id = p_transaccion_id AND tipo = 'VENTA';
  IF NOT FOUND THEN RAISE EXCEPTION 'Transaccion IC no encontrada'; END IF;
  IF v_trans.estado NOT IN ('BORRADOR', 'APROBADA') THEN
    RAISE EXCEPTION 'Estado invalido para confirmar: %', v_trans.estado;
  END IF;

  SELECT * INTO v_config FROM intercompany_config
  WHERE empresa_origen_id = v_trans.empresa_origen_id
    AND empresa_destino_id = v_trans.empresa_destino_id;

  IF v_config.requiere_aprobacion
     AND v_trans.monto_total >= COALESCE(v_config.umbral_aprobacion, 0)
     AND v_trans.estado != 'APROBADA' THEN
    RAISE EXCEPTION 'Requiere aprobacion previa';
  END IF;

  UPDATE intercompany_transacciones SET estado = 'EN_PROCESO' WHERE id = p_transaccion_id;

  -- Buscar/crear contactos IC
  v_contacto_destino_id := find_or_create_intercompany_contact(
    v_trans.empresa_origen_id, v_trans.empresa_destino_id, 'CLIENTE');
  v_contacto_origen_id := find_or_create_intercompany_contact(
    v_trans.empresa_destino_id, v_trans.empresa_origen_id, 'PROVEEDOR');

  -- Crear factura VENTA en empresa origen (A)
  v_factura_origen_id := create_intercompany_invoice_origin(
    p_transaccion_id, v_contacto_destino_id);
  -- Crear factura COMPRA en empresa destino (B)
  v_factura_destino_id := create_intercompany_invoice_destination(
    p_transaccion_id, v_contacto_origen_id);
  -- Auto-generar retencion en B
  IF v_config.auto_generar_retencion THEN
    v_retencion_id := create_intercompany_withholding(
      p_transaccion_id, v_factura_destino_id);
  END IF;

  -- Generar CxC en A y CxP en B
  PERFORM create_intercompany_receivable_payable(
    p_transaccion_id, v_factura_origen_id, v_factura_destino_id);

  -- Actualizar saldo cruzado
  INSERT INTO intercompany_saldos (grupo_id, empresa_deudora_id, empresa_acreedora_id, saldo)
  VALUES (v_trans.grupo_id, v_trans.empresa_destino_id, v_trans.empresa_origen_id, v_trans.monto_total)
  ON CONFLICT (grupo_id, empresa_deudora_id, empresa_acreedora_id)
  DO UPDATE SET saldo = intercompany_saldos.saldo + v_trans.monto_total,
                ultima_actualizacion = NOW();

  UPDATE intercompany_transacciones
  SET estado = 'COMPLETADA',
      doc_origen_tipo = 'FACTURA', doc_origen_id = v_factura_origen_id,
      doc_destino_tipo = 'FACTURA_PROVEEDOR', doc_destino_id = v_factura_destino_id,
      updated_at = NOW()
  WHERE id = p_transaccion_id;

  RETURN jsonb_build_object(
    'transaccion_id', p_transaccion_id,
    'factura_origen_id', v_factura_origen_id,
    'factura_destino_id', v_factura_destino_id,
    'retencion_id', v_retencion_id,
    'estado', 'COMPLETADA');
END;
$$;

-- ============================================================
-- Helper: Buscar/crear contacto intercompany
-- ============================================================
CREATE OR REPLACE FUNCTION find_or_create_intercompany_contact(
  p_empresa_id         UUID,
  p_empresa_contra_id  UUID,
  p_tipo               VARCHAR(20)
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_contacto_id UUID;
  v_empresa RECORD;
BEGIN
  SELECT * INTO v_empresa FROM empresas WHERE id = p_empresa_contra_id;

  SELECT id INTO v_contacto_id FROM contactos
  WHERE empresa_id = p_empresa_id AND identificacion = v_empresa.ruc LIMIT 1;

  IF v_contacto_id IS NULL THEN
    INSERT INTO contactos (
      empresa_id, tipo, nombre, identificacion,
      tipo_identificacion, email, telefono, direccion,
      es_intercompany, empresa_vinculada_id, origen
    ) VALUES (
      p_empresa_id, p_tipo, v_empresa.razon_social,
      v_empresa.ruc, '04', v_empresa.email,
      v_empresa.telefono, v_empresa.direccion,
      true, p_empresa_contra_id, 'INTERCOMPANY'
    ) RETURNING id INTO v_contacto_id;
  END IF;

  RETURN v_contacto_id;
END;
$$;
```

### Triggers

```sql
-- Audit trail para transacciones IC
CREATE OR REPLACE FUNCTION trg_intercompany_audit()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.estado IS DISTINCT FROM NEW.estado THEN
    INSERT INTO registro_actividad (
      tabla, registro_id, empresa_id, accion, usuario_id, datos_nuevos
    ) VALUES (
      'intercompany_transacciones', NEW.id, NEW.empresa_origen_id,
      'IC_CAMBIO_ESTADO', COALESCE(auth.uid(), NEW.created_by),
      jsonb_build_object(
        'estado_anterior', OLD.estado, 'estado_nuevo', NEW.estado,
        'tipo', NEW.tipo, 'empresa_destino', NEW.empresa_destino_id,
        'monto', NEW.monto_total));
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_ic_transaccion_audit
  AFTER UPDATE ON intercompany_transacciones
  FOR EACH ROW EXECUTE FUNCTION trg_intercompany_audit();
```

### Vistas

```sql
-- Resumen de transacciones IC por grupo
CREATE OR REPLACE VIEW v_intercompany_resumen AS
SELECT
  t.grupo_id, g.nombre AS grupo_nombre,
  t.empresa_origen_id, eo.razon_social AS empresa_origen,
  t.empresa_destino_id, ed.razon_social AS empresa_destino,
  t.tipo, t.estado,
  COUNT(*) AS num_transacciones,
  SUM(t.monto_total) AS monto_total,
  MIN(t.created_at) AS primera_transaccion,
  MAX(t.created_at) AS ultima_transaccion
FROM intercompany_transacciones t
JOIN grupos_empresariales g ON g.id = t.grupo_id
JOIN empresas eo ON eo.id = t.empresa_origen_id
JOIN empresas ed ON ed.id = t.empresa_destino_id
GROUP BY t.grupo_id, g.nombre, t.empresa_origen_id, eo.razon_social,
         t.empresa_destino_id, ed.razon_social, t.tipo, t.estado;

-- Saldos cruzados del grupo
CREATE OR REPLACE VIEW v_intercompany_saldos AS
SELECT
  s.grupo_id, g.nombre AS grupo_nombre,
  ed.razon_social AS empresa_deudora,
  ea.razon_social AS empresa_acreedora,
  s.saldo, s.moneda, s.ultima_actualizacion
FROM intercompany_saldos s
JOIN grupos_empresariales g ON g.id = s.grupo_id
JOIN empresas ed ON ed.id = s.empresa_deudora_id
JOIN empresas ea ON ea.id = s.empresa_acreedora_id
WHERE s.saldo != 0
ORDER BY s.grupo_id, ABS(s.saldo) DESC;
```

### Integracion Module Service Bus

```sql
CREATE OR REPLACE FUNCTION module_bus.create_intercompany_sale(
  p_empresa_id         UUID,
  p_grupo_id           UUID,
  p_empresa_destino_id UUID,
  p_lineas             JSONB,
  p_notas              TEXT DEFAULT NULL
) RETURNS module_bus.bus_response
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_result module_bus.bus_response;
  v_trans_id UUID;
BEGIN
  -- Intercompany no es modulo activable; verificar pertenencia al grupo
  IF NOT EXISTS (SELECT 1 FROM grupo_empresas
                 WHERE grupo_id = p_grupo_id AND empresa_id = p_empresa_id AND activo = true) THEN
    v_result := (false, 'empresa_not_in_grupo', 'intercompany', null);
    RETURN v_result;
  END IF;

  v_trans_id := create_intercompany_sale(
    p_grupo_id, p_empresa_id, p_empresa_destino_id, p_lineas, p_notas);

  v_result := (true, null, 'intercompany',
    jsonb_build_object('transaccion_id', v_trans_id));
  RETURN v_result;
END;
$$;
```

### Flujo UI/UX

```
MENU: Administracion > Intercompany

+-- Grupo Empresarial
|   +-- Detalle grupo (nombre, empresa holding, empresas miembro)
|   +-- + Agregar empresa al grupo
|   +-- Configurar pares IC (origen-destino, metodo precio, margen, aprobacion)
|
+-- Transacciones IC
|   +-- Lista (DataGrid: fecha, tipo, origen, destino, monto, estado)
|   +-- Filtros: tipo, estado, empresa, periodo
|   +-- + Nueva venta IC (wizard):
|   |   1. Seleccionar empresa destino
|   |   2. Agregar productos (precio calculado automaticamente)
|   |   3. Revisar totales y precio de transferencia
|   |   4. Confirmar (si requiere aprobacion -> cola de aprobaciones)
|   +-- Detalle transaccion:
|       - Datos generales + lineas
|       - Documentos generados (factura origen, factura destino, retencion)
|       - Timeline de estados
|       - Botones: Aprobar | Rechazar | Confirmar | Anular
|
+-- Saldos Cruzados
|   +-- Matriz de saldos (empresa vs empresa)
|   +-- Detalle de movimientos
|   +-- Compensar saldos (seleccionar pares -> generar asientos de compensacion)
|
+-- Mapeo Productos
|   +-- Lista de equivalencias de productos entre empresas
|   +-- Wizard de mapeo masivo (por SKU, nombre similar)
|
+-- Reportes IC
    +-- Resumen transacciones por periodo
    +-- Saldos pendientes
    +-- Eliminacion IC para consolidacion (preview)
```

---

## Transferencias Intercompany de Inventario

### Descripcion Funcional

Transferencia de mercaderia entre bodegas de diferentes empresas del mismo grupo. Genera documentos reales:

- **Empresa origen (A):** Guia de remision electronica SRI + salida de inventario
- **Empresa destino (B):** Recepcion de mercaderia + entrada de inventario

**Valoracion:**
- Al costo de A (sin margen): transferencia interna de grupo
- Al precio de transferencia: si se quiere registrar margen (genera factura IC ademas de guia)

### Funcion PostgreSQL

```sql
CREATE OR REPLACE FUNCTION create_intercompany_transfer(
  p_grupo_id            UUID,
  p_empresa_origen_id   UUID,
  p_bodega_origen_id    UUID,
  p_empresa_destino_id  UUID,
  p_bodega_destino_id   UUID,
  p_lineas              JSONB,
  p_valoracion          VARCHAR(20) DEFAULT 'COSTO',
  p_notas               TEXT DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_trans_id UUID;
  v_linea JSONB;
  v_producto RECORD;
  v_costo DECIMAL(14,2);
  v_total DECIMAL(14,2) := 0;
BEGIN
  -- Validar grupo, empresas y bodegas (similar a venta IC)
  -- ... (validaciones omitidas por brevedad, misma logica que create_intercompany_sale)

  INSERT INTO intercompany_transacciones (
    grupo_id, empresa_origen_id, empresa_destino_id,
    tipo, estado, notas, created_by
  ) VALUES (
    p_grupo_id, p_empresa_origen_id, p_empresa_destino_id,
    'TRANSFERENCIA_INVENTARIO', 'BORRADOR', p_notas, auth.uid()
  ) RETURNING id INTO v_trans_id;

  FOR v_linea IN SELECT * FROM jsonb_array_elements(p_lineas) LOOP
    SELECT * INTO v_producto FROM productos
    WHERE id = (v_linea ->> 'producto_id')::UUID AND empresa_id = p_empresa_origen_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Producto no encontrado en empresa origen'; END IF;

    v_costo := COALESCE(v_producto.costo_promedio, v_producto.precio_costo, 0);

    INSERT INTO intercompany_transaccion_lineas (
      transaccion_id, producto_id, descripcion, cantidad,
      precio_unitario, subtotal, iva_tarifa, iva_monto,
      total_linea, costo_unitario, producto_destino_id
    ) VALUES (
      v_trans_id, v_producto.id, v_producto.nombre,
      (v_linea ->> 'cantidad')::DECIMAL,
      v_costo, v_costo * (v_linea ->> 'cantidad')::DECIMAL,
      0, 0, v_costo * (v_linea ->> 'cantidad')::DECIMAL, v_costo,
      (SELECT producto_empresa_b FROM intercompany_mapeo_productos
       WHERE grupo_id = p_grupo_id AND producto_empresa_a = v_producto.id
         AND empresa_b_id = p_empresa_destino_id)
    );
    v_total := v_total + v_costo * (v_linea ->> 'cantidad')::DECIMAL;
  END LOOP;

  UPDATE intercompany_transacciones SET monto_total = v_total WHERE id = v_trans_id;
  RETURN v_trans_id;
END;
$$;

-- Confirmar transferencia: genera guia remision + recepcion + kardex
CREATE OR REPLACE FUNCTION confirm_intercompany_transfer(
  p_transaccion_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_trans RECORD;
BEGIN
  SELECT * INTO v_trans FROM intercompany_transacciones
  WHERE id = p_transaccion_id AND tipo = 'TRANSFERENCIA_INVENTARIO';
  IF NOT FOUND OR v_trans.estado NOT IN ('BORRADOR', 'APROBADA') THEN
    RAISE EXCEPTION 'Transaccion no valida para confirmar';
  END IF;

  UPDATE intercompany_transacciones SET estado = 'EN_PROCESO' WHERE id = p_transaccion_id;

  -- 1. Generar guia de remision SRI en empresa origen
  -- 2. Descontar stock en bodega origen + registrar kardex
  -- 3. Ingresar stock en bodega destino + registrar kardex
  -- 4. Contabilizar en ambas empresas
  -- (Cada paso delega a module_bus.* existentes, ejecutados
  --  con SECURITY DEFINER para operar cross-empresa)

  UPDATE intercompany_transacciones
  SET estado = 'COMPLETADA', doc_origen_tipo = 'GUIA_REMISION', updated_at = NOW()
  WHERE id = p_transaccion_id;

  RETURN jsonb_build_object('transaccion_id', p_transaccion_id, 'estado', 'COMPLETADA');
END;
$$;
```

---

## Prestamos Intercompany

### Descripcion Funcional

Empresa A presta dinero o mercaderia a Empresa B dentro del mismo grupo.

**Prestamo monetario:**
- A registra CxC intercompany (activo)
- B registra CxP intercompany (pasivo)
- Intereses configurables (tasa anual, periodo de calculo)
- Amortizacion: tabla generada automaticamente
- Compensacion: los saldos se pueden netear contra otras transacciones IC

**Prestamo de mercaderia:**
- Similar a transferencia pero con obligacion de devolucion
- Valoracion al costo
- Control de vencimiento (plazo para devolver o comprar)

### Modelo de Datos

```sql
CREATE TABLE intercompany_prestamos (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  transaccion_id      UUID NOT NULL REFERENCES intercompany_transacciones(id),
  tipo_prestamo       VARCHAR(20) NOT NULL, -- DINERO, MERCADERIA
  monto_principal     DECIMAL(14,2) NOT NULL,
  tasa_interes_anual  DECIMAL(5,2) DEFAULT 0,
  plazo_meses         INTEGER NOT NULL DEFAULT 12,
  fecha_desembolso    DATE NOT NULL,
  fecha_vencimiento   DATE NOT NULL,
  saldo_pendiente     DECIMAL(14,2) NOT NULL,
  estado              VARCHAR(20) DEFAULT 'VIGENTE',
    -- VIGENTE, PAGADO, VENCIDO, CANCELADO, COMPENSADO
  created_at          TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE intercompany_prestamos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "user_in_grupo" ON intercompany_prestamos
  FOR ALL TO authenticated
  USING ((SELECT private.user_in_grupo(
    (SELECT grupo_id FROM intercompany_transacciones WHERE id = transaccion_id))));

CREATE TABLE intercompany_prestamo_cuotas (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  prestamo_id         UUID NOT NULL REFERENCES intercompany_prestamos(id) ON DELETE CASCADE,
  numero_cuota        INTEGER NOT NULL,
  fecha_vencimiento   DATE NOT NULL,
  monto_capital       DECIMAL(14,2) NOT NULL,
  monto_interes       DECIMAL(14,2) NOT NULL DEFAULT 0,
  monto_total         DECIMAL(14,2) NOT NULL,
  saldo_despues       DECIMAL(14,2) NOT NULL,
  estado              VARCHAR(15) DEFAULT 'PENDIENTE', -- PENDIENTE, PAGADA, VENCIDA
  fecha_pago          DATE,
  created_at          TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE intercompany_prestamo_cuotas ENABLE ROW LEVEL SECURITY;
CREATE POLICY "user_in_grupo" ON intercompany_prestamo_cuotas
  FOR ALL TO authenticated
  USING ((SELECT private.user_in_grupo(
    (SELECT t.grupo_id FROM intercompany_transacciones t
     JOIN intercompany_prestamos p ON p.transaccion_id = t.id
     WHERE p.id = prestamo_id))));

CREATE INDEX idx_ic_prestamo_cuotas ON intercompany_prestamo_cuotas(prestamo_id, numero_cuota);
```

### Funcion: Generar Tabla de Amortizacion

```sql
CREATE OR REPLACE FUNCTION generate_intercompany_amortization(
  p_prestamo_id UUID
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_prestamo RECORD;
  v_cuota_capital DECIMAL(14,2);
  v_interes_mensual DECIMAL(14,6);
  v_saldo DECIMAL(14,2);
  v_fecha DATE;
  i INTEGER;
BEGIN
  SELECT * INTO v_prestamo FROM intercompany_prestamos WHERE id = p_prestamo_id;
  v_saldo := v_prestamo.monto_principal;
  v_cuota_capital := ROUND(v_prestamo.monto_principal / v_prestamo.plazo_meses, 2);
  v_interes_mensual := v_prestamo.tasa_interes_anual / 12 / 100;
  v_fecha := v_prestamo.fecha_desembolso;

  DELETE FROM intercompany_prestamo_cuotas WHERE prestamo_id = p_prestamo_id;

  FOR i IN 1..v_prestamo.plazo_meses LOOP
    v_fecha := v_fecha + INTERVAL '1 month';
    IF i = v_prestamo.plazo_meses THEN v_cuota_capital := v_saldo; END IF;

    INSERT INTO intercompany_prestamo_cuotas (
      prestamo_id, numero_cuota, fecha_vencimiento,
      monto_capital, monto_interes, monto_total, saldo_despues
    ) VALUES (
      p_prestamo_id, i, v_fecha,
      v_cuota_capital, ROUND(v_saldo * v_interes_mensual, 2),
      v_cuota_capital + ROUND(v_saldo * v_interes_mensual, 2),
      v_saldo - v_cuota_capital
    );
    v_saldo := v_saldo - v_cuota_capital;
  END LOOP;
END;
$$;
```

---

## Consolidacion de Grupo

### Descripcion Funcional

Reporte consolidado que suma los estados financieros de todas las empresas del grupo, eliminando las transacciones intercompany para evitar doble contabilizacion.

**Reportes consolidados:**
- Balance General Consolidado
- Estado de Resultados Consolidado
- Flujo de Efectivo Consolidado (futuro)
- Detalle de eliminaciones IC

**Proceso de consolidacion:**
1. Sumar balances de todas las empresas del grupo
2. Identificar transacciones IC (via `intercompany_transacciones`)
3. Eliminar CxC IC de A contra CxP IC de B
4. Eliminar ventas IC de A contra compras IC de B
5. Eliminar utilidad interna (margen IC en inventario no vendido a terceros)
6. Ajustar por porcentaje de participacion (si < 100%)

### Funcion: Balance Consolidado

```sql
CREATE OR REPLACE FUNCTION get_consolidated_balance(
  p_grupo_id    UUID,
  p_fecha_corte DATE
) RETURNS TABLE (
  cuenta_consolidada VARCHAR(20),
  nombre_cuenta      TEXT,
  saldo_individual   DECIMAL(14,2),
  eliminacion_ic     DECIMAL(14,2),
  saldo_consolidado  DECIMAL(14,2)
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN QUERY
  WITH saldos_empresas AS (
    SELECT
      COALESCE(mc.cuenta_consolidada, pc.codigo) AS cuenta_cod,
      pc.nombre,
      SUM(
        COALESCE(
          (SELECT SUM(al.debe - al.haber)
           FROM asiento_lineas al
           JOIN asientos_contables ac ON ac.id = al.asiento_id
           WHERE al.cuenta_id = pc.id
             AND ac.empresa_id = ge.empresa_id
             AND ac.estado = 'CONTABILIZADO'
             AND ac.fecha <= p_fecha_corte), 0
        ) * (ge.porcentaje_participacion / 100)
      ) AS saldo
    FROM grupo_empresas ge
    JOIN plan_cuentas pc ON pc.empresa_id = ge.empresa_id
    LEFT JOIN intercompany_mapeo_cuentas mc ON mc.cuenta_empresa_id = pc.id
      AND mc.grupo_id = p_grupo_id
    WHERE ge.grupo_id = p_grupo_id AND ge.activo = true
    GROUP BY COALESCE(mc.cuenta_consolidada, pc.codigo), pc.nombre
  ),
  eliminaciones_ic AS (
    SELECT
      COALESCE(mc.cuenta_consolidada, '999999') AS cuenta_cod,
      SUM(CASE WHEN t.tipo = 'VENTA' THEN t.monto_total ELSE 0 END) AS monto_ventas_ic,
      SUM(CASE WHEN t.tipo = 'PRESTAMO_DINERO' THEN t.monto_total ELSE 0 END) AS monto_prestamos_ic
    FROM intercompany_transacciones t
    LEFT JOIN intercompany_mapeo_cuentas mc ON mc.grupo_id = t.grupo_id
    WHERE t.grupo_id = p_grupo_id AND t.estado = 'COMPLETADA'
      AND t.created_at::DATE <= p_fecha_corte
    GROUP BY COALESCE(mc.cuenta_consolidada, '999999')
  )
  SELECT
    se.cuenta_cod::VARCHAR(20),
    se.nombre,
    se.saldo,
    COALESCE(ei.monto_ventas_ic, 0)::DECIMAL(14,2),
    (se.saldo - COALESCE(ei.monto_ventas_ic, 0))::DECIMAL(14,2)
  FROM saldos_empresas se
  LEFT JOIN eliminaciones_ic ei ON ei.cuenta_cod = se.cuenta_cod
  ORDER BY se.cuenta_cod;
END;
$$;

-- Vista: eliminaciones IC detalladas
CREATE OR REPLACE VIEW v_eliminaciones_intercompany AS
SELECT
  t.grupo_id, g.nombre AS grupo_nombre, t.tipo,
  eo.razon_social AS empresa_origen,
  ed.razon_social AS empresa_destino,
  t.monto_total, t.created_at AS fecha,
  CASE t.tipo
    WHEN 'VENTA' THEN 'Eliminar ingreso en origen + costo en destino'
    WHEN 'NOTA_CREDITO' THEN 'Reversar eliminacion proporcional'
    WHEN 'PRESTAMO_DINERO' THEN 'Eliminar CxC en acreedor + CxP en deudor'
    ELSE 'Eliminacion generica'
  END AS tipo_eliminacion
FROM intercompany_transacciones t
JOIN grupos_empresariales g ON g.id = t.grupo_id
JOIN empresas eo ON eo.id = t.empresa_origen_id
JOIN empresas ed ON ed.id = t.empresa_destino_id
WHERE t.estado = 'COMPLETADA';
```

### Edge Functions Intercompany

```
No se requieren Edge Functions externas para intercompany.
Toda la logica se ejecuta en PostgreSQL via RPCs.

Opcionales:
1. intercompany-report/index.ts
   - Genera PDF consolidado del grupo (Syncfusion server-side)
   - POST /functions/v1/intercompany-report
   - verify_jwt: true

2. intercompany-notifications/index.ts
   - Cron diario: detecta cuotas IC vencidas, saldos > umbral
   - Envia notificacion a usuarios del grupo
```

---




