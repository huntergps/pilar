# Importación de Documentos XML del SRI (Compras)

*Spec derivada del módulo `l10n_ec_edi_import` (Odoo 19.1 Ecuador — producción en csolish/tecnoh)*

---

## Descripción

Permite importar facturas de compra, liquidaciones y otros documentos electrónicos emitidos por proveedores, consultando directamente al SRI por clave de acceso o cargando el archivo XML. Incluye homologación de productos (mapeo del catálogo del proveedor al catálogo PILAR), generación automática de órdenes de compra o facturas de compra, y detección de duplicados.

---

## Flujo General

```
1. INGRESAR clave de acceso (49 dígitos) o cargar XML
     ↓
2. CONSULTAR SRI — verifica autorización y descarga XML
     ↓
3. PARSEAR XML — crea/actualiza proveedor, extrae líneas
     ↓
4. HOMOLOGAR PRODUCTOS — mapea códigos proveedor → productos PILAR
     (auto si existe mapeo previo, manual si no)
     ↓
5. GENERAR documento:
   - Productos físicos → Orden de Compra
   - Solo servicios → Factura de Compra directa
     ↓
6. CONFIRMAR OC → recepción → factura de compra
```

---

## Estados del Documento Importado

| Estado | estatus_import | Descripción |
|---|---|---|
| `borrador` | NONE | Recién creado, sin procesar |
| `enviando` (sent) | GET | Consultado al SRI, XML descargado |
| `sent` | MAPPING | Homologando productos |
| `purchase` | ORDER | OC generada |
| `invoice` | INVOICE | Factura de compra generada |
| `done` | — | Completamente procesado |
| `cancel` | — | Cancelado |

### Errores posibles

| estatus_import | Causa |
|---|---|
| `FAIL GET` | Error SOAP al consultar el SRI (timeout, red) |
| `FAIL READ` | XML malformado o estructura desconocida |
| `FAIL PRODUCTS` | Error crítico durante mapeo automático |

---

## Modelo de Datos

### Tabla: `documentos_importados` (edocuments)

```sql
CREATE TABLE documentos_importados (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id              UUID NOT NULL REFERENCES empresas(id),
  -- Identificación SRI
  clave_acceso            TEXT NOT NULL,               -- 49 dígitos (= autorización)
  nro_documento           TEXT,                        -- 001-001-000001234
  estado_sri              TEXT DEFAULT 'NO AUTORIZADO'
                          CHECK (estado_sri IN ('NO ENVIADO','RECIBIDA','EN PROCESO',
                            'DEVUELTA','AUTORIZADO','NO AUTORIZADO','RECHAZADA')),
  fecha_autorizacion      TIMESTAMPTZ,
  -- Datos del proveedor
  proveedor_id            UUID REFERENCES contactos(id),
  -- Montos (del RIDE / XML)
  subtotal                NUMERIC(15,2) DEFAULT 0,
  iva_12                  NUMERIC(15,2) DEFAULT 0,
  iva_15                  NUMERIC(15,2) DEFAULT 0,
  iva_8                   NUMERIC(15,2) DEFAULT 0,
  descuento               NUMERIC(15,2) DEFAULT 0,
  total                   NUMERIC(15,2) DEFAULT 0,
  -- Fechas
  fecha_emision           DATE,
  fecha_proceso           TIMESTAMPTZ,
  -- Tipo y estado de importación
  tipo_importacion        TEXT DEFAULT 'sri'
                          CHECK (tipo_importacion IN ('sri','file')),
  tipo_homologacion       TEXT DEFAULT 'manual'
                          CHECK (tipo_homologacion IN ('auto','manual')),
  estado                  TEXT DEFAULT 'borrador'
                          CHECK (estado IN ('borrador','enviando','purchase','invoice','done','cancel')),
  estatus_import          TEXT DEFAULT 'NONE',
  -- Configuración
  estado_oc_al_generar    TEXT DEFAULT 'draft'
                          CHECK (estado_oc_al_generar IN ('draft','done')),
  produccion_sri          BOOLEAN DEFAULT TRUE,
  -- Relacionados
  orden_compra_id         UUID REFERENCES ordenes_compra(id),
  factura_compra_id       UUID REFERENCES facturas(id),
  -- Error
  error_detalle           TEXT,
  notas                   TEXT,
  -- Métricas de homologación
  lineas_sin_mapear       INT DEFAULT 0,
  lineas_mapeadas         INT DEFAULT 0
);

ALTER TABLE documentos_importados ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON documentos_importados FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- Previene importar la misma clave de acceso dos veces
CREATE UNIQUE INDEX uq_clave_acceso ON documentos_importados(empresa_id, clave_acceso);
```

### Tabla: `documentos_importados_lineas`

```sql
CREATE TABLE documentos_importados_lineas (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  documento_id        UUID NOT NULL REFERENCES documentos_importados(id) ON DELETE CASCADE,
  empresa_id          UUID NOT NULL REFERENCES empresas(id),
  -- Del XML del proveedor
  codigo_proveedor    TEXT NOT NULL,
  nombre_proveedor    TEXT NOT NULL,
  cantidad            NUMERIC(15,4) NOT NULL,
  precio_unitario     NUMERIC(15,4) NOT NULL,
  descuento_pct       NUMERIC(8,4) DEFAULT 0,
  -- Homologación
  producto_id         UUID REFERENCES productos(id),  -- NULL si no homologado
  unidad_medida_id    UUID REFERENCES unidades_medida(id),
  vinculado           BOOLEAN DEFAULT FALSE,
  tipo_linea          TEXT DEFAULT 'consu'
                      CHECK (tipo_linea IN ('consu','service')),
  -- Distribución especial (unificar o distribuir líneas)
  unificar            BOOLEAN DEFAULT FALSE,
  distribuir          BOOLEAN DEFAULT FALSE,
  distribuir_codigo   TEXT,
  -- Totales
  subtotal            NUMERIC(15,2),
  impuesto_ids        UUID[]
);
```

### Tabla: `mapeo_proveedor_producto` (homologación persistente)

```sql
CREATE TABLE mapeo_proveedor_producto (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id          UUID NOT NULL REFERENCES empresas(id),
  proveedor_id        UUID NOT NULL REFERENCES contactos(id),
  codigo_proveedor    TEXT NOT NULL,
  nombre_proveedor    TEXT NOT NULL,
  producto_id         UUID NOT NULL REFERENCES productos(id),
  unidad_medida_id    UUID REFERENCES unidades_medida(id),
  unificar            BOOLEAN DEFAULT FALSE,
  distribuir          BOOLEAN DEFAULT FALSE,
  distribuir_codigo   TEXT,
  UNIQUE(empresa_id, proveedor_id, codigo_proveedor)
);
```

---

## Homologación de Productos

El proceso mapea los códigos del proveedor al catálogo PILAR:

1. **Búsqueda por código proveedor** en `mapeo_proveedor_producto` → si existe, se usa automáticamente
2. **Búsqueda por código interno** del producto en PILAR
3. **Si no se encuentra** → línea queda pendiente de homologación manual
4. **Al confirmar mapeo manual** → se guarda en `mapeo_proveedor_producto` para futuros documentos del mismo proveedor

### Opciones especiales de líneas

| Flag | Descripción |
|---|---|
| `unificar` | Agrupa líneas del mismo producto en una sola línea de OC (suma qty, promedia precio) |
| `distribuir` | Distribuye qty/precio de varias líneas XML a un solo producto por `distribuir_codigo` |

---

## Funciones RPC

```typescript
// Importar por clave de acceso SRI
importar_por_clave(params: {
  clave_acceso: string         // 49 dígitos
  produccion_sri?: boolean     // true=producción, false=pruebas
}): {
  documento_id: UUID
  estado_sri: string
  proveedor: string
  total: number
  lineas_sin_mapear: number
}

// Importar desde archivo XML en base64
importar_desde_xml(params: {
  archivo_base64: string
}): {
  documento_id: UUID
  proveedor: string
  total: number
}

// Homologar línea manualmente
homologar_linea(params: {
  linea_id: UUID
  producto_id: UUID
  unidad_medida_id?: UUID
  guardar_mapeo?: boolean      // true = persistir en mapeo_proveedor_producto
}): { linea_id: UUID, vinculado: boolean }

// Ejecutar homologación automática (todas las líneas)
auto_homologar(documento_id: UUID): {
  mapeadas: number
  pendientes: number
}

// Generar Orden de Compra
generar_orden_compra(params: {
  documento_id: UUID
  confirmar_oc?: boolean       // true = OC confirmada directamente
}): { orden_compra_id: UUID }

// Generar Factura de Compra directa (solo servicios)
generar_factura_compra(documento_id: UUID): { factura_id: UUID }

// Verificar si clave ya fue importada
verificar_duplicado(clave_acceso: string): {
  existe: boolean
  documento_id?: UUID
}
```

---

## Edge Function: `import-sri-document`

```typescript
POST /functions/v1/import-sri-document
Body: {
  empresa_id: UUID
  clave_acceso: string       // 49 dígitos
  produccion: boolean
}
Response: {
  estado: 'AUTORIZADO' | 'NO AUTORIZADO' | 'EN PROCESO' | 'ERROR'
  numero_autorizacion: string
  fecha_autorizacion: string
  xml_content: string        // XML completo del documento
  proveedor: {
    ruc: string
    razon_social: string
    email?: string
  }
  detalles: [{
    codigo: string
    descripcion: string
    cantidad: number
    precio_unitario: number
    descuento: number
    subtotal: number
    impuestos: object
  }]
  totales: {
    subtotal: number
    iva12: number
    iva15: number
    total: number
    descuento: number
  }
}
```

---

## Validaciones de Negocio

- Clave de acceso única: no se puede importar dos veces la misma
- No se puede generar OC si quedan líneas sin homologar
- Para Factura directa: todas las líneas deben ser servicios (`tipo_linea = 'service'`)
- Si el proveedor (RUC) no existe en PILAR, se crea automáticamente
- Descuento del XML es monto absoluto → se convierte a porcentaje para la OC

---

## Pantallas Flutter

### Lista de Documentos Importados
- `CrudScaffold<DocumentoImportado>` filtros: estado, proveedor, rango fechas, estado_sri
- Columnas: clave_acceso (truncada), proveedor, fecha, total, lineas_mapeadas/total, estado

### Formulario de Importación

```
┌────────────────────────────────────────────────────────────┐
│ IMPORTAR DOCUMENTO ELECTRÓNICO                             │
│ ○ Por clave de acceso SRI    ○ Desde archivo XML           │
│ Clave: [49 dígitos___________________] [Consultar SRI]     │
├────────────────────────────────────────────────────────────┤
│ PROVEEDOR: Empresa XYZ SA (RUC 0912345678001)              │
│ Nro: 001-001-000001234  Fecha: 15/01/2026  Total: $1,500   │
├────────────────────────────────────────────────────────────┤
│ HOMOLOGACIÓN DE PRODUCTOS                                  │
│ ┌──────────┬───────────────┬────────┬────────────────────┐ │
│ │ Código   │ Descripción   │ Cant.  │ Producto PILAR     │ │
│ ├──────────┼───────────────┼────────┼────────────────────┤ │
│ │ 001-ABC  │ Laptop 15"    │  2.00  │ ✓ Laptop ASUS X15  │ │
│ │ 002-XYZ  │ Mouse USB     │  5.00  │ ⚠️ [Buscar prod.]   │ │
│ └──────────┴───────────────┴────────┴────────────────────┘ │
│ [Auto-Homologar]                                           │
├────────────────────────────────────────────────────────────┤
│ [Generar Orden de Compra]  [Generar Factura]  [Cancelar]  │
└────────────────────────────────────────────────────────────┘
```

### Pantalla de Homologación Manual
- Tap en línea pendiente → búsqueda de productos PILAR
- Checkbox "Recordar mapeo para próximas importaciones"
- Opciones avanzadas: Unificar / Distribuir líneas

---

## Tabla de Auditoría de Importaciones

Para trazabilidad completa de todas las importaciones (exitosas, duplicadas y con error), se mantiene una tabla de log independiente de `documentos_importados`:

```sql
CREATE TABLE importaciones_xml_sri (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id              UUID NOT NULL REFERENCES empresas(id),
  metodo_importacion      VARCHAR(20) NOT NULL
                          CHECK (metodo_importacion IN ('CLAVE_ACCESO','ARCHIVO_XML','LOTE_ZIP')),
  clave_acceso            VARCHAR(49),
  archivo_url             TEXT,                   -- URL en Supabase Storage si fue por archivo
  estado                  VARCHAR(20) DEFAULT 'PENDIENTE'
                          CHECK (estado IN (
                            'PENDIENTE','PROCESANDO','IMPORTADO',
                            'DUPLICADO','ERROR','RECHAZADO'
                          )),
  error_detalle           TEXT,                   -- Mensaje de error SRI o de parseo
  factura_proveedor_id    UUID,                   -- Factura creada tras importación exitosa
  proveedor_encontrado_id UUID REFERENCES contactos(id),
  proveedor_ruc           VARCHAR(13),            -- RUC del emisor en el XML
  tipo_documento          VARCHAR(2),             -- 01=Factura,03=Liq,04=NC,05=ND,06=GR,07=Ret
  numero_documento        VARCHAR(17),            -- 001-001-000000001
  fecha_emision           DATE,
  total_xml               DECIMAL(14,2),
  total_homologado        DECIMAL(14,2),          -- Total tras homologación de precios
  diferencia_precio       DECIMAL(14,2)           -- total_xml - total_homologado
                          GENERATED ALWAYS AS (total_xml - COALESCE(total_homologado, total_xml)) STORED,
  requiere_aprobacion     BOOLEAN DEFAULT FALSE,  -- Diferencia > umbral configurado
  aprobador_id            UUID REFERENCES auth.users(id),
  usuario_id              UUID REFERENCES auth.users(id),  -- Quien ejecutó la importación
  created_at              TIMESTAMPTZ DEFAULT NOW(),
  procesado_at            TIMESTAMPTZ
);

ALTER TABLE importaciones_xml_sri ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON importaciones_xml_sri FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- Previene importar la misma clave de acceso dos veces en la misma empresa
CREATE UNIQUE INDEX uq_importacion_clave_empresa
  ON importaciones_xml_sri (empresa_id, clave_acceso)
  WHERE clave_acceso IS NOT NULL AND estado != 'ERROR';
```

---

## Funciones RPC Adicionales

### `import_sri_xml_by_key` — Importación por clave de acceso con reintentos

```sql
CREATE OR REPLACE FUNCTION import_sri_xml_by_key(
  p_clave_acceso  VARCHAR(49),
  p_produccion    BOOLEAN DEFAULT TRUE
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_empresa_id    UUID;
  v_log_id        UUID;
  v_doc_id        UUID;
  v_sri_response  JSONB;
  v_intento       INT := 0;
  v_max_reintentos CONSTANT INT := 3;
BEGIN
  v_empresa_id := (SELECT private.get_empresa_id());

  -- Verificar que no existe duplicado ya importado exitosamente
  IF EXISTS (
    SELECT 1 FROM importaciones_xml_sri
    WHERE empresa_id = v_empresa_id
      AND clave_acceso = p_clave_acceso
      AND estado IN ('IMPORTADO','PROCESANDO')
  ) THEN
    RAISE EXCEPTION 'DUPLICADO: Esta clave de acceso ya fue importada anteriormente';
  END IF;

  -- Crear registro de auditoría
  INSERT INTO importaciones_xml_sri (
    empresa_id, metodo_importacion, clave_acceso, estado,
    usuario_id
  ) VALUES (
    v_empresa_id, 'CLAVE_ACCESO', p_clave_acceso, 'PROCESANDO',
    auth.uid()
  ) RETURNING id INTO v_log_id;

  -- La consulta real al SRI se hace via Edge Function (no desde SQL)
  -- Esta función registra el log y delega a la Edge Function import-sri-document
  -- El resultado se actualiza vía callback o polling desde Flutter

  -- Extraer datos básicos de la clave de acceso (formato: DDMMAAAA TT RRRRRRRRRRR D XXXXXXXXXX N)
  UPDATE importaciones_xml_sri SET
    tipo_documento    = SUBSTRING(p_clave_acceso, 9, 2),
    proveedor_ruc     = SUBSTRING(p_clave_acceso, 11, 13),
    fecha_emision     = TO_DATE(SUBSTRING(p_clave_acceso, 1, 8), 'DDMMYYYY'),
    numero_documento  = SUBSTRING(p_clave_acceso, 24, 3) || '-' ||
                        SUBSTRING(p_clave_acceso, 27, 3) || '-' ||
                        SUBSTRING(p_clave_acceso, 30, 9)
  WHERE id = v_log_id;

  RETURN v_log_id;
END;
$$;
```

### `homologate_xml_products` — Mapeo automático + fuzzy search

```sql
CREATE OR REPLACE FUNCTION homologate_xml_products(p_importacion_id UUID)
RETURNS TABLE (
  linea_id        UUID,
  codigo_proveedor TEXT,
  nombre_proveedor TEXT,
  producto_id     UUID,
  producto_nombre TEXT,
  metodo          TEXT,   -- 'MAPEO_PREVIO','CODIGO_INTERNO','FUZZY','NUEVO'
  confianza       DECIMAL(5,2)
) LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_empresa_id UUID;
  v_linea      RECORD;
  v_prod_id    UUID;
  v_metodo     TEXT;
  v_confianza  DECIMAL(5,2);
BEGIN
  v_empresa_id := (SELECT private.get_empresa_id());

  FOR v_linea IN
    SELECT dil.*, di.proveedor_id
    FROM documentos_importados_lineas dil
    JOIN documentos_importados di ON di.id = dil.documento_id
    WHERE dil.documento_id = p_importacion_id
      AND NOT dil.vinculado
  LOOP
    v_prod_id   := NULL;
    v_metodo    := 'NUEVO';
    v_confianza := 0;

    -- 1. Buscar en mapeo previo del proveedor (máxima confianza)
    SELECT mpp.producto_id INTO v_prod_id
    FROM mapeo_proveedor_producto mpp
    WHERE mpp.empresa_id = v_empresa_id
      AND mpp.proveedor_id = v_linea.proveedor_id
      AND mpp.codigo_proveedor = v_linea.codigo_proveedor;

    IF FOUND THEN
      v_metodo    := 'MAPEO_PREVIO';
      v_confianza := 100.00;
    END IF;

    -- 2. Si no hay mapeo previo, buscar por código de barras/interno del producto
    IF v_prod_id IS NULL THEN
      SELECT p.id INTO v_prod_id
      FROM productos p
      WHERE p.empresa_id = v_empresa_id
        AND (p.referencia = v_linea.codigo_proveedor
             OR EXISTS (
               SELECT 1 FROM producto_codigos_barras pcb
               WHERE pcb.producto_id = p.id
                 AND pcb.codigo = v_linea.codigo_proveedor
             ));
      IF FOUND THEN
        v_metodo    := 'CODIGO_INTERNO';
        v_confianza := 95.00;
      END IF;
    END IF;

    -- 3. Búsqueda fuzzy por nombre (similarity de pg_trgm, umbral 0.4)
    IF v_prod_id IS NULL AND length(v_linea.nombre_proveedor) > 3 THEN
      SELECT p.id,
             similarity(p.nombre, v_linea.nombre_proveedor) * 100 AS sim
      INTO v_prod_id, v_confianza
      FROM productos p
      WHERE p.empresa_id = v_empresa_id
        AND similarity(p.nombre, v_linea.nombre_proveedor) > 0.4
      ORDER BY similarity(p.nombre, v_linea.nombre_proveedor) DESC
      LIMIT 1;

      IF FOUND THEN
        v_metodo := 'FUZZY';
        -- Si confianza > 80% se aplica; si es menor queda como sugerencia
        IF v_confianza < 80 THEN
          v_prod_id := NULL;  -- Dejar para homologación manual con sugerencia
        END IF;
      END IF;
    END IF;

    -- 4. Si se encontró producto, actualizar línea
    IF v_prod_id IS NOT NULL THEN
      UPDATE documentos_importados_lineas SET
        producto_id = v_prod_id,
        vinculado   = TRUE
      WHERE id = v_linea.id;
    END IF;

    RETURN QUERY SELECT
      v_linea.id,
      v_linea.codigo_proveedor,
      v_linea.nombre_proveedor,
      v_prod_id,
      (SELECT nombre FROM productos WHERE id = v_prod_id),
      v_metodo,
      v_confianza;
  END LOOP;

  -- Actualizar contadores en documento padre
  UPDATE documentos_importados SET
    lineas_mapeadas  = (SELECT COUNT(*) FROM documentos_importados_lineas
                        WHERE documento_id = p_importacion_id AND vinculado = TRUE),
    lineas_sin_mapear = (SELECT COUNT(*) FROM documentos_importados_lineas
                         WHERE documento_id = p_importacion_id AND vinculado = FALSE)
  WHERE id = p_importacion_id;
END;
$$;
```

### `approve_price_difference` — Aprobar diferencia de precio

```sql
CREATE OR REPLACE FUNCTION approve_price_difference(
  p_importacion_id  UUID,
  p_aprobador_id    UUID
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE importaciones_xml_sri SET
    aprobador_id        = p_aprobador_id,
    requiere_aprobacion = FALSE,
    procesado_at        = NOW()
  WHERE id = p_importacion_id
    AND empresa_id = (SELECT private.get_empresa_id())
    AND requiere_aprobacion = TRUE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Importación no encontrada o no requiere aprobación';
  END IF;
END;
$$;
```

---

## Manejo de Errores del WS SRI

Los errores del Web Service SRI se clasifican y manejan con lógica específica:

| Código de Error | Descripción | Acción |
|---|---|---|
| `CLAVE_NO_ENCONTRADA` | El comprobante no existe en el SRI | Verificar que los 49 dígitos sean correctos; puede que el proveedor no haya enviado al SRI |
| `COMPROBANTE_NO_AUTORIZADO` | El SRI aún no ha procesado/autorizado | Reintentar en 24h con cron job; guardar en cola de reintentos |
| `XML_INVALIDO` | El XML no cumple el XSD del SRI | Problema del proveedor; notificar al proveedor; no reintentar |
| `RUC_NO_ACTIVO` | El proveedor tiene RUC suspendido o dado de baja | Bloquear procesamiento; notificar al usuario; no pagar |
| `TIMEOUT` | El WS SRI no respondió en tiempo | Reintentar hasta 3 veces con backoff exponencial (1s, 2s, 4s) |
| `SERVICIO_NO_DISPONIBLE` | SRI en mantenimiento | Reintentar en 30 min; el SRI tiene ventanas de mantenimiento programadas |

### Tabla de cola de reintentos SRI

```sql
CREATE TABLE importacion_sri_reintentos (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  importacion_id    UUID NOT NULL REFERENCES importaciones_xml_sri(id),
  intento_numero    SMALLINT NOT NULL DEFAULT 1,
  programado_para   TIMESTAMPTZ NOT NULL,
  ejecutado_at      TIMESTAMPTZ,
  resultado         VARCHAR(30),    -- 'EXITOSO','FALLIDO','PENDIENTE'
  error_detalle     TEXT
);
```

---

## Validaciones de Seguridad

### Integridad del Emisor

```
Al importar un XML por clave de acceso:
  1. Extraer RUC del emisor: clave_acceso[10..22] (posición 11-23)
  2. Si el usuario seleccionó un proveedor manualmente:
       Verificar RUC del proveedor == RUC en XML
       Si no coincide → RAISE EXCEPTION 'El RUC del proveedor no coincide con el XML SRI'
  3. Si el proveedor no existe en PILAR:
       Crear automáticamente con RUC + razón social del XML
       Marcar como pendiente_verificacion = TRUE (usuario debe completar datos)
```

### Control de Duplicados

```
Duplicado exacto: mismo empresa_id + clave_acceso ya importado → bloquear
Posible duplicado: mismo establecimiento + punto + secuencial + proveedor
  pero diferente proceso de importación → alertar al usuario, no bloquear
```

### Plazo de Registro SRI

```
Verificar: fecha_emision del XML <= CURRENT_DATE
           fecha_emision del XML >= CURRENT_DATE - INTERVAL '5 years'

Si la fecha de emisión supera 5 años:
  RAISE EXCEPTION 'El SRI no acepta el registro de comprobantes
                   con más de 5 años de antigüedad'
```

### Verificación de RUC Activo

```
Antes de registrar como proveedor nuevo:
  → Consultar API SRI: https://srienlinea.sri.gob.ec/sri-en-linea/...
  → Si RUC suspendido o dado de baja: advertir al usuario
    (no bloquea, pero registra alerta)
```

---

## RLS e Índices

```sql
-- Índices para importaciones_xml_sri
CREATE INDEX idx_import_xml_empresa_estado
  ON importaciones_xml_sri (empresa_id, estado);
CREATE INDEX idx_import_xml_empresa_tipo
  ON importaciones_xml_sri (empresa_id, tipo_documento);
CREATE INDEX idx_import_xml_proveedor_ruc
  ON importaciones_xml_sri (empresa_id, proveedor_ruc);
CREATE INDEX idx_import_xml_fecha
  ON importaciones_xml_sri (empresa_id, fecha_emision DESC);
CREATE INDEX idx_import_xml_requiere_aprobacion
  ON importaciones_xml_sri (empresa_id, requiere_aprobacion)
  WHERE requiere_aprobacion = TRUE;

-- Índice para búsqueda fuzzy de productos (requiere extensión pg_trgm)
-- CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX idx_productos_nombre_trgm
  ON productos USING gin (nombre gin_trgm_ops);

-- Índice para tabla de reintentos
CREATE INDEX idx_reintentos_programado
  ON importacion_sri_reintentos (programado_para)
  WHERE resultado = 'PENDIENTE';
```
