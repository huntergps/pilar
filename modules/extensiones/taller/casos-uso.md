# CU-05: Taller de servicios

> Caso de uso de referencia para implementación de PILAR ERP en talleres de reparación y mantenimiento.
> Ver índice completo en [`foundation/casos-uso/README.md`](../../../foundation/casos-uso/README.md).

**Tipo de negocio**: Taller de reparación de equipos electrónicos, electrodomésticos o maquinaria industrial.

## Módulos activos

| Módulo | Rol en el negocio |
|--------|------------------|
| **Facturación** (Core) | Facturas por reparaciones y repuestos vendidos |
| **Inventario** (Core) | Repuestos y materiales para reparaciones |
| **Tesorería** (Core) | Cobros, anticipos de clientes |
| **Taller** (Auxiliar) | Órdenes de reparación, diagnóstico, proforma, consumo, entrega |
| **Garantías/RMA** (Auxiliar) | Reclamos de garantía de clientes y devoluciones a proveedores |
| **Activos Fijos** (Auxiliar) | Herramientas del taller, maquinaria, equipos de diagnóstico |
| **Consumibles** (Auxiliar) | Insumos de taller (soldadura, adhesivos, lubricantes) |

## Flujos principales

1. **Ingreso de equipo para reparación**:
   ```
   Recepción del equipo (foto/video del estado inicial) →
   Diagnóstico técnico → Proforma al cliente →
   Aprobación cliente (firma digital o WhatsApp) →
   Asignación a técnico → Consumo de repuestos (inventario) +
   Registro mano de obra (horas × tarifa) →
   Control de calidad → Entrega con firma → Factura
   ```

2. **Reclamo de garantía**:
   ```
   Cliente reporta falla en período de garantía →
   RMA en Garantías/RMA (referencia factura original) →
   Evaluación: ¿dentro de garantía? →
   Sí: reparación sin costo (Taller) o reemplazo (NC + nueva factura) →
   No: presupuesto nueva reparación
   ```

3. **Reparación en garantía con proveedor**:
   ```
   El proveedor del repuesto defectuoso cubre garantía →
   RMA hacia proveedor (Garantías/RMA → Compras) →
   Proveedor repone repuesto o emite NC →
   Cierre de RMA con proveedor
   ```

## Consideraciones especiales

- Conversión de unidades en consumibles: se compra aceite en galones, se consume en mililitros.
- Herramientas vinculadas a Activos Fijos para control de mantenimiento y depreciación.
- Bodegas especializadas: TALLER (repuestos asignados a órdenes), SUMINISTROS_TALLER (insumos generales).
- Fotografías de evidencia almacenadas en Supabase Storage como adjuntos de la orden.
