# Costos de Aterrizaje Ecuador

*Spec derivada del módulo `l10n_ec_stock_landed_costs` (Odoo 19.1 Ecuador — producción en csolish/tecnoh)*

---

## Descripción

Extensión del módulo estándar de costos de aterrizaje (`stock.landed.cost`) para el contexto de importaciones en Ecuador. Agrega un estado `provisional` para calcular costos antes de tener las facturas definitivas, separación entre costos locales e internacionales, vinculación directa con facturas de gastos (flete, seguro, arancel), incoterms, y actualización automática del último precio de compra del producto al validar.

---

## Diferencias vs Costos de Aterrizaje Estándar

| Característica | Estándar Odoo | Ecuador |
|---|---|---|
| Estados | borrador → validado → cancelado | + `provisional` (cálculo sin facturas definitivas) |
| Líneas de costo | Una sola lista | Separadas: locales vs internacionales |
| Facturas | Opcional | Vinculación explícita con facturas de importación |
| Incoterms | No | Sí (FOB, CIF, DAP, etc.) |
| Último precio compra | No | Se actualiza automáticamente al validar |
| Tipo de compra | No | Filtra por `tipo_compra = 'importacion'` |

---

## Modelo de Datos

### Extensión de `costos_aterrizaje`

```sql
ALTER TABLE costos_aterrizaje ADD COLUMN estado_extra        TEXT DEFAULT 'draft'
  CHECK (estado_extra IN ('draft', 'provisional', 'done', 'cancel'));
ALTER TABLE costos_aterrizaje ADD COLUMN incoterm_id         UUID REFERENCES incoterms(id);
ALTER TABLE costos_aterrizaje ADD COLUMN factura_gasto_ids   UUID[];   -- facturas de flete/seguro/arancel

-- Las líneas de costo se dividen en dos grupos por campo boolean:
ALTER TABLE costos_aterrizaje_lineas ADD COLUMN es_internacional BOOLEAN DEFAULT FALSE;
-- es_internacional = FALSE → costo local (bodegaje, transporte interno)
-- es_internacional = TRUE  → costo internacional (flete, seguro, arancel FOB)
```

### Tabla: `costos_aterrizaje_lineas` (extensión)

```sql
-- Campos estándar ya existentes:
-- costo_id, producto_id, precio, metodo_division (equal, by_quantity, by_current_cost, by_weight, by_volume)
-- Campo nuevo Ecuador:
ALTER TABLE costos_aterrizaje_lineas ADD COLUMN es_internacional BOOLEAN DEFAULT FALSE;
ALTER TABLE costos_aterrizaje_lineas ADD COLUMN porcentaje       NUMERIC(5,2);  -- para método porcentual
```

---

## Estados del Costo de Aterrizaje

```
BORRADOR
  → [Provisional] → PROVISIONAL (cálculo estimado sin facturas definitivas)
       → [Recalcular] → PROVISIONAL (actualiza con nuevos valores)
       → [Validar] → HECHO (aplica costos al inventario)
  → [Validar] → HECHO (directo desde borrador)
  → [Cancelar] → CANCELADO

PROVISIONAL: permite ver el impacto estimado en el costo de productos
             sin generar asientos contables definitivos
```

---

## Métodos de Distribución de Costos

| Método | Descripción |
|---|---|
| `equal` | Costo dividido en partes iguales entre todos los productos |
| `by_quantity` | Proporcional a la cantidad recibida |
| `by_current_cost` | Proporcional al costo actual del producto |
| `by_weight` | Proporcional al peso del producto |
| `by_volume` | Proporcional al volumen del producto |

---

## Funciones RPC

```typescript
// Calcular preliminar (estado provisional)
calcular_provisional(params: {
  costo_id: UUID
}): {
  costo_id: UUID
  estado: 'provisional'
  lineas_valoracion: [{
    producto_id: UUID
    picking_id: UUID
    costo_adicional: number
    nuevo_costo_unitario: number
  }]
}

// Validar costo de aterrizaje (genera asientos y actualiza costos)
validar_costo_aterrizaje(params: {
  costo_id: UUID
}): {
  costo_id: UUID
  estado: 'done'
  asiento_id: UUID
  productos_actualizados: [{
    producto_id: UUID
    ultimo_precio_compra: number
    ultimo_proveedor_id: UUID
    ultima_fecha_compra: string
  }]
}

// Cancelar y eliminar (solo desde borrador/provisional)
cancelar_costo_aterrizaje(costo_id: UUID): { eliminado: boolean }

// Vincular facturas de gastos
vincular_facturas(params: {
  costo_id: UUID
  factura_ids: UUID[]
}): { costo_id: UUID, facturas_vinculadas: number }

// Obtener costos de aterrizaje por importación
get_costos_importacion(importacion_id: UUID): [{
  costo_id: UUID
  nombre: string
  estado: string
  total_costos_locales: number
  total_costos_internacionales: number
  pickings: string[]
}]
```

---

## Actualización Automática de Precio de Compra

Al validar un costo de aterrizaje vinculado a una orden de compra de importación:

```
Para cada producto en los pickings valorados:
  precio_unitario_final = (precio_OC + costo_distribuido) / cantidad

  producto.ultimo_precio_compra = precio_unitario_final
  producto.ultimo_proveedor = OC.proveedor
  producto.ultima_fecha_compra = OC.fecha
```

---

## Validaciones de Negocio

- Solo puede estar en `provisional` si está en `draft` o ya en `provisional`
- Para validar: debe tener al menos un `picking` vinculado en estado `done`
- Los costos internacionales generalmente se cargan al costo del producto (método: `by_quantity` o `by_current_cost`)
- Los costos locales pueden cargarse al costo o registrarse como gasto del período
- No se puede editar un costo en estado `done`; crear notas de crédito para revertir
- Al cancelar desde `provisional`: no hay asientos que revertir; se elimina el registro

---

## Configuración por Empresa

```json
{
  "costos_aterrizaje": {
    "cuenta_diferencia_costo_id": "uuid",
    "metodo_division_default": "by_quantity",
    "actualizar_precio_compra": true,
    "mostrar_costos_internacionales": true
  }
}
```

---

## Pantallas Flutter

### Formulario de Costo de Aterrizaje

```
┌────────────────────────────────────────────────────────────────┐
│ COSTO DE ATERRIZAJE — LC-0012                   PROVISIONAL    │
│ Incoterm: [CIF ▼]    Facturas gastos: [FAC-001, FAC-002]      │
├────────────────────────────────────────────────────────────────┤
│ TRANSFERENCIAS VINCULADAS                                      │
│ [REC-0088 — Laptop ASUS ×10, Mouse ×20]        [+ Agregar]   │
├────────────────────────────────────────────────────────────────┤
│ COSTOS INTERNACIONALES                                         │
│ Producto        │ Descripción    │ Monto      │ Método        │
│ Flete marino    │ DHL Express    │ $1,200.00  │ Por cantidad  │
│ Seguro          │ Aseguradora EC │  $150.00   │ Por costo     │
│ Arancel CIF     │ SENAE          │  $800.00   │ Por costo     │
├────────────────────────────────────────────────────────────────┤
│ COSTOS LOCALES                                                 │
│ Bodegaje EXPO   │ Terminal Guay. │  $200.00   │ Equitativo    │
├────────────────────────────────────────────────────────────────┤
│ [Calcular Provisional]  [Validar]  [Cancelar]                  │
└────────────────────────────────────────────────────────────────┘
```

### Vista de Impacto por Producto (Provisional)

| Producto | Costo Base | Costo Aterrizaje | Nuevo Costo Unit |
|---|---|---|---|
| Laptop ASUS X15 | $850.00 | $213.50 | $1,063.50 |
| Mouse USB Logitech | $15.00 | $3.85 | $18.85 |

---

## Modelo de Datos Completo (Tablas PILAR)

La versión PILAR nativa reemplaza la extensión de tablas Odoo con tablas propias que incorporan desde el inicio el contexto Ecuador (incoterms, multi-moneda, distribución):

```sql
CREATE TABLE costos_aterrizaje (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  recepcion_id    UUID NOT NULL REFERENCES recepciones_compra(id),
  nombre          VARCHAR(100) NOT NULL,    -- "LC-0012" o "Aterrizaje Importación China Ene-2026"
  estado          VARCHAR(20) DEFAULT 'PROVISIONAL'
                  CHECK (estado IN ('PROVISIONAL','CONFIRMADO','DISTRIBUIDO')),
  incoterm        VARCHAR(10)
                  CHECK (incoterm IN ('FOB','CIF','EXW','DDP','FCA','CFR','DAP','DAT')),
  asiento_id      UUID,                     -- Referencia al asiento contable (soft)
  notas           TEXT,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE costos_aterrizaje ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON costos_aterrizaje FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE TABLE costos_aterrizaje_lineas (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  costo_id              UUID NOT NULL REFERENCES costos_aterrizaje(id) ON DELETE CASCADE,
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  concepto              VARCHAR(100) NOT NULL,
                        -- 'FLETE_MARITIMO','FLETE_AEREO','SEGURO','ARANCEL',
                        -- 'FODINFA','IVA_IMPORTACION','AGENTE_ADUANA','TRANSPORTE_LOCAL','OTROS'
  tipo                  VARCHAR(15) NOT NULL CHECK (tipo IN ('LOCAL','INTERNACIONAL')),
  proveedor_id          UUID REFERENCES contactos(id),    -- Naviera, agente de aduana, etc.
  factura_proveedor_id  UUID,                              -- Factura del servicio (soft ref)
  monto                 DECIMAL(14,2) NOT NULL CHECK (monto > 0),
  moneda_id             VARCHAR(3) DEFAULT 'USD',
  tasa_cambio           DECIMAL(18,8) DEFAULT 1.00000000,
  monto_usd             DECIMAL(14,2) GENERATED ALWAYS AS
                          (ROUND(monto * tasa_cambio, 2)) STORED,
  metodo_distribucion   VARCHAR(20) DEFAULT 'VALOR'
                        CHECK (metodo_distribucion IN ('VALOR','CANTIDAD','PESO','VOLUMEN'))
);

ALTER TABLE costos_aterrizaje_lineas ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON costos_aterrizaje_lineas FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE TABLE costos_aterrizaje_distribucion (
  id                        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  costo_linea_id            UUID NOT NULL REFERENCES costos_aterrizaje_lineas(id),
  producto_id               UUID NOT NULL REFERENCES productos(id),
  cantidad                  DECIMAL(18,6) NOT NULL,
  costo_asignado            DECIMAL(14,2) NOT NULL,     -- Monto distribuido a este producto
  costo_unitario_adicional  DECIMAL(14,6) NOT NULL,     -- costo_asignado / cantidad
  applied                   BOOLEAN DEFAULT FALSE       -- true = ya sumado al CPP del producto
);
```

---

## Funciones RPC Adicionales

### `distribute_landing_costs` — Distribución proporcional entre productos

```sql
CREATE OR REPLACE FUNCTION distribute_landing_costs(p_costo_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_costo   RECORD;
  v_linea   RECORD;
  v_totales RECORD;
  v_base    DECIMAL(14,2);
  v_prod    RECORD;
BEGIN
  SELECT ca.*, rc.id AS recepcion_id
  INTO v_costo
  FROM costos_aterrizaje ca
  JOIN recepciones_compra rc ON rc.id = ca.recepcion_id
  WHERE ca.id = p_costo_id
    AND ca.empresa_id = (SELECT private.get_empresa_id())
    AND ca.estado = 'CONFIRMADO';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Costo de aterrizaje no encontrado o no está confirmado';
  END IF;

  -- Eliminar distribución previa si existe
  DELETE FROM costos_aterrizaje_distribucion
  WHERE costo_linea_id IN (
    SELECT id FROM costos_aterrizaje_lineas WHERE costo_id = p_costo_id
  );

  -- Para cada línea de costo
  FOR v_linea IN
    SELECT * FROM costos_aterrizaje_lineas WHERE costo_id = p_costo_id
  LOOP
    -- Calcular base de distribución según método
    CASE v_linea.metodo_distribucion
      WHEN 'VALOR' THEN
        SELECT SUM(rl.precio_unitario * rl.cantidad) INTO v_base
        FROM recepcion_lineas rl WHERE rl.recepcion_id = v_costo.recepcion_id;

      WHEN 'CANTIDAD' THEN
        SELECT SUM(rl.cantidad) INTO v_base
        FROM recepcion_lineas rl WHERE rl.recepcion_id = v_costo.recepcion_id;

      WHEN 'PESO' THEN
        SELECT SUM(rl.cantidad * p.peso_bruto) INTO v_base
        FROM recepcion_lineas rl
        JOIN productos p ON p.id = rl.producto_id
        WHERE rl.recepcion_id = v_costo.recepcion_id;

      WHEN 'VOLUMEN' THEN
        SELECT SUM(rl.cantidad * p.volumen) INTO v_base
        FROM recepcion_lineas rl
        JOIN productos p ON p.id = rl.producto_id
        WHERE rl.recepcion_id = v_costo.recepcion_id;
    END CASE;

    IF COALESCE(v_base, 0) = 0 THEN
      RAISE EXCEPTION 'Base de distribución % = 0 para método %. Verificar datos de productos.',
        v_linea.metodo_distribucion, v_linea.concepto;
    END IF;

    -- Distribuir proporcionalmente a cada producto de la recepción
    FOR v_prod IN
      SELECT rl.producto_id, rl.cantidad, rl.precio_unitario,
        CASE v_linea.metodo_distribucion
          WHEN 'VALOR'    THEN rl.precio_unitario * rl.cantidad / v_base
          WHEN 'CANTIDAD' THEN rl.cantidad / v_base
          WHEN 'PESO'     THEN (rl.cantidad * p.peso_bruto) / v_base
          WHEN 'VOLUMEN'  THEN (rl.cantidad * p.volumen) / v_base
        END AS proporcion
      FROM recepcion_lineas rl
      JOIN productos p ON p.id = rl.producto_id
      WHERE rl.recepcion_id = v_costo.recepcion_id
    LOOP
      INSERT INTO costos_aterrizaje_distribucion (
        costo_linea_id, producto_id, cantidad,
        costo_asignado, costo_unitario_adicional
      ) VALUES (
        v_linea.id,
        v_prod.producto_id,
        v_prod.cantidad,
        ROUND(v_linea.monto_usd * v_prod.proporcion, 2),
        ROUND(v_linea.monto_usd * v_prod.proporcion / NULLIF(v_prod.cantidad, 0), 6)
      );
    END LOOP;
  END LOOP;

  -- Actualizar CPP de cada producto con el costo adicional distribuido
  UPDATE productos p
  SET costo_promedio = ROUND(
    p.costo_promedio + (
      SELECT SUM(d.costo_unitario_adicional)
      FROM costos_aterrizaje_distribucion d
      JOIN costos_aterrizaje_lineas cal ON cal.id = d.costo_linea_id
      WHERE cal.costo_id = p_costo_id AND d.producto_id = p.id
    ), 6
  )
  WHERE p.id IN (
    SELECT DISTINCT d.producto_id
    FROM costos_aterrizaje_distribucion d
    JOIN costos_aterrizaje_lineas cal ON cal.id = d.costo_linea_id
    WHERE cal.costo_id = p_costo_id
  );

  -- Marcar distribución como aplicada
  UPDATE costos_aterrizaje_distribucion d SET applied = TRUE
  FROM costos_aterrizaje_lineas cal
  WHERE cal.id = d.costo_linea_id AND cal.costo_id = p_costo_id;

  UPDATE costos_aterrizaje SET estado = 'DISTRIBUIDO' WHERE id = p_costo_id;
END;
$$;
```

### `calculate_total_import_cost` — Análisis completo de costo de importación

```sql
CREATE OR REPLACE FUNCTION calculate_total_import_cost(p_recepcion_id UUID)
RETURNS TABLE (
  producto_id          UUID,
  producto_nombre      TEXT,
  cantidad             DECIMAL(18,6),
  costo_fob_unitario   DECIMAL(14,6),   -- Precio de la OC (valor producto)
  costo_aterrizaje_unit DECIMAL(14,6),  -- Suma de todos los costos distribuidos
  costo_real_unit      DECIMAL(14,6),   -- costo_fob + costo_aterrizaje
  pct_sobre_fob        DECIMAL(5,2),    -- % que representan los costos s/ valor FOB
  valor_fob_total      DECIMAL(14,2),
  valor_aterrizaje_total DECIMAL(14,2),
  costo_real_total     DECIMAL(14,2)
) LANGUAGE sql SECURITY DEFINER AS $$
  SELECT
    rl.producto_id,
    p.nombre AS producto_nombre,
    rl.cantidad,
    rl.precio_unitario                          AS costo_fob_unitario,
    COALESCE(SUM(d.costo_unitario_adicional), 0) AS costo_aterrizaje_unit,
    rl.precio_unitario + COALESCE(SUM(d.costo_unitario_adicional), 0) AS costo_real_unit,
    CASE WHEN rl.precio_unitario > 0
         THEN ROUND(COALESCE(SUM(d.costo_unitario_adicional), 0) / rl.precio_unitario * 100, 2)
         ELSE 0 END                             AS pct_sobre_fob,
    ROUND(rl.precio_unitario * rl.cantidad, 2)  AS valor_fob_total,
    ROUND(COALESCE(SUM(d.costo_unitario_adicional), 0) * rl.cantidad, 2) AS valor_aterrizaje_total,
    ROUND((rl.precio_unitario + COALESCE(SUM(d.costo_unitario_adicional), 0)) * rl.cantidad, 2)
                                                AS costo_real_total
  FROM recepcion_lineas rl
  JOIN productos p ON p.id = rl.producto_id
  LEFT JOIN costos_aterrizaje ca ON ca.recepcion_id = rl.recepcion_id
  LEFT JOIN costos_aterrizaje_lineas cal ON cal.costo_id = ca.id
  LEFT JOIN costos_aterrizaje_distribucion d ON d.costo_linea_id = cal.id
    AND d.producto_id = rl.producto_id
  WHERE rl.recepcion_id = p_recepcion_id
    AND rl.empresa_id = (SELECT private.get_empresa_id())
  GROUP BY rl.producto_id, p.nombre, rl.cantidad, rl.precio_unitario;
$$;
```

---

## Incoterms Ecuador — Los Más Usados

Ecuador importa principalmente bajo FOB y CIF. Los incoterms determinan qué costos carga el importador:

| Incoterm | Quién paga flete int. | Quién paga seguro | Quién paga aduana EC | Uso típico |
|----------|:---:|:---:|:---:|---|
| **FOB** | Importador | Importador | Importador | China, USA (manufactura) |
| **CIF** | Exportador | Exportador | Importador | Europa, commodities |
| **EXW** | Importador | Importador | Importador | Cuando importador controla toda la logística |
| **DDP** | Exportador | Exportador | Exportador | Mínimo trámite, precio todo incluido |
| **FCA** | Importador (desde origen) | Importador | Importador | Carga aérea |

---

## Costos Típicos Importación Ecuador

Estructura de costos para una importación estándar (FOB China → Guayaquil):

| # | Concepto | Tipo | Método distribución | Referencia |
|---|----------|------|---------------------|------------|
| 1 | Precio FOB proveedor | Costo producto | — | Factura proveedor |
| 2 | Flete marítimo | INTERNACIONAL | VALOR o CANTIDAD | Naviera / freight forwarder |
| 3 | Seguro de transporte | INTERNACIONAL | VALOR | ~1% del valor FOB |
| 4 | Arancel ad valorem | INTERNACIONAL | VALOR | 0-45% según partida NANDINA |
| 5 | FODINFA | INTERNACIONAL | VALOR | 0.5% del valor CIF |
| 6 | IVA importación | INTERNACIONAL | VALOR | 15% sobre valor aduanero total |
| 7 | Agente de aduana | LOCAL | CANTIDAD | Comisión fija o % |
| 8 | Bodegaje/terminal | LOCAL | CANTIDAD | Puerto o terminal privado |
| 9 | Transporte local | LOCAL | PESO o VOLUMEN | Del puerto a bodega |

**Valor aduanero** = valor FOB + flete internacional + seguro

**Base IVA** = valor aduanero + arancel + FODINFA + otros aranceles

**Ejemplo numérico:**

```
Importación: 100 laptops desde China, FOB $850/und = $85,000 total

Flete marítimo:       $2,400.00
Seguro:               $  850.00   (1% del FOB)
─────────────────────────────────
Valor CIF:           $88,250.00

Arancel (0%):         $      0    (partida NANDINA 847130)
FODINFA (0.5% CIF):   $  441.25
─────────────────────────────────
Base IVA:            $88,691.25

IVA importación (15%):$13,303.69
Agente aduana:        $  500.00
Transporte local:     $  350.00
─────────────────────────────────
Costo total aterrizaje: $17,844.94
Costo aterrizaje/laptop: $178.45

Costo real laptop: $850.00 + $178.45 = $1,028.45
% costos s/FOB: 21.0%
```

---

## RLS e Índices

```sql
-- Índices para costos_aterrizaje
CREATE INDEX idx_cost_aterr_empresa_estado
  ON costos_aterrizaje (empresa_id, estado);
CREATE INDEX idx_cost_aterr_recepcion
  ON costos_aterrizaje (recepcion_id);

-- Índices para costos_aterrizaje_lineas
CREATE INDEX idx_cost_aterr_lineas_costo
  ON costos_aterrizaje_lineas (costo_id);
CREATE INDEX idx_cost_aterr_lineas_proveedor
  ON costos_aterrizaje_lineas (empresa_id, proveedor_id)
  WHERE proveedor_id IS NOT NULL;

-- Índice para distribución
CREATE INDEX idx_cost_aterr_dist_linea
  ON costos_aterrizaje_distribucion (costo_linea_id);
CREATE INDEX idx_cost_aterr_dist_producto
  ON costos_aterrizaje_distribucion (producto_id)
  WHERE applied = FALSE;
```
