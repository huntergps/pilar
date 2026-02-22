# Importaciones y Costos Aduaneros (Compras)

*Spec derivada del módulo `l10n_ec_importaciones` (Odoo 19.1 Ecuador — producción en csolish/tecnoh)*

---

## Descripción

Extensión del módulo de Costos de Aterrizaje (Landed Costs) para el proceso de importación ecuatoriano. Permite registrar y distribuir costos aduaneros (aranceles, seguros, fletes, gastos de aduana) entre los productos importados, usando la **partida arancelaria** del Sistema Armonizado como base de distribución proporcional.

---

## Conceptos Ecuador

| Concepto | Descripción |
|---|---|
| **Partida Arancelaria** | Código NANDINA/HS de 10 dígitos que clasifica el producto en aduana |
| **Ad Valorem** | Arancel como % sobre el valor CIF de la mercancía |
| **Fodinfa** | Fondo de desarrollo infantil (0.5% sobre CIF) |
| **ICE** | Impuesto a Consumos Especiales (varía por partida) |
| **DAU** | Declaración Aduanera Única — documento principal de importación |
| **CIF** | Costo + Seguro + Flete (valor de referencia para aranceles) |

---

## Flujo General

```
1. Crear Importación (cabecera con DAU, fecha, proveedor)
     ↓
2. Vincular recepciones de mercancía (pickings/receipts)
     ↓
3. Registrar líneas de costo:
   - Flete internacional
   - Seguro
   - Arancel Ad Valorem (por partida arancelaria)
   - Fodinfa
   - Gastos agente aduanero
     ↓
4. Calcular distribución proporcional (por partida o por valor)
     ↓
5. Validar → genera asientos de valoración de inventario
```

---

## Modelo de Datos

### Tabla: `importaciones` (cabecera)

```sql
CREATE TABLE importaciones (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  nombre                TEXT,                         -- Secuencia: IMP-00001
  referencia            TEXT,                         -- # DAU / # declaración
  fecha                 DATE NOT NULL DEFAULT CURRENT_DATE,
  fecha_embarque        DATE,
  proveedor_id          UUID REFERENCES contactos(id),
  pais_origen_id        UUID REFERENCES catalogo_paises(id),
  incoterm              TEXT,                         -- FOB, CIF, EXW, etc.
  moneda_id             UUID REFERENCES monedas(id),
  tipo_cambio           NUMERIC(15,6) DEFAULT 1,
  estado                TEXT NOT NULL DEFAULT 'borrador'
                        CHECK (estado IN ('borrador','confirmado','validado','cancelado')),
  -- Totales
  valor_fob             NUMERIC(15,2) DEFAULT 0,
  valor_flete           NUMERIC(15,2) DEFAULT 0,
  valor_seguro          NUMERIC(15,2) DEFAULT 0,
  valor_cif             NUMERIC(15,2) GENERATED ALWAYS AS
                        (valor_fob + valor_flete + valor_seguro) STORED,
  total_aranceles       NUMERIC(15,2) DEFAULT 0,
  total_costos_locales  NUMERIC(15,2) DEFAULT 0,
  -- Notas
  notas                 TEXT,
  creado_en             TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE importaciones ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON importaciones FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));
```

### Tabla: `partidas_arancelarias` (catálogo)

```sql
CREATE TABLE partidas_arancelarias (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  codigo                TEXT NOT NULL,               -- 10 dígitos NANDINA
  descripcion           TEXT NOT NULL,
  -- Tasas vigentes (actualizables)
  tasa_ad_valorem       NUMERIC(8,4) DEFAULT 0,      -- % sobre CIF
  tasa_fodinfa          NUMERIC(8,4) DEFAULT 0.5,    -- siempre 0.5% sobre CIF
  tasa_ice              NUMERIC(8,4) DEFAULT 0,
  -- Prohibiciones/restricciones
  restringido           BOOLEAN DEFAULT FALSE,
  activa                BOOLEAN DEFAULT TRUE
);
```

### Tabla: `importacion_costos` (líneas de costo = landed costs)

```sql
CREATE TABLE importacion_costos (
  id                        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id                UUID NOT NULL REFERENCES empresas(id),
  importacion_id            UUID NOT NULL REFERENCES importaciones(id) ON DELETE CASCADE,
  nombre                    TEXT NOT NULL,             -- "Flete marítimo", "Ad Valorem", etc.
  tipo_costo                TEXT NOT NULL
                            CHECK (tipo_costo IN (
                              'flete','seguro','arancel','fodinfa','ice',
                              'agente_aduana','almacenaje','otro'
                            )),
  cuenta_id                 UUID REFERENCES cuentas_contables(id),
  monto                     NUMERIC(15,2) NOT NULL DEFAULT 0,
  -- Distribución por partida arancelaria
  aplica_partida            BOOLEAN DEFAULT FALSE,     -- distribuir por partida vs por valor
  aplica_porcentaje_aduana  BOOLEAN DEFAULT FALSE,     -- usar % en lugar de monto fijo
  porcentaje_aduana         NUMERIC(8,4) DEFAULT 0,   -- % sobre CIF si aplica_porcentaje=true
  -- Método de distribución (igual que landed costs estándar)
  metodo_distribucion       TEXT DEFAULT 'por_valor_actual'
                            CHECK (metodo_distribucion IN (
                              'por_cantidad','por_valor_actual','por_peso_neto','por_volumen'
                            ))
);
```

### Tabla: `importacion_ajustes` (resultado de distribución por producto)

```sql
CREATE TABLE importacion_ajustes (
  id                        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id                UUID NOT NULL REFERENCES empresas(id),
  importacion_id            UUID NOT NULL REFERENCES importaciones(id),
  costo_id                  UUID REFERENCES importacion_costos(id),
  producto_id               UUID REFERENCES productos(id),
  move_id                   UUID,                      -- stock move de la recepción
  -- Partida arancelaria del producto
  partida_arancelaria_id    UUID REFERENCES partidas_arancelarias(id),
  porcentaje_partida        NUMERIC(8,4) DEFAULT 0,   -- % que le corresponde del costo
  -- Valores calculados
  cantidad                  NUMERIC(15,4) DEFAULT 0,
  valor_adicional           NUMERIC(15,2) DEFAULT 0,  -- costo adicional al producto
  costo_unitario_anterior   NUMERIC(15,4) DEFAULT 0,
  costo_unitario_nuevo      NUMERIC(15,4) DEFAULT 0,
  -- Asiento generado
  asiento_id                UUID REFERENCES asientos_contables(id)
);
```

---

## Lógica de Distribución

### Distribución estándar (por valor/cantidad/peso)

Para costos sin `aplica_partida`:
```
costo_por_producto = monto_costo * (valor_producto / valor_total_importacion)
```

### Distribución por Partida Arancelaria

Para costos con `aplica_partida = true` (típicamente aranceles):

```
1. Agrupar productos por partida_arancelaria_id
2. Para cada partida: porcentaje_partida = CIF_partida / CIF_total
3. costo_partida = monto_costo * porcentaje_partida
4. Distribuir costo_partida entre productos de esa partida por cantidad/valor
```

### Distribución por Porcentaje Aduanero

Para costos con `aplica_porcentaje_aduana = true`:
```
monto_real = valor_cif_total * (porcentaje_aduana / 100)
// Luego distribuir monto_real como en el método anterior
```

---

## Funciones RPC

```typescript
// Crear importación
create_importacion(params: {
  referencia: string         // # DAU
  fecha: string
  proveedor_id?: UUID
  pais_origen_id?: UUID
  incoterm?: string
  valor_fob?: number
  valor_flete?: number
  valor_seguro?: number
}): { importacion_id: UUID, nombre: string }

// Vincular recepciones de mercancía
vincular_recepciones(params: {
  importacion_id: UUID
  picking_ids: UUID[]        // recepciones de compra validadas
}): { productos_vinculados: number }

// Agregar línea de costo
agregar_costo(params: {
  importacion_id: UUID
  nombre: string
  tipo_costo: string
  cuenta_id: UUID
  monto?: number
  aplica_partida?: boolean
  aplica_porcentaje_aduana?: boolean
  porcentaje_aduana?: number
  metodo_distribucion?: string
}): { costo_id: UUID }

// Calcular distribución (preview sin guardar)
calcular_distribucion(importacion_id: UUID): {
  ajustes: [{
    producto_id: UUID
    nombre: string
    partida_arancelaria: string
    costo_adicional: number
    costo_unitario_anterior: number
    costo_unitario_nuevo: number
  }]
  total_costos: number
}

// Validar importación (genera asientos y actualiza valoración)
validar_importacion(importacion_id: UUID): {
  asientos: UUID[]
  productos_actualizados: number
}

// Cancelar importación
cancelar_importacion(importacion_id: UUID): void

// Consultar partidas arancelarias
search_partidas(query: string): PartidaArancelaria[]
```

---

## Asientos Contables Generados

### Por cada costo adicional distribuido al producto:

```
DEBE: 1.1.6.x Inventario (cuenta valoración del producto)   valor_adicional
HABER: 2.1.x.x Cuenta de Costo (flete/arancel/etc.)        valor_adicional
```

### Pago de aranceles a aduana:

```
DEBE: 2.1.x.x Cuentas por Pagar Aduana   total_aranceles
HABER: 1.1.2.x Banco                      total_aranceles
```

---

## Configuración por Empresa

```json
{
  "importaciones": {
    "cuenta_flete_id": "uuid",
    "cuenta_seguro_id": "uuid",
    "cuenta_aranceles_id": "uuid",
    "cuenta_fodinfa_id": "uuid",
    "cuenta_agente_aduana_id": "uuid",
    "metodo_distribucion_default": "por_valor_actual",
    "moneda_importacion_id": "uuid",    // USD por defecto Ecuador
    "requiere_partida_arancelaria": true
  }
}
```

---

## Validaciones de Negocio

- Las recepciones vinculadas deben estar en estado `done` (validadas)
- No se puede validar sin al menos una recepción vinculada
- No se puede validar sin líneas de costo
- `valor_cif` = `valor_fob + valor_flete + valor_seguro` (calculado, no editable)
- Partida arancelaria obligatoria en producto si `requiere_partida_arancelaria = true`
- No se puede cancelar si tiene asientos publicados
- Suma de `porcentaje_partida` por costo debe ser 100% si `aplica_partida = true`

---

## Catálogo NANDINA Ecuador (referencia)

Las partidas más comunes en importaciones de tecnología:

| Partida | Descripción | Ad Valorem |
|---|---|---|
| 8471.30.00.00 | Computadoras portátiles | 0% |
| 8471.50.00.00 | Unidades de proceso (servidores) | 0% |
| 8517.12.00.00 | Teléfonos celulares | 0% |
| 8523.51.10.00 | Memorias USB | 0% |
| 8528.72.00.00 | Monitores | 0% |
| 3926.90.90.99 | Accesorios plástico | 10% |

> Las tasas se configuran en la tabla `partidas_arancelarias` y son actualizables por la empresa.

---

## Pantallas Flutter

### Lista de Importaciones
- `CrudScaffold<Importacion>` con filtros: estado, proveedor, rango fechas, país
- Columnas: nombre, referencia DAU, proveedor, país, valor CIF, total costos, estado

### Formulario de Importación

```
┌──────────────────────────────────────────────────────────┐
│ IMPORTACIÓN                               [IMP-00015]    │
│ DAU: [texto]   Proveedor: [selector]  País: [selector]   │
│ Fecha: [date]  Incoterm: [FOB▼]       T/C: [1.00]       │
├──────────────────────────────────────────────────────────┤
│ VALOR CIF                                                │
│ FOB: $15,000  +  Flete: $800  +  Seguro: $150          │
│ CIF: $15,950                                             │
├──────────────────────────────────────────────────────────┤
│ RECEPCIONES VINCULADAS                                   │
│ • REC/2026/00123 — 50 und Laptop ASUS (8471.30)         │
│ • REC/2026/00124 — 100 und Mouse USB (8471.60)          │
│ [+ Vincular Recepción]                                   │
├──────────────────────────────────────────────────────────┤
│ COSTOS A DISTRIBUIR                                      │
│ ┌──────────────────┬───────────┬─────────┬─────────────┐ │
│ │ Concepto         │ Tipo      │ Monto   │ Distribución│ │
│ ├──────────────────┼───────────┼─────────┼─────────────┤ │
│ │ Flete marítimo   │ flete     │ $800    │ por valor   │ │
│ │ Ad Valorem       │ arancel   │ 0%      │ por partida │ │
│ │ Fodinfa          │ fodinfa   │ 0.5%    │ por partida │ │
│ │ Agente Aduana    │ agente    │ $350    │ por valor   │ │
│ └──────────────────┴───────────┴─────────┴─────────────┘ │
│ [+ Agregar Costo]                                        │
├──────────────────────────────────────────────────────────┤
│ [Vista Previa Distribución]  [Validar]  [Cancelar]      │
└──────────────────────────────────────────────────────────┘
```

### Vista Previa de Distribución

Tabla expandible con:
- Producto | Partida | Cant. | Costo adicional | C.U. anterior | C.U. nuevo | Variación %
- Subtotales por partida arancelaria
- Total general de costos distribuidos
