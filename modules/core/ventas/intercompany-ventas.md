# Transacciones Intercompany (Ventas)


#### Descripcion Funcional

Para grupos empresariales donde un usuario gestiona multiples empresas en PILAR. Cuando empresa A vende a empresa B (ambas del mismo grupo), el sistema genera automaticamente el documento espejo en la empresa compradora. Esto elimina la doble digitacion y asegura consistencia.

**Escenarios:**
1. **Venta A -> Compra B:** Factura de venta en A genera factura de compra en B automaticamente
2. **Transferencia de inventario:** Mercaderia de bodega A a bodega B entre empresas
3. **Precios de transferencia:** Precios especiales configurados entre empresas del grupo
4. **Documentos SRI cruzados:** La factura de A es el documento de compra en B (misma clave de acceso)

**Requisitos:**
- Un usuario debe tener acceso a ambas empresas (via `usuarios_empresa`)
- Las empresas deben estar configuradas como "grupo empresarial"
- Los precios de transferencia se configuran aparte de las listas de precios regulares
- Cada empresa mantiene su propia contabilidad (no se fusionan cuentas)
- En consolidacion contable se eliminan las operaciones intercompany

**Flujo principal:**

```
CONFIGURACION:
  Admin define grupo empresarial → agrega empresas al grupo
  → configura precios de transferencia (opcional, default: precio de lista)
  → configura cuentas contables intercompany

VENTA INTERCOMPANY:
  1. Usuario en Empresa A crea factura de venta a Empresa B
  2. Sistema detecta que el contacto es una empresa del grupo
  3. Al confirmar factura en A:
     a. Se emite factura electronica SRI normalmente (empresa A como emisor)
     b. Trigger crea automaticamente en Empresa B:
        - Factura de compra (como factura recibida)
        - CxP al proveedor (Empresa A)
        - Asiento contable de compra
  4. El XML autorizado de la factura de A se vincula automaticamente como
     documento de compra en B (sin necesidad de importar XML)

ELIMINACION EN CONSOLIDACION:
  - Reporte consolidado elimina CxC de A con CxP de B
  - Elimina ingreso de A con gasto de B
  - Solo queda el efecto neto para el grupo
```

#### Modelo de Datos SQL

```sql
-- ══════════════════════════════════════════════════════════════════
-- TRANSACCIONES INTERCOMPANY (22.5)
-- ══════════════════════════════════════════════════════════════════

-- Grupo empresarial
CREATE TABLE grupos_empresariales (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre              VARCHAR(200) NOT NULL,
  codigo              VARCHAR(20) NOT NULL UNIQUE,
  descripcion         TEXT,
  -- Empresa controladora (casa matriz del grupo)
  empresa_matriz_id   UUID NOT NULL REFERENCES empresas(id),
  -- Configuracion
  auto_crear_espejo   BOOLEAN DEFAULT true,              -- Crear doc espejo automaticamente?
  validar_precios_transferencia BOOLEAN DEFAULT false,    -- Requiere precio de transferencia?
  -- Estado
  activo              BOOLEAN DEFAULT true,
  created_at          TIMESTAMPTZ DEFAULT now(),
  updated_at          TIMESTAMPTZ DEFAULT now()
);

-- Empresas del grupo
CREATE TABLE grupo_empresas (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  grupo_id            UUID NOT NULL REFERENCES grupos_empresariales(id) ON DELETE CASCADE,
  empresa_id          UUID NOT NULL REFERENCES empresas(id),
  -- Contacto de esta empresa en las otras empresas del grupo
  -- (cada empresa aparece como contacto/proveedor en las demas)
  -- Se vincula automaticamente al crear el registro
  activo              BOOLEAN DEFAULT true,
  fecha_ingreso       DATE DEFAULT CURRENT_DATE,
  created_at          TIMESTAMPTZ DEFAULT now(),
  UNIQUE(grupo_id, empresa_id)
);

-- Mapeo de contactos intercompany
-- Vincula: "Empresa A como contacto en Empresa B" y viceversa
CREATE TABLE intercompany_contactos (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  grupo_id            UUID NOT NULL REFERENCES grupos_empresariales(id),
  -- Empresa origen (la que se representa como contacto)
  empresa_origen_id   UUID NOT NULL REFERENCES empresas(id),
  -- Empresa destino (donde aparece como contacto)
  empresa_destino_id  UUID NOT NULL REFERENCES empresas(id),
  -- Contacto que representa a empresa_origen en empresa_destino
  contacto_id         UUID NOT NULL REFERENCES contactos(id),
  created_at          TIMESTAMPTZ DEFAULT now(),
  UNIQUE(grupo_id, empresa_origen_id, empresa_destino_id)
);

-- Precios de transferencia entre empresas del grupo
CREATE TABLE intercompany_precios (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  grupo_id            UUID NOT NULL REFERENCES grupos_empresariales(id),
  empresa_vendedora_id UUID NOT NULL REFERENCES empresas(id),
  empresa_compradora_id UUID NOT NULL REFERENCES empresas(id),
  producto_id         UUID NOT NULL REFERENCES productos(id),
  -- Precio de transferencia
  metodo_precio       VARCHAR(20) DEFAULT 'COSTO_MAS_MARGEN',
    -- COSTO_MAS_MARGEN: costo + X% margen
    -- PRECIO_FIJO: precio fijo acordado
    -- PRECIO_LISTA: usa la lista de precios configurada
    -- MERCADO: precio de mercado (referencia)
  precio_fijo         DECIMAL(14,2),                     -- Si metodo = PRECIO_FIJO
  margen_porcentaje   DECIMAL(5,2),                      -- Si metodo = COSTO_MAS_MARGEN
  lista_precios_id    UUID REFERENCES listas_precios(id), -- Si metodo = PRECIO_LISTA
  -- Vigencia
  vigencia_desde      DATE NOT NULL DEFAULT CURRENT_DATE,
  vigencia_hasta      DATE,
  activo              BOOLEAN DEFAULT true,
  created_at          TIMESTAMPTZ DEFAULT now(),
  UNIQUE(grupo_id, empresa_vendedora_id, empresa_compradora_id, producto_id)
);

-- Cuentas contables intercompany (por empresa)
CREATE TABLE intercompany_cuentas (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  grupo_id            UUID NOT NULL REFERENCES grupos_empresariales(id),
  empresa_id          UUID NOT NULL REFERENCES empresas(id),
  -- Cuentas para operaciones intercompany
  cuenta_cxc_ic       UUID REFERENCES cuentas_contables(id), -- CxC intercompany (activo)
  cuenta_cxp_ic       UUID REFERENCES cuentas_contables(id), -- CxP intercompany (pasivo)
  cuenta_ingreso_ic   UUID REFERENCES cuentas_contables(id), -- Ingreso intercompany
  cuenta_gasto_ic     UUID REFERENCES cuentas_contables(id), -- Gasto/costo intercompany
  created_at          TIMESTAMPTZ DEFAULT now(),
  UNIQUE(grupo_id, empresa_id)
);

-- Transacciones intercompany (registro de operaciones cruzadas)
CREATE TABLE intercompany_transacciones (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  grupo_id            UUID NOT NULL REFERENCES grupos_empresariales(id),
  -- Empresa vendedora (origen)
  empresa_origen_id   UUID NOT NULL REFERENCES empresas(id),
  documento_origen_tipo VARCHAR(20) NOT NULL,
    -- FACTURA, NOTA_CREDITO, NOTA_DEBITO, TRANSFERENCIA_INV
  documento_origen_id UUID NOT NULL,                     -- ID de la factura/NC/ND/transferencia en empresa origen
  -- Empresa compradora (destino)
  empresa_destino_id  UUID NOT NULL REFERENCES empresas(id),
  documento_destino_tipo VARCHAR(20),
  documento_destino_id UUID,                             -- ID del documento espejo en empresa destino
  -- Montos
  monto_total         DECIMAL(14,2) NOT NULL,
  moneda              VARCHAR(10) DEFAULT 'USD',
  -- Estado
  estado              VARCHAR(20) DEFAULT 'PENDIENTE',
    -- PENDIENTE: documento origen creado, espejo pendiente
    -- PROCESADO: documento espejo creado exitosamente
    -- ERROR: error al crear espejo
    -- ANULADO: anulado en ambas empresas
  error_detalle       TEXT,
  -- Consolidacion
  eliminado_consolidacion BOOLEAN DEFAULT false,         -- Marcado para eliminar en consolidacion
  -- Metadata
  procesado_por       UUID REFERENCES auth.users(id),
  created_at          TIMESTAMPTZ DEFAULT now(),
  updated_at          TIMESTAMPTZ DEFAULT now()
);

-- Indices
CREATE INDEX idx_grupo_empresas_grupo ON grupo_empresas(grupo_id);
CREATE INDEX idx_grupo_empresas_empresa ON grupo_empresas(empresa_id);
CREATE INDEX idx_ic_contactos_destino ON intercompany_contactos(empresa_destino_id, contacto_id);
CREATE INDEX idx_ic_transacciones_origen ON intercompany_transacciones(empresa_origen_id, documento_origen_id);
CREATE INDEX idx_ic_transacciones_destino ON intercompany_transacciones(empresa_destino_id, documento_destino_id);
CREATE INDEX idx_ic_transacciones_consolidacion ON intercompany_transacciones(grupo_id, estado)
  WHERE eliminado_consolidacion = false;
```

#### Funciones PostgreSQL Principales

```sql
-- Detectar si una venta es intercompany
CREATE OR REPLACE FUNCTION intercompany_detectar(
  p_empresa_id  UUID,
  p_contacto_id UUID
) RETURNS JSONB -- {es_intercompany, grupo_id, empresa_destino_id}
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_result JSONB;
BEGIN
  SELECT jsonb_build_object(
    'es_intercompany', true,
    'grupo_id', ic.grupo_id,
    'empresa_destino_id', ic.empresa_origen_id,
    'grupo_nombre', g.nombre
  ) INTO v_result
  FROM intercompany_contactos ic
  JOIN grupos_empresariales g ON g.id = ic.grupo_id AND g.activo = true
  WHERE ic.empresa_destino_id = p_empresa_id
    AND ic.contacto_id = p_contacto_id;

  IF v_result IS NULL THEN
    RETURN jsonb_build_object('es_intercompany', false);
  END IF;

  RETURN v_result;
END;
$$;

-- Obtener precio de transferencia para un producto
CREATE OR REPLACE FUNCTION intercompany_obtener_precio(
  p_grupo_id          UUID,
  p_empresa_vendedora UUID,
  p_empresa_compradora UUID,
  p_producto_id       UUID
) RETURNS DECIMAL(14,2)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_config intercompany_precios%ROWTYPE;
  v_precio DECIMAL(14,2);
  v_costo DECIMAL(18,6);
BEGIN
  SELECT * INTO v_config FROM intercompany_precios
  WHERE grupo_id = p_grupo_id
    AND empresa_vendedora_id = p_empresa_vendedora
    AND empresa_compradora_id = p_empresa_compradora
    AND producto_id = p_producto_id
    AND activo = true
    AND vigencia_desde <= CURRENT_DATE
    AND (vigencia_hasta IS NULL OR vigencia_hasta >= CURRENT_DATE)
  LIMIT 1;

  IF NOT FOUND THEN
    -- Sin precio de transferencia: usar precio regular del producto
    SELECT precio_unitario INTO v_precio FROM productos
    WHERE id = p_producto_id AND empresa_id = p_empresa_vendedora;
    RETURN COALESCE(v_precio, 0);
  END IF;

  CASE v_config.metodo_precio
    WHEN 'PRECIO_FIJO' THEN
      RETURN v_config.precio_fijo;
    WHEN 'COSTO_MAS_MARGEN' THEN
      SELECT costo_promedio INTO v_costo FROM productos
      WHERE id = p_producto_id AND empresa_id = p_empresa_vendedora;
      RETURN ROUND(COALESCE(v_costo, 0) * (1 + v_config.margen_porcentaje / 100), 2);
    WHEN 'PRECIO_LISTA' THEN
      -- Buscar en lista de precios configurada
      SELECT precio INTO v_precio FROM lista_precios_productos
      WHERE lista_id = v_config.lista_precios_id AND producto_id = p_producto_id;
      RETURN COALESCE(v_precio, 0);
    ELSE
      SELECT precio_unitario INTO v_precio FROM productos
      WHERE id = p_producto_id AND empresa_id = p_empresa_vendedora;
      RETURN COALESCE(v_precio, 0);
  END CASE;
END;
$$;

-- Crear documento espejo en la empresa destino
CREATE OR REPLACE FUNCTION intercompany_crear_espejo(
  p_empresa_origen_id   UUID,
  p_factura_id          UUID  -- Factura emitida en empresa origen
) RETURNS UUID -- ID de la transaccion intercompany
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_factura RECORD;
  v_ic_info JSONB;
  v_grupo_id UUID;
  v_empresa_destino_id UUID;
  v_contacto_origen_en_destino UUID;
  v_cuentas_destino RECORD;
  v_tx_id UUID;
BEGIN
  -- Obtener factura
  SELECT f.*, c.id AS contacto_id_factura
  INTO v_factura FROM facturas f
  JOIN contactos c ON c.id = f.contacto_id
  WHERE f.id = p_factura_id AND f.empresa_id = p_empresa_origen_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Factura no encontrada';
  END IF;

  -- Detectar intercompany
  v_ic_info := intercompany_detectar(p_empresa_origen_id, v_factura.contacto_id_factura);
  IF NOT (v_ic_info->>'es_intercompany')::BOOLEAN THEN
    RAISE EXCEPTION 'Factura no es intercompany';
  END IF;

  v_grupo_id := (v_ic_info->>'grupo_id')::UUID;
  v_empresa_destino_id := (v_ic_info->>'empresa_destino_id')::UUID;

  -- Obtener contacto que representa empresa origen en empresa destino
  SELECT contacto_id INTO v_contacto_origen_en_destino
  FROM intercompany_contactos
  WHERE grupo_id = v_grupo_id
    AND empresa_origen_id = p_empresa_origen_id
    AND empresa_destino_id = v_empresa_destino_id;

  IF v_contacto_origen_en_destino IS NULL THEN
    RAISE EXCEPTION 'Contacto intercompany no configurado para empresa origen en destino';
  END IF;

  -- Registrar transaccion (estado PENDIENTE)
  INSERT INTO intercompany_transacciones (
    grupo_id, empresa_origen_id, documento_origen_tipo, documento_origen_id,
    empresa_destino_id, monto_total, estado
  ) VALUES (
    v_grupo_id, p_empresa_origen_id, 'FACTURA', p_factura_id,
    v_empresa_destino_id, v_factura.importe_total, 'PENDIENTE'
  ) RETURNING id INTO v_tx_id;

  -- Crear factura de compra en empresa destino
  -- NOTA: Esto requiere ejecutar en contexto de empresa destino
  -- Se implementa via Edge Function que puede cambiar de empresa
  -- Aqui solo registramos la transaccion pendiente

  -- El procesamiento real se hace en la Edge Function `process-intercompany`
  -- que tiene acceso SECURITY DEFINER y puede operar en cualquier empresa

  RETURN v_tx_id;
END;
$$;

-- Reporte de eliminacion intercompany para consolidacion
CREATE OR REPLACE FUNCTION intercompany_reporte_consolidacion(
  p_grupo_id      UUID,
  p_fecha_desde   DATE,
  p_fecha_hasta   DATE
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN (
    SELECT jsonb_build_object(
      'grupo', g.nombre,
      'periodo', format('%s al %s', p_fecha_desde, p_fecha_hasta),
      'transacciones', (
        SELECT jsonb_agg(jsonb_build_object(
          'empresa_origen', eo.razon_social,
          'empresa_destino', ed.razon_social,
          'tipo', t.documento_origen_tipo,
          'monto', t.monto_total,
          'fecha', t.created_at
        ))
        FROM intercompany_transacciones t
        JOIN empresas eo ON eo.id = t.empresa_origen_id
        JOIN empresas ed ON ed.id = t.empresa_destino_id
        WHERE t.grupo_id = p_grupo_id
          AND t.estado = 'PROCESADO'
          AND t.created_at::DATE BETWEEN p_fecha_desde AND p_fecha_hasta
      ),
      'total_a_eliminar', (
        SELECT COALESCE(SUM(t.monto_total), 0)
        FROM intercompany_transacciones t
        WHERE t.grupo_id = p_grupo_id
          AND t.estado = 'PROCESADO'
          AND t.created_at::DATE BETWEEN p_fecha_desde AND p_fecha_hasta
      ),
      'pares_empresas', (
        SELECT jsonb_agg(DISTINCT jsonb_build_object(
          'vendedora', eo.razon_social,
          'compradora', ed.razon_social,
          'subtotal', sub.monto
        ))
        FROM (
          SELECT empresa_origen_id, empresa_destino_id, SUM(monto_total) AS monto
          FROM intercompany_transacciones
          WHERE grupo_id = p_grupo_id AND estado = 'PROCESADO'
            AND created_at::DATE BETWEEN p_fecha_desde AND p_fecha_hasta
          GROUP BY empresa_origen_id, empresa_destino_id
        ) sub
        JOIN empresas eo ON eo.id = sub.empresa_origen_id
        JOIN empresas ed ON ed.id = sub.empresa_destino_id
      )
    )
    FROM grupos_empresariales g
    WHERE g.id = p_grupo_id
  );
END;
$$;
```

#### Triggers

```sql
-- Trigger: al confirmar factura, detectar si es intercompany y encolar espejo
CREATE OR REPLACE FUNCTION trg_intercompany_factura_emitida()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_ic_info JSONB;
  v_grupo RECORD;
BEGIN
  IF NEW.estado = 'EMITIDA' AND (OLD.estado IS DISTINCT FROM 'EMITIDA') THEN
    -- Detectar si es intercompany
    v_ic_info := intercompany_detectar(NEW.empresa_id, NEW.contacto_id);

    IF (v_ic_info->>'es_intercompany')::BOOLEAN THEN
      -- Verificar si el grupo tiene auto_crear_espejo
      SELECT * INTO v_grupo FROM grupos_empresariales
      WHERE id = (v_ic_info->>'grupo_id')::UUID AND auto_crear_espejo = true;

      IF FOUND THEN
        PERFORM intercompany_crear_espejo(NEW.empresa_id, NEW.id);
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER tr_intercompany_factura
  AFTER UPDATE OF estado ON facturas
  FOR EACH ROW
  WHEN (NEW.estado = 'EMITIDA')
  EXECUTE FUNCTION trg_intercompany_factura_emitida();
```

#### Vistas para Reportes

```sql
-- Vista: transacciones intercompany pendientes
CREATE OR REPLACE VIEW v_intercompany_pendientes AS
SELECT
  t.id,
  g.nombre AS grupo,
  eo.razon_social AS empresa_origen,
  ed.razon_social AS empresa_destino,
  t.documento_origen_tipo,
  t.monto_total,
  t.estado,
  t.error_detalle,
  t.created_at
FROM intercompany_transacciones t
JOIN grupos_empresariales g ON g.id = t.grupo_id
JOIN empresas eo ON eo.id = t.empresa_origen_id
JOIN empresas ed ON ed.id = t.empresa_destino_id
WHERE t.estado IN ('PENDIENTE', 'ERROR')
ORDER BY t.created_at DESC;

-- Vista: saldos intercompany (para conciliacion)
CREATE OR REPLACE VIEW v_intercompany_saldos AS
SELECT
  t.grupo_id,
  g.nombre AS grupo,
  t.empresa_origen_id,
  eo.razon_social AS vendedora,
  t.empresa_destino_id,
  ed.razon_social AS compradora,
  SUM(t.monto_total) AS total_operaciones,
  COUNT(*) AS num_transacciones
FROM intercompany_transacciones t
JOIN grupos_empresariales g ON g.id = t.grupo_id
JOIN empresas eo ON eo.id = t.empresa_origen_id
JOIN empresas ed ON ed.id = t.empresa_destino_id
WHERE t.estado = 'PROCESADO'
GROUP BY t.grupo_id, g.nombre, t.empresa_origen_id, eo.razon_social,
         t.empresa_destino_id, ed.razon_social;
```

#### Integracion Module Service Bus

```sql
-- Detectar intercompany (llamada desde formulario de facturacion)
CREATE OR REPLACE FUNCTION module_bus.detect_intercompany(
  p_empresa_id  UUID,
  p_contacto_id UUID
) RETURNS module_bus.bus_response
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_result module_bus.bus_response;
  v_data JSONB;
BEGIN
  -- Intercompany no depende de un modulo especifico, es infraestructura
  v_data := intercompany_detectar(p_empresa_id, p_contacto_id);
  v_result := (true, null, 'infraestructura', v_data);
  RETURN v_result;
END;
$$;

-- Obtener precio de transferencia (desde formulario de venta)
CREATE OR REPLACE FUNCTION module_bus.get_transfer_price(
  p_empresa_id  UUID,
  p_contacto_id UUID,
  p_producto_id UUID
) RETURNS module_bus.bus_response
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_result module_bus.bus_response;
  v_ic_info JSONB;
  v_precio DECIMAL(14,2);
BEGIN
  v_ic_info := intercompany_detectar(p_empresa_id, p_contacto_id);

  IF NOT (v_ic_info->>'es_intercompany')::BOOLEAN THEN
    v_result := (true, null, 'infraestructura',
      jsonb_build_object('es_intercompany', false));
    RETURN v_result;
  END IF;

  v_precio := intercompany_obtener_precio(
    (v_ic_info->>'grupo_id')::UUID,
    p_empresa_id,
    (v_ic_info->>'empresa_destino_id')::UUID,
    p_producto_id
  );

  v_result := (true, null, 'infraestructura',
    jsonb_build_object(
      'es_intercompany', true,
      'precio_transferencia', v_precio,
      'grupo', v_ic_info->>'grupo_nombre'
    ));
  RETURN v_result;
END;
$$;
```

#### RLS Policies

```sql
-- Grupos empresariales: accesible por empresas miembro
ALTER TABLE grupos_empresariales ENABLE ROW LEVEL SECURITY;
CREATE POLICY "grupo_member" ON grupos_empresariales FOR ALL TO authenticated
  USING (
    id IN (
      SELECT grupo_id FROM grupo_empresas
      WHERE empresa_id = (SELECT private.get_empresa_id())
    )
  );

ALTER TABLE grupo_empresas ENABLE ROW LEVEL SECURITY;
CREATE POLICY "grupo_member" ON grupo_empresas FOR ALL TO authenticated
  USING (
    grupo_id IN (
      SELECT grupo_id FROM grupo_empresas
      WHERE empresa_id = (SELECT private.get_empresa_id())
    )
  );

ALTER TABLE intercompany_contactos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "ic_member" ON intercompany_contactos FOR ALL TO authenticated
  USING (
    empresa_destino_id = (SELECT private.get_empresa_id())
    OR empresa_origen_id = (SELECT private.get_empresa_id())
  );

ALTER TABLE intercompany_precios ENABLE ROW LEVEL SECURITY;
CREATE POLICY "ic_member" ON intercompany_precios FOR ALL TO authenticated
  USING (
    grupo_id IN (
      SELECT grupo_id FROM grupo_empresas
      WHERE empresa_id = (SELECT private.get_empresa_id())
    )
  );

ALTER TABLE intercompany_cuentas ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON intercompany_cuentas FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

ALTER TABLE intercompany_transacciones ENABLE ROW LEVEL SECURITY;
CREATE POLICY "ic_member" ON intercompany_transacciones FOR ALL TO authenticated
  USING (
    empresa_origen_id = (SELECT private.get_empresa_id())
    OR empresa_destino_id = (SELECT private.get_empresa_id())
  );
```

#### Flujo UI/UX

```
features/admin/intercompany/  (en modulo Administracion)
  screens/
    corporate_groups_screen.dart         # CRUD grupos empresariales
    group_companies_screen.dart          # Empresas del grupo + mapeo contactos
    transfer_pricing_screen.dart         # Precios de transferencia por producto
    ic_accounts_screen.dart              # Cuentas contables intercompany
    ic_transactions_screen.dart          # Transacciones IC: pendientes, procesadas, errores
    ic_consolidation_screen.dart         # Reporte de eliminacion para consolidacion

Integracion en Facturacion (features/ventas/facturas/):
  - Al seleccionar contacto en nueva factura:
    → Si es intercompany, mostrar badge "INTERCOMPANY" junto al nombre
    → Precios se autocompletan con precios de transferencia
    → Al emitir factura: aviso "Se creara documento espejo en Empresa B"

Integracion en Compras (features/compras/):
  - Facturas de compra intercompany se crean automaticamente
  - Aparecen marcadas con badge "IC" en listado
  - Al hacer click, se puede ver el documento origen (factura de venta de la otra empresa)

Edge Function `process-intercompany`:
  - Procesa transacciones PENDIENTE
  - Crea documento espejo en empresa destino
  - Actualiza estado a PROCESADO o ERROR
  - Se ejecuta via webhook trigger o cron cada 5 min

Responsive:
  COMPACT: badge "IC" compacto, lista simple de transacciones
  MEDIUM: badge + empresa contrapartida, transacciones con filtros
  EXPANDED/LARGE: dashboard IC con saldos cruzados + transacciones + consolidacion
```

---

