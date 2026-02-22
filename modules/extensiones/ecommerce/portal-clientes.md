# Portal Autoservicio de Clientes


## Descripcion Funcional

Portal web donde los clientes de una empresa PILAR pueden acceder a sus documentos, estado de cuenta, pagar online y gestionar sus datos. El portal es una extension del modulo Ecommerce existente, implementado como Flutter Web (misma tecnologia que PILAR ERP).

**Acceso al portal:**
- URL: `portal.<slug-empresa>.pilar.ec` (subdominio por empresa)
- Login por email + password (supabase_auth) o magic link
- Opcion de acceso con token temporal (link en email de factura)
- No requiere instalacion (100% web)

**Funcionalidades del portal:**

| Funcionalidad | Descripcion | Prioridad |
|--------------|-------------|-----------|
| Ver facturas emitidas | Lista de facturas con filtros, descarga PDF/XML | Alta |
| Descargar RIDE + XML | PDF del comprobante + XML autorizado SRI | Alta |
| Ver estado de cuenta | Saldo pendiente, facturas vencidas, pagos realizados | Alta |
| Pagar online | Pago con tarjeta (Kushki/Paymentez) desde el portal | Alta |
| Historial de compras | Todas las compras con detalle de productos | Media |
| Repetir pedido | Seleccionar pedido anterior y re-ordenar | Media |
| Descargar retenciones | Retenciones que la empresa le ha emitido | Media |
| Actualizar datos | Modificar email, telefono, direccion de entrega | Media |
| Tickets de soporte | Crear y dar seguimiento a reclamos/consultas | Baja |
| Cotizaciones | Ver cotizaciones pendientes y aceptar/rechazar | Baja |

**Notificaciones automaticas al cliente:**
- Nueva factura emitida: email con link al portal + PDF adjunto
- Factura proxima a vencer: recordatorio 5 dias antes
- Pago recibido: confirmacion por email
- Cotizacion enviada: email con link para ver/aceptar
- Respuesta a ticket de soporte: notificacion por email

## Modelo de Datos

```sql
-- ============================================================
-- MIGRACION: 027_create_portal_clientes.sql
-- ============================================================

-- 1. Accesos al portal de clientes
-- Cada contacto puede tener un usuario de Supabase Auth asociado
CREATE TABLE portal_accesos (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  contacto_id     UUID NOT NULL REFERENCES contactos(id),
  usuario_id      UUID REFERENCES auth.users(id),     -- Login Supabase Auth (nullable para token)
  email           VARCHAR(200) NOT NULL,
  activo          BOOLEAN DEFAULT true,
  ultimo_acceso   TIMESTAMPTZ,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(empresa_id, contacto_id)
);

ALTER TABLE portal_accesos ENABLE ROW LEVEL SECURITY;
-- RLS especial: el cliente del portal solo ve SU acceso
CREATE POLICY "portal_self" ON portal_accesos
  FOR SELECT TO authenticated
  USING (usuario_id = auth.uid());
-- Los usuarios internos de la empresa ven todos los accesos
CREATE POLICY "tenant_admin" ON portal_accesos
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE INDEX idx_portal_accesos_usuario ON portal_accesos(usuario_id);
CREATE INDEX idx_portal_accesos_contacto ON portal_accesos(contacto_id);

-- 2. Tokens temporales para acceso sin registro
CREATE TABLE portal_tokens (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  contacto_id     UUID NOT NULL REFERENCES contactos(id),
  token           VARCHAR(64) NOT NULL UNIQUE,
  tipo            VARCHAR(20) NOT NULL DEFAULT 'FACTURA',
    -- FACTURA: ver una factura especifica
    -- CUENTA: ver estado de cuenta completo
    -- PAGO: pagar una factura especifica
  referencia_id   UUID,                            -- ID de factura, cotizacion, etc.
  expira_at       TIMESTAMPTZ NOT NULL,
  usado           BOOLEAN DEFAULT false,
  usado_at        TIMESTAMPTZ,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_portal_tokens_token ON portal_tokens(token);
CREATE INDEX idx_portal_tokens_expira ON portal_tokens(expira_at) WHERE usado = false;

-- 3. Tickets de soporte del portal
CREATE TABLE portal_tickets (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  contacto_id     UUID NOT NULL REFERENCES contactos(id),
  numero          VARCHAR(20) NOT NULL,            -- TKT-000001
  asunto          VARCHAR(200) NOT NULL,
  descripcion     TEXT NOT NULL,
  categoria       VARCHAR(30) DEFAULT 'GENERAL',
    -- GENERAL, FACTURACION, PRODUCTO, ENVIO, DEVOLUCION, GARANTIA, OTRO
  prioridad       VARCHAR(10) DEFAULT 'NORMAL',    -- BAJA, NORMAL, ALTA, URGENTE
  estado          VARCHAR(20) DEFAULT 'ABIERTO',
    -- ABIERTO, EN_PROCESO, ESPERANDO_CLIENTE, RESUELTO, CERRADO
  asignado_a      UUID REFERENCES auth.users(id),
  factura_id      UUID REFERENCES facturas(id),    -- Factura relacionada (opcional)
  pedido_ecommerce_id UUID REFERENCES pedidos_ecommerce(id),
  fecha_resolucion TIMESTAMPTZ,
  calificacion    INTEGER CHECK (calificacion BETWEEN 1 AND 5),
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE portal_tickets ENABLE ROW LEVEL SECURITY;
-- Cliente ve solo sus tickets
CREATE POLICY "portal_own_tickets" ON portal_tickets
  FOR SELECT TO authenticated
  USING (contacto_id = (
    SELECT contacto_id FROM portal_accesos WHERE usuario_id = auth.uid() LIMIT 1
  ));
-- Usuarios internos ven todos los tickets de su empresa
CREATE POLICY "tenant_tickets" ON portal_tickets
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

CREATE INDEX idx_portal_tickets_empresa ON portal_tickets(empresa_id);
CREATE INDEX idx_portal_tickets_contacto ON portal_tickets(contacto_id);
CREATE INDEX idx_portal_tickets_estado ON portal_tickets(estado) WHERE estado NOT IN ('CERRADO', 'RESUELTO');

-- 4. Mensajes de tickets (conversacion)
CREATE TABLE portal_ticket_mensajes (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id       UUID NOT NULL REFERENCES portal_tickets(id) ON DELETE CASCADE,
  autor_tipo      VARCHAR(10) NOT NULL, -- CLIENTE, AGENTE
  autor_id        UUID,                 -- usuario_id (auth.users)
  autor_nombre    VARCHAR(100),
  mensaje         TEXT NOT NULL,
  adjuntos        JSONB DEFAULT '[]',   -- [{nombre, url, tipo}]
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE portal_ticket_mensajes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "portal_own_messages" ON portal_ticket_mensajes
  FOR SELECT TO authenticated
  USING (ticket_id IN (
    SELECT id FROM portal_tickets
    WHERE contacto_id = (
      SELECT contacto_id FROM portal_accesos WHERE usuario_id = auth.uid() LIMIT 1
    )
  ));
CREATE POLICY "tenant_messages" ON portal_ticket_mensajes
  FOR ALL TO authenticated
  USING (ticket_id IN (
    SELECT id FROM portal_tickets WHERE empresa_id = (SELECT private.get_empresa_id())
  ));

CREATE INDEX idx_portal_msg_ticket ON portal_ticket_mensajes(ticket_id);

-- 5. Configuracion del portal por empresa
CREATE TABLE portal_config (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id) UNIQUE,
  portal_activo   BOOLEAN DEFAULT false,
  slug            VARCHAR(50) UNIQUE,              -- subdominio: slug.pilar.ec
  logo_url        TEXT,
  color_primario  VARCHAR(7) DEFAULT '#1976D2',
  color_secundario VARCHAR(7) DEFAULT '#424242',
  mensaje_bienvenida TEXT,
  mostrar_precios BOOLEAN DEFAULT true,
  permitir_pago_online BOOLEAN DEFAULT true,
  permitir_repetir_pedido BOOLEAN DEFAULT true,
  permitir_tickets BOOLEAN DEFAULT true,
  permitir_actualizar_datos BOOLEAN DEFAULT true,
  notificar_factura_nueva BOOLEAN DEFAULT true,
  notificar_vencimiento_dias INTEGER DEFAULT 5,
  pasarela_pago   VARCHAR(20) DEFAULT 'KUSHKI',    -- KUSHKI, PAYMENTEZ
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE portal_config ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON portal_config
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- 6. Log de actividad del portal (auditoria)
CREATE TABLE portal_actividad_log (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  contacto_id     UUID NOT NULL REFERENCES contactos(id),
  accion          VARCHAR(30) NOT NULL,
    -- LOGIN, LOGOUT, VER_FACTURA, DESCARGAR_PDF, DESCARGAR_XML,
    -- VER_ESTADO_CUENTA, PAGAR, REPETIR_PEDIDO, CREAR_TICKET,
    -- ACTUALIZAR_DATOS, ACEPTAR_COTIZACION
  referencia_tipo VARCHAR(30),
  referencia_id   UUID,
  ip_address      INET,
  user_agent      TEXT,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_portal_log_empresa ON portal_actividad_log(empresa_id, created_at DESC);
CREATE INDEX idx_portal_log_contacto ON portal_actividad_log(contacto_id);

ALTER TABLE portal_actividad_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON portal_actividad_log
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));
```

## Funciones PostgreSQL

```sql
-- ============================================================
-- RPC: Obtener estado de cuenta del cliente (para portal)
-- ============================================================
CREATE OR REPLACE FUNCTION portal_get_account_statement(
  p_token VARCHAR(64) DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_contacto_id UUID;
  v_empresa_id UUID;
  v_resultado JSONB;
BEGIN
  -- Determinar contacto por token o por sesion
  IF p_token IS NOT NULL THEN
    SELECT contacto_id, empresa_id INTO v_contacto_id, v_empresa_id
    FROM portal_tokens
    WHERE token = p_token AND expira_at > NOW() AND usado = false
      AND tipo IN ('CUENTA', 'PAGO');

    IF NOT FOUND THEN RAISE EXCEPTION 'Token invalido o expirado'; END IF;
  ELSE
    SELECT pa.contacto_id, pa.empresa_id INTO v_contacto_id, v_empresa_id
    FROM portal_accesos pa
    WHERE pa.usuario_id = auth.uid() AND pa.activo = true
    LIMIT 1;

    IF NOT FOUND THEN RAISE EXCEPTION 'Acceso al portal no configurado'; END IF;
  END IF;

  -- Construir estado de cuenta
  SELECT jsonb_build_object(
    'contacto', (SELECT jsonb_build_object(
      'nombre', c.nombre, 'identificacion', c.identificacion, 'email', c.email
    ) FROM contactos c WHERE c.id = v_contacto_id),

    'resumen', jsonb_build_object(
      'total_pendiente', COALESCE((
        SELECT SUM(saldo_pendiente) FROM cuentas_por_cobrar
        WHERE empresa_id = v_empresa_id AND contacto_id = v_contacto_id
          AND estado IN ('PENDIENTE', 'PARCIAL', 'VENCIDA')
      ), 0),
      'total_vencido', COALESCE((
        SELECT SUM(saldo_pendiente) FROM cuentas_por_cobrar
        WHERE empresa_id = v_empresa_id AND contacto_id = v_contacto_id
          AND estado = 'VENCIDA'
      ), 0),
      'facturas_pendientes', (
        SELECT COUNT(*) FROM cuentas_por_cobrar
        WHERE empresa_id = v_empresa_id AND contacto_id = v_contacto_id
          AND estado IN ('PENDIENTE', 'PARCIAL', 'VENCIDA')
      )
    ),

    'facturas', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', f.id,
        'numero', f.numero_comprobante,
        'fecha', f.fecha_emision,
        'total', f.total,
        'saldo', cxc.saldo_pendiente,
        'vencimiento', cxc.fecha_vencimiento,
        'estado', cxc.estado,
        'dias_vencido', GREATEST(0, CURRENT_DATE - cxc.fecha_vencimiento)
      ) ORDER BY f.fecha_emision DESC), '[]'::JSONB)
      FROM facturas f
      LEFT JOIN cuentas_por_cobrar cxc ON cxc.documento_id = f.id
      WHERE f.empresa_id = v_empresa_id AND f.contacto_id = v_contacto_id
        AND f.estado NOT IN ('ANULADA', 'BORRADOR')
    ),

    'pagos_recientes', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', cb.id,
        'fecha', cb.fecha,
        'monto', cb.monto_total,
        'metodo', cb.metodo_pago
      ) ORDER BY cb.fecha DESC), '[]'::JSONB)
      FROM cobros cb
      WHERE cb.empresa_id = v_empresa_id AND cb.contacto_id = v_contacto_id
      LIMIT 20
    )
  ) INTO v_resultado;

  -- Registrar actividad
  INSERT INTO portal_actividad_log (empresa_id, contacto_id, accion)
  VALUES (v_empresa_id, v_contacto_id, 'VER_ESTADO_CUENTA');

  RETURN v_resultado;
END;
$$;

-- ============================================================
-- RPC: Obtener facturas del cliente (para portal)
-- ============================================================
CREATE OR REPLACE FUNCTION portal_get_invoices(
  p_page INTEGER DEFAULT 1,
  p_page_size INTEGER DEFAULT 20,
  p_estado VARCHAR(20) DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_contacto_id UUID;
  v_empresa_id UUID;
BEGIN
  SELECT pa.contacto_id, pa.empresa_id INTO v_contacto_id, v_empresa_id
  FROM portal_accesos pa
  WHERE pa.usuario_id = auth.uid() AND pa.activo = true LIMIT 1;

  IF NOT FOUND THEN RAISE EXCEPTION 'Acceso al portal no configurado'; END IF;

  RETURN jsonb_build_object(
    'facturas', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', f.id,
        'numero', f.numero_comprobante,
        'fecha', f.fecha_emision,
        'subtotal', f.subtotal_iva + f.subtotal_0,
        'iva', f.iva,
        'total', f.total,
        'estado_sri', de.estado,
        'xml_url', de.xml_autorizado_url,
        'ride_url', de.ride_url
      ) ORDER BY f.fecha_emision DESC), '[]'::JSONB)
      FROM facturas f
      LEFT JOIN documentos_electronicos de ON de.documento_id = f.id
        AND de.tipo_documento = 'FACTURA'
      WHERE f.empresa_id = v_empresa_id AND f.contacto_id = v_contacto_id
        AND f.estado NOT IN ('ANULADA', 'BORRADOR')
      OFFSET (p_page - 1) * p_page_size
      LIMIT p_page_size
    ),
    'total', (
      SELECT COUNT(*) FROM facturas
      WHERE empresa_id = v_empresa_id AND contacto_id = v_contacto_id
        AND estado NOT IN ('ANULADA', 'BORRADOR')
    ),
    'page', p_page,
    'page_size', p_page_size
  );
END;
$$;

-- ============================================================
-- RPC: Generar token temporal para acceso al portal
-- ============================================================
CREATE OR REPLACE FUNCTION generate_portal_token(
  p_empresa_id    UUID,
  p_contacto_id   UUID,
  p_tipo          VARCHAR(20),
  p_referencia_id UUID DEFAULT NULL,
  p_horas_validez INTEGER DEFAULT 72
) RETURNS VARCHAR(64)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_token VARCHAR(64);
BEGIN
  v_token := encode(gen_random_bytes(32), 'hex');

  INSERT INTO portal_tokens (empresa_id, contacto_id, token, tipo, referencia_id, expira_at)
  VALUES (p_empresa_id, p_contacto_id, v_token, p_tipo, p_referencia_id,
          NOW() + (p_horas_validez || ' hours')::INTERVAL);

  RETURN v_token;
END;
$$;

-- ============================================================
-- RPC: Crear ticket de soporte desde portal
-- ============================================================
CREATE OR REPLACE FUNCTION portal_create_ticket(
  p_asunto      VARCHAR(200),
  p_descripcion TEXT,
  p_categoria   VARCHAR(30) DEFAULT 'GENERAL',
  p_factura_id  UUID DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_contacto_id UUID;
  v_empresa_id UUID;
  v_ticket_id UUID;
  v_numero VARCHAR(20);
BEGIN
  SELECT pa.contacto_id, pa.empresa_id INTO v_contacto_id, v_empresa_id
  FROM portal_accesos pa
  WHERE pa.usuario_id = auth.uid() AND pa.activo = true LIMIT 1;

  IF NOT FOUND THEN RAISE EXCEPTION 'Acceso al portal no configurado'; END IF;

  -- Generar numero secuencial
  SELECT 'TKT-' || LPAD(
    (COALESCE(MAX(CAST(SUBSTRING(numero FROM 5) AS INTEGER)), 0) + 1)::TEXT,
    6, '0')
  INTO v_numero
  FROM portal_tickets WHERE empresa_id = v_empresa_id;

  INSERT INTO portal_tickets (
    empresa_id, contacto_id, numero, asunto, descripcion,
    categoria, factura_id
  ) VALUES (
    v_empresa_id, v_contacto_id, v_numero, p_asunto,
    p_descripcion, p_categoria, p_factura_id
  ) RETURNING id INTO v_ticket_id;

  -- Registrar actividad
  INSERT INTO portal_actividad_log (empresa_id, contacto_id, accion, referencia_tipo, referencia_id)
  VALUES (v_empresa_id, v_contacto_id, 'CREAR_TICKET', 'portal_tickets', v_ticket_id);

  RETURN v_ticket_id;
END;
$$;

-- ============================================================
-- RPC: Repetir pedido anterior
-- ============================================================
CREATE OR REPLACE FUNCTION portal_repeat_order(
  p_factura_id UUID
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_contacto_id UUID;
  v_empresa_id UUID;
  v_nueva_ov_id UUID;
  v_factura RECORD;
BEGIN
  SELECT pa.contacto_id, pa.empresa_id INTO v_contacto_id, v_empresa_id
  FROM portal_accesos pa
  WHERE pa.usuario_id = auth.uid() AND pa.activo = true LIMIT 1;

  IF NOT FOUND THEN RAISE EXCEPTION 'Acceso al portal no configurado'; END IF;

  -- Validar que la factura pertenece al cliente
  SELECT * INTO v_factura FROM facturas
  WHERE id = p_factura_id AND empresa_id = v_empresa_id AND contacto_id = v_contacto_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Factura no encontrada'; END IF;

  -- Crear nueva orden de venta con los mismos items (precios actualizados)
  INSERT INTO ordenes_venta (empresa_id, contacto_id, estado, origen, notas)
  VALUES (v_empresa_id, v_contacto_id, 'BORRADOR', 'PORTAL',
          'Repeticion del pedido ' || v_factura.numero_comprobante)
  RETURNING id INTO v_nueva_ov_id;

  -- Copiar lineas (actualizando precios si cambiaron)
  INSERT INTO orden_venta_lineas (orden_id, producto_id, descripcion, cantidad,
    precio_unitario, subtotal)
  SELECT v_nueva_ov_id, fl.producto_id, fl.descripcion, fl.cantidad,
    COALESCE(p.precio_venta, fl.precio_unitario),
    fl.cantidad * COALESCE(p.precio_venta, fl.precio_unitario)
  FROM factura_lineas fl
  JOIN productos p ON p.id = fl.producto_id
  WHERE fl.factura_id = p_factura_id;

  INSERT INTO portal_actividad_log (empresa_id, contacto_id, accion, referencia_tipo, referencia_id)
  VALUES (v_empresa_id, v_contacto_id, 'REPETIR_PEDIDO', 'ordenes_venta', v_nueva_ov_id);

  RETURN v_nueva_ov_id;
END;
$$;
```

## Triggers

```sql
-- Trigger: al emitir factura, generar token y notificar al cliente
CREATE OR REPLACE FUNCTION trg_factura_notify_portal()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_config RECORD;
  v_token VARCHAR(64);
  v_contacto RECORD;
BEGIN
  -- Solo cuando la factura pasa a estado AUTORIZADA (SRI)
  IF NEW.estado = 'AUTORIZADA' AND (OLD.estado IS NULL OR OLD.estado != 'AUTORIZADA') THEN
    -- Verificar si el portal esta activo para la empresa
    SELECT * INTO v_config FROM portal_config
    WHERE empresa_id = NEW.empresa_id AND portal_activo = true;

    IF FOUND AND v_config.notificar_factura_nueva THEN
      SELECT * INTO v_contacto FROM contactos WHERE id = NEW.contacto_id;

      IF v_contacto.email IS NOT NULL THEN
        -- Generar token temporal
        v_token := generate_portal_token(
          NEW.empresa_id, NEW.contacto_id, 'FACTURA', NEW.id, 168);
          -- 168 horas = 7 dias

        -- Encolar notificacion (usa sistema de notificaciones existente)
        INSERT INTO cola_notificaciones (
          empresa_id, canal, destinatario, plantilla,
          variables, prioridad
        ) VALUES (
          NEW.empresa_id, 'EMAIL', v_contacto.email,
          'factura_nueva_portal',
          jsonb_build_object(
            'cliente_nombre', v_contacto.nombre,
            'factura_numero', NEW.numero_comprobante,
            'factura_total', NEW.total,
            'portal_url', 'https://portal.' || v_config.slug || '.pilar.ec',
            'token_url', 'https://portal.' || v_config.slug || '.pilar.ec/factura?token=' || v_token
          ),
          'NORMAL'
        );
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- NOTA: Este trigger se agrega a facturas SOLO si el portal esta habilitado.
-- Se crea como trigger condicional para no impactar performance.
CREATE TRIGGER trg_factura_portal_notify
  AFTER UPDATE OF estado ON facturas
  FOR EACH ROW
  WHEN (NEW.estado = 'AUTORIZADA')
  EXECUTE FUNCTION trg_factura_notify_portal();
```

## Vistas

```sql
-- Vista: resumen del portal por empresa
CREATE OR REPLACE VIEW v_portal_resumen AS
SELECT
  pc.empresa_id,
  e.razon_social,
  pc.portal_activo,
  pc.slug,
  (SELECT COUNT(*) FROM portal_accesos WHERE empresa_id = pc.empresa_id AND activo = true) AS clientes_registrados,
  (SELECT COUNT(*) FROM portal_tickets WHERE empresa_id = pc.empresa_id AND estado = 'ABIERTO') AS tickets_abiertos,
  (SELECT COUNT(*) FROM portal_actividad_log WHERE empresa_id = pc.empresa_id
    AND created_at > NOW() - INTERVAL '30 days') AS actividad_30_dias,
  (SELECT COUNT(DISTINCT contacto_id) FROM portal_actividad_log WHERE empresa_id = pc.empresa_id
    AND created_at > NOW() - INTERVAL '30 days') AS clientes_activos_30_dias
FROM portal_config pc
JOIN empresas e ON e.id = pc.empresa_id;

-- Vista: tickets pendientes para agentes
CREATE OR REPLACE VIEW v_portal_tickets_pendientes AS
SELECT
  t.id, t.empresa_id, t.numero, t.asunto, t.categoria,
  t.prioridad, t.estado, t.created_at,
  c.nombre AS cliente_nombre,
  c.email AS cliente_email,
  u.email AS agente_email,
  NOW() - t.created_at AS tiempo_abierto,
  (SELECT COUNT(*) FROM portal_ticket_mensajes WHERE ticket_id = t.id) AS num_mensajes
FROM portal_tickets t
JOIN contactos c ON c.id = t.contacto_id
LEFT JOIN auth.users u ON u.id = t.asignado_a
WHERE t.estado NOT IN ('CERRADO', 'RESUELTO')
ORDER BY
  CASE t.prioridad WHEN 'URGENTE' THEN 1 WHEN 'ALTA' THEN 2 WHEN 'NORMAL' THEN 3 ELSE 4 END,
  t.created_at;
```

## Integracion Module Service Bus

```sql
-- El portal usa funciones SECURITY DEFINER directamente,
-- no pasa por module_bus ya que el portal es una extension de ecommerce.

-- Sin embargo, al repetir pedido, se usa el bus para crear OV:
CREATE OR REPLACE FUNCTION module_bus.create_portal_order(
  p_empresa_id    UUID,
  p_contacto_id   UUID,
  p_lineas        JSONB,
  p_origen        VARCHAR(20) DEFAULT 'PORTAL'
) RETURNS module_bus.bus_response
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_result module_bus.bus_response;
  v_ov_id UUID;
BEGIN
  IF NOT module_bus.is_module_active(p_empresa_id, 'ventas') THEN
    v_result := (false, 'module_inactive', 'ventas', null);
    RETURN v_result;
  END IF;

  -- Crear OV en estado BORRADOR (requiere confirmacion interna)
  INSERT INTO ordenes_venta (empresa_id, contacto_id, estado, origen)
  VALUES (p_empresa_id, p_contacto_id, 'BORRADOR', p_origen)
  RETURNING id INTO v_ov_id;

  -- Insertar lineas...
  -- (delegado a logica existente de OV)

  v_result := (true, null, 'ventas',
    jsonb_build_object('orden_venta_id', v_ov_id));
  RETURN v_result;
END;
$$;
```

## RLS Policies

Ya definidas en cada tabla de la seccion 27.1.2. Resumen del patron:

```
Portal de Clientes - Patron de Seguridad:

1. Tablas con datos DEL cliente (portal_accesos, portal_tickets, etc.):
   - Policy "portal_self": cliente solo ve SUS datos (via auth.uid() -> portal_accesos -> contacto_id)
   - Policy "tenant_admin": usuarios internos ven TODOS los datos de la empresa

2. Tablas con datos de facturas/cobros/CxC:
   - El portal NO accede directamente a estas tablas
   - Accede via funciones SECURITY DEFINER (portal_get_invoices, portal_get_account_statement)
   - Las funciones validan el contacto_id del usuario autenticado

3. Tokens temporales:
   - No pasan por RLS (funciones SECURITY DEFINER)
   - Validados por token + expiracion + tipo
   - Se marcan como usados al primer acceso

4. Supabase Auth:
   - Clientes del portal usan el mismo auth.users pero con app_metadata diferente
   - app_metadata.role = 'portal_client'
   - app_metadata.empresa_id = UUID de la empresa
   - app_metadata.contacto_id = UUID del contacto
   - Esto permite diferenciar usuarios internos de clientes del portal
```

## Flujo UI/UX - Portal del Cliente

```
PORTAL WEB (Flutter Web - app separada de PILAR ERP)

+-- LOGIN
|   +-- Email + password
|   +-- Magic link
|   +-- Token temporal (link directo a factura)
|
+-- INICIO (Dashboard del cliente)
|   +-- Bienvenida con nombre
|   +-- Resumen: saldo pendiente, facturas vencidas, ultima compra
|   +-- Accesos rapidos: Ver facturas | Pagar | Soporte
|
+-- MIS FACTURAS
|   +-- Lista paginada con filtros (fecha, estado, monto)
|   +-- Detalle factura (productos, totales, impuestos)
|   +-- Botones: Descargar PDF | Descargar XML | Pagar esta factura
|   +-- Boton: Repetir este pedido
|
+-- ESTADO DE CUENTA
|   +-- Resumen: saldo total, vencido, al dia
|   +-- Aging: 0-30 | 31-60 | 61-90 | 90+ dias
|   +-- Lista de documentos pendientes
|   +-- Boton: Pagar todo | Pagar seleccionados
|
+-- PAGAR
|   +-- Seleccionar facturas a pagar
|   +-- Ingresar monto (total o parcial)
|   +-- Formulario de pago (Kushki widget embebido)
|   +-- Confirmacion de pago + recibo descargable
|
+-- MIS RETENCIONES
|   +-- Lista de retenciones que la empresa le ha emitido
|   +-- Descargar PDF/XML de cada retencion
|
+-- MIS DATOS
|   +-- Ver/editar: nombre, email, telefono, direccion
|   +-- Cambiar password
|   +-- Direcciones de entrega adicionales
|
+-- SOPORTE
|   +-- Lista de tickets (abiertos, cerrados)
|   +-- + Nuevo ticket (asunto, descripcion, categoria, adjuntos)
|   +-- Conversacion del ticket (mensajes cliente <-> agente)
|
+-- COTIZACIONES (si habilitado)
    +-- Lista de cotizaciones pendientes
    +-- Detalle con productos y precios
    +-- Botones: Aceptar | Rechazar | Solicitar cambios
```

## Edge Functions - Portal

```
1. portal-auth/index.ts (NUEVA)
   - POST /functions/v1/portal-auth
   - verify_jwt: false (pre-auth)
   - Acciones:
     a. validate_token: valida token temporal, retorna JWT de sesion limitada
     b. register_client: crea cuenta de portal para un contacto existente
   - Retorna JWT con claims especiales (role=portal_client, contacto_id)

2. portal-payment/index.ts (NUEVA)
   - POST /functions/v1/portal-payment
   - verify_jwt: true (portal_client)
   - Integra con Kushki/Paymentez para procesar pago
   - Registra cobro en PILAR (via module_bus.create_payment)
   - Actualiza CxC
   - Envia confirmacion por email

3. portal-download/index.ts (NUEVA)
   - GET /functions/v1/portal-download?type=ride&id=xxx
   - GET /functions/v1/portal-download?type=xml&id=xxx
   - verify_jwt: true (portal_client) o token temporal
   - Valida que el documento pertenece al contacto
   - Genera URL firmada de Supabase Storage (expira en 1 hora)
   - Registra en portal_actividad_log

4. portal-notifications/index.ts (NUEVA)
   - Cron diario
   - Detecta facturas proximas a vencer (config.notificar_vencimiento_dias)
   - Envia recordatorio por email al cliente
   - Detecta cuotas de credito proximas a vencer
```

---

## Resumen de Tablas Nuevas

### Modulo Ecommerce/Marketplace

| Tabla | Proposito |
|-------|-----------|
| `mapeo_categorias_marketplace` | Mapeo categorias PILAR <-> marketplace |
| `marketplace_mensajes` | Preguntas y mensajes de marketplaces |
| `marketplace_metricas` | Metricas diarias de reputacion/ventas |
| `ecommerce_sync_log` | Log de sincronizaciones |
| `marketplace_liquidaciones` | Liquidaciones de cobros del marketplace |
| `ecommerce_stock_queue` | Cola de actualizacion de stock a marketplaces |

Tablas existentes ampliadas: `tiendas_ecommerce`, `mapeo_productos`, `pedidos_ecommerce`

### Modulo Intercompany

| Tabla | Proposito |
|-------|-----------|
| `grupos_empresariales` | Grupos de empresas vinculadas |
| `grupo_empresas` | Relacion grupo <-> empresa con % participacion |
| `intercompany_config` | Config de precios/aprobacion por par de empresas |
| `intercompany_transacciones` | Registro maestro de operaciones IC |
| `intercompany_transaccion_lineas` | Detalle de items por transaccion |
| `intercompany_saldos` | Saldos cruzados entre empresas |
| `intercompany_mapeo_productos` | Equivalencia de productos entre empresas |
| `intercompany_mapeo_cuentas` | Equivalencia de cuentas para consolidacion |
| `intercompany_prestamos` | Prestamos monetarios/mercaderia IC |
| `intercompany_prestamo_cuotas` | Tabla de amortizacion de prestamos IC |

Tablas existentes ampliadas: `contactos` (es_intercompany, empresa_vinculada_id)

### Portal de Clientes

| Tabla | Proposito |
|-------|-----------|
| `portal_accesos` | Vinculacion contacto <-> usuario auth del portal |
| `portal_tokens` | Tokens temporales de acceso (link en email) |
| `portal_tickets` | Tickets de soporte del cliente |
| `portal_ticket_mensajes` | Conversacion de tickets |
| `portal_config` | Configuracion del portal por empresa |
| `portal_actividad_log` | Auditoria de acciones del portal |

---

## Resumen de Edge Functions Nuevas

| Edge Function | Modulo | Tipo | verify_jwt |
|--------------|--------|------|------------|
| `ml-oauth-callback` | Ecommerce | HTTP GET (callback) | false |
| `ml-refresh-token` | Ecommerce | Cron (5h) | N/A |
| `sync-marketplace-stock` | Ecommerce | Cron (5min) | N/A |
| `marketplace-messages` | Ecommerce | HTTP POST | true |
| `marketplace-metrics` | Ecommerce | Cron (diario) | N/A |
| `portal-auth` | Portal | HTTP POST | false |
| `portal-payment` | Portal | HTTP POST | true |
| `portal-download` | Portal | HTTP GET | true/token |
| `portal-notifications` | Portal | Cron (diario) | N/A |

Edge Functions existentes ampliadas: `webhook-ecommerce`, `sync-ecommerce`

---

## Resumen de Funciones PostgreSQL (RPC) Nuevas

| Funcion | Modulo | Tipo |
|---------|--------|------|
| `process_marketplace_order` | Ecommerce | RPC |
| `find_or_create_contact_from_marketplace` | Ecommerce | Helper |
| `sync_stock_to_marketplaces` | Ecommerce | Internal |
| `module_bus.notify_stock_change` | Bus -> Ecommerce | Bus |
| `module_bus.create_ecommerce_order` | Bus -> Ecommerce | Bus |
| `create_intercompany_sale` | Intercompany | RPC |
| `calculate_transfer_price` | Intercompany | Helper |
| `confirm_intercompany_sale` | Intercompany | RPC |
| `find_or_create_intercompany_contact` | Intercompany | Helper |
| `create_intercompany_transfer` | Intercompany | RPC |
| `confirm_intercompany_transfer` | Intercompany | RPC |
| `generate_intercompany_amortization` | Intercompany | RPC |
| `get_consolidated_balance` | Intercompany | RPC |
| `module_bus.create_intercompany_sale` | Bus -> IC | Bus |
| `private.get_user_grupo_ids` | Intercompany | RLS Helper |
| `private.user_in_grupo` | Intercompany | RLS Helper |
| `portal_get_account_statement` | Portal | RPC |
| `portal_get_invoices` | Portal | RPC |
| `generate_portal_token` | Portal | RPC |
| `portal_create_ticket` | Portal | RPC |
| `portal_repeat_order` | Portal | RPC |
| `module_bus.create_portal_order` | Bus -> Ventas | Bus |

---

*Documento extraido del INFORME_ERP_PILAR.md.*


