# Módulo Ecommerce


```
ecommerce/
  ├── conectores/
  │     ├── woocommerce/    # Conector WooCommerce (REST API)
  │     ├── shopify/        # Conector Shopify (GraphQL API) [futuro]
  │     └── mercadolibre/   # Conector MercadoLibre [futuro]
  ├── sincronizacion/
  │     ├── productos/      # Sync catalogo (ERP → tienda)
  │     ├── stock/          # Sync stock en tiempo real
  │     ├── precios/        # Sync precios
  │     └── pedidos/        # Sync pedidos (tienda → ERP)
  └── configuracion/
        ├── tiendas/        # CRUD conexiones a tiendas
        └── mapeos/         # Mapeo categorias/impuestos
```

#### Arquitectura Ecommerce

```
WooCommerce / Shopify / MercadoLibre
    │
    ├── Webhook: nuevo pedido ──────────────────┐
    │                                            ▼
    │                               Edge Function: webhook-ecommerce
    │                                   (verify_jwt: false, valida firma)
    │                                            │
    │   ┌────────────────────────────────────────┤
    │   │  1. Crear contacto (si no existe)      │
    │   │  2. Crear orden de venta               │
    │   │  3. Reservar stock                     │
    │   │  4. Generar factura electronica        │
    │   │  5. Registrar pago (si ya pagado)      │
    │   │  6. Notificar al vendedor              │
    │   └────────────────────────────────────────┘
    │
    ├── API: sync productos ←── Edge Function: sync-ecommerce
    ├── API: actualizar stock ←── Trigger: al facturar/despachar
    └── API: actualizar estado ←── Al cambiar estado del pedido
```

#### Modelo de Datos - Ecommerce

```sql
-- Conexiones a tiendas ecommerce
tiendas_ecommerce
  id                    UUID PK
  empresa_id            UUID FK -> empresas
  plataforma            VARCHAR(20) NOT NULL  -- WOOCOMMERCE, SHOPIFY, MERCADOLIBRE
  nombre                VARCHAR(100)
  url_tienda            TEXT NOT NULL
  credenciales          JSONB NOT NULL  -- Encriptado (api_key, secret, token)
  sync_productos        BOOLEAN DEFAULT true
  sync_stock            BOOLEAN DEFAULT true
  sync_pedidos          BOOLEAN DEFAULT true
  activa                BOOLEAN DEFAULT true

-- Mapeo productos ERP ↔ tienda
mapeo_productos
  id                    UUID PK
  tienda_id             UUID FK -> tiendas_ecommerce
  producto_id           UUID FK -> productos
  producto_externo_id   VARCHAR(100)   -- ID en la plataforma
  sku_externo           VARCHAR(50)
  sync_precio           BOOLEAN DEFAULT true
  sync_stock            BOOLEAN DEFAULT true

-- Pedidos recibidos de ecommerce
pedidos_ecommerce
  id                    UUID PK
  tienda_id             UUID FK -> tiendas_ecommerce
  pedido_externo_id     VARCHAR(100) NOT NULL
  estado_externo        VARCHAR(50)
  orden_venta_id        UUID FK -> ordenes_venta
  factura_id            UUID FK -> facturas
  monto_total           DECIMAL(14,2)
  estado                VARCHAR(20) DEFAULT 'RECIBIDO'
    -- RECIBIDO, PROCESANDO, FACTURADO, DESPACHADO, COMPLETADO, CANCELADO
  datos_raw             JSONB          -- Datos originales del pedido
  created_at            TIMESTAMPTZ
```

#### Bodega Ecommerce Dedicada

El stock sincronizado al canal ecommerce proviene SOLO de una bodega dedicada. Esto evita sobreventas
al separar stock fisico de stock online. La configuracion se realiza a nivel de tienda:

```sql
-- En tabla tiendas_ecommerce agregar referencia a bodega:
ALTER TABLE tiendas_ecommerce
  ADD COLUMN bodega_ecommerce_id UUID REFERENCES bodegas(id);

-- NOTA: La sincronizacion de stock WooCommerce/Shopify usa EXCLUSIVAMENTE
-- inventario_stock WHERE bodega_id = tiendas_ecommerce.bodega_ecommerce_id
-- Si bodega_ecommerce_id IS NULL, se usa la bodega principal del establecimiento.

-- La Edge Function sync-ecommerce consulta:
--   SELECT s.cantidad_disponible
--   FROM inventario_stock s
--   JOIN tiendas_ecommerce t ON t.bodega_ecommerce_id = s.bodega_id
--   WHERE t.id = p_tienda_id AND s.producto_id = p_producto_id;
```

#### Fulfillment y Tracking de Envios

Gestion de envios con integracion a couriers ecuatorianos. Integracion inicial con Servientrega REST API;
otros couriers soportan tracking manual.

```sql
-- ENVIOS (seguimiento de despachos ecommerce/ventas)
CREATE TABLE envios (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  factura_id      UUID REFERENCES facturas(id),
  pedido_ecommerce_id UUID REFERENCES pedidos_ecommerce(id),
  courier         VARCHAR(30) NOT NULL,   -- SERVIENTREGA, TRAMACO, LAAR, OTRO
  guia_numero     VARCHAR(50),
  estado          VARCHAR(20) NOT NULL DEFAULT 'PREPARANDO',
    -- PREPARANDO, ENVIADO, EN_TRANSITO, ENTREGADO, DEVUELTO
  tracking_url    TEXT,
  peso            DECIMAL(10,3),
  bultos          INTEGER DEFAULT 1,
  costo_envio     DECIMAL(14,2) DEFAULT 0,
  fecha_envio     TIMESTAMPTZ,
  fecha_entrega   TIMESTAMPTZ,
  direccion_destino TEXT,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE envios ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON envios
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- EVENTOS DE TRACKING (historial de estados del envio)
CREATE TABLE envio_eventos (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  envio_id        UUID NOT NULL REFERENCES envios(id) ON DELETE CASCADE,
  estado          VARCHAR(20) NOT NULL,
  fecha           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  detalle         TEXT,
  origen          VARCHAR(20) NOT NULL DEFAULT 'MANUAL'  -- COURIER_API, MANUAL
);

CREATE INDEX idx_envio_eventos_envio ON envio_eventos(envio_id);
```

```
Edge Function: sync-courier-tracking (cron cada 4 horas)
Endpoint: /functions/v1/sync-courier-tracking

Flujo:
  1. Consulta envios con estado != ENTREGADO y estado != DEVUELTO
  2. Agrupa por courier
  3. Para SERVIENTREGA: llama REST API con guia_numero -> obtiene ultimo estado
  4. Para otros couriers: solo procesa si tienen API configurada
  5. Inserta envio_eventos con origen = COURIER_API
  6. Actualiza envios.estado si cambio
  7. Si estado = ENTREGADO -> notifica al vendedor + cliente (email/whatsapp)

NOTA: Integracion inicial solo con Servientrega REST API.
Otros couriers (Tramaco, Laar) se registran manualmente desde la UI
hasta que se implemente su conector API.
```

#### Devoluciones Ecommerce

Flujo completo de devolucion para compras realizadas por canal ecommerce:

```
1. Cliente solicita devolucion via portal web o email
2. Operador crea registro de devolucion ecommerce (estado: SOLICITADA)
3. Se evalua y aprueba/rechaza la devolucion
4. Si aprobada: cliente envia producto de vuelta (o se coordina recogida)
5. Bodega recibe producto e inspecciona -> estado RECIBIDA
6. Se genera Nota de Credito electronica (SRI) -> estado NC_EMITIDA
7. Se procesa reembolso:
   - REVERSION_PAGO: reverso via pasarela (Kushki/PayPhone reverse API)
   - CREDITO_TIENDA: se acredita saldo a favor del cliente
8. Estado final: REEMBOLSADA o RECHAZADA
```

```sql
-- DEVOLUCIONES ECOMMERCE
CREATE TABLE devoluciones_ecommerce (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  pedido_ecommerce_id   UUID NOT NULL REFERENCES pedidos_ecommerce(id),
  contacto_id           UUID REFERENCES contactos(id),
  motivo                TEXT NOT NULL,
  estado                VARCHAR(20) NOT NULL DEFAULT 'SOLICITADA',
    -- SOLICITADA, APROBADA, RECIBIDA, NC_EMITIDA, REEMBOLSADA, RECHAZADA
  nc_id                 UUID REFERENCES notas_credito(id),
  rma_id                UUID REFERENCES rma(id),   -- Link a RMA si aplica inspeccion
  reembolso_monto       DECIMAL(14,2),
  metodo_reembolso      VARCHAR(20),               -- REVERSION_PAGO, CREDITO_TIENDA
  pago_online_id        UUID REFERENCES pagos_online(id),  -- Pago original a reversar
  notas_rechazo         TEXT,
  fecha_solicitud       TIMESTAMPTZ DEFAULT NOW(),
  fecha_reembolso       TIMESTAMPTZ,
  created_at            TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE devoluciones_ecommerce ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON devoluciones_ecommerce
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

---

## Modelo de Datos Base (Tiendas y Sincronización)

### Arquitectura General del Módulo

```
PILAR ERP ←→ Edge Functions (Deno) ←→ APIs Externas
             ecommerce-sync-stock      WooCommerce REST API
             ecommerce-pull-orders     MercadoLibre API
             ecommerce-push-price      Shopify GraphQL API
             webhook-ecommerce         Amazon SP-API
```

Edge Functions manejan todas las credenciales de tiendas, rate limiting y reintentos.
PILAR nunca llama directamente a las APIs externas desde el cliente Flutter.

```
WooCommerce / Shopify / MercadoLibre / Amazon
    │
    ├── Webhook: nuevo pedido ──────────────────────────────┐
    │                                                        ▼
    │                                    Edge Function: webhook-ecommerce
    │                                        (verify_jwt: false, valida firma HMAC)
    │                                                        │
    │   ┌────────────────────────────────────────────────────┤
    │   │  1. Lookup tienda por endpoint / secreto           │
    │   │  2. Crear/vincular contacto por email              │
    │   │  3. INSERT pedidos_ecommerce                       │
    │   │  4. Llamar process_ecommerce_order()               │
    │   │     → Crear OV en Ventas                           │
    │   │     → Reservar stock en Inventario                 │
    │   │     → Facturar si factura_automatica = true        │
    │   │  5. Notificar al vendedor (WhatsApp/email)         │
    │   └────────────────────────────────────────────────────┘
    │
    ├── PUSH stock/precio ←── Edge Function: ecommerce-sync-stock / push-price
    │                         (cron horario o trigger post-movimiento inventario)
    └── PULL pedidos ←────── Edge Function: ecommerce-pull-orders
                             (cron cada 15 min para tiendas sin webhook)
```

### Tabla: `tiendas_online`

```sql
CREATE TABLE tiendas_online (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id UUID NOT NULL REFERENCES empresas(id),
  nombre VARCHAR(100) NOT NULL,
  tipo VARCHAR(20) NOT NULL CHECK (tipo IN ('WOOCOMMERCE','MERCADOLIBRE','SHOPIFY','AMAZON','CUSTOM')),
  url_base TEXT,                        -- Para WooCommerce: URL de la tienda
  api_key TEXT,                          -- API Key encriptada en Supabase Vault
  api_secret TEXT,                       -- Secret encriptado
  access_token TEXT,                     -- Token OAuth (MercadoLibre, Shopify)
  refresh_token TEXT,
  token_expira TIMESTAMPTZ,
  bodega_id UUID REFERENCES bodegas(id), -- Bodega que despacha pedidos de esta tienda
  punto_emision_id UUID REFERENCES puntos_emision(id), -- Para facturar automáticamente
  factura_automatica BOOLEAN DEFAULT false, -- Facturar al confirmar pedido
  sync_stock BOOLEAN DEFAULT true,
  sync_precios BOOLEAN DEFAULT true,
  sync_pedidos BOOLEAN DEFAULT true,
  ultimo_sync TIMESTAMPTZ,
  estado VARCHAR(15) DEFAULT 'ACTIVA' CHECK (estado IN ('ACTIVA','PAUSADA','ERROR')),
  activa BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(empresa_id, nombre)
);

ALTER TABLE tiendas_online ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON tiendas_online FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE INDEX idx_tiendas_empresa ON tiendas_online(empresa_id, activa);
```

### Tabla: `sync_log_ecommerce`

```sql
CREATE TABLE sync_log_ecommerce (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id UUID NOT NULL REFERENCES empresas(id),
  tienda_id UUID NOT NULL REFERENCES tiendas_online(id),
  tipo_sync VARCHAR(20) NOT NULL CHECK (tipo_sync IN ('STOCK','PRECIO','PRODUCTO','PEDIDO')),
  direccion VARCHAR(10) NOT NULL CHECK (direccion IN ('PUSH','PULL')),  -- PUSH=PILAR→Tienda, PULL=Tienda→PILAR
  registros_procesados INTEGER DEFAULT 0,
  registros_exitosos INTEGER DEFAULT 0,
  registros_error INTEGER DEFAULT 0,
  errores_detalle JSONB DEFAULT '[]',
  duracion_ms INTEGER,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE sync_log_ecommerce ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON sync_log_ecommerce FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE INDEX idx_sync_log_tienda ON sync_log_ecommerce(tienda_id, created_at DESC);
```

### Tabla: `pedidos_ecommerce` (ampliada)

```sql
-- Versión canónica con todos los campos. Reemplaza el stub anterior.
CREATE TABLE pedidos_ecommerce (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id UUID NOT NULL REFERENCES empresas(id),
  tienda_id UUID NOT NULL REFERENCES tiendas_online(id),
  external_order_id VARCHAR(100) NOT NULL,   -- ID del pedido en la tienda externa
  external_order_number VARCHAR(50),          -- Número visible (ej: "#1234")
  contacto_id UUID REFERENCES contactos(id), -- Cliente PILAR vinculado
  cliente_nombre VARCHAR(300),                -- Nombre del comprador en la tienda
  cliente_email VARCHAR(200),
  cliente_telefono VARCHAR(30),
  direccion_entrega JSONB,                    -- Dirección de entrega completa
  subtotal DECIMAL(14,2) NOT NULL,
  descuento DECIMAL(14,2) DEFAULT 0,
  envio DECIMAL(14,2) DEFAULT 0,
  impuestos DECIMAL(14,2) DEFAULT 0,
  total DECIMAL(14,2) NOT NULL,
  moneda VARCHAR(3) DEFAULT 'USD',
  estado_externo VARCHAR(50),                 -- Estado en la tienda (pending, processing, etc.)
  estado_pilar VARCHAR(20) DEFAULT 'NUEVO' CHECK (estado_pilar IN ('NUEVO','PROCESANDO','CONFIRMADO','DESPACHADO','ENTREGADO','CANCELADO')),
  orden_venta_id UUID,                        -- OV generada en PILAR
  factura_id UUID,                            -- Factura generada automáticamente
  fecha_pedido TIMESTAMPTZ NOT NULL,
  lineas JSONB NOT NULL DEFAULT '[]',         -- Líneas del pedido (producto, qty, precio)
  metadata JSONB DEFAULT '{}',                -- Datos extra de la tienda
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(empresa_id, tienda_id, external_order_id)
);

ALTER TABLE pedidos_ecommerce ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON pedidos_ecommerce FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE INDEX idx_pedidos_tienda ON pedidos_ecommerce(tienda_id, estado_pilar);
CREATE INDEX idx_pedidos_externo ON pedidos_ecommerce(empresa_id, external_order_id);
```

---

## RPCs Principales del Módulo Ecommerce

```sql
-- ══════════════════════════════════════════════════════════════
-- RPC: Sincronizar stock de PILAR → tienda externa
-- Si p_producto_ids es NULL, sincroniza todos los productos activos
-- Delega la llamada real a Edge Function ecommerce-sync-stock
-- ══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION sync_stock_to_store(
  p_tienda_id UUID,
  p_producto_ids UUID[] DEFAULT NULL
) RETURNS JSONB  -- {enviados, exitosos, errores}
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_tienda tiendas_online%ROWTYPE;
  v_log_id UUID;
BEGIN
  SELECT * INTO v_tienda FROM tiendas_online
  WHERE id = p_tienda_id AND empresa_id = (SELECT private.get_empresa_id()) AND activa = true;
  IF v_tienda.id IS NULL THEN RAISE EXCEPTION 'Tienda no encontrada o inactiva'; END IF;
  IF NOT v_tienda.sync_stock THEN RAISE EXCEPTION 'Sincronización de stock deshabilitada para esta tienda'; END IF;

  -- Registrar inicio del sync
  INSERT INTO sync_log_ecommerce (empresa_id, tienda_id, tipo_sync, direccion)
  VALUES (v_tienda.empresa_id, p_tienda_id, 'STOCK', 'PUSH')
  RETURNING id INTO v_log_id;

  -- La ejecución real ocurre en Edge Function ecommerce-sync-stock
  -- Esta RPC registra la intención y retorna el log_id para tracking
  RETURN jsonb_build_object('log_id', v_log_id, 'tienda', v_tienda.nombre, 'tipo', v_tienda.tipo);
END;
$$;

-- ══════════════════════════════════════════════════════════════
-- RPC: Descargar pedidos nuevos desde la tienda externa
-- Consulta la API de la tienda por pedidos más recientes que ultimo_sync
-- Crea registros en pedidos_ecommerce, vincula clientes por email
-- ══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION pull_orders_from_store(
  p_tienda_id UUID
) RETURNS JSONB  -- {pedidos_nuevos, pedidos_actualizados}
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_tienda tiendas_online%ROWTYPE;
  v_log_id UUID;
BEGIN
  SELECT * INTO v_tienda FROM tiendas_online
  WHERE id = p_tienda_id AND empresa_id = (SELECT private.get_empresa_id()) AND activa = true;
  IF v_tienda.id IS NULL THEN RAISE EXCEPTION 'Tienda no encontrada o inactiva'; END IF;
  IF NOT v_tienda.sync_pedidos THEN RAISE EXCEPTION 'Sincronización de pedidos deshabilitada'; END IF;

  INSERT INTO sync_log_ecommerce (empresa_id, tienda_id, tipo_sync, direccion)
  VALUES (v_tienda.empresa_id, p_tienda_id, 'PEDIDO', 'PULL')
  RETURNING id INTO v_log_id;

  -- Edge Function ecommerce-pull-orders ejecuta la lógica real:
  -- 1. GET /orders?after=ultimo_sync (WooCommerce) o similar
  -- 2. INSERT INTO pedidos_ecommerce (con UPSERT por external_order_id)
  -- 3. UPDATE tiendas_online SET ultimo_sync = NOW()
  RETURN jsonb_build_object('log_id', v_log_id, 'desde', v_tienda.ultimo_sync);
END;
$$;

-- ══════════════════════════════════════════════════════════════
-- RPC: Procesar pedido ecommerce → OV en PILAR
-- Convierte pedido_ecommerce en OV, reserva stock,
-- opcionalmente factura vía module_bus.facturacion
-- ══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION process_ecommerce_order(
  p_pedido_id UUID
) RETURNS JSONB  -- {orden_venta_id, factura_id}
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_pedido pedidos_ecommerce%ROWTYPE;
  v_tienda tiendas_online%ROWTYPE;
  v_ov_id UUID;
  v_factura_id UUID;
BEGIN
  SELECT * INTO v_pedido FROM pedidos_ecommerce
  WHERE id = p_pedido_id AND empresa_id = (SELECT private.get_empresa_id());
  IF v_pedido.id IS NULL THEN RAISE EXCEPTION 'Pedido ecommerce no encontrado'; END IF;
  IF v_pedido.estado_pilar != 'NUEVO' THEN RAISE EXCEPTION 'Pedido ya procesado'; END IF;

  SELECT * INTO v_tienda FROM tiendas_online WHERE id = v_pedido.tienda_id;

  -- Actualizar estado a PROCESANDO
  UPDATE pedidos_ecommerce SET estado_pilar = 'PROCESANDO' WHERE id = p_pedido_id;

  -- 1. Crear contacto si no existe (lookup por email)
  IF v_pedido.contacto_id IS NULL AND v_pedido.cliente_email IS NOT NULL THEN
    SELECT id INTO v_pedido.contacto_id FROM contactos
    WHERE empresa_id = v_pedido.empresa_id AND email = v_pedido.cliente_email LIMIT 1;
  END IF;

  -- 2. Crear Orden de Venta a través del Module Service Bus
  v_ov_id := module_bus.ventas.create_order_from_ecommerce(
    v_pedido.empresa_id,
    v_pedido.contacto_id,
    v_pedido.lineas,
    v_tienda.bodega_id,
    v_tienda.punto_emision_id
  );

  -- 3. Facturar automáticamente si está configurado
  IF v_tienda.factura_automatica AND v_tienda.punto_emision_id IS NOT NULL THEN
    v_factura_id := module_bus.facturacion.create_invoice(
      v_pedido.empresa_id, v_ov_id, v_tienda.punto_emision_id
    );
  END IF;

  -- 4. Vincular OV y factura al pedido ecommerce
  UPDATE pedidos_ecommerce SET
    estado_pilar = 'CONFIRMADO',
    orden_venta_id = v_ov_id,
    factura_id = v_factura_id
  WHERE id = p_pedido_id;

  RETURN jsonb_build_object('orden_venta_id', v_ov_id, 'factura_id', v_factura_id);
END;
$$;
```

---

## Diagrama de Integración PILAR ↔ Plataformas Ecommerce

```
┌─────────────────────────────────────────────────────────────┐
│                        PILAR ERP                            │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │ Ventas   │  │Inventario│  │Facturac. │  │Contactos │   │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘   │
│       │             │             │              │          │
│  ─────┴─────────────┴─────────────┴──────────────┴──────── │
│                   Module Service Bus                        │
│  ─────────────────────────┬──────────────────────────────── │
│                           │                                 │
│              ┌────────────┴────────────┐                    │
│              │    Ecommerce Core       │                    │
│              │  tiendas_online         │                    │
│              │  pedidos_ecommerce      │                    │
│              │  sync_log_ecommerce     │                    │
│              └────────────┬────────────┘                    │
└───────────────────────────┼─────────────────────────────────┘
                            │ Supabase Edge Functions
          ┌─────────────────┼───────────────────────────┐
          │                 │                           │
          ▼                 ▼                           ▼
   ecommerce-sync-stock  ecommerce-pull-orders   webhook-ecommerce
   ecommerce-push-price  ecommerce-courier-sync  ecommerce-auth-refresh
          │                 │                           │
          │                 │                           │
   ┌──────┴──────┐   ┌──────┴──────┐           ┌───────┴──────┐
   │WooCommerce  │   │MercadoLibre │           │  Shopify     │
   │REST API v3  │   │API v2       │           │  GraphQL     │
   └─────────────┘   └─────────────┘           └──────────────┘
                                                       │
                                               ┌───────┴──────┐
                                               │  Amazon      │
                                               │  SP-API      │
                                               └──────────────┘
```

---

## Sub-módulos

| Sub-módulo | Descripción |
|---|---|
| [Multi-Marketplace](./multi-marketplace.md) | Integración con MercadoLibre, Shopify y Amazon — autenticación OAuth, sincronización de catálogo, gestión de publicaciones y pedidos por canal |
| [Portal de Clientes](./portal-clientes.md) | Portal B2C para clientes frecuentes — consulta de facturas, pagos online, historial de pedidos y autoservicio |

---

## RLS e Índices Complementarios

```sql
-- Índice para búsqueda de pedidos por email de cliente (vincular contacto)
CREATE INDEX idx_pedidos_email ON pedidos_ecommerce(empresa_id, cliente_email)
  WHERE cliente_email IS NOT NULL;

-- Índice para pedidos pendientes de procesar
CREATE INDEX idx_pedidos_nuevos ON pedidos_ecommerce(tienda_id, created_at)
  WHERE estado_pilar = 'NUEVO';

-- Índice para sync log por fecha
CREATE INDEX idx_sync_log_fecha ON sync_log_ecommerce(empresa_id, created_at DESC);

-- Índice para tiendas activas con token próximo a vencer (alertas OAuth)
CREATE INDEX idx_tiendas_token_exp ON tiendas_online(empresa_id, token_expira)
  WHERE activa = true AND token_expira IS NOT NULL;
```
```

