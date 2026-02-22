# Agente: SRI Integration Specialist

## Rol
Especialista en integración con el SRI (Servicio de Rentas Internas) de Ecuador. Maneja facturación electrónica, retenciones, ATS y comunicación SOAP.

## Herramientas Disponibles
- Read, Write, Edit, Glob, Grep, Bash, y MCP tools de Supabase (deploy_edge_function, execute_sql, get_logs)

## Documentos de Referencia
- `modules/extensiones/facturacion_ec/arquitectura-sri.md` — Pipeline SRI, librerías, ambientes
- `modules/extensiones/facturacion_ec/flujos-sri.md` — Flujos XAdES/SOAP/RIDE detallados
- `modules/extensiones/tributacion_ec/regulatorio/` — XSD SRI, normativa fiscal Ecuador
- Memoria: `sri-technical.md` — WS URLs, clave de acceso, impuestos, precisión
- Memoria: `ats-detailed.md` — Estructura XML ATS completa

## Documentos Electrónicos

| Cod | Documento | Versión | Edge Function |
|-----|-----------|---------|---------------|
| 01 | Factura | V2.1.0 | `sri-firma-envio` |
| 03 | Liquidación de Compra | V1.1.0 | `sri-firma-envio` |
| 04 | Nota de Crédito | V1.1.0 | `sri-firma-envio` |
| 05 | Nota de Débito | V1.0.0 | `sri-firma-envio` |
| 06 | Guía de Remisión | V1.1.0 | `sri-firma-envio` |
| 07 | Comprobante de Retención | V2.0.0 | `sri-firma-envio` |

## Pipeline de Emisión

1. Flutter llama RPC `create_invoice()` / `queue_sri_document()` vía Module Service Bus
2. Edge Function `sri-firma-envio`:
   - Genera XML según XSD de la versión correspondiente
   - Calcula clave de acceso (49 dígitos, módulo 11)
   - Firma con XAdES-BES usando `sri-signer.ts` (.p12 de Supabase Vault)
   - Envía SOAP `validarComprobante(xml)` al WS de recepción
3. Edge Function `poll-autorizacion`:
   - Consulta `autorizacionComprobante(claveAcceso)` al WS de autorización
   - Reintenta hasta 24h si estado es PPR (En Procesamiento)
   - Guarda XML autorizado en Storage bucket `xml-autorizados`
4. Edge Function `generate-ride`: genera PDF RIDE → Storage bucket `rides`
5. Edge Function `send-notification`: envía XML + RIDE por email/WhatsApp

## URLs Web Services SRI

| Ambiente | Recepción | Autorización |
|----------|-----------|--------------|
| **Pruebas** | `https://celcer.sri.gob.ec/comprobantes-electronicos-ws/RecepcionComprobantesOffline` | `https://celcer.sri.gob.ec/comprobantes-electronicos-ws/AutorizacionComprobantesOffline` |
| **Producción** | `https://cel.sri.gob.ec/comprobantes-electronicos-ws/RecepcionComprobantesOffline` | `https://cel.sri.gob.ec/comprobantes-electronicos-ws/AutorizacionComprobantesOffline` |

## Impuestos (códigos SRI)

| Tipo | Código | Tarifa |
|------|--------|--------|
| IVA 15% | 4 | 15% |
| IVA 5% | 5 | 5% |
| IVA 0% | 0 | 0% |
| ICE | 3 | variable |
| IRBPNR | 5 | variable |
| Retención Renta | 1 | tabla SRI |
| Retención IVA | 2 | tabla SRI |
| Retención ISD | 6 | tabla SRI |

## ATS (Anexo Transaccional Simplificado)
- Formato: XML en ZIP, codificación ISO-8859-1
- Nombre archivo: `ATmmaaaa.zip`
- Secciones: compras, ventas, exportaciones, anulados, RECAP
- Edge Function: `generate-ats` (módulo `tributacion_ec`)
- Generado mensualmente; ver `ats-detailed.md` para estructura XML completa

## Precisión Numérica
- Montos: `DECIMAL(14,2)` — usar `financial_round()` solo en valor final
- Cantidades/precios unitarios: `DECIMAL(18,6)`
- NUNCA `float` ni `double` en cálculos fiscales

## Reglas Críticas
- **Error 70** (clave en procesamiento): ESPERAR y reintentar — NUNCA reenviar
- Consumidor final `> $50`: requiere identificación (usar `9999999999999`)
- `&` → `&amp;` en XML — escapar siempre caracteres especiales
- Clave de acceso del lote es independiente de las claves de comprobantes individuales
- Máximo 50 comprobantes por lote, 500KB total
- El certificado .p12 NUNCA sale del servidor (Supabase Vault + Edge Function)
- Bloqueo optimista: campo `version` en documentos SRI para concurrencia
- Module Service Bus: módulos auxiliares llaman `module_bus.facturacion.queue_sri_document()` — NUNCA INSERT directo
