# Co-productos y Subproductos


## Descripcion Funcional

Extension del sistema BOM/ensamblaje para soportar la produccion de multiples productos a partir de una sola orden de produccion. Al producir el producto principal, se generan automaticamente co-productos y/o subproductos con sus propios movimientos de inventario.

**Definiciones:**

- **Producto principal:** El producto que motiva la orden de produccion. Recibe la mayor parte del costo.
- **Co-producto:** Producto con valor comercial significativo que se genera junto al principal. Recibe una porcion del costo total de produccion. Ejemplo: al procesar pollo entero, se obtienen pechugas (principal), alas, muslos y menudencias (co-productos).
- **Subproducto:** Producto secundario con poco o ningun valor comercial. Puede tener costo cero o minimo. Ejemplo: aserrin al cortar madera, suero al hacer queso.
- **Merma de produccion:** Material perdido durante el proceso que no tiene valor recuperable. Se registra como merma con asiento contable (ya soportado por `mermas_inventario`).

**Metodos de distribucion de costos:**

1. **Por peso:** El costo total se distribuye proporcionalmente al peso de cada producto resultante. Ideal para industrias alimenticias (desposte, lacteos).

2. **Por valor de mercado:** El costo se distribuye proporcionalmente al valor de venta de cada producto. Ideal cuando los co-productos tienen precios de mercado conocidos.

3. **Por cantidad:** El costo se distribuye proporcionalmente a la cantidad producida. Simple pero menos preciso.

4. **Manual/Porcentaje fijo:** El usuario define el porcentaje del costo para cada producto. Maximo control.

**Casos de uso Ecuador:**

- Desposte de carne (res, pollo, cerdo): 1 animal = N cortes con diferentes valores
- Aserradero: 1 tronco = tablas (principal) + aserrin (subproducto) + retazos (subproducto)
- Procesadora de lacteos: Leche = queso (principal) + suero (subproducto)
- Recicladora: Material reciclado = N materias primas separadas (co-productos)

## Modelo de Datos SQL

```sql
-- ============================================================
-- ENUMS para Co-productos
-- ============================================================

CREATE TYPE coproducto_tipo AS ENUM ('PRINCIPAL', 'CO_PRODUCTO', 'SUBPRODUCTO');
CREATE TYPE coproducto_dist_costo AS ENUM ('PESO', 'VALOR_MERCADO', 'CANTIDAD', 'PORCENTAJE_FIJO');

-- ============================================================
-- LINEAS DE CO-PRODUCTOS EN BOM
-- ============================================================

CREATE TABLE bom_coproductos (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bom_id          UUID NOT NULL REFERENCES lista_materiales(id) ON DELETE CASCADE,
  producto_id     UUID NOT NULL REFERENCES productos(id),
  tipo            coproducto_tipo NOT NULL,
  -- Cantidades esperadas por lote de produccion
  cantidad_esperada DECIMAL(18,6) NOT NULL,
  unidad_medida_id UUID REFERENCES unidades_medida(id),
  -- Distribucion de costos
  porcentaje_costo DECIMAL(5,2),                           -- % del costo total (si dist = PORCENTAJE_FIJO)
  peso_estimado   DECIMAL(12,4),                           -- Peso en kg (si dist = PESO)
  valor_mercado   DECIMAL(14,2),                           -- Precio venta (si dist = VALOR_MERCADO)
  -- Para subproductos
  costo_cero      BOOLEAN DEFAULT false,                   -- true = no recibe costo (merma recuperable)
  -- Bodega destino
  bodega_destino_id UUID REFERENCES bodegas(id),           -- NULL = misma bodega que producto principal
  -- Orden y notas
  orden           INTEGER DEFAULT 0,
  notas           TEXT,
  UNIQUE(bom_id, producto_id)
);

ALTER TABLE bom_coproductos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON bom_coproductos
  FOR ALL TO authenticated
  USING (bom_id IN (
    SELECT id FROM lista_materiales WHERE empresa_id = (SELECT private.get_empresa_id())
  ));

-- ============================================================
-- METODO DE DISTRIBUCION EN BOM (agregar a lista_materiales)
-- ============================================================

ALTER TABLE lista_materiales
  ADD COLUMN tiene_coproductos BOOLEAN DEFAULT false,
  ADD COLUMN dist_costo_metodo coproducto_dist_costo DEFAULT 'PORCENTAJE_FIJO';

-- ============================================================
-- REGISTRO DE CO-PRODUCTOS REALES EN ORDEN DE ENSAMBLAJE
-- ============================================================

CREATE TABLE orden_ensamblaje_coproductos (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  orden_id        UUID NOT NULL REFERENCES ordenes_ensamblaje(id) ON DELETE CASCADE,
  bom_coproducto_id UUID NOT NULL REFERENCES bom_coproductos(id),
  producto_id     UUID NOT NULL REFERENCES productos(id),
  tipo            coproducto_tipo NOT NULL,
  -- Cantidades reales (pueden diferir de las esperadas)
  cantidad_real   DECIMAL(18,6) NOT NULL,
  -- Costo asignado
  costo_asignado  DECIMAL(14,2),
  porcentaje_costo_real DECIMAL(5,2),
  -- Movimiento generado
  kardex_id       UUID REFERENCES kardex(id),
  bodega_destino_id UUID REFERENCES bodegas(id)
);

ALTER TABLE orden_ensamblaje_coproductos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON orden_ensamblaje_coproductos
  FOR ALL TO authenticated
  USING (orden_id IN (
    SELECT id FROM ordenes_ensamblaje WHERE empresa_id = (SELECT private.get_empresa_id())
  ));
```

## Funciones PostgreSQL

```sql
-- ============================================================
-- CALCULAR DISTRIBUCION DE COSTOS ENTRE CO-PRODUCTOS
-- ============================================================

CREATE OR REPLACE FUNCTION calculate_coproduct_cost_distribution(
  p_bom_id UUID,
  p_costo_total DECIMAL(14,2),
  p_cantidades_reales JSONB DEFAULT NULL  -- [{producto_id, cantidad_real, peso_real}] override
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER STABLE AS $$
DECLARE
  v_bom RECORD;
  v_total_base DECIMAL := 0;
  v_coprod RECORD;
  v_resultados JSONB := '[]'::JSONB;
  v_base_valor DECIMAL;
BEGIN
  SELECT * INTO v_bom FROM lista_materiales WHERE id = p_bom_id;
  IF v_bom IS NULL THEN
    RAISE EXCEPTION 'BOM no encontrada';
  END IF;

  -- Calcular denominador segun metodo
  FOR v_coprod IN
    SELECT bc.*, COALESCE(
      (SELECT (elem->>'cantidad_real')::DECIMAL
       FROM jsonb_array_elements(COALESCE(p_cantidades_reales, '[]'::JSONB)) elem
       WHERE (elem->>'producto_id')::UUID = bc.producto_id),
      bc.cantidad_esperada
    ) AS qty_real,
    COALESCE(
      (SELECT (elem->>'peso_real')::DECIMAL
       FROM jsonb_array_elements(COALESCE(p_cantidades_reales, '[]'::JSONB)) elem
       WHERE (elem->>'producto_id')::UUID = bc.producto_id),
      bc.peso_estimado
    ) AS peso_real
    FROM bom_coproductos bc
    WHERE bc.bom_id = p_bom_id
      AND bc.costo_cero = false
  LOOP
    v_base_valor := CASE v_bom.dist_costo_metodo
      WHEN 'PESO' THEN COALESCE(v_coprod.peso_real, 0)
      WHEN 'VALOR_MERCADO' THEN COALESCE(v_coprod.valor_mercado, 0) * v_coprod.qty_real
      WHEN 'CANTIDAD' THEN v_coprod.qty_real
      WHEN 'PORCENTAJE_FIJO' THEN COALESCE(v_coprod.porcentaje_costo, 0)
    END;
    v_total_base := v_total_base + v_base_valor;
  END LOOP;

  -- Distribuir costo
  FOR v_coprod IN
    SELECT bc.*, COALESCE(
      (SELECT (elem->>'cantidad_real')::DECIMAL
       FROM jsonb_array_elements(COALESCE(p_cantidades_reales, '[]'::JSONB)) elem
       WHERE (elem->>'producto_id')::UUID = bc.producto_id),
      bc.cantidad_esperada
    ) AS qty_real,
    COALESCE(
      (SELECT (elem->>'peso_real')::DECIMAL
       FROM jsonb_array_elements(COALESCE(p_cantidades_reales, '[]'::JSONB)) elem
       WHERE (elem->>'producto_id')::UUID = bc.producto_id),
      bc.peso_estimado
    ) AS peso_real
    FROM bom_coproductos bc WHERE bc.bom_id = p_bom_id
  LOOP
    IF v_coprod.costo_cero THEN
      v_resultados := v_resultados || jsonb_build_object(
        'producto_id', v_coprod.producto_id,
        'tipo', v_coprod.tipo,
        'cantidad', v_coprod.qty_real,
        'costo_asignado', 0,
        'porcentaje', 0
      );
    ELSE
      v_base_valor := CASE v_bom.dist_costo_metodo
        WHEN 'PESO' THEN COALESCE(v_coprod.peso_real, 0)
        WHEN 'VALOR_MERCADO' THEN COALESCE(v_coprod.valor_mercado, 0) * v_coprod.qty_real
        WHEN 'CANTIDAD' THEN v_coprod.qty_real
        WHEN 'PORCENTAJE_FIJO' THEN COALESCE(v_coprod.porcentaje_costo, 0)
      END;

      v_resultados := v_resultados || jsonb_build_object(
        'producto_id', v_coprod.producto_id,
        'tipo', v_coprod.tipo,
        'cantidad', v_coprod.qty_real,
        'costo_asignado', ROUND(
          CASE WHEN v_total_base > 0
            THEN p_costo_total * v_base_valor / v_total_base
            ELSE 0
          END, 2
        ),
        'porcentaje', ROUND(
          CASE WHEN v_total_base > 0
            THEN v_base_valor / v_total_base * 100
            ELSE 0
          END, 2
        )
      );
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'costo_total', p_costo_total,
    'metodo', v_bom.dist_costo_metodo,
    'distribucion', v_resultados
  );
END;
$$;

-- ============================================================
-- EJECUTAR ENSAMBLAJE CON CO-PRODUCTOS
-- Extension de execute_assembly_multilevel
-- ============================================================

CREATE OR REPLACE FUNCTION execute_assembly_with_coproducts(
  p_empresa_id UUID,
  p_orden_id UUID,
  p_cantidades_reales JSONB DEFAULT NULL  -- Override cantidades co-productos
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_orden RECORD;
  v_bom RECORD;
  v_costo_produccion JSONB;
  v_distribucion JSONB;
  v_item JSONB;
  v_items_ingreso JSONB;
  v_kardex_ids UUID[];
BEGIN
  SELECT oe.*, lm.producto_id AS prod_terminado, lm.tiene_coproductos, lm.dist_costo_metodo
  INTO v_orden
  FROM ordenes_ensamblaje oe
  JOIN lista_materiales lm ON lm.id = oe.lista_id
  WHERE oe.id = p_orden_id AND oe.empresa_id = p_empresa_id;

  IF NOT v_orden.tiene_coproductos THEN
    -- Sin co-productos, usar funcion multi-nivel estandar
    RETURN execute_assembly_multilevel(p_empresa_id, p_orden_id);
  END IF;

  -- Ejecutar consumo de componentes (reutiliza logica multi-nivel)
  v_costo_produccion := calculate_bom_cost_multilevel(v_orden.lista_id, v_orden.cantidad);

  -- Consumir componentes
  PERFORM execute_assembly_multilevel(p_empresa_id, p_orden_id);

  -- Distribuir costo entre co-productos
  v_distribucion := calculate_coproduct_cost_distribution(
    v_orden.lista_id,
    (v_costo_produccion->>'costo_total')::DECIMAL,
    p_cantidades_reales
  );

  -- Ingresar cada co-producto/subproducto
  FOR v_item IN SELECT * FROM jsonb_array_elements(v_distribucion->'distribucion') LOOP
    v_items_ingreso := jsonb_build_array(jsonb_build_object(
      'producto_id', v_item->>'producto_id',
      'cantidad', (v_item->>'cantidad')::DECIMAL,
      'costo_unitario', CASE WHEN (v_item->>'cantidad')::DECIMAL > 0
        THEN ROUND((v_item->>'costo_asignado')::DECIMAL / (v_item->>'cantidad')::DECIMAL, 6)
        ELSE 0
      END
    ));

    v_kardex_ids := create_inventory_movement(
      p_empresa_id, v_orden.bodega_destino_id, 'INGRESO', v_items_ingreso
    );

    -- Registrar en tabla de co-productos de la orden
    INSERT INTO orden_ensamblaje_coproductos (
      orden_id, bom_coproducto_id, producto_id, tipo,
      cantidad_real, costo_asignado, porcentaje_costo_real,
      kardex_id, bodega_destino_id
    )
    SELECT
      p_orden_id, bc.id, (v_item->>'producto_id')::UUID,
      (v_item->>'tipo')::coproducto_tipo,
      (v_item->>'cantidad')::DECIMAL,
      (v_item->>'costo_asignado')::DECIMAL,
      (v_item->>'porcentaje')::DECIMAL,
      v_kardex_ids[1], v_orden.bodega_destino_id
    FROM bom_coproductos bc
    WHERE bc.bom_id = v_orden.lista_id
      AND bc.producto_id = (v_item->>'producto_id')::UUID;

    -- Actualizar costo del co-producto
    UPDATE productos SET costo = CASE
      WHEN (v_item->>'cantidad')::DECIMAL > 0
        THEN ROUND((v_item->>'costo_asignado')::DECIMAL / (v_item->>'cantidad')::DECIMAL, 6)
        ELSE costo
      END
    WHERE id = (v_item->>'producto_id')::UUID;
  END LOOP;

  RETURN jsonb_build_object(
    'orden_id', p_orden_id,
    'costo_produccion', v_costo_produccion,
    'distribucion_coproductos', v_distribucion
  );
END;
$$;
```

## Triggers

```sql
-- Validar que los porcentajes de co-productos sumen 100% (si metodo = PORCENTAJE_FIJO)
CREATE OR REPLACE FUNCTION trg_validate_coproduct_percentages()
RETURNS TRIGGER AS $$
DECLARE
  v_total DECIMAL;
  v_metodo coproducto_dist_costo;
BEGIN
  SELECT dist_costo_metodo INTO v_metodo
  FROM lista_materiales WHERE id = NEW.bom_id;

  IF v_metodo = 'PORCENTAJE_FIJO' THEN
    SELECT COALESCE(SUM(porcentaje_costo), 0) INTO v_total
    FROM bom_coproductos
    WHERE bom_id = NEW.bom_id AND costo_cero = false AND id != NEW.id;

    v_total := v_total + COALESCE(NEW.porcentaje_costo, 0);

    IF v_total > 100.01 THEN  -- Tolerancia de 0.01 por redondeo
      RAISE EXCEPTION 'Los porcentajes de costo de co-productos exceden 100%% (total: %%)',
        v_total;
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_coproduct_pct_check
  BEFORE INSERT OR UPDATE ON bom_coproductos
  FOR EACH ROW EXECUTE FUNCTION trg_validate_coproduct_percentages();
```

## Vistas

```sql
-- Vista: BOMs con co-productos y distribucion
CREATE OR REPLACE VIEW v_bom_coproductos AS
SELECT
  lm.id AS bom_id,
  lm.empresa_id,
  lm.producto_id AS producto_principal_id,
  pp.nombre AS producto_principal,
  lm.dist_costo_metodo,
  bc.id AS coproducto_id,
  bc.producto_id AS coproducto_producto_id,
  pc.nombre AS coproducto_nombre,
  bc.tipo,
  bc.cantidad_esperada,
  bc.porcentaje_costo,
  bc.peso_estimado,
  bc.valor_mercado,
  bc.costo_cero
FROM lista_materiales lm
JOIN productos pp ON pp.id = lm.producto_id
JOIN bom_coproductos bc ON bc.bom_id = lm.id
JOIN productos pc ON pc.id = bc.producto_id
WHERE lm.tiene_coproductos = true;
```

## Integracion Module Service Bus

```sql
-- No se requiere bus adicional. Los co-productos se gestionan
-- internamente por el modulo de inventario al ejecutar ordenes de ensamblaje.
-- El bus existente (module_bus.get_bom_cost) ya retorna el costo total
-- que luego se distribuye internamente.
```

## RLS Policies

```sql
-- Ya definidas inline en 23.5.2
```

## Flujo UI/UX

```
PANTALLA: Integrada en el formulario BOM existente (seccion 23.1.8)

[Formulario BOM - Tab "Co-productos"] (solo visible si tiene_coproductos = true)
  Toggle: "Esta BOM genera co-productos/subproductos"
  Selector: Metodo de distribucion de costos (Peso / Valor Mercado / Cantidad / % Fijo)

  [SfDataGrid editable - Co-productos]:
    Producto | Tipo (Principal/Co-producto/Subproducto) | Cantidad | UoM | Peso Est. |
    Valor Mercado | % Costo | Costo Cero? | Bodega Destino

  Preview visual: Diagrama de flujo
    [Componentes] -> [Proceso] -> [Principal (60%)]
                                -> [Co-producto A (30%)]
                                -> [Subproducto B (10%)]
                                -> [Merma (0%)]

---

PANTALLA: Orden de Ensamblaje con Co-productos

  Al completar una orden con co-productos:
  1. Modal muestra cantidades esperadas vs cantidades reales (editables)
  2. Preview de distribucion de costos (recalcula en tiempo real)
  3. Confirmacion -> ejecuta produccion + ingresa todos los productos

  [Tabla resultados]:
    Producto | Tipo | Qty Esperada | Qty Real | Costo Asignado | % | Bodega

[Responsive]
  COMPACT: Tab co-productos en formulario, preview simplificado
  MEDIUM: Formulario con preview side-by-side
  EXPANDED/LARGE: Todo visible con diagrama de flujo interactivo
```

---

