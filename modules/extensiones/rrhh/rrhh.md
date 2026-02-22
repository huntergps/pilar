# Módulo RRHH (Recursos Humanos, Nómina y Asistencia)


Este es un modulo unificado que integra la gestion de personal, contratos, asistencia,
nomina y su integracion con contabilidad. La asistencia es un sub-modulo de RRHH.

```
features/rrhh/
  ├── screens/
  │   ├── employees/
  │   │   ├── employees_screen.dart           # CRUD empleados (SfDataGrid)
  │   │   ├── employee_form_screen.dart       # Formulario empleado completo
  │   │   ├── employee_profile_screen.dart    # Perfil: historial, contratos, posiciones, docs
  │   │   ├── employee_history_screen.dart    # Timeline: cambios cargo, sueldo, depto, etc.
  │   │   └── employee_documents_screen.dart  # Documentos del empleado (contrato, cedula, etc.)
  │   ├── organization/
  │   │   ├── departments_screen.dart         # CRUD departamentos/areas
  │   │   ├── positions_screen.dart           # CRUD cargos/posiciones
  │   │   ├── org_chart_screen.dart           # Organigrama visual
  │   │   └── cost_centers_screen.dart        # Centros de costo (para contabilidad)
  │   ├── contracts/
  │   │   ├── contracts_screen.dart           # Contratos laborales (SfDataGrid)
  │   │   ├── contract_form_screen.dart       # Crear/renovar contrato
  │   │   └── contract_renewals_screen.dart   # Vencimientos proximos + renovacion
  │   ├── attendance/
  │   │   ├── attendance_screen.dart          # Registro entrada/salida (multi-metodo)
  │   │   ├── attendance_report_screen.dart   # Reporte de asistencia (SfDataGrid)
  │   │   ├── shifts_screen.dart              # CRUD turnos de la empresa
  │   │   ├── shift_detail_screen.dart        # Detalle turno con horarios por dia
  │   │   ├── rotation_patterns_screen.dart   # Patrones de rotacion (5x2, 4x2, 7x7)
  │   │   ├── schedule_screen.dart            # Planificacion de horarios por empleado/grupo
  │   │   ├── schedule_calendar_screen.dart   # Calendario visual de asignaciones (SfCalendar)
  │   │   ├── overtime_screen.dart            # Horas extras (calculo y aprobacion)
  │   │   ├── overtime_approval_screen.dart   # Aprobacion masiva de horas extras
  │   │   ├── holidays_screen.dart            # Feriados nacionales + locales
  │   │   ├── attendance_summary_screen.dart  # Resumen mensual: horas normales/extras/faltas
  │   │   └── biometric_devices_screen.dart   # CRUD dispositivos biometricos
  │   ├── leave/
  │   │   ├── leave_request_screen.dart       # Solicitud de permiso/ausencia
  │   │   ├── leave_approval_screen.dart      # Aprobacion de permisos (jefe directo)
  │   │   ├── leave_calendar_screen.dart      # Calendario de ausencias del equipo
  │   │   ├── vacation_screen.dart            # Solicitud y liquidacion vacaciones
  │   │   └── vacation_balance_screen.dart    # Saldo de dias disponibles por empleado
  │   ├── payroll/
  │   │   ├── payroll_screen.dart             # Generacion rol de pagos mensual
  │   │   ├── payroll_detail_screen.dart      # Detalle individual del rol
  │   │   ├── payroll_preview_screen.dart     # Pre-calculo antes de aprobar
  │   │   ├── payslip_screen.dart             # Rol individual PDF (vista + impresion + envio)
  │   │   ├── payslip_bulk_send_screen.dart   # Envio masivo de roles a todos los empleados
  │   │   ├── thirteenth_salary_screen.dart   # Calculo y pago decimo tercero
  │   │   ├── fourteenth_salary_screen.dart   # Calculo y pago decimo cuarto
  │   │   ├── profit_sharing_screen.dart      # Calculo y pago utilidades (15%)
  │   │   ├── settlements_screen.dart         # Liquidaciones (acta de finiquito)
  │   │   ├── salary_history_screen.dart      # Historial de cambios salariales
  │   │   └── payroll_reports_screen.dart     # RDEP, Planillas IESS, F107
  │   ├── loans/
  │   │   ├── loans_screen.dart               # Listado prestamos/anticipos (SfDataGrid)
  │   │   ├── loan_form_screen.dart           # Crear prestamo/anticipo con cuotas
  │   │   ├── loan_detail_screen.dart         # Detalle: tabla amortizacion, cuotas pagadas
  │   │   ├── loan_approval_screen.dart       # Aprobacion de prestamos (jefe/gerencia)
  │   │   └── store_purchases_screen.dart     # Compras del empleado en almacen pendientes
  │   ├── bank_payments/
  │   │   ├── bank_payment_screen.dart        # Generacion archivo bancario para pago masivo
  │   │   ├── bank_payment_preview_screen.dart # Vista previa: empleados, montos, bancos
  │   │   ├── bank_format_config_screen.dart  # Configuracion de formatos por banco
  │   │   └── bank_payment_history_screen.dart # Historial de archivos generados
  │   └── biometric/
  │       ├── biometric_enroll_screen.dart    # Enrolamiento de empleados en dispositivos
  │       └── biometric_kiosk_screen.dart     # Modo kiosko para tablet/PC
  ├── providers/
  │   ├── employee_provider.dart
  │   ├── contract_provider.dart
  │   ├── department_provider.dart
  │   ├── attendance_provider.dart
  │   ├── schedule_provider.dart
  │   ├── overtime_provider.dart
  │   ├── leave_provider.dart
  │   ├── payroll_provider.dart
  │   ├── loan_provider.dart              # Prestamos, anticipos, compras almacen
  │   ├── bank_payment_provider.dart      # Generacion archivos bancarios
  │   ├── iess_provider.dart
  │   └── biometric_provider.dart
  ├── services/
  │   ├── schedule_engine.dart            # Motor de calculo de horarios y rotaciones
  │   ├── overtime_calculator.dart        # Calculo horas extras segun normativa Ecuador
  │   ├── payroll_calculator.dart         # Motor de calculo de nomina
  │   ├── payslip_pdf_service.dart        # Genera PDF del rol individual (syncfusion_flutter_pdf)
  │   ├── bank_file_generator.dart        # Genera archivos bancarios (patron adaptador por banco)
  │   ├── biometric_service.dart          # Capa abstracta para dispositivos biometricos
  │   ├── zkteco_adapter.dart             # Adaptador ZKTeco (Push SDK / REST API)
  │   ├── generic_api_adapter.dart        # Adaptador generico HTTP para otros dispositivos
  │   └── local_biometric_service.dart    # Huella/FaceID nativo del celular/tablet (local_auth)
  └── models/
```

**Modelo de Datos - RRHH**

```sql
-- ══════════════════════════════════════════════════════════════════
-- ESTRUCTURA ORGANIZACIONAL
-- ══════════════════════════════════════════════════════════════════

departamentos
  id              UUID PK
  empresa_id      UUID FK -> empresas
  codigo          VARCHAR(20) NOT NULL
  nombre          VARCHAR(100) NOT NULL       -- 'Ventas', 'Produccion', 'Administracion'
  departamento_padre_id UUID FK -> departamentos  -- Para jerarquia/organigrama
  responsable_id  UUID FK -> empleados        -- Jefe del departamento
  centro_costo_id UUID FK -> cuentas_contables -- Cuenta contable para gastos del depto
  activo          BOOLEAN DEFAULT true
  UNIQUE(empresa_id, codigo)

cargos
  id              UUID PK
  empresa_id      UUID FK -> empresas
  codigo          VARCHAR(20) NOT NULL
  nombre          VARCHAR(100) NOT NULL       -- 'Gerente General', 'Vendedor Senior'
  departamento_id UUID FK -> departamentos
  nivel           INTEGER DEFAULT 1           -- Nivel jerarquico (para organigrama)
  sueldo_minimo   DECIMAL(14,2)               -- Rango salarial del cargo
  sueldo_maximo   DECIMAL(14,2)
  descripcion     TEXT                        -- Funciones del cargo
  activo          BOOLEAN DEFAULT true
  UNIQUE(empresa_id, codigo)

-- ══════════════════════════════════════════════════════════════════
-- EMPLEADOS
-- ══════════════════════════════════════════════════════════════════

empleados
  id              UUID PK
  empresa_id      UUID FK -> empresas
  user_id         UUID FK -> auth.users       -- Vinculo con usuario del sistema (opcional)
  contacto_id     UUID FK -> contactos        -- Datos personales (nombre, cedula, direccion, etc.)
  codigo_empleado VARCHAR(20) NOT NULL
  establecimiento_id UUID FK -> establecimientos
  -- Posicion actual
  departamento_id UUID FK -> departamentos
  cargo_id        UUID FK -> cargos
  jefe_directo_id UUID FK -> empleados        -- Para aprobaciones y organigrama
  -- Datos laborales
  fecha_ingreso   DATE NOT NULL
  fecha_salida    DATE                        -- NULL si activo
  sueldo          DECIMAL(14,2) NOT NULL      -- Sueldo vigente
  -- IESS
  numero_afiliacion VARCHAR(20)
  tipo_afiliacion VARCHAR(20) DEFAULT 'DEPENDENCIA'
  -- Impuesto a la Renta
  proyeccion_gastos DECIMAL(14,2) DEFAULT 0
  cargas_familiares INTEGER DEFAULT 0
  -- Cuenta bancaria para pago
  banco           VARCHAR(100)
  tipo_cuenta     VARCHAR(20)                 -- AHORROS, CORRIENTE
  numero_cuenta   VARCHAR(30)
  -- Fondos de reserva
  fondos_reserva_acumular BOOLEAN DEFAULT false
  -- Bonos fijos (se suman al rol cada mes)
  bono_fijo       DECIMAL(14,2) DEFAULT 0     -- Bono fijo mensual (alimentacion, transporte, etc.)
  bono_descripcion VARCHAR(200)               -- Descripcion del bono
  -- Estado
  activo          BOOLEAN DEFAULT true
  motivo_salida   VARCHAR(50)
  UNIQUE(empresa_id, codigo_empleado)

-- ══════════════════════════════════════════════════════════════════
-- CONTRATOS LABORALES (historial completo)
-- ══════════════════════════════════════════════════════════════════

contratos
  id              UUID PK
  empresa_id      UUID FK -> empresas
  empleado_id     UUID FK -> empleados
  numero_contrato VARCHAR(20)
  tipo            VARCHAR(20) NOT NULL
    -- INDEFINIDO: sin fecha fin (el mas comun en Ecuador)
    -- FIJO: con fecha fin determinada
    -- EVENTUAL: por obra cierta o necesidad
    -- PRUEBA: periodo de prueba (max 90 dias)
    -- PARCIAL: jornada parcial (menos de 8h)
    -- APRENDIZAJE: contrato de aprendizaje
  fecha_inicio    DATE NOT NULL
  fecha_fin       DATE                        -- NULL si indefinido
  sueldo          DECIMAL(14,2) NOT NULL      -- Sueldo pactado en el contrato
  jornada         VARCHAR(20) DEFAULT 'COMPLETA'
  horas_semanales INTEGER DEFAULT 40          -- Ecuador: max 40h semanales
  periodo_prueba_dias INTEGER DEFAULT 90
  -- Renovacion
  renovacion_de   UUID FK -> contratos        -- Contrato anterior si es renovacion
  -- Documentos
  documento_url   TEXT                        -- Contrato firmado (Supabase Storage)
  -- Estado
  estado          VARCHAR(20) DEFAULT 'VIGENTE'
    -- VIGENTE, VENCIDO, TERMINADO, RENOVADO
  activo          BOOLEAN DEFAULT true
  created_at      TIMESTAMPTZ DEFAULT now()

-- ══════════════════════════════════════════════════════════════════
-- HISTORIAL DE CAMBIOS DEL EMPLEADO (posiciones, salarios, deptos)
-- ══════════════════════════════════════════════════════════════════

historial_empleado
  id              UUID PK
  empresa_id      UUID FK -> empresas
  empleado_id     UUID FK -> empleados
  fecha_cambio    DATE NOT NULL
  tipo_cambio     VARCHAR(30) NOT NULL
    -- INGRESO, CAMBIO_CARGO, CAMBIO_DEPARTAMENTO, CAMBIO_SUELDO,
    -- CAMBIO_ESTABLECIMIENTO, PROMOCION, AMONESTACION, RECONOCIMIENTO
  -- Valores anteriores y nuevos
  campo           VARCHAR(50)                 -- 'cargo_id', 'sueldo', 'departamento_id'
  valor_anterior  TEXT
  valor_nuevo     TEXT
  motivo          TEXT
  documento_url   TEXT                        -- Accion de personal firmada
  registrado_por  UUID FK -> auth.users
  created_at      TIMESTAMPTZ DEFAULT now()

roles_pago  -- Cabecera del rol de pagos mensual
  id              UUID PK
  empresa_id      UUID FK -> empresas
  anio            INTEGER NOT NULL
  mes             INTEGER NOT NULL       -- 1-12
  fecha_generacion DATE
  estado          VARCHAR(20) DEFAULT 'BORRADOR'
    -- BORRADOR, APROBADO, PAGADO
  total_ingresos  DECIMAL(14,2) DEFAULT 0
  total_egresos   DECIMAL(14,2) DEFAULT 0
  total_neto      DECIMAL(14,2) DEFAULT 0
  total_aporte_patronal DECIMAL(14,2) DEFAULT 0
  aprobado_por    UUID FK -> auth.users
  UNIQUE(empresa_id, anio, mes)

rol_detalle  -- Detalle por empleado
  id              UUID PK
  rol_id          UUID FK -> roles_pago
  empleado_id     UUID FK -> empleados
  dias_trabajados INTEGER DEFAULT 30
  -- INGRESOS
  sueldo_base     DECIMAL(14,2)
  horas_extras_50 DECIMAL(14,2) DEFAULT 0   -- Suplementarias (+50%)
  horas_extras_100 DECIMAL(14,2) DEFAULT 0  -- Extraordinarias (+100%)
  comisiones      DECIMAL(14,2) DEFAULT 0
  bonificaciones  DECIMAL(14,2) DEFAULT 0
  otros_ingresos  DECIMAL(14,2) DEFAULT 0
  total_ingresos  DECIMAL(14,2)
  -- EGRESOS
  aporte_personal_iess DECIMAL(14,2)    -- 9.45%
  impuesto_renta  DECIMAL(14,2) DEFAULT 0  -- Retencion mensual
  prestamos       DECIMAL(14,2) DEFAULT 0    -- Cuotas de prestamos descontadas este mes
  anticipos       DECIMAL(14,2) DEFAULT 0    -- Anticipos de sueldo descontados
  compras_almacen DECIMAL(14,2) DEFAULT 0    -- Compras del empleado en almacen de la empresa
  otros_egresos   DECIMAL(14,2) DEFAULT 0
  total_egresos   DECIMAL(14,2)
  -- NETO
  neto_a_pagar    DECIMAL(14,2)
  -- PATRONAL (no descuenta al empleado)
  aporte_patronal_iess DECIMAL(14,2)    -- 11.15%
  fondos_reserva  DECIMAL(14,2)         -- 8.33% (si aplica)
  decimo_tercero_provision DECIMAL(14,2) -- Provision mensual
  decimo_cuarto_provision DECIMAL(14,2)  -- Provision mensual
  vacaciones_provision DECIMAL(14,2)     -- Provision mensual

provisiones  -- Acumulado de provisiones por empleado
  id              UUID PK
  empresa_id      UUID FK -> empresas
  empleado_id     UUID FK -> empleados
  anio            INTEGER NOT NULL
  tipo            VARCHAR(20) NOT NULL
    -- DECIMO_TERCERO, DECIMO_CUARTO, VACACIONES
  monto_acumulado DECIMAL(14,2) DEFAULT 0
  monto_pagado    DECIMAL(14,2) DEFAULT 0
  saldo           DECIMAL(14,2) DEFAULT 0
  UNIQUE(empresa_id, empleado_id, anio, tipo)

-- ══════════════════════════════════════════════════════════════════
-- PRESTAMOS Y ANTICIPOS A EMPLEADOS
-- ══════════════════════════════════════════════════════════════════

prestamos_empleado
  id              UUID PK
  empresa_id      UUID FK -> empresas
  empleado_id     UUID FK -> empleados
  numero          VARCHAR(20)               -- Numero secuencial del prestamo
  tipo            VARCHAR(20) NOT NULL
    -- PRESTAMO: prestamo de dinero con cuotas mensuales
    -- ANTICIPO: anticipo de sueldo (1-2 cuotas, sin interes)
    -- COMPRA_ALMACEN: compra del empleado en el almacen de la empresa
  -- Montos
  monto_total     DECIMAL(14,2) NOT NULL
  tasa_interes    DECIMAL(5,2) DEFAULT 0    -- % anual (0 = sin interes, comun en anticipos)
  cuotas_total    INTEGER DEFAULT 1         -- Numero de cuotas pactadas
  monto_cuota     DECIMAL(14,2) NOT NULL    -- Valor de cada cuota mensual
  cuotas_pagadas  INTEGER DEFAULT 0
  saldo_pendiente DECIMAL(14,2) NOT NULL    -- Se actualiza con cada descuento
  -- Fechas
  fecha_solicitud DATE NOT NULL
  fecha_aprobacion DATE
  fecha_primer_descuento DATE              -- Mes desde el cual se descuenta en rol
  fecha_ultimo_descuento DATE              -- Calculado: primer_descuento + cuotas - 1
  -- Aprobacion
  solicitado_por  UUID FK -> auth.users     -- Empleado o RRHH
  aprobado_por    UUID FK -> auth.users     -- Jefe directo o gerencia
  -- Referencia (para COMPRA_ALMACEN)
  factura_id      UUID FK -> facturas       -- Factura de la compra en el almacen (NULL si no aplica)
  -- Observaciones
  motivo          TEXT                      -- 'Emergencia medica', 'Compra electrodomestico', etc.
  notas           TEXT
  -- Estado
  estado          VARCHAR(20) DEFAULT 'PENDIENTE'
    -- PENDIENTE: esperando aprobacion
    -- APROBADO: aprobado, pendiente de desembolso/primer descuento
    -- ACTIVO: en curso, descontando cuotas del rol
    -- PAGADO: todas las cuotas pagadas
    -- CANCELADO: cancelado antes de desembolso
  created_at      TIMESTAMPTZ DEFAULT now()
  UNIQUE(empresa_id, numero)

-- Detalle de cuotas pagadas (historial de descuentos)
prestamo_cuotas
  id              UUID PK
  empresa_id      UUID FK -> empresas
  prestamo_id     UUID FK -> prestamos_empleado
  numero_cuota    INTEGER NOT NULL          -- 1, 2, 3, ...
  monto_capital   DECIMAL(14,2) NOT NULL
  monto_interes   DECIMAL(14,2) DEFAULT 0
  monto_total     DECIMAL(14,2) NOT NULL    -- capital + interes
  -- Vinculo con nomina
  rol_detalle_id  UUID FK -> rol_detalle    -- Rol donde se desconto
  mes_descuento   INTEGER NOT NULL          -- 1-12
  anio_descuento  INTEGER NOT NULL
  fecha_descuento DATE
  estado          VARCHAR(20) DEFAULT 'PENDIENTE'
    -- PENDIENTE: cuota futura, aun no descontada
    -- DESCONTADO: ya se desconto del rol
    -- CONDONADO: perdonada por la empresa
  UNIQUE(prestamo_id, numero_cuota)

-- ══════════════════════════════════════════════════════════════════
-- COMPRAS DE EMPLEADOS EN EL ALMACEN (para descuento a rol)
-- Vincula Ventas/POS con RRHH para descuento en nomina
-- ══════════════════════════════════════════════════════════════════

compras_empleado_almacen
  id              UUID PK
  empresa_id      UUID FK -> empresas
  empleado_id     UUID FK -> empleados
  factura_id      UUID FK -> facturas       -- Factura POS/Ventas al empleado
  fecha_compra    DATE NOT NULL
  monto_total     DECIMAL(14,2) NOT NULL    -- Total de la factura
  -- Condicion de pago
  forma_pago      VARCHAR(20) NOT NULL
    -- CONTADO: empleado pago en caja (no afecta rol)
    -- DESCUENTO_ROL: se descuenta del proximo rol de pagos
    -- CUOTAS_ROL: se descuenta en N cuotas mensuales
  cuotas          INTEGER DEFAULT 1         -- Numero de cuotas si es CUOTAS_ROL
  -- Vinculo con prestamo (se crea automaticamente si es DESCUENTO_ROL o CUOTAS_ROL)
  prestamo_id     UUID FK -> prestamos_empleado  -- Prestamo generado tipo COMPRA_ALMACEN
  -- Estado
  estado          VARCHAR(20) DEFAULT 'PENDIENTE'
    -- PENDIENTE: pendiente de descuento
    -- EN_DESCUENTO: se esta descontando (cuotas activas)
    -- DESCONTADO: totalmente descontado del rol
    -- PAGADO_CONTADO: pagado en caja
  notas           TEXT
  registrado_por  UUID FK -> auth.users
  created_at      TIMESTAMPTZ DEFAULT now()

-- ══════════════════════════════════════════════════════════════════
-- ARCHIVOS BANCARIOS PARA PAGO MASIVO DE NOMINA
-- ══════════════════════════════════════════════════════════════════

formatos_banco
  id              UUID PK
  empresa_id      UUID FK -> empresas       -- NULL = formato global del sistema
  banco_nombre    VARCHAR(100) NOT NULL     -- 'Banco Pichincha', 'Banco Guayaquil', etc.
  banco_codigo    VARCHAR(10) NOT NULL      -- Codigo interbancario (BP, BG, PRD, INT, etc.)
  formato         VARCHAR(20) NOT NULL      -- CSV, TXT, XLSX
  separador       VARCHAR(5) DEFAULT ','    -- Separador de campos (,  ;  |  TAB)
  encoding        VARCHAR(20) DEFAULT 'UTF-8' -- UTF-8, ISO-8859-1, Windows-1252
  -- Definicion de columnas (configurable)
  columnas        JSONB NOT NULL            -- Array de {posicion, campo, formato, longitud}
    -- Ejemplo Pichincha: [
    --   {"pos":1, "campo":"tipo_pago", "valor_fijo":"CTA"},
    --   {"pos":2, "campo":"tipo_cuenta", "map":{"AHORROS":"AHO","CORRIENTE":"CTE"}},
    --   {"pos":3, "campo":"numero_cuenta"},
    --   {"pos":4, "campo":"cedula"},
    --   {"pos":5, "campo":"nombre_empleado", "longitud":40},
    --   {"pos":6, "campo":"monto", "decimales":2},
    --   {"pos":7, "campo":"referencia"}
    -- ]
  tiene_cabecera  BOOLEAN DEFAULT false     -- Si el archivo lleva fila de cabecera
  cabecera        JSONB                     -- Definicion de cabecera si aplica
  tiene_totales   BOOLEAN DEFAULT false     -- Si lleva fila de totales al final
  totales         JSONB                     -- Definicion de fila de totales
  -- Plantilla
  activo          BOOLEAN DEFAULT true
  notas           TEXT
  UNIQUE(empresa_id, banco_codigo)

archivos_pago_nomina
  id              UUID PK
  empresa_id      UUID FK -> empresas
  rol_id          UUID FK -> roles_pago     -- Rol de pagos que se esta pagando
  formato_banco_id UUID FK -> formatos_banco
  -- Archivo generado
  nombre_archivo  VARCHAR(200) NOT NULL     -- 'pago_nomina_2026_01_pichincha.csv'
  archivo_url     TEXT                      -- URL en Supabase Storage
  -- Totales
  total_empleados INTEGER NOT NULL
  total_monto     DECIMAL(14,2) NOT NULL
  -- Estado
  estado          VARCHAR(20) DEFAULT 'GENERADO'
    -- GENERADO: archivo creado, listo para descargar
    -- ENVIADO: subido al portal del banco
    -- PROCESADO: banco confirmo procesamiento
    -- ERROR: banco reporto errores
  generado_por    UUID FK -> auth.users
  fecha_generacion TIMESTAMPTZ DEFAULT now()
  notas           TEXT

-- ══════════════════════════════════════════════════════════════════
-- ENVIOS DE ROL DE PAGO (historial de envio a empleados)
-- ══════════════════════════════════════════════════════════════════

envios_rol_pago
  id              UUID PK
  empresa_id      UUID FK -> empresas
  rol_detalle_id  UUID FK -> rol_detalle    -- Detalle del empleado en el rol
  empleado_id     UUID FK -> empleados
  -- Canales
  canal           VARCHAR(20) NOT NULL      -- EMAIL, WHATSAPP, TELEGRAM
  destino         VARCHAR(200)              -- email, telefono, @username
  -- Contenido
  pdf_url         TEXT                      -- URL del PDF del rol individual
  -- Estado
  estado          VARCHAR(20) DEFAULT 'PENDIENTE'
    -- PENDIENTE, ENVIADO, ENTREGADO, FALLIDO
  fecha_envio     TIMESTAMPTZ
  error_detalle   TEXT                      -- Si fallo, razon del error
  created_at      TIMESTAMPTZ DEFAULT now()
```

**Rol de Pago Individual (PDF) y Envio Multi-canal**

```
╔══════════════════════════════════════════════════════════════════════════╗
║  ROL DE PAGO INDIVIDUAL - GENERACION PDF + ENVIO                       ║
╠══════════════════════════════════════════════════════════════════════════╣
║                                                                          ║
║  GENERACION DEL PDF (syncfusion_flutter_pdf / Edge Function)            ║
║  ┌────────────────────────────────────────────────────────────────┐     ║
║  │  PILAR ERP - Rol de Pagos Individual                          │     ║
║  │  Empresa: [nombre_empresa]         Periodo: Enero 2026        │     ║
║  │  RUC: [ruc]                        Fecha: 31/01/2026          │     ║
║  │  ─────────────────────────────────────────────────────────────│     ║
║  │  Empleado: Juan Perez              Cedula: 0912345678         │     ║
║  │  Cargo: Vendedor Senior            Depto: Ventas              │     ║
║  │  Fecha ingreso: 15/03/2020         Dias trab: 30              │     ║
║  │  ─────────────────────────────────────────────────────────────│     ║
║  │  INGRESOS                          EGRESOS                    │     ║
║  │  Sueldo base         $1,200.00     IESS personal    $113.40   │     ║
║  │  Horas extras 50%      $112.50     Impuesto renta     $0.00   │     ║
║  │  Horas extras 100%      $50.00     Prestamo cuota   $100.00   │     ║
║  │  Comisiones             $80.00     Anticipo           $50.00   │     ║
║  │  Bono fijo              $40.00     Compra almacen     $35.00   │     ║
║  │  ─────────────────────────────────────────────────────────────│     ║
║  │  Total ingresos     $1,482.50     Total egresos     $298.40   │     ║
║  │  ═════════════════════════════════════════════════════════════│     ║
║  │  NETO A RECIBIR:                              $1,184.10      │     ║
║  │  ─────────────────────────────────────────────────────────────│     ║
║  │  PROVISIONES PATRONALES (informativo, no descuenta)           │     ║
║  │  IESS patronal: $133.80 | Fondos reserva: $99.96             │     ║
║  │  13ro: $100.00 | 14to: $40.17 | Vacaciones: $50.00           │     ║
║  │  ─────────────────────────────────────────────────────────────│     ║
║  │  Detalle prestamos activos:                                    │     ║
║  │  - Prestamo #001: cuota 3/12 ($100.00) - saldo $900.00       │     ║
║  │  - Anticipo #005: cuota 1/1 ($50.00) - saldo $0.00           │     ║
║  │  - Compra almacen Fact-001-001-123: 1/1 ($35.00) - saldo $0  │     ║
║  └────────────────────────────────────────────────────────────────┘     ║
║                                                                          ║
║  ENVIO MULTI-CANAL (usa misma infra que documentos electronicos)        ║
║  ┌─────────────────────────────────────────────────────────────┐        ║
║  │ Canal     │ Metodo                                          │        ║
║  │ EMAIL     │ Edge Function send-notification → Resend API    │        ║
║  │           │ Adjunta: PDF del rol individual                 │        ║
║  │ WHATSAPP  │ Edge Function send-notification → WA Cloud API  │        ║
║  │           │ Template con link seguro al PDF (URL temporal)  │        ║
║  │ TELEGRAM  │ Edge Function send-notification → Telegram Bot  │        ║
║  │           │ Envia PDF como documento adjunto                │        ║
║  └─────────────────────────────────────────────────────────────┘        ║
║                                                                          ║
║  FLUJO:                                                                  ║
║  1. RRHH genera rol mensual (calculate_payroll)                         ║
║  2. Revisa y aprueba el rol (estado: APROBADO)                          ║
║  3. Opcion A: Envio individual - selecciona empleado → genera PDF       ║
║     → elige canal(es) → envia                                           ║
║  4. Opcion B: Envio masivo - genera todos los PDFs → envia a cada       ║
║     empleado por su canal preferido (contacto.canal_notificacion)       ║
║  5. Se registra en envios_rol_pago con estado de entrega                ║
║                                                                          ║
║  IMPRESION: Desde payslip_screen.dart con package:printing              ║
║  → Impresion directa en impresora local o guardar PDF                   ║
║                                                                          ║
╚══════════════════════════════════════════════════════════════════════════╝
```

**Archivo Bancario para Pago Masivo de Nomina**

```
╔══════════════════════════════════════════════════════════════════════════╗
║  GENERACION DE ARCHIVOS BANCARIOS PARA PAGO DE NOMINA                  ║
╠══════════════════════════════════════════════════════════════════════════╣
║                                                                          ║
║  BANCOS PRINCIPALES DE ECUADOR (formatos pre-configurados):             ║
║  ┌────────────────────────────────────────────────────────────────┐     ║
║  │ Banco               │ Formato │ Separador │ Encoding          │     ║
║  │ Banco Pichincha      │ CSV     │ ,         │ UTF-8             │     ║
║  │ Banco Guayaquil      │ TXT     │ |         │ ISO-8859-1        │     ║
║  │ Produbanco           │ CSV     │ ;         │ Windows-1252      │     ║
║  │ Banco Internacional  │ TXT     │ TAB       │ UTF-8             │     ║
║  │ Banco Pacifico       │ CSV     │ ,         │ UTF-8             │     ║
║  │ Banco Bolivariano    │ TXT     │ |         │ ISO-8859-1        │     ║
║  │ Cooperativa JEP      │ CSV     │ ;         │ UTF-8             │     ║
║  │ Banco del Austro     │ CSV     │ ,         │ UTF-8             │     ║
║  │ (Personalizable)     │ *       │ *         │ *                 │     ║
║  └────────────────────────────────────────────────────────────────┘     ║
║                                                                          ║
║  ESTRUCTURA TIPICA DEL ARCHIVO:                                         ║
║  ┌─────────────────────────────────────────────────────────────┐        ║
║  │ [Cabecera opcional]                                          │        ║
║  │ Tipo,TipoCuenta,NroCuenta,Cedula,Nombre,Monto,Referencia   │        ║
║  │ CTA,AHO,2200012345,0912345678,JUAN PEREZ,1184.10,ROL-ENE26 │        ║
║  │ CTA,CTE,3300067890,0998765432,MARIA LOPEZ,980.50,ROL-ENE26 │        ║
║  │ ...                                                          │        ║
║  │ [Totales opcionales: registros, monto total]                 │        ║
║  └─────────────────────────────────────────────────────────────┘        ║
║                                                                          ║
║  FLUJO:                                                                  ║
║  1. Rol de pagos en estado APROBADO                                     ║
║  2. Ir a bank_payment_screen → seleccionar rol y banco destino          ║
║  3. Sistema agrupa empleados por banco (cada empleado tiene banco       ║
║     y cuenta en su ficha)                                                ║
║  4. Si empleados tienen cuentas en diferentes bancos:                   ║
║     → Genera UN archivo por cada banco                                  ║
║     → Ej: 15 en Pichincha, 8 en Guayaquil → 2 archivos                ║
║  5. Vista previa: muestra tabla con empleados, bancos, montos           ║
║  6. Confirmar → genera archivo(s) → guarda en Supabase Storage          ║
║  7. Descargar archivo(s) para subir al portal del banco                 ║
║  8. Registrar estado: ENVIADO → PROCESADO (manual por RRHH)            ║
║  9. Al marcar como PROCESADO → actualiza rol_pago.estado = PAGADO      ║
║     → genera asiento contable: Sueldos por pagar (D) / Banco (H)       ║
║                                                                          ║
║  FORMATO CONFIGURABLE POR BANCO (tabla formatos_banco):                 ║
║  - Cada banco tiene su definicion de columnas en JSONB                  ║
║  - El admin de RRHH puede personalizar formato, agregar bancos nuevos   ║
║  - Soporta: cabecera, detalle, totales, encoding especifico            ║
║  - Patron adaptador: BankFileGenerator → PichinchaFormat,               ║
║    GuayaquilFormat, GenericCSVFormat, etc.                               ║
║                                                                          ║
║  PAGO PARCIAL / BANCOS MULTIPLES:                                       ║
║  - Si un empleado no tiene cuenta bancaria → excluido del archivo       ║
║    (se paga manualmente: cheque o efectivo)                              ║
║  - Reporte de "empleados sin cuenta" para que RRHH gestione             ║
║                                                                          ║
╚══════════════════════════════════════════════════════════════════════════╝
```

**Prestamos, Anticipos y Compras en Almacen**

```
╔══════════════════════════════════════════════════════════════════════════╗
║  PRESTAMOS Y ANTICIPOS - FLUJO COMPLETO                                ║
╠══════════════════════════════════════════════════════════════════════════╣
║                                                                          ║
║  TIPOS:                                                                  ║
║  ┌─────────────────────────────────────────────────────────────┐        ║
║  │ PRESTAMO:                                                    │        ║
║  │  - Monto mayor (ej: $500 - $5,000)                          │        ║
║  │  - Multiple cuotas mensuales (3, 6, 12, 24 meses)           │        ║
║  │  - Interes opcional (tasa anual configurable, default 0%)    │        ║
║  │  - Requiere aprobacion de jefe + gerencia/RRHH              │        ║
║  │  - Tabla de amortizacion generada automaticamente            │        ║
║  │  - Descuento automatico en rol mensual                       │        ║
║  ├─────────────────────────────────────────────────────────────┤        ║
║  │ ANTICIPO:                                                    │        ║
║  │  - Monto menor (hasta 50% del sueldo, configurable)         │        ║
║  │  - 1-2 cuotas, sin interes                                  │        ║
║  │  - Aprobacion de jefe directo                                │        ║
║  │  - Se descuenta del rol del mismo mes o siguiente            │        ║
║  ├─────────────────────────────────────────────────────────────┤        ║
║  │ COMPRA EN ALMACEN:                                           │        ║
║  │  - Empleado compra productos en el almacen/tienda            │        ║
║  │  - En POS: cajero identifica al empleado como comprador      │        ║
║  │  - Opcion de pago: CONTADO o DESCUENTO_ROL o CUOTAS_ROL     │        ║
║  │  - Si descuento rol: se genera prestamo tipo COMPRA_ALMACEN  │        ║
║  │  - La factura se emite normalmente (venta real)              │        ║
║  │  - El descuento aparece en el rol del empleado               │        ║
║  │  - Max compra a credito: configurable (ej: 30% del sueldo)  │        ║
║  └─────────────────────────────────────────────────────────────┘        ║
║                                                                          ║
║  FLUJO PRESTAMO/ANTICIPO:                                               ║
║  1. Empleado o RRHH solicita (loan_form_screen)                         ║
║  2. Estado: PENDIENTE → notifica a aprobador                            ║
║  3. Aprobador revisa en loan_approval_screen                            ║
║  4. Si aprueba → estado: APROBADO → se generan cuotas (prestamo_cuotas)║
║  5. Al calcular siguiente rol (calculate_payroll):                      ║
║     → busca prestamos ACTIVOS con cuota pendiente en ese mes            ║
║     → descuenta monto_cuota del neto a pagar                           ║
║     → marca cuota como DESCONTADO                                       ║
║     → actualiza saldo_pendiente y cuotas_pagadas                        ║
║  6. Cuando saldo = 0 → estado: PAGADO                                  ║
║                                                                          ║
║  FLUJO COMPRA EN ALMACEN:                                               ║
║  1. En POS: cajero selecciona "Venta a empleado" como forma pago        ║
║  2. Selecciona empleado (busqueda por codigo o nombre)                  ║
║  3. Elige: pago contado, descuento rol (1 cuota), cuotas rol           ║
║  4. Se emite factura normalmente (con impuestos, etc.)                  ║
║  5. Si es descuento/cuotas: se crea compra_empleado_almacen             ║
║     → automaticamente crea prestamo tipo COMPRA_ALMACEN                 ║
║     → con cuotas programadas para descuento en rol                      ║
║  6. Empleado ve en su perfil: compras pendientes de descuento           ║
║  7. RRHH ve en store_purchases_screen: todas las compras pendientes     ║
║                                                                          ║
║  VALIDACIONES:                                                           ║
║  - No permitir nuevo prestamo si saldo pendiente > X% del sueldo       ║
║  - Anticipo max 50% del sueldo (configurable por empresa)              ║
║  - Compras almacen max 30% del sueldo mensual (configurable)           ║
║  - Total descuentos no puede superar neto minimo (SBU vigente)         ║
║  - Al liquidar empleado: saldo prestamos se descuenta de liquidacion   ║
║                                                                          ║
╚══════════════════════════════════════════════════════════════════════════╝
```

**Reglas de Negocio Ecuador (Parametrizables)**

```
╔══════════════════════════════════════════════════════════════════════════╗
║  IESS (Instituto Ecuatoriano de Seguridad Social)                      ║
╠══════════════════════════════════════════════════════════════════════════╣
║  Aporte personal:  9.45% (parametro: APORTE_PERSONAL_IESS)            ║
║  Aporte patronal: 11.15% (parametro: APORTE_PATRONAL_IESS)            ║
║  Total:           20.60%                                               ║
║  Base: sueldo + horas extras + comisiones regulares                    ║
║  Pago: mensual, hasta el 15 del mes siguiente                          ║
╠══════════════════════════════════════════════════════════════════════════╣
║  DECIMO TERCER SUELDO (Bono Navidad)                                   ║
╠══════════════════════════════════════════════════════════════════════════╣
║  Formula: SUM(remuneraciones Dic1 a Nov30) / 12                        ║
║  Pago: hasta 24 de Diciembre                                           ║
║  Incluye: sueldo + horas extras + comisiones                           ║
║  Excluye: utilidades, viaticos, decimo cuarto                          ║
║  Opcion mensualizado: empleado solicita antes del 15 de enero          ║
║  Provision mensual: sueldo_base / 12                                   ║
╠══════════════════════════════════════════════════════════════════════════╣
║  DECIMO CUARTO SUELDO (Bono Escolar)                                   ║
╠══════════════════════════════════════════════════════════════════════════╣
║  Monto fijo: 1 SBU = $482 (parametro: SBU, se actualiza cada anio)    ║
║  Costa/Galapagos: pago 15 marzo (periodo Mar1 - Feb28)                 ║
║  Sierra/Amazonia: pago 15 agosto (periodo Ago1 - Jul31)                ║
║  Proporcional: SBU / 12 * meses trabajados                             ║
║  Provision mensual: SBU / 12                                           ║
╠══════════════════════════════════════════════════════════════════════════╣
║  FONDOS DE RESERVA                                                     ║
╠══════════════════════════════════════════════════════════════════════════╣
║  Porcentaje: 8.33% (parametro: FONDOS_RESERVA_PCT)                     ║
║  Aplica: despues de 1 anio continuo de trabajo                         ║
║  Opciones: pago mensual directo O acumulacion en IESS                  ║
║  Base: misma que para IESS                                             ║
╠══════════════════════════════════════════════════════════════════════════╣
║  VACACIONES                                                            ║
╠══════════════════════════════════════════════════════════════════════════╣
║  Base: 15 dias al anio (despues de 1 anio)                             ║
║  +1 dia por cada anio adicional despues de 5 anios (max total 30 dias)║
║  Formula pago: (sueldo * 12 + extras + comisiones) / 24                ║
║  Acumulacion maxima: 3 anios consecutivos                              ║
║  Provision mensual: sueldo_base * 15 / 360                             ║
╠══════════════════════════════════════════════════════════════════════════╣
║  UTILIDADES (15% de ganancias de la empresa)                           ║
╠══════════════════════════════════════════════════════════════════════════╣
║  10%: distribucion igual por dias trabajados                            ║
║  5%: distribucion por cargas familiares                                 ║
║  Pago: hasta 15 de abril                                               ║
║  Cargas: conyugue + hijos menores 18 + hijos con discapacidad          ║
╠══════════════════════════════════════════════════════════════════════════╣
║  HORAS EXTRAS                                                          ║
╠══════════════════════════════════════════════════════════════════════════╣
║  Suplementarias (despues de jornada, hasta 24:00): +50%                ║
║  Extraordinarias (24:00-06:00, sabados, domingos, feriados): +100%     ║
║  Limites: max 4h/dia, 12h/semana, 60h/mes                              ║
║  Base: sueldo_mensual / 240 = valor hora normal                        ║
╠══════════════════════════════════════════════════════════════════════════╣
║  IMPUESTO A LA RENTA EMPLEADOS                                        ║
╠══════════════════════════════════════════════════════════════════════════╣
║  Exento hasta: $12,208/anio ($1,017.33/mes)                            ║
║  Tabla progresiva (parametrizable en tabla_impuesto_renta):            ║
║    $0 - $12,208         → 0%                                           ║
║    $12,208 - $15,549    → 5% sobre excedente                           ║
║    $15,549 - $20,188    → $167 + 10% sobre excedente                   ║
║    $20,188 - $40,366    → $631 + 15% sobre excedente                   ║
║    ... hasta 37% (rangos completos en tabla parametrizable)             ║
║  Retencion: mensual (Feb-Dic = 11 cuotas)                              ║
║  Deducciones: gastos personales proyectados                             ║
╚══════════════════════════════════════════════════════════════════════════╝
```

```sql
-- Tabla progresiva impuesto a la renta (parametrizable por anio fiscal)
tabla_impuesto_renta
  id              UUID PK
  anio_fiscal     INTEGER NOT NULL
  fraccion_basica DECIMAL(14,2) NOT NULL
  exceso_hasta    DECIMAL(14,2) NOT NULL
  impuesto_fb     DECIMAL(14,2) NOT NULL  -- Impuesto sobre fraccion basica
  porcentaje_excedente DECIMAL(5,2) NOT NULL
  orden           INTEGER NOT NULL
  UNIQUE(anio_fiscal, orden)

-- Seed tabla IR 2026
INSERT INTO tabla_impuesto_renta (anio_fiscal, fraccion_basica, exceso_hasta, impuesto_fb, porcentaje_excedente, orden) VALUES
  (2026, 0,       12208,   0,    0,  1),
  (2026, 12208,   15549,   0,    5,  2),
  (2026, 15549,   20188,   167,  10, 3),
  (2026, 20188,   40366,   631,  15, 4);
  -- ... (completar con todos los rangos hasta 37%)

-- RPCs Nomina
CREATE OR REPLACE FUNCTION calculate_payroll(
  p_empresa_id UUID, p_anio INTEGER, p_mes INTEGER
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER AS $$
  -- 1. Obtener todos los empleados activos
  -- 2. Para cada empleado:
  --    a. Calcular ingresos (sueldo + extras + comisiones + bonos)
  --    b. Calcular aporte IESS personal (base * get_parametro_sri('APORTE_PERSONAL_IESS') / 100)
  --    c. Calcular retencion IR mensual (usando tabla_impuesto_renta)
  --    d. Descontar prestamos/anticipos/compras almacen:
  --       → Buscar en prestamos_empleado WHERE estado = 'ACTIVO'
  --       → Para cada prestamo activo, buscar cuota del mes en prestamo_cuotas
  --       → Sumar todos los descuentos al total_egresos del rol_detalle
  --       → Marcar cuota como DESCONTADO, vincular con rol_detalle_id
  --       → Actualizar saldo_pendiente y cuotas_pagadas en prestamos_empleado
  --       → Si saldo = 0 → estado PAGADO
  --    e. Validar: total descuentos no exceda neto minimo (SBU)
  --    f. Calcular patronal (IESS + fondos reserva + provisiones)
  --    g. Generar asiento contable automatico
  -- 3. Retornar ID del rol_pago generado
$$;

CREATE OR REPLACE FUNCTION calculate_settlement(
  p_empresa_id UUID, p_empleado_id UUID, p_fecha_salida DATE, p_motivo VARCHAR
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
  -- Calcula acta de finiquito:
  -- + Sueldo proporcional del mes
  -- + Decimo tercero proporcional
  -- + Decimo cuarto proporcional
  -- + Vacaciones no gozadas
  -- + Fondos de reserva pendientes
  -- + Desahucio (si aplica): 25% del sueldo por anio
  -- + Indemnizacion (si despido intempestivo)
  -- - Saldo total prestamos pendientes (se descuenta de la liquidacion)
  -- - Saldo compras almacen pendientes
  -- Retorna JSONB con desglose completo
$$;

CREATE OR REPLACE FUNCTION approve_loan(
  p_empresa_id UUID, p_prestamo_id UUID, p_aprobado_por UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
  -- 1. Validar que el prestamo este en estado PENDIENTE
  -- 2. Validar que el total de descuentos mensuales del empleado
  --    (prestamos activos + nuevo) no exceda el % maximo del sueldo
  -- 3. Actualizar estado a APROBADO, fecha_aprobacion, aprobado_por
  -- 4. Generar cuotas en prestamo_cuotas (tabla de amortizacion):
  --    - Si tasa_interes = 0: cuota fija = monto_total / cuotas_total
  --    - Si tasa_interes > 0: amortizacion francesa (cuota fija, interes decreciente)
  --    - Asignar mes/anio de descuento a cada cuota (desde fecha_primer_descuento)
  -- 5. Actualizar estado a ACTIVO
  -- 6. Retornar tabla de amortizacion como JSONB
$$;

CREATE OR REPLACE FUNCTION register_store_purchase(
  p_empresa_id UUID, p_empleado_id UUID, p_factura_id UUID,
  p_monto DECIMAL, p_forma_pago VARCHAR, p_cuotas INTEGER DEFAULT 1
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
  -- 1. Validar que el empleado esta activo
  -- 2. Validar que monto no exceda % max del sueldo para compras almacen
  -- 3. Insertar en compras_empleado_almacen
  -- 4. Si forma_pago = 'DESCUENTO_ROL' o 'CUOTAS_ROL':
  --    a. Crear prestamo tipo COMPRA_ALMACEN (tasa 0%, sin aprobacion requerida)
  --    b. Generar cuotas en prestamo_cuotas
  --    c. Vincular prestamo_id en compras_empleado_almacen
  --    d. Estado directo: ACTIVO (no necesita aprobacion)
  -- 5. Si forma_pago = 'CONTADO': estado PAGADO_CONTADO (no afecta rol)
  -- 6. Retornar resumen de la operacion
$$;

CREATE OR REPLACE FUNCTION generate_bank_file(
  p_empresa_id UUID, p_rol_id UUID, p_formato_banco_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
  -- 1. Obtener todos los rol_detalle del rol con neto_a_pagar > 0
  -- 2. Filtrar empleados que tengan cuenta en el banco del formato
  -- 3. Obtener definicion de columnas del formato_banco
  -- 4. Generar contenido del archivo:
  --    a. Cabecera (si tiene_cabecera = true)
  --    b. Por cada empleado: generar fila segun columnas JSONB
  --       → Mapear campos: tipo_cuenta, numero_cuenta, cedula, nombre, monto, referencia
  --    c. Totales (si tiene_totales = true): count + sum montos
  -- 5. Subir archivo a Supabase Storage (rrhh/archivos_pago/)
  -- 6. Insertar en archivos_pago_nomina
  -- 7. Retornar: {archivo_url, total_empleados, total_monto, empleados_sin_cuenta: [...]}
$$;

-- ============================================
-- LIQUIDACIONES Y FINIQUITOS (OBLIGATORIO LEY ECUADOR)
-- ============================================
-- Calculo automatico al terminar relacion laboral.
-- Codigo del Trabajo Arts. 95, 185, 188, 196

CREATE TABLE liquidaciones (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  empleado_id     UUID NOT NULL REFERENCES empleados(id),
  numero          SERIAL NOT NULL,
  fecha_liquidacion DATE NOT NULL DEFAULT CURRENT_DATE,
  fecha_ingreso   DATE NOT NULL,                   -- Fecha inicio relacion laboral
  fecha_salida    DATE NOT NULL,                   -- Ultimo dia trabajado
  tipo_salida     VARCHAR(30) NOT NULL,            -- RENUNCIA, DESPIDO_INTEMPESTIVO, DESAHUCIO,
                                                    -- MUTUO_ACUERDO, VISTO_BUENO, TERMINACION_CONTRATO
  -- Haberes proporcionales
  sueldo_proporcional   DECIMAL(14,2) DEFAULT 0,   -- Dias trabajados del mes de salida
  decimo_tercero_prop   DECIMAL(14,2) DEFAULT 0,   -- Proporcional dic-nov
  decimo_cuarto_prop    DECIMAL(14,2) DEFAULT 0,   -- Proporcional ago-jul (sierra) o mar-feb (costa)
  vacaciones_pendientes DECIMAL(14,2) DEFAULT 0,   -- Dias no gozados * sueldo diario
  fondos_reserva_prop   DECIMAL(14,2) DEFAULT 0,   -- Proporcional si aplica

  -- Indemnizaciones
  indemnizacion_despido  DECIMAL(14,2) DEFAULT 0,  -- Art. 188: 1 mes por anio (sin tope desde 2015)
  indemnizacion_desahucio DECIMAL(14,2) DEFAULT 0, -- Art. 185: 25% ultimo sueldo * anios
  bonificacion_25_anios  DECIMAL(14,2) DEFAULT 0,  -- Art. 185: 25 anios = 1 mes por anio

  -- Descuentos
  prestamos_pendientes  DECIMAL(14,2) DEFAULT 0,   -- Saldo de prestamos empresa
  anticipos_pendientes  DECIMAL(14,2) DEFAULT 0,   -- Anticipos no descontados
  otros_descuentos      DECIMAL(14,2) DEFAULT 0,

  -- Totales
  total_haberes         DECIMAL(14,2) NOT NULL DEFAULT 0,
  total_indemnizaciones DECIMAL(14,2) NOT NULL DEFAULT 0,
  total_descuentos      DECIMAL(14,2) NOT NULL DEFAULT 0,
  total_liquidacion     DECIMAL(14,2) NOT NULL DEFAULT 0, -- haberes + indemnizaciones - descuentos

  estado          VARCHAR(20) DEFAULT 'BORRADOR',  -- BORRADOR, CALCULADA, APROBADA, PAGADA
  aprobado_por    UUID REFERENCES auth.users(id),
  notas           TEXT,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE liquidaciones ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON liquidaciones
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- RPC para calcular liquidacion
CREATE OR REPLACE FUNCTION calculate_settlement_full(
  p_empleado_id UUID,
  p_fecha_salida DATE,
  p_tipo_salida VARCHAR
) RETURNS UUID AS $$
DECLARE
  v_empleado RECORD;
  v_liquidacion_id UUID;
  v_anios_servicio DECIMAL(10,4);
  v_sueldo_diario DECIMAL(14,2);
  v_ultimo_sueldo DECIMAL(14,2);
BEGIN
  SELECT * INTO v_empleado FROM empleados WHERE id = p_empleado_id;
  v_anios_servicio := EXTRACT(EPOCH FROM (p_fecha_salida - v_empleado.fecha_ingreso)) / 86400.0 / 365.25;
  v_ultimo_sueldo := v_empleado.sueldo_actual;
  v_sueldo_diario := v_ultimo_sueldo / 30;

  INSERT INTO liquidaciones (empresa_id, empleado_id, fecha_ingreso, fecha_salida, tipo_salida,
    -- Haberes proporcionales
    sueldo_proporcional,          -- Dias trabajados del mes
    decimo_tercero_prop,          -- (meses desde dic * sueldo) / 12
    decimo_cuarto_prop,           -- (meses desde ago/mar * SBU) / 12
    vacaciones_pendientes,        -- dias_pendientes * sueldo_diario
    fondos_reserva_prop,          -- Si > 1 anio: proporcional mensual
    -- Indemnizaciones segun tipo
    indemnizacion_despido,        -- DESPIDO_INTEMPESTIVO: 1 mes * anios (sin tope)
    indemnizacion_desahucio,      -- DESAHUCIO: 25% * ultimo_sueldo * anios
    -- Descuentos
    prestamos_pendientes,         -- SUM(saldo) de prestamos_empleado
    anticipos_pendientes          -- SUM(anticipos no descontados)
  ) VALUES (...)
  RETURNING id INTO v_liquidacion_id;

  -- Calcular totales
  UPDATE liquidaciones SET
    total_haberes = sueldo_proporcional + decimo_tercero_prop + decimo_cuarto_prop + vacaciones_pendientes + fondos_reserva_prop,
    total_indemnizaciones = indemnizacion_despido + indemnizacion_desahucio + bonificacion_25_anios,
    total_descuentos = prestamos_pendientes + anticipos_pendientes + otros_descuentos,
    total_liquidacion = total_haberes + total_indemnizaciones - total_descuentos,
    estado = 'CALCULADA'
  WHERE id = v_liquidacion_id;

  RETURN v_liquidacion_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- REPARTO DE UTILIDADES 15% (OBLIGATORIO LEY ECUADOR)
-- ============================================
-- Codigo del Trabajo Art. 97: 15% de utilidades netas.
-- 10% reparto igualitario + 5% proporcional a cargas familiares.
-- Plazo: hasta 15 de abril del anio siguiente.

CREATE TABLE reparto_utilidades (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  anio_fiscal     INTEGER NOT NULL,
  utilidad_neta   DECIMAL(14,2) NOT NULL,          -- Utilidad contable del ejercicio
  monto_15_porciento DECIMAL(14,2) NOT NULL,       -- utilidad_neta * 0.15
  monto_10_igualitario DECIMAL(14,2) NOT NULL,     -- monto_15 * (10/15)
  monto_5_cargas  DECIMAL(14,2) NOT NULL,           -- monto_15 * (5/15)
  total_dias_trabajados INTEGER,                    -- Suma de dias de todos los empleados
  total_cargas    INTEGER,                          -- Suma de cargas familiares
  estado          VARCHAR(20) DEFAULT 'BORRADOR',  -- BORRADOR, CALCULADO, APROBADO, PAGADO
  fecha_pago      DATE,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(empresa_id, anio_fiscal)
);

CREATE TABLE reparto_utilidades_detalle (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reparto_id      UUID NOT NULL REFERENCES reparto_utilidades(id) ON DELETE CASCADE,
  empleado_id     UUID NOT NULL REFERENCES empleados(id),
  dias_trabajados INTEGER NOT NULL,                -- Dias trabajados en el anio fiscal
  cargas_familiares INTEGER NOT NULL DEFAULT 0,    -- Hijos menores 18, hijos discapacitados, conyuge dependiente
  monto_10_individual DECIMAL(14,2) NOT NULL,      -- (monto_10 / total_dias) * dias_empleado
  monto_5_individual  DECIMAL(14,2) NOT NULL,      -- (monto_5 / total_cargas) * cargas_empleado
  total_utilidades DECIMAL(14,2) NOT NULL,          -- monto_10 + monto_5
  pagado          BOOLEAN DEFAULT false
);

-- RPC para calcular reparto
CREATE OR REPLACE FUNCTION calculate_profit_sharing(
  p_empresa_id UUID,
  p_anio INTEGER,
  p_utilidad_neta DECIMAL(14,2)
) RETURNS UUID AS $$
  -- 1. Calcular montos: 15%, 10% igualitario, 5% cargas
  -- 2. Obtener empleados que trabajaron en el anio fiscal
  -- 3. Para cada empleado: calcular dias trabajados y cargas familiares
  -- 4. Distribuir 10%: proporcional a dias trabajados
  -- 5. Distribuir 5%: proporcional a cargas familiares
  -- 6. Insertar cabecera y detalle
  -- NOTA: Empleados que salieron durante el anio tambien participan (proporcional)
  -- NOTA: Maximo por empleado del 5%: no puede exceder el 5% total * factor
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- PLANILLAS IESS (OBLIGATORIO MENSUAL)
-- ============================================
-- Generacion de archivos en formato IESS para:
-- 1. Planilla de aportes mensuales (patronal + personal)
-- 2. Planilla de fondos de reserva
-- 3. Avisos de entrada/salida

CREATE TABLE planillas_iess (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  tipo            VARCHAR(30) NOT NULL,            -- APORTES_MENSUALES, FONDOS_RESERVA, AVISO_ENTRADA, AVISO_SALIDA
  periodo_anio    INTEGER NOT NULL,
  periodo_mes     INTEGER NOT NULL,                -- 1-12
  numero_patronal VARCHAR(20),                     -- Numero patronal IESS de la empresa
  total_empleados INTEGER,
  total_aporte_personal DECIMAL(14,2) DEFAULT 0,   -- 9.45% del sueldo
  total_aporte_patronal DECIMAL(14,2) DEFAULT 0,   -- 11.15% del sueldo (+ 1% IECE + 0.5% SECAP)
  total_fondos_reserva  DECIMAL(14,2) DEFAULT 0,   -- 8.33% del sueldo (empleados > 1 anio)
  estado          VARCHAR(20) DEFAULT 'BORRADOR',  -- BORRADOR, GENERADA, ENVIADA
  archivo_generado TEXT,                           -- Ruta al archivo CSV/TXT generado
  fecha_generacion TIMESTAMPTZ,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(empresa_id, tipo, periodo_anio, periodo_mes)
);

CREATE TABLE planilla_iess_detalle (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  planilla_id     UUID NOT NULL REFERENCES planillas_iess(id) ON DELETE CASCADE,
  empleado_id     UUID NOT NULL REFERENCES empleados(id),
  cedula          VARCHAR(13) NOT NULL,
  nombres         VARCHAR(200) NOT NULL,
  dias_trabajados INTEGER NOT NULL DEFAULT 30,
  sueldo_base     DECIMAL(14,2) NOT NULL,
  horas_extras    DECIMAL(14,2) DEFAULT 0,
  comisiones      DECIMAL(14,2) DEFAULT 0,
  otros_ingresos  DECIMAL(14,2) DEFAULT 0,
  total_ingresos  DECIMAL(14,2) NOT NULL,          -- Base imponible IESS
  aporte_personal DECIMAL(14,2) NOT NULL,          -- 9.45%
  aporte_patronal DECIMAL(14,2) NOT NULL,          -- 11.15%
  fondo_reserva   DECIMAL(14,2) DEFAULT 0,         -- 8.33% si > 1 anio
  novedad         VARCHAR(5)                       -- Codigo novedad IESS si aplica
);

ALTER TABLE planillas_iess ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON planillas_iess
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- RPC para generar planilla mensual
CREATE OR REPLACE FUNCTION generate_iess_payroll(
  p_empresa_id UUID,
  p_anio INTEGER,
  p_mes INTEGER
) RETURNS UUID AS $$
  -- 1. Obtener empleados activos con relacion IESS
  -- 2. Para cada empleado: calcular base imponible (sueldo + HE + comisiones)
  -- 3. Calcular aportes: personal (9.45%), patronal (11.15%), FR (8.33%)
  -- 4. Generar archivo en formato IESS (CSV con estructura oficial)
  -- 5. Almacenar archivo en Supabase Storage
  -- 6. Retornar ID de la planilla generada
  --
  -- Formato archivo IESS (campos separados por comas):
  -- tipo_registro,cedula,nombres,dias,sueldo,horas_extras,otros,novedad
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

**Reportes RRHH**

```
| Reporte | Formato | Destino | Frecuencia |
|---------|---------|---------|------------|
| Rol de pagos mensual (consolidado) | PDF/Excel | Interno | Mensual |
| Rol de pago individual (por empleado) | PDF | Empleado (email/WA/Telegram) | Mensual |
| Planilla IESS | CSV (formato IESS) | IESS web | Mensual |
| RDEP (Anexo Relacion Dependencia) | XML (formato SRI) | SRI | Anual (Ene-Feb) |
| Formulario 107 | PDF | Empleado | Anual (Enero) |
| Decimo tercer sueldo | PDF | MDT/Interno | Anual (Diciembre) |
| Decimo cuarto sueldo | PDF | MDT/Interno | Anual (Mar o Ago) |
| Liquidacion / Finiquito | PDF | MDT/Empleado | Al terminar relacion |
| Utilidades 15% | PDF | Interno | Anual (Abril) |
| Archivo bancario pago nomina | CSV/TXT (formato banco) | Portal banco | Mensual |
| Prestamos activos por empleado | PDF/Excel | RRHH | Bajo demanda |
| Compras almacen pendientes descuento | PDF/Excel | RRHH | Mensual |
| Tabla amortizacion prestamo | PDF | Empleado | Al aprobar |
| Asistencia mensual | PDF/Excel | Interno | Mensual |
| Horas extras por empleado | PDF/Excel | Interno | Mensual |
| Atrasos y faltas | PDF/Excel | Interno | Mensual |
| Planificado vs real (horarios) | PDF/Excel | Interno | Mensual |
| Rotacion de personal | PDF | Gerencia | Trimestral |
| Vencimiento de contratos | PDF | RRHH | Mensual |
| Organigrama | PDF | Interno | Bajo demanda |
```

**Sub-modulo: Asistencia y Horarios (dentro de RRHH)**

**Modelo de Datos - Horarios, Turnos y Asistencia**

```
NOTA: La estructura Flutter de asistencia esta integrada en features/rrhh/screens/attendance/
y features/rrhh/screens/leave/ (ver estructura arriba). No es un modulo separado.
```
  ├── screens/
  │   ├── attendance_screen.dart          # Registro entrada/salida (multi-metodo)
  │   ├── attendance_report_screen.dart   # Reporte de asistencia (SfDataGrid)
  │   ├── shifts_screen.dart              # CRUD turnos de la empresa
  │   ├── shift_detail_screen.dart        # Detalle turno con horarios por dia
  │   ├── rotation_patterns_screen.dart   # Patrones de rotacion (ej: 5x2, 4x2, 7x7)
  │   ├── schedule_screen.dart            # Planificacion de horarios por empleado/grupo
  │   ├── schedule_calendar_screen.dart   # Calendario visual de asignaciones (SfCalendar)
  │   ├── schedule_template_screen.dart   # Plantillas de horario reutilizables
  │   ├── overtime_screen.dart            # Horas extras (calculo y aprobacion)
  │   ├── overtime_approval_screen.dart   # Aprobacion masiva de horas extras
  │   ├── leave_request_screen.dart       # Solicitudes de permiso/ausencia
  │   ├── holidays_screen.dart            # Feriados nacionales + locales por empresa
  │   ├── attendance_summary_screen.dart  # Resumen mensual: horas normales/extras/faltas
  │   ├── biometric_devices_screen.dart   # CRUD dispositivos biometricos
  │   ├── biometric_enroll_screen.dart    # Enrolamiento de empleados en dispositivos
  │   └── biometric_kiosk_screen.dart     # Modo kiosko para tablet/PC (marcacion in-situ)
  ├── providers/
  │   ├── attendance_provider.dart
  │   ├── shift_provider.dart
  │   ├── schedule_provider.dart          # Planificacion y rotaciones
  │   ├── overtime_provider.dart
  │   └── biometric_provider.dart         # Comunicacion con dispositivos
  ├── services/
  │   ├── schedule_engine.dart            # Motor de calculo de horarios y rotaciones
  │   ├── overtime_calculator.dart        # Calculo horas extras segun normativa Ecuador
  │   ├── biometric_service.dart          # Capa abstracta para dispositivos biometricos
  │   ├── zkteco_adapter.dart             # Adaptador ZKTeco (Push SDK / REST API)
  │   ├── generic_api_adapter.dart        # Adaptador generico HTTP para otros dispositivos
  │   └── local_biometric_service.dart    # Huella/FaceID nativo del celular/tablet (local_auth)
  └── models/
```

**Modelo de Datos - Horarios y Turnos**

```sql
-- ══════════════════════════════════════════════════════════════════
-- TURNOS (una empresa puede tener N turnos)
-- Un turno define las reglas generales: nombre, tipo jornada, tolerancias
-- ══════════════════════════════════════════════════════════════════

turnos
  id                UUID PK
  empresa_id        UUID FK -> empresas
  codigo            VARCHAR(20) NOT NULL        -- 'MAT', 'VESP', 'NOCT', 'ROT-A'
  nombre            VARCHAR(100) NOT NULL       -- 'Matutino', 'Vespertino', 'Nocturno 12h'
  tipo_jornada      VARCHAR(20) DEFAULT 'NORMAL'
    -- NORMAL: jornada estandar (ej: 8h diurnas, lun-vie)
    -- ESPECIAL: jornada reducida o diferente (ej: 6h, sectores especificos)
    -- NOCTURNA: jornada nocturna (25% recargo segun Codigo Trabajo Ecuador art. 49)
    -- MIXTA: combina horas diurnas y nocturnas
    -- CONTINUA: jornada continua (ej: guardias 12h o 24h)
  color             VARCHAR(7) DEFAULT '#1976D2' -- Color para calendario visual
  -- Horas de la jornada
  horas_jornada     DECIMAL(4,2) DEFAULT 8      -- Horas contratadas por dia
  horas_semana      DECIMAL(5,2) DEFAULT 40     -- Horas contratadas por semana (Ecuador max 40h)
  -- Tolerancias
  tolerancia_entrada_min INTEGER DEFAULT 10     -- Minutos de tolerancia al ingreso
  tolerancia_salida_min  INTEGER DEFAULT 5      -- Minutos de tolerancia a la salida
  minutos_almuerzo  INTEGER DEFAULT 60          -- Minutos de almuerzo (se descuenta de horas)
  descuenta_almuerzo BOOLEAN DEFAULT true       -- Si descuenta almuerzo de horas trabajadas
  -- Configuracion
  permite_horas_extras BOOLEAN DEFAULT true
  requiere_aprobacion_extras BOOLEAN DEFAULT true -- Horas extras necesitan aprobacion
  max_extras_dia    DECIMAL(4,2) DEFAULT 4      -- Max horas extras por dia (Codigo Trabajo)
  max_extras_semana DECIMAL(4,2) DEFAULT 12     -- Max horas extras por semana
  max_extras_mes    DECIMAL(5,2) DEFAULT 60     -- Max horas extras por mes
  activo            BOOLEAN DEFAULT true
  created_at        TIMESTAMPTZ DEFAULT now()
  updated_at        TIMESTAMPTZ DEFAULT now()

  UNIQUE(empresa_id, codigo)

-- ══════════════════════════════════════════════════════════════════
-- HORARIOS DEL TURNO (define hora entrada/salida por dia de la semana)
-- Un turno puede tener diferentes horarios por dia (ej: viernes salida 16:00)
-- ══════════════════════════════════════════════════════════════════

turno_horarios
  id                UUID PK
  empresa_id        UUID FK -> empresas
  turno_id          UUID FK -> turnos
  dia_semana        INTEGER NOT NULL            -- 1=Lun, 2=Mar, ..., 7=Dom
  hora_entrada      TIME NOT NULL               -- 08:00
  hora_salida       TIME NOT NULL               -- 17:00
  hora_almuerzo_ini TIME                        -- 12:00 (NULL = sin hora fija)
  hora_almuerzo_fin TIME                        -- 13:00
  es_laborable      BOOLEAN DEFAULT true        -- false = dia libre en este turno
  horas_efectivas   DECIMAL(4,2)                -- Horas reales del dia (auto-calculado)
  UNIQUE(turno_id, dia_semana)

-- ══════════════════════════════════════════════════════════════════
-- PATRONES DE ROTACION
-- Define ciclos repetitivos (ej: 5 dias trabajo / 2 descanso,
-- semana 1 matutino / semana 2 vespertino / semana 3 nocturno)
-- ══════════════════════════════════════════════════════════════════

patrones_rotacion
  id                UUID PK
  empresa_id        UUID FK -> empresas
  nombre            VARCHAR(100) NOT NULL       -- 'Rotacion 3 turnos', '5x2 standard'
  descripcion       TEXT
  dias_ciclo        INTEGER NOT NULL            -- Duracion total del ciclo en dias (ej: 21 para 3 semanas)
  activo            BOOLEAN DEFAULT true
  UNIQUE(empresa_id, nombre)

-- Detalle del patron: que turno aplica en cada dia del ciclo
patron_rotacion_dias
  id                UUID PK
  patron_id         UUID FK -> patrones_rotacion
  dia_ciclo         INTEGER NOT NULL            -- Dia dentro del ciclo (1, 2, 3, ..., dias_ciclo)
  turno_id          UUID FK -> turnos           -- NULL = dia libre/descanso
  es_descanso       BOOLEAN DEFAULT false       -- true = dia de descanso obligatorio
  UNIQUE(patron_id, dia_ciclo)

-- Ejemplo patron "Rotacion 3 turnos (21 dias)":
--   dias 1-5: turno Matutino,   dias 6-7: descanso
--   dias 8-12: turno Vespertino, dias 13-14: descanso
--   dias 15-19: turno Nocturno,  dias 20-21: descanso
--   → Luego se repite el ciclo

-- Ejemplo patron "Guardia 24h (4x4)":
--   dias 1-4: turno Guardia_24h
--   dias 5-8: descanso
--   → Ciclo de 8 dias

-- ══════════════════════════════════════════════════════════════════
-- ASIGNACION DE HORARIOS A EMPLEADOS
-- Un empleado puede tener: turno fijo, patron rotativo, o asignacion manual dia a dia
-- ══════════════════════════════════════════════════════════════════

asignaciones_horario
  id                UUID PK
  empresa_id        UUID FK -> empresas
  empleado_id       UUID FK -> empleados
  tipo_asignacion   VARCHAR(20) NOT NULL
    -- TURNO_FIJO: siempre el mismo turno
    -- ROTACION: sigue un patron de rotacion ciclico
    -- MANUAL: se asigna turno dia por dia (para casos especiales)
  -- Para TURNO_FIJO
  turno_id          UUID FK -> turnos           -- Turno fijo asignado (NULL si rotacion/manual)
  -- Para ROTACION
  patron_id         UUID FK -> patrones_rotacion -- Patron de rotacion (NULL si fijo/manual)
  fecha_inicio_ciclo DATE                       -- Fecha en que empieza el dia 1 del patron
  -- Vigencia
  fecha_desde       DATE NOT NULL               -- Desde cuando aplica esta asignacion
  fecha_hasta       DATE                        -- NULL = vigente indefinidamente
  -- Grupo (para asignar el mismo horario a un equipo)
  grupo_horario     VARCHAR(50)                 -- 'Equipo A', 'Turno Noche', etc. (opcional)
  observaciones     TEXT
  created_at        TIMESTAMPTZ DEFAULT now()

  -- Solo una asignacion activa por empleado en cada fecha
  -- Se valida por logica: no solapar fecha_desde/fecha_hasta

-- ══════════════════════════════════════════════════════════════════
-- PLANIFICACION DIARIA (generada automaticamente o manual)
-- Es la "agenda" final: que turno tiene cada empleado cada dia
-- Se genera a partir de asignaciones + rotaciones + excepciones
-- ══════════════════════════════════════════════════════════════════

planificacion_diaria
  id                UUID PK
  empresa_id        UUID FK -> empresas
  empleado_id       UUID FK -> empleados
  fecha             DATE NOT NULL
  turno_id          UUID FK -> turnos           -- Turno asignado para este dia
  hora_entrada_esperada TIME NOT NULL           -- Hora que debe entrar (del turno_horarios)
  hora_salida_esperada  TIME NOT NULL           -- Hora que debe salir
  horas_esperadas   DECIMAL(4,2) NOT NULL       -- Horas que debe trabajar
  es_laborable      BOOLEAN DEFAULT true        -- false = descanso o feriado
  es_feriado        BOOLEAN DEFAULT false
  -- Origen de la asignacion
  origen            VARCHAR(20) DEFAULT 'AUTOMATICO'
    -- AUTOMATICO: generado desde asignacion/rotacion
    -- MANUAL: modificado manualmente por supervisor
    -- INTERCAMBIO: resultado de intercambio de turno entre empleados
  asignacion_id     UUID FK -> asignaciones_horario  -- De donde salio esta planificacion
  notas             TEXT
  UNIQUE(empresa_id, empleado_id, fecha)

-- ══════════════════════════════════════════════════════════════════
-- FERIADOS (nacionales + locales por empresa/establecimiento)
-- ══════════════════════════════════════════════════════════════════

feriados
  id                UUID PK
  empresa_id        UUID FK -> empresas         -- NULL = feriado nacional (aplica a todas)
  establecimiento_id UUID FK -> establecimientos -- NULL = aplica a todos los establecimientos
  fecha             DATE NOT NULL
  nombre            VARCHAR(100) NOT NULL       -- 'Dia del Trabajo', 'Fundacion de Guayaquil'
  tipo              VARCHAR(20) DEFAULT 'NACIONAL'
    -- NACIONAL: feriado obligatorio (Codigo Trabajo art. 65)
    -- LOCAL: feriado cantonal/provincial
    -- EMPRESA: dia libre otorgado por la empresa
  es_recuperable    BOOLEAN DEFAULT false       -- Si se puede recuperar (trabajo en otro dia)
  aplica_recargo    BOOLEAN DEFAULT true        -- Si aplica recargo 100% si se trabaja
  UNIQUE(empresa_id, fecha, establecimiento_id)

-- Seed feriados Ecuador 2026
-- INSERT INTO feriados (fecha, nombre, tipo) VALUES
--   ('2026-01-01', 'Ano Nuevo', 'NACIONAL'),
--   ('2026-02-16', 'Carnaval (lunes)', 'NACIONAL'),
--   ('2026-02-17', 'Carnaval (martes)', 'NACIONAL'),
--   ('2026-04-03', 'Viernes Santo', 'NACIONAL'),
--   ('2026-05-01', 'Dia del Trabajo', 'NACIONAL'),
--   ('2026-05-24', 'Batalla de Pichincha', 'NACIONAL'),
--   ('2026-08-10', 'Primer Grito de Independencia', 'NACIONAL'),
--   ('2026-10-09', 'Independencia de Guayaquil', 'NACIONAL'),
--   ('2026-11-02', 'Dia de Difuntos', 'NACIONAL'),
--   ('2026-11-03', 'Independencia de Cuenca', 'NACIONAL'),
--   ('2026-12-25', 'Navidad', 'NACIONAL');
--   -- + feriados locales segun canton del establecimiento

-- ══════════════════════════════════════════════════════════════════
-- INTERCAMBIO DE TURNOS (entre empleados, con aprobacion)
-- ══════════════════════════════════════════════════════════════════

intercambios_turno
  id                UUID PK
  empresa_id        UUID FK -> empresas
  solicitante_id    UUID FK -> empleados        -- Empleado que pide el intercambio
  receptor_id       UUID FK -> empleados        -- Empleado que acepta cubrir
  fecha_intercambio DATE NOT NULL               -- Dia que se intercambia
  turno_solicitante UUID FK -> turnos           -- Turno original del solicitante
  turno_receptor    UUID FK -> turnos           -- Turno original del receptor
  motivo            TEXT
  estado            VARCHAR(20) DEFAULT 'PENDIENTE'
    -- PENDIENTE, ACEPTADO_RECEPTOR, APROBADO, RECHAZADO
  aceptado_receptor BOOLEAN                     -- El receptor acepto?
  aprobado_por      UUID FK -> auth.users       -- Supervisor que aprobo
  created_at        TIMESTAMPTZ DEFAULT now()

-- ══════════════════════════════════════════════════════════════════
-- DISPOSITIVOS BIOMETRICOS
-- ══════════════════════════════════════════════════════════════════

dispositivos_biometricos
  id              UUID PK
  empresa_id      UUID FK -> empresas
  establecimiento_id UUID FK -> establecimientos
  nombre          VARCHAR(100) NOT NULL   -- 'Biometrico Entrada Principal'
  marca           VARCHAR(50) NOT NULL    -- ZKTECO, HIKVISION, DAHUA, GENERIC
  modelo          VARCHAR(50)             -- 'SpeedFace V5L', 'K40', 'MB160', etc.
  numero_serie    VARCHAR(50)
  -- Conectividad
  tipo_conexion   VARCHAR(20) NOT NULL    -- NETWORK, USB, CLOUD
    -- NETWORK: dispositivo autonomo conectado a red TCP/IP o WiFi
    -- USB: dispositivo conectado por USB a un computador
    -- CLOUD: dispositivo con Push SDK que envia datos a un endpoint
  ip_address      VARCHAR(45)             -- IP del dispositivo (para NETWORK)
  puerto          INTEGER DEFAULT 4370    -- Puerto de comunicacion (ZKTeco default: 4370)
  webhook_url     TEXT                    -- URL webhook para recibir marcaciones (CLOUD)
  api_key         TEXT                    -- Clave de autenticacion del dispositivo
  -- Capacidades
  soporta_huella  BOOLEAN DEFAULT true
  soporta_facial  BOOLEAN DEFAULT false
  soporta_tarjeta BOOLEAN DEFAULT false   -- RFID/NFC
  soporta_pin     BOOLEAN DEFAULT false
  -- Estado
  estado          VARCHAR(20) DEFAULT 'ACTIVO'  -- ACTIVO, INACTIVO, SIN_CONEXION, MANTENIMIENTO
  ultimo_ping     TIMESTAMPTZ             -- Ultima vez que respondio al heartbeat
  ultima_sincronizacion TIMESTAMPTZ       -- Ultima vez que se sincronizaron marcaciones
  -- Configuracion
  config          JSONB DEFAULT '{}'      -- Configuracion especifica del dispositivo/marca
  created_at      TIMESTAMPTZ DEFAULT now()
  updated_at      TIMESTAMPTZ DEFAULT now()

-- ══════════════════════════════════════════════════════════════════
-- ENROLAMIENTO (huellas/rostros registrados en dispositivos)
-- ══════════════════════════════════════════════════════════════════

enrolamiento_biometrico
  id              UUID PK
  empresa_id      UUID FK -> empresas
  empleado_id     UUID FK -> empleados
  dispositivo_id  UUID FK -> dispositivos_biometricos  -- NULL = dispositivo nativo (celular/tablet)
  tipo_biometria  VARCHAR(20) NOT NULL    -- HUELLA, FACIAL, TARJETA, PIN
  -- Referencia en el dispositivo
  device_user_id  VARCHAR(50)             -- ID del usuario en el dispositivo (para ZKTeco, etc.)
  template_data   TEXT                    -- Template biometrico encriptado (backup)
  -- Estado
  fecha_enrolamiento TIMESTAMPTZ DEFAULT now()
  activo          BOOLEAN DEFAULT true
  UNIQUE(empresa_id, empleado_id, dispositivo_id, tipo_biometria)

-- ══════════════════════════════════════════════════════════════════
-- MARCACIONES
-- ══════════════════════════════════════════════════════════════════

marcaciones
  id              UUID PK
  empresa_id      UUID FK -> empresas
  empleado_id     UUID FK -> empleados
  fecha           DATE NOT NULL
  hora_entrada    TIMESTAMPTZ
  hora_salida     TIMESTAMPTZ
  -- Metodo de registro
  metodo_entrada  VARCHAR(20)
    -- HUELLA_DISPOSITIVO: huella en dispositivo autonomo (ZKTeco, Hikvision, etc.)
    -- FACIAL_DISPOSITIVO: reconocimiento facial en dispositivo autonomo
    -- HUELLA_CELULAR: huella dactilar del celular/tablet (local_auth)
    -- FACEID_CELULAR: Face ID del celular/tablet (local_auth)
    -- QR_APP: escaneo QR desde app movil + GPS
    -- WEB: check-in desde navegador (con verificacion IP)
    -- MANUAL: supervisor registra (requiere aprobacion)
    -- TARJETA: tarjeta RFID/NFC en dispositivo
  metodo_salida   VARCHAR(20)
  -- Dispositivo que registro la marcacion
  dispositivo_entrada_id UUID FK -> dispositivos_biometricos  -- NULL = app/web/manual
  dispositivo_salida_id  UUID FK -> dispositivos_biometricos
  -- Ubicacion GPS (si aplica, para app movil)
  latitud_entrada DECIMAL(10,7)
  longitud_entrada DECIMAL(10,7)
  latitud_salida  DECIMAL(10,7)
  longitud_salida DECIMAL(10,7)
  -- Calculo
  horas_trabajadas DECIMAL(4,2)
  horas_extras_50 DECIMAL(4,2) DEFAULT 0  -- Suplementarias
  horas_extras_100 DECIMAL(4,2) DEFAULT 0 -- Extraordinarias
  atraso_minutos  INTEGER DEFAULT 0
  estado          VARCHAR(20) DEFAULT 'REGISTRADO'
    -- REGISTRADO, APROBADO, RECHAZADO
  notas           TEXT
  UNIQUE(empresa_id, empleado_id, fecha)

-- ══════════════════════════════════════════════════════════════════
-- LOG DE EVENTOS BIOMETRICOS (raw data del dispositivo)
-- ══════════════════════════════════════════════════════════════════

log_biometrico
  id              UUID PK
  empresa_id      UUID FK -> empresas
  dispositivo_id  UUID FK -> dispositivos_biometricos
  empleado_id     UUID FK -> empleados    -- NULL si no se pudo identificar
  device_user_id  VARCHAR(50)             -- ID en el dispositivo
  timestamp       TIMESTAMPTZ NOT NULL    -- Hora exacta del evento
  tipo_evento     VARCHAR(20) NOT NULL    -- ENTRADA, SALIDA, DESCONOCIDO
  tipo_verificacion VARCHAR(20)           -- HUELLA, FACIAL, TARJETA, PIN
  exitoso         BOOLEAN DEFAULT true    -- false si fallo la verificacion
  raw_data        JSONB                   -- Datos crudos del dispositivo
  procesado       BOOLEAN DEFAULT false   -- Ya se convirtio en marcacion
  created_at      TIMESTAMPTZ DEFAULT now()

CREATE INDEX idx_log_biometrico_proc ON log_biometrico(empresa_id, procesado, timestamp);
CREATE INDEX idx_dispositivos_estado ON dispositivos_biometricos(empresa_id, estado);

permisos_ausencias
  id              UUID PK
  empresa_id      UUID FK -> empresas
  empleado_id     UUID FK -> empleados
  tipo            VARCHAR(30) NOT NULL
    -- VACACIONES, ENFERMEDAD, CALAMIDAD, MATERNIDAD, PATERNIDAD,
    -- PERSONAL, CAPACITACION, FALTA_INJUSTIFICADA
  fecha_desde     DATE NOT NULL
  fecha_hasta     DATE NOT NULL
  dias            INTEGER NOT NULL
  con_sueldo      BOOLEAN DEFAULT true
  documento_url   TEXT                   -- Certificado medico, etc.
  estado          VARCHAR(20) DEFAULT 'PENDIENTE'
    -- PENDIENTE, APROBADO, RECHAZADO
  aprobado_por    UUID FK -> auth.users
  notas           TEXT
```

**Dispositivos Biometricos Soportados**

```
╔══════════════════════════════════════════════════════════════════════════╗
║  METODOS DE MARCACION DE ASISTENCIA                                     ║
╠══════════════════════════════════════════════════════════════════════════╣
║                                                                          ║
║  1. DISPOSITIVOS AUTONOMOS (red TCP/IP o WiFi)                          ║
║     ┌─────────────────────────────────────────────────────────────┐      ║
║     │ Marca: ZKTeco (principal, mayor presencia en Ecuador)       │      ║
║     │ Modelos: K40, K50 (huella), MB160 (facial+huella),         │      ║
║     │          SpeedFace V5L (facial+huella+WiFi+4G),            │      ║
║     │          SENSEFACE M2F-LR (facial+huella+tarjeta)          │      ║
║     │ Protocolo: ZKTeco Push SDK → webhook HTTP POST             │      ║
║     │   - Marcacion en dispositivo → push instantaneo a server   │      ║
║     │   - Enrolamiento remoto de huellas/rostros via API         │      ║
║     │   - API REST via Cams Biometrics o directo TCP/IP          │      ║
║     │ Puerto default: 4370 (TCP/IP)                              │      ║
║     ├─────────────────────────────────────────────────────────────┤      ║
║     │ Marca: Hikvision (facial con camara IP)                     │      ║
║     │ Protocolo: ISAPI REST API                                   │      ║
║     ├─────────────────────────────────────────────────────────────┤      ║
║     │ Marca: Dahua (facial+huella)                                │      ║
║     │ Protocolo: HTTP API / SDK                                   │      ║
║     ├─────────────────────────────────────────────────────────────┤      ║
║     │ Generico: cualquier dispositivo con API REST/webhook        │      ║
║     └─────────────────────────────────────────────────────────────┘      ║
║                                                                          ║
║  2. DISPOSITIVOS USB (conectados a computador)                          ║
║     ┌─────────────────────────────────────────────────────────────┐      ║
║     │ Lectores de huella USB (DigitalPersona, ZKTeco, etc.)      │      ║
║     │ PILAR corre en modo kiosko en el PC con lector USB         │      ║
║     │ Empleado pone huella → app identifica → registra marcacion │      ║
║     │ Comunicacion: via Web USB API o app desktop nativa         │      ║
║     └─────────────────────────────────────────────────────────────┘      ║
║                                                                          ║
║  3. CELULAR / TABLET (biometria nativa del dispositivo)                 ║
║     ┌─────────────────────────────────────────────────────────────┐      ║
║     │ Flutter package: local_auth (oficial)                       │      ║
║     │ iOS: Face ID + Touch ID                                     │      ║
║     │ Android: huella dactilar + reconocimiento facial            │      ║
║     │ Flujo: empleado abre app → biometria local → GPS → marca   │      ║
║     │ Ventaja: sin hardware adicional, usa celular del empleado   │      ║
║     │ Verificacion: GPS + geocerca (radio configurable)           │      ║
║     └─────────────────────────────────────────────────────────────┘      ║
║                                                                          ║
║  4. TABLET EN MODO KIOSKO (punto de marcacion compartido)               ║
║     ┌─────────────────────────────────────────────────────────────┐      ║
║     │ Tablet Android/iPad fija en la entrada                      │      ║
║     │ App PILAR en modo kiosko (pantalla completa, sin salir)     │      ║
║     │ Empleado se identifica con:                                 │      ║
║     │   - Huella/Face ID nativo de la tablet (local_auth)         │      ║
║     │   - PIN personal                                            │      ║
║     │   - Escaneo QR de credencial                                │      ║
║     │ Opcion: conectar lector USB de huella a tablet Android      │      ║
║     └─────────────────────────────────────────────────────────────┘      ║
║                                                                          ║
║  5. WEB (sin hardware)                                                  ║
║     ┌─────────────────────────────────────────────────────────────┐      ║
║     │ Check-in desde navegador con verificacion de IP             │      ║
║     │ Opcional: Web Authentication API (WebAuthn) para biometria  │      ║
║     │ Ideal para trabajo remoto con geocerca por IP               │      ║
║     └─────────────────────────────────────────────────────────────┘      ║
║                                                                          ║
║  6. MANUAL (supervisor)                                                 ║
║     ┌─────────────────────────────────────────────────────────────┐      ║
║     │ Supervisor registra manualmente (requiere aprobacion)       │      ║
║     │ Para casos excepcionales: olvido, fallo dispositivo, etc.   │      ║
║     └─────────────────────────────────────────────────────────────┘      ║
║                                                                          ║
╠══════════════════════════════════════════════════════════════════════════╣
║  ARQUITECTURA DE INTEGRACION (Patron Adaptador)                         ║
║                                                                          ║
║  BiometricService (interfaz abstracta)                                  ║
║    ├── ZKTecoAdapter (Push SDK: webhook → Edge Function → BD)           ║
║    ├── HikvisionAdapter (ISAPI REST)                                    ║
║    ├── GenericAPIAdapter (HTTP REST generico)                            ║
║    └── LocalBiometricService (local_auth: huella/face del dispositivo)  ║
║                                                                          ║
║  Flujo dispositivo autonomo (ZKTeco/Hikvision):                         ║
║    Empleado marca en dispositivo                                         ║
║    → Dispositivo envia HTTP POST a Edge Function (webhook-biometric)    ║
║    → Edge Function valida + inserta en log_biometrico                   ║
║    → Trigger procesa log → crea/actualiza marcacion                     ║
║    → Supabase Realtime notifica al dashboard en tiempo real             ║
║                                                                          ║
║  Flujo celular/tablet (local_auth):                                     ║
║    Empleado abre app PILAR                                               ║
║    → local_auth verifica huella/Face ID nativo                          ║
║    → App captura GPS + valida geocerca                                  ║
║    → Inserta marcacion directamente via Supabase SDK                    ║
║                                                                          ║
║  Edge Function: webhook-biometric (verify_jwt: false)                   ║
║    - Recibe marcaciones de dispositivos autonomos via HTTP POST         ║
║    - Valida api_key del dispositivo                                     ║
║    - Identifica empleado por device_user_id                             ║
║    - Inserta en log_biometrico para procesamiento                       ║
║                                                                          ║
║  Edge Function: sync-biometric-device                                   ║
║    - Enrola/desenrola empleados en dispositivos remotamente             ║
║    - Sincroniza lista de usuarios dispositivo ↔ BD                     ║
║    - Consulta estado/conexion del dispositivo                           ║
║                                                                          ║
╚══════════════════════════════════════════════════════════════════════════╝
```

**RPCs de Horarios y Calculo**

```sql
-- ══════════════════════════════════════════════════════════════════
-- RPC: Generar planificacion diaria para un rango de fechas
-- Toma las asignaciones de horario y genera la agenda dia a dia
-- ══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION generate_daily_schedule(
  p_empresa_id UUID,
  p_fecha_desde DATE,
  p_fecha_hasta DATE,
  p_empleado_id UUID DEFAULT NULL  -- NULL = todos los empleados
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_count INTEGER := 0;
  rec_asig RECORD;
  v_fecha DATE;
  v_dia_ciclo INTEGER;
  v_turno_id UUID;
  v_dia_semana INTEGER;
  v_horario RECORD;
BEGIN
  -- Para cada empleado con asignacion activa en el rango
  FOR rec_asig IN
    SELECT a.*, e.id AS emp_id
    FROM asignaciones_horario a
    JOIN empleados e ON a.empleado_id = e.id
    WHERE a.empresa_id = p_empresa_id
      AND a.fecha_desde <= p_fecha_hasta
      AND (a.fecha_hasta IS NULL OR a.fecha_hasta >= p_fecha_desde)
      AND (p_empleado_id IS NULL OR a.empleado_id = p_empleado_id)
  LOOP
    -- Para cada dia del rango
    v_fecha := GREATEST(p_fecha_desde, rec_asig.fecha_desde);
    WHILE v_fecha <= LEAST(p_fecha_hasta, COALESCE(rec_asig.fecha_hasta, p_fecha_hasta)) LOOP

      -- Determinar turno del dia segun tipo de asignacion
      CASE rec_asig.tipo_asignacion
        WHEN 'TURNO_FIJO' THEN
          v_turno_id := rec_asig.turno_id;

        WHEN 'ROTACION' THEN
          -- Calcular en que dia del ciclo estamos
          v_dia_ciclo := ((v_fecha - rec_asig.fecha_inicio_ciclo) %
            (SELECT dias_ciclo FROM patrones_rotacion WHERE id = rec_asig.patron_id)) + 1;
          -- Obtener turno del dia del ciclo
          SELECT turno_id INTO v_turno_id
          FROM patron_rotacion_dias
          WHERE patron_id = rec_asig.patron_id AND dia_ciclo = v_dia_ciclo;

        ELSE -- MANUAL: no genera automaticamente, se crea a mano
          v_fecha := v_fecha + 1;
          CONTINUE;
      END CASE;

      -- Obtener horario del dia de la semana
      v_dia_semana := EXTRACT(ISODOW FROM v_fecha)::INTEGER; -- 1=Lun, 7=Dom
      SELECT * INTO v_horario
      FROM turno_horarios
      WHERE turno_id = v_turno_id AND dia_semana = v_dia_semana;

      -- Verificar si es feriado
      -- INSERT o UPDATE en planificacion_diaria
      INSERT INTO planificacion_diaria (
        empresa_id, empleado_id, fecha, turno_id,
        hora_entrada_esperada, hora_salida_esperada, horas_esperadas,
        es_laborable, es_feriado, origen, asignacion_id
      ) VALUES (
        p_empresa_id, rec_asig.empleado_id, v_fecha, v_turno_id,
        COALESCE(v_horario.hora_entrada, '08:00'),
        COALESCE(v_horario.hora_salida, '17:00'),
        COALESCE(v_horario.horas_efectivas, 8),
        COALESCE(v_horario.es_laborable, true)
          AND NOT EXISTS (SELECT 1 FROM feriados f
            WHERE (f.empresa_id IS NULL OR f.empresa_id = p_empresa_id)
              AND f.fecha = v_fecha),
        EXISTS (SELECT 1 FROM feriados f
          WHERE (f.empresa_id IS NULL OR f.empresa_id = p_empresa_id)
            AND f.fecha = v_fecha),
        'AUTOMATICO',
        rec_asig.id
      ) ON CONFLICT (empresa_id, empleado_id, fecha) DO NOTHING;
      -- No sobreescribe si ya fue modificada manualmente

      v_count := v_count + 1;
      v_fecha := v_fecha + 1;
    END LOOP;
  END LOOP;

  RETURN jsonb_build_object('dias_planificados', v_count);
END;
$$;

-- ══════════════════════════════════════════════════════════════════
-- RPC: Calcular resumen mensual de horas por empleado
-- Compara marcaciones reales vs planificacion esperada
-- Produce el insumo para el rol de pagos
-- ══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION calculate_monthly_hours(
  p_empresa_id UUID,
  p_empleado_id UUID,
  p_anio INTEGER,
  p_mes INTEGER
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_fecha_ini DATE;
  v_fecha_fin DATE;
  -- Acumuladores
  v_dias_laborables INTEGER := 0;
  v_dias_trabajados INTEGER := 0;
  v_dias_falta INTEGER := 0;
  v_dias_permiso INTEGER := 0;
  v_horas_normales DECIMAL(6,2) := 0;
  v_horas_suplementarias DECIMAL(6,2) := 0;  -- +50% (despues de jornada hasta 24:00)
  v_horas_extraordinarias DECIMAL(6,2) := 0; -- +100% (24:00-06:00, sab/dom/feriados)
  v_horas_nocturnas DECIMAL(6,2) := 0;       -- +25% (19:00-06:00 en jornada nocturna)
  v_minutos_atraso INTEGER := 0;
  v_sueldo DECIMAL(14,2);
  v_valor_hora DECIMAL(14,6);
  rec RECORD;
BEGIN
  v_fecha_ini := make_date(p_anio, p_mes, 1);
  v_fecha_fin := (v_fecha_ini + INTERVAL '1 month' - INTERVAL '1 day')::DATE;

  -- Obtener sueldo del empleado
  SELECT sueldo INTO v_sueldo
  FROM empleados WHERE id = p_empleado_id AND empresa_id = p_empresa_id;

  -- Valor hora = sueldo / 240 (Codigo Trabajo Ecuador: 30 dias * 8 horas)
  v_valor_hora := v_sueldo / 240;

  -- Recorrer cada dia del mes
  FOR rec IN
    SELECT
      p.fecha, p.turno_id, p.hora_entrada_esperada, p.hora_salida_esperada,
      p.horas_esperadas, p.es_laborable, p.es_feriado,
      m.hora_entrada AS marca_entrada, m.hora_salida AS marca_salida,
      m.horas_trabajadas AS marca_horas, m.atraso_minutos,
      m.estado AS marca_estado,
      t.tipo_jornada, t.descuenta_almuerzo, t.minutos_almuerzo,
      t.permite_horas_extras, t.max_extras_dia
    FROM planificacion_diaria p
    LEFT JOIN marcaciones m ON m.empleado_id = p.empleado_id
      AND m.fecha = p.fecha AND m.empresa_id = p.empresa_id
    LEFT JOIN turnos t ON p.turno_id = t.id
    WHERE p.empresa_id = p_empresa_id
      AND p.empleado_id = p_empleado_id
      AND p.fecha BETWEEN v_fecha_ini AND v_fecha_fin
    ORDER BY p.fecha
  LOOP
    IF rec.es_laborable THEN
      v_dias_laborables := v_dias_laborables + 1;

      IF rec.marca_entrada IS NOT NULL THEN
        v_dias_trabajados := v_dias_trabajados + 1;
        v_minutos_atraso := v_minutos_atraso + COALESCE(rec.atraso_minutos, 0);

        -- Calcular horas trabajadas del dia
        DECLARE
          v_horas_dia DECIMAL(6,2);
          v_exceso DECIMAL(6,2);
        BEGIN
          v_horas_dia := COALESCE(rec.marca_horas, 0);

          -- Horas normales (hasta la jornada contratada)
          v_horas_normales := v_horas_normales + LEAST(v_horas_dia, rec.horas_esperadas);

          -- Horas extras (exceso sobre jornada)
          v_exceso := GREATEST(v_horas_dia - rec.horas_esperadas, 0);
          IF v_exceso > 0 AND rec.permite_horas_extras THEN
            -- Limitar al maximo diario
            v_exceso := LEAST(v_exceso, rec.max_extras_dia);

            -- Clasificar: suplementarias vs extraordinarias
            IF rec.es_feriado THEN
              -- Feriado: TODO es extraordinario (+100%)
              v_horas_extraordinarias := v_horas_extraordinarias + v_exceso;
            ELSIF EXTRACT(ISODOW FROM rec.fecha) IN (6, 7) THEN
              -- Sabado/Domingo: extraordinario (+100%)
              v_horas_extraordinarias := v_horas_extraordinarias + v_exceso;
            ELSE
              -- Dia normal: suplementario (+50%) hasta 24:00
              -- Si trabaja despues de medianoche → extraordinario (+100%)
              v_horas_suplementarias := v_horas_suplementarias + v_exceso;
              -- Nota: la distincion exacta por hora se refina con hora_salida real
            END IF;
          END IF;

          -- Recargo nocturno (19:00-06:00) segun Codigo Trabajo art. 49
          IF rec.tipo_jornada = 'NOCTURNA' THEN
            v_horas_nocturnas := v_horas_nocturnas + LEAST(v_horas_dia, rec.horas_esperadas);
          END IF;
        END;
      ELSE
        -- No marco → verificar si tiene permiso aprobado
        IF EXISTS (
          SELECT 1 FROM permisos_ausencias
          WHERE empleado_id = p_empleado_id
            AND estado = 'APROBADO'
            AND rec.fecha BETWEEN fecha_desde AND fecha_hasta
        ) THEN
          v_dias_permiso := v_dias_permiso + 1;
          -- Si es con sueldo, cuenta como horas normales
          IF (SELECT con_sueldo FROM permisos_ausencias
              WHERE empleado_id = p_empleado_id AND estado = 'APROBADO'
                AND rec.fecha BETWEEN fecha_desde AND fecha_hasta LIMIT 1
          ) THEN
            v_horas_normales := v_horas_normales + rec.horas_esperadas;
          END IF;
        ELSE
          v_dias_falta := v_dias_falta + 1;
        END IF;
      END IF;

    ELSE
      -- Dia no laborable pero con marcacion → extraordinarias (+100%)
      IF rec.marca_entrada IS NOT NULL THEN
        v_horas_extraordinarias := v_horas_extraordinarias +
          LEAST(COALESCE(rec.marca_horas, 0), COALESCE(rec.max_extras_dia, 4));
      END IF;
    END IF;
  END LOOP;

  -- Validar limites mensuales de extras (Codigo Trabajo)
  -- Max 60 horas extras/mes combinadas
  IF (v_horas_suplementarias + v_horas_extraordinarias) > 60 THEN
    v_horas_suplementarias := LEAST(v_horas_suplementarias, 60);
    v_horas_extraordinarias := LEAST(v_horas_extraordinarias, 60 - v_horas_suplementarias);
  END IF;

  RETURN jsonb_build_object(
    'empleado_id', p_empleado_id,
    'periodo', p_anio || '-' || lpad(p_mes::text, 2, '0'),
    'sueldo_base', v_sueldo,
    'valor_hora', ROUND(v_valor_hora, 6),
    -- Dias
    'dias_laborables', v_dias_laborables,
    'dias_trabajados', v_dias_trabajados,
    'dias_falta_injustificada', v_dias_falta,
    'dias_permiso', v_dias_permiso,
    'minutos_atraso_total', v_minutos_atraso,
    -- Horas
    'horas_normales', ROUND(v_horas_normales, 2),
    'horas_suplementarias', ROUND(v_horas_suplementarias, 2),        -- +50%
    'horas_extraordinarias', ROUND(v_horas_extraordinarias, 2),      -- +100%
    'horas_nocturnas', ROUND(v_horas_nocturnas, 2),                  -- +25%
    -- Valores monetarios (insumo para nomina)
    'valor_horas_normales', ROUND(v_horas_normales * v_valor_hora, 2),
    'valor_suplementarias', ROUND(v_horas_suplementarias * v_valor_hora * 1.5, 2),
    'valor_extraordinarias', ROUND(v_horas_extraordinarias * v_valor_hora * 2.0, 2),
    'valor_recargo_nocturno', ROUND(v_horas_nocturnas * v_valor_hora * 0.25, 2),
    'descuento_faltas', ROUND(v_dias_falta * v_sueldo / 30, 2),
    'descuento_atrasos', ROUND((v_minutos_atraso / 60.0) * v_valor_hora, 2)
  );
END;
$$;

-- ══════════════════════════════════════════════════════════════════
-- RPC: Procesar log biometrico → marcaciones
-- ══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION process_biometric_log(
  p_empresa_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_procesados INTEGER := 0;
  rec RECORD;
BEGIN
  FOR rec IN
    SELECT * FROM log_biometrico
    WHERE empresa_id = p_empresa_id AND procesado = false AND exitoso = true
    ORDER BY timestamp
  LOOP
    -- Determinar si es entrada o salida
    -- Si no tiene marcacion hoy → es entrada
    -- Si ya tiene entrada pero no salida → es salida
    IF NOT EXISTS (
      SELECT 1 FROM marcaciones
      WHERE empleado_id = rec.empleado_id AND fecha = rec.timestamp::DATE
        AND empresa_id = p_empresa_id
    ) THEN
      -- Primera marcacion del dia = ENTRADA
      INSERT INTO marcaciones (empresa_id, empleado_id, fecha, hora_entrada,
        metodo_entrada, dispositivo_entrada_id)
      VALUES (p_empresa_id, rec.empleado_id, rec.timestamp::DATE, rec.timestamp,
        rec.tipo_verificacion || '_DISPOSITIVO', rec.dispositivo_id);
    ELSE
      -- Marcacion posterior = SALIDA (actualiza la ultima)
      UPDATE marcaciones SET
        hora_salida = rec.timestamp,
        metodo_salida = rec.tipo_verificacion || '_DISPOSITIVO',
        dispositivo_salida_id = rec.dispositivo_id,
        horas_trabajadas = ROUND(EXTRACT(EPOCH FROM (rec.timestamp - hora_entrada)) / 3600.0, 2)
      WHERE empleado_id = rec.empleado_id AND fecha = rec.timestamp::DATE
        AND empresa_id = p_empresa_id;
    END IF;

    -- Marcar como procesado
    UPDATE log_biometrico SET procesado = true WHERE id = rec.id;
    v_procesados := v_procesados + 1;
  END LOOP;

  RETURN jsonb_build_object('procesados', v_procesados);
END;
$$;
```

**Integraciones Asistencia → Nomina → Contabilidad**

```
╔══════════════════════════════════════════════════════════════════════════╗
║  FLUJO COMPLETO: ASISTENCIA → NOMINA → CONTABILIDAD                    ║
╠══════════════════════════════════════════════════════════════════════════╣
║                                                                          ║
║  1. REGISTRO DIARIO                                                     ║
║     Empleados marcan entrada/salida (biometrico, app, web, manual)      ║
║     → Sistema registra en tabla marcaciones                             ║
║     → Calcula horas_trabajadas y atraso_minutos automaticamente         ║
║                                                                          ║
║  2. COMPARACION CON PLANIFICACION                                       ║
║     Cada marcacion se compara con planificacion_diaria del empleado:    ║
║     ┌─────────────────────────────────────────────────────────────┐      ║
║     │ hora_entrada_real vs hora_entrada_esperada → atraso         │      ║
║     │ hora_salida_real vs hora_salida_esperada → horas extras     │      ║
║     │ dia no laborable + marcacion → extraordinarias +100%        │      ║
║     │ feriado + marcacion → extraordinarias +100%                 │      ║
║     │ jornada nocturna → recargo nocturno +25%                    │      ║
║     │ sin marcacion + sin permiso → falta injustificada           │      ║
║     └─────────────────────────────────────────────────────────────┘      ║
║                                                                          ║
║  3. CALCULO MENSUAL (calculate_monthly_hours)                           ║
║     Al cerrar el mes, genera resumen por empleado:                      ║
║     - Horas normales (valor_hora = sueldo / 240)                       ║
║     - Horas suplementarias × valor_hora × 1.50 (+50%)                  ║
║     - Horas extraordinarias × valor_hora × 2.00 (+100%)                ║
║     - Recargo nocturno × valor_hora × 0.25 (+25%)                      ║
║     - Descuento por faltas (dias_falta × sueldo / 30)                  ║
║     - Descuento por atrasos (minutos_atraso / 60 × valor_hora)         ║
║     Limites Codigo Trabajo: max 4h/dia, 12h/semana, 60h/mes            ║
║                                                                          ║
║  4. NOMINA (calculate_payroll del modulo RRHH)                        ║
║     Consume el JSON de calculate_monthly_hours para cada empleado:      ║
║     ┌─ INGRESOS ─────────────────────────────────────────────────┐      ║
║     │ + Sueldo base (proporcional a dias trabajados)             │      ║
║     │ + Horas suplementarias                                      │      ║
║     │ + Horas extraordinarias                                     │      ║
║     │ + Recargo nocturno                                          │      ║
║     │ + Comisiones / bonos                                        │      ║
║     ├─ EGRESOS ──────────────────────────────────────────────────┤      ║
║     │ - IESS personal (9.45% sobre base IESS)                   │      ║
║     │ - Retencion impuesto renta (tabla progresiva)              │      ║
║     │ - Descuento faltas injustificadas                           │      ║
║     │ - Descuento atrasos                                         │      ║
║     │ - Prestamos / anticipos (cuotas del mes)                    │      ║
║     │ - Compras almacen (cuotas del mes)                          │      ║
║     ├─ PROVISIONES (patronal) ───────────────────────────────────┤      ║
║     │ + IESS patronal (11.15%)                                   │      ║
║     │ + Fondos de reserva (8.33%, desde mes 13)                  │      ║
║     │ + Decimo tercero (1/12 mensual)                            │      ║
║     │ + Decimo cuarto (SBU/12 mensual)                           │      ║
║     │ + Vacaciones (proporcional)                                 │      ║
║     └────────────────────────────────────────────────────────────┘      ║
║                                                                          ║
║  5. CONTABILIDAD (asiento automatico)                                   ║
║     El rol de pagos genera asiento contable con:                        ║
║     ┌─ DEBE ─────────────────────────────────────────────────────┐      ║
║     │ Gasto sueldos y salarios (cuenta configurable)             │      ║
║     │ Gasto horas extras                                          │      ║
║     │ Gasto aporte patronal IESS                                 │      ║
║     │ Gasto fondos de reserva                                     │      ║
║     │ Gasto decimo tercero                                        │      ║
║     │ Gasto decimo cuarto                                         │      ║
║     │ Gasto vacaciones                                            │      ║
║     ├─ HABER ────────────────────────────────────────────────────┤      ║
║     │ Sueldos por pagar (neto a pagar al empleado)               │      ║
║     │ IESS por pagar (personal + patronal)                       │      ║
║     │ Retencion IR por pagar                                      │      ║
║     │ Provision decimo tercero por pagar                          │      ║
║     │ Provision decimo cuarto por pagar                           │      ║
║     │ Provision vacaciones por pagar                              │      ║
║     │ Fondos de reserva por pagar                                 │      ║
║     │ Prestamos por cobrar (descuento prestamos/anticipos)        │      ║
║     │ Cuentas por cobrar empleados (descuento compras almacen)   │      ║
║     └────────────────────────────────────────────────────────────┘      ║
║                                                                          ║
║  6. PAGO (Tesoreria / Archivo Bancario)                                 ║
║     Opcion A: Archivo bancario (generate_bank_file)                     ║
║     → Genera CSV/TXT con formato del banco destino                      ║
║     → Agrupa empleados por banco (un archivo por banco)                 ║
║     → RRHH descarga y sube al portal del banco                          ║
║     → Al confirmar procesamiento: Sueldos por pagar (D) / Banco (H)    ║
║     Opcion B: Transferencia individual o cheque                         ║
║     → Para empleados sin cuenta bancaria registrada                     ║
║     → Asiento: Sueldos por pagar (D) / Banco o Caja (H)                ║
║                                                                          ║
║  7. ENVIO ROL INDIVIDUAL (multi-canal)                                  ║
║     → Genera PDF individual por empleado (payslip_pdf_service.dart)     ║
║     → Envia por canal preferido del empleado:                           ║
║       Email (Resend) / WhatsApp (Cloud API) / Telegram (Bot API)        ║
║     → Envio individual o masivo a todos los empleados                   ║
║     → Registra en envios_rol_pago con estado de entrega                 ║
║                                                                          ║
╚══════════════════════════════════════════════════════════════════════════╝
```

**Configuracion por empresa**

```
- Cada empresa define sus turnos, horarios por dia, y patrones de rotacion
- Puede combinar: dispositivos biometricos en oficina + app movil para campo
- Geocerca configurable por establecimiento (radio en metros)
- Tolerancias de atraso y salida configurables por turno
- Feriados nacionales pre-cargados + feriados locales por empresa/establecimiento
- Planificacion se genera automaticamente desde asignaciones/rotaciones
- Supervisor puede modificar planificacion manualmente (excepciones)
- Empleados pueden solicitar intercambio de turno (con aprobacion)
- Dashboard en tiempo real: marcaciones del dia, atrasos, ausencias
- Reportes: asistencia mensual, horas extras, atrasos, comparativo planificado vs real
```

**Evaluaciones de Desempeno (G-RRHH-01)**

```sql
CREATE TABLE periodos_evaluacion (
  id UUID PK, empresa_id UUID FK, nombre VARCHAR(100),
  fecha_inicio DATE, fecha_fin DATE,
  estado VARCHAR(20) DEFAULT 'PLANIFICADO' -- PLANIFICADO, EN_CURSO, FINALIZADO
);
CREATE TABLE evaluaciones_desempeno (
  id UUID PK, empresa_id UUID FK, periodo_id UUID FK -> periodos_evaluacion,
  empleado_id UUID FK -> empleados, evaluador_id UUID FK -> empleados,
  fecha DATE DEFAULT CURRENT_DATE, puntaje_total DECIMAL(5,2),
  estado VARCHAR(20) DEFAULT 'BORRADOR', -- BORRADOR, EN_REVISION, COMPLETADA
  comentarios TEXT, UNIQUE(periodo_id, empleado_id, evaluador_id)
);
CREATE TABLE evaluacion_criterios (
  id UUID PK, evaluacion_id UUID FK ON DELETE CASCADE,
  criterio VARCHAR(200), peso DECIMAL(5,2), puntaje DECIMAL(5,2), comentario TEXT
);
CREATE TABLE planes_mejora (
  id UUID PK, evaluacion_id UUID FK, objetivo TEXT, fecha_limite DATE,
  estado VARCHAR(20) DEFAULT 'PENDIENTE', seguimiento TEXT
);
```

**Portal Self-Service Empleado (G-RRHH-04)**

```sql
-- Capacidades: ver rol pagos, certificado laboral PDF, solicitar vacaciones
-- (workflow solicitud->jefe->RRHH), saldo vacaciones, actualizar datos, asistencia.
CREATE TABLE solicitudes_empleado (
  id UUID PK, empresa_id UUID FK, empleado_id UUID FK -> empleados,
  tipo VARCHAR(20) NOT NULL, -- VACACIONES/PERMISO/ANTICIPO/CERTIFICADO/ACTUALIZACION_DATOS
  estado VARCHAR(20) DEFAULT 'PENDIENTE', -- PENDIENTE/APROBADA/RECHAZADA
  datos JSONB NOT NULL, -- {fecha_inicio,fecha_fin,dias,motivo} etc segun tipo
  aprobado_por UUID FK -> auth.users, fecha_respuesta TIMESTAMPTZ,
  comentario_respuesta TEXT, created_at TIMESTAMPTZ DEFAULT NOW()
);
```

**Control Saldo Vacaciones (G-RRHH-06)**

```sql
-- 15 dias base + 1/anio desde 5to (Art.69 CT). Max 30. Acumula max 3 anios.
CREATE TABLE saldo_vacaciones (
  id UUID PK, empresa_id UUID FK, empleado_id UUID FK, anio INTEGER,
  dias_derecho DECIMAL(5,2) DEFAULT 15, dias_adicionales_antiguedad DECIMAL(5,2) DEFAULT 0,
  dias_tomados DECIMAL(5,2) DEFAULT 0,
  dias_pendientes DECIMAL(5,2) GENERATED ALWAYS AS
    (dias_derecho + dias_adicionales_antiguedad - dias_tomados) STORED,
  UNIQUE(empresa_id, empleado_id, anio)
);
-- RPC calculate_vacation_balance(empresa_id, empleado_id) -> {anios_servicio, dias_derecho, saldos[]}
```

**Jubilacion Patronal (G-RRHH-08)**

```sql
-- Art.216 CT: obligatoria 25 anios. Provision NIC 19 desde 10 anios.
CREATE TABLE provisiones_jubilacion (
  id UUID PK, empresa_id UUID FK, empleado_id UUID FK, anio INTEGER,
  anios_servicio INTEGER, sueldo_promedio DECIMAL(14,2),
  provision_mensual DECIMAL(14,2), provision_acumulada DECIMAL(14,2),
  asiento_id UUID FK -> asientos, UNIQUE(empresa_id, empleado_id, anio)
);
-- RPC calculate_jubilation_provision(empresa_id, anio) -> [{empleado, provision_mensual, acumulado}]
```

**RDEP Formato DIMM (G-RRHH-10)**

```sql
-- Obligacion anual SRI (febrero). XML formato DIMM.
-- RPC generate_rdep(empresa_id, anio) -> {xml_content, total_empleados, resumen}
-- Calcula por empleado: ingresos gravados, IESS 9.45%, gastos deducibles,
-- base imponible, IR causado (tabla progresiva), IR retenido en roles.
-- XML: <rdep><empleados><empleado><cedula/><sueldosYSalarios/><aporteIESS/>
--   <gastosPersonales/><baseImponible/><irCausado/><irRetenido/></empleado>...
```

**Reclutamiento y Seleccion (G-RRHH-02)**

```sql
CREATE TABLE vacantes (
  id UUID PK, empresa_id UUID FK, departamento_id UUID FK -> departamentos,
  cargo_id UUID FK -> cargos, titulo VARCHAR(200), descripcion TEXT,
  requisitos TEXT,
  estado VARCHAR(20) DEFAULT 'ABIERTA', -- ABIERTA/EN_PROCESO/CERRADA/CANCELADA
  fecha_publicacion DATE, fecha_cierre DATE
);
CREATE TABLE postulaciones (
  id UUID PK, vacante_id UUID FK -> vacantes ON DELETE CASCADE,
  nombre VARCHAR(200), email VARCHAR(200), telefono VARCHAR(20),
  cv_url TEXT, -- PDF en Supabase Storage
  etapa VARCHAR(20) DEFAULT 'RECIBIDA',
    -- RECIBIDA/PRESELECCION/ENTREVISTA/PRUEBA/OFERTA/CONTRATADA/RECHAZADA
  puntaje DECIMAL(5,2), notas TEXT
);
```

**Capacitacion / Formacion (G-RRHH-03)**

```sql
CREATE TABLE cursos_capacitacion (
  id UUID PK, empresa_id UUID FK, nombre VARCHAR(200),
  proveedor VARCHAR(200), horas INTEGER, costo DECIMAL(14,2),
  certificacion BOOLEAN DEFAULT false
);
CREATE TABLE asistencia_capacitacion (
  id UUID PK, curso_id UUID FK -> cursos_capacitacion,
  empleado_id UUID FK -> empleados, fecha DATE,
  estado VARCHAR(20) DEFAULT 'INSCRITO', -- INSCRITO/COMPLETADO/REPROBADO
  nota DECIMAL(5,2), certificado_url TEXT
);
-- Tracking de costo capacitacion por departamento/empleado para control presupuestario.
-- Reporte: horas capacitacion por empleado, costo por departamento, certificaciones vigentes.
```

---

