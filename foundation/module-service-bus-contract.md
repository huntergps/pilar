# Contrato del Module Service Bus (MSB)

**Estado**: Referencia canónica — leer antes de implementar cualquier interacción cross-módulo
**Relacionado con**: ADR-002, `arquitectura-modular.md`, `foundation/migrations/001_core_foundation.sql`

---

## Qué es el Module Service Bus y por qué existe

PILAR tiene 24 módulos que pueden activarse o desactivarse por empresa. Un módulo **Auxiliar** (POS, eCommerce, RRHH, CRM, etc.) necesita con frecuencia crear documentos o consultar datos en módulos **Core** (Facturación, Ventas, Inventario, etc.). El problema es que un módulo Core puede no estar activo para una empresa específica.

Si el módulo Auxiliar hace `INSERT INTO facturas (...)` directamente y el módulo Facturación no está activo, el resultado es una incoherencia de datos o un error en runtime. Peor aún: se crea un acoplamiento fuerte que hace imposible desactivar un módulo Core sin romper todos los Auxiliares que escriben en sus tablas.

El **Module Service Bus** resuelve esto con un contrato explícito:

```
Módulo Auxiliar → module_bus.<modulo_core>.<funcion>() → Módulo Core
```

Las funciones gateway en el schema `module_bus` verifican si el módulo Core destino está activo para la empresa. Si no está activo, retornan un NO-OP limpio en lugar de un error. Si está activo, ejecutan la operación real.

**Regla absoluta**: los módulos Auxiliares NUNCA hacen INSERT, UPDATE o DELETE directamente en tablas que pertenecen a módulos Core. Toda escritura cross-módulo pasa por el MSB.

---

## El patrón exacto que cada módulo Core debe implementar

### Plantilla de función gateway

Cada función gateway en `module_bus` sigue este patrón invariable:

```sql
-- Crear el schema del módulo dentro de module_bus (una vez por módulo)
CREATE SCHEMA IF NOT EXISTS module_bus_ventas;   -- ejemplo para ventas

-- Función gateway (ejemplo genérico)
CREATE OR REPLACE FUNCTION module_bus.<modulo_core>.<nombre_operacion>(
    p_empresa_id  UUID,
    p_param_1     <tipo>,
    p_param_2     <tipo>
    -- ... más parámetros según la operación
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER   -- Obligatorio: las funciones MSB omiten RLS por diseño
SET search_path = public, private
AS $$
DECLARE
    v_modulo_activo BOOLEAN;
    v_resultado     JSONB;
BEGIN
    -- PASO 1: Verificar si el módulo Core está activo para esta empresa
    SELECT EXISTS(
        SELECT 1
        FROM modulos_empresa
        WHERE empresa_id = p_empresa_id
          AND modulo_id  = '<modulo_core>'   -- ID exacto del módulo en tabla modulos
    ) INTO v_modulo_activo;

    -- PASO 2: NO-OP si el módulo no está activo
    IF NOT v_modulo_activo THEN
        RETURN jsonb_build_object(
            'ok',     FALSE,
            'error',  'MODULE_NOT_ACTIVE',
            'modulo', '<modulo_core>'
        );
    END IF;

    -- PASO 3: Validar parámetros obligatorios
    IF p_empresa_id IS NULL THEN
        RETURN jsonb_build_object('ok', FALSE, 'error', 'EMPRESA_ID_REQUIRED');
    END IF;

    -- PASO 4: Lógica real de la operación
    -- (INSERT / UPDATE / SELECT en las tablas del módulo Core)
    -- IMPORTANTE: incluir empresa_id en todas las operaciones (SECURITY DEFINER omite RLS)
    -- ...

    RETURN v_resultado;

EXCEPTION
    WHEN OTHERS THEN
        -- Loguear el error sin exponer stack interno
        RAISE WARNING '[module_bus.<modulo_core>.<nombre_operacion>] Error: %', SQLERRM;
        RETURN jsonb_build_object(
            'ok',    FALSE,
            'error', 'INTERNAL_ERROR',
            'msg',   SQLERRM
        );
END;
$$;

-- Revocar acceso público y otorgar solo a roles autenticados
REVOKE ALL ON FUNCTION module_bus.<modulo_core>.<nombre_operacion>(...) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION module_bus.<modulo_core>.<nombre_operacion>(...) TO authenticated;
```

### Contrato de respuesta

Toda función del MSB retorna `JSONB` con esta estructura:

| Caso | Respuesta |
|------|-----------|
| Módulo inactivo | `{"ok": false, "error": "MODULE_NOT_ACTIVE", "modulo": "<id>"}` |
| Parámetro inválido | `{"ok": false, "error": "VALIDATION_ERROR", "campo": "<nombre>", "msg": "<detalle>"}` |
| Error interno | `{"ok": false, "error": "INTERNAL_ERROR", "msg": "<mensaje>"}` |
| Éxito sin dato | `{"ok": true}` |
| Éxito con dato | `{"ok": true, "id": "<uuid>", "numero": "<doc>", ...}` |

**Nunca** retornar `NULL` ni lanzar `RAISE EXCEPTION` desde funciones MSB. El contrato exige que siempre retornen un JSONB evaluable por el caller.

---

## Módulos Core y sus funciones gateway obligatorias

Cada módulo Core que provee servicios al MSB debe implementar como mínimo las funciones listadas aquí. Las funciones adicionales se documentan en el `module.md` de cada módulo.

| Módulo Core | Schema MSB | Funciones gateway mínimas |
|-------------|-----------|--------------------------|
| **Facturación** | `module_bus.facturacion` | `create_invoice()`, `queue_sri_document()`, `get_invoice_status()` |
| **Ventas** | `module_bus.ventas` | `create_sale_order()`, `confirm_sale_order()`, `get_customer_credit()` |
| **Compras** | `module_bus.compras` | `create_purchase_order()`, `register_receipt()` |
| **Inventario** | `module_bus.inventario` | `reserve_stock()`, `move_stock()`, `get_available_stock()` |
| **Contabilidad** | `module_bus.contabilidad` | `create_journal_entry()`, `get_account_balance()` |
| **Tesorería** | `module_bus.tesoreria` | `register_payment()`, `get_account_balance()` |
| **Entidades** | `module_bus.entidades` | `get_or_create_contact()`, `get_product()` |

> Los módulos de Infraestructura (Administración, Comunicación) son siempre activos y no requieren verificación de actividad. Sus funciones se llaman directamente desde el schema `public` o `private`.

---

## Cómo llamar al MSB desde módulos Auxiliares

### Desde SQL / Edge Functions (Deno)

```sql
-- Desde una función o trigger del módulo Auxiliar:
SELECT module_bus.inventario.reserve_stock(
    p_empresa_id  := v_empresa_id,
    p_producto_id := v_producto_id,
    p_cantidad    := v_cantidad,
    p_referencia  := v_orden_id::TEXT,
    p_bodega_id   := v_bodega_id
);
```

```typescript
// Desde una Edge Function Deno:
const { data, error } = await supabase.rpc('module_bus_inventario_reserve_stock', {
  p_empresa_id:  empresaId,
  p_producto_id: productoId,
  p_cantidad:    cantidad,
  p_referencia:  ordenId,
  p_bodega_id:   bodegaId,
});

// SIEMPRE verificar el resultado
if (!data?.ok) {
  if (data?.error === 'MODULE_NOT_ACTIVE') {
    // Continuar en modo degradado: inventario no disponible
    console.warn('Módulo inventario inactivo — omitiendo reserva de stock');
  } else {
    throw new Error(`MSB error: ${data?.error}`);
  }
}
```

### Desde Dart / Flutter (a través de repository)

```dart
// Los módulos Auxiliares NUNCA llaman Supabase directamente desde widgets.
// La llamada al MSB ocurre en el repository o provider:

class PosOrderRepository {
  final SupabaseClient _supabase;

  Future<MsbResult> reservarStock({
    required String empresaId,
    required String productoId,
    required Decimal cantidad,
    required String bodegaId,
  }) async {
    final response = await _supabase.rpc(
      'module_bus_inventario_reserve_stock',
      params: {
        'p_empresa_id':  empresaId,
        'p_producto_id': productoId,
        'p_cantidad':    cantidad.toString(),
        'p_bodega_id':   bodegaId,
      },
    );

    final result = MsbResult.fromJson(response as Map<String, dynamic>);

    if (!result.ok && result.error == 'MODULE_NOT_ACTIVE') {
      // Modo degradado: POS puede funcionar sin inventario activo
      return MsbResult.noOp();
    }

    return result;
  }
}
```

---

## Ejemplo completo: `module_bus.ventas.create_invoice()`

Este ejemplo muestra la función completa que el módulo POS usa para crear una factura a través del módulo Facturación:

```sql
CREATE OR REPLACE FUNCTION module_bus.ventas.create_invoice(
    p_empresa_id        UUID,
    p_cliente_id        UUID,
    p_lineas            JSONB,   -- [{producto_id, cantidad, precio_unitario, descuento}]
    p_tipo_documento    CHAR(2)  DEFAULT '01',  -- 01=Factura, 04=NC, etc.
    p_forma_pago        TEXT     DEFAULT 'efectivo',
    p_referencia_origen TEXT     DEFAULT NULL   -- ID de la orden POS, OV, etc.
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
    v_facturacion_activo BOOLEAN;
    v_ventas_activo      BOOLEAN;
    v_factura_id         UUID;
    v_numero_documento   TEXT;
    v_linea              JSONB;
    v_subtotal           DECIMAL(14,2) := 0;
    v_total_iva          DECIMAL(14,2) := 0;
    v_total              DECIMAL(14,2) := 0;
BEGIN
    -- Verificar módulo Facturación activo
    SELECT EXISTS(
        SELECT 1 FROM modulos_empresa
        WHERE empresa_id = p_empresa_id AND modulo_id = 'facturacion'
    ) INTO v_facturacion_activo;

    IF NOT v_facturacion_activo THEN
        RETURN jsonb_build_object(
            'ok', FALSE, 'error', 'MODULE_NOT_ACTIVE', 'modulo', 'facturacion'
        );
    END IF;

    -- Verificar que el cliente existe y pertenece a la empresa
    IF NOT EXISTS (
        SELECT 1 FROM contactos
        WHERE id = p_cliente_id AND empresa_id = p_empresa_id AND es_cliente = TRUE
    ) THEN
        RETURN jsonb_build_object(
            'ok', FALSE, 'error', 'VALIDATION_ERROR',
            'campo', 'p_cliente_id', 'msg', 'Cliente no encontrado o no pertenece a la empresa'
        );
    END IF;

    -- Generar número de documento
    SELECT public.generar_numero_documento(p_empresa_id, p_tipo_documento)
    INTO v_numero_documento;

    -- Calcular totales de las líneas
    FOR v_linea IN SELECT * FROM jsonb_array_elements(p_lineas) LOOP
        v_subtotal := v_subtotal + (
            (v_linea->>'cantidad')::DECIMAL(18,6) *
            (v_linea->>'precio_unitario')::DECIMAL(18,6)
        ) - COALESCE((v_linea->>'descuento')::DECIMAL(14,2), 0);
    END LOOP;

    -- Calcular IVA (15% Ecuador — se obtiene de configuración)
    SELECT financial_round(v_subtotal * (tarifa / 100))
    INTO v_total_iva
    FROM tarifas_impuesto
    WHERE empresa_id = p_empresa_id AND codigo_sri = '2' AND activo = TRUE
    LIMIT 1;

    v_total := financial_round(v_subtotal + v_total_iva);

    -- Insertar factura
    INSERT INTO facturas (
        empresa_id, cliente_id, numero_documento, tipo_documento,
        subtotal, total_iva, total, forma_pago, referencia_origen,
        estado, created_at
    ) VALUES (
        p_empresa_id, p_cliente_id, v_numero_documento, p_tipo_documento,
        v_subtotal, v_total_iva, v_total, p_forma_pago, p_referencia_origen,
        'borrador', NOW()
    )
    RETURNING id INTO v_factura_id;

    -- Insertar líneas de factura
    INSERT INTO facturas_lineas (factura_id, empresa_id, producto_id, cantidad, precio_unitario, descuento)
    SELECT
        v_factura_id,
        p_empresa_id,
        (linea->>'producto_id')::UUID,
        (linea->>'cantidad')::DECIMAL(18,6),
        (linea->>'precio_unitario')::DECIMAL(18,6),
        COALESCE((linea->>'descuento')::DECIMAL(14,2), 0)
    FROM jsonb_array_elements(p_lineas) AS linea;

    RETURN jsonb_build_object(
        'ok',               TRUE,
        'factura_id',       v_factura_id,
        'numero_documento', v_numero_documento,
        'subtotal',         v_subtotal,
        'total_iva',        v_total_iva,
        'total',            v_total
    );

EXCEPTION
    WHEN OTHERS THEN
        RAISE WARNING '[module_bus.ventas.create_invoice] Error: %', SQLERRM;
        RETURN jsonb_build_object('ok', FALSE, 'error', 'INTERNAL_ERROR', 'msg', SQLERRM);
END;
$$;

REVOKE ALL ON FUNCTION module_bus.ventas.create_invoice(UUID, UUID, JSONB, CHAR(2), TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION module_bus.ventas.create_invoice(UUID, UUID, JSONB, CHAR(2), TEXT, TEXT) TO authenticated;
```

---

## Ejemplo completo: `module_bus.inventario.reserve_stock()`

```sql
CREATE OR REPLACE FUNCTION module_bus.inventario.reserve_stock(
    p_empresa_id  UUID,
    p_producto_id UUID,
    p_cantidad    DECIMAL(18,6),
    p_referencia  TEXT,           -- ID del documento que genera la reserva (orden, presupuesto, etc.)
    p_bodega_id   UUID DEFAULT NULL  -- NULL = bodega principal de la empresa
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
    v_activo          BOOLEAN;
    v_stock_disponible DECIMAL(18,6);
    v_bodega_id       UUID;
    v_reserva_id      UUID;
BEGIN
    -- Verificar módulo activo
    SELECT EXISTS(
        SELECT 1 FROM modulos_empresa
        WHERE empresa_id = p_empresa_id AND modulo_id = 'inventario'
    ) INTO v_activo;

    IF NOT v_activo THEN
        RETURN jsonb_build_object(
            'ok', FALSE, 'error', 'MODULE_NOT_ACTIVE', 'modulo', 'inventario'
        );
    END IF;

    -- Validar cantidad positiva
    IF p_cantidad <= 0 THEN
        RETURN jsonb_build_object(
            'ok', FALSE, 'error', 'VALIDATION_ERROR',
            'campo', 'p_cantidad', 'msg', 'La cantidad debe ser mayor a cero'
        );
    END IF;

    -- Resolver bodega (usar bodega principal si no se especificó)
    IF p_bodega_id IS NULL THEN
        SELECT id INTO v_bodega_id
        FROM bodegas
        WHERE empresa_id = p_empresa_id AND es_principal = TRUE AND activo = TRUE
        LIMIT 1;
    ELSE
        v_bodega_id := p_bodega_id;
    END IF;

    IF v_bodega_id IS NULL THEN
        RETURN jsonb_build_object(
            'ok', FALSE, 'error', 'VALIDATION_ERROR',
            'msg', 'No hay bodega principal configurada para esta empresa'
        );
    END IF;

    -- Verificar stock disponible (stock real - reservas previas activas)
    SELECT
        COALESCE(s.cantidad_disponible, 0) - COALESCE(SUM(r.cantidad), 0)
    INTO v_stock_disponible
    FROM inventario_stock s
    LEFT JOIN inventario_reservas r
           ON r.producto_id = p_producto_id
          AND r.bodega_id   = v_bodega_id
          AND r.empresa_id  = p_empresa_id
          AND r.estado       = 'activa'
    WHERE s.producto_id = p_producto_id
      AND s.bodega_id   = v_bodega_id
      AND s.empresa_id  = p_empresa_id
    GROUP BY s.cantidad_disponible;

    IF COALESCE(v_stock_disponible, 0) < p_cantidad THEN
        RETURN jsonb_build_object(
            'ok',                FALSE,
            'error',             'STOCK_INSUFICIENTE',
            'disponible',        COALESCE(v_stock_disponible, 0),
            'solicitado',        p_cantidad
        );
    END IF;

    -- Crear reserva
    INSERT INTO inventario_reservas (
        empresa_id, producto_id, bodega_id, cantidad, referencia, estado, created_at
    ) VALUES (
        p_empresa_id, p_producto_id, v_bodega_id, p_cantidad, p_referencia, 'activa', NOW()
    )
    RETURNING id INTO v_reserva_id;

    RETURN jsonb_build_object(
        'ok',         TRUE,
        'reserva_id', v_reserva_id,
        'bodega_id',  v_bodega_id,
        'cantidad',   p_cantidad,
        'disponible_restante', v_stock_disponible - p_cantidad
    );

EXCEPTION
    WHEN OTHERS THEN
        RAISE WARNING '[module_bus.inventario.reserve_stock] Error: %', SQLERRM;
        RETURN jsonb_build_object('ok', FALSE, 'error', 'INTERNAL_ERROR', 'msg', SQLERRM);
END;
$$;

REVOKE ALL ON FUNCTION module_bus.inventario.reserve_stock(UUID, UUID, DECIMAL, TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION module_bus.inventario.reserve_stock(UUID, UUID, DECIMAL, TEXT, UUID) TO authenticated;
```

---

## Dónde vive el código SQL del MSB

Las funciones gateway de cada módulo Core se definen en las migraciones del módulo correspondiente:

```
modules/core/<modulo>/migrations/NNN_module_bus.sql
```

El schema `module_bus` se crea en `foundation/migrations/001_core_foundation.sql`. Cada módulo Core crea su sub-schema dentro de él:

```sql
-- En modules/core/inventario/migrations/002_module_bus.sql
CREATE SCHEMA IF NOT EXISTS module_bus_inventario;
-- Las funciones se crean en el schema público con nombre prefijado
-- para compatibilidad con el PostgREST de Supabase:
-- module_bus_inventario_reserve_stock(...)
```

> **Nota de naming**: Supabase/PostgREST expone funciones mediante su nombre en el schema `public`. Para llamar a `module_bus.inventario.reserve_stock()` desde el cliente, la función se llama mediante `supabase.rpc('module_bus_inventario_reserve_stock', {...})`. El schema interno `module_bus` es una convención de nomenclatura para claridad en SQL; la función real vive en `public` con nombre compuesto.

---

## Referencias

- `foundation/adrs/ADR-002_module-service-bus.md` — decisión y alternativas rechazadas
- `foundation/arquitectura-modular.md` — ciclo de vida de módulos, activate_module()
- `foundation/field-ownership-matrix.md` — qué módulo posee cada tabla
- `modules/core/*/migrations/*_module_bus.sql` — implementaciones concretas por módulo
