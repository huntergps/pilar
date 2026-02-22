# Módulo: Pagos Online (extensión)

## Descripción

Pasarela de pagos configurable para procesar cobros online desde el portal de clientes y ecommerce. Soporta múltiples proveedores (Kushki, Paymentez, PayPhone) con patrón adaptador intercambiable.

## Funcionalidades

- Cobro con tarjeta de crédito/débito (Kushki, Paymentez)
- Cobro con billetera móvil (PayPhone)
- Webhooks de notificación de eventos de pago
- Conciliación automática de pagos con facturas
- Registro de transacciones y estados
- Configuración por empresa (proveedor activo, credenciales)
- Reembolsos parciales y totales

## Dependencias (módulos requeridos)

- `foundation` — Core foundation (empresas, auth, RLS)
- `facturacion` — Aplicar cobros a facturas autorizadas
- `tesoreria` — Registrar movimiento bancario al conciliar

## Tablas Principales

- `pagos_online` — Transacciones de pago online con estado
- `pagos_online_lineas` — Facturas cubiertas por cada pago
- `configuracion_pasarelas` — Credenciales por empresa por proveedor

## Edge Functions

- `process-payment/` — Procesa pago via proveedor configurado (patrón adaptador)
- `webhook-kushki/` — Recibe eventos Kushki (verify_jwt = false, firma HMAC)
- `webhook-paymentez/` — Recibe eventos Paymentez/Nuvei (verify_jwt = false, sync_token)

## Module Service Bus

```sql
-- Registrar pago exitoso y aplicar a factura
SELECT module_bus.facturacion.apply_online_payment(
  p_factura_id UUID,
  p_monto DECIMAL,
  p_referencia TEXT,
  p_proveedor TEXT
);
```

## Validaciones y Restricciones de Negocio

- Solo facturas en estado AUTORIZADO pueden recibir pagos
- El monto no puede superar el saldo pendiente de la factura
- Webhooks se validan con firma HMAC (Kushki) o sync_token (Paymentez)
- Credenciales se almacenan en Supabase Vault (nunca en texto plano)

## Flujos Principales

1. Cliente selecciona factura en portal → inicia pago → `process-payment`
2. Proveedor procesa cobro → notifica via webhook → `webhook-kushki` / `webhook-paymentez`
3. Webhook valida firma → registra en `pagos_online` → aplica a factura via MSB
4. Conciliación automática actualiza saldo CxC en Tesorería

## Sub-docs

- `migrations/001_tables.sql` — DDL tabla pagos_online + configuracion_pasarelas + RLS
