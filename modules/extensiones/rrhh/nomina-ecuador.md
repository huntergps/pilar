# Nómina Ecuador (RRHH)

*Spec derivada del módulo `l10n_ec_hr_payroll` (Odoo 19.1 Ecuador — producción en csolish/tecnoh)*

---

## Descripción

Cálculo del rol de pagos conforme a la legislación laboral ecuatoriana: aportes IESS (personal y patronal), décimos tercero y cuarto, fondos de reserva, vacaciones, utilidades 15%, impuesto a la renta, horas extras suplementarias/extraordinarias, préstamos y deducciones. Genera RDEP (Relación de Dependencia) para el SRI y planillas del IESS.

---

## Marco Legal Ecuador

| Concepto | Tasa / Monto |
|---|---|
| Aporte personal IESS | 9.45% del salario |
| Aporte patronal IESS | 11.15% del salario |
| Fondos de reserva | 8.33% (después de 1 año) — pago mensual o acumulación IESS |
| Décimo tercer sueldo | 1/12 del ingreso anual — diciembre o mensualizado |
| Décimo cuarto sueldo | SBU vigente ($470 para 2025) — agosto/marzo por región |
| Horas suplementarias | 50% del valor hora |
| Horas extraordinarias | 100% del valor hora |
| Vacaciones | 15 días + días adicionales por antigüedad |
| Utilidades | 15% de utilidades: 10% por días trabajados + 5% por cargas familiares |

---

## Modelo de Datos

### Tabla: `contratos_laborales` (extensión Ecuador)

```sql
ALTER TABLE contratos_laborales ADD COLUMN iess_aporte_personal    NUMERIC(5,4) DEFAULT 9.45;
ALTER TABLE contratos_laborales ADD COLUMN iess_aporte_patronal    NUMERIC(5,4) DEFAULT 11.15;
ALTER TABLE contratos_laborales ADD COLUMN region_trabajo          TEXT DEFAULT 'costa'
  CHECK (region_trabajo IN ('costa','sierra','oriente','galapagos','zona_franca'));
ALTER TABLE contratos_laborales ADD COLUMN region_decimo_cuarto    TEXT DEFAULT 'costa'
  CHECK (region_decimo_cuarto IN ('costa','sierra','oriente','galapagos'));
ALTER TABLE contratos_laborales ADD COLUMN elegible_fondos_reserva BOOLEAN DEFAULT FALSE; -- auto después de 1 año
ALTER TABLE contratos_laborales ADD COLUMN elegible_decimo_tercero BOOLEAN DEFAULT TRUE;
ALTER TABLE contratos_laborales ADD COLUMN elegible_decimo_cuarto  BOOLEAN DEFAULT TRUE;
-- Préstamos
ALTER TABLE contratos_laborales ADD COLUMN cuota_prestamo_iess     NUMERIC(15,2) DEFAULT 0;
ALTER TABLE contratos_laborales ADD COLUMN cuota_prestamo_interno  NUMERIC(15,2) DEFAULT 0;
ALTER TABLE contratos_laborales ADD COLUMN cuota_comisariato       NUMERIC(15,2) DEFAULT 0;
-- Ingresos adicionales flexibles (para casos especiales: Galápagos, etc.)
ALTER TABLE contratos_laborales ADD COLUMN otros_ingresos_1        NUMERIC(15,2) DEFAULT 0;
ALTER TABLE contratos_laborales ADD COLUMN otros_ingresos_2        NUMERIC(15,2) DEFAULT 0;
ALTER TABLE contratos_laborales ADD COLUMN otros_ingresos_3        NUMERIC(15,2) DEFAULT 0;
ALTER TABLE contratos_laborales ADD COLUMN otros_ingresos_4        NUMERIC(15,2) DEFAULT 0;
-- Descuentos adicionales flexibles
ALTER TABLE contratos_laborales ADD COLUMN otros_descuentos_1      NUMERIC(15,2) DEFAULT 0;
ALTER TABLE contratos_laborales ADD COLUMN otros_descuentos_2      NUMERIC(15,2) DEFAULT 0;
ALTER TABLE contratos_laborales ADD COLUMN otros_descuentos_3      NUMERIC(15,2) DEFAULT 0;
ALTER TABLE contratos_laborales ADD COLUMN otros_descuentos_4      NUMERIC(15,2) DEFAULT 0;
```

### Tabla: `roles_pago` (payslips)

```sql
CREATE TABLE roles_pago (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  nombre                TEXT NOT NULL,                 -- "Rol Enero 2026"
  empleado_id           UUID NOT NULL REFERENCES contactos(id),
  contrato_id           UUID NOT NULL REFERENCES contratos_laborales(id),
  fecha_desde           DATE NOT NULL,
  fecha_hasta           DATE NOT NULL,
  fecha_pago            DATE,
  estado                TEXT DEFAULT 'borrador'
                        CHECK (estado IN ('borrador','verificado','pagado','cancelado')),
  -- Salario base
  salario_base          NUMERIC(15,2) NOT NULL,
  -- Ingresos
  horas_extras_sup      NUMERIC(8,2) DEFAULT 0,
  monto_extras_sup      NUMERIC(15,2) DEFAULT 0,
  horas_extras_ext      NUMERIC(8,2) DEFAULT 0,
  monto_extras_ext      NUMERIC(15,2) DEFAULT 0,
  comisiones            NUMERIC(15,2) DEFAULT 0,
  bonificaciones        NUMERIC(15,2) DEFAULT 0,
  otros_ingresos        NUMERIC(15,2) DEFAULT 0,
  -- Deducciones
  iess_personal         NUMERIC(15,2) DEFAULT 0,       -- 9.45% del ingreso gravado
  impuesto_renta        NUMERIC(15,2) DEFAULT 0,       -- tabla progresiva
  anticipos_descuento   NUMERIC(15,2) DEFAULT 0,
  prestamo_iess         NUMERIC(15,2) DEFAULT 0,
  prestamo_interno      NUMERIC(15,2) DEFAULT 0,
  otras_deducciones     NUMERIC(15,2) DEFAULT 0,
  -- Neto
  total_ingresos        NUMERIC(15,2) DEFAULT 0,
  total_deducciones     NUMERIC(15,2) DEFAULT 0,
  neto_a_pagar          NUMERIC(15,2) DEFAULT 0,
  -- Cargas empresa (no aparecen en rol del empleado)
  iess_patronal         NUMERIC(15,2) DEFAULT 0,       -- 11.15%
  fondos_reserva        NUMERIC(15,2) DEFAULT 0,       -- 8.33% (si aplica)
  provision_decimo13    NUMERIC(15,2) DEFAULT 0,
  provision_decimo14    NUMERIC(15,2) DEFAULT 0,
  provision_vacaciones  NUMERIC(15,2) DEFAULT 0,
  -- Asiento
  asiento_id            UUID REFERENCES asientos_contables(id)
);

ALTER TABLE roles_pago ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON roles_pago FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));
```

### Tabla: `roles_pago_lotes`

```sql
CREATE TABLE roles_pago_lotes (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  nombre          TEXT NOT NULL,
  fecha_desde     DATE NOT NULL,
  fecha_hasta     DATE NOT NULL,
  estado          TEXT DEFAULT 'borrador'
                  CHECK (estado IN ('borrador','verificado','pagado')),
  rol_ids         UUID[],
  total_neto      NUMERIC(15,2) DEFAULT 0
);
```

---

## Cálculo del Rol de Pagos

### Ingreso Base Gravado

```
ingreso_gravado = salario_base
                + horas_extra_suplementarias (50%)
                + horas_extra_extraordinarias (100%)
                + comisiones
                + bonificaciones_gravadas
                + otros_ingresos_gravados
```

### Deducciones IESS

```
iess_personal = ingreso_gravado × 9.45%
iess_patronal = ingreso_gravado × 11.15%  (costo empresa)
```

### Fondos de Reserva

```
-- Solo empleados con > 1 año de antigüedad
fondos_reserva = ingreso_gravado × 8.33%
-- Puede: pagarse mensualmente en el rol, o acumularse en el IESS
```

### Décimos (prorrateo mensual)

```
-- Por opción del empleado: acumular en dic/ago/mar ó pago mensual
provision_decimo13 = ingreso_anual / 12
provision_decimo14 = SBU / 12
```

### Impuesto a la Renta (tabla progresiva 2026)

```
Base imponible = ingreso_anual - aportes_iess - gastos_personales_deducibles
IR = calcular según tabla fracción básica SRI del año en curso
Retención mensual = IR_anual / 12
```

---

## Funciones RPC

```typescript
// Calcular rol individual
calcular_rol(params: {
  empleado_id: UUID
  fecha_desde: string
  fecha_hasta: string
  horas_extras_sup?: number
  horas_extras_ext?: number
  comisiones?: number
  anticipos?: number
}): {
  rol_id: UUID
  desglose: RolDesglose
}

// Calcular lote de roles (todos los empleados)
calcular_lote_roles(params: {
  fecha_desde: string
  fecha_hasta: string
}): {
  lote_id: UUID
  total_empleados: number
  total_neto: number
}

// Verificar y publicar roles
publicar_roles(lote_id: UUID): {
  asientos: UUID[]
  estado: 'verificado'
}

// Generar planilla IESS (para pago en línea)
generar_planilla_iess(params: {
  lote_id: UUID
  mes: number
  anio: number
}): { archivo_base64: string, formato: 'xlsx' }

// Calcular décimo tercer sueldo
calcular_decimo_tercero(params: {
  empleado_id?: UUID       // null = todos
  anio: number
}): [{ empleado_id: UUID, monto: number }]

// Calcular décimo cuarto sueldo
calcular_decimo_cuarto(params: {
  region: 'costa' | 'sierra' | 'oriente' | 'galapagos'
  anio: number
}): [{ empleado_id: UUID, monto: number }]

// Generar RDEP (Relación de Dependencia) para SRI
generar_rdep(anio: number): { archivo_xml_base64: string }

// Acreditar rol (transfiere al banco del empleado)
acreditar_lote(params: {
  lote_id: UUID
  diario_id: UUID
}): { pagos: UUID[], total_acreditado: number }
```

---

## Configuración por Empresa

```json
{
  "nomina": {
    "sbu_vigente": 470.00,
    "tabla_ir_anio": 2026,
    "fondos_reserva_modalidad": "mensual",    // mensual | iess
    "decimo13_modalidad": "acumulado",         // mensual | acumulado
    "decimo14_modalidad": "acumulado",
    "cuenta_iess_personal_id": "uuid",
    "cuenta_iess_patronal_id": "uuid",
    "cuenta_salarios_id": "uuid",
    "cuenta_provision_dec13_id": "uuid",
    "cuenta_provision_dec14_id": "uuid"
  }
}
```

---

## Validaciones de Negocio

- El contrato debe estar activo en el período del rol
- `fondos_reserva_eligible = true` solo si el contrato tiene ≥ 1 año
- Horas extras suplementarias: máximo 12 por semana según CT
- No se puede publicar el rol si hay inconsistencias en datos del empleado (RUC, cuenta bancaria)
- RDEP solo se genera cuando todos los roles del año están publicados

---

## Pantallas Flutter

### Lista de Roles de Pago
- `CrudScaffold<RolPago>` filtros: período, estado, empleado, departamento
- Columnas: empleado, período, salario_base, total_ingresos, deducciones, neto, estado

### Formulario de Rol Individual

```
┌────────────────────────────────────────────────────────┐
│ ROL DE PAGOS - Juan Pérez     Enero 2026               │
├────────────────────────────────────────────────────────┤
│ INGRESOS                          DEDUCCIONES          │
│ Salario Base:    $500.00          IESS Personal: $47.25│
│ H. Extra Sup:    $18.75           IR Mensual:    $0.00 │
│ H. Extra Ext:    $0.00            Préstamo IESS: $25.00│
│ Otros Ingresos:  $0.00            Otros Desc.:   $0.00 │
├────────────────────────────────────────────────────────┤
│ TOTAL INGRESOS:  $518.75   TOTAL DEDUC:  $72.25       │
│                            NETO A PAGAR: $446.50       │
├────────────────────────────────────────────────────────┤
│ PROVISIONES (costo empresa)                            │
│ IESS Patronal: $55.75  Dec.13: $43.23  Dec.14: $39.17│
├────────────────────────────────────────────────────────┤
│ [Calcular]  [Verificar]  [Publicar]  [Imprimir]       │
└────────────────────────────────────────────────────────┘
```

### Lote de Roles (proceso masivo)
- Selector de período, botón "Calcular Todos"
- DataGrid con resumen por empleado
- Acciones masivas: Verificar todos, Publicar lote, Acreditar a bancos

---

## Tabla Canónica del Rol de Pagos (roles_nomina)

La tabla `roles_nomina` es la versión canónica para el cálculo completo del rol mensual.
Complementa a `roles_pago` (que se usa para el lote/proceso general) con campos
detallados de ingresos y provisiones patronales.

```sql
CREATE TABLE roles_nomina (   -- "Rol de pagos" en Ecuador
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id UUID NOT NULL REFERENCES empresas(id),
  empleado_id UUID NOT NULL REFERENCES empleados(id),
  periodo VARCHAR(7) NOT NULL,               -- '2026-01' = enero 2026
  fecha_pago DATE NOT NULL,
  -- Ingresos
  sueldo_basico DECIMAL(14,2) NOT NULL,
  horas_extras_25 DECIMAL(14,2) DEFAULT 0,   -- HE suplementarias (50% del valor hora = +25% sobre 100%)
  horas_extras_100 DECIMAL(14,2) DEFAULT 0,  -- HE extraordinarias (100% del valor hora nocturnas/feriados)
  comisiones DECIMAL(14,2) DEFAULT 0,
  bonos DECIMAL(14,2) DEFAULT 0,
  subsidio_alimentacion DECIMAL(14,2) DEFAULT 0,
  otros_ingresos DECIMAL(14,2) DEFAULT 0,
  total_ingresos DECIMAL(14,2) NOT NULL,
  -- Descuentos empleado
  aporte_iess_personal DECIMAL(14,2) NOT NULL,  -- 9.45% del ingreso gravado
  impuesto_renta DECIMAL(14,2) DEFAULT 0,        -- Retención mensual IR (tabla progresiva / 12)
  descuento_prestamo DECIMAL(14,2) DEFAULT 0,    -- Cuota préstamo quirografario IESS o interno
  descuento_anticipo DECIMAL(14,2) DEFAULT 0,    -- Anticipo de sueldo descontado
  otros_descuentos DECIMAL(14,2) DEFAULT 0,
  total_descuentos DECIMAL(14,2) NOT NULL,
  -- Neto
  neto_a_pagar DECIMAL(14,2) NOT NULL,
  -- Provisiones patronales (costo empresa, no afectan el neto del empleado)
  aporte_patronal_iess DECIMAL(14,2) NOT NULL,  -- 11.15% del ingreso gravado
  decimo_tercero_provisionado DECIMAL(14,2) NOT NULL,
  decimo_cuarto_provisionado DECIMAL(14,2) NOT NULL,
  fondos_reserva_provisionado DECIMAL(14,2) DEFAULT 0, -- 8.33% (solo si > 1 año antigüedad)
  vacaciones_provisionadas DECIMAL(14,2) DEFAULT 0,
  -- Control
  estado VARCHAR(15) DEFAULT 'BORRADOR' CHECK (estado IN ('BORRADOR','APROBADO','PAGADO','ANULADO')),
  asiento_id UUID,
  cuenta_bancaria_pago UUID REFERENCES cuentas_bancarias(id),
  transferencia_id UUID,                     -- Referencia en lote débito bancario
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(empresa_id, empleado_id, periodo)
);

ALTER TABLE roles_nomina ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON roles_nomina FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE INDEX idx_roles_nomina_empresa ON roles_nomina(empresa_id, periodo);
CREATE INDEX idx_roles_nomina_empleado ON roles_nomina(empleado_id, periodo DESC);
CREATE INDEX idx_roles_nomina_estado ON roles_nomina(empresa_id, estado) WHERE estado != 'ANULADO';
```

---

## RPCs de Nómina Ecuador

```sql
-- ══════════════════════════════════════════════════════════════
-- RPC: Calcular nómina para todos los empleados activos
-- Aplica: SBU base, horas extras, IESS 9.45%, IR tabla progresiva,
-- provisiones patronales 11.15% + décimos + fondos de reserva
-- ══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION calculate_payroll(
  p_empresa_id UUID,
  p_periodo VARCHAR   -- '2026-01'
) RETURNS JSONB  -- {empleados_procesados, total_neto, total_costo_empresa}
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_empleado RECORD;
  v_contrato RECORD;
  v_sbu DECIMAL(14,2);
  v_iess_personal DECIMAL(5,4);
  v_iess_patronal DECIMAL(5,4);
  v_fondos_pct DECIMAL(5,4);
  v_ingreso_gravado DECIMAL(14,2);
  v_iess_pers DECIMAL(14,2);
  v_iess_patro DECIMAL(14,2);
  v_dec13 DECIMAL(14,2);
  v_dec14 DECIMAL(14,2);
  v_fondos DECIMAL(14,2);
  v_vac DECIMAL(14,2);
  v_ir DECIMAL(14,2);
  v_neto DECIMAL(14,2);
  v_total_neto DECIMAL(14,2) := 0;
  v_total_costo DECIMAL(14,2) := 0;
  v_procesados INTEGER := 0;
  v_fecha_pago DATE;
BEGIN
  -- Verificar que no exista nómina para este período
  IF EXISTS (SELECT 1 FROM roles_nomina WHERE empresa_id = p_empresa_id AND periodo = p_periodo LIMIT 1) THEN
    RAISE EXCEPTION 'Ya existe nómina calculada para el período %', p_periodo;
  END IF;

  -- Obtener parámetros vigentes desde parametros_sri
  v_sbu := get_parametro_sri('SBU')::DECIMAL;
  v_iess_personal := get_parametro_sri('APORTE_PERSONAL_IESS')::DECIMAL / 100;
  v_iess_patronal := get_parametro_sri('APORTE_PATRONAL_IESS')::DECIMAL / 100;
  v_fondos_pct := get_parametro_sri('FONDOS_RESERVA_PCT')::DECIMAL / 100;
  v_fecha_pago := (TO_DATE(p_periodo || '-01', 'YYYY-MM-DD') + INTERVAL '1 month - 1 day')::DATE;

  FOR v_empleado IN
    SELECT e.id, e.empresa_id
    FROM empleados e
    WHERE e.empresa_id = p_empresa_id AND e.activo = true
  LOOP
    -- Obtener contrato activo
    SELECT * INTO v_contrato FROM contratos_laborales
    WHERE empleado_id = v_empleado.id AND activo = true
    ORDER BY fecha_inicio DESC LIMIT 1;
    IF v_contrato.id IS NULL THEN CONTINUE; END IF;

    v_ingreso_gravado := v_contrato.salario_base
      + COALESCE(v_contrato.otros_ingresos_1, 0)
      + COALESCE(v_contrato.otros_ingresos_2, 0);

    v_iess_pers  := ROUND(v_ingreso_gravado * v_iess_personal, 2);
    v_iess_patro := ROUND(v_ingreso_gravado * v_iess_patronal, 2);
    v_dec13      := ROUND(v_ingreso_gravado / 12, 2);
    v_dec14      := ROUND(v_sbu / 12, 2);
    v_fondos     := CASE WHEN v_contrato.elegible_fondos_reserva THEN ROUND(v_ingreso_gravado * v_fondos_pct, 2) ELSE 0 END;
    v_vac        := ROUND(v_ingreso_gravado / 24, 2);  -- 15 días = ingreso/24

    -- IR: cálculo simplificado; la función completa usa tabla progresiva anualizada
    v_ir := ROUND(calculate_ir_mensual(v_empleado.id, v_ingreso_gravado * 12, v_iess_pers * 12) / 12, 2);

    v_neto := v_ingreso_gravado - v_iess_pers - v_ir
              - COALESCE(v_contrato.cuota_prestamo_iess, 0)
              - COALESCE(v_contrato.cuota_prestamo_interno, 0)
              - COALESCE(v_contrato.cuota_comisariato, 0)
              - COALESCE(v_contrato.otros_descuentos_1, 0);

    INSERT INTO roles_nomina (empresa_id, empleado_id, periodo, fecha_pago,
      sueldo_basico, total_ingresos,
      aporte_iess_personal, impuesto_renta,
      descuento_prestamo,
      total_descuentos, neto_a_pagar,
      aporte_patronal_iess, decimo_tercero_provisionado,
      decimo_cuarto_provisionado, fondos_reserva_provisionado, vacaciones_provisionadas)
    VALUES (p_empresa_id, v_empleado.id, p_periodo, v_fecha_pago,
      v_contrato.salario_base, v_ingreso_gravado,
      v_iess_pers, v_ir,
      COALESCE(v_contrato.cuota_prestamo_iess, 0) + COALESCE(v_contrato.cuota_prestamo_interno, 0),
      v_iess_pers + v_ir + COALESCE(v_contrato.cuota_prestamo_iess, 0) + COALESCE(v_contrato.cuota_prestamo_interno, 0),
      v_neto,
      v_iess_patro, v_dec13, v_dec14, v_fondos, v_vac);

    v_total_neto  := v_total_neto + v_neto;
    v_total_costo := v_total_costo + v_ingreso_gravado + v_iess_patro + v_dec13 + v_dec14 + v_fondos + v_vac;
    v_procesados  := v_procesados + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'empleados_procesados', v_procesados,
    'total_neto', v_total_neto,
    'total_costo_empresa', v_total_costo,
    'periodo', p_periodo
  );
END;
$$;

-- ══════════════════════════════════════════════════════════════
-- RPC: Cálculo del décimo tercer sueldo
-- Base: suma de ingresos del período dic→nov / 12
-- Si modalidad = 'acumulado': pago en diciembre; si = 'mensual': ya provisionado
-- ══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION calculate_decimo_tercero(
  p_empresa_id UUID,
  p_anio INTEGER
) RETURNS JSONB  -- [{empleado_id, monto}] + total
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_resultado JSONB := '[]';
  v_empleado RECORD;
  v_monto DECIMAL(14,2);
  v_total DECIMAL(14,2) := 0;
BEGIN
  FOR v_empleado IN
    SELECT rn.empleado_id, SUM(rn.total_ingresos) / 12 AS dec13
    FROM roles_nomina rn
    WHERE rn.empresa_id = p_empresa_id
      AND rn.periodo BETWEEN (p_anio - 1 || '-12') AND (p_anio || '-11')
      AND rn.estado IN ('APROBADO','PAGADO')
    GROUP BY rn.empleado_id
  LOOP
    v_monto := ROUND(v_empleado.dec13, 2);
    v_resultado := v_resultado || jsonb_build_object('empleado_id', v_empleado.empleado_id, 'monto', v_monto);
    v_total := v_total + v_monto;
  END LOOP;

  RETURN jsonb_build_object('detalle', v_resultado, 'total', v_total, 'anio', p_anio);
END;
$$;

-- ══════════════════════════════════════════════════════════════
-- RPC: Cálculo del décimo cuarto sueldo
-- Monto = SBU vigente (igual para todos)
-- Sierra/Oriente: pago en agosto; Costa/Galápagos: pago en marzo
-- ══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION calculate_decimo_cuarto(
  p_empresa_id UUID,
  p_region VARCHAR   -- 'costa' | 'sierra' | 'oriente' | 'galapagos'
) RETURNS JSONB  -- {empleados, monto_unitario, total}
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_sbu DECIMAL(14,2) := get_parametro_sri('SBU')::DECIMAL;
  v_empleados INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_empleados
  FROM empleados e
  JOIN contratos_laborales cl ON cl.empleado_id = e.id AND cl.activo = true
  WHERE e.empresa_id = p_empresa_id
    AND cl.region_decimo_cuarto = p_region
    AND cl.elegible_decimo_cuarto = true;

  RETURN jsonb_build_object(
    'region', p_region,
    'empleados', v_empleados,
    'monto_unitario', v_sbu,
    'total', ROUND(v_sbu * v_empleados, 2)
  );
END;
$$;

-- ══════════════════════════════════════════════════════════════
-- RPC: Generar planilla IESS en formato CSV
-- Formato requerido por IESS Online para pago de aportes
-- Incluye: aporte personal 9.45% + patronal 11.15% + fondos reserva
-- ══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION generate_iess_planilla(
  p_empresa_id UUID,
  p_periodo VARCHAR   -- '2026-01'
) RETURNS JSONB  -- {filas_csv: TEXT, total_aportes, empleados}
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_empresa RECORD;
  v_filas TEXT := '';
  v_row RECORD;
  v_total DECIMAL(14,2) := 0;
  v_empleados INTEGER := 0;
BEGIN
  SELECT * INTO v_empresa FROM empresas WHERE id = p_empresa_id;

  -- Formato IESS: RUC_EMPLEADOR|CEDULA_EMPLEADO|NOMBRE|SALARIO|APORTE_PERSONAL|APORTE_PATRONAL|FONDOS
  FOR v_row IN
    SELECT
      e.cedula_ruc,
      c.nombre || ' ' || c.apellido AS nombre,
      rn.sueldo_basico,
      rn.aporte_iess_personal,
      rn.aporte_patronal_iess,
      rn.fondos_reserva_provisionado
    FROM roles_nomina rn
    JOIN empleados e ON e.id = rn.empleado_id
    JOIN contactos c ON c.id = e.contacto_id
    WHERE rn.empresa_id = p_empresa_id AND rn.periodo = p_periodo
      AND rn.estado IN ('APROBADO','PAGADO')
    ORDER BY c.apellido, c.nombre
  LOOP
    v_filas := v_filas ||
      v_empresa.ruc || '|' ||
      v_row.cedula_ruc || '|' ||
      v_row.nombre || '|' ||
      v_row.sueldo_basico || '|' ||
      v_row.aporte_iess_personal || '|' ||
      v_row.aporte_patronal_iess || '|' ||
      v_row.fondos_reserva_provisionado || E'\n';

    v_total := v_total + v_row.aporte_iess_personal + v_row.aporte_patronal_iess + v_row.fondos_reserva_provisionado;
    v_empleados := v_empleados + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'filas_csv', v_filas,
    'total_aportes', v_total,
    'empleados', v_empleados,
    'periodo', p_periodo
  );
END;
$$;
```

---

## Tabla Progresiva IR Ecuador 2024-2026

Aplicada a personas naturales en relación de dependencia (RDEP):

```
╔══════════════════════════════════════════════════════════════════════════════╗
║  TABLA IMPUESTO A LA RENTA — PERSONAS NATURALES EN RELACIÓN DEPENDENCIA   ║
╠═══════════════╦═══════════════╦══════════════╦═══════════════════╦═════════╣
║ Fracción Básica│ Exceso hasta  │ Imp. Fracc.  │ % Fracción Exced. ║         ║
╠═══════════════╬═══════════════╬══════════════╬═══════════════════╬═════════╣
║ $         0   ║  $  11.722    ║ $      0,00  ║ 0%                ║         ║
║ $  11.722     ║  $  14.931    ║ $      0,00  ║ 5%                ║         ║
║ $  14.931     ║  $  19.385    ║ $    160,45  ║ 10%               ║         ║
║ $  19.385     ║  $  25.721    ║ $    605,95  ║ 12%               ║         ║
║ $  25.721     ║  $  33.603    ║ $  1.366,27  ║ 15%               ║         ║
║ $  33.603     ║  $  44.721    ║ $  2.548,57  ║ 20%               ║         ║
║ $  44.721     ║  $  59.527    ║ $  4.772,17  ║ 25%               ║         ║
║ $  59.527     ║  $  79.369    ║ $  8.473,67  ║ 30%               ║         ║
║ $  79.369     ║  En adelante  ║ $ 14.425,87  ║ 35%               ║         ║
╚═══════════════╩═══════════════╩══════════════╩═══════════════════╩═════════╝

Nota: La tabla se actualiza anualmente. Se almacena en parametros_sri con
clave 'TABLA_IR_<AÑO>' o en tabla dedicada tabla_ir_personas.
Los valores se leen en tiempo de cálculo, nunca hardcodeados.
```

### Función de cálculo IR mensual

```sql
CREATE OR REPLACE FUNCTION calculate_ir_mensual(
  p_empleado_id UUID,
  p_ingreso_anual DECIMAL(14,2),     -- Proyección anual del ingreso gravado
  p_iess_anual DECIMAL(14,2)         -- Total aportes IESS personal en el año
) RETURNS DECIMAL(14,2)              -- Retención mensual (IR_anual / 12)
LANGUAGE plpgsql STABLE SECURITY DEFINER AS $$
DECLARE
  v_base_imponible DECIMAL(14,2);
  v_gastos_personales DECIMAL(14,2) := 0;
  v_ir_anual DECIMAL(14,2) := 0;
  v_fraccion RECORD;
BEGIN
  -- Base imponible = ingresos - IESS personal - gastos personales deducibles
  v_base_imponible := p_ingreso_anual - p_iess_anual - v_gastos_personales;
  IF v_base_imponible <= 0 THEN RETURN 0; END IF;

  -- Aplicar tabla progresiva (leída desde tabla_ir_personas o parametros_sri)
  -- Lógica simplificada de escalonamiento:
  SELECT
    impuesto_base + GREATEST(0, v_base_imponible - fraccion_basica) * porcentaje_exceso / 100
  INTO v_ir_anual
  FROM tabla_ir_personas
  WHERE fraccion_basica <= v_base_imponible
  ORDER BY fraccion_basica DESC
  LIMIT 1;

  RETURN ROUND(COALESCE(v_ir_anual, 0) / 12, 2);
END;
$$;
```

---

## Integración RDEP (Retención en la Fuente — Relación de Dependencia)

Al cerrar el año fiscal, el empleador genera el **RDEP** para entregar al SRI y a cada empleado:

```
Proceso RDEP:
1. Consolidar roles_nomina del año (enero → diciembre)
2. Calcular base imponible real = ingresos - IESS personal - gastos personales
3. Recalcular IR real vs retenciones aplicadas
4. Si IR real > retenciones → diferencia se retiene en diciembre
5. Si IR real < retenciones → se devuelve al empleado
6. Generar XML RDEP según formato SRI (similar a ATS)
7. Enviar por email/WhatsApp a cada empleado
8. Archivo XML se sube a Supabase Storage: rrhh/{empresa_id}/rdep/{anio}.xml
```

```typescript
// Edge Function: generate-rdep
// Genera el archivo XML RDEP para el SRI
// Ruta: /functions/v1/generate-rdep
// Body: { empresa_id, anio }
// Respuesta: { url_storage, empleados_incluidos }
```


