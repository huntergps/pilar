# Flujos SRI Ecuador

> Extraído de `foundation/flujos-casos-uso.md` durante refactor ADR-006 (foundation country-agnostic).
> Contiene todos los flujos y casos de uso específicos del sistema tributario ecuatoriano:
> XAdES-BES, SOAP al SRI, generación RIDE, comprobantes electrónicos, ATS.

---

## Flujo de Ventas con Facturación Electrónica SRI

```
┌─────────┐    ┌──────────┐    ┌──────────────┐    ┌─────────┐
│ Crear   │───>│ Aprobar  │───>│ Generar      │───>│ Firmar  │
│ Cotiza- │    │ Pedido   │    │ Factura XML  │    │ XML     │
│ cion    │    │ Venta    │    │ (V2.1.0)     │    │ (XAdES) │
└─────────┘    └──────────┘    └──────────────┘    └────┬────┘
                                                        │
┌──────────┐    ┌──────────┐    ┌──────────────┐       │
│ Registrar│<───│ Generar  │<───│ Enviar WS    │<──────┘
│ Cobro    │    │ RIDE     │    │ SRI (recep.  │
│          │    │ (PDF)    │    │ + autoriz.)  │
└──────────┘    └──────────┘    └──────────────┘
      │
      v
┌──────────┐    ┌──────────┐
│ Asiento  │───>│ Incluir  │
│ Contable │    │ en ATS   │
│ Autom.   │    │ (ventas) │
└──────────┘    └──────────┘
```

### Flujos Alternativos de Facturación Electrónica

```
DESDE PROFORMA/COTIZACION:
  Cotizacion (aprobada) ──> Generar Factura (datos precargados) ──> Firma + SRI

DESDE DESPACHO:
  Orden Venta ──> Despacho (egreso bodega) ──> Facturar despacho ──> Firma + SRI

DESDE POS:
  Abrir caja ──> Escanear/buscar productos ──> Cobrar ──> Factura auto ──> Cerrar caja

DESDE ECOMMERCE:
  WooCommerce pedido ──> Webhook ──> Crear factura + despacho ──> Firma + SRI
```

---

## Flujo de Compras con Retención SRI

```
┌──────────┐    ┌──────────┐    ┌──────────────┐    ┌───────────┐
│ Registrar│───>│ Validar  │───>│ Calcular     │───>│ Generar   │
│ Factura  │    │ XML del  │    │ Retenciones  │    │ Comp.     │
│ Recibida │    │ Proveedor│    │ (IVA + Renta)│    │ Retencion │
└──────────┘    └──────────┘    └──────────────┘    └─────┬─────┘
                                                          │
┌──────────┐    ┌──────────┐    ┌──────────────┐         │
│ Incluir  │<───│ Asiento  │<───│ Registrar    │<────────┘
│ en ATS   │    │ Contable │    │ Pago a       │
│ (compras)│    │ Autom.   │    │ Proveedor    │
└──────────┘    └──────────┘    └──────────────┘
```

---

## Flujo de Nota de Crédito Electrónica

```
┌──────────┐    ┌──────────┐    ┌──────────────┐    ┌─────────┐
│ Seleccio-│───>│ Indicar  │───>│ Generar NC   │───>│ Firmar  │
│ nar      │    │ Items a  │    │ XML con ref  │    │ y Enviar│
│ Factura  │    │ Devolver │    │ a factura    │    │ al SRI  │
│ Original │    │ + Motivo │    │ original     │    │         │
└──────────┘    └──────────┘    └──────────────┘    └────┬────┘
                                                         │
                ┌──────────┐    ┌──────────────┐         │
                │ Asiento  │<───│ Actualizar   │<────────┘
                │ Contable │    │ Inventario   │
                │ Reverso  │    │ (devolucion) │
                └──────────┘    └──────────────┘
```

---

## Flujo de Generación ATS Mensual

```
┌──────────┐    ┌──────────┐    ┌──────────────┐    ┌──────────┐
│ Cierre   │───>│ Recopilar│───>│ Generar XML  │───>│ Validar  │
│ Mes      │    │ Compras  │    │ ATS segun    │    │ contra   │
│ Contable │    │ Ventas   │    │ XSD oficial  │    │ XSD      │
└──────────┘    │ Anulados │    │ (ISO-8859-1) │    └────┬─────┘
                │ Export.  │    └──────────────┘         │
                └──────────┘                              │
                                ┌──────────────┐         │
                                │ Comprimir    │<────────┘
                                │ ATmmaaaa.zip │
                                │ y Subir SRI  │
                                └──────────────┘
```

---

## Actores del Sistema (SRI-relevantes)

| Actor | Descripcion |
|-------|-------------|
| **Administrador** | Configura empresa, RUC, establecimientos, puntos de emisión, certificado digital (.p12), ambiente SRI, secuenciales, catálogo de retenciones |
| **Facturador** | Emite facturas electrónicas, notas de crédito/débito, comprobantes de retención, liquidaciones de compra |
| **Comprador** | Registra facturas de proveedores (XML SRI), calcula retenciones |
| **Contador** | Gestiona retenciones, declaraciones (103/104), ATS mensual |
| **SRI** | Sistema externo que recibe y autoriza documentos electrónicos vía SOAP |

---

## Casos de Uso — Ventas con Documentos Electrónicos SRI

| ID | Caso de Uso | Actor | Prioridad |
|----|-------------|-------|-----------|
| V03 | Emitir factura electrónica | Facturador | **Crítica** |
| V04 | Emitir nota de crédito electrónica | Facturador | **Crítica** |
| V05 | Emitir nota de débito electrónica | Facturador | Alta |
| V08 | Reenviar comprobante por email | Facturador | Media |
| V09 | Anular comprobante | Facturador | Alta |
| V11 | Facturar desde proforma/cotización | Facturador | Alta |
| V12 | Facturar desde despacho de inventario | Facturador/Bodeguero | Alta |

---

## Casos de Uso — Punto de Venta (POS) con Facturación Electrónica

| ID | Caso de Uso | Actor | Prioridad |
|----|-------------|-------|-----------|
| POS08 | Emitir factura electrónica o nota de venta | Cajero | **Crítica** |
| POS09 | Imprimir ticket/RIDE en impresora térmica | Cajero | Alta |

---

## Casos de Uso — Compras con Comprobantes SRI

| ID | Caso de Uso | Actor | Prioridad |
|----|-------------|-------|-----------|
| C02 | Registrar factura de proveedor | Comprador/Contador | **Crítica** |
| C03 | Emitir comprobante de retención | Contador | **Crítica** |
| C04 | Emitir liquidación de compra | Contador | Alta |

---

## Casos de Uso — Contabilidad SRI

| ID | Caso de Uso | Actor | Prioridad |
|----|-------------|-------|-----------|
| CT07 | Generar ATS mensual | Contador | **Crítica** |
| CT10 | Reporte de retenciones | Contador | Alta |

---

## Casos de Uso — Administración SRI

| ID | Caso de Uso | Actor | Prioridad |
|----|-------------|-------|-----------|
| A01 | Configurar empresa (RUC, establecimientos, puntos emisión) | Administrador | **Crítica** |
| A02 | Cargar certificado digital (.p12) | Administrador | **Crítica** |
| A05 | Configurar ambiente SRI (pruebas/producción) | Administrador | Alta |
| A06 | Gestionar catálogo de retenciones | Administrador | Alta |

---

## Documentos Electrónicos SRI Emitidos por PILAR

| Cod | Documento | Versión XSD | Actor |
|-----|-----------|-------------|-------|
| 01 | Factura | V2.1.0 | Facturador |
| 03 | Liquidación de Compra | V1.1.0 | Contador |
| 04 | Nota de Crédito | V1.1.0 | Facturador |
| 05 | Nota de Débito | V1.0.0 | Facturador |
| 06 | Guía de Remisión | V1.1.0 | Bodeguero |
| 07 | Comprobante de Retención | V2.0.0 | Contador |

---

## Referencias

- Pipeline técnico XAdES-BES + SOAP: `modules/extensiones/facturacion_ec/module.md`
- Edge Functions: `sri-firma-envio`, `generate-ride`, `poll-autorizacion`
- Regulatorio SRI: `foundation/regulatorio/`
- ATS detallado: `modules/extensiones/tributacion_ec/module.md`
