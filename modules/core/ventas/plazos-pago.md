# Plazos de Pago Ecuador (Ventas)

*Spec derivada del módulo `l10n_ec_sale_payment_term` (Odoo 19.1 Ecuador — producción en csolish/tecnoh)*

---

## Descripción

Extensión de los términos de pago de Odoo para el contexto ecuatoriano. Agrega flags computados `is_cash` / `is_credit` a los plazos de pago y añade líneas de cuotas sobre las órdenes de venta para detallar fechas y montos de cada cuota al crédito.

---

## Modelo de Datos

### Extensión de `plazos_pago`

```sql
-- Los campos is_cash e is_credit se calculan, no se almacenan
-- is_cash  = true si alguna línea tiene nb_days = 0
-- is_credit = true si alguna línea tiene nb_days > 0
ALTER TABLE plazos_pago ADD COLUMN is_cash   BOOLEAN GENERATED ALWAYS AS (
  EXISTS (SELECT 1 FROM plazos_pago_lineas l WHERE l.plazo_id = plazos_pago.id AND l.nb_dias = 0)
) STORED;
ALTER TABLE plazos_pago ADD COLUMN is_credit BOOLEAN GENERATED ALWAYS AS (
  EXISTS (SELECT 1 FROM plazos_pago_lineas l WHERE l.plazo_id = plazos_pago.id AND l.nb_dias > 0)
) STORED;
```

### Tabla: `plazos_pago_lineas`

Líneas que definen las cuotas del plazo (fecha + porcentaje + días).

```sql
CREATE TABLE plazos_pago_lineas (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id  UUID NOT NULL REFERENCES empresas(id),
  plazo_id    UUID NOT NULL REFERENCES plazos_pago(id) ON DELETE CASCADE,
  nb_dias     INT NOT NULL DEFAULT 0,         -- 0 = contado, >0 = crédito
  porcentaje  NUMERIC(5,2) DEFAULT 100.00,    -- porcentaje del total
  dia_del_mes INT,                             -- vencimiento día fijo del mes
  tipo        TEXT DEFAULT 'percent'
              CHECK (tipo IN ('percent', 'fixed', 'balance'))
);
```

### Tabla: `ov_cuotas_pago` (detalle de cuotas en una OV)

Cuando la OV tiene plazo a crédito, se generan filas con fecha y monto por cuota.

```sql
CREATE TABLE ov_cuotas_pago (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id       UUID NOT NULL REFERENCES empresas(id),
  orden_venta_id   UUID NOT NULL REFERENCES ordenes_venta(id) ON DELETE CASCADE,
  fecha_vencimiento DATE NOT NULL,
  monto            NUMERIC(15,2) NOT NULL,
  porcentaje       NUMERIC(5,2),
  estado           TEXT DEFAULT 'pendiente'
                   CHECK (estado IN ('pendiente','pagado','vencido')),
  factura_id       UUID REFERENCES facturas(id)
);

ALTER TABLE ov_cuotas_pago ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON ov_cuotas_pago FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));
```

---

## Lógica de Negocio

### Clasificación de Términos de Pago

| Condición | is_cash | is_credit | Ejemplo |
|---|---|---|---|
| Todas las líneas con `nb_dias = 0` | true | false | Contado inmediato |
| Alguna línea con `nb_dias > 0` | false | true | 30 días, 60/90 días |
| Mixto (enganche + cuotas) | true | true | 30% hoy + 70% a 30 días |

### Generación de Cuotas al Confirmar OV

Al confirmar una orden de venta con plazo a crédito:
1. Se leen las líneas del `plazo_pago`
2. Se calcula la fecha de vencimiento: `fecha_confirmacion + nb_dias`
3. Se distribuye el monto total según `porcentaje` de cada línea
4. Se insertan filas en `ov_cuotas_pago`

### Integración con Control de Crédito

El campo `is_credit` en el plazo de pago es el trigger del módulo `credito-clientes`:
```
plazo_pago.is_credit = true → verificar límite de crédito del cliente
```

---

## Funciones RPC

```typescript
// Calcular cuotas para una OV dado el plazo
calcular_cuotas_ov(params: {
  orden_venta_id: UUID
  plazo_pago_id: UUID
  fecha_inicio?: string   // default: hoy
}): [{
  fecha_vencimiento: string
  monto: number
  porcentaje: number
}]

// Obtener plazos disponibles clasificados
get_plazos_pago(empresa_id: UUID): [{
  id: UUID
  nombre: string
  is_cash: boolean
  is_credit: boolean
  lineas: [{ nb_dias: number, porcentaje: number }]
}]

// Marcar cuota como pagada (al registrar cobro)
marcar_cuota_pagada(params: {
  cuota_id: UUID
  factura_id?: UUID
}): { cuota_id: UUID, estado: 'pagado' }
```

---

## Validaciones de Negocio

- Si el plazo tiene `is_credit = true`, se activa la verificación de crédito al confirmar la OV
- La suma de porcentajes de todas las líneas del plazo debe ser exactamente 100%
- Las cuotas se regeneran si se cambia el plazo de pago antes de confirmar la OV
- Una cuota pasa a `vencido` automáticamente si `fecha_vencimiento < hoy` y sigue `pendiente`

---

## Pantallas Flutter

### Selector de Plazo con Indicadores

```
Plazo de Pago: [▼ Crédito 30/60/90 días]
               ● CRÉDITO — se verificará límite de crédito
               Cuotas:
               - 33.33% — vence 17/03/2026
               - 33.33% — vence 16/04/2026
               - 33.34% — vence 16/05/2026
```

### Vista de Cuotas en Formulario de OV

| # | Fecha Vencimiento | Monto | Estado |
|---|---|---|---|
| 1 | 17/03/2026 | $333.33 | Pendiente |
| 2 | 16/04/2026 | $333.33 | Pendiente |
| 3 | 16/05/2026 | $333.34 | Pendiente |

---

## Modelo de Datos SQL Completo

### Tabla: `terminos_pago`

Catálogo maestro de términos de pago. Reemplaza / extiende la tabla `plazos_pago` de Odoo con semántica explícita para Ecuador.

```sql
CREATE TABLE terminos_pago (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  nombre          TEXT NOT NULL,                              -- ej: "Contado", "30 días", "30/60/90"
  descripcion     TEXT,
  es_contado      BOOLEAN NOT NULL DEFAULT TRUE,             -- calculado: todas las cuotas con dias=0
  es_credito      BOOLEAN NOT NULL DEFAULT FALSE,            -- calculado: alguna cuota con dias>0
  dias_plazo      INT NOT NULL DEFAULT 0,                    -- días totales del crédito (para CxC)
  genera_cxc      BOOLEAN NOT NULL DEFAULT FALSE,            -- TRUE = genera cuotas en CxC al facturar
  requiere_anticipo BOOLEAN NOT NULL DEFAULT FALSE,          -- requiere pago parcial antes de despacho
  porcentaje_anticipo DECIMAL(5,2) DEFAULT 0,               -- % del total a pagar como anticipo
  -- Cuotas: se definen en terminos_pago_cuotas. El campo cuotas es un resumen JSONB calculado
  cuotas_resumen  JSONB,                                     -- [{dias, porcentaje}] snapshot legible
  activo          BOOLEAN NOT NULL DEFAULT TRUE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE terminos_pago ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON terminos_pago FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE INDEX idx_terminos_pago_empresa  ON terminos_pago(empresa_id) WHERE activo = TRUE;
CREATE INDEX idx_terminos_pago_credito  ON terminos_pago(empresa_id) WHERE es_credito = TRUE AND activo = TRUE;
```

### Tabla: `terminos_pago_cuotas`

Detalla el plan de cuotas de un término de pago: porcentaje y días desde emisión.

```sql
CREATE TABLE terminos_pago_cuotas (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id       UUID NOT NULL REFERENCES empresas(id),
  termino_pago_id  UUID NOT NULL REFERENCES terminos_pago(id) ON DELETE CASCADE,
  numero_cuota     INT NOT NULL DEFAULT 1,                   -- 1, 2, 3...
  porcentaje       DECIMAL(5,2) NOT NULL DEFAULT 100.00,    -- % del total para esta cuota
  dias_desde_emision INT NOT NULL DEFAULT 0,                -- 0 = al momento de emisión
  dia_del_mes      INT,                                      -- si vence un día fijo del mes
  descripcion      TEXT,                                     -- ej: "Anticipo", "Cuota 1"
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE terminos_pago_cuotas ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON terminos_pago_cuotas FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE INDEX idx_terminos_cuotas_termino ON terminos_pago_cuotas(termino_pago_id);
CREATE INDEX idx_terminos_cuotas_empresa ON terminos_pago_cuotas(empresa_id);

-- Validar suma de porcentajes = 100 por término de pago (constraint diferida)
CREATE OR REPLACE FUNCTION ventas.check_termino_cuotas_sum()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE v_suma DECIMAL(6,2);
BEGIN
  SELECT COALESCE(SUM(porcentaje), 0) INTO v_suma
  FROM terminos_pago_cuotas
  WHERE termino_pago_id = NEW.termino_pago_id;

  IF v_suma > 100.01 THEN  -- tolerancia por redondeo
    RAISE EXCEPTION 'La suma de porcentajes de cuotas excede 100%% (actual: %%)', v_suma;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_check_cuotas_sum
  AFTER INSERT OR UPDATE ON terminos_pago_cuotas
  FOR EACH ROW EXECUTE FUNCTION ventas.check_termino_cuotas_sum();
```

### Extensión de `ov_cuotas_pago` (campos adicionales)

```sql
-- Añadir campos faltantes a la tabla existente (definida arriba como MVP)
ALTER TABLE ov_cuotas_pago
  ADD COLUMN IF NOT EXISTS numero_cuota      INT NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS termino_cuota_id  UUID REFERENCES terminos_pago_cuotas(id),
  ADD COLUMN IF NOT EXISTS cobro_id          UUID,             -- ref a cobro cuando se paga
  ADD COLUMN IF NOT EXISTS dias_vencido      INT GENERATED ALWAYS AS (
    CASE WHEN estado = 'pendiente' AND fecha_vencimiento < CURRENT_DATE
         THEN (CURRENT_DATE - fecha_vencimiento)
         ELSE 0 END
  ) STORED;

CREATE INDEX idx_ov_cuotas_vencidas ON ov_cuotas_pago(empresa_id, fecha_vencimiento)
  WHERE estado = 'pendiente';
```

---

## Funciones RPC SQL Completas

### `generate_payment_schedule(p_factura_id, p_termino_id)`

Genera las cuotas de CxC para una factura basadas en el término de pago. Llamada desde el pipeline de facturación al emitir.

```sql
CREATE OR REPLACE FUNCTION ventas.generate_payment_schedule(
  p_factura_id UUID,
  p_termino_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_empresa_id    UUID;
  v_factura       RECORD;
  v_termino       terminos_pago%ROWTYPE;
  v_cuota         terminos_pago_cuotas%ROWTYPE;
  v_monto_cuota   DECIMAL(14,2);
  v_monto_resto   DECIMAL(14,2);
  v_monto_acum    DECIMAL(14,2) := 0;
  v_fecha_vcto    DATE;
  v_cuotas_gen    INT := 0;
  v_total_cuotas  INT;
  v_cuota_num     INT := 0;
BEGIN
  v_empresa_id := (SELECT private.get_empresa_id());

  -- Obtener factura
  SELECT f.id, f.empresa_id, f.total_con_impuestos, f.fecha_emision,
         f.contacto_id, f.numero
  INTO v_factura
  FROM facturas f
  WHERE f.id = p_factura_id AND f.empresa_id = v_empresa_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Factura % no encontrada', p_factura_id;
  END IF;

  -- Obtener término de pago
  SELECT * INTO v_termino
  FROM terminos_pago
  WHERE id = p_termino_id AND empresa_id = v_empresa_id AND activo = TRUE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Término de pago no encontrado o inactivo';
  END IF;

  -- Eliminar cuotas anteriores de esta factura si se regenera
  DELETE FROM cuentas_por_cobrar
  WHERE factura_id = p_factura_id AND tipo = 'CUOTA';

  -- Contar cuotas del término
  SELECT COUNT(*) INTO v_total_cuotas
  FROM terminos_pago_cuotas
  WHERE termino_pago_id = p_termino_id;

  -- Generar cuota por cuota
  FOR v_cuota IN
    SELECT * FROM terminos_pago_cuotas
    WHERE termino_pago_id = p_termino_id
    ORDER BY numero_cuota
  LOOP
    v_cuota_num := v_cuota_num + 1;

    -- Calcular fecha de vencimiento
    v_fecha_vcto := v_factura.fecha_emision + v_cuota.dias_desde_emision;

    -- Si tiene día fijo del mes, ajustar al próximo mes con ese día
    IF v_cuota.dia_del_mes IS NOT NULL THEN
      v_fecha_vcto := DATE_TRUNC('month', v_fecha_vcto)
                    + MAKE_INTERVAL(months := 1)
                    + (v_cuota.dia_del_mes - 1) * INTERVAL '1 day';
    END IF;

    -- Monto de la cuota: si es la última, asignar el resto para evitar diff por redondeo
    IF v_cuota_num = v_total_cuotas THEN
      v_monto_cuota := v_factura.total_con_impuestos - v_monto_acum;
    ELSE
      v_monto_cuota := ROUND(v_factura.total_con_impuestos * v_cuota.porcentaje / 100.0, 2);
    END IF;

    v_monto_acum := v_monto_acum + v_monto_cuota;

    -- Insertar en CxC
    INSERT INTO cuentas_por_cobrar (
      empresa_id, factura_id, contacto_id,
      numero_cuota, fecha_emision, fecha_vencimiento,
      monto_original, monto_pendiente, tipo, estado
    ) VALUES (
      v_empresa_id, p_factura_id, v_factura.contacto_id,
      v_cuota_num, v_factura.fecha_emision, v_fecha_vcto,
      v_monto_cuota, v_monto_cuota, 'CUOTA', 'PENDIENTE'
    );

    v_cuotas_gen := v_cuotas_gen + 1;
  END LOOP;

  -- Llamar a module_bus.facturacion para registrar cuotas en el pipeline SRI
  PERFORM module_bus.facturacion.create_cxc_installments(
    jsonb_build_object(
      'factura_id',  p_factura_id,
      'empresa_id',  v_empresa_id,
      'total',       v_factura.total_con_impuestos,
      'termino_id',  p_termino_id,
      'cuotas_gen',  v_cuotas_gen
    )
  );

  RETURN jsonb_build_object(
    'success',      TRUE,
    'factura_id',   p_factura_id,
    'termino',      v_termino.nombre,
    'cuotas_generadas', v_cuotas_gen,
    'total_cuotas', v_factura.total_con_impuestos
  );
END;
$$;
```

### `get_next_due_date(p_factura_id)`

Retorna la próxima cuota de CxC pendiente de pago (fecha y monto) para la factura indicada.

```sql
CREATE OR REPLACE FUNCTION ventas.get_next_due_date(
  p_factura_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_empresa_id UUID;
  v_cuota      RECORD;
BEGIN
  v_empresa_id := (SELECT private.get_empresa_id());

  SELECT
    cxc.id,
    cxc.numero_cuota,
    cxc.fecha_vencimiento,
    cxc.monto_pendiente,
    cxc.dias_vencido,
    cxc.estado,
    CASE
      WHEN cxc.fecha_vencimiento < CURRENT_DATE THEN 'VENCIDA'
      WHEN cxc.fecha_vencimiento = CURRENT_DATE THEN 'VENCE_HOY'
      WHEN cxc.fecha_vencimiento <= CURRENT_DATE + 7 THEN 'POR_VENCER'
      ELSE 'VIGENTE'
    END AS alerta
  INTO v_cuota
  FROM cuentas_por_cobrar cxc
  WHERE cxc.factura_id   = p_factura_id
    AND cxc.empresa_id   = v_empresa_id
    AND cxc.estado       = 'PENDIENTE'
    AND cxc.tipo         = 'CUOTA'
  ORDER BY cxc.fecha_vencimiento ASC
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'found',   FALSE,
      'message', 'No hay cuotas pendientes para esta factura'
    );
  END IF;

  RETURN jsonb_build_object(
    'found',              TRUE,
    'cuota_id',           v_cuota.id,
    'numero_cuota',       v_cuota.numero_cuota,
    'fecha_vencimiento',  v_cuota.fecha_vencimiento,
    'monto_pendiente',    v_cuota.monto_pendiente,
    'dias_vencido',       v_cuota.dias_vencido,
    'alerta',             v_cuota.alerta
  );
END;
$$;
```

---

## Seed Data: Términos de Pago Estándar Ecuador

```sql
-- Insertar términos base al crear empresa
DO $$
DECLARE v_emp UUID := :empresa_id;
        v_t   UUID;
BEGIN
  -- 1. Contado inmediato
  INSERT INTO terminos_pago (empresa_id, nombre, es_contado, es_credito, dias_plazo, genera_cxc)
  VALUES (v_emp, 'Contado', TRUE, FALSE, 0, FALSE) RETURNING id INTO v_t;
  INSERT INTO terminos_pago_cuotas (empresa_id, termino_pago_id, numero_cuota, porcentaje, dias_desde_emision)
  VALUES (v_emp, v_t, 1, 100.00, 0);

  -- 2. Crédito 30 días
  INSERT INTO terminos_pago (empresa_id, nombre, es_contado, es_credito, dias_plazo, genera_cxc)
  VALUES (v_emp, 'Crédito 30 días', FALSE, TRUE, 30, TRUE) RETURNING id INTO v_t;
  INSERT INTO terminos_pago_cuotas (empresa_id, termino_pago_id, numero_cuota, porcentaje, dias_desde_emision)
  VALUES (v_emp, v_t, 1, 100.00, 30);

  -- 3. Crédito 30/60/90 días (3 cuotas 33.33% cada una)
  INSERT INTO terminos_pago (empresa_id, nombre, es_contado, es_credito, dias_plazo, genera_cxc)
  VALUES (v_emp, 'Crédito 30/60/90 días', FALSE, TRUE, 90, TRUE) RETURNING id INTO v_t;
  INSERT INTO terminos_pago_cuotas (empresa_id, termino_pago_id, numero_cuota, porcentaje, dias_desde_emision)
  VALUES
    (v_emp, v_t, 1, 33.33,  30),
    (v_emp, v_t, 2, 33.33,  60),
    (v_emp, v_t, 3, 33.34,  90);  -- última cuota absorbe diferencia de redondeo

  -- 4. Anticipo 30% + saldo 60 días
  INSERT INTO terminos_pago (empresa_id, nombre, es_contado, es_credito, dias_plazo,
                              genera_cxc, requiere_anticipo, porcentaje_anticipo)
  VALUES (v_emp, 'Anticipo 30% + 60 días', TRUE, TRUE, 60, TRUE, TRUE, 30.00)
  RETURNING id INTO v_t;
  INSERT INTO terminos_pago_cuotas (empresa_id, termino_pago_id, numero_cuota, porcentaje, dias_desde_emision, descripcion)
  VALUES
    (v_emp, v_t, 1, 30.00,  0,  'Anticipo'),
    (v_emp, v_t, 2, 70.00, 60,  'Saldo');
END;
$$;
```

---

## Integración con CxC (Module Service Bus)

Al emitir una factura a crédito, el pipeline de Facturación llama a este módulo para generar las cuotas:

```
facturacion.emit_invoice()
  → plazo_pago.es_credito = TRUE
  → module_bus.facturacion.create_cxc_installments(factura_id, termino_id)
     → ventas.generate_payment_schedule(factura_id, termino_id)
        → INSERT INTO cuentas_por_cobrar (cuotas)
        → notificacion al cliente con calendario de pagos
```

```sql
-- Gateway module_bus
CREATE OR REPLACE FUNCTION module_bus.facturacion.create_cxc_installments(p_params JSONB)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM modulos_empresa
    WHERE modulo_codigo = 'facturacion'
      AND empresa_id    = (p_params->>'empresa_id')::UUID
      AND activo        = TRUE
  ) THEN
    RETURN jsonb_build_object('success', FALSE, 'message', 'Módulo Facturación no activo');
  END IF;
  -- El módulo de ventas maneja la generación real; facturación solo valida
  RETURN jsonb_build_object('success', TRUE);
END;
$$;
```
