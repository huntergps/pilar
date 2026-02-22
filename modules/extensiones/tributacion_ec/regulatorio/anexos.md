# Anexos


### A. Validaciones Criticas del XSD (patrones regex)

| Campo | Pattern | Ejemplo |
|-------|---------|---------|
| RUC | `[0-9]{10}001` | `1790016919001` |
| Clave Acceso | `[0-9]{49}` | `1402202601179001691900110010020000001231234567` + verificador |
| Fecha | `(0[1-9]\|[12][0-9]\|3[01])/(0[1-9]\|1[012])/20[0-9][0-9]` | `14/02/2026` |
| Establecimiento | `[0-9]{3}` | `001` |
| Punto Emision | `[0-9]{3}` | `002` |
| Secuencial | `[0-9]{9}` | `000000123` |
| Tipo ID | `[0][4-8]` | `04` (RUC) |
| Codigo Impuesto | `[235]` | `2` (IVA) |
| Forma Pago | `[0][1-9]\|[1][0-9]\|[2][0-1]` | `01` |
| Num Doc Sustento | `[0-9]{15}` | `001002000000123` |
| Num Doc Modificado | `[0-9]{3}-[0-9]{3}-[0-9]{9}` | `001-002-000000123` |

### B. Restricciones Numericas

| Tipo | totalDigits | fractionDigits | Min |
|------|-------------|----------------|-----|
| Montos generales | 14 | 2 | 0 |
| Cantidad/Precio (V2.1.0) | 18 | 6 | 0 |
| Tarifa impuesto | 4 | 2 | 0 |
| Porcentaje retencion | 5 | 2 | 0 |

### C. URLs Web Services SRI

| Servicio | Ambiente | URL |
|----------|----------|-----|
| Recepcion | Pruebas | `https://celcer.sri.gob.ec/comprobantes-electronicos-ws/RecepcionComprobantesOffline` |
| Recepcion | Produccion | `https://cel.sri.gob.ec/comprobantes-electronicos-ws/RecepcionComprobantesOffline` |
| Autorizacion | Pruebas | `https://celcer.sri.gob.ec/comprobantes-electronicos-ws/AutorizacionComprobantesOffline` |
| Autorizacion | Produccion | `https://cel.sri.gob.ec/comprobantes-electronicos-ws/AutorizacionComprobantesOffline` |

### D. Codigos de Error SRI - Recepcion

| Codigo | Descripcion | Motivo |
|--------|-------------|--------|
| 26 | Tamano maximo superado | Archivo excede limite (320KB individual, 500KB lote) |
| 28 | Acuerdo de medios no aceptado | Falta acuerdo de medios electronicos |
| 35 | Documento invalido | XML no pasa validacion de esquema XSD |
| 36 | Version esquema descontinuada | Version XSD incorrecta o descontinuada |
| 43 | Clave acceso registrada | Ya existe en la base de datos del SRI |
| 45 | Secuencial registrado | Secuencial duplicado para el mismo emisor |
| 47 | Tipo de comprobante no existe | Codigo de documento no valido |
| 48 | Esquema XSD no existe | No existe esquema para el tipo de documento |
| 49 | Argumentos nulos al WS | Parametros vacios enviados al servicio |
| 50 | Error interno general | Error del servidor SRI |
| 65 | Fecha de emision extemporanea | Fuera de tiempo permitido |
| 67 | Fecha invalida | Formato de fecha incorrecto |
| 70 | Clave de acceso en procesamiento | Comprobante previo no ha terminado de procesar |
| 82 | Error fecha inicio transporte | Fecha menor a la guia de remision |
| 92 | Error devolucion IVA | Valor no corresponde al servicio DIG |

### E. Codigos de Error SRI - Autorizacion

| Codigo | Descripcion | Motivo |
|--------|-------------|--------|
| 2 | RUC del emisor NO ACTIVO | RUC no esta activo en el registro |
| 10 | Establecimiento clausurado | Establecimiento cerrado por SRI |
| 27 | Clase no permitida | No puede emitir electronicamente |
| 37 | RUC sin autorizacion de emision | No tiene solicitud de certificacion |
| 39 | Firma invalida | Firma electronica no es valida |
| 40 | Error en el certificado | No se encontro o no se puede convertir X509 |
| 46 | RUC no existe | RUC del emisor no existe en el registro |
| 52 | Error en diferencias | Error en calculos aritmeticos del comprobante |
| 56 | Establecimiento cerrado | Desde el cual se genera el comprobante |
| 57 | Autorizacion suspendida | Suspendida por procesos de control |
| 58 | Error estructura clave acceso | Componentes diferentes a los del comprobante |
| 63 | RUC clausurado | RUC clausurado por procesos de control |
| 80 | Error estructura clave acceso | Supera 49 digitos o tiene caracteres alfanumericos |

**Advertencias (no bloquean autorizacion):**

| Codigo | Descripcion |
|--------|-------------|
| 59 | Identificacion del adquirente no existe |
| 60 | Ambiente ejecucion diferente (pruebas/produccion) |
| 62 | Identificacion incorrecta del adquirente |
| 68 | Documento sustento no existe como electronico |

### F. Orden de Validaciones en el SRI

El SRI procesa los comprobantes en este orden:

1. **Validacion XML:** Tamano archivo, esquema activo, XML bien formado
2. **Validacion contribuyente emisor:** RUC activo, establecimiento activo
3. **Validacion unicidad:** Autorizacion activa, tipo comprobante, clave acceso unica, secuencial unico
4. **Validacion Firma:** Validez firma y cadena de confianza OCSP
5. **Verificaciones adicionales:** Fecha emision, identificacion receptor, documentos sustento
6. **Validacion diferencias:** Calculos aritmeticos

### G. Envio por Lote

Es posible enviar multiples comprobantes en un solo lote:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<lote version="1.0.0">
  <claveAcceso>[49 digitos del lote]</claveAcceso>
  <ruc>[RUC emisor]</ruc>
  <comprobantes>
    <comprobante><![CDATA[XML_FIRMADO_1]]></comprobante>
    <comprobante><![CDATA[XML_FIRMADO_2]]></comprobante>
  </comprobantes>
</lote>
```

**Limites del lote:**
- Maximo comprobantes por lote: **50**
- Tamano maximo por lote: **500 KB**
- Tamano maximo individual: **320 KB**
- La clave de acceso del lote es independiente de las claves de los comprobantes

### H. WS de Consulta de Validez

Ademas de los WS de Recepcion y Autorizacion, existen servicios de consulta:

| Servicio | Pruebas | Produccion |
|----------|---------|------------|
| Consulta Comprobante | `celcer.sri.gob.ec/.../ConsultaComprobante?wsdl` | `cel.sri.gob.ec/.../ConsultaComprobante?wsdl` |
| Consulta Factura | `celcer.sri.gob.ec/.../ConsultaFactura?wsdl` | `cel.sri.gob.ec/.../ConsultaFactura?wsdl` |

**Metodo:** `consultarEstadoAutorizacionComprobante(claveAcceso)`

**Valores posibles de `estadoAutorizacion`:**
- `AUTORIZADO` - Comprobante validado y autorizado
- `NO AUTORIZADO` - Comprobante rechazado
- `PENDIENTE DE ANULAR` - En proceso de anulacion
- `ANULADO` - Comprobante anulado

### I. Servicio DIG (Devolucion Automatica IVA)

Servicio REST con autenticacion OAuth2 para devolucion automatica del IVA a personas adultas mayores:

- **Autenticacion:** Token con vigencia de 35 minutos, obtenido via SHA-512
- **Pruebas:** `celcer.sri.gob.ec/sri-seguridad-sso-api-servicio-internet/rest/...`
- **Produccion:** `srienlinea.sri.gob.ec/sri-seguridad-sso-api-servicio-internet/rest/...`
- Se incluye como cabecera `Authorization` en las llamadas REST

### J. Consideraciones Tecnicas de Implementacion

1. **Consumo asincrono de WS:** El SRI puede tardar hasta **24 horas** en procesar un comprobante (estado PPR). Implementar cola con reintentos.
2. **Error 70 (clave en procesamiento):** NO reenviar ni generar nueva clave. Esperar hasta 24 horas.
3. **Reenvio de rechazados:** Se puede reutilizar la misma clave de acceso y secuencial para corregir y reenviar.
4. **Consumidor final >$50:** Si la factura supera $50 USD, es obligatorio especificar datos del adquirente. Para consumidor final: `9999999999999`.
5. **Caracteres especiales:** El signo `&` debe codificarse como `&amp;` en el XML. Sin espacios extra entre caracteres.
6. **RIDE (Representacion Impresa):** Tiene validez tributaria y juridica. Se recomienda codigo de barras GS1-128 con la clave de acceso.
7. **Inmutabilidad de asientos contables:** Los asientos contabilizados son inmutables. Para correcciones, usar asientos de reverso.

---

