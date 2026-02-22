# CU-01: Ferretería ecuatoriana

> Caso de uso de referencia para implementación de PILAR ERP en retail/distribución con POS.
> Ver índice completo en [`foundation/casos-uso/README.md`](../../../foundation/casos-uso/README.md).

**Tipo de negocio**: Ferretería con local físico, atención al público general y venta a constructoras.

## Módulos activos

| Módulo | Rol en el negocio |
|--------|------------------|
| **Facturación** (Core) | Emisión de facturas electrónicas tipo 01 al contado y a crédito |
| **Ventas** (Core) | Órdenes de venta a crédito para constructoras con control de límite |
| **Compras** (Core) | Órdenes de compra a proveedores, retenciones tipo 07 |
| **Inventario** (Core) | Multi-bodega (bodega principal + bodegas externas), multi-empaque |
| **Contabilidad** (Core) | Asientos automáticos, estados financieros Supercias |
| **Tesorería** (Core) | CxC, CxP, conciliación bancaria, caja chica mostrador |
| **Tributación** (Core) | ATS mensual, Form 103/104 |
| **POS** (Auxiliar) | Caja en mostrador, modo FERRETERÍA (pre-venta + despacho) |
| **Ecommerce** *(opcional)* | Catálogo online para constructoras con precios de lista |

## Flujos principales

1. **Venta mostrador (POS)**:
   ```
   Búsqueda producto (código/nombre) → Agregar al carrito →
   Seleccionar forma de pago (efectivo/tarjeta/transferencia) →
   Factura electrónica automática → Despacho desde bodega
   ```

2. **Venta a crédito (constructoras)**:
   ```
   OV con condición de crédito → Verificación límite →
   Despacho con guía de remisión (tipo 06) →
   Factura electrónica → CxC → Cobro multi-factura
   ```

3. **Compra a proveedor**:
   ```
   OC → Recepción (verifica cantidades y series) →
   Factura proveedor (import XML SRI o manual) →
   Retención electrónica (tipo 07) → CxP → Pago
   ```

## Configuración SRI requerida

- Establecimiento + puntos de emisión para POS y ventas
- Certificado digital `.p12` del representante legal
- Resolución de contribuyente especial (si aplica)
- Parametrización de retenciones (proveedor tipo persona natural: IR 1% bienes, IVA 30%)

## Documentos electrónicos emitidos

| Tipo | Documento | Módulo emisor |
|------|-----------|---------------|
| 01 | Factura al cliente | Facturación |
| 04 | Nota de crédito (devoluciones) | Facturación |
| 06 | Guía de remisión (entregas a domicilio) | Inventario → Facturación |
| 07 | Retención a proveedores | Compras → Facturación |

## Consideraciones especiales

- Multi-empaque crítico: varillas de acero en unidades, paquetes y toneladas; cemento en sacos y pallets.
- Series en productos eléctricos (transformadores, tableros) para trazabilidad en garantías.
- Bodega virtual de reservas para constructoras con proyectos a largo plazo.
- Modo FERRETERÍA del POS: el vendedor crea la pre-venta, el bodeguero despacha con validación de cantidades.
