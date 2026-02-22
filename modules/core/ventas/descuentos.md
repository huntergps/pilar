# Descuentos en Ventas

*Spec derivada del módulo `l10n_ec_sale_discount` (Odoo 19.1 Ecuador — producción en csolish/tecnoh)*

---

## Descripción

Extensión del módulo de ventas para calcular y visualizar correctamente los descuentos por línea. Agrega campos calculados de `monto_descuento`, `subtotal_sin_descuento`, `costo_linea` y `margen` en líneas de OV. En la OV agrega totales de descuento, monto sin descuento y costo total. Genera un template personalizado de `tax_totals` para Ecuador que muestra la columna de descuentos en el RIDE/factura.

---

## Modelo de Datos

### Extensión de `ordenes_venta_lineas`

```sql
ALTER TABLE ordenes_venta_lineas ADD COLUMN producto_codigo    TEXT;          -- related: producto.codigo_interno
ALTER TABLE ordenes_venta_lineas ADD COLUMN descuento_monto    NUMERIC(15,2) DEFAULT 0;  -- calculado
ALTER TABLE ordenes_venta_lineas ADD COLUMN subtotal_sin_desc  NUMERIC(15,2) DEFAULT 0;  -- calculado
ALTER TABLE ordenes_venta_lineas ADD COLUMN impuesto_monto     NUMERIC(15,2) DEFAULT 0;  -- calculado
ALTER TABLE ordenes_venta_lineas ADD COLUMN costo_linea        NUMERIC(15,2) DEFAULT 0;  -- calculado
ALTER TABLE ordenes_venta_lineas ADD COLUMN margen_linea       NUMERIC(15,2) DEFAULT 0;  -- calculado
```

### Extensión de `ordenes_venta`

```sql
ALTER TABLE ordenes_venta ADD COLUMN total_descuento   NUMERIC(15,2) DEFAULT 0;  -- suma descuento_monto líneas
ALTER TABLE ordenes_venta ADD COLUMN total_sin_desc    NUMERIC(15,2) DEFAULT 0;  -- suma subtotal_sin_desc líneas
ALTER TABLE ordenes_venta ADD COLUMN total_costo       NUMERIC(15,2) DEFAULT 0;  -- suma costo_linea líneas
```

---

## Fórmulas de Cálculo

### Por Línea

```
subtotal_sin_desc = precio_unitario × cantidad
descuento_monto   = subtotal_sin_desc × (descuento_pct / 100)
precio_neto       = precio_unitario × (1 - descuento_pct / 100)
subtotal          = precio_neto × cantidad
impuesto_monto    = subtotal × tasa_impuesto
costo_linea       = costo_standard × cantidad
margen_linea      = subtotal - costo_linea
```

### Por OV

```
total_sin_desc = SUM(subtotal_sin_desc de todas las líneas)
total_descuento = SUM(descuento_monto de todas las líneas)
total_costo    = SUM(costo_linea de todas las líneas)
margen_total   = total_amount_untaxed - total_costo
```

---

## Template de Totales Ecuador

Cuando la OV tiene `total_descuento > 0`, se usa un template personalizado de totales que incluye:

```
┌─────────────────────────────────────────────┐
│ Subtotal (sin descuento):      $1,200.00    │
│ (-) Total Descuentos:          - $120.00    │
│ Subtotal (con descuento):      $1,080.00    │
│ IVA 15%:                         $162.00   │
│ TOTAL:                         $1,242.00   │
└─────────────────────────────────────────────┘
```

El JSON extendido de `tax_totals`:
```json
{
  "discount_amount_currency": 120.00,
  "amount_undiscounted_currency": 1200.00,
  "has_discounts": true,
  "currency_id": "uuid"
}
```

---

## Funciones RPC

```typescript
// Obtener resumen de descuentos de una OV
get_descuentos_ov(orden_venta_id: UUID): {
  total_sin_descuento: number
  total_descuento: number
  total_con_descuento: number
  porcentaje_descuento_promedio: number
  lineas: [{
    linea_id: UUID
    producto: string
    subtotal_sin_desc: number
    descuento_pct: number
    descuento_monto: number
    subtotal: number
    margen: number
  }]
}

// Aplicar descuento global a todas las líneas de una OV
aplicar_descuento_global(params: {
  orden_venta_id: UUID
  descuento_pct: number
}): { lineas_actualizadas: number, total_descuento: number }

// Calcular margen proyectado
get_margen_ov(orden_venta_id: UUID): {
  total_ingresos: number
  total_costo: number
  margen_bruto: number
  porcentaje_margen: number
}
```

---

## Validaciones de Negocio

- El descuento por línea es un porcentaje (0-100%), ya existente en Odoo estándar
- Los campos de descuento adicional son calculados (no editables directamente)
- El template de Ecuador solo aplica si `total_descuento > 0`
- El costo de línea usa `standard_price` del producto (no el costo real de lote)

---

## Configuración por Empresa

```json
{
  "descuentos": {
    "mostrar_columna_descuento": true,
    "mostrar_margen_en_ov": false,       // ocultar márgenes a vendedores
    "mostrar_costo_en_ov": false,
    "permitir_descuento_global": true
  }
}
```

---

## Pantallas Flutter

### Línea de OV con Descuento

```
┌──────────────┬──────┬──────────┬──────────┬──────────┬──────────┐
│ Producto     │ Cant │ P.Unit   │ Desc %   │ Desc $   │ Subtotal │
├──────────────┼──────┼──────────┼──────────┼──────────┼──────────┤
│ Laptop ASUS  │  2   │ $950.00  │ 10%      │ $190.00  │$1,710.00 │
│ Mouse USB    │  5   │  $25.00  │  5%      │  $6.25   │  $118.75 │
└──────────────┴──────┴──────────┴──────────┴──────────┴──────────┘
                              Total descuento: $196.25
```

### Resumen de Totales en OV

```
Subtotal sin descuento:  $2,025.00
(-) Descuentos:          - $196.25
Subtotal:                $1,828.75
IVA 15%:                   $274.31
TOTAL:                   $2,103.06
```

---

## Modelo de Datos SQL Completo

### Tabla: `politicas_descuento`

Define las reglas de descuento por empresa: límites, tipo de aplicación y si requieren aprobación.

```sql
CREATE TABLE politicas_descuento (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id          UUID NOT NULL REFERENCES empresas(id),
  nombre              TEXT NOT NULL,
  descripcion         TEXT,
  tipo                TEXT NOT NULL DEFAULT 'PORCENTAJE'
                      CHECK (tipo IN (
                        'PORCENTAJE',    -- descuento % sobre precio unitario
                        'MONTO_FIJO',    -- descuento valor fijo por línea
                        'ESCALONADO'     -- descuento por volumen (usa escalas_descuento)
                      )),
  aplicacion          TEXT NOT NULL DEFAULT 'LINEA'
                      CHECK (aplicacion IN (
                        'LINEA',         -- aplica línea a línea
                        'CABECERA',      -- aplica sobre subtotal de la OV
                        'GLOBAL'         -- aplica sobre total incluyendo impuestos
                      )),
  -- Para tipo PORCENTAJE o MONTO_FIJO: valor base
  valor               DECIMAL(14,2) DEFAULT 0,
  -- Límites
  limite_maximo_pct   DECIMAL(5,2) DEFAULT 100.00,   -- tope máximo en porcentaje
  limite_maximo_monto DECIMAL(14,2),                  -- tope máximo en valor absoluto
  -- Aprobación
  requiere_aprobacion BOOLEAN NOT NULL DEFAULT FALSE,
  pct_max_sin_aprobacion DECIMAL(5,2) DEFAULT 0,     -- % máximo sin requerir aprobación
  -- Acumulación: aditivo vs multiplicativo
  es_acumulable       BOOLEAN NOT NULL DEFAULT TRUE,  -- FALSE = exclusivo (no se combina)
  prioridad           INT NOT NULL DEFAULT 10,        -- menor = se aplica primero
  -- Condiciones de activación
  aplica_a            TEXT DEFAULT 'TODOS'
                      CHECK (aplica_a IN (
                        'TODOS',         -- sin restricción
                        'CATEGORIA',     -- solo para categoría de producto
                        'PRODUCTO',      -- solo para producto específico
                        'CLIENTE',       -- solo para cliente específico
                        'LISTA_PRECIO'   -- solo cuando la OV usa cierta lista de precios
                      )),
  categoria_id        UUID REFERENCES categorias_productos(id),
  producto_id         UUID REFERENCES productos(id),
  contacto_id         UUID REFERENCES contactos(id),
  lista_precio_id     UUID REFERENCES listas_precio(id),
  -- Vigencia
  fecha_inicio        DATE,
  fecha_fin           DATE,
  activo              BOOLEAN NOT NULL DEFAULT TRUE,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE politicas_descuento ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON politicas_descuento FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE INDEX idx_politicas_descuento_empresa ON politicas_descuento(empresa_id) WHERE activo = TRUE;
CREATE INDEX idx_politicas_descuento_tipo    ON politicas_descuento(empresa_id, tipo, aplicacion) WHERE activo = TRUE;
```

### Tabla: `escalas_descuento`

Define los tramos de descuento por volumen para políticas de tipo ESCALONADO.

```sql
CREATE TABLE escalas_descuento (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id           UUID NOT NULL REFERENCES empresas(id),
  politica_id          UUID NOT NULL REFERENCES politicas_descuento(id) ON DELETE CASCADE,
  cantidad_desde       DECIMAL(18,6) NOT NULL DEFAULT 0,   -- cantidad mínima del tramo
  cantidad_hasta       DECIMAL(18,6),                      -- NULL = sin límite superior
  porcentaje_descuento DECIMAL(5,2) NOT NULL DEFAULT 0,   -- % de descuento del tramo
  monto_fijo_descuento DECIMAL(14,2) DEFAULT 0,           -- alternativa: monto fijo por tramo
  descripcion          TEXT,                               -- etiqueta del tramo (ej: "Mayorista")
  secuencia            INT NOT NULL DEFAULT 10,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE escalas_descuento ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON escalas_descuento FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE INDEX idx_escalas_descuento_politica ON escalas_descuento(politica_id);
CREATE INDEX idx_escalas_descuento_empresa  ON escalas_descuento(empresa_id);

-- Constraint: cantidad_hasta > cantidad_desde
ALTER TABLE escalas_descuento
  ADD CONSTRAINT chk_escala_rango
  CHECK (cantidad_hasta IS NULL OR cantidad_hasta > cantidad_desde);
```

### Tabla: `descuentos_aplicados_ov`

Registro histórico de las políticas de descuento aplicadas a cada OV (trazabilidad de auditoría).

```sql
CREATE TABLE descuentos_aplicados_ov (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id        UUID NOT NULL REFERENCES empresas(id),
  orden_venta_id    UUID NOT NULL REFERENCES ordenes_venta(id) ON DELETE CASCADE,
  linea_id          UUID REFERENCES ordenes_venta_lineas(id),   -- NULL = descuento de cabecera
  politica_id       UUID REFERENCES politicas_descuento(id),
  tipo_origen       TEXT NOT NULL
                    CHECK (tipo_origen IN (
                      'POLITICA',   -- aplicada por política automática
                      'MANUAL',     -- ingresada manualmente por vendedor
                      'GLOBAL'      -- descuento global aplicado desde wizard
                    )),
  porcentaje        DECIMAL(5,2) NOT NULL DEFAULT 0,
  monto             DECIMAL(14,2) NOT NULL DEFAULT 0,
  aprobado_por      UUID REFERENCES usuarios(id),
  requirio_aprobacion BOOLEAN NOT NULL DEFAULT FALSE,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE descuentos_aplicados_ov ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON descuentos_aplicados_ov FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE INDEX idx_desc_aplicados_ov     ON descuentos_aplicados_ov(orden_venta_id);
CREATE INDEX idx_desc_aplicados_linea  ON descuentos_aplicados_ov(linea_id);
```

---

## Funciones RPC SQL Completas

### `apply_discount_policy(p_orden_id, p_politica_id)`

Aplica una política de descuento a una OV o cotización. Soporta los tres tipos: PORCENTAJE, MONTO_FIJO y ESCALONADO. Los descuentos se acumulan aditivamente (no multiplicativamente) excepto cuando el tipo es GLOBAL.

```sql
CREATE OR REPLACE FUNCTION ventas.apply_discount_policy(
  p_orden_id    UUID,
  p_politica_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_empresa_id    UUID;
  v_politica      politicas_descuento%ROWTYPE;
  v_ov            ordenes_venta%ROWTYPE;
  v_linea         RECORD;
  v_escala        escalas_descuento%ROWTYPE;
  v_desc_pct      DECIMAL(5,2);
  v_desc_monto    DECIMAL(14,2);
  v_total_desc    DECIMAL(14,2) := 0;
  v_lineas_upd    INT := 0;
BEGIN
  v_empresa_id := (SELECT private.get_empresa_id());

  -- Obtener política
  SELECT * INTO v_politica
  FROM politicas_descuento
  WHERE id = p_politica_id AND empresa_id = v_empresa_id AND activo = TRUE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Política de descuento no encontrada o inactiva';
  END IF;

  -- Obtener OV
  SELECT * INTO v_ov
  FROM ordenes_venta
  WHERE id = p_orden_id AND empresa_id = v_empresa_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Orden de venta no encontrada';
  END IF;

  -- Solo OV en borrador o cotización son modificables
  IF v_ov.estado NOT IN ('draft', 'borrador', 'sent', 'quotation') THEN
    RAISE EXCEPTION 'Solo se pueden modificar descuentos en cotizaciones o borradores';
  END IF;

  -- Aplicar según tipo y aplicación
  CASE v_politica.aplicacion
  WHEN 'LINEA' THEN
    -- Aplicar a cada línea individualmente
    FOR v_linea IN
      SELECT ovl.id, ovl.cantidad, ovl.precio_unitario, ovl.descuento_pct,
             ovl.subtotal_sin_desc
      FROM ordenes_venta_lineas ovl
      WHERE ovl.orden_venta_id = p_orden_id
        AND ovl.tipo_linea     = 'producto'
    LOOP
      -- Calcular descuento según tipo
      IF v_politica.tipo = 'PORCENTAJE' THEN
        v_desc_pct := v_politica.valor;
      ELSIF v_politica.tipo = 'MONTO_FIJO' THEN
        -- Convertir monto fijo a porcentaje sobre subtotal de línea
        v_desc_pct := CASE WHEN v_linea.subtotal_sin_desc > 0
                      THEN (v_politica.valor / v_linea.subtotal_sin_desc) * 100
                      ELSE 0 END;
      ELSIF v_politica.tipo = 'ESCALONADO' THEN
        -- Buscar tramo por cantidad
        SELECT * INTO v_escala
        FROM escalas_descuento
        WHERE politica_id    = p_politica_id
          AND cantidad_desde <= v_linea.cantidad
          AND (cantidad_hasta IS NULL OR cantidad_hasta >= v_linea.cantidad)
        ORDER BY cantidad_desde DESC
        LIMIT 1;
        v_desc_pct := COALESCE(v_escala.porcentaje_descuento, 0);
      END IF;

      -- Acumulación aditiva: nuevo_desc = actual + politica (tope en limite_maximo_pct)
      IF v_politica.es_acumulable THEN
        v_desc_pct := LEAST(v_linea.descuento_pct + v_desc_pct, v_politica.limite_maximo_pct);
      ELSE
        v_desc_pct := LEAST(v_desc_pct, v_politica.limite_maximo_pct);
      END IF;

      -- Calcular monto de descuento
      v_desc_monto := (v_linea.subtotal_sin_desc * v_desc_pct / 100)::DECIMAL(14,2);

      -- Actualizar línea
      UPDATE ordenes_venta_lineas
      SET descuento_pct   = v_desc_pct,
          descuento_monto = v_desc_monto,
          subtotal        = v_linea.subtotal_sin_desc - v_desc_monto,
          updated_at      = NOW()
      WHERE id = v_linea.id;

      v_total_desc := v_total_desc + v_desc_monto;
      v_lineas_upd := v_lineas_upd + 1;
    END LOOP;

  WHEN 'CABECERA', 'GLOBAL' THEN
    -- Aplicar descuento sobre el subtotal total de la OV
    v_desc_monto := CASE v_politica.tipo
      WHEN 'PORCENTAJE' THEN (v_ov.total_sin_desc * v_politica.valor / 100)::DECIMAL(14,2)
      WHEN 'MONTO_FIJO' THEN v_politica.valor
      ELSE 0
    END;

    -- Respetar límite máximo
    IF v_politica.limite_maximo_monto IS NOT NULL THEN
      v_desc_monto := LEAST(v_desc_monto, v_politica.limite_maximo_monto);
    END IF;

    UPDATE ordenes_venta
    SET total_descuento = total_descuento + v_desc_monto,
        updated_at      = NOW()
    WHERE id = p_orden_id;

    v_total_desc := v_desc_monto;
  END CASE;

  -- Registrar auditoría
  INSERT INTO descuentos_aplicados_ov (
    empresa_id, orden_venta_id, politica_id, tipo_origen,
    porcentaje, monto, requirio_aprobacion
  ) VALUES (
    v_empresa_id, p_orden_id, p_politica_id, 'POLITICA',
    v_politica.valor, v_total_desc,
    v_politica.requiere_aprobacion
  );

  RETURN jsonb_build_object(
    'success',          TRUE,
    'politica',         v_politica.nombre,
    'lineas_actualizadas', v_lineas_upd,
    'total_descuento',  v_total_desc
  );
END;
$$;
```

### `validate_discount_approval(p_descuento_pct, p_usuario_id, p_empresa_id)`

Verifica si el usuario tiene permiso para aplicar el porcentaje de descuento sin requerir aprobación. Usa los límites por rol definidos en la configuración de la empresa.

```sql
CREATE OR REPLACE FUNCTION ventas.validate_discount_approval(
  p_descuento_pct DECIMAL(5,2),
  p_usuario_id    UUID,
  p_empresa_id    UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_empresa_id   UUID;
  v_rol          TEXT;
  v_limite_rol   DECIMAL(5,2);
  v_config       JSONB;
BEGIN
  v_empresa_id := COALESCE(p_empresa_id, (SELECT private.get_empresa_id()));

  -- Obtener rol del usuario en la empresa
  SELECT ur.rol INTO v_rol
  FROM usuarios_roles ur
  WHERE ur.usuario_id = p_usuario_id
    AND ur.empresa_id = v_empresa_id
    AND ur.activo     = TRUE
  ORDER BY ur.created_at DESC
  LIMIT 1;

  -- Límites máximos por rol (configurables en parámetros de empresa)
  SELECT configuracion->'descuentos'->'limites_rol' INTO v_config
  FROM empresas
  WHERE id = v_empresa_id;

  -- Límites por defecto del sistema (sobreescribibles por empresa)
  v_limite_rol := CASE v_rol
    WHEN 'VENDEDOR'    THEN COALESCE((v_config->>'VENDEDOR')::DECIMAL,   10.00)
    WHEN 'SUPERVISOR'  THEN COALESCE((v_config->>'SUPERVISOR')::DECIMAL, 20.00)
    WHEN 'GERENTE'     THEN COALESCE((v_config->>'GERENTE')::DECIMAL,    30.00)
    WHEN 'ADMIN'       THEN 100.00
    ELSE 0.00  -- sin rol definido: sin descuento
  END;

  RETURN jsonb_build_object(
    'permitido',          p_descuento_pct <= v_limite_rol,
    'rol',                v_rol,
    'limite_rol_pct',     v_limite_rol,
    'descuento_solicitado', p_descuento_pct,
    'requiere_aprobacion', p_descuento_pct > v_limite_rol,
    'exceso_pct',         GREATEST(p_descuento_pct - v_limite_rol, 0)
  );
END;
$$;
```

---

## Reglas de Cascada y Acumulación de Descuentos

Los descuentos se acumulan **aditivamente** (no multiplicativamente), excepto cuando el tipo es GLOBAL (que reemplaza cualquier descuento anterior en cabecera).

```
Ejemplo - Descuento cascada aditivo:
  Precio unitario:              $100.00
  1. Descuento por lista precio:  -5%  → precio efectivo $95.00  (desc acumulado: 5%)
  2. Descuento por cliente:       -3%  → precio efectivo $92.00  (desc acumulado: 8%)
  3. Descuento por volumen:       -2%  → precio efectivo $90.00  (desc acumulado: 10%)
  Total descuento (aditivo):      10%  → $10.00 sobre precio original

  (NO multiplicativo, que daría: $100 × 0.95 × 0.97 × 0.98 = $90.32)
```

### Límites Máximos por Rol

| Rol | Límite sin aprobación | Con aprobación supervisor |
|---|---|---|
| VENDEDOR | 10% | Hasta 20% |
| SUPERVISOR | 20% | Hasta 30% |
| GERENTE | 30% | Hasta 100% |
| ADMIN | 100% | Sin restricción |

```sql
-- Configuración en empresas.configuracion (JSONB)
{
  "descuentos": {
    "limites_rol": {
      "VENDEDOR":   10,
      "SUPERVISOR": 20,
      "GERENTE":    30
    },
    "acumulacion": "ADITIVO",
    "mostrar_margen_en_ov":     false,
    "mostrar_costo_en_ov":      false,
    "permitir_descuento_global": true,
    "requiere_aprobacion_excedente": true
  }
}
```

---

## Índices Adicionales

```sql
-- Índice para búsqueda de políticas vigentes
CREATE INDEX idx_politicas_descuento_vigencia ON politicas_descuento(empresa_id, fecha_inicio, fecha_fin)
  WHERE activo = TRUE;

-- Índice para escalas por rango de cantidad
CREATE INDEX idx_escalas_descuento_cantidad ON escalas_descuento(politica_id, cantidad_desde, cantidad_hasta);

-- Índice para auditoría de descuentos
CREATE INDEX idx_desc_aplicados_fecha ON descuentos_aplicados_ov(empresa_id, created_at DESC);
```
