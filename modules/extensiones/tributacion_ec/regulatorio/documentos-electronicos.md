# Documentos Electrónicos SRI - Análisis Detallado


### Factura Electronica (V2.1.0 - Version Mas Completa)

```
factura (id="comprobante", version="2.1.0")
  |-- infoTributaria
  |     |-- ambiente [1=Pruebas, 2=Produccion]
  |     |-- tipoEmision [1=Normal, 2=Contingencia]
  |     |-- razonSocial (1-300 chars)
  |     |-- nombreComercial (opcional, 1-300)
  |     |-- ruc [13 digitos: 10+001]
  |     |-- claveAcceso [49 digitos]
  |     |-- codDoc [01]
  |     |-- estab [3 digitos]
  |     |-- ptoEmi [3 digitos]
  |     |-- secuencial [9 digitos]
  |     |-- dirMatriz (1-300)
  |     |-- agenteRetencion (opcional)
  |     |-- contribuyenteRimpe (opcional)
  |
  |-- infoFactura
  |     |-- fechaEmision [dd/mm/aaaa]
  |     |-- tipoIdentificacionComprador [04-08]
  |     |-- razonSocialComprador
  |     |-- identificacionComprador
  |     |-- totalSinImpuestos
  |     |-- totalDescuento
  |     |-- totalConImpuestos (1..N totalImpuesto)
  |     |     |-- codigo [2=IVA, 3=ICE, 5=IRBPNR]
  |     |     |-- codigoPorcentaje
  |     |     |-- baseImponible
  |     |     |-- tarifa
  |     |     |-- valor
  |     |-- importeTotal
  |     |-- moneda (opcional)
  |     |-- pagos (1..N pago)
  |           |-- formaPago [01-21]
  |           |-- total
  |           |-- plazo (opcional)
  |           |-- unidadTiempo (opcional)
  |
  |-- detalles (1..N detalle)
  |     |-- codigoPrincipal (opcional, 1-25)
  |     |-- descripcion (1-300)
  |     |-- cantidad (decimal 18,6)
  |     |-- precioUnitario (decimal 18,6)
  |     |-- descuento (decimal 14,2)
  |     |-- precioTotalSinImpuesto
  |     |-- detallesAdicionales (opcional, max 3)
  |     |-- impuestos (1..N impuesto)
  |
  |-- reembolsos (opcional)
  |-- retenciones (opcional, V2.1.0)
  |-- infoSustitutivaGuiaRemision (opcional, V2.0.0+)
  |-- otrosRubrosTerceros (opcional, V2.0.0+)
  |-- tipoNegociable (opcional)
  |-- maquinaFiscal (opcional)
  |-- infoAdicional (opcional, max 15 campos)
  |-- ds:Signature (firma electronica XAdES-BES)
```

**Evolucion de Versiones de Factura:**

| Funcionalidad | V1.0.0 | V1.1.0 | V2.0.0 | V2.1.0 |
|---------------|--------|--------|--------|--------|
| Estructura base | SI | SI | SI | SI |
| Precision 6 decimales (cantidad/precio) | NO | **SI** | NO | **SI** |
| Retenciones en factura | NO | **SI** | NO | **SI** |
| Info sustitutiva guia remision | NO | NO | **SI** | **SI** |
| Otros rubros terceros | NO | NO | **SI** | **SI** |
| Reembolsos | SI | SI | SI | SI |

### Comprobante de Retencion (V2.0.0 - Reestructurado)

La V2.0.0 introduce un cambio arquitectonico fundamental: las retenciones se organizan **por documento sustento**, no en lista plana.

```
comprobanteRetencion
  |-- infoTributaria
  |-- infoCompRetencion
  |     |-- tipoIdentificacionSujetoRetenido
  |     |-- tipoSujetoRetenido (01|02, NUEVO)
  |     |-- parteRel (SI|NO, NUEVO obligatorio)
  |     |-- periodoFiscal (mm/aaaa)
  |
  |-- docsSustento (REEMPLAZA "impuestos" de V1)
        |-- docSustento (1..N)
              |-- codSustento
              |-- codDocSustento
              |-- numDocSustento
              |-- fechaEmisionDocSustento
              |-- pagoLocExt (01=Local, 02=Exterior)
              |-- totalSinImpuestos
              |-- importeTotal
              |-- impuestosDocSustento
              |     |-- impuestoDocSustento (1..N)
              |           |-- codImpuestoDocSustento [2,3,5]
              |           |-- codigoPorcentaje
              |           |-- baseImponible
              |           |-- tarifa
              |           |-- valorImpuesto
              |-- retenciones
              |     |-- retencion (1..N)
              |           |-- codigo [1=Renta, 2=IVA, 6=ISD]
              |           |-- codigoRetencion
              |           |-- baseImponible
              |           |-- porcentajeRetener
              |           |-- valorRetenido
              |           |-- dividendos (opcional)
              |           |-- compraCajBanano (opcional)
              |-- pagos
                    |-- pago (1..N)
```

### Nota de Credito (V1.1.0)

```
notaCredito
  |-- infoTributaria
  |-- infoNotaCredito
  |     |-- codDocModificado [referencia tipo doc original]
  |     |-- numDocModificado [000-000-000000000]
  |     |-- fechaEmisionDocSustento
  |     |-- totalSinImpuestos
  |     |-- totalConImpuestos (con valorDevolucionIva)
  |     |-- valorModificacion
  |     |-- motivo (1-300)
  |-- detalles (1..N detalle, precision 18,6)
```

### Nota de Debito (V1.0.0)

```
notaDebito
  |-- infoTributaria
  |-- infoNotaDebito
  |     |-- codDocModificado
  |     |-- numDocModificado
  |     |-- valorTotal
  |     |-- pagos (formaPago + total + plazo)
  |-- motivos (1..N motivo: razon + valor)
```

### Guia de Remision (V1.1.0)

```
guiaRemision
  |-- infoTributaria
  |-- infoGuiaRemision
  |     |-- dirPartida
  |     |-- razonSocialTransportista
  |     |-- rucTransportista
  |     |-- placa
  |     |-- fechaIniTransporte / fechaFinTransporte
  |-- destinatarios (1..N destinatario)
        |-- identificacionDestinatario
        |-- dirDestinatario
        |-- motivoTraslado
        |-- codDocSustento / numDocSustento (opcional)
        |-- detalles (1..N: codigo, descripcion, cantidad 18,6)
```

### Liquidacion de Compra (V1.1.0)

```
liquidacionCompra
  |-- infoTributaria
  |-- infoLiquidacionCompra
  |     |-- tipoIdentificacionProveedor
  |     |-- razonSocialProveedor
  |     |-- totalSinImpuestos
  |     |-- totalConImpuestos [SOLO codigo 2 = IVA]
  |     |-- importeTotal
  |     |-- pagos
  |-- detalles (con unidadMedida, precioSinSubsidio, precision 18,6)
  |-- reembolsos (opcional)
```

### Relaciones entre Documentos

```
FACTURA (01) ←──── NOTA DE CREDITO (04) [modifica]
     |
     ├←──── NOTA DE DEBITO (05) [modifica]
     |
     ├←──── COMPROBANTE DE RETENCION (07) [sustenta]
     |
     └←──── GUIA DE REMISION (06) [sustenta transporte]

LIQUIDACION DE COMPRA (03) ←──── COMPROBANTE DE RETENCION (07)
                           ←──── GUIA DE REMISION (06)

TODOS ──────→ ATS (consolidacion mensual)
TODOS ──────→ ANULADOS (si se anulan)
```

### Clave de Acceso (49 digitos)

La clave de acceso es el identificador unico de cada documento electronico:

```
Posiciones:
[1-8]   Fecha emision (ddmmaaaa)
[9-10]  Tipo comprobante (01, 04, 05, 06, 07)
[11-23] RUC del emisor
[24-25] Ambiente (01=Pruebas, 02=Produccion)
[26-28] Serie (establecimiento)
[29-31] Serie (punto emision)
[32-40] Secuencial
[41-48] Codigo numerico aleatorio (8 digitos)
[49]    Digito verificador (modulo 11)
```

### Proceso de Emision Electronica (Esquema Offline)

```
1. GENERACION XML
   |-- Construir XML segun XSD de la version correspondiente
   |
2. FIRMA ELECTRONICA
   |-- Firmar con certificado digital (.p12)
   |-- Algoritmo: XAdES-BES (XML Advanced Electronic Signatures)
   |-- Se inserta bloque <ds:Signature> en el XML
   |
3. ENVIO AL SRI (Web Service SOAP)
   |-- URL Pruebas: https://celcer.sri.gob.ec/comprobantes-electronicos-ws/RecepcionComprobantesOffline
   |-- URL Produccion: https://cel.sri.gob.ec/comprobantes-electronicos-ws/RecepcionComprobantesOffline
   |-- Metodo: validarComprobante(xml)
   |-- Respuesta: RECIBIDA o DEVUELTA (con errores)
   |
4. AUTORIZACION (consulta posterior)
   |-- URL Pruebas: https://celcer.sri.gob.ec/comprobantes-electronicos-ws/AutorizacionComprobantesOffline
   |-- URL Produccion: https://cel.sri.gob.ec/comprobantes-electronicos-ws/AutorizacionComprobantesOffline
   |-- Metodo: autorizacionComprobante(claveAcceso)
   |-- Respuesta: AUTORIZADO, NO AUTORIZADO, o EN PROCESO
   |
5. GENERACION RIDE
   |-- Generar representacion impresa (PDF)
   |-- Incluye: datos del comprobante + codigo de barras de clave de acceso
   |
6. ENVIO AL CLIENTE
   |-- Email con XML autorizado + RIDE (PDF)
```

---

