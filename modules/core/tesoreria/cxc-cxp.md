# Cuentas por Cobrar, Cuentas por Pagar, Control de Crédito y Planes de Pago


Este sub-sistema es transversal a Ventas, Compras y Tesoreria. Gestiona todas las deudas
pendientes (CxC y CxP), control de credito para clientes, planes de pago a proveedores,
cobros/pagos con metodos mixtos, y reportes de cartera.

**Relacion entre factura_pagos (SRI) y cobro_metodos (real)**

```
╔══════════════════════════════════════════════════════════════════════════╗
║  FORMAS DE PAGO: SRI vs REAL                                            ║
╠══════════════════════════════════════════════════════════════════════════╣
║                                                                          ║
║  factura_pagos (tabla existente) → va en el XML del SRI                 ║
║  - Es DECLARATIVA: indica como se COMPROMETE a pagar el cliente         ║
║  - Se genera AUTOMATICAMENTE a partir de los cobro_metodos reales       ║
║  - Mapeo de metodos reales a codigos SRI:                               ║
║    ┌───────────────────────────┬────────────────────────────────┐       ║
║    │ cobro_metodos.metodo      │ factura_pagos.forma_pago (SRI) │       ║
║    │ EFECTIVO                  │ 01 (Sin sistema financiero)     │       ║
║    │ CHEQUE                    │ 20 (Otros sist. financiero)     │       ║
║    │ TRANSFERENCIA             │ 20 (Otros sist. financiero)     │       ║
║    │ DEPOSITO                  │ 20 (Otros sist. financiero)     │       ║
║    │ TARJETA_CREDITO           │ 16 nacional / 17 internacional  │       ║
║    │ TARJETA_DEBITO            │ 18 nacional / 19 internacional  │       ║
║    │ RETENCION                 │ 15 (Compensacion de deudas)     │       ║
║    │ NOTA_CREDITO              │ 15 (Compensacion de deudas)     │       ║
║    └───────────────────────────┴────────────────────────────────┘       ║
║                                                                          ║
║  VENTA AL CONTADO (pago inmediato):                                     ║
║    - cobro_metodos se registran al emitir la factura                    ║
║    - factura_pagos se genera con plazo=0                                ║
║    - CxC se crea y se marca PAGADA inmediatamente                       ║
║                                                                          ║
║  VENTA A CREDITO (pago diferido):                                       ║
║    - factura_pagos con plazo > 0 (ej: 30 dias, 60 dias)                ║
║    - CxC se crea con estado PENDIENTE                                   ║
║    - Los cobros se registran despues, cuando el cliente paga            ║
║                                                                          ║
║  VENTA MIXTA (parte contado + parte credito):                           ║
║    - Ej: $500 total → $200 contado + $300 en 3 cuotas mensuales        ║
║    - factura_pagos genera 2 registros:                                  ║
║      {forma_pago: "01", total: 200, plazo: 0}     (contado)            ║
║      {forma_pago: "20", total: 300, plazo: 30}    (credito)            ║
║    - cobro_metodos del $200: efectivo/$100 + tarjeta/$100               ║
║    - CxC se crea por $300 con cuotas: $100 a 30d, $100 a 60d, $100 90d║
║                                                                          ║
╚══════════════════════════════════════════════════════════════════════════╝
```

**Flujo de Venta con Pago Mixto**

```
╔══════════════════════════════════════════════════════════════════════════╗
║  FLUJO: CREAR FACTURA CON PAGO MIXTO                                    ║
╠══════════════════════════════════════════════════════════════════════════╣
║                                                                          ║
║  1. DATOS DE FACTURA                                                     ║
║     Usuario selecciona cliente, agrega productos, revisa totales        ║
║     Total factura: $1,150.00 (con IVA)                                  ║
║                                                                          ║
║  2. VERIFICACION DE CREDITO (automatica si es a credito)                ║
║     ┌─────────────────────────────────────────────────────────────┐     ║
║     │ check_credit_status(empresa_id, contacto_id, monto_venta)  │     ║
║     │                                                             │     ║
║     │ Verifica:                                                   │     ║
║     │ a) Cliente tiene_credito = true?                            │     ║
║     │ b) saldo_credito + monto_venta <= limite_credito?           │     ║
║     │ c) Facturas vencidas < max_facturas_vencidas?               │     ║
║     │ d) Monto vencido < max_monto_vencido?                      │     ║
║     │ e) Cliente no esta bloqueado?                               │     ║
║     │                                                             │     ║
║     │ Si FALLA cualquier check:                                   │     ║
║     │ → Muestra alerta con motivo del bloqueo                    │     ║
║     │ → Opcion: "Solicitar autorizacion de supervisor"            │     ║
║     │ → Supervisor ingresa credenciales + motivo                  │     ║
║     │ → Se registra en excepciones_credito (auditoria)           │     ║
║     │ → Permite continuar la venta excepcionalmente              │     ║
║     └─────────────────────────────────────────────────────────────┘     ║
║                                                                          ║
║  3. FORMA DE PAGO (pantalla de cobro)                                   ║
║     ┌─────────────────────────────────────────────────────────────┐     ║
║     │ Total a pagar: $1,150.00                                    │     ║
║     │                                                             │     ║
║     │ [+ Agregar metodo de pago]                                  │     ║
║     │                                                             │     ║
║     │ Metodo 1: EFECTIVO .............. $  300.00                 │     ║
║     │ Metodo 2: TARJETA CREDITO ....... $  200.00                 │     ║
║     │           Visa **** 4532  Auth: 123456                      │     ║
║     │ Metodo 3: RETENCION ............. $   50.00                 │     ║
║     │           Ret 001-001-000000045 (cruce)                     │     ║
║     │ Metodo 4: CREDITO (cuotas) ...... $  600.00                 │     ║
║     │           3 cuotas × $200.00 c/30 dias                     │     ║
║     │                                                             │     ║
║     │ Subtotal contado:  $550.00  ✓ Cubierto                     │     ║
║     │ Subtotal credito:  $600.00  ✓ Dentro de limite             │     ║
║     │ TOTAL:           $1,150.00  ✓ Balanceado                   │     ║
║     │                                                             │     ║
║     │ [Emitir Factura]                                            │     ║
║     └─────────────────────────────────────────────────────────────┘     ║
║                                                                          ║
║  4. AL CONFIRMAR:                                                        ║
║     a. Crea factura con lineas, impuestos                               ║
║     b. Genera factura_pagos (SRI) mapeando metodos a codigos SRI       ║
║     c. Crea CxC por el total ($1,150.00)                                ║
║     d. Registra cobro inmediato por la parte contado ($550.00):         ║
║        - cobro_metodos: EFECTIVO $300, TARJETA $200, RETENCION $50     ║
║        - cobro_documentos: aplica $550 a la CxC                        ║
║        - Marca retencion como cruzada (no reutilizable)                 ║
║     e. Genera cuotas_credito por la parte a credito ($600.00):          ║
║        - Cuota 1: $200 vence 17/03/2026                                ║
║        - Cuota 2: $200 vence 16/04/2026                                ║
║        - Cuota 3: $200 vence 16/05/2026                                ║
║     f. CxC queda con saldo = $600 y estado = PARCIAL                   ║
║     g. Actualiza saldo_credito del cliente (+$600)                      ║
║     h. Firma XML → envia SRI → genera RIDE                             ║
║     i. Asiento contable:                                                ║
║        DEBE: Caja $300 + Banco $200 + Ret recibidas $50 + CxC $600    ║
║        HABER: Ventas $1,000 + IVA cobrado $150                         ║
║                                                                          ║
║  CRUCE CON NOTAS DE CREDITO:                                            ║
║  - Si el cliente tiene NC no aplicadas, se pueden cruzar como metodo   ║
║  - Ej: NC por $80 → agrega como metodo NOTA_CREDITO $80               ║
║  - La NC queda marcada como aplicada (no reutilizable)                  ║
║  - Solo NC del mismo cliente y no aplicadas previamente                 ║
║                                                                          ║
╚══════════════════════════════════════════════════════════════════════════╝
```

**Plan de Pagos a Proveedores**

```
╔══════════════════════════════════════════════════════════════════════════╗
║  FLUJO: PLAN DE PAGO A PROVEEDORES                                      ║
╠══════════════════════════════════════════════════════════════════════════╣
║                                                                          ║
║  1. LISTADO DE CxP (cuentas_por_pagar)                                 ║
║     Pantalla muestra todas las deudas con proveedores:                  ║
║     ┌─────────────────────────────────────────────────────────────┐     ║
║     │ ☐ │ Proveedor      │ Documento        │ Vence   │ Saldo    │     ║
║     │ ☑ │ ProveedorA     │ Fact 001-345     │ 10/02  │ $500.00  │     ║
║     │ ☑ │ ProveedorA     │ Fact 001-346     │ 15/02  │ $300.00  │     ║
║     │ ☑ │ ProveedorB     │ Fact 002-100     │ 20/02  │ $1,200   │     ║
║     │ ☐ │ ProveedorC     │ Fact 003-050     │ 28/02  │ $800.00  │     ║
║     │                                                             │     ║
║     │ Seleccionados: 3 docs, Total: $2,000.00                    │     ║
║     │ [Agregar a Plan Existente ▼] [Crear Nuevo Plan]             │     ║
║     └─────────────────────────────────────────────────────────────┘     ║
║                                                                          ║
║  2. CREAR/EDITAR PLAN DE PAGO                                           ║
║     ┌─────────────────────────────────────────────────────────────┐     ║
║     │ Plan: "Pagos Febrero 2da quincena"                          │     ║
║     │ Fecha programada: 18/02/2026                                │     ║
║     │                                                             │     ║
║     │ DETALLE POR DOCUMENTO:                                      │     ║
║     │ Proveedor A - Fact 001-345                                  │     ║
║     │   Saldo: $500.00  Pagar: [$500.00]  Metodo: [Transferencia]│     ║
║     │                                                             │     ║
║     │ Proveedor A - Fact 001-346                                  │     ║
║     │   Saldo: $300.00  Pagar: [$300.00]  Metodo: [Transferencia]│     ║
║     │                                                             │     ║
║     │ Proveedor B - Fact 002-100                                  │     ║
║     │   Saldo: $1,200   Pagar: [$800.00]  Metodo: [Cheque]       │     ║
║     │   (pago parcial: queda saldo $400)                          │     ║
║     │                                                             │     ║
║     │ RESUMEN POR PROVEEDOR:                                      │     ║
║     │   ProveedorA: $800.00 (2 docs) → Transferencia              │     ║
║     │   ProveedorB: $800.00 (1 doc)  → Cheque                     │     ║
║     │                                                             │     ║
║     │ RESUMEN POR METODO:                                          │     ║
║     │   Transferencias: $800.00                                    │     ║
║     │   Cheques: $800.00                                           │     ║
║     │   TOTAL PLAN: $1,600.00                                      │     ║
║     │                                                             │     ║
║     │ [Guardar Borrador] [Enviar a Aprobacion]                    │     ║
║     └─────────────────────────────────────────────────────────────┘     ║
║                                                                          ║
║  3. APROBACION                                                           ║
║     - Gerencia revisa el plan                                           ║
║     - Puede modificar montos o metodos                                  ║
║     - Aprueba → estado: APROBADO                                        ║
║                                                                          ║
║  4. EJECUCION DEL PAGO                                                  ║
║     - RRHH/Tesoreria ejecuta los pagos del plan                        ║
║     - Por cada linea del plan:                                          ║
║       → Crea pago_proveedor con pago_metodos y pago_documentos         ║
║       → Si es cheque: crea cheque en modulo Tesoreria                   ║
║       → Si es transferencia: crea transferencia en Tesoreria            ║
║       → Actualiza saldo en cuentas_por_pagar                           ║
║       → Genera asiento contable: CxP (D) / Banco (H)                   ║
║       → Al cruzar retencion emitida: CxP (D) / Ret por pagar (H)      ║
║     - Plan pasa a estado: PAGADO cuando todos los items estan pagados   ║
║                                                                          ║
╚══════════════════════════════════════════════════════════════════════════╝
```

**Reportes de Cartera (en pantalla + PDF/Excel)**

```
╔══════════════════════════════════════════════════════════════════════════╗
║  REPORTES DE CARTERA Y CxC/CxP                                         ║
╠══════════════════════════════════════════════════════════════════════════╣
║                                                                          ║
║  1. CARTERA VENCIDA (Aging Report) - CxC                                ║
║     ┌──────────────────────────────────────────────────────────────┐    ║
║     │ Cliente    │ Por vencer │ 1-30d  │ 31-60d │ 61-90d │ 90+d  │    ║
║     │ Cliente A  │   $500     │ $300   │ $200   │   $0   │  $0   │    ║
║     │ Cliente B  │     $0     │   $0   │ $800   │ $400   │ $100  │    ║
║     │ ...        │            │        │        │        │       │    ║
║     │ TOTAL      │   $500     │ $300   │ $1,000 │ $400   │ $100  │    ║
║     └──────────────────────────────────────────────────────────────┘    ║
║     Filtros: rango fechas, cliente, vendedor, estado                    ║
║     Exportar: [PDF] [Excel]                                             ║
║                                                                          ║
║  2. CARTERA POR PAGAR (Aging Report) - CxP                             ║
║     Mismo formato pero para proveedores                                 ║
║     Filtros: rango fechas, proveedor, estado                            ║
║     Exportar: [PDF] [Excel]                                             ║
║                                                                          ║
║  3. ESTADO DE CUENTA (por cliente o proveedor)                          ║
║     ┌──────────────────────────────────────────────────────────────┐    ║
║     │ Fecha     │ Documento         │ Debe     │ Haber   │ Saldo  │    ║
║     │ 01/01/26  │ Saldo anterior    │          │         │ $500   │    ║
║     │ 05/01/26  │ Fact 001-001-123  │ $1,150   │         │ $1,650 │    ║
║     │ 10/01/26  │ Cobro #045        │          │ $800    │ $850   │    ║
║     │ 15/01/26  │ NC 001-001-005    │          │ $150    │ $700   │    ║
║     │ 20/01/26  │ Fact 001-001-124  │ $300     │         │ $1,000 │    ║
║     │ 25/01/26  │ Ret recibida #012 │          │ $50     │ $950   │    ║
║     └──────────────────────────────────────────────────────────────┘    ║
║     Exportar: [PDF] [Excel]                                             ║
║                                                                          ║
║  4. CxC vs COBROS por periodo                                           ║
║     Grafico + tabla: deudas generadas vs cobros por mes                 ║
║     Exportar: [PDF] [Excel]                                             ║
║                                                                          ║
║  5. CxP vs PAGOS por periodo                                            ║
║     Grafico + tabla: deudas generadas vs pagos por mes                  ║
║     Exportar: [PDF] [Excel]                                             ║
║                                                                          ║
║  6. REPORTE DE CREDITO DE CLIENTES                                      ║
║     ┌──────────────────────────────────────────────────────────────┐    ║
║     │ Cliente    │ Limite  │ Usado   │ Disponible │ % Uso │ Bloq? │    ║
║     │ Cliente A  │ $5,000  │ $3,200  │ $1,800     │ 64%   │ No    │    ║
║     │ Cliente B  │ $2,000  │ $2,000  │ $0         │ 100%  │ Si    │    ║
║     └──────────────────────────────────────────────────────────────┘    ║
║     Exportar: [PDF] [Excel]                                             ║
║                                                                          ║
║  TODOS los reportes se muestran en pantalla con SfDataGrid              ║
║  y permiten exportar a PDF (syncfusion_flutter_pdf) o                   ║
║  Excel (syncfusion_flutter_xlsio) con un boton                          ║
║                                                                          ║
╚══════════════════════════════════════════════════════════════════════════╝
```

**RPCs de CxC/CxP**

```sql
-- Crear CxC al emitir factura de venta
CREATE OR REPLACE FUNCTION create_receivable(
  p_empresa_id UUID, p_factura_id UUID
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER AS $$
  -- 1. Obtener datos de la factura (contacto_id, importe_total, dias_credito)
  -- 2. Crear registro en cuentas_por_cobrar
  -- 3. Si tiene cuotas (venta mixta): crear registros en cuotas_credito
  -- 4. Si tiene cobro inmediato: crear cobro + cobro_documentos + cobro_metodos
  -- 5. Actualizar saldo_credito del contacto
  -- 6. Generar factura_pagos (SRI) a partir de cobro_metodos
  -- 7. Generar asiento contable: CxC (D) / Ventas + IVA (H)
  -- 8. Retornar ID de la CxC
$$;

-- Registrar cobro (pago de cliente)
CREATE OR REPLACE FUNCTION register_collection(
  p_empresa_id UUID,
  p_contacto_id UUID,
  p_fecha DATE,
  p_documentos JSONB,  -- [{cxc_id, monto_aplicado}]
  p_metodos JSONB      -- [{metodo, monto, referencia, banco, retencion_id, nota_credito_id, ...}]
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER AS $$
  -- 1. Validar que suma de documentos = suma de metodos
  -- 2. Crear cobro (cabecera)
  -- 3. Por cada documento: crear cobro_documentos, actualizar CxC
  -- 4. Por cada metodo: crear cobro_metodos
  --    Si RETENCION: marcar retencion como cruzada (verificar que no este ya cruzada)
  --    Si NOTA_CREDITO: marcar NC como aplicada (verificar que no este ya aplicada)
  -- 5. Actualizar saldo_credito del contacto
  -- 6. Generar asiento contable:
  --    DEBE: Caja/Banco/Ret recibidas/NC aplicadas (segun metodos)
  --    HABER: CxC clientes
  -- 7. Si CxC.saldo = 0 → estado PAGADA, factura.estado = PAGADA
  -- 8. Si CxC.saldo > 0 → estado PARCIAL, factura.estado = PARCIAL
$$;

-- Verificar credito del cliente antes de vender
CREATE OR REPLACE FUNCTION check_credit_status(
  p_empresa_id UUID, p_contacto_id UUID, p_monto_venta DECIMAL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
  -- Retorna:
  -- {
  --   "puede_vender": true/false,
  --   "limite_credito": 5000,
  --   "saldo_actual": 3200,
  --   "disponible": 1800,
  --   "monto_venta": 500,
  --   "saldo_despues": 3700,
  --   "bloqueos": [
  --     {"tipo": "FACTURAS_VENCIDAS", "detalle": "3 facturas vencidas (max: 2)"},
  --     {"tipo": "MONTO_VENCIDO", "detalle": "$1,500 vencido (max: $1,000)"}
  --   ],
  --   "facturas_vencidas": 3,
  --   "monto_vencido": 1500,
  --   "requiere_autorizacion": true
  -- }
$$;

-- Autorizar venta excepcional (supervisor)
CREATE OR REPLACE FUNCTION authorize_credit_exception(
  p_empresa_id UUID, p_contacto_id UUID, p_factura_id UUID,
  p_tipo_bloqueo VARCHAR, p_autorizado_por UUID, p_motivo TEXT
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER AS $$
  -- 1. Registrar en excepciones_credito
  -- 2. Retornar ID de la excepcion (para vincular con la factura)
$$;

-- Crear plan de pago a proveedores
CREATE OR REPLACE FUNCTION create_payment_plan(
  p_empresa_id UUID, p_nombre VARCHAR, p_fecha_programada DATE,
  p_detalle JSONB  -- [{cxp_id, monto_a_pagar, metodo_pago, banco_destino, cuenta_destino}]
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER AS $$
  -- 1. Crear plan de pago (cabecera)
  -- 2. Por cada item del detalle: crear plan_pago_detalle
  -- 3. Calcular totales
  -- 4. Retornar ID del plan
$$;

-- Ejecutar pago de un plan aprobado
CREATE OR REPLACE FUNCTION execute_payment_plan(
  p_empresa_id UUID, p_plan_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
  -- 1. Verificar plan en estado APROBADO
  -- 2. Por cada detalle pendiente:
  --    a. Crear pago_proveedor + pago_documentos + pago_metodos
  --    b. Si metodo = CHEQUE: crear cheque en tesoreria
  --    c. Si metodo = TRANSFERENCIA: crear transferencia en tesoreria
  --    d. Actualizar CxP (saldo, estado)
  --    e. Generar asiento: CxP (D) / Banco (H)
  -- 3. Actualizar plan estado = PAGADO
  -- 4. Retornar resumen de pagos ejecutados
$$;

-- Registrar pago manual a proveedor (sin plan)
CREATE OR REPLACE FUNCTION register_supplier_payment(
  p_empresa_id UUID,
  p_contacto_id UUID,
  p_fecha DATE,
  p_documentos JSONB,  -- [{cxp_id, monto_aplicado}]
  p_metodos JSONB      -- [{metodo, monto, referencia, cheque_id, transferencia_id, retencion_id}]
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER AS $$
  -- Similar a register_collection pero para CxP
  -- Si metodo = RETENCION: cruza retencion emitida al proveedor
$$;

-- Reporte cartera vencida (aging)
CREATE OR REPLACE FUNCTION get_aging_report(
  p_empresa_id UUID,
  p_tipo VARCHAR,       -- 'CXC' o 'CXP'
  p_fecha_corte DATE DEFAULT CURRENT_DATE,
  p_contacto_id UUID DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
  -- Retorna aging por contacto:
  -- [{
  --   contacto_id, razon_social,
  --   por_vencer, vencido_1_30, vencido_31_60, vencido_61_90, vencido_90_mas,
  --   total_deuda
  -- }]
  -- Calcula dias vencidos: fecha_corte - fecha_vencimiento
$$;

-- Estado de cuenta de un contacto
CREATE OR REPLACE FUNCTION get_account_statement(
  p_empresa_id UUID, p_contacto_id UUID,
  p_fecha_desde DATE, p_fecha_hasta DATE,
  p_tipo VARCHAR  -- 'CXC' o 'CXP'
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
  -- Retorna movimientos cronologicos:
  -- [{fecha, documento, descripcion, debe, haber, saldo}]
  -- Incluye: facturas, NC, ND, cobros/pagos, retenciones
  -- Calcula saldo acumulado
$$;

-- Deudas manuales (sin documento electronico)
CREATE OR REPLACE FUNCTION create_manual_debt(
  p_empresa_id UUID, p_contacto_id UUID,
  p_tipo VARCHAR,       -- 'CXC' o 'CXP'
  p_monto DECIMAL, p_fecha DATE, p_fecha_vencimiento DATE,
  p_descripcion TEXT, p_cuenta_contable_id UUID
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER AS $$
  -- 1. Crear registro en cuentas_por_cobrar o cuentas_por_pagar (tipo_origen = MANUAL)
  -- 2. Generar asiento contable: CxC/CxP (D/H) segun tipo
  -- 3. Retornar ID
$$;

-- ============================================
-- COMISIONES DE VENDEDORES (G-VTA-06)
-- ============================================

CREATE TABLE reglas_comision (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  vendedor_id     UUID REFERENCES contactos(id),
  producto_id     UUID REFERENCES productos(id),
  categoria_id    UUID REFERENCES categorias_producto(id),
  tipo            VARCHAR(20) NOT NULL,       -- PORCENTAJE | MONTO_FIJO
  valor           DECIMAL(10,4) NOT NULL,
  rango_desde     DECIMAL(14,2) DEFAULT 0,
  rango_hasta     DECIMAL(14,2),
  vigencia_desde  DATE NOT NULL,
  vigencia_hasta  DATE,
  prioridad       INTEGER DEFAULT 0,
  activo          BOOLEAN DEFAULT true,
  created_at      TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE comisiones_vendedor (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  vendedor_id     UUID NOT NULL REFERENCES contactos(id),
  factura_id      UUID REFERENCES facturas(id),
  monto_base      DECIMAL(14,2) NOT NULL,
  porcentaje      DECIMAL(10,4),
  monto_comision  DECIMAL(14,2) NOT NULL,
  estado          VARCHAR(20) DEFAULT 'CALCULADA',  -- CALCULADA | APROBADA | PAGADA
  periodo_desde   DATE NOT NULL,
  periodo_hasta   DATE NOT NULL,
  regla_comision_id UUID REFERENCES reglas_comision(id),
  created_at      TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE reglas_comision ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON reglas_comision FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));
ALTER TABLE comisiones_vendedor ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON comisiones_vendedor FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE OR REPLACE FUNCTION calculate_commissions(
  p_empresa_id UUID, p_periodo_desde DATE, p_periodo_hasta DATE
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  -- 1. Facturas PAGADAS en periodo con vendedor_id NOT NULL
  -- 2. Buscar regla aplicable por prioridad DESC (vendedor+producto > vendedor+cat > vendedor > general)
  -- 3. Aplicar rangos y calcular: PORCENTAJE -> base*val/100, MONTO_FIJO -> val*qty
  -- 4. INSERT comisiones_vendedor, retornar resumen por vendedor
  RETURN '{}'::JSONB;
END;
$$;

-- ============================================
-- METAS / CUOTAS DE VENTA (G-VTA-08) — P2
-- ============================================
-- Objetivos por vendedor con calculo automatico de cumplimiento.

CREATE TABLE metas_venta (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id              UUID NOT NULL REFERENCES empresas(id),
  vendedor_id             UUID NOT NULL REFERENCES contactos(id),
  periodo_tipo            VARCHAR(15) NOT NULL,         -- MENSUAL | TRIMESTRAL | ANUAL
  anio                    INTEGER NOT NULL,
  mes                     INTEGER,                      -- NULL si ANUAL
  trimestre               INTEGER,                      -- NULL si MENSUAL/ANUAL
  monto_meta              DECIMAL(14,2) NOT NULL,
  monto_real              DECIMAL(14,2) DEFAULT 0,
  porcentaje_cumplimiento DECIMAL(5,2) GENERATED ALWAYS AS (
    CASE WHEN monto_meta > 0 THEN ROUND(monto_real / monto_meta * 100, 2) ELSE 0 END
  ) STORED,
  created_at              TIMESTAMPTZ DEFAULT now(),
  UNIQUE(empresa_id, vendedor_id, periodo_tipo, anio, COALESCE(mes,0), COALESCE(trimestre,0))
);
ALTER TABLE metas_venta ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON metas_venta FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));
-- monto_real se actualiza via trigger al PAGAR factura con vendedor_id

-- ============================================
-- PORTAL AUTOSERVICIO CLIENTES (G-VTA-10) — P3
-- ============================================
-- Portal publico (Edge Functions + HTML/Flutter Web) donde clientes pueden:
--   - Ver facturas emitidas y descargar RIDEs (PDF)
--   - Ver estado de cuenta (CxC pendientes, saldos)
--   - Pagar online (PayPhone/Kushki integration)
--   - Ver estado de ordenes de venta / despachos
-- Autenticacion por token temporal enviado por email (sin registro).

CREATE TABLE tokens_portal_cliente (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id  UUID NOT NULL REFERENCES empresas(id),
  contacto_id UUID NOT NULL REFERENCES contactos(id),
  token       UUID NOT NULL UNIQUE DEFAULT gen_random_uuid(),
  expira_at   TIMESTAMPTZ NOT NULL DEFAULT now() + INTERVAL '72 hours',
  activo      BOOLEAN DEFAULT true,
  created_at  TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE tokens_portal_cliente ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON tokens_portal_cliente FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- ============================================
-- ANTICIPOS CLIENTES / PROVEEDORES (G-CXC-03)
-- ============================================

CREATE TABLE anticipos (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  contacto_id     UUID NOT NULL REFERENCES contactos(id),
  tipo            VARCHAR(15) NOT NULL,       -- CLIENTE | PROVEEDOR
  numero          VARCHAR(20),
  fecha           DATE NOT NULL DEFAULT CURRENT_DATE,
  monto           DECIMAL(14,2) NOT NULL,
  saldo_disponible DECIMAL(14,2) NOT NULL,
  estado          VARCHAR(20) DEFAULT 'REGISTRADO',  -- REGISTRADO | PARCIAL | APLICADO | ANULADO
  cobro_id        UUID,
  pago_id         UUID,
  cuenta_contable_id UUID REFERENCES cuentas_contables(id),
  asiento_id      UUID REFERENCES asientos_contables(id),
  notas           TEXT,
  created_at      TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE anticipo_aplicaciones (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  anticipo_id     UUID NOT NULL REFERENCES anticipos(id),
  factura_id      UUID NOT NULL REFERENCES facturas(id),
  monto_aplicado  DECIMAL(14,2) NOT NULL,
  fecha           DATE NOT NULL DEFAULT CURRENT_DATE,
  asiento_id      UUID REFERENCES asientos_contables(id),
  created_at      TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE anticipos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON anticipos FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE OR REPLACE FUNCTION register_advance(
  p_empresa_id UUID, p_contacto_id UUID, p_tipo VARCHAR, p_monto DECIMAL, p_cobro_pago_id UUID
) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  -- CLIENTE: Db Banco / Cr Anticipo Clientes (2.1.8.x)
  -- PROVEEDOR: Db Anticipo Proveedores (1.1.5.x) / Cr Banco
  RETURN gen_random_uuid();
END;
$$;

CREATE OR REPLACE FUNCTION apply_advance_to_invoice(
  p_anticipo_id UUID, p_factura_id UUID, p_monto DECIMAL
) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  -- 1. Validar monto <= saldo_disponible
  -- 2. INSERT anticipo_aplicaciones, UPDATE anticipos.saldo_disponible
  -- 3. Reclasifica: Db Anticipo Transitorio / Cr CxC (o Db CxP / Cr Anticipo)
  -- 4. Reduce cuentas_por_cobrar/pagar.saldo
  RETURN gen_random_uuid();
END;
$$;

-- ============================================
-- PROVISION CUENTAS INCOBRABLES (G-CXC-04)
-- Art. 10 num. 11 LRTI Ecuador
-- ============================================

CREATE OR REPLACE FUNCTION calculate_bad_debt_provision(
  p_empresa_id UUID, p_fecha_corte DATE DEFAULT CURRENT_DATE
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_prov_general DECIMAL(14,2); v_prov_especifica DECIMAL(14,2); v_num_cxc INTEGER;
BEGIN
  -- Especifica: CxC vencidas > 360 dias -> 100%
  SELECT COALESCE(SUM(saldo), 0), COUNT(*) INTO v_prov_especifica, v_num_cxc
  FROM cuentas_por_cobrar WHERE empresa_id = p_empresa_id
    AND estado IN ('PENDIENTE','PARCIAL') AND (p_fecha_corte - fecha_vencimiento) > 360;
  -- General: 1% CxC del ejercicio (max 10% cartera total)
  SELECT COALESCE(SUM(monto_original), 0) * 0.01 INTO v_prov_general
  FROM cuentas_por_cobrar WHERE empresa_id = p_empresa_id
    AND EXTRACT(YEAR FROM fecha_emision) = EXTRACT(YEAR FROM p_fecha_corte);
  -- Asiento: Db Gasto Provision (6.x.x) / Cr Provision Acumulada (1.1.2.9.x)
  RETURN jsonb_build_object('provision_especifica', v_prov_especifica,
    'provision_general_1pct', v_prov_general,
    'total_provision', v_prov_especifica + v_prov_general,
    'num_cxc_vencidas_360', v_num_cxc, 'fecha_corte', p_fecha_corte);
END;
$$;

-- ============================================
-- ALERTAS TEMPRANAS VENCIMIENTO CxC (G-CXC-05)
-- ============================================
-- Parametros en parametros_empresa: dias_alerta_vencimiento_1/2/3 (default 15/7/3)

CREATE OR REPLACE FUNCTION check_upcoming_due_dates(p_empresa_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_dias_1 INT; v_dias_2 INT; v_dias_3 INT; v_alertas JSONB := '[]';
BEGIN
  v_dias_1 := COALESCE((SELECT valor::INT FROM parametros_empresa
    WHERE empresa_id = p_empresa_id AND clave = 'dias_alerta_vencimiento_1'), 15);
  v_dias_2 := COALESCE((SELECT valor::INT FROM parametros_empresa
    WHERE empresa_id = p_empresa_id AND clave = 'dias_alerta_vencimiento_2'), 7);
  v_dias_3 := COALESCE((SELECT valor::INT FROM parametros_empresa
    WHERE empresa_id = p_empresa_id AND clave = 'dias_alerta_vencimiento_3'), 3);
  -- SELECT CxC PENDIENTE/PARCIAL con vencimiento en proximos N dias
  -- JOIN facturas.vendedor_id, agrupar por vendedor
  -- PERFORM module_bus.send_notification(..., 'ALERTA_VENCIMIENTO')
  -- Retorna: [{vendedor_id, nombre, dias_rango, num_documentos, monto_total}]
  RETURN v_alertas;
END;
$$;
-- Cron diario L-V 8am en tareas_programadas

-- ============================================
-- DESCUENTO PRONTO PAGO (G-CXC-06) — P2
-- ============================================
-- Ej: "2/10 net 30" = 2% descuento si paga en 10 dias, vence en 30.
-- Se agregan campos a terminos_pago_lineas:
ALTER TABLE terminos_pago_lineas
  ADD COLUMN descuento_pronto_pago DECIMAL(5,2) DEFAULT 0,  -- % descuento
  ADD COLUMN dias_descuento INTEGER DEFAULT 0;               -- ventana de descuento

CREATE OR REPLACE FUNCTION apply_early_payment_discount(
  p_cxc_id UUID, p_fecha_pago DATE
) RETURNS DECIMAL  -- Monto del descuento aplicado
-- 1. Obtener termino_pago de la factura origen
-- 2. Verificar si p_fecha_pago <= fecha_emision + dias_descuento
-- 3. Si dentro de ventana: descuento = saldo * descuento_pronto_pago / 100
-- 4. Registrar NC automatica o ajuste contable (Db Descuento Concedido / Cr CxC)

-- ============================================
-- COMPENSACION CxC vs CxP (G-CXC-07) — P2
-- ============================================
-- Cuando un contacto es cliente Y proveedor, permite netear saldos.

CREATE OR REPLACE FUNCTION compensate_cxc_cxp(
  p_empresa_id UUID, p_contacto_id UUID
) RETURNS UUID  -- ID del documento de compensacion
-- 1. SELECT SUM(saldo) FROM cuentas_por_cobrar WHERE contacto_id AND estado IN ('PENDIENTE','PARCIAL')
-- 2. SELECT SUM(saldo) FROM cuentas_por_pagar WHERE contacto_id AND estado IN ('PENDIENTE','PARCIAL')
-- 3. neto = CxC - CxP; crear documento compensacion con el menor de ambos
-- 4. Asiento: Db CxP / Cr CxC por monto compensado
-- 5. Marcar items compensados, retornar ID

-- ============================================
-- SCORING CREDITICIO AUTOMATICO (G-CXC-08) — P2
-- ============================================

CREATE OR REPLACE FUNCTION calculate_credit_score(
  p_empresa_id UUID, p_contacto_id UUID
) RETURNS JSONB
-- Retorna: {dso_promedio, pct_pagos_a_tiempo, volumen_compras_anual,
--   score ('A'|'B'|'C'|'D'), sugerencia ('AUMENTAR'|'MANTENER'|'REDUCIR')}
-- A = >90% a tiempo + DSO < 30; B = >75%; C = >50%; D = resto
-- Calcula sobre ultimos 12 meses de CxC del contacto

-- ============================================
-- REVISION MASIVA LIMITES DE CREDITO (G-CXC-09) — P2
-- ============================================

CREATE OR REPLACE FUNCTION bulk_review_credit_limits(p_empresa_id UUID)
RETURNS TABLE(contacto_id UUID, nombre TEXT, limite_actual DECIMAL,
  score VARCHAR, limite_sugerido DECIMAL, accion_sugerida VARCHAR)
-- 1. Para cada cliente activo con CxC en ultimos 12 meses
-- 2. Llama calculate_credit_score por contacto
-- 3. Sugiere limite basado en score + volumen: A=+20%, B=mantener, C=-10%, D=-30%
-- 4. Admin aprueba/modifica individual o masivamente via UI

-- ============================================
-- DUNNING / SEGUIMIENTO DE COBRANZA AUTOMATICO
-- ============================================
-- Niveles de seguimiento con escalamiento automatico.
-- Cada nivel tiene: dias de retraso, accion, plantilla de comunicacion.

CREATE TABLE niveles_cobranza (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  nivel           INTEGER NOT NULL,                -- 1, 2, 3, 4...
  nombre          VARCHAR(100) NOT NULL,           -- 'Recordatorio amable', 'Aviso formal', 'Ultimo aviso'
  dias_retraso    INTEGER NOT NULL,                -- Dias despues del vencimiento
  accion          VARCHAR(20) NOT NULL,            -- EMAIL, WHATSAPP, CARTA, BLOQUEO
  plantilla_asunto TEXT,                           -- Asunto del mensaje
  plantilla_cuerpo TEXT,                           -- Cuerpo con variables: {cliente}, {monto}, {dias}, {documentos}
  cobrar_interes  BOOLEAN DEFAULT false,           -- Generar interes por mora en este nivel
  tasa_interes_mensual DECIMAL(5,2),               -- % mensual de interes
  bloquear_credito BOOLEAN DEFAULT false,          -- Bloquear ventas a credito en este nivel
  activo          BOOLEAN DEFAULT true,
  UNIQUE(empresa_id, nivel)
);

CREATE TABLE seguimiento_cobranza (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  contacto_id     UUID NOT NULL REFERENCES contactos(id),
  nivel_id        UUID NOT NULL REFERENCES niveles_cobranza(id),
  fecha_ejecucion TIMESTAMPTZ DEFAULT NOW(),
  monto_vencido   DECIMAL(14,2) NOT NULL,
  documentos_vencidos INTEGER NOT NULL,
  canal_usado     VARCHAR(20),                     -- EMAIL, WHATSAPP, TELEGRAM
  enviado         BOOLEAN DEFAULT false,
  fecha_envio     TIMESTAMPTZ,
  respuesta       TEXT,                            -- Respuesta/compromiso del cliente
  created_by      UUID REFERENCES auth.users(id)
);

ALTER TABLE niveles_cobranza ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON niveles_cobranza
  FOR ALL TO authenticated USING (empresa_id = (SELECT private.get_empresa_id()));

ALTER TABLE seguimiento_cobranza ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON seguimiento_cobranza
  FOR ALL TO authenticated USING (empresa_id = (SELECT private.get_empresa_id()));

-- Edge Function ejecutada diariamente (cron) para procesar cobranza
-- Nombre: process-dunning
-- Logica:
--   1. Obtener CxC vencidas agrupadas por contacto
--   2. Para cada contacto, determinar nivel de cobranza segun max(dias_retraso)
--   3. Si el nivel actual > ultimo nivel ejecutado, escalar
--   4. Enviar notificacion por canal configurado (usa send-notification)
--   5. Si nivel tiene bloquear_credito=true, actualizar contacto.bloqueado=true
--   6. Registrar en seguimiento_cobranza
```

### Recibo de Cobro / Comprobante de Pago (PDF)

Documento imprimible generado con Syncfusion PDF al registrar un cobro o pago.

**Recibo de Cobro (entrega al cliente):**
```
┌──────────────────────────────────────────────┐
│ [LOGO]  EMPRESA S.A.           RECIBO DE COBRO │
│         RUC: 0990123456001     No. RC-000123   │
│         Dir: Av. Principal 123                  │
│                                                  │
│ RECIBIMOS DE: Juan Perez (0912345678)           │
│ FECHA: 2026-02-15                                │
│                                                  │
│ DOCUMENTOS CANCELADOS:                           │
│ ┌────────────────────────────────────────────┐  │
│ │ Documento          │ Vencimiento │ Monto    │  │
│ │ Fact 001-001-00123 │ 2026-01-15 │ $500.00  │  │
│ │ Fact 001-001-00145 │ 2026-02-01 │ $300.00  │  │
│ └────────────────────────────────────────────┘  │
│                                                  │
│ FORMA DE PAGO:                                   │
│   Efectivo:       $200.00                        │
│   Transferencia:  $400.00 (Ref: 987654)          │
│   Retencion:      $200.00 (001-001-000456)       │
│                                                  │
│ TOTAL RECIBIDO: $800.00                          │
│                                                  │
│ SON: OCHOCIENTOS DOLARES CON 00/100             │
│                                                  │
│ _________________    _________________           │
│ Recibido por         Entregado por               │
└──────────────────────────────────────────────┘
```

**Comprobante de Pago (entrega al proveedor):**
Misma estructura pero con titulo "COMPROBANTE DE PAGO" y datos del proveedor.

Generacion: RPC `generate_receipt_pdf(cobro_id UUID)` o `generate_payment_pdf(pago_id UUID)`
usando Syncfusion Flutter PDF (syncfusion_flutter_pdf).

