# Módulo de Inventario

Gestión integral de productos, bodegas, stock, movimientos y documentos de traslado. Incluye control multi-bodega, series/lotes, multi-empaque y guías de remisión electrónicas (SRI tipo 06).

> Sub-módulos detallados: [BOM](bom-multinivel.md) · [Control Calidad](control-calidad.md) · [Forecast](forecast-demanda.md) · [Kardex](kardex.md) · [Reservas](reservas-productos.md) · [Devoluciones](devoluciones.md) · [Co-productos](co-productos.md) · [Conversión Stock](conversion-stock.md) · [App Bodeguero](app-bodeguero.md) · [IA Inventario](ia-inventario.md) · [Dashboard](dashboard.md)

---

## Navegación

```
inventario/
  ├── productos/
  │     ├── listado/            # SfDataGrid con filtros (categoría, bodega, stock)
  │     ├── nuevo/              # Formulario con pestañas (general, presentaciones, impuestos, fotos)
  │     └── detalle/            # Vista producto + historial movimientos + stock por bodega
  ├── categorias/               # Árbol de categorías (TreeView)
  ├── bodegas/                  # CRUD bodegas y configuración multi-bodega
  ├── movimientos/
  │     ├── ingresos/           # Entrada de mercadería (compras, producción, ajuste+)
  │     ├── egresos/            # Salida de mercadería (ventas, consumo, ajuste-)
  │     ├── transferencias/     # Transferencias entre bodegas
  │     └── ajustes/            # Ajustes de inventario (con motivo)
  ├── guias-remision/           # Emisión guías de remisión V1.1.0 (SRI tipo 06)
  ├── kardex/                   # Consulta de movimientos por producto/bodega/período
  └── reportes/
        ├── stock-actual/       # Stock en tiempo real por bodega
        ├── stock-minimo/       # Productos bajo stock mínimo
        ├── valoracion/         # Valoración de inventario (costo promedio)
        └── movimientos/        # Reporte de movimientos por período
```

---

## Modelo de Datos

### Productos y Presentaciones

```sql
-- Producto base (unidad mínima de control)
CREATE TABLE productos (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  categoria_id          UUID REFERENCES categorias_producto(id),
  codigo                VARCHAR(50) NOT NULL,         -- Código interno
  nombre                VARCHAR(300) NOT NULL,
  descripcion           TEXT,
  tipo                  VARCHAR(20) NOT NULL DEFAULT 'PRODUCTO',
    -- PRODUCTO, SERVICIO, CONSUMIBLE, ACTIVO_FIJO, KIT, MATERIA_PRIMA
  es_compra             BOOLEAN DEFAULT true,
  es_venta              BOOLEAN DEFAULT true,
  -- Unidad de medida
  uom_id                UUID REFERENCES unidades_medida(id),
  uom_compra_id         UUID REFERENCES unidades_medida(id),   -- UoM de compra (puede diferir)
  -- Precios base
  precio_venta          DECIMAL(18,6) DEFAULT 0,
  costo                 DECIMAL(18,6) DEFAULT 0,               -- Costo promedio calculado
  -- Control de stock
  control_stock         BOOLEAN DEFAULT true,
  stock_minimo          DECIMAL(18,6) DEFAULT 0,
  stock_maximo          DECIMAL(18,6) DEFAULT 0,
  punto_reorden         DECIMAL(18,6) DEFAULT 0,
  -- Trazabilidad
  usa_series            BOOLEAN DEFAULT false,                  -- Números de serie (1:1)
  usa_lotes             BOOLEAN DEFAULT false,                  -- Lotes (1:N)
  -- Estado
  activo                BOOLEAN DEFAULT true,
  created_at            TIMESTAMPTZ DEFAULT now(),
  UNIQUE(empresa_id, codigo)
);

-- Presentaciones (multi-empaque): 1 producto → N presentaciones
CREATE TABLE producto_presentaciones (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  producto_id           UUID NOT NULL REFERENCES productos(id) ON DELETE CASCADE,
  nombre                VARCHAR(100) NOT NULL,         -- 'Caja x12', 'Pack x6'
  factor_conversion     DECIMAL(18,6) NOT NULL,        -- 12.0 → 1 caja = 12 unidades
  precio_venta          DECIMAL(18,6),                 -- NULL = heredar producto * factor
  costo                 DECIMAL(18,6),
  activo                BOOLEAN DEFAULT true,
  UNIQUE(producto_id, nombre)
);

-- Códigos de barras por producto/presentación
CREATE TABLE producto_codigos_barras (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  producto_id           UUID NOT NULL REFERENCES productos(id) ON DELETE CASCADE,
  presentacion_id       UUID REFERENCES producto_presentaciones(id),  -- NULL = unidad base
  codigo                VARCHAR(100) NOT NULL UNIQUE,
  tipo                  VARCHAR(10) DEFAULT 'EAN13'     -- EAN13, EAN8, CODE128, QR
);

-- Impuestos del producto
CREATE TABLE producto_impuestos (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  producto_id           UUID NOT NULL REFERENCES productos(id) ON DELETE CASCADE,
  tarifa_iva_id         UUID REFERENCES catalogo_tarifas_iva(id),     -- IVA aplicable
  tarifa_ice_id         UUID REFERENCES catalogo_tarifas_ice(id),     -- ICE (si aplica)
  tipo                  VARCHAR(10) DEFAULT 'VENTA'     -- VENTA, COMPRA
);
```

### Categorías y Unidades de Medida

```sql
CREATE TABLE categorias_producto (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  parent_id             UUID REFERENCES categorias_producto(id),      -- Árbol
  nombre                VARCHAR(200) NOT NULL,
  cuenta_inventario_id  UUID REFERENCES cuentas_contables(id),        -- Cuenta NIIF
  cuenta_costo_id       UUID REFERENCES cuentas_contables(id),
  cuenta_ingreso_id     UUID REFERENCES cuentas_contables(id),
  activo                BOOLEAN DEFAULT true
);

CREATE TABLE unidades_medida (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  nombre                VARCHAR(50) NOT NULL,            -- 'Unidad', 'Caja', 'Galón', 'Kg'
  abreviatura           VARCHAR(10) NOT NULL,            -- 'u', 'cj', 'gal', 'kg'
  tipo                  VARCHAR(20) DEFAULT 'UNIDAD',    -- UNIDAD, PESO, VOLUMEN, LONGITUD
  factor_conversion     DECIMAL(18,6) DEFAULT 1,         -- Relativo a la unidad base del tipo
  es_base               BOOLEAN DEFAULT false,
  activo                BOOLEAN DEFAULT true
);
```

### Bodegas y Stock

```sql
CREATE TABLE bodegas (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  establecimiento_id    UUID REFERENCES establecimientos(id),
  nombre                VARCHAR(200) NOT NULL,
  tipo                  VARCHAR(20) DEFAULT 'PRINCIPAL',
    -- PRINCIPAL, ALTERNA, TALLER, GARANTIAS, SUMINISTROS_TALLER, VIRTUAL
  es_principal          BOOLEAN DEFAULT false,           -- Bodega principal del establecimiento
  responsable_id        UUID REFERENCES auth.users(id),
  activo                BOOLEAN DEFAULT true,
  UNIQUE(empresa_id, nombre)
);

-- Stock actual por producto + bodega (tabla denormalizada para consultas rápidas)
CREATE TABLE inventario_stock (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  producto_id           UUID NOT NULL REFERENCES productos(id),
  bodega_id             UUID NOT NULL REFERENCES bodegas(id),
  cantidad              DECIMAL(18,6) NOT NULL DEFAULT 0,
  cantidad_reservada    DECIMAL(18,6) DEFAULT 0,         -- Reservas activas
  cantidad_disponible   DECIMAL(18,6) GENERATED ALWAYS AS (cantidad - cantidad_reservada) STORED,
  costo_promedio        DECIMAL(18,6) DEFAULT 0,         -- Costo promedio ponderado
  updated_at            TIMESTAMPTZ DEFAULT now(),
  UNIQUE(empresa_id, producto_id, bodega_id)
);
```

### Movimientos de Inventario (Kardex)

```sql
-- Todos los movimientos de stock quedan registrados aquí
CREATE TABLE movimientos_inventario (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  producto_id           UUID NOT NULL REFERENCES productos(id),
  bodega_id             UUID NOT NULL REFERENCES bodegas(id),
  tipo                  VARCHAR(30) NOT NULL,
    -- ENTRADA_COMPRA, ENTRADA_PRODUCCION, ENTRADA_AJUSTE,
    -- SALIDA_VENTA, SALIDA_CONSUMO, SALIDA_AJUSTE,
    -- TRANSFERENCIA_SALIDA, TRANSFERENCIA_ENTRADA,
    -- DEVOLUCION_VENTA, DEVOLUCION_COMPRA
  cantidad              DECIMAL(18,6) NOT NULL,           -- Positivo siempre
  costo_unitario        DECIMAL(18,6) NOT NULL,
  costo_total           DECIMAL(18,6) NOT NULL,           -- cantidad * costo_unitario
  -- Saldo calculado después del movimiento
  saldo_cantidad        DECIMAL(18,6) NOT NULL,
  saldo_valor           DECIMAL(18,6) NOT NULL,
  -- Referencia al documento origen
  documento_tipo        VARCHAR(30),                      -- FACTURA, OC, TRANSFERENCIA, AJUSTE
  documento_id          UUID,                             -- FK al documento origen
  -- Trazabilidad
  serie_id              UUID REFERENCES series_producto(id),
  lote_id               UUID REFERENCES lotes_producto(id),
  -- Transferencia (si aplica)
  bodega_destino_id     UUID REFERENCES bodegas(id),      -- En transferencias
  transferencia_id      UUID REFERENCES transferencias_bodega(id),
  -- Motivo (para ajustes)
  motivo                VARCHAR(300),
  usuario_id            UUID REFERENCES auth.users(id),
  fecha                 TIMESTAMPTZ DEFAULT now(),
  created_at            TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_mov_inv_producto ON movimientos_inventario(empresa_id, producto_id, fecha DESC);
CREATE INDEX idx_mov_inv_bodega ON movimientos_inventario(empresa_id, bodega_id, fecha DESC);
CREATE INDEX idx_mov_inv_documento ON movimientos_inventario(documento_tipo, documento_id);
```

### Series y Lotes

```sql
-- Series de producto (trazabilidad 1:1 — un número de serie = 1 unidad)
CREATE TABLE series_producto (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  producto_id           UUID NOT NULL REFERENCES productos(id),
  numero_serie          VARCHAR(100) NOT NULL,
  bodega_id             UUID REFERENCES bodegas(id),
  estado                VARCHAR(20) DEFAULT 'DISPONIBLE',
    -- DISPONIBLE, VENDIDO, GARANTIA, REPARACION, DADO_BAJA
  proveedor_id          UUID REFERENCES contactos(id),
  fecha_ingreso         DATE,
  factura_compra_id     UUID,                             -- Doc de compra
  factura_venta_id      UUID,                             -- Doc de venta
  UNIQUE(empresa_id, producto_id, numero_serie)
);

-- Lotes (trazabilidad 1:N — un lote puede tener varias unidades)
CREATE TABLE lotes_producto (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  producto_id           UUID NOT NULL REFERENCES productos(id),
  numero_lote           VARCHAR(100) NOT NULL,
  fecha_produccion      DATE,
  fecha_vencimiento     DATE,
  proveedor_id          UUID REFERENCES contactos(id),
  UNIQUE(empresa_id, producto_id, numero_lote)
);
```

### Transferencias entre Bodegas

```sql
CREATE TABLE transferencias_bodega (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  numero                VARCHAR(30) NOT NULL,
  bodega_origen_id      UUID NOT NULL REFERENCES bodegas(id),
  bodega_destino_id     UUID NOT NULL REFERENCES bodegas(id),
  estado                VARCHAR(20) DEFAULT 'BORRADOR',
    -- BORRADOR, CONFIRMADA, EN_TRANSITO, RECIBIDA, CANCELADA
  tipo                  VARCHAR(20) DEFAULT 'MANUAL',     -- MANUAL, AUTO (auto-transferencia)
  motivo                VARCHAR(300),
  solicitado_por        UUID REFERENCES auth.users(id),
  recibido_por          UUID REFERENCES auth.users(id),
  fecha_transferencia   DATE DEFAULT CURRENT_DATE,
  fecha_recepcion       DATE,
  guia_remision_id      UUID,                             -- Si genera guía SRI
  created_at            TIMESTAMPTZ DEFAULT now(),
  UNIQUE(empresa_id, numero)
);

CREATE TABLE transferencia_lineas (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  transferencia_id      UUID NOT NULL REFERENCES transferencias_bodega(id) ON DELETE CASCADE,
  producto_id           UUID NOT NULL REFERENCES productos(id),
  presentacion_id       UUID REFERENCES producto_presentaciones(id),
  cantidad              DECIMAL(18,6) NOT NULL,
  cantidad_recibida     DECIMAL(18,6) DEFAULT 0,          -- Puede diferir (merma, error)
  serie_ids             UUID[],                           -- Series transferidas
  lote_id               UUID REFERENCES lotes_producto(id),
  notas                 TEXT
);
```

### Ajustes de Inventario

```sql
CREATE TABLE ajustes_inventario (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  numero                VARCHAR(30) NOT NULL,
  bodega_id             UUID NOT NULL REFERENCES bodegas(id),
  tipo                  VARCHAR(20) DEFAULT 'CONTEO',     -- CONTEO, MERMA, DONACION, OTRO
  motivo                VARCHAR(300) NOT NULL,
  estado                VARCHAR(20) DEFAULT 'BORRADOR',   -- BORRADOR, APROBADO, APLICADO
  aprobado_por          UUID REFERENCES auth.users(id),
  created_at            TIMESTAMPTZ DEFAULT now(),
  UNIQUE(empresa_id, numero)
);

CREATE TABLE ajuste_lineas (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ajuste_id             UUID NOT NULL REFERENCES ajustes_inventario(id) ON DELETE CASCADE,
  producto_id           UUID NOT NULL REFERENCES productos(id),
  cantidad_sistema      DECIMAL(18,6) NOT NULL,           -- Stock según sistema antes del ajuste
  cantidad_fisica       DECIMAL(18,6) NOT NULL,           -- Conteo físico real
  diferencia            DECIMAL(18,6) GENERATED ALWAYS AS (cantidad_fisica - cantidad_sistema) STORED,
  costo_unitario        DECIMAL(18,6) NOT NULL,
  bodega_id             UUID REFERENCES bodegas(id)
);
```

### Guías de Remisión (SRI tipo 06)

```sql
CREATE TABLE guias_remision (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  establecimiento_id    UUID NOT NULL REFERENCES establecimientos(id),
  punto_emision_id      UUID NOT NULL REFERENCES puntos_emision(id),
  secuencial            VARCHAR(9),                        -- Asignado al confirmar
  clave_acceso          VARCHAR(49),                       -- 49 dígitos
  -- Datos del transporte
  ruc_transportista     VARCHAR(13) NOT NULL,
  razon_social_transportista VARCHAR(300) NOT NULL,
  placa                 VARCHAR(20) NOT NULL,
  -- Origen y destino
  direccion_partida     VARCHAR(300) NOT NULL,
  ruta                  VARCHAR(300),
  -- Destinatario
  ruc_destinatario      VARCHAR(20),
  razon_social_destinatario VARCHAR(300),
  direccion_destinatario VARCHAR(300),
  -- Fechas
  fecha_inicio_transporte DATE NOT NULL,
  fecha_fin_transporte  DATE,
  -- Estado SRI
  estado                VARCHAR(20) DEFAULT 'BORRADOR',
    -- BORRADOR, FIRMADA, AUTORIZADA, RECHAZADA, ANULADA
  fecha_autorizacion    TIMESTAMPTZ,
  numero_autorizacion   VARCHAR(49),
  xml_firmado_url       TEXT,                              -- URL en Supabase Storage
  -- Referencia
  transferencia_id      UUID REFERENCES transferencias_bodega(id),
  orden_venta_id        UUID,
  version               INTEGER DEFAULT 1,                 -- Bloqueo optimista
  created_at            TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE guia_lineas (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  guia_id               UUID NOT NULL REFERENCES guias_remision(id) ON DELETE CASCADE,
  codigo_interno        VARCHAR(50),
  descripcion           VARCHAR(300) NOT NULL,
  cantidad              DECIMAL(18,6) NOT NULL,
  uom                   VARCHAR(20) NOT NULL,
  unidad_medida         VARCHAR(3) DEFAULT '800',          -- Código SRI: 800=unidad
  detalles_adicionales  JSONB                              -- [{nombre, valor}] campos extra SRI
);
```

---

## Funciones RPC Clave

```sql
-- Crear movimiento de stock (función central — todos los movimientos pasan por aquí)
CREATE OR REPLACE FUNCTION create_stock_movement(
  p_empresa_id        UUID,
  p_producto_id       UUID,
  p_bodega_id         UUID,
  p_tipo              VARCHAR,
  p_cantidad          DECIMAL,
  p_costo_unitario    DECIMAL,
  p_documento_tipo    VARCHAR DEFAULT NULL,
  p_documento_id      UUID DEFAULT NULL,
  p_serie_id          UUID DEFAULT NULL,
  p_lote_id           UUID DEFAULT NULL,
  p_motivo            VARCHAR DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_movimiento_id UUID;
  v_saldo_anterior DECIMAL;
  v_saldo_valor DECIMAL;
  v_nueva_cantidad DECIMAL;
BEGIN
  -- Obtener saldo actual
  SELECT COALESCE(cantidad, 0), COALESCE(cantidad * costo_promedio, 0)
  INTO v_saldo_anterior, v_saldo_valor
  FROM inventario_stock
  WHERE empresa_id = p_empresa_id AND producto_id = p_producto_id AND bodega_id = p_bodega_id;

  IF NOT FOUND THEN
    v_saldo_anterior := 0;
    v_saldo_valor    := 0;
  END IF;

  -- Calcular nuevo saldo
  v_nueva_cantidad := CASE
    WHEN p_tipo LIKE 'ENTRADA%' OR p_tipo IN ('TRANSFERENCIA_ENTRADA', 'DEVOLUCION_VENTA')
      THEN v_saldo_anterior + p_cantidad
    WHEN p_tipo LIKE 'SALIDA%' OR p_tipo IN ('TRANSFERENCIA_SALIDA', 'DEVOLUCION_COMPRA')
      THEN v_saldo_anterior - p_cantidad
  END;

  -- Insertar movimiento
  INSERT INTO movimientos_inventario (
    empresa_id, producto_id, bodega_id, tipo, cantidad,
    costo_unitario, costo_total, saldo_cantidad, saldo_valor,
    documento_tipo, documento_id, serie_id, lote_id, motivo, usuario_id
  ) VALUES (
    p_empresa_id, p_producto_id, p_bodega_id, p_tipo, p_cantidad,
    p_costo_unitario, p_cantidad * p_costo_unitario, v_nueva_cantidad,
    v_nueva_cantidad * p_costo_unitario,
    p_documento_tipo, p_documento_id, p_serie_id, p_lote_id, p_motivo,
    auth.uid()
  ) RETURNING id INTO v_movimiento_id;

  -- Actualizar inventario_stock con costo promedio ponderado (entradas)
  INSERT INTO inventario_stock (empresa_id, producto_id, bodega_id, cantidad, costo_promedio)
  VALUES (p_empresa_id, p_producto_id, p_bodega_id, p_cantidad, p_costo_unitario)
  ON CONFLICT (empresa_id, producto_id, bodega_id) DO UPDATE SET
    cantidad = CASE
      WHEN p_tipo LIKE 'ENTRADA%' OR p_tipo IN ('TRANSFERENCIA_ENTRADA', 'DEVOLUCION_VENTA')
        THEN inventario_stock.cantidad + p_cantidad
      ELSE inventario_stock.cantidad - p_cantidad
    END,
    costo_promedio = CASE
      WHEN p_tipo LIKE 'ENTRADA%'  -- Solo actualizar costo en entradas
        THEN (inventario_stock.cantidad * inventario_stock.costo_promedio + p_cantidad * p_costo_unitario)
             / NULLIF(inventario_stock.cantidad + p_cantidad, 0)
      ELSE inventario_stock.costo_promedio
    END,
    updated_at = now();

  RETURN v_movimiento_id;
END;
$$;

-- Obtener stock de un producto (todos los bodegas o una específica)
CREATE OR REPLACE FUNCTION get_product_stock(
  p_empresa_id    UUID,
  p_producto_id   UUID,
  p_bodega_id     UUID DEFAULT NULL  -- NULL = todas las bodegas
) RETURNS TABLE (
  bodega_id UUID, bodega_nombre VARCHAR,
  cantidad DECIMAL, cantidad_reservada DECIMAL, cantidad_disponible DECIMAL,
  costo_promedio DECIMAL, valor_total DECIMAL
)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT s.bodega_id, b.nombre,
    s.cantidad, s.cantidad_reservada, s.cantidad_disponible,
    s.costo_promedio, s.cantidad * s.costo_promedio
  FROM inventario_stock s
  JOIN bodegas b ON b.id = s.bodega_id
  WHERE s.empresa_id = p_empresa_id
    AND s.producto_id = p_producto_id
    AND (p_bodega_id IS NULL OR s.bodega_id = p_bodega_id)
  ORDER BY b.es_principal DESC, b.nombre;
$$;

-- Transferencia entre bodegas (crea movimientos en ambas bodegas)
CREATE OR REPLACE FUNCTION transfer_stock(
  p_empresa_id        UUID,
  p_transferencia_id  UUID
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_trans RECORD;
  v_linea RECORD;
  v_costo DECIMAL;
BEGIN
  SELECT * INTO v_trans FROM transferencias_bodega WHERE id = p_transferencia_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transferencia % no encontrada', p_transferencia_id;
  END IF;

  IF v_trans.estado != 'CONFIRMADA' THEN
    RAISE EXCEPTION 'La transferencia debe estar en estado CONFIRMADA';
  END IF;

  FOR v_linea IN
    SELECT * FROM transferencia_lineas WHERE transferencia_id = p_transferencia_id
  LOOP
    -- Obtener costo promedio de la bodega origen
    SELECT costo_promedio INTO v_costo FROM inventario_stock
    WHERE empresa_id = p_empresa_id AND producto_id = v_linea.producto_id
      AND bodega_id = v_trans.bodega_origen_id;

    -- Salida de bodega origen
    PERFORM create_stock_movement(
      p_empresa_id, v_linea.producto_id, v_trans.bodega_origen_id,
      'TRANSFERENCIA_SALIDA', v_linea.cantidad, COALESCE(v_costo, 0),
      'TRANSFERENCIA', p_transferencia_id
    );
    -- Entrada a bodega destino
    PERFORM create_stock_movement(
      p_empresa_id, v_linea.producto_id, v_trans.bodega_destino_id,
      'TRANSFERENCIA_ENTRADA', v_linea.cantidad, COALESCE(v_costo, 0),
      'TRANSFERENCIA', p_transferencia_id
    );
  END LOOP;

  UPDATE transferencias_bodega
  SET estado = 'RECIBIDA', fecha_recepcion = CURRENT_DATE
  WHERE id = p_transferencia_id;
END;
$$;

-- Verificar y ejecutar auto-transferencia (modo CONSOLIDADO)
CREATE OR REPLACE FUNCTION check_and_auto_transfer(
  p_empresa_id      UUID,
  p_producto_id     UUID,
  p_bodega_principal UUID,
  p_cantidad_req    DECIMAL
) RETURNS BOOLEAN  -- true = stock suficiente (directo o tras transferencia)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_stock_principal DECIMAL;
  v_faltante DECIMAL;
  v_bodega RECORD;
  v_disponible DECIMAL;
BEGIN
  SELECT cantidad_disponible INTO v_stock_principal
  FROM inventario_stock
  WHERE empresa_id = p_empresa_id AND producto_id = p_producto_id
    AND bodega_id = p_bodega_principal;

  IF COALESCE(v_stock_principal, 0) >= p_cantidad_req THEN
    RETURN true;
  END IF;

  v_faltante := p_cantidad_req - COALESCE(v_stock_principal, 0);

  -- Buscar en bodegas alternas (por orden de prioridad)
  FOR v_bodega IN
    SELECT b.id, COALESCE(s.cantidad_disponible, 0) as disponible
    FROM bodegas b
    LEFT JOIN inventario_stock s ON s.bodega_id = b.id
      AND s.producto_id = p_producto_id AND s.empresa_id = p_empresa_id
    WHERE b.empresa_id = p_empresa_id AND b.tipo = 'ALTERNA' AND b.activo = true
    ORDER BY COALESCE(s.cantidad_disponible, 0) DESC
  LOOP
    IF v_faltante <= 0 THEN EXIT; END IF;

    v_disponible := LEAST(v_bodega.disponible, v_faltante);
    IF v_disponible > 0 THEN
      -- Crear transferencia automática
      PERFORM create_auto_transfer(p_empresa_id, v_bodega.id, p_bodega_principal,
        p_producto_id, v_disponible);
      v_faltante := v_faltante - v_disponible;
    END IF;
  END LOOP;

  RETURN v_faltante <= 0;
END;
$$;

-- Aplicar ajuste de inventario
CREATE OR REPLACE FUNCTION apply_inventory_adjustment(
  p_ajuste_id UUID
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_ajuste RECORD;
  v_linea RECORD;
BEGIN
  SELECT * INTO v_ajuste FROM ajustes_inventario WHERE id = p_ajuste_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ajuste de inventario % no encontrado', p_ajuste_id;
  END IF;

  IF v_ajuste.estado != 'APROBADO' THEN
    RAISE EXCEPTION 'El ajuste debe estar aprobado antes de aplicar';
  END IF;

  FOR v_linea IN
    SELECT * FROM ajuste_lineas WHERE ajuste_id = p_ajuste_id
  LOOP
    IF v_linea.diferencia > 0 THEN
      PERFORM create_stock_movement(
        v_ajuste.empresa_id, v_linea.producto_id, v_ajuste.bodega_id,
        'ENTRADA_AJUSTE', v_linea.diferencia, v_linea.costo_unitario,
        'AJUSTE', p_ajuste_id, NULL, NULL, v_ajuste.motivo
      );
    ELSIF v_linea.diferencia < 0 THEN
      PERFORM create_stock_movement(
        v_ajuste.empresa_id, v_linea.producto_id, v_ajuste.bodega_id,
        'SALIDA_AJUSTE', ABS(v_linea.diferencia), v_linea.costo_unitario,
        'AJUSTE', p_ajuste_id, NULL, NULL, v_ajuste.motivo
      );
    END IF;
  END LOOP;

  UPDATE ajustes_inventario SET estado = 'APLICADO' WHERE id = p_ajuste_id;
END;
$$;

-- Generar guía de remisión electrónica (SRI tipo 06)
CREATE OR REPLACE FUNCTION generate_guia_remision(
  p_empresa_id              UUID,
  p_establecimiento_id      UUID,
  p_ruc_transportista       VARCHAR,
  p_razon_social_transportista VARCHAR,
  p_placa                   VARCHAR,
  p_direccion_partida       VARCHAR,
  p_transferencia_id        UUID DEFAULT NULL,
  p_lineas                  JSONB DEFAULT '[]'
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_guia_id UUID;
  v_punto_emision RECORD;
BEGIN
  SELECT pe.* INTO v_punto_emision FROM puntos_emision pe
  WHERE pe.establecimiento_id = p_establecimiento_id
    AND pe.tipo_doc = '06' AND pe.activo = true LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No hay punto de emisión configurado para guías de remisión';
  END IF;

  INSERT INTO guias_remision (
    empresa_id, establecimiento_id, punto_emision_id,
    ruc_transportista, razon_social_transportista, placa,
    direccion_partida, fecha_inicio_transporte, transferencia_id
  ) VALUES (
    p_empresa_id, p_establecimiento_id, v_punto_emision.id,
    p_ruc_transportista, p_razon_social_transportista, p_placa,
    p_direccion_partida, CURRENT_DATE, p_transferencia_id
  ) RETURNING id INTO v_guia_id;

  -- Insertar líneas desde JSONB o desde la transferencia
  IF p_transferencia_id IS NOT NULL THEN
    INSERT INTO guia_lineas (guia_id, descripcion, cantidad, uom)
    SELECT v_guia_id, p.nombre, tl.cantidad, 'u'
    FROM transferencia_lineas tl
    JOIN productos p ON p.id = tl.producto_id
    WHERE tl.transferencia_id = p_transferencia_id;
  ELSE
    INSERT INTO guia_lineas (guia_id, descripcion, cantidad, uom)
    SELECT v_guia_id, l->>'descripcion', (l->>'cantidad')::DECIMAL, l->>'uom'
    FROM jsonb_array_elements(p_lineas) l;
  END IF;

  -- Encolar para firma y envío al SRI (no bloqueante)
  PERFORM module_bus.queue_electronic_document(v_guia_id, '06');

  RETURN v_guia_id;
END;
$$;
```

---

## Row Level Security

```sql
-- Aplicar a todas las tablas del módulo
ALTER TABLE productos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON productos
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

ALTER TABLE inventario_stock ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON inventario_stock
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

ALTER TABLE movimientos_inventario ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON movimientos_inventario
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- (aplicar patrón equivalente a bodegas, transferencias, ajustes, guias_remision)

-- Índices de soporte para RLS (evitar seq scan en tablas grandes)
CREATE INDEX idx_productos_empresa ON productos(empresa_id) WHERE activo = true;
CREATE INDEX idx_stock_empresa ON inventario_stock(empresa_id);
CREATE INDEX idx_mov_empresa ON movimientos_inventario(empresa_id, fecha DESC);
CREATE INDEX idx_bodegas_empresa ON bodegas(empresa_id) WHERE activo = true;
```

---

## Integraciones con otros Módulos

| Evento | Origen | Acción en Inventario |
|--------|--------|----------------------|
| Factura de venta confirmada | Ventas | `create_stock_movement` SALIDA_VENTA por establecimiento |
| OC recibida | Compras | `create_stock_movement` ENTRADA_COMPRA |
| Devolución de venta (NC) | Ventas/POS | `create_stock_movement` DEVOLUCION_VENTA a bodega POS |
| Devolución a proveedor | Compras | `create_stock_movement` DEVOLUCION_COMPRA |
| OT de ensamblaje completada | BOM | Consume materiales + ingresa producto terminado |
| Consumo en taller | Garantías/Taller | `create_stock_movement` SALIDA_CONSUMO desde SUMINISTROS_TALLER |
| Orden de trabajo instalación | Servicios | `create_stock_movement` SALIDA_CONSUMO materiales OT |

---

## Sub-módulos

| Sub-módulo | Descripción |
|------------|-------------|
| [BOM Multi-nivel](bom-multinivel.md) | Lista de materiales, órdenes de ensamblaje, explosión de componentes |
| [Control de Calidad](control-calidad.md) | Puntos de control QC en recepciones, transferencias y producción |
| [Forecast de Demanda](forecast-demanda.md) | Predicción de demanda con IA (pgvector + modelos) |
| [Kardex](kardex.md) | Reporte valorado ENTRADAS/SALIDAS/SALDOS |
| [Reservas de Productos](reservas-productos.md) | Reserva con bodega virtual, vencimiento, renovación |
| [Devoluciones](devoluciones.md) | Validación de series en devoluciones, bloqueo optimista |
| [Co-productos](co-productos.md) | Producción con múltiples productos resultado (subproductos) |
| [Conversión de Stock](conversion-stock.md) | Conversión producto A → producto B con movimientos inversos |
| [App Bodeguero](app-bodeguero.md) | UI mobile-first para bodegueros (recepción, despacho, conteo) |
| [IA Inventario](ia-inventario.md) | Detección de anomalías, sugerencias reorden, análisis ABC |
| [Dashboard](dashboard.md) | KPIs de inventario en tiempo real |
