# Módulo Punto de Venta (POS)


```
pos/
  ├── sesion/               # Abrir/cerrar sesion de caja
  ├── venta/                # Pantalla POS (touch-friendly)
  │     ├── carrito/        # Items, cantidades, descuentos
  │     ├── busqueda/       # Buscar producto (nombre, codigo, escaner)
  │     ├── cobro/          # Cobro (efectivo, tarjeta, transferencia)
  │     └── facturacion/    # Factura electronica automatica
  ├── preventa/             # Pre-ventas por vendedores (multi-piso/seccion)
  │     ├── nueva/          # Vendedor registra lineas para un cliente
  │     ├── pendientes/     # Pre-ventas pendientes de cobro
  │     ├── recuperar/      # Cajero recupera pre-ventas del cliente
  │     └── consolidar/     # Unir multiples pre-ventas en una sola venta
  ├── caja/
  │     ├── arqueo/         # Cuadre de caja (conteo fisico vs sistema)
  │     ├── movimientos/    # Entradas/salidas de efectivo
  │     └── reporte-z/      # Resumen de ventas del dia
  └── configuracion/
        ├── cajas/          # CRUD cajas registradoras
        ├── impresoras/     # Config impresoras termicas
        ├── metodos-pago/   # Metodos habilitados en POS
        └── modos-pos/      # SUPERMERCADO, FERRETERIA, TIENDA_DEPARTAMENTAL
```

#### Modelo de Datos - POS

```sql
-- Cajas registradoras
cajas_pos
  id                    UUID PK
  empresa_id            UUID FK -> empresas
  establecimiento_id    UUID FK -> establecimientos
  bodega_id             UUID FK -> bodegas    -- Bodega predeterminada para esta caja
  nombre                VARCHAR(100) NOT NULL  -- 'Caja 1', 'Caja 2'
  activa                BOOLEAN DEFAULT true

-- Sesiones de caja (soporta pausar para almuerzo, etc.)
sesiones_caja
  id                    UUID PK
  empresa_id            UUID FK -> empresas
  caja_id               UUID FK -> cajas_pos
  usuario_id            UUID FK -> auth.users
  fecha_apertura        TIMESTAMPTZ NOT NULL DEFAULT now()
  fecha_cierre          TIMESTAMPTZ
  monto_apertura        DECIMAL(14,2) NOT NULL  -- Fondo de caja inicial
  monto_cierre_sistema  DECIMAL(14,2)           -- Total segun sistema
  monto_cierre_fisico   DECIMAL(14,2)           -- Total contado por cajero
  diferencia            DECIMAL(14,2)           -- fisico - sistema
  estado                VARCHAR(20) DEFAULT 'ABIERTA'
    -- ABIERTA, PAUSADA, CERRADA
  notas                 TEXT

-- Pausas de sesion (almuerzo, break, etc.)
pausas_sesion
  id                    UUID PK
  sesion_id             UUID FK -> sesiones_caja
  fecha_pausa           TIMESTAMPTZ NOT NULL DEFAULT now()
  fecha_reanudacion     TIMESTAMPTZ
  motivo                VARCHAR(100)  -- 'Almuerzo', 'Break', 'Cambio turno'

-- Movimientos de caja (entradas/salidas de efectivo no relacionadas a ventas)
movimientos_caja
  id                    UUID PK
  sesion_id             UUID FK -> sesiones_caja
  tipo                  VARCHAR(10) NOT NULL  -- ENTRADA, SALIDA
  monto                 DECIMAL(14,2) NOT NULL
  motivo                VARCHAR(300)
  created_at            TIMESTAMPTZ

-- Las ventas POS son facturas normales con referencia a la sesion
-- factura.sesion_caja_id = UUID FK -> sesiones_caja (opcional)
ALTER TABLE facturas ADD COLUMN sesion_caja_id UUID REFERENCES sesiones_caja(id);

-- ============================================
-- PRE-VENTAS (ventas asistidas por vendedores)
-- ============================================
-- Un vendedor registra lineas de productos para un cliente desde su dispositivo.
-- El cliente puede tener N pre-ventas (una por vendedor/seccion).
-- Al llegar a caja, el cajero recupera y consolida todas las pre-ventas.

preventas
  id                    UUID PK
  empresa_id            UUID FK -> empresas
  establecimiento_id    UUID FK -> establecimientos
  codigo                VARCHAR(20) NOT NULL  -- Codigo unico (para busqueda rapida)
  -- Identificacion del cliente (puede ser anonimo hasta llegar a caja)
  contacto_id           UUID FK -> contactos  -- NULL si es anonimo
  nombre_cliente        VARCHAR(200)          -- Nombre temporal si no tiene contacto
  identificacion_temp   VARCHAR(20)           -- Cedula/RUC temporal
  -- Vendedor que creo la pre-venta
  vendedor_id           UUID FK -> auth.users NOT NULL
  -- Estado
  estado                VARCHAR(20) DEFAULT 'ABIERTA'
    -- ABIERTA: vendedor sigue agregando productos
    -- CERRADA: vendedor termino, lista para caja
    -- EN_CAJA: cajero la recupero y esta procesando
    -- FACTURADA: se genero factura
    -- CANCELADA: cancelada sin facturar
  -- Referencia al documento final
  factura_id            UUID FK -> facturas   -- NULL hasta que se facture
  sesion_caja_id        UUID FK -> sesiones_caja  -- Sesion donde se cobro
  -- Totales (se recalculan al agregar/quitar lineas)
  subtotal              DECIMAL(14,2) DEFAULT 0
  total_impuestos       DECIMAL(14,2) DEFAULT 0
  total                 DECIMAL(14,2) DEFAULT 0
  notas                 TEXT
  created_at            TIMESTAMPTZ DEFAULT now()
  updated_at            TIMESTAMPTZ

preventa_lineas
  id                    UUID PK
  preventa_id           UUID FK -> preventas
  producto_id           UUID FK -> productos
  presentacion_id       UUID FK -> producto_presentaciones  -- NULL = unidad base
  vendedor_id           UUID FK -> auth.users  -- Vendedor que registro esta linea
  descripcion           VARCHAR(300) NOT NULL
  cantidad              DECIMAL(18,6) NOT NULL
  cantidad_base         DECIMAL(18,6) NOT NULL  -- Convertida a unidad base
  precio_unitario       DECIMAL(18,6) NOT NULL  -- Precio por presentacion
  descuento             DECIMAL(14,2) DEFAULT 0
  precio_total          DECIMAL(14,2) NOT NULL
  -- Verificacion en caja
  verificado            BOOLEAN DEFAULT false   -- Cajero verifico este item
  verificado_por        UUID FK -> auth.users   -- Cajero que verifico
  -- Si fue agregado directamente en caja (sin vendedor previo)
  agregado_en_caja      BOOLEAN DEFAULT false
  orden                 INTEGER DEFAULT 0
  created_at            TIMESTAMPTZ DEFAULT now()

-- Indices
CREATE INDEX idx_preventas_estado ON preventas(empresa_id, establecimiento_id, estado);
CREATE INDEX idx_preventas_vendedor ON preventas(vendedor_id, estado);
CREATE INDEX idx_preventas_codigo ON preventas(empresa_id, codigo);
```

#### Modos de Operacion POS

```
╔══════════════════════════════════════════════════════════════════════════╗
║  PILAR POS soporta 3 modos de operacion configurables por             ║
║  establecimiento. Un mismo negocio puede usar modos distintos          ║
║  en diferentes sucursales.                                             ║
╠══════════════════════════════════════════════════════════════════════════╣
║                                                                        ║
║  MODO 1: SUPERMERCADO (autoservicio)                                   ║
║  ───────────────────────────────────                                   ║
║  - El cliente toma productos y los lleva a la caja                     ║
║  - El cajero escanea/digita cada producto                              ║
║  - No hay pre-venta ni vendedor asignado                               ║
║  - Cobro inmediato → factura → tirilla                                 ║
║  - Flujo: Escanear → Cobrar → Facturar → Imprimir                     ║
║                                                                        ║
║  MODO 2: TIENDA DEPARTAMENTAL (multi-vendedor, multi-piso)            ║
║  ──────────────────────────────────────────────────────────            ║
║  Ejemplo: Tienda de 3 pisos                                           ║
║    Piso 3: Vendedor A ayuda al cliente a elegir muebles               ║
║            → Crea PRE-VENTA y registra lineas desde su dispositivo    ║
║    Piso 2: Vendedor B ayuda al mismo cliente con ropa                 ║
║            → Crea OTRA PRE-VENTA (o agrega a la existente)            ║
║    Piso 1: Cliente selecciona viveres POR SU CUENTA (sin vendedor)    ║
║            → Va directo a caja con los productos fisicos              ║
║                                                                        ║
║  En CAJA:                                                              ║
║    1. Cajero busca pre-ventas del cliente (por cedula, nombre, codigo)║
║    2. Recupera y consolida todas las pre-ventas                        ║
║    3. Pasa cada producto fisico por el escaner/digitacion              ║
║    4. Si el producto ESTA en una pre-venta → marca como verificado    ║
║    5. Si el producto NO esta → lo agrega SIN vendedor vinculado       ║
║    6. Puede ver que items de pre-venta NO fueron verificados           ║
║       (el cliente cambio de opinion y no llevo ese producto)           ║
║    7. Cobra → Factura → Tirilla                                        ║
║                                                                        ║
║  Medicion de ventas por vendedor:                                      ║
║    - Cada linea tiene vendedor_id (NULL si agregado en caja)           ║
║    - Reportes: ventas por vendedor, comisiones, ranking                ║
║                                                                        ║
║  MODO 3: FERRETERIA (pre-venta + despacho)                            ║
║  ─────────────────────────────────────────                             ║
║  - Vendedor atiende al cliente y registra PRE-VENTA completa          ║
║  - Cliente va a CAJA a pagar                                           ║
║  - Cajero recupera la pre-venta, cobra y factura                       ║
║  - Al confirmar pago → notificacion al vendedor (Realtime)            ║
║  - Vendedor recibe OK → genera ORDEN DE DESPACHO                      ║
║  - Bodeguero prepara y entrega productos al cliente                    ║
║  - Flujo: Pre-venta → Pago en caja → Notificacion → Despacho         ║
║                                                                        ║
║  Diferencia con Modo 2:                                                ║
║    - En ferreteria el vendedor hace TODA la pre-venta                 ║
║    - El cliente NO agrega productos por su cuenta                      ║
║    - El despacho es POSTERIOR al pago (no se entrega antes de pagar)  ║
║    - El vendedor controla fisicamente los productos hasta el despacho  ║
║                                                                        ║
╠══════════════════════════════════════════════════════════════════════════╣
║  CONFIGURACION                                                         ║
║  - Tabla config_stock_establecimiento.modo_pos                         ║
║    'SUPERMERCADO', 'DEPARTAMENTAL', 'FERRETERIA'                       ║
║  - SUPERMERCADO: no usa pre-ventas, escaneo directo                    ║
║  - DEPARTAMENTAL: pre-ventas opcionales, consolidacion en caja         ║
║  - FERRETERIA: pre-ventas obligatorias, despacho post-pago             ║
╚══════════════════════════════════════════════════════════════════════════╝
```

```sql
-- Agregar modo POS a la configuracion del establecimiento
ALTER TABLE config_stock_establecimiento ADD COLUMN
  modo_pos VARCHAR(20) DEFAULT 'SUPERMERCADO';
  -- SUPERMERCADO, DEPARTAMENTAL, FERRETERIA

-- RPC: Crear pre-venta (vendedor)
CREATE OR REPLACE FUNCTION create_preventa(
  p_empresa_id UUID,
  p_establecimiento_id UUID,
  p_vendedor_id UUID,
  p_nombre_cliente VARCHAR DEFAULT NULL,
  p_identificacion VARCHAR DEFAULT NULL,
  p_contacto_id UUID DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_preventa_id UUID;
  v_codigo VARCHAR(20);
BEGIN
  -- Generar codigo unico (PV-YYYYMMDD-XXXX)
  v_codigo := 'PV-' || to_char(now(), 'YYYYMMDD') || '-' ||
    lpad(nextval('preventa_seq')::text, 4, '0');

  INSERT INTO preventas (empresa_id, establecimiento_id, codigo,
    contacto_id, nombre_cliente, identificacion_temp, vendedor_id)
  VALUES (p_empresa_id, p_establecimiento_id, v_codigo,
    p_contacto_id, p_nombre_cliente, p_identificacion, p_vendedor_id)
  RETURNING id INTO v_preventa_id;

  RETURN v_preventa_id;
END;
$$;

-- RPC: Consolidar pre-ventas en caja
CREATE OR REPLACE FUNCTION consolidate_preventas(
  p_empresa_id UUID,
  p_preventa_ids UUID[],  -- Array de IDs de pre-ventas a consolidar
  p_sesion_caja_id UUID
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_preventa_principal UUID;
  v_id UUID;
BEGIN
  -- Usar la primera pre-venta como principal
  v_preventa_principal := p_preventa_ids[1];

  -- Mover todas las lineas a la pre-venta principal
  FOREACH v_id IN ARRAY p_preventa_ids[2:] LOOP
    UPDATE preventa_lineas SET preventa_id = v_preventa_principal
    WHERE preventa_id = v_id;

    -- Marcar las otras como consolidadas
    UPDATE preventas SET estado = 'EN_CAJA', sesion_caja_id = p_sesion_caja_id
    WHERE id = v_id;
  END LOOP;

  -- Marcar la principal como EN_CAJA
  UPDATE preventas SET estado = 'EN_CAJA', sesion_caja_id = p_sesion_caja_id
  WHERE id = v_preventa_principal;

  -- Recalcular totales
  UPDATE preventas SET
    subtotal = (SELECT COALESCE(SUM(precio_total), 0) FROM preventa_lineas WHERE preventa_id = v_preventa_principal),
    updated_at = now()
  WHERE id = v_preventa_principal;

  RETURN v_preventa_principal;
END;
$$;

-- RPC: Facturar pre-venta (desde caja, despues de verificar items)
CREATE OR REPLACE FUNCTION invoice_preventa(
  p_empresa_id UUID,
  p_preventa_id UUID,
  p_formas_pago JSONB
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_factura_id UUID;
  v_preventa RECORD;
BEGIN
  SELECT * INTO v_preventa FROM preventas WHERE id = p_preventa_id;

  -- Crear factura con las lineas verificadas
  -- (las no verificadas se excluyen = cliente no llevo ese producto)
  -- ... (usa create_invoice internamente)

  -- Actualizar pre-venta
  UPDATE preventas SET estado = 'FACTURADA', factura_id = v_factura_id
  WHERE id = p_preventa_id;

  -- Si modo FERRETERIA → crear orden de despacho automaticamente
  -- y notificar al vendedor via Supabase Realtime

  RETURN v_factura_id;
END;
$$;
```

#### Facturacion sin sesion POS

```
PILAR permite facturar de 3 formas:

1. DESDE PROFORMA/COTIZACION (sin POS):
   - Cotizacion aprobada → Boton "Generar Factura"
   - Datos precargados (cliente, items, precios)
   - sesion_caja_id = NULL (no es venta POS)
   - Control de stock: segun modo_stock_venta del establecimiento
   - Si modo CONSOLIDADO: puede vender de principal + alternas
   - Si auto_transferencia=true: transfiere automaticamente desde alternas

2. DESDE DESPACHO DE INVENTARIO (sin POS):
   - Orden de venta despachada → Boton "Facturar Despacho"
   - Items del despacho precargados
   - sesion_caja_id = NULL
   - Stock ya fue descontado al despachar

3. DESDE PUNTO DE VENTA (con sesion POS):
   - Venta rapida con busqueda/escaner
   - Cobro inmediato (efectivo, tarjeta, transferencia)
   - sesion_caja_id = <sesion activa>
   - Impresion termica automatica (esc_pos_printer)
   - Control de stock: SIEMPRE desde la bodega asignada a la caja (cajas_pos.bodega_id)
```

#### Estrategia de Control de Stock

```
╔══════════════════════════════════════════════════════════════════════════╗
║  MODOS DE CONTROL DE STOCK (configurable por establecimiento)          ║
╠══════════════════════════════════════════════════════════════════════════╣
║                                                                        ║
║  1. PRINCIPAL (recomendado para POS)                                   ║
║     - Verifica stock SOLO en la bodega principal (o bodega del POS)    ║
║     - Si no hay stock → no permite vender                              ║
║     - Rapido, simple, sin esperas para el cliente                      ║
║     - El reabastecimiento se hace por separado                         ║
║                                                                        ║
║  2. CONSOLIDADO (recomendado para ventas desde proformas)              ║
║     - Verifica stock sumando principal + todas las alternas            ║
║     - Si no hay en principal pero hay en alternas → permite vender     ║
║     - Con auto_transferencia=true: crea transferencia automatica       ║
║     - Ideal para ventas donde hay tiempo para preparar despacho        ║
║                                                                        ║
║  3. SIN_CONTROL                                                        ║
║     - No verifica stock (para servicios o empresas sin inventario)     ║
║     - Permite vender sin importar existencias                          ║
║                                                                        ║
╠══════════════════════════════════════════════════════════════════════════╣
║  RECOMENDACION:                                                        ║
║  - POS: modo PRINCIPAL → el cliente esta esperando, no hay tiempo      ║
║    para transferencias. La caja tiene su bodega asignada.              ║
║  - Proformas/OV: modo CONSOLIDADO + auto_transferencia → permite       ║
║    vender aunque no haya stock local, se transfiere de alternas.       ║
║  - Ecommerce: modo CONSOLIDADO → el despacho toma tiempo igualmente.  ║
╚══════════════════════════════════════════════════════════════════════════╝

Flujo de auto-transferencia (modo CONSOLIDADO + auto_transferencia=true):

  Cliente pide 10 unidades de Producto X
        │
        ▼
  ¿Stock en bodega principal >= 10?
        │
   SI ──┤── NO
   │         │
   │         ▼
   │   Buscar en bodegas alternas (por prioridad)
   │         │
   │         ▼
   │   Alterna 1: tiene 6 → transferir 6
   │   Alterna 2: tiene 8 → transferir 4 (solo faltante)
   │         │
   │         ▼
   │   Crear transferencias automaticas en kardex
   │         │
   ▼         ▼
  Descontar stock de bodega principal
        │
        ▼
  Generar factura/despacho
```

### Devoluciones desde POS (con Nota de Credito electronica SRI)

Flujo de devolucion en pantalla POS:

```
FLUJO: DEVOLUCION DESDE POS
═══════════════════════════

1. BUSCAR VENTA ORIGINAL
   - Cajero presiona [Devolucion] en pantalla POS
   - Busca por: numero factura, nombre cliente, o escaneo barcode del RIDE
   - Se muestra la factura original con todos sus items

2. SELECCIONAR ITEMS A DEVOLVER
   ┌───────────────────────────────────────────────────┐
   │ Factura: 001-001-000000123                         │
   │ Cliente: Juan Perez                                │
   │ Fecha: 2026-02-10                                  │
   │                                                     │
   │ ☑ Producto A    x2    $10.00    Devolver: [2]      │
   │ ☐ Producto B    x1    $25.00    Devolver: [0]      │
   │ ☑ Producto C    x3    $5.00     Devolver: [1]      │
   │                                                     │
   │ Motivo: [Producto defectuoso ▼]                    │
   │ Tipo:   ◉ Devolucion (dinero)  ○ Cambio (producto) │
   │                                                     │
   │ Total devolucion: $25.00                            │
   │ [Cancelar]                    [Procesar Devolucion] │
   └───────────────────────────────────────────────────┘

3. GENERAR NOTA DE CREDITO ELECTRONICA
   - Crear NC tipo '04' referenciando factura original
   - Copiar datos fiscales (RUC, razon social, direccion)
   - Lineas: solo los items devueltos con cantidades seleccionadas
   - Motivo de la devolucion en campo 'razon' de la NC
   - Asignar secuencial SRI (del punto de emision POS)
   - Firmar y enviar al SRI via Edge Function (o encolar si offline)

4. REINGRESAR STOCK
   - Crear movimiento DEVOLUCION_VENTA en kardex
   - Bodega destino: bodega_pos del establecimiento
   - Actualizar inventario_stock (sumar cantidades devueltas)

5. DEVOLVER DINERO
   - Si pago original fue EFECTIVO: devolucion en efectivo (registrar en sesion caja)
   - Si pago original fue TARJETA: reverso/devolucion via pasarela (Kushki/Paymentez)
   - Si pago original fue MIXTO: devolver proporcional o segun seleccion del cajero
   - Registrar en cobros como cobro negativo vinculado a la NC

6. PARA CAMBIOS (devolucion + nueva venta)
   - Generar NC por items devueltos (pasos 3-4)
   - Inmediatamente abrir nueva venta con el cliente
   - La NC se aplica como metodo de pago en la nueva factura
   - Diferencia se cobra/devuelve segun corresponda
```

```sql
-- Campos adicionales en sesion_caja para tracking de devoluciones
-- total_devoluciones DECIMAL(14,2) DEFAULT 0  -- Acumulado de devoluciones en la sesion
-- conteo_devoluciones INTEGER DEFAULT 0        -- Numero de devoluciones

-- RPC para procesar devolucion POS
CREATE OR REPLACE FUNCTION process_pos_return(
  p_factura_id UUID,
  p_sesion_caja_id UUID,
  p_lineas JSONB,          -- [{producto_id, cantidad_devuelta, motivo}]
  p_tipo VARCHAR DEFAULT 'DEVOLUCION',  -- DEVOLUCION o CAMBIO
  p_metodo_devolucion VARCHAR DEFAULT 'EFECTIVO' -- EFECTIVO, TARJETA_REVERSO, NOTA_CREDITO
) RETURNS UUID AS $$
  -- 1. Validar factura existe y tiene items para devolver
  -- 2. Crear nota_credito tipo '04' referenciando factura
  -- 3. Crear NC lineas con items seleccionados
  -- 4. Encolar documento electronico (process-doc-queue)
  -- 5. Crear movimientos de ingreso a bodega POS
  -- 6. Registrar devolucion de dinero segun metodo
  -- 7. Actualizar sesion caja (total_devoluciones, conteo)
  -- 8. Retornar ID de la nota de credito generada
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

#### Programa de Fidelidad / Puntos

```sql
CREATE TABLE programas_fidelidad (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), empresa_id UUID NOT NULL REFERENCES empresas(id),
  nombre VARCHAR(100) NOT NULL, tipo VARCHAR(20) NOT NULL, -- PUNTOS, CASHBACK, DESCUENTO
  regla_acumulacion DECIMAL(14,2) NOT NULL, regla_canje DECIMAL(14,2) NOT NULL,
  vigencia_puntos_dias INTEGER DEFAULT 365, activo BOOLEAN DEFAULT true,
  UNIQUE(empresa_id, nombre)
);
CREATE TABLE saldo_fidelidad (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), empresa_id UUID NOT NULL REFERENCES empresas(id),
  contacto_id UUID NOT NULL REFERENCES contactos(id), programa_id UUID NOT NULL REFERENCES programas_fidelidad(id),
  puntos_acumulados DECIMAL(14,2) DEFAULT 0, puntos_canjeados DECIMAL(14,2) DEFAULT 0,
  puntos_vencidos DECIMAL(14,2) DEFAULT 0, saldo_actual DECIMAL(14,2) DEFAULT 0,
  UNIQUE(empresa_id, contacto_id, programa_id)
);
CREATE TABLE movimientos_fidelidad (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), saldo_id UUID NOT NULL REFERENCES saldo_fidelidad(id),
  tipo VARCHAR(20) NOT NULL, -- ACUMULACION, CANJE, VENCIMIENTO, AJUSTE
  puntos DECIMAL(14,2) NOT NULL, factura_id UUID REFERENCES facturas(id), fecha TIMESTAMPTZ DEFAULT NOW()
);
-- RLS + POS: al cerrar venta mostrar puntos ganados + opcion canjear (tipo CANJE).
```

#### Promociones Automaticas

```sql
CREATE TABLE promociones (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), empresa_id UUID NOT NULL REFERENCES empresas(id),
  nombre VARCHAR(150) NOT NULL,
  tipo VARCHAR(30) NOT NULL, -- DESCUENTO_PORCENTAJE/DESCUENTO_MONTO/2X1/COMBO/NXM/HAPPY_HOUR
  condicion JSONB NOT NULL, beneficio JSONB NOT NULL,
  fecha_inicio DATE NOT NULL, fecha_fin DATE, dias_semana INTEGER[],
  hora_inicio TIME, hora_fin TIME, activa BOOLEAN DEFAULT true, prioridad INTEGER DEFAULT 0
);
CREATE TABLE promocion_productos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  promocion_id UUID NOT NULL REFERENCES promociones(id) ON DELETE CASCADE,
  producto_id UUID, categoria_id UUID, aplica_a VARCHAR(20) DEFAULT 'PRODUCTO'
);
CREATE OR REPLACE FUNCTION evaluate_promotions(p_empresa_id UUID, p_lineas JSONB, p_fecha TIMESTAMPTZ DEFAULT NOW())
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
  -- Retorna [{promocion_id, nombre, tipo, descuento_linea_idx, monto_descuento}]
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

#### POS Offline Completo

```
ARQUITECTURA POS OFFLINE
1. SECUENCIALES PRE-ASIGNADOS: rango exclusivo por sesion (ej: 1001-2000)
2. COLA LOCAL: facturas SQLite, RIDE con "PENDIENTE AUTORIZACION SRI", push FIFO
3. STOCK LOCAL: snapshot al abrir sesion, decrementos optimistas, no bloquea si negativo
4. SYNC: push facturas → pull stock/precios → reconciliar (stock<0 = alerta no bloqueo)
5. CONFLICTOS: rangos exclusivos evitan duplicados, precio offline se respeta
```

#### Dashboard POS Tiempo Real

```sql
CREATE OR REPLACE FUNCTION get_pos_dashboard(
  p_empresa_id UUID, p_punto_venta_id UUID DEFAULT NULL, p_fecha DATE DEFAULT CURRENT_DATE
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
-- KPIs: ventas_hoy, ticket_promedio, items_vendidos, cajeros_activos, sesiones_abiertas
-- Charts: ventas_por_hora [{hora,total}], top_5_productos [{producto,cantidad,monto}]
-- Realtime: subscribe facturas POS + polling 60s agregados
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

#### Modo Restaurante / Kitchen Display (G-POS-10) — P3

```sql
-- ============================================
-- MODO RESTAURANTE Y KITCHEN DISPLAY (G-POS-10) — P3
-- ============================================
-- Nuevo modo POS: RESTAURANTE (adicional a SUPERMERCADO/DEPARTAMENTAL/FERRETERIA).
-- Funcionalidades:
--   - Mapa de mesas (drag-drop layout editor, estados LIBRE/OCUPADA/RESERVADA/CUENTA_PEDIDA)
--   - Comandas: items agrupados por estacion de preparacion (COCINA/BAR/POSTRES)
--   - Kitchen Display System (KDS): pantalla separada mostrando comandas pendientes,
--     touch para marcar PREPARANDO/LISTO
--   - Modificadores: "sin cebolla", "extra queso", "termino medio"
--   - Division de cuenta por comensal
--   - Propinas (% configurable por establecimiento)
-- Implementacion: Fase 2+ (requiere UI significativa, modulo Flutter separado).

CREATE TABLE mesas_restaurante (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  establecimiento_id UUID NOT NULL,
  nombre          VARCHAR(20) NOT NULL,       -- "Mesa 1", "Barra 3"
  capacidad       INTEGER DEFAULT 4,
  pos_x           INTEGER DEFAULT 0,          -- posicion en layout editor
  pos_y           INTEGER DEFAULT 0,
  estado          VARCHAR(20) DEFAULT 'LIBRE', -- LIBRE|OCUPADA|RESERVADA|CUENTA_PEDIDA
  sesion_caja_id  UUID,
  activa          BOOLEAN DEFAULT true
);
CREATE TABLE comandas (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  mesa_id         UUID REFERENCES mesas_restaurante(id),
  sesion_caja_id  UUID NOT NULL,
  numero          VARCHAR(10),
  estado          VARCHAR(20) DEFAULT 'ABIERTA', -- ABIERTA|EN_PREPARACION|LISTA|FACTURADA
  mesero_id       UUID,
  comensales      INTEGER DEFAULT 1,
  created_at      TIMESTAMPTZ DEFAULT now()
);
CREATE TABLE comanda_lineas (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  comanda_id      UUID NOT NULL REFERENCES comandas(id) ON DELETE CASCADE,
  producto_id     UUID NOT NULL,
  cantidad        DECIMAL(18,6) NOT NULL DEFAULT 1,
  estacion        VARCHAR(20) DEFAULT 'COCINA', -- COCINA|BAR|POSTRES
  estado_kds      VARCHAR(20) DEFAULT 'PENDIENTE', -- PENDIENTE|PREPARANDO|LISTO
  comensal_num    INTEGER DEFAULT 1,
  notas           TEXT
);
CREATE TABLE modificadores_producto (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  nombre          VARCHAR(60) NOT NULL,         -- "sin cebolla", "extra queso"
  grupo           VARCHAR(40),                  -- "Extras", "Coccion", "Alergenos"
  precio_extra    DECIMAL(14,2) DEFAULT 0,
  activo          BOOLEAN DEFAULT true
);
```

