# Documentos e Informes Contables Ecuador


PILAR debe generar o facilitar la preparacion de todos los documentos, informes y reportes requeridos por los organismos reguladores ecuatorianos.

## Declaraciones SRI (Formularios)

| Formulario | Nombre | Periodicidad | Formato | Generado por ERP |
|-----------|--------|-------------|---------|-----------------|
| **103** | Retenciones en la Fuente del IR | **Mensual** | Portal SRI | **Si** - totales de retenciones por codigo |
| **104** | Declaracion del IVA | **Mensual** | Portal SRI | **Si** - ventas/compras por tarifa IVA |
| **104A** | Declaracion del IVA (semestral) | **Semestral** | Portal SRI | **Si** |
| **101** | Impuesto a la Renta Sociedades | **Anual** (abril) | Portal SRI | **Si** - datos de balance y resultados |
| **102** | IR Personas Naturales (contabilidad obligatoria) | **Anual** (marzo) | Portal SRI | **Si** |
| **107** | Retenciones IR por Relacion de Dependencia | **Anual** (enero) | PDF impreso | **Si** - modulo RRHH |
| **106** | Formulario Multiple de Pagos | Cuando aplique | Portal SRI | Parcial |

**Nota:** Los formularios se llenan en el portal SRI, pero el ERP genera los datos necesarios (totales de ventas, compras, retenciones, ingresos, gastos) exportados en **Excel** para facilitar el llenado.

> **Nota de arquitectura**: Los informes tributarios SRI (`get_form_104_data`, `get_form_103_data`, `get_ats_data`) se han movido al módulo **[Tributación (Core #10)](../tributacion/tributacion.md)**. Contabilidad provee el plan de cuentas y los asientos; Tributación consume esos datos vía module_bus y genera las declaraciones con degradación elegante según los módulos activos. Ver también la nota al pie de [`contabilidad.md`](./contabilidad.md).

## Anexos Tributarios SRI

| Anexo | Nombre | Periodicidad | Formato | Generado por ERP |
|-------|--------|-------------|---------|-----------------|
| **ATS** | Anexo Transaccional Simplificado | **Mensual** | **XML** (ISO-8859-1, ZIP) | **Si** - Edge Function `generate-ats` |
| **RDEP** | Retenciones bajo Relacion de Dependencia | **Anual** (ene-feb) | **XML** (DIMM) | **Si** - modulo RRHH |
| **APS** | Accionistas, Participes, Socios | **Anual** (febrero) | **XML** (DIMM) | Parcial - datos societarios |
| **ADI** | Anexo de Dividendos | **Anual** | **XML** (DIMM) | Parcial |

## Comprobantes Electronicos SRI

| Documento | Codigo | Periodicidad | Formato | Generado por ERP |
|-----------|--------|-------------|---------|-----------------|
| Factura electronica | 01 | Tiempo real | **XML firmado** | **Si** |
| Liquidacion de compra | 03 | Tiempo real | **XML firmado** | **Si** |
| Nota de credito | 04 | Tiempo real | **XML firmado** | **Si** |
| Nota de debito | 05 | Tiempo real | **XML firmado** | **Si** |
| Guia de remision | 06 | Tiempo real | **XML firmado** | **Si** |
| Comprobante de retencion | 07 | Tiempo real | **XML firmado** | **Si** |

**Importante 2026:** Transmision inmediata al SRI (ya no hay plazo de 4 dias). Multa por incumplimiento: 30 RBU (~USD 14.460).

## Superintendencia de Companias (NIIF)

Estados financieros obligatorios (plazo: hasta **30 de abril** del anio siguiente):

| Documento | Formato | Generado por ERP |
|-----------|---------|-----------------|
| **Estado de Situacion Financiera** (Balance General) | Portal SCVS + **PDF** + **Excel** | **Si** |
| **Estado de Resultado Integral** | Portal SCVS + **PDF** + **Excel** | **Si** |
| **Estado de Cambios en el Patrimonio** | Portal SCVS + **PDF** + **Excel** | **Si** |
| **Estado de Flujos de Efectivo** (metodo directo o indirecto) | Portal SCVS + **PDF** + **Excel** | **Si** |
| **Notas a los Estados Financieros** | **PDF** | Parcial (plantilla + datos) |
| Informe de Administradores/Gerencia | **PDF** | No (redaccion manual) |
| Informe del Comisario | **PDF** | No |
| Nomina de Socios/Accionistas | Portal SCVS | Parcial |

**Clasificacion NIIF:** PYMES (activos < USD 4M, ventas < USD 5M, < 200 empleados) aplican **NIIF para PYMES**. Las demas aplican **NIIF completas**.

## Libros Contables Obligatorios

| Libro | Descripcion | Formato de Exportacion | Generado por ERP |
|-------|-------------|----------------------|-----------------|
| **Libro Diario** | Registro cronologico de asientos contables | **PDF** + **Excel** | **Si** |
| **Libro Mayor** | Movimientos y saldos por cuenta contable | **PDF** + **Excel** | **Si** |
| **Libro de Inventarios y Balances** | Inventario inicial/final y balances | **PDF** + **Excel** | **Si** |
| **Balance de Comprobacion** | Sumas y saldos de todas las cuentas | **PDF** + **Excel** | **Si** |

### Formulario 101 - Impuesto a la Renta Sociedades (G-CON-08)

Mapeo configurable de las 800+ casillas del formulario 101 a cuentas contables. Exportable a CSV/XML para DIMM.

```sql
CREATE TABLE mapeo_formulario_101 (
  id UUID PK, empresa_id UUID FK,
  casilla VARCHAR(10) NOT NULL,
  descripcion TEXT,
  cuenta_id UUID FK -> cuentas_contables,
  tipo_calculo VARCHAR(15) DEFAULT 'SALDO',  -- SALDO, MOVIMIENTO, FORMULA
  formula TEXT  -- Si FORMULA: ej '{301}+{302}-{303}'
);
-- UNIQUE(empresa_id, casilla), RLS: tenant_isolation

CREATE OR REPLACE FUNCTION generate_form_101(p_empresa_id UUID, p_anio INTEGER)
RETURNS JSONB  -- {casilla: valor}
-- SALDO: saldo_final al 31/dic, MOVIMIENTO: suma debe/haber del anio
-- FORMULA: evalua expresion con valores de otras casillas calculadas
```

### Formato Superintendencia de Companias (G-CON-09)

Mapeo de cuentas al catalogo SCVS para Estado de Situacion Financiera y Estado de Resultados en formato oficial.

```sql
CREATE TABLE mapeo_supercias (
  id UUID PK, empresa_id UUID FK,
  codigo_supercias VARCHAR(20) NOT NULL,
  descripcion TEXT,
  cuenta_id UUID FK -> cuentas_contables
);
-- UNIQUE(empresa_id, codigo_supercias, cuenta_id)

CREATE OR REPLACE FUNCTION generate_supercias_report(p_empresa_id UUID, p_anio INTEGER)
RETURNS JSONB  -- {codigo_supercias: valor}
-- Requerido para empresas bajo control Superintendencia, plazo 30 abril
```

### Balance General - Estado de Situacion Financiera (G-CON-10)

RPC para generacion del Estado de Situacion Financiera al cierre de una fecha dada. Clasifica cuentas en Activo Corriente / No Corriente, Pasivo Corriente / No Corriente y Patrimonio conforme a NIIF.

```sql
-- Balance General (Estado de Situación Financiera)
-- Clasifica cuentas en ACTIVO CORRIENTE / NO CORRIENTE, PASIVO CORRIENTE / NO CORRIENTE, PATRIMONIO
CREATE OR REPLACE FUNCTION get_balance_sheet(
  p_empresa_id UUID,
  p_fecha      DATE  -- al cierre de esa fecha
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_resultado JSONB;
BEGIN
  -- Estructura: {activo: {corriente: [{cuenta, saldo}], no_corriente: [...]},
  --              pasivo:  {corriente: [...], no_corriente: [...]},
  --              patrimonio: [...],
  --              total_activo, total_pasivo, total_patrimonio,
  --              diferencia}  -- debe ser 0
  WITH saldos AS (
    SELECT
      c.id, c.codigo, c.nombre, c.tipo, c.naturaleza,
      c.codigo_niif,
      COALESCE(SUM(
        CASE WHEN c.naturaleza = 'DEUDORA' THEN l.debe - l.haber
             ELSE l.haber - l.debe END
      ), 0) AS saldo
    FROM cuentas_contables c
    LEFT JOIN asiento_lineas l ON l.cuenta_id = c.id
    LEFT JOIN asientos_contables a ON a.id = l.asiento_id
      AND a.estado = 'CONTABILIZADO'
      AND a.fecha <= p_fecha
    WHERE c.empresa_id = p_empresa_id AND c.es_movimiento = true
    GROUP BY c.id, c.codigo, c.nombre, c.tipo, c.naturaleza, c.codigo_niif
    HAVING COALESCE(SUM(ABS(l.debe) + ABS(l.haber)), 0) > 0
  )
  SELECT jsonb_build_object(
    'fecha', p_fecha,
    'activo', jsonb_build_object(
      'corriente',    jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre, 'saldo', saldo))
                      FILTER (WHERE tipo = 'ACTIVO' AND codigo LIKE '101%'),
      'no_corriente', jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre, 'saldo', saldo))
                      FILTER (WHERE tipo = 'ACTIVO' AND codigo NOT LIKE '101%')
    ),
    'pasivo', jsonb_build_object(
      'corriente',    jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre, 'saldo', saldo))
                      FILTER (WHERE tipo = 'PASIVO' AND codigo LIKE '201%'),
      'no_corriente', jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre, 'saldo', saldo))
                      FILTER (WHERE tipo = 'PASIVO' AND codigo NOT LIKE '201%')
    ),
    'patrimonio',     jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre, 'saldo', saldo))
                      FILTER (WHERE tipo = 'PATRIMONIO'),
    'total_activo',    SUM(saldo) FILTER (WHERE tipo = 'ACTIVO'),
    'total_pasivo',    SUM(saldo) FILTER (WHERE tipo = 'PASIVO'),
    'total_patrimonio',SUM(saldo) FILTER (WHERE tipo = 'PATRIMONIO')
  ) INTO v_resultado FROM saldos;

  RETURN v_resultado;
END;
$$;
```

### Estado de Resultado Integral (G-CON-11)

RPC para generacion del Estado de Resultado Integral por periodo. Incluye ingresos operacionales, costos, gastos operacionales, gastos financieros, otros ingresos/gastos y resultado neto.

```sql
-- Estado de Resultado Integral
-- Incluye: Ingresos operacionales, Costos, Gastos operacionales, Resultado operacional,
--          Otros ingresos/gastos, Resultado antes impuestos, Impuesto a la Renta, Resultado neto
CREATE OR REPLACE FUNCTION get_income_statement(
  p_empresa_id  UUID,
  p_fecha_desde DATE,
  p_fecha_hasta DATE
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_resultado JSONB;
BEGIN
  WITH movimientos AS (
    SELECT
      c.id, c.codigo, c.nombre, c.tipo,
      COALESCE(SUM(
        CASE WHEN c.naturaleza = 'ACREEDORA' THEN l.haber - l.debe  -- INGRESO es acreedora
             ELSE l.debe - l.haber END                               -- GASTO/COSTO es deudora
      ), 0) AS saldo
    FROM cuentas_contables c
    LEFT JOIN asiento_lineas l ON l.cuenta_id = c.id
    LEFT JOIN asientos_contables a ON a.id = l.asiento_id
      AND a.estado = 'CONTABILIZADO'
      AND a.fecha BETWEEN p_fecha_desde AND p_fecha_hasta
    WHERE c.empresa_id = p_empresa_id
      AND c.tipo IN ('INGRESO', 'GASTO', 'COSTO')
      AND c.es_movimiento = true
    GROUP BY c.id, c.codigo, c.nombre, c.tipo
    HAVING COALESCE(SUM(ABS(l.debe) + ABS(l.haber)), 0) > 0
  )
  SELECT jsonb_build_object(
    'periodo', jsonb_build_object('desde', p_fecha_desde, 'hasta', p_fecha_hasta),
    'ingresos_operacionales', jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre, 'saldo', saldo))
                              FILTER (WHERE tipo = 'INGRESO' AND codigo LIKE '41%'),
    'otros_ingresos',         jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre, 'saldo', saldo))
                              FILTER (WHERE tipo = 'INGRESO' AND codigo NOT LIKE '41%'),
    'costos',                 jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre, 'saldo', saldo))
                              FILTER (WHERE tipo = 'COSTO'),
    'gastos_operacionales',   jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre, 'saldo', saldo))
                              FILTER (WHERE tipo = 'GASTO' AND (codigo LIKE '5201%' OR codigo LIKE '5202%')),
    'gastos_financieros',     jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre, 'saldo', saldo))
                              FILTER (WHERE tipo = 'GASTO' AND codigo LIKE '5203%'),
    'otros_gastos',           jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre, 'saldo', saldo))
                              FILTER (WHERE tipo = 'GASTO' AND codigo NOT LIKE '5201%' AND codigo NOT LIKE '5202%' AND codigo NOT LIKE '5203%'),
    'total_ingresos',         SUM(saldo) FILTER (WHERE tipo = 'INGRESO'),
    'total_costos',           SUM(saldo) FILTER (WHERE tipo = 'COSTO'),
    'total_gastos',           SUM(saldo) FILTER (WHERE tipo = 'GASTO'),
    'resultado_neto',         SUM(saldo) FILTER (WHERE tipo = 'INGRESO')
                              - SUM(saldo) FILTER (WHERE tipo IN ('GASTO','COSTO'))
  ) INTO v_resultado FROM movimientos;

  RETURN v_resultado;
END;
$$;
```

### Estado de Flujos de Efectivo (G-CON-12)

RPC para generacion del Estado de Flujos de Efectivo por metodo directo o indirecto (NIC 7).

> **Implementación**: Ver función completa `get_cash_flow_statement(p_empresa_id, p_anio, p_mes_hasta)` en [`contabilidad.md`](./contabilidad.md) — sección "get_cash_flow_statement — estado de flujo de efectivo (método indirecto)". Implementa el **método INDIRECTO** (NIIF-NIC 7): utilidad neta + ajustes no monetarios (depreciación, amortización, provisiones) ± variaciones de capital de trabajo. No requiere otros módulos activos — trabaja exclusivamente con datos de `asientos_contables` y `cuentas_contables`.

### Constructor de Reportes Financieros (G-CON-13) -- P2

Permite crear plantillas de reportes personalizados (Balance, Resultados, custom) con estructura JSONB.

```sql
CREATE TABLE plantillas_reporte (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id  UUID NOT NULL REFERENCES empresas(id),
  nombre      VARCHAR(150) NOT NULL,
  tipo        VARCHAR(15) NOT NULL,         -- BALANCE | RESULTADOS | CUSTOM
  estructura  JSONB NOT NULL,               -- [{seccion, titulo, lineas: [{cuenta_id|formula, label, tipo}]}]
  -- tipo linea: SALDO | MOVIMIENTO | SUBTOTAL | TOTAL
  -- formula: "SUM(1.1.*) - SUM(2.1.*)" para subtotales calculados
  activa      BOOLEAN DEFAULT true,
  created_at  TIMESTAMPTZ DEFAULT now(),
  UNIQUE(empresa_id, nombre)
);
ALTER TABLE plantillas_reporte ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON plantillas_reporte FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE OR REPLACE FUNCTION generate_custom_report(
  p_empresa_id UUID, p_plantilla_id UUID,
  p_fecha_desde DATE, p_fecha_hasta DATE
) RETURNS JSONB
-- 1. Leer estructura JSONB de la plantilla
-- 2. Por cada linea: SALDO=saldo cuenta, MOVIMIENTO=debe-haber en periodo,
--    SUBTOTAL/TOTAL=evaluar formula sobre lineas previas
-- 3. Retorna {nombre, tipo, fecha_desde, fecha_hasta, secciones: [{titulo, lineas: [{label, valor}]}]}
```

### Consolidacion Multi-Empresa (G-CON-14) -- P3

Consolidacion de Estados Financieros para grupos empresariales (NIIF 10).

```sql
CREATE TABLE grupos_empresariales (id UUID PK, nombre VARCHAR, empresa_matriz_id UUID REFERENCES empresas);
CREATE TABLE grupo_empresarial_miembros (id UUID PK, grupo_id UUID, empresa_id UUID, porcentaje_participacion DECIMAL(5,2));
-- Eliminaciones inter-company: CxC vs CxP, ventas vs compras entre empresas del grupo

CREATE OR REPLACE FUNCTION generate_consolidated_statements(
  p_grupo_id UUID, p_fecha_desde DATE, p_fecha_hasta DATE
) RETURNS JSONB
-- 1. Obtiene balances de comprobacion de cada empresa miembro
-- 2. Suma proporcional segun porcentaje_participacion
-- 3. Elimina transacciones inter-company (CxC↔CxP, ventas↔compras)
-- 4. Retorna: Balance General Consolidado + Estado de Resultados Consolidado
-- Nota: Requiere mismo plan de cuentas (o tabla mapeo_cuentas_grupo) entre empresas
```

## Reportes de Gestion (internos, exportables)

| Reporte | Modulo | Periodicidad | Formato |
|---------|--------|-------------|---------|
| **Reporte de Ventas** (por periodo, cliente, producto) | Ventas | Mensual/diario | **PDF** + **Excel** |
| **Reporte de Compras** (por periodo, proveedor) | Compras | Mensual | **PDF** + **Excel** |
| **Reporte de Retenciones** (emitidas y recibidas) | Compras | Mensual | **PDF** + **Excel** |
| **Cartera Vencida CxC** (aging: 0-30, 31-60, 61-90, 90+) | CxC | Mensual/demanda | **Pantalla** + **PDF** + **Excel** |
| **Cartera Vencida CxP** (aging: por vencer y vencidas) | CxP | Mensual/demanda | **Pantalla** + **PDF** + **Excel** |
| **Estado de Cuenta Cliente** (movimientos cronologicos) | CxC | Bajo demanda | **Pantalla** + **PDF** + **Excel** |
| **Estado de Cuenta Proveedor** (movimientos cronologicos) | CxP | Bajo demanda | **Pantalla** + **PDF** + **Excel** |
| **CxC vs Cobros** (deudas generadas vs cobros por periodo) | CxC | Mensual | **Pantalla** + **PDF** + **Excel** |
| **CxP vs Pagos** (deudas vs pagos por periodo) | CxP | Mensual | **Pantalla** + **PDF** + **Excel** |
| **Credito de Clientes** (limite, uso, disponible, % uso) | CxC | Bajo demanda | **Pantalla** + **PDF** + **Excel** |
| **Comprobante de Cobro** (recibo de pago del cliente) | CxC | Al cobrar | **PDF** (imprimible) |
| **Comprobante de Pago** (pago a proveedor) | CxP | Al pagar | **PDF** (imprimible) |
| **Plan de Pagos** (detalle con documentos, montos, metodos) | CxP | Al crear/aprobar | **PDF** (imprimible) |
| **Cheque impreso** (formato pre-impreso para impresora cheques) | Tesoreria | Al emitir | **PDF** (imprimible) |
| **Asiento Contable** (detalle con lineas debe/haber) | Contabilidad | Bajo demanda | **PDF** (imprimible) |
| **Kardex de Inventarios** (por producto, bodega) | Inventario | Permanente | **PDF** + **Excel** |
| **Reporte de Stock** (existencias por bodega) | Inventario | Diario | **PDF** + **Excel** |
| **Reporte de Despachos** (por orden de venta) | Inventario | Diario | **PDF** + **Excel** |
| **Conciliacion Bancaria** | Tesoreria | Mensual | **PDF** + **Excel** |
| **Flujo de Caja** | Tesoreria | Mensual | **PDF** + **Excel** |
| **Cheques Pendientes** | Tesoreria | Mensual | **PDF** + **Excel** |
| **Saldos Bancarios** | Tesoreria | Diario | **PDF** + **Excel** |
| **Dashboard Gerencial** (KPIs) | Dashboard | Tiempo real | Pantalla (Syncfusion Charts) |
| **Depreciacion de Activos Fijos** | Contabilidad | Mensual/Anual | **PDF** + **Excel** |

## Obligaciones Laborales (Modulo RRHH)

| Obligacion | Organismo | Periodicidad | Formato | Generable |
|-----------|-----------|-------------|---------|-----------|
| **Planillas de Aportes IESS** (patronal 11.15% + personal 9.45%) | IESS | **Mensual** | Portal IESS | **Si** (datos exportables) |
| **Fondos de Reserva** (8.33%) | IESS | **Mensual** | Portal IESS | **Si** |
| **Decimo Tercer Sueldo** (registro) | MDT/SUT | **Anual** (dic) | Portal SUT | **Si** |
| **Decimo Cuarto Sueldo** (registro) | MDT/SUT | **Anual** (mar/ago) | Portal SUT | **Si** |
| **Utilidades 15%** (registro) | MDT/SUT | **Anual** (abril) | Portal SUT | **Si** |
| **RDEP** (retenciones empleados) | SRI | **Anual** | **XML** | **Si** |

## Impuestos Municipales

| Impuesto | Organismo | Periodicidad | Base de Calculo | Datos del ERP |
|----------|-----------|-------------|----------------|--------------|
| **Patente Municipal** | GAD Municipal | **Anual** | Patrimonio neto | **Si** - del balance |
| **1.5 por Mil sobre Activos** | GAD Municipal | **Anual** | Activos - pasivos corrientes | **Si** - del balance |

## Implementacion de Reportes en Flutter

```
GENERACION DE PDF (Syncfusion):
  syncfusion_flutter_pdf → Genera PDFs con formato profesional
  - Encabezado: logo empresa, RUC, direccion
  - Cuerpo: tablas con SfDataGrid exportados
  - Pie: totales, firmas, fecha generacion
  - Impresion directa via paquete 'printing'

GENERACION DE EXCEL (Syncfusion):
  syncfusion_flutter_xlsio → Genera Excel (.xlsx) nativamente
  - Hojas con datos tabulares
  - Formulas calculadas
  - Formato con colores, bordes, fuentes
  - Compatible con Excel, Google Sheets, LibreOffice

FLUJO DE EXPORTACION:
  1. Usuario selecciona reporte y parametros (fecha, cuenta, etc.)
  2. RPC/PostgREST obtiene datos filtrados por empresa_id
  3. Flutter genera PDF o Excel en memoria
  4. Usuario elige: ver en pantalla, descargar, imprimir, enviar por email
  5. (Opcional) Guardar copia en Supabase Storage

EDGE FUNCTIONS para reportes complejos:
  - ATS → genera XML ISO-8859-1 + ZIP en servidor
  - RIDE → genera PDF en servidor (disponible offline via cache)
  - Estados Financieros → calcula desde RPCs, formatea en Flutter

DOCUMENTOS IMPRIMIBLES (syncfusion_flutter_pdf + package:printing):
  Todos estos documentos se pueden ver en pantalla, imprimir o guardar PDF:
  - Comprobante de Cobro: recibo entregado al cliente al registrar pago
    (datos empresa, cliente, fecha, documentos pagados, metodos, total)
  - Comprobante de Pago: comprobante interno de pago a proveedor
    (datos empresa, proveedor, fecha, facturas pagadas, metodos, total)
  - Plan de Pagos: documento con detalle de CxP seleccionadas, montos,
    metodos de pago, resumen por proveedor y por metodo
  - Cheque impreso: formato para impresora de cheques con campos:
    (fecha, beneficiario, monto numerico, monto en letras, concepto)
    Soporta formatos pre-impresos de bancos ecuatorianos
  - Asiento Contable: comprobante contable con lineas debe/haber,
    fecha, descripcion, origen, totales balanceados
  - Estado de Cuenta: movimientos de un cliente/proveedor por periodo
  - Reporte Cartera Vencida: aging report por contacto con totales
```

## Calendario Tributario Anual

```
ENERO:    RDEP (anual anterior), F107 a empleados
FEBRERO:  APS (composicion societaria)
MARZO:    IR Personas Naturales (F102), Decimo 4to (Costa/Galapagos)
ABRIL:    IR Sociedades (F101), Utilidades 15%, EEFF a Supercias
MAYO:     OPR personas naturales (partes relacionadas)
JUNIO:    OPR sociedades
AGOSTO:   Decimo 4to (Sierra/Oriente)
DICIEMBRE: Decimo 3er sueldo

CADA MES:  F103 (Retenciones IR), F104 (IVA), ATS
           Planillas IESS, Conciliacion bancaria
```

---

