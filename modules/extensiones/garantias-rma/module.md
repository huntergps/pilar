# Módulo de Garantías/RMA

Módulo auxiliar puente que gestiona el ciclo completo de reclamos de garantía y devoluciones de clientes (Return Merchandise Authorization). Conecta los módulos Core de **Ventas** y **Compras** con el módulo auxiliar **Taller** para coordinar la resolución: reparar, reemplazar, emitir nota de crédito, devolver al proveedor o declarar merma.

> **Módulo Auxiliar #21 — Dependencias:**
> - **Ventas** (Core, requerido): verifica `garantias_venta` y `factura_detalles`; emite notas de crédito vía `module_bus.ventas.emitir_nc()`.
> - **Compras** (Core, requerido): gestiona devoluciones upstream a través de `garantias_proveedor`; ejecuta devoluciones vía `module_bus.compras.devolucion_proveedor()`.
> - **Inventario** (Core, requerido): mueve productos entre bodegas (GARANTIAS → destino final) vía `module_bus.inventario.despachar()`.
> - **Taller** (Auxiliar, opcional): si está activo, crea órdenes de reparación vía `module_bus.taller.crear_orden_desde_rma()`. Sin Taller, la resolución REPARAR no está disponible.
> - **Contabilidad** (Core, opcional): genera asiento contable de baja cuando hay mermas.

**Definiciones de garantía en módulos Core (no en este módulo):**

Las condiciones de garantía viven en los módulos de origen, este módulo solo las referencia:
- `garantias_proveedor` — definida en **Compras**: qué garantía otorga el proveedor sobre cada producto adquirido.
- `garantias_venta` — definida en **Ventas**: qué garantía otorga la empresa al cliente. Tres tipos: `PROPIA` (la empresa asume el costo), `TRANSFERIDA` (se transfiere la garantía del proveedor) o `MIXTA` (la empresa extiende la del proveedor).
- Al confirmar una factura de venta, `factura_detalles` registra `garantia_venta_id` y `fecha_fin_garantia` por línea, permitiendo verificar vigencia directamente desde el detalle.

---

## Flujo Completo

```
──────────────────────────────────────────────────────────────────
SETUP PREVIO (en módulos Core, antes del reclamo):
──────────────────────────────────────────────────────────────────

COMPRAS: garantias_proveedor
  Proveedor → empresa: "12 meses, cubre defecto de fábrica"

VENTAS: garantias_venta (tipo PROPIA | TRANSFERIDA | MIXTA)
  Al confirmar factura:
    factura_detalles.garantia_venta_id  = <id>
    factura_detalles.fecha_fin_garantia = fecha_emision + duracion_garantia

──────────────────────────────────────────────────────────────────
RECLAMO (este módulo - Garantías/RMA):
──────────────────────────────────────────────────────────────────

1. RECEPCIÓN
   Cliente presenta reclamo → crear solicitud_rma
     · verifica factura_detalles.fecha_fin_garantia
     · determina es_garantia (dentro o fuera de período)
     · recibe físicamente el producto con evidencia + firma

2. DIAGNÓSTICO
   Técnico evalúa el equipo:
     · determina tipo_garantia: PROPIA | TRANSFERIDA_PROVEEDOR | MIXTA | SIN_GARANTIA
     · determina es_reparable: true | false
     · registra diagnóstico técnico

3. RESOLUCIÓN (una de 6 opciones):

   REPARAR_GRATIS     → module_bus.taller.crear_orden_desde_rma()
                         (garantía cubre 100%; requiere módulo Taller activo)

   REPARAR_CON_COSTO  → module_bus.taller.crear_orden_desde_rma()
                         (costo parcial; genera cotización al cliente primero)

   NOTA_CREDITO       → module_bus.ventas.emitir_nc()
                         (NC al cliente por el valor de la factura original)

   REEMPLAZO          → module_bus.inventario.despachar()
                         (despacha producto equivalente desde stock VENTAS)

   DEVOLUCION_PROVEEDOR → module_bus.compras.devolucion_proveedor()
                           (devuelve upstream con tracking de respuesta)

   SCRAP              → mermas_garantia
                         (baja del inventario; requiere aprobación gerente)

4. CIERRE
   · Evidencia de entrega + firma digital del cliente
   · Movimiento físico final de bodegas
   · Asiento contable de merma (si aplica)
   · Estado → CERRADO
```

---

## Navegación

```
garantias-rma/
  ├── dashboard/
  │     └── (KPIs: RMAs abiertos, tiempo promedio resolución, mermas del mes)
  ├── rma/
  │     ├── listado/          # SfDataGrid: RMAs filtrados por estado/período/tipo
  │     ├── nuevo/            # Recepción: factura + producto + motivo + evidencia + firma
  │     ├── detalle/          # Vista completa del caso con historial de estados
  │     ├── diagnostico/      # Técnico: tipo_garantia + es_reparable + diagnóstico
  │     ├── cotizacion/       # Aprobar costo con cliente (si REPARAR_CON_COSTO)
  │     ├── resolucion/       # Ejecutar resolución según tipo elegido
  │     └── devolucion-prov/  # Tracking: fecha envío, respuesta proveedor
  └── reportes/
        ├── rma-status/       # RMA abiertos por estado y antigüedad (aging)
        ├── mermas-garantia/  # Mermas por período, motivo y cuenta contable
        └── tiempos-resol/    # SLA de resolución: días promedio por tipo
```

---

## Modelo de Datos

### Solicitudes RMA

```sql
CREATE TABLE solicitudes_rma (
  id                         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id                 UUID NOT NULL REFERENCES empresas(id),
  establecimiento_id         UUID REFERENCES establecimientos(id),

  -- Número secuencial
  numero_rma                 VARCHAR(20) NOT NULL,  -- Ej: RMA-20260215-0001

  -- Cliente y factura original (Ventas Core)
  contacto_id                UUID REFERENCES contactos(id),
  factura_id                 UUID REFERENCES facturas(id),
  factura_detalle_id         UUID REFERENCES factura_detalles(id),

  -- Producto devuelto
  producto_id                UUID NOT NULL REFERENCES productos(id),
  presentacion_id            UUID REFERENCES producto_presentaciones(id),
  serie_lote_id              UUID REFERENCES series_lotes(id),
  cantidad                   DECIMAL(18,6) NOT NULL DEFAULT 1,

  -- Motivo de la devolución
  motivo                     VARCHAR(30) NOT NULL,
    -- DEFECTO_FABRICA:        producto llegó defectuoso de fábrica
    -- DANO_TRANSPORTE:        se dañó durante la entrega al cliente
    -- FALLA_USO:              falló durante uso normal dentro del período de garantía
    -- NO_CUMPLE_EXPECTATIVA:  producto no corresponde a lo esperado/descrito
    -- ERROR_ENVIO:            se despachó el producto equivocado
    -- OTRO:                   otro motivo (especificar en descripcion_problema)
  descripcion_problema       TEXT NOT NULL,

  -- Información de garantía
  es_garantia                BOOLEAN NOT NULL DEFAULT false,
  fecha_compra               DATE,                  -- Fecha de la factura original
  fecha_vencimiento_garantia DATE,                  -- Calculada: fecha_compra + duración

  -- Tipo de garantía (determinado al diagnosticar)
  tipo_garantia              VARCHAR(25),
    -- PROPIA:                  la empresa asume el 100% del costo
    -- TRANSFERIDA_PROVEEDOR:   garantía del proveedor transferida directamente al cliente
    -- MIXTA:                   empresa amplió o complementó la garantía del proveedor
    -- SIN_GARANTIA:            fuera de período o producto sin cobertura de garantía

  -- Vínculos a definiciones de garantía en módulos Core
  garantia_venta_id          UUID REFERENCES garantias_venta(id),       -- Ventas Core
  garantia_proveedor_id      UUID REFERENCES garantias_proveedor(id),   -- Compras Core

  -- Evidencia de ingreso (recepción del producto)
  evidencia_ingreso          JSONB NOT NULL DEFAULT '[]',
    -- [{url: 'https://...', tipo: 'FOTO'|'VIDEO', descripcion: '...'}]
  firma_cliente_ingreso      TEXT,                  -- URL imagen firma digital

  -- Diagnóstico técnico
  diagnosticado_por          UUID REFERENCES auth.users(id),
  fecha_diagnostico          TIMESTAMPTZ,
  diagnostico                TEXT,
  es_reparable               BOOLEAN,               -- NULL hasta diagnosticar

  -- Resolución elegida
  tipo_resolucion            VARCHAR(25),
    -- REPARAR_GRATIS:          reparación en Taller sin costo para el cliente
    -- REPARAR_CON_COSTO:       reparación con costo parcial (fuera o mixta)
    -- REEMPLAZO:               entrega de producto equivalente nuevo
    -- NOTA_CREDITO:            emisión de NC al cliente por el valor original
    -- DEVOLUCION_PROVEEDOR:    devolución upstream al fabricante/proveedor
    -- SCRAP:                   baja de inventario por irreparable (requiere aprobación)
    -- REVENTA:                 producto reparado/reacondicionado vuelve al stock

  -- Cotización (si aplica costo al cliente: REPARAR_CON_COSTO)
  cotizacion_id              UUID REFERENCES cotizaciones(id),
  cotizacion_aprobada        BOOLEAN,
  monto_cotizacion           DECIMAL(14,2),

  -- Enlace a orden de reparación (módulo Taller — si aplica)
  orden_reparacion_id        UUID REFERENCES ordenes_reparacion(id),

  -- Devolución a proveedor (si aplica)
  proveedor_id               UUID REFERENCES contactos(id),
  fecha_envio_proveedor      TIMESTAMPTZ,
  fecha_retorno_proveedor    TIMESTAMPTZ,
  resolucion_proveedor       VARCHAR(20),
    -- REPARADO:     proveedor reparó y devolvió el mismo equipo
    -- REEMPLAZADO:  proveedor envió una unidad nueva
    -- NOTA_CREDITO: proveedor emitió nota de crédito
    -- RECHAZADO:    proveedor no aceptó el reclamo de garantía

  -- Movimientos de inventario
  bodega_garantias_id        UUID REFERENCES bodegas(id),  -- Bodega mientras se evalúa
  bodega_destino_id          UUID REFERENCES bodegas(id),  -- Bodega final tras resolución

  -- Estado del ciclo de vida
  estado                     VARCHAR(20) NOT NULL DEFAULT 'RECIBIDO',
    -- RECIBIDO:         producto devuelto por el cliente, en bodega de garantías
    -- EN_DIAGNOSTICO:   técnico evaluando el equipo
    -- DIAGNOSTICADO:    evaluación completa, pendiente decisión de resolución
    -- COTIZADO:         proforma de reparación generada y enviada al cliente
    -- APROBADO:         cliente o gerente aprobó la resolución a ejecutar
    -- EN_PROCESO:       resolución en curso (reparación en taller o en tránsito a proveedor)
    -- RESUELTO:         resolución completada exitosamente
    -- ENTREGADO:        producto devuelto al cliente (o NC emitida y comunicada)
    -- CERRADO:          caso completamente cerrado, archivado

  -- Evidencia de entrega
  evidencia_entrega          JSONB NOT NULL DEFAULT '[]',
  firma_cliente_entrega      TEXT,                  -- URL imagen firma digital de recepción

  -- Auditoría
  notas_internas             TEXT,
  created_at                 TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at                 TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by                 UUID REFERENCES auth.users(id),
  updated_by                 UUID REFERENCES auth.users(id),

  UNIQUE(empresa_id, numero_rma)
);

ALTER TABLE solicitudes_rma ENABLE ROW LEVEL SECURITY;
```

### Historial de Estado RMA

Trazabilidad completa de transiciones de estado para auditoría y SLA.

```sql
CREATE TABLE rma_historial_estado (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  rma_id          UUID NOT NULL REFERENCES solicitudes_rma(id) ON DELETE CASCADE,
  estado_anterior VARCHAR(20),
  estado_nuevo    VARCHAR(20) NOT NULL,
  comentario      TEXT,
  duracion_horas  DECIMAL(10,2),  -- Horas en el estado anterior (para SLA)
  usuario_id      UUID REFERENCES auth.users(id),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE rma_historial_estado ENABLE ROW LEVEL SECURITY;
```

### Mermas de Garantía

Registro de productos dados de baja que provienen de garantías/RMA. Separado de `mermas_inventario` (que es para stock vendible normal).

```sql
CREATE TABLE mermas_garantia (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id        UUID NOT NULL REFERENCES empresas(id),
  rma_id            UUID NOT NULL REFERENCES solicitudes_rma(id),

  -- Producto
  producto_id       UUID NOT NULL REFERENCES productos(id),
  presentacion_id   UUID REFERENCES producto_presentaciones(id),
  serie_lote_id     UUID REFERENCES series_lotes(id),
  cantidad          DECIMAL(18,6) NOT NULL DEFAULT 1,

  -- Valorización
  costo_unitario    DECIMAL(18,6) NOT NULL,
  costo_total       DECIMAL(14,2) NOT NULL,

  -- Motivo de la merma
  motivo            VARCHAR(30) NOT NULL,
    -- IRREPARABLE:         no se puede reparar técnicamente
    -- PROVEEDOR_RECHAZA:   proveedor no acepta la devolución ni el reclamo
    -- DECISION_GERENCIAL:  gerente decide dar de baja por criterio de negocio
    -- COSTO_MAYOR_VALOR:   costo de reparación supera el valor de mercado del producto
    -- DANO_ALMACENAMIENTO: se dañó mientras esperaba resolución en bodega
  descripcion       TEXT,

  -- Aprobación gerencial (obligatoria para toda merma de garantía)
  aprobado_por      UUID NOT NULL REFERENCES auth.users(id),
  fecha_aprobacion  TIMESTAMPTZ NOT NULL,

  -- Contabilidad (opcional si módulo Contabilidad está activo)
  asiento_id        UUID REFERENCES asientos_contables(id),
  cuenta_gasto_id   UUID REFERENCES cuentas_contables(id),

  -- Bodega de origen (GARANTIAS)
  bodega_origen_id  UUID REFERENCES bodegas(id),

  -- Auditoría
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by        UUID NOT NULL REFERENCES auth.users(id)
);

ALTER TABLE mermas_garantia ENABLE ROW LEVEL SECURITY;
```

### Configuración RMA por Establecimiento

```sql
CREATE TABLE config_rma (
  id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id               UUID NOT NULL REFERENCES empresas(id),
  establecimiento_id       UUID NOT NULL REFERENCES establecimientos(id),

  -- Bodega dedicada a almacenar equipos en evaluación de garantía
  bodega_garantias_id      UUID REFERENCES bodegas(id),

  -- Cuenta contable para registrar pérdidas por mermas de garantía
  cuenta_merma_garantia    UUID REFERENCES cuentas_contables(id),

  -- Numeración de RMAs
  prefijo_rma              VARCHAR(10) NOT NULL DEFAULT 'RMA',
  secuencia_rma            INTEGER NOT NULL DEFAULT 0,

  -- Días máximos por estado (para alertas de SLA)
  dias_max_diagnostico     INTEGER DEFAULT 3,   -- Días para completar diagnóstico
  dias_max_resolucion      INTEGER DEFAULT 15,  -- Días para cerrar el caso

  -- Requiere aprobación de gerente para mermas
  aprobacion_merma         BOOLEAN DEFAULT true,

  created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at               TIMESTAMPTZ NOT NULL DEFAULT now(),

  UNIQUE(empresa_id, establecimiento_id)
);

ALTER TABLE config_rma ENABLE ROW LEVEL SECURITY;
```

---

## Índices

```sql
-- solicitudes_rma
CREATE INDEX idx_rma_empresa_estado    ON solicitudes_rma(empresa_id, estado);
CREATE INDEX idx_rma_empresa_periodo   ON solicitudes_rma(empresa_id, created_at DESC);
CREATE INDEX idx_rma_contacto          ON solicitudes_rma(contacto_id);
CREATE INDEX idx_rma_factura           ON solicitudes_rma(factura_id);
CREATE INDEX idx_rma_factura_detalle   ON solicitudes_rma(factura_detalle_id);
CREATE INDEX idx_rma_producto          ON solicitudes_rma(producto_id);
CREATE INDEX idx_rma_orden_reparacion  ON solicitudes_rma(orden_reparacion_id) WHERE orden_reparacion_id IS NOT NULL;
CREATE INDEX idx_rma_numero            ON solicitudes_rma(empresa_id, numero_rma);

-- rma_historial_estado
CREATE INDEX idx_rma_historial_rma     ON rma_historial_estado(rma_id);
CREATE INDEX idx_rma_historial_empresa ON rma_historial_estado(empresa_id, created_at DESC);

-- mermas_garantia
CREATE INDEX idx_mermas_garantia_rma     ON mermas_garantia(rma_id);
CREATE INDEX idx_mermas_garantia_empresa ON mermas_garantia(empresa_id, created_at DESC);
CREATE INDEX idx_mermas_garantia_prod    ON mermas_garantia(producto_id);

-- config_rma
CREATE UNIQUE INDEX idx_config_rma_estab ON config_rma(empresa_id, establecimiento_id);
```

---

## Políticas RLS

```sql
-- solicitudes_rma
CREATE POLICY "tenant_isolation" ON solicitudes_rma
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- rma_historial_estado
CREATE POLICY "tenant_isolation" ON rma_historial_estado
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- mermas_garantia
CREATE POLICY "tenant_isolation" ON mermas_garantia
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- config_rma
CREATE POLICY "tenant_isolation" ON config_rma
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));
```

---

## Triggers

```sql
-- Auto-actualizar updated_at
CREATE OR REPLACE FUNCTION trg_rma_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  NEW.updated_by := auth.uid();
  RETURN NEW;
END;
$$;

CREATE TRIGGER tr_solicitudes_rma_updated_at
  BEFORE UPDATE ON solicitudes_rma
  FOR EACH ROW EXECUTE FUNCTION trg_rma_updated_at();

-- Registrar transición de estado automáticamente
CREATE OR REPLACE FUNCTION trg_rma_estado_historial()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_duracion_horas DECIMAL(10,2);
BEGIN
  IF OLD.estado IS DISTINCT FROM NEW.estado THEN
    -- Calcular duración en el estado anterior
    SELECT EXTRACT(EPOCH FROM (now() - created_at)) / 3600
    INTO v_duracion_horas
    FROM rma_historial_estado
    WHERE rma_id = OLD.id AND estado_nuevo = OLD.estado
    ORDER BY created_at DESC
    LIMIT 1;

    INSERT INTO rma_historial_estado (
      empresa_id, rma_id,
      estado_anterior, estado_nuevo,
      duracion_horas, usuario_id
    ) VALUES (
      NEW.empresa_id, NEW.id,
      OLD.estado, NEW.estado,
      v_duracion_horas, auth.uid()
    );
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER tr_rma_estado_historial
  AFTER UPDATE ON solicitudes_rma
  FOR EACH ROW EXECUTE FUNCTION trg_rma_estado_historial();
```

---

## RPCs Principales

```sql
-- ══════════════════════════════════════════════════════════════════
-- RPC: Crear solicitud RMA
-- Verifica garantía vigente desde factura_detalles.fecha_fin_garantia
-- ══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION create_rma_request(
  p_empresa_id          UUID,
  p_contacto_id         UUID,
  p_factura_id          UUID,
  p_factura_detalle_id  UUID,
  p_producto_id         UUID,
  p_motivo              VARCHAR(30),
  p_descripcion         TEXT,
  p_evidencia           JSONB    DEFAULT '[]',
  p_firma_cliente       TEXT    DEFAULT NULL,
  p_serie_lote_id       UUID    DEFAULT NULL,
  p_cantidad            DECIMAL DEFAULT 1
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_rma_id              UUID;
  v_numero              VARCHAR(20);
  v_config              config_rma%ROWTYPE;
  v_establecimiento_id  UUID;
  v_fecha_compra        DATE;
  v_fecha_venc          DATE;
  v_es_garantia         BOOLEAN := false;
  v_garantia_venta_id   UUID;
  v_garantia_prov_id    UUID;
BEGIN
  -- Verificar que la empresa coincide
  IF p_empresa_id != (SELECT private.get_empresa_id()) THEN
    RAISE EXCEPTION 'Acceso denegado';
  END IF;

  -- Obtener establecimiento y fecha de la factura original
  SELECT establecimiento_id, fecha_emision::date
  INTO v_establecimiento_id, v_fecha_compra
  FROM facturas
  WHERE id = p_factura_id AND empresa_id = p_empresa_id;

  IF v_establecimiento_id IS NULL THEN
    RAISE EXCEPTION 'Factura no encontrada o no pertenece a esta empresa';
  END IF;

  -- Leer garantía vigente desde el detalle de factura
  SELECT fd.garantia_venta_id,
         fd.fecha_fin_garantia,
         gv.garantia_proveedor_id
  INTO   v_garantia_venta_id, v_fecha_venc, v_garantia_prov_id
  FROM   factura_detalles fd
  LEFT JOIN garantias_venta gv ON gv.id = fd.garantia_venta_id
  WHERE  fd.id = p_factura_detalle_id;

  -- Determinar si está dentro del período de garantía
  v_es_garantia := (v_fecha_venc IS NOT NULL AND CURRENT_DATE <= v_fecha_venc);

  -- Obtener configuración RMA del establecimiento
  SELECT * INTO v_config
  FROM config_rma
  WHERE empresa_id = p_empresa_id AND establecimiento_id = v_establecimiento_id;

  IF v_config.id IS NULL THEN
    RAISE EXCEPTION 'No existe configuración RMA para este establecimiento. Configure primero en Administración → Garantías/RMA.';
  END IF;

  -- Generar número RMA secuencial
  UPDATE config_rma
  SET secuencia_rma = secuencia_rma + 1
  WHERE id = v_config.id
  RETURNING secuencia_rma INTO v_config.secuencia_rma;

  v_numero := v_config.prefijo_rma || '-' ||
              to_char(CURRENT_DATE, 'YYYYMMDD') || '-' ||
              lpad(v_config.secuencia_rma::text, 4, '0');

  -- Insertar el RMA
  INSERT INTO solicitudes_rma (
    empresa_id, establecimiento_id, numero_rma,
    contacto_id, factura_id, factura_detalle_id,
    producto_id, serie_lote_id, cantidad,
    motivo, descripcion_problema,
    es_garantia, fecha_compra, fecha_vencimiento_garantia,
    garantia_venta_id, garantia_proveedor_id,
    evidencia_ingreso, firma_cliente_ingreso,
    bodega_garantias_id, estado,
    created_by
  ) VALUES (
    p_empresa_id, v_establecimiento_id, v_numero,
    p_contacto_id, p_factura_id, p_factura_detalle_id,
    p_producto_id, p_serie_lote_id, p_cantidad,
    p_motivo, p_descripcion,
    v_es_garantia, v_fecha_compra, v_fecha_venc,
    v_garantia_venta_id, v_garantia_prov_id,
    p_evidencia, p_firma_cliente,
    v_config.bodega_garantias_id, 'RECIBIDO',
    auth.uid()
  ) RETURNING id INTO v_rma_id;

  -- Mover producto a bodega de garantías (vía Module Service Bus)
  PERFORM module_bus.inventario.mover_producto(
    p_empresa_id,
    p_producto_id,
    p_cantidad,
    NULL,                       -- bodega origen: bodega del establecimiento del cliente
    v_config.bodega_garantias_id,
    'ENTRADA_GARANTIA',
    'Ingreso RMA ' || v_numero
  );

  RETURN v_rma_id;
END;
$$;

-- ══════════════════════════════════════════════════════════════════
-- RPC: Registrar diagnóstico técnico
-- ══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION update_rma_diagnosis(
  p_rma_id        UUID,
  p_diagnostico   TEXT,
  p_es_reparable  BOOLEAN,
  p_tipo_garantia VARCHAR(25)   -- PROPIA | TRANSFERIDA_PROVEEDOR | MIXTA | SIN_GARANTIA
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_empresa_id UUID;
  v_estado     VARCHAR(20);
BEGIN
  SELECT empresa_id, estado
  INTO v_empresa_id, v_estado
  FROM solicitudes_rma
  WHERE id = p_rma_id AND empresa_id = (SELECT private.get_empresa_id());

  IF v_empresa_id IS NULL THEN
    RAISE EXCEPTION 'RMA no encontrado';
  END IF;

  IF v_estado NOT IN ('RECIBIDO', 'EN_DIAGNOSTICO') THEN
    RAISE EXCEPTION 'Solo se puede registrar diagnóstico en estado RECIBIDO o EN_DIAGNOSTICO. Estado actual: %', v_estado;
  END IF;

  UPDATE solicitudes_rma SET
    diagnostico       = p_diagnostico,
    es_reparable      = p_es_reparable,
    tipo_garantia     = p_tipo_garantia,
    diagnosticado_por = auth.uid(),
    fecha_diagnostico = now(),
    estado            = 'DIAGNOSTICADO'
  WHERE id = p_rma_id;
END;
$$;

-- ══════════════════════════════════════════════════════════════════
-- RPC: Ejecutar resolución de un RMA
-- Enruta al módulo correspondiente vía Module Service Bus
-- ══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION resolve_rma(
  p_rma_id          UUID,
  p_tipo_resolucion VARCHAR(25),
  p_proveedor_id    UUID DEFAULT NULL    -- Para DEVOLUCION_PROVEEDOR
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_rma         solicitudes_rma%ROWTYPE;
  v_orden_id    UUID;
  v_nc_id       UUID;
  v_resultado   JSONB;
  v_prod_nombre VARCHAR(200);
BEGIN
  SELECT * INTO v_rma
  FROM solicitudes_rma
  WHERE id = p_rma_id AND empresa_id = (SELECT private.get_empresa_id());

  IF v_rma.id IS NULL THEN
    RAISE EXCEPTION 'RMA no encontrado';
  END IF;

  IF v_rma.estado NOT IN ('DIAGNOSTICADO', 'COTIZADO', 'APROBADO') THEN
    RAISE EXCEPTION 'Solo se puede ejecutar resolución cuando el RMA está en estado DIAGNOSTICADO, COTIZADO o APROBADO. Estado actual: %', v_rma.estado;
  END IF;

  SELECT nombre INTO v_prod_nombre FROM productos WHERE id = v_rma.producto_id;

  CASE p_tipo_resolucion

    WHEN 'REPARAR_GRATIS', 'REPARAR_CON_COSTO' THEN
      -- Crear orden de reparación en módulo Taller via Module Service Bus
      v_orden_id := module_bus.taller.crear_orden_desde_rma(
        p_rma_id              := p_rma_id,
        p_empresa_id          := v_rma.empresa_id,
        p_establecimiento_id  := v_rma.establecimiento_id,
        p_contacto_id         := v_rma.contacto_id,
        p_producto_desc       := v_prod_nombre,
        p_problema            := v_rma.descripcion_problema,
        p_garantia_total      := (p_tipo_resolucion = 'REPARAR_GRATIS')
      );

      IF v_orden_id IS NULL THEN
        RAISE EXCEPTION 'El módulo Taller no está activo. Elija otra resolución (NOTA_CREDITO, REEMPLAZO o DEVOLUCION_PROVEEDOR).';
      END IF;

      UPDATE solicitudes_rma
      SET orden_reparacion_id = v_orden_id
      WHERE id = p_rma_id;

      v_resultado := jsonb_build_object(
        'accion', p_tipo_resolucion,
        'orden_reparacion_id', v_orden_id
      );

    WHEN 'NOTA_CREDITO' THEN
      -- Emitir NC al cliente vía módulo Ventas (que a su vez usa Facturación)
      v_nc_id := module_bus.ventas.emitir_nc(
        p_empresa_id         := v_rma.empresa_id,
        p_factura_id         := v_rma.factura_id,
        p_factura_detalle_id := v_rma.factura_detalle_id,
        p_cantidad           := v_rma.cantidad,
        p_motivo             := 'Garantía/RMA ' || v_rma.numero_rma
      );

      v_resultado := jsonb_build_object(
        'accion', 'NOTA_CREDITO',
        'nc_id', v_nc_id
      );

    WHEN 'REEMPLAZO' THEN
      -- Despachar producto equivalente desde stock ventas
      PERFORM module_bus.inventario.despachar(
        p_empresa_id          := v_rma.empresa_id,
        p_producto_id         := v_rma.producto_id,
        p_cantidad            := v_rma.cantidad,
        p_establecimiento_id  := v_rma.establecimiento_id,
        p_referencia          := 'Reemplazo RMA ' || v_rma.numero_rma
      );

      v_resultado := jsonb_build_object('accion', 'REEMPLAZO');

    WHEN 'DEVOLUCION_PROVEEDOR' THEN
      -- Crear devolución a proveedor vía módulo Compras
      PERFORM module_bus.compras.devolucion_proveedor(
        p_empresa_id          := v_rma.empresa_id,
        p_proveedor_id        := COALESCE(p_proveedor_id, v_rma.proveedor_id),
        p_producto_id         := v_rma.producto_id,
        p_cantidad            := v_rma.cantidad,
        p_referencia          := 'Devolución garantía RMA ' || v_rma.numero_rma
      );

      UPDATE solicitudes_rma SET
        proveedor_id          = COALESCE(p_proveedor_id, proveedor_id),
        fecha_envio_proveedor = now()
      WHERE id = p_rma_id;

      v_resultado := jsonb_build_object(
        'accion', 'DEVOLUCION_PROVEEDOR',
        'proveedor_id', COALESCE(p_proveedor_id, v_rma.proveedor_id)
      );

    ELSE
      RAISE EXCEPTION 'Tipo de resolución no reconocido: %. Valores válidos: REPARAR_GRATIS, REPARAR_CON_COSTO, NOTA_CREDITO, REEMPLAZO, DEVOLUCION_PROVEEDOR', p_tipo_resolucion;

  END CASE;

  -- Actualizar estado del RMA
  UPDATE solicitudes_rma SET
    tipo_resolucion = p_tipo_resolucion,
    estado          = 'EN_PROCESO'
  WHERE id = p_rma_id;

  RETURN v_resultado;
END;
$$;

-- ══════════════════════════════════════════════════════════════════
-- RPC: Registrar merma (baja de producto por garantía)
-- Solo disponible cuando tipo_resolucion = 'SCRAP'
-- Requiere aprobación gerencial previa
-- ══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION register_rma_scrap(
  p_rma_id           UUID,
  p_motivo           VARCHAR(30),
  p_descripcion      TEXT,
  p_aprobado_por     UUID,        -- ID del gerente que autorizó
  p_fecha_aprobacion TIMESTAMPTZ DEFAULT now()
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_rma          solicitudes_rma%ROWTYPE;
  v_config       config_rma%ROWTYPE;
  v_costo        DECIMAL(18,6);
  v_merma_id     UUID;
  v_asiento_id   UUID;
BEGIN
  SELECT * INTO v_rma
  FROM solicitudes_rma
  WHERE id = p_rma_id AND empresa_id = (SELECT private.get_empresa_id());

  IF v_rma.id IS NULL THEN
    RAISE EXCEPTION 'RMA no encontrado';
  END IF;

  -- Obtener configuración (cuenta contable de merma)
  SELECT * INTO v_config
  FROM config_rma
  WHERE empresa_id = v_rma.empresa_id AND establecimiento_id = v_rma.establecimiento_id;

  -- Obtener costo promedio del producto
  SELECT costo_promedio INTO v_costo
  FROM inventario_stock
  WHERE empresa_id = v_rma.empresa_id AND producto_id = v_rma.producto_id
  LIMIT 1;

  v_costo := COALESCE(v_costo, 0);

  -- Registrar merma
  INSERT INTO mermas_garantia (
    empresa_id, rma_id,
    producto_id, serie_lote_id, cantidad,
    costo_unitario, costo_total,
    motivo, descripcion,
    aprobado_por, fecha_aprobacion,
    cuenta_gasto_id, bodega_origen_id,
    created_by
  ) VALUES (
    v_rma.empresa_id, p_rma_id,
    v_rma.producto_id, v_rma.serie_lote_id, v_rma.cantidad,
    v_costo, ROUND((v_costo * v_rma.cantidad)::NUMERIC, 2),
    p_motivo, p_descripcion,
    p_aprobado_por, p_fecha_aprobacion,
    v_config.cuenta_merma_garantia, v_rma.bodega_garantias_id,
    auth.uid()
  ) RETURNING id INTO v_merma_id;

  -- Generar asiento contable de baja (vía Module Service Bus si Contabilidad está activo)
  IF v_config.cuenta_merma_garantia IS NOT NULL THEN
    v_asiento_id := module_bus.contabilidad.create_journal_entry(
      p_empresa_id    := v_rma.empresa_id,
      p_descripcion   := 'Merma garantía RMA ' || v_rma.numero_rma,
      p_referencia    := v_merma_id::text,
      p_lineas        := jsonb_build_array(
        jsonb_build_object(
          'cuenta_id', v_config.cuenta_merma_garantia,
          'debe',      ROUND((v_costo * v_rma.cantidad)::NUMERIC, 2),
          'haber',     0,
          'descripcion', 'Pérdida merma garantía'
        ),
        jsonb_build_object(
          'cuenta_id', (SELECT cuenta_inventario_id FROM config_inventario
                        WHERE empresa_id = v_rma.empresa_id LIMIT 1),
          'debe',      0,
          'haber',     ROUND((v_costo * v_rma.cantidad)::NUMERIC, 2),
          'descripcion', 'Baja inventario garantías'
        )
      )
    );

    UPDATE mermas_garantia SET asiento_id = v_asiento_id WHERE id = v_merma_id;
  END IF;

  -- Actualizar estado del RMA
  UPDATE solicitudes_rma SET
    tipo_resolucion = 'SCRAP',
    estado          = 'RESUELTO'
  WHERE id = p_rma_id;

  RETURN v_merma_id;
END;
$$;

-- ══════════════════════════════════════════════════════════════════
-- RPC: Cerrar RMA tras entrega al cliente
-- ══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION close_rma(
  p_rma_id          UUID,
  p_evidencia       JSONB DEFAULT '[]',
  p_firma_cliente   TEXT  DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_rma solicitudes_rma%ROWTYPE;
BEGIN
  SELECT * INTO v_rma
  FROM solicitudes_rma
  WHERE id = p_rma_id AND empresa_id = (SELECT private.get_empresa_id());

  IF v_rma.id IS NULL THEN
    RAISE EXCEPTION 'RMA no encontrado';
  END IF;

  IF v_rma.estado NOT IN ('RESUELTO', 'ENTREGADO') THEN
    RAISE EXCEPTION 'Solo se puede cerrar un RMA en estado RESUELTO o ENTREGADO. Estado actual: %', v_rma.estado;
  END IF;

  UPDATE solicitudes_rma SET
    estado                = 'CERRADO',
    evidencia_entrega     = p_evidencia,
    firma_cliente_entrega = p_firma_cliente
  WHERE id = p_rma_id;
END;
$$;

-- ══════════════════════════════════════════════════════════════════
-- RPC: Dashboard de Garantías/RMA
-- ══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION get_rma_dashboard(
  p_empresa_id UUID,
  p_fecha_desde DATE DEFAULT (CURRENT_DATE - INTERVAL '30 days'),
  p_fecha_hasta DATE DEFAULT CURRENT_DATE
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_result JSONB;
BEGIN
  IF p_empresa_id != (SELECT private.get_empresa_id()) THEN
    RAISE EXCEPTION 'Acceso denegado';
  END IF;

  SELECT jsonb_build_object(
    'abiertos_total',         COUNT(*) FILTER (WHERE estado NOT IN ('CERRADO', 'RESUELTO')),
    'cerrados_periodo',       COUNT(*) FILTER (WHERE estado = 'CERRADO'
                                               AND updated_at::date BETWEEN p_fecha_desde AND p_fecha_hasta),
    'mermas_periodo_usd',     COALESCE((
                                SELECT SUM(costo_total)
                                FROM mermas_garantia
                                WHERE empresa_id = p_empresa_id
                                  AND created_at::date BETWEEN p_fecha_desde AND p_fecha_hasta
                              ), 0),
    'tiempo_prom_horas',      COALESCE((
                                SELECT AVG(
                                  EXTRACT(EPOCH FROM (updated_at - created_at)) / 3600
                                )
                                FROM solicitudes_rma
                                WHERE empresa_id = p_empresa_id
                                  AND estado = 'CERRADO'
                                  AND updated_at::date BETWEEN p_fecha_desde AND p_fecha_hasta
                              ), 0),
    'por_estado',             jsonb_object_agg(estado, cnt),
    'por_resolucion',         (
                                SELECT jsonb_object_agg(tipo_resolucion, cnt2)
                                FROM (
                                  SELECT tipo_resolucion,
                                         COUNT(*) AS cnt2
                                  FROM solicitudes_rma
                                  WHERE empresa_id = p_empresa_id
                                    AND tipo_resolucion IS NOT NULL
                                    AND created_at::date BETWEEN p_fecha_desde AND p_fecha_hasta
                                  GROUP BY tipo_resolucion
                                ) r2
                              )
  ) INTO v_result
  FROM (
    SELECT estado, COUNT(*) AS cnt
    FROM solicitudes_rma
    WHERE empresa_id = p_empresa_id
    GROUP BY estado
  ) stats;

  RETURN v_result;
END;
$$;
```

---

## Module Service Bus

### Garantías/RMA como CONSUMIDOR

Garantías/RMA nunca hace INSERT directo en tablas de módulos Core. Toda interacción es vía `module_bus.*`:

```
module_bus.ventas.emitir_nc(
  p_empresa_id, p_factura_id, p_factura_detalle_id, p_cantidad, p_motivo
)
  → Emite NC al cliente cuando tipo_resolucion = NOTA_CREDITO.
  → Ventas llama internamente a module_bus.facturacion.create_invoice(tipo='NC').
  → Retorna nc_id (UUID de la nota de crédito creada).
  → Si módulo Ventas no está activo: RAISE EXCEPTION (es requerido).

module_bus.compras.devolucion_proveedor(
  p_empresa_id, p_proveedor_id, p_producto_id, p_cantidad, p_referencia
)
  → Inicia devolución upstream cuando tipo_resolucion = DEVOLUCION_PROVEEDOR.
  → Crea recepción negativa en Compras con referencia al número de RMA.
  → Si módulo Compras no está activo: RAISE EXCEPTION (es requerido).

module_bus.inventario.despachar(
  p_empresa_id, p_producto_id, p_cantidad, p_establecimiento_id, p_referencia
)
  → Despacha producto equivalente cuando tipo_resolucion = REEMPLAZO.
  → Genera movimiento de salida desde bodega VENTAS.
  → Si módulo Inventario no está activo: RAISE EXCEPTION (es requerido).

module_bus.inventario.mover_producto(
  p_empresa_id, p_producto_id, p_cantidad,
  p_bodega_origen_id, p_bodega_destino_id,
  p_tipo_movimiento, p_referencia
)
  → Mueve producto a bodega GARANTIAS al crear el RMA.
  → Al cerrar el RMA, mueve al destino final según resolución.

module_bus.taller.crear_orden_desde_rma(
  p_rma_id, p_empresa_id, p_establecimiento_id, p_contacto_id,
  p_producto_desc, p_problema, p_garantia_total
)
  → Crea orden de reparación con tipo_origen='RMA' en módulo Taller.
  → Si módulo Taller no está activo: retorna NULL (no es requerido).
  → El RMA valida el retorno; si es NULL bloquea la resolución REPARAR
    y el usuario debe elegir otra opción.

module_bus.contabilidad.create_journal_entry(
  p_empresa_id, p_descripcion, p_referencia, p_lineas
)
  → Genera asiento de baja cuando hay merma de garantía.
  → Si módulo Contabilidad no está activo: retorna NULL (no es requerido).
  → La merma se registra igualmente; el asiento queda pendiente.
```

### Garantías/RMA como PROVEEDOR (hacia otros módulos)

```
module_bus.garantias_rma.get_rma_by_producto(p_empresa_id, p_producto_id)
  → Retorna RMAs activos para un producto específico.
  → Usado por módulo Ventas para avisar al vendedor al hacer nueva venta.

module_bus.garantias_rma.tiene_rma_abierto(p_empresa_id, p_factura_id)
  → Verifica si una factura tiene RMA en curso antes de emitir NC manual.
  → Usado por módulo Ventas/Facturación para evitar doble reembolso.
```

---

## Flujo de Bodegas durante el Ciclo RMA

```
Devolución cliente → BODEGA GARANTIAS (mientras se evalúa)
    │
    ├── REPARAR (+ módulo Taller activo)
    │     BODEGA GARANTIAS → BODEGA TALLER   (Taller ejecuta la reparación)
    │     Al entregar: BODEGA TALLER → entrega física al cliente
    │     Si queda apto: BODEGA TALLER → BODEGA VENTAS (producto reacondicionado)
    │
    ├── REEMPLAZO
    │     BODEGA VENTAS → despacho al cliente   (producto nuevo)
    │     BODEGA GARANTIAS → BODEGA VENTAS      (si el devuelto se recondiciona)
    │     BODEGA GARANTIAS → SCRAP              (si no se puede reacondicionar)
    │
    ├── NOTA_CREDITO
    │     BODEGA GARANTIAS → queda en evaluación hasta NC emitida
    │     Luego: decisión gerente → BODEGA VENTAS (reventa) o SCRAP
    │
    ├── DEVOLUCION_PROVEEDOR
    │     BODEGA GARANTIAS → sale físicamente al proveedor
    │     Si proveedor repara/reemplaza → entra a BODEGA VENTAS cuando retorna
    │     Si proveedor rechaza → SCRAP o decisión gerente
    │
    └── SCRAP
          BODEGA GARANTIAS → baja definitiva
          → registro en mermas_garantia
          → asiento contable: Pérdida Merma (D) / Inventario (H)
```

---

## Pantallas Flutter

### Listado de RMAs (lib/features/garantias_rma/screens/rma_list_screen.dart)

```dart
// Columnas del SfDataGrid
// numero_rma | cliente | producto | estado | tipo_garantia | dias_abierto | acciones
//
// Filtros:
//   - Estado: chips seleccionables (RECIBIDO / EN_DIAGNOSTICO / ... / CERRADO)
//   - Período: DateRangePicker
//   - Búsqueda: nombre cliente o número RMA
//
// Acciones por fila:
//   - Ver detalle (→ RmaDetailScreen)
//   - Cambiar estado rápido (→ bottom sheet)
```

### Nuevo RMA (lib/features/garantias_rma/screens/rma_create_screen.dart)

```dart
// Pasos del formulario (Stepper):
// 1. Buscar factura (autocomplete cliente → lista facturas → lista líneas)
// 2. Verificar garantía (muestra fecha_fin_garantia, si es_garantia: badge verde/rojo)
// 3. Detalles del problema (motivo dropdown + descripcion_problema textarea)
// 4. Evidencia (CameraWidget: fotos + video + firma digital del cliente)
// 5. Confirmar y crear
```

### Diagnóstico (lib/features/garantias_rma/screens/rma_diagnosis_screen.dart)

```dart
// Campos:
//   - tipo_garantia: SegmentedButton (PROPIA / TRANSFERIDA_PROVEEDOR / MIXTA / SIN_GARANTIA)
//   - es_reparable: Switch
//   - diagnostico: TextField multiline
//
// Al guardar → llama update_rma_diagnosis() → estado pasa a DIAGNOSTICADO
// → muestra opciones de resolución disponibles según tipo_garantia + es_reparable + módulos activos
```

### Resolución (lib/features/garantias_rma/screens/rma_resolution_screen.dart)

```dart
// Opciones mostradas dinámicamente según contexto:
//   REPARAR_GRATIS      → visible si es_garantia=true y Taller activo
//   REPARAR_CON_COSTO   → visible si es_reparable=true y Taller activo
//   NOTA_CREDITO        → siempre visible
//   REEMPLAZO           → visible si hay stock disponible
//   DEVOLUCION_PROVEEDOR → visible si tiene garantia_proveedor_id o tipo=TRANSFERIDA
//   SCRAP               → visible si !es_reparable o costo_rep > valor_prod
//
// Al confirmar → llama resolve_rma() → navega a pantalla de seguimiento
```

---

## Consideraciones de Negocio

### Tipos de Garantía y Costo

| tipo_garantia | ¿Quién paga la reparación? | Opciones de resolución típicas |
|---|---|---|
| PROPIA | La empresa absorbe el 100% | REPARAR_GRATIS, REEMPLAZO, NOTA_CREDITO |
| TRANSFERIDA_PROVEEDOR | El proveedor cubre | DEVOLUCION_PROVEEDOR, REPARAR_GRATIS (si proveedor aprueba) |
| MIXTA | Compartido según acuerdo | REPARAR_CON_COSTO, DEVOLUCION_PROVEEDOR parcial |
| SIN_GARANTIA | El cliente paga | REPARAR_CON_COSTO, ninguna otra |

### Reglas de Negocio

1. Todo RMA requiere evidencia fotográfica del producto al ingreso (mínimo 1 foto).
2. La firma digital del cliente es obligatoria al recibir y al devolver el producto.
3. Las mermas siempre requieren aprobación de un usuario con rol GERENTE o superior.
4. Un mismo producto puede tener máximo 1 RMA activo (estado != CERRADO) a la vez.
5. La resolución DEVOLUCION_PROVEEDOR solo aplica si existe `garantia_proveedor_id` vinculado o el tipo es TRANSFERIDA_PROVEEDOR o MIXTA.
6. El número de RMA es único por empresa y se genera secuencialmente con prefijo configurable.
7. El tiempo máximo de diagnóstico y resolución son configurables por establecimiento en `config_rma`. Pasado el límite, el sistema genera alertas automáticas.

### Integración con SRI

Las resoluciones que generan documentos electrónicos no los crean directamente; los delegan a los módulos Core correspondientes:
- **NOTA_CREDITO** → `module_bus.ventas.emitir_nc()` → NC tipo 04 procesada por módulo Facturación vía pipeline SRI.
- **DEVOLUCION_PROVEEDOR** → `module_bus.compras.devolucion_proveedor()` → puede generar liquidación de compra tipo 03 si aplica.
