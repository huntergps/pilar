# Módulo Tributación (Core #10)

> **Módulo Core #10** — Standalone (sin dependencias obligatorias entre módulos Core)
> Contabilidad (#8) requerida solo para F-101 y EEFF Supercias. Opcional: Facturación (#4), Compras (#6), Inventario (#7), RRHH (#14)

Centraliza el cumplimiento tributario Ecuador: generación y presentación de ATS mensual, Formularios 103/104/101, y Estados Financieros para Supercias (EEFF TXT). Lee datos de otros módulos Core via Module Service Bus — entrega datos parciales si algún módulo no está activo.

**¿Por qué módulo separado y no en Contabilidad?**
- Los informes SRI requieren datos de Facturación + Compras + Inventario + Contabilidad (cross-module)
- Contabilidad queda como contabilidad pura (plan cuentas + asientos)
- Patrón Odoo Enterprise: `l10n_ec_reports` y `l10n_ec_reports_ats` son módulos add-on separados
- Degradación elegante: con solo Facturación activo → ATS genera solo sección ventas
- Futuros informes (F-101, RDEP, SCVS EEFF) pertenecen naturalmente aquí

---

## Navegación

Prefijo de pantallas: `T-TRI`

```
/tributacion/                    → T-TRI-01: Dashboard tributario
/tributacion/declaraciones/      → T-TRI-02: Historial declaraciones
/tributacion/ats/                → T-TRI-03: Generación ATS mensual
  /tributacion/ats/:id/preview   → Preview ATS antes de generar
/tributacion/formularios/104     → T-TRI-04: Formulario 104 IVA
/tributacion/formularios/103     → T-TRI-05: Formulario 103 Retenciones
/tributacion/formularios/101     → T-TRI-06: Formulario 101 IR Anual
/tributacion/scvs/               → T-TRI-07: EEFF Supercias
/tributacion/rdep/               → T-TRI-08: RDEP Relación de Dependencia
```

### T-TRI-01 Dashboard Tributario

- Cards de próximos vencimientos SRI (F-103, F-104 según tabla de vencimientos SRI por noveno dígito RUC)
- Estado de declaraciones del mes actual (pendiente / generada / presentada)
- Alertas: declaraciones vencidas no presentadas
- Calendario tributario del año con fechas por tipo de declarante (mensual / semestral)
- KPIs: IVA cobrado vs IVA pagado (crédito tributario del mes), total retenciones emitidas

### T-TRI-03 Generador ATS

- Selector año/mes
- Botón "Calcular" → llama `get_ats_data()` y muestra preview con totales por sección
- Sección VENTAS: número de facturas, monto base, IVA
- Sección COMPRAS: número de facturas proveedor, retenciones emitidas
- Indicadores de módulos activos que alimentan el ATS
- Botón "Generar ZIP" → llama Edge Function `generate-ats` → descarga ZIP o guarda en Storage
- Historial de generaciones anteriores

### T-TRI-04 Formulario 104

- Selector período (mes/año) — o semestral para contribuyentes especiales
- Preview de casillas calculadas automáticamente
- Campos agrupados por sección del F-104: ventas, compras, liquidación IVA
- Botón "Generar PDF" o "Exportar datos para SRI Online"

### T-TRI-05 Formulario 103

- Selector período
- Tabla de retenciones agrupadas por código de retención
- Totales de base imponible y valor retenido
- Botón "Generar PDF"

### T-TRI-06 Formulario 101 IR Anual

- Selector año fiscal
- Estado de resultados proyectado: ingresos, costos, gastos, utilidad antes de IR
- Cálculo de base imponible, participación trabajadores 15%, IR 22/25%
- Solo disponible si módulo Contabilidad está activo

### T-TRI-07 EEFF Supercias

- Selector año fiscal
- Balances: Balance General + Estado de Resultados en formato SCVS
- Exportar archivo TXT con estructura SCVS para carga en portal
- Guarda en Storage y registra en `declaraciones_tributarias`

### T-TRI-08 RDEP Relación de Dependencia

- Selector año fiscal
- Lista de empleados con datos de ingresos y retenciones del año
- Exportar archivo XML para carga en SRI
- Solo disponible si módulo RRHH está activo

---

## Modelo de Datos

### Historial de declaraciones

```sql
-- Historial de declaraciones generadas/presentadas
CREATE TABLE declaraciones_tributarias (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id          UUID NOT NULL REFERENCES empresas(id),
  tipo                VARCHAR(20) NOT NULL
                        CHECK (tipo IN ('ATS','F_103','F_104','F_101','SCVS_EEFF','RDEP')),
  anio                INTEGER NOT NULL CHECK (anio >= 2020),
  mes                 INTEGER CHECK (mes BETWEEN 1 AND 12),  -- NULL para anuales (F-101, SCVS)
  estado              VARCHAR(20) NOT NULL DEFAULT 'BORRADOR'
                        CHECK (estado IN ('BORRADOR','GENERADA','PRESENTADA','ENVIADA_ONLINE','ERROR')),
  fecha_generacion    TIMESTAMPTZ,
  fecha_presentacion  TIMESTAMPTZ,
  archivo_url         TEXT,          -- URL Supabase Storage (ZIP para ATS, PDF para formularios)
  archivo_nombre      TEXT,
  datos_resumen       JSONB,         -- Totales clave al momento de generacion (no todo el detalle)
  numero_registro     TEXT,          -- Numero asignado por SRI/SCVS al presentar
  presentado_por      UUID REFERENCES auth.users(id),
  observaciones       TEXT,
  error_detalle       TEXT,          -- En caso de estado ERROR
  created_at          TIMESTAMPTZ DEFAULT NOW(),
  updated_at          TIMESTAMPTZ DEFAULT NOW()
  -- Unicidad garantizada por índices parciales (ver sección Índices):
  -- mensuales: (empresa_id, tipo, anio, mes) WHERE mes IS NOT NULL
  -- anuales:   (empresa_id, tipo, anio)      WHERE mes IS NULL
);
```

### Configuracion tributaria de la empresa

```sql
-- Configuracion de vencimientos tributarios por empresa
-- (fecha limite segun digito RUC y tipo contribuyente)
CREATE TABLE configuracion_tributaria (
  id                        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id                UUID NOT NULL REFERENCES empresas(id),
  tipo_contribuyente        VARCHAR(30) NOT NULL DEFAULT 'PERSONA_NATURAL'
                              CHECK (tipo_contribuyente IN (
                                'PERSONA_NATURAL',
                                'SOCIEDAD',
                                'CONTRIBUYENTE_ESPECIAL'
                              )),
  noveno_digito_ruc         INTEGER NOT NULL
                              CHECK (noveno_digito_ruc BETWEEN 0 AND 9),
  regimen_iva               VARCHAR(30) NOT NULL DEFAULT 'MENSUAL'
                              CHECK (regimen_iva IN (
                                'MENSUAL',
                                'SEMESTRAL_ENE_JUN',
                                'SEMESTRAL_JUL_DIC'
                              )),
  obligado_contabilidad     BOOLEAN NOT NULL DEFAULT true,
  activo                    BOOLEAN NOT NULL DEFAULT true,
  created_at                TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(empresa_id)
);
```

---

## Indices

```sql
-- Unicidad mensual: un registro por (empresa, tipo, año, mes) para F-103, F-104, ATS
CREATE UNIQUE INDEX idx_decl_trib_mensual ON declaraciones_tributarias (empresa_id, tipo, anio, mes)
  WHERE mes IS NOT NULL;

-- Unicidad anual: un registro por (empresa, tipo, año) para F-101, SCVS_EEFF, RDEP
-- (UNIQUE normal no funciona con mes=NULL porque NULL != NULL en SQL)
CREATE UNIQUE INDEX idx_decl_trib_anual ON declaraciones_tributarias (empresa_id, tipo, anio)
  WHERE mes IS NULL;

CREATE INDEX idx_decl_trib_empresa_estado ON declaraciones_tributarias(empresa_id, estado);
CREATE INDEX idx_decl_trib_empresa_fecha  ON declaraciones_tributarias(empresa_id, fecha_generacion DESC);
CREATE INDEX idx_config_trib_empresa      ON configuracion_tributaria(empresa_id);
```

---

## Row Level Security

```sql
-- declaraciones_tributarias
ALTER TABLE declaraciones_tributarias ENABLE ROW LEVEL SECURITY;

CREATE POLICY "trib_decl_empresa" ON declaraciones_tributarias
  TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()))
  WITH CHECK (empresa_id = (SELECT private.get_empresa_id()));

-- configuracion_tributaria
ALTER TABLE configuracion_tributaria ENABLE ROW LEVEL SECURITY;

CREATE POLICY "trib_config_empresa" ON configuracion_tributaria
  TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()))
  WITH CHECK (empresa_id = (SELECT private.get_empresa_id()));
```

---

## Funciones RPC

### get_form_104_data — Datos para Formulario 104 IVA

Lee ventas desde Facturación y compras desde Compras con guards de activación. Retorna
estructura lista para renderizar las casillas del F-104 y calcular la liquidación de IVA.

```sql
CREATE OR REPLACE FUNCTION get_form_104_data(
  p_empresa_id UUID,
  p_anio       INT,
  p_mes        INT
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_facturacion_active BOOLEAN;
  v_compras_active     BOOLEAN;
  v_fecha_desde        DATE;
  v_fecha_hasta        DATE;
  -- Ventas
  v_ventas_iva0        DECIMAL(14,2) := 0;
  v_ventas_iva5        DECIMAL(14,2) := 0;
  v_ventas_iva15       DECIMAL(14,2) := 0;
  v_iva_cobrado        DECIMAL(14,2) := 0;
  -- Compras
  v_compras_iva0       DECIMAL(14,2) := 0;
  v_compras_iva5       DECIMAL(14,2) := 0;
  v_compras_iva15      DECIMAL(14,2) := 0;
  v_credito_tributario DECIMAL(14,2) := 0;
  v_iva_pagado         DECIMAL(14,2) := 0;
  -- Liquidacion
  v_iva_causado        DECIMAL(14,2) := 0;
  v_credito_anterior   DECIMAL(14,2) := 0;
  v_impuesto_pagar     DECIMAL(14,2) := 0;
BEGIN
  v_fecha_desde := make_date(p_anio, p_mes, 1);
  v_fecha_hasta := (v_fecha_desde + INTERVAL '1 month - 1 day')::DATE;

  -- Verificar modulos activos
  SELECT EXISTS (
    SELECT 1 FROM modulos_empresa
    WHERE empresa_id = p_empresa_id
      AND modulo_id = 'facturacion'
      AND activo = true
  ) INTO v_facturacion_active;

  SELECT EXISTS (
    SELECT 1 FROM modulos_empresa
    WHERE empresa_id = p_empresa_id
      AND modulo_id = 'compras'
      AND activo = true
  ) INTO v_compras_active;

  -- SECCION VENTAS (solo si Facturacion activo)
  IF v_facturacion_active THEN
    SELECT
      COALESCE(SUM(CASE WHEN fl.porcentaje_iva = 0  THEN fl.subtotal ELSE 0 END), 0),
      COALESCE(SUM(CASE WHEN fl.porcentaje_iva = 5  THEN fl.subtotal ELSE 0 END), 0),
      COALESCE(SUM(CASE WHEN fl.porcentaje_iva = 15 THEN fl.subtotal ELSE 0 END), 0),
      COALESCE(SUM(fl.valor_iva), 0)
    INTO v_ventas_iva0, v_ventas_iva5, v_ventas_iva15, v_iva_cobrado
    FROM facturas f
    JOIN factura_lineas fl ON fl.factura_id = f.id
    WHERE f.empresa_id = p_empresa_id
      AND f.estado = 'AUTORIZADA'
      AND f.fecha_emision BETWEEN v_fecha_desde AND v_fecha_hasta;
  END IF;

  -- SECCION COMPRAS (solo si Compras activo)
  IF v_compras_active THEN
    SELECT
      COALESCE(SUM(CASE WHEN fpl.porcentaje_iva = 0  THEN fpl.subtotal ELSE 0 END), 0),
      COALESCE(SUM(CASE WHEN fpl.porcentaje_iva = 5  THEN fpl.subtotal ELSE 0 END), 0),
      COALESCE(SUM(CASE WHEN fpl.porcentaje_iva = 15 THEN fpl.subtotal ELSE 0 END), 0),
      COALESCE(SUM(fpl.valor_iva), 0)
    INTO v_compras_iva0, v_compras_iva5, v_compras_iva15, v_iva_pagado
    FROM facturas_proveedor fp
    JOIN factura_proveedor_lineas fpl ON fpl.factura_proveedor_id = fp.id
    WHERE fp.empresa_id = p_empresa_id
      AND fp.estado = 'CONTABILIZADA'
      AND fp.fecha_emision BETWEEN v_fecha_desde AND v_fecha_hasta;

    -- Credito tributario = IVA pagado en compras
    v_credito_tributario := v_iva_pagado;
  END IF;

  -- Liquidacion
  v_iva_causado    := v_iva_cobrado;
  v_impuesto_pagar := GREATEST(0, v_iva_causado - v_credito_tributario - v_credito_anterior);

  RETURN jsonb_build_object(
    'periodo', jsonb_build_object('anio', p_anio, 'mes', p_mes),
    'modulos_activos', jsonb_build_object(
      'facturacion', v_facturacion_active,
      'compras',     v_compras_active
    ),
    'ventas', jsonb_build_object(
      'base_iva0',   v_ventas_iva0,
      'base_iva5',   v_ventas_iva5,
      'base_iva15',  v_ventas_iva15,
      'iva_cobrado', v_iva_cobrado
    ),
    'compras', jsonb_build_object(
      'base_iva0',          v_compras_iva0,
      'base_iva5',          v_compras_iva5,
      'base_iva15',         v_compras_iva15,
      'iva_pagado',         v_iva_pagado,
      'credito_tributario', v_credito_tributario
    ),
    'liquidacion', jsonb_build_object(
      'iva_causado',              v_iva_causado,
      'credito_mes_anterior',     v_credito_anterior,
      'impuesto_pagar',           v_impuesto_pagar,
      'credito_proximo_mes',      GREATEST(0, v_credito_tributario - v_iva_causado)
    )
  );
END;
$$;
```

---

### get_form_103_data — Datos para Formulario 103 Retenciones en la Fuente

Lee retenciones emitidas desde el módulo Compras. Si Compras no está activo, retorna
estructura vacía con flag indicador. Las retenciones se agrupan por código para mapeo
directo a las casillas del F-103.

```sql
CREATE OR REPLACE FUNCTION get_form_103_data(
  p_empresa_id UUID,
  p_anio       INT,
  p_mes        INT
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_compras_active BOOLEAN;
  v_fecha_desde    DATE;
  v_fecha_hasta    DATE;
  v_retenciones    JSONB := '[]'::JSONB;
  v_total_base     DECIMAL(14,2) := 0;
  v_total_retenido DECIMAL(14,2) := 0;
BEGIN
  v_fecha_desde := make_date(p_anio, p_mes, 1);
  v_fecha_hasta := (v_fecha_desde + INTERVAL '1 month - 1 day')::DATE;

  SELECT EXISTS (
    SELECT 1 FROM modulos_empresa
    WHERE empresa_id = p_empresa_id
      AND modulo_id = 'compras'
      AND activo = true
  ) INTO v_compras_active;

  IF v_compras_active THEN
    -- CTE intermedia para evitar agregados anidados (SUM dentro de jsonb_agg no es válido en PostgreSQL)
    WITH grupos AS (
      SELECT rl.codigo_retencion, rl.descripcion, rl.porcentaje_retencion,
             SUM(rl.base_imponible)  AS base_imponible,
             SUM(rl.valor_retenido)  AS valor_retenido
      FROM retenciones r
      JOIN retencion_lineas rl ON rl.retencion_id = r.id
      WHERE r.empresa_id = p_empresa_id
        AND r.estado = 'AUTORIZADA'
        AND r.fecha_emision BETWEEN v_fecha_desde AND v_fecha_hasta
      GROUP BY rl.codigo_retencion, rl.descripcion, rl.porcentaje_retencion
    )
    SELECT
      jsonb_agg(jsonb_build_object(
        'codigo_retencion', codigo_retencion,
        'descripcion',      descripcion,
        'base_imponible',   base_imponible,
        'porcentaje',       porcentaje_retencion,
        'valor_retenido',   valor_retenido
      ) ORDER BY codigo_retencion),
      COALESCE(SUM(base_imponible),  0),
      COALESCE(SUM(valor_retenido),  0)
    INTO v_retenciones, v_total_base, v_total_retenido
    FROM grupos;
  END IF;

  RETURN jsonb_build_object(
    'periodo', jsonb_build_object('anio', p_anio, 'mes', p_mes),
    'modulos_activos', jsonb_build_object('compras', v_compras_active),
    'retenciones_por_codigo', COALESCE(v_retenciones, '[]'::JSONB),
    'totales', jsonb_build_object(
      'base_imponible_total', v_total_base,
      'valor_retenido_total', v_total_retenido
    )
  );
END;
$$;
```

---

### get_ats_data — Datos completos para el ATS mensual

Agrega datos de Facturación, Compras y Retenciones. Genera la estructura JSONB que
la Edge Function `generate-ats` transforma a XML ISO-8859-1 con el esquema del SRI.
Cada sección solo se incluye si el módulo correspondiente está activo.

```sql
CREATE OR REPLACE FUNCTION get_ats_data(
  p_empresa_id UUID,
  p_anio       INT,
  p_mes        INT
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_facturacion_active BOOLEAN;
  v_compras_active     BOOLEAN;
  v_inventario_active  BOOLEAN;
  v_fecha_desde        DATE;
  v_fecha_hasta        DATE;
  v_ventas             JSONB := '[]'::JSONB;
  v_compras            JSONB := '[]'::JSONB;
  v_retenciones        JSONB := '[]'::JSONB;
  v_total_ventas       DECIMAL(14,2) := 0;
  v_empresa            RECORD;
BEGIN
  v_fecha_desde := make_date(p_anio, p_mes, 1);
  v_fecha_hasta := (v_fecha_desde + INTERVAL '1 month - 1 day')::DATE;

  -- Verificar modulos activos
  SELECT EXISTS (
    SELECT 1 FROM modulos_empresa
    WHERE empresa_id = p_empresa_id AND modulo_id = 'facturacion' AND activo = true
  ) INTO v_facturacion_active;

  SELECT EXISTS (
    SELECT 1 FROM modulos_empresa
    WHERE empresa_id = p_empresa_id AND modulo_id = 'compras' AND activo = true
  ) INTO v_compras_active;

  SELECT EXISTS (
    SELECT 1 FROM modulos_empresa
    WHERE empresa_id = p_empresa_id AND modulo_id = 'inventario' AND activo = true
  ) INTO v_inventario_active;

  -- Datos empresa
  SELECT ruc, razon_social, tipo_contribuyente
  INTO v_empresa
  FROM empresas
  WHERE id = p_empresa_id;

  -- SECCION VENTAS: facturas emitidas tipo 01 (una fila por cliente)
  IF v_facturacion_active THEN
    SELECT
      COALESCE(SUM(f.total), 0)
    INTO v_total_ventas
    FROM facturas f
    WHERE f.empresa_id = p_empresa_id
      AND f.estado = 'AUTORIZADA'
      AND f.fecha_emision BETWEEN v_fecha_desde AND v_fecha_hasta;

    WITH ventas_cli AS (
      SELECT c.tipo_identificacion, c.numero_identificacion,
             COUNT(DISTINCT f.id)                                                              AS n_comprobantes,
             COALESCE(SUM(CASE WHEN fl.porcentaje_iva = 0 THEN fl.subtotal ELSE 0 END), 0)   AS base_iva0,
             COALESCE(SUM(CASE WHEN fl.porcentaje_iva > 0 THEN fl.subtotal ELSE 0 END), 0)   AS base_grav,
             COALESCE(SUM(fl.valor_iva), 0)                                                   AS monto_iva
      FROM facturas f
      JOIN contactos c ON c.id = f.cliente_id
      JOIN factura_lineas fl ON fl.factura_id = f.id
      WHERE f.empresa_id = p_empresa_id
        AND f.estado = 'AUTORIZADA'
        AND f.fecha_emision BETWEEN v_fecha_desde AND v_fecha_hasta
      GROUP BY c.tipo_identificacion, c.numero_identificacion
    )
    SELECT jsonb_agg(jsonb_build_object(
        'tpIdCliente',        tipo_identificacion,
        'idCliente',          numero_identificacion,
        'parteRel',           'NO',
        'tipoComprobante',    '01',
        'numeroComprobantes', n_comprobantes,
        'baseNoGraIva',       base_iva0,
        'baseImponible',      base_grav,
        'baseImpGrav',        base_grav,
        'montoIva',           monto_iva,
        'valorRetIva',        0,
        'valorRetRenta',      0
      ))
    INTO v_ventas
    FROM ventas_cli;
  END IF;

  -- SECCION COMPRAS: facturas proveedor (una fila por documento)
  IF v_compras_active THEN
    WITH compras_doc AS (
      SELECT fp.codigo_sustento, c.tipo_identificacion, c.numero_identificacion,
             fp.tipo_documento, fp.fecha_emision, fp.numero_documento, fp.numero_autorizacion,
             COALESCE(SUM(CASE WHEN fpl.porcentaje_iva = 0 THEN fpl.subtotal ELSE 0 END), 0) AS base_iva0,
             COALESCE(SUM(CASE WHEN fpl.porcentaje_iva > 0 THEN fpl.subtotal ELSE 0 END), 0) AS base_grav,
             COALESCE(SUM(fpl.valor_iva), 0)                                                  AS monto_iva
      FROM facturas_proveedor fp
      JOIN contactos c ON c.id = fp.proveedor_id
      LEFT JOIN factura_proveedor_lineas fpl ON fpl.factura_proveedor_id = fp.id
      WHERE fp.empresa_id = p_empresa_id
        AND fp.estado = 'CONTABILIZADA'
        AND fp.fecha_emision BETWEEN v_fecha_desde AND v_fecha_hasta
      GROUP BY fp.codigo_sustento, c.tipo_identificacion, c.numero_identificacion,
               fp.tipo_documento, fp.fecha_emision, fp.numero_documento, fp.numero_autorizacion
    )
    SELECT jsonb_agg(jsonb_build_object(
        'codSustento',       codigo_sustento,
        'tpIdProv',          tipo_identificacion,
        'idProv',            numero_identificacion,
        'tipoComprobante',   tipo_documento,
        'parteRel',          'NO',
        'fechaRegistro',     to_char(fecha_emision, 'DD/MM/YYYY'),
        'establecimiento',   SUBSTRING(numero_documento, 1, 3),
        'puntoEmision',      SUBSTRING(numero_documento, 5, 3),
        'secuencial',        SUBSTRING(numero_documento, 9, 9),
        'autorizacion',      numero_autorizacion,
        'baseNoGraIva',      base_iva0,
        'baseImponible',     base_grav,
        'baseImpGrav',       base_grav,
        'montoIce',          0,
        'montoIva',          monto_iva,
        'valRetBien10',      0,
        'valRetServ20',      0,
        'valorRetBienes',    0,
        'valorRetServicios', 0,
        'valorRetServ100',   0,
        'totbasesImpReemb',  0
      ))
    INTO v_compras
    FROM compras_doc;

    -- RETENCIONES emitidas (una fila por retención)
    -- CTE intermedia agrupa sumas por retención; jsonb_agg externo construye el array sin anidar agregados
    WITH ret_agg AS (
      SELECT r.id, r.fecha_emision, r.numero_retencion, r.numero_autorizacion,
             c.tipo_identificacion, c.numero_identificacion,
             fp.fecha_emision AS fp_fecha, fp.numero_documento AS fp_numero,
             COALESCE(SUM(CASE WHEN rl.tipo = 'IVA'   THEN rl.base_imponible  ELSE 0 END), 0) AS base_iva,
             COALESCE(SUM(CASE WHEN rl.tipo = 'RENTA' THEN rl.base_imponible  ELSE 0 END), 0) AS base_renta,
             COALESCE(SUM(CASE WHEN rl.tipo = 'IVA'   THEN rl.valor_retenido  ELSE 0 END), 0) AS ret_iva,
             COALESCE(SUM(CASE WHEN rl.tipo = 'RENTA' THEN rl.valor_retenido  ELSE 0 END), 0) AS ret_renta
      FROM retenciones r
      JOIN contactos c ON c.id = r.proveedor_id
      JOIN retencion_lineas rl ON rl.retencion_id = r.id
      LEFT JOIN facturas_proveedor fp ON fp.id = r.factura_proveedor_id
      WHERE r.empresa_id = p_empresa_id
        AND r.estado = 'AUTORIZADA'
        AND r.fecha_emision BETWEEN v_fecha_desde AND v_fecha_hasta
      GROUP BY r.id, r.fecha_emision, r.numero_retencion, r.numero_autorizacion,
               c.tipo_identificacion, c.numero_identificacion,
               fp.fecha_emision, fp.numero_documento
    )
    SELECT jsonb_agg(jsonb_build_object(
        'tpIdProv',          tipo_identificacion,
        'idProv',            numero_identificacion,
        'periodoFiscal',     to_char(fecha_emision, 'MM/YYYY'),
        'establecimiento',   SUBSTRING(numero_retencion, 1, 3),
        'puntoEmision',      SUBSTRING(numero_retencion, 5, 3),
        'secuencial',        SUBSTRING(numero_retencion, 9, 9),
        'autorizacion',      numero_autorizacion,
        'fechaEmiComp',      to_char(fp_fecha, 'DD/MM/YYYY'),
        'numComp',           fp_numero,
        'baseImpCIva',       base_iva,
        'baseImpGrav',       base_renta,
        'baseNoGraIva',      0,
        'baseImpExe',        0,
        'montoIce',          0,
        'montoIva',          ret_iva,
        'valorRetBienes',    ret_renta,
        'valorRetServicios', 0,
        'valRetBien10',      0,
        'valRetServ20',      0,
        'valorRetServ100',   0,
        'totbasesImpReemb',  0,
        'detalleAirValues',  (
          SELECT jsonb_agg(jsonb_build_object(
            'baseImpAir',    rl2.base_imponible,
            'porcentajeAir', rl2.porcentaje_retencion,
            'valRetAir',     rl2.valor_retenido
          ))
          FROM retencion_lineas rl2 WHERE rl2.retencion_id = id
        )
      ))
    INTO v_retenciones
    FROM ret_agg;
  END IF;

  RETURN jsonb_build_object(
    'TipoIDInformante', 'R',
    'IdInformante',     v_empresa.ruc,
    'razonSocial',      v_empresa.razon_social,
    'Anio',             p_anio,
    'Mes',              LPAD(p_mes::TEXT, 2, '0'),
    'numEstabRuc',      '001',
    'totalVentas',      v_total_ventas,
    'codigoOperativo',  'IVA',
    'modulos_activos', jsonb_build_object(
      'facturacion', v_facturacion_active,
      'compras',     v_compras_active,
      'inventario',  v_inventario_active
    ),
    'ventas',      COALESCE(v_ventas,      '[]'::JSONB),
    'compras',     COALESCE(v_compras,     '[]'::JSONB),
    'retenciones', COALESCE(v_retenciones, '[]'::JSONB)
  );
END;
$$;
```

---

### get_form_101_summary — Resumen para Formulario 101 IR Anual

Calcula totales por categoria de cuenta contable para el estado de resultados del F-101.
Requiere modulo Contabilidad activo. Los codigos de cuenta (41%, 42%, 520x%, 43%) deben
coincidir con el plan de cuentas configurado en la empresa.

```sql
CREATE OR REPLACE FUNCTION get_form_101_summary(
  p_empresa_id UUID,
  p_anio       INT
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_contabilidad_active    BOOLEAN;
  v_ingresos_operacionales DECIMAL(14,2) := 0;
  v_costo_ventas           DECIMAL(14,2) := 0;
  v_gastos_operacionales   DECIMAL(14,2) := 0;
  v_gastos_financieros     DECIMAL(14,2) := 0;
  v_otros_ingresos         DECIMAL(14,2) := 0;
  v_utilidad_bruta         DECIMAL(14,2) := 0;
  v_utilidad_operacional   DECIMAL(14,2) := 0;
  v_utilidad_antes_ir      DECIMAL(14,2) := 0;
  v_participacion_trab     DECIMAL(14,2) := 0;
  v_fecha_desde            DATE;
  v_fecha_hasta            DATE;
BEGIN
  v_fecha_desde := make_date(p_anio, 1, 1);
  v_fecha_hasta := make_date(p_anio, 12, 31);

  SELECT EXISTS (
    SELECT 1 FROM modulos_empresa
    WHERE empresa_id = p_empresa_id
      AND modulo_id = 'contabilidad'
      AND activo = true
  ) INTO v_contabilidad_active;

  IF NOT v_contabilidad_active THEN
    RETURN jsonb_build_object(
      'error', 'Modulo Contabilidad no activo',
      'anio',  p_anio
    );
  END IF;

  -- Calcular saldos anuales por tipo y codigo de cuenta
  WITH saldos AS (
    SELECT
      cc.tipo,
      cc.codigo,
      cc.naturaleza,
      CASE WHEN cc.naturaleza = 'DEUDORA'
        THEN COALESCE(SUM(al.debe - al.haber), 0)
        ELSE COALESCE(SUM(al.haber - al.debe), 0)
      END AS saldo
    FROM cuentas_contables cc
    LEFT JOIN asiento_lineas al ON al.cuenta_id = cc.id
    LEFT JOIN asientos_contables ac ON ac.id = al.asiento_id
      AND ac.empresa_id = p_empresa_id
      AND ac.estado = 'CONTABILIZADO'
      AND ac.fecha BETWEEN v_fecha_desde AND v_fecha_hasta
    WHERE cc.empresa_id = p_empresa_id
      AND cc.es_movimiento = true
    GROUP BY cc.tipo, cc.codigo, cc.naturaleza
  )
  SELECT
    COALESCE(SUM(CASE WHEN tipo = 'INGRESO' AND codigo LIKE '41%'       THEN saldo ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN tipo = 'COSTO'                               THEN saldo ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN tipo = 'GASTO'  AND (codigo LIKE '5201%' OR codigo LIKE '5202%') THEN saldo ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN tipo = 'GASTO'  AND codigo LIKE '5203%'      THEN saldo ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN tipo = 'INGRESO' AND codigo LIKE '43%'       THEN saldo ELSE 0 END), 0)
  INTO
    v_ingresos_operacionales,
    v_costo_ventas,
    v_gastos_operacionales,
    v_gastos_financieros,
    v_otros_ingresos
  FROM saldos;

  v_utilidad_bruta       := v_ingresos_operacionales - v_costo_ventas;
  v_utilidad_operacional := v_utilidad_bruta - v_gastos_operacionales;
  v_utilidad_antes_ir    := v_utilidad_operacional - v_gastos_financieros + v_otros_ingresos;
  v_participacion_trab   := GREATEST(0, v_utilidad_antes_ir * 0.15);

  RETURN jsonb_build_object(
    'anio', p_anio,
    'estado_resultados', jsonb_build_object(
      'ingresos_operacionales',         v_ingresos_operacionales,
      'costo_ventas',                   v_costo_ventas,
      'utilidad_bruta',                 v_utilidad_bruta,
      'gastos_operacionales',           v_gastos_operacionales,
      'utilidad_operacional',           v_utilidad_operacional,
      'gastos_financieros',             v_gastos_financieros,
      'otros_ingresos',                 v_otros_ingresos,
      'utilidad_antes_impuestos',       v_utilidad_antes_ir,
      'participacion_trabajadores_15',  v_participacion_trab,
      'base_imponible_ir',              GREATEST(0, v_utilidad_antes_ir - v_participacion_trab)
    )
  );
END;
$$;
```

---

### save_declaracion — Registrar generacion de declaracion

Guarda o actualiza el registro en `declaraciones_tributarias` tras generar un archivo.
Verifica que la empresa sea la misma del contexto RLS antes de insertar.

```sql
CREATE OR REPLACE FUNCTION save_declaracion(
  p_empresa_id       UUID,
  p_tipo             TEXT,
  p_anio             INT,
  p_mes              INT,            -- NULL para anuales
  p_estado           TEXT,
  p_archivo_url      TEXT DEFAULT NULL,
  p_archivo_nombre   TEXT DEFAULT NULL,
  p_datos_resumen    JSONB DEFAULT NULL,
  p_numero_registro  TEXT DEFAULT NULL,
  p_observaciones    TEXT DEFAULT NULL,
  p_error_detalle    TEXT DEFAULT NULL
) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_id UUID;
BEGIN
  -- Verificar que la empresa pertenece al contexto actual
  IF p_empresa_id != (SELECT private.get_empresa_id()) THEN
    RAISE EXCEPTION 'empresa_id no coincide con el contexto de sesion';
  END IF;

  -- Upsert manual para soportar índices parciales (mensuales y anuales separados).
  -- ON CONFLICT simple no funciona cuando el índice es parcial (WHERE mes IS NOT NULL / IS NULL).
  UPDATE declaraciones_tributarias SET
    estado           = p_estado,
    fecha_generacion = CASE WHEN p_estado IN ('GENERADA','ERROR')
                        THEN NOW()
                        ELSE fecha_generacion END,
    archivo_url      = COALESCE(p_archivo_url,      archivo_url),
    archivo_nombre   = COALESCE(p_archivo_nombre,   archivo_nombre),
    datos_resumen    = COALESCE(p_datos_resumen,    datos_resumen),
    numero_registro  = COALESCE(p_numero_registro,  numero_registro),
    observaciones    = COALESCE(p_observaciones,    observaciones),
    error_detalle    = p_error_detalle,
    updated_at       = NOW()
  WHERE empresa_id = p_empresa_id
    AND tipo       = p_tipo
    AND anio       = p_anio
    AND (mes = p_mes OR (mes IS NULL AND p_mes IS NULL))
  RETURNING id INTO v_id;

  IF v_id IS NULL THEN
    INSERT INTO declaraciones_tributarias (
      empresa_id, tipo, anio, mes, estado,
      fecha_generacion, archivo_url, archivo_nombre,
      datos_resumen, numero_registro, presentado_por,
      observaciones, error_detalle
    ) VALUES (
      p_empresa_id, p_tipo, p_anio, p_mes, p_estado,
      CASE WHEN p_estado IN ('GENERADA','ERROR') THEN NOW() ELSE NULL END,
      p_archivo_url, p_archivo_nombre,
      p_datos_resumen, p_numero_registro, auth.uid(),
      p_observaciones, p_error_detalle
    )
    RETURNING id INTO v_id;
  END IF;

  RETURN v_id;
END;
$$;
```

---

### get_calendario_tributario — Fechas de vencimiento del año

Devuelve las fechas limite de declaracion por tipo de formulario para el año
solicitado, calculadas segun el noveno digito RUC y el tipo de contribuyente
configurados en `configuracion_tributaria`.

```sql
CREATE OR REPLACE FUNCTION get_calendario_tributario(
  p_empresa_id UUID,
  p_anio       INT
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_config     RECORD;
  v_fechas     JSONB := '[]'::JSONB;
  v_mes        INT;
  -- Dias limite por noveno digito (segun tabla SRI)
  v_dia_limite INT;
BEGIN
  SELECT * INTO v_config
  FROM configuracion_tributaria
  WHERE empresa_id = p_empresa_id AND activo = true;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Sin configuracion tributaria');
  END IF;

  -- Tabla SRI: dias de plazo segun noveno digito RUC
  -- 1→10, 2→12, 3→14, 4→16, 5→18, 6→20, 7→22, 8→24, 9→26, 0→28
  v_dia_limite := CASE v_config.noveno_digito_ruc
    WHEN 1 THEN 10 WHEN 2 THEN 12 WHEN 3 THEN 14
    WHEN 4 THEN 16 WHEN 5 THEN 18 WHEN 6 THEN 20
    WHEN 7 THEN 22 WHEN 8 THEN 24 WHEN 9 THEN 26
    ELSE 28  -- digito 0
  END;

  -- Generar fechas mensuales para F-103 y F-104
  IF v_config.regimen_iva = 'MENSUAL' THEN
    FOR v_mes IN 1..12 LOOP
      -- Para diciembre (v_mes=12): el vencimiento cae en enero del año siguiente.
      -- make_date(p_anio, 13, ...) sería inválido; se usa CASE para evitar el overflow.
      v_fechas := v_fechas || jsonb_build_object(
        'mes',           v_mes,
        'anio',          p_anio,
        'tipo',          'F_103',
        'descripcion',   'Retenciones Fuente - mes ' || v_mes,
        'fecha_limite',  make_date(
          CASE WHEN v_mes = 12 THEN p_anio + 1 ELSE p_anio END,
          CASE WHEN v_mes = 12 THEN 1           ELSE v_mes + 1 END,
          v_dia_limite
        )
      ) || jsonb_build_object(
        'mes',           v_mes,
        'anio',          p_anio,
        'tipo',          'F_104',
        'descripcion',   'IVA - mes ' || v_mes,
        'fecha_limite',  make_date(
          CASE WHEN v_mes = 12 THEN p_anio + 1 ELSE p_anio END,
          CASE WHEN v_mes = 12 THEN 1           ELSE v_mes + 1 END,
          v_dia_limite
        )
      );
    END LOOP;
  ELSE
    -- Semestral: primer semestre vence julio, segundo semestre vence enero siguiente
    v_fechas := v_fechas
      || jsonb_build_object(
        'mes', 6, 'anio', p_anio, 'tipo', 'F_104',
        'descripcion', 'IVA Semestral Ene-Jun',
        'fecha_limite', make_date(p_anio, 7, v_dia_limite)
      )
      || jsonb_build_object(
        'mes', 12, 'anio', p_anio, 'tipo', 'F_104',
        'descripcion', 'IVA Semestral Jul-Dic',
        'fecha_limite', make_date(p_anio + 1, 1, v_dia_limite)
      );
  END IF;

  -- ATS mensual
  FOR v_mes IN 1..12 LOOP
    v_fechas := v_fechas || jsonb_build_object(
      'mes',          v_mes,
      'anio',         p_anio,
      'tipo',         'ATS',
      'descripcion',  'ATS - mes ' || v_mes,
      'fecha_limite', make_date(
        CASE WHEN v_mes = 12 THEN p_anio + 1 ELSE p_anio END,
        CASE WHEN v_mes = 12 THEN 1           ELSE v_mes + 1 END,
        28
      )
    );
  END LOOP;

  -- F-101 anual
  v_fechas := v_fechas || jsonb_build_object(
    'mes',          NULL,
    'anio',         p_anio,
    'tipo',         'F_101',
    'descripcion',  'Impuesto a la Renta Anual ' || p_anio,
    'fecha_limite', make_date(p_anio + 1, 4, v_dia_limite)
  );

  RETURN jsonb_build_object(
    'anio',              p_anio,
    'noveno_digito_ruc', v_config.noveno_digito_ruc,
    'dia_limite',        v_dia_limite,
    'tipo_contribuyente', v_config.tipo_contribuyente,
    'regimen_iva',       v_config.regimen_iva,
    'fechas',            v_fechas
  );
END;
$$;
```

---

## Module Service Bus

```sql
-- Funcion para que otros modulos verifiquen si Tributacion esta activo
CREATE OR REPLACE FUNCTION module_bus.tributacion_is_active(
  p_empresa_id UUID
) RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT EXISTS (
    SELECT 1 FROM modulos_empresa
    WHERE empresa_id = p_empresa_id
      AND modulo_id = 'tributacion'
      AND activo = true
  );
$$;
```

Tributacion NO expone funciones gateway que otros modulos llamen directamente.
Es un modulo consumidor puro: lee de otros via Module Service Bus, nunca escribe
en sus tablas.

---

## Edge Functions

```
supabase/functions/
├── generate-ats/
│   └── index.ts      # Recibe resultado de get_ats_data(), genera XML ISO-8859-1 + ZIP, guarda Storage
├── generate-declaracion-103/
│   └── index.ts      # Genera reporte F-103 PDF con datos de get_form_103_data()
└── generate-declaracion-104/
    └── index.ts      # Genera reporte F-104 PDF con datos de get_form_104_data()
```

### generate-ats/index.ts

```typescript
// POST /functions/v1/generate-ats
// Body: { empresa_id: string, anio: number, mes: number }
// Headers: Authorization: Bearer <jwt>

// Flujo:
// 1. Validar JWT y extraer empresa_id del contexto
// 2. Llamar a get_ats_data(empresa_id, anio, mes) via Supabase RPC
// 3. Generar XML con estructura ATS del SRI (encoding ISO-8859-1):
//    <iva>
//      <TipoIDInformante>R</TipoIDInformante>
//      <IdInformante>{ruc}</IdInformante>
//      <razonSocial>{razon_social}</razonSocial>
//      <Anio>{anio}</Anio>
//      <Mes>{mes_2_digitos}</Mes>
//      <numEstabRuc>001</numEstabRuc>
//      <totalVentas>{total_ventas}</totalVentas>
//      <codigoOperativo>IVA</codigoOperativo>
//      <ventas>...</ventas>
//      <compras>...</compras>
//    </iva>
// 4. Comprimir a ZIP: ATS_{YYYY}{MM}_{RUC}.zip
// 5. Guardar en Storage: tributacion/{empresa_id}/ats/ATS_{YYYYMM}.zip
// 6. Llamar save_declaracion() para registrar en declaraciones_tributarias
// 7. Retornar: { url, nombre_archivo, totales: { ventas, compras, retenciones } }
```

### generate-declaracion-104/index.ts

```typescript
// POST /functions/v1/generate-declaracion-104
// Body: { empresa_id: string, anio: number, mes: number }

// Flujo:
// 1. Llamar a get_form_104_data(empresa_id, anio, mes) via RPC
// 2. Renderizar PDF con estructura de casillas del F-104 (Syncfusion PDF o jsPDF)
// 3. Guardar en Storage: tributacion/{empresa_id}/f104/F104_{YYYYMM}.pdf
// 4. Registrar en declaraciones_tributarias (tipo = 'F_104')
// 5. Retornar { url, nombre_archivo }
```

### generate-declaracion-103/index.ts

```typescript
// POST /functions/v1/generate-declaracion-103
// Body: { empresa_id: string, anio: number, mes: number }

// Flujo:
// 1. Llamar a get_form_103_data(empresa_id, anio, mes) via RPC
// 2. Renderizar PDF con tabla de retenciones agrupada por codigo
// 3. Guardar en Storage: tributacion/{empresa_id}/f103/F103_{YYYYMM}.pdf
// 4. Registrar en declaraciones_tributarias (tipo = 'F_103')
// 5. Retornar { url, nombre_archivo }
```

---

## Integracion con otros modulos

```
TRIBUTACION lee (via module_bus checks, nunca sin guard):
  <- Facturacion  : facturas, factura_lineas, notas_credito, notas_debito
  <- Compras      : facturas_proveedor, factura_proveedor_lineas, retenciones, retencion_lineas
  <- Contabilidad : cuentas_contables, asientos_contables, asiento_lineas, periodos_contables
  <- Inventario   : guias_remision (ATS tipo 06, si aplica)
  <- RRHH         : empleados, nominas (para RDEP — solo si modulo RRHH activo)

TRIBUTACION NO escribe en tablas de otros modulos (modulo consumidor puro)

TRIBUTACION escribe en sus propias tablas:
  -> declaraciones_tributarias  (historial y estado)
  -> Supabase Storage:
       tributacion/{empresa_id}/ats/       ZIP ATS mensual
       tributacion/{empresa_id}/f103/      PDF Formulario 103
       tributacion/{empresa_id}/f104/      PDF Formulario 104
       tributacion/{empresa_id}/f101/      PDF/datos Formulario 101
       tributacion/{empresa_id}/scvs/      TXT EEFF Supercias
       tributacion/{empresa_id}/rdep/      XML RDEP
```

### Degradacion elegante por modulos activos

| Modulos activos | ATS | F-104 | F-103 | F-101 | RDEP |
|-----------------|-----|-------|-------|-------|------|
| Solo Facturacion | Solo seccion ventas | Solo ventas, sin compras | No disponible | No disponible | No disponible |
| Facturacion + Compras | Ventas + Compras + Retenciones | Completo | Completo | No disponible | No disponible |
| + Contabilidad | Completo | Completo | Completo | Completo (estado resultados) | No disponible |
| + RRHH | Completo | Completo | Completo | Completo | Completo |

---

## Resumen de pantallas

| Codigo | Pantalla | RPC principal | Edge Function |
|--------|----------|---------------|---------------|
| T-TRI-01 | Dashboard tributario | `get_form_104_data` + `get_form_103_data` + `get_calendario_tributario` | — |
| T-TRI-02 | Historial declaraciones | — (lee `declaraciones_tributarias`) | — |
| T-TRI-03 | Generar ATS | `get_ats_data()` | `generate-ats` |
| T-TRI-04 | Formulario 104 IVA | `get_form_104_data()` | `generate-declaracion-104` |
| T-TRI-05 | Formulario 103 Retenciones | `get_form_103_data()` | `generate-declaracion-103` |
| T-TRI-06 | Formulario 101 IR Anual | `get_form_101_summary()` | — |
| T-TRI-07 | EEFF Supercias | `get_balance_sheet()` + `get_income_statement()` (de Contabilidad) | `generate-scvs-eeff` |
| T-TRI-08 | RDEP | `get_rdep_data()` (requiere RRHH) | `generate-rdep` |

---

## Notas de implementacion

- **Precisión monetaria**: todas las funciones usan `DECIMAL(14,2)`. Los intermedios no se redondean; el redondeo ocurre solo en el valor final retornado.
- **Encoding ATS**: el XML debe generarse en ISO-8859-1 segun especificacion SRI. La Edge Function hace la conversion desde UTF-8 antes de comprimir.
- **Credito tributario mes anterior**: `get_form_104_data` inicializa `v_credito_anterior := 0`. En la implementacion final debe leer el campo `credito_proximo_mes` de la declaracion del mes previo en `declaraciones_tributarias.datos_resumen`.
- **ATS guias de remision**: si Inventario esta activo, incluir `guias_remision` autorizadas en la seccion compras del ATS con `tipoComprobante = '06'`.
- **Fechas limite mes 12**: `get_calendario_tributario` maneja el desbordamiento de diciembre con `CASE WHEN v_mes = 12 THEN p_anio + 1 ELSE p_anio END` y `CASE WHEN v_mes = 12 THEN 1 ELSE v_mes + 1 END` en los tres loops (F-103, F-104 y ATS). Evitar `v_mes + 1` directo sin este guard — produce `make_date(anio, 13, dia)` que PostgreSQL rechaza.
- **Contribuyentes especiales**: tienen fechas especiales asignadas directamente por el SRI, no siguen la tabla de noveno digito. La tabla `configuracion_tributaria` permite sobreescribir con `tipo_contribuyente = 'CONTRIBUYENTE_ESPECIAL'`.

---

## Flujos Principales

### Flujo de Generacion ATS

```
┌──────────┐    ┌──────────┐    ┌──────────────┐    ┌──────────┐
│ Ejecutar │───>│ Consultar│───>│ Generar XML  │───>│ Comprimir│
│ get_ats_ │    │ ventas,  │    │ ATS (ISO-    │    │ como     │
│ data()   │    │ compras, │    │ 8859-1, XSD) │    │ ATmmaaaa │
│          │    │ retenc.  │    │              │    │ .zip     │
└──────────┘    └──────────┘    └──────────────┘    └────┬─────┘
                                                         │
                                ┌──────────────┐         │
                                │ Subir al     │<────────┘
                                │ Portal SRI   │
                                │ (manual)     │
                                └──────────────┘
```

> La Edge Function `generate-ats` realiza los pasos de generación XML y compresión. La subida al portal SRI se hace manualmente por el contador descargando el archivo ZIP.

### Flujo Declaracion 103 / 104

```
┌──────────┐    ┌──────────┐    ┌──────────────┐
│ Ejecutar │───>│ Calcular │───>│ Generar      │
│ get_form_│    │ base     │    │ reporte PDF  │
│ 10x_data │    │ imponible│    │ (borrador)   │
└──────────┘    └──────────┘    └──────────────┘
                                       │
                                ┌──────────────┐
                                │ Presentar    │
                                │ en portal    │
                                │ SRI (manual) │
                                └──────────────┘
```
