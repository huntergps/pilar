# Módulo: Facturación Ecuador (SRI)

**ID**: `facturacion_ec`
**Tipo**: Auxiliar (Extension)
**Icono**: `verified`
**Depende de**: `facturacion` (Core, requerido)
**Opcional**: `compras` (liquidaciones, retenciones proveedor), `inventario` (guías de remisión)

---

## Descripción

Extensión del módulo Core `facturacion` con cumplimiento legal SRI Ecuador.

Transforma el módulo de facturación genérico en un sistema de comprobantes electrónicos conforme a la **Ficha Técnica de Comprobantes Electrónicos SRI v2.32**.

Documentos electrónicos soportados:
| Cod | Documento | Versión XSD |
|-----|-----------|-------------|
| 01  | Factura | V2.1.0 |
| 03  | Liquidación de Compra | V1.1.0 |
| 04  | Nota de Crédito | V1.1.0 |
| 05  | Nota de Débito | V1.0.0 |
| 06  | Guía de Remisión | V1.1.0 |
| 07  | Comprobante de Retención | V2.0.0 |

---

## Tablas Propias

### establecimientos
Sucursales y puntos físicos de la empresa, registrados en el SRI.
```
id, empresa_id, codigo (3 dígitos), nombre, tipo (MATRIZ/SUCURSAL/BODEGA/PUNTO_VENTA),
es_matriz, provincia_id, ciudad_id, direccion, telefono, email, zona_horaria, activo
```

### puntos_emision
Terminales o canales que emiten documentos electrónicos.
```
id, empresa_id, establecimiento_id, codigo (3 dígitos), descripcion,
tipo (NORMAL/POS/ECOMMERCE/MOVIL), activo
```

### secuenciales
Contadores atómicos de numeración SRI por empresa/establecimiento/punto/tipo.
```
id, empresa_id, establecimiento_id, punto_emision_id, tipo_documento (01–07), ultimo_numero, activo
```
Numeración: `estab.codigo || '-' || pe.codigo || '-' || LPAD(ultimo_numero, 9, '0')`

### cola_documentos_electronicos
Cola de procesamiento asíncrono para el pipeline SRI.
```
id, empresa_id, tipo_documento, documento_id, tabla_origen, numero, estado
(PENDIENTE→FIRMADO→ENVIADO→AUTORIZADO|RECHAZADO|ERROR), intentos, error_msg,
clave_acceso, numero_autorizacion, xml_sin_firma, xml_firmado, xml_autorizado,
fecha_autorizacion, processing_at, created_at, updated_at
```

### documento_ec_impuestos (007_extend_facturas.sql)
Tabla polimórfica de totales de impuestos por documento. Espeja el elemento `<totalConImpuestos>/<totalImpuesto>` del XML SRI.
```
id, empresa_id,
tabla_origen      VARCHAR(30)  — 'facturas','notas_credito','notas_debito',
                                  'cotizaciones','ordenes_venta','facturas_proveedor',
                                  'ordenes_compra','liquidaciones_compra'
documento_id      UUID
codigo_impuesto   VARCHAR(1)   — '2'=IVA, '3'=ICE, '5'=IRBPNR
codigo_porcentaje VARCHAR(4)   — código SRI (Tabla 17/18). Ej: '0','4','7' para IVA
tarifa_id         UUID         — soft ref a catalogo_tarifas_iva/ice/irbpnr
base_imponible    DECIMAL(14,2)
descuento         DECIMAL(14,2)
valor             DECIMAL(14,2)
UNIQUE (tabla_origen, documento_id, codigo_impuesto, codigo_porcentaje)
```

### linea_ec_impuestos (016_linea_impuestos.sql) — PENDIENTE
Tabla polimórfica de impuestos por línea de documento. Espeja el elemento `<detalle>/<impuesto>` del XML SRI. Cubre todas las líneas de todos los documentos.
```
id, empresa_id,
tabla_origen_linea VARCHAR(40) — 'factura_lineas','cotizacion_lineas','orden_venta_lineas',
                                  'nota_credito_lineas','nota_debito_lineas',
                                  'factura_proveedor_lineas','orden_compra_lineas'
linea_id           UUID
codigo_impuesto    VARCHAR(1)   — '2'=IVA, '3'=ICE, '5'=IRBPNR
codigo_porcentaje  VARCHAR(4)   — código SRI de la tarifa
tarifa_id          UUID         — soft ref al catálogo correspondiente
tipo_calculo       VARCHAR(12)  — PORCENTAJE | ESPECIFICO | MIXTO
base_imponible     DECIMAL(14,2)
tarifa_valor       DECIMAL(10,4) — porcentaje o valor fijo según tipo_calculo
descuento_adicional DECIMAL(14,2)
valor              DECIMAL(14,2)
UNIQUE (tabla_origen_linea, linea_id, codigo_impuesto, codigo_porcentaje)
```

### factura_rubros_terceros (017_rubros_terceros.sql)
Rubros cobrados en nombre de terceros. Espeja `<otrosRubrosTerceros>/<rubro>` del ANEXO 8.
Solo aplica a facturas versión XML 2.0.0 y 2.1.0. La propina (10%, Cód. Trabajo Art. 318)
es distinta y vive en `facturas.propina`.
```
id, empresa_id,
factura_id   UUID         — soft ref a facturas(id)
concepto     VARCHAR(300) — descripción del rubro (Alfanumérico Max 300)
total        DECIMAL(14,2)
orden        SMALLINT     — orden de aparición en el XML
```
> Si hay rubros de terceros → usar XSD versión 2.0.0 o 2.1.0.
> Sin rubros → usar versión 1.0.0 o 1.1.0.

### log_sri_autorizaciones
Registro inmutable de cada intento de comunicación con el WS SRI. Permite auditoría completa del pipeline.
```
id, empresa_id, cola_id → cola_documentos_electronicos,
tipo_documento, clave_acceso,
intento_numero, timestamp_envio,
estado_sri (RECIBIDA|AUTORIZADA|NO_AUTORIZADA),
codigo_error, mensaje_error, respuesta_completa (JSONB),
duracion_ms  — tiempo de respuesta para monitoreo
```

### Catálogos SRI (002_seed.sql)
- `catalogo_formas_pago` — Tabla 24 de la ficha técnica SRI (01–21)
- `catalogo_tipos_documento` — Tipos de comprobante electrónico
- `catalogo_tarifas_iva` — Tarifas IVA con vigencias y vigente_desde (Tabla 17)
- `catalogo_tarifas_ice` — ICE con tipo_calculo (PORCENTAJE/ESPECIFICO/MIXTO), tarifa_porcentaje, tarifa_especifica, unidad_medida (Tabla 18)
- `catalogo_tarifas_irbpnr` — Impuesto Redimible Botellas Plásticas (fijo USD/botella)

### Catálogos de retenciones y sustentos (011, 012)
- `catalogo_tipos_retencion_iva` — Porcentajes retención IVA
- `catalogo_tipos_retencion_ir` — Porcentajes retención IR (tablas ATS)
- `catalogo_sustentos_tributarios` — Sustentos ATS (01–15)

---

## Columnas Añadidas a Tablas Core

El módulo extiende tablas del módulo `facturacion` con campos SRI (idempotente via `ALTER TABLE … ADD COLUMN IF NOT EXISTS`):

### facturas (007_extend_facturas.sql)
```
establecimiento_id    UUID          Soft ref → establecimientos
punto_emision_id      UUID          Soft ref → puntos_emision
secuencial            VARCHAR(9)    9 dígitos con cero izquierdo (ej: 000000001)
clave_acceso          VARCHAR(49)   49 dígitos SRI (generada por sri-firma-envio)
numero_autorizacion   VARCHAR(49)   Devuelto por SRI al autorizar
fecha_autorizacion    TIMESTAMPTZ
cola_doc_id           UUID          Soft ref → cola_documentos_electronicos
ride_url              TEXT          PDF RIDE en Storage (bucket ride-pdf)
xml_autorizado_url    TEXT          XML autorizado en Storage (bucket sri-documents)
propina               DECIMAL(14,2) 10% restaurantes (Cód. Trabajo Art. 318). DEFAULT 0.
                                    XML: tag <propina> OBLIGATORIO en infoFactura
                                    (versiones 1.0.0–2.1.0). 0.00 si no aplica.
                                    NO es impuesto SRI. Va fuera de <totalConImpuestos>.
                                    importeTotal = subtotal - descuento + impuestos + propina
```

### notas_credito, notas_debito (007_extend_facturas.sql)
```
establecimiento_id    UUID        Soft ref → establecimientos
punto_emision_id      UUID        Soft ref → puntos_emision
secuencial            VARCHAR(9)  9 dígitos con cero izquierdo (ej: 000000001)
clave_acceso          VARCHAR(49) 49 dígitos SRI (generada por sri-firma-envio)
numero_autorizacion   VARCHAR(49) Devuelto por SRI al autorizar
fecha_autorizacion    TIMESTAMPTZ
cola_doc_id           UUID        Soft ref → cola_documentos_electronicos
ride_url              TEXT        PDF RIDE en Storage (bucket ride-pdf)
xml_autorizado_url    TEXT        XML autorizado en Storage (bucket sri-documents)
```
> NC y ND no tienen `<propina>` — solo facturas.

> **¿Por qué no hay columnas `subtotal_X`?**
> El SRI maneja múltiples tarifas IVA simultáneas que cambian con frecuencia
> (0%, 5%, 8%, 13%, 15%, exento, no objeto, diferenciados). Columnas fijas
> rompen el schema con cada cambio normativo y no cubren ICE (>50 códigos).
> El desglose vive en `documento_ec_impuestos` (ver abajo).

### empresas (001_ec_tables.sql)
```
ambiente_sri              VARCHAR(10)  PRUEBAS | PRODUCCION
certificado_path          TEXT         Path .p12 en Storage (bucket certificados)
certificado_vault_key_id  TEXT         ID secreto en Supabase Vault
certificado_vence         DATE
certificado_activo        BOOLEAN
```

### contactos (008_extend_entidades.sql)
```
obligado_contabilidad  BOOLEAN
agente_retencion       BOOLEAN
contribuyente_especial VARCHAR(20)
regimen_microempresa   BOOLEAN
rimpe                  BOOLEAN
```

### productos (008_extend_entidades.sql)
```
tarifa_iva_id         UUID  Soft ref catalogo_tarifas_iva
tarifa_iva_compras_id UUID
codigo_sri            VARCHAR(20)  Código arancelario NANDINA
aplica_iva            BOOLEAN
aplica_ice            BOOLEAN
```

---

## RPCs Reemplazadas (CREATE OR REPLACE)

Estas RPCs del módulo Core `facturacion` son **reemplazadas** por la versión SRI:

| Función | Cambio |
|---------|--------|
| `confirmar_factura(factura_id, version)` | Añade: secuencial SRI atómico, construcción número `estab-pe-seq`, inserción en `cola_documentos_electronicos` |
| `get_estado_factura(factura_id)` | Añade campos SRI en respuesta: `clave_acceso`, `numero_autorizacion`, `propina`, `ride_url`, `xml_autorizado_url`, desglose `impuestos[]` |
| `anular_factura(id, motivo, version, tipo)` | Reemplaza versión Core. Aplica restricciones NAC-DGERCGC25-00000014: bloquea consumidor_final, negociable, sustenta_devolucion. Valida plazo 7 días para EN_LINEA. |

## RPCs Propias

| Función | Descripción |
|---------|-------------|
| `get_next_sri_sequence(estab_id, pe_id, tipo_doc)` | Incrementa y retorna siguiente número SRI (atómico) |
| `get_cola_item_para_firma(empresa_id)` | Retorna primer item PENDIENTE para firmar |
| `update_cola_firmado(id, xml_firmado, clave_acceso)` | Actualiza estado a FIRMADO |
| `update_cola_enviado(id)` | Actualiza estado a ENVIADO |
| `update_cola_autorizado(id, num_aut, fecha_aut, xml_aut)` | Actualiza estado a AUTORIZADO |
| `update_cola_rechazado(id, error_msg)` | Actualiza estado a RECHAZADO |
| `update_cola_error(id, error_msg)` | Registra error y actualiza intentos |
| `get_cola_pendientes_para_procesar(empresa_id, limit)` | Retorna items para procesamiento batch |
| `get_estado_documento_sri(documento_id)` | Estado del documento en el pipeline SRI |
| `store_certificate_password(empresa_id, password)` | Almacena clave .p12 en Supabase Vault |
| `get_certificate_password(empresa_id)` | Recupera clave descifrada del Vault |
| `update_empresa_certificado(empresa_id, path, vence, vault_id)` | Registra certificado en empresas |
| `calcular_impuestos_linea(...)` | Calcula IVA/ICE/IRBPNR según reglas cascade Ecuador (ICE primero, IVA sobre subtotal+ICE) |
| `agregar_impuestos_documento(tabla_origen, documento_id)` | Agrega impuestos de líneas a nivel documento en `documento_ec_impuestos` |
| `get_rubros_terceros(factura_id)` | Retorna rubros de terceros para generación XML. Si `tiene_rubros=true`, usar XSD v2.0.0/v2.1.0 |
| `esta_en_plazo_anulacion_en_linea(fecha_emision)` | TRUE si el comprobante está dentro del plazo de 7 días del mes siguiente. Considera regla pre/post 01-ago-2025 |
| `get_reglas_anulacion(doc_id, tabla_origen)` | Retorna opciones disponibles: `puede_anular_en_linea`, `puede_anular_por_nc`, `motivo_bloqueo`. Consultar desde la UI antes de mostrar botones |
| `get_pending_documents(limit)` | Retorna documentos en cola SRI listos para procesar (`EN_COLA`, `PENDIENTE`, `RECIBIDA`, `proximo_reintento <= now()`, `intentos_envio < 20`) |
| `validate_document_sri_rules(doc_id, tipo_documento)` | Valida restricciones SRI antes de generar el XML. Retorna array de errores. Se ejecuta sincrónicamente — el usuario ve los errores antes de intentar emitir |
| `import_supplier_credit_note(empresa_id, xml)` | Importa y parsea XML de Nota de Crédito del proveedor desde el SRI. Valida clave_acceso 49 dígitos, estructura `infoTributaria`/`infoNotaCredito`, verifica no duplicada, crea registro NC, ajusta CxP, genera asiento contable |

---

## Restricciones y Validaciones SRI

PILAR valida las siguientes restricciones del SRI ANTES de permitir emitir un comprobante electrónico. La función `validate_document_sri_rules()` corre síncronamente — el usuario ve los errores inmediatamente, el documento NO se encola hasta que pase validación.

```
╔══════════════════════════════════════════════════════════════════════╗
║  FACTURA (tipo 01)                                                  ║
╠══════════════════════════════════════════════════════════════════════╣
║  - Consumidor final (9999999999999):                                ║
║    • Monto maximo por factura: $50 USD                              ║
║    • Si supera $50 → OBLIGATORIO datos del comprador               ║
║    • Tipo identificacion: 07 (Consumidor Final)                     ║
║  - RUC del emisor debe estar activo en el SRI                       ║
║  - Establecimiento y punto de emision deben estar activos           ║
║  - Fecha emision no puede ser anterior a la del ultimo secuencial   ║
║  - Secuencial debe ser correlativo (sin saltos)                     ║
║  - Tipo emision: 1 (Normal) siempre (contingencia requiere permiso)║
╠══════════════════════════════════════════════════════════════════════╣
║  NOTA DE CREDITO (tipo 04)                                          ║
╠══════════════════════════════════════════════════════════════════════╣
║  - DEBE referenciar una factura existente y AUTORIZADA              ║
║  - Plazo: dentro de los 5 ANIOS siguientes a la emision factura    ║
║  - El monto de la NC NO puede superar el total de la factura        ║
║  - La suma de NC emitidas contra una factura no puede superar       ║
║    el total de la factura original                                   ║
║  - Motivo de modificacion es OBLIGATORIO                            ║
║  - Debe incluir datos exactos de la factura original:               ║
║    codDocModificado='01', numDocModificado, fechaEmisionDocSustento ║
╠══════════════════════════════════════════════════════════════════════╣
║  NOTA DE DEBITO (tipo 05)                                           ║
╠══════════════════════════════════════════════════════════════════════╣
║  - DEBE referenciar una factura existente y AUTORIZADA              ║
║  - Motivo(s) de modificacion obligatorio(s)                         ║
║  - Cada motivo con descripcion + valor                              ║
╠══════════════════════════════════════════════════════════════════════╣
║  RETENCION (tipo 07)                                                ║
╠══════════════════════════════════════════════════════════════════════╣
║  - Debe emitirse dentro de los 5 DIAS habiles siguientes            ║
║    al registro del comprobante de venta del proveedor               ║
║  - Documento sustento obligatorio (factura/liquidacion)             ║
║  - Codigos de retencion deben ser vigentes (catalogo SRI)           ║
║  - Porcentaje de retencion segun codigo (no inventar)               ║
║  - Base imponible >= 0                                               ║
║  - Un comprobante de venta puede tener maximo UNA retencion         ║
╠══════════════════════════════════════════════════════════════════════╣
║  LIQUIDACION DE COMPRA (tipo 03)                                    ║
╠══════════════════════════════════════════════════════════════════════╣
║  - Solo para proveedores SIN factura (informales, extranjeros)      ║
║  - Tipo identificacion proveedor: 05 (cedula), 06 (pasaporte)      ║
║  - Incluye retenciones automaticas (100% IVA + 100% Renta)         ║
╠══════════════════════════════════════════════════════════════════════╣
║  GUIA DE REMISION (tipo 06)                                        ║
╠══════════════════════════════════════════════════════════════════════╣
║  - Obligatoria para traslado de mercancias entre establecimientos   ║
║  - Datos obligatorios: transportista, placa, ruta, destinatarios   ║
║  - Fecha inicio transporte no puede ser pasada (max 24h atras)     ║
╠══════════════════════════════════════════════════════════════════════╣
║  GENERALES                                                          ║
╠══════════════════════════════════════════════════════════════════════╣
║  - Ambiente: 1=Pruebas, 2=Produccion (NUNCA mezclar)               ║
║  - Clave de acceso: 49 digitos, unica, algoritmo modulo 11         ║
║  - Caracteres especiales: & debe ser &amp; en XML                   ║
║  - Tarifas IVA vigentes: 0% (cod 0), 15% (cod 4), 5% (cod 5),    ║
║    No objeto (cod 6), Exento (cod 7)                                ║
║  - El SRI puede tardar hasta 24h en autorizar (estado PPR)          ║
║  - Reenvio: se puede reutilizar clave+secuencial para corregir     ║
║  - Error 70: clave en procesamiento, NO reenviar, esperar 24h      ║
╚══════════════════════════════════════════════════════════════════════╝
```

---

## Flujo de Emisión Detallado (No Bloqueante)

```
╔══════════════════════════════════════════════════════════════════════════╗
║  PRINCIPIO: Cumplir la obligacion SRI de enviar el comprobante al      ║
║  momento de la transaccion. El secuencial, clave de acceso, firma      ║
║  y envio al WS del SRI se ejecutan INMEDIATAMENTE al confirmar.        ║
║  El RIDE se genera e imprime de inmediato.                             ║
║  La COLA es solo para reintentos (cuando el SRI no responde o falla).  ║
╚══════════════════════════════════════════════════════════════════════════╝

  1. CONFIRMAR PAGO / EMISION (inmediato, sincrono)
     │ ├── Asignar secuencial atomico (SELECT nextval via get_next_sri_sequence)
     │ ├── Generar clave de acceso (49 digitos)
     │ ├── Generar XML sin firma
     │ ├── VALIDAR XML contra XSD (esquema del tipo de documento)
     │ │     └── Si XSD falla → ERROR INMEDIATO al usuario + anotar en log
     │ │     └── Si XSD OK → continuar con firma
     │ ├── Firmar XML (XAdES-BES) via Edge Function sri-firma-envio
     │ ├── ENVIAR AL SRI INMEDIATAMENTE (cumplimiento normativa SRI)
     │ │     └── Enviar al WS Recepcion del SRI
     │ │     └── Si SRI responde RECIBIDA → estado='RECIBIDA'
     │ │     └── Consultar WS Autorizacion
     │ │     └── Si AUTORIZADO → almacenar, estado='AUTORIZADO'
     │ │     └── Si SRI NO RESPONDE → estado='EN_COLA' (reintento automatico)
     │ │         (el SRI permite hasta 24h para procesar, pero el envio
     │ │          debe ser al momento de la transaccion)
     │ ├── Generar RIDE (PDF) inmediatamente (con o sin autorizacion)
     │ ├── Imprimir RIDE o tirilla termica
     │ └── RETORNAR al usuario → Transaccion completada
     │
     ▼ (el usuario ya tiene su comprobante impreso)

  2. COLA DE REINTENTOS (asincrono, solo para fallos de comunicacion)
     │ ├── Edge Function sri-firma-envio + poll-autorizacion (pg_cron)
     │ ├── Toma documentos con estado='EN_COLA', 'PENDIENTE' o 'RECIBIDA'
     │ ├── Reintenta envio al WS Recepcion del SRI (si no fue recibido)
     │ ├── Consulta WS Autorizacion del SRI (si ya fue recibido)
     │ │     └── AUTORIZADO → almacenar XML autorizado, estado='AUTORIZADO'
     │ │     └── NO_AUTORIZADO → almacenar errores, estado='NO_AUTORIZADO'
     │ │     └── PPR (en proceso) → reintentar con backoff exponencial (hasta 24h)
     │ └── Al autorizar → disparar envio de notificaciones multi-canal
     │
     ▼

  3. NOTIFICACIONES MULTI-CANAL (asincrono, post-autorizacion)
     └── send-notification Edge Function
           ├── Email: Resend API (XML autorizado + RIDE PDF adjuntos)
           ├── WhatsApp: API de WhatsApp Business (enlace al RIDE)
           └── Telegram: Bot API (enlace al RIDE + PDF adjunto)

OFFLINE FIRST (cuando no hay conexion al servidor Supabase):
  - brick_offline_first almacena la factura localmente (SQLite)
  - El secuencial se pre-asigna del rango offline (secuenciales_offline)
  - Al recuperar conexion, Brick sincroniza con Supabase
  - La cola de procesamiento recoge los documentos sincronizados
  - El RIDE se genera localmente con Syncfusion PDF (no necesita internet)

NOTA LEGAL: La facturacion offline genera un BORRADOR con secuencial SRI
pre-asignado del rango offline. La firma digital (XAdES-BES) y el envio
al SRI se ejecutan automaticamente al recuperar conexion via Edge Function
sri-firma-envio. Esto cumple con la normativa SRI ya que:
1. El secuencial se reserva al momento de la transaccion
2. El SRI permite envio posterior dentro de las 24 horas
3. La clave de acceso se genera localmente (no requiere internet)
4. El RIDE se imprime inmediatamente con datos del borrador
Al reconectar: Brick sync → Edge Function firma → envio SRI → actualizacion estado

VALIDACION XSD (pre-firma, sincrona):
  - Factura: factura_V2.1.0.xsd
  - Nota de Credito: notaCredito_V1.1.0.xsd
  - Retencion: comprobanteRetencion_V2.0.0.xsd
  - La validacion se ejecuta en la Edge Function sri-firma-envio
  - Si el XML NO pasa validacion:
    → Retorna error 422 con detalle de los campos invalidos
    → Registra error en log de sincronizacion
    → El usuario ve el error INMEDIATAMENTE (no espera cola)
    → El documento NO se encola hasta que pase validacion
```

---

## Tabla secuenciales_offline

Pre-asigna rangos de secuenciales para operación sin conexión al servidor Supabase.

```sql
CREATE TABLE secuenciales_offline (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID REFERENCES empresas(id) NOT NULL,
  establecimiento VARCHAR(3) NOT NULL,
  punto_emision   VARCHAR(3) NOT NULL,
  tipo_documento  VARCHAR(2) NOT NULL,
  rango_desde     INTEGER NOT NULL,
  rango_hasta     INTEGER NOT NULL,
  dispositivo_id  VARCHAR(100) NOT NULL,  -- ID unico del dispositivo
  usado_hasta     INTEGER DEFAULT 0,       -- Ultimo secuencial usado
  created_at      TIMESTAMPTZ DEFAULT now(),
  UNIQUE(empresa_id, establecimiento, punto_emision, tipo_documento, dispositivo_id)
);
```

---

## RPC import_supplier_credit_note

```sql
-- Flujo: Proveedor emite NC electronica -> cliente importa XML ->
--   parsear (clave_acceso, doc_sustento, monto) -> validar contra facturas compra ->
--   crear registro NC -> ajustar CxP -> opcionalmente aplicar como metodo de pago
CREATE OR REPLACE FUNCTION import_supplier_credit_note(
  p_empresa_id UUID, p_xml TEXT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_clave VARCHAR(49); v_ruc VARCHAR(13); v_total DECIMAL(14,2);
  v_doc_sustento VARCHAR(20); v_fc_id UUID; v_cxp_id UUID; v_nc_id UUID;
BEGIN
  -- 1. Parsear XML: infoTributaria (clave, ruc) + infoNotaCredito (valorModificacion, numDocModificado)
  -- 2. Validar clave acceso (49 digitos + digito verificador)
  -- 3. Verificar no duplicada: SELECT FROM documentos_electronicos WHERE clave_acceso = v_clave
  -- 4. Buscar factura compra original por numDocModificado + validar RUC proveedor
  -- 5. Crear registro NC (facturas con tipo_documento = 'NC_PROVEEDOR'), guardar XML en adjuntos
  -- 6. Ajustar CxP: UPDATE cuentas_por_pagar SET saldo = saldo - v_total
  -- 7. Asiento: Db CxP (2.1.1.x) / Cr Inventario o Gasto (segun tipo)
  RETURN jsonb_build_object('nc_id', v_nc_id, 'clave_acceso', v_clave,
    'proveedor_ruc', v_ruc, 'total', v_total,
    'factura_compra_id', v_fc_id, 'cxp_id', v_cxp_id, 'estado', 'REGISTRADA');
END;
$$;
```

---

## Edge Functions

| Función | Descripción |
|---------|-------------|
| `sri-firma-envio` | Obtiene item de la cola (`tipo_operacion='EMISION'`), genera XML según XSD, firma XAdES-BES con .p12, envía SOAP al SRI, actualiza estado |
| `generate-ride` | Genera PDF RIDE desde XML autorizado, sube a Storage `ride-pdf` |
| `poll-autorizacion` | Consulta estado de documentos ENVIADOS en el SRI, actualiza cola con autorización o rechazo |
| `anular-documento` | Procesa cola con `tipo_operacion='ANULACION'`. Genera mensaje de anulación, firma XAdES-BES, envía SOAP al WS de anulaciones SRI, actualiza estado del documento a ANULADA. Normativa: NAC-DGERCGC25-00000014 |

---

## Storage Buckets

| Bucket | Tipo | Contenido | Límite |
|--------|------|-----------|--------|
| `certificados` | Privado | Archivos .p12 del SRI | 10 MB |
| `sri-documents` | Privado | XMLs sin firma, firmados y autorizados | 50 MB |
| `ride-pdf` | Privado | PDFs RIDE para clientes | 5 MB |

**Estructura de rutas en `sri-documents`:**
```
{empresa_id}/
  {año}/
    {mes}/
      {clave_acceso}.xml    # XML firmado XAdES-BES
      {clave_acceso}.pdf    # RIDE generado (también en ride-pdf)
```

---

## Pipeline SRI (flujo asíncrono)

```
confirmar_factura()
  → INSERT cola (PENDIENTE)
  → Edge Function sri-firma-envio (pg_cron cada 30s)
      → get_cola_item_para_firma()
      → Genera XML según XSD
      → Firma XAdES-BES (certificado .p12 del Vault)
      → update_cola_firmado()
      → Envía SOAP a SRI (ambiente PRUEBAS o PRODUCCION)
      → update_cola_enviado() / update_cola_rechazado()
      → Si ENVIADO: inicia polling
  → Edge Function poll-autorizacion (pg_cron cada 5min)
      → Consulta SRI por número de autorización
      → Si AUTORIZADO: update_cola_autorizado()
          → Actualiza facturas: numero_autorizacion, fecha_autorizacion
          → Edge Function generate-ride: genera PDF RIDE
      → Si RECHAZADO: update_cola_rechazado()
```

---

## Permisos

| Código | Descripción |
|--------|-------------|
| `facturacion_ec.establecimientos.ver` | Ver establecimientos y puntos de emisión |
| `facturacion_ec.establecimientos.editar` | Configurar establecimientos y puntos de emisión |
| `facturacion_ec.cola_sri.ver` | Ver cola de documentos electrónicos |
| `facturacion_ec.cola_sri.reintentar` | Reintentar documentos rechazados |
| `facturacion_ec.certificado.ver` | Ver estado del certificado digital |
| `facturacion_ec.certificado.cargar` | Cargar/actualizar certificado .p12 |
| `facturacion_ec.config_sri.ver` | Ver configuración SRI |
| `facturacion_ec.config_sri.editar` | Cambiar ambiente SRI y secuenciales |

---

## Notas de Implementación

### Reintentos Cola SRI — Backoff Exponencial

El campo `proximo_intento` se calcula como `NOW() + INTERVAL '1 minute' * 2^intentos`.

| Intento | Espera |
|---------|--------|
| 1 | 2 min |
| 2 | 4 min |
| 3 | 8 min |
| 4 | 16 min |
| 5 | 32 min |
| 6 | 64 min (~1 h) |
| 7 | 128 min (~2 h) |
| 8 | 256 min (~4 h) → ERROR_PERMANENTE |

Tras `ERROR_PERMANENTE`, el documento requiere revisión manual desde el monitor de cola SRI (`facturacion_ec/cola-sri/`).

### Secuenciales Offline

- Estado `BORRADOR`: factura guardada sin número SRI (compatible con modo offline)
- Al confirmar (con conectividad): `confirmar_factura()` llama `get_next_sri_sequence()` → asigna secuencial atómico, construye `clave_acceso` 49 dígitos, inserta en `cola_documentos_electronicos` con estado `PENDIENTE`
- Flutter no bloquea esperando autorización; el pipeline corre en background (pg_cron + Edge Functions)

---

## Migrations

| # | Archivo | Contenido |
|---|---------|-----------|
| 001 | `001_ec_tables.sql` | establecimientos, puntos_emision, secuenciales + campos SRI en empresas |
| 002 | `002_seed.sql` | Catálogos oficiales SRI (formas pago, tipos doc, tarifas IVA/ICE/IRBPNR) |
| 003 | `003_storage.sql` | Buckets Storage + funciones Vault certificado |
| 004 | `004_cola.sql` | cola_documentos_electronicos + 8 RPCs pipeline |
| 005 | `005_ride.sql` | Funciones auxiliares generación RIDE |
| 006 | `006_poll.sql` | Funciones poll autorización SRI |
| 007 | `007_extend_facturas.sql` | Crea `documento_ec_impuestos` (polimórfica, todos los docs). Añade campos SRI a facturas (incl. `propina`) y nc/nd (sin subtotales fijos). Reemplaza `confirmar_factura` y `get_estado_factura` |
| 008 | `008_extend_entidades.sql` | Añade campos tributarios SRI a contactos y productos |
| 009 | `009_extend_inventario.sql` | Integración SRI con inventario (guías de remisión) |
| 010 | `010_extend_tesoreria.sql` | Integración SRI con tesorería (comprobantes retención) |
| 011 | `011_seed_retenciones.sql` | Catálogos retenciones IVA e IR |
| 012 | `012_seed_sustentos.sql` | Catálogo sustentos tributarios ATS (01–15) |
| 013 | `013_seed_catalogos_ats.sql` | Catálogos ATS parte 1 |
| 014 | `014_seed_catalogos_ats2.sql` | Catálogos ATS parte 2 |
| 015 | `015_seed_permissions.sql` | Permisos del módulo + asignaciones a roles |
| 016 | `016_linea_impuestos.sql` | Crea `linea_ec_impuestos` (polimórfica). Actualiza `catalogo_tarifas_ice` con `tipo_calculo`/`tarifa_especifica`. Elimina campos ICE hardcodeados de Core |
| 017 | `017_rubros_terceros.sql` | Crea `factura_rubros_terceros` para `<otrosRubrosTerceros>` (ANEXO 8, facturas v2.0.0/v2.1.0). RPC `get_rubros_terceros()` |
| 018 | `018_anulacion_electronica.sql` | Anulación electrónica según NAC-DGERCGC25-00000014 + reforma NAC-DGERCGC25-00000017 (vigente 01-ago-2025). Añade campos anulación a facturas/nc/nd, `tipo_operacion` en cola, tabla `solicitudes_anulacion_receptor`. Reemplaza `anular_factura()` con reglas 2025. Nuevas RPCs: `esta_en_plazo_anulacion_en_linea()`, `get_reglas_anulacion()` |
