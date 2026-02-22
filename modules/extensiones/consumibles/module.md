# Módulo de Consumibles (Suministros)

Gestión de materiales de oficina, limpieza, suministros y cualquier insumo interno que NO se comercializa. Controla solicitudes por departamento, despachos desde bodega especializada, presupuesto mensual por área y consumo histórico. Los consumibles son productos con `tipo = 'CONSUMIBLE'` en la tabla `productos` de Inventario, pero tienen tablas propias de control, solicitudes y presupuesto.

> **Módulo Auxiliar #16 — Requiere: Inventario (#6), opcionalmente Contabilidad (#8) y RRHH (#13)**
>
> El stock se controla en `inventario_stock` (mismo mecanismo de Inventario). Los egresos se generan via `module_bus.inventario_register_movement()`. Los asientos contables de gasto se crean con `module_bus.contabilidad_create_journal_entry()`. Si un módulo Core no está activo, la llamada devuelve NO-OP.

---

## Navegación

```
consumibles/
  ├── catalogo/                   # Listado de consumibles (SfDataGrid con filtros)
  │     ├── nuevo/                # Crear consumible: nombre, categoría, UoM, mínimos
  │     └── detalle/              # Ficha: stock, historial movimientos, proveedor preferente
  ├── solicitudes/
  │     ├── listado/              # Todas las solicitudes con filtros (estado, área, periodo)
  │     ├── nueva/                # Formulario: seleccionar consumibles + cantidades + motivo
  │     └── detalle/              # Ver/aprobar/rechazar solicitud + líneas + historial estado
  ├── despachos/                  # Solicitudes aprobadas listas para despachar
  │     └── despachar/            # Registrar cantidades reales despachadas por línea
  ├── stock/                      # Stock actual por consumible y bodega
  │     └── ajuste/               # Ajuste de inventario (diferencias de conteo)
  ├── presupuestos/               # Presupuesto mensual por departamento/categoría
  │     └── configurar/           # Asignar monto mensual por área + año
  └── reportes/
        ├── consumo-departamento/ # Consumo por área (período, comparativo)
        ├── consumo-producto/     # Top consumidos (cantidad + costo)
        ├── presupuesto-vs-real/  # Presupuesto asignado vs. consumido por mes/área
        └── stock-minimo/         # Consumibles bajo punto de reorden
```

---

## Modelo de Datos

### Categorías de Consumibles

```sql
CREATE TABLE categorias_consumibles (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  nombre                VARCHAR(200) NOT NULL,              -- 'Útiles de Oficina', 'Limpieza'
  descripcion           TEXT,
  -- Contabilidad: cuenta de gasto por defecto para esta categoría
  cuenta_gasto_id       UUID REFERENCES cuentas_contables(id),
    -- Ej: 5.1.05 Suministros y Materiales de Oficina
    --     5.1.06 Materiales de Aseo y Limpieza
  -- Presupuesto mensual por defecto (puede sobreescribirse por departamento)
  presupuesto_mensual   DECIMAL(14,2) DEFAULT 0,
  activo                BOOLEAN DEFAULT true,
  created_at            TIMESTAMPTZ DEFAULT now(),
  updated_at            TIMESTAMPTZ DEFAULT now(),
  UNIQUE(empresa_id, nombre)
);
```

### Catálogo de Consumibles

```sql
CREATE TABLE consumibles (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  -- Los consumibles son productos tipo='CONSUMIBLE' en la tabla productos
  -- Esta tabla extiende esos productos con atributos propios del módulo
  producto_id           UUID NOT NULL REFERENCES productos(id),
    -- El producto base (tipo='CONSUMIBLE') ya controla stock en inventario_stock
  codigo                VARCHAR(50) NOT NULL,               -- Código interno del consumible
  nombre                VARCHAR(300) NOT NULL,              -- Nombre descriptivo
  descripcion           TEXT,
  categoria_id          UUID NOT NULL REFERENCES categorias_consumibles(id),
  -- Unidad de medida y stock
  unidad_medida         VARCHAR(30) NOT NULL DEFAULT 'UND', -- UND, RESMA, CAJA, LITRO, KG
  stock_minimo          DECIMAL(14,6) DEFAULT 0,
  stock_maximo          DECIMAL(14,6) DEFAULT 0,
  punto_reorden         DECIMAL(14,6) DEFAULT 0,
  -- Bodega dedicada a consumibles (distinta del almacén comercial)
  bodega_consumibles_id UUID REFERENCES bodegas(id),
  -- Proveedor preferente (para órdenes de compra de reposición)
  proveedor_preferente_id UUID REFERENCES contactos(id),
  precio_referencia     DECIMAL(14,2) DEFAULT 0,            -- Precio de referencia para presupuesto
  -- Estado
  activo                BOOLEAN DEFAULT true,
  created_at            TIMESTAMPTZ DEFAULT now(),
  updated_at            TIMESTAMPTZ DEFAULT now(),
  UNIQUE(empresa_id, codigo)
);
```

### Stock de Consumibles

```sql
-- Vista del stock actual de consumibles (usa inventario_stock del módulo Inventario)
-- Esta tabla es un snapshot local para consultas rápidas; la fuente de verdad
-- es inventario_stock del módulo Core de Inventario.
CREATE TABLE stock_consumibles (
  consumible_id         UUID NOT NULL REFERENCES consumibles(id) ON DELETE CASCADE,
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  bodega_id             UUID NOT NULL REFERENCES bodegas(id),
  cantidad_disponible   DECIMAL(14,6) DEFAULT 0,
  ultima_actualizacion  TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (consumible_id, bodega_id)
);
```

### Solicitudes de Consumibles

```sql
CREATE TABLE solicitudes_consumibles (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  -- Solicitante
  solicitante_id        UUID NOT NULL REFERENCES auth.users(id),
  departamento_id       UUID REFERENCES departamentos(id), -- Departamento del solicitante
  -- Estado
  estado                VARCHAR(15) DEFAULT 'PENDIENTE',
    -- PENDIENTE → APROBADA → DESPACHADA (total o parcial)
    -- PENDIENTE → RECHAZADA
    -- APROBADA  → CANCELADA (antes del despacho)
  -- Fechas
  fecha_solicitud       DATE NOT NULL DEFAULT CURRENT_DATE,
  fecha_necesidad       DATE,                              -- Cuándo se necesita para planificación
  fecha_aprobacion      TIMESTAMPTZ,
  fecha_despacho        TIMESTAMPTZ,
  -- Aprobación
  aprobado_por          UUID REFERENCES auth.users(id),
  nivel_aprobacion      INT DEFAULT 1,                     -- Nivel del aprobador que autorizó
  motivo_rechazo        TEXT,
  -- Costo estimado total de la solicitud
  costo_estimado        DECIMAL(14,2) DEFAULT 0,           -- Suma de (cantidad × precio_referencia)
  notas                 TEXT,
  -- Auditoría
  version               INT NOT NULL DEFAULT 1,
  created_at            TIMESTAMPTZ DEFAULT now(),
  updated_at            TIMESTAMPTZ DEFAULT now()
);

-- Líneas de la solicitud
CREATE TABLE solicitud_consumible_lineas (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  solicitud_id          UUID NOT NULL REFERENCES solicitudes_consumibles(id) ON DELETE CASCADE,
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  consumible_id         UUID NOT NULL REFERENCES consumibles(id),
  -- Cantidades
  cantidad_solicitada   DECIMAL(14,6) NOT NULL,
  cantidad_aprobada     DECIMAL(14,6),                     -- NULL = aún no aprobada
  cantidad_despachada   DECIMAL(14,6) DEFAULT 0,           -- Real despachada
  -- Motivo de uso (para trazabilidad)
  motivo                VARCHAR(300),                      -- 'Para capacitación Q1', 'Oficina 3er piso'
  -- Referencia al movimiento de inventario generado al despachar
  movimiento_inventario_id UUID,                           -- soft ref -> movimientos_inventario
  created_at            TIMESTAMPTZ DEFAULT now()
);
```

### Movimientos de Consumibles

```sql
CREATE TABLE movimientos_consumibles (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  consumible_id         UUID NOT NULL REFERENCES consumibles(id),
  tipo                  VARCHAR(15) NOT NULL,
    -- ENTRADA:    Ingreso de compra (OC proveedor aprobada)
    -- SALIDA:     Despacho por solicitud aprobada
    -- AJUSTE_MAS: Ajuste positivo (conteo físico)
    -- AJUSTE_MEN: Ajuste negativo (diferencia conteo)
    -- DEVOLUCION: Empleado devuelve consumible no utilizado
  cantidad              DECIMAL(14,6) NOT NULL,
  -- Referencias
  solicitud_id          UUID REFERENCES solicitudes_consumibles(id), -- Si es SALIDA/DEVOLUCION
  empleado_id           UUID REFERENCES empleados(id),    -- Empleado que recibe/devuelve
  bodega_id             UUID REFERENCES bodegas(id),      -- Bodega afectada
  -- Costo
  costo_unitario        DECIMAL(14,2),
  costo_total           DECIMAL(14,2),
  -- Metadata
  fecha                 DATE NOT NULL DEFAULT CURRENT_DATE,
  referencia            VARCHAR(100),                     -- Número OC, nota interna, etc.
  notas                 TEXT,
  -- Auditoría
  version               INT NOT NULL DEFAULT 1,
  created_at            TIMESTAMPTZ DEFAULT now()
);
```

### Presupuesto por Departamento

```sql
CREATE TABLE presupuestos_consumibles (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  departamento_id       UUID NOT NULL REFERENCES departamentos(id),
  categoria_id          UUID REFERENCES categorias_consumibles(id), -- NULL = todos
  anio                  INT NOT NULL,
  mes                   INT NOT NULL,                      -- 1-12
  monto_asignado        DECIMAL(14,2) NOT NULL DEFAULT 0,
  monto_consumido       DECIMAL(14,2) DEFAULT 0,           -- Acumulado de despachos del período
  created_at            TIMESTAMPTZ DEFAULT now(),
  updated_at            TIMESTAMPTZ DEFAULT now(),
  UNIQUE(empresa_id, departamento_id, categoria_id, anio, mes)
);

-- Niveles de aprobación por monto
CREATE TABLE niveles_aprobacion_consumibles (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  monto_hasta           DECIMAL(14,2) NOT NULL,            -- Umbral máximo para este nivel
  rol_aprobador         VARCHAR(100) NOT NULL,             -- Rol requerido ('JEFE_AREA', 'GERENTE', etc.)
  orden                 INT NOT NULL,                      -- 1=más bajo, N=más alto
  created_at            TIMESTAMPTZ DEFAULT now(),
  UNIQUE(empresa_id, orden)
);
-- Ejemplo configuración:
-- orden=1, monto_hasta=100,  rol='JEFE_AREA'    → hasta $100 aprueba el jefe directo
-- orden=2, monto_hasta=500,  rol='GERENTE'       → hasta $500 aprueba gerencia
-- orden=3, monto_hasta=9999, rol='DIRECTOR'      → montos mayores requieren dirección
```

---

## RPCs (Funciones PostgreSQL)

### get_consumibles_stock(p_empresa_id)

Retorna el stock actual de todos los consumibles con alertas de nivel mínimo.

```sql
CREATE OR REPLACE FUNCTION get_consumibles_stock(p_empresa_id UUID DEFAULT NULL)
RETURNS TABLE (
  consumible_id       UUID,
  codigo              VARCHAR,
  nombre              VARCHAR,
  categoria           VARCHAR,
  unidad_medida       VARCHAR,
  bodega_id           UUID,
  cantidad_disponible DECIMAL,
  stock_minimo        DECIMAL,
  punto_reorden       DECIMAL,
  alerta              VARCHAR   -- 'OK', 'BAJO_REORDEN', 'CRITICO'
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_empresa_id UUID := (SELECT private.get_empresa_id());
BEGIN
  RETURN QUERY
  SELECT
    c.id,
    c.codigo,
    c.nombre,
    cat.nombre,
    c.unidad_medida,
    sc.bodega_id,
    COALESCE(sc.cantidad_disponible, 0),
    c.stock_minimo,
    c.punto_reorden,
    CASE
      WHEN COALESCE(sc.cantidad_disponible, 0) <= c.stock_minimo  THEN 'CRITICO'
      WHEN COALESCE(sc.cantidad_disponible, 0) <= c.punto_reorden THEN 'BAJO_REORDEN'
      ELSE 'OK'
    END
  FROM consumibles c
  JOIN categorias_consumibles cat ON cat.id = c.categoria_id
  LEFT JOIN stock_consumibles sc  ON sc.consumible_id = c.id
  WHERE c.empresa_id = v_empresa_id
    AND c.activo = true
  ORDER BY
    CASE
      WHEN COALESCE(sc.cantidad_disponible, 0) <= c.stock_minimo  THEN 1
      WHEN COALESCE(sc.cantidad_disponible, 0) <= c.punto_reorden THEN 2
      ELSE 3
    END,
    cat.nombre, c.nombre;
END;
$$;
```

### request_consumibles(p_data)

Crea una solicitud de consumibles con validación de presupuesto departamental.

```sql
CREATE OR REPLACE FUNCTION request_consumibles(
  p_departamento_id UUID,
  p_fecha_necesidad DATE,
  p_notas           TEXT,
  p_lineas          JSONB  -- [{consumible_id, cantidad_solicitada, motivo}]
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_empresa_id    UUID := (SELECT private.get_empresa_id());
  v_solicitante   UUID := auth.uid();
  v_solicitud_id  UUID;
  v_costo_estimado DECIMAL(14,2) := 0;
  v_item          JSONB;
  v_precio_ref    DECIMAL(14,2);
  v_monto_asignado  DECIMAL(14,2);
  v_monto_consumido DECIMAL(14,2);
  v_nivel_aprobador INT;
BEGIN
  -- Calcular costo estimado total
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_lineas)
  LOOP
    SELECT precio_referencia INTO v_precio_ref
    FROM consumibles WHERE id = (v_item->>'consumible_id')::UUID AND empresa_id = v_empresa_id;

    v_costo_estimado := v_costo_estimado + (v_item->>'cantidad_solicitada')::DECIMAL * COALESCE(v_precio_ref, 0);
  END LOOP;

  -- Validar presupuesto del departamento para el mes actual
  SELECT monto_asignado, monto_consumido
  INTO v_monto_asignado, v_monto_consumido
  FROM presupuestos_consumibles
  WHERE empresa_id = v_empresa_id
    AND departamento_id = p_departamento_id
    AND categoria_id IS NULL
    AND anio = EXTRACT(YEAR FROM CURRENT_DATE)::INT
    AND mes  = EXTRACT(MONTH FROM CURRENT_DATE)::INT;

  IF FOUND AND (COALESCE(v_monto_consumido, 0) + v_costo_estimado) > v_monto_asignado THEN
    RAISE EXCEPTION 'Presupuesto de consumibles excedido para el departamento en este período. '
                    'Presupuesto: %, Consumido: %, Nueva solicitud: %',
                    v_monto_asignado, v_monto_consumido, v_costo_estimado
      USING ERRCODE = 'P0001';
  END IF;

  -- Determinar nivel de aprobación requerido por monto
  SELECT orden INTO v_nivel_aprobador
  FROM niveles_aprobacion_consumibles
  WHERE empresa_id = v_empresa_id AND monto_hasta >= v_costo_estimado
  ORDER BY orden ASC LIMIT 1;

  -- Crear solicitud
  INSERT INTO solicitudes_consumibles (
    empresa_id, solicitante_id, departamento_id, estado,
    fecha_necesidad, costo_estimado, notas, nivel_aprobacion
  ) VALUES (
    v_empresa_id, v_solicitante, p_departamento_id, 'PENDIENTE',
    p_fecha_necesidad, v_costo_estimado, p_notas, COALESCE(v_nivel_aprobador, 1)
  )
  RETURNING id INTO v_solicitud_id;

  -- Insertar líneas
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_lineas)
  LOOP
    INSERT INTO solicitud_consumible_lineas (
      solicitud_id, empresa_id, consumible_id,
      cantidad_solicitada, motivo
    ) VALUES (
      v_solicitud_id, v_empresa_id,
      (v_item->>'consumible_id')::UUID,
      (v_item->>'cantidad_solicitada')::DECIMAL,
      v_item->>'motivo'
    );
  END LOOP;

  RETURN v_solicitud_id;
END;
$$;
```

### dispatch_consumibles(p_solicitud_id, p_lineas_despacho)

Despacha materiales de la bodega: genera movimiento de inventario y asiento contable.

```sql
CREATE OR REPLACE FUNCTION dispatch_consumibles(
  p_solicitud_id    UUID,
  p_bodega_id       UUID,
  p_lineas_despacho JSONB  -- [{linea_id, cantidad_despachada}]
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_empresa_id    UUID := (SELECT private.get_empresa_id());
  v_solicitud     RECORD;
  v_linea         RECORD;
  v_item          JSONB;
  v_mov_id        UUID;
  v_consumible    RECORD;
  v_costo_total   DECIMAL(14,2) := 0;
  v_todo_despachado BOOLEAN := true;
BEGIN
  -- Validar solicitud aprobada
  SELECT s.*, d.nombre as departamento_nombre
  INTO v_solicitud
  FROM solicitudes_consumibles s
  LEFT JOIN departamentos d ON d.id = s.departamento_id
  WHERE s.id = p_solicitud_id AND s.empresa_id = v_empresa_id AND s.estado = 'APROBADA';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Solicitud no encontrada o no está en estado APROBADA';
  END IF;

  -- Procesar cada línea de despacho
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_lineas_despacho)
  LOOP
    SELECT scl.*, c.nombre as consumible_nombre, c.producto_id,
           c.categoria_id, c.precio_referencia
    INTO v_linea
    FROM solicitud_consumible_lineas scl
    JOIN consumibles c ON c.id = scl.consumible_id
    WHERE scl.id = (v_item->>'linea_id')::UUID
      AND scl.solicitud_id = p_solicitud_id;

    IF NOT FOUND THEN CONTINUE; END IF;

    -- Generar movimiento de inventario via Module Service Bus
    v_mov_id := module_bus.inventario_register_movement(
      v_empresa_id,
      v_linea.producto_id,
      p_bodega_id,
      'EGRESO',
      (v_item->>'cantidad_despachada')::DECIMAL,
      'CONSUMIBLE',
      p_solicitud_id
    );

    -- Registrar movimiento en tabla propia de consumibles
    INSERT INTO movimientos_consumibles (
      empresa_id, consumible_id, tipo, cantidad, solicitud_id,
      empleado_id, bodega_id, costo_unitario, costo_total, referencia
    )
    SELECT
      v_empresa_id,
      v_linea.consumible_id,
      'SALIDA',
      (v_item->>'cantidad_despachada')::DECIMAL,
      p_solicitud_id,
      v_solicitud.solicitante_id,
      p_bodega_id,
      v_linea.precio_referencia,
      (v_item->>'cantidad_despachada')::DECIMAL * COALESCE(v_linea.precio_referencia, 0),
      'SOL-' || p_solicitud_id::TEXT;

    -- Actualizar línea de solicitud
    UPDATE solicitud_consumible_lineas SET
      cantidad_despachada      = (v_item->>'cantidad_despachada')::DECIMAL,
      movimiento_inventario_id = v_mov_id
    WHERE id = (v_item->>'linea_id')::UUID;

    -- Actualizar stock local
    UPDATE stock_consumibles SET
      cantidad_disponible  = cantidad_disponible - (v_item->>'cantidad_despachada')::DECIMAL,
      ultima_actualizacion = now()
    WHERE consumible_id = v_linea.consumible_id AND bodega_id = p_bodega_id;

    v_costo_total := v_costo_total + (v_item->>'cantidad_despachada')::DECIMAL * COALESCE(v_linea.precio_referencia, 0);

    -- Verificar si todas las líneas están completamente despachadas
    IF (v_item->>'cantidad_despachada')::DECIMAL < v_linea.cantidad_aprobada THEN
      v_todo_despachado := false;
    END IF;
  END LOOP;

  -- Actualizar estado de la solicitud
  UPDATE solicitudes_consumibles SET
    estado        = CASE WHEN v_todo_despachado THEN 'DESPACHADA' ELSE 'PARCIALMENTE_DESPACHADA' END,
    fecha_despacho = now(),
    updated_at    = now()
  WHERE id = p_solicitud_id;

  -- Actualizar presupuesto consumido del departamento
  UPDATE presupuestos_consumibles SET
    monto_consumido = monto_consumido + v_costo_total,
    updated_at      = now()
  WHERE empresa_id = v_empresa_id
    AND departamento_id = v_solicitud.departamento_id
    AND categoria_id IS NULL
    AND anio = EXTRACT(YEAR FROM CURRENT_DATE)::INT
    AND mes  = EXTRACT(MONTH FROM CURRENT_DATE)::INT;

  -- Asiento contable: Debe Gasto → Haber Inventario Suministros (via module_bus)
  PERFORM module_bus.contabilidad_create_journal_entry(
    v_empresa_id,
    jsonb_build_object(
      'descripcion', 'Despacho consumibles - ' || v_solicitud.departamento_nombre,
      'referencia', 'SOL-' || p_solicitud_id::TEXT,
      'lineas', jsonb_build_array(
        jsonb_build_object(
          'tipo', 'DEBE',
          'cuenta_codigo', '5.1.05',   -- Suministros y Materiales
          'monto', v_costo_total,
          'referencia', p_solicitud_id
        ),
        jsonb_build_object(
          'tipo', 'HABER',
          'cuenta_codigo', '1.1.14',   -- Inventario Suministros
          'monto', v_costo_total,
          'referencia', p_solicitud_id
        )
      )
    )
  );

  RETURN jsonb_build_object(
    'solicitud_id',  p_solicitud_id,
    'estado',        CASE WHEN v_todo_despachado THEN 'DESPACHADA' ELSE 'PARCIALMENTE_DESPACHADA' END,
    'costo_total',   v_costo_total
  );
END;
$$;
```

### get_consumption_by_department(p_empresa_id, p_anio, p_mes)

Reporte de consumo mensual por departamento con comparación vs. presupuesto.

```sql
CREATE OR REPLACE FUNCTION get_consumption_by_department(
  p_anio INT DEFAULT NULL,
  p_mes  INT DEFAULT NULL
)
RETURNS TABLE (
  departamento_id   UUID,
  departamento      VARCHAR,
  categoria_id      UUID,
  categoria         VARCHAR,
  monto_asignado    DECIMAL,
  monto_consumido   DECIMAL,
  porcentaje_uso    DECIMAL,
  alerta            VARCHAR,   -- 'OK', 'ALERTA_80PCT', 'EXCEDIDO'
  solicitudes_count BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_empresa_id UUID := (SELECT private.get_empresa_id());
  v_anio       INT  := COALESCE(p_anio, EXTRACT(YEAR FROM CURRENT_DATE)::INT);
  v_mes        INT  := COALESCE(p_mes, EXTRACT(MONTH FROM CURRENT_DATE)::INT);
BEGIN
  RETURN QUERY
  SELECT
    d.id,
    d.nombre,
    cat.id,
    cat.nombre,
    COALESCE(pb.monto_asignado, 0),
    COALESCE(pb.monto_consumido, 0),
    CASE
      WHEN COALESCE(pb.monto_asignado, 0) = 0 THEN 0
      ELSE ROUND((pb.monto_consumido / pb.monto_asignado) * 100, 2)
    END,
    CASE
      WHEN COALESCE(pb.monto_asignado, 0) = 0 THEN 'SIN_PRESUPUESTO'
      WHEN pb.monto_consumido > pb.monto_asignado THEN 'EXCEDIDO'
      WHEN pb.monto_consumido >= pb.monto_asignado * 0.80 THEN 'ALERTA_80PCT'
      ELSE 'OK'
    END,
    COUNT(DISTINCT s.id)::BIGINT
  FROM departamentos d
  LEFT JOIN presupuestos_consumibles pb ON pb.departamento_id = d.id
    AND pb.empresa_id = v_empresa_id
    AND pb.anio = v_anio AND pb.mes = v_mes
  LEFT JOIN categorias_consumibles cat ON cat.id = pb.categoria_id
  LEFT JOIN solicitudes_consumibles s ON s.departamento_id = d.id
    AND s.empresa_id = v_empresa_id
    AND EXTRACT(YEAR FROM s.fecha_solicitud)::INT = v_anio
    AND EXTRACT(MONTH FROM s.fecha_solicitud)::INT = v_mes
    AND s.estado = 'DESPACHADA'
  WHERE d.empresa_id = v_empresa_id AND d.activo = true
  GROUP BY d.id, d.nombre, cat.id, cat.nombre, pb.monto_asignado, pb.monto_consumido
  ORDER BY d.nombre, cat.nombre;
END;
$$;
```

### check_consumable_reorder_levels()

Cron diario que verifica stock mínimo y genera notificaciones de reposición.

```sql
CREATE OR REPLACE FUNCTION check_consumable_reorder_levels()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
BEGIN
  -- Buscar consumibles cuyo stock actual <= punto_reorden
  PERFORM module_bus.send_notification(
    c.empresa_id,
    (SELECT responsable_id FROM bodegas WHERE id = c.bodega_consumibles_id),
    'CONSUMIBLE_BAJO_STOCK',
    jsonb_build_object(
      'consumible_id',    c.id,
      'consumible_nombre',c.nombre,
      'stock_actual',     COALESCE(sc.cantidad_disponible, 0),
      'stock_minimo',     c.stock_minimo,
      'punto_reorden',    c.punto_reorden,
      'unidad_medida',    c.unidad_medida,
      'proveedor_id',     c.proveedor_preferente_id
    )
  )
  FROM consumibles c
  LEFT JOIN stock_consumibles sc ON sc.consumible_id = c.id
    AND sc.bodega_id = c.bodega_consumibles_id
  WHERE c.activo = true
    AND c.punto_reorden > 0
    AND COALESCE(sc.cantidad_disponible, 0) <= c.punto_reorden;
END;
$$;
-- Programar con pg_cron: SELECT cron.schedule('0 8 * * *', 'SELECT check_consumable_reorder_levels()');
```

---

## Module Service Bus

### consumibles.consume_for_project(p_proyecto_id, p_items)

Permite que el módulo Proyectos consuma consumibles (distinto de inventario comercial) asignados a un proyecto.

```sql
CREATE OR REPLACE FUNCTION module_bus.consumibles_consume_for_project(
  p_proyecto_id UUID,
  p_items       JSONB  -- [{consumible_id, cantidad, tarea_id}]
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, module_bus, private
AS $$
DECLARE
  v_empresa_id        UUID := (SELECT private.get_empresa_id());
  v_modulo_activo     BOOLEAN;
  v_item              JSONB;
  v_consumible        RECORD;
  v_costo_total       DECIMAL(14,2) := 0;
  v_movimientos       JSONB := '[]'::JSONB;
BEGIN
  -- Verificar módulo Consumibles activo
  SELECT activo INTO v_modulo_activo
  FROM modulos_empresa
  WHERE empresa_id = v_empresa_id AND modulo_codigo = 'consumibles';

  IF NOT COALESCE(v_modulo_activo, false) THEN
    RETURN jsonb_build_object('status', 'NOOP', 'motivo', 'modulo_consumibles_inactivo');
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    SELECT c.*, sc.cantidad_disponible
    INTO v_consumible
    FROM consumibles c
    LEFT JOIN stock_consumibles sc ON sc.consumible_id = c.id
      AND sc.bodega_id = c.bodega_consumibles_id
    WHERE c.id = (v_item->>'consumible_id')::UUID
      AND c.empresa_id = v_empresa_id;

    IF NOT FOUND THEN CONTINUE; END IF;

    -- Verificar stock suficiente
    IF COALESCE(v_consumible.cantidad_disponible, 0) < (v_item->>'cantidad')::DECIMAL THEN
      RAISE EXCEPTION 'Stock insuficiente para consumible %. Disponible: %, Requerido: %',
        v_consumible.nombre, v_consumible.cantidad_disponible, (v_item->>'cantidad')::DECIMAL
        USING ERRCODE = 'P0001';
    END IF;

    -- Registrar movimiento de salida
    INSERT INTO movimientos_consumibles (
      empresa_id, consumible_id, tipo, cantidad, bodega_id,
      costo_unitario, costo_total, referencia, notas
    ) VALUES (
      v_empresa_id, v_consumible.id, 'SALIDA',
      (v_item->>'cantidad')::DECIMAL,
      v_consumible.bodega_consumibles_id,
      v_consumible.precio_referencia,
      (v_item->>'cantidad')::DECIMAL * COALESCE(v_consumible.precio_referencia, 0),
      'PROYECTO-' || p_proyecto_id::TEXT,
      'Consumo para proyecto'
    );

    -- Actualizar stock local
    UPDATE stock_consumibles SET
      cantidad_disponible  = cantidad_disponible - (v_item->>'cantidad')::DECIMAL,
      ultima_actualizacion = now()
    WHERE consumible_id = v_consumible.id
      AND bodega_id = v_consumible.bodega_consumibles_id;

    -- También descontar del inventario Core
    PERFORM module_bus.inventario_register_movement(
      v_empresa_id,
      v_consumible.producto_id,
      v_consumible.bodega_consumibles_id,
      'EGRESO',
      (v_item->>'cantidad')::DECIMAL,
      'PROYECTO',
      p_proyecto_id
    );

    v_costo_total := v_costo_total +
      (v_item->>'cantidad')::DECIMAL * COALESCE(v_consumible.precio_referencia, 0);

    v_movimientos := v_movimientos || jsonb_build_object(
      'consumible_id', v_consumible.id,
      'nombre',        v_consumible.nombre,
      'cantidad',      (v_item->>'cantidad')::DECIMAL
    );
  END LOOP;

  -- Asiento contable gasto de proyecto
  PERFORM module_bus.contabilidad_create_journal_entry(
    v_empresa_id,
    jsonb_build_object(
      'descripcion', 'Consumibles usados en proyecto #' || p_proyecto_id::TEXT,
      'lineas', jsonb_build_array(
        jsonb_build_object('tipo', 'DEBE',  'cuenta_codigo', '5.1.01', 'monto', v_costo_total),
        jsonb_build_object('tipo', 'HABER', 'cuenta_codigo', '1.1.14', 'monto', v_costo_total)
      )
    )
  );

  RETURN jsonb_build_object(
    'status',      'OK',
    'costo_total', v_costo_total,
    'movimientos', v_movimientos
  );
END;
$$;
```

---

## Row Level Security (RLS)

```sql
-- categorias_consumibles
ALTER TABLE categorias_consumibles ENABLE ROW LEVEL SECURITY;
CREATE POLICY categorias_consumibles_empresa ON categorias_consumibles
  TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- consumibles
ALTER TABLE consumibles ENABLE ROW LEVEL SECURITY;
CREATE POLICY consumibles_empresa ON consumibles
  TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- stock_consumibles
ALTER TABLE stock_consumibles ENABLE ROW LEVEL SECURITY;
CREATE POLICY stock_consumibles_empresa ON stock_consumibles
  TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- solicitudes_consumibles
ALTER TABLE solicitudes_consumibles ENABLE ROW LEVEL SECURITY;
-- Empleado ve sus propias solicitudes; aprobador/admin ve todas
CREATE POLICY solicitudes_consumibles_empresa ON solicitudes_consumibles
  TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- solicitud_consumible_lineas
ALTER TABLE solicitud_consumible_lineas ENABLE ROW LEVEL SECURITY;
CREATE POLICY solicitud_lineas_empresa ON solicitud_consumible_lineas
  TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- movimientos_consumibles
ALTER TABLE movimientos_consumibles ENABLE ROW LEVEL SECURITY;
CREATE POLICY movimientos_consumibles_empresa ON movimientos_consumibles
  TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- presupuestos_consumibles
ALTER TABLE presupuestos_consumibles ENABLE ROW LEVEL SECURITY;
CREATE POLICY presupuestos_consumibles_empresa ON presupuestos_consumibles
  TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- niveles_aprobacion_consumibles
ALTER TABLE niveles_aprobacion_consumibles ENABLE ROW LEVEL SECURITY;
CREATE POLICY niveles_aprobacion_empresa ON niveles_aprobacion_consumibles
  TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));
```

---

## Índices

```sql
-- consumibles
CREATE INDEX idx_consumibles_empresa_activo   ON consumibles(empresa_id, activo);
CREATE INDEX idx_consumibles_categoria        ON consumibles(categoria_id);
CREATE INDEX idx_consumibles_proveedor        ON consumibles(proveedor_preferente_id)
  WHERE proveedor_preferente_id IS NOT NULL;

-- stock_consumibles
CREATE INDEX idx_stock_consumibles_empresa    ON stock_consumibles(empresa_id);
CREATE INDEX idx_stock_consumibles_bajo_min   ON stock_consumibles(empresa_id, consumible_id)
  WHERE cantidad_disponible <= 0;

-- solicitudes_consumibles
CREATE INDEX idx_solicitudes_cons_empresa     ON solicitudes_consumibles(empresa_id, estado);
CREATE INDEX idx_solicitudes_cons_depto       ON solicitudes_consumibles(departamento_id, fecha_solicitud);
CREATE INDEX idx_solicitudes_cons_solicitante ON solicitudes_consumibles(solicitante_id);

-- solicitud_consumible_lineas
CREATE INDEX idx_solicitud_lineas_solicitud   ON solicitud_consumible_lineas(solicitud_id);
CREATE INDEX idx_solicitud_lineas_consumible  ON solicitud_consumible_lineas(consumible_id);

-- movimientos_consumibles
CREATE INDEX idx_movimientos_cons_empresa     ON movimientos_consumibles(empresa_id, fecha);
CREATE INDEX idx_movimientos_cons_consumible  ON movimientos_consumibles(consumible_id, fecha);
CREATE INDEX idx_movimientos_cons_solicitud   ON movimientos_consumibles(solicitud_id)
  WHERE solicitud_id IS NOT NULL;

-- presupuestos_consumibles
CREATE INDEX idx_presupuestos_cons_depto      ON presupuestos_consumibles(empresa_id, departamento_id, anio, mes);
```

---

## Integraciones

### Consumibles → Inventario (Módulo Core #6)

```
Los consumibles son productos tipo='CONSUMIBLE' en la tabla productos.
Su stock se refleja tanto en inventario_stock (Core) como en stock_consumibles (local).

Al despachar solicitud:
  → module_bus.inventario_register_movement('EGRESO', ...)
  → Genera movimiento de egreso sin generar documento SRI
  → Egreso tipo 'CONSUMIBLE' no aparece en ventas ni facturas

Al recibir reposición (vía OC):
  → Compras genera factura proveedor
  → Al confirmar recepción: module_bus.inventario_register_movement('INGRESO', ...)
  → Se actualiza stock_consumibles.cantidad_disponible

Diferencia con productos comercializables:
  - NO aparecen en POS ni en facturas de venta (es_venta = false)
  - NO tienen precio_venta (solo precio_referencia para presupuesto)
  - El egreso es interno, no genera documento SRI
  - Se controlan por solicitud/aprobación, no por venta
```

### Consumibles → Contabilidad (Módulo Core #8)

```
Al despachar solicitud (asiento automático):
  Debe:   5.1.05 Suministros y Materiales de Oficina (cuenta_gasto de la categoría)
  Haber:  1.1.14 Inventario Suministros y Materiales

Si la compra va directamente a gasto sin pasar por bodega:
  Debe:   5.1.05 Suministros y Materiales (gasto directo)
  Haber:  2.1.01 Cuentas por Pagar Proveedores

Todos los asientos se crean vía:
  → module_bus.contabilidad_create_journal_entry(empresa_id, payload)
  → NO-OP si módulo Contabilidad no está activo
```

### Consumibles → Proyectos (Módulo Auxiliar #18)

```
Un proyecto puede consumir consumibles directamente desde su bodega:
  → module_bus.consumibles_consume_for_project(proyecto_id, items[])
  → Genera movimiento SALIDA en movimientos_consumibles
  → Descuenta de stock_consumibles + inventario_stock
  → Registra asiento de gasto referenciando el proyecto
  → El costo aparece en el reporte de rentabilidad del proyecto
```

### Consumibles → RRHH (Módulo Auxiliar #13)

```
Solicitudes por empleado:
  → solicitante_id referencia auth.users, que se cruza con empleados.user_id
  → El reporte de consumo puede agruparse por empleado/área

Aprobación jerárquica:
  → El aprobador se determina por niveles_aprobacion_consumibles
  → Se notifica al aprobador correspondiente via module_bus.send_notification()
  → El rol del aprobador se verifica en la tabla de roles/permisos de RRHH
```

---

## Flujo Completo de una Solicitud

```
1. EMPLEADO crea solicitud:
   request_consumibles(departamento_id, fecha_necesidad, notas, lineas[])
   → Validación de presupuesto del departamento (EXCEPCIÓN si excede)
   → Se determina nivel de aprobación por monto
   → Estado: PENDIENTE

2. NOTIFICACIÓN al aprobador:
   module_bus.send_notification(empresa_id, aprobador_id, 'SOLICITUD_CONSUMIBLES', ...)
   → Email / WhatsApp según configuración del contacto

3. APROBADOR revisa y aprueba (o rechaza):
   UPDATE solicitudes_consumibles SET estado='APROBADA', aprobado_por=..., cantidad_aprobada=...
   → Si rechazada: estado='RECHAZADA', motivo_rechazo
   → Notificación al solicitante

4. BODEGUERO despacha:
   dispatch_consumibles(solicitud_id, bodega_id, lineas_despacho[])
   → Genera movimiento egreso en inventario
   → Registra movimiento en movimientos_consumibles
   → Actualiza stock_consumibles
   → Actualiza presupuesto_consumibles.monto_consumido
   → Genera asiento contable (Gasto / Inventario)
   → Estado: DESPACHADA (o PARCIALMENTE_DESPACHADA si hay pendientes)

5. NOTIFICACIÓN al solicitante:
   module_bus.send_notification(empresa_id, solicitante_id, 'CONSUMIBLES_DESPACHADOS', ...)
```

---

## Pantalla Flutter: Solicitud de Consumibles

```dart
// features/consumibles/screens/supply_request_screen.dart
//
// Formulario de solicitud con:
//   - Selector de consumibles (búsqueda + autocomplete desde catálogo)
//   - Campo cantidad con validación contra stock disponible
//   - Campo motivo por línea (obligatorio)
//   - Fecha de necesidad (calendar picker)
//   - Resumen: costo estimado vs. presupuesto disponible del departamento
//     → Barra de progreso: monto_consumido / monto_asignado (color según alerta)
//   - Botón "Enviar solicitud" → llama RPC request_consumibles()
//
// En breakpoint COMPACT (móvil): formulario vertical, líneas como lista
// En EXPANDED/LARGE (desktop): formulario en dos columnas con tabla de líneas SfDataGrid
```

---
