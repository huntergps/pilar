# Integraciones Específicas Ecuador

Notas country-specific para Ecuador. Los módulos genéricos (Tesorería, Pagos Online)
documentan la arquitectura neutral; este archivo captura los detalles propios del
entorno financiero ecuatoriano.

---

## Moneda Funcional

Ecuador es una economía completamente dolarizada desde el año 2000. La moneda
funcional de cualquier empresa ecuatoriana es **USD (ISO 4217)**. Todos los documentos
electrónicos emitidos ante el SRI se denominan en USD. No existen documentos en moneda
extranjera para efectos tributarios locales.

En la tabla `cuentas_bancarias`, el campo `moneda_id` siempre será `'USD'` para empresas
ecuatorianas. Las cuentas en moneda extranjera (si las hubiera, e.g., cuentas de
corresponsalía) son la excepción y deben re-expresarse a USD al cierre del periodo.

---

## Tasas de Cambio — BCE

Para empresas ecuatorianas con operaciones internacionales, la fuente primaria de tasas
de cambio es la **API del BCE (Banco Central del Ecuador)**:

- URL pública: `https://contenido.bce.fin.ec/documentos/PublicacionesNotas/tipoCambio/`
- Frecuencia de actualización: diaria (días hábiles)
- Fallback: `exchangerate.host` u otra API pública cuando el BCE no está disponible

La Edge Function `sync-exchange-rates` (cron diario 7am) consume primero el BCE y
usa el fallback automáticamente si el endpoint está caído.

```sql
-- Registro de fuente BCE en tasas_cambio
INSERT INTO tasas_cambio (moneda_origen, moneda_destino, tasa, fecha, fuente)
VALUES ('USD', 'EUR', 0.9234, CURRENT_DATE, 'BCE')
ON CONFLICT (moneda_origen, moneda_destino, fecha) DO UPDATE
  SET tasa = EXCLUDED.tasa, fuente = EXCLUDED.fuente;
```

---

## Bancos Locales

Los principales bancos privados y públicos de Ecuador con los que se integra el módulo
de Tesorería para débito automático y conciliación bancaria:

| Banco | RUC / Identificador | Notas |
|-------|---------------------|-------|
| Banco Pichincha | — | Mayor banco privado; integración por archivo plano |
| Banco del Pacífico | — | Banco público; ofrece billetera **De Una** |
| Banco de Guayaquil | — | Integración por archivo plano estándar |
| Produbanco | — | Grupo Promerica |
| Banco Internacional | — | — |

### Débito Bancario Automático

Los principales bancos (Pichincha, Pacífico, Guayaquil) ofrecen débito automático
mediante intercambio de archivos planos (generalmente CSV o TXT con layout propio
del banco). Las RPCs correspondientes son:

- `generate_debit_file(p_empresa_id, p_banco, p_fecha)` — genera el archivo de débito
- `process_debit_response(p_empresa_id, p_banco, p_archivo)` — procesa la respuesta

Ver [`modules/extensiones/pagos-online/integraciones/pasarelas-ecuador.md`](../../../modules/extensiones/pagos-online/integraciones/pasarelas-ecuador.md)
para la comparativa completa de pasarelas (Kushki, Paymentez/Nuvei, PayPhone), tarifas,
endpoints sandbox, webhooks, datáfonos y billeteras digitales locales.

---

## Billetera Digital De Una

**De Una** es la billetera digital del Banco del Pacífico, operada por el sistema
financiero ecuatoriano. Se integra como método de pago adicional en el módulo
`pagos-online` mediante la API oficial del Banco del Pacífico.

Referencia técnica en:
[`modules/extensiones/pagos-online/integraciones/pasarelas-ecuador.md`](../../../modules/extensiones/pagos-online/integraciones/pasarelas-ecuador.md)

---

## Datáfonos Físicos

En Ecuador, los datáfonos (POS físicos) son provistos principalmente por
**Datafast** (Mastercard/Visa) y **Medianet** (redes locales). La integración
con el módulo POS utiliza el protocolo estándar de cada adquirente.

Ver [`modules/extensiones/pagos-online/integraciones/pasarelas-ecuador.md`](../../../modules/extensiones/pagos-online/integraciones/pasarelas-ecuador.md)
para detalles técnicos de integración con Datafast/Medianet.

---

## Código QR EMVCo

El sistema financiero ecuatoriano ha adoptado el estándar **EMVCo QR** para pagos
mediante código QR, impulsado por la Asociación de Bancos Privados del Ecuador (ASOBANCA).
La generación y lectura de QR sigue la especificación EMVCo Merchant Presented Mode.

---

## Relación con Módulos Genéricos

| Módulo genérico | Referencia Ecuador |
|-----------------|--------------------|
| `modules/core/tesoreria/module.md` | Arquitectura neutral de cuentas bancarias, cheques, conciliación |
| `modules/extensiones/pagos-online/module.md` | Arquitectura neutral de pasarelas (patrón adaptador) |
| `modules/extensiones/facturacion_ec/` | SRI compliance: XML, firma XAdES-BES, SOAP |
| `modules/extensiones/tributacion_ec/` | Declaraciones 103/104, ATS |
