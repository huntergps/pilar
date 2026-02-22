# Módulo de Contabilidad

> **Módulo Core #8** — Fase 5
>
> Plan contable NIIF Ecuador, asientos manuales y automáticos, libros contables, estados financieros, cierre de período, presupuestos, diferidos y asientos recurrentes.
>
> Todos los módulos que generan asientos contables (Facturación, Compras, Inventario, RRHH, Activos Fijos, Taller) llaman a `module_bus.contabilidad_create_journal_entry()`. Contabilidad devuelve `NULL` (NO-OP) si el módulo no está activo para la empresa.

## Dependencias del Módulo

- **No requiere** otros módulos Core para funcionar — Contabilidad es **standalone**.
- **Se integra opcionalmente** con Facturación, Ventas, Compras, Tesorería: cuando esos módulos están activos, generan asientos automáticos llamando a `module_bus.contabilidad_create_journal_entry()`.
- **Provee servicios** al módulo Tributación vía `module_bus.contabilidad_create_journal_entry()` y consultas de saldos por cuenta, de modo que Tributación puede generar ATS, F-103 y F-104 sin acceso directo a los schemas de Facturación o Compras.

## Navegación

```
contabilidad/
  ├── plan-cuentas/       # Plan de cuentas NIIF Ecuador (TreeView jerárquico)
  ├── diarios/            # Diarios contables (Ventas, Compras, Banco, Nómina, etc.)
  ├── centros-costo/      # Centros de costo y proyecto analítico
  ├── periodos/           # Apertura/cierre de períodos contables
  ├── asientos/
  │     ├── manuales/     # Asientos manuales (formulario con líneas debe/haber)
  │     ├── automaticos/  # Generados por transacciones (sólo lectura)
  │     └── reverso/      # Asientos de corrección (inmutabilidad)
  ├── libros/
  │     ├── diario/       # Libro diario (SfDataGrid filtros por fecha/cuenta/diario)
  │     └── mayor/        # Libro mayor por cuenta (con saldo inicial)
  ├── estados-financieros/
  │     ├── balance-general/
  │     ├── estado-resultados/
  │     └── flujo-efectivo/
  └── reportes/
        ├── balance-comprobacion/
        ├── auxiliar-terceros/
        └── presupuesto-vs-real/
```

## Modelo de Datos

### cuentas_contables

```sql
CREATE TABLE cuentas_contables (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  codigo                VARCHAR(20) NOT NULL,
  nombre                VARCHAR(200) NOT NULL,
  tipo                  VARCHAR(15) NOT NULL
    CHECK (tipo IN ('ACTIVO','PASIVO','PATRIMONIO','INGRESO','GASTO','COSTO','ORDEN')),
  naturaleza            VARCHAR(10) NOT NULL
    CHECK (naturaleza IN ('DEUDORA','ACREEDORA')),
  -- Naturaleza por tipo:
  -- DEUDORA:   ACTIVO, GASTO, COSTO
  -- ACREEDORA: PASIVO, PATRIMONIO, INGRESO, ORDEN
  nivel                 INTEGER NOT NULL,
  -- 1=grupo, 2=subgrupo, 3=cuenta, 4=subcuenta, 5=auxiliar
  padre_id              UUID REFERENCES cuentas_contables(id),
  es_movimiento         BOOLEAN NOT NULL DEFAULT false,
  -- true = cuenta hoja (admite asientos). false = cuenta de agrupación.
  permite_contacto      BOOLEAN NOT NULL DEFAULT false,
  -- true = CxC, CxP, anticipos (requiere contacto_id en asiento_lineas)
  permite_centro_costo  BOOLEAN NOT NULL DEFAULT false,

  -- Mapeo regulatorio
  codigo_sri            VARCHAR(10),   -- código para ATS y formularios SRI
  codigo_niif           VARCHAR(20),   -- código catálogo SCVS

  activa                BOOLEAN NOT NULL DEFAULT true,
  created_at            TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(empresa_id, codigo)
);
```

### diarios_contables

```sql
CREATE TABLE diarios_contables (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id        UUID NOT NULL REFERENCES empresas(id),
  nombre            VARCHAR(100) NOT NULL,
  tipo              VARCHAR(20) NOT NULL
    CHECK (tipo IN ('VENTAS','COMPRAS','BANCO','CAJA','NOMINA','DEPRECIACION','MISCELANEO')),
  -- Tipo → inferido en create_journal_entry según documento_tipo:
  -- FACTURA/NC/ND → VENTAS | COMPRA/LC → COMPRAS | NOMINA → NOMINA | ACTIVO → DEPRECIACION
  -- Resto → MISCELANEO (fallback)
  secuencia_prefijo VARCHAR(10),        -- prefijo del número: "VTA", "CMP", etc.
  ultimo_numero     INTEGER NOT NULL DEFAULT 0,
  cuenta_default_id UUID REFERENCES cuentas_contables(id),  -- cuenta por defecto del diario
  activo            BOOLEAN NOT NULL DEFAULT true,
  created_at        TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(empresa_id, tipo)
);
```

### centros_costo

```sql
CREATE TABLE centros_costo (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id  UUID NOT NULL REFERENCES empresas(id),
  codigo      VARCHAR(20) NOT NULL,
  nombre      VARCHAR(100) NOT NULL,
  padre_id    UUID REFERENCES centros_costo(id),
  activo      BOOLEAN NOT NULL DEFAULT true,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(empresa_id, codigo)
);
```

### periodos_contables

```sql
CREATE TABLE periodos_contables (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  anio            INTEGER NOT NULL,
  mes             INTEGER NOT NULL CHECK (mes BETWEEN 1 AND 12),
  estado          VARCHAR(10) NOT NULL DEFAULT 'ABIERTO'
    CHECK (estado IN ('ABIERTO','CERRADO')),
  fecha_apertura  TIMESTAMPTZ DEFAULT NOW(),
  fecha_cierre    TIMESTAMPTZ,
  cerrado_por     UUID REFERENCES auth.users(id),
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(empresa_id, anio, mes)
);
```

### asientos_contables

```sql
CREATE TABLE asientos_contables (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id        UUID NOT NULL REFERENCES empresas(id),
  periodo_id        UUID NOT NULL REFERENCES periodos_contables(id),
  diario_id         UUID NOT NULL REFERENCES diarios_contables(id),
  numero            INTEGER NOT NULL,
  -- Asignado por trigger tr_asiento_numero (secuencial por empresa+diario)
  fecha             DATE NOT NULL,
  descripcion       TEXT NOT NULL,
  tipo              VARCHAR(25) NOT NULL DEFAULT 'MANUAL'
    CHECK (tipo IN ('MANUAL','AUTOMATICO','REVERSO','APERTURA','CIERRE')),
  estado            VARCHAR(25) NOT NULL DEFAULT 'BORRADOR'
    CHECK (estado IN ('BORRADOR','PENDIENTE_APROBACION','CONTABILIZADO','ANULADO')),
  -- Flujo MANUAL:     BORRADOR → PENDIENTE_APROBACION → CONTABILIZADO | ANULADO
  -- Flujo AUTOMATICO: directo a CONTABILIZADO (sin aprobación)

  -- Referencia al documento origen (para trazabilidad)
  documento_tipo    VARCHAR(25),
  -- FACTURA | NC | ND | RETENCION | LIQUIDACION | GUIA_REMISION |
  -- NOMINA | ACTIVO_FIJO | TALLER | COBRO | PAGO | CONCILIACION
  documento_id      UUID,

  -- Reverso (para asientos de corrección)
  asiento_reverso_id UUID REFERENCES asientos_contables(id),

  -- Aprobación (P2)
  aprobado_por      UUID REFERENCES auth.users(id),
  fecha_aprobacion  TIMESTAMPTZ,

  -- Bloqueo optimista
  version           INTEGER NOT NULL DEFAULT 1,

  creado_por        UUID REFERENCES auth.users(id),
  created_at        TIMESTAMPTZ DEFAULT NOW(),
  updated_at        TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE(empresa_id, diario_id, numero)
);
```

### asiento_lineas

```sql
CREATE TABLE asiento_lineas (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  asiento_id      UUID NOT NULL REFERENCES asientos_contables(id) ON DELETE CASCADE,
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  cuenta_id       UUID NOT NULL REFERENCES cuentas_contables(id),
  descripcion     TEXT,
  debe            DECIMAL(14,2) NOT NULL DEFAULT 0,
  haber           DECIMAL(14,2) NOT NULL DEFAULT 0,

  -- Analítica opcional
  contacto_id     UUID REFERENCES contactos(id),
  -- requerido cuando cuenta.permite_contacto = true (CxC, CxP)
  centro_costo_id UUID REFERENCES centros_costo(id),
  proyecto_id     UUID,  -- referencia soft a proyectos.id (sin FK — Proyectos es Auxiliar #17, activable)

  created_at      TIMESTAMPTZ DEFAULT NOW(),

  CONSTRAINT chk_debe_haber_exclusivo
    CHECK (debe >= 0 AND haber >= 0
      AND (debe > 0 OR haber > 0)
      AND NOT (debe > 0 AND haber > 0))
  -- Una línea solo puede tener debe OR haber, nunca ambos > 0
);
```

### presupuestos

```sql
CREATE TABLE presupuestos (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id  UUID NOT NULL REFERENCES empresas(id),
  nombre      VARCHAR(200) NOT NULL,
  anio        INTEGER NOT NULL,
  estado      VARCHAR(20) NOT NULL DEFAULT 'BORRADOR'
    CHECK (estado IN ('BORRADOR','APROBADO','CERRADO')),
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(empresa_id, nombre, anio)
);
```

### presupuesto_lineas

```sql
CREATE TABLE presupuesto_lineas (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  presupuesto_id  UUID NOT NULL REFERENCES presupuestos(id) ON DELETE CASCADE,
  cuenta_id       UUID NOT NULL REFERENCES cuentas_contables(id),
  centro_costo_id UUID REFERENCES centros_costo(id),
  -- Nullable: si NULL aplica a toda la empresa
  mes_01  DECIMAL(14,2) NOT NULL DEFAULT 0,
  mes_02  DECIMAL(14,2) NOT NULL DEFAULT 0,
  mes_03  DECIMAL(14,2) NOT NULL DEFAULT 0,
  mes_04  DECIMAL(14,2) NOT NULL DEFAULT 0,
  mes_05  DECIMAL(14,2) NOT NULL DEFAULT 0,
  mes_06  DECIMAL(14,2) NOT NULL DEFAULT 0,
  mes_07  DECIMAL(14,2) NOT NULL DEFAULT 0,
  mes_08  DECIMAL(14,2) NOT NULL DEFAULT 0,
  mes_09  DECIMAL(14,2) NOT NULL DEFAULT 0,
  mes_10  DECIMAL(14,2) NOT NULL DEFAULT 0,
  mes_11  DECIMAL(14,2) NOT NULL DEFAULT 0,
  mes_12  DECIMAL(14,2) NOT NULL DEFAULT 0,
  total   DECIMAL(14,2) GENERATED ALWAYS AS (
    mes_01 + mes_02 + mes_03 + mes_04 + mes_05 + mes_06 +
    mes_07 + mes_08 + mes_09 + mes_10 + mes_11 + mes_12
  ) STORED
);
```

### diferidos

```sql
-- NIIF 15: reconocimiento ingresos por obligaciones de desempeño
-- NIC 18: matching gastos al período correspondiente (seguros, alquileres prepagados)
CREATE TABLE diferidos (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id        UUID NOT NULL REFERENCES empresas(id),
  tipo              VARCHAR(10) NOT NULL CHECK (tipo IN ('INGRESO','GASTO')),
  descripcion       VARCHAR(300) NOT NULL,
  monto_total       DECIMAL(14,2) NOT NULL,
  fecha_inicio      DATE NOT NULL,
  fecha_fin         DATE NOT NULL,
  cuenta_origen_id  UUID NOT NULL REFERENCES cuentas_contables(id),
  -- Cuenta balance: Activo (gasto prepagado) o Pasivo (ingreso diferido)
  cuenta_destino_id UUID NOT NULL REFERENCES cuentas_contables(id),
  -- Cuenta resultado: Gasto o Ingreso
  periodos          INTEGER NOT NULL,
  estado            VARCHAR(15) NOT NULL DEFAULT 'ACTIVO'
    CHECK (estado IN ('ACTIVO','COMPLETADO','CANCELADO')),
  created_at        TIMESTAMPTZ DEFAULT NOW()
);
```

### diferido_lineas

```sql
CREATE TABLE diferido_lineas (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  diferido_id UUID NOT NULL REFERENCES diferidos(id) ON DELETE CASCADE,
  fecha       DATE NOT NULL,
  monto       DECIMAL(14,2) NOT NULL,
  -- monto_total / periodos; el último período absorbe centavos de redondeo
  asiento_id  UUID REFERENCES asientos_contables(id),
  estado      VARCHAR(15) NOT NULL DEFAULT 'PENDIENTE'
    CHECK (estado IN ('PENDIENTE','CONTABILIZADO'))
);
```

### asientos_recurrentes

```sql
CREATE TABLE asientos_recurrentes (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id        UUID NOT NULL REFERENCES empresas(id),
  nombre            VARCHAR(200) NOT NULL,
  diario_id         UUID NOT NULL REFERENCES diarios_contables(id),
  lineas_template   JSONB NOT NULL,
  -- [{cuenta_id, debe, haber, descripcion, centro_costo_id}]
  frecuencia        VARCHAR(15) NOT NULL
    CHECK (frecuencia IN ('MENSUAL','TRIMESTRAL','ANUAL')),
  proximo_fecha     DATE NOT NULL,
  fecha_fin         DATE,
  activo            BOOLEAN NOT NULL DEFAULT true,
  ultimo_asiento_id UUID REFERENCES asientos_contables(id),
  created_at        TIMESTAMPTZ DEFAULT NOW()
);
```

### cierre_periodo

```sql
CREATE TABLE cierre_periodo (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id        UUID NOT NULL REFERENCES empresas(id),
  periodo_id        UUID NOT NULL REFERENCES periodos_contables(id),
  checklist         JSONB NOT NULL DEFAULT '[]',
  -- [{paso, descripcion, completado, completado_por, fecha}]
  estado            VARCHAR(15) NOT NULL DEFAULT 'PENDIENTE'
    CHECK (estado IN ('PENDIENTE','EN_PROCESO','CERRADO')),
  fecha_cierre      TIMESTAMPTZ,
  cerrado_por       UUID REFERENCES auth.users(id),
  asiento_cierre_id UUID REFERENCES asientos_contables(id),
  lock_date         DATE,
  -- No se permiten asientos con fecha <= lock_date
  created_at        TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(empresa_id, periodo_id)
);
```

## RLS

```sql
-- Aplicar a todas las tablas del módulo:
ALTER TABLE cuentas_contables ENABLE ROW LEVEL SECURITY;
CREATE POLICY cuentas_contables_empresa ON cuentas_contables
  TO authenticated USING (empresa_id = (SELECT private.get_empresa_id()));

ALTER TABLE diarios_contables ENABLE ROW LEVEL SECURITY;
CREATE POLICY diarios_contables_empresa ON diarios_contables
  TO authenticated USING (empresa_id = (SELECT private.get_empresa_id()));

ALTER TABLE centros_costo ENABLE ROW LEVEL SECURITY;
CREATE POLICY centros_costo_empresa ON centros_costo
  TO authenticated USING (empresa_id = (SELECT private.get_empresa_id()));

ALTER TABLE periodos_contables ENABLE ROW LEVEL SECURITY;
CREATE POLICY periodos_contables_empresa ON periodos_contables
  TO authenticated USING (empresa_id = (SELECT private.get_empresa_id()));

ALTER TABLE asientos_contables ENABLE ROW LEVEL SECURITY;
CREATE POLICY asientos_contables_empresa ON asientos_contables
  TO authenticated USING (empresa_id = (SELECT private.get_empresa_id()));

ALTER TABLE asiento_lineas ENABLE ROW LEVEL SECURITY;
CREATE POLICY asiento_lineas_empresa ON asiento_lineas
  TO authenticated USING (empresa_id = (SELECT private.get_empresa_id()));

ALTER TABLE presupuestos ENABLE ROW LEVEL SECURITY;
CREATE POLICY presupuestos_empresa ON presupuestos
  TO authenticated USING (empresa_id = (SELECT private.get_empresa_id()));

ALTER TABLE presupuesto_lineas ENABLE ROW LEVEL SECURITY;
CREATE POLICY presupuesto_lineas_empresa ON presupuesto_lineas
  TO authenticated USING (
    presupuesto_id IN (
      SELECT id FROM presupuestos
      WHERE empresa_id = (SELECT private.get_empresa_id())
    )
  );

ALTER TABLE diferidos ENABLE ROW LEVEL SECURITY;
CREATE POLICY diferidos_empresa ON diferidos
  TO authenticated USING (empresa_id = (SELECT private.get_empresa_id()));

ALTER TABLE diferido_lineas ENABLE ROW LEVEL SECURITY;
CREATE POLICY diferido_lineas_empresa ON diferido_lineas
  TO authenticated USING (
    diferido_id IN (
      SELECT id FROM diferidos
      WHERE empresa_id = (SELECT private.get_empresa_id())
    )
  );

ALTER TABLE asientos_recurrentes ENABLE ROW LEVEL SECURITY;
CREATE POLICY asientos_recurrentes_empresa ON asientos_recurrentes
  TO authenticated USING (empresa_id = (SELECT private.get_empresa_id()));

ALTER TABLE cierre_periodo ENABLE ROW LEVEL SECURITY;
CREATE POLICY cierre_periodo_empresa ON cierre_periodo
  TO authenticated USING (empresa_id = (SELECT private.get_empresa_id()));
```

## Índices

```sql
-- Plan de cuentas
CREATE INDEX idx_cuentas_empresa_codigo ON cuentas_contables(empresa_id, codigo);
CREATE INDEX idx_cuentas_padre ON cuentas_contables(padre_id) WHERE padre_id IS NOT NULL;
CREATE INDEX idx_cuentas_movimiento ON cuentas_contables(empresa_id, es_movimiento) WHERE es_movimiento = true;

-- Asientos
CREATE INDEX idx_asientos_empresa_fecha ON asientos_contables(empresa_id, fecha DESC);
CREATE INDEX idx_asientos_periodo ON asientos_contables(periodo_id);
CREATE INDEX idx_asientos_diario ON asientos_contables(empresa_id, diario_id, numero DESC);
CREATE INDEX idx_asientos_estado ON asientos_contables(empresa_id, estado) WHERE estado != 'CONTABILIZADO';
CREATE INDEX idx_asientos_documento ON asientos_contables(documento_tipo, documento_id) WHERE documento_id IS NOT NULL;

-- Líneas de asiento
CREATE INDEX idx_lineas_asiento ON asiento_lineas(asiento_id);
CREATE INDEX idx_lineas_cuenta ON asiento_lineas(empresa_id, cuenta_id);
CREATE INDEX idx_lineas_contacto ON asiento_lineas(contacto_id) WHERE contacto_id IS NOT NULL;
CREATE INDEX idx_lineas_centro_costo ON asiento_lineas(centro_costo_id) WHERE centro_costo_id IS NOT NULL;

-- Períodos
CREATE INDEX idx_periodos_empresa ON periodos_contables(empresa_id, anio, mes);
```

## Module Service Bus — funciones que expone Contabilidad

```sql
-- Todos los módulos Core y Auxiliares llaman esta función para crear asientos.
-- Retorna NULL (NO-OP) si Contabilidad no está activo para la empresa.
CREATE OR REPLACE FUNCTION module_bus.contabilidad_create_journal_entry(
  p_empresa_id     UUID,
  p_fecha          DATE,
  p_descripcion    TEXT,
  p_tipo           VARCHAR DEFAULT 'AUTOMATICO',
  p_lineas         JSONB,
  -- [{cuenta_id, descripcion, debe, haber, contacto_id, centro_costo_id, proyecto_id}]
  p_documento_tipo VARCHAR DEFAULT NULL,
  p_documento_id   UUID DEFAULT NULL,
  p_diario_id      UUID DEFAULT NULL
) RETURNS UUID      -- asiento_id, o NULL si módulo inactivo
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM modulos_empresa
    WHERE empresa_id = p_empresa_id
      AND modulo_id = 'contabilidad'
      AND activo = true
  ) THEN
    RETURN NULL;  -- NO-OP: empresa sin módulo Contabilidad
  END IF;

  RETURN create_journal_entry(
    p_empresa_id, p_fecha, p_descripcion, p_tipo,
    p_lineas, p_documento_tipo, p_documento_id, p_diario_id
  );
END;
$$;

-- Consultar saldo de una cuenta en una fecha
CREATE OR REPLACE FUNCTION module_bus.contabilidad_get_account_balance(
  p_empresa_id UUID,
  p_cuenta_id  UUID,
  p_fecha      DATE DEFAULT CURRENT_DATE
) RETURNS DECIMAL(14,2)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_saldo DECIMAL(14,2);
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM modulos_empresa
    WHERE empresa_id = p_empresa_id AND modulo_id = 'contabilidad' AND activo = true
  ) THEN RETURN NULL; END IF;

  SELECT COALESCE(SUM(
    CASE WHEN c.naturaleza = 'DEUDORA' THEN l.debe - l.haber
         ELSE l.haber - l.debe END
  ), 0) INTO v_saldo
  FROM asiento_lineas l
  JOIN asientos_contables a ON a.id = l.asiento_id
  JOIN cuentas_contables c ON c.id = l.cuenta_id
  WHERE l.cuenta_id = p_cuenta_id
    AND a.empresa_id = p_empresa_id
    AND a.estado = 'CONTABILIZADO'
    AND a.fecha <= p_fecha;
  RETURN v_saldo;
END;
$$;

-- Verificar si un período está abierto
CREATE OR REPLACE FUNCTION module_bus.contabilidad_is_period_open(
  p_empresa_id UUID,
  p_fecha      DATE
) RETURNS BOOLEAN
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT EXISTS (
    SELECT 1 FROM periodos_contables
    WHERE empresa_id = p_empresa_id
      AND anio = EXTRACT(YEAR FROM p_fecha)
      AND mes  = EXTRACT(MONTH FROM p_fecha)
      AND estado = 'ABIERTO'
  );
$$;
```

### Módulos que consumen el Module Service Bus de Contabilidad

| Módulo | Evento | documento_tipo |
|--------|--------|----------------|
| **Facturación** | Factura AUTORIZADA | FACTURA |
| **Facturación** | NC AUTORIZADA | NC |
| **Facturación** | ND AUTORIZADA | ND |
| **Compras** | Factura proveedor registrada | COMPRA |
| **Compras** | Liquidación de compra | LIQUIDACION |
| **Compras** | Retención emitida | RETENCION |
| **Tesorería** | Cobro registrado | COBRO |
| **Tesorería** | Pago registrado | PAGO |
| **Tesorería** | Conciliación bancaria | CONCILIACION |
| **RRHH** | Nómina aprobada | NOMINA |
| **Activos Fijos** | Depreciación mensual | ACTIVO_FIJO |
| **Taller** | Orden de reparación cerrada | TALLER |
| **POS** | Cierre de caja | POS_CIERRE |

## RPCs del Módulo

### Trigger: numeración automática de asientos

```sql
-- Asigna numero secuencial por empresa+diario antes de insertar
CREATE OR REPLACE FUNCTION tr_fn_asiento_numero()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  UPDATE diarios_contables
    SET ultimo_numero = ultimo_numero + 1
  WHERE id = NEW.diario_id AND empresa_id = NEW.empresa_id
  RETURNING ultimo_numero INTO NEW.numero;
  RETURN NEW;
END;
$$;

CREATE TRIGGER tr_asiento_numero
  BEFORE INSERT ON asientos_contables
  FOR EACH ROW EXECUTE FUNCTION tr_fn_asiento_numero();
```

### create_journal_entry

```sql
-- Crear asiento contable con sus líneas (transaccional).
-- El campo 'numero' se asigna automáticamente via trigger tr_asiento_numero
-- (secuencial por empresa+diario). El campo 'diario_id' es requerido para la
-- secuencia correcta. Si no se proporciona, se infiere del tipo de asiento.
CREATE OR REPLACE FUNCTION create_journal_entry(
  p_empresa_id     UUID,
  p_fecha          DATE,
  p_descripcion    TEXT,
  p_tipo           VARCHAR DEFAULT 'MANUAL',
  p_lineas         JSONB,
  -- [{cuenta_id, descripcion, debe, haber, contacto_id, centro_costo_id, proyecto_id}]
  p_documento_tipo VARCHAR DEFAULT NULL,  -- 'FACTURA', 'NOMINA', 'TALLER', 'ACTIVO', etc.
  p_documento_id   UUID DEFAULT NULL,     -- ID del documento origen
  p_diario_id      UUID DEFAULT NULL      -- Diario contable; si NULL, se infiere del tipo
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_asiento_id    UUID;
  v_periodo_id    UUID;
  v_diario_id     UUID;
  v_total_debe    DECIMAL(14,2) := 0;
  v_total_haber   DECIMAL(14,2) := 0;
  v_linea         JSONB;
BEGIN
  -- Validar que el período esté abierto
  SELECT id INTO v_periodo_id FROM periodos_contables
  WHERE empresa_id = p_empresa_id
    AND anio = EXTRACT(YEAR FROM p_fecha)
    AND mes  = EXTRACT(MONTH FROM p_fecha)
    AND estado = 'ABIERTO';
  IF v_periodo_id IS NULL THEN
    RAISE EXCEPTION 'Período contable cerrado o no existe para %', p_fecha;
  END IF;

  -- Resolver diario contable
  IF p_diario_id IS NOT NULL THEN
    v_diario_id := p_diario_id;
  ELSE
    -- Inferir diario del documento_tipo o tipo de asiento
    SELECT id INTO v_diario_id FROM diarios_contables
    WHERE empresa_id = p_empresa_id
      AND tipo = CASE
        WHEN p_documento_tipo IN ('FACTURA', 'NC', 'ND') THEN 'VENTAS'
        WHEN p_documento_tipo IN ('COMPRA', 'LC')        THEN 'COMPRAS'
        WHEN p_documento_tipo = 'NOMINA'                 THEN 'NOMINA'
        WHEN p_documento_tipo = 'ACTIVO_FIJO'            THEN 'DEPRECIACION'
        ELSE 'MISCELANEO'
      END
      AND activo = true
    LIMIT 1;
    IF v_diario_id IS NULL THEN
      -- Fallback: diario MISCELANEO
      SELECT id INTO v_diario_id FROM diarios_contables
      WHERE empresa_id = p_empresa_id AND tipo = 'MISCELANEO' AND activo = true
      LIMIT 1;
    END IF;
  END IF;

  -- Validar balance (debe = haber)
  FOR v_linea IN SELECT * FROM jsonb_array_elements(p_lineas) LOOP
    v_total_debe  := v_total_debe  + (v_linea->>'debe')::DECIMAL;
    v_total_haber := v_total_haber + (v_linea->>'haber')::DECIMAL;
  END LOOP;
  IF v_total_debe != v_total_haber THEN
    RAISE EXCEPTION 'Asiento desbalanceado: debe=% haber=%', v_total_debe, v_total_haber;
  END IF;

  -- Crear asiento (numero asignado por trigger tr_asiento_numero)
  INSERT INTO asientos_contables (
    empresa_id, periodo_id, diario_id, fecha, descripcion,
    tipo, documento_tipo, documento_id
  ) VALUES (
    p_empresa_id, v_periodo_id, v_diario_id, p_fecha, p_descripcion,
    p_tipo, p_documento_tipo, p_documento_id
  ) RETURNING id INTO v_asiento_id;

  -- Crear líneas
  INSERT INTO asiento_lineas (
    asiento_id, empresa_id, cuenta_id, descripcion, debe, haber,
    contacto_id, centro_costo_id, proyecto_id
  )
  SELECT
    v_asiento_id,
    p_empresa_id,
    (l->>'cuenta_id')::UUID,
    l->>'descripcion',
    (l->>'debe')::DECIMAL,
    (l->>'haber')::DECIMAL,
    (l->>'contacto_id')::UUID,
    (l->>'centro_costo_id')::UUID,
    (l->>'proyecto_id')::UUID
  FROM jsonb_array_elements(p_lineas) l;

  RETURN v_asiento_id;
END;
$$;
```

### get_ledger — libro mayor por cuenta (bug corregido)

```sql
-- CORRECCIÓN: la versión anterior calculaba saldo siempre como (debe - haber),
-- lo cual era incorrecto para cuentas ACREEDORAS (Pasivo, Patrimonio, Ingreso).
-- El saldo de una cuenta ACREEDORA se incrementa con haber y disminuye con debe.
CREATE OR REPLACE FUNCTION get_ledger(
  p_empresa_id  UUID,
  p_cuenta_id   UUID,
  p_fecha_desde DATE,
  p_fecha_hasta DATE
) RETURNS TABLE (
  fecha DATE, asiento_numero INT, asiento_id UUID, diario VARCHAR,
  descripcion TEXT, debe DECIMAL, haber DECIMAL, saldo DECIMAL
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_saldo_inicial DECIMAL(14,2);
  v_naturaleza    VARCHAR(10);
BEGIN
  -- Obtener naturaleza de la cuenta para calcular saldo correctamente
  SELECT naturaleza INTO v_naturaleza
  FROM cuentas_contables WHERE id = p_cuenta_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Cuenta contable % no encontrada', p_cuenta_id;
  END IF;

  -- Saldo inicial: todos los movimientos ANTES de fecha_desde
  SELECT COALESCE(SUM(
    CASE WHEN v_naturaleza = 'DEUDORA' THEN l.debe - l.haber
         ELSE l.haber - l.debe END
  ), 0) INTO v_saldo_inicial
  FROM asiento_lineas l
  JOIN asientos_contables a ON a.id = l.asiento_id
  WHERE l.cuenta_id = p_cuenta_id
    AND a.empresa_id = p_empresa_id
    AND a.estado = 'CONTABILIZADO'
    AND a.fecha < p_fecha_desde;

  RETURN QUERY
  SELECT
    a.fecha,
    a.numero,
    a.id,
    d.nombre AS diario,
    COALESCE(l.descripcion, a.descripcion),
    l.debe,
    l.haber,
    -- Saldo acumulado ajustado según naturaleza de la cuenta
    v_saldo_inicial + SUM(
      CASE WHEN v_naturaleza = 'DEUDORA' THEN l.debe - l.haber
           ELSE l.haber - l.debe END
    ) OVER (ORDER BY a.fecha, a.numero, l.id) AS saldo
  FROM asiento_lineas l
  JOIN asientos_contables a  ON a.id = l.asiento_id
  JOIN diarios_contables   d ON d.id = a.diario_id
  WHERE a.empresa_id = p_empresa_id
    AND l.cuenta_id  = p_cuenta_id
    AND a.fecha BETWEEN p_fecha_desde AND p_fecha_hasta
    AND a.estado = 'CONTABILIZADO'
  ORDER BY a.fecha, a.numero, l.id;
END;
$$;
```

### get_journal — libro diario

```sql
-- Obtener libro diario de un período
CREATE OR REPLACE FUNCTION get_journal(
  p_empresa_id  UUID,
  p_fecha_desde DATE,
  p_fecha_hasta DATE
) RETURNS TABLE (
  asiento_id UUID, numero INT, fecha DATE, descripcion TEXT, tipo VARCHAR,
  cuenta_codigo VARCHAR, cuenta_nombre VARCHAR, debe DECIMAL, haber DECIMAL
)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT a.id, a.numero, a.fecha, a.descripcion, a.tipo,
         c.codigo, c.nombre, l.debe, l.haber
  FROM asientos_contables a
  JOIN asiento_lineas l    ON l.asiento_id = a.id
  JOIN cuentas_contables c ON c.id = l.cuenta_id
  WHERE a.empresa_id = p_empresa_id
    AND a.fecha BETWEEN p_fecha_desde AND p_fecha_hasta
    AND a.estado = 'CONTABILIZADO'
  ORDER BY a.fecha, a.numero, l.id;
$$;
```

### get_trial_balance — balance de comprobación

```sql
-- Balance de comprobación (incluye p_fecha_desde para saldo inicial + movimientos del período)
CREATE OR REPLACE FUNCTION get_trial_balance(
  p_empresa_id  UUID,
  p_fecha_desde DATE,  -- fecha inicio del período (saldo inicial = acumulado antes de esta fecha)
  p_fecha_hasta DATE
) RETURNS TABLE (
  cuenta_codigo    VARCHAR,
  cuenta_nombre    VARCHAR,
  tipo             VARCHAR,
  naturaleza       VARCHAR,
  saldo_inicial    DECIMAL,  -- Movimientos acumulados ANTES de p_fecha_desde
  debe_periodo     DECIMAL,  -- Débitos entre p_fecha_desde y p_fecha_hasta
  haber_periodo    DECIMAL,  -- Créditos entre p_fecha_desde y p_fecha_hasta
  saldo_final      DECIMAL   -- saldo_inicial ± movimientos del período (según naturaleza)
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN QUERY
  SELECT
    c.codigo, c.nombre, c.tipo, c.naturaleza,
    -- Saldo inicial: movimientos antes de p_fecha_desde
    COALESCE(SUM(CASE WHEN a.fecha < p_fecha_desde
      THEN CASE WHEN c.naturaleza = 'DEUDORA' THEN l.debe - l.haber ELSE l.haber - l.debe END
      ELSE 0 END), 0) AS saldo_inicial,
    -- Movimientos del período
    COALESCE(SUM(CASE WHEN a.fecha BETWEEN p_fecha_desde AND p_fecha_hasta THEN l.debe  ELSE 0 END), 0) AS debe_periodo,
    COALESCE(SUM(CASE WHEN a.fecha BETWEEN p_fecha_desde AND p_fecha_hasta THEN l.haber ELSE 0 END), 0) AS haber_periodo,
    -- Saldo final acumulado hasta p_fecha_hasta
    COALESCE(SUM(
      CASE WHEN c.naturaleza = 'DEUDORA' THEN l.debe - l.haber ELSE l.haber - l.debe END
    ), 0) AS saldo_final
  FROM cuentas_contables c
  LEFT JOIN asiento_lineas l    ON l.cuenta_id = c.id
  LEFT JOIN asientos_contables a ON a.id = l.asiento_id
    AND a.estado = 'CONTABILIZADO'
    AND a.fecha <= p_fecha_hasta
  WHERE c.empresa_id = p_empresa_id AND c.es_movimiento = true
  GROUP BY c.codigo, c.nombre, c.tipo, c.naturaleza
  HAVING COALESCE(SUM(ABS(l.debe) + ABS(l.haber)), 0) > 0
  ORDER BY c.codigo;
END;
$$;
```

### reverse_journal_entry — crear asiento de reverso

```sql
CREATE OR REPLACE FUNCTION reverse_journal_entry(
  p_empresa_id UUID,
  p_asiento_id UUID,
  p_fecha      DATE DEFAULT CURRENT_DATE,
  p_motivo     TEXT DEFAULT 'Reverso de asiento'
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_asiento    asientos_contables%ROWTYPE;
  v_lineas     JSONB;
  v_reverso_id UUID;
BEGIN
  SELECT * INTO v_asiento FROM asientos_contables
  WHERE id = p_asiento_id AND empresa_id = p_empresa_id AND estado = 'CONTABILIZADO';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Asiento % no existe o no está contabilizado', p_asiento_id;
  END IF;

  -- Invertir debe/haber de todas las líneas
  SELECT jsonb_agg(jsonb_build_object(
    'cuenta_id',       cuenta_id,
    'descripcion',     descripcion,
    'debe',            haber,   -- invertido
    'haber',           debe,    -- invertido
    'contacto_id',     contacto_id,
    'centro_costo_id', centro_costo_id,
    'proyecto_id',     proyecto_id
  )) INTO v_lineas
  FROM asiento_lineas WHERE asiento_id = p_asiento_id;

  v_reverso_id := create_journal_entry(
    p_empresa_id, p_fecha,
    p_motivo || ' #' || v_asiento.numero,
    'REVERSO', v_lineas,
    v_asiento.documento_tipo, v_asiento.documento_id,
    v_asiento.diario_id
  );

  UPDATE asientos_contables
    SET asiento_reverso_id = v_reverso_id
  WHERE id = p_asiento_id;

  RETURN v_reverso_id;
END;
$$;
```

### get_budget_vs_actual — presupuesto vs real

```sql
CREATE OR REPLACE FUNCTION get_budget_vs_actual(
  p_empresa_id     UUID,
  p_presupuesto_id UUID,
  p_mes            INTEGER
) RETURNS TABLE (
  cuenta_codigo        VARCHAR,
  cuenta_nombre        VARCHAR,
  centro_costo         VARCHAR,
  presupuestado        DECIMAL,
  ejecutado            DECIMAL,
  diferencia           DECIMAL,
  porcentaje_ejecucion DECIMAL
)
-- Compara monto presupuestado del mes vs suma real de asientos contabilizados
-- del mismo mes/anio, agrupado por cuenta y centro de costo.
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_anio INTEGER;
BEGIN
  SELECT anio INTO v_anio FROM presupuestos
  WHERE id = p_presupuesto_id AND empresa_id = p_empresa_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Presupuesto % no encontrado para la empresa', p_presupuesto_id;
  END IF;

  RETURN QUERY
  WITH mes AS (
    SELECT pl2.cuenta_id, pl2.centro_costo_id,
      CASE p_mes
        WHEN 1  THEN pl2.mes_01 WHEN 2  THEN pl2.mes_02 WHEN 3  THEN pl2.mes_03
        WHEN 4  THEN pl2.mes_04 WHEN 5  THEN pl2.mes_05 WHEN 6  THEN pl2.mes_06
        WHEN 7  THEN pl2.mes_07 WHEN 8  THEN pl2.mes_08 WHEN 9  THEN pl2.mes_09
        WHEN 10 THEN pl2.mes_10 WHEN 11 THEN pl2.mes_11 WHEN 12 THEN pl2.mes_12
        ELSE 0 END AS monto
    FROM presupuesto_lineas pl2 WHERE pl2.presupuesto_id = p_presupuesto_id
  )
  SELECT
    c.codigo,
    c.nombre,
    cc.nombre AS centro_costo,
    mes.monto AS presupuestado,
    COALESCE(real.ejecutado, 0) AS ejecutado,
    mes.monto - COALESCE(real.ejecutado, 0) AS diferencia,
    CASE WHEN mes.monto = 0 THEN 0::DECIMAL
         ELSE ROUND(COALESCE(real.ejecutado, 0) * 100 / mes.monto, 2) END
  FROM presupuesto_lineas pl
  JOIN presupuestos p         ON p.id = pl.presupuesto_id
  JOIN cuentas_contables c    ON c.id = pl.cuenta_id
  JOIN mes                    ON mes.cuenta_id = pl.cuenta_id
        AND (mes.centro_costo_id IS NOT DISTINCT FROM pl.centro_costo_id)
  LEFT JOIN centros_costo cc  ON cc.id = pl.centro_costo_id
  LEFT JOIN (
    SELECT l.cuenta_id, l.centro_costo_id,
           SUM(CASE WHEN c2.naturaleza = 'DEUDORA' THEN l.debe - l.haber
                    ELSE l.haber - l.debe END) AS ejecutado
    FROM asiento_lineas l
    JOIN asientos_contables a  ON a.id = l.asiento_id
    JOIN cuentas_contables c2  ON c2.id = l.cuenta_id
    WHERE a.empresa_id = p_empresa_id
      AND a.estado = 'CONTABILIZADO'
      AND EXTRACT(YEAR  FROM a.fecha) = v_anio
      AND EXTRACT(MONTH FROM a.fecha) = p_mes
    GROUP BY l.cuenta_id, l.centro_costo_id
  ) real ON real.cuenta_id = pl.cuenta_id
        AND (real.centro_costo_id IS NOT DISTINCT FROM pl.centro_costo_id)
  WHERE p.id = p_presupuesto_id
  ORDER BY c.codigo;
END;
$$;
```

### generate_deferred_entries — diferidos

```sql
CREATE OR REPLACE FUNCTION generate_deferred_entries(
  p_empresa_id UUID,
  p_fecha      DATE DEFAULT CURRENT_DATE
) RETURNS INTEGER  -- cantidad de asientos generados
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_linea      diferido_lineas%ROWTYPE;
  v_diferido   diferidos%ROWTYPE;
  v_lineas     JSONB;
  v_count      INTEGER := 0;
BEGIN
  FOR v_linea IN
    SELECT dl.* FROM diferido_lineas dl
    JOIN diferidos d ON d.id = dl.diferido_id
    WHERE d.empresa_id = p_empresa_id
      AND dl.estado = 'PENDIENTE'
      AND dl.fecha <= p_fecha
  LOOP
    SELECT * INTO v_diferido FROM diferidos WHERE id = v_linea.diferido_id;

    -- INGRESO: Db cuenta_origen (Pasivo diferido) / Cr cuenta_destino (Ingreso)
    -- GASTO:   Db cuenta_destino (Gasto) / Cr cuenta_origen (Activo prepagado)
    IF v_diferido.tipo = 'INGRESO' THEN
      v_lineas := jsonb_build_array(
        jsonb_build_object('cuenta_id', v_diferido.cuenta_origen_id,
          'descripcion', v_diferido.descripcion, 'debe', v_linea.monto, 'haber', 0),
        jsonb_build_object('cuenta_id', v_diferido.cuenta_destino_id,
          'descripcion', v_diferido.descripcion, 'debe', 0, 'haber', v_linea.monto)
      );
    ELSE
      v_lineas := jsonb_build_array(
        jsonb_build_object('cuenta_id', v_diferido.cuenta_destino_id,
          'descripcion', v_diferido.descripcion, 'debe', v_linea.monto, 'haber', 0),
        jsonb_build_object('cuenta_id', v_diferido.cuenta_origen_id,
          'descripcion', v_diferido.descripcion, 'debe', 0, 'haber', v_linea.monto)
      );
    END IF;

    UPDATE diferido_lineas SET
      asiento_id = create_journal_entry(
        p_empresa_id, v_linea.fecha, v_diferido.descripcion,
        'AUTOMATICO', v_lineas, 'DIFERIDO', v_diferido.id
      ),
      estado = 'CONTABILIZADO'
    WHERE id = v_linea.id;

    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$;
```

### generate_recurring_entries — asientos recurrentes

```sql
CREATE OR REPLACE FUNCTION generate_recurring_entries(
  p_empresa_id UUID,
  p_fecha      DATE DEFAULT CURRENT_DATE
) RETURNS INTEGER  -- cantidad de asientos generados
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_rec    asientos_recurrentes%ROWTYPE;
  v_id     UUID;
  v_count  INTEGER := 0;
BEGIN
  FOR v_rec IN
    SELECT * FROM asientos_recurrentes
    WHERE empresa_id = p_empresa_id
      AND activo = true
      AND proximo_fecha <= p_fecha
      AND (fecha_fin IS NULL OR fecha_fin >= p_fecha)
  LOOP
    v_id := create_journal_entry(
      p_empresa_id, v_rec.proximo_fecha,
      v_rec.nombre, 'AUTOMATICO',
      v_rec.lineas_template,
      'RECURRENTE', v_rec.id,
      v_rec.diario_id
    );

    -- Avanzar proximo_fecha según frecuencia
    UPDATE asientos_recurrentes SET
      proximo_fecha = CASE v_rec.frecuencia
        WHEN 'MENSUAL'     THEN proximo_fecha + INTERVAL '1 month'
        WHEN 'TRIMESTRAL'  THEN proximo_fecha + INTERVAL '3 months'
        WHEN 'ANUAL'       THEN proximo_fecha + INTERVAL '1 year'
      END,
      ultimo_asiento_id = v_id
    WHERE id = v_rec.id;

    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$;
```

### get_cash_flow_statement — estado de flujo de efectivo (método indirecto)

```sql
CREATE OR REPLACE FUNCTION get_cash_flow_statement(
  p_empresa_id UUID,
  p_anio       INTEGER,
  p_mes_hasta  INTEGER DEFAULT 12
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $
DECLARE
  v_fecha_desde   DATE;
  v_fecha_hasta   DATE;

  -- Actividades de Operación
  v_utilidad_neta          DECIMAL(14,2) := 0;
  v_depreciacion           DECIMAL(14,2) := 0;
  v_amortizacion           DECIMAL(14,2) := 0;
  v_provision_incobrables  DECIMAL(14,2) := 0;
  v_var_cxc                DECIMAL(14,2) := 0;
  v_var_inventarios        DECIMAL(14,2) := 0;
  v_var_cxp                DECIMAL(14,2) := 0;
  v_var_otros_corrientes   DECIMAL(14,2) := 0;
  v_flujo_operacion        DECIMAL(14,2) := 0;

  -- Actividades de Inversión
  v_compras_ppe            DECIMAL(14,2) := 0;
  v_ventas_ppe             DECIMAL(14,2) := 0;
  v_flujo_inversion        DECIMAL(14,2) := 0;

  -- Actividades de Financiamiento
  v_prestamos_recibidos    DECIMAL(14,2) := 0;
  v_pagos_prestamos        DECIMAL(14,2) := 0;
  v_aportes_capital        DECIMAL(14,2) := 0;
  v_dividendos_pagados     DECIMAL(14,2) := 0;
  v_flujo_financiamiento   DECIMAL(14,2) := 0;

  -- Efectivo
  v_efectivo_inicial       DECIMAL(14,2) := 0;
  v_efectivo_final         DECIMAL(14,2) := 0;
  v_variacion_neta         DECIMAL(14,2) := 0;
BEGIN
  v_fecha_desde := make_date(p_anio, 1, 1);
  v_fecha_hasta := make_date(p_anio, p_mes_hasta, 1) + (INTERVAL '1 month' - INTERVAL '1 day');

  -- Materializar saldos en tablas temporales.
  -- En plpgsql, cada sentencia SQL tiene su propio scope: las CTEs definidas
  -- en una sentencia NO son accesibles en sentencias posteriores. Por eso se
  -- usan TEMP TABLEs que persisten durante la transacción (ON COMMIT DROP).
  CREATE TEMP TABLE _sp (
    codigo     VARCHAR(20),
    tipo       VARCHAR(15),
    naturaleza VARCHAR(10),
    saldo      DECIMAL(14,2)
  ) ON COMMIT DROP;

  -- _sp: saldos del período actual (entre v_fecha_desde y v_fecha_hasta)
  INSERT INTO _sp (codigo, tipo, naturaleza, saldo)
  SELECT cc.codigo, cc.tipo, cc.naturaleza,
    CASE WHEN cc.naturaleza = 'DEUDORA'
      THEN COALESCE(SUM(al.debe - al.haber), 0)
      ELSE COALESCE(SUM(al.haber - al.debe), 0)
    END
  FROM cuentas_contables cc
  LEFT JOIN asiento_lineas al ON al.cuenta_id = cc.id
  LEFT JOIN asientos_contables ac ON ac.id = al.asiento_id
    AND ac.empresa_id = p_empresa_id
    AND ac.estado = 'CONTABILIZADO'
    AND ac.fecha BETWEEN v_fecha_desde AND v_fecha_hasta
  WHERE cc.empresa_id = p_empresa_id AND cc.es_movimiento = true
  GROUP BY cc.codigo, cc.tipo, cc.naturaleza;

  CREATE TEMP TABLE _sa (
    codigo     VARCHAR(20),
    naturaleza VARCHAR(10),
    saldo      DECIMAL(14,2)
  ) ON COMMIT DROP;

  -- _sa: saldos acumulados hasta el día anterior al período (saldo inicial)
  INSERT INTO _sa (codigo, naturaleza, saldo)
  SELECT cc.codigo, cc.naturaleza,
    CASE WHEN cc.naturaleza = 'DEUDORA'
      THEN COALESCE(SUM(al.debe - al.haber), 0)
      ELSE COALESCE(SUM(al.haber - al.debe), 0)
    END
  FROM cuentas_contables cc
  LEFT JOIN asiento_lineas al ON al.cuenta_id = cc.id
  LEFT JOIN asientos_contables ac ON ac.id = al.asiento_id
    AND ac.empresa_id = p_empresa_id
    AND ac.estado = 'CONTABILIZADO'
    AND ac.fecha < v_fecha_desde
  WHERE cc.empresa_id = p_empresa_id AND cc.es_movimiento = true
  GROUP BY cc.codigo, cc.naturaleza;

  -- Utilidad neta + ajustes no monetarios (desde _sp)
  SELECT
    COALESCE(SUM(CASE WHEN tipo = 'INGRESO' THEN saldo ELSE 0 END), 0)
    - COALESCE(SUM(CASE WHEN tipo IN ('COSTO','GASTO') THEN saldo ELSE 0 END), 0),
    -- Depreciación: cuentas 520103 (admin) y 520204 (ventas)
    COALESCE(SUM(CASE WHEN codigo LIKE '520103%' OR codigo LIKE '520204%' THEN saldo ELSE 0 END), 0),
    -- Amortización: cuenta 520205
    COALESCE(SUM(CASE WHEN codigo LIKE '520205%' THEN saldo ELSE 0 END), 0),
    -- Provisión cuentas incobrables: cuenta 520213
    COALESCE(SUM(CASE WHEN codigo LIKE '520213%' THEN saldo ELSE 0 END), 0)
  INTO v_utilidad_neta, v_depreciacion, v_amortizacion, v_provision_incobrables
  FROM _sp;

  -- Variación capital de trabajo (período vs saldo inicial)
  SELECT
    -- CxC: aumento de activo corriente = uso de efectivo (negativo)
    -(COALESCE(SUM(CASE WHEN cc.codigo LIKE '10102%' THEN COALESCE(sp.saldo,0) - COALESCE(sa.saldo,0) ELSE 0 END), 0)),
    -- Inventarios: aumento = uso de efectivo (negativo)
    -(COALESCE(SUM(CASE WHEN cc.codigo LIKE '10103%' THEN COALESCE(sp.saldo,0) - COALESCE(sa.saldo,0) ELSE 0 END), 0)),
    -- CxP: aumento de pasivo corriente = fuente de efectivo (positivo)
    COALESCE(SUM(CASE WHEN cc.codigo LIKE '20101%' THEN COALESCE(sp.saldo,0) - COALESCE(sa.saldo,0) ELSE 0 END), 0),
    -- Otros corrientes netos (SRI por pagar menos otros activos corrientes)
    COALESCE(SUM(CASE WHEN cc.codigo LIKE '20107%' THEN COALESCE(sp.saldo,0) - COALESCE(sa.saldo,0) ELSE 0 END), 0)
    - COALESCE(SUM(CASE WHEN cc.codigo LIKE '10104%' THEN COALESCE(sp.saldo,0) - COALESCE(sa.saldo,0) ELSE 0 END), 0)
  INTO v_var_cxc, v_var_inventarios, v_var_cxp, v_var_otros_corrientes
  FROM cuentas_contables cc
  LEFT JOIN _sp sp USING (codigo)
  LEFT JOIN _sa sa USING (codigo)
  WHERE cc.empresa_id = p_empresa_id AND cc.es_movimiento = true;

  v_flujo_operacion := v_utilidad_neta + v_depreciacion + v_amortizacion
    + v_provision_incobrables + v_var_cxc + v_var_inventarios
    + v_var_cxp + v_var_otros_corrientes;

  -- Actividades de inversión (PP&E: cuentas 1020x)
  SELECT
    -- Compras PP&E: aumento neto en activos (uso efectivo)
    -(GREATEST(0, COALESCE(SUM(COALESCE(sp.saldo,0) - COALESCE(sa.saldo,0)), 0))),
    -- Ventas PP&E: disminución neta (fuente efectivo)
    GREATEST(0, -(COALESCE(SUM(COALESCE(sp.saldo,0) - COALESCE(sa.saldo,0)), 0)))
  INTO v_compras_ppe, v_ventas_ppe
  FROM cuentas_contables cc
  LEFT JOIN _sp sp USING (codigo)
  LEFT JOIN _sa sa USING (codigo)
  WHERE cc.empresa_id = p_empresa_id AND cc.es_movimiento = true
    AND cc.codigo LIKE '1020%';

  v_flujo_inversion := v_compras_ppe + v_ventas_ppe;

  -- Actividades de financiamiento
  SELECT
    -- Préstamos LP recibidos: aumento pasivo LP
    GREATEST(0, COALESCE(SUM(CASE WHEN cc.codigo LIKE '202%' THEN COALESCE(sp.saldo,0) - COALESCE(sa.saldo,0) ELSE 0 END), 0)),
    -- Pagos préstamos: disminución pasivo LP
    -(LEAST(0, COALESCE(SUM(CASE WHEN cc.codigo LIKE '202%' THEN COALESCE(sp.saldo,0) - COALESCE(sa.saldo,0) ELSE 0 END), 0))),
    -- Aportes capital: aumento patrimonio (cuentas 301xx)
    GREATEST(0, COALESCE(SUM(CASE WHEN cc.codigo LIKE '301%' THEN COALESCE(sp.saldo,0) - COALESCE(sa.saldo,0) ELSE 0 END), 0)),
    -- Dividendos pagados: disminución resultados acumulados (306 excepto 307x)
    -(LEAST(0, COALESCE(SUM(CASE WHEN cc.codigo LIKE '306%' AND cc.codigo NOT LIKE '3070%' THEN COALESCE(sp.saldo,0) - COALESCE(sa.saldo,0) ELSE 0 END), 0)))
  INTO v_prestamos_recibidos, v_pagos_prestamos, v_aportes_capital, v_dividendos_pagados
  FROM cuentas_contables cc
  LEFT JOIN _sp sp USING (codigo)
  LEFT JOIN _sa sa USING (codigo)
  WHERE cc.empresa_id = p_empresa_id AND cc.es_movimiento = true;

  v_flujo_financiamiento := v_prestamos_recibidos - v_pagos_prestamos
    + v_aportes_capital - v_dividendos_pagados;

  -- Efectivo inicial y final (cuentas 10101 = Efectivo y Equivalentes)
  SELECT
    COALESCE(SUM(COALESCE(sa.saldo, 0)), 0),
    COALESCE(SUM(COALESCE(sp.saldo, 0)), 0)
  INTO v_efectivo_inicial, v_efectivo_final
  FROM cuentas_contables cc
  LEFT JOIN _sp sp USING (codigo)
  LEFT JOIN _sa sa USING (codigo)
  WHERE cc.empresa_id = p_empresa_id AND cc.es_movimiento = true
    AND cc.codigo LIKE '10101%';

  v_variacion_neta := v_flujo_operacion + v_flujo_inversion + v_flujo_financiamiento;

  RETURN jsonb_build_object(
    'periodo', jsonb_build_object('anio', p_anio, 'mes_hasta', p_mes_hasta),
    'metodo', 'INDIRECTO',
    'actividades_operacion', jsonb_build_object(
      'utilidad_neta',            v_utilidad_neta,
      'ajustes_no_monetarios', jsonb_build_object(
        'depreciacion',           v_depreciacion,
        'amortizacion',           v_amortizacion,
        'provision_incobrables',  v_provision_incobrables
      ),
      'variaciones_capital_trabajo', jsonb_build_object(
        'variacion_cxc',          v_var_cxc,
        'variacion_inventarios',  v_var_inventarios,
        'variacion_cxp',          v_var_cxp,
        'variacion_otros_neto',   v_var_otros_corrientes
      ),
      'total',                    v_flujo_operacion
    ),
    'actividades_inversion', jsonb_build_object(
      'compras_activos_fijos',    v_compras_ppe,
      'ventas_activos_fijos',     v_ventas_ppe,
      'total',                    v_flujo_inversion
    ),
    'actividades_financiamiento', jsonb_build_object(
      'prestamos_recibidos',      v_prestamos_recibidos,
      'pagos_prestamos',          v_pagos_prestamos,
      'aportes_capital',          v_aportes_capital,
      'dividendos_pagados',       v_dividendos_pagados,
      'total',                    v_flujo_financiamiento
    ),
    'variacion_neta_efectivo',    v_variacion_neta,
    'efectivo_inicio_periodo',    v_efectivo_inicial,
    'efectivo_fin_periodo',       v_efectivo_final,
    'verificacion_cuadre',        jsonb_build_object(
      'cuadra', ABS((v_efectivo_inicial + v_variacion_neta) - v_efectivo_final) < 0.01,
      'diferencia', (v_efectivo_inicial + v_variacion_neta) - v_efectivo_final
    )
  );
END;
$;
```

### approve_journal_entry — aprobación de asientos manuales (P2)

```sql
-- Flujo de aprobación para asientos tipo MANUAL.
-- Los AUTOMATICO van directo a CONTABILIZADO (sin aprobación).
CREATE OR REPLACE FUNCTION approve_journal_entry(
  p_asiento_id UUID
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  -- Validar estado y tipo
  UPDATE asientos_contables
    SET estado           = 'CONTABILIZADO',
        aprobado_por     = auth.uid(),
        fecha_aprobacion = NOW(),
        version          = version + 1,
        updated_at       = NOW()
  WHERE id = p_asiento_id
    AND estado = 'PENDIENTE_APROBACION'
    AND tipo   = 'MANUAL';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Asiento % no está pendiente de aprobación o no es de tipo MANUAL', p_asiento_id;
  END IF;
END;
$$;
```

### execute_period_close — cierre de período

```sql
CREATE OR REPLACE FUNCTION execute_period_close(
  p_empresa_id UUID,
  p_periodo_id UUID
) RETURNS UUID  -- asiento_cierre_id (NULL si no es diciembre)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_periodo        periodos_contables%ROWTYPE;
  v_asiento_id     UUID := NULL;
  v_lineas         JSONB := '[]'::JSONB;
  v_cuenta_resultado UUID;
BEGIN
  SELECT * INTO v_periodo FROM periodos_contables
  WHERE id = p_periodo_id AND empresa_id = p_empresa_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Período % no existe para la empresa', p_periodo_id;
  END IF;

  -- Verificar checklist completo
  IF EXISTS (
    SELECT 1 FROM cierre_periodo
    WHERE periodo_id = p_periodo_id
      AND EXISTS (
        SELECT 1 FROM jsonb_array_elements(checklist) c
        WHERE NOT (c->>'completado')::BOOLEAN
      )
  ) THEN
    RAISE EXCEPTION 'Checklist de cierre incompleto';
  END IF;

  -- Asiento de cierre anual NIIF (solo diciembre)
  IF v_periodo.mes = 12 THEN
    -- Cuenta "Resultado del Ejercicio" (Patrimonio, código 307xx en plan SCVS Ecuador)
    SELECT id INTO v_cuenta_resultado FROM cuentas_contables
    WHERE empresa_id = p_empresa_id
      AND tipo = 'PATRIMONIO'
      AND codigo LIKE '307%'
    LIMIT 1;

    -- La generación completa del asiento de cierre (con todas las líneas de
    -- cuentas de Ingreso, Gasto y Resultado del Ejercicio balanceadas) se
    -- delega a la Edge Function `contabilidad-cierre-anual` para evitar
    -- timeouts en empresas con muchas cuentas de movimiento.
    -- Esta RPC orquesta el proceso y devuelve el asiento_id creado.

    v_asiento_id := create_journal_entry(
      p_empresa_id,
      (v_periodo.anio || '-12-31')::DATE,
      'Asiento de cierre anual ' || v_periodo.anio,
      'CIERRE', v_lineas,
      'CIERRE_ANUAL', p_periodo_id
    );
  END IF;

  -- Cerrar período
  UPDATE periodos_contables
    SET estado      = 'CERRADO',
        fecha_cierre = NOW(),
        cerrado_por  = auth.uid()
  WHERE id = p_periodo_id;

  UPDATE cierre_periodo
    SET estado            = 'CERRADO',
        fecha_cierre      = NOW(),
        cerrado_por       = auth.uid(),
        asiento_cierre_id = v_asiento_id,
        lock_date         = (
          (v_periodo.anio || '-' || LPAD(v_periodo.mes::TEXT, 2, '0') || '-01')::DATE
          + INTERVAL '1 month' - INTERVAL '1 day'
        )
  WHERE periodo_id = p_periodo_id AND empresa_id = p_empresa_id;

  RETURN v_asiento_id;
END;
$$;

-- NOTA: El asiento de cierre anual completo (con todas las líneas de cuentas
-- de Ingreso, Gasto y Resultado del Ejercicio) se genera en la Edge Function
-- `contabilidad-cierre-anual`. La RPC `execute_period_close` orquesta el
-- proceso y llama a la Edge Function.
```

> **Nota**: Los informes tributarios SRI (ATS, F-103, F-104) se han movido al módulo
> **[Tributación (Core #10)](../tributacion/tributacion.md)**. Contabilidad provee los datos
> del plan de cuentas y asientos vía module_bus; Tributación consume esos datos para generar
> las declaraciones. Esto elimina la dependencia de Contabilidad sobre los schemas de Facturación y Compras.

## Seed: Plan de Cuentas NIIF PYMES Ecuador (SCVS)

Al activar Contabilidad para una nueva empresa, se invoca `create_niif_pymes_chart_of_accounts()` para crear el plan de cuentas base según el catálogo oficial SCVS (Superintendencia de Compañías, Resolución SCVS-INC-DNCDN-2019-0009).

```sql
CREATE OR REPLACE FUNCTION create_niif_pymes_chart_of_accounts(
  p_empresa_id UUID
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $
DECLARE
  -- Nivel 1
  v_activo     UUID; v_pasivo    UUID; v_patrimonio UUID;
  v_ingresos   UUID; v_costos    UUID; v_gastos     UUID;
  -- Nivel 2 Activo
  v_act_corr   UUID; v_act_nc    UUID;
  -- Nivel 2 Pasivo
  v_pas_corr   UUID; v_pas_nc    UUID;
  -- Nivel 2 Patrimonio
  v_capital    UUID; v_reservas  UUID; v_res_acum   UUID; v_res_ej    UUID;
  -- Nivel 2 Ingresos
  v_ing_ord    UUID; v_ing_otros UUID;
  -- Nivel 2 Costos y Gastos
  v_costo_vtas UUID;
  v_gasto_vtas UUID; v_gasto_adm UUID; v_gasto_fin UUID; v_gasto_otros UUID;
  -- Nivel 3 Activo Corriente
  v_efectivo   UUID; v_act_fin   UUID; v_inventarios UUID;
  v_ant_prov   UUID; v_imp_corr  UUID;
  -- Nivel 3 Activo No Corriente
  v_ppe        UUID; v_intang    UUID;
  -- Nivel 3 Pasivo Corriente
  v_cxp        UUID; v_otras_obl UUID;
BEGIN
  -- ================================================================
  -- NIVEL 1: Grupos principales
  -- ================================================================
  INSERT INTO cuentas_contables (empresa_id, codigo, nombre, tipo, naturaleza, nivel, padre_id, es_movimiento)
  VALUES (p_empresa_id, '1', 'ACTIVO', 'ACTIVO', 'DEUDORA', 1, NULL, false)
  RETURNING id INTO v_activo;

  INSERT INTO cuentas_contables (empresa_id, codigo, nombre, tipo, naturaleza, nivel, padre_id, es_movimiento)
  VALUES (p_empresa_id, '2', 'PASIVO', 'PASIVO', 'ACREEDORA', 1, NULL, false)
  RETURNING id INTO v_pasivo;

  INSERT INTO cuentas_contables (empresa_id, codigo, nombre, tipo, naturaleza, nivel, padre_id, es_movimiento)
  VALUES (p_empresa_id, '3', 'PATRIMONIO NETO', 'PATRIMONIO', 'ACREEDORA', 1, NULL, false)
  RETURNING id INTO v_patrimonio;

  INSERT INTO cuentas_contables (empresa_id, codigo, nombre, tipo, naturaleza, nivel, padre_id, es_movimiento)
  VALUES (p_empresa_id, '4', 'INGRESOS', 'INGRESO', 'ACREEDORA', 1, NULL, false)
  RETURNING id INTO v_ingresos;

  INSERT INTO cuentas_contables (empresa_id, codigo, nombre, tipo, naturaleza, nivel, padre_id, es_movimiento)
  VALUES (p_empresa_id, '5', 'COSTOS DE VENTAS Y PRODUCCIÓN', 'COSTO', 'DEUDORA', 1, NULL, false)
  RETURNING id INTO v_costos;

  INSERT INTO cuentas_contables (empresa_id, codigo, nombre, tipo, naturaleza, nivel, padre_id, es_movimiento)
  VALUES (p_empresa_id, '52', 'GASTOS', 'GASTO', 'DEUDORA', 1, NULL, false)
  RETURNING id INTO v_gastos;

  -- ================================================================
  -- NIVEL 2: Subgrupos Activo
  -- ================================================================
  INSERT INTO cuentas_contables (empresa_id, codigo, nombre, tipo, naturaleza, nivel, padre_id, es_movimiento)
  VALUES (p_empresa_id, '101', 'Activo Corriente', 'ACTIVO', 'DEUDORA', 2, v_activo, false)
  RETURNING id INTO v_act_corr;

  INSERT INTO cuentas_contables (empresa_id, codigo, nombre, tipo, naturaleza, nivel, padre_id, es_movimiento)
  VALUES (p_empresa_id, '102', 'Activo No Corriente', 'ACTIVO', 'DEUDORA', 2, v_activo, false)
  RETURNING id INTO v_act_nc;

  -- Pasivo
  INSERT INTO cuentas_contables (empresa_id, codigo, nombre, tipo, naturaleza, nivel, padre_id, es_movimiento)
  VALUES (p_empresa_id, '201', 'Pasivo Corriente', 'PASIVO', 'ACREEDORA', 2, v_pasivo, false)
  RETURNING id INTO v_pas_corr;

  INSERT INTO cuentas_contables (empresa_id, codigo, nombre, tipo, naturaleza, nivel, padre_id, es_movimiento)
  VALUES (p_empresa_id, '202', 'Pasivo No Corriente', 'PASIVO', 'ACREEDORA', 2, v_pasivo, false)
  RETURNING id INTO v_pas_nc;

  -- Patrimonio
  INSERT INTO cuentas_contables (empresa_id, codigo, nombre, tipo, naturaleza, nivel, padre_id, es_movimiento)
  VALUES (p_empresa_id, '301', 'Capital', 'PATRIMONIO', 'ACREEDORA', 2, v_patrimonio, false)
  RETURNING id INTO v_capital;

  INSERT INTO cuentas_contables (empresa_id, codigo, nombre, tipo, naturaleza, nivel, padre_id, es_movimiento)
  VALUES (p_empresa_id, '304', 'Reservas', 'PATRIMONIO', 'ACREEDORA', 2, v_patrimonio, false)
  RETURNING id INTO v_reservas;

  INSERT INTO cuentas_contables (empresa_id, codigo, nombre, tipo, naturaleza, nivel, padre_id, es_movimiento)
  VALUES (p_empresa_id, '306', 'Resultados Acumulados', 'PATRIMONIO', 'ACREEDORA', 2, v_patrimonio, false)
  RETURNING id INTO v_res_acum;

  INSERT INTO cuentas_contables (empresa_id, codigo, nombre, tipo, naturaleza, nivel, padre_id, es_movimiento)
  VALUES (p_empresa_id, '307', 'Resultados del Ejercicio', 'PATRIMONIO', 'ACREEDORA', 2, v_patrimonio, false)
  RETURNING id INTO v_res_ej;

  -- Ingresos
  INSERT INTO cuentas_contables (empresa_id, codigo, nombre, tipo, naturaleza, nivel, padre_id, es_movimiento)
  VALUES (p_empresa_id, '41', 'Ingresos de Actividades Ordinarias', 'INGRESO', 'ACREEDORA', 2, v_ingresos, false)
  RETURNING id INTO v_ing_ord;

  INSERT INTO cuentas_contables (empresa_id, codigo, nombre, tipo, naturaleza, nivel, padre_id, es_movimiento)
  VALUES (p_empresa_id, '43', 'Otros Ingresos', 'INGRESO', 'ACREEDORA', 2, v_ingresos, false)
  RETURNING id INTO v_ing_otros;

  -- Costos
  INSERT INTO cuentas_contables (empresa_id, codigo, nombre, tipo, naturaleza, nivel, padre_id, es_movimiento)
  VALUES (p_empresa_id, '51', 'Costo de Ventas y Producción', 'COSTO', 'DEUDORA', 2, v_costos, false)
  RETURNING id INTO v_costo_vtas;

  -- Gastos
  INSERT INTO cuentas_contables (empresa_id, codigo, nombre, tipo, naturaleza, nivel, padre_id, es_movimiento)
  VALUES (p_empresa_id, '5201', 'Gastos de Ventas', 'GASTO', 'DEUDORA', 2, v_gastos, false)
  RETURNING id INTO v_gasto_vtas;

  INSERT INTO cuentas_contables (empresa_id, codigo, nombre, tipo, naturaleza, nivel, padre_id, es_movimiento)
  VALUES (p_empresa_id, '5202', 'Gastos Administrativos', 'GASTO', 'DEUDORA', 2, v_gastos, false)
  RETURNING id INTO v_gasto_adm;

  INSERT INTO cuentas_contables (empresa_id, codigo, nombre, tipo, naturaleza, nivel, padre_id, es_movimiento)
  VALUES (p_empresa_id, '5203', 'Gastos Financieros', 'GASTO', 'DEUDORA', 2, v_gastos, false)
  RETURNING id INTO v_gasto_fin;

  INSERT INTO cuentas_contables (empresa_id, codigo, nombre, tipo, naturaleza, nivel, padre_id, es_movimiento)
  VALUES (p_empresa_id, '5204', 'Otros Gastos', 'GASTO', 'DEUDORA', 2, v_gastos, false)
  RETURNING id INTO v_gasto_otros;

  -- ================================================================
  -- NIVEL 3: Activo Corriente
  -- ================================================================
  INSERT INTO cuentas_contables (empresa_id, codigo, nombre, tipo, naturaleza, nivel, padre_id, es_movimiento)
  VALUES (p_empresa_id, '10101', 'Efectivo y Equivalentes del Efectivo', 'ACTIVO', 'DEUDORA', 3, v_act_corr, false)
  RETURNING id INTO v_efectivo;

  INSERT INTO cuentas_contables (empresa_id, codigo, nombre, tipo, naturaleza, nivel, padre_id, es_movimiento)
  VALUES (p_empresa_id, '10102', 'Activos Financieros', 'ACTIVO', 'DEUDORA', 3, v_act_corr, false)
  RETURNING id INTO v_act_fin;

  INSERT INTO cuentas_contables (empresa_id, codigo, nombre, tipo, naturaleza, nivel, padre_id, es_movimiento)
  VALUES (p_empresa_id, '10103', 'Inventarios', 'ACTIVO', 'DEUDORA', 3, v_act_corr, false)
  RETURNING id INTO v_inventarios;

  INSERT INTO cuentas_contables (empresa_id, codigo, nombre, tipo, naturaleza, nivel, padre_id, es_movimiento)
  VALUES (p_empresa_id, '10104', 'Servicios y Otros Pagos Anticipados', 'ACTIVO', 'DEUDORA', 3, v_act_corr, false)
  RETURNING id INTO v_ant_prov;

  INSERT INTO cuentas_contables (empresa_id, codigo, nombre, tipo, naturaleza, nivel, padre_id, es_movimiento)
  VALUES (p_empresa_id, '10105', 'Activos por Impuestos Corrientes', 'ACTIVO', 'DEUDORA', 3, v_act_corr, false)
  RETURNING id INTO v_imp_corr;

  -- Activo No Corriente
  INSERT INTO cuentas_contables (empresa_id, codigo, nombre, tipo, naturaleza, nivel, padre_id, es_movimiento)
  VALUES (p_empresa_id, '10201', 'Propiedades, Planta y Equipo', 'ACTIVO', 'DEUDORA', 3, v_act_nc, false)
  RETURNING id INTO v_ppe;

  INSERT INTO cuentas_contables (empresa_id, codigo, nombre, tipo, naturaleza, nivel, padre_id, es_movimiento)
  VALUES (p_empresa_id, '10202', 'Activos Intangibles', 'ACTIVO', 'DEUDORA', 3, v_act_nc, false)
  RETURNING id INTO v_intang;

  -- Pasivo Corriente
  INSERT INTO cuentas_contables (empresa_id, codigo, nombre, tipo, naturaleza, nivel, padre_id, es_movimiento)
  VALUES (p_empresa_id, '20101', 'Cuentas y Documentos por Pagar', 'PASIVO', 'ACREEDORA', 3, v_pas_corr, false)
  RETURNING id INTO v_cxp;

  INSERT INTO cuentas_contables (empresa_id, codigo, nombre, tipo, naturaleza, nivel, padre_id, es_movimiento)
  VALUES (p_empresa_id, '20107', 'Otras Obligaciones Corrientes', 'PASIVO', 'ACREEDORA', 3, v_pas_corr, false)
  RETURNING id INTO v_otras_obl;

  -- ================================================================
  -- NIVEL 4: Cuentas de movimiento (es_movimiento = true)
  -- ================================================================
  -- Efectivo
  INSERT INTO cuentas_contables (empresa_id, codigo, nombre, tipo, naturaleza, nivel, padre_id, es_movimiento)
  VALUES
    (p_empresa_id, '1010101', 'Caja General', 'ACTIVO', 'DEUDORA', 4, v_efectivo, true),
    (p_empresa_id, '1010102', 'Bancos', 'ACTIVO', 'DEUDORA', 4, v_efectivo, true);

  -- Activos Financieros
  INSERT INTO cuentas_contables (empresa_id, codigo, nombre, tipo, naturaleza, nivel, padre_id, es_movimiento, permite_contacto)
  VALUES
    (p_empresa_id, '1010201', 'Cuentas y Documentos por Cobrar - No Relacionados', 'ACTIVO', 'DEUDORA', 4, v_act_fin, true, true),
    (p_empresa_id, '1010202', 'Cuentas y Documentos por Cobrar - Relacionados', 'ACTIVO', 'DEUDORA', 4, v_act_fin, true, true),
    (p_empresa_id, '1010206', '(-) Provisión Cuentas Incobrables', 'ACTIVO', 'ACREEDORA', 4, v_act_fin, true, false);

  -- Inventarios
  INSERT INTO cuentas_contables (empresa_id, codigo, nombre, tipo, naturaleza, nivel, padre_id, es_movimiento)
  VALUES
    (p_empresa_id, '1010304', 'Inventario de Materias Primas / Suministros', 'ACTIVO', 'DEUDORA', 4, v_inventarios, true),
    (p_empresa_id, '1010305', 'Inventario de Mercaderías', 'ACTIVO', 'DEUDORA', 4, v_inventarios, true),
    (p_empresa_id, '1010301', 'Inventario de Productos Terminados', 'ACTIVO', 'DEUDORA', 4, v_inventarios, true),
    (p_empresa_id, '1010302', 'Inventario de Productos en Proceso', 'ACTIVO', 'DEUDORA', 4, v_inventarios, true);

  -- Pagos anticipados y anticipos
  INSERT INTO cuentas_contables (empresa_id, codigo, nombre, tipo, naturaleza, nivel, padre_id, es_movimiento)
  VALUES
    (p_empresa_id, '1010401', 'Seguros Pagados por Anticipado', 'ACTIVO', 'DEUDORA', 4, v_ant_prov, true),
    (p_empresa_id, '1010402', 'Arriendos Pagados por Anticipado', 'ACTIVO', 'DEUDORA', 4, v_ant_prov, true);

  INSERT INTO cuentas_contables (empresa_id, codigo, nombre, tipo, naturaleza, nivel, padre_id, es_movimiento, permite_contacto)
  VALUES
    (p_empresa_id, '1010403', 'Anticipos a Proveedores', 'ACTIVO', 'DEUDORA', 4, v_ant_prov, true, true);

  -- Impuestos corrientes
  INSERT INTO cuentas_contables (empresa_id, codigo, nombre, tipo, naturaleza, nivel, padre_id, es_movimiento)
  VALUES
    (p_empresa_id, '1010501', 'Crédito Tributario a Favor - IVA', 'ACTIVO', 'DEUDORA', 4, v_imp_corr, true),
    (p_empresa_id, '1010502', 'Crédito Tributario a Favor - IR', 'ACTIVO', 'DEUDORA', 4, v_imp_corr, true),
    (p_empresa_id, '1010503', 'Anticipo de Impuesto a la Renta', 'ACTIVO', 'DEUDORA', 4, v_imp_corr, true);

  -- PP&E
  INSERT INTO cuentas_contables (empresa_id, codigo, nombre, tipo, naturaleza, nivel, padre_id, es_movimiento)
  VALUES
    (p_empresa_id, '1020101', 'Terrenos', 'ACTIVO', 'DEUDORA', 4, v_ppe, true),
    (p_empresa_id, '1020102', 'Edificios y Locales Comerciales', 'ACTIVO', 'DEUDORA', 4, v_ppe, true),
    (p_empresa_id, '1020103', 'Muebles y Enseres', 'ACTIVO', 'DEUDORA', 4, v_ppe, true),
    (p_empresa_id, '1020104', 'Maquinaria, Equipo e Instalaciones', 'ACTIVO', 'DEUDORA', 4, v_ppe, true),
    (p_empresa_id, '1020105', 'Equipos de Computación', 'ACTIVO', 'DEUDORA', 4, v_ppe, true),
    (p_empresa_id, '1020106', 'Vehículos, Equipos de Transporte', 'ACTIVO', 'DEUDORA', 4, v_ppe, true),
    (p_empresa_id, '1020107', 'Equipos de Oficina', 'ACTIVO', 'DEUDORA', 4, v_ppe, true),
    (p_empresa_id, '102(-)', '(-) Depreciación Acumulada PP&E', 'ACTIVO', 'ACREEDORA', 4, v_ppe, true);

  -- Intangibles
  INSERT INTO cuentas_contables (empresa_id, codigo, nombre, tipo, naturaleza, nivel, padre_id, es_movimiento)
  VALUES
    (p_empresa_id, '1020201', 'Marcas y Patentes', 'ACTIVO', 'DEUDORA', 4, v_intang, true),
    (p_empresa_id, '1020202', 'Licencias de Software', 'ACTIVO', 'DEUDORA', 4, v_intang, true),
    (p_empresa_id, '102(--)','(-) Amortización Acumulada Intangibles', 'ACTIVO', 'ACREEDORA', 4, v_intang, true);

  -- CxP Proveedores
  INSERT INTO cuentas_contables (empresa_id, codigo, nombre, tipo, naturaleza, nivel, padre_id, es_movimiento, permite_contacto)
  VALUES
    (p_empresa_id, '2010101', 'Proveedores - No Relacionados', 'PASIVO', 'ACREEDORA', 4, v_cxp, true, true),
    (p_empresa_id, '2010102', 'Proveedores - Relacionados', 'PASIVO', 'ACREEDORA', 4, v_cxp, true, true);

  -- Otras obligaciones corrientes (obligaciones tributarias, IESS, etc.)
  INSERT INTO cuentas_contables (empresa_id, codigo, nombre, tipo, naturaleza, nivel, padre_id, es_movimiento)
  VALUES
    (p_empresa_id, '201070101', 'IVA en Ventas por Pagar', 'PASIVO', 'ACREEDORA', 4, v_otras_obl, true),
    (p_empresa_id, '201070104', 'Retenciones en la Fuente por Pagar', 'PASIVO', 'ACREEDORA', 4, v_otras_obl, true),
    (p_empresa_id, '201070105', 'IESS por Pagar', 'PASIVO', 'ACREEDORA', 4, v_otras_obl, true),
    (p_empresa_id, '2010702', 'Impuesto a la Renta por Pagar del Ejercicio', 'PASIVO', 'ACREEDORA', 4, v_otras_obl, true),
    (p_empresa_id, '2010704', 'Beneficios de Ley Empleados (15% PT)', 'PASIVO', 'ACREEDORA', 4, v_otras_obl, true),
    (p_empresa_id, '2010705', 'Participación Trabajadores 15%', 'PASIVO', 'ACREEDORA', 4, v_otras_obl, true),
    (p_empresa_id, '2010706', 'Anticipo Clientes', 'PASIVO', 'ACREEDORA', 4, v_otras_obl, true);

  -- Pasivo No Corriente
  INSERT INTO cuentas_contables (empresa_id, codigo, nombre, tipo, naturaleza, nivel, padre_id, es_movimiento)
  VALUES
    (p_empresa_id, '20201', 'Préstamos Bancarios Largo Plazo', 'PASIVO', 'ACREEDORA', 3, v_pas_nc, true),
    (p_empresa_id, '20202', 'Hipotecas por Pagar', 'PASIVO', 'ACREEDORA', 3, v_pas_nc, true);

  -- Capital y Patrimonio
  INSERT INTO cuentas_contables (empresa_id, codigo, nombre, tipo, naturaleza, nivel, padre_id, es_movimiento)
  VALUES
    (p_empresa_id, '30101', 'Capital Social Suscrito y Pagado', 'PATRIMONIO', 'ACREEDORA', 3, v_capital, true),
    (p_empresa_id, '30401', 'Reserva Legal', 'PATRIMONIO', 'ACREEDORA', 3, v_reservas, true),
    (p_empresa_id, '30402', 'Reservas Facultativas', 'PATRIMONIO', 'ACREEDORA', 3, v_reservas, true),
    (p_empresa_id, '30601', 'Ganancias Acumuladas de Ejercicios Anteriores', 'PATRIMONIO', 'ACREEDORA', 3, v_res_acum, true),
    (p_empresa_id, '30602', '(-) Pérdidas Acumuladas de Ejercicios Anteriores', 'PATRIMONIO', 'DEUDORA', 3, v_res_acum, true),
    (p_empresa_id, '30701', 'Ganancia Neta del Período', 'PATRIMONIO', 'ACREEDORA', 3, v_res_ej, true),
    (p_empresa_id, '30702', '(-) Pérdida Neta del Período', 'PATRIMONIO', 'DEUDORA', 3, v_res_ej, true);

  -- Ingresos
  INSERT INTO cuentas_contables (empresa_id, codigo, nombre, tipo, naturaleza, nivel, padre_id, es_movimiento)
  VALUES
    (p_empresa_id, '4101', 'Ventas de Bienes', 'INGRESO', 'ACREEDORA', 3, v_ing_ord, true),
    (p_empresa_id, '4102', 'Prestación de Servicios', 'INGRESO', 'ACREEDORA', 3, v_ing_ord, true),
    (p_empresa_id, '4105', '(-) Descuentos en Ventas', 'INGRESO', 'DEUDORA', 3, v_ing_ord, true),
    (p_empresa_id, '4106', '(-) Devoluciones en Ventas', 'INGRESO', 'DEUDORA', 3, v_ing_ord, true),
    (p_empresa_id, '4301', 'Intereses Ganados', 'INGRESO', 'ACREEDORA', 3, v_ing_otros, true),
    (p_empresa_id, '4302', 'Utilidad en Venta de Activos', 'INGRESO', 'ACREEDORA', 3, v_ing_otros, true),
    (p_empresa_id, '4399', 'Otros Ingresos No Operacionales', 'INGRESO', 'ACREEDORA', 3, v_ing_otros, true);

  -- Costos
  INSERT INTO cuentas_contables (empresa_id, codigo, nombre, tipo, naturaleza, nivel, padre_id, es_movimiento)
  VALUES
    (p_empresa_id, '5101', 'Costo de Ventas de Mercaderías', 'COSTO', 'DEUDORA', 3, v_costo_vtas, true),
    (p_empresa_id, '5102', 'Materias Primas y Materiales Utilizados', 'COSTO', 'DEUDORA', 3, v_costo_vtas, true),
    (p_empresa_id, '5103', 'Mano de Obra Directa', 'COSTO', 'DEUDORA', 3, v_costo_vtas, true),
    (p_empresa_id, '5104', 'Costos Indirectos de Fabricación', 'COSTO', 'DEUDORA', 3, v_costo_vtas, true);

  -- Gastos de Ventas
  INSERT INTO cuentas_contables (empresa_id, codigo, nombre, tipo, naturaleza, nivel, padre_id, es_movimiento)
  VALUES
    (p_empresa_id, '520101', 'Sueldos y Salarios - Ventas', 'GASTO', 'DEUDORA', 3, v_gasto_vtas, true),
    (p_empresa_id, '520102', 'Beneficios Sociales - Ventas', 'GASTO', 'DEUDORA', 3, v_gasto_vtas, true),
    (p_empresa_id, '520103', 'Depreciación de Activos - Ventas', 'GASTO', 'DEUDORA', 3, v_gasto_vtas, true),
    (p_empresa_id, '520104', 'Publicidad y Propaganda', 'GASTO', 'DEUDORA', 3, v_gasto_vtas, true),
    (p_empresa_id, '520105', 'Comisiones en Ventas', 'GASTO', 'DEUDORA', 3, v_gasto_vtas, true),
    (p_empresa_id, '520106', 'Transporte y Fletes Ventas', 'GASTO', 'DEUDORA', 3, v_gasto_vtas, true);

  -- Gastos Administrativos
  INSERT INTO cuentas_contables (empresa_id, codigo, nombre, tipo, naturaleza, nivel, padre_id, es_movimiento)
  VALUES
    (p_empresa_id, '520201', 'Sueldos y Salarios - Administrativos', 'GASTO', 'DEUDORA', 3, v_gasto_adm, true),
    (p_empresa_id, '520202', 'Beneficios Sociales - Administrativos', 'GASTO', 'DEUDORA', 3, v_gasto_adm, true),
    (p_empresa_id, '520203', 'Aporte Patronal IESS', 'GASTO', 'DEUDORA', 3, v_gasto_adm, true),
    (p_empresa_id, '520204', 'Depreciación de Activos - Administrativos', 'GASTO', 'DEUDORA', 3, v_gasto_adm, true),
    (p_empresa_id, '520205', 'Amortización de Intangibles', 'GASTO', 'DEUDORA', 3, v_gasto_adm, true),
    (p_empresa_id, '520206', 'Honorarios Profesionales', 'GASTO', 'DEUDORA', 3, v_gasto_adm, true),
    (p_empresa_id, '520207', 'Arrendamiento de Locales', 'GASTO', 'DEUDORA', 3, v_gasto_adm, true),
    (p_empresa_id, '520208', 'Servicios Básicos (Agua, Luz, Teléfono)', 'GASTO', 'DEUDORA', 3, v_gasto_adm, true),
    (p_empresa_id, '520209', 'Suministros y Materiales de Oficina', 'GASTO', 'DEUDORA', 3, v_gasto_adm, true),
    (p_empresa_id, '520210', 'Mantenimiento y Reparaciones', 'GASTO', 'DEUDORA', 3, v_gasto_adm, true),
    (p_empresa_id, '520211', 'Gastos de Viaje y Gestión', 'GASTO', 'DEUDORA', 3, v_gasto_adm, true),
    (p_empresa_id, '520212', 'IVA que se Carga al Gasto', 'GASTO', 'DEUDORA', 3, v_gasto_adm, true),
    (p_empresa_id, '520213', 'Provisión de Cuentas Incobrables', 'GASTO', 'DEUDORA', 3, v_gasto_adm, true),
    (p_empresa_id, '520214', 'Multas e Intereses Tributarios', 'GASTO', 'DEUDORA', 3, v_gasto_adm, true),
    (p_empresa_id, '520215', 'Seguros y Fianzas', 'GASTO', 'DEUDORA', 3, v_gasto_adm, true),
    (p_empresa_id, '520216', 'Otros Gastos Administrativos', 'GASTO', 'DEUDORA', 3, v_gasto_adm, true);

  -- Gastos Financieros
  INSERT INTO cuentas_contables (empresa_id, codigo, nombre, tipo, naturaleza, nivel, padre_id, es_movimiento)
  VALUES
    (p_empresa_id, '520301', 'Intereses Bancarios', 'GASTO', 'DEUDORA', 3, v_gasto_fin, true),
    (p_empresa_id, '520302', 'Comisiones Bancarias', 'GASTO', 'DEUDORA', 3, v_gasto_fin, true),
    (p_empresa_id, '520303', 'Gastos de Financiamiento y Préstamos', 'GASTO', 'DEUDORA', 3, v_gasto_fin, true);

  -- Otros Gastos
  INSERT INTO cuentas_contables (empresa_id, codigo, nombre, tipo, naturaleza, nivel, padre_id, es_movimiento)
  VALUES
    (p_empresa_id, '520401', 'Pérdida en Venta de Activos', 'GASTO', 'DEUDORA', 3, v_gasto_otros, true),
    (p_empresa_id, '520402', 'Gastos de Ejercicios Anteriores', 'GASTO', 'DEUDORA', 3, v_gasto_otros, true),
    (p_empresa_id, '520403', 'Otras Pérdidas', 'GASTO', 'DEUDORA', 3, v_gasto_otros, true);

END;
$;
```

## Integraciones

| Módulo | Evento que genera asiento | Llamada |
|--------|--------------------------|---------|
| **Facturación** | Factura/NC/ND AUTORIZADA | `module_bus.contabilidad_create_journal_entry()` |
| **Compras** | Factura proveedor, liquidación, retención | `module_bus.contabilidad_create_journal_entry()` |
| **Tesorería** | Cobro, pago, conciliación bancaria | `module_bus.contabilidad_create_journal_entry()` |
| **RRHH** | Nómina aprobada | `module_bus.contabilidad_create_journal_entry()` |
| **Activos Fijos** | Depreciación mensual | `module_bus.contabilidad_create_journal_entry()` |
| **Taller** | Orden de reparación cerrada | `module_bus.contabilidad_create_journal_entry()` |
| **Proyectos** | Hoja de tiempo aprobada | `module_bus.contabilidad_create_journal_entry()` |
| **POS** | Cierre de caja | `module_bus.contabilidad_create_journal_entry()` |
| **IA/Chat** | Lectura de asientos (anomalías, cashflow) | consulta directa con RLS |

---

## Flujos Principales

### Asientos Contables Automáticos por Módulo

```
Cada transaccion genera asientos automaticos via module_bus.contabilidad_create_journal_entry():

VENTA (Factura):
  DEBE: Cuentas por Cobrar     xxx.xx
  HABER: Ventas                       xxx.xx
  HABER: IVA Cobrado                  xxx.xx

COMPRA (Factura proveedor):
  DEBE: Inventario/Gasto       xxx.xx
  DEBE: IVA Pagado             xxx.xx
  HABER: Cuentas por Pagar           xxx.xx

RETENCION EMITIDA:
  DEBE: Cuentas por Pagar      xxx.xx
  HABER: Ret. IVA por Pagar          xxx.xx
  HABER: Ret. Renta por Pagar        xxx.xx

COBRO:
  DEBE: Banco/Caja             xxx.xx
  HABER: Cuentas por Cobrar          xxx.xx

PAGO:
  DEBE: Cuentas por Pagar      xxx.xx
  HABER: Banco/Caja                  xxx.xx
```

---

## Casos de Uso

### Actores

| Actor | Descripcion |
|-------|-------------|
| **Contador** | Configura plan de cuentas, registra asientos manuales, genera reportes, cierra períodos |
| **Gerente** | Consulta estados financieros y reportes de gestión |
| **Sistema** | Módulos que generan asientos automáticos vía MSB |

### Casos de Uso - Contabilidad

| ID | Caso de Uso | Actor | Prioridad |
|----|-------------|-------|-----------|
| CT01 | Configurar plan de cuentas (NIIF) | Contador | **Critica** |
| CT02 | Registrar asiento manual | Contador | Alta |
| CT03 | Consultar libro diario | Contador | Alta |
| CT04 | Consultar libro mayor | Contador | Alta |
| CT05 | Generar balance general | Contador | Alta |
| CT06 | Generar estado de resultados | Contador | Alta |
| CT07 | Generar reporte tributario mensual | Contador | **Critica** |
| CT08 | Cierre de periodo | Contador | Alta |
| CT09 | Conciliacion bancaria | Contador | Media |
| CT10 | Reporte de retenciones | Contador | Alta |

> **CT07/CT10 Ecuador** (ATS, declaraciones 103/104, retenciones SRI): Ver [`modules/extensiones/tributacion_ec/module.md`](../../extensiones/tributacion_ec/module.md).
