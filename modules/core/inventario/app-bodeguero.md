# App Móvil Bodeguero


## Descripcion Funcional

Conjunto de pantallas Flutter optimizadas para tablet y smartphone, disenadas para el uso diario del bodeguero en un ambiente de bodega. Priorizan operacion con una sola mano, texto grande, botones amplios, y escaneo de codigos de barras como input principal.

**Principio: Offline-first es CRITICO.** Las bodegas frecuentemente carecen de WiFi estable. Todas las operaciones deben funcionar sin conexion y sincronizar automaticamente al reconectar, usando `brick_offline_first_with_supabase` y la estrategia SUMA DELTA para stock.

**Pantallas principales:**

1. **Recepcion de Mercaderia:** Escanear productos, validar contra OC, registrar cantidades recibidas, disparar inspeccion QC si aplica, ubicar en bodega.

2. **Conteo Fisico:** Modo ciego (sin mostrar stock teorico) y doble conteo. Escanear producto + ingresar cantidad contada. Optimizado para velocidad.

3. **Picking para Despacho:** Lista de items a recoger con ubicacion sugerida. Escanear para confirmar cada item. Estado visual de progreso.

4. **Transferencias entre Bodegas:** Seleccionar bodega origen/destino, escanear productos, confirmar cantidades, enviar.

5. **Consulta de Stock/Ubicacion:** Escanear barcode -> ver stock por bodega, ubicacion, lote, fecha vencimiento, ultimo movimiento.

**Interaccion principal: Escaneo de codigo de barras** usando `mobile_scanner` (camara del dispositivo) o lector USB/Bluetooth. Cada escaneo identifica producto + presentacion y rellena automaticamente los campos.

## Modelo de Datos SQL

```sql
-- ============================================================
-- COLA DE OPERACIONES OFFLINE (SQLite local en Flutter)
-- No es tabla de PostgreSQL, sino modelo Brick local
-- ============================================================
-- brick_offline_first_with_supabase ya maneja la cola de sync.
-- Las tablas siguientes son auxiliares para la app movil:

-- Sesiones de bodeguero (rastrear actividad)
CREATE TABLE bodeguero_sesiones (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  usuario_id      UUID NOT NULL REFERENCES auth.users(id),
  bodega_id       UUID NOT NULL REFERENCES bodegas(id),
  dispositivo     VARCHAR(100),                            -- 'Samsung Tab A8', 'Zebra TC21'
  ip_local        VARCHAR(45),
  inicio          TIMESTAMPTZ DEFAULT NOW(),
  fin             TIMESTAMPTZ,
  operaciones_realizadas INTEGER DEFAULT 0,
  version         INTEGER DEFAULT 1,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE bodeguero_sesiones ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON bodeguero_sesiones
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- Log de escaneos (para auditoria y analytics)
CREATE TABLE bodeguero_log_escaneos (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  sesion_id       UUID REFERENCES bodeguero_sesiones(id),
  usuario_id      UUID NOT NULL REFERENCES auth.users(id),
  operacion       VARCHAR(30) NOT NULL,                    -- 'RECEPCION', 'CONTEO', 'PICKING', 'TRANSFERENCIA', 'CONSULTA'
  barcode         VARCHAR(50) NOT NULL,
  producto_id     UUID REFERENCES productos(id),
  presentacion_id UUID REFERENCES producto_presentaciones(id),
  cantidad        DECIMAL(18,6),
  bodega_id       UUID REFERENCES bodegas(id),
  resultado       VARCHAR(20) DEFAULT 'OK',                -- 'OK', 'ERROR', 'NO_ENCONTRADO'
  error_mensaje   TEXT,
  timestamp_local TIMESTAMPTZ NOT NULL,                    -- Hora del dispositivo (offline)
  timestamp_sync  TIMESTAMPTZ,                             -- Hora de sincronizacion
  version         INTEGER DEFAULT 1,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE bodeguero_log_escaneos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON bodeguero_log_escaneos
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE INDEX idx_bodeguero_log_sesion ON bodeguero_log_escaneos(sesion_id, timestamp_local);
CREATE INDEX idx_bodeguero_log_operacion ON bodeguero_log_escaneos(empresa_id, operacion, created_at);

-- ============================================================
-- RECEPCION DE MERCADERIA (vinculada a OC)
-- ============================================================

CREATE TABLE recepciones_mercaderia (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  numero          SERIAL NOT NULL,
  orden_compra_id UUID,                                    -- FK a ordenes_compra (NULL si recepcion sin OC)
  bodega_id       UUID NOT NULL REFERENCES bodegas(id),
  proveedor_id    UUID REFERENCES contactos(id),
  estado          VARCHAR(20) NOT NULL DEFAULT 'BORRADOR',
    -- BORRADOR, EN_PROCESO, COMPLETADA, CON_DISCREPANCIA
  fecha_recepcion TIMESTAMPTZ DEFAULT NOW(),
  responsable_id  UUID NOT NULL REFERENCES auth.users(id),
  notas           TEXT,
  -- Discrepancias
  tiene_discrepancia BOOLEAN DEFAULT false,
  version         INTEGER DEFAULT 1,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE recepcion_mercaderia_lineas (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recepcion_id    UUID NOT NULL REFERENCES recepciones_mercaderia(id) ON DELETE CASCADE,
  producto_id     UUID NOT NULL REFERENCES productos(id),
  presentacion_id UUID REFERENCES producto_presentaciones(id),
  lote_id         UUID REFERENCES series_lotes(id),
  -- Cantidades
  cantidad_esperada DECIMAL(18,6),                         -- De la OC (NULL si sin OC)
  cantidad_recibida DECIMAL(18,6) NOT NULL,
  cantidad_rechazada DECIMAL(18,6) DEFAULT 0,
  -- Ubicacion destino
  ubicacion_id    UUID REFERENCES bodega_ubicaciones(id),
  -- Costo
  costo_unitario  DECIMAL(18,6),
  -- QC
  requiere_qc     BOOLEAN DEFAULT false,
  qc_inspeccion_id UUID REFERENCES qc_inspecciones(id),
  -- Escaneo
  barcode_escaneado VARCHAR(50),
  timestamp_escaneo TIMESTAMPTZ
);

ALTER TABLE recepciones_mercaderia ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON recepciones_mercaderia
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

ALTER TABLE recepcion_mercaderia_lineas ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON recepcion_mercaderia_lineas
  FOR ALL TO authenticated
  USING (recepcion_id IN (
    SELECT id FROM recepciones_mercaderia WHERE empresa_id = (SELECT private.get_empresa_id())
  ));
```

## Funciones PostgreSQL

```sql
-- ============================================================
-- RESOLVER BARCODE -> PRODUCTO + PRESENTACION
-- Reutilizable en todas las pantallas del bodeguero
-- ============================================================

CREATE OR REPLACE FUNCTION resolve_barcode(
  p_empresa_id UUID,
  p_barcode VARCHAR(50)
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER STABLE AS $$
DECLARE
  v_result JSONB;
  v_codigo RECORD;
  v_producto RECORD;
  v_peso DECIMAL;
BEGIN
  -- 1. Buscar en tabla de codigos de barras
  SELECT pcb.*, pp.factor_conversion, pp.nombre AS presentacion_nombre
  INTO v_codigo
  FROM producto_codigos_barras pcb
  LEFT JOIN producto_presentaciones pp ON pp.id = pcb.presentacion_id
  WHERE pcb.empresa_id = p_empresa_id AND pcb.codigo = p_barcode AND pcb.activo = true
  LIMIT 1;

  IF v_codigo IS NOT NULL THEN
    SELECT * INTO v_producto FROM productos WHERE id = v_codigo.producto_id;
    RETURN jsonb_build_object(
      'found', true,
      'producto_id', v_producto.id,
      'producto_nombre', v_producto.nombre,
      'sku', v_producto.sku,
      'presentacion_id', v_codigo.presentacion_id,
      'presentacion_nombre', v_codigo.presentacion_nombre,
      'factor_conversion', COALESCE(v_codigo.factor_conversion, 1),
      'tipo', 'BARCODE',
      'control_lote', v_producto.control_lote,
      'control_serial', v_producto.control_serial,
      'peso_variable', v_producto.peso_variable
    );
  END IF;

  -- 2. Verificar si es codigo EAN-13 con peso variable (prefijo 2x)
  IF LENGTH(p_barcode) = 13 AND LEFT(p_barcode, 1) = '2' THEN
    -- Formato: 2PPPPPWWWWWC (P=producto, W=peso en gramos)
    SELECT * INTO v_producto
    FROM productos
    WHERE empresa_id = p_empresa_id
      AND codigo_interno = SUBSTRING(p_barcode, 2, 5)
      AND peso_variable = true;

    IF v_producto IS NOT NULL THEN
      v_peso := SUBSTRING(p_barcode, 7, 5)::DECIMAL / 1000;  -- gramos a kg
      RETURN jsonb_build_object(
        'found', true,
        'producto_id', v_producto.id,
        'producto_nombre', v_producto.nombre,
        'tipo', 'PESO_VARIABLE',
        'peso_kg', v_peso,
        'precio_calculado', ROUND(v_peso * COALESCE(v_producto.precio_por_kg, 0), 2),
        'control_lote', false,
        'control_serial', false,
        'peso_variable', true
      );
    END IF;
  END IF;

  -- 3. Buscar por SKU
  SELECT * INTO v_producto
  FROM productos
  WHERE empresa_id = p_empresa_id AND sku = p_barcode AND activo = true;

  IF v_producto IS NOT NULL THEN
    RETURN jsonb_build_object(
      'found', true,
      'producto_id', v_producto.id,
      'producto_nombre', v_producto.nombre,
      'sku', v_producto.sku,
      'tipo', 'SKU',
      'control_lote', v_producto.control_lote,
      'control_serial', v_producto.control_serial
    );
  END IF;

  -- No encontrado
  RETURN jsonb_build_object('found', false, 'barcode', p_barcode);
END;
$$;

-- ============================================================
-- CONFIRMAR RECEPCION DE MERCADERIA
-- ============================================================

CREATE OR REPLACE FUNCTION confirm_reception(
  p_recepcion_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_recepcion RECORD;
  v_linea RECORD;
  v_items JSONB := '[]'::JSONB;
  v_discrepancias INTEGER := 0;
  v_kardex_ids UUID[];
BEGIN
  SELECT * INTO v_recepcion
  FROM recepciones_mercaderia WHERE id = p_recepcion_id;

  IF v_recepcion IS NULL THEN RAISE EXCEPTION 'Recepcion no encontrada'; END IF;
  IF v_recepcion.estado != 'BORRADOR' AND v_recepcion.estado != 'EN_PROCESO' THEN
    RAISE EXCEPTION 'Recepcion ya procesada';
  END IF;

  -- Procesar lineas
  FOR v_linea IN
    SELECT * FROM recepcion_mercaderia_lineas WHERE recepcion_id = p_recepcion_id
  LOOP
    IF v_linea.cantidad_recibida > 0 THEN
      v_items := v_items || jsonb_build_object(
        'producto_id', v_linea.producto_id,
        'cantidad', v_linea.cantidad_recibida,
        'costo_unitario', v_linea.costo_unitario
      );
    END IF;

    -- Detectar discrepancias vs OC
    IF v_linea.cantidad_esperada IS NOT NULL
       AND v_linea.cantidad_recibida != v_linea.cantidad_esperada THEN
      v_discrepancias := v_discrepancias + 1;
    END IF;

    -- Crear inspeccion QC si aplica
    IF v_linea.requiere_qc THEN
      UPDATE recepcion_mercaderia_lineas SET qc_inspeccion_id = qc_create_inspection(
        v_recepcion.empresa_id, v_linea.producto_id, 'RECEPCION',
        'RECEPCION_MERCADERIA', p_recepcion_id, v_linea.lote_id,
        v_recepcion.bodega_id, v_linea.cantidad_recibida, v_recepcion.proveedor_id
      ) WHERE id = v_linea.id;
    END IF;
  END LOOP;

  -- Crear movimientos de ingreso
  IF jsonb_array_length(v_items) > 0 THEN
    v_kardex_ids := create_inventory_movement(
      v_recepcion.empresa_id, v_recepcion.bodega_id, 'INGRESO', v_items
    );
  END IF;

  -- Actualizar estado
  UPDATE recepciones_mercaderia SET
    estado = CASE WHEN v_discrepancias > 0 THEN 'CON_DISCREPANCIA' ELSE 'COMPLETADA' END,
    tiene_discrepancia = v_discrepancias > 0,
    updated_at = NOW()
  WHERE id = p_recepcion_id;

  RETURN jsonb_build_object(
    'recepcion_id', p_recepcion_id,
    'lineas_procesadas', jsonb_array_length(v_items),
    'discrepancias', v_discrepancias,
    'estado', CASE WHEN v_discrepancias > 0 THEN 'CON_DISCREPANCIA' ELSE 'COMPLETADA' END,
    'kardex_ids', v_kardex_ids
  );
END;
$$;

-- ============================================================
-- CONFIRMAR PICKING (escaneo item por item)
-- ============================================================

CREATE OR REPLACE FUNCTION confirm_picking_line(
  p_linea_id UUID,
  p_cantidad_pickeada DECIMAL(18,6),
  p_barcode_escaneado VARCHAR(50) DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_linea RECORD;
  v_orden RECORD;
BEGIN
  SELECT opl.*, op.empresa_id, op.bodega_id, op.id AS orden_id
  INTO v_linea
  FROM orden_picking_lineas opl
  JOIN ordenes_picking op ON op.id = opl.orden_picking_id
  WHERE opl.id = p_linea_id;

  IF v_linea IS NULL THEN RAISE EXCEPTION 'Linea de picking no encontrada'; END IF;

  -- Validar barcode si fue escaneado
  IF p_barcode_escaneado IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM producto_codigos_barras
      WHERE producto_id = v_linea.producto_id
        AND codigo = p_barcode_escaneado
        AND empresa_id = v_linea.empresa_id
    ) AND NOT EXISTS (
      SELECT 1 FROM productos
      WHERE id = v_linea.producto_id AND sku = p_barcode_escaneado
    ) THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Barcode no corresponde al producto esperado'
      );
    END IF;
  END IF;

  -- Actualizar cantidad pickeada
  UPDATE orden_picking_lineas SET cantidad_pickeada = p_cantidad_pickeada
  WHERE id = p_linea_id;

  -- Verificar si toda la orden esta completa
  IF NOT EXISTS (
    SELECT 1 FROM orden_picking_lineas
    WHERE orden_picking_id = v_linea.orden_id
      AND cantidad_pickeada < cantidad_solicitada
  ) THEN
    UPDATE ordenes_picking SET estado = 'COMPLETADA', fecha_fin = NOW()
    WHERE id = v_linea.orden_id;
  ELSIF (SELECT estado FROM ordenes_picking WHERE id = v_linea.orden_id) = 'PENDIENTE' THEN
    UPDATE ordenes_picking SET estado = 'EN_PROCESO', fecha_inicio = NOW()
    WHERE id = v_linea.orden_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'linea_id', p_linea_id,
    'cantidad_pickeada', p_cantidad_pickeada,
    'cantidad_solicitada', v_linea.cantidad_solicitada,
    'completa', p_cantidad_pickeada >= v_linea.cantidad_solicitada
  );
END;
$$;

-- ============================================================
-- CONSULTA RAPIDA DE STOCK POR BARCODE
-- ============================================================

CREATE OR REPLACE FUNCTION quick_stock_lookup(
  p_empresa_id UUID,
  p_barcode VARCHAR(50)
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER STABLE AS $$
DECLARE
  v_producto JSONB;
  v_stock JSONB;
BEGIN
  -- Resolver barcode
  v_producto := resolve_barcode(p_empresa_id, p_barcode);
  IF NOT (v_producto->>'found')::BOOLEAN THEN
    RETURN v_producto;
  END IF;

  -- Obtener stock por bodega
  SELECT jsonb_agg(jsonb_build_object(
    'bodega_id', b.id,
    'bodega_nombre', b.nombre,
    'cantidad', COALESCE(ist.cantidad, 0),
    'ubicacion', bu.nombre,
    'lotes', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'numero', sl.numero,
        'cantidad', sl.cantidad,
        'vencimiento', sl.fecha_vencimiento,
        'estado', sl.estado
      )), '[]'::JSONB)
      FROM series_lotes sl
      WHERE sl.producto_id = (v_producto->>'producto_id')::UUID
        AND sl.bodega_id = b.id
        AND sl.estado IN ('DISPONIBLE', 'RESERVADO')
    )
  ))
  INTO v_stock
  FROM bodegas b
  LEFT JOIN inventario_stock ist ON ist.bodega_id = b.id
    AND ist.producto_id = (v_producto->>'producto_id')::UUID
  LEFT JOIN bodega_ubicaciones bu ON bu.id = ist.ubicacion_id
  WHERE b.empresa_id = p_empresa_id AND b.activo = true
    AND COALESCE(ist.cantidad, 0) != 0;

  RETURN v_producto || jsonb_build_object(
    'stock', COALESCE(v_stock, '[]'::JSONB),
    'stock_total', (
      SELECT COALESCE(SUM(cantidad), 0) FROM inventario_stock
      WHERE empresa_id = p_empresa_id
        AND producto_id = (v_producto->>'producto_id')::UUID
    ),
    'ultimo_movimiento', (
      SELECT jsonb_build_object('fecha', fecha, 'tipo', tipo_movimiento, 'cantidad', cantidad)
      FROM kardex
      WHERE producto_id = (v_producto->>'producto_id')::UUID
        AND empresa_id = p_empresa_id
      ORDER BY fecha DESC LIMIT 1
    )
  );
END;
$$;
```

## Triggers

```sql
-- Trigger: registrar log de escaneo automaticamente
-- (Se implementa en Flutter, no como trigger SQL, porque el log
--  se genera localmente y se sincroniza via brick_offline_first)

-- Trigger: al completar recepcion, actualizar estado de OC
CREATE OR REPLACE FUNCTION trg_reception_update_oc()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.estado IN ('COMPLETADA', 'CON_DISCREPANCIA') AND NEW.orden_compra_id IS NOT NULL THEN
    -- Verificar si toda la OC fue recibida
    -- (Simplificado: marcar OC como RECIBIDA si existe recepcion completa)
    UPDATE ordenes_compra SET estado = 'RECIBIDA'
    WHERE id = NEW.orden_compra_id
      AND NOT EXISTS (
        SELECT 1 FROM recepcion_mercaderia_lineas rml
        JOIN recepciones_mercaderia rm ON rm.id = rml.recepcion_id
        WHERE rm.orden_compra_id = NEW.orden_compra_id
          AND rm.estado != 'COMPLETADA'
      );
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_reception_oc_status
  AFTER UPDATE OF estado ON recepciones_mercaderia
  FOR EACH ROW EXECUTE FUNCTION trg_reception_update_oc();
```

## Vistas

```sql
-- Vista: Productividad del bodeguero
CREATE OR REPLACE VIEW v_bodeguero_productividad AS
SELECT
  bs.empresa_id,
  bs.usuario_id,
  u.email AS usuario_email,
  b.nombre AS bodega_nombre,
  DATE(bs.inicio) AS fecha,
  COUNT(*) AS sesiones,
  SUM(bs.operaciones_realizadas) AS total_operaciones,
  SUM(EXTRACT(EPOCH FROM COALESCE(bs.fin, NOW()) - bs.inicio) / 3600) AS horas_trabajadas,
  (SELECT COUNT(*) FROM bodeguero_log_escaneos ble
   WHERE ble.sesion_id = bs.id AND ble.resultado = 'OK') AS escaneos_exitosos,
  (SELECT COUNT(*) FROM bodeguero_log_escaneos ble
   WHERE ble.sesion_id = bs.id AND ble.resultado = 'ERROR') AS escaneos_error
FROM bodeguero_sesiones bs
JOIN auth.users u ON u.id = bs.usuario_id
JOIN bodegas b ON b.id = bs.bodega_id
GROUP BY bs.empresa_id, bs.usuario_id, u.email, b.nombre, DATE(bs.inicio), bs.id;

-- Vista: Recepciones pendientes (OC sin recibir)
CREATE OR REPLACE VIEW v_recepciones_pendientes AS
SELECT
  oc.empresa_id,
  oc.id AS orden_compra_id,
  oc.numero AS oc_numero,
  c.nombre AS proveedor_nombre,
  oc.fecha_esperada,
  oc.estado,
  (SELECT COUNT(*) FROM recepcion_mercaderia_lineas rml
   JOIN recepciones_mercaderia rm ON rm.id = rml.recepcion_id
   WHERE rm.orden_compra_id = oc.id) AS lineas_recibidas,
  EXTRACT(DAY FROM NOW() - oc.fecha_esperada) AS dias_retraso
FROM ordenes_compra oc
LEFT JOIN contactos c ON c.id = oc.proveedor_id
WHERE oc.estado IN ('CONFIRMADA', 'PARCIAL');
```

## Integracion Module Service Bus

```sql
-- BUS: Resolver barcode (desde POS, Ventas, o cualquier modulo)
CREATE OR REPLACE FUNCTION module_bus.resolve_barcode(
  p_empresa_id UUID,
  p_barcode VARCHAR(50)
) RETURNS module_bus.bus_response
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_result module_bus.bus_response;
  v_producto JSONB;
BEGIN
  IF NOT module_bus.is_module_active(p_empresa_id, 'inventario') THEN
    v_result := (false, 'module_inactive', 'inventario', null);
    RETURN v_result;
  END IF;

  v_producto := resolve_barcode(p_empresa_id, p_barcode);
  v_result := (true, null, 'inventario', v_producto);
  RETURN v_result;
END;
$$;
```

## RLS Policies

```sql
-- Ya definidas inline en 23.6.2
```

## Flujo UI/UX

```
============================================================
NAVEGACION PRINCIPAL - App Movil Bodeguero
============================================================

[Bottom Navigation Bar - 5 items max]
  [Recibir] [Contar] [Despachar] [Transferir] [Consultar]

Cada pantalla sigue el patron:
  1. Escanear barcode (camara o lector externo)
  2. Ver informacion del producto (card grande)
  3. Ingresar cantidad (numpad grande)
  4. Confirmar (boton prominente)

============================================================
PANTALLA 1: RECEPCION DE MERCADERIA
============================================================

[Header]
  Bodega: [dropdown] | OC: [selector con buscador] (opcional)

[Area de escaneo]
  [Boton grande: ESCANEAR] o campo de texto para barcode manual

[Card Producto Escaneado]
  Imagen | Nombre | SKU | Barcode
  OC esperado: 100 u | Ya recibido: 0 u
  [Input: Cantidad recibida] [Numpad grande]
  [Input: Lote] (si control_lote=true)
  [Input: Serie] (si control_serial=true)
  [Ubicacion destino: dropdown o escanear ubicacion]
  [Boton: AGREGAR A RECEPCION]

[Lista items recibidos] (scroll abajo)
  Producto | Qty esperada | Qty recibida | Discrepancia
  [Deslizar izquierda para eliminar]

[Barra inferior sticky]
  Items: N | Total unidades: XXX
  [CONFIRMAR RECEPCION]

============================================================
PANTALLA 2: CONTEO FISICO
============================================================

[Header]
  Inventario: #NNN | Bodega: XXX | Modo: [Ciego/Normal]

[Area de escaneo]
  [Boton: ESCANEAR]

[Card Producto]
  Imagen | Nombre | SKU
  Stock teorico: [OCULTO si conteo ciego] | 123 u [si modo normal]
  [Input: Cantidad contada] [Numpad GRANDE]
  [Boton: CONFIRMAR CONTEO]

[Progreso]
  Barra de progreso: 45/120 productos contados
  [Lista productos pendientes] (colapsable)

[Indicadores de discrepancia]
  Verde: coincide | Amarillo: diferencia < 5% | Rojo: diferencia > 5%

============================================================
PANTALLA 3: PICKING PARA DESPACHO
============================================================

[Header]
  Orden Picking: #NNN | Cliente: XXX | Items: N

[Lista de items a recoger] (cards grandes)
  Card por item:
    [Indicador: Pendiente / Pickeado]
    Producto: XXXXX
    Ubicacion: Zona A > Pasillo 3 > Estante B2 [con flecha/mapa]
    Cantidad: 5 u
    Lote sugerido: LOT-2025-001 (FEFO)
    [Boton: ESCANEAR PARA CONFIRMAR]

    Al escanear:
      - Si barcode correcto: marca como pickeado (animacion check verde)
      - Si barcode incorrecto: vibracion + mensaje rojo "Producto incorrecto"

[Barra inferior]
  Progreso: 3/8 items | [COMPLETAR PICKING]

============================================================
PANTALLA 4: TRANSFERENCIAS
============================================================

[Header]
  Desde: [dropdown bodega origen]
  Hacia: [dropdown bodega destino]

[Area de escaneo + lista]
  Similar a Recepcion pero sin OC de referencia

[Barra inferior]
  [ENVIAR TRANSFERENCIA]

============================================================
PANTALLA 5: CONSULTA STOCK
============================================================

[Area de escaneo]
  [Boton: ESCANEAR] o busqueda por texto

[Card Resultado]
  Producto: XXXXX | SKU: XXX
  Stock total: 150 u

  [Tabla por bodega]:
    Bodega | Ubicacion | Qty | Lote | Vencimiento
    Bodega A | A-3-B2 | 80 | LOT-001 | 2026-06-15
    Bodega B | B-1-A1 | 70 | LOT-002 | 2026-08-30

  Ultimo movimiento: Egreso 5u hace 2 horas
  [Boton: Ver Kardex completo]

============================================================
CONSIDERACIONES OFFLINE
============================================================

[Indicador de conectividad]
  Barra superior: [Verde: Online] [Amarillo: Sincronizando] [Rojo: Offline]

[Cola de sincronizacion]
  Badge en esquina: "3 operaciones pendientes de sync"
  Tap para ver detalle: lista de operaciones en cola

[Almacenamiento local]
  - Catalogo de productos + barcodes: SQLite via Brick
  - Stock por bodega: cache local actualizado via Realtime
  - Operaciones: cola local, sync al reconectar
  - Imagenes de productos: cache LRU local

[Conflictos]
  - Stock: SUMA DELTA (cada operacion es un delta +/-)
  - Recepciones: append-only (no hay conflicto)
  - Conteo fisico: ultima escritura gana (por producto+bodega)

[Responsive]
  COMPACT (movil): Pantallas full-screen, numpad grande, una columna
  MEDIUM (tablet 8-10"): Dos columnas (lista + detalle), numpad lateral
  EXPANDED (tablet 12"+): Tres columnas, mas informacion visible
```


