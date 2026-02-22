# Módulo de Proyectos

Gestión de proyectos internos y para clientes: fases, tareas, hitos, registro de tiempo (timesheets), control de gastos y materiales, presupuesto vs. costo real y rentabilidad. Puede vincularse a Órdenes de Venta y consume inventario vía Module Service Bus.

> **Módulo Auxiliar #18 — Requiere: Inventario (#6), opcionalmente Ventas (#5) y Contabilidad (#8)**
>
> Los materiales se consumen usando `module_bus.inventario.consume_stock()`. La facturación por horas se genera con `module_bus.facturacion.create_invoice()`. Los asientos de costo se crean con `module_bus.contabilidad.create_journal_entry()`. Si algún módulo Core no está activo, la llamada devuelve NO-OP.

---

## Navegación

```
proyectos/
  ├── listado/                    # SfDataGrid con filtros (estado, tipo, cliente, responsable)
  ├── nuevo/                      # Formulario proyecto: datos generales + fases iniciales
  ├── detalle/                    # Dashboard de proyecto individual (avance, presupuesto, equipo)
  │     ├── fases/                # Listado y gestión de fases del proyecto
  │     ├── tareas/               # Vista Kanban + Gantt (SfCartesianChart)
  │     │     ├── kanban/         # Columnas por estado / fase; drag-and-drop, WIP
  │     │     └── gantt/          # Diagrama Gantt con dependencias y ruta crítica
  │     ├── timesheets/           # Hojas de tiempo por empleado + aprobación
  │     ├── gastos/               # Gastos del proyecto (viáticos, subcontrato, otro)
  │     ├── materiales/           # Materiales planificados vs. consumidos
  │     └── rentabilidad/         # Presupuesto vs. costo real + margen
  ├── mis-tareas/                 # Vista personal: tareas asignadas al usuario activo
  ├── timesheets/
  │     ├── registro/             # Registrar horas (semana actual, selección tarea)
  │     └── aprobacion/           # Aprobación masiva de timesheets (manager/PM)
  └── reportes/
        ├── gantt-empresa/        # Gantt de todos los proyectos activos
        ├── ocupacion-equipo/     # Horas por empleado vs. capacidad (período)
        ├── presupuesto-vs-real/  # Desviaciones por proyecto/fase/tarea
        ├── rentabilidad/         # Ingresos vs. costos por proyecto
        └── horas-facturables/    # Timesheets aprobados pendientes de facturar
```

---

## Modelo de Datos

### Proyectos

```sql
CREATE TABLE proyectos (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  codigo                VARCHAR(20) NOT NULL,               -- PROY-2026-001
  nombre                VARCHAR(200) NOT NULL,
  descripcion           TEXT,
  -- Vínculos
  cliente_id            UUID REFERENCES contactos(id),      -- NULL si proyecto interno
  orden_venta_id        UUID REFERENCES ordenes_venta(id),  -- Proyecto generado desde OV
  responsable_id        UUID NOT NULL REFERENCES auth.users(id),
  -- Clasificación
  tipo                  VARCHAR(10) NOT NULL DEFAULT 'CLIENTE',
    -- INTERNO: sin cliente ni OV (mejora interna, I+D)
    -- CLIENTE: vinculado a contacto, puede tener OV
    -- MIXTO:   parte interna + parte facturable al cliente
  -- Tipo de facturación (solo para tipo CLIENTE/MIXTO)
  tipo_facturacion      VARCHAR(10) DEFAULT 'FIJO',
    -- FIJO:    monto acordado en OV, sin relación con horas reales
    -- HORAS:   tarifa_hora × horas aprobadas (timesheets)
    -- HITOS:   factura por cada hito completado
  tarifa_hora           DECIMAL(14,2),                      -- Solo tipo_facturacion=HORAS
  -- Estado
  estado                VARCHAR(10) NOT NULL DEFAULT 'BORRADOR',
    -- BORRADOR → ACTIVO → EN_PAUSA → CERRADO / CANCELADO
  -- Fechas
  fecha_inicio          DATE NOT NULL,
  fecha_fin_estimada    DATE,
  fecha_fin_real        DATE,
  -- Presupuesto
  presupuesto_horas     DECIMAL(14,2) DEFAULT 0,            -- Horas totales presupuestadas
  presupuesto_costo     DECIMAL(14,2) DEFAULT 0,            -- Costo total presupuestado
  porcentaje_avance     DECIMAL(5,2)  DEFAULT 0,            -- Calculado automáticamente
  -- Contabilidad
  centro_costo_id       UUID REFERENCES centros_costo(id),  -- Para asientos de costo
  -- Auditoría
  version               INT NOT NULL DEFAULT 1,             -- Bloqueo optimista
  created_at            TIMESTAMPTZ DEFAULT now(),
  updated_at            TIMESTAMPTZ DEFAULT now(),
  UNIQUE(empresa_id, codigo)
);
```

### Fases del Proyecto

```sql
CREATE TABLE fases_proyecto (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  proyecto_id           UUID NOT NULL REFERENCES proyectos(id) ON DELETE CASCADE,
  nombre                VARCHAR(200) NOT NULL,
  descripcion           TEXT,
  orden                 INT NOT NULL DEFAULT 1,             -- Orden de ejecución
  -- Fechas
  fecha_inicio          DATE,
  fecha_fin             DATE,
  -- Estado
  estado                VARCHAR(15) DEFAULT 'PENDIENTE',
    -- PENDIENTE / EN_PROGRESO / COMPLETADA
  porcentaje_avance     DECIMAL(5,2) DEFAULT 0,
  -- Auditoría
  created_at            TIMESTAMPTZ DEFAULT now(),
  updated_at            TIMESTAMPTZ DEFAULT now()
);
```

### Tareas del Proyecto

```sql
CREATE TABLE tareas_proyecto (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  proyecto_id           UUID NOT NULL REFERENCES proyectos(id) ON DELETE CASCADE,
  fase_id               UUID REFERENCES fases_proyecto(id),
  padre_id              UUID REFERENCES tareas_proyecto(id), -- Subtareas (jerarquía)
  -- Descripción
  nombre                VARCHAR(200) NOT NULL,
  descripcion           TEXT,
  -- Clasificación
  tipo                  VARCHAR(10) NOT NULL DEFAULT 'TAREA',
    -- TAREA / HITO / ENTREGA
  prioridad             VARCHAR(10) DEFAULT 'MEDIA',
    -- BAJA / MEDIA / ALTA / CRITICA
  -- Estado
  estado                VARCHAR(15) DEFAULT 'PENDIENTE',
    -- PENDIENTE / EN_PROGRESO / REVISION / COMPLETADA / CANCELADA
  -- Responsable
  asignado_a            UUID REFERENCES auth.users(id),
  -- Fechas
  fecha_inicio          DATE,
  fecha_fin_estimada    DATE NOT NULL,
  fecha_fin_real        DATE,
  -- Esfuerzo
  horas_estimadas       DECIMAL(8,2) DEFAULT 0,
  -- Kanban
  columna_kanban_id     UUID REFERENCES kanban_columnas(id),
  orden_columna         INT DEFAULT 0,
  -- Hito: factura vinculada (si tipo_facturacion = HITOS)
  factura_id            UUID,                               -- soft ref -> facturas
  -- Auditoría
  version               INT NOT NULL DEFAULT 1,
  created_at            TIMESTAMPTZ DEFAULT now(),
  updated_at            TIMESTAMPTZ DEFAULT now()
);

-- Dependencias entre tareas (para Gantt y ruta crítica)
CREATE TABLE tarea_dependencias (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  tarea_id              UUID NOT NULL REFERENCES tareas_proyecto(id) ON DELETE CASCADE,
  depende_de_tarea_id   UUID NOT NULL REFERENCES tareas_proyecto(id),
  tipo                  VARCHAR(2) DEFAULT 'FS',
    -- FS = Finish-to-Start (más común)
    -- FF = Finish-to-Finish
    -- SS = Start-to-Start
    -- SF = Start-to-Finish
  lag_dias              INT DEFAULT 0,                      -- Días de retraso/adelanto
  UNIQUE(tarea_id, depende_de_tarea_id)
);

-- Columnas Kanban por proyecto
CREATE TABLE kanban_columnas (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  proyecto_id           UUID NOT NULL REFERENCES proyectos(id) ON DELETE CASCADE,
  nombre                VARCHAR(100) NOT NULL,              -- 'Backlog', 'En progreso', 'QA', 'Listo'
  orden                 INT NOT NULL DEFAULT 1,
  limite_wip            INT,                               -- NULL = sin límite
  color                 VARCHAR(7)                         -- #RRGGBB
);
```

### Timesheets (Hojas de Tiempo)

```sql
CREATE TABLE timesheets (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  proyecto_id           UUID NOT NULL REFERENCES proyectos(id),
  tarea_id              UUID REFERENCES tareas_proyecto(id),
  empleado_id           UUID NOT NULL REFERENCES empleados(id),
  -- Registro
  fecha                 DATE NOT NULL DEFAULT CURRENT_DATE,
  horas                 DECIMAL(8,2) NOT NULL,             -- Horas trabajadas (ej: 2.5 = 2h30m)
  descripcion           TEXT,                              -- Descripción del trabajo realizado
  -- Costo
  costo_hora            DECIMAL(14,2),                     -- (sueldo + aporte patronal) / horas_mes
  costo_total           DECIMAL(14,2),                     -- horas * costo_hora
  -- Facturación
  facturable            BOOLEAN DEFAULT true,
  facturado             BOOLEAN DEFAULT false,
  factura_id            UUID,                              -- soft ref -> facturas (cuando se factura)
  -- Estado de aprobación
  estado                VARCHAR(10) DEFAULT 'BORRADOR',
    -- BORRADOR / APROBADO / RECHAZADO / FACTURADO
  aprobado_por          UUID REFERENCES auth.users(id),
  aprobado_at           TIMESTAMPTZ,
  -- Auditoría
  version               INT NOT NULL DEFAULT 1,
  created_at            TIMESTAMPTZ DEFAULT now(),
  updated_at            TIMESTAMPTZ DEFAULT now()
);
```

### Gastos del Proyecto

```sql
CREATE TABLE gastos_proyecto (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  proyecto_id           UUID NOT NULL REFERENCES proyectos(id),
  tarea_id              UUID REFERENCES tareas_proyecto(id),
  empleado_id           UUID REFERENCES empleados(id),     -- Quien incurrió el gasto
  -- Clasificación
  tipo                  VARCHAR(15) NOT NULL DEFAULT 'OTRO',
    -- MATERIAL / TRANSPORTE / VIATICOS / SUBCONTRATO / OTRO
  descripcion           TEXT NOT NULL,
  -- Montos
  cantidad              DECIMAL(14,6) DEFAULT 1,
  precio_unitario       DECIMAL(14,2) NOT NULL,
  total                 DECIMAL(14,2) GENERATED ALWAYS AS (cantidad * precio_unitario) STORED,
  -- Respaldo
  factura_proveedor_id  UUID,                             -- soft ref -> facturas_proveedor
  reembolsable          BOOLEAN DEFAULT false,             -- Si el cliente debe reembolsar
  -- Estado
  estado                VARCHAR(10) DEFAULT 'PENDIENTE',
    -- PENDIENTE / APROBADO / RECHAZADO
  aprobado_por          UUID REFERENCES auth.users(id),
  aprobado_at           TIMESTAMPTZ,
  -- Auditoría
  version               INT NOT NULL DEFAULT 1,
  fecha                 DATE NOT NULL DEFAULT CURRENT_DATE,
  created_at            TIMESTAMPTZ DEFAULT now(),
  updated_at            TIMESTAMPTZ DEFAULT now()
);
```

### Materiales del Proyecto

```sql
CREATE TABLE materiales_proyecto (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  proyecto_id           UUID NOT NULL REFERENCES proyectos(id),
  tarea_id              UUID REFERENCES tareas_proyecto(id),
  -- Producto
  producto_id           UUID NOT NULL REFERENCES productos(id),
  bodega_id             UUID REFERENCES bodegas(id),       -- Bodega de origen
  -- Cantidades
  cantidad_planificada  DECIMAL(14,6) NOT NULL DEFAULT 0,
  cantidad_usada        DECIMAL(14,6) DEFAULT 0,
  -- Estado
  estado                VARCHAR(15) DEFAULT 'PLANIFICADO',
    -- PLANIFICADO / RESERVADO / CONSUMIDO / CANCELADO
  -- Costos
  costo_unitario        DECIMAL(14,2),                     -- Costo al momento del consumo
  costo_total           DECIMAL(14,2),                     -- cantidad_usada * costo_unitario
  -- Referencia al movimiento de inventario generado
  movimiento_inventario_id UUID,                           -- soft ref -> movimientos_inventario
  -- Auditoría
  created_at            TIMESTAMPTZ DEFAULT now(),
  updated_at            TIMESTAMPTZ DEFAULT now()
);
```

---

## RPCs (Funciones PostgreSQL)

### get_project_dashboard(p_proyecto_id)

Vista consolidada de un proyecto con métricas clave para el panel principal.

```sql
CREATE OR REPLACE FUNCTION get_project_dashboard(p_proyecto_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_empresa_id UUID := (SELECT private.get_empresa_id());
  v_result     JSONB;
BEGIN
  SELECT jsonb_build_object(
    -- Avance general
    'avance_porcentaje',    p.porcentaje_avance,
    'estado',               p.estado,
    'dias_restantes',       (p.fecha_fin_estimada - CURRENT_DATE),
    -- Tareas
    'tareas_total',         COUNT(t.id),
    'tareas_completadas',   COUNT(t.id) FILTER (WHERE t.estado = 'COMPLETADA'),
    'tareas_en_progreso',   COUNT(t.id) FILTER (WHERE t.estado = 'EN_PROGRESO'),
    'tareas_pendientes',    COUNT(t.id) FILTER (WHERE t.estado = 'PENDIENTE'),
    'tareas_vencidas',      COUNT(t.id) FILTER (
                              WHERE t.fecha_fin_estimada < CURRENT_DATE
                                AND t.estado NOT IN ('COMPLETADA', 'CANCELADA')
                            ),
    -- Horas
    'horas_presupuestadas', p.presupuesto_horas,
    'horas_registradas',    COALESCE(SUM(ts.horas), 0),
    'horas_aprobadas',      COALESCE(SUM(ts.horas) FILTER (WHERE ts.estado = 'APROBADO'), 0),
    'horas_facturables',    COALESCE(SUM(ts.horas) FILTER (
                              WHERE ts.estado = 'APROBADO'
                                AND ts.facturable = true
                                AND ts.facturado = false
                            ), 0),
    -- Presupuesto vs real
    'presupuesto_costo',    p.presupuesto_costo,
    'costo_horas',          COALESCE(SUM(ts.costo_total), 0),
    'costo_gastos',         COALESCE((
                              SELECT SUM(g.total) FROM gastos_proyecto g
                              WHERE g.proyecto_id = p.id AND g.estado = 'APROBADO'
                            ), 0),
    'costo_materiales',     COALESCE((
                              SELECT SUM(m.costo_total) FROM materiales_proyecto m
                              WHERE m.proyecto_id = p.id AND m.estado = 'CONSUMIDO'
                            ), 0),
    -- Equipo
    'distribucion_equipo',  (
      SELECT jsonb_agg(jsonb_build_object(
        'empleado_id', ts2.empleado_id,
        'horas',       SUM(ts2.horas),
        'tareas',      COUNT(DISTINCT ts2.tarea_id)
      ))
      FROM timesheets ts2
      WHERE ts2.proyecto_id = p.id
      GROUP BY ts2.empleado_id
    )
  )
  INTO v_result
  FROM proyectos p
  LEFT JOIN tareas_proyecto t ON t.proyecto_id = p.id
  LEFT JOIN timesheets ts ON ts.proyecto_id = p.id
  WHERE p.id = p_proyecto_id
    AND p.empresa_id = v_empresa_id
  GROUP BY p.id;

  RETURN v_result;
END;
$$;
```

### get_project_profitability(p_proyecto_id)

Cálculo detallado de rentabilidad: ingresos facturados vs. costos reales con margen.

```sql
CREATE OR REPLACE FUNCTION get_project_profitability(p_proyecto_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_empresa_id  UUID := (SELECT private.get_empresa_id());
  v_ingresos    DECIMAL(14,2);
  v_costo_horas DECIMAL(14,2);
  v_costo_gastos DECIMAL(14,2);
  v_costo_materiales DECIMAL(14,2);
  v_costo_total DECIMAL(14,2);
  v_margen      DECIMAL(14,2);
  v_margen_pct  DECIMAL(5,2);
BEGIN
  -- Validar acceso
  PERFORM 1 FROM proyectos
  WHERE id = p_proyecto_id AND empresa_id = v_empresa_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Proyecto no encontrado'; END IF;

  -- Ingresos facturados (facturas con referencia a este proyecto)
  SELECT COALESCE(SUM(f.total), 0)
  INTO v_ingresos
  FROM timesheets ts
  JOIN facturas f ON f.id = ts.factura_id     -- soft ref
  WHERE ts.proyecto_id = p_proyecto_id
    AND ts.empresa_id = v_empresa_id
    AND ts.facturado = true;

  -- Costo mano de obra (timesheets aprobados)
  SELECT COALESCE(SUM(costo_total), 0)
  INTO v_costo_horas
  FROM timesheets
  WHERE proyecto_id = p_proyecto_id
    AND empresa_id = v_empresa_id
    AND estado IN ('APROBADO', 'FACTURADO');

  -- Costo gastos aprobados
  SELECT COALESCE(SUM(total), 0)
  INTO v_costo_gastos
  FROM gastos_proyecto
  WHERE proyecto_id = p_proyecto_id
    AND empresa_id = v_empresa_id
    AND estado = 'APROBADO';

  -- Costo materiales consumidos
  SELECT COALESCE(SUM(costo_total), 0)
  INTO v_costo_materiales
  FROM materiales_proyecto
  WHERE proyecto_id = p_proyecto_id
    AND empresa_id = v_empresa_id
    AND estado = 'CONSUMIDO';

  v_costo_total := v_costo_horas + v_costo_gastos + v_costo_materiales;
  v_margen      := v_ingresos - v_costo_total;
  v_margen_pct  := CASE WHEN v_ingresos > 0
                     THEN ROUND((v_margen / v_ingresos) * 100, 2)
                     ELSE 0
                   END;

  RETURN jsonb_build_object(
    'ingresos_facturados',   v_ingresos,
    'costo_mano_obra',       v_costo_horas,
    'costo_gastos',          v_costo_gastos,
    'costo_materiales',      v_costo_materiales,
    'costo_total',           v_costo_total,
    'margen_bruto',          v_margen,
    'margen_porcentaje',     v_margen_pct,
    'es_rentable',           (v_margen >= 0)
  );
END;
$$;
```

### get_gantt_data(p_proyecto_id)

Datos estructurados para renderizar el diagrama Gantt con dependencias.

```sql
CREATE OR REPLACE FUNCTION get_gantt_data(p_proyecto_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_empresa_id UUID := (SELECT private.get_empresa_id());
BEGIN
  -- Validar acceso
  PERFORM 1 FROM proyectos WHERE id = p_proyecto_id AND empresa_id = v_empresa_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Proyecto no encontrado'; END IF;

  RETURN jsonb_build_object(
    'proyecto', (
      SELECT jsonb_build_object('id', id, 'nombre', nombre,
                                'fecha_inicio', fecha_inicio,
                                'fecha_fin_estimada', fecha_fin_estimada)
      FROM proyectos WHERE id = p_proyecto_id
    ),
    'fases', (
      SELECT jsonb_agg(jsonb_build_object(
        'id', f.id, 'nombre', f.nombre, 'orden', f.orden,
        'fecha_inicio', f.fecha_inicio, 'fecha_fin', f.fecha_fin,
        'estado', f.estado, 'porcentaje_avance', f.porcentaje_avance
      ) ORDER BY f.orden)
      FROM fases_proyecto f WHERE f.proyecto_id = p_proyecto_id
    ),
    'tareas', (
      SELECT jsonb_agg(jsonb_build_object(
        'id',               t.id,
        'nombre',           t.nombre,
        'tipo',             t.tipo,
        'fase_id',          t.fase_id,
        'padre_id',         t.padre_id,
        'asignado_a',       t.asignado_a,
        'fecha_inicio',     t.fecha_inicio,
        'fecha_fin',        t.fecha_fin_estimada,
        'fecha_fin_real',   t.fecha_fin_real,
        'horas_estimadas',  t.horas_estimadas,
        'horas_reales',     COALESCE((
          SELECT SUM(ts.horas) FROM timesheets ts
          WHERE ts.tarea_id = t.id
        ), 0),
        'estado',           t.estado,
        'prioridad',        t.prioridad,
        'dependencias',     (
          SELECT jsonb_agg(jsonb_build_object(
            'depende_de', td.depende_de_tarea_id, 'tipo', td.tipo, 'lag', td.lag_dias
          ))
          FROM tarea_dependencias td WHERE td.tarea_id = t.id
        )
      ) ORDER BY t.fecha_inicio NULLS LAST)
      FROM tareas_proyecto t
      WHERE t.proyecto_id = p_proyecto_id
        AND t.tipo IN ('TAREA', 'HITO', 'ENTREGA')
    )
  );
END;
$$;
```

### log_timesheet(p_data)

Registra o actualiza una línea de hoja de tiempo para un empleado.

```sql
CREATE OR REPLACE FUNCTION log_timesheet(
  p_proyecto_id UUID,
  p_tarea_id    UUID,
  p_empleado_id UUID,
  p_fecha       DATE,
  p_horas       DECIMAL(8,2),
  p_descripcion TEXT,
  p_facturable  BOOLEAN DEFAULT true
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_empresa_id  UUID := (SELECT private.get_empresa_id());
  v_costo_hora  DECIMAL(14,2);
  v_ts_id       UUID;
BEGIN
  -- Validar proyecto activo
  PERFORM 1 FROM proyectos
  WHERE id = p_proyecto_id AND empresa_id = v_empresa_id AND estado = 'ACTIVO';
  IF NOT FOUND THEN RAISE EXCEPTION 'Proyecto no activo o no encontrado'; END IF;

  -- Calcular costo/hora del empleado: (sueldo_base + aporte_patronal) / horas_mes_contractual
  SELECT ROUND(
    (c.sueldo_base * 1.1154) / COALESCE(c.horas_mensuales, 160), 2
  )
  INTO v_costo_hora
  FROM contratos_empleado c
  WHERE c.empleado_id = p_empleado_id
    AND c.empresa_id = v_empresa_id
    AND c.estado = 'ACTIVO'
  ORDER BY c.fecha_inicio DESC
  LIMIT 1;

  INSERT INTO timesheets (
    empresa_id, proyecto_id, tarea_id, empleado_id,
    fecha, horas, descripcion, facturable,
    costo_hora, costo_total, estado
  ) VALUES (
    v_empresa_id, p_proyecto_id, p_tarea_id, p_empleado_id,
    p_fecha, p_horas, p_descripcion, p_facturable,
    v_costo_hora, ROUND(p_horas * COALESCE(v_costo_hora, 0), 2), 'BORRADOR'
  )
  RETURNING id INTO v_ts_id;

  RETURN v_ts_id;
END;
$$;
```

### get_project_company_dashboard(p_empresa_id)

Panel global de todos los proyectos activos de la empresa.

```sql
CREATE OR REPLACE FUNCTION get_project_company_dashboard(p_empresa_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_empresa_id UUID := (SELECT private.get_empresa_id());
BEGIN
  RETURN jsonb_build_object(
    'proyectos_activos',    (SELECT COUNT(*) FROM proyectos
                             WHERE empresa_id = v_empresa_id AND estado = 'ACTIVO'),
    'proyectos_en_pausa',   (SELECT COUNT(*) FROM proyectos
                             WHERE empresa_id = v_empresa_id AND estado = 'EN_PAUSA'),
    'proyectos_vencidos',   (SELECT COUNT(*) FROM proyectos
                             WHERE empresa_id = v_empresa_id
                               AND estado = 'ACTIVO'
                               AND fecha_fin_estimada < CURRENT_DATE),
    'horas_semana',         (SELECT COALESCE(SUM(horas), 0) FROM timesheets
                             WHERE empresa_id = v_empresa_id
                               AND fecha >= date_trunc('week', CURRENT_DATE)),
    'por_estado',           (
      SELECT jsonb_agg(jsonb_build_object('estado', estado, 'total', cnt))
      FROM (
        SELECT estado, COUNT(*) as cnt FROM proyectos
        WHERE empresa_id = v_empresa_id GROUP BY estado
      ) s
    ),
    'top_proyectos',        (
      SELECT jsonb_agg(jsonb_build_object(
        'id', p.id, 'nombre', p.nombre, 'avance', p.porcentaje_avance,
        'horas_registradas', COALESCE(SUM(ts.horas), 0)
      ))
      FROM proyectos p
      LEFT JOIN timesheets ts ON ts.proyecto_id = p.id
      WHERE p.empresa_id = v_empresa_id AND p.estado = 'ACTIVO'
      GROUP BY p.id ORDER BY p.porcentaje_avance DESC LIMIT 10
    )
  );
END;
$$;
```

### calculate_critical_path(p_proyecto_id)

Calcula la ruta crítica del proyecto usando las dependencias de tareas.

```sql
CREATE OR REPLACE FUNCTION calculate_critical_path(p_proyecto_id UUID)
RETURNS TABLE(tarea_id UUID, nombre VARCHAR, slack_dias INT, es_critica BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_empresa_id UUID := (SELECT private.get_empresa_id());
BEGIN
  -- Algoritmo simplificado: tareas sin slack son críticas
  -- El slack = fecha_fin_estimada - MAX(fecha_fin real de predecesoras + lag)
  RETURN QUERY
  WITH task_data AS (
    SELECT
      t.id,
      t.nombre,
      t.fecha_inicio,
      t.fecha_fin_estimada,
      COALESCE((
        SELECT MAX(t2.fecha_fin_estimada + (td.lag_dias || ' days')::INTERVAL)
        FROM tarea_dependencias td
        JOIN tareas_proyecto t2 ON t2.id = td.depende_de_tarea_id
        WHERE td.tarea_id = t.id
      )::DATE, t.fecha_inicio) AS early_start
    FROM tareas_proyecto t
    WHERE t.proyecto_id = p_proyecto_id
      AND t.empresa_id = v_empresa_id
      AND t.estado NOT IN ('CANCELADA', 'COMPLETADA')
  )
  SELECT
    td.id::UUID,
    td.nombre,
    GREATEST(0, td.fecha_fin_estimada - (td.early_start + (COALESCE(
      (SELECT EXTRACT(DAY FROM (fecha_fin_estimada - fecha_inicio))::INT FROM tareas_proyecto WHERE id = td.id), 1
    ) || ' days')::INTERVAL)::DATE) AS slack_dias,
    (td.fecha_fin_estimada = (td.early_start + (COALESCE(
      (SELECT EXTRACT(DAY FROM (fecha_fin_estimada - fecha_inicio))::INT FROM tareas_proyecto WHERE id = td.id), 1
    ) || ' days')::INTERVAL)::DATE) AS es_critica
  FROM task_data td;
END;
$$;
```

---

## Module Service Bus

### proyectos.create_from_sale_order(p_ov_id)

Crea automáticamente un proyecto cuando se confirma una Orden de Venta con tipo de entrega PROYECTO.

```sql
-- Schema: module_bus
CREATE OR REPLACE FUNCTION module_bus.proyectos_create_from_sale_order(
  p_ov_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, module_bus, private
AS $$
DECLARE
  v_empresa_id UUID := (SELECT private.get_empresa_id());
  v_modulo_activo BOOLEAN;
  v_proyecto_id UUID;
  v_ov RECORD;
BEGIN
  -- Verificar si el módulo Proyectos está activo para esta empresa
  SELECT activo INTO v_modulo_activo
  FROM modulos_empresa
  WHERE empresa_id = v_empresa_id
    AND modulo_codigo = 'proyectos';

  IF NOT COALESCE(v_modulo_activo, false) THEN
    RETURN NULL; -- NO-OP: módulo inactivo
  END IF;

  -- Obtener datos de la OV
  SELECT ov.*, c.nombre as cliente_nombre
  INTO v_ov
  FROM ordenes_venta ov
  JOIN contactos c ON c.id = ov.contacto_id
  WHERE ov.id = p_ov_id AND ov.empresa_id = v_empresa_id;

  IF NOT FOUND THEN RAISE EXCEPTION 'Orden de venta no encontrada'; END IF;

  -- Crear proyecto desde OV
  INSERT INTO proyectos (
    empresa_id, codigo, nombre, cliente_id, orden_venta_id,
    responsable_id, tipo, tipo_facturacion, fecha_inicio, estado
  ) VALUES (
    v_empresa_id,
    'PROY-' || TO_CHAR(NOW(), 'YYYY') || '-' || LPAD(nextval('seq_proyectos')::TEXT, 4, '0'),
    'Proyecto: ' || v_ov.cliente_nombre || ' - ' || v_ov.numero,
    v_ov.contacto_id,
    p_ov_id,
    v_ov.vendedor_id,
    'CLIENTE',
    'FIJO',
    CURRENT_DATE,
    'BORRADOR'
  )
  RETURNING id INTO v_proyecto_id;

  RETURN v_proyecto_id;
END;
$$;
```

### proyectos.consume_inventory(p_proyecto_id, p_materiales)

Consume materiales del inventario para un proyecto, generando movimientos y asientos contables.

```sql
CREATE OR REPLACE FUNCTION module_bus.proyectos_consume_inventory(
  p_proyecto_id UUID,
  p_materiales  JSONB   -- [{producto_id, cantidad, bodega_id, tarea_id}]
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, module_bus, private
AS $$
DECLARE
  v_empresa_id      UUID := (SELECT private.get_empresa_id());
  v_inventario_activo BOOLEAN;
  v_item            JSONB;
  v_mov_id          UUID;
  v_costo_unitario  DECIMAL(14,2);
  v_resultado       JSONB := '[]'::JSONB;
BEGIN
  -- Verificar módulo Inventario activo
  SELECT activo INTO v_inventario_activo
  FROM modulos_empresa
  WHERE empresa_id = v_empresa_id AND modulo_codigo = 'inventario';

  IF NOT COALESCE(v_inventario_activo, false) THEN
    RETURN jsonb_build_object('status', 'NOOP', 'motivo', 'modulo_inventario_inactivo');
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_materiales)
  LOOP
    -- Obtener costo promedio del producto
    SELECT costo INTO v_costo_unitario
    FROM productos
    WHERE id = (v_item->>'producto_id')::UUID
      AND empresa_id = v_empresa_id;

    -- Registrar el egreso de inventario via module_bus
    v_mov_id := module_bus.inventario_register_movement(
      v_empresa_id,
      (v_item->>'producto_id')::UUID,
      (v_item->>'bodega_id')::UUID,
      'EGRESO',
      (v_item->>'cantidad')::DECIMAL,
      'PROYECTO',
      p_proyecto_id
    );

    -- Actualizar materiales_proyecto
    UPDATE materiales_proyecto SET
      cantidad_usada           = (v_item->>'cantidad')::DECIMAL,
      estado                   = 'CONSUMIDO',
      costo_unitario           = v_costo_unitario,
      costo_total              = (v_item->>'cantidad')::DECIMAL * v_costo_unitario,
      movimiento_inventario_id = v_mov_id,
      updated_at               = now()
    WHERE proyecto_id = p_proyecto_id
      AND producto_id = (v_item->>'producto_id')::UUID
      AND tarea_id IS NOT DISTINCT FROM (v_item->>'tarea_id')::UUID;

    -- Asiento contable: Debe Gasto proyecto → Haber Inventario
    PERFORM module_bus.contabilidad_create_journal_entry(
      v_empresa_id,
      jsonb_build_object(
        'descripcion', 'Consumo materiales proyecto #' || p_proyecto_id,
        'lineas', jsonb_build_array(
          jsonb_build_object('tipo', 'DEBE', 'cuenta_codigo', '5.1.01',
                             'monto', (v_item->>'cantidad')::DECIMAL * v_costo_unitario,
                             'referencia', p_proyecto_id),
          jsonb_build_object('tipo', 'HABER', 'cuenta_codigo', '1.1.04',
                             'monto', (v_item->>'cantidad')::DECIMAL * v_costo_unitario,
                             'referencia', p_proyecto_id)
        )
      )
    );

    v_resultado := v_resultado || jsonb_build_object(
      'producto_id', v_item->>'producto_id',
      'movimiento_id', v_mov_id
    );
  END LOOP;

  RETURN jsonb_build_object('status', 'OK', 'movimientos', v_resultado);
END;
$$;
```

---

## Row Level Security (RLS)

```sql
-- proyectos
ALTER TABLE proyectos ENABLE ROW LEVEL SECURITY;
CREATE POLICY proyectos_empresa ON proyectos
  TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- fases_proyecto
ALTER TABLE fases_proyecto ENABLE ROW LEVEL SECURITY;
CREATE POLICY fases_proyecto_empresa ON fases_proyecto
  TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- tareas_proyecto
ALTER TABLE tareas_proyecto ENABLE ROW LEVEL SECURITY;
CREATE POLICY tareas_proyecto_empresa ON tareas_proyecto
  TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- tarea_dependencias
ALTER TABLE tarea_dependencias ENABLE ROW LEVEL SECURITY;
CREATE POLICY tarea_dependencias_empresa ON tarea_dependencias
  TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- kanban_columnas
ALTER TABLE kanban_columnas ENABLE ROW LEVEL SECURITY;
CREATE POLICY kanban_columnas_empresa ON kanban_columnas
  TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- timesheets
ALTER TABLE timesheets ENABLE ROW LEVEL SECURITY;
-- PM / Admin ven todos; empleado ve solo los suyos
CREATE POLICY timesheets_empresa ON timesheets
  TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- gastos_proyecto
ALTER TABLE gastos_proyecto ENABLE ROW LEVEL SECURITY;
CREATE POLICY gastos_proyecto_empresa ON gastos_proyecto
  TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- materiales_proyecto
ALTER TABLE materiales_proyecto ENABLE ROW LEVEL SECURITY;
CREATE POLICY materiales_proyecto_empresa ON materiales_proyecto
  TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));
```

---

## Índices

```sql
-- proyectos
CREATE INDEX idx_proyectos_empresa_estado    ON proyectos(empresa_id, estado);
CREATE INDEX idx_proyectos_cliente           ON proyectos(cliente_id) WHERE cliente_id IS NOT NULL;
CREATE INDEX idx_proyectos_orden_venta       ON proyectos(orden_venta_id) WHERE orden_venta_id IS NOT NULL;
CREATE INDEX idx_proyectos_responsable       ON proyectos(responsable_id);
CREATE INDEX idx_proyectos_fechas            ON proyectos(empresa_id, fecha_inicio, fecha_fin_estimada);

-- fases_proyecto
CREATE INDEX idx_fases_proyecto              ON fases_proyecto(proyecto_id, orden);

-- tareas_proyecto
CREATE INDEX idx_tareas_proyecto             ON tareas_proyecto(proyecto_id, estado);
CREATE INDEX idx_tareas_fase                 ON tareas_proyecto(fase_id) WHERE fase_id IS NOT NULL;
CREATE INDEX idx_tareas_asignado             ON tareas_proyecto(asignado_a) WHERE asignado_a IS NOT NULL;
CREATE INDEX idx_tareas_vencimiento          ON tareas_proyecto(fecha_fin_estimada, estado);

-- timesheets
CREATE INDEX idx_timesheets_proyecto         ON timesheets(proyecto_id, fecha);
CREATE INDEX idx_timesheets_empleado         ON timesheets(empleado_id, fecha);
CREATE INDEX idx_timesheets_tarea            ON timesheets(tarea_id) WHERE tarea_id IS NOT NULL;
CREATE INDEX idx_timesheets_estado           ON timesheets(empresa_id, estado);
CREATE INDEX idx_timesheets_facturables      ON timesheets(empresa_id, facturable, facturado)
  WHERE facturable = true AND facturado = false;

-- gastos_proyecto
CREATE INDEX idx_gastos_proyecto             ON gastos_proyecto(proyecto_id, estado);
CREATE INDEX idx_gastos_empleado             ON gastos_proyecto(empleado_id) WHERE empleado_id IS NOT NULL;

-- materiales_proyecto
CREATE INDEX idx_materiales_proyecto         ON materiales_proyecto(proyecto_id, estado);
CREATE INDEX idx_materiales_producto         ON materiales_proyecto(producto_id);
```

---

## Integraciones

### Proyectos → Ventas (Módulo Core #5)

```
OV confirmada con tipo_entrega = 'PROYECTO'
  → module_bus.proyectos_create_from_sale_order(ov_id)
  → Proyecto creado en estado BORRADOR
  → PM asigna fases y tareas

Facturación por hitos:
  → Al completar hito con tarea.tipo = 'HITO' y factura_id IS NULL
  → module_bus.facturacion.create_invoice({ orden_venta_id, hito_id })

Facturación por horas (tipo_facturacion = 'HORAS'):
  → Seleccionar timesheets aprobados + facturables + no facturados
  → module_bus.facturacion.create_invoice({ proyecto_id, timesheets: [...] })
  → Marcar timesheets como facturado = true, factura_id = id generado
```

### Proyectos → RRHH (Módulo Auxiliar #13)

```
Costo/hora de empleado:
  → Al registrar timesheet, calcular desde contrato activo:
     costo_hora = ROUND((sueldo_base * 1.1154) / horas_mensuales, 2)
     (1.1154 = factor de carga social: 11.15% aporte patronal IESS + 0.5% SECAP/SETEC)

Horas extras:
  → Los timesheets superan 8h/día → trigger notifica a RRHH para registro de HE

Disponibilidad equipo:
  → module_bus.rrhh_get_employee_availability(empleado_id, rango_fechas)
  → Cruza ausencias/vacaciones/contratos para validar asignación
```

### Proyectos → Inventario (Módulo Core #6)

```
Planificación de materiales:
  → Agregar materiales_proyecto con estado = 'PLANIFICADO'
  → PM puede reservar: module_bus.inventario_reserve_stock(producto_id, cantidad, ref)

Consumo de materiales:
  → module_bus.proyectos_consume_inventory(proyecto_id, materiales[])
  → Genera movimiento de egreso tipo 'CONSUMO_PROYECTO' en inventario
  → Actualiza materiales_proyecto.estado → 'CONSUMIDO'
  → Registra costo real del material

Devolucion de materiales sobrantes:
  → Movimiento de ingreso tipo 'DEVOLUCION_PROYECTO'
  → Actualiza cantidad_usada en materiales_proyecto
```

### Proyectos → Contabilidad (Módulo Core #8)

```
Asiento de costo de mano de obra (mensual o por aprobación de timesheet):
  Debe:   5.1.XX Costo mano de obra proyecto (centro_costo = proyecto)
  Haber:  2.1.XX Nómina por pagar

Asiento de consumo de materiales:
  Debe:   5.1.01 Costo materiales proyecto
  Haber:  1.1.04 Inventario (sale del almacén)

Asiento de gastos aprobados:
  Debe:   5.1.03 Gastos de proyecto
  Haber:  1.1.01 Caja o 2.1.01 CxP (según respaldo)

Reporte de rentabilidad por proyecto:
  → Utiliza centro_costo_id para filtrar asientos del proyecto
  → module_bus.contabilidad_get_cost_center_balance(centro_costo_id)
```

---

## Notificaciones Automáticas (Edge Function `check-project-alerts`)

Edge Function cron diario (`0 8 * * *`) que verifica alertas de proyectos:

```typescript
// Alertas que genera:
// 1. TAREA_VENCIDA: tarea.fecha_fin_estimada < TODAY AND estado NOT IN (COMPLETADA, CANCELADA)
//    → Notifica: tarea.asignado_a + proyecto.responsable_id
//
// 2. HITO_PROXIMO: hito.fecha_fin_estimada <= TODAY + 7 AND estado = 'PENDIENTE'
//    → Notifica: proyecto.responsable_id
//
// 3. PRESUPUESTO_CRITICO: (costo_real / presupuesto_costo) > 0.80
//    → Notifica: proyecto.responsable_id
//
// 4. SIN_ACTIVIDAD: proyecto ACTIVO sin timesheets en los últimos 5 días laborables
//    → Notifica: proyecto.responsable_id
//
// 5. PROYECTO_VENCIDO: proyecto.estado = 'ACTIVO' AND fecha_fin_estimada < TODAY
//    → Notifica: proyecto.responsable_id + gerencia
//
// Usa: module_bus.send_notification(empresa_id, destinatario_id, tipo, payload)
//      Respeta canales configurados del contacto (email/WhatsApp/Telegram)
```

---

## Pantalla Flutter: Registro de Tiempo (Timesheet)

```dart
// features/proyectos/screens/timesheets_screen.dart
// Vista semanal: columna por día (Lun-Dom), fila por proyecto/tarea
// Total horas día / total horas semana en pie de tabla
// Estado BORRADOR → APROBADO: botón "Enviar para aprobación"
// Acciones manager: aprobar/rechazar individual o masivo (checkbox)
// Integración con SfDataGrid para modo tablet/desktop
// Modo compacto (móvil): lista acordeón por proyecto
```

---

## Pantalla Flutter: Gantt (gantt_screen.dart)

```dart
// Renderizado con SfCartesianChart (Syncfusion)
// Eje X: fechas (zoom: semana/mes/trimestre)
// Eje Y: tareas agrupadas por fase (color de fase)
// Barra de progreso: % completado de la tarea
// Hitos: diamante (◆) sobre la línea de tiempo
// Dependencias: flechas de conexión (tipo FS/FF/SS/SF)
// Ruta crítica: resaltada en rojo (calculate_critical_path)
// Click en tarea → panel lateral con detalle + timesheets
// Drag de fechas en EXPANDED/LARGE → actualiza fecha_fin_estimada
```

---
