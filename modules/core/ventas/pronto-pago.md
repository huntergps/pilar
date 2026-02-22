# Descuento por Pronto Pago


#### Descripcion Funcional

Mecanismo de descuento automatico que incentiva el pago anticipado de facturas a credito. Ejemplo clasico: "2/10 neto 30" significa 2% de descuento si paga en los primeros 10 dias, total neto a 30 dias.

El descuento se configura en los terminos de pago (tabla existente `terminos_pago`) y se aplica automaticamente al registrar un cobro dentro del plazo de pronto pago. La diferencia se contabiliza como gasto/ingreso financiero.

**Flujo principal:**

```
CONFIGURACION:
  Admin crea termino de pago con descuento pronto pago:
    Ejemplo: "2/10 Net 30"
    - Linea 1: 100% del total, vence a 30 dias
    - Pronto pago: 2% descuento si paga antes del dia 10

EMISION FACTURA:
  Factura con termino "2/10 Net 30" → total $1,000
  - Vencimiento: 30 dias
  - Si paga antes del dia 10: descuento $20 → paga $980

COBRO DENTRO DEL PLAZO:
  Dia 8: cliente paga $980
  → Sistema detecta que aplica descuento pronto pago
  → Acepta $980 como pago total
  → Registra descuento de $20 como gasto financiero
  → CxC queda PAGADA (saldo = 0)
  → Asiento: Banco $980 + Desc. concedido $20 = CxC $1,000

COBRO FUERA DEL PLAZO:
  Dia 25: cliente intenta pagar $980
  → Sistema no aplica descuento (fuera de plazo)
  → $980 se registra como pago parcial, queda saldo $20

ESTADO DE CUENTA:
  Muestra info de descuento disponible:
  "Factura #123: $1,000 - Desc. 2% ($20) si paga antes del 25/02. Total con desc: $980"
```

#### Modelo de Datos SQL

```sql
-- ══════════════════════════════════════════════════════════════════
-- DESCUENTO POR PRONTO PAGO (22.4)
-- Extiende terminos_pago existente + tablas de soporte
-- ══════════════════════════════════════════════════════════════════

-- Agregar campos de descuento pronto pago a terminos_pago
ALTER TABLE terminos_pago
  ADD COLUMN descuento_pronto_pago DECIMAL(5,2) DEFAULT 0,     -- % descuento (ej: 2.00)
  ADD COLUMN dias_pronto_pago      INTEGER DEFAULT 0;          -- Dias para calificar (ej: 10)
  -- Ejemplo: 2/10 Net 30 → descuento_pronto_pago=2, dias_pronto_pago=10

-- Agregar campo a CxC para trackear descuento disponible
ALTER TABLE cuentas_por_cobrar
  ADD COLUMN descuento_pronto_pago  DECIMAL(14,2) DEFAULT 0,   -- Monto del descuento disponible
  ADD COLUMN fecha_limite_descuento DATE,                       -- Fecha hasta la cual aplica
  ADD COLUMN descuento_aplicado     BOOLEAN DEFAULT false;      -- Ya se aplico el descuento?

-- Agregar campo equivalente en CxP (para descuentos de proveedores)
ALTER TABLE cuentas_por_pagar
  ADD COLUMN descuento_pronto_pago  DECIMAL(14,2) DEFAULT 0,
  ADD COLUMN fecha_limite_descuento DATE,
  ADD COLUMN descuento_aplicado     BOOLEAN DEFAULT false;

-- Registro de descuentos aplicados (historial)
CREATE TABLE descuentos_pronto_pago (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id          UUID NOT NULL REFERENCES empresas(id),
  -- Origen
  tipo                VARCHAR(3) NOT NULL,                -- CXC, CXP
  cxc_id              UUID REFERENCES cuentas_por_cobrar(id),
  cxp_id              UUID REFERENCES cuentas_por_pagar(id),
  cobro_id            UUID REFERENCES cobros(id),
  -- Montos
  monto_factura       DECIMAL(14,2) NOT NULL,             -- Total original de la factura
  porcentaje_descuento DECIMAL(5,2) NOT NULL,             -- % aplicado
  monto_descuento     DECIMAL(14,2) NOT NULL,             -- Monto del descuento
  monto_cobrado       DECIMAL(14,2) NOT NULL,             -- Lo que realmente se cobro/pago
  -- Fechas
  fecha_emision_factura DATE NOT NULL,
  fecha_limite_descuento DATE NOT NULL,
  fecha_cobro         DATE NOT NULL,
  dias_cobro          INTEGER NOT NULL,                   -- Dias transcurridos desde emision
  -- Contabilidad
  asiento_id          UUID REFERENCES asientos_contables(id),
  cuenta_descuento_id UUID REFERENCES cuentas_contables(id), -- Cuenta gasto/ingreso financiero
  -- Estado
  estado              VARCHAR(20) DEFAULT 'APLICADO',
    -- APLICADO, ANULADO
  created_at          TIMESTAMPTZ DEFAULT now()
);

-- Indice
CREATE INDEX idx_descuentos_pp_empresa ON descuentos_pronto_pago(empresa_id, tipo, created_at DESC);
CREATE INDEX idx_cxc_descuento_disponible ON cuentas_por_cobrar(empresa_id, fecha_limite_descuento)
  WHERE descuento_pronto_pago > 0 AND descuento_aplicado = false AND estado = 'PENDIENTE';
```

#### Funciones PostgreSQL Principales

```sql
-- Calcular descuento pronto pago al crear CxC (llamada desde create_receivable)
CREATE OR REPLACE FUNCTION descuento_pp_calcular_cxc(
  p_empresa_id  UUID,
  p_cxc_id      UUID
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_cxc cuentas_por_cobrar%ROWTYPE;
  v_factura facturas%ROWTYPE;
  v_termino terminos_pago%ROWTYPE;
  v_desc_monto DECIMAL(14,2);
  v_fecha_limite DATE;
BEGIN
  SELECT * INTO v_cxc FROM cuentas_por_cobrar WHERE id = p_cxc_id AND empresa_id = p_empresa_id;
  IF NOT FOUND THEN RETURN; END IF;

  -- Obtener factura y termino de pago
  SELECT * INTO v_factura FROM facturas WHERE id = v_cxc.factura_id;
  IF NOT FOUND OR v_factura.termino_pago_id IS NULL THEN RETURN; END IF;

  SELECT * INTO v_termino FROM terminos_pago WHERE id = v_factura.termino_pago_id;
  IF NOT FOUND OR v_termino.descuento_pronto_pago <= 0 OR v_termino.dias_pronto_pago <= 0 THEN
    RETURN;
  END IF;

  -- Calcular descuento
  v_desc_monto := ROUND(v_cxc.monto_original * v_termino.descuento_pronto_pago / 100, 2);
  v_fecha_limite := v_cxc.fecha_emision + v_termino.dias_pronto_pago;

  -- Actualizar CxC con info de descuento disponible
  UPDATE cuentas_por_cobrar SET
    descuento_pronto_pago = v_desc_monto,
    fecha_limite_descuento = v_fecha_limite
  WHERE id = p_cxc_id;
END;
$$;

-- Verificar y aplicar descuento pronto pago al registrar cobro
CREATE OR REPLACE FUNCTION descuento_pp_verificar_aplicar(
  p_empresa_id  UUID,
  p_cxc_id      UUID,
  p_fecha_cobro DATE,
  p_cobro_id    UUID
) RETURNS JSONB -- {aplica, monto_descuento, monto_a_cobrar}
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_cxc cuentas_por_cobrar%ROWTYPE;
  v_cuenta_desc_id UUID;
  v_asiento_id UUID;
BEGIN
  SELECT * INTO v_cxc FROM cuentas_por_cobrar
  WHERE id = p_cxc_id AND empresa_id = p_empresa_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('aplica', false, 'motivo', 'CxC no encontrada');
  END IF;

  -- Verificar si tiene descuento pronto pago disponible
  IF v_cxc.descuento_pronto_pago <= 0 OR v_cxc.descuento_aplicado THEN
    RETURN jsonb_build_object('aplica', false, 'motivo', 'Sin descuento disponible');
  END IF;

  -- Verificar si esta dentro del plazo
  IF p_fecha_cobro > v_cxc.fecha_limite_descuento THEN
    RETURN jsonb_build_object(
      'aplica', false,
      'motivo', format('Plazo vencido (limite: %s)', v_cxc.fecha_limite_descuento),
      'fecha_limite', v_cxc.fecha_limite_descuento
    );
  END IF;

  -- Aplica: registrar descuento
  -- Obtener cuenta contable de descuento concedido
  SELECT id INTO v_cuenta_desc_id FROM cuentas_contables
  WHERE empresa_id = p_empresa_id AND codigo LIKE '5.2.%' -- Gastos financieros
    AND nombre ILIKE '%descuento%concedido%'
  LIMIT 1;

  -- Registrar en tabla de descuentos
  INSERT INTO descuentos_pronto_pago (
    empresa_id, tipo, cxc_id, cobro_id,
    monto_factura, porcentaje_descuento, monto_descuento, monto_cobrado,
    fecha_emision_factura, fecha_limite_descuento, fecha_cobro, dias_cobro,
    cuenta_descuento_id
  ) VALUES (
    p_empresa_id, 'CXC', p_cxc_id, p_cobro_id,
    v_cxc.monto_original,
    (v_cxc.descuento_pronto_pago * 100 / NULLIF(v_cxc.monto_original, 0)),
    v_cxc.descuento_pronto_pago,
    v_cxc.monto_original - v_cxc.descuento_pronto_pago,
    v_cxc.fecha_emision, v_cxc.fecha_limite_descuento, p_fecha_cobro,
    p_fecha_cobro - v_cxc.fecha_emision,
    v_cuenta_desc_id
  );

  -- Marcar descuento como aplicado en la CxC
  UPDATE cuentas_por_cobrar SET
    descuento_aplicado = true,
    saldo = saldo - v_cxc.descuento_pronto_pago
  WHERE id = p_cxc_id;

  -- Contabilizar el descuento via module_bus
  PERFORM module_bus.create_journal_entry(
    p_empresa_id,
    p_fecha_cobro,
    format('Descuento pronto pago CxC %s', p_cxc_id),
    'COBRO',
    p_cobro_id,
    jsonb_build_array(
      jsonb_build_object(
        'cuenta_id', v_cuenta_desc_id,
        'descripcion', 'Descuento por pronto pago concedido',
        'debe', v_cxc.descuento_pronto_pago,
        'haber', 0
      ),
      jsonb_build_object(
        'cuenta_id', v_cxc.cuenta_contable_id,
        'descripcion', 'Reduccion CxC por descuento pronto pago',
        'debe', 0,
        'haber', v_cxc.descuento_pronto_pago
      )
    )
  );

  RETURN jsonb_build_object(
    'aplica', true,
    'monto_descuento', v_cxc.descuento_pronto_pago,
    'monto_a_cobrar', v_cxc.saldo, -- saldo ya actualizado
    'fecha_limite', v_cxc.fecha_limite_descuento,
    'dias_cobro', p_fecha_cobro - v_cxc.fecha_emision
  );
END;
$$;

-- Consultar CxC con descuento pronto pago disponible
CREATE OR REPLACE FUNCTION descuento_pp_listar_disponibles(
  p_empresa_id    UUID,
  p_contacto_id   UUID DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN (
    SELECT jsonb_agg(jsonb_build_object(
      'cxc_id', c.id,
      'factura_id', c.factura_id,
      'descripcion', c.descripcion,
      'monto_original', c.monto_original,
      'saldo', c.saldo,
      'descuento_disponible', c.descuento_pronto_pago,
      'monto_con_descuento', c.saldo - c.descuento_pronto_pago,
      'fecha_limite', c.fecha_limite_descuento,
      'dias_restantes', c.fecha_limite_descuento - CURRENT_DATE,
      'cliente', ct.razon_social
    ))
    FROM cuentas_por_cobrar c
    JOIN contactos ct ON ct.id = c.contacto_id
    WHERE c.empresa_id = p_empresa_id
      AND c.descuento_pronto_pago > 0
      AND c.descuento_aplicado = false
      AND c.estado IN ('PENDIENTE', 'PARCIAL')
      AND c.fecha_limite_descuento >= CURRENT_DATE
      AND (p_contacto_id IS NULL OR c.contacto_id = p_contacto_id)
    ORDER BY c.fecha_limite_descuento ASC
  );
END;
$$;
```

#### Triggers

```sql
-- Al crear CxC, calcular descuento pronto pago automaticamente
CREATE OR REPLACE FUNCTION trg_cxc_calcular_descuento_pp()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NEW.tipo_origen = 'FACTURA' AND NEW.factura_id IS NOT NULL THEN
    PERFORM descuento_pp_calcular_cxc(NEW.empresa_id, NEW.id);
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER tr_cxc_descuento_pp
  AFTER INSERT ON cuentas_por_cobrar
  FOR EACH ROW
  EXECUTE FUNCTION trg_cxc_calcular_descuento_pp();
```

#### Vistas para Reportes

```sql
-- Vista: descuentos pronto pago otorgados por periodo
CREATE OR REPLACE VIEW v_descuentos_pp_periodo AS
SELECT
  d.empresa_id,
  date_trunc('month', d.fecha_cobro) AS mes,
  d.tipo,
  COUNT(*) AS cantidad,
  SUM(d.monto_descuento) AS total_descuento,
  SUM(d.monto_cobrado) AS total_cobrado,
  AVG(d.dias_cobro)::INTEGER AS promedio_dias_cobro,
  AVG(d.porcentaje_descuento)::DECIMAL(5,2) AS promedio_porcentaje
FROM descuentos_pronto_pago d
WHERE d.estado = 'APLICADO'
GROUP BY d.empresa_id, date_trunc('month', d.fecha_cobro), d.tipo;

-- Vista: CxC con descuento pronto pago por vencer pronto
CREATE OR REPLACE VIEW v_cxc_descuento_por_vencer AS
SELECT
  c.empresa_id,
  c.contacto_id,
  ct.razon_social AS cliente,
  ct.email,
  c.descripcion,
  c.monto_original,
  c.saldo,
  c.descuento_pronto_pago,
  c.fecha_limite_descuento,
  c.fecha_limite_descuento - CURRENT_DATE AS dias_restantes
FROM cuentas_por_cobrar c
JOIN contactos ct ON ct.id = c.contacto_id
WHERE c.descuento_pronto_pago > 0
  AND c.descuento_aplicado = false
  AND c.estado IN ('PENDIENTE', 'PARCIAL')
  AND c.fecha_limite_descuento >= CURRENT_DATE
  AND c.fecha_limite_descuento <= CURRENT_DATE + 5; -- 5 dias o menos
```

#### Integracion Module Service Bus

```sql
-- Verificar descuento pronto pago desde Tesoreria
CREATE OR REPLACE FUNCTION module_bus.check_early_payment_discount(
  p_empresa_id  UUID,
  p_cxc_id      UUID,
  p_fecha_cobro DATE DEFAULT CURRENT_DATE
) RETURNS module_bus.bus_response
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_result module_bus.bus_response;
  v_data JSONB;
  v_cxc RECORD;
BEGIN
  IF NOT module_bus.is_module_active(p_empresa_id, 'ventas') THEN
    v_result := (false, 'module_inactive', 'ventas', null);
    RETURN v_result;
  END IF;

  SELECT * INTO v_cxc FROM cuentas_por_cobrar
  WHERE id = p_cxc_id AND empresa_id = p_empresa_id;

  IF v_cxc.descuento_pronto_pago > 0
    AND NOT v_cxc.descuento_aplicado
    AND p_fecha_cobro <= v_cxc.fecha_limite_descuento THEN
    v_data := jsonb_build_object(
      'aplica', true,
      'monto_descuento', v_cxc.descuento_pronto_pago,
      'monto_a_cobrar', v_cxc.saldo - v_cxc.descuento_pronto_pago,
      'fecha_limite', v_cxc.fecha_limite_descuento
    );
  ELSE
    v_data := jsonb_build_object('aplica', false);
  END IF;

  v_result := (true, null, 'ventas', v_data);
  RETURN v_result;
END;
$$;
```

#### RLS Policies

```sql
ALTER TABLE descuentos_pronto_pago ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON descuentos_pronto_pago FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));
```

#### Flujo UI/UX

```
Integracion en Cobros (features/ventas/cobros/):
  - Al seleccionar CxC para cobrar, si tiene descuento pronto pago disponible:
    ┌──────────────────────────────────────────────────────────────┐
    │  Factura 001-001-000000123          Total: $1,000.00        │
    │  ✅ Descuento pronto pago disponible                        │
    │  2% descuento si paga antes del 25/02/2026 (faltan 3 dias) │
    │  Descuento: -$20.00   →   Total con descuento: $980.00     │
    │  [Aplicar descuento]  [Cobrar sin descuento]                │
    └──────────────────────────────────────────────────────────────┘

  - Al hacer click en "Aplicar descuento":
    → Monto a cobrar se ajusta a $980
    → CxC queda PAGADA cuando se cobra $980
    → Contabilizacion automatica del descuento

Integracion en Estado de Cuenta:
  - Mostrar columna "Desc. PP" con monto y fecha limite
  - Highlight en verde si aun esta vigente
  - Highlight en rojo si vencio

Reportes (features/ventas/reportes/):
  - Nuevo reporte: "Descuentos por Pronto Pago"
    → Periodo, tipo (CxC/CxP), totales, promedio dias cobro
    → Grafico comparativo: total facturado vs descuentos otorgados
    → Exportar PDF/Excel (Syncfusion)

Responsive:
  COMPACT: badge simple "Desc. PP -$20" en la linea de CxC
  MEDIUM: badge + fecha limite + boton aplicar
  EXPANDED/LARGE: panel detallado con calculo visible
```

---

