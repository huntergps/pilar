# CU-02: Distribuidora mayorista

> Caso de uso de referencia para implementación de PILAR ERP en distribución B2B.
> Ver índice completo en [`foundation/casos-uso/README.md`](../../../foundation/casos-uso/README.md).

**Tipo de negocio**: Distribuidora de productos de consumo masivo con ventas a tiendas y supermercados a nivel regional.

## Módulos activos

| Módulo | Rol en el negocio |
|--------|------------------|
| **Facturación** (Core) | Facturas electrónicas con condiciones de crédito 30/60/90 días |
| **Ventas** (Core) | Cotizaciones, OV, control crédito clientes, descuentos por volumen |
| **Compras** (Core) | Negociación proveedores, acuerdos marco, costos de aterrizaje |
| **Inventario** (Core) | Multi-bodega por zona, FIFO valoración, lotes con vencimiento |
| **Contabilidad** (Core) | Costeo por lote, margen por producto/categoría |
| **Tesorería** (Core) | CxC con aging, cobros multi-factura, anticipos clientes |
| **Tributación** (Core) | ATS, retenciones masivas |
| **CRM** (Auxiliar) | Seguimiento de clientes, visitas de vendedores, scoring |
| **RRHH** (Auxiliar) | Vendedores con comisiones, repartidores con rutas |
| **Ecommerce** (Auxiliar) | Portal B2B para que los clientes hagan pedidos online |

## Flujos principales

1. **Ciclo de venta con crédito**:
   ```
   Cotización → OV (con verificación crédito) → Picking bodega →
   Guía de remisión → Factura electrónica → Seguimiento CxC →
   Cobro (efectivo/transferencia/cheque) → Conciliación bancaria
   ```

2. **Gestión de cartera vencida**:
   ```
   Aging report → Bloqueo automático clientes >30 días vencidos →
   Notificación WhatsApp automática → Excepción supervisor →
   Plan de pago → Desbloqueo
   ```

3. **Reabastecimiento**:
   ```
   Forecast IA (demanda histórica) → Sugerencia de reorden →
   RFQ a proveedores → Adjudicación → OC → Recepción →
   Costo de aterrizaje (flete, descarga) → Actualización costo promedio
   ```

## Configuraciones especiales

- Lotes con fecha de vencimiento y alertas automáticas de próximo vencimiento.
- Descuentos por volumen escalonados en las OV (módulo Ventas/descuentos.md).
- Portal B2B en Ecommerce para que los clientes coloquen pedidos sin pasar por el vendedor.
- Comisiones de vendedores calculadas desde módulo RRHH con base en facturación cobrada.
