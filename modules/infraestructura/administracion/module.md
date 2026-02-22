# Modulo de Administracion

## Estructura del Modulo

```
admin/
  ├── empresa/            # Datos empresa, RUC, establecimientos
  ├── login/              # Branding login: logo empresa, colores tema, textos personalizados, métodos auth habilitados
  ├── certificado/        # Carga certificado digital .p12
  ├── usuarios/           # Gestion de usuarios y roles
  ├── secuenciales/       # Config secuenciales por punto emision
  ├── pasarela-pago/      # Configurar Kushki y/o Paymentez
  ├── ecommerce/          # Configurar tiendas online
  ├── pos/                # Configurar cajas, modos POS, terminales
  ├── parametros/
  │     ├── impuestos/    # Catalogo IVA, ICE, IRBPNR (PARAMETRIZABLE)
  │     ├── retenciones/  # Catalogo codigos retencion (PARAMETRIZABLE)
  │     ├── formas-pago/  # Catalogo formas de pago (PARAMETRIZABLE)
  │     ├── sustento/     # Catalogo codigos sustento tributario
  │     ├── limites/      # Limites SRI (consumidor final, plazos, etc.)
  │     └── versiones-xsd/ # Versiones XSD activas por tipo documento
  └── sri/
        ├── ambiente/     # Configurar pruebas/produccion
        ├── logs/         # Historial comunicacion con SRI
        └── actualizaciones/ # Historial de cambios tributarios aplicados
```

## Sistema de Parametrizacion Tributaria (SRI)

```
╔══════════════════════════════════════════════════════════════════════════╗
║  El SRI de Ecuador cambia sus reglas tributarias frecuentemente.        ║
║  PILAR parametriza TODAS las variables tributarias para que puedan     ║
║  actualizarse sin modificar codigo. Los cambios se aplican desde       ║
║  PILAR Admin (app SaaS) y se propagan a todas las empresas.           ║
╚══════════════════════════════════════════════════════════════════════════╝
```

```sql
-- ============================================
-- CATALOGOS PARAMETRIZABLES DEL SRI
-- ============================================

-- Tarifas de IVA (el SRI las cambia: en 2024 paso de 12% a 15%)
catalogo_tarifas_iva
  id              UUID PK
  codigo          VARCHAR(4) NOT NULL  -- '0','2','3','4','5','6','7','8'
  descripcion     VARCHAR(100) NOT NULL -- 'IVA 15%', 'IVA 5%', 'IVA 0%'
  porcentaje      DECIMAL(5,2) NOT NULL -- 15.00, 5.00, 0.00
  vigente_desde   DATE NOT NULL        -- Fecha inicio de vigencia
  vigente_hasta   DATE                 -- NULL = vigente indefinidamente
  activo          BOOLEAN DEFAULT true
  UNIQUE(codigo, vigente_desde)

-- Codigos de retencion IVA
catalogo_retenciones_iva
  id              UUID PK
  codigo          VARCHAR(10) NOT NULL  -- '1','2','3','7','8','9','10'
  descripcion     VARCHAR(200) NOT NULL
  porcentaje      DECIMAL(5,2) NOT NULL -- 30.00, 70.00, 100.00
  vigente_desde   DATE NOT NULL
  vigente_hasta   DATE
  activo          BOOLEAN DEFAULT true

-- Codigos de retencion Renta
catalogo_retenciones_renta
  id              UUID PK
  codigo          VARCHAR(10) NOT NULL  -- '303','304','312','332',...
  descripcion     VARCHAR(300) NOT NULL
  porcentaje      DECIMAL(5,2) NOT NULL
  vigente_desde   DATE NOT NULL
  vigente_hasta   DATE
  activo          BOOLEAN DEFAULT true

-- Formas de pago SRI
catalogo_formas_pago
  id              UUID PK
  codigo          VARCHAR(2) NOT NULL  -- '01' a '21'
  descripcion     VARCHAR(100) NOT NULL
  activo          BOOLEAN DEFAULT true

-- Tipos de identificacion
catalogo_tipos_identificacion
  id              UUID PK
  codigo          VARCHAR(2) NOT NULL  -- '04','05','06','07','08'
  descripcion     VARCHAR(100) NOT NULL
  longitud        INTEGER              -- 13 para RUC, 10 para cedula
  validacion      VARCHAR(50)          -- 'ruc', 'cedula', 'pasaporte'
  activo          BOOLEAN DEFAULT true

-- Codigos de sustento tributario
catalogo_sustentos
  id              UUID PK
  codigo          VARCHAR(2) NOT NULL  -- '01' a '15'
  descripcion     VARCHAR(300) NOT NULL
  activo          BOOLEAN DEFAULT true

-- Tarifas ICE (cuando aplica)
catalogo_tarifas_ice
  id              UUID PK
  codigo          VARCHAR(10) NOT NULL
  descripcion     VARCHAR(200) NOT NULL
  tipo_tarifa     VARCHAR(10) NOT NULL  -- 'PORCENTUAL', 'ESPECIFICA'
  porcentaje      DECIMAL(5,2)
  valor_especifico DECIMAL(14,2)       -- Por unidad
  vigente_desde   DATE NOT NULL
  vigente_hasta   DATE
  activo          BOOLEAN DEFAULT true

-- ============================================
-- LIMITES Y REGLAS PARAMETRIZABLES
-- ============================================

parametros_sri
  id              UUID PK
  clave           VARCHAR(50) UNIQUE NOT NULL
  valor           VARCHAR(100) NOT NULL
  descripcion     TEXT
  vigente_desde   DATE NOT NULL
  vigente_hasta   DATE
  -- Ejemplos:
  -- 'CONSUMIDOR_FINAL_MONTO_MAX'    '50.00'    'Monto maximo sin datos comprador'
  -- 'RETENCION_PLAZO_DIAS'          '5'        'Dias habiles para emitir retencion'
  -- 'NC_PLAZO_ANIOS'                '5'        'Anios para emitir NC'
  -- 'LOTE_MAX_COMPROBANTES'         '50'       'Max comprobantes por lote'
  -- 'LOTE_MAX_KB'                   '500'      'Tamano max lote en KB'
  -- 'SBU'                           '460.00'   'Salario Basico Unificado vigente'
  -- 'APORTE_PERSONAL_IESS'          '9.45'     'Porcentaje aporte personal IESS'
  -- 'APORTE_PATRONAL_IESS'          '11.15'    'Porcentaje aporte patronal IESS'
  -- 'FONDOS_RESERVA_PCT'            '8.33'     'Porcentaje fondos de reserva'

-- Versiones XSD activas (para validacion)
versiones_xsd
  id              UUID PK
  tipo_documento  VARCHAR(2) NOT NULL  -- '01','03','04','05','06','07'
  version         VARCHAR(10) NOT NULL -- 'V2.1.0', 'V1.1.0', etc.
  activo          BOOLEAN DEFAULT true
  xsd_url         TEXT                 -- URL al esquema XSD
  fecha_activacion DATE
  UNIQUE(tipo_documento, version)

-- Historial de cambios tributarios (auditoria)
historial_cambios_tributarios
  id              UUID PK
  tabla           VARCHAR(50) NOT NULL  -- 'catalogo_tarifas_iva', etc.
  registro_id     UUID NOT NULL
  campo           VARCHAR(50) NOT NULL
  valor_anterior  TEXT
  valor_nuevo     TEXT
  motivo          TEXT                  -- 'Reforma Ley Org. Simplificacion 2024'
  usuario_id      UUID FK -> auth.users
  created_at      TIMESTAMPTZ DEFAULT now()

-- ============================================
-- POSICIONES FISCALES
-- Mapeo automatico de impuestos segun tipo de cliente/operacion
-- Basado en mejores practicas Odoo 19/SAP
-- ============================================
-- Una posicion fiscal define como se transforman los impuestos de un producto
-- al facturar a un tipo especifico de cliente. Ejemplo:
--   Producto con IVA 15% + Posicion "Exportador" → IVA 0%
--   Producto con IVA 15% + Posicion "RIMPE" → IVA 15% + Retencion automatica

-- Posiciones fiscales (mapeo de impuestos por tipo de cliente)
CREATE TABLE posiciones_fiscales (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  nombre          VARCHAR(100) NOT NULL,           -- 'Consumidor Final', 'Contribuyente Especial', 'Exportador'
  codigo          VARCHAR(20),
  descripcion     TEXT,
  auto_aplicar    BOOLEAN DEFAULT false,           -- Aplicar automaticamente segun tipo_identificacion
  tipo_identificacion VARCHAR(20),                 -- Si auto_aplicar: aplica a este tipo (CEDULA, RUC, PASAPORTE)
  activo          BOOLEAN DEFAULT true,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(empresa_id, nombre)
);

-- Mapeo de impuestos por posicion fiscal
CREATE TABLE posicion_fiscal_impuestos (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  posicion_fiscal_id UUID NOT NULL REFERENCES posiciones_fiscales(id) ON DELETE CASCADE,
  impuesto_origen_id UUID NOT NULL,                -- Impuesto original (IVA 15%)
  impuesto_destino_id UUID,                        -- Impuesto reemplazado (IVA 0%), NULL = exento
  cuenta_origen_id UUID REFERENCES cuentas_contables(id),  -- Cuenta contable original
  cuenta_destino_id UUID REFERENCES cuentas_contables(id), -- Cuenta contable destino (INC-CON-05)
  -- Permite redirigir el impuesto a una cuenta diferente (ej: IVA Retenido en vez de IVA Cobrado)
  codigo_retencion VARCHAR(10),                    -- Codigo retencion SRI si aplica
  porcentaje_retencion DECIMAL(5,2),               -- Porcentaje retencion si aplica
  sustento_tributario VARCHAR(10)                   -- Codigo sustento tributario del SRI
);

ALTER TABLE posiciones_fiscales ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON posiciones_fiscales
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

ALTER TABLE posicion_fiscal_impuestos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON posicion_fiscal_impuestos
  FOR ALL TO authenticated
  USING (posicion_fiscal_id IN (
    SELECT id FROM posiciones_fiscales WHERE empresa_id = (SELECT private.get_empresa_id())
  ));

-- NOTA: La tabla contactos requiere el campo:
--   posicion_fiscal_id UUID FK -> posiciones_fiscales
-- (ya incluido en la definicion de contactos)

-- Funcion para obtener parametro vigente
CREATE OR REPLACE FUNCTION get_parametro_sri(
  p_clave VARCHAR,
  p_fecha DATE DEFAULT CURRENT_DATE
) RETURNS VARCHAR
LANGUAGE sql STABLE AS $$
  SELECT valor FROM parametros_sri
  WHERE clave = p_clave
    AND vigente_desde <= p_fecha
    AND (vigente_hasta IS NULL OR vigente_hasta >= p_fecha)
  ORDER BY vigente_desde DESC
  LIMIT 1;
$$;

-- Funcion para obtener tarifa IVA vigente por codigo
CREATE OR REPLACE FUNCTION get_tarifa_iva(
  p_codigo VARCHAR,
  p_fecha DATE DEFAULT CURRENT_DATE
) RETURNS DECIMAL
LANGUAGE sql STABLE AS $$
  SELECT porcentaje FROM catalogo_tarifas_iva
  WHERE codigo = p_codigo AND activo = true
    AND vigente_desde <= p_fecha
    AND (vigente_hasta IS NULL OR vigente_hasta >= p_fecha)
  ORDER BY vigente_desde DESC
  LIMIT 1;
$$;
```

## Proceso de Actualizacion Tributaria

```
PROCESO DE ACTUALIZACION TRIBUTARIA:

1. SRI publica nueva normativa (ej: cambio tarifa IVA)
2. Equipo PILAR ingresa desde PILAR Admin:
   - Nueva tarifa con fecha de vigencia
   - La tarifa anterior se cierra (vigente_hasta = dia anterior)
3. El cambio se propaga automaticamente a TODAS las empresas
4. Se registra en historial_cambios_tributarios (auditoria)
5. Desde la fecha de vigencia, las nuevas facturas usan la tarifa nueva
6. Las facturas anteriores mantienen la tarifa con la que fueron emitidas

NOTA: Los catalogos son GLOBALES (no por empresa) ya que las reglas
del SRI aplican a todos. Los parametros como SBU, aportes IESS, etc.
tambien son globales y se actualizan centralmente.
```

## Multi-Moneda y Regionalizacion (P3 - future-proofing)

```sql
-- ============================================
-- MULTI-MONEDA Y REGIONALIZACION (P3)
-- ============================================

-- NOTA: Aunque estas tablas se documentan en la seccion Multi-Moneda (P3),
-- son requeridas desde la migracion 001_core_foundation.sql porque:
-- 1. provincias.pais_id referencia paises(id)
-- 2. catalogo_bancos referencia paises
-- 3. configuracion_empresa.moneda_principal referencia monedas
-- Por lo tanto, paises y monedas se crean en Core Foundation con datos
-- iniciales (249 paises ISO 3166, 228 monedas ISO 4217).
-- La funcionalidad avanzada de multi-moneda (tasas_cambio, conversion
-- automatica, revaluacion) si es P3.

-- Catalogo de paises (para regionalizacion futura)
CREATE TABLE paises (
  id VARCHAR(2) PRIMARY KEY,                -- ISO 3166-1 alpha-2: 'EC', 'CO', 'PE', 'CL'
  nombre VARCHAR(100) NOT NULL,
  nombre_corto VARCHAR(50),
  codigo_telefonico VARCHAR(5),             -- '+593', '+57'
  moneda_id VARCHAR(3),                     -- ISO 4217: 'USD', 'COP', 'PEN', 'CLP'
  formato_identificacion VARCHAR(200),      -- regex para validar RUC/NIT/RUT
  formato_direccion TEXT                    -- template de formato de direccion
);

-- Catalogo de monedas (para multi-moneda futura)
CREATE TABLE monedas (
  id VARCHAR(3) PRIMARY KEY,                -- ISO 4217: 'USD', 'EUR', 'COP'
  nombre VARCHAR(50) NOT NULL,
  simbolo VARCHAR(5) NOT NULL,              -- '$', '€', 'S/.'
  decimales INTEGER DEFAULT 2,
  activa BOOLEAN DEFAULT true
);

-- Tasas de cambio (historicas)
CREATE TABLE tasas_cambio (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  moneda_origen VARCHAR(3) REFERENCES monedas(id) NOT NULL,
  moneda_destino VARCHAR(3) REFERENCES monedas(id) NOT NULL,
  tasa DECIMAL(18,8) NOT NULL,
  fecha DATE NOT NULL,
  fuente VARCHAR(50) DEFAULT 'MANUAL',      -- MANUAL, BCE (Banco Central), API
  UNIQUE(moneda_origen, moneda_destino, fecha)
);

-- NOTA: Ecuador usa USD, pero esto permite:
-- 1. Importaciones/exportaciones con proveedores en EUR, CNY, etc.
-- 2. Expansion futura a Colombia (COP), Peru (PEN), Chile (CLP)
-- 3. El campo moneda en facturas referencia esta tabla
-- 4. Diferencias de cambio se registran automaticamente en contabilidad
```

---

## Configuración de la Empresa

### Tabla: `configuracion_empresa`

```sql
CREATE TABLE configuracion_empresa (
  empresa_id UUID PRIMARY KEY REFERENCES empresas(id),
  -- Branding general
  logo_url TEXT,
  logo_secundario_url TEXT,
  color_primario VARCHAR(7) DEFAULT '#1976D2',    -- HEX
  color_secundario VARCHAR(7) DEFAULT '#424242',
  fuente_ui VARCHAR(50) DEFAULT 'Roboto',
  -- Branding de pantalla de inicio de sesión
  login_titulo VARCHAR(100),
  login_subtitulo VARCHAR(200),
  login_logo_url TEXT,
  login_bg_url TEXT,                              -- Fondo personalizado pantalla login
  login_metodos_auth JSONB DEFAULT '["email"]',  -- ["email","google","magic_link"]
  -- Preferencias contables
  periodo_contable_inicio INTEGER DEFAULT 1,      -- Mes de inicio del año fiscal (1=enero, 4=abril)
  metodo_valoracion VARCHAR(10) DEFAULT 'CPP' CHECK (metodo_valoracion IN ('CPP','FIFO')),
  moneda_funcional VARCHAR(3) DEFAULT 'USD',
  -- Configuración SRI
  ambiente_sri SMALLINT DEFAULT 1 CHECK (ambiente_sri IN (1, 2)),  -- 1=Pruebas, 2=Produccion
  punto_emision_defecto UUID REFERENCES puntos_emision(id),
  -- Notificaciones y alertas
  email_notif_sri TEXT,                           -- Destinatario de alertas SRI críticas
  notif_vencimiento_facturas BOOLEAN DEFAULT true,
  dias_alerta_vencimiento INTEGER DEFAULT 3,
  -- Límites de negocio
  max_descuento_sin_aprobacion DECIMAL(5,2) DEFAULT 10.00,  -- 10%
  limite_cxc_dias_vencer INTEGER DEFAULT 30,
  -- Reservas (configurable aquí para centralizar)
  max_renovaciones_reserva INTEGER DEFAULT 3,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- RLS: Solo el admin de la empresa puede leer/modificar su configuración
ALTER TABLE configuracion_empresa ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON configuracion_empresa FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));
```

### Tabla: `integraciones_externas`

```sql
CREATE TABLE integraciones_externas (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id UUID NOT NULL REFERENCES empresas(id),
  tipo VARCHAR(30) NOT NULL CHECK (tipo IN (
    'RESEND','WHATSAPP','TELEGRAM',
    'KUSHKI','PAYMENTEZ','PAYPHONE',
    'WOOCOMMERCE','N8N','CUSTOM'
  )),
  nombre VARCHAR(100) NOT NULL,
  api_key_enc TEXT,                              -- Encriptado en Supabase Vault
  config JSONB DEFAULT '{}',                    -- Configuración específica por tipo
  activa BOOLEAN DEFAULT true,
  estado VARCHAR(20) DEFAULT 'PENDIENTE' CHECK (estado IN ('OK','ERROR','PENDIENTE')),
  ultimo_test TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(empresa_id, tipo, nombre)
);

ALTER TABLE integraciones_externas ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON integraciones_externas FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE INDEX idx_integraciones_empresa ON integraciones_externas(empresa_id, tipo, activa);
```

**Ejemplos de config por tipo de integración:**

```json
// RESEND
{ "from_email": "facturacion@empresa.com", "reply_to": "contabilidad@empresa.com" }

// WHATSAPP (Meta Cloud API)
{ "phone_number_id": "...", "waba_id": "..." }

// KUSHKI
{ "ambiente": "produccion", "currency": "USD" }

// WOOCOMMERCE
{ "url_tienda": "https://tienda.empresa.com", "webhook_secret": "..." }

// N8N
{ "webhook_base_url": "https://n8n.empresa.com/webhook", "credencial_id": "..." }
```

---

## RPCs de Administración

```sql
-- ══════════════════════════════════════════════════════════════
-- RPC: Probar conexión con una integración externa
-- Ejecuta un health-check o ping a la API configurada.
-- Actualiza estado y ultimo_test en integraciones_externas.
-- ══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION test_integration(
  p_integracion_id UUID
) RETURNS JSONB  -- {ok: boolean, mensaje: TEXT, latencia_ms: INTEGER}
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_integ integraciones_externas%ROWTYPE;
  v_ok BOOLEAN := false;
  v_mensaje TEXT;
  v_ts TIMESTAMPTZ := clock_timestamp();
BEGIN
  SELECT * INTO v_integ FROM integraciones_externas
  WHERE id = p_integracion_id AND empresa_id = (SELECT private.get_empresa_id());
  IF v_integ.id IS NULL THEN RAISE EXCEPTION 'Integración no encontrada'; END IF;

  -- El test real es delegado a Edge Function test-integration
  -- Esta RPC registra el resultado y actualiza el estado
  -- (La Edge Function llama a esta RPC con el resultado)
  v_ok := true;  -- Placeholder: la EF actualiza directamente
  v_mensaje := 'Test iniciado. Ver logs en Edge Functions.';

  UPDATE integraciones_externas SET
    ultimo_test = NOW(),
    estado = 'PENDIENTE'
  WHERE id = p_integracion_id;

  RETURN jsonb_build_object(
    'ok', v_ok,
    'mensaje', v_mensaje,
    'integracion', v_integ.nombre,
    'tipo', v_integ.tipo
  );
END;
$$;

-- ══════════════════════════════════════════════════════════════
-- RPC: Obtener configuración completa de la empresa
-- Retorna configuracion_empresa + módulos activos + integraciones
-- SIN campos sensibles (api_key_enc, tokens)
-- ══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION get_company_config(
  p_empresa_id UUID
) RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER AS $$
DECLARE
  v_config JSONB;
BEGIN
  SELECT row_to_json(ce.*)::JSONB INTO v_config
  FROM configuracion_empresa ce
  WHERE ce.empresa_id = p_empresa_id;

  -- Añadir integraciones activas (sin api_key_enc)
  v_config := v_config || jsonb_build_object(
    'integraciones', (
      SELECT jsonb_agg(jsonb_build_object(
        'tipo', tipo, 'nombre', nombre, 'activa', activa, 'estado', estado
      ))
      FROM integraciones_externas
      WHERE empresa_id = p_empresa_id AND activa = true
    )
  );

  RETURN v_config;
END;
$$;

-- ══════════════════════════════════════════════════════════════
-- RPC: Actualizar branding y preferencias de la empresa
-- Solo campos permitidos (no modifica ambiente_sri directamente)
-- ══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION update_company_branding(
  p_empresa_id UUID,
  p_config JSONB
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO configuracion_empresa (empresa_id,
    logo_url, logo_secundario_url, color_primario, color_secundario, fuente_ui,
    login_titulo, login_subtitulo, login_logo_url, login_bg_url, login_metodos_auth,
    dias_alerta_vencimiento, max_descuento_sin_aprobacion,
    notif_vencimiento_facturas, email_notif_sri, updated_at)
  VALUES (p_empresa_id,
    p_config->>'logo_url', p_config->>'logo_secundario_url',
    COALESCE(p_config->>'color_primario', '#1976D2'),
    COALESCE(p_config->>'color_secundario', '#424242'),
    COALESCE(p_config->>'fuente_ui', 'Roboto'),
    p_config->>'login_titulo', p_config->>'login_subtitulo',
    p_config->>'login_logo_url', p_config->>'login_bg_url',
    COALESCE(p_config->'login_metodos_auth', '["email"]'::JSONB),
    COALESCE((p_config->>'dias_alerta_vencimiento')::INTEGER, 3),
    COALESCE((p_config->>'max_descuento_sin_aprobacion')::DECIMAL, 10.00),
    COALESCE((p_config->>'notif_vencimiento_facturas')::BOOLEAN, true),
    p_config->>'email_notif_sri',
    NOW()
  )
  ON CONFLICT (empresa_id) DO UPDATE SET
    logo_url = EXCLUDED.logo_url,
    logo_secundario_url = EXCLUDED.logo_secundario_url,
    color_primario = EXCLUDED.color_primario,
    color_secundario = EXCLUDED.color_secundario,
    fuente_ui = EXCLUDED.fuente_ui,
    login_titulo = EXCLUDED.login_titulo,
    login_subtitulo = EXCLUDED.login_subtitulo,
    login_logo_url = EXCLUDED.login_logo_url,
    login_bg_url = EXCLUDED.login_bg_url,
    login_metodos_auth = EXCLUDED.login_metodos_auth,
    dias_alerta_vencimiento = EXCLUDED.dias_alerta_vencimiento,
    max_descuento_sin_aprobacion = EXCLUDED.max_descuento_sin_aprobacion,
    notif_vencimiento_facturas = EXCLUDED.notif_vencimiento_facturas,
    email_notif_sri = EXCLUDED.email_notif_sri,
    updated_at = NOW();

  RETURN get_company_config(p_empresa_id);
END;
$$;
```

---

## Gestión de Certificados Digitales

El certificado `.p12` es requerido por el SRI para la firma XAdES-BES de documentos electrónicos.

```
Flujo de carga del certificado digital:
1. Admin sube archivo .p12 desde Administración → Certificado Digital
2. Flutter envía el archivo a Edge Function upload-certificate:
   - Valida formato .p12
   - Parsea fecha de vencimiento del certificado
   - Sube a Supabase Storage: bucket privado 'certificados'
     Ruta: certificados/{empresa_id}/firma.p12
   - Encripta la clave del certificado con Supabase Vault
   - Guarda referencia en empresas.certificado_url + certificado_vence
3. Al firmar documentos (Edge Function sign-sri-document):
   - Descarga el .p12 desde Storage (acceso privado)
   - Recupera la clave desde Vault
   - Firma el XML con ec-sri-invoice-signer (XAdES-BES)
   - NUNCA expone el .p12 ni la clave al cliente Flutter
```

```sql
-- Campos en tabla empresas (ya deben existir, agregar si faltan):
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS certificado_url TEXT;
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS certificado_vence DATE;
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS certificado_vault_key_id TEXT;
  -- ID de la clave en Supabase Vault (vault.secrets)

-- Alerta automática de vencimiento
-- Cron diario: verificar certificados que vencen en <= 30 días
-- Notifica a email_notif_sri configurado en configuracion_empresa
-- Edge Function: check-certificate-expiry (cron diario)
```

```typescript
// Edge Function: upload-certificate
// Ruta: /functions/v1/upload-certificate
// Método: POST (multipart/form-data)
// Headers: Authorization: Bearer <JWT>
// Body: { file: .p12, password: string }
// Respuesta: { ok: boolean, vence: string }
//
// Seguridad:
// - verify_jwt: true (solo usuarios autenticados y admin de la empresa)
// - El .p12 nunca retorna al cliente
// - La clave se guarda SOLO en Vault, nunca en texto plano en PostgreSQL
```

---

## Casos de Uso

### Actores

| Actor | Descripcion |
|-------|-------------|
| **Administrador** | Configura empresa, usuarios, parámetros del sistema, plan de cuentas |
| **Gerente** | Consulta reportes y dashboards |

### Casos de Uso - Administracion

| ID | Caso de Uso | Actor | Prioridad |
|----|-------------|-------|-----------|
| A01 | Configurar empresa (nombre, identificacion fiscal, establecimientos) | Administrador | **Critica** |
| A02 | Cargar certificado de firma digital | Administrador | **Critica** |
| A03 | Gestionar usuarios y roles | Administrador | Alta |
| A04 | Configurar secuenciales de documentos | Administrador | Alta |
| A05 | Configurar ambiente de facturacion electronica (pruebas/produccion) | Administrador | Alta |
| A06 | Gestionar catalogo de retenciones / impuestos | Administrador | Alta |
| A07 | Configurar pasarela de pagos | Administrador | Alta |
| A08 | Configurar cuentas bancarias | Administrador | Alta |

> **A01/A02/A05/A06 Ecuador** (RUC, puntos de emisión, .p12, ambiente SRI, retenciones IVA+Renta): Ver [`modules/extensiones/facturacion_ec/flujos-sri.md`](../../extensiones/facturacion_ec/flujos-sri.md).
> **A07 Ecuador** (Kushki, Paymentez, PayPhone): Ver [`modules/extensiones/pagos-online/integraciones/pasarelas-ecuador.md`](../../extensiones/pagos-online/integraciones/pasarelas-ecuador.md).

