# Módulo: Facturación (Core Genérico)

Módulo Core de facturación **country-agnostic**: ciclo de vida de documentos de venta, cobros y cuentas por cobrar. Compatible con cualquier país. Para despliegues en Ecuador, el módulo auxiliar **`facturacion_ec`** añade el cumplimiento SRI.

**ID**: `facturacion`
**Tipo**: Core #4 — Fase de implementación: 2

---

## Decisión Arquitectónica

Facturación se divide en dos capas:

| Capa | Módulo | Contenido |
|------|--------|-----------|
| **Genérica** | `facturacion` (Core) | Ciclo de vida: BORRADOR→CONFIRMADA→AUTORIZADA→ANULADA. Tablas: facturas, NC, ND, cobros, CxC. RPCs genéricas. |
| **SRI Ecuador** | `facturacion_ec` (Extension) | Establecimientos, puntos de emisión, secuenciales, firma XAdES-BES, cola electrónica, RIDE PDF, certificado .p12 |

Este diseño permite usar PILAR en otros países (Colombia, Perú, etc.) simplemente **sin activar `facturacion_ec`** y conectando otra extensión de compliance local.

### Por qué facturacion sigue siendo Core

Otros módulos Core (Ventas, Compras, Tesorería) y Auxiliares (POS, Suscripciones, Citas) dependen del ciclo de vida de facturas. Si facturacion fuera Auxiliar, los módulos Core no podrían depender de él (violación de regla arquitectónica: Core no puede depender de Auxiliar).

---

## Documentos Gestionados

| Campo `tipo_doc` | Documento | Tabla |
|------------------|-----------|-------|
| `01` | Factura de venta | `facturas` |
| `04` | Nota de Crédito | `notas_credito` |
| `05` | Nota de Débito | `notas_debito` |

> En Ecuador (con `facturacion_ec`): tipos 03 (Liquidación Compra), 06 (Guía Remisión) y 07 (Retención) son manejados por `compras` e `inventario` pero encolados vía `facturacion_ec`.

---

## Tablas

### facturas
Documento de venta principal. Sin campos SRI en la versión genérica.

```
id, empresa_id, contacto_id, tipo_doc, numero, fecha_emision, fecha_vencimiento,
estado (BORRADOR|CONFIRMADA|AUTORIZADA|ANULADA), forma_pago_id, lista_precio_id,
moneda, tipo_cambio, subtotal, descuento_total, iva_total, total,
total_cobrado, saldo_pendiente (GENERATED), terminos_pago, notas,
info_adicional (JSONB), version, created_by, created_at, updated_at
```

> `facturacion_ec` añade: `establecimiento_id`, `punto_emision_id`, `secuencial`, `clave_acceso`, `numero_autorizacion`, `fecha_autorizacion`, `subtotal_0/5/15/no_obj/exento`, `ice_total`, `cola_doc_id`, `ride_url`, `xml_autorizado_url`

### factura_lineas
Detalle de ítems por factura. Incluye campos para IVA genérico e ICE (soft ref).

### factura_pagos
Formas de pago declaradas en el documento. En Ecuador SRI: códigos Tabla 24.

### cobros_factura
Pagos efectivos recibidos. Tipos: EFECTIVO, CHEQUE, TRANSFERENCIA, TARJETA, RETENCION, NOTA_CREDITO, ANTICIPO.

### notas_credito / nota_credito_lineas
Documentos de ajuste hacia abajo. Referencian factura origen.

### notas_debito / nota_debito_lineas
Documentos de cargo adicional (intereses, gastos de cobranza).

### cuentas_por_cobrar
Saldos pendientes por cliente. Se crea automáticamente al confirmar facturas a crédito. Aging disponible via `get_resumen_cxc()`.

---

## RPCs

| Función | Descripción |
|---------|-------------|
| `confirmar_factura(factura_id, version)` | **Genérica**: BORRADOR→CONFIRMADA + CxC. `facturacion_ec` reemplaza con versión SRI. |
| `anular_factura(factura_id, motivo, version)` | Anula factura y CxC. Usa bloqueo optimista. |
| `registrar_cobro(factura_id, monto, tipo, ...)` | Registra cobro parcial/total. Actualiza CxC. |
| `get_resumen_cxc(fecha)` | Aging CxC: corriente, 1-30, 31-60, 61-90, >90 días. |
| `get_estado_factura(factura_id)` | **Genérica**: estado, totales, saldo. `facturacion_ec` reemplaza con campos SRI. |

### Bloqueo Optimista

El campo `version` protege contra ediciones concurrentes. Todas las operaciones críticas validan que la `version` enviada coincida con la guardada:

```sql
IF v_factura.version <> p_version THEN
  RETURN jsonb_build_object('success', false, 'error', 'VERSION_CONFLICT', ...)
```

### `create_invoice(...)` — Crear factura completa (con detalles e impuestos)

```sql
CREATE OR REPLACE FUNCTION create_invoice(
  p_empresa_id UUID,
  p_contacto_id UUID,
  p_establecimiento VARCHAR,
  p_punto_emision VARCHAR,
  p_detalles JSONB,  -- [{producto_id, cantidad, precio, descuento}]
  p_formas_pago JSONB  -- [{forma_pago, total, plazo, unidad_tiempo}]
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_factura_id UUID;
  v_documento_id UUID;
  v_secuencial VARCHAR(9);
  v_total_sin_imp DECIMAL := 0;
  v_total_desc DECIMAL := 0;
  v_importe_total DECIMAL := 0;
BEGIN
  -- Obtener siguiente secuencial
  -- (lógica de secuenciales atómica)

  -- Crear documento electronico
  INSERT INTO documentos_electronicos (empresa_id, tipo_documento, ...)
  VALUES (p_empresa_id, '01', ...)
  RETURNING id INTO v_documento_id;

  -- Crear factura
  INSERT INTO facturas (empresa_id, documento_id, contacto_id, ...)
  VALUES (p_empresa_id, v_documento_id, p_contacto_id, ...)
  RETURNING id INTO v_factura_id;

  -- Insertar detalles con cálculos de impuestos
  -- Insertar impuestos por detalle
  -- Insertar formas de pago
  -- Calcular totales

  RETURN v_factura_id;
END;
$$;
```

### PostgREST (automático)

- `GET /rest/v1/facturas?estado=eq.BORRADOR` — Listar facturas en borrador
- `GET /rest/v1/facturas?contacto_id=eq.<uuid>` — Facturas por cliente
- `GET /rest/v1/cobros_factura?factura_id=eq.<uuid>` — Cobros por factura
- `GET /rest/v1/cuentas_por_cobrar?estado=neq.PAGADA` — CxC pendientes

### Notificaciones Multi-Canal (Edge Function `send-notification`)

| Canal | Servicio | Contenido |
|-------|----------|-----------|
| Email | Resend API | XML + RIDE PDF adjuntos |
| WhatsApp | WhatsApp Cloud API (Meta) | Mensaje + enlace al RIDE (requiere template aprobado) |
| Telegram | Bot API | Mensaje + PDF adjunto (bot de la empresa) |

Configuración por contacto (cliente/proveedor):
- En la ficha del contacto se marca cuáles canales activar
- Se puede marcar TODOS (recibe por email + WhatsApp + Telegram)
- Si no tiene ninguno marcado → solo email por defecto

Edge Function `send-notification`:
- Recibe: `documento_id`
- Lee contacto asociado al documento
- Para cada canal marcado, envía el comprobante
- Maneja errores por canal (si WhatsApp falla, no afecta email)
- Registra estado de envío por canal
- Soporta reenvío manual desde la UI

> Las Edge Functions SRI (`sri-firma-envio`, `poll-autorizacion`, `generate-ride`, `anular-documento`) son específicas del módulo `facturacion_ec`. Ver [`modules/extensiones/facturacion_ec/module.md`](../../extensiones/facturacion_ec/module.md#edge-functions).

---

## Module Service Bus

Otros módulos solicitan facturas a través del MSB:

```sql
-- Ventas: confirmar OV genera factura
SELECT module_bus.facturacion.create_invoice(p_orden_venta_id, p_version);

-- POS: confirmar ticket POS genera factura rápida
SELECT module_bus.facturacion.create_invoice_from_pos(p_sesion_caja_id);

-- Suscripciones: facturación recurrente
SELECT module_bus.facturacion.create_invoice(p_contrato_id, p_periodo);
```

La función gateway `module_bus.facturacion.create_invoice()` verifica si el módulo está activo antes de ejecutar.

---

## Navegación Flutter (planificada)

```
facturacion/
  ├── facturas/
  │     ├── index       # DataGrid: filtros por estado, fecha, cliente
  │     ├── nueva       # Emisión directa (sin OV)
  │     ├── :id         # Detalle: líneas, cobros, NC/ND relacionadas
  │     └── :id/cobros  # Registrar cobros
  ├── notas-credito/
  │     ├── index
  │     └── :id
  ├── notas-debito/
  │     ├── index
  │     └── :id
  └── cuentas-por-cobrar/
        └── index       # Aging CxC con filtros
```

> La sección `cola-sri/` está en el módulo `facturacion_ec`.

---

## Migrations

| # | Archivo | Contenido |
|---|---------|-----------|
| 000 | `000_shared_deps.sql` | Stubs idempotentes de `contactos` y `productos` (para instalación standalone) |
| 001 | `001_tables.sql` | 9 tablas + 5 RPCs genéricas |
| 002 | `002_seed_permissions.sql` | Permisos del módulo + asignaciones a roles |

---

## Dependencias

```
foundation (siempre activo)
  └── facturacion (Core)
        └── facturacion_ec (Auxiliar, opcional — solo para Ecuador SRI)
```

Para activar `facturacion_ec`:
```sql
SELECT activate_module('facturacion_ec', p_empresa_id);
-- Instala en orden: facturacion (si no estaba) → facturacion_ec
```

---

## Integraciones

### Cómo usan este módulo los módulos Core

| Módulo | Vía MSB | Descripción |
|--------|---------|-------------|
| **Ventas** | `module_bus.facturacion.create_invoice(orden_venta_id=...)` | Al confirmar OV. Lee facturas por `orden_venta_id` para mostrar estado. |
| **Compras** | `module_bus.facturacion.create_invoice(...)` | Liquidaciones de compra. En Ecuador (con `facturacion_ec`): encola tipo 03 y 07. |
| **Inventario** | `module_bus.facturacion.create_invoice(...)` | En Ecuador: encola guías de remisión tipo 06. |
| **Tesorería** | Lee `cobros_factura` | Para conciliación bancaria. Actualiza `cobros_factura.cuenta_bancaria_id`. |
| **Contabilidad** | Trigger/Realtime | Genera asientos automáticos al confirmar/anular facturas, NC y ND. |

### Cómo usan este módulo los módulos Auxiliares

| Módulo | Vía MSB | Descripción |
|--------|---------|-------------|
| **POS** | `module_bus.facturacion.create_invoice_from_pos(sesion_caja_id=...)` | Al cerrar cada venta en caja. |
| **Suscripciones** | `module_bus.facturacion.create_invoice(contrato_id=...)` | En el cron de facturación periódica. |
| **Proyectos** | `module_bus.facturacion.create_invoice(proyecto_id=...)` | Para hitos facturables. |
| **Garantías/RMA** | `module_bus.facturacion.create_invoice(...)` (NC) | Para emitir NC en devoluciones aprobadas. |

---

## Convenciones

- `DECIMAL(14,2)` para montos, `DECIMAL(18,6)` para cantidades/precios
- **NUNCA** `float` para valores monetarios
- Bloqueo optimista: campo `version` en todas las tablas de documentos
- Soft references a tablas de otros módulos (sin CASCADE) para independencia modular
- RLS: `USING (empresa_id = (SELECT private.get_empresa_id()))`

---

## Flujos Principales

### Ciclo de Vida de Documento

```
BORRADOR ──────────────────> CONFIRMADA ──────> AUTORIZADA
   │                              │                  │
   │ (edición libre)         (cobros, CxC)     (immutable)
   │                                                 │
   └──────────────────────────────────────────> ANULADA
```

> Con `facturacion_ec` activo: CONFIRMADA dispara el pipeline SRI (firma XAdES-BES → SOAP → AUTORIZADA/RECHAZADA). Ver [`modules/extensiones/facturacion_ec/flujos-sri.md`](../../extensiones/facturacion_ec/flujos-sri.md).

### Asientos Contables Automáticos

```
VENTA (Factura):
  DEBE: Cuentas por Cobrar     xxx.xx
  HABER: Ventas                       xxx.xx
  HABER: IVA Cobrado                  xxx.xx

COBRO:
  DEBE: Banco/Caja             xxx.xx
  HABER: Cuentas por Cobrar          xxx.xx
```

---

## Casos de Uso

### Actores

| Actor | Descripcion |
|-------|-------------|
| **Facturador** | Emite facturas, notas de crédito, notas de débito y registra cobros |
| **Contador** | Revisa asientos automáticos, gestiona cuentas por cobrar |
| **Sistema** | Módulos core y auxiliares que llaman al MSB para crear documentos |

### Casos de Uso - Facturación

| ID | Caso de Uso | Actor | Prioridad |
|----|-------------|-------|-----------|
| V03 | Emitir factura / documento de venta | Facturador | **Critica** |
| V04 | Emitir nota de credito | Facturador | **Critica** |
| V05 | Emitir nota de debito | Facturador | Alta |
| V06 | Registrar cobro | Facturador/Contador | Alta |
| V08 | Reenviar comprobante por email | Facturador | Media |
| V09 | Anular comprobante | Facturador | Alta |
| V11 | Facturar desde proforma/cotizacion | Facturador | Alta |
| V12 | Facturar desde despacho de inventario | Facturador/Bodeguero | Alta |

> **Casos de uso con firma electrónica SRI** (V03, V04, V05, V09, V11, V12): Ver [`modules/extensiones/facturacion_ec/flujos-sri.md`](../../extensiones/facturacion_ec/flujos-sri.md).
