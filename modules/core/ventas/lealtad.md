# Programas de Lealtad y Puntos


#### Descripcion Funcional

Sistema de fidelizacion configurable por empresa que permite acumular puntos por compras, canjearlos por beneficios y gestionar niveles de membresia. Cada empresa define su propio programa con reglas de acumulacion, canje y vencimiento.

**Flujo principal:**

```
CONFIGURACION:
  Empresa crea programa → define niveles → define reglas acumulacion → define reglas canje

ACUMULACION (automatica):
  Cliente compra → factura PAGADA → trigger calcula puntos → acredita al cliente
  Regla: X puntos por cada $Y gastados (configurable por programa/categoria/producto)

CANJE (manual o en POS):
  Cliente solicita canje → selecciona beneficio (descuento, producto gratis, upgrade)
  → sistema valida puntos suficientes → descuenta puntos → aplica beneficio

NIVELES (automatico):
  Cron evalua puntos acumulados en periodo → asigna/sube/baja nivel
  Cada nivel tiene beneficios: multiplicador puntos, descuento base, acceso exclusivo

VENCIMIENTO (automatico):
  Cron marca puntos vencidos segun politica del programa
  Notificacion al cliente X dias antes del vencimiento
```

**Integraciones:**
- **POS:** Mostrar puntos del cliente, permitir canje en el cobro
- **Ecommerce:** Mostrar puntos en cuenta del cliente, canje en checkout
- **Facturacion:** Trigger post-pago para acumular puntos
- **Notificaciones:** Alertas de puntos por vencer, cambio de nivel, canje exitoso

#### Modelo de Datos SQL

```sql
-- ══════════════════════════════════════════════════════════════════
-- PROGRAMAS DE LEALTAD Y PUNTOS (22.1)
-- ══════════════════════════════════════════════════════════════════

-- Programa de lealtad (uno por empresa, extensible a multiples)
CREATE TABLE lealtad_programas (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id          UUID NOT NULL REFERENCES empresas(id),
  nombre              VARCHAR(150) NOT NULL,
  codigo              VARCHAR(20) NOT NULL,
  descripcion         TEXT,
  -- Moneda de puntos
  nombre_punto        VARCHAR(50) DEFAULT 'Punto',       -- 'Punto', 'Estrella', 'Milla'
  nombre_punto_plural VARCHAR(50) DEFAULT 'Puntos',
  -- Regla base de acumulacion
  puntos_por_dolar    DECIMAL(10,4) NOT NULL DEFAULT 1,  -- X puntos por cada $1 gastado
  monto_minimo_acumular DECIMAL(14,2) DEFAULT 0,         -- Compra minima para acumular
  -- Vencimiento
  politica_vencimiento VARCHAR(20) DEFAULT 'MESES',
    -- NUNCA: puntos no vencen
    -- MESES: vencen N meses despues de acreditados
    -- ANUAL: vencen el 31/dic de cada anio
    -- INACTIVIDAD: vencen si no hay actividad en N meses
  meses_vencimiento   INTEGER DEFAULT 12,                -- Meses para vencimiento (si aplica)
  dias_aviso_vencimiento INTEGER DEFAULT 30,             -- Dias antes de vencer para notificar
  -- Configuracion
  acumula_con_descuento BOOLEAN DEFAULT true,            -- Acumula puntos sobre monto con descuento?
  acumula_con_impuestos BOOLEAN DEFAULT false,           -- Acumula sobre monto con IVA?
  permite_canje_parcial BOOLEAN DEFAULT true,            -- Puede canjear parte de los puntos?
  puntos_minimo_canje INTEGER DEFAULT 100,               -- Minimo de puntos para poder canjear
  -- Estado
  estado              VARCHAR(20) DEFAULT 'ACTIVO',
    -- BORRADOR, ACTIVO, PAUSADO, FINALIZADO
  fecha_inicio        DATE NOT NULL,
  fecha_fin           DATE,                              -- NULL = indefinido
  activo              BOOLEAN DEFAULT true,
  version             INTEGER DEFAULT 1,
  created_at          TIMESTAMPTZ DEFAULT now(),
  updated_at          TIMESTAMPTZ DEFAULT now(),
  UNIQUE(empresa_id, codigo)
);

-- Niveles de membresia del programa
CREATE TABLE lealtad_niveles (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id          UUID NOT NULL REFERENCES empresas(id),
  programa_id         UUID NOT NULL REFERENCES lealtad_programas(id) ON DELETE CASCADE,
  nombre              VARCHAR(50) NOT NULL,              -- 'Bronce', 'Plata', 'Oro', 'Platino'
  codigo              VARCHAR(20) NOT NULL,              -- 'BRONCE', 'PLATA', 'ORO', 'PLATINO'
  orden               INTEGER NOT NULL DEFAULT 0,        -- 0=base, 1=siguiente, etc.
  -- Requisitos para alcanzar este nivel
  puntos_minimos      INTEGER NOT NULL DEFAULT 0,        -- Puntos acumulados en periodo de evaluacion
  compras_minimas     INTEGER DEFAULT 0,                 -- Numero minimo de compras en periodo
  monto_minimo        DECIMAL(14,2) DEFAULT 0,           -- Monto minimo gastado en periodo
  periodo_evaluacion  VARCHAR(20) DEFAULT 'ANUAL',
    -- MENSUAL, TRIMESTRAL, SEMESTRAL, ANUAL
  -- Beneficios del nivel
  multiplicador_puntos DECIMAL(5,2) DEFAULT 1.00,        -- 1.0=base, 1.5=50% mas puntos, 2.0=doble
  descuento_base      DECIMAL(5,2) DEFAULT 0,            -- % descuento automatico en compras
  envio_gratis        BOOLEAN DEFAULT false,             -- Envio gratis en ecommerce
  acceso_preventas    BOOLEAN DEFAULT false,             -- Acceso a preventas exclusivas
  -- Visual
  color               VARCHAR(20) DEFAULT '#CD7F32',     -- Color del badge
  icono_url           TEXT,                              -- URL icono en Storage
  activo              BOOLEAN DEFAULT true,
  created_at          TIMESTAMPTZ DEFAULT now(),
  UNIQUE(empresa_id, programa_id, codigo)
);

-- Reglas de acumulacion especificas (sobreescriben la regla base del programa)
CREATE TABLE lealtad_reglas_acumulacion (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id          UUID NOT NULL REFERENCES empresas(id),
  programa_id         UUID NOT NULL REFERENCES lealtad_programas(id) ON DELETE CASCADE,
  nombre              VARCHAR(150) NOT NULL,
  -- Alcance (de mas especifico a mas general; NULL = aplica a todo)
  producto_id         UUID REFERENCES productos(id),
  categoria_id        UUID REFERENCES categorias_producto(id),
  -- Regla
  tipo                VARCHAR(20) NOT NULL DEFAULT 'MULTIPLICADOR',
    -- MULTIPLICADOR: multiplica puntos_por_dolar del programa
    -- PUNTOS_FIJOS: otorga N puntos fijos por compra del producto
    -- PUNTOS_POR_UNIDAD: N puntos por cada unidad comprada
  valor               DECIMAL(10,4) NOT NULL,            -- Multiplicador, puntos fijos, o puntos/unidad
  -- Vigencia
  vigencia_desde      DATE,
  vigencia_hasta      DATE,
  -- Restricciones
  solo_niveles        JSONB,                             -- ['ORO','PLATINO'] o NULL = todos
  canal               VARCHAR(20),                       -- POS, ECOMMERCE, NULL = todos
  -- Prioridad (mayor = mas prioritario, como reglas_comision)
  prioridad           INTEGER DEFAULT 0,
  activo              BOOLEAN DEFAULT true,
  created_at          TIMESTAMPTZ DEFAULT now()
);

-- Reglas de canje (que se puede canjear con puntos)
CREATE TABLE lealtad_reglas_canje (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id          UUID NOT NULL REFERENCES empresas(id),
  programa_id         UUID NOT NULL REFERENCES lealtad_programas(id) ON DELETE CASCADE,
  nombre              VARCHAR(150) NOT NULL,              -- 'Descuento $5', 'Producto gratis', 'Envio gratis'
  tipo                VARCHAR(20) NOT NULL,
    -- DESCUENTO_MONTO: canjea por descuento fijo ($X)
    -- DESCUENTO_PORCENTAJE: canjea por descuento porcentual (X%)
    -- PRODUCTO_GRATIS: canjea por un producto especifico
    -- ENVIO_GRATIS: canjea por envio sin costo
  -- Costo en puntos
  puntos_requeridos   INTEGER NOT NULL,
  -- Beneficio
  valor_descuento     DECIMAL(14,2),                     -- Monto o porcentaje del descuento
  producto_id         UUID REFERENCES productos(id),     -- Producto gratis (si tipo = PRODUCTO_GRATIS)
  -- Restricciones
  compra_minima       DECIMAL(14,2) DEFAULT 0,           -- Compra minima para aplicar canje
  max_canjes_dia      INTEGER,                           -- Limite por dia por cliente
  max_canjes_mes      INTEGER,                           -- Limite por mes por cliente
  solo_niveles        JSONB,                             -- ['ORO','PLATINO'] o NULL = todos
  -- Vigencia
  vigencia_desde      DATE,
  vigencia_hasta      DATE,
  activo              BOOLEAN DEFAULT true,
  created_at          TIMESTAMPTZ DEFAULT now()
);

-- Membresia del cliente en el programa
CREATE TABLE lealtad_miembros (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id          UUID NOT NULL REFERENCES empresas(id),
  programa_id         UUID NOT NULL REFERENCES lealtad_programas(id),
  contacto_id         UUID NOT NULL REFERENCES contactos(id),
  -- Estado actual
  nivel_id            UUID REFERENCES lealtad_niveles(id),
  puntos_disponibles  INTEGER DEFAULT 0,                 -- Saldo canjeable actual
  puntos_acumulados_total INTEGER DEFAULT 0,             -- Total historico acumulado
  puntos_canjeados_total INTEGER DEFAULT 0,              -- Total historico canjeado
  puntos_vencidos_total INTEGER DEFAULT 0,               -- Total historico vencido
  -- Periodo de evaluacion actual
  puntos_periodo      INTEGER DEFAULT 0,                 -- Puntos acumulados en periodo actual
  compras_periodo     INTEGER DEFAULT 0,                 -- Compras en periodo actual
  monto_periodo       DECIMAL(14,2) DEFAULT 0,           -- Monto gastado en periodo actual
  inicio_periodo      DATE,
  fin_periodo         DATE,
  -- Fechas
  fecha_inscripcion   DATE NOT NULL DEFAULT CURRENT_DATE,
  fecha_ultimo_movimiento DATE,
  activo              BOOLEAN DEFAULT true,
  created_at          TIMESTAMPTZ DEFAULT now(),
  updated_at          TIMESTAMPTZ DEFAULT now(),
  UNIQUE(empresa_id, programa_id, contacto_id)
);

-- Movimientos de puntos (historial completo, append-only)
CREATE TABLE lealtad_movimientos (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id          UUID NOT NULL REFERENCES empresas(id),
  miembro_id          UUID NOT NULL REFERENCES lealtad_miembros(id),
  -- Tipo de movimiento
  tipo                VARCHAR(20) NOT NULL,
    -- ACUMULACION: puntos ganados por compra
    -- CANJE: puntos usados para beneficio
    -- VENCIMIENTO: puntos que expiraron
    -- AJUSTE_POSITIVO: ajuste manual a favor
    -- AJUSTE_NEGATIVO: ajuste manual en contra
    -- DEVOLUCION: puntos devueltos por NC
    -- BONO: puntos otorgados como bonificacion (cumpleanos, promocion)
  puntos              INTEGER NOT NULL,                  -- Positivo = acredita, negativo = debita
  saldo_despues       INTEGER NOT NULL,                  -- Saldo despues del movimiento
  -- Referencia
  descripcion         TEXT NOT NULL,
  factura_id          UUID REFERENCES facturas(id),      -- Si tipo = ACUMULACION o DEVOLUCION
  canje_id            UUID,                              -- Si tipo = CANJE (FK lealtad_canjes)
  -- Vencimiento de estos puntos
  fecha_vencimiento   DATE,                              -- Cuando vencen estos puntos especificos
  puntos_vigentes     INTEGER,                           -- Puntos aun vigentes de este lote
  -- Metadata
  canal               VARCHAR(20),                       -- POS, ECOMMERCE, MANUAL
  registrado_por      UUID REFERENCES auth.users(id),
  created_at          TIMESTAMPTZ DEFAULT now()
);

-- Canjes realizados
CREATE TABLE lealtad_canjes (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id          UUID NOT NULL REFERENCES empresas(id),
  miembro_id          UUID NOT NULL REFERENCES lealtad_miembros(id),
  regla_canje_id      UUID NOT NULL REFERENCES lealtad_reglas_canje(id),
  puntos_usados       INTEGER NOT NULL,
  -- Resultado del canje
  tipo_beneficio      VARCHAR(20) NOT NULL,              -- Mismo que regla_canje.tipo
  valor_beneficio     DECIMAL(14,2),                     -- Monto descuento o valor producto
  producto_id         UUID REFERENCES productos(id),     -- Producto entregado gratis
  -- Aplicacion
  factura_id          UUID REFERENCES facturas(id),      -- Factura donde se aplico el descuento
  pos_venta_id        UUID,                              -- Venta POS donde se aplico
  -- Estado
  estado              VARCHAR(20) DEFAULT 'APLICADO',
    -- APLICADO, ANULADO
  canal               VARCHAR(20),                       -- POS, ECOMMERCE, MOSTRADOR
  registrado_por      UUID REFERENCES auth.users(id),
  created_at          TIMESTAMPTZ DEFAULT now()
);

-- Indices
CREATE INDEX idx_lealtad_miembros_contacto ON lealtad_miembros(empresa_id, contacto_id);
CREATE INDEX idx_lealtad_miembros_programa ON lealtad_miembros(programa_id, nivel_id);
CREATE INDEX idx_lealtad_movimientos_miembro ON lealtad_movimientos(miembro_id, created_at DESC);
CREATE INDEX idx_lealtad_movimientos_factura ON lealtad_movimientos(factura_id) WHERE factura_id IS NOT NULL;
CREATE INDEX idx_lealtad_movimientos_vencimiento ON lealtad_movimientos(fecha_vencimiento)
  WHERE tipo = 'ACUMULACION' AND puntos_vigentes > 0;
CREATE INDEX idx_lealtad_reglas_acum_producto ON lealtad_reglas_acumulacion(empresa_id, producto_id)
  WHERE producto_id IS NOT NULL;
CREATE INDEX idx_lealtad_reglas_acum_categoria ON lealtad_reglas_acumulacion(empresa_id, categoria_id)
  WHERE categoria_id IS NOT NULL;
```

#### Funciones PostgreSQL Principales

```sql
-- Inscribir cliente en programa de lealtad
CREATE OR REPLACE FUNCTION lealtad_inscribir_miembro(
  p_empresa_id    UUID,
  p_programa_id   UUID,
  p_contacto_id   UUID
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_miembro_id UUID;
  v_nivel_base_id UUID;
  v_programa lealtad_programas%ROWTYPE;
BEGIN
  -- Obtener programa
  SELECT * INTO v_programa FROM lealtad_programas
  WHERE id = p_programa_id AND empresa_id = p_empresa_id AND estado = 'ACTIVO';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Programa de lealtad no encontrado o inactivo';
  END IF;

  -- Obtener nivel base (orden = 0)
  SELECT id INTO v_nivel_base_id FROM lealtad_niveles
  WHERE programa_id = p_programa_id AND empresa_id = p_empresa_id AND activo = true
  ORDER BY orden ASC LIMIT 1;

  -- Crear membresia (upsert para evitar duplicados)
  INSERT INTO lealtad_miembros (
    empresa_id, programa_id, contacto_id, nivel_id,
    inicio_periodo, fin_periodo
  ) VALUES (
    p_empresa_id, p_programa_id, p_contacto_id, v_nivel_base_id,
    date_trunc('year', CURRENT_DATE)::DATE,
    (date_trunc('year', CURRENT_DATE) + INTERVAL '1 year' - INTERVAL '1 day')::DATE
  )
  ON CONFLICT (empresa_id, programa_id, contacto_id) DO NOTHING
  RETURNING id INTO v_miembro_id;

  IF v_miembro_id IS NULL THEN
    SELECT id INTO v_miembro_id FROM lealtad_miembros
    WHERE empresa_id = p_empresa_id AND programa_id = p_programa_id
      AND contacto_id = p_contacto_id;
  END IF;

  RETURN v_miembro_id;
END;
$$;

-- Acumular puntos por una factura pagada
CREATE OR REPLACE FUNCTION lealtad_acumular_puntos(
  p_empresa_id  UUID,
  p_factura_id  UUID
) RETURNS INTEGER -- puntos acumulados
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_factura RECORD;
  v_miembro RECORD;
  v_programa lealtad_programas%ROWTYPE;
  v_monto_base DECIMAL(14,2);
  v_puntos_base INTEGER;
  v_multiplicador DECIMAL(5,2) := 1.00;
  v_puntos_total INTEGER := 0;
  v_puntos_linea INTEGER;
  v_regla RECORD;
  v_nivel RECORD;
  v_fecha_vencimiento DATE;
  v_linea RECORD;
BEGIN
  -- Obtener factura
  SELECT f.*, f.contacto_id, f.total_sin_impuestos, f.importe_total,
         f.total_descuento
  INTO v_factura FROM facturas f
  WHERE f.id = p_factura_id AND f.empresa_id = p_empresa_id;
  IF NOT FOUND THEN RETURN 0; END IF;

  -- Buscar membresia activa del cliente
  SELECT m.*, p.* INTO v_miembro
  FROM lealtad_miembros m
  JOIN lealtad_programas p ON p.id = m.programa_id
  WHERE m.empresa_id = p_empresa_id
    AND m.contacto_id = v_factura.contacto_id
    AND m.activo = true
    AND p.estado = 'ACTIVO'
  LIMIT 1;
  IF NOT FOUND THEN RETURN 0; END IF;

  -- Obtener programa completo
  SELECT * INTO v_programa FROM lealtad_programas WHERE id = v_miembro.programa_id;

  -- Calcular monto base (con o sin impuestos segun config)
  IF v_programa.acumula_con_impuestos THEN
    v_monto_base := v_factura.importe_total;
  ELSE
    v_monto_base := v_factura.total_sin_impuestos;
  END IF;
  IF NOT v_programa.acumula_con_descuento THEN
    v_monto_base := v_monto_base + COALESCE(v_factura.total_descuento, 0);
  END IF;

  -- Verificar monto minimo
  IF v_monto_base < v_programa.monto_minimo_acumular THEN RETURN 0; END IF;

  -- Obtener multiplicador del nivel del miembro
  SELECT multiplicador_puntos INTO v_multiplicador FROM lealtad_niveles
  WHERE id = v_miembro.nivel_id;
  v_multiplicador := COALESCE(v_multiplicador, 1.00);

  -- Calcular puntos: buscar regla mas especifica por linea de factura
  FOR v_linea IN
    SELECT fd.producto_id, fd.cantidad, fd.precio_total_sin_impuesto,
           p2.categoria_id
    FROM factura_detalles fd
    LEFT JOIN productos p2 ON p2.id = fd.producto_id
    WHERE fd.factura_id = p_factura_id
  LOOP
    -- Buscar regla especifica: producto > categoria > general
    SELECT * INTO v_regla FROM lealtad_reglas_acumulacion
    WHERE programa_id = v_programa.id AND empresa_id = p_empresa_id AND activo = true
      AND (vigencia_desde IS NULL OR vigencia_desde <= CURRENT_DATE)
      AND (vigencia_hasta IS NULL OR vigencia_hasta >= CURRENT_DATE)
      AND (
        producto_id = v_linea.producto_id
        OR (producto_id IS NULL AND categoria_id = v_linea.categoria_id)
        OR (producto_id IS NULL AND categoria_id IS NULL)
      )
    ORDER BY
      CASE WHEN producto_id IS NOT NULL THEN 0
           WHEN categoria_id IS NOT NULL THEN 1
           ELSE 2 END,
      prioridad DESC
    LIMIT 1;

    IF v_regla IS NOT NULL THEN
      CASE v_regla.tipo
        WHEN 'MULTIPLICADOR' THEN
          v_puntos_linea := FLOOR(v_linea.precio_total_sin_impuesto * v_programa.puntos_por_dolar * v_regla.valor * v_multiplicador);
        WHEN 'PUNTOS_FIJOS' THEN
          v_puntos_linea := v_regla.valor::INTEGER;
        WHEN 'PUNTOS_POR_UNIDAD' THEN
          v_puntos_linea := FLOOR(v_linea.cantidad * v_regla.valor);
        ELSE
          v_puntos_linea := FLOOR(v_linea.precio_total_sin_impuesto * v_programa.puntos_por_dolar * v_multiplicador);
      END CASE;
    ELSE
      -- Regla base del programa
      v_puntos_linea := FLOOR(v_linea.precio_total_sin_impuesto * v_programa.puntos_por_dolar * v_multiplicador);
    END IF;

    v_puntos_total := v_puntos_total + v_puntos_linea;
  END LOOP;

  IF v_puntos_total <= 0 THEN RETURN 0; END IF;

  -- Calcular fecha vencimiento
  CASE v_programa.politica_vencimiento
    WHEN 'NUNCA' THEN v_fecha_vencimiento := NULL;
    WHEN 'MESES' THEN v_fecha_vencimiento := CURRENT_DATE + (v_programa.meses_vencimiento || ' months')::INTERVAL;
    WHEN 'ANUAL' THEN v_fecha_vencimiento := make_date(EXTRACT(YEAR FROM CURRENT_DATE)::INTEGER, 12, 31);
    WHEN 'INACTIVIDAD' THEN v_fecha_vencimiento := CURRENT_DATE + (v_programa.meses_vencimiento || ' months')::INTERVAL;
    ELSE v_fecha_vencimiento := NULL;
  END CASE;

  -- Registrar movimiento
  INSERT INTO lealtad_movimientos (
    empresa_id, miembro_id, tipo, puntos, saldo_despues,
    descripcion, factura_id, fecha_vencimiento, puntos_vigentes, canal
  ) VALUES (
    p_empresa_id, v_miembro.id, 'ACUMULACION', v_puntos_total,
    v_miembro.puntos_disponibles + v_puntos_total,
    format('Compra factura %s: %s puntos', p_factura_id, v_puntos_total),
    p_factura_id, v_fecha_vencimiento, v_puntos_total, 'FACTURA'
  );

  -- Actualizar miembro
  UPDATE lealtad_miembros SET
    puntos_disponibles = puntos_disponibles + v_puntos_total,
    puntos_acumulados_total = puntos_acumulados_total + v_puntos_total,
    puntos_periodo = puntos_periodo + v_puntos_total,
    compras_periodo = compras_periodo + 1,
    monto_periodo = monto_periodo + v_monto_base,
    fecha_ultimo_movimiento = CURRENT_DATE,
    updated_at = now()
  WHERE id = v_miembro.id;

  RETURN v_puntos_total;
END;
$$;

-- Canjear puntos por beneficio
CREATE OR REPLACE FUNCTION lealtad_canjear_puntos(
  p_empresa_id    UUID,
  p_contacto_id   UUID,
  p_regla_canje_id UUID,
  p_factura_id    UUID DEFAULT NULL,
  p_canal         VARCHAR DEFAULT 'MOSTRADOR',
  p_usuario_id    UUID DEFAULT NULL
) RETURNS UUID -- ID del canje
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_miembro lealtad_miembros%ROWTYPE;
  v_regla lealtad_reglas_canje%ROWTYPE;
  v_canje_id UUID;
  v_canjes_dia INTEGER;
  v_canjes_mes INTEGER;
BEGIN
  -- Obtener miembro
  SELECT m.* INTO v_miembro FROM lealtad_miembros m
  JOIN lealtad_programas p ON p.id = m.programa_id
  WHERE m.empresa_id = p_empresa_id AND m.contacto_id = p_contacto_id
    AND m.activo = true AND p.estado = 'ACTIVO'
  LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Cliente no inscrito en programa de lealtad activo';
  END IF;

  -- Obtener regla de canje
  SELECT * INTO v_regla FROM lealtad_reglas_canje
  WHERE id = p_regla_canje_id AND empresa_id = p_empresa_id AND activo = true
    AND (vigencia_desde IS NULL OR vigencia_desde <= CURRENT_DATE)
    AND (vigencia_hasta IS NULL OR vigencia_hasta >= CURRENT_DATE);
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Regla de canje no encontrada o fuera de vigencia';
  END IF;

  -- Validar nivel requerido
  IF v_regla.solo_niveles IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM lealtad_niveles n
      WHERE n.id = v_miembro.nivel_id AND n.codigo = ANY(
        SELECT jsonb_array_elements_text(v_regla.solo_niveles)
      )
    ) THEN
      RAISE EXCEPTION 'Nivel de membresia insuficiente para este canje';
    END IF;
  END IF;

  -- Validar puntos suficientes
  IF v_miembro.puntos_disponibles < v_regla.puntos_requeridos THEN
    RAISE EXCEPTION 'Puntos insuficientes: disponibles=%, requeridos=%',
      v_miembro.puntos_disponibles, v_regla.puntos_requeridos;
  END IF;

  -- Validar limites de canjes
  IF v_regla.max_canjes_dia IS NOT NULL THEN
    SELECT COUNT(*) INTO v_canjes_dia FROM lealtad_canjes
    WHERE miembro_id = v_miembro.id AND regla_canje_id = v_regla.id
      AND created_at::DATE = CURRENT_DATE AND estado = 'APLICADO';
    IF v_canjes_dia >= v_regla.max_canjes_dia THEN
      RAISE EXCEPTION 'Limite de canjes diarios alcanzado';
    END IF;
  END IF;

  IF v_regla.max_canjes_mes IS NOT NULL THEN
    SELECT COUNT(*) INTO v_canjes_mes FROM lealtad_canjes
    WHERE miembro_id = v_miembro.id AND regla_canje_id = v_regla.id
      AND EXTRACT(MONTH FROM created_at) = EXTRACT(MONTH FROM now())
      AND EXTRACT(YEAR FROM created_at) = EXTRACT(YEAR FROM now())
      AND estado = 'APLICADO';
    IF v_canjes_mes >= v_regla.max_canjes_mes THEN
      RAISE EXCEPTION 'Limite de canjes mensuales alcanzado';
    END IF;
  END IF;

  -- Crear canje
  INSERT INTO lealtad_canjes (
    empresa_id, miembro_id, regla_canje_id, puntos_usados,
    tipo_beneficio, valor_beneficio, producto_id,
    factura_id, canal, registrado_por
  ) VALUES (
    p_empresa_id, v_miembro.id, v_regla.id, v_regla.puntos_requeridos,
    v_regla.tipo, v_regla.valor_descuento, v_regla.producto_id,
    p_factura_id, p_canal, p_usuario_id
  ) RETURNING id INTO v_canje_id;

  -- Descontar puntos (FIFO: primero vencen los mas antiguos)
  PERFORM lealtad_descontar_puntos_fifo(v_miembro.id, v_regla.puntos_requeridos);

  -- Registrar movimiento
  INSERT INTO lealtad_movimientos (
    empresa_id, miembro_id, tipo, puntos, saldo_despues,
    descripcion, canje_id, canal, registrado_por
  ) VALUES (
    p_empresa_id, v_miembro.id, 'CANJE', -v_regla.puntos_requeridos,
    v_miembro.puntos_disponibles - v_regla.puntos_requeridos,
    format('Canje: %s (%s puntos)', v_regla.nombre, v_regla.puntos_requeridos),
    v_canje_id, p_canal, p_usuario_id
  );

  -- Actualizar miembro
  UPDATE lealtad_miembros SET
    puntos_disponibles = puntos_disponibles - v_regla.puntos_requeridos,
    puntos_canjeados_total = puntos_canjeados_total + v_regla.puntos_requeridos,
    fecha_ultimo_movimiento = CURRENT_DATE,
    updated_at = now()
  WHERE id = v_miembro.id;

  RETURN v_canje_id;
END;
$$;

-- Funcion auxiliar: descontar puntos FIFO (los mas antiguos primero)
CREATE OR REPLACE FUNCTION lealtad_descontar_puntos_fifo(
  p_miembro_id  UUID,
  p_puntos      INTEGER
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_restante INTEGER := p_puntos;
  v_mov RECORD;
BEGIN
  FOR v_mov IN
    SELECT id, puntos_vigentes FROM lealtad_movimientos
    WHERE miembro_id = p_miembro_id AND tipo = 'ACUMULACION'
      AND puntos_vigentes > 0
    ORDER BY fecha_vencimiento ASC NULLS LAST, created_at ASC
  LOOP
    IF v_restante <= 0 THEN EXIT; END IF;

    IF v_mov.puntos_vigentes <= v_restante THEN
      UPDATE lealtad_movimientos SET puntos_vigentes = 0 WHERE id = v_mov.id;
      v_restante := v_restante - v_mov.puntos_vigentes;
    ELSE
      UPDATE lealtad_movimientos SET puntos_vigentes = puntos_vigentes - v_restante WHERE id = v_mov.id;
      v_restante := 0;
    END IF;
  END LOOP;
END;
$$;

-- Procesar vencimiento de puntos (llamada desde cron diario)
CREATE OR REPLACE FUNCTION lealtad_procesar_vencimientos(
  p_empresa_id UUID
) RETURNS INTEGER -- cantidad de miembros afectados
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_mov RECORD;
  v_afectados INTEGER := 0;
BEGIN
  FOR v_mov IN
    SELECT m.id AS mov_id, m.miembro_id, m.puntos_vigentes, m.empresa_id,
           mb.puntos_disponibles
    FROM lealtad_movimientos m
    JOIN lealtad_miembros mb ON mb.id = m.miembro_id
    WHERE m.empresa_id = p_empresa_id
      AND m.tipo = 'ACUMULACION'
      AND m.puntos_vigentes > 0
      AND m.fecha_vencimiento IS NOT NULL
      AND m.fecha_vencimiento <= CURRENT_DATE
  LOOP
    -- Registrar movimiento de vencimiento
    INSERT INTO lealtad_movimientos (
      empresa_id, miembro_id, tipo, puntos, saldo_despues, descripcion
    ) VALUES (
      v_mov.empresa_id, v_mov.miembro_id, 'VENCIMIENTO',
      -v_mov.puntos_vigentes,
      v_mov.puntos_disponibles - v_mov.puntos_vigentes,
      format('Vencimiento de %s puntos', v_mov.puntos_vigentes)
    );

    -- Marcar puntos como vencidos
    UPDATE lealtad_movimientos SET puntos_vigentes = 0 WHERE id = v_mov.mov_id;

    -- Actualizar miembro
    UPDATE lealtad_miembros SET
      puntos_disponibles = puntos_disponibles - v_mov.puntos_vigentes,
      puntos_vencidos_total = puntos_vencidos_total + v_mov.puntos_vigentes,
      updated_at = now()
    WHERE id = v_mov.miembro_id;

    v_afectados := v_afectados + 1;
  END LOOP;

  RETURN v_afectados;
END;
$$;

-- Evaluar y actualizar niveles de membresia (llamada desde cron periodico)
CREATE OR REPLACE FUNCTION lealtad_evaluar_niveles(
  p_empresa_id  UUID,
  p_programa_id UUID
) RETURNS INTEGER -- miembros actualizados
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_miembro RECORD;
  v_nuevo_nivel_id UUID;
  v_actualizados INTEGER := 0;
BEGIN
  FOR v_miembro IN
    SELECT m.* FROM lealtad_miembros m
    WHERE m.empresa_id = p_empresa_id AND m.programa_id = p_programa_id AND m.activo = true
  LOOP
    -- Encontrar el nivel mas alto que cumple
    SELECT n.id INTO v_nuevo_nivel_id FROM lealtad_niveles n
    WHERE n.programa_id = p_programa_id AND n.empresa_id = p_empresa_id AND n.activo = true
      AND v_miembro.puntos_periodo >= n.puntos_minimos
      AND v_miembro.compras_periodo >= n.compras_minimas
      AND v_miembro.monto_periodo >= n.monto_minimo
    ORDER BY n.orden DESC
    LIMIT 1;

    IF v_nuevo_nivel_id IS DISTINCT FROM v_miembro.nivel_id THEN
      UPDATE lealtad_miembros SET nivel_id = v_nuevo_nivel_id, updated_at = now()
      WHERE id = v_miembro.id;
      v_actualizados := v_actualizados + 1;
    END IF;
  END LOOP;

  RETURN v_actualizados;
END;
$$;

-- Consultar saldo y estado del cliente
CREATE OR REPLACE FUNCTION lealtad_consultar_miembro(
  p_empresa_id  UUID,
  p_contacto_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_result JSONB;
BEGIN
  SELECT jsonb_build_object(
    'inscrito', true,
    'programa', p.nombre,
    'nivel', n.nombre,
    'nivel_color', n.color,
    'puntos_disponibles', m.puntos_disponibles,
    'puntos_acumulados_total', m.puntos_acumulados_total,
    'multiplicador', n.multiplicador_puntos,
    'descuento_nivel', n.descuento_base,
    'siguiente_nivel', (
      SELECT jsonb_build_object('nombre', n2.nombre, 'puntos_faltan', n2.puntos_minimos - m.puntos_periodo)
      FROM lealtad_niveles n2
      WHERE n2.programa_id = p.id AND n2.orden = n.orden + 1 AND n2.activo = true
      LIMIT 1
    ),
    'canjes_disponibles', (
      SELECT jsonb_agg(jsonb_build_object(
        'id', rc.id, 'nombre', rc.nombre, 'tipo', rc.tipo,
        'puntos_requeridos', rc.puntos_requeridos,
        'valor_descuento', rc.valor_descuento,
        'alcanzable', m.puntos_disponibles >= rc.puntos_requeridos
      ))
      FROM lealtad_reglas_canje rc
      WHERE rc.programa_id = p.id AND rc.empresa_id = p_empresa_id AND rc.activo = true
        AND (rc.vigencia_desde IS NULL OR rc.vigencia_desde <= CURRENT_DATE)
        AND (rc.vigencia_hasta IS NULL OR rc.vigencia_hasta >= CURRENT_DATE)
    )
  ) INTO v_result
  FROM lealtad_miembros m
  JOIN lealtad_programas p ON p.id = m.programa_id
  LEFT JOIN lealtad_niveles n ON n.id = m.nivel_id
  WHERE m.empresa_id = p_empresa_id AND m.contacto_id = p_contacto_id AND m.activo = true
  LIMIT 1;

  IF v_result IS NULL THEN
    RETURN jsonb_build_object('inscrito', false);
  END IF;

  RETURN v_result;
END;
$$;
```

#### Triggers

```sql
-- Acumular puntos automaticamente cuando una factura pasa a PAGADA
CREATE OR REPLACE FUNCTION trg_lealtad_factura_pagada()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NEW.estado = 'PAGADA' AND (OLD.estado IS DISTINCT FROM 'PAGADA') THEN
    PERFORM lealtad_acumular_puntos(NEW.empresa_id, NEW.id);
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER tr_lealtad_factura_pagada
  AFTER UPDATE OF estado ON facturas
  FOR EACH ROW
  WHEN (NEW.estado = 'PAGADA')
  EXECUTE FUNCTION trg_lealtad_factura_pagada();

-- Devolver puntos cuando se emite Nota de Credito
CREATE OR REPLACE FUNCTION trg_lealtad_nota_credito()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_factura_id UUID;
  v_miembro RECORD;
  v_puntos_devolver INTEGER;
BEGIN
  IF NEW.estado = 'AUTORIZADA' AND OLD.estado IS DISTINCT FROM 'AUTORIZADA' THEN
    -- Buscar factura original
    v_factura_id := NEW.factura_referencia_id;
    IF v_factura_id IS NULL THEN RETURN NEW; END IF;

    -- Buscar miembro
    SELECT m.* INTO v_miembro FROM lealtad_miembros m
    JOIN lealtad_programas p ON p.id = m.programa_id
    WHERE m.empresa_id = NEW.empresa_id AND m.contacto_id = NEW.contacto_id
      AND m.activo = true AND p.estado = 'ACTIVO'
    LIMIT 1;
    IF NOT FOUND THEN RETURN NEW; END IF;

    -- Calcular puntos a devolver proporcionalmente
    SELECT COALESCE(SUM(puntos), 0) INTO v_puntos_devolver
    FROM lealtad_movimientos
    WHERE factura_id = v_factura_id AND tipo = 'ACUMULACION';

    IF v_puntos_devolver > 0 THEN
      -- Proporcionar segun monto NC vs factura original
      v_puntos_devolver := FLOOR(v_puntos_devolver *
        (NEW.importe_total / NULLIF((SELECT importe_total FROM facturas WHERE id = v_factura_id), 0)));

      IF v_puntos_devolver > v_miembro.puntos_disponibles THEN
        v_puntos_devolver := v_miembro.puntos_disponibles;
      END IF;

      IF v_puntos_devolver > 0 THEN
        INSERT INTO lealtad_movimientos (
          empresa_id, miembro_id, tipo, puntos, saldo_despues, descripcion, factura_id
        ) VALUES (
          NEW.empresa_id, v_miembro.id, 'DEVOLUCION', -v_puntos_devolver,
          v_miembro.puntos_disponibles - v_puntos_devolver,
          format('Devolucion por NC sobre factura %s', v_factura_id),
          v_factura_id
        );

        UPDATE lealtad_miembros SET
          puntos_disponibles = puntos_disponibles - v_puntos_devolver,
          updated_at = now()
        WHERE id = v_miembro.id;
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER tr_lealtad_nota_credito
  AFTER UPDATE OF estado ON notas_credito
  FOR EACH ROW
  EXECUTE FUNCTION trg_lealtad_nota_credito();
```

#### Vistas para Reportes

```sql
-- Vista: resumen de miembros por nivel
CREATE OR REPLACE VIEW v_lealtad_resumen_niveles AS
SELECT
  m.empresa_id,
  p.nombre AS programa,
  n.nombre AS nivel,
  n.orden,
  n.color,
  COUNT(m.id) AS total_miembros,
  SUM(m.puntos_disponibles) AS puntos_totales_disponibles,
  AVG(m.puntos_periodo)::INTEGER AS promedio_puntos_periodo,
  AVG(m.monto_periodo)::DECIMAL(14,2) AS promedio_monto_periodo
FROM lealtad_miembros m
JOIN lealtad_programas p ON p.id = m.programa_id
LEFT JOIN lealtad_niveles n ON n.id = m.nivel_id
WHERE m.activo = true
GROUP BY m.empresa_id, p.nombre, n.nombre, n.orden, n.color;

-- Vista: movimientos recientes para dashboard
CREATE OR REPLACE VIEW v_lealtad_movimientos_recientes AS
SELECT
  mv.empresa_id,
  mv.miembro_id,
  c.razon_social AS cliente,
  mv.tipo,
  mv.puntos,
  mv.saldo_despues,
  mv.descripcion,
  mv.canal,
  mv.created_at
FROM lealtad_movimientos mv
JOIN lealtad_miembros m ON m.id = mv.miembro_id
JOIN contactos c ON c.id = m.contacto_id
ORDER BY mv.created_at DESC;

-- Vista: puntos proximos a vencer
CREATE OR REPLACE VIEW v_lealtad_puntos_por_vencer AS
SELECT
  mv.empresa_id,
  m.contacto_id,
  c.razon_social AS cliente,
  c.email,
  c.whatsapp,
  SUM(mv.puntos_vigentes) AS puntos_por_vencer,
  MIN(mv.fecha_vencimiento) AS fecha_vencimiento_proxima,
  mv.fecha_vencimiento - CURRENT_DATE AS dias_restantes
FROM lealtad_movimientos mv
JOIN lealtad_miembros m ON m.id = mv.miembro_id
JOIN contactos c ON c.id = m.contacto_id
WHERE mv.tipo = 'ACUMULACION'
  AND mv.puntos_vigentes > 0
  AND mv.fecha_vencimiento IS NOT NULL
GROUP BY mv.empresa_id, m.contacto_id, c.razon_social, c.email, c.whatsapp,
         mv.fecha_vencimiento;
```

#### Integracion Module Service Bus

```sql
-- ========================================
-- BUS → LEALTAD
-- ========================================

-- Acumular puntos (llamada desde POS, Ecommerce, o facturacion)
CREATE OR REPLACE FUNCTION module_bus.accrue_loyalty_points(
  p_empresa_id  UUID,
  p_factura_id  UUID
) RETURNS module_bus.bus_response
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_result module_bus.bus_response;
  v_puntos INTEGER;
BEGIN
  IF NOT module_bus.is_module_active(p_empresa_id, 'ventas') THEN
    v_result := (false, 'module_inactive', 'ventas', null);
    RETURN v_result;
  END IF;

  v_puntos := lealtad_acumular_puntos(p_empresa_id, p_factura_id);

  v_result := (true, null, 'ventas',
    jsonb_build_object('puntos_acumulados', v_puntos));
  RETURN v_result;
END;
$$;

-- Consultar puntos de un cliente (desde POS o Ecommerce)
CREATE OR REPLACE FUNCTION module_bus.get_loyalty_balance(
  p_empresa_id  UUID,
  p_contacto_id UUID
) RETURNS module_bus.bus_response
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_result module_bus.bus_response;
  v_data JSONB;
BEGIN
  IF NOT module_bus.is_module_active(p_empresa_id, 'ventas') THEN
    v_result := (false, 'module_inactive', 'ventas', null);
    RETURN v_result;
  END IF;

  v_data := lealtad_consultar_miembro(p_empresa_id, p_contacto_id);

  v_result := (true, null, 'ventas', v_data);
  RETURN v_result;
END;
$$;

-- Canjear puntos (desde POS o Ecommerce)
CREATE OR REPLACE FUNCTION module_bus.redeem_loyalty_points(
  p_empresa_id    UUID,
  p_contacto_id   UUID,
  p_regla_canje_id UUID,
  p_factura_id    UUID DEFAULT NULL,
  p_canal         VARCHAR DEFAULT 'POS',
  p_usuario_id    UUID DEFAULT NULL
) RETURNS module_bus.bus_response
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_result module_bus.bus_response;
  v_canje_id UUID;
BEGIN
  IF NOT module_bus.is_module_active(p_empresa_id, 'ventas') THEN
    v_result := (false, 'module_inactive', 'ventas', null);
    RETURN v_result;
  END IF;

  v_canje_id := lealtad_canjear_puntos(
    p_empresa_id, p_contacto_id, p_regla_canje_id,
    p_factura_id, p_canal, p_usuario_id
  );

  v_result := (true, null, 'ventas',
    jsonb_build_object('canje_id', v_canje_id));
  RETURN v_result;
END;
$$;
```

#### RLS Policies

```sql
ALTER TABLE lealtad_programas ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON lealtad_programas FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

ALTER TABLE lealtad_niveles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON lealtad_niveles FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

ALTER TABLE lealtad_reglas_acumulacion ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON lealtad_reglas_acumulacion FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

ALTER TABLE lealtad_reglas_canje ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON lealtad_reglas_canje FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

ALTER TABLE lealtad_miembros ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON lealtad_miembros FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

ALTER TABLE lealtad_movimientos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON lealtad_movimientos FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

ALTER TABLE lealtad_canjes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON lealtad_canjes FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));
```

#### Flujo UI/UX

```
features/ventas/lealtad/
  screens/
    loyalty_programs_screen.dart        # Lista de programas (SfDataGrid)
    loyalty_program_form_screen.dart    # Crear/editar programa + niveles + reglas
    loyalty_members_screen.dart         # Lista de miembros con puntos/nivel
    loyalty_member_detail_screen.dart   # Detalle miembro: movimientos, canjes, nivel
    loyalty_redemptions_screen.dart     # Historial de canjes
    loyalty_reports_screen.dart         # Reportes: por nivel, vencimientos, ROI
  widgets/
    loyalty_badge_widget.dart           # Badge nivel (color + nombre + puntos)
    loyalty_points_indicator.dart       # Indicador circular puntos / siguiente nivel
    loyalty_redeem_dialog.dart          # Dialog de canje en POS/facturacion

Integracion en POS:
  - Al identificar cliente: mostrar LoyaltyBadgeWidget con nivel y puntos
  - Al cobrar: boton "Canjear puntos" abre LoyaltyRedeemDialog
  - Dialog muestra canjes disponibles segun puntos del cliente
  - Al confirmar canje: aplica descuento como linea negativa en la venta
  - Al completar venta: trigger acumula puntos automaticamente

Responsive:
  COMPACT: badge compacto (solo puntos), dialog bottom sheet para canje
  MEDIUM: badge con nivel + puntos, dialog lateral
  EXPANDED/LARGE: panel lateral permanente en POS con info de lealtad
```

---

