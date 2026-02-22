# Control de Calidad (QC)


## Descripcion Funcional

Modulo de control de calidad integrado con inventario que permite definir checklists de inspeccion, ejecutar inspecciones en puntos clave del flujo logistico, y gestionar lotes en cuarentena.

**Puntos de inspeccion:**

1. **Recepcion (Incoming QC):** Al recibir mercaderia de un proveedor, antes de ubicar en stock disponible. La mercaderia permanece en ubicacion tipo RECEPCION o CALIDAD hasta pasar inspeccion.

2. **Produccion (In-Process QC):** Al completar una orden de ensamblaje, antes de ingresar el producto terminado a inventario.

3. **Despacho (Outgoing QC):** Antes de enviar mercaderia al cliente (picking completado). Aplica para productos que requieren verificacion final (electronica, equipos calibrados).

**Tipos de checks:**

- **Pass/Fail:** Inspeccion binaria (pasa o no pasa). Ej: "Empaque intacto?", "Etiqueta correcta?"
- **Numerico (rango):** Valor numerico con min/max aceptable. Ej: "Peso neto entre 98g y 102g", "Voltaje entre 118V y 122V"
- **Texto:** Observacion libre. Ej: "Descripcion del defecto encontrado"
- **Foto/Evidencia:** Adjuntar foto como evidencia (Supabase Storage). Ej: "Foto del dano", "Foto del lote recibido"

**Flujo de acciones post-inspeccion:**

- **Aceptar:** Producto pasa a ubicacion de stock normal (INTERNA). Lote queda DISPONIBLE.
- **Rechazar:** Producto se mueve a ubicacion MERMA o se devuelve al proveedor. Se genera merma o nota de credito.
- **Cuarentena:** Producto permanece en ubicacion CALIDAD. Lote se marca como CUARENTENA (nuevo estado). Requiere segunda inspeccion o decision.
- **Devolver:** Se genera solicitud de devolucion al proveedor. Se vincula con flujo de compras (nota de credito proveedor).
- **Reprocesar:** Se genera orden de ensamblaje/reproceso para corregir el defecto.

**Certificados de calidad:** Documento adjunto al lote que certifica que paso inspeccion, con detalle de los checks realizados, valores obtenidos, inspector y fecha. Puede generarse como PDF y adjuntarse al despacho.

## Modelo de Datos SQL

```sql
-- ============================================================
-- ENUMS para QC
-- ============================================================

CREATE TYPE qc_punto_inspeccion AS ENUM ('RECEPCION', 'PRODUCCION', 'DESPACHO');
CREATE TYPE qc_tipo_check AS ENUM ('PASS_FAIL', 'NUMERICO', 'TEXTO', 'FOTO');
CREATE TYPE qc_resultado AS ENUM ('PENDIENTE', 'APROBADA', 'RECHAZADA', 'CUARENTENA');
CREATE TYPE qc_accion AS ENUM ('ACEPTAR', 'RECHAZAR', 'CUARENTENA', 'DEVOLVER', 'REPROCESAR');

-- Agregar estado CUARENTENA a series_lotes
-- (El campo estado existente es VARCHAR(20), ya soporta nuevos valores)
-- Valores posibles: DISPONIBLE, RESERVADO, VENDIDO, DEVUELTO, VENCIDO, CUARENTENA

-- ============================================================
-- PLANTILLAS DE INSPECCION
-- ============================================================

CREATE TABLE qc_plantillas (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  nombre          VARCHAR(100) NOT NULL,
  punto_inspeccion qc_punto_inspeccion NOT NULL,
  -- Aplica a:
  producto_id     UUID REFERENCES productos(id),      -- NULL = aplica a categoria
  categoria_id    UUID REFERENCES categorias(id),      -- NULL = aplica a producto
  proveedor_id    UUID REFERENCES contactos(id),       -- NULL = todos los proveedores
  -- Config
  muestreo_porcentaje DECIMAL(5,2) DEFAULT 100,       -- % de unidades a inspeccionar (100=todas)
  activo          BOOLEAN DEFAULT true,
  version         INTEGER DEFAULT 1,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(empresa_id, nombre)
);

ALTER TABLE qc_plantillas ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON qc_plantillas
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- ============================================================
-- CHECKS (lineas de la plantilla)
-- ============================================================

CREATE TABLE qc_plantilla_checks (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  plantilla_id    UUID NOT NULL REFERENCES qc_plantillas(id) ON DELETE CASCADE,
  nombre          VARCHAR(200) NOT NULL,               -- "Empaque intacto?", "Peso neto"
  descripcion     TEXT,                                 -- Instrucciones para el inspector
  tipo_check      qc_tipo_check NOT NULL,
  -- Para NUMERICO:
  valor_minimo    DECIMAL(18,6),
  valor_maximo    DECIMAL(18,6),
  unidad_medida   VARCHAR(20),                         -- "g", "cm", "V", etc.
  -- Config
  es_critico      BOOLEAN DEFAULT false,               -- Si falla un critico -> rechazo automatico
  orden           INTEGER DEFAULT 0,
  activo          BOOLEAN DEFAULT true
);

ALTER TABLE qc_plantilla_checks ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON qc_plantilla_checks
  FOR ALL TO authenticated
  USING (plantilla_id IN (
    SELECT id FROM qc_plantillas WHERE empresa_id = (SELECT private.get_empresa_id())
  ));

-- ============================================================
-- INSPECCIONES (instancias ejecutadas)
-- ============================================================

CREATE TABLE qc_inspecciones (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  plantilla_id    UUID NOT NULL REFERENCES qc_plantillas(id),
  punto_inspeccion qc_punto_inspeccion NOT NULL,
  -- Documento origen
  documento_tipo  VARCHAR(30) NOT NULL,                -- 'RECEPCION_COMPRA', 'ORDEN_ENSAMBLAJE', 'ORDEN_PICKING'
  documento_id    UUID NOT NULL,
  -- Producto/lote inspeccionado
  producto_id     UUID NOT NULL REFERENCES productos(id),
  lote_id         UUID REFERENCES series_lotes(id),
  bodega_id       UUID NOT NULL REFERENCES bodegas(id),
  cantidad_inspeccionada DECIMAL(18,6) NOT NULL,
  -- Resultado
  resultado       qc_resultado NOT NULL DEFAULT 'PENDIENTE',
  accion_tomada   qc_accion,
  -- Responsables
  inspector_id    UUID NOT NULL REFERENCES auth.users(id),
  aprobador_id    UUID REFERENCES auth.users(id),
  -- Fechas
  fecha_inspeccion TIMESTAMPTZ DEFAULT NOW(),
  fecha_resolucion TIMESTAMPTZ,
  -- Vinculacion
  merma_id        UUID REFERENCES mermas_inventario(id),       -- Si se rechazo como merma
  devolucion_id   UUID,                                         -- Si se devolvio al proveedor
  orden_reproceso_id UUID REFERENCES ordenes_ensamblaje(id),   -- Si se reproceso
  -- Meta
  notas           TEXT,
  certificado_url TEXT,                                         -- URL del PDF certificado en Storage
  version         INTEGER DEFAULT 1,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE qc_inspecciones ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON qc_inspecciones
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE INDEX idx_qc_inspecciones_doc ON qc_inspecciones(documento_tipo, documento_id);
CREATE INDEX idx_qc_inspecciones_producto ON qc_inspecciones(producto_id, resultado);
CREATE INDEX idx_qc_inspecciones_proveedor ON qc_inspecciones(empresa_id, fecha_inspeccion);

-- ============================================================
-- RESULTADOS DE CADA CHECK
-- ============================================================

CREATE TABLE qc_inspeccion_resultados (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  inspeccion_id   UUID NOT NULL REFERENCES qc_inspecciones(id) ON DELETE CASCADE,
  check_id        UUID NOT NULL REFERENCES qc_plantilla_checks(id),
  -- Resultado segun tipo:
  valor_pass_fail BOOLEAN,                             -- Para PASS_FAIL
  valor_numerico  DECIMAL(18,6),                       -- Para NUMERICO
  valor_texto     TEXT,                                 -- Para TEXTO
  foto_url        TEXT,                                 -- Para FOTO (Supabase Storage)
  -- Evaluacion
  cumple          BOOLEAN,                             -- Calculado: paso el check?
  es_critico      BOOLEAN DEFAULT false,               -- Copiado del check para historico
  notas           TEXT
);

ALTER TABLE qc_inspeccion_resultados ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON qc_inspeccion_resultados
  FOR ALL TO authenticated
  USING (inspeccion_id IN (
    SELECT id FROM qc_inspecciones WHERE empresa_id = (SELECT private.get_empresa_id())
  ));
```

## Funciones PostgreSQL

```sql
-- ============================================================
-- DETERMINAR PLANTILLA QC APLICABLE
-- ============================================================

CREATE OR REPLACE FUNCTION qc_get_applicable_template(
  p_empresa_id UUID,
  p_producto_id UUID,
  p_punto qc_punto_inspeccion,
  p_proveedor_id UUID DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER STABLE AS $$
DECLARE
  v_categoria_id UUID;
  v_template_id UUID;
BEGIN
  SELECT categoria_id INTO v_categoria_id FROM productos WHERE id = p_producto_id;

  -- Buscar por prioridad: producto+proveedor > producto > categoria+proveedor > categoria > global
  SELECT id INTO v_template_id
  FROM qc_plantillas
  WHERE empresa_id = p_empresa_id
    AND punto_inspeccion = p_punto
    AND activo = true
    AND (
      (producto_id = p_producto_id AND proveedor_id = p_proveedor_id)
      OR (producto_id = p_producto_id AND proveedor_id IS NULL)
      OR (categoria_id = v_categoria_id AND proveedor_id = p_proveedor_id)
      OR (categoria_id = v_categoria_id AND proveedor_id IS NULL)
      OR (producto_id IS NULL AND categoria_id IS NULL)
    )
  ORDER BY
    CASE
      WHEN producto_id IS NOT NULL AND proveedor_id IS NOT NULL THEN 1
      WHEN producto_id IS NOT NULL THEN 2
      WHEN categoria_id IS NOT NULL AND proveedor_id IS NOT NULL THEN 3
      WHEN categoria_id IS NOT NULL THEN 4
      ELSE 5
    END
  LIMIT 1;

  RETURN v_template_id;
END;
$$;

-- ============================================================
-- CREAR INSPECCION DESDE RECEPCION DE COMPRA
-- ============================================================

CREATE OR REPLACE FUNCTION qc_create_inspection(
  p_empresa_id UUID,
  p_producto_id UUID,
  p_punto qc_punto_inspeccion,
  p_documento_tipo VARCHAR(30),
  p_documento_id UUID,
  p_lote_id UUID,
  p_bodega_id UUID,
  p_cantidad DECIMAL(18,6),
  p_proveedor_id UUID DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_plantilla_id UUID;
  v_inspeccion_id UUID;
BEGIN
  v_plantilla_id := qc_get_applicable_template(
    p_empresa_id, p_producto_id, p_punto, p_proveedor_id
  );

  IF v_plantilla_id IS NULL THEN
    RETURN NULL;  -- Sin plantilla QC, no se requiere inspeccion
  END IF;

  INSERT INTO qc_inspecciones (
    empresa_id, plantilla_id, punto_inspeccion,
    documento_tipo, documento_id, producto_id, lote_id,
    bodega_id, cantidad_inspeccionada, inspector_id
  ) VALUES (
    p_empresa_id, v_plantilla_id, p_punto,
    p_documento_tipo, p_documento_id, p_producto_id, p_lote_id,
    p_bodega_id, p_cantidad, auth.uid()
  ) RETURNING id INTO v_inspeccion_id;

  RETURN v_inspeccion_id;
END;
$$;

-- ============================================================
-- REGISTRAR RESULTADO DE INSPECCION
-- ============================================================

CREATE OR REPLACE FUNCTION qc_submit_inspection(
  p_inspeccion_id UUID,
  p_resultados JSONB,  -- [{check_id, valor_pass_fail, valor_numerico, valor_texto, foto_url, notas}]
  p_accion qc_accion
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_inspeccion RECORD;
  v_resultado JSONB;
  v_check RECORD;
  v_cumple BOOLEAN;
  v_tiene_critico_fallido BOOLEAN := false;
  v_total_checks INTEGER := 0;
  v_checks_ok INTEGER := 0;
BEGIN
  SELECT * INTO v_inspeccion FROM qc_inspecciones WHERE id = p_inspeccion_id;
  IF v_inspeccion IS NULL THEN
    RAISE EXCEPTION 'Inspeccion no encontrada';
  END IF;
  IF v_inspeccion.resultado != 'PENDIENTE' THEN
    RAISE EXCEPTION 'Inspeccion ya resuelta';
  END IF;

  -- Procesar cada resultado
  FOR v_resultado IN SELECT * FROM jsonb_array_elements(p_resultados) LOOP
    SELECT * INTO v_check
    FROM qc_plantilla_checks
    WHERE id = (v_resultado->>'check_id')::UUID;

    -- Evaluar cumplimiento segun tipo
    v_cumple := CASE v_check.tipo_check
      WHEN 'PASS_FAIL' THEN (v_resultado->>'valor_pass_fail')::BOOLEAN
      WHEN 'NUMERICO' THEN
        (v_resultado->>'valor_numerico')::DECIMAL
          BETWEEN COALESCE(v_check.valor_minimo, '-Infinity'::DECIMAL)
              AND COALESCE(v_check.valor_maximo, 'Infinity'::DECIMAL)
      WHEN 'TEXTO' THEN true  -- Texto siempre cumple (informativo)
      WHEN 'FOTO' THEN true   -- Foto siempre cumple (evidencia)
    END;

    v_total_checks := v_total_checks + 1;
    IF v_cumple THEN v_checks_ok := v_checks_ok + 1; END IF;
    IF NOT v_cumple AND v_check.es_critico THEN
      v_tiene_critico_fallido := true;
    END IF;

    INSERT INTO qc_inspeccion_resultados (
      inspeccion_id, check_id, valor_pass_fail, valor_numerico,
      valor_texto, foto_url, cumple, es_critico, notas
    ) VALUES (
      p_inspeccion_id, v_check.id,
      (v_resultado->>'valor_pass_fail')::BOOLEAN,
      (v_resultado->>'valor_numerico')::DECIMAL,
      v_resultado->>'valor_texto',
      v_resultado->>'foto_url',
      v_cumple, v_check.es_critico,
      v_resultado->>'notas'
    );
  END LOOP;

  -- Determinar resultado global
  UPDATE qc_inspecciones SET
    resultado = CASE
      WHEN p_accion = 'ACEPTAR' AND NOT v_tiene_critico_fallido THEN 'APROBADA'
      WHEN p_accion = 'CUARENTENA' THEN 'CUARENTENA'
      ELSE 'RECHAZADA'
    END,
    accion_tomada = p_accion,
    fecha_resolucion = NOW(),
    aprobador_id = auth.uid()
  WHERE id = p_inspeccion_id;

  -- Ejecutar accion sobre el lote
  IF v_inspeccion.lote_id IS NOT NULL THEN
    CASE p_accion
      WHEN 'ACEPTAR' THEN
        UPDATE series_lotes SET estado = 'DISPONIBLE'
        WHERE id = v_inspeccion.lote_id;
      WHEN 'CUARENTENA' THEN
        UPDATE series_lotes SET estado = 'CUARENTENA'
        WHERE id = v_inspeccion.lote_id;
      WHEN 'RECHAZAR', 'DEVOLVER' THEN
        UPDATE series_lotes SET estado = 'RECHAZADO'
        WHERE id = v_inspeccion.lote_id;
      ELSE NULL;
    END CASE;
  END IF;

  RETURN jsonb_build_object(
    'inspeccion_id', p_inspeccion_id,
    'total_checks', v_total_checks,
    'checks_ok', v_checks_ok,
    'checks_fallidos', v_total_checks - v_checks_ok,
    'critico_fallido', v_tiene_critico_fallido,
    'accion', p_accion,
    'resultado', CASE
      WHEN p_accion = 'ACEPTAR' AND NOT v_tiene_critico_fallido THEN 'APROBADA'
      WHEN p_accion = 'CUARENTENA' THEN 'CUARENTENA'
      ELSE 'RECHAZADA'
    END
  );
END;
$$;
```

## Triggers

```sql
-- Trigger: al recibir mercaderia, crear inspeccion QC si aplica
CREATE OR REPLACE FUNCTION trg_qc_on_reception()
RETURNS TRIGGER AS $$
DECLARE
  v_inspeccion_id UUID;
BEGIN
  -- Solo para movimientos tipo INGRESO vinculados a recepcion de compra
  IF NEW.tipo_movimiento = 'INGRESO' AND NEW.documento_tipo IN ('RECEPCION_OC', '01', '03') THEN
    v_inspeccion_id := qc_create_inspection(
      NEW.empresa_id, NEW.producto_id, 'RECEPCION',
      COALESCE(NEW.documento_tipo, 'RECEPCION_OC'), NEW.documento_id,
      NEW.serie_lote_id, NEW.bodega_id,
      NEW.cantidad
    );

    -- Si se creo inspeccion, mover lote a CUARENTENA hasta inspeccionar
    IF v_inspeccion_id IS NOT NULL AND NEW.serie_lote_id IS NOT NULL THEN
      UPDATE series_lotes SET estado = 'CUARENTENA'
      WHERE id = NEW.serie_lote_id;
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_kardex_qc_reception
  AFTER INSERT ON kardex
  FOR EACH ROW EXECUTE FUNCTION trg_qc_on_reception();

-- Alerta automatica cuando inspeccion tiene checks criticos fallidos
CREATE OR REPLACE FUNCTION trg_qc_alert_critical()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.cumple = false AND NEW.es_critico = true THEN
    -- Insertar notificacion via infraestructura existente
    INSERT INTO notificaciones (
      empresa_id, tipo, titulo, mensaje, nivel, referencia_tipo, referencia_id
    )
    SELECT
      qi.empresa_id, 'QC_CRITICO',
      'Check critico fallido en inspeccion',
      'Producto: ' || p.nombre || ' - Check: ' || qpc.nombre,
      'ALTA', 'qc_inspecciones', qi.id
    FROM qc_inspecciones qi
    JOIN productos p ON p.id = qi.producto_id
    JOIN qc_plantilla_checks qpc ON qpc.id = NEW.check_id
    WHERE qi.id = NEW.inspeccion_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_qc_critical_alert
  AFTER INSERT ON qc_inspeccion_resultados
  FOR EACH ROW EXECUTE FUNCTION trg_qc_alert_critical();
```

## Vistas

```sql
-- Vista: Tasa de rechazo por proveedor
CREATE OR REPLACE VIEW v_qc_tasa_rechazo_proveedor AS
SELECT
  qi.empresa_id,
  k.documento_id AS orden_compra_id,
  c.id AS proveedor_id,
  c.nombre AS proveedor_nombre,
  COUNT(*) AS total_inspecciones,
  COUNT(CASE WHEN qi.resultado = 'APROBADA' THEN 1 END) AS aprobadas,
  COUNT(CASE WHEN qi.resultado = 'RECHAZADA' THEN 1 END) AS rechazadas,
  COUNT(CASE WHEN qi.resultado = 'CUARENTENA' THEN 1 END) AS en_cuarentena,
  ROUND(
    COUNT(CASE WHEN qi.resultado = 'RECHAZADA' THEN 1 END)::DECIMAL
    / NULLIF(COUNT(*), 0) * 100, 2
  ) AS tasa_rechazo_pct,
  MIN(qi.fecha_inspeccion) AS primera_inspeccion,
  MAX(qi.fecha_inspeccion) AS ultima_inspeccion
FROM qc_inspecciones qi
LEFT JOIN kardex k ON k.id = qi.documento_id
LEFT JOIN contactos c ON c.id = k.documento_id  -- Simplificado; en practica se vincula via OC
WHERE qi.punto_inspeccion = 'RECEPCION'
GROUP BY qi.empresa_id, k.documento_id, c.id, c.nombre;

-- Vista: Lotes en cuarentena
CREATE OR REPLACE VIEW v_qc_lotes_cuarentena AS
SELECT
  sl.empresa_id,
  sl.id AS lote_id,
  sl.numero AS lote_numero,
  p.nombre AS producto_nombre,
  p.sku,
  b.nombre AS bodega_nombre,
  sl.cantidad,
  sl.fecha_ingreso,
  qi.id AS inspeccion_id,
  qi.fecha_inspeccion,
  qi.inspector_id,
  EXTRACT(DAY FROM NOW() - qi.fecha_inspeccion) AS dias_en_cuarentena
FROM series_lotes sl
JOIN productos p ON p.id = sl.producto_id
JOIN bodegas b ON b.id = sl.bodega_id
LEFT JOIN qc_inspecciones qi ON qi.lote_id = sl.id AND qi.resultado = 'CUARENTENA'
WHERE sl.estado = 'CUARENTENA';

-- Vista: Tendencia de calidad mensual
CREATE OR REPLACE VIEW v_qc_tendencia_mensual AS
SELECT
  qi.empresa_id,
  DATE_TRUNC('month', qi.fecha_inspeccion) AS mes,
  qi.punto_inspeccion,
  COUNT(*) AS total,
  COUNT(CASE WHEN qi.resultado = 'APROBADA' THEN 1 END) AS aprobadas,
  COUNT(CASE WHEN qi.resultado = 'RECHAZADA' THEN 1 END) AS rechazadas,
  ROUND(
    COUNT(CASE WHEN qi.resultado = 'APROBADA' THEN 1 END)::DECIMAL
    / NULLIF(COUNT(*), 0) * 100, 2
  ) AS tasa_aprobacion_pct
FROM qc_inspecciones qi
WHERE qi.resultado != 'PENDIENTE'
GROUP BY qi.empresa_id, DATE_TRUNC('month', qi.fecha_inspeccion), qi.punto_inspeccion
ORDER BY mes DESC;
```

## Integracion Module Service Bus

```sql
-- BUS: Verificar si un producto requiere inspeccion QC
CREATE OR REPLACE FUNCTION module_bus.requires_qc_inspection(
  p_empresa_id UUID,
  p_producto_id UUID,
  p_punto qc_punto_inspeccion,
  p_proveedor_id UUID DEFAULT NULL
) RETURNS module_bus.bus_response
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_result module_bus.bus_response;
  v_plantilla_id UUID;
BEGIN
  IF NOT module_bus.is_module_active(p_empresa_id, 'inventario') THEN
    v_result := (false, 'module_inactive', 'inventario',
      jsonb_build_object('requires_qc', false));
    RETURN v_result;
  END IF;

  v_plantilla_id := qc_get_applicable_template(
    p_empresa_id, p_producto_id, p_punto, p_proveedor_id
  );

  v_result := (true, null, 'inventario',
    jsonb_build_object(
      'requires_qc', v_plantilla_id IS NOT NULL,
      'plantilla_id', v_plantilla_id
    ));
  RETURN v_result;
END;
$$;
```

## RLS Policies

```sql
-- Ya definidas inline en la creacion de tablas (ver 23.2.2)
-- Patron: empresa_id directo o via join a tabla padre con empresa_id
```

## Flujo UI/UX

```
PANTALLA: Inventario > Calidad > Plantillas de Inspeccion

[Lista Plantillas] (SfDataGrid)
  Columnas: Nombre | Punto | Producto/Categoria | Proveedor | Checks | Muestreo% | Activo
  Acciones: + Nueva Plantilla

[Formulario Plantilla]
  Cabecera: Nombre | Punto (Recepcion/Produccion/Despacho) | Producto | Categoria | Proveedor | Muestreo%
  Checks (SfDataGrid editable):
    Nombre check | Tipo (Pass/Fail, Numerico, Texto, Foto) | Min | Max | Unidad | Critico?
  Preview: Mockup de como se vera el formulario de inspeccion en movil

---

PANTALLA: Inventario > Calidad > Inspecciones

[Lista Inspecciones] (SfDataGrid)
  Columnas: # | Fecha | Producto | Lote | Punto | Inspector | Resultado | Accion
  Filtros: resultado (pendiente/aprobada/rechazada/cuarentena), punto, fecha
  Badge: N inspecciones pendientes

[Formulario Inspeccion] (optimizado para tablet/movil)
  Cabecera (read-only): Producto | Lote | Bodega | Cantidad | Documento origen
  Lista de checks (cards):
    Card por check:
      [Nombre del check + instrucciones]
      [Input segun tipo: switch, slider+number, textarea, boton camara]
      [Indicador verde/rojo de cumplimiento]
  Barra inferior sticky:
    [Aceptar] [Cuarentena] [Rechazar] [Devolver] [Reprocesar]

---

PANTALLA: Inventario > Calidad > Reportes

  Tab 1: Tasa de rechazo por proveedor (SfCartesianChart barras)
  Tab 2: Tendencia mensual de calidad (SfCartesianChart linea)
  Tab 3: Lotes en cuarentena (SfDataGrid con dias en cuarentena)
  Tab 4: Detalle de inspecciones con filtros avanzados

[Responsive]
  COMPACT: Formulario inspeccion en cards verticales (ideal tablet bodega)
  MEDIUM: Lista + detalle side-by-side
  EXPANDED/LARGE: Dashboard QC completo con graficos
```

---

