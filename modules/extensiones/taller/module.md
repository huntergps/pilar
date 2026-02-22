# Módulo de Taller

Taller de reparación físico standalone. Gestiona la recepción, diagnóstico, cotización, ejecución y entrega de equipos para reparación, tanto de clientes externos como de la propia empresa. No requiere que los módulos Ventas, Compras ni Garantías/RMA estén activos.

**Integraciones opcionales:**
- Si el módulo **Inventario** está activo: consume materiales con movimiento de kardex automático, controla stock de bodegas de taller y suministros.
- Si el módulo **Ventas** está activo: genera cotizaciones/proformas y facturas al entregar equipos reparados.
- Si el módulo **Garantías/RMA** está activo: las órdenes pueden originarse desde una solicitud RMA (`tipo_origen = 'RMA'`). El módulo Taller no conoce la lógica de garantías; simplemente acepta la orden y la ejecuta.
- Si el módulo **Activos Fijos** está activo: las herramientas de taller se vinculan a `activos_fijos` para depreciación y mantenimiento.
- Si el módulo **RRHH** está activo: las tarifas de mano de obra de técnicos pueden sincronizarse con sus contratos.

**Diferencia con Servicios/Contratos:**
- `ordenes_trabajo_servicio` (módulo Servicios/Contratos) son para servicios recurrentes de campo: instalación de TV cable, corte, reinstalación, mantenimiento de infraestructura de red.
- `ordenes_reparacion` (este módulo) son para reparación física de equipos/productos en taller: electrónicos, electrodomésticos, vehículos, maquinaria. Incluyen diagnóstico, cotización, consumo de materiales, mano de obra detallada y trazabilidad completa.

---

## Navegación

```
taller/
  ├── dashboard/              # KPIs: órdenes activas, SLA, técnicos, stock suministros
  ├── reparacion/
  │     ├── listado/          # SfDataGrid con filtros (estado, técnico, prioridad, fecha)
  │     ├── ingreso/          # Recepción equipo: descripción + fotos/video + firma cliente
  │     ├── diagnostico/      # Evaluación técnica: diagnóstico + decisión
  │     ├── cotizacion/       # Generar proforma (materiales + mano obra + revisión)
  │     ├── ejecucion/        # Registrar materiales consumidos + tiempo + etapas
  │     └── entrega/          # Entrega equipo: fotos + firma cliente + facturación
  ├── suministros/
  │     ├── stock-taller/     # Stock por bodega taller (filtrado por tipo_bodega)
  │     ├── transferencias/   # Centro acopio (SUMINISTROS_TALLER) → talleres individuales
  │     └── autoconsumo/      # Bodega VENTAS → bodega TALLER (transferencia manual)
  ├── herramientas/
  │     └── asignacion/       # Asignar/devolver herramientas a técnicos
  ├── config/
  │     ├── bodegas/          # Asignar bodegas TALLER y SUMINISTROS_TALLER
  │     ├── tarifas/          # Tarifas mano de obra (base, senior), overhead, revisión
  │     ├── cuentas/          # Cuentas contables del taller
  │     └── plantillas/       # BoM de reparación (materiales + tiempo sugerido)
  └── reportes/
        ├── consumo-taller/   # Consumo materiales por taller/período
        ├── rentabilidad/     # Margen por tipo de reparación
        ├── productividad/    # Órdenes/tiempo/calidad por técnico
        └── sla/              # Cumplimiento tiempo prometido vs real
```

---

## Modelo de Datos

### Bodegas de Taller (extensión de bodegas)

```sql
-- Campo adicional en tabla bodegas (Core Inventario):
-- tipo_bodega VARCHAR(20) DEFAULT 'VENTAS'
--   VENTAS:             bodega de productos para venta (por defecto)
--   GARANTIAS:          bodega de equipos devueltos por garantía (módulo Garantías/RMA)
--   TALLER:             bodega de repuestos/consumibles asignada a un taller específico
--   SUMINISTROS_TALLER: bodega central de suministros/insumos (centro de acopio)
--
-- FLUJO BODEGAS TALLER:
--   Compra insumos → SUMINISTROS_TALLER (centro acopio)
--     → transferencia → TALLER (bodega taller por sucursal)
--     → consumo en orden de reparación (kardex EGRESO)
--
--   Autoconsumo (cuando el repuesto viene de stock de venta):
--     VENTAS → TALLER (transferencia manual) → consumo en orden
```

### Órdenes de Reparación

```sql
ordenes_reparacion
  id                      UUID PK DEFAULT gen_random_uuid()
  empresa_id              UUID NOT NULL REFERENCES empresas(id)
  establecimiento_id      UUID REFERENCES establecimientos(id)
  numero_orden            VARCHAR(20) NOT NULL          -- REP-20260215-0001
  -- Origen de la orden
  tipo_origen             VARCHAR(20) NOT NULL
    -- EXTERNO:  cliente trae equipo para reparación/mantenimiento/revisión
    -- INTERNO:  equipo propio de la empresa (activo fijo, herramienta)
    -- RMA:      viene de una solicitud RMA (módulo Garantías/RMA, si está activo)
  rma_id                  UUID REFERENCES solicitudes_rma(id)    -- Solo si tipo_origen = 'RMA'
  -- Cliente
  contacto_id             UUID REFERENCES contactos(id)
  -- Equipo a reparar
  equipo_descripcion      TEXT NOT NULL                 -- "Samsung Galaxy S24, pantalla rota"
  equipo_marca            VARCHAR(100)
  equipo_modelo           VARCHAR(100)
  equipo_serie            VARCHAR(100)                  -- Número de serie del equipo físico
  producto_id             UUID REFERENCES productos(id) -- Producto del catálogo (si aplica)
  serie_lote_id           UUID REFERENCES series_lotes(id)
  -- Falla reportada y evidencia de ingreso
  sintoma_reportado       TEXT NOT NULL                 -- Lo que reporta el cliente
  evidencia_ingreso        JSONB DEFAULT '[]'            -- [{url, tipo: 'FOTO'|'VIDEO', descripcion}]
  firma_cliente_ingreso    TEXT NOT NULL                 -- URL firma digital del cliente al entregar
  -- Diagnóstico
  diagnostico             TEXT
  diagnosticado_por       UUID REFERENCES auth.users(id)
  fecha_diagnostico       TIMESTAMPTZ
  -- Garantía (informativo; si viene de RMA, el módulo Garantías/RMA gestiona esta lógica)
  es_garantia             BOOLEAN DEFAULT false
  garantia_cubre_total    BOOLEAN DEFAULT false          -- true = reparación gratis
  -- Cotización / Proforma (siempre se genera, incluso con monto $0)
  cobrar_revision         BOOLEAN DEFAULT false
  costo_revision          DECIMAL(14,2) DEFAULT 0
  cotizacion_id           UUID REFERENCES cotizaciones(id)
  cotizacion_aprobada     BOOLEAN                       -- NULL=pendiente, true/false
  aprobado_por            VARCHAR(50)                   -- 'CLIENTE' o 'GERENTE'
  -- Aprobación online (token para link enviado por WhatsApp/email)
  token_aprobacion        UUID DEFAULT gen_random_uuid()
  -- Asignación
  tecnico_id              UUID REFERENCES auth.users(id)
  bodega_taller_id        UUID REFERENCES bodegas(id)
  -- Tiempos
  fecha_ingreso           TIMESTAMPTZ DEFAULT now()
  fecha_inicio_reparacion TIMESTAMPTZ
  fecha_fin_reparacion    TIMESTAMPTZ
  fecha_entrega           TIMESTAMPTZ
  fecha_prometida         DATE
  tiempo_estimado_min     INTEGER
  -- Estado
  estado                  VARCHAR(20) DEFAULT 'RECIBIDO'
    -- RECIBIDO:        equipo ingresado al taller (firma cliente obligatoria)
    -- EN_DIAGNOSTICO:  técnico evaluando la falla
    -- COTIZADO:        proforma generada, esperando aprobación
    -- APROBADO:        cliente/gerente aprobó, despachos generados
    -- EN_REPARACION:   técnico trabajando
    -- REPARADO:        reparación terminada, pendiente entrega
    -- ENTREGADO:       equipo devuelto al cliente (firma cliente obligatoria)
    -- CANCELADO:       cliente canceló
    -- NO_REPARABLE:    sin solución técnica
  prioridad               VARCHAR(10) DEFAULT 'NORMAL'  -- URGENTE, ALTA, NORMAL, BAJA
  -- Costos (calculados desde líneas de materiales y mano de obra)
  costo_materiales        DECIMAL(14,2) DEFAULT 0
  costo_mano_obra         DECIMAL(14,2) DEFAULT 0
  costo_overhead          DECIMAL(14,2) DEFAULT 0       -- overhead_% * (materiales + mano_obra)
  costo_total             DECIMAL(14,2) DEFAULT 0
  precio_cobrado          DECIMAL(14,2) DEFAULT 0
  margen                  DECIMAL(14,2) DEFAULT 0       -- precio_cobrado - costo_total
  -- Facturación
  es_facturable           BOOLEAN DEFAULT true
  factura_id              UUID REFERENCES facturas(id)
  -- Garantía de la reparación realizada
  garantia_reparacion_dias INTEGER DEFAULT 30
  garantia_vence          DATE                          -- = fecha_entrega + garantia_reparacion_dias
  orden_original_id       UUID REFERENCES ordenes_reparacion(id) -- Si es reingreso por garantía
  -- Seguimiento online (link enviado al cliente)
  token_seguimiento       UUID DEFAULT gen_random_uuid()
  -- Evidencia de entrega
  evidencia_entrega        JSONB DEFAULT '[]'
  firma_cliente_entrega    TEXT
  -- Notas
  notas_internas          TEXT
  notas_cliente           TEXT
  created_at              TIMESTAMPTZ DEFAULT now()
  updated_at              TIMESTAMPTZ DEFAULT now()
  created_by              UUID REFERENCES auth.users(id)

  UNIQUE(empresa_id, numero_orden)
```

### Etapas y Trazabilidad

```sql
-- Historial de etapas con evidencia por usuario
reparacion_etapas
  id                  UUID PK DEFAULT gen_random_uuid()
  empresa_id          UUID NOT NULL REFERENCES empresas(id)
  orden_id            UUID NOT NULL REFERENCES ordenes_reparacion(id) ON DELETE CASCADE
  etapa               VARCHAR(20) NOT NULL    -- Mismo enum que ordenes_reparacion.estado
  descripcion         TEXT                    -- Qué se hizo en esta etapa
  tecnico_id          UUID REFERENCES auth.users(id)
  duracion_minutos    INTEGER
  evidencia            JSONB DEFAULT '[]'     -- Fotos/video de la etapa
  created_at          TIMESTAMPTZ DEFAULT now()
```

### Materiales y Mano de Obra

```sql
-- Materiales consumidos en reparación (con conversión UoM)
reparacion_materiales
  id                  UUID PK DEFAULT gen_random_uuid()
  empresa_id          UUID NOT NULL REFERENCES empresas(id)
  orden_id            UUID NOT NULL REFERENCES ordenes_reparacion(id) ON DELETE CASCADE
  producto_id         UUID NOT NULL REFERENCES productos(id)
  presentacion_id     UUID REFERENCES producto_presentaciones(id)
  -- Cantidades con conversión UoM
  cantidad            DECIMAL(18,6) NOT NULL  -- En UoM de consumo (ej: 15 ml)
  unidad_medida_id    UUID REFERENCES unidades_medida(id)
  cantidad_base       DECIMAL(18,6) NOT NULL  -- Convertida a UoM base del producto
  -- Costos al momento del consumo (desde kardex/valoración promedio ponderado)
  costo_unitario      DECIMAL(18,6) NOT NULL
  costo_total         DECIMAL(14,2) NOT NULL  -- cantidad_base * costo_unitario
  -- Cobro al cliente
  precio_cobro        DECIMAL(18,6) DEFAULT 0
  precio_cobro_total  DECIMAL(14,2) DEFAULT 0
  es_facturable       BOOLEAN DEFAULT true
  -- Origen del stock
  bodega_id           UUID REFERENCES bodegas(id)
  kardex_id           UUID REFERENCES kardex(id) -- Movimiento kardex generado (EGRESO)
  -- Tipo de consumo
  tipo_consumo        VARCHAR(20) DEFAULT 'REPUESTO'
    -- REPUESTO:    pieza de reemplazo (pantalla, batería, placa)
    -- CONSUMIBLE:  material bulk (soldadura, pegamento, tinta, pasta térmica)
    -- ACCESORIO:   complemento (cable, tornillo, conector)
  notas               TEXT
  created_at          TIMESTAMPTZ DEFAULT now()

-- Mano de obra registrada por técnico
reparacion_mano_obra
  id                  UUID PK DEFAULT gen_random_uuid()
  empresa_id          UUID NOT NULL REFERENCES empresas(id)
  orden_id            UUID NOT NULL REFERENCES ordenes_reparacion(id) ON DELETE CASCADE
  tecnico_id          UUID NOT NULL REFERENCES auth.users(id)
  -- Tiempo
  fecha               DATE NOT NULL
  hora_inicio         TIME
  hora_fin            TIME
  duracion_minutos    INTEGER NOT NULL
  -- Costos internos
  tarifa_hora         DECIMAL(14,2) NOT NULL   -- Tarifa del técnico (de config_taller)
  costo_total         DECIMAL(14,2) NOT NULL   -- (duracion_minutos / 60) * tarifa_hora
  -- Cobro al cliente
  precio_cobro_hora   DECIMAL(14,2) DEFAULT 0
  precio_cobro_total  DECIMAL(14,2) DEFAULT 0
  es_facturable       BOOLEAN DEFAULT true
  descripcion         VARCHAR(300)             -- "Desoldado IC de carga, reemplazo capacitor"
  etapa_id            UUID REFERENCES reparacion_etapas(id)
  created_at          TIMESTAMPTZ DEFAULT now()
```

### Plantillas de Reparación

```sql
-- BoM de reparación: materiales + tiempo estimado + precio sugerido
plantillas_reparacion
  id                  UUID PK DEFAULT gen_random_uuid()
  empresa_id          UUID NOT NULL REFERENCES empresas(id)
  nombre              VARCHAR(150) NOT NULL    -- "Cambio pantalla iPhone 15 Pro"
  descripcion         TEXT
  categoria_equipo    VARCHAR(100)             -- "Celulares", "Laptops", "Impresoras"
  tiempo_estimado_min INTEGER
  tarifa_mano_obra    DECIMAL(14,2)
  precio_sugerido     DECIMAL(14,2)
  activo              BOOLEAN DEFAULT true
  created_at          TIMESTAMPTZ DEFAULT now()

plantilla_reparacion_materiales
  id                  UUID PK DEFAULT gen_random_uuid()
  plantilla_id        UUID NOT NULL REFERENCES plantillas_reparacion(id) ON DELETE CASCADE
  producto_id         UUID NOT NULL REFERENCES productos(id)
  cantidad            DECIMAL(18,6) NOT NULL
  unidad_medida_id    UUID REFERENCES unidades_medida(id)
  es_opcional         BOOLEAN DEFAULT false
  notas               TEXT
```

### Herramientas de Taller

```sql
-- Herramientas durables del taller (activos físicos)
herramientas_taller
  id                  UUID PK DEFAULT gen_random_uuid()
  empresa_id          UUID NOT NULL REFERENCES empresas(id)
  establecimiento_id  UUID REFERENCES establecimientos(id)
  nombre              VARCHAR(150) NOT NULL    -- "Estación soldadura Hakko FX-951"
  codigo              VARCHAR(30)
  numero_serie        VARCHAR(100)
  categoria           VARCHAR(50)             -- "Soldadura", "Medición", "Desmontaje"
  estado              VARCHAR(20) DEFAULT 'DISPONIBLE'
    -- DISPONIBLE, EN_USO, EN_MANTENIMIENTO, DANADA, BAJA
  asignada_a          UUID REFERENCES auth.users(id)
  bodega_taller_id    UUID REFERENCES bodegas(id)
  fecha_adquisicion   DATE
  costo_adquisicion   DECIMAL(14,2)
  vida_util_meses     INTEGER
  proximo_mantenimiento DATE
  activo_fijo_id      UUID REFERENCES activos_fijos(id) -- Link para depreciación (módulo Activos Fijos)
  imagen_url          TEXT
  notas               TEXT
  created_at          TIMESTAMPTZ DEFAULT now()

-- Historial de movimientos de herramientas
herramienta_movimientos
  id                  UUID PK DEFAULT gen_random_uuid()
  empresa_id          UUID NOT NULL REFERENCES empresas(id)
  herramienta_id      UUID NOT NULL REFERENCES herramientas_taller(id)
  tipo                VARCHAR(20) NOT NULL
    -- ASIGNACION, DEVOLUCION, MANTENIMIENTO, BAJA
  tecnico_id          UUID REFERENCES auth.users(id)
  orden_reparacion_id UUID REFERENCES ordenes_reparacion(id)
  fecha               TIMESTAMPTZ DEFAULT now()
  notas               TEXT
  created_by          UUID REFERENCES auth.users(id)
```

### Configuración de Taller

```sql
-- Configuración por establecimiento
config_taller
  id                        UUID PK DEFAULT gen_random_uuid()
  empresa_id                UUID NOT NULL REFERENCES empresas(id)
  establecimiento_id        UUID NOT NULL REFERENCES establecimientos(id)
  -- Bodegas
  bodega_taller_id          UUID REFERENCES bodegas(id)          -- Repuestos/consumibles del taller
  bodega_suministros_id     UUID REFERENCES bodegas(id)          -- Centro de acopio de suministros
  -- Overhead y tarifas
  overhead_porcentaje       DECIMAL(5,2) DEFAULT 15.00           -- % sobre costos directos
  tarifa_hora_base          DECIMAL(14,2) DEFAULT 0              -- Tarifa técnico estándar
  tarifa_hora_senior        DECIMAL(14,2) DEFAULT 0              -- Tarifa técnico senior
  tarifa_revision           DECIMAL(14,2) DEFAULT 0              -- Costo diagnóstico (si se cobra)
  -- Cuentas contables
  cuenta_ingreso_reparacion UUID REFERENCES cuentas_contables(id)
  cuenta_costo_materiales   UUID REFERENCES cuentas_contables(id)
  cuenta_costo_mano_obra    UUID REFERENCES cuentas_contables(id)
  cuenta_overhead           UUID REFERENCES cuentas_contables(id)
  -- Numeración
  prefijo_reparacion        VARCHAR(10) DEFAULT 'REP'
  secuencia_reparacion      INTEGER DEFAULT 0

  UNIQUE(empresa_id, establecimiento_id)
```

### Índices

```sql
CREATE INDEX idx_ordenes_reparacion_estado     ON ordenes_reparacion(empresa_id, estado);
CREATE INDEX idx_ordenes_reparacion_tecnico    ON ordenes_reparacion(tecnico_id, fecha_ingreso);
CREATE INDEX idx_ordenes_reparacion_contacto   ON ordenes_reparacion(contacto_id);
CREATE INDEX idx_ordenes_reparacion_tipo       ON ordenes_reparacion(empresa_id, tipo_origen);
CREATE INDEX idx_reparacion_materiales_orden   ON reparacion_materiales(orden_id);
CREATE INDEX idx_reparacion_materiales_producto ON reparacion_materiales(producto_id);
CREATE INDEX idx_reparacion_mano_obra_orden    ON reparacion_mano_obra(orden_id);
CREATE INDEX idx_reparacion_mano_obra_tecnico  ON reparacion_mano_obra(tecnico_id);
CREATE INDEX idx_herramientas_estado           ON herramientas_taller(empresa_id, estado);
```

---

## RPCs Principales

```sql
-- ══════════════════════════════════════════════════════════════════
-- RPC: Crear orden de reparación
-- Origen: EXTERNO (cliente), INTERNO (equipo propio), RMA (desde módulo Garantías/RMA)
-- ══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION create_repair_order(
  p_empresa_id        UUID,
  p_establecimiento_id UUID,
  p_tipo_origen       VARCHAR(20),   -- 'EXTERNO' | 'INTERNO' | 'RMA'
  p_contacto_id       UUID,
  p_equipo_descripcion TEXT,
  p_sintoma_reportado TEXT,
  p_evidencia          JSONB DEFAULT '[]',
  p_firma_cliente     TEXT DEFAULT NULL,
  p_rma_id            UUID DEFAULT NULL,  -- Solo si tipo_origen = 'RMA'
  p_producto_id       UUID DEFAULT NULL,
  p_serie_lote_id     UUID DEFAULT NULL,
  p_equipo_marca      VARCHAR DEFAULT NULL,
  p_equipo_modelo     VARCHAR DEFAULT NULL,
  p_equipo_serie      VARCHAR DEFAULT NULL,
  p_es_garantia       BOOLEAN DEFAULT false,
  p_fecha_prometida   DATE DEFAULT NULL,
  p_prioridad         VARCHAR DEFAULT 'NORMAL'
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_orden_id UUID;
  v_numero   VARCHAR(20);
  v_config   config_taller%ROWTYPE;
BEGIN
  SELECT * INTO v_config FROM config_taller
  WHERE empresa_id = p_empresa_id AND establecimiento_id = p_establecimiento_id;

  IF v_config.id IS NULL THEN
    RAISE EXCEPTION 'Configuración de taller no encontrada para este establecimiento';
  END IF;

  v_numero := COALESCE(v_config.prefijo_reparacion, 'REP') || '-' ||
    to_char(CURRENT_DATE, 'YYYYMMDD') || '-' ||
    lpad((COALESCE(v_config.secuencia_reparacion, 0) + 1)::text, 4, '0');

  UPDATE config_taller
    SET secuencia_reparacion = COALESCE(secuencia_reparacion, 0) + 1
  WHERE id = v_config.id;

  INSERT INTO ordenes_reparacion (
    empresa_id, establecimiento_id, numero_orden,
    tipo_origen, rma_id, contacto_id,
    equipo_descripcion, equipo_marca, equipo_modelo, equipo_serie,
    producto_id, serie_lote_id,
    sintoma_reportado, evidencia_ingreso, firma_cliente_ingreso,
    es_garantia, bodega_taller_id,
    fecha_prometida, prioridad, estado
  ) VALUES (
    p_empresa_id, p_establecimiento_id, v_numero,
    p_tipo_origen, p_rma_id, p_contacto_id,
    p_equipo_descripcion, p_equipo_marca, p_equipo_modelo, p_equipo_serie,
    p_producto_id, p_serie_lote_id,
    p_sintoma_reportado, p_evidencia, p_firma_cliente,
    p_es_garantia, v_config.bodega_taller_id,
    p_fecha_prometida, p_prioridad, 'RECIBIDO'
  ) RETURNING id INTO v_orden_id;

  INSERT INTO reparacion_etapas (empresa_id, orden_id, etapa, descripcion, tecnico_id)
  VALUES (p_empresa_id, v_orden_id, 'RECIBIDO', 'Equipo ingresado al taller', auth.uid());

  RETURN v_orden_id;
END;
$$;

-- ══════════════════════════════════════════════════════════════════
-- RPC: Asignar técnico a una orden
-- ══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION assign_technician(
  p_orden_id   UUID,
  p_tecnico_id UUID
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE ordenes_reparacion SET
    tecnico_id = p_tecnico_id,
    estado     = CASE WHEN estado = 'RECIBIDO' THEN 'EN_DIAGNOSTICO' ELSE estado END,
    updated_at = now()
  WHERE id = p_orden_id
    AND empresa_id = (SELECT private.get_empresa_id());

  INSERT INTO reparacion_etapas (empresa_id, orden_id, etapa, descripcion, tecnico_id)
  SELECT empresa_id, id, 'EN_DIAGNOSTICO', 'Asignado a técnico', p_tecnico_id
  FROM ordenes_reparacion WHERE id = p_orden_id;
END;
$$;

-- ══════════════════════════════════════════════════════════════════
-- RPC: Registrar consumo de material en reparación
-- Crea kardex (EGRESO) + actualiza stock + registra en reparacion_materiales
-- ══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION register_material_consumption(
  p_empresa_id        UUID,
  p_orden_id          UUID,
  p_producto_id       UUID,
  p_cantidad          DECIMAL(18,6),
  p_unidad_medida_id  UUID,
  p_bodega_id         UUID,
  p_tipo_consumo      VARCHAR(20) DEFAULT 'REPUESTO',
  p_es_facturable     BOOLEAN DEFAULT true,
  p_precio_cobro      DECIMAL(18,6) DEFAULT 0,
  p_presentacion_id   UUID DEFAULT NULL,
  p_notas             TEXT DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_material_id      UUID;
  v_cantidad_base    DECIMAL(18,6);
  v_factor           DECIMAL(18,6);
  v_costo_unitario   DECIMAL(18,6);
  v_costo_total      DECIMAL(14,2);
  v_kardex_id        UUID;
BEGIN
  -- Convertir cantidad a UoM base del producto
  SELECT COALESCE(factor_conversion, 1) INTO v_factor
  FROM unidades_medida WHERE id = p_unidad_medida_id;
  v_cantidad_base := p_cantidad * v_factor;

  -- Costo promedio ponderado actual
  SELECT COALESCE(costo_promedio, 0) INTO v_costo_unitario
  FROM inventario_stock
  WHERE empresa_id = p_empresa_id AND producto_id = p_producto_id AND bodega_id = p_bodega_id;

  v_costo_total := ROUND(v_cantidad_base * v_costo_unitario, 2);

  -- Crear movimiento kardex (EGRESO por consumo taller)
  INSERT INTO kardex (
    empresa_id, producto_id, bodega_id,
    tipo_movimiento, cantidad, costo_unitario, costo_total,
    referencia_tipo, referencia_id, descripcion
  ) VALUES (
    p_empresa_id, p_producto_id, p_bodega_id,
    'EGRESO', v_cantidad_base, v_costo_unitario, v_costo_total,
    'REPARACION', p_orden_id,
    'Consumo en orden ' || (SELECT numero_orden FROM ordenes_reparacion WHERE id = p_orden_id)
  ) RETURNING id INTO v_kardex_id;

  -- Actualizar stock
  UPDATE inventario_stock
  SET cantidad = cantidad - v_cantidad_base, updated_at = now()
  WHERE empresa_id = p_empresa_id AND producto_id = p_producto_id AND bodega_id = p_bodega_id;

  -- Registrar material
  INSERT INTO reparacion_materiales (
    empresa_id, orden_id, producto_id, presentacion_id,
    cantidad, unidad_medida_id, cantidad_base,
    costo_unitario, costo_total,
    precio_cobro, precio_cobro_total, es_facturable,
    bodega_id, kardex_id, tipo_consumo, notas
  ) VALUES (
    p_empresa_id, p_orden_id, p_producto_id, p_presentacion_id,
    p_cantidad, p_unidad_medida_id, v_cantidad_base,
    v_costo_unitario, v_costo_total,
    p_precio_cobro, ROUND(p_cantidad * p_precio_cobro, 2), p_es_facturable,
    p_bodega_id, v_kardex_id, p_tipo_consumo, p_notas
  ) RETURNING id INTO v_material_id;

  -- Recalcular costos totales de la orden
  PERFORM _recalculate_repair_costs(p_orden_id);

  RETURN v_material_id;
END;
$$;

-- ══════════════════════════════════════════════════════════════════
-- RPC auxiliar: Recalcular costos de una orden
-- ══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION _recalculate_repair_costs(p_orden_id UUID)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE
  v_materiales    DECIMAL(14,2);
  v_mano_obra     DECIMAL(14,2);
  v_overhead_pct  DECIMAL(5,2);
  v_overhead      DECIMAL(14,2);
  v_total         DECIMAL(14,2);
  v_precio        DECIMAL(14,2);
BEGIN
  SELECT COALESCE(SUM(costo_total), 0) INTO v_materiales
  FROM reparacion_materiales WHERE orden_id = p_orden_id;

  SELECT COALESCE(SUM(costo_total), 0) INTO v_mano_obra
  FROM reparacion_mano_obra WHERE orden_id = p_orden_id;

  SELECT COALESCE(ct.overhead_porcentaje, 0) INTO v_overhead_pct
  FROM ordenes_reparacion r
  JOIN config_taller ct
    ON ct.empresa_id = r.empresa_id AND ct.establecimiento_id = r.establecimiento_id
  WHERE r.id = p_orden_id;

  v_overhead := ROUND((v_materiales + v_mano_obra) * v_overhead_pct / 100, 2);
  v_total    := v_materiales + v_mano_obra + v_overhead;

  SELECT COALESCE(precio_cobrado, 0) INTO v_precio
  FROM ordenes_reparacion WHERE id = p_orden_id;

  UPDATE ordenes_reparacion SET
    costo_materiales = v_materiales,
    costo_mano_obra  = v_mano_obra,
    costo_overhead   = v_overhead,
    costo_total      = v_total,
    margen           = v_precio - v_total,
    updated_at       = now()
  WHERE id = p_orden_id;
END;
$$;

-- ══════════════════════════════════════════════════════════════════
-- RPC: Generar proforma/cotización desde orden de reparación
-- Incluye materiales facturables + mano de obra + revisión (si aplica)
-- ══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION generate_repair_quotation(
  p_orden_id UUID
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_orden          ordenes_reparacion%ROWTYPE;
  v_cotizacion_id  UUID;
  v_lineas         JSONB := '[]'::JSONB;
BEGIN
  SELECT * INTO v_orden FROM ordenes_reparacion WHERE id = p_orden_id;
  IF v_orden.id IS NULL THEN RAISE EXCEPTION 'Orden no encontrada'; END IF;

  -- Materiales facturables
  SELECT jsonb_agg(jsonb_build_object(
    'producto_id',     rm.producto_id,
    'descripcion',     p.nombre || ' (' || rm.tipo_consumo || ')',
    'cantidad',        rm.cantidad,
    'precio_unitario', rm.precio_cobro,
    'unidad_medida_id', rm.unidad_medida_id
  )) INTO v_lineas
  FROM reparacion_materiales rm
  JOIN productos p ON p.id = rm.producto_id
  WHERE rm.orden_id = p_orden_id AND rm.es_facturable = true;

  -- Costo de revisión si aplica
  IF v_orden.cobrar_revision AND v_orden.costo_revision > 0 THEN
    v_lineas := COALESCE(v_lineas, '[]'::JSONB) || jsonb_build_array(jsonb_build_object(
      'descripcion',     'Revisión/Diagnóstico técnico',
      'cantidad',        1,
      'precio_unitario', v_orden.costo_revision
    ));
  END IF;

  -- Crear cotización usando RPC del módulo Ventas
  v_cotizacion_id := create_quotation(
    v_orden.empresa_id,
    v_orden.contacto_id,
    COALESCE(v_lineas, '[]'::JSONB),
    'Reparación: ' || v_orden.numero_orden || ' — ' || v_orden.equipo_descripcion
  );

  UPDATE ordenes_reparacion SET
    cotizacion_id = v_cotizacion_id,
    estado        = 'COTIZADO',
    updated_at    = now()
  WHERE id = p_orden_id;

  INSERT INTO reparacion_etapas (empresa_id, orden_id, etapa, descripcion, tecnico_id)
  SELECT empresa_id, id, 'COTIZADO', 'Proforma generada y enviada al cliente', auth.uid()
  FROM ordenes_reparacion WHERE id = p_orden_id;

  RETURN v_cotizacion_id;
END;
$$;

-- ══════════════════════════════════════════════════════════════════
-- RPC: Entregar equipo reparado al cliente
-- Actualiza estado, registra evidencia/firma, genera factura si aplica
-- ══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION deliver_repair_order(
  p_orden_id          UUID,
  p_evidencia_entrega  JSONB DEFAULT '[]',
  p_firma_cliente     TEXT DEFAULT NULL,
  p_generar_factura   BOOLEAN DEFAULT false
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_orden       ordenes_reparacion%ROWTYPE;
  v_factura_id  UUID;
BEGIN
  SELECT * INTO v_orden FROM ordenes_reparacion WHERE id = p_orden_id;

  IF v_orden.estado <> 'REPARADO' THEN
    RAISE EXCEPTION 'La orden debe estar en estado REPARADO para ser entregada';
  END IF;

  UPDATE ordenes_reparacion SET
    estado                   = 'ENTREGADO',
    fecha_entrega            = now(),
    evidencia_entrega         = p_evidencia_entrega,
    firma_cliente_entrega    = p_firma_cliente,
    garantia_vence           = (now()::date + garantia_reparacion_dias),
    updated_at               = now()
  WHERE id = p_orden_id;

  INSERT INTO reparacion_etapas (empresa_id, orden_id, etapa, descripcion, tecnico_id)
  SELECT empresa_id, id, 'ENTREGADO', 'Equipo entregado al cliente', auth.uid()
  FROM ordenes_reparacion WHERE id = p_orden_id;

  -- Generar factura si es facturable (llama a flujo de Ventas vía module_bus)
  IF p_generar_factura AND v_orden.es_facturable THEN
    v_factura_id := module_bus.ventas.create_invoice_from_repair(p_orden_id);
    UPDATE ordenes_reparacion SET factura_id = v_factura_id WHERE id = p_orden_id;
  END IF;

  RETURN v_factura_id;
END;
$$;

-- ══════════════════════════════════════════════════════════════════
-- RPC: Historial de reparaciones por número de serie de equipo
-- Útil para decidir si seguir reparando o recomendar reemplazo
-- ══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION get_equipment_repair_history(
  p_empresa_id UUID,
  p_serial     VARCHAR
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_reparaciones JSONB;
  v_count        INTEGER;
  v_costo_total  DECIMAL(14,2);
  v_ultima       DATE;
BEGIN
  SELECT
    jsonb_agg(jsonb_build_object(
      'orden_id',      r.id,
      'numero_orden',  r.numero_orden,
      'fecha_ingreso', r.fecha_ingreso,
      'diagnostico',   r.diagnostico,
      'costo_total',   r.costo_total,
      'precio_cobrado',r.precio_cobrado,
      'estado',        r.estado,
      'garantia_vigente', COALESCE(r.garantia_vence >= CURRENT_DATE, false)
    ) ORDER BY r.fecha_ingreso DESC),
    COUNT(*),
    COALESCE(SUM(r.costo_total), 0),
    MAX(r.fecha_ingreso::date)
  INTO v_reparaciones, v_count, v_costo_total, v_ultima
  FROM ordenes_reparacion r
  WHERE r.empresa_id = p_empresa_id AND r.equipo_serie = p_serial;

  RETURN jsonb_build_object(
    'serial',               p_serial,
    'total_reparaciones',   v_count,
    'costo_acumulado',      v_costo_total,
    'ultima_reparacion',    v_ultima,
    'reparaciones',         COALESCE(v_reparaciones, '[]'::JSONB)
  );
END;
$$;

-- ══════════════════════════════════════════════════════════════════
-- RPC: Reporte de consumo de materiales por taller y período
-- ══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION report_workshop_consumption(
  p_empresa_id          UUID,
  p_establecimiento_id  UUID,
  p_fecha_desde         DATE,
  p_fecha_hasta         DATE
) RETURNS TABLE(
  producto_id       UUID,
  producto_nombre   VARCHAR,
  tipo_consumo      VARCHAR,
  cantidad_total    DECIMAL,
  unidad_medida     VARCHAR,
  costo_total       DECIMAL,
  ordenes_count     BIGINT
)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT
    rm.producto_id,
    p.nombre,
    rm.tipo_consumo,
    SUM(rm.cantidad_base),
    um.nombre,
    SUM(rm.costo_total),
    COUNT(DISTINCT rm.orden_id)
  FROM reparacion_materiales rm
  JOIN ordenes_reparacion r ON r.id = rm.orden_id
  JOIN productos p          ON p.id = rm.producto_id
  LEFT JOIN unidades_medida um ON um.id = p.uom_id
  WHERE rm.empresa_id = p_empresa_id
    AND r.establecimiento_id = p_establecimiento_id
    AND rm.created_at::date BETWEEN p_fecha_desde AND p_fecha_hasta
  GROUP BY rm.producto_id, p.nombre, rm.tipo_consumo, um.nombre
  ORDER BY SUM(rm.costo_total) DESC;
$$;
```

---

## RLS

```sql
ALTER TABLE ordenes_reparacion             ENABLE ROW LEVEL SECURITY;
ALTER TABLE reparacion_etapas              ENABLE ROW LEVEL SECURITY;
ALTER TABLE reparacion_materiales          ENABLE ROW LEVEL SECURITY;
ALTER TABLE reparacion_mano_obra           ENABLE ROW LEVEL SECURITY;
ALTER TABLE plantillas_reparacion          ENABLE ROW LEVEL SECURITY;
ALTER TABLE plantilla_reparacion_materiales ENABLE ROW LEVEL SECURITY;
ALTER TABLE herramientas_taller            ENABLE ROW LEVEL SECURITY;
ALTER TABLE herramienta_movimientos        ENABLE ROW LEVEL SECURITY;
ALTER TABLE config_taller                  ENABLE ROW LEVEL SECURITY;

CREATE POLICY "tenant_isolation" ON ordenes_reparacion
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE POLICY "tenant_isolation" ON reparacion_etapas
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE POLICY "tenant_isolation" ON reparacion_materiales
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE POLICY "tenant_isolation" ON reparacion_mano_obra
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE POLICY "tenant_isolation" ON plantillas_reparacion
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE POLICY "tenant_isolation" ON plantilla_reparacion_materiales
  FOR ALL TO authenticated
  USING (plantilla_id IN (
    SELECT id FROM plantillas_reparacion WHERE empresa_id = (SELECT private.get_empresa_id())
  ));

CREATE POLICY "tenant_isolation" ON herramientas_taller
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE POLICY "tenant_isolation" ON herramienta_movimientos
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE POLICY "tenant_isolation" ON config_taller
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));
```

---

## Integración Module Service Bus

El módulo Taller expone funciones gateway en `module_bus.taller.*` para que otros módulos puedan crear órdenes de reparación sin depender directamente de las tablas internas.

```sql
-- ══════════════════════════════════════════════════════════════════
-- TALLER como PROVEEDOR de servicios al Module Service Bus
-- ══════════════════════════════════════════════════════════════════

-- Gateway: crear orden desde un RMA (llamado por módulo Garantías/RMA)
CREATE OR REPLACE FUNCTION module_bus.taller.crear_orden_desde_rma(
  p_rma_id            UUID,
  p_empresa_id        UUID,
  p_establecimiento_id UUID,
  p_contacto_id       UUID,
  p_equipo_descripcion TEXT,
  p_sintoma           TEXT,
  p_es_garantia       BOOLEAN DEFAULT false
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  -- Verificar que el módulo Taller está activo para esta empresa
  IF NOT EXISTS (
    SELECT 1 FROM modulos_empresa
    WHERE empresa_id = p_empresa_id AND modulo_codigo = 'taller' AND activo = true
  ) THEN
    RETURN NULL; -- NO-OP si Taller no está activo
  END IF;

  RETURN create_repair_order(
    p_empresa_id, p_establecimiento_id,
    'RMA', p_contacto_id,
    p_equipo_descripcion, p_sintoma,
    '[]'::JSONB, NULL,
    p_rma_id,
    NULL, NULL, NULL, NULL, NULL,
    p_es_garantia
  );
END;
$$;
```

### Taller como CONSUMIDOR de otros módulos

```
Taller → Inventario (obligatorio si Inventario activo):
  module_bus.inventario.consumir_material()
    Consume material de bodega TALLER → genera kardex EGRESO
  module_bus.inventario.transferir()
    Transfiere SUMINISTROS_TALLER → TALLER cuando se necesitan insumos
  module_bus.inventario.ajustar_stock()
    Ajuste manual de stock de taller

Taller → Ventas (opcional, si Ventas activo):
  module_bus.ventas.create_quotation()
    Genera cotización/proforma desde la orden de reparación
  module_bus.ventas.create_invoice_from_repair()
    Factura al cliente al entregar el equipo reparado

Taller → Contabilidad (opcional, si Contabilidad activo):
  Asientos generados automáticamente al facturar:
    Ingreso reparaciones:   cuenta_ingreso_reparacion (H)
    Costo materiales:       cuenta_costo_materiales (D) / inventario (H)
    Costo mano de obra:     cuenta_costo_mano_obra (D) / sueldos por pagar (H)
    Overhead aplicado:      cuenta_overhead (D) / overhead aplicado (H)

Taller → Activos Fijos (opcional, si Activos Fijos activo):
  Herramientas vinculadas a activos_fijos para depreciación
  Órdenes tipo INTERNO para reparar activos propios de la empresa
```

### Flujo de bodegas de suministros

```
Compra insumos (módulo Compras)
  → Recepción → BODEGA SUMINISTROS_TALLER (centro de acopio)
  → Transferencia interna → BODEGA TALLER (por sucursal)
  → Consumo en orden → reparacion_materiales + kardex EGRESO

Consumibles bulk (conversión UoM):
  Compra: 1 galón tinta (3,785 ml) → stock: 3,785 ml (UoM base: ml)
  Consumo orden REP-001: 15 ml → stock restante: 3,770 ml
  Registro: cantidad=15, unidad_medida='ml', cantidad_base=15
```

### Notificaciones automáticas al cliente

```sql
-- Trigger: notificar al cliente en cada cambio de estado
CREATE OR REPLACE FUNCTION notify_repair_status_change() RETURNS TRIGGER AS $$
BEGIN
  IF OLD.estado IS DISTINCT FROM NEW.estado THEN
    PERFORM module_bus.send_notification(
      NEW.empresa_id,
      NEW.contacto_id,
      'TALLER_ESTADO',
      jsonb_build_object(
        'orden_numero', NEW.numero_orden,
        'estado_nuevo', NEW.estado,
        'equipo',       NEW.equipo_descripcion,
        'url_tracking', '/taller/seguimiento/' || NEW.token_seguimiento,
        'mensaje', CASE NEW.estado
          WHEN 'EN_DIAGNOSTICO' THEN 'Su equipo está siendo diagnosticado'
          WHEN 'COTIZADO'       THEN 'La cotización está lista para su aprobación'
          WHEN 'APROBADO'       THEN 'La reparación ha sido aprobada e iniciará pronto'
          WHEN 'EN_REPARACION'  THEN 'Su equipo está en proceso de reparación'
          WHEN 'REPARADO'       THEN 'Su equipo está listo para retiro'
          WHEN 'ENTREGADO'      THEN 'Equipo entregado. ¡Gracias por su confianza!'
          WHEN 'NO_REPARABLE'   THEN 'Lamentamos informar que el equipo no puede ser reparado'
          ELSE 'El estado de su reparación cambió a: ' || NEW.estado
        END
      )
    );
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER tr_notify_repair_status
  AFTER UPDATE OF estado ON ordenes_reparacion
  FOR EACH ROW EXECUTE FUNCTION notify_repair_status_change();
```

### Seguimiento online y aprobación de cotización (Edge Functions)

```
GET  /repair-status?token={token_seguimiento}
     Público (verify_jwt=false). Devuelve estado, equipo, diagnóstico,
     monto cotización y fecha estimada. Sin datos sensibles.

POST /approve-repair-quote
     body: {token: token_aprobacion, action: 'APROBAR'|'RECHAZAR'}
     APROBAR → SET cotizacion_aprobada=true, notifica taller
     RECHAZAR → SET estado='CANCELADO', notifica taller
```
