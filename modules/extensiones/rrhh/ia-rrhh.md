# IA para RRHH


### Descripcion Funcional

1. **Prediccion de ausentismo:** Analisis de patrones historicos de faltas por empleado, identificando correlaciones con dia de la semana, mes, temporada y eventos. Genera alertas proactivas.

2. **Optimizacion de turnos:** Dado un conjunto de empleados, horarios y restricciones (horas maximas, descansos obligatorios, preferencias), sugiere asignacion de turnos que minimice costo y maximice cobertura.

3. **Deteccion de horas extras anomalas:** Identifica empleados con acumulacion inusual de horas extras respecto a su promedio y al promedio del departamento. Alerta sobre posible sobrecarga o fraude de marcaciones.

### Modelo de Datos - RRHH IA

```sql
-- ============================================================
-- VISTA MATERIALIZADA: Patrones de asistencia por empleado
-- ============================================================

CREATE MATERIALIZED VIEW mv_hr_attendance_patterns AS
SELECT
  a.empresa_id,
  a.empleado_id,
  e.nombre AS empleado_nombre,
  e.departamento_id,
  d.nombre AS departamento_nombre,
  EXTRACT(DOW FROM a.fecha) AS dia_semana,
  EXTRACT(MONTH FROM a.fecha) AS mes,
  a.tipo_novedad,
    -- FALTA_JUSTIFICADA, FALTA_INJUSTIFICADA, ATRASO, PERMISO, VACACION
  COUNT(*) AS ocurrencias,
  -- Tasa de ausentismo (faltas / dias laborables)
  COUNT(*) FILTER (WHERE a.tipo_novedad IN ('FALTA_JUSTIFICADA','FALTA_INJUSTIFICADA'))::DECIMAL /
    NULLIF(COUNT(DISTINCT a.fecha), 0) AS tasa_ausentismo
FROM asistencia_novedades a
JOIN empleados e ON e.id = a.empleado_id
LEFT JOIN departamentos d ON d.id = e.departamento_id
WHERE a.fecha >= CURRENT_DATE - INTERVAL '365 days'
GROUP BY a.empresa_id, a.empleado_id, e.nombre, e.departamento_id,
         d.nombre, EXTRACT(DOW FROM a.fecha), EXTRACT(MONTH FROM a.fecha),
         a.tipo_novedad
WITH DATA;

CREATE INDEX idx_mv_hr_patterns_emp
  ON mv_hr_attendance_patterns(empresa_id, empleado_id);

-- ============================================================
-- VISTA MATERIALIZADA: Horas extras por empleado/periodo
-- ============================================================

CREATE MATERIALIZED VIEW mv_hr_overtime AS
SELECT
  a.empresa_id,
  a.empleado_id,
  e.nombre AS empleado_nombre,
  e.departamento_id,
  d.nombre AS departamento_nombre,
  DATE_TRUNC('week', a.fecha) AS semana,
  DATE_TRUNC('month', a.fecha) AS mes,
  SUM(a.horas_extra_50) AS he_50_total,
  SUM(a.horas_extra_100) AS he_100_total,
  SUM(a.horas_extra_50 + a.horas_extra_100) AS he_total,
  SUM(a.horas_extra_50 * e.sueldo_hora * 1.5 +
      a.horas_extra_100 * e.sueldo_hora * 2.0) AS costo_he
FROM asistencia a
JOIN empleados e ON e.id = a.empleado_id
LEFT JOIN departamentos d ON d.id = e.departamento_id
WHERE a.fecha >= CURRENT_DATE - INTERVAL '180 days'
GROUP BY a.empresa_id, a.empleado_id, e.nombre, e.departamento_id,
         d.nombre, DATE_TRUNC('week', a.fecha), DATE_TRUNC('month', a.fecha)
WITH DATA;

CREATE INDEX idx_mv_hr_overtime_emp
  ON mv_hr_overtime(empresa_id, empleado_id, semana);
```

### Funciones PostgreSQL - RRHH IA

```sql
-- ============================================================
-- FN_PREDICCION_AUSENTISMO
-- ============================================================

CREATE OR REPLACE FUNCTION fn_prediccion_ausentismo(
  p_empresa_id UUID,
  p_horizonte_dias INTEGER DEFAULT 30
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_resultado JSONB := '[]'::JSONB;
  v_emp RECORD;
  v_score DECIMAL(5,2);
BEGIN
  FOR v_emp IN
    SELECT
      empleado_id,
      empleado_nombre,
      departamento_nombre,
      -- Tasa general de ausentismo (ultimos 12 meses)
      COALESCE(SUM(ocurrencias) FILTER (
        WHERE tipo_novedad IN ('FALTA_JUSTIFICADA','FALTA_INJUSTIFICADA')
      ), 0) AS total_faltas,
      -- Dia con mas faltas
      (SELECT dia_semana FROM mv_hr_attendance_patterns p2
       WHERE p2.empleado_id = p.empleado_id AND p2.empresa_id = p_empresa_id
         AND p2.tipo_novedad IN ('FALTA_JUSTIFICADA','FALTA_INJUSTIFICADA')
       GROUP BY dia_semana ORDER BY SUM(ocurrencias) DESC LIMIT 1
      ) AS dia_mas_faltas,
      -- Mes con mas faltas
      (SELECT mes FROM mv_hr_attendance_patterns p2
       WHERE p2.empleado_id = p.empleado_id AND p2.empresa_id = p_empresa_id
         AND p2.tipo_novedad IN ('FALTA_JUSTIFICADA','FALTA_INJUSTIFICADA')
       GROUP BY mes ORDER BY SUM(ocurrencias) DESC LIMIT 1
      ) AS mes_mas_faltas,
      -- Atrasos frecuentes (indicador de desvinculacion)
      COALESCE(SUM(ocurrencias) FILTER (WHERE tipo_novedad = 'ATRASO'), 0) AS total_atrasos
    FROM mv_hr_attendance_patterns p
    WHERE empresa_id = p_empresa_id
    GROUP BY empleado_id, empleado_nombre, departamento_nombre
    HAVING SUM(ocurrencias) FILTER (
      WHERE tipo_novedad IN ('FALTA_JUSTIFICADA','FALTA_INJUSTIFICADA')
    ) > 0
    ORDER BY SUM(ocurrencias) FILTER (
      WHERE tipo_novedad IN ('FALTA_JUSTIFICADA','FALTA_INJUSTIFICADA')
    ) DESC
  LOOP
    -- Score de riesgo de ausentismo (0-100)
    v_score := LEAST(100,
      v_emp.total_faltas * 5 +  -- 5 puntos por falta
      v_emp.total_atrasos * 2 + -- 2 puntos por atraso
      CASE WHEN v_emp.dia_mas_faltas IN (1, 5) THEN 15 ELSE 0 END  -- lunes/viernes = patron
    );

    IF v_score >= 30 THEN
      v_resultado := v_resultado || jsonb_build_object(
        'empleado_id', v_emp.empleado_id,
        'nombre', v_emp.empleado_nombre,
        'departamento', v_emp.departamento_nombre,
        'score_riesgo', v_score,
        'total_faltas_12m', v_emp.total_faltas,
        'total_atrasos_12m', v_emp.total_atrasos,
        'dia_critico', CASE v_emp.dia_mas_faltas
          WHEN 0 THEN 'Domingo' WHEN 1 THEN 'Lunes' WHEN 2 THEN 'Martes'
          WHEN 3 THEN 'Miercoles' WHEN 4 THEN 'Jueves'
          WHEN 5 THEN 'Viernes' WHEN 6 THEN 'Sabado' END,
        'mes_critico', v_emp.mes_mas_faltas,
        'prediccion', FORMAT('Probabilidad %s%% de falta en los proximos %s dias. Dia critico: %s.',
          LEAST(v_score, 95), p_horizonte_dias,
          CASE v_emp.dia_mas_faltas
            WHEN 1 THEN 'Lunes' WHEN 5 THEN 'Viernes' ELSE 'variable' END)
      );
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'predicciones', v_resultado,
    'total_riesgo_alto', (SELECT COUNT(*) FROM jsonb_array_elements(v_resultado) e
      WHERE (e->>'score_riesgo')::DECIMAL >= 60)
  );
END;
$$;

-- ============================================================
-- FN_DETECTAR_HORAS_EXTRAS_ANOMALAS
-- ============================================================

CREATE OR REPLACE FUNCTION fn_detectar_horas_extras_anomalas(
  p_empresa_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_resultado JSONB := '[]'::JSONB;
  v_emp RECORD;
BEGIN
  FOR v_emp IN
    SELECT
      o.empleado_id,
      o.empleado_nombre,
      o.departamento_nombre,
      -- HE del ultimo mes
      SUM(o.he_total) FILTER (WHERE o.mes = DATE_TRUNC('month', CURRENT_DATE)) AS he_mes_actual,
      -- Promedio HE mensual historico
      AVG(monthly.he_mensual) AS he_promedio_mensual,
      STDDEV(monthly.he_mensual) AS he_stddev_mensual,
      -- Promedio del departamento
      dept.he_promedio_dept,
      -- Costo HE del mes
      SUM(o.costo_he) FILTER (WHERE o.mes = DATE_TRUNC('month', CURRENT_DATE)) AS costo_he_mes
    FROM mv_hr_overtime o
    LEFT JOIN (
      SELECT empleado_id, mes, SUM(he_total) AS he_mensual
      FROM mv_hr_overtime WHERE empresa_id = p_empresa_id
      GROUP BY empleado_id, mes
    ) monthly ON monthly.empleado_id = o.empleado_id
    LEFT JOIN (
      SELECT departamento_id, AVG(he_total_dept) AS he_promedio_dept
      FROM (
        SELECT departamento_id, mes, SUM(he_total) AS he_total_dept
        FROM mv_hr_overtime WHERE empresa_id = p_empresa_id
        GROUP BY departamento_id, mes
      ) sub
      GROUP BY departamento_id
    ) dept ON dept.departamento_id = o.departamento_id
    WHERE o.empresa_id = p_empresa_id
    GROUP BY o.empleado_id, o.empleado_nombre, o.departamento_nombre, dept.he_promedio_dept
    HAVING SUM(o.he_total) FILTER (WHERE o.mes = DATE_TRUNC('month', CURRENT_DATE)) >
           AVG(monthly.he_mensual) + 2 * COALESCE(STDDEV(monthly.he_mensual), 0)
      -- HE del mes > promedio + 2 stddev
  LOOP
    v_resultado := v_resultado || jsonb_build_object(
      'empleado_id', v_emp.empleado_id,
      'nombre', v_emp.empleado_nombre,
      'departamento', v_emp.departamento_nombre,
      'he_mes_actual', ROUND(v_emp.he_mes_actual, 1),
      'he_promedio_mensual', ROUND(v_emp.he_promedio_mensual, 1),
      'ratio_vs_promedio', ROUND(v_emp.he_mes_actual / NULLIF(v_emp.he_promedio_mensual, 0), 1),
      'he_promedio_departamento', ROUND(COALESCE(v_emp.he_promedio_dept, 0), 1),
      'costo_he_mes', ROUND(v_emp.costo_he_mes, 2),
      'alerta', FORMAT('%s tiene %s HE este mes vs promedio de %s (%sx). Costo: $%s.',
        v_emp.empleado_nombre, ROUND(v_emp.he_mes_actual, 1),
        ROUND(v_emp.he_promedio_mensual, 1),
        ROUND(v_emp.he_mes_actual / NULLIF(v_emp.he_promedio_mensual, 0), 1),
        ROUND(v_emp.costo_he_mes, 2))
    );

    -- Crear alerta
    INSERT INTO alertas_anomalias
      (empresa_id, tipo, severidad, descripcion, datos, modulo, subtipo, accion_sugerida)
    VALUES
      (p_empresa_id, 'HORARIO_INUSUAL',
       CASE WHEN v_emp.he_mes_actual > v_emp.he_promedio_mensual * 3 THEN 'ALTA' ELSE 'MEDIA' END,
       FORMAT('HE anomalas: %s tiene %sh este mes (promedio: %sh)',
         v_emp.empleado_nombre, ROUND(v_emp.he_mes_actual, 1),
         ROUND(v_emp.he_promedio_mensual, 1)),
       jsonb_build_object('empleado_id', v_emp.empleado_id,
         'he_actual', v_emp.he_mes_actual, 'he_promedio', v_emp.he_promedio_mensual),
       'RRHH', 'HE_ANOMALA',
       FORMAT('Revisar carga laboral de %s. Verificar marcaciones.', v_emp.empleado_nombre))
    ON CONFLICT DO NOTHING;
  END LOOP;

  RETURN jsonb_build_object('empleados_anomalos', v_resultado,
    'total', jsonb_array_length(v_resultado));
END;
$$;
```

### Flujo UI/UX - RRHH IA

```
PANTALLA: Dashboard IA RRHH (dentro del modulo RRHH)
├── Tab: Ausentismo
│   ├── Heatmap: empleados (filas) x dias semana (columnas), color = frecuencia faltas
│   ├── Lista top 10 empleados con mayor riesgo (ordenado por score)
│   ├── Cada item: Nombre | Depto | Score | Faltas 12m | Dia critico | Prediccion
│   └── KPI: Tasa ausentismo empresa | Costo estimado ausentismo mensual
│
├── Tab: Horas Extras
│   ├── Grafico barras: HE por departamento (mes actual vs promedio)
│   ├── Lista empleados con HE anomalas (flag rojo si >2x promedio)
│   ├── Cada item: Nombre | Depto | HE mes | HE promedio | Ratio | Costo
│   └── KPI: Costo total HE mes | Empleados con anomalia
│
└── Tab: Turnos (futuro P3)
    ├── Calendario visual: turnos propuestos por IA
    ├── Restricciones configurables: max horas, descansos, preferencias
    └── Boton: "Optimizar turnos" → genera propuesta
```

---

