# Anulación de Comprobantes Electrónicos — Normativa 2025

## Resoluciones vigentes

| Resolución | Fecha | Vigencia | Objeto |
|------------|-------|----------|--------|
| **NAC-DGERCGC25-00000014** | 27-jun-2025 | 01-ago-2025 | Normas para anulación de comprobantes electrónicos |
| **NAC-DGERCGC25-00000017** | 29-jul-2025 | 01-ago-2025 | Reforma la anterior: reduce plazo 10→7 días, agrega excepciones |

> La NAC-DGERCGC25-00000017 modifica varios artículos de la NAC-DGERCGC25-00000014.
> Las reglas a continuación ya incorporan las reformas (texto unificado).

---

## Reglas de anulación (texto unificado)

### Por tipo de documento

| Documento | Anulación en línea | Anulación por NC |
|-----------|-------------------|------------------|
| **Factura** | Sí, hasta día 7 del mes siguiente | Sí, después del día 7 (según Reglamento) |
| **Retención** | Sí, hasta día 7 del mes siguiente | **NO** — solo en línea |
| **Nota de Crédito** | Sí, hasta día 7 del mes siguiente | **NO** — solo en línea |
| **Nota de Débito** | Sí, hasta día 7 del mes siguiente | **NO** — solo en línea |
| **Guía de Remisión** | Sí, hasta día 7 del mes siguiente | **NO** — solo en línea |

### Plazo para anulación en línea (Art. 3)

- **Plazo**: hasta el **día 7** del mes siguiente al de emisión del comprobante
- Si el día 7 cae en feriado o descanso obligatorio: hasta el siguiente día hábil
- La anulación en línea se realiza a través del portal web del SRI o el Facturador SRI

### Restricciones absolutas

| Situación | Anulación en línea | Por NC |
|-----------|--------------------|--------|
| Factura a **Consumidor Final** (9999999999999) | **NUNCA** | **NUNCA** |
| Factura **comercialmente negociable** que fue negociada | **NO** | **NO** |
| Comprobante que **sustenta devolución de impuestos** | **NO** | **NO** |

### Proceso de aceptación del receptor (Art. 4)

Aplica a: **NC, ND, Retenciones** cuando se solicita anulación

1. El emisor solicita la anulación
2. El receptor recibe notificación
3. El receptor tiene **5 días hábiles** para aceptar o rechazar
4. **Sin respuesta** en el plazo → solicitud sin efecto, comprobante sigue válido
5. **Si rechaza** → sin efecto
6. **Si acepta** → se procede con la anulación en línea

**Excepción automática** (sin necesidad de aceptación):
- Receptor con identificación o pasaporte **del exterior**
- Receptor registrado como **fallecido** en el Registro Civil

### Emisión de Notas de Crédito (Art. 5)

- Las NC solo se emiten en los casos del **Reglamento de Comprobantes de Venta, Retención y Documentos Complementarios** (Art. 15)
- El SRI puede verificar el uso adecuado
- El plazo de 12 meses mencionado en la versión original fue **eliminado** por la reforma

---

## Disposiciones generales

**SEGUNDA**: Las facturas con carácter de "comerciales negociables" (Cód. de Comercio) que **en efecto** hayan sido negociadas, no son objeto de anulación ni de NC.

**TERCERA**: Los comprobantes que **sustentan devolución de impuestos** no pueden anularse ni recibir NC.

**CUARTA**: Anulación masiva (>1,000 comprobantes del mismo mes): puede solicitarse mediante trámite especial al SRI.

**QUINTA** (añadida por NAC-DGERCGC25-00000017): En procesos de control por fedatarios fiscales, el SRI podrá **anular de oficio** los comprobantes emitidos con leyenda "consumidor final".

---

## Disposición transitoria

Las reglas de plazo (Art. 3) y aceptación (Art. 4) aplican a comprobantes emitidos **desde el 01 de agosto de 2025**.

Para comprobantes emitidos **antes del 01-ago-2025** se aplica la normativa anterior:
- Plazo de anulación en línea era 10 días del mes siguiente (Resolución NAC-DGERCGC16-00000092 — ya derogada en su Art. 7)

---

## Implementación en PILAR

### Tablas afectadas

| Tabla | Cambio | Migración |
|-------|--------|-----------|
| `facturas` | `es_consumidor_final`, `negociable`, `sustenta_devolucion`, `motivo_anulacion`, `fecha_anulacion`, `tipo_anulacion` | 018 |
| `notas_credito` | Campos de anulación y `estado_aceptacion`, `fecha_limite_aceptacion` | 018 |
| `notas_debito` | Ídem NC | 018 |
| `cola_documentos_electronicos` | `tipo_operacion` (EMISION \| ANULACION) | 018 |
| `solicitudes_anulacion_receptor` | Nueva tabla — tracking del proceso de aceptación | 018 |

### RPCs nuevas/modificadas

| Función | Descripción |
|---------|-------------|
| `esta_en_plazo_anulacion_en_linea(fecha)` | TRUE si el comprobante está dentro del plazo de 7 días |
| `get_reglas_anulacion(doc_id, tabla)` | Retorna opciones disponibles para la UI |
| `anular_factura(id, motivo, version, tipo)` | Reemplaza la del Core con reglas SRI 2025 |

### Flujo de anulación en línea (via portal SRI)

La anulación "en línea" requiere acción humana en el portal del SRI. PILAR soporta este flujo así:

1. Usuario llama `get_reglas_anulacion()` → UI muestra si puede anular en línea
2. Usuario confirma → `anular_factura(id, motivo, version, 'EN_LINEA')` registra el intent
   - Las validaciones (consumidor_final, plazo, etc.) se ejecutan
   - `facturas.tipo_anulacion = 'EN_LINEA'` se almacena
   - El estado NO cambia todavía (sigue CONFIRMADA/AUTORIZADA)
3. PILAR muestra al usuario la `clave_acceso` e instrucciones para ir al portal SRI
4. El usuario va al portal SRI (https://srienlinea.sri.gob.ec) y anula el documento
5. `poll-autorizacion` (pg_cron cada 5 min) detecta estado `ANULADO` desde el SRI
6. `marcar_factura_anulada_por_sri(clave_acceso)` actualiza automáticamente el estado a ANULADA

**No se requiere Edge Function adicional.** El `poll-autorizacion` existente cubre la detección.

### Flujo de anulación por NC (automático)

Para facturas fuera del plazo de 7 días (o cuando el usuario prefiere NC):
1. Usuario emite una NC (tipo 04) referenciando la factura original
2. La NC va por el pipeline SOAP normal: sri-firma-envio → autorización → RIDE
3. Cuando la NC es AUTORIZADA, se marca la factura original como ANULADA

### ¿Por qué no existe `anular-documento` Edge Function?

El SRI Ecuador (esquema offline) solo expone dos endpoints SOAP:
- `RecepcionComprobantesOffline` — para enviar documentos
- `AutorizacionComprobantesOffline` — para consultar estado de autorización

**No existe endpoint SOAP para enviar solicitudes de anulación.** La resolución NAC-DGERCGC25-00000014 Art. 2 establece explícitamente que la anulación "en línea" es a través del portal web del SRI o el Facturador SRI — ambas interfaces para humanos, no APIs machine-to-machine.

---

## Campos clave en la UI

### Pantalla de factura — sección "Anulación"

La UI debe llamar `get_reglas_anulacion()` antes de mostrar opciones:

```
get_reglas_anulacion(factura_id, 'facturas')
→ {
    puede_anular_en_linea:  true/false,
    puede_anular_por_nc:    true/false,
    en_plazo_en_linea:      true/false,
    fecha_limite_en_linea:  "YYYY-MM-DD",
    motivo_bloqueo:         "texto explicativo" (si ninguna opción disponible)
  }
```

### Flag `es_consumidor_final`

Establecer al crear/confirmar la factura, basándose en:
- `contactos.tipo_identificacion = '07'` (Consumidor Final, Tabla 6 SRI), OR
- `contactos.identificacion = '9999999999999'`

Una vez la factura tiene `es_consumidor_final = TRUE`, la UI debe mostrar solo lectura
en el campo de anulación con el mensaje normativo correspondiente.
