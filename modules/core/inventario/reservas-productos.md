# Reservas de Productos (Inventario)

*Spec derivada del módulo `l10n_ec_product_reservation` (Odoo 19.1 Ecuador — producción en csolish/tecnoh)*

---

## Descripción

Permite reservar productos del stock para un cliente o propósito específico sin crear una orden de venta, usando una ubicación de almacén dedicada. Soporta vencimientos automáticos, renovaciones con límite de días, y conversión directa a orden de venta.

---

## Flujo General

```
1. CREAR reserva (cliente, productos, fecha vencimiento)
     ↓
2. CONFIRMAR → mueve stock a ubicación de reservas
     ↓
3. [Opcional] RENOVAR → extiende vencimiento
     ↓
4. ENTREGAR → convierte en orden de venta / despacha
     o
   CANCELAR → devuelve stock a ubicación original
     ↓
5. Cron diario → VENCER reservas expiradas automáticamente
```

---

## Modelo de Datos

### Tabla: `reservas_productos`

```sql
CREATE TABLE reservas_productos (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  nombre                TEXT,                       -- Secuencia: RES-00001
  contacto_id           UUID NOT NULL REFERENCES contactos(id),
  vendedor_id           UUID REFERENCES usuarios(id),
  fecha                 DATE NOT NULL DEFAULT CURRENT_DATE,
  fecha_vencimiento     DATE NOT NULL,              -- fecha + dias_reserva_default
  estado                TEXT NOT NULL DEFAULT 'borrador'
                        CHECK (estado IN ('borrador','reservado','entregado','cancelado','vencido')),
  ubicacion_origen_id   UUID REFERENCES ubicaciones(id),    -- desde dónde se toma el stock
  ubicacion_reserva_id  UUID REFERENCES ubicaciones(id),    -- bodega de reservas (virtual)
  notas                 TEXT,
  orden_venta_id        UUID REFERENCES ordenes_venta(id),  -- OV generada al entregar
  -- Auditoría
  creado_por            UUID REFERENCES usuarios(id),
  creado_en             TIMESTAMPTZ DEFAULT now(),
  actualizado_en        TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE reservas_productos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON reservas_productos FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));
```

### Tabla: `reservas_productos_lineas`

```sql
CREATE TABLE reservas_productos_lineas (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  reserva_id            UUID NOT NULL REFERENCES reservas_productos(id) ON DELETE CASCADE,
  secuencia             INT DEFAULT 10,
  producto_id           UUID NOT NULL REFERENCES productos(id),
  cantidad              NUMERIC(15,4) NOT NULL CHECK (cantidad > 0),
  unidad_medida_id      UUID REFERENCES unidades_medida(id),
  precio_unitario       NUMERIC(15,4) DEFAULT 0,
  -- Stock moves
  picking_reserva_id    UUID,                       -- movimiento a ubicación reservas
  picking_devolucion_id UUID,                       -- movimiento de retorno
  cantidad_disponible   NUMERIC(15,4),              -- stock en ubicacion_origen (calculado)
  -- Lote/Serie
  lote_id               UUID REFERENCES lotes_series(id)
);
```

### Tabla: `reservas_renovaciones` (historial)

```sql
CREATE TABLE reservas_renovaciones (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reserva_id      UUID NOT NULL REFERENCES reservas_productos(id) ON DELETE CASCADE,
  fecha_anterior  DATE NOT NULL,
  fecha_nueva     DATE NOT NULL,
  usuario_id      UUID REFERENCES usuarios(id),
  motivo          TEXT,
  creado_en       TIMESTAMPTZ DEFAULT now()
);
```

---

## Estados del Ciclo de Vida

```
BORRADOR → RESERVADO → ENTREGADO
              ↓
           CANCELADO
              ↓
           VENCIDO (cron)
```

| Estado | Descripción | Movimiento de stock |
|---|---|---|
| `borrador` | Creada, sin confirmar | Ninguno |
| `reservado` | Confirmada, stock en ubicación reservas | Picking a bodega virtual |
| `entregado` | Convertida en OV o despachada | Picking de entrega |
| `cancelado` | Anulada manualmente | Devolución a origen |
| `vencido` | Expiró sin entrega | Devolución automática a origen |

---

## Lógica de Reserva

### Confirmar Reserva (`action_reserve`)

1. Valida que haya stock suficiente en `ubicacion_origen_id`
2. Crea picking de tipo `internal`: origen → ubicación de reservas
3. Si `auto_validate_reservations = true` en config → valida el picking automáticamente
4. Cambia estado a `reservado`

### Cancelar/Vencer (`action_cancel` / `action_expire`)

1. Crea picking de retorno: ubicación reservas → origen
2. Valida el picking
3. Cambia estado a `cancelado` o `vencido`

### Renovar (`action_renew`)

- Extiende `fecha_vencimiento` por N días (configurable, con máximo absoluto)
- Valida que la nueva fecha no exceda `fecha + max_dias_renovacion`
- Registra en `reservas_renovaciones`

### Entregar (`action_deliver`)

1. Crea orden de venta con las líneas de la reserva
2. La OV puede confirmar y generar picking de entrega automáticamente
3. Cambia estado a `entregado`

---

## Funciones RPC

```typescript
// Crear reserva
create_reserva(params: {
  contacto_id: UUID
  fecha_vencimiento: string
  ubicacion_origen_id?: UUID    // por defecto: ubicación principal empresa
  lineas: [{
    producto_id: UUID
    cantidad: number
    precio_unitario?: number
    lote_id?: UUID
  }]
  notas?: string
}): { reserva_id: UUID, nombre: string }

// Confirmar (reserva el stock)
confirmar_reserva(reserva_id: UUID): {
  estado: 'reservado'
  picking_id: UUID
}

// Renovar vencimiento
renovar_reserva(params: {
  reserva_id: UUID
  nueva_fecha: string
  motivo?: string
}): { fecha_vencimiento: string }

// Entregar (genera OV)
entregar_reserva(params: {
  reserva_id: UUID
  diario_id?: UUID
  confirmar_ov?: boolean
}): { orden_venta_id: UUID }

// Cancelar
cancelar_reserva(reserva_id: UUID): {
  estado: 'cancelado'
  picking_devolucion_id: UUID
}

// Verificar disponibilidad antes de reservar
check_disponibilidad(params: {
  lineas: [{ producto_id: UUID, cantidad: number }]
  ubicacion_id: UUID
}): [{ producto_id: UUID, disponible: number, suficiente: boolean }]

// Dashboard de reservas
get_reservas_dashboard(): {
  total_activas: number
  por_vencer_7_dias: number
  vencidas_hoy: number
  valor_reservado: number
}
```

---

## Edge Functions (Cron)

| Función | Trigger | Descripción |
|---|---|------|
| `expire-reservations` | Cron diario (00:00) | Marca como `vencido` y devuelve stock de reservas cuya `fecha_vencimiento < CURRENT_DATE` y estado=`reservado` |
| `notify-expiring-reservations` | Cron diario | Alerta a vendedor/cliente N días antes del vencimiento |

---

## Configuración por Empresa

```json
{
  "reservas": {
    "dias_reserva_default": 7,
    "max_dias_renovacion": 30,
    "dias_alerta_vencimiento": 2,
    "auto_validate_reservations": true,
    "ubicacion_reservas_id": "uuid",
    "requiere_precio": false,
    "grupo_puede_reservar": "inventario.grupo_reservas_user",
    "grupo_puede_renovar": "inventario.grupo_reservas_manager"
  }
}
```

---

## Permisos

| Rol | Puede crear | Puede renovar | Puede cancelar | Puede entregar |
|---|---|---|---|---|
| `Usuario Ventas` | ✓ | ✓ (dentro del límite) | ✗ | ✓ |
| `Manager Inventario` | ✓ | ✓ (sin límite) | ✓ | ✓ |
| `Admin` | ✓ | ✓ | ✓ | ✓ |

---

## Validaciones de Negocio

- Stock debe ser suficiente al confirmar (no se permite reserva parcial por línea)
- `fecha_vencimiento` ≥ fecha actual
- La renovación no puede superar `fecha_creacion + max_dias_renovacion`
- No se puede cancelar si ya fue entregada
- No se puede modificar líneas una vez `reservado`
- Solo un picking activo por reserva (no duplicar movimientos)

---

## Pantallas Flutter

### Lista de Reservas
- `CrudScaffold<Reserva>` con filtros: estado, contacto, vendedor, rango fechas
- Columnas: nombre, contacto, fecha_vencimiento, # productos, valor, estado
- Badge de color: verde (reservado), naranja (por vencer ≤7 días), rojo (vencido)
- Acción rápida: renovar desde la lista

### Formulario de Reserva

```
┌────────────────────────────────────────────────────────┐
│ RESERVA DE PRODUCTOS                    [RES-00042]    │
│ Cliente: [selector contacto]   Vendedor: [auto-fill]   │
│ Vence: [date picker]           Origen: [ubicación]     │
├────────────────────────────────────────────────────────┤
│ PRODUCTOS                                              │
│ ┌───────────────┬──────────┬──────────┬──────────────┐ │
│ │ Producto      │ Cantidad │ Disponib.│ Precio       │ │
│ ├───────────────┼──────────┼──────────┼──────────────┤ │
│ │ Laptop ASUS   │    2     │    8     │ $950.00      │ │
│ │ Mouse USB     │    2     │   15     │ $12.00       │ │
│ └───────────────┴──────────┴──────────┴──────────────┘ │
│ [+ Agregar Línea]                                      │
├────────────────────────────────────────────────────────┤
│ Total: $1,924.00                                       │
│ [Confirmar Reserva]  [Renovar]  [Entregar]  [Cancelar] │
└────────────────────────────────────────────────────────┘
```

### Dialog de Renovación
- Campo: nueva fecha de vencimiento
- Muestra: máximo permitido
- Campo: motivo (opcional)
- Historial de renovaciones anteriores

---

## Tabla Adicional: `reservas_producto` (integración con stock)

La tabla `reservas_producto` complementa a `reservas_productos` para el control
fino de stock a nivel de campo `cantidad_reservada` en `inventario_stock`.
A diferencia de `reservas_productos` (que modela la reserva formal de un cliente con
bodega virtual), esta tabla modela la reserva a nivel de línea de OV/cotización para
el control de disponibilidad inmediata sin mover físicamente el stock.

```sql
CREATE TABLE reservas_producto (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id UUID NOT NULL REFERENCES empresas(id),
  producto_id UUID NOT NULL REFERENCES productos(id),
  presentacion_id UUID REFERENCES producto_presentaciones(id),
  bodega_id UUID NOT NULL REFERENCES bodegas(id),
  cantidad DECIMAL(18,6) NOT NULL,
  origen_tipo VARCHAR(20) NOT NULL CHECK (origen_tipo IN ('ORDEN_VENTA','COTIZACION','MANUAL','POS')),
  origen_id UUID NOT NULL,                -- ID de la OV, cotización, sesión POS, etc.
  fecha_vencimiento TIMESTAMPTZ NOT NULL, -- Cuándo expira la reserva automáticamente
  estado VARCHAR(15) DEFAULT 'ACTIVA' CHECK (estado IN ('ACTIVA','LIBERADA','CONSUMIDA','VENCIDA')),
  motivo_liberacion TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- El stock reservado NO se separa físicamente en esta modalidad.
-- Se refleja en inventario_stock.cantidad_reservada (campo calculado/actualizado por trigger).
-- La disponibilidad real = cantidad_actual - cantidad_reservada

ALTER TABLE reservas_producto ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON reservas_producto FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE INDEX idx_reservas_prod_bodega ON reservas_producto(bodega_id, producto_id)
  WHERE estado = 'ACTIVA';
CREATE INDEX idx_reservas_prod_origen ON reservas_producto(origen_tipo, origen_id);
CREATE INDEX idx_reservas_prod_vencimiento ON reservas_producto(fecha_vencimiento)
  WHERE estado = 'ACTIVA';
CREATE INDEX idx_reservas_prod_empresa ON reservas_producto(empresa_id, estado);
```

---

## RPCs Adicionales de Reservas

```sql
-- ══════════════════════════════════════════════════════════════
-- RPC: Reservar stock (a nivel de inventario_stock)
-- Verifica disponible = cantidad_actual - cantidad_reservada
-- Incrementa cantidad_reservada en inventario_stock
-- Crea registro en reservas_producto con fecha de vencimiento
-- ══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION reserve_stock(
  p_producto_id UUID,
  p_bodega_id UUID,
  p_cantidad DECIMAL(18,6),
  p_origen_tipo VARCHAR(20),
  p_origen_id UUID,
  p_horas_vencimiento INT DEFAULT 24
) RETURNS UUID  -- reserva_id
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_empresa_id UUID := (SELECT private.get_empresa_id());
  v_stock RECORD;
  v_disponible DECIMAL(18,6);
  v_reserva_id UUID;
BEGIN
  -- Verificar stock disponible con bloqueo para evitar race conditions
  SELECT * INTO v_stock FROM inventario_stock
  WHERE empresa_id = v_empresa_id
    AND producto_id = p_producto_id
    AND bodega_id = p_bodega_id
  FOR UPDATE;

  IF v_stock.id IS NULL THEN
    RAISE EXCEPTION 'No existe stock del producto en la bodega indicada';
  END IF;

  v_disponible := v_stock.cantidad_actual - COALESCE(v_stock.cantidad_reservada, 0);

  IF v_disponible < p_cantidad THEN
    RAISE EXCEPTION 'Stock insuficiente. Disponible: %, solicitado: %', v_disponible, p_cantidad;
  END IF;

  -- Incrementar cantidad reservada
  UPDATE inventario_stock SET
    cantidad_reservada = COALESCE(cantidad_reservada, 0) + p_cantidad,
    updated_at = NOW()
  WHERE id = v_stock.id;

  -- Crear registro de reserva
  INSERT INTO reservas_producto (empresa_id, producto_id, presentacion_id, bodega_id,
    cantidad, origen_tipo, origen_id, fecha_vencimiento)
  VALUES (v_empresa_id, p_producto_id, NULL, p_bodega_id,
    p_cantidad, p_origen_tipo, p_origen_id,
    NOW() + (p_horas_vencimiento || ' hours')::INTERVAL)
  RETURNING id INTO v_reserva_id;

  RETURN v_reserva_id;
END;
$$;

-- ══════════════════════════════════════════════════════════════
-- RPC: Liberar una reserva de stock
-- Decrementa cantidad_reservada, actualiza estado a LIBERADA
-- ══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION release_reservation(
  p_reserva_id UUID,
  p_motivo TEXT DEFAULT NULL
) RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_reserva reservas_producto%ROWTYPE;
  v_empresa_id UUID := (SELECT private.get_empresa_id());
BEGIN
  SELECT * INTO v_reserva FROM reservas_producto
  WHERE id = p_reserva_id AND empresa_id = v_empresa_id AND estado = 'ACTIVA';
  IF v_reserva.id IS NULL THEN
    RAISE EXCEPTION 'Reserva no encontrada o ya liberada';
  END IF;

  -- Liberar en inventario_stock
  UPDATE inventario_stock SET
    cantidad_reservada = GREATEST(0, COALESCE(cantidad_reservada, 0) - v_reserva.cantidad),
    updated_at = NOW()
  WHERE empresa_id = v_empresa_id
    AND producto_id = v_reserva.producto_id
    AND bodega_id = v_reserva.bodega_id;

  -- Actualizar estado de la reserva
  UPDATE reservas_producto SET
    estado = 'LIBERADA',
    motivo_liberacion = p_motivo
  WHERE id = p_reserva_id;

  RETURN true;
END;
$$;

-- ══════════════════════════════════════════════════════════════
-- RPC: Expirar reservas vencidas (ejecutado por cron job)
-- Libera automáticamente reservas cuya fecha_vencimiento < NOW()
-- Notifica al vendedor vía WhatsApp/email cuando corresponda
-- ══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION expire_old_reservations()
RETURNS JSONB  -- {liberadas, total_unidades_liberadas}
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_reserva RECORD;
  v_liberadas INTEGER := 0;
  v_unidades DECIMAL(18,6) := 0;
BEGIN
  FOR v_reserva IN
    SELECT rp.*, is2.id AS stock_id
    FROM reservas_producto rp
    JOIN inventario_stock is2 ON is2.empresa_id = rp.empresa_id
      AND is2.producto_id = rp.producto_id
      AND is2.bodega_id = rp.bodega_id
    WHERE rp.estado = 'ACTIVA'
      AND rp.fecha_vencimiento < NOW()
  LOOP
    -- Liberar cantidad reservada en stock
    UPDATE inventario_stock SET
      cantidad_reservada = GREATEST(0, COALESCE(cantidad_reservada, 0) - v_reserva.cantidad),
      updated_at = NOW()
    WHERE id = v_reserva.stock_id;

    -- Marcar reserva como vencida
    UPDATE reservas_producto SET estado = 'VENCIDA'
    WHERE id = v_reserva.id;

    -- TODO: Notificar al vendedor (via module_bus.comunicacion.notify())
    -- cuando el origen_tipo = 'ORDEN_VENTA' o 'COTIZACION'

    v_liberadas := v_liberadas + 1;
    v_unidades := v_unidades + v_reserva.cantidad;
  END LOOP;

  RETURN jsonb_build_object('liberadas', v_liberadas, 'total_unidades_liberadas', v_unidades);
END;
$$;
```

---

## Flujo de Reserva en Órdenes de Venta

```
1. Vendedor crea línea en OV → sistema llama reserve_stock() automáticamente
     │
     ├── Stock disponible: reserva creada (ACTIVA, vence en 24h por defecto)
     │     inventario_stock.cantidad_reservada += cantidad
     │
     └── Sin stock: opciones del vendedor:
           a) Lista de espera (notificar cuando ingrese stock)
           b) Back-order (OV parcial, el resto cuando haya stock)
           c) Rechazar línea

2. Cliente confirma OV y realiza pago
     │
     └── Reserva se CONSUME: release_reservation() + movimiento_inventario real
           inventario_stock.cantidad_actual -= cantidad
           inventario_stock.cantidad_reservada -= cantidad (queda en 0 para esa reserva)
           reservas_producto.estado = 'CONSUMIDA'

3. OV cancelada antes del pago
     └── release_reservation() → estado = 'LIBERADA'
           inventario_stock.cantidad_reservada -= cantidad

4. Cron diario (expire_old_reservations)
     └── Reservas vencidas → estado = 'VENCIDA' + liberar cantidad_reservada
           → Notificar al vendedor (evitar sorpresas en despacho)
```

**Renovación de reservas en órdenes de venta:**

```
- Supervisor puede extender la reserva de una OV no confirmada
- Máximo de renovaciones configurable: configuracion_empresa.max_renovaciones_reserva (default: 3)
- Cada renovación extiende la fecha_vencimiento por N horas (configurable)
- El historial de renovaciones se registra en reservas_renovaciones
- Flujo de aprobación: si la OV supera el límite de días sin pago → alerta a supervisor
```

---

## Relación con `reservas_productos` (Reserva Formal de Cliente)

```
reservas_producto          reservas_productos
(nivel stock interno)      (reserva formal con cliente)
─────────────────────      ────────────────────────────
Sin bodega virtual         Con bodega virtual dedicada
Auto-creada por OV/POS     Creada manualmente por vendedor
Vence en horas             Vence en días (configurable)
No mueve stock físico      Mueve stock a ubicación reservas
                           (picking interno)
Control inmediato           Control formal con cliente
```

Ambas modalidades pueden coexistir. Una reserva formal (`reservas_productos`)
crea internamente una `reserva_producto` para bloquear el stock durante el proceso.
