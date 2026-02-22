# Arquitectura Multi-Marketplace


Ampliacion del modulo Ecommerce existente (WooCommerce) para soportar multiples marketplaces: MercadoLibre Ecuador, Shopify, Amazon. Patron adaptador con interfaz comun.

## Arquitectura Multi-Marketplace

### Descripcion Funcional

PILAR ya cuenta con un modulo Ecommerce con conector WooCommerce (REST API), sincronizacion de productos/stock/pedidos, bodega ecommerce dedicada, envios con tracking, y devoluciones. Esta seccion amplía esa arquitectura con un **patron adaptador multi-marketplace** que permite conectar MercadoLibre, Shopify y Amazon bajo una interfaz unificada.

**Principio de diseno:** Cada marketplace implementa una interfaz comun (`IMarketplaceAdapter`) que expone operaciones estandar. La logica de negocio (crear OV, reservar stock, facturar, despachar) es identica independientemente del canal. Solo cambia la capa de comunicacion con la API externa.

**Canales soportados:**

| Canal | Tipo | API | Prioridad | Estado |
|-------|------|-----|-----------|--------|
| Tienda Fisica | Interno | N/A | P1 | Implementado |
| POS | Interno | N/A | P1 | Implementado |
| WooCommerce | Ecommerce propio | REST API v3 | P1 | Implementado |
| MercadoLibre | Marketplace 3P | REST API v2 (OAuth2) | P2 | Esta seccion |
| Shopify | Ecommerce propio | REST + GraphQL Admin API | P2 | Esta seccion |
| Amazon | Marketplace 3P | SP-API (OAuth2) | P3 | Referencial |

### Modelo de Datos - Ampliacion Ecommerce

Las tablas `tiendas_ecommerce`, `mapeo_productos`, `pedidos_ecommerce`, `envios`, `devoluciones_ecommerce` ya existen (seccion 9.7 del INFORME). Se amplian con nuevas tablas y columnas para soportar multi-marketplace.

```sql
-- ============================================================
-- MIGRACION: 025_ampliar_ecommerce_marketplace.sql
-- ============================================================

-- 1. Ampliar ENUM de plataformas en tiendas_ecommerce
-- (campo plataforma VARCHAR(20) ya soporta valores libres)
-- Valores validos: WOOCOMMERCE, SHOPIFY, MERCADOLIBRE, AMAZON

-- 2. Nuevas columnas en tiendas_ecommerce
ALTER TABLE tiendas_ecommerce
  ADD COLUMN IF NOT EXISTS marketplace_seller_id VARCHAR(100),
  ADD COLUMN IF NOT EXISTS marketplace_config JSONB DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS webhook_secret VARCHAR(255),
  ADD COLUMN IF NOT EXISTS ultima_sync_productos TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS ultima_sync_pedidos TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS ultima_sync_stock TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS moneda VARCHAR(3) DEFAULT 'USD',
  ADD COLUMN IF NOT EXISTS comision_marketplace DECIMAL(5,2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS lista_precios_id UUID REFERENCES listas_precios(id),
  ADD COLUMN IF NOT EXISTS posicion_fiscal_id UUID REFERENCES posiciones_fiscales(id),
  ADD COLUMN IF NOT EXISTS auto_facturar BOOLEAN DEFAULT true,
  ADD COLUMN IF NOT EXISTS auto_despachar BOOLEAN DEFAULT false;

COMMENT ON COLUMN tiendas_ecommerce.marketplace_seller_id IS 'ID del vendedor en el marketplace (ej: ML seller_id, Shopify shop_id)';
COMMENT ON COLUMN tiendas_ecommerce.marketplace_config IS 'Config especifica por plataforma: ML={site_id,listing_type}, Shopify={api_version}, etc.';
COMMENT ON COLUMN tiendas_ecommerce.comision_marketplace IS 'Porcentaje de comision que cobra el marketplace por venta';

-- 3. Mapeo de categorias ERP <-> Marketplace
CREATE TABLE IF NOT EXISTS mapeo_categorias_marketplace (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id          UUID NOT NULL REFERENCES empresas(id),
  tienda_id           UUID NOT NULL REFERENCES tiendas_ecommerce(id) ON DELETE CASCADE,
  categoria_id        UUID NOT NULL REFERENCES categorias(id),
  categoria_externa_id VARCHAR(100) NOT NULL,
  categoria_externa_nombre VARCHAR(200),
  atributos_requeridos JSONB DEFAULT '[]',
  created_at          TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(tienda_id, categoria_id)
);

ALTER TABLE mapeo_categorias_marketplace ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON mapeo_categorias_marketplace
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE INDEX idx_mapeo_cat_mkt_tienda ON mapeo_categorias_marketplace(tienda_id);

-- 4. Ampliar mapeo_productos con campos marketplace
ALTER TABLE mapeo_productos
  ADD COLUMN IF NOT EXISTS url_publicacion TEXT,
  ADD COLUMN IF NOT EXISTS estado_publicacion VARCHAR(20) DEFAULT 'PENDIENTE',
    -- PENDIENTE, ACTIVA, PAUSADA, CERRADA, ERROR
  ADD COLUMN IF NOT EXISTS categoria_externa_id VARCHAR(100),
  ADD COLUMN IF NOT EXISTS atributos_externos JSONB DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS ultimo_error TEXT,
  ADD COLUMN IF NOT EXISTS ultima_sync TIMESTAMPTZ;

-- 5. Preguntas y mensajes de marketplace
CREATE TABLE IF NOT EXISTS marketplace_mensajes (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id          UUID NOT NULL REFERENCES empresas(id),
  tienda_id           UUID NOT NULL REFERENCES tiendas_ecommerce(id) ON DELETE CASCADE,
  mensaje_externo_id  VARCHAR(100) NOT NULL,
  producto_externo_id VARCHAR(100),
  pedido_externo_id   VARCHAR(100),
  tipo                VARCHAR(20) NOT NULL DEFAULT 'PREGUNTA',
    -- PREGUNTA, RESPUESTA, MENSAJE_COMPRADOR, MENSAJE_VENDEDOR, RECLAMO
  texto               TEXT NOT NULL,
  autor               VARCHAR(100),
  autor_tipo          VARCHAR(10) DEFAULT 'COMPRADOR', -- COMPRADOR, VENDEDOR
  leido               BOOLEAN DEFAULT false,
  respondido          BOOLEAN DEFAULT false,
  fecha_externa       TIMESTAMPTZ,
  datos_raw           JSONB,
  created_at          TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE marketplace_mensajes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON marketplace_mensajes
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE INDEX idx_mkt_msg_tienda ON marketplace_mensajes(tienda_id);
CREATE INDEX idx_mkt_msg_no_leido ON marketplace_mensajes(tienda_id, leido) WHERE leido = false;

-- 6. Metricas y reputacion por marketplace
CREATE TABLE IF NOT EXISTS marketplace_metricas (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id          UUID NOT NULL REFERENCES empresas(id),
  tienda_id           UUID NOT NULL REFERENCES tiendas_ecommerce(id) ON DELETE CASCADE,
  fecha               DATE NOT NULL,
  ventas_cantidad     INTEGER DEFAULT 0,
  ventas_monto        DECIMAL(14,2) DEFAULT 0,
  devoluciones        INTEGER DEFAULT 0,
  reclamos            INTEGER DEFAULT 0,
  preguntas_sin_responder INTEGER DEFAULT 0,
  tiempo_respuesta_promedio_min INTEGER,
  calificacion        DECIMAL(3,2),          -- ej: 4.85
  reputacion_nivel    VARCHAR(30),           -- ML: mercado_lider_gold, etc.
  metricas_raw        JSONB,                 -- datos completos del marketplace
  created_at          TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(tienda_id, fecha)
);

ALTER TABLE marketplace_metricas ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON marketplace_metricas
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- 7. Log de sincronizacion (auditoria de syncs)
CREATE TABLE IF NOT EXISTS ecommerce_sync_log (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id          UUID NOT NULL REFERENCES empresas(id),
  tienda_id           UUID NOT NULL REFERENCES tiendas_ecommerce(id) ON DELETE CASCADE,
  tipo_sync           VARCHAR(20) NOT NULL,
    -- PRODUCTOS, STOCK, PEDIDOS, CATEGORIAS, METRICAS, MENSAJES
  direccion           VARCHAR(10) NOT NULL DEFAULT 'PUSH',
    -- PUSH (ERP->Marketplace), PULL (Marketplace->ERP)
  registros_procesados INTEGER DEFAULT 0,
  registros_error     INTEGER DEFAULT 0,
  errores_detalle     JSONB DEFAULT '[]',
  duracion_ms         INTEGER,
  estado              VARCHAR(10) NOT NULL DEFAULT 'OK', -- OK, ERROR, PARCIAL
  created_at          TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE ecommerce_sync_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON ecommerce_sync_log
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE INDEX idx_sync_log_tienda_fecha ON ecommerce_sync_log(tienda_id, created_at DESC);

-- 8. Comisiones y liquidaciones de marketplace
CREATE TABLE IF NOT EXISTS marketplace_liquidaciones (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id          UUID NOT NULL REFERENCES empresas(id),
  tienda_id           UUID NOT NULL REFERENCES tiendas_ecommerce(id),
  liquidacion_externa_id VARCHAR(100),
  periodo_desde       DATE NOT NULL,
  periodo_hasta       DATE NOT NULL,
  monto_ventas        DECIMAL(14,2) NOT NULL DEFAULT 0,
  monto_comisiones    DECIMAL(14,2) NOT NULL DEFAULT 0,
  monto_envios        DECIMAL(14,2) NOT NULL DEFAULT 0,
  monto_impuestos     DECIMAL(14,2) NOT NULL DEFAULT 0,
  monto_devoluciones  DECIMAL(14,2) NOT NULL DEFAULT 0,
  monto_neto          DECIMAL(14,2) NOT NULL DEFAULT 0,
  estado              VARCHAR(20) DEFAULT 'PENDIENTE',
    -- PENDIENTE, ACREDITADA, CONCILIADA
  fecha_acreditacion  DATE,
  cuenta_bancaria_id  UUID REFERENCES cuentas_bancarias(id),
  asiento_id          UUID,   -- Asiento contable generado
  datos_raw           JSONB,
  created_at          TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE marketplace_liquidaciones ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON marketplace_liquidaciones
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- 9. Ampliar pedidos_ecommerce con datos de marketplace
ALTER TABLE pedidos_ecommerce
  ADD COLUMN IF NOT EXISTS canal VARCHAR(30),
    -- WOOCOMMERCE, MERCADOLIBRE, SHOPIFY, AMAZON
  ADD COLUMN IF NOT EXISTS comision_monto DECIMAL(14,2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS envio_marketplace BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS fulfillment_tipo VARCHAR(20),
    -- PROPIO, ML_FULL, FBA, SHOPIFY_FULFILLMENT
  ADD COLUMN IF NOT EXISTS comprador_externo_id VARCHAR(100),
  ADD COLUMN IF NOT EXISTS comprador_nickname VARCHAR(100),
  ADD COLUMN IF NOT EXISTS direccion_envio JSONB;
```

### Funciones PostgreSQL - Core Multi-Marketplace

```sql
-- ============================================================
-- RPC: Procesar pedido de cualquier marketplace
-- Reutiliza logica existente de process_ecommerce_order
-- ============================================================
CREATE OR REPLACE FUNCTION process_marketplace_order(
  p_tienda_id         UUID,
  p_pedido_externo_id VARCHAR(100),
  p_datos_pedido      JSONB
  -- Estructura esperada de p_datos_pedido:
  -- {
  --   canal: 'MERCADOLIBRE' | 'SHOPIFY' | 'AMAZON',
  --   comprador: {nombre, email, telefono, identificacion, tipo_id, direccion},
  --   items: [{sku, cantidad, precio_unitario, descuento}],
  --   envio: {direccion, ciudad, provincia, courier, costo, fulfillment_tipo},
  --   pago: {monto, metodo, referencia, estado, comision_marketplace},
  --   notas: ''
  -- }
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_tienda RECORD;
  v_contacto_id UUID;
  v_orden_id UUID;
  v_factura_id UUID;
  v_pedido_id UUID;
  v_item RECORD;
  v_producto_id UUID;
  v_total DECIMAL(14,2) := 0;
BEGIN
  -- 1. Obtener tienda y validar
  SELECT * INTO v_tienda FROM tiendas_ecommerce WHERE id = p_tienda_id AND activa = true;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Tienda ecommerce no encontrada o inactiva: %', p_tienda_id;
  END IF;

  -- 2. Verificar duplicados
  IF EXISTS (SELECT 1 FROM pedidos_ecommerce
             WHERE tienda_id = p_tienda_id AND pedido_externo_id = p_pedido_externo_id) THEN
    RAISE EXCEPTION 'Pedido duplicado: % en tienda %', p_pedido_externo_id, p_tienda_id;
  END IF;

  -- 3. Buscar o crear contacto
  v_contacto_id := find_or_create_contact_from_marketplace(
    v_tienda.empresa_id,
    p_datos_pedido -> 'comprador'
  );

  -- 4. Crear pedido ecommerce
  INSERT INTO pedidos_ecommerce (
    tienda_id, pedido_externo_id, estado, monto_total,
    canal, comision_monto, envio_marketplace,
    fulfillment_tipo, comprador_externo_id,
    comprador_nickname, direccion_envio, datos_raw
  ) VALUES (
    p_tienda_id, p_pedido_externo_id, 'RECIBIDO',
    (p_datos_pedido ->> 'pago')::JSONB ->> 'monto',
    p_datos_pedido ->> 'canal',
    COALESCE((p_datos_pedido -> 'pago' ->> 'comision_marketplace')::DECIMAL, 0),
    COALESCE((p_datos_pedido -> 'envio' ->> 'fulfillment_tipo') != 'PROPIO', false),
    p_datos_pedido -> 'envio' ->> 'fulfillment_tipo',
    p_datos_pedido -> 'comprador' ->> 'id_externo',
    p_datos_pedido -> 'comprador' ->> 'nickname',
    p_datos_pedido -> 'envio',
    p_datos_pedido
  ) RETURNING id INTO v_pedido_id;

  -- 5. Crear orden de venta (via module_bus si Ventas activo)
  -- La logica de crear OV, reservar stock, facturar y registrar pago
  -- depende de la config auto_facturar / auto_despachar de la tienda.
  -- Delega a la funcion existente process_ecommerce_order_internal().
  PERFORM process_ecommerce_order_internal(
    v_tienda.empresa_id, v_pedido_id, v_contacto_id, p_datos_pedido
  );

  RETURN v_pedido_id;
END;
$$;

-- ============================================================
-- RPC: Buscar o crear contacto desde datos de marketplace
-- ============================================================
CREATE OR REPLACE FUNCTION find_or_create_contact_from_marketplace(
  p_empresa_id  UUID,
  p_comprador   JSONB
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_contacto_id UUID;
  v_email VARCHAR(200);
  v_identificacion VARCHAR(20);
BEGIN
  v_email := p_comprador ->> 'email';
  v_identificacion := p_comprador ->> 'identificacion';

  -- Buscar por identificacion (RUC/cedula) primero
  IF v_identificacion IS NOT NULL AND v_identificacion != '' THEN
    SELECT id INTO v_contacto_id
    FROM contactos
    WHERE empresa_id = p_empresa_id
      AND identificacion = v_identificacion
    LIMIT 1;
  END IF;

  -- Si no encontrado, buscar por email
  IF v_contacto_id IS NULL AND v_email IS NOT NULL AND v_email != '' THEN
    SELECT id INTO v_contacto_id
    FROM contactos
    WHERE empresa_id = p_empresa_id
      AND email = v_email
    LIMIT 1;
  END IF;

  -- Si no encontrado, crear nuevo contacto
  IF v_contacto_id IS NULL THEN
    INSERT INTO contactos (
      empresa_id, tipo, nombre, email, telefono,
      identificacion, tipo_identificacion,
      direccion, origen
    ) VALUES (
      p_empresa_id, 'CLIENTE',
      COALESCE(p_comprador ->> 'nombre', 'Comprador Marketplace'),
      v_email,
      p_comprador ->> 'telefono',
      v_identificacion,
      COALESCE(p_comprador ->> 'tipo_id', '05'),
      p_comprador ->> 'direccion',
      'MARKETPLACE'
    ) RETURNING id INTO v_contacto_id;
  END IF;

  RETURN v_contacto_id;
END;
$$;

-- ============================================================
-- RPC: Sincronizar stock de un producto a todos los marketplaces
-- Llamado por trigger al cambiar inventario_stock
-- ============================================================
CREATE OR REPLACE FUNCTION sync_stock_to_marketplaces(
  p_empresa_id  UUID,
  p_producto_id UUID
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_tienda RECORD;
  v_stock DECIMAL(18,6);
BEGIN
  -- Para cada tienda activa que tenga este producto mapeado
  FOR v_tienda IN
    SELECT t.id as tienda_id, t.plataforma, t.bodega_ecommerce_id,
           m.producto_externo_id, m.id as mapeo_id
    FROM tiendas_ecommerce t
    JOIN mapeo_productos m ON m.tienda_id = t.id
    WHERE t.empresa_id = p_empresa_id
      AND t.activa = true
      AND t.sync_stock = true
      AND m.producto_id = p_producto_id
      AND m.sync_stock = true
  LOOP
    -- Obtener stock de la bodega dedicada
    SELECT COALESCE(cantidad_disponible, 0) INTO v_stock
    FROM inventario_stock
    WHERE bodega_id = COALESCE(v_tienda.bodega_ecommerce_id,
          (SELECT bodega_principal_id FROM establecimientos
           WHERE empresa_id = p_empresa_id LIMIT 1))
      AND producto_id = p_producto_id;

    -- Encolar actualizacion de stock (procesada por Edge Function)
    INSERT INTO ecommerce_stock_queue (
      tienda_id, producto_externo_id, cantidad, estado
    ) VALUES (
      v_tienda.tienda_id, v_tienda.producto_externo_id,
      GREATEST(v_stock, 0), 'PENDIENTE'
    )
    ON CONFLICT (tienda_id, producto_externo_id)
    DO UPDATE SET cantidad = GREATEST(v_stock, 0),
                  estado = 'PENDIENTE',
                  updated_at = NOW();
  END LOOP;
END;
$$;

-- Cola de actualizacion de stock (batch processing)
CREATE TABLE IF NOT EXISTS ecommerce_stock_queue (
  tienda_id           UUID NOT NULL REFERENCES tiendas_ecommerce(id),
  producto_externo_id VARCHAR(100) NOT NULL,
  cantidad            DECIMAL(18,6) NOT NULL DEFAULT 0,
  estado              VARCHAR(10) DEFAULT 'PENDIENTE', -- PENDIENTE, PROCESANDO, OK, ERROR
  ultimo_error        TEXT,
  updated_at          TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (tienda_id, producto_externo_id)
);
```

### Triggers

```sql
-- Trigger: al cambiar stock en inventario_stock, encolar sync a marketplaces
CREATE OR REPLACE FUNCTION trg_stock_change_sync_marketplace()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
  -- Solo si la cantidad cambio
  IF TG_OP = 'UPDATE' AND OLD.cantidad_disponible = NEW.cantidad_disponible THEN
    RETURN NEW;
  END IF;

  -- Encolar sync asincrono (la Edge Function procesa la cola)
  PERFORM sync_stock_to_marketplaces(
    (SELECT empresa_id FROM bodegas WHERE id = NEW.bodega_id),
    NEW.producto_id
  );

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_inventario_stock_marketplace
  AFTER INSERT OR UPDATE OF cantidad_disponible ON inventario_stock
  FOR EACH ROW
  EXECUTE FUNCTION trg_stock_change_sync_marketplace();

-- Trigger: al cambiar estado de pedido ecommerce, notificar
CREATE OR REPLACE FUNCTION trg_pedido_ecommerce_estado()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.estado IS DISTINCT FROM NEW.estado THEN
    -- Registrar en actividad
    INSERT INTO registro_actividad (
      tabla, registro_id, empresa_id, accion, datos_nuevos
    ) VALUES (
      'pedidos_ecommerce', NEW.id,
      (SELECT empresa_id FROM tiendas_ecommerce WHERE id = NEW.tienda_id),
      'CAMBIO_ESTADO',
      jsonb_build_object('estado_anterior', OLD.estado, 'estado_nuevo', NEW.estado)
    );
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_pedido_ecommerce_estado_change
  AFTER UPDATE OF estado ON pedidos_ecommerce
  FOR EACH ROW
  EXECUTE FUNCTION trg_pedido_ecommerce_estado();
```

### Vistas para Reportes

```sql
-- Vista: ventas por canal (omnicanal)
CREATE OR REPLACE VIEW v_ventas_por_canal AS
SELECT
  f.empresa_id,
  COALESCE(pe.canal,
    CASE WHEN f.pos_sesion_id IS NOT NULL THEN 'POS'
         ELSE 'TIENDA_FISICA'
    END
  ) AS canal,
  DATE_TRUNC('day', f.fecha_emision) AS fecha,
  COUNT(*) AS num_facturas,
  SUM(f.total) AS total_ventas,
  SUM(f.subtotal_iva) AS base_iva,
  SUM(f.subtotal_0) AS base_0,
  SUM(f.iva) AS iva_cobrado,
  SUM(COALESCE(pe.comision_monto, 0)) AS comisiones_marketplace
FROM facturas f
LEFT JOIN pedidos_ecommerce pe ON pe.factura_id = f.id
WHERE f.estado != 'ANULADA'
GROUP BY f.empresa_id, canal, DATE_TRUNC('day', f.fecha_emision);

-- Vista: stock por canal (disponible por bodega ecommerce)
CREATE OR REPLACE VIEW v_stock_por_canal AS
SELECT
  t.empresa_id,
  t.plataforma AS canal,
  t.nombre AS tienda,
  p.nombre AS producto,
  p.sku,
  COALESCE(s.cantidad_disponible, 0) AS stock_disponible,
  m.estado_publicacion
FROM tiendas_ecommerce t
JOIN mapeo_productos m ON m.tienda_id = t.id
JOIN productos p ON p.id = m.producto_id
LEFT JOIN inventario_stock s ON s.producto_id = p.id
  AND s.bodega_id = COALESCE(t.bodega_ecommerce_id,
    (SELECT b.id FROM bodegas b
     JOIN establecimientos e ON e.id = b.establecimiento_id
     WHERE e.empresa_id = t.empresa_id AND b.es_principal = true LIMIT 1))
WHERE t.activa = true;

-- Vista: performance por marketplace
CREATE OR REPLACE VIEW v_marketplace_performance AS
SELECT
  mm.empresa_id,
  t.plataforma,
  t.nombre AS tienda,
  mm.fecha,
  mm.ventas_cantidad,
  mm.ventas_monto,
  mm.devoluciones,
  mm.reclamos,
  mm.calificacion,
  mm.reputacion_nivel,
  CASE WHEN mm.ventas_cantidad > 0
    THEN ROUND(mm.devoluciones::DECIMAL / mm.ventas_cantidad * 100, 2)
    ELSE 0
  END AS tasa_devolucion_pct
FROM marketplace_metricas mm
JOIN tiendas_ecommerce t ON t.id = mm.tienda_id;
```

### Integracion Module Service Bus

```sql
-- ========================================
-- BUS -> ECOMMERCE
-- ========================================

-- Notificar a marketplaces cuando cambia stock
CREATE OR REPLACE FUNCTION module_bus.notify_stock_change(
  p_empresa_id    UUID,
  p_producto_id   UUID,
  p_bodega_id     UUID,
  p_nueva_cantidad DECIMAL(18,6)
) RETURNS module_bus.bus_response
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_result module_bus.bus_response;
BEGIN
  IF NOT module_bus.is_module_active(p_empresa_id, 'ecommerce') THEN
    v_result := (false, 'module_inactive', 'ecommerce', null);
    RETURN v_result;
  END IF;

  PERFORM sync_stock_to_marketplaces(p_empresa_id, p_producto_id);

  v_result := (true, null, 'ecommerce',
    jsonb_build_object('producto_id', p_producto_id, 'synced', true));
  RETURN v_result;
END;
$$;

-- Crear pedido desde ecommerce (ya existente, se amplía)
CREATE OR REPLACE FUNCTION module_bus.create_ecommerce_order(
  p_empresa_id    UUID,
  p_tienda_id     UUID,
  p_pedido_ext_id VARCHAR(100),
  p_datos         JSONB
) RETURNS module_bus.bus_response
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_result module_bus.bus_response;
  v_pedido_id UUID;
BEGIN
  IF NOT module_bus.is_module_active(p_empresa_id, 'ecommerce') THEN
    v_result := (false, 'module_inactive', 'ecommerce', null);
    RETURN v_result;
  END IF;

  v_pedido_id := process_marketplace_order(p_tienda_id, p_pedido_ext_id, p_datos);

  v_result := (true, null, 'ecommerce',
    jsonb_build_object('pedido_ecommerce_id', v_pedido_id));
  RETURN v_result;
END;
$$;
```

### RLS Policies

Todas las tablas nuevas de la seccion 25.1 siguen el patron estandar PILAR:

```sql
-- Patron aplicado a TODAS las tablas con empresa_id:
-- mapeo_categorias_marketplace, marketplace_mensajes,
-- marketplace_metricas, ecommerce_sync_log, marketplace_liquidaciones

-- Ejemplo (ya definidas arriba en cada CREATE TABLE):
-- ALTER TABLE <tabla> ENABLE ROW LEVEL SECURITY;
-- CREATE POLICY "tenant_isolation" ON <tabla>
--   FOR ALL TO authenticated
--   USING (empresa_id = (SELECT private.get_empresa_id()));

-- Tabla ecommerce_stock_queue NO tiene empresa_id (clave compuesta tienda+producto)
-- Se protege via la FK a tiendas_ecommerce que ya tiene RLS.
-- Acceso solo via funciones SECURITY DEFINER.
```

### Flujo UI/UX

```
MODULO ECOMMERCE (Menu principal: Ecommerce ▼)

├── Tiendas
│   ├── Lista de tiendas conectadas (DataGrid: nombre, plataforma, estado, ultima_sync)
│   ├── + Nueva tienda (wizard: elegir plataforma → credenciales → configurar)
│   └── Detalle tienda (tabs: General | Productos | Pedidos | Metricas | Sync Log)
│
├── Productos Online
│   ├── Lista con filtro por tienda/estado (publicados, pendientes, errores)
│   ├── Publicar productos (seleccion masiva → mapear categoria → publicar)
│   └── Contenido SEO (editor HTML, galeria, meta tags)
│
├── Pedidos
│   ├── Lista unificada de pedidos de TODOS los canales
│   ├── Filtros: canal, estado, fecha, monto
│   ├── Detalle pedido (datos comprador, items, pagos, envio, factura vinculada)
│   └── Acciones: Facturar | Despachar | Cancelar | Ver en marketplace
│
├── Mensajes (solo marketplaces)
│   ├── Bandeja unificada de preguntas/mensajes
│   ├── Responder desde PILAR (se envia via API al marketplace)
│   └── Indicador de tiempo de respuesta
│
├── Envios
│   ├── Lista de envios pendientes/en_transito
│   ├── Crear envio (seleccionar courier, ingresar guia)
│   └── Tracking en tiempo real (timeline de eventos)
│
├── Liquidaciones
│   ├── Liquidaciones recibidas del marketplace
│   ├── Conciliar con movimientos bancarios
│   └── Generar asiento contable
│
└── Dashboard Ecommerce
    ├── Ventas por canal (grafico barras apiladas)
    ├── Top productos online
    ├── Tasa de devolucion por canal
    ├── Reputacion marketplace (gauges)
    └── Stock critico por canal
```

### Edge Functions

```
Edge Functions requeridas (amplian las existentes):

1. webhook-ecommerce/index.ts (EXISTENTE - ampliar)
   - Ruta: POST /functions/v1/webhook-ecommerce
   - verify_jwt: false (valida firma/HMAC del marketplace)
   - Ampliar para detectar plataforma por headers/params:
     - WooCommerce: header X-WC-Webhook-Source
     - MercadoLibre: header X-Signature + topic param
     - Shopify: header X-Shopify-Hmac-Sha256
   - Delega a handler especifico por plataforma
   - Idempotente (verifica pedido_externo_id antes de procesar)

2. sync-ecommerce/index.ts (EXISTENTE - ampliar)
   - Ruta: POST /functions/v1/sync-ecommerce
   - verify_jwt: true
   - Params: {tienda_id, tipo: 'productos'|'stock'|'categorias'|'metricas'}
   - Implementa patron adaptador: crea instancia del conector segun plataforma
   - Registra resultado en ecommerce_sync_log

3. sync-marketplace-stock/index.ts (NUEVA)
   - Ruta: invocada por cron cada 5 minutos
   - Lee ecommerce_stock_queue WHERE estado = 'PENDIENTE'
   - Agrupa por tienda, llama API por lotes (batch)
   - Actualiza estado a OK o ERROR

4. marketplace-messages/index.ts (NUEVA)
   - Ruta: POST /functions/v1/marketplace-messages
   - verify_jwt: true
   - Acciones: responder_pregunta, listar_mensajes
   - Envia respuesta via API del marketplace

5. marketplace-metrics/index.ts (NUEVA)
   - Ruta: invocada por cron diario
   - Consulta metricas de cada marketplace activo
   - Inserta en marketplace_metricas
```

**Patron Adaptador en Edge Functions (TypeScript):**

```typescript
// types/marketplace-adapter.ts
interface IMarketplaceAdapter {
  // Autenticacion
  authenticate(): Promise<void>;
  refreshToken(): Promise<string>;

  // Productos
  publishProduct(product: PilarProduct): Promise<ExternalProductId>;
  updateProduct(externalId: string, product: PilarProduct): Promise<void>;
  pauseProduct(externalId: string): Promise<void>;
  deleteProduct(externalId: string): Promise<void>;

  // Stock
  updateStock(externalId: string, quantity: number): Promise<void>;
  updateStockBatch(items: {externalId: string; quantity: number}[]): Promise<void>;

  // Pedidos
  getOrders(since: Date): Promise<MarketplaceOrder[]>;
  getOrderDetail(orderId: string): Promise<MarketplaceOrder>;
  updateOrderStatus(orderId: string, status: string, tracking?: TrackingInfo): Promise<void>;

  // Categorias
  getCategories(parentId?: string): Promise<MarketplaceCategory[]>;
  getCategoryAttributes(categoryId: string): Promise<CategoryAttribute[]>;

  // Mensajes
  getMessages(since: Date): Promise<MarketplaceMessage[]>;
  replyMessage(messageId: string, text: string): Promise<void>;

  // Metricas
  getSellerMetrics(): Promise<SellerMetrics>;

  // Envios
  getShippingLabels(orderId: string): Promise<ShippingLabel>;
  markAsShipped(orderId: string, tracking: TrackingInfo): Promise<void>;
}

// Cada conector implementa la interfaz:
// adapters/woocommerce-adapter.ts  (EXISTENTE)
// adapters/mercadolibre-adapter.ts (NUEVA - seccion 25.2)
// adapters/shopify-adapter.ts      (NUEVA - seccion 25.3)
// adapters/amazon-adapter.ts       (FUTURA - seccion 25.4)
```

---

## Conector MercadoLibre Ecuador

### Descripcion Funcional

MercadoLibre es el marketplace #1 en Ecuador y America Latina. PILAR se integra con la API de MercadoLibre para permitir que los vendedores gestionen sus publicaciones, pedidos, preguntas, envios y reputacion directamente desde el ERP.

**Alcance de la integracion:**

| Funcionalidad | Direccion | Detalle |
|--------------|-----------|---------|
| Publicar productos | PILAR -> ML | Crear/editar publicaciones con titulo, descripcion, fotos, precio, stock |
| Recibir pedidos | ML -> PILAR | Webhook de ordenes nuevas, crear OV + factura SRI |
| Sincronizar stock | PILAR -> ML | Al vender en cualquier canal, actualizar stock en ML |
| Gestionar preguntas | Bidireccional | Ver y responder preguntas desde PILAR |
| Tracking de envios | PILAR -> ML | Informar numero de guia y estado de envio |
| MercadoLibre Full | ML -> PILAR | Gestion de stock en centros de fulfillment ML |
| MercadoPago | ML -> PILAR | Recibir datos de cobro y liquidaciones |
| Metricas vendedor | ML -> PILAR | Reputacion, nivel, ventas, reclamos |

**API de MercadoLibre:**
- Base URL: `https://api.mercadolibre.com`
- Autenticacion: OAuth2 (authorization_code + refresh_token)
- Site ID Ecuador: `MEC`
- Rate limits: 10,000 requests/hora por app
- Webhooks (notifications): POST a URL configurada con topic + resource

**Flujo de autenticacion OAuth2:**

```
1. Usuario hace click en "Conectar MercadoLibre" en PILAR
2. PILAR redirige a: https://auth.mercadolibre.com/authorization?
     response_type=code&client_id=APP_ID&redirect_uri=CALLBACK_URL
3. Usuario autoriza en ML
4. ML redirige a CALLBACK_URL con ?code=AUTH_CODE
5. Edge Function intercambia code por access_token + refresh_token
6. Se almacenan tokens encriptados en tiendas_ecommerce.credenciales
7. Refresh automatico antes de expiracion (6h access, 6m refresh)
```

**Mapeo de categorias ML Ecuador:**
- ML tiene un arbol de categorias propio (ej: MEC1182 = Celulares)
- Cada categoria requiere atributos especificos (marca, modelo, color, etc.)
- PILAR almacena el mapeo en `mapeo_categorias_marketplace`
- El wizard de publicacion carga atributos requeridos dinamicamente

**Tipos de publicacion ML:**
- `gold_special` (Premium/Clasica con exposicion maxima)
- `gold_pro` (Pro con envio gratis)
- `gold` (Clasica)
- `silver` (Gratuita, baja exposicion)
- Configurado en `tiendas_ecommerce.marketplace_config.listing_type`

**MercadoLibre Full (Fulfillment):**
- Vendedor envia stock al centro de distribucion de ML
- ML almacena, empaca y envia al comprador
- PILAR registra stock en bodega virtual tipo `MARKETPLACE_FULL`
- Al vender, ML descuenta stock y notifica a PILAR
- PILAR solo actualiza inventario interno, no gestiona el envio

### Modelo de Datos Especifico ML

```sql
-- Las tablas genericas ya cubren la mayor parte.
-- Datos especificos de ML se almacenan en campos JSONB.

-- marketplace_config para tienda ML:
-- {
--   "site_id": "MEC",
--   "app_id": "123456789",
--   "listing_type": "gold_special",
--   "shipping_mode": "me2",        -- me2=MercadoEnvios, custom=Propio
--   "free_shipping": true,
--   "local_pick_up": false,
--   "fulfillment_enabled": false,
--   "official_store_id": null,
--   "catalog_listing": false
-- }

-- credenciales para tienda ML (encriptado):
-- {
--   "access_token": "APP_USR-...",
--   "refresh_token": "TG-...",
--   "token_expiry": "2026-02-15T18:00:00Z",
--   "user_id": "123456"
-- }

-- atributos_externos en mapeo_productos para ML:
-- {
--   "listing_type": "gold_special",
--   "condition": "new",
--   "warranty": "12 meses garantia del vendedor",
--   "attributes": [
--     {"id": "BRAND", "value_name": "Samsung"},
--     {"id": "MODEL", "value_name": "Galaxy S24"},
--     {"id": "COLOR", "value_name": "Negro"}
--   ]
-- }

-- Bodega virtual para ML Full
-- Se crea automaticamente al habilitar fulfillment:
INSERT INTO bodegas (empresa_id, establecimiento_id, nombre, tipo, es_principal)
VALUES (p_empresa_id, p_establecimiento_id, 'MercadoLibre Full', 'MARKETPLACE_FULL', false);

-- Agregar tipo de bodega si no existe
-- En la tabla bodegas, el campo tipo VARCHAR ya soporta:
-- PRINCIPAL, ALTERNA, TRANSITO, GARANTIAS, TALLER, SUMINISTROS_TALLER, MARKETPLACE_FULL
```

### Edge Functions Especificas ML

```
1. ml-oauth-callback/index.ts (NUEVA)
   - Ruta: GET /functions/v1/ml-oauth-callback?code=XXX&state=TIENDA_ID
   - verify_jwt: false (callback desde ML)
   - Valida state para evitar CSRF
   - Intercambia code por tokens
   - Almacena tokens encriptados en tiendas_ecommerce.credenciales
   - Redirige a PILAR con exito/error

2. ml-refresh-token/index.ts (NUEVA)
   - Cron cada 5 horas (tokens expiran en 6h)
   - Recorre tiendas ML activas
   - Renueva access_token con refresh_token
   - Si refresh falla (refresh_token expirado): marca tienda como inactiva,
     notifica al usuario para re-autorizar

3. webhook-ecommerce (AMPLIAR handler ML):
   Topics ML soportados:
   - orders_v2: nueva orden o cambio de estado
   - questions: nueva pregunta en publicacion
   - items: cambio en publicacion (ML puede pausar por stock 0)
   - payments: pago recibido o devuelto
   - shipments: cambio de estado en envio
   - claims: reclamo abierto por comprador

4. sync-ecommerce (AMPLIAR con MercadoLibreAdapter):
   - publishProduct: POST /items
   - updateProduct: PUT /items/{id}
   - updateStock: PUT /items/{id} con available_quantity
   - getOrders: GET /orders/search?seller={id}&sort=date_desc
   - getMessages: GET /questions/search?seller_id={id}
   - replyMessage: POST /answers
   - getSellerMetrics: GET /users/{id}/reputation
```

### Facturacion SRI desde Pedido ML

```
Flujo completo:

1. Comprador compra en MercadoLibre Ecuador
2. ML envia webhook topic=orders_v2 a PILAR
3. Edge Function webhook-ecommerce procesa:
   a. Extrae datos del comprador (nombre, cedula/RUC, direccion)
   b. NOTA: ML Ecuador NO siempre provee cedula/RUC del comprador.
      Si no hay identificacion → factura como CONSUMIDOR FINAL (07/9999999999999)
   c. Busca/crea contacto en PILAR
   d. Crea pedido_ecommerce con estado RECIBIDO
   e. Si auto_facturar = true:
      - Crea factura electronica con los items del pedido
      - Precios del pedido ML (ya incluyen comision ML, se factura precio al comprador)
      - IVA segun posicion fiscal configurada
      - Forma de pago: 20 (Otros con sistema financiero - MercadoPago)
      - Envia a cola SRI para firma y autorizacion
   f. Si auto_despachar = false:
      - Pedido queda en estado FACTURADO, esperando que operador confirme despacho
      - Si fulfillment ML Full: pedido va directo a COMPLETADO (ML despacha)
4. Operador prepara el envio desde pantalla Pedidos:
   - Imprime etiqueta ML (si MercadoEnvios)
   - Ingresa guia manual (si envio propio)
   - Confirma despacho → estado DESPACHADO
5. PILAR actualiza estado en ML via API: POST /shipments/{id}/tracking
6. ML notifica al comprador
7. Al entregar, ML notifica webhook topic=shipments → estado COMPLETADO
```

---

## Conector Shopify

### Descripcion Funcional

Shopify permite a empresas crear su propia tienda online (a diferencia de ML que es marketplace). La integracion con PILAR sincroniza productos, pedidos y stock de forma bidireccional.

**API de Shopify:**
- Admin API: REST + GraphQL (preferir GraphQL para eficiencia)
- API Version: 2025-01 (estable)
- Autenticacion: Custom App con access_token (o OAuth para apps publicas)
- Webhooks: HTTPS POST con HMAC-SHA256 en header
- Rate limits: REST 40 req/s, GraphQL 1000 puntos/s

**Alcance de la integracion:**

| Funcionalidad | Direccion | Detalle |
|--------------|-----------|---------|
| Sincronizar productos | PILAR -> Shopify | Crear/editar productos (1 SKU PILAR = 1 product Shopify), imagenes, precios |
| Recibir pedidos | Shopify -> PILAR | Webhook orders/create, crear OV + factura SRI |
| Sincronizar stock | PILAR -> Shopify | Actualizar inventory_level por location |
| Fulfillment | PILAR -> Shopify | Marcar pedido como fulfilled con tracking |
| Pagos | Shopify -> PILAR | Datos de pago (Shopify Payments, PayPal, etc.) |
| Clientes | Bidireccional | Sync datos de clientes |

### Modelo de Datos Especifico Shopify

```sql
-- marketplace_config para tienda Shopify:
-- {
--   "shop_domain": "mi-tienda.myshopify.com",
--   "api_version": "2025-01",
--   "location_id": "12345678",       -- Shopify Location para stock
--   "inventory_management": true,
--   "auto_fulfill": false,
--   "currency": "USD"
-- }

-- credenciales para tienda Shopify:
-- {
--   "access_token": "shpat_xxxxx",    -- Admin API access token
--   "api_key": "xxxxx",
--   "api_secret": "xxxxx"
-- }

-- atributos_externos en mapeo_productos para Shopify:
-- {
--   "shopify_product_id": "7654321",
--   "shopify_variant_id": "98765432",
--   "inventory_item_id": "11111111",
--   "handle": "producto-slug"
-- }
```

### Edge Functions Especificas Shopify

```
webhook-ecommerce (AMPLIAR handler Shopify):
  Topics Shopify soportados:
  - orders/create: nueva orden
  - orders/updated: cambio estado
  - orders/cancelled: cancelacion
  - refunds/create: devolucion
  - products/update: producto editado desde Shopify admin
  - inventory_levels/update: stock cambiado desde Shopify

sync-ecommerce (AMPLIAR con ShopifyAdapter):
  GraphQL queries para eficiencia:
  - productCreate / productUpdate (mutaciones)
  - inventorySetQuantities (batch stock update)
  - orders (query paginada con cursor)
  - fulfillmentCreate (marcar como enviado)
```

---

## Conector Amazon (P3)

### Descripcion Funcional (Referencial)

Amazon Seller Central para vendedores ecuatorianos que exportan o venden en Amazon.com. Prioridad P3 (futuro). Se documenta la arquitectura para que el patron adaptador lo soporte.

**SP-API (Selling Partner API):**
- Autenticacion: OAuth2 (Login with Amazon) + IAM Role (AWS STS)
- Endpoints por region: NA (North America)
- Rate limits: varies por endpoint
- Modelos de fulfillment: FBA (Fulfilled by Amazon) vs FBM (Fulfilled by Merchant)

**Alcance minimo P3:**
- Sincronizar listings (productos)
- Recibir ordenes
- Actualizar stock
- Informar tracking (FBM)
- Reportes de liquidacion

### Modelo de Datos

```sql
-- marketplace_config para Amazon:
-- {
--   "marketplace_id": "A2Q3Y263D00KWC",   -- Amazon US
--   "seller_id": "A1234567890",
--   "fulfillment_channel": "FBM",          -- FBA o FBM
--   "aws_region": "us-east-1"
-- }

-- credenciales para Amazon (encriptado):
-- {
--   "refresh_token": "Atzr|...",
--   "client_id": "amzn1.application-oa2-client.xxx",
--   "client_secret": "xxx",
--   "aws_access_key": "AKIA...",
--   "aws_secret_key": "xxx",
--   "role_arn": "arn:aws:iam::role/xxx"
-- }
```

---

## Dashboard Omnicanal

### Descripcion Funcional

Dashboard unificado que muestra KPIs de ventas consolidadas por canal (tienda fisica, POS, WooCommerce, MercadoLibre, Shopify, Amazon). Permite al gerente ver en un solo lugar el rendimiento de todos los canales de venta.

### KPIs del Dashboard

```
┌──────────────────────────────────────────────────────────────────┐
│  DASHBOARD OMNICANAL                                  [Periodo] │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  VENTAS TOTALES           PEDIDOS         TICKET PROMEDIO        │
│  $45,230.00               312             $145.00                │
│  ▲ 12% vs mes anterior    ▲ 8%            ▲ 3.5%                │
│                                                                  │
├──────────────────────────────────────────────────────────────────┤
│  VENTAS POR CANAL (Barras apiladas)                              │
│  ████████████████░░░░░░░░░░  Tienda Fisica  $20,100 (44%)       │
│  ██████████░░░░░░░░░░░░░░░░  POS            $12,300 (27%)       │
│  ██████░░░░░░░░░░░░░░░░░░░░  MercadoLibre   $ 8,200 (18%)      │
│  ███░░░░░░░░░░░░░░░░░░░░░░░  WooCommerce    $ 3,500 ( 8%)      │
│  █░░░░░░░░░░░░░░░░░░░░░░░░░  Shopify        $ 1,130 ( 3%)      │
│                                                                  │
├──────────────────────────────────────────────────────────────────┤
│  TOP 10 PRODUCTOS        │  REPUTACION MARKETPLACES              │
│  1. Producto A  $3,200   │  ML: ★★★★★ MercadoLider Gold        │
│  2. Producto B  $2,800   │  Shopify: 4.8/5.0 (120 reviews)      │
│  3. Producto C  $2,100   │  Devoluciones ML: 1.2%               │
│  ...                     │  Preguntas sin responder: 3           │
│                          │                                        │
├──────────────────────────────────────────────────────────────────┤
│  STOCK CRITICO POR CANAL                                         │
│  ⚠ Producto X: Stock ML = 2 (minimo 5)                          │
│  ⚠ Producto Y: Stock Shopify = 0 (pausado automaticamente)      │
│  ⚠ Producto Z: Stock WooCommerce = 3 (minimo 10)                │
│                                                                  │
├──────────────────────────────────────────────────────────────────┤
│  LIQUIDACIONES PENDIENTES                                        │
│  ML Febrero 2026: $7,800 (acreditacion estimada: 18/02)         │
│  Shopify Febrero 2026: $1,100 (proximo payout: 20/02)           │
└──────────────────────────────────────────────────────────────────┘
```

### Vista SQL para Dashboard

```sql
-- Vista consolidada para dashboard omnicanal
CREATE OR REPLACE VIEW v_dashboard_omnicanal AS
WITH ventas_periodo AS (
  SELECT
    f.empresa_id,
    COALESCE(pe.canal,
      CASE WHEN f.pos_sesion_id IS NOT NULL THEN 'POS'
           ELSE 'TIENDA_FISICA'
      END
    ) AS canal,
    f.total,
    f.fecha_emision
  FROM facturas f
  LEFT JOIN pedidos_ecommerce pe ON pe.factura_id = f.id
  WHERE f.estado NOT IN ('ANULADA', 'BORRADOR')
)
SELECT
  empresa_id,
  canal,
  DATE_TRUNC('month', fecha_emision) AS mes,
  COUNT(*) AS num_ventas,
  SUM(total) AS monto_total,
  AVG(total) AS ticket_promedio,
  MIN(total) AS venta_minima,
  MAX(total) AS venta_maxima
FROM ventas_periodo
GROUP BY empresa_id, canal, DATE_TRUNC('month', fecha_emision);
```

---



