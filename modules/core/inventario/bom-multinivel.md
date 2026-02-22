# BOM Multi-nivel


## Descripcion Funcional

Evolucion del sistema BOM single-level existente (tablas `lista_materiales` y `lista_materiales_lineas`) para soportar sub-ensamblajes anidados. Un componente de una BOM puede a su vez tener su propia BOM, creando una estructura de arbol de N niveles.

**Capacidades nuevas:**

1. **Sub-ensamblajes anidados:** Un componente con `es_ensamblaje=true` referencia otra BOM. Al producir el producto padre, el sistema puede producir automaticamente los sub-ensamblajes o consumir stock existente del sub-ensamblaje.

2. **Explosion BOM plana:** Dada una BOM multi-nivel, devuelve la lista de TODOS los materiales finales (hojas del arbol) con cantidades acumuladas. Util para verificar disponibilidad total de materia prima.

3. **Explosion BOM estructurada:** Devuelve el arbol completo con niveles, mostrando la jerarquia de componentes y sub-ensamblajes. Util para planificacion y visualizacion.

4. **Implosion BOM (Where-Used):** Dado un componente, retorna todos los productos terminados que lo utilizan (directa o indirectamente). Util para analisis de impacto ante cambios de proveedor o discontinuacion.

5. **Costo acumulado multi-nivel:** Calcula el costo total de un producto sumando recursivamente los costos de todos sus componentes en todos los niveles.

6. **Versiones de BOM con vigencia temporal:** Una misma BOM puede tener multiples versiones. Solo una version esta activa en un momento dado (por rango de fechas). Permite planificar cambios de formulacion o composicion.

7. **Phantom BOMs:** Sub-ensamblajes que no se almacenan fisicamente. Al producir, el sistema "atraviesa" el phantom y consume directamente sus componentes. Ejemplo: un "kit de tornilleria" que nunca se ensambla como producto independiente, sino que sus tornillos se consumen directamente al ensamblar el producto padre.

**Casos de uso Ecuador:**

- Ensamblador de computadoras: PC tiene BOM con sub-ensamblaje "torre armada" que a su vez tiene CPU, RAM, disco, fuente.
- Fabrica de muebles: Mesa tiene BOM con sub-ensamblaje "estructura metalica" + "tablero MDF cortado".
- Procesadora de alimentos: Producto terminado con receta multi-nivel (salsa base que se usa en N productos finales).

## Modelo de Datos SQL

```sql
-- ============================================================
-- ENUMS para BOM Multi-nivel
-- ============================================================

CREATE TYPE bom_tipo AS ENUM ('NORMAL', 'PHANTOM');
-- NORMAL: BOM que produce un producto almacenable
-- PHANTOM: BOM cuyo producto NO se almacena; al producir el padre,
--          se "atraviesa" y se consumen directamente sus componentes

CREATE TYPE bom_version_estado AS ENUM ('BORRADOR', 'ACTIVA', 'OBSOLETA');

CREATE TYPE bom_linea_tipo AS ENUM ('COMPONENTE', 'SUB_ENSAMBLAJE');

-- ============================================================
-- VERSIONES DE BOM (evoluciona tabla lista_materiales existente)
-- ============================================================
-- Se agregan campos a la tabla existente lista_materiales

ALTER TABLE lista_materiales
  ADD COLUMN tipo bom_tipo NOT NULL DEFAULT 'NORMAL',
  ADD COLUMN version INTEGER NOT NULL DEFAULT 1,
  ADD COLUMN version_estado bom_version_estado NOT NULL DEFAULT 'ACTIVA',
  ADD COLUMN vigencia_desde DATE,
  ADD COLUMN vigencia_hasta DATE,
  ADD COLUMN version_notas TEXT,
  ADD COLUMN costo_mano_obra DECIMAL(14,2) DEFAULT 0,
  ADD COLUMN costo_indirecto DECIMAL(14,2) DEFAULT 0,
  ADD COLUMN created_at TIMESTAMPTZ DEFAULT NOW(),
  ADD COLUMN updated_at TIMESTAMPTZ DEFAULT NOW();

-- Constraint: solo 1 version ACTIVA por producto en un momento dado
-- (las vigencias no deben solaparse para el mismo producto)
CREATE UNIQUE INDEX idx_bom_version_activa
  ON lista_materiales(empresa_id, producto_id)
  WHERE version_estado = 'ACTIVA' AND vigencia_desde IS NULL;

-- ============================================================
-- LINEAS BOM MULTI-NIVEL (evoluciona lista_materiales_lineas)
-- ============================================================

ALTER TABLE lista_materiales_lineas
  ADD COLUMN tipo_linea bom_linea_tipo NOT NULL DEFAULT 'COMPONENTE',
  ADD COLUMN sub_bom_id UUID REFERENCES lista_materiales(id),
  ADD COLUMN es_phantom BOOLEAN DEFAULT false,
  ADD COLUMN merma_porcentaje DECIMAL(5,2) DEFAULT 0,
  ADD COLUMN opcional BOOLEAN DEFAULT false;

-- Constraint: si tipo_linea = SUB_ENSAMBLAJE, sub_bom_id es obligatorio
ALTER TABLE lista_materiales_lineas
  ADD CONSTRAINT chk_sub_bom
  CHECK (tipo_linea = 'COMPONENTE' OR sub_bom_id IS NOT NULL);

-- Indice para implosion (where-used)
CREATE INDEX idx_bom_linea_componente
  ON lista_materiales_lineas(producto_id);

CREATE INDEX idx_bom_linea_sub_bom
  ON lista_materiales_lineas(sub_bom_id)
  WHERE sub_bom_id IS NOT NULL;
```

## Funciones PostgreSQL

```sql
-- ============================================================
-- EXPLOSION BOM PLANA (recursiva)
-- Devuelve TODOS los materiales finales con cantidades acumuladas
-- ============================================================

CREATE OR REPLACE FUNCTION explode_bom_flat(
  p_bom_id UUID,
  p_cantidad DECIMAL(18,6) DEFAULT 1,
  p_fecha DATE DEFAULT CURRENT_DATE
) RETURNS TABLE(
  producto_id UUID,
  nombre_producto VARCHAR,
  cantidad_total DECIMAL(18,6),
  unidad_medida_id UUID,
  nivel INTEGER,
  es_phantom BOOLEAN
)
LANGUAGE plpgsql SECURITY DEFINER STABLE AS $$
BEGIN
  RETURN QUERY
  WITH RECURSIVE bom_tree AS (
    -- Nivel base: lineas de la BOM raiz
    SELECT
      lml.producto_id,
      p.nombre AS nombre_producto,
      lml.cantidad * p_cantidad * (1 + lml.merma_porcentaje / 100) AS cantidad_acum,
      lml.unidad_medida_id,
      1 AS nivel,
      lml.sub_bom_id,
      lml.tipo_linea,
      COALESCE(lml.es_phantom, false) AS es_phantom_flag,
      COALESCE(sub_lm.tipo, 'NORMAL') AS sub_bom_tipo
    FROM lista_materiales_lineas lml
    JOIN productos p ON p.id = lml.producto_id
    LEFT JOIN lista_materiales sub_lm ON sub_lm.id = lml.sub_bom_id
    WHERE lml.lista_id = p_bom_id
      AND lml.opcional = false

    UNION ALL

    -- Recursion: expandir sub-ensamblajes y phantoms
    SELECT
      lml2.producto_id,
      p2.nombre,
      lml2.cantidad * bt.cantidad_acum * (1 + lml2.merma_porcentaje / 100),
      lml2.unidad_medida_id,
      bt.nivel + 1,
      lml2.sub_bom_id,
      lml2.tipo_linea,
      COALESCE(lml2.es_phantom, false),
      COALESCE(sub_lm2.tipo, 'NORMAL')
    FROM bom_tree bt
    JOIN lista_materiales_lineas lml2 ON lml2.lista_id = bt.sub_bom_id
    JOIN productos p2 ON p2.id = lml2.producto_id
    LEFT JOIN lista_materiales sub_lm2 ON sub_lm2.id = lml2.sub_bom_id
    WHERE bt.sub_bom_id IS NOT NULL
      AND lml2.opcional = false
  )
  -- Solo retornar hojas (componentes finales sin sub-BOM, o phantoms expandidos)
  SELECT
    bt.producto_id,
    bt.nombre_producto,
    SUM(bt.cantidad_acum) AS cantidad_total,
    bt.unidad_medida_id,
    MIN(bt.nivel) AS nivel,
    false AS es_phantom
  FROM bom_tree bt
  WHERE bt.sub_bom_id IS NULL  -- Es hoja (componente final)
     OR (bt.sub_bom_tipo = 'NORMAL' AND bt.tipo_linea = 'SUB_ENSAMBLAJE')
  GROUP BY bt.producto_id, bt.nombre_producto, bt.unidad_medida_id;
END;
$$;

-- ============================================================
-- EXPLOSION BOM ESTRUCTURADA (arbol completo con niveles)
-- ============================================================

CREATE OR REPLACE FUNCTION explode_bom_structured(
  p_bom_id UUID,
  p_cantidad DECIMAL(18,6) DEFAULT 1
) RETURNS TABLE(
  nivel INTEGER,
  producto_id UUID,
  nombre_producto VARCHAR,
  cantidad DECIMAL(18,6),
  unidad_medida VARCHAR,
  tipo_linea bom_linea_tipo,
  es_phantom BOOLEAN,
  bom_hijo_id UUID,
  ruta TEXT
)
LANGUAGE plpgsql SECURITY DEFINER STABLE AS $$
BEGIN
  RETURN QUERY
  WITH RECURSIVE bom_tree AS (
    SELECT
      1 AS nivel,
      lml.producto_id,
      p.nombre AS nombre_producto,
      lml.cantidad * p_cantidad AS cantidad,
      um.abreviacion AS unidad_medida,
      lml.tipo_linea,
      COALESCE(lml.es_phantom, false) AS es_phantom,
      lml.sub_bom_id AS bom_hijo_id,
      p.nombre::TEXT AS ruta
    FROM lista_materiales_lineas lml
    JOIN productos p ON p.id = lml.producto_id
    LEFT JOIN unidades_medida um ON um.id = lml.unidad_medida_id
    WHERE lml.lista_id = p_bom_id

    UNION ALL

    SELECT
      bt.nivel + 1,
      lml2.producto_id,
      p2.nombre,
      lml2.cantidad * bt.cantidad,
      um2.abreviacion,
      lml2.tipo_linea,
      COALESCE(lml2.es_phantom, false),
      lml2.sub_bom_id,
      bt.ruta || ' > ' || p2.nombre
    FROM bom_tree bt
    JOIN lista_materiales_lineas lml2 ON lml2.lista_id = bt.bom_hijo_id
    JOIN productos p2 ON p2.id = lml2.producto_id
    LEFT JOIN unidades_medida um2 ON um2.id = lml2.unidad_medida_id
    WHERE bt.bom_hijo_id IS NOT NULL
  )
  SELECT * FROM bom_tree
  ORDER BY ruta;
END;
$$;

-- ============================================================
-- IMPLOSION BOM (Where-Used)
-- Dado un componente, retorna todos los productos padre
-- ============================================================

CREATE OR REPLACE FUNCTION implode_bom(
  p_producto_id UUID,
  p_empresa_id UUID
) RETURNS TABLE(
  nivel INTEGER,
  producto_padre_id UUID,
  nombre_padre VARCHAR,
  bom_id UUID,
  bom_nombre VARCHAR,
  cantidad_usada DECIMAL(18,6),
  ruta TEXT
)
LANGUAGE plpgsql SECURITY DEFINER STABLE AS $$
BEGIN
  RETURN QUERY
  WITH RECURSIVE where_used AS (
    -- Nivel base: BOMs donde el producto aparece directamente
    SELECT
      1 AS nivel,
      lm.producto_id AS producto_padre_id,
      p.nombre AS nombre_padre,
      lm.id AS bom_id,
      lm.nombre AS bom_nombre,
      lml.cantidad AS cantidad_usada,
      p.nombre::TEXT AS ruta
    FROM lista_materiales_lineas lml
    JOIN lista_materiales lm ON lm.id = lml.lista_id
    JOIN productos p ON p.id = lm.producto_id
    WHERE lml.producto_id = p_producto_id
      AND lm.empresa_id = p_empresa_id
      AND lm.version_estado = 'ACTIVA'

    UNION ALL

    -- Recursion: BOMs padre que usan el sub-ensamblaje
    SELECT
      wu.nivel + 1,
      lm2.producto_id,
      p2.nombre,
      lm2.id,
      lm2.nombre,
      lml2.cantidad,
      wu.ruta || ' < ' || p2.nombre
    FROM where_used wu
    JOIN lista_materiales_lineas lml2
      ON lml2.producto_id = wu.producto_padre_id
         OR lml2.sub_bom_id = wu.bom_id
    JOIN lista_materiales lm2 ON lm2.id = lml2.lista_id
    JOIN productos p2 ON p2.id = lm2.producto_id
    WHERE lm2.empresa_id = p_empresa_id
      AND lm2.version_estado = 'ACTIVA'
  )
  SELECT DISTINCT * FROM where_used
  ORDER BY nivel, nombre_padre;
END;
$$;

-- ============================================================
-- COSTO ACUMULADO MULTI-NIVEL
-- ============================================================

CREATE OR REPLACE FUNCTION calculate_bom_cost_multilevel(
  p_bom_id UUID,
  p_cantidad DECIMAL(18,6) DEFAULT 1
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER STABLE AS $$
DECLARE
  v_costo_materiales DECIMAL(14,2) := 0;
  v_costo_mano_obra DECIMAL(14,2) := 0;
  v_costo_indirecto DECIMAL(14,2) := 0;
  v_bom RECORD;
  v_comp RECORD;
BEGIN
  -- Obtener datos de la BOM
  SELECT * INTO v_bom FROM lista_materiales WHERE id = p_bom_id;
  IF v_bom IS NULL THEN
    RAISE EXCEPTION 'BOM no encontrada: %', p_bom_id;
  END IF;

  -- Sumar costo de componentes (expansion plana)
  FOR v_comp IN
    SELECT ef.producto_id, ef.cantidad_total,
           COALESCE(ist.costo_promedio, p.costo, p.costo_estandar, 0) AS costo_unit
    FROM explode_bom_flat(p_bom_id, p_cantidad) ef
    JOIN productos p ON p.id = ef.producto_id
    LEFT JOIN (
      SELECT producto_id, AVG(costo_unitario) AS costo_promedio
      FROM kardex
      WHERE tipo_movimiento = 'INGRESO'
      GROUP BY producto_id
    ) ist ON ist.producto_id = ef.producto_id
  LOOP
    v_costo_materiales := v_costo_materiales +
      (v_comp.cantidad_total * v_comp.costo_unit);
  END LOOP;

  v_costo_mano_obra := COALESCE(v_bom.costo_mano_obra, 0) * p_cantidad;
  v_costo_indirecto := COALESCE(v_bom.costo_indirecto, 0) * p_cantidad;

  RETURN jsonb_build_object(
    'bom_id', p_bom_id,
    'producto_id', v_bom.producto_id,
    'cantidad', p_cantidad,
    'costo_materiales', ROUND(v_costo_materiales, 2),
    'costo_mano_obra', ROUND(v_costo_mano_obra, 2),
    'costo_indirecto', ROUND(v_costo_indirecto, 2),
    'costo_total', ROUND(v_costo_materiales + v_costo_mano_obra + v_costo_indirecto, 2),
    'costo_unitario', ROUND(
      (v_costo_materiales + v_costo_mano_obra + v_costo_indirecto) / NULLIF(p_cantidad, 0), 2
    )
  );
END;
$$;

-- ============================================================
-- EJECUTAR ENSAMBLAJE MULTI-NIVEL
-- Evoluciona execute_assembly existente para manejar phantoms y sub-BOMs
-- ============================================================

CREATE OR REPLACE FUNCTION execute_assembly_multilevel(
  p_empresa_id UUID,
  p_orden_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_orden RECORD;
  v_comp RECORD;
  v_items_egreso JSONB := '[]'::JSONB;
  v_items_ingreso JSONB;
  v_resultado JSONB;
BEGIN
  -- Obtener orden
  SELECT oe.*, lm.producto_id AS prod_terminado, lm.cantidad_produce, lm.tipo AS bom_tipo
  INTO v_orden
  FROM ordenes_ensamblaje oe
  JOIN lista_materiales lm ON lm.id = oe.lista_id
  WHERE oe.id = p_orden_id AND oe.empresa_id = p_empresa_id;

  IF v_orden IS NULL THEN
    RAISE EXCEPTION 'Orden de ensamblaje no encontrada';
  END IF;
  IF v_orden.estado != 'BORRADOR' AND v_orden.estado != 'EN_PROCESO' THEN
    RAISE EXCEPTION 'Orden debe estar en BORRADOR o EN_PROCESO';
  END IF;

  -- Obtener componentes finales via explosion plana (resuelve phantoms y sub-niveles)
  FOR v_comp IN
    SELECT ef.producto_id, ef.cantidad_total
    FROM explode_bom_flat(v_orden.lista_id, v_orden.cantidad / v_orden.cantidad_produce) ef
  LOOP
    -- Verificar stock
    IF (SELECT COALESCE(cantidad, 0) FROM inventario_stock
        WHERE producto_id = v_comp.producto_id
          AND bodega_id = v_orden.bodega_origen_id) < v_comp.cantidad_total THEN
      RAISE EXCEPTION 'Stock insuficiente componente %', v_comp.producto_id;
    END IF;

    v_items_egreso := v_items_egreso || jsonb_build_object(
      'producto_id', v_comp.producto_id,
      'cantidad', v_comp.cantidad_total
    );
  END LOOP;

  -- Egresar componentes
  PERFORM create_inventory_movement(
    p_empresa_id, v_orden.bodega_origen_id, 'EGRESO', v_items_egreso
  );

  -- Ingresar producto terminado (solo si BOM no es PHANTOM)
  IF v_orden.bom_tipo != 'PHANTOM' THEN
    v_items_ingreso := jsonb_build_array(jsonb_build_object(
      'producto_id', v_orden.prod_terminado,
      'cantidad', v_orden.cantidad
    ));
    PERFORM create_inventory_movement(
      p_empresa_id, v_orden.bodega_destino_id, 'INGRESO', v_items_ingreso
    );
  END IF;

  -- Actualizar estado y calcular costo
  UPDATE ordenes_ensamblaje SET estado = 'COMPLETADA' WHERE id = p_orden_id;
  v_resultado := calculate_bom_cost_multilevel(v_orden.lista_id, v_orden.cantidad);

  -- Actualizar costo del producto terminado
  UPDATE productos
  SET costo = (v_resultado->>'costo_unitario')::DECIMAL
  WHERE id = v_orden.prod_terminado;

  RETURN v_resultado;
END;
$$;

-- ============================================================
-- CREAR NUEVA VERSION DE BOM
-- ============================================================

CREATE OR REPLACE FUNCTION create_bom_version(
  p_bom_id UUID,
  p_notas TEXT DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_old_bom RECORD;
  v_new_bom_id UUID;
  v_new_version INTEGER;
BEGIN
  SELECT * INTO v_old_bom FROM lista_materiales WHERE id = p_bom_id;
  IF v_old_bom IS NULL THEN
    RAISE EXCEPTION 'BOM no encontrada';
  END IF;

  v_new_version := v_old_bom.version + 1;

  -- Marcar version anterior como obsoleta
  UPDATE lista_materiales SET version_estado = 'OBSOLETA'
  WHERE id = p_bom_id;

  -- Crear nueva version copiando cabecera
  INSERT INTO lista_materiales (
    empresa_id, producto_id, nombre, cantidad_produce, activo,
    tipo, version, version_estado, vigencia_desde, version_notas,
    costo_mano_obra, costo_indirecto
  ) VALUES (
    v_old_bom.empresa_id, v_old_bom.producto_id, v_old_bom.nombre,
    v_old_bom.cantidad_produce, true,
    v_old_bom.tipo, v_new_version, 'BORRADOR', CURRENT_DATE,
    COALESCE(p_notas, 'Version ' || v_new_version),
    v_old_bom.costo_mano_obra, v_old_bom.costo_indirecto
  ) RETURNING id INTO v_new_bom_id;

  -- Copiar lineas
  INSERT INTO lista_materiales_lineas (
    lista_id, producto_id, cantidad, unidad_medida_id, observaciones,
    orden, tipo_linea, sub_bom_id, es_phantom,
    merma_porcentaje, opcional
  )
  SELECT
    v_new_bom_id, producto_id, cantidad, unidad_medida_id, observaciones,
    orden, tipo_linea, sub_bom_id, es_phantom,
    merma_porcentaje, opcional
  FROM lista_materiales_lineas
  WHERE lista_id = p_bom_id;

  RETURN v_new_bom_id;
END;
$$;
```

## Triggers

```sql
-- Prevenir ciclos en BOM (un producto no puede ser componente de si mismo, directa o indirectamente)
CREATE OR REPLACE FUNCTION trg_check_bom_cycle()
RETURNS TRIGGER AS $$
DECLARE
  v_bom_producto_id UUID;
  v_found BOOLEAN;
BEGIN
  -- Obtener producto padre de la BOM
  SELECT producto_id INTO v_bom_producto_id
  FROM lista_materiales WHERE id = NEW.lista_id;

  -- Verificar si el componente crearia un ciclo
  IF NEW.producto_id = v_bom_producto_id THEN
    RAISE EXCEPTION 'Ciclo detectado: un producto no puede ser componente de si mismo';
  END IF;

  -- Verificar ciclos indirectos via sub-BOMs
  IF NEW.tipo_linea = 'SUB_ENSAMBLAJE' AND NEW.sub_bom_id IS NOT NULL THEN
    WITH RECURSIVE cycle_check AS (
      SELECT lml.producto_id, lml.sub_bom_id
      FROM lista_materiales_lineas lml
      WHERE lml.lista_id = NEW.sub_bom_id
      UNION ALL
      SELECT lml2.producto_id, lml2.sub_bom_id
      FROM cycle_check cc
      JOIN lista_materiales_lineas lml2 ON lml2.lista_id = cc.sub_bom_id
      WHERE cc.sub_bom_id IS NOT NULL
    )
    SELECT EXISTS(
      SELECT 1 FROM cycle_check WHERE producto_id = v_bom_producto_id
    ) INTO v_found;

    IF v_found THEN
      RAISE EXCEPTION 'Ciclo detectado en BOM multi-nivel: el producto padre aparece como componente en un sub-nivel';
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_bom_cycle_check
  BEFORE INSERT OR UPDATE ON lista_materiales_lineas
  FOR EACH ROW EXECUTE FUNCTION trg_check_bom_cycle();

-- Auto-detectar sub-ensamblaje al agregar componente con BOM propia
CREATE OR REPLACE FUNCTION trg_auto_detect_sub_assembly()
RETURNS TRIGGER AS $$
DECLARE
  v_sub_bom_id UUID;
BEGIN
  IF NEW.tipo_linea = 'COMPONENTE' AND NEW.sub_bom_id IS NULL THEN
    SELECT id INTO v_sub_bom_id
    FROM lista_materiales
    WHERE producto_id = NEW.producto_id
      AND version_estado = 'ACTIVA'
      AND activo = true
    ORDER BY version DESC
    LIMIT 1;

    IF v_sub_bom_id IS NOT NULL THEN
      NEW.tipo_linea := 'SUB_ENSAMBLAJE';
      NEW.sub_bom_id := v_sub_bom_id;
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_bom_auto_sub_assembly
  BEFORE INSERT ON lista_materiales_lineas
  FOR EACH ROW EXECUTE FUNCTION trg_auto_detect_sub_assembly();
```

## Vistas

```sql
-- Vista: BOMs activas con resumen de componentes y costo
CREATE OR REPLACE VIEW v_bom_resumen AS
SELECT
  lm.id AS bom_id,
  lm.empresa_id,
  lm.producto_id,
  p.nombre AS producto_nombre,
  p.sku,
  lm.nombre AS bom_nombre,
  lm.tipo,
  lm.version,
  lm.version_estado,
  lm.vigencia_desde,
  lm.vigencia_hasta,
  lm.cantidad_produce,
  COUNT(lml.id) AS total_lineas,
  COUNT(CASE WHEN lml.tipo_linea = 'SUB_ENSAMBLAJE' THEN 1 END) AS sub_ensamblajes,
  lm.costo_mano_obra,
  lm.costo_indirecto
FROM lista_materiales lm
JOIN productos p ON p.id = lm.producto_id
LEFT JOIN lista_materiales_lineas lml ON lml.lista_id = lm.id
GROUP BY lm.id, p.nombre, p.sku;
```

## Integracion Module Service Bus

```sql
-- BUS: Obtener costo BOM multi-nivel (desde cualquier modulo)
CREATE OR REPLACE FUNCTION module_bus.get_bom_cost(
  p_empresa_id UUID,
  p_producto_id UUID,
  p_cantidad DECIMAL(18,6) DEFAULT 1
) RETURNS module_bus.bus_response
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_result module_bus.bus_response;
  v_bom_id UUID;
  v_costo JSONB;
BEGIN
  IF NOT module_bus.is_module_active(p_empresa_id, 'inventario') THEN
    v_result := (false, 'module_inactive', 'inventario', null);
    RETURN v_result;
  END IF;

  SELECT id INTO v_bom_id
  FROM lista_materiales
  WHERE empresa_id = p_empresa_id AND producto_id = p_producto_id
    AND version_estado = 'ACTIVA' AND activo = true
  ORDER BY version DESC LIMIT 1;

  IF v_bom_id IS NULL THEN
    v_result := (true, 'no_bom_found', 'inventario', null);
    RETURN v_result;
  END IF;

  v_costo := calculate_bom_cost_multilevel(v_bom_id, p_cantidad);
  v_result := (true, null, 'inventario', v_costo);
  RETURN v_result;
END;
$$;
```

## RLS Policies

```sql
-- Las tablas lista_materiales y lista_materiales_lineas ya tienen RLS
-- via empresa_id. No se requieren policies adicionales dado que
-- las nuevas columnas se agregan a tablas existentes.
-- Las funciones son SECURITY DEFINER por lo que bypasean RLS internamente.
```

## Flujo UI/UX

```
PANTALLA: Inventario > Manufactura > Lista de Materiales

[Lista BOM] (SfDataGrid)
  Columnas: Producto | Nombre BOM | Tipo (Normal/Phantom) | Version | Estado | Componentes | Costo Est.
  Filtros: tipo, estado, producto
  Acciones: + Nueva BOM, Editar, Duplicar, Nueva Version

[Formulario BOM]
  Cabecera: Producto terminado | Nombre BOM | Tipo | Cantidad produce
            Vigencia desde/hasta | Mano de obra | Costos indirectos | Variante (opcional)
  Lineas (SfDataGrid editable):
    Componente | Tipo (Componente/Sub-ensamblaje) | Cantidad | UoM | Merma% | Opcional
    [icono expandir sub-BOM inline si es sub-ensamblaje]
  Acciones: Calcular Costo | Explosion Plana | Explosion Estructurada | Nueva Version
  Panel lateral: Arbol visual del BOM (TreeView con niveles coloreados)

[Pantalla Implosion]
  Seleccionar producto -> Muestra arbol inverso "Donde se usa"
  Columnas: Producto Padre | BOM | Cantidad usada | Nivel

[Responsive]
  COMPACT: Lista simplificada, formulario en tabs
  MEDIUM: Lista + formulario side-by-side
  EXPANDED/LARGE: Vista completa con arbol lateral
```

---

