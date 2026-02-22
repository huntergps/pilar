# Módulo de Servicio de Campo

Gestión de órdenes de trabajo para técnicos en campo. Activable sobre cualquier empresa que requiera despacho presencial de personal técnico: ISP (instalaciones/cortes por mora), climatización HVAC, ascensores, seguridad privada, mantenimiento industrial, entre otros. Funciona standalone o vinculado a Suscripciones para contratos recurrentes. Incluye zonificación geográfica, SLA, reporte diario automático y seguimiento GPS del técnico al completar cada orden.

## Nota de Integración

Este módulo es Auxiliar. No requiere ningún otro módulo para funcionar, pero amplía su funcionalidad cuando otros módulos están activos:

- **Suscripciones** (opcional): Las órdenes tipo CORTE, REINSTALACION e INSTALACION actualizan el estado del contrato via `module_bus.suscripciones.update_contract_state()`. Si Suscripciones no está activo, los cambios de estado son informativos, sin efecto en contratos.
- **Taller**: Si en campo se detecta que un equipo requiere reparación física en banco, se escala via `module_bus.taller.crear_orden()`. El equipo queda en estado EN_REPARACION hasta que Taller lo devuelva.
- **Activos Fijos**: Los equipos en instalaciones de clientes pueden estar vinculados a activos fijos para tracking de mantenimiento preventivo y depreciación.
- **Inventario**: Los materiales usados en cada orden descuentan stock automáticamente al completar la orden.
- **Ventas**: Las órdenes marcadas como facturables generan factura electrónica SRI (tarifa + materiales facturables) via `module_bus.ventas.crear_factura_campo()`.

## Casos de Uso

```
ISP / Cableoperadora:
  INSTALACION       Puesta en marcha inicial de servicio de internet/cable
  CORTE             Suspensión por mora (genera orden automática desde Suscripciones)
  REINSTALACION     Reconexión al cliente que regularizó su deuda
  RETIRO            Retiro definitivo de equipos al cerrar contrato

HVAC (Climatización):
  PREVENTIVO        Mantenimiento programado periódico (limpieza filtros, carga gas)
  CORRECTIVO        Falla reportada por cliente, atención en campo
  REVISION          Inspección anual, verificación normativa, garantía

Ascensores:
  PREVENTIVO        Mantenimiento mensual obligatorio por normativa
  CORRECTIVO        Falla mecánica, atención urgente
  REVISION          Inspección técnica por entidad reguladora

Seguridad Privada:
  RONDA             Visita de verificación programada
  EMERGENCIA        Atención fuera de horario, alarma activada
  INSTALACION       Instalación de sensor, cámara, panel de alarma

Genérico:
  Cualquier visita técnica a cliente con registro de materiales,
  resultado, foto antes/después y firma digital del cliente
```

## Navegación

```
servicio-de-campo/
  ordenes/
    listado/         SfDataGrid: estado, tipo, técnico, fecha programada, zona, cliente
    nueva/           Crear orden: tipo + contrato/cliente + técnico + fecha + prioridad
    detalle/         Ver orden: materiales usados, resultado, GPS, fotos, firma cliente
    asignar/         Asignación masiva de órdenes pendientes a técnicos
  agenda/
    tecnico/         Vista calendario por técnico: órdenes del día organizadas por hora
  zonas/
    listado/         Zonas geográficas con técnicos asignados y carga actual del día
    nueva/           Definir zona: nombre + polígono GeoJSON + técnicos responsables
    mapa/            Mapa interactivo con zonas coloreadas y órdenes del día en tiempo real
  sla/
    definiciones/    SLA por tipo de servicio: tiempo máximo de respuesta y resolución
    mediciones/      Cumplimiento SLA por período, contrato y técnico
  reportes/
    diario/          Órdenes del día por técnico (generado y enviado automáticamente 06:00 AM)
    productividad/   Órdenes completadas, tiempo promedio, técnico con más incidencias
    cumplimiento-sla/ SLA: programadas vs ejecutadas vs incumplidas por período
    materiales/      Consumo de materiales por período, tipo de orden y técnico
  config/
    tipos-orden/     Tipos de orden habilitados para esta empresa (CORTE, PREVENTIVO, etc.)
    notificaciones/  Configuración de notificaciones a técnicos y clientes
```

## Modelo de Datos

```sql
-- ══════════════════════════════════════════════════════════════════
-- ZONAS DE SERVICIO
-- Polígonos geográficos con técnicos asignados
-- Se crea antes que ordenes_campo por FK
-- ══════════════════════════════════════════════════════════════════

CREATE TABLE zonas_campo (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  nombre                VARCHAR(100) NOT NULL,
  descripcion           TEXT,
  poligono_geojson      JSONB,
  -- GeoJSON Polygon {"type":"Polygon","coordinates":[[[lon,lat],...]]}.
  -- Usado con ST_Contains() para auto-asignar zona a coordenadas de la orden.
  tecnicos_asignados    JSONB NOT NULL DEFAULT '[]',
  -- Array de auth.users.id: [uuid, uuid, ...]
  activo                BOOLEAN NOT NULL DEFAULT true,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(empresa_id, nombre)
);

-- ══════════════════════════════════════════════════════════════════
-- SLA DE CAMPO
-- Acuerdos de nivel de servicio por tipo de orden
-- ══════════════════════════════════════════════════════════════════

CREATE TABLE sla_campo (
  id                        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id                UUID NOT NULL REFERENCES empresas(id),
  nombre                    VARCHAR(100) NOT NULL,
  tipo_orden                VARCHAR(20),
  -- NULL = aplica a todos los tipos; o un tipo específico: CORTE, PREVENTIVO, etc.
  tiempo_respuesta_horas    INTEGER NOT NULL,
  -- Máx horas desde creación hasta asignación de técnico
  tiempo_resolucion_horas   INTEGER NOT NULL,
  -- Máx horas desde creación hasta COMPLETADA
  activo                    BOOLEAN NOT NULL DEFAULT true,
  created_at                TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ══════════════════════════════════════════════════════════════════
-- ÓRDENES DE CAMPO
-- Unidad de trabajo: una visita de un técnico a la ubicación del cliente
-- ══════════════════════════════════════════════════════════════════

CREATE TABLE ordenes_campo (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  establecimiento_id    UUID NOT NULL REFERENCES establecimientos(id),
  numero_orden          VARCHAR(20) NOT NULL,

  tipo                  VARCHAR(20) NOT NULL,
  -- INSTALACION    Puesta en marcha inicial; activa contrato si Suscripciones activo
  -- REINSTALACION  Reconexión tras corte por mora; reactiva contrato
  -- CORTE          Suspensión de servicio por mora; corta contrato
  -- MANTENIMIENTO  Correctivo: falla reportada, solución en campo
  -- PREVENTIVO     Mantenimiento programado periódico
  -- REVISION       Inspección / auditoría (normativa, garantía, etc.)
  -- RETIRO         Retiro definitivo de equipos al cerrar contrato
  -- EMERGENCIA     Atención urgente fuera de horario habitual
  -- RONDA          Visita de verificación programada (seguridad privada)

  -- Vinculación a contrato (opcional, requiere módulo Suscripciones activo)
  contrato_id           UUID,
  -- FK lógica a contratos_suscripcion; sin FK física para funcionar standalone

  -- Cliente directo (cuando no hay contrato vinculado)
  contacto_id           UUID REFERENCES contactos(id),

  -- Ubicación de la visita
  direccion             TEXT NOT NULL,
  latitud               DECIMAL(10,8),
  longitud              DECIMAL(11,8),
  zona_id               UUID REFERENCES zonas_campo(id),

  -- Asignación
  tecnico_id            UUID REFERENCES auth.users(id),
  fecha_programada      DATE NOT NULL,
  hora_programada       TIME,
  prioridad             VARCHAR(10) NOT NULL DEFAULT 'NORMAL',
  -- URGENTE / ALTA / NORMAL / BAJA

  -- Ejecución real
  fecha_ejecucion       TIMESTAMPTZ,
  duracion_minutos      INTEGER,
  lat_ejecucion         DECIMAL(10,8),
  -- GPS del técnico al marcar COMPLETADA: verificación de presencia en sitio
  lon_ejecucion         DECIMAL(11,8),

  -- Estado del ciclo de vida
  estado                VARCHAR(20) NOT NULL DEFAULT 'PENDIENTE',
  -- PENDIENTE     Creada, sin técnico asignado
  -- ASIGNADA      Técnico asignado, aún no en ruta
  -- EN_RUTA       Técnico confirmó que va en camino
  -- EN_EJECUCION  Técnico marcó inicio de trabajo en sitio
  -- COMPLETADA    Trabajo terminado, materiales registrados
  -- CANCELADA     Cancelada antes de ejecutar (con motivo)
  -- NO_EJECUTADA  Técnico llegó pero no pudo realizar el trabajo

  motivo_no_ejecucion   TEXT,
  -- Razón cuando estado = CANCELADA o NO_EJECUTADA

  -- Contenido de la orden
  descripcion           TEXT,
  -- Trabajo a realizar: instrucciones para el técnico
  resultado             TEXT,
  -- Resultado / observaciones del técnico al completar

  -- Evidencia fotográfica (URLs en Supabase Storage)
  foto_antes            TEXT,
  foto_despues          TEXT,
  firma_cliente         TEXT,
  -- URL de firma digital capturada en tablet del técnico.
  -- OBLIGATORIA para tipos: INSTALACION, REINSTALACION, RETIRO

  -- Facturación
  es_facturable         BOOLEAN NOT NULL DEFAULT false,
  -- true: genera factura electrónica al completar (via module_bus.ventas)
  factura_id            UUID REFERENCES facturas(id),

  -- SLA
  sla_id                UUID REFERENCES sla_campo(id),
  sla_cumplido          BOOLEAN,
  -- Calculado automáticamente al marcar COMPLETADA

  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by            UUID REFERENCES auth.users(id),

  UNIQUE(empresa_id, numero_orden)
);

-- ══════════════════════════════════════════════════════════════════
-- MATERIALES USADOS EN ORDEN DE CAMPO
-- Descuenta stock al completar la orden
-- ══════════════════════════════════════════════════════════════════

CREATE TABLE materiales_orden_campo (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  orden_id              UUID NOT NULL REFERENCES ordenes_campo(id) ON DELETE CASCADE,
  producto_id           UUID NOT NULL REFERENCES productos(id),
  presentacion_id       UUID REFERENCES producto_presentaciones(id),

  cantidad              DECIMAL(18,6) NOT NULL,
  -- En unidad de la presentación seleccionada
  cantidad_base         DECIMAL(18,6) NOT NULL,
  -- En unidad base del producto (para movimiento de inventario)
  costo_unitario        DECIMAL(18,6) NOT NULL,
  -- Costo promedio al momento de usar el material
  precio_cobro          DECIMAL(14,2) NOT NULL DEFAULT 0,
  -- Precio a facturar al cliente (0 si es_facturable = false)

  es_facturable         BOOLEAN NOT NULL DEFAULT true,
  -- true: incluido como línea en la factura
  -- false: descuenta inventario pero no se factura (costo interno)

  bodega_id             UUID REFERENCES bodegas(id),
  -- Bodega desde donde sale el material (bodega del técnico o principal)
  kardex_id             UUID REFERENCES kardex(id),
  -- Referencia al movimiento de inventario generado

  created_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ══════════════════════════════════════════════════════════════════
-- MEDICIONES SLA
-- Registro de cumplimiento por orden
-- ══════════════════════════════════════════════════════════════════

CREATE TABLE sla_mediciones (
  id                        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id                UUID NOT NULL REFERENCES empresas(id),
  sla_id                    UUID NOT NULL REFERENCES sla_campo(id),
  orden_id                  UUID NOT NULL REFERENCES ordenes_campo(id),

  tiempo_respuesta_real     DECIMAL(8,2),
  -- Horas desde creación de la orden hasta asignación de técnico
  tiempo_resolucion_real    DECIMAL(8,2),
  -- Horas desde creación hasta COMPLETADA

  cumple_respuesta          BOOLEAN,
  cumple_resolucion         BOOLEAN,

  created_at                TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ══════════════════════════════════════════════════════════════════
-- REPORTE DIARIO DE ÓRDENES
-- Generado automáticamente a las 06:00 AM y enviado a técnicos
-- ══════════════════════════════════════════════════════════════════

CREATE TABLE reportes_diarios_campo (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  fecha_reporte         DATE NOT NULL,

  tipo_orden            VARCHAR(20),
  -- NULL = todas las órdenes del día; o filtrado por tipo: 'CORTE', 'PREVENTIVO', etc.

  total_ordenes         INTEGER NOT NULL DEFAULT 0,
  completadas           INTEGER NOT NULL DEFAULT 0,
  pendientes            INTEGER NOT NULL DEFAULT 0,
  no_ejecutadas         INTEGER NOT NULL DEFAULT 0,

  tecnicos              JSONB NOT NULL DEFAULT '[]',
  -- [{tecnico_id, nombre, asignadas, completadas, ordenes:[{orden_id, cliente,
  --   direccion, tipo, lat, lon, monto_deuda}]}]

  generado_por          UUID REFERENCES auth.users(id),
  -- NULL si fue generado automáticamente por el cron

  enviado               BOOLEAN NOT NULL DEFAULT false,
  fecha_envio           TIMESTAMPTZ,
  canales_envio         JSONB DEFAULT '[]',
  -- Canales usados: ['push', 'whatsapp', 'email', 'telegram']

  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),

  UNIQUE(empresa_id, fecha_reporte, tipo_orden)
);

-- ══════════════════════════════════════════════════════════════════
-- ÍNDICES
-- ══════════════════════════════════════════════════════════════════

CREATE INDEX idx_ordenes_campo_estado
  ON ordenes_campo(empresa_id, estado, fecha_programada);

CREATE INDEX idx_ordenes_campo_tecnico
  ON ordenes_campo(tecnico_id, fecha_programada);

CREATE INDEX idx_ordenes_campo_contrato
  ON ordenes_campo(contrato_id)
  WHERE contrato_id IS NOT NULL;

CREATE INDEX idx_ordenes_campo_tipo
  ON ordenes_campo(empresa_id, tipo, fecha_programada);

CREATE INDEX idx_ordenes_campo_zona
  ON ordenes_campo(zona_id, fecha_programada);

CREATE INDEX idx_materiales_orden_campo
  ON materiales_orden_campo(orden_id);

CREATE INDEX idx_materiales_orden_campo_producto
  ON materiales_orden_campo(empresa_id, producto_id);

CREATE INDEX idx_sla_mediciones_orden
  ON sla_mediciones(orden_id);

CREATE INDEX idx_reportes_diarios_fecha
  ON reportes_diarios_campo(empresa_id, fecha_reporte);

-- ══════════════════════════════════════════════════════════════════
-- RLS
-- ══════════════════════════════════════════════════════════════════

ALTER TABLE zonas_campo             ENABLE ROW LEVEL SECURITY;
ALTER TABLE sla_campo               ENABLE ROW LEVEL SECURITY;
ALTER TABLE ordenes_campo           ENABLE ROW LEVEL SECURITY;
ALTER TABLE materiales_orden_campo  ENABLE ROW LEVEL SECURITY;
ALTER TABLE sla_mediciones          ENABLE ROW LEVEL SECURITY;
ALTER TABLE reportes_diarios_campo  ENABLE ROW LEVEL SECURITY;

-- Política estándar multi-tenant (aplicar a todas las tablas):
-- CREATE POLICY "tenant_isolation" ON <tabla>
--   FOR ALL TO authenticated
--   USING (empresa_id = (SELECT private.get_empresa_id()))
--   WITH CHECK (empresa_id = (SELECT private.get_empresa_id()));
```

## RPCs Principales

```sql
-- create_field_order(
--   p_empresa_id         UUID,
--   p_tipo               VARCHAR,
--   p_contacto_id        UUID,
--   p_direccion          TEXT,
--   p_latitud            DECIMAL,
--   p_longitud           DECIMAL,
--   p_fecha_programada   DATE,
--   p_tecnico_id         UUID    DEFAULT NULL,
--   p_contrato_id        UUID    DEFAULT NULL,
--   p_prioridad          VARCHAR DEFAULT 'NORMAL',
--   p_descripcion        TEXT    DEFAULT NULL,
--   p_sla_id             UUID    DEFAULT NULL
-- ) RETURNS UUID
--
-- Crea la orden de campo.
-- Si p_zona_id es NULL y hay coordenadas, ejecuta ST_Contains() para auto-asignar zona.
-- Si p_contrato_id presente, verifica módulo Suscripciones activo via module_bus
--   antes de vincular. Si no está activo, la orden se crea sin contrato_id.
-- Genera numero_orden secuencial por empresa.
-- Retorna el id de la orden creada.


-- complete_field_order(
--   p_orden_id        UUID,
--   p_resultado       TEXT,
--   p_materiales      JSONB,
--   -- [{producto_id, presentacion_id, cantidad, precio_cobro, es_facturable, bodega_id}]
--   p_lat             DECIMAL,
--   p_lon             DECIMAL,
--   p_foto_antes      TEXT    DEFAULT NULL,
--   p_foto_despues    TEXT    DEFAULT NULL,
--   p_firma_cliente   TEXT    DEFAULT NULL
-- ) RETURNS VOID
--
-- Marca la orden como COMPLETADA.
-- Registra GPS del técnico en lat_ejecucion / lon_ejecucion.
-- Descuenta materiales del inventario via movimientos_inventario.
-- Calcula sla_cumplido comparando duracion_minutos con sla_campo.tiempo_resolucion_horas.
-- Inserta registro en sla_mediciones.
-- Acciones adicionales según tipo:
--   CORTE:         module_bus.suscripciones.update_contract_state(contrato_id, 'CORTADO')
--   REINSTALACION: module_bus.suscripciones.update_contract_state(contrato_id, 'ACTIVO')
--   INSTALACION:   module_bus.suscripciones.update_contract_state(contrato_id, 'ACTIVO')
-- Si es_facturable = true:
--   module_bus.ventas.crear_factura_campo(orden_id)
-- Retorna VOID; lanza EXCEPTION si falta firma en tipos que la requieren.


-- generate_daily_report(
--   p_empresa_id   UUID,
--   p_fecha        DATE    DEFAULT CURRENT_DATE,
--   p_tipo_orden   VARCHAR DEFAULT NULL
-- ) RETURNS UUID
--
-- Agrega órdenes del día por técnico y genera el registro en reportes_diarios_campo.
-- Si Suscripciones está activo para la empresa:
--   Consulta contratos con mora > parametro dias_para_suspension.
--   Crea automáticamente órdenes tipo CORTE para cada contrato moroso
--   que no tenga ya un CORTE pendiente para esa fecha.
-- Retorna el id del reporte generado.


-- send_daily_report_to_technicians(
--   p_empresa_id   UUID,
--   p_fecha        DATE DEFAULT CURRENT_DATE
-- ) RETURNS VOID
--
-- Lee el reporte generado por generate_daily_report().
-- Por cada técnico en el JSONB tecnicos[]:
--   Envía push notification con resumen (N órdenes hoy).
--   Envía WhatsApp con lista detallada: cliente, dirección, tipo, link Google Maps.
--   Para órdenes tipo CORTE: incluye monto de deuda del cliente.
-- Marca reportes_diarios_campo.enviado = true, canales_envio = ['push','whatsapp'].


-- escalate_to_workshop(
--   p_orden_id             UUID,
--   p_equipo_descripcion   TEXT,
--   p_descripcion_falla    TEXT,
--   p_activo_fijo_id       UUID DEFAULT NULL
-- ) RETURNS UUID
--
-- Detectado en campo que el equipo requiere reparación en banco.
-- Llama module_bus.taller.crear_orden(tipo='CORRECTIVO', descripcion=p_descripcion_falla).
-- Si p_activo_fijo_id presente: actualiza estado del activo a EN_MANTENIMIENTO.
-- Actualiza la orden de campo con referencia a la orden de taller creada.
-- Retorna el id de la orden de taller.


-- get_sla_compliance_report(
--   p_empresa_id   UUID,
--   p_fecha_desde  DATE,
--   p_fecha_hasta  DATE,
--   p_tecnico_id   UUID DEFAULT NULL
-- ) RETURNS TABLE(
--   tecnico_nombre       TEXT,
--   tipo_orden           VARCHAR,
--   total_ordenes        INTEGER,
--   cumple_respuesta     INTEGER,
--   cumple_resolucion    INTEGER,
--   pct_respuesta        DECIMAL(5,2),
--   pct_resolucion       DECIMAL(5,2)
-- )
--
-- Informe de cumplimiento SLA por técnico y tipo de orden en el período.
```

## Edge Functions

```
supabase/functions/send-daily-field-report/index.ts
  Trigger: cron diario a las 06:00 AM en la zona horaria de cada empresa.
  Para cada empresa con módulo Servicio de Campo activo:
    1. Llama generate_daily_report(empresa_id, CURRENT_DATE).
    2. Llama send_daily_report_to_technicians(empresa_id, CURRENT_DATE).
  Cada técnico recibe en WhatsApp:
    - Encabezado: "REPORTE DE ÓRDENES — {fecha}"
    - Lista numerada: {N}. {TIPO} | {Cliente} | {Dirección} | {link Google Maps}
    - Para CORTE: "+ Deuda: $XX.XX"
    - Pie: "Total: {N} órdenes asignadas"

supabase/functions/process-field-order-billing/index.ts
  Trigger: webhook al completar orden con es_facturable = true.
  Lee materiales_orden_campo WHERE es_facturable = true.
  Construye líneas de factura:
    - Línea 1: tarifa del servicio (INSTALACION, REINSTALACION, MANTENIMIENTO, etc.)
    - Líneas N+: materiales facturables con precio_cobro
  Genera factura electrónica via pipeline SRI normal (XML → firma XAdES-BES → SOAP SRI).
  Actualiza ordenes_campo.factura_id con el UUID de la factura generada.

supabase/functions/check-sla-breaches/index.ts
  Trigger: cron cada 15 minutos.
  Consulta órdenes en estado PENDIENTE, ASIGNADA, EN_RUTA, EN_EJECUCION
    donde sla_id IS NOT NULL.
  Calcula porcentaje de tiempo transcurrido vs tiempo_resolucion_horas.
  Si >= 80%: envía alerta push al supervisor con detalles de la orden.
  Si >= 100%: registra incumplimiento en sla_mediciones (cumple_resolucion = false)
    y envía notificación urgente.
```

## Module Service Bus

Funciones que este módulo expone para que otros módulos lo llamen:

```sql
-- module_bus.servicio_campo.create_order(
--   p_contrato_id    UUID,
--   p_tipo           VARCHAR,
--   p_fecha          DATE,
--   p_tecnico_id     UUID    DEFAULT NULL,
--   p_prioridad      VARCHAR DEFAULT 'ALTA'
-- ) RETURNS UUID
--
-- Permite a Suscripciones crear órdenes de campo directamente.
-- Caso de uso: cron de mora detecta contrato vencido → crea CORTE automáticamente.
-- Verifica que el módulo Servicio de Campo esté activo para la empresa.
-- Retorna id de la orden creada, o NULL si el módulo no está activo.


-- module_bus.servicio_campo.get_pending_orders(
--   p_tecnico_id   UUID,
--   p_fecha        DATE DEFAULT CURRENT_DATE
-- ) RETURNS TABLE(orden_id UUID, tipo VARCHAR, direccion TEXT, prioridad VARCHAR)
--
-- Usado por Dashboard para mostrar KPIs de órdenes pendientes del técnico.
-- Retorna tabla vacía si el módulo no está activo.
```

## Reglas de Negocio

```
Órdenes de campo:
  contrato_id es NULLABLE: el módulo funciona sin Suscripciones activo.
  Si Suscripciones activo: CORTE, REINSTALACION e INSTALACION actualizan estado contrato
    via module_bus.suscripciones.update_contract_state().
  Si Suscripciones no activo: el tipo de orden es informativo, sin efecto en contratos.
  GPS del técnico al completar (lat_ejecucion / lon_ejecucion) = verificación de presencia.
  Firma del cliente OBLIGATORIA para tipos: INSTALACION, REINSTALACION, RETIRO.
    complete_field_order() lanza EXCEPTION si firma_cliente es NULL en esos tipos.
  numero_orden: secuencial por empresa, formato configurable (ej: OC-2026-00001).

Materiales:
  Descuento de inventario ocurre al completar la orden, no al registrar los materiales.
  Materiales es_facturable = true: se incluyen como líneas en la factura electrónica.
  Materiales es_facturable = false: solo afectan inventario (costo interno de la empresa).
  Si bodega_id es NULL en el material, se usa la bodega predeterminada del técnico
    configurada en la tabla tecnicos_config (o la bodega principal de la empresa).

Escalamiento a Taller:
  Si en campo se detecta falla que requiere reparación en banco: escalate_to_workshop().
  El equipo del cliente queda en estado EN_REPARACION hasta que Taller lo devuelva.
  Taller notifica a Servicio de Campo via canal de Notificaciones cuando el equipo está listo.
  La orden de campo puede quedar en NO_EJECUTADA o COMPLETADA parcialmente,
    según si se realizó algún trabajo en sitio antes del escalamiento.

Reportes diarios:
  Generados automáticamente a las 06:00 AM en la zona horaria de la empresa.
  Cada técnico recibe únicamente SUS órdenes asignadas para ese día.
  El contenido incluye: cliente, dirección, tipo de orden, coordenadas, link Google Maps.
  Para órdenes tipo CORTE: incluye monto de deuda del cliente (solo para el técnico).
  El técnico actualiza el estado de sus órdenes desde la app Flutter mobile.

SLA:
  Un SLA puede aplicar a un tipo específico de orden o a todos los tipos (tipo_orden NULL).
  Si una orden tiene sla_id: el cron check-sla-breaches la monitorea cada 15 minutos.
  Pre-breach warning al 80% del tiempo límite: alerta al supervisor.
  Incumplimiento al 100%: registrado en sla_mediciones para reportes de gestión.
  sla_cumplido en ordenes_campo es calculado y guardado al completar la orden.

Facturación:
  Solo las órdenes con es_facturable = true generan factura electrónica.
  La factura incluye: tarifa del tipo de servicio + materiales con es_facturable = true.
  La factura sigue el pipeline SRI normal: XML, firma XAdES-BES, SOAP, RIDE PDF, email.
  El costo de materiales no facturables se absorbe como costo de servicio de la empresa.

Zonificación:
  Las zonas son polígonos GeoJSON. La auto-asignación usa ST_Contains() de PostGIS.
  Si las coordenadas de la orden caen fuera de todas las zonas, zona_id queda NULL.
  La asignación manual de técnico siempre prevalece sobre la auto-asignación por zona.
```

---

> Módulos relacionados:
> - [Suscripciones](../suscripciones/suscripciones.md) — Contratos recurrentes (opcional, no requerido)
> - [Taller](../taller/taller.md) — Escalamiento para reparación física de equipos en banco
> - [Inventario](../inventario/inventario.md) — Stock de materiales para órdenes de campo
> - [Activos Fijos](../activos-fijos/activos-fijos.md) — Equipos en campo vinculados a activos fijos
