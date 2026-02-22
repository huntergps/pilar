# CU-06: Tienda ecommerce

> Caso de uso de referencia para implementación de PILAR ERP en comercio electrónico multi-canal.
> Ver índice completo en [`foundation/casos-uso/README.md`](../../../foundation/casos-uso/README.md).

**Tipo de negocio**: Tienda online que vende en su web propia y en marketplaces (MercadoLibre, Shopify).

## Módulos activos

| Módulo | Rol en el negocio |
|--------|------------------|
| **Facturación** (Core) | Facturas automáticas al procesar pagos online |
| **Ventas** (Core) | Órdenes de venta desde todos los canales unificadas |
| **Inventario** (Core) | Stock unificado entre canales, alertas de quiebre |
| **Tesorería** (Core) | Conciliación de pagos online (Kushki/Paymentez) |
| **Tributación** (Core) | ATS con volumen alto de pequeñas transacciones |
| **Ecommerce** (Auxiliar) | Tienda WooCommerce, sync MercadoLibre/Shopify, portal clientes |
| **CRM** (Auxiliar) | Historial de compras, segmentación, email marketing |
| **IA/Chat** (Auxiliar) | Recomendaciones de productos, chat de soporte |

## Flujos principales

1. **Venta en tienda propia**:
   ```
   Cliente navega catálogo web → Agrega al carrito →
   Checkout (Kushki/PayPhone) → Pago aprobado →
   OV automática en PILAR → Factura electrónica al email →
   Picking bodega → Guía de remisión → Despacho (correo/mensajería) →
   Tracking enviado por email/WhatsApp
   ```

2. **Sincronización con MercadoLibre**:
   ```
   Venta en ML → Webhook → Edge Function sync →
   OV en PILAR (canal: MercadoLibre) → Descuento stock →
   Factura electrónica → Despacho → Upload tracking a ML
   ```

3. **Programa de lealtad**:
   ```
   Compra → Acumulación automática de puntos (por monto) →
   Email "¡Ganaste X puntos!" → Canje en siguiente compra →
   Descuento aplicado en checkout → Reducción de puntos (FIFO por vencimiento)
   ```

## Consideraciones especiales

- Gestión de stock unificado: un mismo producto tiene una sola bodega pero N canales de venta.
- Regla de stock: no permitir venta si stock < 0 (configurable por producto: sin_control/bloqueante).
- Imágenes de productos en Supabase Storage con CDN para la tienda web.
- Devoluciones (RMA) iniciadas desde el portal de clientes con foto obligatoria.
