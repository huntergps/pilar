# Módulo de Suscripciones

Gestión de contratos de suscripción recurrentes para cualquier tipo de negocio: ISP/cableoperadoras (internet, TV), gimnasios, parking, seguridad privada, SaaS, mantenimiento con contrato, entre otros. Maneja planes configurables, contratos con N planes asignados, generación de deudas prorrateadas bajo demanda o automática, facturación electrónica SRI y portal de autoservicio para suscriptores.

> Si el módulo **Servicio de Campo** está activo, los contratos pueden vincularse a órdenes de trabajo (instalación, corte, reinstalación). Los cambios de estado del contrato pueden ser disparados por Servicio de Campo vía `module_bus.suscripciones.update_estado()`.

**Casos de uso por tipo de negocio:**

```
ISP / Cableoperadora:  plan INTERNET/TV_CABLE, cortes por mora, reinstalaciones
Gimnasio:              plan MENSUAL/TRIMESTRAL/ANUAL, freezes, upgrades
Parking / Bodega:      plan por espacio, facturación mensual
Seguridad privada:     plan por puesto de guardia o monitoreo remoto
SaaS / Software:       plan BASICO/PREMIUM/ENTERPRISE, upgrades/downgrades
Mantenimiento:         contrato anual con visitas incluidas (+ Servicio de Campo)
```

---

## Navegación

```
suscripciones/
  ├── suscriptores/
  │     ├── listado/          # SfDataGrid con filtros (estado, plan, mora)
  │     ├── nuevo/            # Formulario contacto + nuevo contrato
  │     └── detalle/          # Ficha 360: contratos, deudas, historial, equipos
  ├── planes/
  │     ├── listado/          # Planes activos por tipo de suscripción
  │     ├── nuevo/            # Crear plan: tarifa, duración, cobertura
  │     └── detalle/          # Ver/editar plan
  ├── contratos/
  │     ├── listado/          # SfDataGrid: estado, suscriptor, plan, mora
  │     ├── nuevo/            # Formulario contrato + planes asignados
  │     ├── detalle/          # Contrato + planes activos + historial estados
  │     ├── upgrade-downgrade/# Cambio de plan con prorrateo
  │     └── cancelar/         # Cancelación con motivo
  ├── deudas/
  │     ├── listado/          # Deudas pendientes/facturadas por período
  │     ├── generar/          # Generar deudas: período + contrato(s)
  │     └── facturar/         # Seleccionar deudas → generar factura SRI
  ├── equipos/
  │     ├── listado/          # Equipos en comodato por estado
  │     ├── nuevo/            # Registrar equipo: serial, producto, contrato
  │     └── movimientos/      # Historial: instalación, retiro, reemplazo
  ├── portal/
  │     └── config/           # URL portal, campos visibles, branding
  └── reportes/
        ├── morosidad/        # Deudas pendientes por antigüedad
        ├── ingresos-plan/    # Ingresos por plan/período
        ├── churn/            # Cancelaciones y motivos
        └── dashboard/        # Contratos activos, tasa mora, ingresos recurrentes (MRR)
```

---

## Modelo de Datos

```sql
-- ══════════════════════════════════════════════════════════════════
-- PLANES DE SUSCRIPCIÓN
-- Genérico: aplica a cualquier servicio recurrente
-- ══════════════════════════════════════════════════════════════════

CREATE TABLE planes_suscripcion (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  codigo                VARCHAR(20) NOT NULL,
  nombre                VARCHAR(150) NOT NULL,
  tipo_suscripcion      VARCHAR(50) NOT NULL,
  -- Libre, definido por la empresa. Ejemplos:
  -- 'INTERNET', 'TV_CABLE', 'TELEFONIA', 'GIMNASIO', 'PARKING',
  -- 'SEGURIDAD', 'SAAS', 'MANTENIMIENTO', 'LIMPIEZA', etc.
  descripcion           TEXT,
  tarifa_mensual        DECIMAL(14,2) NOT NULL,
  tarifa_activacion     DECIMAL(14,2) DEFAULT 0,   -- Costo de alta/instalación/matrícula
  dias_gracia_pago      INTEGER DEFAULT 15,
  dias_para_suspension  INTEGER DEFAULT 30,         -- Días mora → suspensión automática
  aplica_iva            BOOLEAN NOT NULL DEFAULT true,
  codigo_iva            VARCHAR(4) DEFAULT '4',
  tarifa_iva            DECIMAL(4,2) DEFAULT 15.00,
  producto_id           UUID REFERENCES productos(id),  -- Para línea de factura
  cuenta_ingreso_id     UUID REFERENCES cuentas_contables(id),
  activo                BOOLEAN NOT NULL DEFAULT true,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(empresa_id, codigo)
);

-- ══════════════════════════════════════════════════════════════════
-- CONTRATOS DE SUSCRIPCIÓN
-- ══════════════════════════════════════════════════════════════════

CREATE TABLE contratos_suscripcion (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  establecimiento_id    UUID NOT NULL REFERENCES establecimientos(id),
  numero_contrato       VARCHAR(20) NOT NULL,
  contacto_id           UUID NOT NULL REFERENCES contactos(id),
  -- Datos de ubicación (opcional, útil para ISP / field service)
  direccion_servicio    TEXT,
  referencia            TEXT,
  latitud               DECIMAL(10,8),
  longitud              DECIMAL(11,8),
  zona                  VARCHAR(100),              -- Zona/sector libre (p.e. "Norte", "Zona 3")
  -- Fechas
  fecha_contrato        DATE NOT NULL,
  fecha_inicio          DATE NOT NULL,
  fecha_fin             DATE,                      -- NULL = indefinido
  -- Estado
  estado                VARCHAR(25) NOT NULL DEFAULT 'ACTIVO',
  -- PENDIENTE_ACTIVACION: contrato firmado, pendiente activación
  -- ACTIVO:              suscripción funcionando
  -- SUSPENDIDO:          suspendido por solicitud del suscriptor
  -- MORA:                en mora, aún activo pero con aviso
  -- CORTADO:             servicio cortado por falta de pago
  -- CANCELADO:           contrato terminado definitivamente
  motivo_estado         TEXT,
  fecha_estado          DATE,                      -- Fecha del último cambio de estado
  -- Facturación
  dia_facturacion       INTEGER DEFAULT 1,         -- Día del mes para generar deuda (1-28)
  modo_facturacion      VARCHAR(10) DEFAULT 'MANUAL',
  -- MANUAL: operador ejecuta generate_subscription_debts() cuando decide
  -- AUTO:   cron genera deudas automáticamente en dia_facturacion de cada contrato
  ultimo_periodo_facturado VARCHAR(7),             -- 'YYYY-MM'
  -- Portal de autoservicio
  token_portal          UUID NOT NULL DEFAULT gen_random_uuid() UNIQUE,
  -- Observaciones
  observaciones         TEXT,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by            UUID REFERENCES auth.users(id),
  UNIQUE(empresa_id, numero_contrato)
);

-- ══════════════════════════════════════════════════════════════════
-- PLANES POR CONTRATO (N planes por contrato)
-- ══════════════════════════════════════════════════════════════════

CREATE TABLE contrato_planes (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  contrato_id           UUID NOT NULL REFERENCES contratos_suscripcion(id),
  plan_id               UUID NOT NULL REFERENCES planes_suscripcion(id),
  tarifa_mensual        DECIMAL(14,2) NOT NULL,   -- Tarifa real (puede diferir del plan por descuento)
  fecha_inicio          DATE NOT NULL,
  fecha_fin             DATE,                     -- NULL = vigente
  activo                BOOLEAN NOT NULL DEFAULT true,
  observaciones         TEXT,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ══════════════════════════════════════════════════════════════════
-- DEUDAS DE SUSCRIPCIÓN
-- Generadas bajo demanda (manual o auto según modo_facturacion)
-- ══════════════════════════════════════════════════════════════════

CREATE TABLE deudas_suscripcion (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  contrato_id           UUID NOT NULL REFERENCES contratos_suscripcion(id),
  contrato_plan_id      UUID NOT NULL REFERENCES contrato_planes(id),
  periodo               VARCHAR(7) NOT NULL,       -- 'YYYY-MM'
  fecha_desde           DATE NOT NULL,
  fecha_hasta           DATE NOT NULL,
  dias_totales          INTEGER NOT NULL,
  dias_uso              INTEGER NOT NULL,          -- Para prorrateo
  tarifa_mensual        DECIMAL(14,2) NOT NULL,
  subtotal              DECIMAL(14,2) NOT NULL,    -- tarifa * dias_uso / dias_totales
  iva                   DECIMAL(14,2) NOT NULL DEFAULT 0,
  total                 DECIMAL(14,2) NOT NULL,
  estado                VARCHAR(20) NOT NULL DEFAULT 'PENDIENTE',
  -- PENDIENTE / FACTURADA / PAGADA / ANULADA
  factura_id            UUID REFERENCES facturas(id),
  generado_por          UUID REFERENCES auth.users(id),
  fecha_generacion      TIMESTAMPTZ NOT NULL DEFAULT now(),
  observaciones         TEXT,
  UNIQUE(empresa_id, contrato_id, contrato_plan_id, periodo)
);

-- ══════════════════════════════════════════════════════════════════
-- HISTORIAL DE ESTADOS DEL CONTRATO
-- ══════════════════════════════════════════════════════════════════

CREATE TABLE historial_suscripcion (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  contrato_id           UUID NOT NULL REFERENCES contratos_suscripcion(id),
  estado_anterior       VARCHAR(25),
  estado_nuevo          VARCHAR(25) NOT NULL,
  motivo                TEXT,
  usuario_id            UUID REFERENCES auth.users(id),
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ══════════════════════════════════════════════════════════════════
-- EQUIPOS EN COMODATO (entregados al suscriptor)
-- Genérico: router, decoder, máquina gym, extintor, sensor, etc.
-- ══════════════════════════════════════════════════════════════════

CREATE TABLE equipos_cliente (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  producto_id           UUID NOT NULL REFERENCES productos(id),
  activo_fijo_id        UUID REFERENCES activos_fijos(id),  -- Si tiene depreciación controlada
  serial                VARCHAR(100) NOT NULL,
  contrato_id           UUID REFERENCES contratos_suscripcion(id),
  estado                VARCHAR(20) NOT NULL DEFAULT 'EN_BODEGA',
  -- EN_BODEGA / INSTALADO / DEVUELTO / EXTRAVIADO / DANADO / EN_REPARACION
  fecha_instalacion     DATE,
  fecha_retiro          DATE,
  notas                 TEXT,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(empresa_id, serial)
);

CREATE TABLE equipo_historial (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  equipo_id             UUID NOT NULL REFERENCES equipos_cliente(id),
  accion                VARCHAR(20) NOT NULL,
  -- INSTALACION / RETIRO / REEMPLAZO / ENVIADO_A_TALLER / DEVUELTO_DE_TALLER
  contrato_id           UUID REFERENCES contratos_suscripcion(id),
  fecha                 TIMESTAMPTZ NOT NULL DEFAULT now(),
  tecnico_id            UUID REFERENCES auth.users(id),
  orden_campo_id        UUID,    -- FK a ordenes_campo (Servicio de Campo, si está activo)
  notas                 TEXT
);

-- ══════════════════════════════════════════════════════════════════
-- INCIDENCIAS DEL SUSCRIPTOR (portal de autoservicio)
-- ══════════════════════════════════════════════════════════════════

CREATE TABLE incidencias_suscriptor (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  contrato_id           UUID NOT NULL REFERENCES contratos_suscripcion(id),
  tipo                  VARCHAR(30) NOT NULL,
  -- FALLA_SERVICIO / CONSULTA / RECLAMO / SOLICITUD_SUSPENSION / SOLICITUD_CANCELACION
  descripcion           TEXT NOT NULL,
  estado                VARCHAR(20) NOT NULL DEFAULT 'REPORTADA',
  -- REPORTADA / EN_PROCESO / RESUELTA / CERRADA
  orden_campo_id        UUID,    -- FK a ordenes_campo (Servicio de Campo, si se crea OT)
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  resolved_at           TIMESTAMPTZ
);

-- ══════════════════════════════════════════════════════════════════
-- ÍNDICES
-- ══════════════════════════════════════════════════════════════════

CREATE INDEX idx_planes_tipo ON planes_suscripcion(empresa_id, tipo_suscripcion);
CREATE INDEX idx_contratos_estado ON contratos_suscripcion(empresa_id, estado);
CREATE INDEX idx_contratos_contacto ON contratos_suscripcion(contacto_id);
CREATE INDEX idx_contratos_token ON contratos_suscripcion(token_portal);
CREATE INDEX idx_contrato_planes_contrato ON contrato_planes(contrato_id, activo);
CREATE INDEX idx_deudas_periodo ON deudas_suscripcion(empresa_id, periodo, estado);
CREATE INDEX idx_deudas_contrato ON deudas_suscripcion(contrato_id, estado);
CREATE INDEX idx_equipos_cliente_contrato ON equipos_cliente(contrato_id, estado);
CREATE INDEX idx_equipos_cliente_serial ON equipos_cliente(empresa_id, serial);
CREATE INDEX idx_incidencias_contrato ON incidencias_suscriptor(contrato_id, estado);

-- ══════════════════════════════════════════════════════════════════
-- RLS
-- ══════════════════════════════════════════════════════════════════

ALTER TABLE planes_suscripcion ENABLE ROW LEVEL SECURITY;
ALTER TABLE contratos_suscripcion ENABLE ROW LEVEL SECURITY;
ALTER TABLE contrato_planes ENABLE ROW LEVEL SECURITY;
ALTER TABLE deudas_suscripcion ENABLE ROW LEVEL SECURITY;
ALTER TABLE historial_suscripcion ENABLE ROW LEVEL SECURITY;
ALTER TABLE equipos_cliente ENABLE ROW LEVEL SECURITY;
ALTER TABLE equipo_historial ENABLE ROW LEVEL SECURITY;
ALTER TABLE incidencias_suscriptor ENABLE ROW LEVEL SECURITY;

CREATE POLICY "tenant_isolation" ON planes_suscripcion
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE POLICY "tenant_isolation" ON contratos_suscripcion
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE POLICY "tenant_isolation" ON contrato_planes
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE POLICY "tenant_isolation" ON deudas_suscripcion
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE POLICY "tenant_isolation" ON historial_suscripcion
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE POLICY "tenant_isolation" ON equipos_cliente
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- equipo_historial: acceso por empresa a través del equipo padre
CREATE POLICY "tenant_isolation" ON equipo_historial
  FOR ALL TO authenticated
  USING (
    equipo_id IN (
      SELECT id FROM equipos_cliente
      WHERE empresa_id = (SELECT private.get_empresa_id())
    )
  );

CREATE POLICY "tenant_isolation" ON incidencias_suscriptor
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));
```

---

## RPCs Principales

```sql
-- generate_subscription_debts(empresa_id, periodo, contrato_id DEFAULT NULL)
--   Genera deudas prorrateadas para el período. Idempotente (no duplica si ya existe).
--   Recorre contrato_planes activos de contratos ACTIVO/MORA/CORTADO.
--   Calcula: tarifa * dias_uso / dias_periodo. Respeta fecha_inicio del plan.
--   Parámetro contrato_id NULL = procesa todos los contratos elegibles de la empresa.

-- invoice_subscription_debts(empresa_id, contrato_id, periodos[] DEFAULT NULL)
--   Factura deudas en estado PENDIENTE de un contrato.
--   Crea una factura electrónica SRI agrupando todas las deudas seleccionadas.
--   Cada deuda genera una línea en la factura con descripción del período y días de uso.
--   Actualiza estado de deudas a FACTURADA y registra factura_id.
--   La factura pasa al flujo estándar de emisión electrónica SRI.

-- generate_debts_cron(empresa_id, fecha DEFAULT CURRENT_DATE)
--   Ejecutada por Edge Function diaria (cron 0 2 * * *).
--   Solo actúa en contratos con modo_facturacion='AUTO'
--   y dia_facturacion = EXTRACT(DAY FROM fecha).
--   Llama a generate_subscription_debts() por cada contrato elegible.
--   Retorna: {contratos_procesados, deudas_generadas, monto_total}

-- change_subscription_plan(contrato_id, plan_id_nuevo, fecha_efectiva DEFAULT CURRENT_DATE)
--   Cierra el contrato_planes vigente (fecha_fin = fecha_efectiva - 1).
--   Crea nuevo registro en contrato_planes con el nuevo plan.
--   UPGRADE: genera deuda adicional (diferencia de tarifa prorrateada por días restantes).
--   DOWNGRADE: genera NC vía module_bus.ventas.emitir_nc() si hay exceso cobrado.
--   Registra el cambio en historial_suscripcion.

-- update_contract_state(contrato_id, nuevo_estado, motivo)
--   Actualiza contratos_suscripcion.estado + fecha_estado.
--   Inserta registro en historial_suscripcion.
--   Callable externamente por module_bus desde Servicio de Campo.
```

---

## Portal del Suscriptor

Edge Functions públicas (`verify_jwt=false`), autenticadas por `token_portal` (UUID único por contrato).

```
subscriber-portal/index.ts
  GET  /facturas?token=X         → facturas del contrato (listado + estado SRI)
  GET  /estado-cuenta?token=X   → deudas pendientes con montos y períodos
  GET  /ride/:id?token=X        → descarga RIDE PDF desde Supabase Storage
  POST /incidencia?token=X      → reportar falla/consulta/reclamo
  POST /pagar?token=X           → redirige a Kushki/PayPhone para pago online

  Auth:  contratos_suscripcion.token_portal (UUID único, regenerable)
  URL:   https://pilar.app/portal/{token}
  Nota:  Si Servicio de Campo está activo, POST /incidencia puede
         disparar creación de orden de campo vía module_bus.
```

---

## Module Service Bus

Funciones expuestas por este módulo para uso de otros módulos:

```sql
-- module_bus.suscripciones.update_contract_state(contrato_id, estado, motivo)
--   Usado por: Servicio de Campo (al completar corte/reinstalación)
--   Permite que una orden de campo cambie el estado del contrato sin acceso directo.

-- module_bus.suscripciones.get_contract_info(contrato_id)
--   Usado por: Servicio de Campo (muestra datos del suscriptor en la orden de trabajo)
--   Retorna: número contrato, suscriptor, dirección, planes activos, deuda pendiente.

-- module_bus.suscripciones.get_pending_debts(empresa_id)
--   Usado por: Dashboard (KPI de morosidad en tiempo real)
--   Retorna: total contratos en mora, monto total pendiente, distribución por antigüedad.
```

---

## Reglas de Negocio

```
Prorrateo:
  - valor = tarifa_mensual * dias_uso / dias_periodo
  - Se aplica al inicio del servicio (alta a mitad de mes) y al cierre (baja o corte)
  - IVA se calcula sobre el subtotal prorrateado, no sobre la tarifa completa
  - El redondeo se aplica solo al resultado final (DECIMAL(14,2))

Billing modes:
  - MANUAL (default): el operador ejecuta generate_subscription_debts() cuando decide
  - AUTO: Edge Function diaria genera deudas en dia_facturacion de cada contrato
  - En ambos modos, la FACTURACIÓN siempre es manual: el operador selecciona
    las deudas pendientes y decide cuándo emitir la factura electrónica SRI

Estados de contrato:
  - Sin Servicio de Campo:
      PENDIENTE_ACTIVACION → ACTIVO → MORA → CORTADO → CANCELADO
  - Con Servicio de Campo:
      Los estados CORTADO y ACTIVO pueden ser disparados automáticamente
      por órdenes de campo completadas (via module_bus)

Múltiples planes por contrato:
  - Un contrato puede tener N planes simultáneos (ej: INTERNET + TV_CABLE)
  - Cada plan en contrato_planes tiene su propia tarifa (puede diferir del plan base)
  - Cada plan genera su propia deuda independiente por período

Equipos en comodato:
  - Si el equipo se daña → estado EN_REPARACION
    + module_bus.taller.crear_orden() si el módulo Taller está activo
  - Si Taller no está activo → estado DANADO (resolución manual)
  - Equipos con activo_fijo_id → depreciación calculada en módulo Activos Fijos

Upgrade/Downgrade:
  - UPGRADE: se genera deuda adicional por la diferencia de tarifa prorrateada
  - DOWNGRADE: se genera nota de crédito via module_bus.ventas.emitir_nc()
  - El historial_suscripcion registra todos los cambios de estado y plan

Generación de deuda en contratos CORTADO:
  - Los contratos en estado CORTADO siguen generando deuda mensual
  - La deuda acumulada no desaparece al cortar: el suscriptor sigue debiendo
  - Al pagar y reinstalar (vía Servicio de Campo), el estado vuelve a ACTIVO
```

---

## Integraciones

```
Suscripciones → Ventas (Facturación):
  - Deudas facturadas generan facturas electrónicas via flujo SRI estándar
  - Notas de crédito por downgrade via module_bus.ventas.emitir_nc()

Suscripciones → Contabilidad:
  - Facturación de deudas genera asiento contra cuenta_ingreso_id del plan
  - IVA registrado en cuenta de IVA cobrado configurada en el plan

Suscripciones → Tesorería:
  - Pagos online desde portal redirigen a Kushki/PayPhone
  - Pago exitoso actualiza estado de deuda a PAGADA y puede
    disparar reinstalación vía Servicio de Campo (si activo)

Suscripciones → Notificaciones:
  - Al generar deuda: notificación al suscriptor (email/WhatsApp/Telegram)
  - Al suspender/cortar: notificación al suscriptor con motivo y monto
  - Al activar/reinstalar: confirmación al suscriptor

Suscripciones → Activos Fijos:
  - Equipos con activo_fijo_id participan del ciclo de depreciación
  - El módulo Activos Fijos puede consultar ubicación actual del equipo

Suscripciones → Servicio de Campo (si activo):
  - Cambios de estado del contrato pueden disparar órdenes de campo
  - Órdenes completadas actualizan el estado del contrato vía module_bus
  - Incidencias reportadas por el portal pueden generar órdenes de campo
```

---

## Reportes

| Reporte | Descripción |
|---------|-------------|
| Morosidad | Deudas PENDIENTE por antigüedad (0-30, 31-60, 61-90, +90 días) |
| Ingresos por plan | Subtotales facturados agrupados por tipo_suscripcion y plan, por período |
| Churn | Contratos cancelados: período, motivo, plan, valor mensual perdido |
| Dashboard MRR | Contratos activos, tasa de mora, ingresos recurrentes mensuales (MRR) |
| Estado de cuenta | Por suscriptor: deudas pendientes, historial de pagos, próximos vencimientos |

---

> Sub-módulos / integraciones opcionales:
> - [Servicio de Campo](../servicio-de-campo/servicio-de-campo.md) — Órdenes de trabajo, técnicos, zonas, SLA
> - [Taller](../taller/taller.md) — Reparación física de equipos en comodato dañados
> - [Activos Fijos](../activos-fijos/activos-fijos.md) — Depreciación de equipos en comodato
