# Glosario Ecuador — PILAR ERP

> Términos fiscales, tributarios y regulatorios específicos de Ecuador (ADR-006).
> Para términos genéricos de arquitectura, stack y negocio, ver [foundation/glossario.md](../../../foundation/glossario.md).
> Última revisión: 2026-02-20

---

## Organismos y Marcos Legales

### SRI
**Servicio de Rentas Internas** — Organismo gubernamental ecuatoriano encargado de la administración, recaudación y control de los tributos internos. En PILAR, toda emisión de documentos electrónicos (facturas, NC, ND, retenciones, guías de remisión, liquidaciones) pasa por los Web Services del SRI para autorización en tiempo real o en diferido.

### Supercias
**Superintendencia de Compañías, Valores y Seguros** — Organismo de control de las sociedades en Ecuador. Las empresas constituidas como compañías deben presentar estados financieros anuales en formato TXT definido por Supercias (5 EEFF obligatorios: Balance General, Estado de Resultados, Estado de Flujo de Efectivo, Estado de Cambios en Patrimonio, Notas). En PILAR el módulo Tributación genera estos reportes desde los datos de Contabilidad.

### LOPDP
**Ley Orgánica de Protección de Datos Personales** — Marco legal ecuatoriano vigente desde 2021 que regula el tratamiento de datos personales. En PILAR impacta en: cifrado AES-256 de datos sensibles (RUC, certificados), logging de auditoría en `audit_log`, política de retención de datos, consentimiento explícito para comunicaciones por WhatsApp/email, y derecho al olvido. Ver `modules/localizacion/ecuador/lopdp.md` para la implementación.

### IESS
**Instituto Ecuatoriano de Seguridad Social** — Entidad pública que administra el sistema de seguridad social en Ecuador. En PILAR el módulo RRHH calcula las aportaciones patronales y personales al IESS (aporte individual 9.45%, patronal 11.15%) y genera los formularios de aviso de entrada/salida de trabajadores. Ver `modules/extensiones/rrhh/nomina-ecuador.md`.

### BCE
**Banco Central del Ecuador** — Institución financiera pública que emite las tasas de interés legales, tablas de amortización y tipos de cambio referenciales. En PILAR el módulo Tesorería consulta las tasas activa y pasiva del BCE para el cálculo de intereses en documentos vencidos y anticipos. Ver `modules/localizacion/ecuador/integraciones-ec.md`.

### RIMPE
**Régimen Simplificado para Emprendedores y Negocios Populares** — Régimen tributario simplificado del SRI para contribuyentes con ingresos anuales de hasta USD 300.000. Los contribuyentes RIMPE tienen tablas de impuesto a la renta diferenciadas y obligaciones reducidas. En PILAR se parametriza en la configuración de empresa para aplicar las tarifas y restricciones correctas.

---

## Identificación Tributaria

### RUC
**Registro Único de Contribuyentes** — Identificación tributaria de 13 dígitos que el SRI asigna a personas naturales y jurídicas que realizan actividades económicas en Ecuador. Los tres últimos dígitos son siempre `001`. En PILAR, el RUC del emisor forma parte de la clave de acceso de cada documento electrónico y se valida con el algoritmo de módulo 11 al registrar proveedores y clientes.

---

## Documentos Electrónicos SRI

### Factura electrónica
Documento tributario de tipo `01` autorizado por el SRI en formato XML firmado con XAdES-BES. En PILAR la emite el módulo Facturación a través de la Edge Function `sri-firma-envio`, que genera el XML, lo firma, lo envía vía SOAP al SRI, almacena el XML autorizado en Supabase Storage y genera el RIDE en PDF.

### NC (Nota de Crédito)
Documento electrónico tipo `04` que anula total o parcialmente una factura emitida. En PILAR se crea desde Facturación con `create_credit_note(factura_id, motivo, lineas)` y sigue el mismo pipeline SRI que la factura original. El módulo Ventas llama a este RPC vía Module Service Bus.

### ND (Nota de Débito)
Documento electrónico tipo `05` que incrementa el valor de una factura ya emitida (intereses, gastos adicionales). En PILAR se gestiona desde Facturación y aplica el mismo pipeline XAdES-BES → SOAP → autorización → RIDE.

### Liquidación de compra
Documento electrónico tipo `03` que emite una empresa cuando adquiere bienes o servicios a personas naturales no obligadas a llevar contabilidad (artesanos, agricultores, etc.). En PILAR se gestiona desde el módulo Compras y sigue el mismo pipeline SRI que la factura estándar.

### Guía de remisión
Documento electrónico tipo `06` que respalda el traslado de mercaderías. En PILAR la tabla `guias_remision` está en el módulo Inventario y se emite automáticamente al aprobar una transferencia entre bodegas de diferente dirección o al despachar una orden de venta con entrega física. El pipeline SRI aplica igual que para otros documentos.

### Comprobante de retención
Documento electrónico tipo `07` que emite el agente de retención al proveedor como constancia de los valores retenidos. En PILAR se genera automáticamente al registrar una factura de proveedor sujeta a retención, a través del módulo Compras y el pipeline SRI de Facturación.

---

## Impuestos y Tributos

### IVA (Ecuador)
**Impuesto al Valor Agregado** — Impuesto indirecto aplicado al consumo. Las tarifas vigentes y sus códigos SRI:

| Código SRI | Tarifa | Vigencia / Contexto |
|-----------|--------|---------------------|
| 0 | Sin impuesto (campo vacío) | Retenciones y doc sin IVA |
| 2 | 0% | Bienes/servicios gravados tarifa 0% |
| 4 | 15% | Tarifa general vigente desde 2024 |
| 5 | 5% | Bienes de primera necesidad (canasta básica ampliada), aplicable desde 2024 |
| 6 | Exento | Bienes/servicios exentos por ley |
| 7 | No objeto de IVA | Transacciones que no son objeto del impuesto |
| 8 | 0% diferenciado | Régimen especial (Galápagos, zonas francas) |

En PILAR las tarifas se parametrizan en `catalogo_tarifas_iva` (módulo Administración) con vigencias, para soportar cambios futuros sin modificar código. Ver `modules/localizacion/ecuador/datos-referencia-ec.md`.

### Retención en la fuente
Mecanismo por el cual el agente de retención descuenta un porcentaje del pago al proveedor y lo declara al SRI. Existen dos tipos:
- **IR (Impuesto a la Renta)**: porcentajes según el tipo de bien/servicio (1%, 2%, 8%, 10%, etc.).
- **IVA**: porcentajes según el tipo de transacción (20%, 30%, 70%, 100%).

En PILAR, la retención genera el comprobante electrónico tipo `07` vía Facturación y su tabla principal es `retenciones` en el módulo Compras.

---

## Reportes y Anexos SRI

### ATS
**Anexo Transaccional Simplificado** — Reporte mensual que todos los contribuyentes especiales y sociedades deben presentar al SRI en formato XML, detallando todas las compras, ventas, retenciones y exportaciones del período. En PILAR lo genera el módulo Tributación mediante la Edge Function `generate-ats`, leyendo datos de Facturación, Compras y Contabilidad vía Module Service Bus. El archivo ZIP resultante se sube a Supabase Storage y queda disponible para descarga.

### Formulario 103
Declaración mensual del Impuesto a la Renta en la Fuente. En PILAR lo genera el módulo Tributación con la Edge Function `generate-declaracion-103`, consolidando todas las retenciones de IR del período desde el módulo Compras.

### Formulario 104
Declaración mensual del IVA. En PILAR lo genera el módulo Tributación con la Edge Function `generate-declaracion-104`, consolidando ventas, compras e IVA del período.

---

## Firma Electrónica y Protocolo SRI

### XAdES-BES
Estándar de firma digital XML Advanced Electronic Signature - Basic Electronic Signature. El SRI exige esta firma para todos los documentos electrónicos. En PILAR la firma se realiza en el servidor (Edge Function Deno con la librería `ec-sri-invoice-signer`) usando el certificado `.p12` del contribuyente almacenado cifrado en Supabase Storage. **Flutter nunca maneja la firma** — el cliente solo envía los datos del documento.

### Clave de acceso
Identificador único de 49 dígitos que el SRI asigna a cada documento electrónico. Se construye así:
```
[8 fecha][2 tipo_doc][13 RUC][1 ambiente][9 establecimiento+punto+secuencial][8 código_numérico][1 tipo_emisión][1 dígito_verificador_mod11]
```
En PILAR se genera en la Edge Function `sri-firma-envio` antes de construir el XML. La tabla `facturas` almacena `clave_acceso` como campo único con índice.

### SOAP (SRI)
**Simple Object Access Protocol** — Protocolo de servicios web que el SRI de Ecuador usa para recibir documentos electrónicos y retornar autorizaciones. En PILAR, las llamadas SOAP se realizan exclusivamente desde Edge Functions Deno (nunca desde Flutter) a las URLs de recepción y autorización del SRI. La Edge Function construye el envelope XML, lo envía con `fetch` y parsea la respuesta para actualizar `cola_documentos_electronicos`.

### Cola de documentos electrónicos
Tabla `cola_documentos_electronicos` en el módulo Facturación que gestiona el ciclo de vida de envíos al SRI. Estados: `PENDIENTE → ENVIADO → AUTORIZADO | RECHAZADO | ERROR`. La Edge Function `poll-autorizacion` procesa la cola en background con reintentos exponenciales (máximo 24 horas). El secuencial del documento se asigna al confirmar localmente, no al autorizar el SRI, para garantizar numeración continua incluso offline.

### RIDE
**Representación Impresa del Documento Electrónico** — PDF que acompaña al XML autorizado por el SRI y sirve como comprobante para el receptor. En PILAR se genera con Syncfusion PDF en la Edge Function `generate-ride`, se almacena en Supabase Storage y se envía por email (Resend) y/o WhatsApp (Cloud API) según los canales configurados en el contacto.

---

## Nomenclaturas y Catálogos

### NANDINA
Nomenclatura Arancelaria Común de la Comunidad Andina — Clasificación de mercancías para comercio exterior basada en el Sistema Armonizado de Designación y Codificación de Mercancías. En PILAR se usa en el módulo Compras para clasificar productos importados y en la guía de remisión cuando aplica. Los códigos NANDINA son de 10 dígitos.

### CIIU
**Clasificación Industrial Internacional Uniforme** — Estándar de la ONU para clasificar actividades económicas. El SRI exige el código CIIU de la actividad económica del contribuyente en los documentos electrónicos. En PILAR se parametriza en la configuración de empresa y se incluye automáticamente en el XML de cada documento.
