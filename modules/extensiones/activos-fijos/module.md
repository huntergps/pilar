# Módulo de Activos Fijos


```
features/activos_fijos/
  ├── screens/
  │   ├── assets_screen.dart            # Listado activos (SfDataGrid)
  │   ├── asset_form_screen.dart        # Registro/edicion activo
  │   ├── asset_detail_screen.dart      # Detalle con historial depreciacion
  │   ├── depreciation_screen.dart      # Proceso depreciacion mensual
  │   ├── revaluation_screen.dart       # Revaluacion de activos
  │   ├── disposal_screen.dart          # Baja/venta de activos
  │   ├── transfer_screen.dart          # Transferencia entre sucursales
  │   └── asset_reports_screen.dart     # Reportes de activos
  ├── providers/
  │   ├── asset_provider.dart
  │   └── depreciation_provider.dart
  └── models/
```

**Modelo de Datos - Activos Fijos**

```sql
categorias_activo
  id              UUID PK
  empresa_id      UUID FK -> empresas
  nombre          VARCHAR(100) NOT NULL
  tipo            VARCHAR(30) NOT NULL
    -- TERRENO, EDIFICIO, MAQUINARIA, VEHICULO, EQUIPO_COMPUTO,
    -- SOFTWARE, MUEBLES, INSTALACIONES, OTROS
  -- Depreciacion segun normativa Ecuador
  vida_util_anios INTEGER NOT NULL       -- 20, 10, 5, 3 segun tipo
  porcentaje_anual DECIMAL(5,2) NOT NULL -- 5%, 10%, 20%, 33%
  -- Cuentas contables
  cuenta_activo_id UUID FK -> cuentas_contables    -- Ej: 1.2.01 Edificios
  cuenta_depreciacion_id UUID FK -> cuentas_contables -- Ej: 1.2.99 Dep. Acum.
  cuenta_gasto_id UUID FK -> cuentas_contables     -- Ej: 5.1.08 Gasto Dep.
  cuenta_baja_id UUID FK -> cuentas_contables      -- Ej: 4.2.01 Perdida baja

activos_fijos
  id              UUID PK
  empresa_id      UUID FK -> empresas
  categoria_id    UUID FK -> categorias_activo
  codigo          VARCHAR(30) NOT NULL   -- Codigo interno del activo
  descripcion     VARCHAR(300) NOT NULL
  marca           VARCHAR(100)
  modelo          VARCHAR(100)
  serie           VARCHAR(100)           -- Numero de serie
  -- Ubicacion
  establecimiento_id UUID FK -> establecimientos
  ubicacion       VARCHAR(200)           -- 'Piso 2, Oficina 201'
  responsable_id  UUID FK -> empleados   -- Custodio
  -- Valores
  fecha_adquisicion DATE NOT NULL
  costo_adquisicion DECIMAL(14,2) NOT NULL
  valor_residual  DECIMAL(14,2) DEFAULT 0  -- Valor de salvamento
  -- Depreciacion
  metodo_depreciacion VARCHAR(20) DEFAULT 'LINEA_RECTA'
    -- LINEA_RECTA (principal en Ecuador)
    -- ACELERADA (requiere autorizacion SRI, solo activos nuevos >5 anios vida util)
  vida_util_meses INTEGER NOT NULL
  depreciacion_acumulada DECIMAL(14,2) DEFAULT 0
  valor_en_libros DECIMAL(14,2)          -- costo - dep_acumulada
  -- Fechas
  fecha_inicio_depreciacion DATE         -- Puede diferir de adquisicion
  fecha_baja      DATE                   -- Si fue dado de baja
  -- Estado
  estado          VARCHAR(20) DEFAULT 'ACTIVO'
    -- ACTIVO, DEPRECIADO_TOTAL, DADO_DE_BAJA, VENDIDO, TRANSFERIDO
  -- Documento de compra
  factura_compra_id UUID FK -> facturas  -- Factura de adquisicion
  documento_url   TEXT                   -- Documento en Storage
  notas           TEXT
  UNIQUE(empresa_id, codigo)

depreciacion_mensual
  id              UUID PK
  empresa_id      UUID FK -> empresas
  activo_id       UUID FK -> activos_fijos
  anio            INTEGER NOT NULL
  mes             INTEGER NOT NULL
  monto_depreciacion DECIMAL(14,2) NOT NULL
  depreciacion_acumulada DECIMAL(14,2) NOT NULL  -- Acumulado hasta este mes
  valor_en_libros DECIMAL(14,2) NOT NULL
  asiento_id      UUID FK -> asientos_contables  -- Asiento automatico
  UNIQUE(activo_id, anio, mes)

movimientos_activo  -- Historial de cambios
  id              UUID PK
  activo_id       UUID FK -> activos_fijos
  tipo            VARCHAR(20) NOT NULL
    -- ADQUISICION, DEPRECIACION, REVALUACION, MEJORA, BAJA, VENTA, TRANSFERENCIA
  fecha           DATE NOT NULL
  descripcion     TEXT
  monto           DECIMAL(14,2)
  asiento_id      UUID FK -> asientos_contables
  usuario_id      UUID FK -> auth.users
```

**Depreciacion Ecuador (Normativa SRI)**

```
╔══════════════════════════════════════════════════════════════════════════╗
║  DEPRECIACION LINEA RECTA (metodo principal en Ecuador)                ║
╠══════════════════════════════════════════════════════════════════════════╣
║                                                                        ║
║  Tipo Activo           │ Vida Util │ % Anual │ % Mensual              ║
║  ──────────────────────┼───────────┼─────────┼──────────              ║
║  Terrenos              │ N/A       │ 0%      │ No deprecia            ║
║  Edificios             │ 20 anios  │ 5%      │ 0.4167%               ║
║  Maquinaria/Equipos    │ 10 anios  │ 10%     │ 0.8333%               ║
║  Muebles/Enseres       │ 10 anios  │ 10%     │ 0.8333%               ║
║  Vehiculos             │ 5 anios   │ 20%     │ 1.6667%               ║
║  Equipos de Computo    │ 3 anios   │ 33%     │ 2.7500%               ║
║  Software              │ 3 anios   │ 33%     │ 2.7500%               ║
║                                                                        ║
║  Formula mensual:                                                      ║
║  dep_mensual = (costo_adquisicion - valor_residual) / vida_util_meses ║
║                                                                        ║
║  Depreciacion acelerada (con autorizacion SRI):                        ║
║  - Solo activos NUEVOS con vida util >= 5 anios                        ║
║  - Maximo el doble de la tasa normal                                   ║
║  - Requiere autorizacion del Director Regional del SRI                 ║
║                                                                        ║
║  Revaluacion de activos:                                               ║
║  - Permitida bajo NIIF (NIC 16)                                        ║
║  - La depreciacion por revaluacion NO es deducible tributariamente     ║
╚══════════════════════════════════════════════════════════════════════════╝
```

```sql
-- RPC: Proceso mensual de depreciacion
CREATE OR REPLACE FUNCTION process_depreciation(
  p_empresa_id UUID, p_anio INTEGER, p_mes INTEGER
) RETURNS INTEGER  -- Retorna cantidad de activos depreciados
LANGUAGE plpgsql SECURITY DEFINER AS $$
  -- 1. Obtener activos con estado='ACTIVO' y dep_acumulada < (costo - residual)
  -- 2. Para cada activo:
  --    dep_mensual = (costo - residual) / vida_util_meses
  --    INSERT depreciacion_mensual
  --    UPDATE activos_fijos SET depreciacion_acumulada += dep_mensual
  -- 3. Generar asiento contable:
  --    Debe: Gasto depreciacion (cuenta_gasto_id)
  --    Haber: Depreciacion acumulada (cuenta_depreciacion_id)
  -- 4. Si dep_acumulada >= (costo - residual) → estado = 'DEPRECIADO_TOTAL'
$$;

-- ══════════════════════════════════════════════════════════════════
-- RPC: Capitalizar mejora sobre un activo fijo existente (G-AF-01)
-- Incrementa valor, recalcula depreciacion restante, genera asiento
-- ══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION capitalize_improvement(
  p_activo_id UUID,
  p_monto DECIMAL(14,2),
  p_descripcion TEXT,
  p_fecha DATE DEFAULT CURRENT_DATE
) RETURNS UUID  -- Retorna asiento_id generado
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_activo activos_fijos%ROWTYPE;
  v_meses_restantes INTEGER;
  v_asiento_id UUID;
BEGIN
  SELECT * INTO v_activo FROM activos_fijos WHERE id = p_activo_id AND estado = 'ACTIVO';
  IF v_activo.id IS NULL THEN RAISE EXCEPTION 'Activo no encontrado o no activo'; END IF;

  -- Calcular meses restantes de vida util
  v_meses_restantes := v_activo.vida_util_meses -
    EXTRACT(MONTH FROM AGE(p_fecha, v_activo.fecha_inicio_depreciacion))::INTEGER;
  IF v_meses_restantes <= 0 THEN RAISE EXCEPTION 'Activo ya completamente depreciado'; END IF;

  -- Incrementar valor del activo
  UPDATE activos_fijos SET
    costo_adquisicion = costo_adquisicion + p_monto,
    valor_en_libros = (costo_adquisicion + p_monto) - depreciacion_acumulada,
    updated_at = now()
  WHERE id = p_activo_id;

  -- Generar asiento contable: Db Activo Fijo / Cr Banco o CxP
  v_asiento_id := module_bus.create_journal_entry(
    v_activo.empresa_id, p_fecha, 'MEJORA_ACTIVO',
    jsonb_build_array(
      jsonb_build_object('cuenta_id', (SELECT cuenta_activo_id FROM categorias_activo WHERE id = v_activo.categoria_id), 'debe', p_monto),
      jsonb_build_object('cuenta_id', (SELECT cuenta_baja_id FROM categorias_activo WHERE id = v_activo.categoria_id), 'haber', p_monto)
    ),
    'Mejora activo ' || v_activo.codigo || ': ' || p_descripcion
  );

  -- Registrar en historial
  INSERT INTO movimientos_activo (activo_id, tipo, fecha, descripcion, monto, asiento_id, usuario_id)
  VALUES (p_activo_id, 'MEJORA', p_fecha, p_descripcion, p_monto, v_asiento_id, auth.uid());

  -- Nota: la depreciacion mensual futura se recalcula automaticamente en process_depreciation()
  -- usando: dep_mensual = (costo_adquisicion - valor_residual - depreciacion_acumulada) / meses_restantes
  RETURN v_asiento_id;
END;
$$;

-- ══════════════════════════════════════════════════════════════════
-- RPC: Baja o venta de activo fijo con ganancia/perdida (G-AF-02)
-- Genera asiento contable completo y marca activo como DADO_DE_BAJA o VENDIDO
-- ══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION dispose_fixed_asset(
  p_activo_id UUID,
  p_tipo VARCHAR(10),                    -- 'BAJA' o 'VENTA'
  p_monto_venta DECIMAL(14,2) DEFAULT 0, -- Solo aplica si p_tipo = 'VENTA'
  p_fecha DATE DEFAULT CURRENT_DATE
) RETURNS JSONB  -- {valor_libros, ganancia_perdida, asiento_id}
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_activo activos_fijos%ROWTYPE;
  v_cat categorias_activo%ROWTYPE;
  v_valor_libros DECIMAL(14,2);
  v_ganancia_perdida DECIMAL(14,2);
  v_asiento_id UUID;
  v_lineas JSONB := '[]'::JSONB;
BEGIN
  SELECT * INTO v_activo FROM activos_fijos WHERE id = p_activo_id AND estado = 'ACTIVO';
  IF v_activo.id IS NULL THEN RAISE EXCEPTION 'Activo no encontrado o ya dado de baja'; END IF;
  SELECT * INTO v_cat FROM categorias_activo WHERE id = v_activo.categoria_id;

  v_valor_libros := v_activo.costo_adquisicion - v_activo.depreciacion_acumulada;

  IF p_tipo = 'VENTA' THEN
    v_ganancia_perdida := p_monto_venta - v_valor_libros;
  ELSE
    v_ganancia_perdida := -v_valor_libros; -- Perdida total en baja
  END IF;

  -- Construir lineas del asiento:
  -- Db: Depreciacion Acumulada (cancelar acumulada)
  v_lineas := v_lineas || jsonb_build_object('cuenta_id', v_cat.cuenta_depreciacion_id, 'debe', v_activo.depreciacion_acumulada);
  -- Db: Banco/CxC (si venta, por monto_venta)
  IF p_tipo = 'VENTA' AND p_monto_venta > 0 THEN
    v_lineas := v_lineas || jsonb_build_object('cuenta_id', v_cat.cuenta_baja_id, 'debe', p_monto_venta);
  END IF;
  -- Db/Cr: Ganancia o Perdida en venta/baja de activo fijo
  IF v_ganancia_perdida < 0 THEN
    v_lineas := v_lineas || jsonb_build_object('cuenta_id', v_cat.cuenta_baja_id, 'debe', ABS(v_ganancia_perdida));
  ELSIF v_ganancia_perdida > 0 THEN
    v_lineas := v_lineas || jsonb_build_object('cuenta_id', v_cat.cuenta_baja_id, 'haber', v_ganancia_perdida);
  END IF;
  -- Cr: Activo Fijo (cancelar valor original completo)
  v_lineas := v_lineas || jsonb_build_object('cuenta_id', v_cat.cuenta_activo_id, 'haber', v_activo.costo_adquisicion);

  v_asiento_id := module_bus.create_journal_entry(
    v_activo.empresa_id, p_fecha,
    CASE p_tipo WHEN 'VENTA' THEN 'VENTA_ACTIVO' ELSE 'BAJA_ACTIVO' END,
    v_lineas,
    p_tipo || ' activo ' || v_activo.codigo || ': ' || v_activo.descripcion
  );

  -- Actualizar estado del activo
  UPDATE activos_fijos SET
    estado = CASE p_tipo WHEN 'VENTA' THEN 'VENDIDO' ELSE 'DADO_DE_BAJA' END,
    fecha_baja = p_fecha,
    updated_at = now()
  WHERE id = p_activo_id;

  -- Registrar movimiento en historial
  INSERT INTO movimientos_activo (activo_id, tipo, fecha, descripcion, monto, asiento_id, usuario_id)
  VALUES (p_activo_id, p_tipo, p_fecha,
    p_tipo || ': valor_libros=' || v_valor_libros || ', ganancia_perdida=' || v_ganancia_perdida,
    COALESCE(p_monto_venta, 0), v_asiento_id, auth.uid());

  RETURN jsonb_build_object(
    'valor_libros', v_valor_libros,
    'ganancia_perdida', v_ganancia_perdida,
    'asiento_id', v_asiento_id
  );
END;
$$;
```

**Depreciacion Fiscal vs Contable (G-AF-03)**

```sql
-- Campos adicionales en activos_fijos para doble pista de depreciacion:
--   vida_util_fiscal INTEGER          -- Vida util segun tabla SRI
--   metodo_depreciacion_fiscal VARCHAR(20) DEFAULT 'LINEA_RECTA'
--   depreciacion_acumulada_fiscal DECIMAL(14,2) DEFAULT 0
-- NIIF puede requerir vida util diferente a la fiscal (Ej: edificio NIIF 30 anios vs SRI 20).
-- Dos tracks paralelos de depreciacion, conciliacion al cierre anual.
-- process_depreciation() calcula ambos tracks y genera asiento contable (NIIF).
```

**Inventario Fisico de Activos (G-AF-04)**

```sql
CREATE TABLE constataciones_activos (
  id UUID PK, empresa_id UUID FK, fecha DATE NOT NULL,
  responsable_id UUID FK -> empleados,
  estado VARCHAR(20) DEFAULT 'PLANIFICADA' -- PLANIFICADA/EN_CURSO/COMPLETADA
);
CREATE TABLE constatacion_activo_lineas (
  id UUID PK, constatacion_id UUID FK -> constataciones_activos ON DELETE CASCADE,
  activo_id UUID FK -> activos_fijos,
  ubicacion_esperada VARCHAR(200), ubicacion_real VARCHAR(200),
  estado VARCHAR(20) DEFAULT 'PENDIENTE', -- ENCONTRADO/NO_ENCONTRADO/REUBICADO
  observaciones TEXT
);
-- Flujo: escanear QR/codigo barras con movil -> marcar ENCONTRADO + ubicacion GPS.
-- Reporte: activos faltantes, reubicados, % cobertura constatacion.
```

**Codigo QR/Barras para Activos (G-AF-05)**

```sql
-- Cada activo genera QR con {activo_id, codigo, descripcion}.
-- Etiquetas impresas via Syncfusion PDF (layout grid A4, multiples etiquetas por hoja).
-- Escaneo movil (camera) -> muestra ficha del activo (detalle + custodio + ubicacion).
-- QR almacenado como SVG en Supabase Storage: assets/{empresa_id}/qr/{activo_id}.svg
-- Campo en activos_fijos: qr_url TEXT (URL del SVG generado)
```

**Mantenimiento Preventivo Activos (G-AF-06)**

```sql
CREATE TABLE programacion_mantenimiento (
  id UUID PK, empresa_id UUID FK, activo_id UUID FK -> activos_fijos,
  tipo VARCHAR(20) NOT NULL, -- PREVENTIVO/CORRECTIVO
  descripcion TEXT, frecuencia_meses INTEGER,
  ultimo_mantenimiento DATE,
  proximo_mantenimiento DATE GENERATED ALWAYS AS
    (ultimo_mantenimiento + (frecuencia_meses || ' months')::INTERVAL)::DATE STORED,
  responsable_id UUID FK -> empleados, costo_estimado DECIMAL(14,2)
);
CREATE TABLE historial_mantenimiento (
  id UUID PK, programacion_id UUID FK -> programacion_mantenimiento,
  fecha DATE NOT NULL, descripcion TEXT,
  costo_real DECIMAL(14,2), tecnico_id UUID FK -> empleados, notas TEXT
);
-- Cron diario: alertar mantenimientos proximos (< 7 dias) via notificaciones
```

---

## Tablas Adicionales: Mejoras y Bajas de Activos

### Tabla: `mejoras_activo`

```sql
CREATE TABLE mejoras_activo (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id UUID NOT NULL REFERENCES empresas(id),
  activo_id UUID NOT NULL REFERENCES activos_fijos(id),
  descripcion VARCHAR(300) NOT NULL,
  costo DECIMAL(14,2) NOT NULL,
  fecha DATE NOT NULL,
  tipo VARCHAR(15) CHECK (tipo IN ('MEJORA','MANTENIMIENTO','REPARACION')),
  -- Solo el tipo MEJORA capitaliza (aumenta el valor del activo en libros)
  capitaliza BOOLEAN DEFAULT false,
  proveedor_id UUID REFERENCES contactos(id),
  factura_proveedor_id UUID,              -- Referencia a facturas_proveedor
  asiento_id UUID,                        -- Asiento contable generado
  created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE mejoras_activo ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON mejoras_activo FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE INDEX idx_mejoras_activo ON mejoras_activo(activo_id, fecha DESC);
CREATE INDEX idx_mejoras_empresa ON mejoras_activo(empresa_id, tipo);
```

### Tabla: `bajas_activo`

```sql
CREATE TABLE bajas_activo (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id UUID NOT NULL REFERENCES empresas(id),
  activo_id UUID NOT NULL REFERENCES activos_fijos(id),
  fecha DATE NOT NULL,
  motivo VARCHAR(20) CHECK (motivo IN ('VENTA','DONACION','ROBO','SINIESTRO','OBSOLESCENCIA','SCRAP')),
  valor_libro DECIMAL(14,2),                            -- Valor neto al momento de baja
  valor_residual_real DECIMAL(14,2) DEFAULT 0,          -- Lo efectivamente recuperado
  ganancia_perdida DECIMAL(14,2) GENERATED ALWAYS AS
    (valor_residual_real - COALESCE(valor_libro, 0)) STORED,
  descripcion TEXT,
  asiento_id UUID,                                      -- Asiento contable de baja
  created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE bajas_activo ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON bajas_activo FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE INDEX idx_bajas_activo ON bajas_activo(activo_id);
CREATE INDEX idx_bajas_empresa ON bajas_activo(empresa_id, fecha DESC);
```

---

## RPCs Adicionales de Activos Fijos

```sql
-- ══════════════════════════════════════════════════════════════
-- RPC: Depreciación masiva del período (mensual o anual)
-- Ejecuta depreciación para todos los activos activos de la empresa.
-- Agrupa por categoría y genera un único asiento por grupo.
-- Retorna resumen: activos procesados y total depreciación.
-- ══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION run_depreciation_period(
  p_empresa_id UUID,
  p_periodo VARCHAR   -- formato 'YYYY-MM' (ej: '2026-01')
) RETURNS JSONB  -- {activos_procesados, total_depreciacion, asientos_generados}
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_anio INTEGER := EXTRACT(YEAR FROM TO_DATE(p_periodo || '-01', 'YYYY-MM-DD'))::INTEGER;
  v_mes  INTEGER := EXTRACT(MONTH FROM TO_DATE(p_periodo || '-01', 'YYYY-MM-DD'))::INTEGER;
  v_activo RECORD;
  v_dep_mensual DECIMAL(14,2);
  v_meses_restantes INTEGER;
  v_total DECIMAL(14,2) := 0;
  v_procesados INTEGER := 0;
  v_asientos UUID[] := '{}';
  v_asiento_id UUID;
BEGIN
  -- Verificar que no se haya procesado este período
  IF EXISTS (
    SELECT 1 FROM depreciacion_mensual dm
    JOIN activos_fijos af ON af.id = dm.activo_id
    WHERE af.empresa_id = p_empresa_id AND dm.anio = v_anio AND dm.mes = v_mes
    LIMIT 1
  ) THEN
    RAISE EXCEPTION 'El período % ya fue procesado', p_periodo;
  END IF;

  FOR v_activo IN
    SELECT af.*, ca.cuenta_gasto_id, ca.cuenta_depreciacion_id
    FROM activos_fijos af
    JOIN categorias_activo ca ON ca.id = af.categoria_id
    WHERE af.empresa_id = p_empresa_id
      AND af.estado = 'ACTIVO'
      AND af.fecha_inicio_depreciacion IS NOT NULL
      AND af.depreciacion_acumulada < (af.costo_adquisicion - COALESCE(af.valor_residual, 0))
  LOOP
    -- Depreciación mensual = (costo - residual) / vida_util_meses
    v_dep_mensual := ROUND(
      (v_activo.costo_adquisicion - COALESCE(v_activo.valor_residual, 0)) /
      v_activo.vida_util_meses,
      2
    );

    -- No superar el valor neto restante
    v_dep_mensual := LEAST(
      v_dep_mensual,
      v_activo.costo_adquisicion - COALESCE(v_activo.valor_residual, 0) - v_activo.depreciacion_acumulada
    );

    IF v_dep_mensual <= 0 THEN CONTINUE; END IF;

    -- Generar asiento contable: Db Gasto Depreciación / Cr Depreciación Acumulada
    v_asiento_id := module_bus.contabilidad.create_journal_entry(
      p_empresa_id,
      (TO_DATE(p_periodo || '-01', 'YYYY-MM-DD') + INTERVAL '1 month - 1 day')::DATE,
      'DEPRECIACION',
      jsonb_build_array(
        jsonb_build_object('cuenta_id', v_activo.cuenta_gasto_id, 'debe', v_dep_mensual),
        jsonb_build_object('cuenta_id', v_activo.cuenta_depreciacion_id, 'haber', v_dep_mensual)
      ),
      'Depreciación ' || p_periodo || ' — ' || v_activo.descripcion
    );

    -- Registrar línea de depreciación
    INSERT INTO depreciacion_mensual (empresa_id, activo_id, anio, mes, monto_depreciacion,
      depreciacion_acumulada, valor_en_libros, asiento_id)
    VALUES (p_empresa_id, v_activo.id, v_anio, v_mes, v_dep_mensual,
      v_activo.depreciacion_acumulada + v_dep_mensual,
      v_activo.costo_adquisicion - (v_activo.depreciacion_acumulada + v_dep_mensual),
      v_asiento_id);

    -- Actualizar activo
    UPDATE activos_fijos SET
      depreciacion_acumulada = depreciacion_acumulada + v_dep_mensual,
      valor_en_libros = costo_adquisicion - (depreciacion_acumulada + v_dep_mensual),
      estado = CASE
        WHEN depreciacion_acumulada + v_dep_mensual >= (costo_adquisicion - COALESCE(valor_residual, 0))
        THEN 'DEPRECIADO_TOTAL' ELSE estado
      END,
      updated_at = NOW()
    WHERE id = v_activo.id;

    v_total := v_total + v_dep_mensual;
    v_procesados := v_procesados + 1;
    v_asientos := v_asientos || v_asiento_id;
  END LOOP;

  RETURN jsonb_build_object(
    'activos_procesados', v_procesados,
    'total_depreciacion', v_total,
    'asientos_generados', array_length(v_asientos, 1)
  );
END;
$$;

-- ══════════════════════════════════════════════════════════════
-- RPC: Revalorización de activo (NIIF NIC 16)
-- Ajusta el valor del activo al valor razonable, recalcula la
-- depreciación futura y genera asiento de revalorización.
-- NOTA: La depreciación adicional por revalorización NO es
-- deducible tributariamente (diferencia fiscal vs contable).
-- ══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION revalue_asset(
  p_activo_id UUID,
  p_nuevo_valor DECIMAL(14,2),
  p_fecha DATE DEFAULT CURRENT_DATE
) RETURNS JSONB  -- {diferencia_revaluacion, asiento_id}
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_activo activos_fijos%ROWTYPE;
  v_cat categorias_activo%ROWTYPE;
  v_valor_actual DECIMAL(14,2);
  v_diferencia DECIMAL(14,2);
  v_asiento_id UUID;
  v_empresa_id UUID := (SELECT private.get_empresa_id());
BEGIN
  SELECT * INTO v_activo FROM activos_fijos
  WHERE id = p_activo_id AND empresa_id = v_empresa_id AND estado = 'ACTIVO';
  IF v_activo.id IS NULL THEN RAISE EXCEPTION 'Activo no encontrado o no activo'; END IF;
  SELECT * INTO v_cat FROM categorias_activo WHERE id = v_activo.categoria_id;

  v_valor_actual := v_activo.costo_adquisicion - v_activo.depreciacion_acumulada;
  v_diferencia := p_nuevo_valor - v_valor_actual;

  IF ABS(v_diferencia) < 0.01 THEN RAISE EXCEPTION 'El nuevo valor es igual al valor actual'; END IF;

  -- Asiento de revalorización:
  -- Si diferencia > 0: Db Activo Fijo / Cr Superávit por Revalorización (Patrimonio)
  -- Si diferencia < 0: Db Pérdida por Desvalorización / Cr Activo Fijo
  v_asiento_id := module_bus.contabilidad.create_journal_entry(
    v_empresa_id, p_fecha, 'REVALUACION_ACTIVO',
    CASE
      WHEN v_diferencia > 0 THEN jsonb_build_array(
        jsonb_build_object('cuenta_id', v_cat.cuenta_activo_id, 'debe', ABS(v_diferencia)),
        jsonb_build_object('cuenta_id', v_cat.cuenta_baja_id, 'haber', ABS(v_diferencia))
      )
      ELSE jsonb_build_array(
        jsonb_build_object('cuenta_id', v_cat.cuenta_baja_id, 'debe', ABS(v_diferencia)),
        jsonb_build_object('cuenta_id', v_cat.cuenta_activo_id, 'haber', ABS(v_diferencia))
      )
    END,
    'Revalorización activo ' || v_activo.codigo || ' a $' || p_nuevo_valor
  );

  -- Ajustar costo para que valor_en_libros = p_nuevo_valor
  UPDATE activos_fijos SET
    costo_adquisicion = v_activo.depreciacion_acumulada + p_nuevo_valor,
    valor_en_libros = p_nuevo_valor,
    updated_at = NOW()
  WHERE id = p_activo_id;

  INSERT INTO movimientos_activo (activo_id, tipo, fecha, descripcion, monto, asiento_id, usuario_id)
  VALUES (p_activo_id, 'REVALUACION', p_fecha,
    'Revalorización: de $' || v_valor_actual || ' a $' || p_nuevo_valor,
    v_diferencia, v_asiento_id, auth.uid());

  RETURN jsonb_build_object('diferencia_revaluacion', v_diferencia, 'asiento_id', v_asiento_id);
END;
$$;

-- ══════════════════════════════════════════════════════════════
-- RPC: Baja de activo con motivo y valor recuperado
-- Envuelve dispose_fixed_asset con registro en bajas_activo
-- y motivos ampliados (VENTA/DONACION/ROBO/SINIESTRO/etc.)
-- ══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION dispose_asset(
  p_activo_id UUID,
  p_motivo VARCHAR(20),           -- VENTA | DONACION | ROBO | SINIESTRO | OBSOLESCENCIA | SCRAP
  p_valor_recuperado DECIMAL(14,2) DEFAULT 0,
  p_descripcion TEXT DEFAULT NULL,
  p_fecha DATE DEFAULT CURRENT_DATE
) RETURNS JSONB  -- {valor_libro, ganancia_perdida, asiento_id, baja_id}
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_activo activos_fijos%ROWTYPE;
  v_resultado JSONB;
  v_baja_id UUID;
  v_empresa_id UUID := (SELECT private.get_empresa_id());
BEGIN
  SELECT * INTO v_activo FROM activos_fijos
  WHERE id = p_activo_id AND empresa_id = v_empresa_id AND estado = 'ACTIVO';
  IF v_activo.id IS NULL THEN RAISE EXCEPTION 'Activo no encontrado o ya dado de baja'; END IF;

  -- Reusar la función existente dispose_fixed_asset para el asiento
  v_resultado := dispose_fixed_asset(
    p_activo_id,
    CASE p_motivo WHEN 'VENTA' THEN 'VENTA' ELSE 'BAJA' END,
    p_valor_recuperado,
    p_fecha
  );

  -- Registrar en bajas_activo
  INSERT INTO bajas_activo (empresa_id, activo_id, fecha, motivo, valor_libro,
    valor_residual_real, descripcion, asiento_id)
  VALUES (v_empresa_id, p_activo_id, p_fecha, p_motivo,
    (v_resultado->>'valor_libros')::DECIMAL,
    p_valor_recuperado,
    p_descripcion,
    (v_resultado->>'asiento_id')::UUID)
  RETURNING id INTO v_baja_id;

  RETURN v_resultado || jsonb_build_object('baja_id', v_baja_id);
END;
$$;
```

---

## Depreciación Ecuador (Normativa SRI Detallada)

```
╔══════════════════════════════════════════════════════════════════════════╗
║  TASAS DE DEPRECIACIÓN SRI (Art. 28 RLRTI)                             ║
╠══════════════════════════════════════════════════════════════════════════╣
║                                                                        ║
║  Tipo de Activo          │ Vida Útil │ % Anual │ % Mensual            ║
║  ────────────────────────┼───────────┼─────────┼──────────            ║
║  Inmuebles (edificios)   │ 20 años   │ 5%      │ 0.4167%             ║
║  Muebles y enseres       │ 10 años   │ 10%     │ 0.8333%             ║
║  Maquinaria y equipo     │ 10 años   │ 10%     │ 0.8333%             ║
║  Vehículos de transporte │ 5 años    │ 20%     │ 1.6667%             ║
║  Equipos de cómputo      │ 3 años    │ 33.33%  │ 2.7778%             ║
║  Intangibles             │ Estimada  │ Según vida útil técnica        ║
║  Terrenos                │ N/A       │ 0%      │ No deprecian        ║
║                                                                        ║
║  Depreciación acelerada (requiere autorización SRI):                   ║
║  - Solo activos NUEVOS con vida útil >= 5 años                         ║
║  - Máximo el doble de la tasa normal                                   ║
║  - Autorización del Director Regional del SRI                          ║
║                                                                        ║
║  Revalorización (NIIF NIC 16):                                         ║
║  - Permitida contablemente                                             ║
║  - La depreciación adicional por revalorización NO es deducible SRI    ║
║  - Genera diferencia temporal → conciliación tributaria                ║
╚══════════════════════════════════════════════════════════════════════════╝
```

---

## Integración con Módulo Taller

Si un activo requiere mantenimiento correctivo o preventivo, el sistema puede crear
una orden de reparación en el módulo Taller vía Module Service Bus:

```sql
-- Crear orden de mantenimiento desde un activo
SELECT module_bus.taller.create_maintenance_order(
  p_empresa_id := empresa_id,
  p_activo_id  := activo_id,
  p_tipo       := 'PREVENTIVO',   -- PREVENTIVO | CORRECTIVO
  p_descripcion := 'Mantenimiento anual motor compresor',
  p_responsable_id := empleado_id
);
-- La función verifica si el módulo Taller está activo para la empresa.
-- Si no está activo, retorna NO-OP (no lanza error).
-- Los costos de mano de obra y materiales del Taller se registran
-- en mejoras_activo (tipo='MANTENIMIENTO') para trazabilidad contable.
```

**Flujo de costos Taller → Activos Fijos:**
1. Taller ejecuta la reparación y cierra la orden
2. Al cerrar, module_bus crea registro en `mejoras_activo` con `tipo='MANTENIMIENTO'`
3. Si el costo supera el umbral de capitalización: `capitaliza = true` → `capitalize_improvement()`
4. Si es mantenimiento ordinario: `capitaliza = false` → se registra como gasto del período

