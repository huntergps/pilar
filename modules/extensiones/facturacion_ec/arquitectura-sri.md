# Arquitectura SRI — Facturación Electrónica Ecuador

> Este documento contiene las secciones de arquitectura específicas del SRI Ecuador, extraídas de `foundation/arquitectura.md` para mantener la capa base country-agnostic (ADR-006).
>
> **Módulo**: `modules/extensiones/facturacion_ec/`
> **Referencia canónica**: Ver también [`module.md`](./module.md) para la especificación completa del módulo.

---

## Librerías Backend — Edge Functions Deno/TypeScript (SRI Ecuador)

La lógica SRI se ejecuta **siempre en el servidor** (Edge Functions de Supabase). El frontend Flutter NO maneja firma, SOAP ni certificados digitales. Solo envía datos/tokens al servidor y recibe resultados.

| Librería | Función | Uso |
|----------|---------|-----|
| **ec-sri-invoice-signer** | Firma XAdES-BES en TS puro | Firma de todos los documentos electrónicos |
| **open-factura** | Generación XML + envío SRI | Base para construcción XML y SOAP |
| **fast-xml-parser** | Parseo XML rápido | Respuestas SRI + ATS |
| **xmlbuilder2** | Construcción XML programática | Generación XMLs SRI (facturas, NC, ND, retenciones, guías, liquidaciones) |

### Principio de seguridad

El certificado `.p12` **nunca reside en el dispositivo** del usuario ni en el cliente Flutter. Solo es accesible desde Edge Functions via `service_role` key. Ver sección de Storage más abajo.

---

## Supabase Storage — Buckets SRI Ecuador

Los siguientes buckets son específicos del módulo `facturacion_ec` y almacenan artefactos del ciclo de facturación electrónica:

| Bucket | Contenido | Acceso |
|--------|-----------|--------|
| `xml-firmados` | XMLs firmados con XAdES-BES antes de enviar al SRI | Server-side (Edge Functions únicamente) |
| `xml-autorizados` | XMLs autorizados por el SRI con clave de acceso | Lectura por empresa (RLS por `empresa_id`) |
| `rides` | PDFs RIDE generados (Representación Impresa del Documento Electrónico) | Lectura por empresa (RLS por `empresa_id`) |
| `certificados` | Certificados `.p12` del emisor, encriptados | **Solo Edge Functions** via `service_role` — NUNCA al cliente |
| `assets` | Logos, plantillas, recursos de la empresa | Lectura por empresa (RLS por `empresa_id`) — bucket genérico, no exclusivo de facturacion_ec |

**Políticas de acceso:** Cada bucket tiene policies que filtran por `empresa_id` del JWT. Los certificados `.p12` solo son accesibles desde Edge Functions via `service_role` key.

---

## Ambientes SRI

| Ambiente | Propósito | Entorno SRI |
|----------|-----------|-------------|
| **Local** | Desarrollo local (Supabase local) | N/A — no conecta al SRI real |
| **Staging** | QA y pruebas de integración | Ambiente Pruebas SRI (WS de pruebas) |
| **Producción** | Producción real | Ambiente Producción SRI (WS de producción) |

> **NUNCA mezclar** ambiente de pruebas con producción. El campo `ambiente` en `documentos_electronicos` controla esto: `1=Pruebas`, `2=Produccion`.

---

## Stack Principal — Entradas Ecuador-Specific

Las siguientes entradas del stack principal de PILAR son específicas del módulo `facturacion_ec`:

| Capa | Tecnología | Uso Ecuador-specific |
|------|-----------|---------------------|
| **Firma XML (server)** | `ec-sri-invoice-signer` | Firma XAdES-BES requerida por el SRI |
| **XML (server)** | `fast-xml-parser` + `xmlbuilder2` | Generación/parseo de comprobantes electrónicos SRI |
| **Pagos** | Kushki (`flutter_kushki`) | Pasarela primaria Ecuador — ver también `modules/extensiones/pagos-online/` |

---

## Referencias

- [`module.md`](./module.md) — Especificación completa del módulo facturacion_ec (tablas, RPCs, flujos)
- [`foundation/apis/rpcs-por-modulo.md`](../../../foundation/apis/rpcs-por-modulo.md) — RPCs marcadas con 🇪🇨 para este módulo
- [`foundation/regulatorio/`](../../../foundation/regulatorio/) — Normas SRI, XSD, documentos electrónicos
- [`foundation/adrs/ADR-006`](../../../foundation/adrs/) — Decisión de mantener foundation country-agnostic
