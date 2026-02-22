# Caja Chica y Fondo a Rendir (Tesorería)

*Spec derivada del módulo `l10n_ec_petty_cash` (Odoo 19.1 Ecuador — producción en csolish/tecnoh)*

---

## Descripción

Gestión de cajas chicas físicas y fondos a rendir. Permite registrar gastos pequeños sin pasar por el proceso normal de compras, con control de límites, responsables, y reposiciones periódicas.

---

## Tipos

| Tipo | Descripción | Flujo de reposición |
|---|---|---|
| `CAJA_CHICA` | Fondo fijo con límite máximo | Reposición directa al llegar al mínimo |
| `FONDO_A_RENDIR` | Empleado recibe dinero, rinde cuentas | Liquidación con respaldos (2 pasos: working → posted) |

---

## Modelo de Datos

### Tabla: `cajas_chicas`

```sql
CREATE TABLE cajas_chicas (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  nombre          TEXT NOT NULL,
  tipo            TEXT NOT NULL DEFAULT 'caja_chica'
                  CHECK (tipo IN ('caja_chica', 'fondo_rendir')),
  diario_id       UUID REFERENCES diarios_contables(id),  -- diario tipo=efectivo
  responsable_id  UUID REFERENCES contactos(id),          -- persona responsable
  limite          NUMERIC(15,2) NOT NULL CHECK (limite > 0),
  saldo           NUMERIC(15,2) DEFAULT 0,                -- calculado desde movimientos
  activa          BOOLEAN DEFAULT TRUE,
  -- Auditoría
  creado_en       TIMESTAMPTZ DEFAULT now(),
  actualizado_en  TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE cajas_chicas ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON cajas_chicas FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));
```

### Tabla: `caja_chica_usuarios`

```sql
CREATE TABLE caja_chica_usuarios (
  caja_chica_id   UUID REFERENCES cajas_chicas(id) ON DELETE CASCADE,
  usuario_id      UUID REFERENCES usuarios(id),
  PRIMARY KEY (caja_chica_id, usuario_id)
);
```

### Tabla: `caja_chica_gastos` (movimientos/egresos)

```sql
CREATE TABLE caja_chica_gastos (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  caja_chica_id   UUID NOT NULL REFERENCES cajas_chicas(id),
  fecha           DATE NOT NULL DEFAULT CURRENT_DATE,
  descripcion     TEXT NOT NULL,
  beneficiario    TEXT,
  monto           NUMERIC(15,2) NOT NULL CHECK (monto > 0),
  cuenta_gasto_id UUID REFERENCES cuentas_contables(id),
  factura_id      UUID REFERENCES facturas(id),           -- factura proveedor relacionada
  asiento_id      UUID REFERENCES asientos_contables(id),
  adjunto_id      UUID,                                   -- comprobante (foto/PDF)
  estado          TEXT DEFAULT 'borrador'
                  CHECK (estado IN ('borrador','validado','cancelado')),
  creado_por      UUID REFERENCES usuarios(id)
);
```

### Tabla: `caja_chica_reposiciones`

```sql
CREATE TABLE caja_chica_reposiciones (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id          UUID NOT NULL REFERENCES empresas(id),
  caja_chica_id       UUID NOT NULL REFERENCES cajas_chicas(id),
  nombre              TEXT NOT NULL,
  fecha               DATE NOT NULL DEFAULT CURRENT_DATE,
  tipo                TEXT NOT NULL DEFAULT 'normal'
                      CHECK (tipo IN ('normal', 'liquidacion')),
  estado              TEXT DEFAULT 'borrador'
                      CHECK (estado IN ('borrador','en_proceso','validado','cancelado')),
  monto               NUMERIC(15,2) DEFAULT 0,
  monto_liquidado     NUMERIC(15,2) DEFAULT 0,
  saldo               NUMERIC(15,2) GENERATED ALWAYS AS (monto - monto_liquidado) STORED,
  es_inicial          BOOLEAN DEFAULT FALSE,
  responsable_id      UUID REFERENCES contactos(id),
  -- Comprobantes adjuntos
  factura_ids         UUID[],   -- facturas de respaldo
  pago_ids            UUID[]    -- pagos de reposición
);
```

---

## Flujos de Negocio

### Flujo Caja Chica Normal

```
1. CONFIGURAR caja chica (nombre, límite, diario, responsable)
2. REPOSICIÓN INICIAL → pone saldo = límite
3. GASTOS → registrar egresos con comprobantes
4. cuando saldo < mínimo configurado → REPOSICIÓN
   - Adjuntar facturas de respaldo
   - Aprobar → genera asiento: DEBE Caja Chica / HABER Banco
5. Ciclo continuo
```

### Flujo Fondo a Rendir (2 pasos)

```
1. REPOSICIÓN INICIAL (es_inicial=true) → empleado recibe dinero efectivo
   - estado: borrador → en_proceso (1er approve)
2. Empleado realiza GASTOS durante período
3. LIQUIDACIÓN → empleado presenta comprobantes/facturas
   - estado: en_proceso → validado (2do approve, cierra el ciclo)
4. Si hay sobrante: el empleado devuelve la diferencia
5. Si hay faltante: se descuenta del siguiente pago
```

---

## Estados de Reposición

| Tipo | Estados válidos |
|---|---|
| Caja Chica | borrador → validado (1 paso) |
| Fondo a Rendir | borrador → en_proceso → validado (2 pasos) |

---

## Asientos Contables

### Reposición Caja Chica

```
DEBE: 1.1.1.x Caja Chica                    monto_reposicion
HABER: 1.1.2.x Banco (cuenta de la empresa) monto_reposicion
```

### Gasto desde Caja Chica

```
DEBE: 6.x.x.x Cuenta de Gasto              monto
HABER: 1.1.1.x Caja Chica                  monto
```

### Liquidación Fondo a Rendir

```
Por cada factura de respaldo:
DEBE: 6.x.x.x Cuenta de Gasto              monto_factura
HABER: 1.1.1.x Fondo a Rendir              monto_factura
```

---

## Funciones RPC

```typescript
// Crear caja chica
create_caja_chica(params: {
  nombre: string
  tipo: 'caja_chica' | 'fondo_rendir'
  diario_id: UUID
  responsable_id: UUID
  limite: number
  usuario_ids?: UUID[]
}): { caja_chica_id: UUID }

// Registrar gasto
registrar_gasto_caja(params: {
  caja_chica_id: UUID
  fecha: string
  descripcion: string
  monto: number
  cuenta_gasto_id: UUID
  factura_id?: UUID
  adjunto_id?: UUID
}): { gasto_id: UUID, saldo_actual: number }

// Crear reposición
crear_reposicion(params: {
  caja_chica_id: UUID
  nombre: string
  monto: number
  factura_ids?: UUID[]
  es_inicial?: boolean
}): { reposicion_id: UUID }

// Aprobar reposición (1 paso para caja chica, 2 para fondo)
aprobar_reposicion(reposicion_id: UUID): { estado: string, asiento_id?: UUID }

// Dashboard de cajas chicas
get_cajas_chicas_dashboard(): {
  cajas: { id: UUID, nombre: string, saldo: number, limite: number, estado_saldo: string }[]
}

// Reimbolso de caja chica
reembolsar_caja_chica(params: {
  caja_chica_id: UUID
  monto: number
  diario_id: UUID
}): { asiento_id: UUID }
```

---

## Configuración por Empresa

```json
{
  "caja_chica": {
    "monto_minimo_reposicion": 20.00,
    "cuenta_caja_chica_id": "uuid",
    "cuenta_fondo_rendir_id": "uuid",
    "requiere_aprobacion_reposicion": true,
    "max_gastos_sin_factura": 5.00
  }
}
```

---

## Validaciones de Negocio

- Saldo no puede exceder el límite configurado
- No se pueden eliminar reposiciones fuera de estado borrador
- Fondo a Rendir requiere 2 aprobaciones (en_proceso → validado)
- Gastos deben tener comprobante (configurable)
- Solo usuarios autorizados pueden registrar gastos

---

## Pantallas Flutter

### Lista de Cajas Chicas
- `CrudScaffold<CajaChica>` con saldo actual vs límite (barra de progreso)
- Indicador visual: verde (OK), amarillo (bajo), rojo (agotado)

### Detalle de Caja Chica
- Tabs: Movimientos | Reposiciones | Configuración
- `Tab Movimientos`: lista de gastos con fecha, descripción, monto, cuenta
- `Tab Reposiciones`: historial con estado y montos
- Botones: Nuevo Gasto, Nueva Reposición

### Formulario de Gasto
- fecha, descripción, monto, cuenta de gasto
- Campo para adjuntar foto del comprobante (cámara nativa)
- Selector de factura proveedor relacionada (opcional)

### Formulario de Reposición / Liquidación
- Para caja chica: simple (monto + facturas)
- Para fondo a rendir: wizard 2 pasos con líneas de facturas y diferencial

---

## Modelo de Datos Completo (Ampliado)

Las tablas siguientes complementan el modelo anterior con mayor detalle de campos, validaciones y control de flujo de aprobación en dos pasos.

### Tabla: `fondos_caja_chica`

```sql
CREATE TABLE fondos_caja_chica (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id           UUID NOT NULL REFERENCES empresas(id),
  establecimiento_id   UUID REFERENCES establecimientos(id),
  nombre               VARCHAR(100) NOT NULL,          -- "Caja Chica Quito Norte"
  tipo                 VARCHAR(10) NOT NULL CHECK (tipo IN ('FIJO','RENDIR')),
  monto_asignado       DECIMAL(14,2) NOT NULL,          -- Fondo fijo autorizado
  monto_disponible     DECIMAL(14,2) NOT NULL,
  responsable_id       UUID REFERENCES auth.users(id),
  aprobador_id         UUID REFERENCES auth.users(id),
  cuenta_contable_id   UUID,
  estado               VARCHAR(15) DEFAULT 'ACTIVA' CHECK (estado IN ('ACTIVA','SUSPENDIDA','CERRADA')),
  created_at           TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(empresa_id, nombre)
);

ALTER TABLE fondos_caja_chica ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON fondos_caja_chica FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));
```

### Tabla: `solicitudes_caja_chica`

```sql
CREATE TABLE solicitudes_caja_chica (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  fondo_id             UUID NOT NULL REFERENCES fondos_caja_chica(id),
  empresa_id           UUID NOT NULL REFERENCES empresas(id),
  solicitante_id       UUID NOT NULL REFERENCES auth.users(id),
  monto                DECIMAL(14,2) NOT NULL,
  concepto             VARCHAR(300) NOT NULL,
  categoria            VARCHAR(50),                    -- 'TRANSPORTE','ALIMENTACION','PAPELERIA','VARIOS'
  beneficiario         VARCHAR(200),
  fecha_gasto          DATE NOT NULL,
  estado               VARCHAR(20) DEFAULT 'PENDIENTE'
                       CHECK (estado IN ('PENDIENTE','APROBADA','RECHAZADA','REEMBOLSADA','LIQUIDADA')),
  aprobador_id         UUID REFERENCES auth.users(id),
  fecha_aprobacion     TIMESTAMPTZ,
  fecha_rechazo        TIMESTAMPTZ,
  motivo_rechazo       TEXT,
  -- Comprobantes de respaldo
  comprobante_tipo     VARCHAR(20),                    -- 'FACTURA_SRI','TICKET','OTRO'
  comprobante_numero   VARCHAR(49),                    -- Clave acceso si es factura SRI
  adjuntos             JSONB DEFAULT '[]',             -- URLs en Storage
  asiento_id           UUID,
  created_at           TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE solicitudes_caja_chica ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON solicitudes_caja_chica FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE INDEX idx_solicitudes_cc_fondo       ON solicitudes_caja_chica(fondo_id, estado);
CREATE INDEX idx_solicitudes_cc_solicitante ON solicitudes_caja_chica(solicitante_id);
```

### Tabla: `reposiciones_caja_chica`

```sql
CREATE TABLE reposiciones_caja_chica (
  id                        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  fondo_id                  UUID NOT NULL REFERENCES fondos_caja_chica(id),
  empresa_id                UUID NOT NULL REFERENCES empresas(id),
  monto_total               DECIMAL(14,2) NOT NULL,
  estado                    VARCHAR(20) DEFAULT 'BORRADOR'
                            CHECK (estado IN ('BORRADOR','SOLICITADA','APROBADA','EJECUTADA')),
  aprobador_id              UUID REFERENCES auth.users(id),
  fecha_aprobacion          TIMESTAMPTZ,
  asiento_id                UUID,
  cuenta_bancaria_destino   UUID REFERENCES cuentas_bancarias(id),
  created_at                TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE reposiciones_caja_chica ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON reposiciones_caja_chica FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE INDEX idx_reposiciones_cc_fondo ON reposiciones_caja_chica(fondo_id, estado);
```

---

## RPCs Ampliadas

```sql
-- Crea una nueva solicitud de gasto; verifica que el fondo tenga saldo suficiente.
-- Retorna solicitud_id o error si monto > monto_disponible.
SELECT submit_petty_cash_request(
  p_fondo_id    => 'uuid',
  p_monto       => 45.00,
  p_concepto    => 'Taxi aeropuerto cliente',
  p_categoria   => 'TRANSPORTE',
  p_fecha_gasto => CURRENT_DATE,
  p_adjuntos    => '[{"url":"https://storage.../foto.jpg","tipo":"TICKET"}]'::jsonb
);
-- Retorna: { solicitud_id: UUID }

-- Aprueba la solicitud, descuenta del monto_disponible del fondo y genera asiento contable.
SELECT approve_petty_cash_request(
  p_solicitud_id => 'uuid',
  p_aprobador_id => auth.uid()
);
-- Retorna: { estado: 'APROBADA', asiento_id: UUID, monto_disponible_restante: DECIMAL }

-- Agrupa todas las solicitudes REEMBOLSADAS del fondo en una reposición.
-- Calcula monto total y crea el registro de reposición.
-- Llama a module_bus.tesoreria para crear la transferencia bancaria de reposición.
SELECT create_reposition_request(
  p_fondo_id => 'uuid'
);
-- Retorna: { reposicion_id: UUID, monto_total: DECIMAL, solicitudes_incluidas: INT }

-- Cuadre físico del fondo: compara monto_contado vs monto_disponible.
-- Registra la diferencia (sobrante o faltante) en un asiento de ajuste.
SELECT reconcile_petty_cash(
  p_fondo_id      => 'uuid',
  p_monto_contado => 120.50
);
-- Retorna: { diferencia: DECIMAL, tipo_diferencia: 'SOBRANTE'|'FALTANTE'|'CUADRADO', asiento_id: UUID }
```

---

## Proceso de 2 Pasos por Tipo de Fondo

### FONDO FIJO (tipo = 'FIJO')

```
1. Solicitante registra gasto → estado PENDIENTE
2. Aprobador aprueba → estado APROBADA → descuenta monto_disponible
3. Solicitante presenta comprobante físico → adjunta foto → estado REEMBOLSADA
4. Al fin del período: create_reposition_request() agrupa reembolsadas
5. Contabilidad ejecuta transferencia bancaria → repone el fondo
6. monto_disponible vuelve a monto_asignado
```

### FONDO A RENDIR (tipo = 'RENDIR')

```
1. Funcionario solicita anticipo → aprobador aprueba anticipo (primer paso)
   - Se entrega efectivo al funcionario
   - monto_disponible = 0 (dinero "en manos del funcionario")
2. Funcionario realiza gastos durante el período
3. Al regresar: adjunta comprobantes → liquida (segundo paso)
   - Si gastos < anticipo: devuelve la diferencia (asiento de devolución)
   - Si gastos > anticipo: empresa reembolsa el exceso
4. Estado final → LIQUIDADA
```

---

## Asientos Contables Generados Automáticamente

### Al aprobar solicitud (gasto desde caja chica)

```
DEBE:  6.x.x.x  Cuenta de Gasto (según categoría)     monto
HABER: 1.1.1.x  Fondo Caja Chica / Fondo a Rendir     monto
```

### Al ejecutar reposición (transferencia bancaria al fondo)

```
DEBE:  1.1.1.x  Fondo Caja Chica                      monto_total
HABER: 1.1.2.x  Banco (cuenta_bancaria_destino)        monto_total
```

### Al cuadrar con diferencia (reconcile_petty_cash)

```
-- Si hay FALTANTE (contado < disponible):
DEBE:  6.x.x.x  Pérdida / Faltante de Caja            |diferencia|
HABER: 1.1.1.x  Fondo Caja Chica                       |diferencia|

-- Si hay SOBRANTE (contado > disponible):
DEBE:  1.1.1.x  Fondo Caja Chica                       |diferencia|
HABER: 4.x.x.x  Sobrante de Caja                       |diferencia|
```
