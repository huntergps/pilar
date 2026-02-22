# Requisiciones de Compra Internas

## Descripción

Flujo interno de solicitud de compra antes de generar una Orden de Compra formal.

```
Departamento solicita → Aprobación gerencial → Convierte en OC
```

## Tablas

```sql
CREATE TABLE requisiciones_compra (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id       UUID NOT NULL REFERENCES empresas(id),
  departamento_id  UUID,           -- soft ref → departamentos
  solicitante_id   UUID NOT NULL REFERENCES auth.users(id),
  numero           VARCHAR(20),    -- Secuencial auto: REQ-000001
  fecha            DATE NOT NULL DEFAULT CURRENT_DATE,
  estado           VARCHAR(25) DEFAULT 'BORRADOR',
    -- BORRADOR → PENDIENTE_APROBACION → APROBADA → RECHAZADA → CONVERTIDA
  notas            TEXT,
  aprobado_por     UUID REFERENCES auth.users(id),
  fecha_aprobacion TIMESTAMPTZ,
  motivo_rechazo   TEXT,
  created_at       TIMESTAMPTZ DEFAULT now(),
  updated_at       TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE requisicion_compra_lineas (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  requisicion_id   UUID NOT NULL REFERENCES requisiciones_compra(id) ON DELETE CASCADE,
  producto_id      UUID NOT NULL REFERENCES productos(id),
  cantidad         DECIMAL(18,6) NOT NULL,
  unidad_medida_id UUID REFERENCES unidades_medida(id),
  motivo           TEXT,           -- Justificación de la solicitud
  orden_compra_id  UUID,           -- soft ref → ordenes_compra (NULL hasta conversión)
  orden            INTEGER DEFAULT 0
);

ALTER TABLE requisiciones_compra ENABLE ROW LEVEL SECURITY;
CREATE POLICY "empresa_isolation" ON requisiciones_compra
  USING (empresa_id = (SELECT private.get_empresa_id()));
```

## RPCs

### `approve_requisition(p_requisicion_id, p_aprobado_por)` — Aprobar requisición

```sql
CREATE OR REPLACE FUNCTION approve_requisition(
  p_requisicion_id UUID,
  p_aprobado_por   UUID
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE requisiciones_compra SET
    estado = 'APROBADA',
    aprobado_por = p_aprobado_por,
    fecha_aprobacion = now()
  WHERE id = p_requisicion_id AND estado = 'PENDIENTE_APROBACION';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Requisicion no encontrada o no está pendiente de aprobación';
  END IF;
END;
$$;
```

### `convert_requisition_to_po(p_requisicion_id, p_proveedor_id)` — Convertir a OC

Crea una Orden de Compra a partir de una requisición aprobada. Usa el último precio de compra
al proveedor seleccionado como precio sugerido, con fallback a `costo_promedio` del producto.

```sql
-- Retorna el UUID de la OC creada
SELECT convert_requisition_to_po('req-uuid', 'proveedor-uuid');
```

**Lógica:**
1. Valida que la requisición esté en estado `APROBADA`
2. Resuelve el proveedor: parámetro explícito o `productos.proveedor_preferido_id`
3. Crea la OC en estado `BORRADOR`
4. Copia líneas: busca último precio de compra al proveedor, fallback a `costo_promedio`
5. Vincula las líneas a la OC generada
6. Marca la requisición como `CONVERTIDA`

## Permisos Recomendados

| Acción | Permiso |
|--------|---------|
| Crear/editar requisición | `compras.requisiciones.crear` |
| Aprobar | `compras.requisiciones.aprobar` |
| Rechazar | `compras.requisiciones.aprobar` |
| Convertir a OC | `compras.ordenes.crear` |

## Flujo de Estados

```
BORRADOR
  ↓ (solicitante envía)
PENDIENTE_APROBACION
  ↓ approve_requisition()      ↓ reject
APROBADA                    RECHAZADA
  ↓ convert_requisition_to_po()
CONVERTIDA
```
