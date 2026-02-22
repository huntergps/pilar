# Suscripciones Recurrentes


#### Descripcion Funcional

Modulo de suscripciones recurrentes para empresas de servicios (TV cable, internet, gimnasios, academias, SaaS, etc.). Complementa el modulo existente de Servicios/Contratos (15.2.6) con capacidad de facturacion automatica periodica, auto-renovacion, upgrade/downgrade de plan, suspension temporal y prorrateado.

**Diferencia con Servicios/Contratos existente:**
- Servicios/Contratos (15.2.6) tiene facturacion "bajo demanda" (el operador genera deudas manualmente)
- Suscripciones Recurrentes agrega facturacion AUTOMATICA con cron, auto-renovacion y gestion de ciclo de vida completa

**Flujo principal:**

```
CREACION:
  Cliente elige plan → se crea suscripcion → periodo de prueba (opcional)
  → primera factura prorrateada (si inicia a mitad de mes) → facturacion recurrente

CICLO DE VIDA:
  PRUEBA → ACTIVA → [SUSPENDIDA | GRACIA] → CANCELADA
                ↕
           UPGRADE/DOWNGRADE

FACTURACION AUTOMATICA (cron diario):
  1. Buscar suscripciones activas con fecha_proximo_cobro <= hoy
  2. Generar deuda/factura para el periodo
  3. Si tiene metodo de pago automatico: intentar cobro
  4. Si cobro falla: entrar en periodo de gracia
  5. Si periodo de gracia expira: suspender servicio
  6. Actualizar fecha_proximo_cobro al siguiente periodo

PRORRATEADO:
  - Inicio a mitad de periodo: cobro proporcional (dias_restantes / dias_periodo * tarifa)
  - Cancelacion a mitad de periodo: credito proporcional via NC
  - Upgrade a mitad de periodo: diferencia prorrateada cobrada inmediatamente
  - Downgrade: se aplica al siguiente periodo

NOTIFICACIONES:
  - X dias antes de cobro: "Su proximo cobro de $Y sera el DD/MM"
  - Cobro exitoso: "Se ha procesado su pago de $Y"
  - Cobro fallido: "No pudimos procesar su pago. Tiene Z dias de gracia"
  - Renovacion: "Su suscripcion se ha renovado por N meses"
  - Cancelacion: "Su suscripcion ha sido cancelada"
  - Periodo de prueba por vencer: "Su prueba gratuita termina en X dias"
```

#### Modelo de Datos SQL

```sql
-- ══════════════════════════════════════════════════════════════════
-- SUSCRIPCIONES RECURRENTES (22.3)
-- ══════════════════════════════════════════════════════════════════

-- Planes de suscripcion (catalogo)
CREATE TABLE suscripcion_planes (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id          UUID NOT NULL REFERENCES empresas(id),
  codigo              VARCHAR(30) NOT NULL,
  nombre              VARCHAR(200) NOT NULL,
  descripcion         TEXT,
  -- Producto vinculado (para facturacion SRI)
  producto_id         UUID NOT NULL REFERENCES productos(id),
  -- Precios por frecuencia
  precio_mensual      DECIMAL(14,2),
  precio_bimestral    DECIMAL(14,2),
  precio_trimestral   DECIMAL(14,2),
  precio_semestral    DECIMAL(14,2),
  precio_anual        DECIMAL(14,2),
  -- Frecuencias habilitadas
  frecuencias         JSONB DEFAULT '["MENSUAL"]',
    -- MENSUAL, BIMESTRAL, TRIMESTRAL, SEMESTRAL, ANUAL
  -- Periodo de prueba
  dias_prueba         INTEGER DEFAULT 0,                 -- 0 = sin prueba
  -- Configuracion
  auto_renovacion     BOOLEAN DEFAULT true,
  dias_gracia         INTEGER DEFAULT 5,                 -- Dias de gracia post-vencimiento
  permite_suspension  BOOLEAN DEFAULT true,              -- Permitir pausa/vacaciones
  max_dias_suspension INTEGER DEFAULT 30,                -- Maximo dias de pausa
  -- Impuestos
  codigo_iva          VARCHAR(4) DEFAULT '4',
  tarifa_iva          DECIMAL(5,2) DEFAULT 15.00,
  -- Contabilidad
  cuenta_ingreso_id   UUID REFERENCES cuentas_contables(id),
  -- Limites
  max_suscriptores    INTEGER,                           -- NULL = ilimitado
  suscriptores_actuales INTEGER DEFAULT 0,
  -- Estado
  activo              BOOLEAN DEFAULT true,
  created_at          TIMESTAMPTZ DEFAULT now(),
  updated_at          TIMESTAMPTZ DEFAULT now(),
  UNIQUE(empresa_id, codigo)
);

-- Caracteristicas/features del plan (para comparacion en UI)
CREATE TABLE suscripcion_plan_features (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_id             UUID NOT NULL REFERENCES suscripcion_planes(id) ON DELETE CASCADE,
  empresa_id          UUID NOT NULL REFERENCES empresas(id),
  nombre              VARCHAR(200) NOT NULL,              -- 'Usuarios ilimitados', '100 GB almacenamiento'
  valor               VARCHAR(100),                       -- '10', 'Ilimitado', 'Si'
  orden               INTEGER DEFAULT 0,
  incluido            BOOLEAN DEFAULT true                -- true = incluido, false = no incluido
);

-- Suscripcion del cliente
CREATE TABLE suscripciones (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id          UUID NOT NULL REFERENCES empresas(id),
  numero              VARCHAR(20) NOT NULL,               -- Secuencial por empresa
  contacto_id         UUID NOT NULL REFERENCES contactos(id),
  plan_id             UUID NOT NULL REFERENCES suscripcion_planes(id),
  -- Contrato de servicio vinculado (si aplica, para TV cable/internet)
  contrato_servicio_id UUID REFERENCES contratos_servicio(id),
  -- Frecuencia elegida
  frecuencia          VARCHAR(20) NOT NULL DEFAULT 'MENSUAL',
    -- MENSUAL, BIMESTRAL, TRIMESTRAL, SEMESTRAL, ANUAL
  precio_periodo      DECIMAL(14,2) NOT NULL,            -- Precio segun frecuencia elegida
  -- Fechas de ciclo
  fecha_inicio        DATE NOT NULL,
  fecha_fin           DATE,                              -- NULL = indefinida (auto-renovacion)
  fecha_proximo_cobro DATE NOT NULL,                     -- Siguiente fecha de cobro
  fecha_ultimo_cobro  DATE,                              -- Ultimo cobro exitoso
  -- Periodo actual
  periodo_actual_desde DATE NOT NULL,
  periodo_actual_hasta DATE NOT NULL,
  -- Prueba
  en_prueba           BOOLEAN DEFAULT false,
  fecha_fin_prueba    DATE,
  -- Suspension
  suspendida_desde    DATE,
  suspendida_hasta    DATE,                              -- Fecha programada de reactivacion
  motivo_suspension   TEXT,
  -- Pago automatico
  cobro_automatico    BOOLEAN DEFAULT false,
  metodo_pago_auto    VARCHAR(20),                       -- TARJETA, TRANSFERENCIA
  referencia_pago     TEXT,                              -- Token de tarjeta, cuenta bancaria
  -- Renovacion
  auto_renovacion     BOOLEAN DEFAULT true,
  renovaciones        INTEGER DEFAULT 0,                 -- Numero de renovaciones ejecutadas
  -- Gracia
  en_gracia           BOOLEAN DEFAULT false,
  fecha_fin_gracia    DATE,
  intentos_cobro      INTEGER DEFAULT 0,
  -- Estado
  estado              VARCHAR(20) DEFAULT 'BORRADOR',
    -- BORRADOR: creada, pendiente de activacion
    -- PRUEBA: en periodo de prueba gratuito
    -- ACTIVA: suscripcion activa y al dia
    -- GRACIA: pago vencido, en periodo de gracia
    -- SUSPENDIDA: pausada por solicitud del cliente (vacaciones, etc.)
    -- VENCIDA: periodo de gracia expirado, servicio cortado
    -- CANCELADA: cancelada definitivamente
  motivo_cancelacion  TEXT,
  cancelada_por       UUID REFERENCES auth.users(id),
  fecha_cancelacion   DATE,
  -- Metadata
  version             INTEGER DEFAULT 1,
  created_by          UUID REFERENCES auth.users(id),
  created_at          TIMESTAMPTZ DEFAULT now(),
  updated_at          TIMESTAMPTZ DEFAULT now(),
  UNIQUE(empresa_id, numero)
);

-- Historial de cambios de plan (upgrades/downgrades)
CREATE TABLE suscripcion_cambios_plan (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id          UUID NOT NULL REFERENCES empresas(id),
  suscripcion_id      UUID NOT NULL REFERENCES suscripciones(id),
  -- Plan anterior y nuevo
  plan_anterior_id    UUID NOT NULL REFERENCES suscripcion_planes(id),
  plan_nuevo_id       UUID NOT NULL REFERENCES suscripcion_planes(id),
  frecuencia_anterior VARCHAR(20),
  frecuencia_nueva    VARCHAR(20),
  precio_anterior     DECIMAL(14,2) NOT NULL,
  precio_nuevo        DECIMAL(14,2) NOT NULL,
  -- Prorrateado
  tipo_cambio         VARCHAR(20) NOT NULL,
    -- UPGRADE: cambio a plan mas caro
    -- DOWNGRADE: cambio a plan mas barato
    -- CAMBIO_FRECUENCIA: solo cambia frecuencia
  aplicacion          VARCHAR(20) DEFAULT 'INMEDIATO',
    -- INMEDIATO: aplica prorrateado ahora (upgrade)
    -- PROXIMO_PERIODO: aplica al siguiente cobro (downgrade)
  monto_prorrateado   DECIMAL(14,2) DEFAULT 0,           -- Diferencia prorrateada (cobro o credito)
  factura_ajuste_id   UUID REFERENCES facturas(id),      -- Factura por la diferencia prorrateada
  nota_credito_id     UUID,                              -- NC si downgrade genera credito
  -- Metadata
  efectivo_desde      DATE NOT NULL,
  registrado_por      UUID REFERENCES auth.users(id),
  created_at          TIMESTAMPTZ DEFAULT now()
);

-- Facturas generadas por suscripcion (vinculo)
CREATE TABLE suscripcion_facturas (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id          UUID NOT NULL REFERENCES empresas(id),
  suscripcion_id      UUID NOT NULL REFERENCES suscripciones(id),
  factura_id          UUID NOT NULL REFERENCES facturas(id),
  periodo_desde       DATE NOT NULL,
  periodo_hasta       DATE NOT NULL,
  monto               DECIMAL(14,2) NOT NULL,
  es_prorrateado      BOOLEAN DEFAULT false,
  es_ajuste           BOOLEAN DEFAULT false,             -- true si es factura de ajuste por upgrade
  created_at          TIMESTAMPTZ DEFAULT now()
);

-- Indices
CREATE INDEX idx_suscripciones_contacto ON suscripciones(empresa_id, contacto_id);
CREATE INDEX idx_suscripciones_estado ON suscripciones(empresa_id, estado, fecha_proximo_cobro);
CREATE INDEX idx_suscripciones_cobro ON suscripciones(empresa_id, fecha_proximo_cobro)
  WHERE estado IN ('ACTIVA', 'PRUEBA');
CREATE INDEX idx_suscripciones_gracia ON suscripciones(empresa_id, fecha_fin_gracia)
  WHERE en_gracia = true;
CREATE INDEX idx_suscripcion_facturas_suscripcion ON suscripcion_facturas(suscripcion_id);
```

#### Funciones PostgreSQL Principales

```sql
-- Crear suscripcion
CREATE OR REPLACE FUNCTION suscripcion_crear(
  p_empresa_id    UUID,
  p_contacto_id   UUID,
  p_plan_id       UUID,
  p_frecuencia    VARCHAR DEFAULT 'MENSUAL',
  p_fecha_inicio  DATE DEFAULT CURRENT_DATE,
  p_cobro_automatico BOOLEAN DEFAULT false,
  p_metodo_pago   VARCHAR DEFAULT NULL,
  p_referencia_pago TEXT DEFAULT NULL,
  p_usuario_id    UUID DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_plan suscripcion_planes%ROWTYPE;
  v_precio DECIMAL(14,2);
  v_suscripcion_id UUID;
  v_numero VARCHAR(20);
  v_periodo_hasta DATE;
  v_fecha_cobro DATE;
  v_en_prueba BOOLEAN := false;
  v_fecha_fin_prueba DATE;
BEGIN
  -- Obtener plan
  SELECT * INTO v_plan FROM suscripcion_planes
  WHERE id = p_plan_id AND empresa_id = p_empresa_id AND activo = true;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Plan de suscripcion no encontrado o inactivo';
  END IF;

  -- Obtener precio segun frecuencia
  CASE p_frecuencia
    WHEN 'MENSUAL' THEN v_precio := v_plan.precio_mensual;
    WHEN 'BIMESTRAL' THEN v_precio := v_plan.precio_bimestral;
    WHEN 'TRIMESTRAL' THEN v_precio := v_plan.precio_trimestral;
    WHEN 'SEMESTRAL' THEN v_precio := v_plan.precio_semestral;
    WHEN 'ANUAL' THEN v_precio := v_plan.precio_anual;
    ELSE RAISE EXCEPTION 'Frecuencia no valida: %', p_frecuencia;
  END CASE;

  IF v_precio IS NULL THEN
    RAISE EXCEPTION 'Plan no tiene precio configurado para frecuencia %', p_frecuencia;
  END IF;

  -- Calcular periodo
  v_periodo_hasta := suscripcion_calcular_fin_periodo(p_fecha_inicio, p_frecuencia);

  -- Periodo de prueba
  IF v_plan.dias_prueba > 0 THEN
    v_en_prueba := true;
    v_fecha_fin_prueba := p_fecha_inicio + v_plan.dias_prueba;
    v_fecha_cobro := v_fecha_fin_prueba;  -- Primer cobro al terminar prueba
  ELSE
    v_fecha_cobro := p_fecha_inicio;      -- Cobro inmediato
  END IF;

  -- Generar numero secuencial
  SELECT 'SUB-' || LPAD((COALESCE(MAX(NULLIF(regexp_replace(numero, '[^0-9]', '', 'g'), '')::INTEGER, 0) + 1)::TEXT, 6, '0')
  INTO v_numero
  FROM suscripciones WHERE empresa_id = p_empresa_id;

  -- Crear suscripcion
  INSERT INTO suscripciones (
    empresa_id, numero, contacto_id, plan_id, frecuencia, precio_periodo,
    fecha_inicio, fecha_proximo_cobro, periodo_actual_desde, periodo_actual_hasta,
    en_prueba, fecha_fin_prueba, cobro_automatico, metodo_pago_auto, referencia_pago,
    auto_renovacion, estado, created_by
  ) VALUES (
    p_empresa_id, v_numero, p_contacto_id, p_plan_id, p_frecuencia, v_precio,
    p_fecha_inicio, v_fecha_cobro, p_fecha_inicio, v_periodo_hasta,
    v_en_prueba, v_fecha_fin_prueba, p_cobro_automatico, p_metodo_pago, p_referencia_pago,
    v_plan.auto_renovacion,
    CASE WHEN v_en_prueba THEN 'PRUEBA' ELSE 'ACTIVA' END,
    p_usuario_id
  ) RETURNING id INTO v_suscripcion_id;

  -- Actualizar contador de suscriptores
  UPDATE suscripcion_planes SET suscriptores_actuales = suscriptores_actuales + 1
  WHERE id = p_plan_id;

  RETURN v_suscripcion_id;
END;
$$;

-- Calcular fin de periodo
CREATE OR REPLACE FUNCTION suscripcion_calcular_fin_periodo(
  p_fecha_inicio DATE,
  p_frecuencia   VARCHAR
) RETURNS DATE
LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
  CASE p_frecuencia
    WHEN 'MENSUAL' THEN RETURN p_fecha_inicio + INTERVAL '1 month' - INTERVAL '1 day';
    WHEN 'BIMESTRAL' THEN RETURN p_fecha_inicio + INTERVAL '2 months' - INTERVAL '1 day';
    WHEN 'TRIMESTRAL' THEN RETURN p_fecha_inicio + INTERVAL '3 months' - INTERVAL '1 day';
    WHEN 'SEMESTRAL' THEN RETURN p_fecha_inicio + INTERVAL '6 months' - INTERVAL '1 day';
    WHEN 'ANUAL' THEN RETURN p_fecha_inicio + INTERVAL '1 year' - INTERVAL '1 day';
    ELSE RAISE EXCEPTION 'Frecuencia invalida: %', p_frecuencia;
  END CASE;
END;
$$;

-- Facturar suscripciones pendientes (llamada desde cron diario)
CREATE OR REPLACE FUNCTION suscripcion_facturar_pendientes(
  p_empresa_id UUID
) RETURNS JSONB -- {procesadas, exitosas, fallidas, detalles}
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_sub RECORD;
  v_procesadas INTEGER := 0;
  v_exitosas INTEGER := 0;
  v_fallidas INTEGER := 0;
  v_detalles JSONB := '[]'::JSONB;
  v_monto DECIMAL(14,2);
  v_dias_periodo INTEGER;
  v_dias_uso INTEGER;
  v_periodo_desde DATE;
  v_periodo_hasta DATE;
BEGIN
  FOR v_sub IN
    SELECT s.*, sp.dias_gracia, sp.producto_id, sp.codigo_iva, sp.tarifa_iva,
           sp.cuenta_ingreso_id
    FROM suscripciones s
    JOIN suscripcion_planes sp ON sp.id = s.plan_id
    WHERE s.empresa_id = p_empresa_id
      AND s.estado IN ('ACTIVA', 'PRUEBA')
      AND s.fecha_proximo_cobro <= CURRENT_DATE
    ORDER BY s.fecha_proximo_cobro
  LOOP
    v_procesadas := v_procesadas + 1;

    -- Si estaba en prueba, activar
    IF v_sub.estado = 'PRUEBA' THEN
      UPDATE suscripciones SET estado = 'ACTIVA', en_prueba = false WHERE id = v_sub.id;
    END IF;

    -- Calcular monto (prorrateado si primer cobro no es inicio de mes)
    v_periodo_desde := v_sub.periodo_actual_desde;
    v_periodo_hasta := v_sub.periodo_actual_hasta;
    v_dias_periodo := v_periodo_hasta - v_periodo_desde + 1;
    v_dias_uso := v_dias_periodo; -- Periodo completo por defecto

    -- Prorrateado: si la suscripcion inicio a mitad de periodo
    IF v_sub.fecha_ultimo_cobro IS NULL AND
       EXTRACT(DAY FROM v_sub.fecha_inicio) > 1 THEN
      v_dias_uso := v_periodo_hasta - v_sub.fecha_inicio + 1;
      v_monto := ROUND(v_sub.precio_periodo * v_dias_uso / v_dias_periodo, 2);
    ELSE
      v_monto := v_sub.precio_periodo;
    END IF;

    BEGIN
      -- Crear factura via module_bus (si facturacion activa)
      PERFORM module_bus.create_invoice(
        p_empresa_id := p_empresa_id,
        p_contacto_id := v_sub.contacto_id,
        p_origen := 'SUSCRIPCION',
        p_referencia_id := v_sub.id,
        p_lineas := jsonb_build_array(jsonb_build_object(
          'producto_id', v_sub.producto_id,
          'descripcion', format('Suscripcion %s - Periodo %s al %s',
            v_sub.numero, v_periodo_desde, v_periodo_hasta),
          'cantidad', 1,
          'precio_unitario', v_monto,
          'codigo_iva', v_sub.codigo_iva,
          'tarifa_iva', v_sub.tarifa_iva
        ))
      );

      -- Avanzar al siguiente periodo
      UPDATE suscripciones SET
        fecha_ultimo_cobro = CURRENT_DATE,
        periodo_actual_desde = v_periodo_hasta + 1,
        periodo_actual_hasta = suscripcion_calcular_fin_periodo(v_periodo_hasta + 1, v_sub.frecuencia),
        fecha_proximo_cobro = v_periodo_hasta + 1,
        updated_at = now()
      WHERE id = v_sub.id;

      v_exitosas := v_exitosas + 1;
    EXCEPTION WHEN OTHERS THEN
      -- Marcar en gracia si falla
      UPDATE suscripciones SET
        en_gracia = true,
        fecha_fin_gracia = CURRENT_DATE + v_sub.dias_gracia,
        intentos_cobro = intentos_cobro + 1,
        estado = 'GRACIA',
        updated_at = now()
      WHERE id = v_sub.id;

      v_fallidas := v_fallidas + 1;
      v_detalles := v_detalles || jsonb_build_object(
        'suscripcion_id', v_sub.id, 'error', SQLERRM
      );
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'procesadas', v_procesadas,
    'exitosas', v_exitosas,
    'fallidas', v_fallidas,
    'detalles', v_detalles
  );
END;
$$;

-- Upgrade/Downgrade de plan
CREATE OR REPLACE FUNCTION suscripcion_cambiar_plan(
  p_empresa_id      UUID,
  p_suscripcion_id  UUID,
  p_nuevo_plan_id   UUID,
  p_nueva_frecuencia VARCHAR DEFAULT NULL,
  p_usuario_id      UUID DEFAULT NULL
) RETURNS UUID -- ID del cambio registrado
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_sub suscripciones%ROWTYPE;
  v_plan_actual suscripcion_planes%ROWTYPE;
  v_plan_nuevo suscripcion_planes%ROWTYPE;
  v_precio_nuevo DECIMAL(14,2);
  v_frecuencia_nueva VARCHAR(20);
  v_tipo_cambio VARCHAR(20);
  v_monto_prorrateado DECIMAL(14,2) := 0;
  v_dias_restantes INTEGER;
  v_dias_periodo INTEGER;
  v_cambio_id UUID;
BEGIN
  SELECT * INTO v_sub FROM suscripciones
  WHERE id = p_suscripcion_id AND empresa_id = p_empresa_id AND estado = 'ACTIVA';
  IF NOT FOUND THEN RAISE EXCEPTION 'Suscripcion no encontrada o no activa'; END IF;

  SELECT * INTO v_plan_actual FROM suscripcion_planes WHERE id = v_sub.plan_id;
  SELECT * INTO v_plan_nuevo FROM suscripcion_planes
  WHERE id = p_nuevo_plan_id AND empresa_id = p_empresa_id AND activo = true;
  IF NOT FOUND THEN RAISE EXCEPTION 'Nuevo plan no encontrado'; END IF;

  v_frecuencia_nueva := COALESCE(p_nueva_frecuencia, v_sub.frecuencia);

  -- Obtener precio del nuevo plan
  CASE v_frecuencia_nueva
    WHEN 'MENSUAL' THEN v_precio_nuevo := v_plan_nuevo.precio_mensual;
    WHEN 'BIMESTRAL' THEN v_precio_nuevo := v_plan_nuevo.precio_bimestral;
    WHEN 'TRIMESTRAL' THEN v_precio_nuevo := v_plan_nuevo.precio_trimestral;
    WHEN 'SEMESTRAL' THEN v_precio_nuevo := v_plan_nuevo.precio_semestral;
    WHEN 'ANUAL' THEN v_precio_nuevo := v_plan_nuevo.precio_anual;
  END CASE;

  -- Determinar tipo de cambio
  IF v_precio_nuevo > v_sub.precio_periodo THEN
    v_tipo_cambio := 'UPGRADE';
  ELSIF v_precio_nuevo < v_sub.precio_periodo THEN
    v_tipo_cambio := 'DOWNGRADE';
  ELSE
    v_tipo_cambio := 'CAMBIO_FRECUENCIA';
  END IF;

  -- Calcular prorrateado para upgrade
  IF v_tipo_cambio = 'UPGRADE' THEN
    v_dias_periodo := v_sub.periodo_actual_hasta - v_sub.periodo_actual_desde + 1;
    v_dias_restantes := v_sub.periodo_actual_hasta - CURRENT_DATE;
    IF v_dias_restantes > 0 THEN
      v_monto_prorrateado := ROUND(
        (v_precio_nuevo - v_sub.precio_periodo) * v_dias_restantes / v_dias_periodo, 2
      );
    END IF;
  END IF;

  -- Registrar cambio
  INSERT INTO suscripcion_cambios_plan (
    empresa_id, suscripcion_id, plan_anterior_id, plan_nuevo_id,
    frecuencia_anterior, frecuencia_nueva, precio_anterior, precio_nuevo,
    tipo_cambio,
    aplicacion,
    monto_prorrateado, efectivo_desde, registrado_por
  ) VALUES (
    p_empresa_id, p_suscripcion_id, v_sub.plan_id, p_nuevo_plan_id,
    v_sub.frecuencia, v_frecuencia_nueva, v_sub.precio_periodo, v_precio_nuevo,
    v_tipo_cambio,
    CASE WHEN v_tipo_cambio = 'DOWNGRADE' THEN 'PROXIMO_PERIODO' ELSE 'INMEDIATO' END,
    v_monto_prorrateado, CURRENT_DATE, p_usuario_id
  ) RETURNING id INTO v_cambio_id;

  -- Actualizar suscripcion
  IF v_tipo_cambio IN ('UPGRADE', 'CAMBIO_FRECUENCIA') THEN
    UPDATE suscripciones SET
      plan_id = p_nuevo_plan_id,
      frecuencia = v_frecuencia_nueva,
      precio_periodo = v_precio_nuevo,
      updated_at = now()
    WHERE id = p_suscripcion_id;
  END IF;
  -- DOWNGRADE se aplica en la siguiente facturacion

  -- Actualizar contadores
  UPDATE suscripcion_planes SET suscriptores_actuales = suscriptores_actuales - 1
  WHERE id = v_sub.plan_id;
  UPDATE suscripcion_planes SET suscriptores_actuales = suscriptores_actuales + 1
  WHERE id = p_nuevo_plan_id;

  RETURN v_cambio_id;
END;
$$;

-- Suspender suscripcion (vacaciones/pausa)
CREATE OR REPLACE FUNCTION suscripcion_suspender(
  p_empresa_id      UUID,
  p_suscripcion_id  UUID,
  p_dias_suspension INTEGER DEFAULT 30,
  p_motivo          TEXT DEFAULT NULL,
  p_usuario_id      UUID DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_sub suscripciones%ROWTYPE;
  v_plan suscripcion_planes%ROWTYPE;
BEGIN
  SELECT * INTO v_sub FROM suscripciones
  WHERE id = p_suscripcion_id AND empresa_id = p_empresa_id AND estado = 'ACTIVA';
  IF NOT FOUND THEN RAISE EXCEPTION 'Suscripcion no encontrada o no activa'; END IF;

  SELECT * INTO v_plan FROM suscripcion_planes WHERE id = v_sub.plan_id;
  IF NOT v_plan.permite_suspension THEN
    RAISE EXCEPTION 'Este plan no permite suspension temporal';
  END IF;

  IF p_dias_suspension > v_plan.max_dias_suspension THEN
    RAISE EXCEPTION 'Dias de suspension exceden el maximo permitido (%)', v_plan.max_dias_suspension;
  END IF;

  UPDATE suscripciones SET
    estado = 'SUSPENDIDA',
    suspendida_desde = CURRENT_DATE,
    suspendida_hasta = CURRENT_DATE + p_dias_suspension,
    motivo_suspension = p_motivo,
    updated_at = now()
  WHERE id = p_suscripcion_id;
END;
$$;

-- Reactivar suscripcion
CREATE OR REPLACE FUNCTION suscripcion_reactivar(
  p_empresa_id      UUID,
  p_suscripcion_id  UUID,
  p_usuario_id      UUID DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_sub suscripciones%ROWTYPE;
BEGIN
  SELECT * INTO v_sub FROM suscripciones
  WHERE id = p_suscripcion_id AND empresa_id = p_empresa_id
    AND estado IN ('SUSPENDIDA', 'GRACIA', 'VENCIDA');
  IF NOT FOUND THEN RAISE EXCEPTION 'Suscripcion no encontrada o no puede reactivarse'; END IF;

  UPDATE suscripciones SET
    estado = 'ACTIVA',
    suspendida_desde = NULL,
    suspendida_hasta = NULL,
    motivo_suspension = NULL,
    en_gracia = false,
    fecha_fin_gracia = NULL,
    intentos_cobro = 0,
    fecha_proximo_cobro = CURRENT_DATE,
    updated_at = now()
  WHERE id = p_suscripcion_id;
END;
$$;

-- Cancelar suscripcion
CREATE OR REPLACE FUNCTION suscripcion_cancelar(
  p_empresa_id      UUID,
  p_suscripcion_id  UUID,
  p_motivo          TEXT,
  p_usuario_id      UUID DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_sub suscripciones%ROWTYPE;
BEGIN
  SELECT * INTO v_sub FROM suscripciones
  WHERE id = p_suscripcion_id AND empresa_id = p_empresa_id
    AND estado NOT IN ('CANCELADA');
  IF NOT FOUND THEN RAISE EXCEPTION 'Suscripcion no encontrada o ya cancelada'; END IF;

  UPDATE suscripciones SET
    estado = 'CANCELADA',
    motivo_cancelacion = p_motivo,
    cancelada_por = p_usuario_id,
    fecha_cancelacion = CURRENT_DATE,
    updated_at = now()
  WHERE id = p_suscripcion_id;

  UPDATE suscripcion_planes SET suscriptores_actuales = GREATEST(suscriptores_actuales - 1, 0)
  WHERE id = v_sub.plan_id;
END;
$$;

-- Procesar periodos de gracia expirados (cron diario)
CREATE OR REPLACE FUNCTION suscripcion_procesar_gracias_expiradas(
  p_empresa_id UUID
) RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_count INTEGER;
BEGIN
  UPDATE suscripciones SET
    estado = 'VENCIDA',
    en_gracia = false,
    updated_at = now()
  WHERE empresa_id = p_empresa_id
    AND en_gracia = true
    AND fecha_fin_gracia IS NOT NULL
    AND fecha_fin_gracia < CURRENT_DATE;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

-- Procesar suspensiones expiradas (reactivar automaticamente, cron diario)
CREATE OR REPLACE FUNCTION suscripcion_procesar_suspensiones(
  p_empresa_id UUID
) RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_count INTEGER;
BEGIN
  UPDATE suscripciones SET
    estado = 'ACTIVA',
    suspendida_desde = NULL,
    suspendida_hasta = NULL,
    motivo_suspension = NULL,
    fecha_proximo_cobro = CURRENT_DATE,
    updated_at = now()
  WHERE empresa_id = p_empresa_id
    AND estado = 'SUSPENDIDA'
    AND suspendida_hasta IS NOT NULL
    AND suspendida_hasta <= CURRENT_DATE;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;
```

#### Triggers

```sql
-- Trigger para notificar cambios de estado de suscripcion
CREATE OR REPLACE FUNCTION trg_suscripcion_estado_cambio()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF OLD.estado IS DISTINCT FROM NEW.estado THEN
    -- Registrar en registro_actividad (audit trail)
    INSERT INTO registro_actividad (
      empresa_id, tabla_nombre, registro_id, accion, campo,
      valor_anterior, valor_nuevo, usuario_id
    ) VALUES (
      NEW.empresa_id, 'suscripciones', NEW.id, 'UPDATE', 'estado',
      OLD.estado, NEW.estado, COALESCE(NEW.cancelada_por, auth.uid())
    );

    -- Encolar notificacion al cliente segun nuevo estado
    -- (se procesa via Edge Function notify-subscription-change)
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER tr_suscripcion_estado
  AFTER UPDATE OF estado ON suscripciones
  FOR EACH ROW
  EXECUTE FUNCTION trg_suscripcion_estado_cambio();
```

#### Vistas para Reportes

```sql
-- Vista: resumen de suscripciones por estado
CREATE OR REPLACE VIEW v_suscripciones_resumen AS
SELECT
  s.empresa_id,
  sp.nombre AS plan,
  s.estado,
  s.frecuencia,
  COUNT(*) AS total,
  SUM(s.precio_periodo) AS mrr_potencial, -- Monthly Recurring Revenue
  AVG(s.precio_periodo)::DECIMAL(14,2) AS ticket_promedio
FROM suscripciones s
JOIN suscripcion_planes sp ON sp.id = s.plan_id
GROUP BY s.empresa_id, sp.nombre, s.estado, s.frecuencia;

-- Vista: MRR (Monthly Recurring Revenue) actual
CREATE OR REPLACE VIEW v_suscripciones_mrr AS
SELECT
  s.empresa_id,
  SUM(CASE s.frecuencia
    WHEN 'MENSUAL' THEN s.precio_periodo
    WHEN 'BIMESTRAL' THEN s.precio_periodo / 2
    WHEN 'TRIMESTRAL' THEN s.precio_periodo / 3
    WHEN 'SEMESTRAL' THEN s.precio_periodo / 6
    WHEN 'ANUAL' THEN s.precio_periodo / 12
  END) AS mrr,
  COUNT(*) AS suscripciones_activas
FROM suscripciones s
WHERE s.estado = 'ACTIVA'
GROUP BY s.empresa_id;

-- Vista: churn (cancelaciones por periodo)
CREATE OR REPLACE VIEW v_suscripciones_churn AS
SELECT
  s.empresa_id,
  date_trunc('month', s.fecha_cancelacion) AS mes,
  COUNT(*) AS cancelaciones,
  SUM(s.precio_periodo) AS revenue_perdido
FROM suscripciones s
WHERE s.estado = 'CANCELADA' AND s.fecha_cancelacion IS NOT NULL
GROUP BY s.empresa_id, date_trunc('month', s.fecha_cancelacion);
```

#### Integracion Module Service Bus

```sql
-- Crear factura desde suscripcion (el cron de suscripciones necesita crear facturas)
CREATE OR REPLACE FUNCTION module_bus.create_subscription_invoice(
  p_empresa_id    UUID,
  p_suscripcion_id UUID
) RETURNS module_bus.bus_response
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_result module_bus.bus_response;
BEGIN
  -- Las suscripciones usan module_bus.create_invoice internamente
  -- Este gateway es para uso externo (ej: facturacion manual de una suscripcion)
  IF NOT module_bus.is_module_active(p_empresa_id, 'ventas') THEN
    v_result := (false, 'module_inactive', 'ventas', null);
    RETURN v_result;
  END IF;

  -- Delegar a la funcion de facturacion pendiente individual
  -- (se invoca suscripcion_facturar_pendientes con filtro)
  v_result := (true, null, 'ventas', jsonb_build_object('nota', 'Usar suscripcion_facturar_pendientes'));
  RETURN v_result;
END;
$$;
```

#### RLS Policies

```sql
ALTER TABLE suscripcion_planes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON suscripcion_planes FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

ALTER TABLE suscripcion_plan_features ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON suscripcion_plan_features FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

ALTER TABLE suscripciones ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON suscripciones FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

ALTER TABLE suscripcion_cambios_plan ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON suscripcion_cambios_plan FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

ALTER TABLE suscripcion_facturas ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON suscripcion_facturas FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));
```

#### Flujo UI/UX

```
features/ventas/suscripciones/
  screens/
    subscription_plans_screen.dart       # Catalogo de planes (cards comparativas)
    subscription_plan_form_screen.dart   # Crear/editar plan + features + precios
    subscriptions_screen.dart            # Lista suscripciones (SfDataGrid, filtros por estado)
    subscription_detail_screen.dart      # Detalle: estado, historial, facturas, cambios
    subscription_form_screen.dart        # Crear suscripcion (seleccionar plan + frecuencia)
    subscription_change_plan_screen.dart # Upgrade/downgrade con preview de prorrateado
    subscription_reports_screen.dart     # MRR, churn, LTV, cohortes
  widgets/
    plan_comparison_card.dart            # Card de plan con features y precio
    subscription_status_timeline.dart    # Timeline visual de estados
    mrr_chart_widget.dart                # Grafico MRR en el tiempo (SfCartesianChart)
    churn_rate_widget.dart               # Indicador de tasa de cancelacion

Responsive:
  COMPACT: lista simple de suscripciones, detalle bottom sheet
  MEDIUM: lista + preview lateral del plan
  EXPANDED/LARGE: dashboard completo con MRR + lista + detalle

Edge Function (cron):
  process-subscriptions: ejecuta diariamente
    1. suscripcion_facturar_pendientes()
    2. suscripcion_procesar_gracias_expiradas()
    3. suscripcion_procesar_suspensiones()
    4. Envia notificaciones de proximos cobros (dias_aviso)
```

---

