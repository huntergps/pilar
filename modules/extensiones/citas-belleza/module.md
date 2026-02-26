# Módulo de Gestión de Citas (Belleza, Salud, Servicios)


Modulo auxiliar (#19 en tabla `modulos`) diseñado para negocios de servicios de belleza y cuidado personal. Soporta spas, peluquerias, barberias, nail spas y centros de estetica. Se integra via **Module Service Bus** con Facturacion, Inventario, Contabilidad, RRHH y Notificaciones.

### Vision General y Tipos de Negocio

| Tipo de Negocio | Modelo Predominante | Servicios Tipicos |
|-----------------|--------------------|--------------------|
| Barberia | Walk-in 70-80%, comision 50% | Corte (30min), Barba (15min), Tinte barba (25min) |
| Peluqueria/Salon | Citas 60-70%, comision 40-45% | Corte (45min), Tinte (90-120min), Mechas (120min), Peinado (60min) |
| Nail Spa | Mixto 50/50, comision 40% | Manicure (30min), Pedicure (60min), Acrilicas (90min), Gelish (45min) |
| Spa/Estetica | Citas 90%+, comision 35-40% | Facial (60min), Masaje (60min), Depilacion (30min) |

**Caracteristicas principales:**
- Agenda visual por profesional (columnas = profesionales, filas = horas)
- Reservas multi-canal: presencial, telefono, WhatsApp, Telegram, email, web
- Walk-in con cola de espera y tiempo estimado
- Double-booking inteligente (tiempo activo vs procesamiento)
- Sistema de comisiones configurable (6 modelos)
- Tracking de insumos/consumibles por servicio (backbar)
- Paquetes, membresias y gift cards
- Liquidacion periodica de comisiones
- Propinas con asignacion configurable
- Recordatorios automaticos multi-canal

### Ciclo de Vida de la Cita (Estados)

```
SOLICITADA → CONFIRMADA → CHECK_IN → EN_PROGRESO → COMPLETADA
     │            │           │            │
     ▼            ▼           ▼            ▼
  RECHAZADA   CANCELADA    NO_SHOW     CANCELADA
                  │
                  ▼
             REPROGRAMADA (genera nueva cita)
```

| Estado | Descripcion | Trigger |
|--------|-------------|---------|
| SOLICITADA | Cliente pidio cita, pendiente de confirmar | Booking online/WhatsApp/telefono |
| CONFIRMADA | Cita aceptada, espacio reservado en agenda | Confirmacion manual o automatica |
| CHECK_IN | Cliente llego al local | Recepcionista registra llegada |
| EN_PROGRESO | Servicio en ejecucion | Profesional inicia servicio |
| COMPLETADA | Servicio finalizado, pendiente de cobro o ya cobrado | Profesional marca fin |
| CANCELADA | Cancelada por cliente o negocio | Antes de la hora de la cita |
| NO_SHOW | Cliente no se presento (grace period 10-15 min) | Automatico o manual |
| REPROGRAMADA | Movida a otra fecha/hora, genera nueva cita | Cliente o negocio solicitan cambio |

### Gestion de Agenda y Disponibilidad

La agenda se construye en capas superpuestas:

```
CAPA 1: Horario del establecimiento (Lun-Sab 9:00-19:00)
CAPA 2: Horario del profesional (puede ser diferente)
CAPA 3: Bloqueos recurrentes (almuerzo 13:00-14:00)
CAPA 4: Bloqueos puntuales (vacaciones, permisos, capacitaciones)
CAPA 5: Citas ya agendadas
─────────────────────────────────────
RESULTADO: Slots disponibles (calculados por citas_obtener_disponibilidad)
```

**Granularidad:** 15 minutos por defecto (configurable: 10, 15, 20, 30 min).

#### Double-Booking Inteligente

Cada servicio tiene **5 tiempos desglosados**:

| Tiempo | Descripcion | Bloquea al profesional? |
|--------|-------------|------------------------|
| `duracion_preparacion` | Mezcla de tinte, calentar cera | SI |
| `duracion_activa` | Trabajo directo con el cliente | SI |
| `duracion_procesamiento` | Espera (tinte revelando, secado) | NO |
| `duracion_limpieza` | Limpiar puesto, esterilizar | SI |
| `buffer_posterior` | Margen entre citas | NO |

**Regla:** Solo `duracion_activa` bloquea al profesional. Durante `duracion_procesamiento`, el profesional puede atender otra cita (configurable via `max_double_booking` en citas_configuracion).

Ejemplo: Estilista aplica tinte (20 min activos) → tinte procesa 30-45 min → durante el procesamiento puede hacer un corte a otro cliente.

### Walk-in y Cola de Espera

```
Cliente llega sin cita
  → Recepcionista registra walk-in (nombre, telefono, servicio deseado)
  → Sistema verifica disponibilidad inmediata
    → Si hay profesional libre: asignar directamente (crea cita EN_PROGRESO)
    → Si no hay: agregar a citas_lista_espera
      → Sistema calcula tiempo estimado (citas en progreso + duraciones restantes)
      → Notifica al cliente por WhatsApp/SMS
      → Cuando se libera profesional: notifica recepcion
      → Walk-in pasa a cita
```

- Turno secuencial diario (reinicia cada dia)
- Tiempo real de espera visible (cronometro en vivo)
- Indicador visual: verde (<10min), amarillo (10-20min), rojo (>20min)
- Al atender, el walk-in se convierte automaticamente en cita con `es_walk_in = true`

### Reservas Multi-Canal

Todos los canales convergen en una UNICA tabla de citas centralizada:

| Canal | Implementacion | Campo `canal_reserva` |
|-------|---------------|-----------------------|
| Presencial | Recepcionista usa el sistema directamente | PRESENCIAL |
| Telefono | Recepcionista registra manualmente | TELEFONO |
| WhatsApp | Bot conversacional (Cloud API) o asistente manual | WHATSAPP |
| Telegram | Bot con menu de servicios (Bot API) | TELEGRAM |
| Email | Link de reserva en correos del negocio | EMAIL |
| Web | Widget de booking embebido en sitio web | WEB |
| App movil | Reserva desde app del negocio | APP |

**Principios:**
- Single Source of Truth: una sola tabla `citas`, sin importar el canal
- Validacion centralizada: toda reserva pasa por `citas_verificar_conflicto()`
- Confirmacion uniforme: mismo flujo de confirmacion/recordatorio
- Registro de canal para analytics (reportes de canales mas usados)

### Sistema de Comisiones

#### Modelos de Comision Soportados

```sql
CREATE TYPE citas_tipo_comision AS ENUM (
  'PORCENTAJE_FIJO',     -- X% de cada servicio
  'ESCALONADO',          -- % variable segun monto acumulado del periodo
  'POR_SERVICIO',        -- Monto fijo por cada servicio realizado
  'HIBRIDO',             -- Base fija + % del excedente sobre meta
  'ALQUILER_SILLA'       -- Profesional paga renta fija, se queda con el resto
);
```

**Modelo 1 - Porcentaje Fijo:** El mas comun. El profesional recibe X% de cada servicio.

| Tipo Negocio | Rango Tipico | Promedio |
|-------------|-------------|---------|
| Barberia | 40-60% | 50% |
| Peluqueria | 30-50% | 40-45% |
| Spa | 30-45% | 35-40% |
| Nail Spa | 30-50% | 40% |

**Modelo 2 - Escalonado:** La tasa aumenta con el volumen de ventas del periodo (tabla `citas_comision_escalones`).

```
Hasta $500/mes    → 35%
$501 - $1,000     → 40%
$1,001 - $2,000   → 45%
$2,001 - $3,000   → 50%
Mas de $3,000     → 55%
```

**Modelo 3 - Por Servicio:** Monto fijo por cada servicio, no porcentaje (ej: $5 por corte, $15 por tinte).

**Modelo 4 - Hibrido (Base + Comision):** Salario base garantizado + comision sobre meta.

```
Base: $482/mes (SBU Ecuador 2026)
Meta: $1,500/mes en servicios
Comision: 30% sobre todo lo que supere la meta
Si vende $2,000: $482 + 30% * ($2,000 - $1,500) = $482 + $150 = $632
```

**Modelo 5 - Alquiler de Silla (Booth Rental):** Profesional paga renta fija mensual y se queda con todo el ingreso. No hay relacion laboral. El profesional cobra directo al cliente con su propio RUC.

#### Motor de Calculo de Comisiones

La funcion `citas_calcular_comision()` busca la regla mas especifica por prioridad:

```
Prioridad 1: Regla especifica profesional + servicio
Prioridad 2: Regla profesional + categoria de servicio
Prioridad 3: Regla general del profesional
Prioridad 4: Regla general del servicio
Prioridad 5: Regla general de la empresa
```

Al completar una cita, el trigger `trg_citas_estado` llama a `citas_generar_comisiones_cita()` que genera una fila en `citas_comisiones` por cada linea de detalle, aplicando la regla correspondiente y descontando backbar.

#### Liquidacion de Comisiones

Proceso periodico (quincenal o mensual) via `citas_liquidar_comisiones()`:

```
1. Agrupar comisiones CALCULADAS del periodo por profesional
2. Sumar: total_servicios + comision_bruta + propinas
3. Restar: backbar + alquiler_silla_prorrateado
4. Generar registro en citas_liquidaciones (estado BORRADOR)
5. Administrador revisa y aprueba → estado APROBADA
6. Se genera pago → estado PAGADA
7. Via module_bus.register_appointment_commissions() → RRHH (si activo)
```

#### Comision por Productos Retail

Separada de la comision por servicios. Tipicamente 10-25% del precio de venta del producto. Se configura en `citas_comision_reglas` con `aplicar_a` incluyendo el porcentaje de productos.

#### Propinas

- Registro en `citas_propinas` por profesional, metodo de pago y cita
- Configurable: 100% para el profesional o pool con reparto (citas_configuracion.propina_pool_pct)
- No forman parte de la base salarial IESS
- Metodos: efectivo, tarjeta, transferencia, app

### Servicios y Tiempos

#### Catalogo de Servicios

```sql
citas_servicios
  id                    UUID PK
  empresa_id            UUID FK -> empresas
  categoria_id          UUID FK -> citas_categorias_servicio
  producto_id           UUID FK -> productos           -- Vinculo con catalogo de productos del ERP
  nombre                VARCHAR(200) NOT NULL
  descripcion           TEXT
  -- 5 tiempos desglosados (minutos)
  duracion_preparacion  INTEGER DEFAULT 0              -- Mezcla tinte, calentar cera
  duracion_activa       INTEGER NOT NULL               -- Trabajo directo con cliente
  duracion_procesamiento INTEGER DEFAULT 0             -- Espera (tinte revelando)
  duracion_limpieza     INTEGER DEFAULT 0              -- Limpiar puesto
  buffer_posterior      INTEGER DEFAULT 0              -- Margen entre citas
  -- Precios
  precio_base           DECIMAL(14,2) NOT NULL
  costo_estimado        DECIMAL(14,2) DEFAULT 0        -- Costo de insumos estimado
  -- Restricciones
  nivel_minimo          citas_nivel_profesional DEFAULT 'JUNIOR'
  permite_double_booking BOOLEAN DEFAULT false          -- Si tiene procesamiento, puede ser true
  max_simultaneos       INTEGER DEFAULT 1
  requiere_deposito     BOOLEAN DEFAULT false
  deposito_porcentaje   DECIMAL(5,2) DEFAULT 0
  -- IVA
  codigo_iva            VARCHAR(4) DEFAULT '4'         -- 4 = IVA 15%
  tarifa_iva            DECIMAL(5,2) DEFAULT 15.00
  genero_target         VARCHAR(1) DEFAULT 'U'         -- M, F, U (unisex)
  disponible_online     BOOLEAN DEFAULT true
```

#### Servicios Tipicos con Tiempos

| Servicio | Prep | Activa | Proceso | Limpieza | Total | Double-booking? |
|----------|------|--------|---------|----------|-------|-----------------|
| Corte caballero | 0 | 30 | 0 | 5 | 35 min | No |
| Corte + barba | 0 | 45 | 0 | 5 | 50 min | No |
| Tinte raiz | 15 | 30 | 35 | 10 | 90 min | Si (35 min libres) |
| Mechas/Balayage | 15 | 90 | 40 | 10 | 155 min | Si (40 min libres) |
| Manicure basico | 0 | 30 | 5 | 0 | 35 min | No |
| Manicure gel | 0 | 40 | 3 | 0 | 43 min | No |
| Pedicure spa | 5 | 55 | 0 | 5 | 65 min | No |
| Facial basico | 5 | 50 | 10 | 5 | 70 min | Si (10 min libres) |
| Masaje relajante | 5 | 60 | 0 | 5 | 70 min | No |
| Depilacion cera | 10 | 25 | 0 | 5 | 40 min | No |

### Insumos y Consumibles (Backbar)

#### Estimacion vs Consumo Real

Cada servicio tiene insumos estimados en `citas_servicio_insumos`:

```sql
citas_servicio_insumos
  servicio_id       UUID FK -> citas_servicios
  producto_id       UUID FK -> productos           -- Producto de inventario
  cantidad_estimada DECIMAL(18,6) NOT NULL         -- 30 ml, 2 unidades, etc.
  unidad_medida_id  UUID FK -> unidades_medida
  costo_estimado    DECIMAL(14,2) DEFAULT 0
```

Al completar la cita, se registra el consumo real en `citas_consumos`:

```sql
citas_consumos
  cita_id           UUID FK -> citas
  cita_detalle_id   UUID FK -> citas_detalle
  producto_id       UUID FK -> productos
  cantidad_estimada DECIMAL(18,6)                  -- Del catalogo
  cantidad_real     DECIMAL(18,6) NOT NULL         -- Lo que realmente se uso
  costo_unitario    DECIMAL(14,2) NOT NULL
  costo_total       DECIMAL(14,2)                  -- GENERATED: cantidad_real * costo_unitario
  movimiento_inv_id UUID                           -- Referencia al movimiento de inventario (si modulo activo)
```

**Trigger `trg_citas_consumo_insert`:** Al insertar consumo, llama a `module_bus.request_inventory_movement()` para descontar stock. Si Inventario esta inactivo, retorna NO-OP silencioso.

#### Impacto Financiero del Tracking de Backbar

- 25-40% reduccion en producto desperdiciado
- 10-15% mejora en margen de ganancia
- Permite calcular rentabilidad real por servicio

### Paquetes, Membresias y Gift Cards

#### Paquetes (Combos de Servicios)

```sql
citas_paquetes
  nombre            VARCHAR(200)
  precio_paquete    DECIMAL(14,2) NOT NULL         -- Precio con descuento
  precio_individual DECIMAL(14,2) NOT NULL         -- Suma de precios individuales
  ahorro            DECIMAL(14,2)                  -- GENERATED: precio_individual - precio_paquete
  vigencia_dias     INTEGER DEFAULT 180            -- Dias para usar el paquete
  max_ventas        INTEGER                        -- Limite de ventas (NULL = ilimitado)
```

Control de uso en `citas_paquete_clientes` con campo JSONB `servicios_usados` que rastrea que servicios del paquete se han consumido.

#### Membresias (Suscripciones Recurrentes)

```sql
citas_membresias
  nombre            VARCHAR(200)
  tipo              citas_tipo_membresia           -- MENSUAL, TRIMESTRAL, SEMESTRAL, ANUAL
  precio            DECIMAL(14,2) NOT NULL
  servicios_incluidos JSONB                        -- [{servicio_id, cantidad_periodo}]
  descuento_servicios_extra DECIMAL(5,2) DEFAULT 0 -- % descuento en servicios no incluidos
  descuento_productos DECIMAL(5,2) DEFAULT 0       -- % descuento en productos retail
  prioridad_reserva BOOLEAN DEFAULT false          -- Fast-lane para reservas
  auto_renovacion   BOOLEAN DEFAULT true
```

#### Gift Cards (Tarjetas de Regalo)

```sql
citas_gift_cards
  codigo            VARCHAR(20) UNIQUE
  monto_original    DECIMAL(14,2) NOT NULL
  saldo_disponible  DECIMAL(14,2) NOT NULL
  comprador_id      UUID FK -> contactos
  beneficiario_id   UUID FK -> contactos           -- NULL = portador anonimo
  estado            citas_estado_gift_card          -- ACTIVA, AGOTADA, VENCIDA, CANCELADA
  fecha_vencimiento DATE                           -- NULL = sin vencimiento
```

Movimientos transaccionales en `citas_gift_card_movimientos` con saldo_anterior/saldo_posterior. Trigger valida saldo suficiente y marca AGOTADA automaticamente.

### Normativa Ecuador

#### Facturacion SRI

Los servicios de belleza **gravan IVA 15%** (no estan en la lista de servicios tarifa 0% del Art. 56 LRTI).

| Regimen del Negocio | IVA | Comprobante |
|---------------------|-----|-------------|
| RIMPE Negocio Popular (hasta $20,000/ano) | No cobra IVA separado (incluido en cuota fija $60/ano) | Nota de venta preimpresa |
| RIMPE Emprendedor ($20,001-$300,000/ano) | Cobra IVA 15% | Factura electronica obligatoria |
| Regimen General (mas de $300,000/ano) | Cobra IVA 15% | Factura electronica obligatoria |

#### Retenciones (cuando el salon paga a profesional independiente)

| Concepto | Codigo SRI | Porcentaje |
|----------|-----------|------------|
| Honorarios profesionales (con titulo) | 303 | 10% IR |
| Servicios mano de obra (sin titulo) | 304 | 2% IR |
| Retencion IVA servicios profesionales | 725 | 50% |
| Retencion IVA mano de obra | 727 | 70% |

**ADVERTENCIA:** Si existe subordinacion (horario fijo, herramientas del salon, instrucciones directas), los jueces pueden reclasificar la relacion como laboral. Multas + pago retroactivo de beneficios sociales.

#### IESS

| Escenario | Obligacion |
|-----------|-----------|
| Profesional empleado | Aporte patronal 11.15% + personal 9.45% sobre base + comisiones |
| Profesional independiente | Sin obligacion del salon. Afiliacion voluntaria 17.60% |
| Alquiler de silla | Cero obligacion. Contrato de arrendamiento |

#### Codigo CIIU

**9602 - Peluqueria y otros tratamientos de belleza.** Incluye: corte, tinte, afeitado, manicure, pedicure, maquillaje, depilacion.

#### Permisos de Funcionamiento

| Permiso | Entidad | Nota |
|---------|---------|------|
| RUC | SRI | Obligatorio, gratuito |
| Patente Municipal | Municipio | Anual, variable segun canton |
| LUAE | Municipio (ej: Quito) | Integra varios permisos |
| Certificado Bomberos | Cuerpo Bomberos | Anual |
| Permiso ARCSA | ARCSA | **Ya NO obligatorio** para centros de belleza |

### Modelo de Datos

Se diseñaron **25 tablas**, **14 tipos ENUM**, organizados en el esquema `public` con prefijo `citas_`. Archivos SQL completos en `sql/modulo_citas.sql` y `sql/modulo_citas_funciones.sql`.

#### Tablas por Grupo

| Grupo | Tablas |
|-------|--------|
| Configuracion | `citas_configuracion` |
| Profesionales y Horarios | `citas_profesionales`, `citas_horarios`, `citas_bloqueos` |
| Catalogo de Servicios | `citas_categorias_servicio`, `citas_servicios`, `citas_servicio_profesionales`, `citas_servicio_insumos` |
| Citas Core | `citas`, `citas_detalle`, `citas_consumos` |
| Comisiones | `citas_comision_reglas`, `citas_comision_escalones`, `citas_comisiones`, `citas_liquidaciones` |
| Propinas | `citas_propinas` |
| Paquetes y Membresias | `citas_paquetes`, `citas_paquete_servicios`, `citas_paquete_clientes`, `citas_membresias`, `citas_membresia_clientes` |
| Gift Cards | `citas_gift_cards`, `citas_gift_card_movimientos` |
| Walk-in y Recordatorios | `citas_lista_espera`, `citas_recordatorios` |

#### Tabla Principal: citas

```sql
citas
  id                  UUID PK
  empresa_id          UUID FK -> empresas
  establecimiento_id  UUID FK -> sucursales
  numero              VARCHAR(20)                    -- Auto: CT-2026-000123
  -- Cliente
  contacto_id         UUID FK -> contactos           -- NULL si walk-in anonimo
  nombre_cliente      VARCHAR(200)                   -- Desnormalizado o para walk-in sin contacto
  telefono_cliente    VARCHAR(20)
  -- Profesional principal
  profesional_id      UUID FK -> citas_profesionales
  -- Fecha/Hora
  fecha               DATE NOT NULL
  hora_inicio         TIME NOT NULL
  hora_fin_estimada   TIME NOT NULL                  -- Calculada: hora_inicio + sum(duraciones)
  zona_horaria        VARCHAR(50) DEFAULT 'America/Guayaquil'
  -- Estado y origen
  estado              citas_estado DEFAULT 'SOLICITADA'
  canal_reserva       citas_canal DEFAULT 'PRESENCIAL'
  es_walk_in          BOOLEAN DEFAULT false
  -- Totales (recalculados por trigger desde citas_detalle)
  subtotal            DECIMAL(14,2) DEFAULT 0
  descuento_total     DECIMAL(14,2) DEFAULT 0
  impuesto_total      DECIMAL(14,2) DEFAULT 0
  total               DECIMAL(14,2) DEFAULT 0
  cobrado             DECIMAL(14,2) DEFAULT 0
  -- Integracion
  factura_id          UUID FK -> facturas            -- Si ya se facturo
  paquete_cliente_id  UUID FK -> citas_paquete_clientes
  membresia_cliente_id UUID FK -> citas_membresia_clientes
  gift_card_id        UUID FK -> citas_gift_cards
  -- Reprogramacion
  cita_original_id    UUID FK -> citas               -- Si es reprogramacion
  motivo_cancelacion  TEXT
  -- Calificacion
  calificacion        SMALLINT CHECK (calificacion BETWEEN 1 AND 5)
  comentario_cliente  TEXT
  -- Notas
  notas_internas      TEXT
  notas_cliente       TEXT
  -- Timestamps de flujo
  confirmada_at       TIMESTAMPTZ
  check_in_at         TIMESTAMPTZ
  inicio_servicio_at  TIMESTAMPTZ
  fin_servicio_at     TIMESTAMPTZ
  cobrada_at          TIMESTAMPTZ
  -- Audit
  version             INTEGER DEFAULT 1
  created_by          UUID FK -> auth.users
  updated_by          UUID FK -> auth.users
  created_at          TIMESTAMPTZ DEFAULT NOW()
  updated_at          TIMESTAMPTZ DEFAULT NOW()
```

#### Tabla: citas_detalle (Servicios dentro de una cita)

```sql
citas_detalle
  id                UUID PK
  cita_id           UUID FK -> citas ON DELETE CASCADE
  servicio_id       UUID FK -> citas_servicios
  profesional_id    UUID FK -> citas_profesionales   -- Puede ser diferente al principal
  -- Horario individual
  hora_inicio       TIME
  hora_fin_estimada TIME
  duracion_real_min INTEGER                          -- Registrado al completar
  -- Valores
  cantidad          INTEGER DEFAULT 1
  precio_unitario   DECIMAL(14,2) NOT NULL
  descuento_pct     DECIMAL(5,2) DEFAULT 0
  descuento_monto   DECIMAL(14,2) DEFAULT 0          -- Calculado por trigger
  subtotal          DECIMAL(14,2)                    -- Calculado: precio * cantidad - descuento
  codigo_iva        VARCHAR(4) DEFAULT '4'
  tarifa_iva        DECIMAL(5,2) DEFAULT 15.00
  impuesto          DECIMAL(14,2)                    -- Calculado: subtotal * tarifa_iva / 100
  total             DECIMAL(14,2)                    -- Calculado: subtotal + impuesto
  orden             SMALLINT DEFAULT 1
```

#### Tabla: citas_profesionales

```sql
citas_profesionales
  id                UUID PK
  empresa_id        UUID FK -> empresas
  empleado_id       UUID FK -> empleados             -- Vinculo con RRHH
  nombre_artistico  VARCHAR(100)
  nivel             citas_nivel_profesional DEFAULT 'JUNIOR'
  especialidades    TEXT[]                           -- ARRAY de especialidades
  comision_default_pct DECIMAL(5,2) DEFAULT 40.00
  color_agenda      VARCHAR(7) DEFAULT '#2196F3'    -- Color en calendario
  acepta_walk_in    BOOLEAN DEFAULT true
  biografia         TEXT
  instagram         VARCHAR(100)
  foto_url          TEXT
  activo            BOOLEAN DEFAULT true
```

#### Tabla: citas_comision_reglas

```sql
citas_comision_reglas
  id                UUID PK
  empresa_id        UUID FK -> empresas
  profesional_id    UUID FK -> citas_profesionales   -- NULL = regla general
  servicio_id       UUID FK -> citas_servicios       -- NULL = todos los servicios
  categoria_id      UUID FK -> citas_categorias_servicio -- NULL = todas las categorias
  tipo              citas_tipo_comision NOT NULL
  porcentaje        DECIMAL(5,2)                     -- Para PORCENTAJE_FIJO
  monto_fijo        DECIMAL(14,2)                    -- Para POR_SERVICIO
  base_mensual      DECIMAL(14,2)                    -- Para HIBRIDO (salario base)
  meta_mensual      DECIMAL(14,2)                    -- Para HIBRIDO (meta de ventas)
  pct_sobre_meta    DECIMAL(5,2)                     -- Para HIBRIDO (% sobre excedente)
  renta_mensual     DECIMAL(14,2)                    -- Para ALQUILER_SILLA
  backbar_por_servicio DECIMAL(14,2) DEFAULT 0       -- Descuento por insumos
  prioridad         INTEGER DEFAULT 100              -- Menor = mas prioritario
  vigente_desde     DATE NOT NULL DEFAULT CURRENT_DATE
  vigente_hasta     DATE                             -- NULL = sin fecha fin
  activo            BOOLEAN DEFAULT true
```

### Funciones PostgreSQL

Archivo: `sql/modulo_citas_funciones.sql`

#### Funciones de Disponibilidad (2)

| Funcion | Descripcion |
|---------|-------------|
| `citas_obtener_disponibilidad(empresa, profesional, fecha, servicio?, establecimiento?)` | Retorna JSONB con slots libres considerando horarios, bloqueos, double-booking inteligente |
| `citas_verificar_conflicto(empresa, profesional, fecha, hora_inicio, hora_fin, servicio?, excluir_cita?)` | Verifica si existe conflicto antes de agendar |

#### Funciones de Comisiones (3)

| Funcion | Descripcion |
|---------|-------------|
| `citas_calcular_comision(empresa, profesional, servicio, monto, fecha)` | Motor de calculo con busqueda de regla por prioridad, soporte 5 tipos |
| `citas_generar_comisiones_cita(cita_id)` | Genera todas las comisiones de una cita completada |
| `citas_liquidar_comisiones(empresa, profesional, periodo_desde, periodo_hasta)` | Crea liquidacion agrupando comisiones + propinas del periodo |

#### Funciones Walk-in (1)

| Funcion | Descripcion |
|---------|-------------|
| `citas_agregar_walk_in(empresa, establecimiento, nombre, telefono?, contacto?, servicio?, profesional?)` | Agrega a cola con turno secuencial y estimacion de espera |

#### Triggers (6)

| Trigger | Tabla | Accion |
|---------|-------|--------|
| `trg_citas_estado` | citas (BEFORE UPDATE) | Genera comisiones al COMPLETAR, registra timestamps, anula comisiones si cancela, bloqueo optimista |
| `trg_citas_consumo_insert` | citas_consumos (BEFORE INSERT) | Descuenta stock via module_bus, calcula costo_total |
| `trg_gift_card_mov_insert` | gift_card_movimientos (BEFORE INSERT) | Actualiza saldo, valida suficiencia, marca AGOTADA |
| `trg_citas_detalle_totales` | citas_detalle (AFTER INSERT/UPDATE/DELETE) | Recalcula totales de la cita cabecera |
| `trg_citas_detalle_before` | citas_detalle (BEFORE INSERT/UPDATE) | Calcula descuento_monto, subtotal, impuesto, total por linea |
| `trg_citas_numero_insert` | citas (BEFORE INSERT) | Auto-genera numero secuencial: CT-2026-000123 |

#### Vistas (6)

| Vista | Uso |
|-------|-----|
| `v_citas_agenda_dia` | Agenda diaria desnormalizada (cliente, profesional, servicios, totales, calificacion) |
| `v_citas_ocupacion_semanal` | Ocupacion por profesional/dia (citas, horas, revenue, tasa) |
| `v_citas_comisiones_mes` | Resumen mensual de comisiones (bruto, backbar, neto, propinas) |
| `v_citas_rentabilidad_servicio` | Revenue, costos insumos, comisiones, margen y revenue/minuto por servicio |
| `v_citas_cola_espera` | Cola walk-in activa con tiempo real de espera y posicion |
| `v_citas_dashboard_dia` | KPIs diarios: volumen, revenue, ticket promedio, propinas, canales |

### Integracion via Module Service Bus

El modulo Citas es **tipo AUXILIAR** (Tipo 3). NUNCA hace INSERT directo en tablas de otros modulos.

| Operacion | Modulo Destino | Funcion Bus | Si Inactivo |
|-----------|---------------|-------------|-------------|
| Crear factura | Facturacion | `module_bus.create_invoice_from_appointment()` | Facturacion es infraestructura, SIEMPRE activa |
| Descontar insumos | Inventario | `module_bus.request_inventory_movement()` | NO-OP silencioso |
| Crear asiento contable | Contabilidad | `module_bus.create_journal_entry()` | NO-OP silencioso |
| Registrar comisiones en nomina | RRHH | `module_bus.register_appointment_commissions()` | NO-OP silencioso |
| Enviar notificacion | Infraestructura | `module_bus.send_notification()` | SIEMPRE se ejecuta |
| Registrar actividad | Infraestructura | `module_bus.log_activity()` | SIEMPRE se ejecuta |

**Funciones gateway nuevas del bus:**

```sql
-- Citas → Facturacion: genera factura desde cita completada
module_bus.create_invoice_from_appointment(p_empresa_id UUID, p_cita_id UUID)

-- Citas → RRHH: registra comisiones liquidadas en nomina
module_bus.register_appointment_commissions(p_empresa_id UUID, p_liquidacion_id UUID)
```

### UI/UX (Flutter + Material 3 + Syncfusion)

#### Calendario/Agenda Principal

**Widget:** Syncfusion `SfCalendar` con `CalendarView.timelineDay` y `resources` (columnas = profesionales).

```dart
SfCalendar(
  view: CalendarView.timelineDay,
  dataSource: CitasDataSource(citas, profesionales),
  allowDragAndDrop: true,  // Solo desktop/tablet
  resourceViewSettings: ResourceViewSettings(
    visibleResourceCount: _getVisibleResourceCount(breakpoint),
    showAvatar: true,
    size: 80,
  ),
  timeSlotViewSettings: TimeSlotViewSettings(
    startHour: 7, endHour: 21,
    timeInterval: Duration(minutes: 15),
  ),
  specialRegions: _getBreakTimes(profesionales),  // Almuerzos, descansos
  appointmentBuilder: (context, details) => _CitaBlock(details),
  onDragEnd: (details) => _handleReschedule(details),
)
```

**Vistas disponibles** (toggle en header):
- Dia (por defecto): todas las columnas de profesionales
- 3 Dias: una columna por dia, un profesional a la vez
- Semana: una columna por dia con selector de profesional
- Lista/Agenda: lista cronologica (movil)

#### Paleta de Colores por Estado

Usando tokens de color de fluent_ui (se adaptan al accentColor de la empresa):

| Estado | Color Fondo | Color Borde | Icono |
|--------|-------------|-------------|-------|
| SOLICITADA | surfaceContainerLow | outline | schedule |
| CONFIRMADA | primaryContainer | primary | check_circle_outline |
| EN_PROGRESO | tertiaryContainer | tertiary | play_circle_outline |
| COMPLETADA | surfaceContainerHighest | outlineVariant | task_alt |
| COBRADA | secondaryContainer | secondary | payments |
| CANCELADA | errorContainer | error | cancel_outlined |
| NO_SHOW | errorContainer (60%) | error | person_off |
| EN_ESPERA | tertiaryContainer | tertiary | hourglass_top |

**Regla:** NUNCA colores hardcoded. Siempre via `Theme.of(context).colorScheme`.

#### Flujo: Nueva Cita (Stepper 5 pasos)

```
Paso 1: CLIENTE    → Buscar/crear cliente, historial resumido, "Repetir ultima cita"
Paso 2: SERVICIOS  → Multi-seleccion por categoria, subtotal + duracion acumulada
Paso 3: PROFESIONAL → Grid cards con avatar, disponibilidad, "Cualquier disponible"
Paso 4: HORARIO    → Grid visual de slots (verde=libre, rojo=ocupado), selector de fecha
Paso 5: CONFIRMAR  → Resumen tipo recibo, canal de recordatorio, notas, deposito
```

**Tiempo objetivo:** < 60 segundos para el flujo comun. Maximo 3 pantallas/clicks.

#### Flujo: Completar Servicio y Cobrar

```
Profesional termina → Marcar servicios completados (checkboxes)
  → Registrar insumos usados (opcional, sugeridos del catalogo)
  → Agregar propina (10%, 15%, 20%, personalizado)
  → Generar factura (module_bus → Facturacion)
  → Cobrar (efectivo/tarjeta/transferencia/mixto/gift card)
  → Registrar comision (automatico via trigger)
  → Sugerir re-booking ("Agendar proxima cita?")
  → Enviar comprobante por canal preferido
```

#### Adaptacion Responsive

| Elemento | COMPACT (<600px) | MEDIUM (600-840px) | EXPANDED (840-1200px) | LARGE (>1200px) |
|----------|-------------------|--------------------|-----------------------|-----------------|
| Calendario | Lista del dia | Timeline 2-3 cols | Timeline full | Timeline + split view |
| Detalle cita | Bottom sheet | Panel 40% | Panel 30% | Panel fijo + chat |
| Nueva cita | Full screen stepper | Dialog stepper | Dialog stepper | Dialog stepper |
| Profesionales | Tabs pill scroll | Chips + scroll | Columnas visibles | Todas las columnas |
| Lista espera | Pantalla separada | Tab | Panel colapsable | Panel inferior fijo |
| Drag & drop | No | No | Si | Si + context menu |

#### Iconografia Canal de Reserva

| Canal | Icono | Color |
|-------|-------|-------|
| WhatsApp | chat | #25D366 (verde WhatsApp) |
| Telegram | send | #0088CC (azul Telegram) |
| Telefono | phone | tertiary del tema |
| Email | email | secondary del tema |
| Presencial | store | primary del tema |
| Web/App | language | primary del tema |

### Notificaciones y Recordatorios

Usa el sistema de notificaciones existente de PILAR (Resend para email, Cloud API para WhatsApp, Bot API para Telegram). El contacto tiene `canales_notificacion` en la tabla de contactos del Core Foundation.

| Evento | Destinatario | Canal | Momento |
|--------|-------------|-------|---------|
| Cita creada | Cliente | Canal de reserva + preferidos | Inmediato |
| Recordatorio 24h | Cliente | Canal preferido | 24h antes |
| Recordatorio 2h | Cliente | Push + canal preferido | 2h antes |
| Nueva cita asignada | Profesional | Push in-app | Inmediato |
| Cita cancelada | Profesional + Cliente | Push + canal preferido | Inmediato |
| Walk-in listo | Cliente en espera | WhatsApp/SMS | Al liberar slot |
| No-show | Cliente | Email | 1h despues |
| Resumen diario | Profesional | Email + canal preferido | Dia anterior 20:00 |
| Liquidacion comision | Profesional | Email + WhatsApp | Al liquidar |
| Re-booking sugerido | Cliente | WhatsApp/Email | 3 dias post-visita |

Secuencia de recordatorios que reduce no-shows hasta un 40%:
1. Confirmacion inmediata al reservar
2. Recordatorio a 24 horas (WhatsApp: 98% tasa apertura)
3. Recordatorio a 2 horas con opcion confirmar/cancelar/reprogramar
4. Post-servicio: agradecimiento + re-booking

### KPIs y Reportes

#### Metricas de Ocupacion

| KPI | Formula | Benchmark |
|-----|---------|-----------|
| Tasa de Ocupacion | Citas realizadas / Slots disponibles | 75-85% |
| Utilizacion por Profesional | Horas facturables / Horas disponibles | 70-80% |
| Clientes por Dia (por profesional) | Total clientes / Dias trabajados | 8-12 |

#### Metricas de Ingresos

| KPI | Formula | Benchmark |
|-----|---------|-----------|
| Ticket Promedio | Ingreso total / Num transacciones | Variable |
| Revenue por Profesional | Ingreso del profesional / Periodo | Variable |
| Retail vs Servicios | Ingreso productos / Ingreso total | 15-25% |
| Revenue por Hora | Ingreso total / Horas operativas | Variable |

#### Metricas de Clientes

| KPI | Formula | Benchmark |
|-----|---------|-----------|
| Tasa de No-Show | No-shows / Total citas | < 5% (meta) |
| Retencion Nuevos Clientes | Nuevos que regresan (90d) / Total nuevos | 50%+ |
| Retencion Existentes | Existentes que regresan / Total existentes | 85%+ |
| Frecuencia de Visita | Total visitas / Clientes unicos | 4.88/ano promedio, 7-8 meta |
| Tasa de Pre-booking | Agendan siguiente cita / Total | 60%+ |

#### Reportes Disponibles

1. **Dashboard Diario** (vista `v_citas_dashboard_dia`): citas, revenue, no-shows, walk-ins, canales
2. **Reporte Semanal de Profesional**: servicios, revenue, comisiones, retencion
3. **Reporte Mensual de Negocio**: revenue total, ocupacion, top servicios, top profesionales
4. **Comisiones del Periodo** (vista `v_citas_comisiones_mes`): bruto, backbar, neto, propinas
5. **Rentabilidad por Servicio** (vista `v_citas_rentabilidad_servicio`): revenue, costos, margen, revenue/minuto
6. **Analisis de No-Shows**: lista de clientes, frecuencia, valor perdido
7. **Canales de Reserva**: distribucion WhatsApp/Presencial/Web/Telefono

### Fases de Implementacion

**Fase 1 (MVP):**
- Catalogo de servicios con duraciones
- Profesionales con horarios y bloqueos
- Agenda por profesional (SfCalendar)
- Reserva de citas (estados basicos)
- Checkout con facturacion (module_bus)
- Recordatorios automaticos (24h)

**Fase 2:**
- Walk-in + cola de espera
- Comisiones (modelo basico: porcentaje fijo)
- Reportes basicos (ocupacion, revenue, no-shows)
- Gift cards
- Tracking de consumibles/backbar

**Fase 3:**
- Multi-canal completo (WhatsApp bot, Telegram bot)
- Comisiones escalonadas e hibridas
- Membresias y paquetes prepagados
- Double-booking inteligente
- Reportes avanzados y KPIs
- Alquiler de silla
- Liquidacion periodica integrada con RRHH

### Software de Referencia

| App | Patron Adoptado |
|-----|-----------------|
| **Fresha** | Columnas por profesional, drag-drop, waitlist integrada, calendar limpio |
| **Vagaro** (Aura UI) | Multiple vistas (team/day/week), color coding, "Minimise Gaps" |
| **Mangomint** | Single-screen calendar + checkout, sin cambio de pantalla para cobrar |
| **Booksy** | Simplicity-first mobile, marketplace para captar clientes |
| **Square Appointments** | Filtros por servicio/staff, iconos de atributos en citas |
| **Zenoti** | Focus mode (hover destaca, otras se atenuan), cards responsivas |

---

## App Flutter — Arquitectura Multi-Flavor

El modulo Citas/Belleza se implementa dentro del mismo repositorio Flutter que PILAR ERP usando **Flutter Flavors**: un unico codebase produce tres apps independientes. Ver `docs/core/estructura-proyecto.md` para el arbol completo de archivos.

### Los Tres Flavors

| Flavor | App | Bundle ID | Usuarios | Plataformas |
|--------|-----|-----------|----------|-------------|
| `erp` | PILAR ERP | `com.pilar.erp` | Staff ERP completo | Web + iOS + Android + Desktop |
| `salon` | PILAR Salon | `com.pilar.salon` | Admin salon + Empleados | iOS + Android |
| `cliente` | *(nombre del salon)* | `com.pilar.cliente` | Clientes del salon | iOS + Android |

El modulo `citas_salon/` dentro de `features/` es visible en los flavors `salon` y `cliente`. El flavor `erp` puede acceder al modulo Citas desde la navegacion ERP completa.

### FlavorConfig

```dart
enum AppFlavor { erp, salon, cliente }

class FlavorConfig {
  final AppFlavor flavor;
  final String appName;
  final String bundleId;
  final String? salonSlug;    // Identifica el salon para white-label

  static FlavorConfig? _instance;
  static FlavorConfig get instance => _instance!;

  FlavorConfig._({required this.flavor, required this.appName,
                  required this.bundleId, this.salonSlug});

  static void setup({required AppFlavor flavor, String? salonSlug}) {
    _instance = FlavorConfig._(
      flavor:   flavor,
      appName:  switch (flavor) {
        AppFlavor.erp     => 'PILAR ERP',
        AppFlavor.salon   => 'PILAR Salon',
        AppFlavor.cliente => 'Mi Salon',     // Reemplazado por branding en runtime
      },
      bundleId: switch (flavor) {
        AppFlavor.erp     => 'com.pilar.erp',
        AppFlavor.salon   => 'com.pilar.salon',
        AppFlavor.cliente => 'com.pilar.cliente',
      },
      salonSlug: salonSlug,
    );
  }
}
```

### Entry Points

```dart
// main_salon.dart — Admin + Empleados
void main() {
  FlavorConfig.setup(flavor: AppFlavor.salon);
  runApp(ProviderScope(child: PilarApp(flavor: AppFlavor.salon)));
}

// main_cliente.dart — Clientes del salon
void main() {
  FlavorConfig.setup(flavor: AppFlavor.cliente, salonSlug: 'nails-queen-quito');
  runApp(ProviderScope(child: PilarApp(flavor: AppFlavor.cliente)));
}
```

### go_router — Redireccion por Rol

```dart
// Flavor salon: detecta rol y envia a home correcto
String? _redirectByRole(BuildContext ctx, GoRouterState state, WidgetRef ref) {
  if (state.matchedLocation != '/') return null;
  final role = ref.read(salonRoleProvider);
  return switch (role) {
    SalonUserRole.adminSalon => '/admin/dashboard',
    SalonUserRole.empleado   => '/empleado/mi-dia',
    SalonUserRole.cliente    => '/cliente/home',
  };
}
```

---

## Roles de Usuario y Auth

### Enum de Roles

```dart
enum SalonUserRole {
  adminSalon,   // Dueno o gerente del salon — acceso total
  empleado,     // Especialista — ve solo sus citas y comisiones
  cliente,      // Cliente — reserva citas, ve historial
}
```

### Metadata en Supabase Auth

Al crear o invitar un usuario se establece `raw_user_meta_data`:

```json
// Administrador del salon
{
  "salon_role":     "ADMIN_SALON",
  "empresa_id":     "uuid-del-salon",
  "profesional_id": null
}

// Empleado / Especialista
{
  "salon_role":     "EMPLEADO",
  "empresa_id":     "uuid-del-salon",
  "profesional_id": "uuid-en-citas_profesionales"
}

// Cliente del salon
{
  "salon_role":   "CLIENTE",
  "empresa_id":   "uuid-del-salon",
  "contacto_id":  "uuid-en-contactos"
}
```

### Funciones Helper en PostgreSQL

```sql
-- Rol del usuario actual
CREATE OR REPLACE FUNCTION private.get_salon_role()
RETURNS VARCHAR LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT (auth.jwt() -> 'user_metadata' ->> 'salon_role');
$$;

-- profesional_id del empleado autenticado
CREATE OR REPLACE FUNCTION private.get_profesional_id()
RETURNS UUID LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT (auth.jwt() -> 'user_metadata' ->> 'profesional_id')::UUID;
$$;

-- contacto_id del cliente autenticado
CREATE OR REPLACE FUNCTION private.get_contacto_id()
RETURNS UUID LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT (auth.jwt() -> 'user_metadata' ->> 'contacto_id')::UUID;
$$;
```

### Deteccion de Rol en Flutter

```dart
// features/citas_salon/shared/providers/salon_role_provider.dart
@riverpod
SalonUserRole salonRole(SalonRoleRef ref) {
  final user = ref.watch(authProvider).value;
  final role = user?.userMetadata?['salon_role'] as String?;
  return switch (role) {
    'ADMIN_SALON' => SalonUserRole.adminSalon,
    'EMPLEADO'    => SalonUserRole.empleado,
    'CLIENTE'     => SalonUserRole.cliente,
    _             => SalonUserRole.cliente,
  };
}
```

---

## RLS por Rol

### Politicas para la tabla `citas`

```sql
-- Admin: CRUD completo sobre todas las citas del salon
CREATE POLICY "admin_citas_all" ON citas
  FOR ALL TO authenticated
  USING (
    empresa_id = (SELECT private.get_empresa_id())
    AND private.get_salon_role() = 'ADMIN_SALON'
  );

-- Empleado: solo lectura de sus citas asignadas
CREATE POLICY "empleado_citas_propias" ON citas
  FOR SELECT TO authenticated
  USING (
    empresa_id     = (SELECT private.get_empresa_id())
    AND profesional_id = (SELECT private.get_profesional_id())
    AND private.get_salon_role() = 'EMPLEADO'
  );

-- Empleado: puede actualizar estado de sus citas (CHECK_IN, EN_PROGRESO, COMPLETADA)
CREATE POLICY "empleado_citas_update" ON citas
  FOR UPDATE TO authenticated
  USING (
    profesional_id = (SELECT private.get_profesional_id())
    AND private.get_salon_role() = 'EMPLEADO'
  )
  WITH CHECK (estado IN ('CHECK_IN', 'EN_PROGRESO', 'COMPLETADA', 'NO_SHOW'));

-- Cliente: solo sus propias citas
CREATE POLICY "cliente_citas_select" ON citas
  FOR SELECT TO authenticated
  USING (
    empresa_id  = (SELECT private.get_empresa_id())
    AND contacto_id = (SELECT private.get_contacto_id())
    AND private.get_salon_role() = 'CLIENTE'
  );

-- Cliente: puede crear nuevas reservas
CREATE POLICY "cliente_citas_insert" ON citas
  FOR INSERT TO authenticated
  WITH CHECK (
    empresa_id  = (SELECT private.get_empresa_id())
    AND contacto_id = (SELECT private.get_contacto_id())
    AND private.get_salon_role() = 'CLIENTE'
  );

-- Cliente: puede cancelar solo citas SOLICITADA o CONFIRMADA
CREATE POLICY "cliente_citas_cancel" ON citas
  FOR UPDATE TO authenticated
  USING (
    contacto_id = (SELECT private.get_contacto_id())
    AND estado IN ('SOLICITADA', 'CONFIRMADA')
    AND private.get_salon_role() = 'CLIENTE'
  )
  WITH CHECK (estado = 'CANCELADA');
```

### Politicas para `citas_servicios` (catalogo)

```sql
-- Admin: CRUD completo del catalogo
CREATE POLICY "admin_servicios_all" ON citas_servicios
  FOR ALL TO authenticated
  USING (
    empresa_id = (SELECT private.get_empresa_id())
    AND private.get_salon_role() = 'ADMIN_SALON'
  );

-- Empleado y Cliente: lectura de servicios disponibles online
CREATE POLICY "public_servicios_read" ON citas_servicios
  FOR SELECT TO authenticated
  USING (
    empresa_id = (SELECT private.get_empresa_id())
    AND disponible_online = true
  );
```

### Politicas para `citas_comisiones`

```sql
-- Admin: ve todas las comisiones del salon
CREATE POLICY "admin_comisiones_all" ON citas_comisiones
  FOR SELECT TO authenticated
  USING (
    empresa_id = (SELECT private.get_empresa_id())
    AND private.get_salon_role() = 'ADMIN_SALON'
  );

-- Empleado: solo sus propias comisiones
CREATE POLICY "empleado_comisiones_propias" ON citas_comisiones
  FOR SELECT TO authenticated
  USING (
    profesional_id = (SELECT private.get_profesional_id())
    AND private.get_salon_role() = 'EMPLEADO'
  );
```

---

## Tablas Adicionales (App Movil)

### salon_perfiles_publicos

Perfil y branding de cada salon, leido por el App Cliente para white-label y por los clientes para conocer el salon.

```sql
CREATE TABLE salon_perfiles_publicos (
  empresa_id          UUID PRIMARY KEY REFERENCES empresas(id),
  slug                VARCHAR(100) UNIQUE NOT NULL,     -- nails-queen-quito
  nombre_comercial    VARCHAR(200) NOT NULL,
  descripcion         TEXT,
  slogan              VARCHAR(200),
  -- Branding white-label (App Cliente)
  logo_url            TEXT,                             -- Supabase Storage
  color_primario      VARCHAR(7)  DEFAULT '#6750A4',    -- Material seed color (hex)
  color_secundario    VARCHAR(7)  DEFAULT '#625B71',
  fuente_preferida    VARCHAR(50) DEFAULT 'Inter',
  -- Ubicacion y contacto
  direccion           TEXT,
  ciudad              VARCHAR(100),
  provincia           VARCHAR(100),
  coordenadas         GEOGRAPHY(POINT),                 -- PostGIS para busqueda cercana
  whatsapp            VARCHAR(20),
  instagram           VARCHAR(100),
  sitio_web           TEXT,
  horario_texto       TEXT,                             -- "Lun-Sab 9:00-19:00"
  -- Metricas (actualizadas por trigger desde citas.calificacion)
  rating_promedio     DECIMAL(3,2) DEFAULT 0,
  total_resenas       INTEGER DEFAULT 0,
  -- Categorias ofrecidas
  categorias          TEXT[] DEFAULT '{}',              -- ['UÑAS','CABELLO','CEJAS']
  -- Control SaaS
  visible_directorio  BOOLEAN DEFAULT true,
  verificado          BOOLEAN DEFAULT false,
  plan_activo         VARCHAR(20) DEFAULT 'FREE',       -- FREE | PROFESSIONAL | ENTERPRISE
  created_at          TIMESTAMPTZ DEFAULT NOW(),
  updated_at          TIMESTAMPTZ DEFAULT NOW()
);

-- Indices
CREATE INDEX idx_salon_perfiles_ciudad
  ON salon_perfiles_publicos(ciudad) WHERE visible_directorio = true;
CREATE INDEX idx_salon_perfiles_geo
  ON salon_perfiles_publicos USING GIST(coordenadas);
CREATE INDEX idx_salon_perfiles_categorias
  ON salon_perfiles_publicos USING GIN(categorias);

-- RLS
ALTER TABLE salon_perfiles_publicos ENABLE ROW LEVEL SECURITY;

-- Admin del salon edita su propio perfil
CREATE POLICY "admin_perfil_salon" ON salon_perfiles_publicos
  FOR ALL TO authenticated
  USING (
    empresa_id = (SELECT private.get_empresa_id())
    AND private.get_salon_role() = 'ADMIN_SALON'
  );

-- Cualquier usuario autenticado lee perfiles publicos
CREATE POLICY "lectura_publica_perfiles" ON salon_perfiles_publicos
  FOR SELECT TO authenticated
  USING (visible_directorio = true);
```

### device_tokens

Tokens FCM para push notifications en iOS y Android.

```sql
CREATE TABLE device_tokens (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  empresa_id    UUID REFERENCES empresas(id),
  token         TEXT NOT NULL,
  plataforma    VARCHAR(10) NOT NULL CHECK (plataforma IN ('ios', 'android')),
  flavor        VARCHAR(10) NOT NULL CHECK (flavor IN ('erp', 'salon', 'cliente')),
  activo        BOOLEAN DEFAULT true,
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  updated_at    TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (user_id, token)
);

CREATE INDEX idx_device_tokens_user ON device_tokens(user_id) WHERE activo = true;

ALTER TABLE device_tokens ENABLE ROW LEVEL SECURITY;

-- Cada usuario gestiona solo sus propios tokens
CREATE POLICY "user_own_tokens" ON device_tokens
  FOR ALL TO authenticated
  USING (user_id = auth.uid());
```

---

## White-label (App Cliente)

El App Cliente carga el branding del salon al iniciar sesion y aplica logo y colores dinamicamente:

```dart
// features/citas_salon/shared/providers/salon_branding_provider.dart
@riverpod
Future<SalonBranding> salonBranding(SalonBrandingRef ref) async {
  final slug = FlavorConfig.instance.salonSlug ?? 'default';
  final data = await supabase
      .from('salon_perfiles_publicos')
      .select('nombre_comercial, logo_url, color_primario, color_secundario, slogan')
      .eq('slug', slug)
      .single();
  return SalonBranding.fromJson(data);
}

// app.dart — aplica tema dinamico con colores del salon
@override
Widget build(BuildContext context, WidgetRef ref) {
  final branding = ref.watch(salonBrandingProvider);
  return branding.when(
    data: (b) => FluentApp.router(
      title: b.nombreComercial,
      theme: FluentThemeData(
        brightness: Brightness.light,
        accentColor: Color(int.parse(b.colorPrimario.replaceFirst('#', ''), radix: 16) + 0xFF000000).toAccentColor(),
      ),
      routerConfig: clienteRouter,
    ),
    loading: (_)  => const SplashScreen(),
    error:   (_, __) => const SplashScreen(),
  );
}
```

---

## Navegacion Bottom por Rol

```dart
// Flavor salon — NavigationBar adaptativo segun rol
Widget _buildNav(SalonUserRole role) => switch (role) {
  SalonUserRole.adminSalon => NavigationBar(destinations: [
    NavigationDestination(icon: Icon(Icons.calendar_today), label: 'Agenda'),
    NavigationDestination(icon: Icon(Icons.people),         label: 'Clientes'),
    NavigationDestination(icon: Icon(Icons.group),          label: 'Equipo'),
    NavigationDestination(icon: Icon(Icons.bar_chart),      label: 'Reportes'),
    NavigationDestination(icon: Icon(Icons.settings),       label: 'Config'),
  ]),
  SalonUserRole.empleado => NavigationBar(destinations: [
    NavigationDestination(icon: Icon(Icons.today),          label: 'Mi Dia'),
    NavigationDestination(icon: Icon(Icons.login),          label: 'Check-in'),
    NavigationDestination(icon: Icon(Icons.payments),       label: 'Comisiones'),
    NavigationDestination(icon: Icon(Icons.calendar_month), label: 'Mi Agenda'),
  ]),
  SalonUserRole.cliente => NavigationBar(destinations: [
    NavigationDestination(icon: Icon(Icons.home),           label: 'Inicio'),
    NavigationDestination(icon: Icon(Icons.add_circle),     label: 'Reservar'),
    NavigationDestination(icon: Icon(Icons.event_note),     label: 'Mis Citas'),
    NavigationDestination(icon: Icon(Icons.person),         label: 'Perfil'),
  ]),
};
```

---

## Edge Functions Adicionales (App Movil)

| Funcion | Descripcion |
|---------|-------------|
| `booking-availability/index.ts` | Expone `citas_obtener_disponibilidad()` sin autenticacion de staff — usada por App Cliente |
| `salon-reminders/index.ts` | Cron diario: envia recordatorios 24h y 2h antes via WhatsApp/email/push |
| `push-notify/index.ts` | Envia notificacion push via FCM a tokens registrados en `device_tokens` |

