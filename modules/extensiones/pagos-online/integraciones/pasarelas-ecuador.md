# Pasarelas de Pago Ecuador

> Extraído de `foundation/integraciones/pagos.md` durante refactor ADR-006 (foundation country-agnostic).
> Contiene toda la especificación Ecuador-específica: comparativa de pasarelas locales,
> tarifas en USD, endpoints sandbox, webhooks, débito bancario (Pichincha/Pacifico/Guayaquil),
> datafonos (Datafast/Medianet), QR EMVCo y billeteras digitales locales.

---

## Comparativa de Pasarelas para Ecuador

| Caracteristica | **Kushki** | **PayPhone** | **Paymentez/Nuvei** | **PlaceToPay** | **Stripe** |
|----------------|-----------|-------------|-------------------|---------------|-----------|
| **Disponible en Ecuador** | Si (HQ Quito) | Si (nativo) | Si | Si | No directo |
| **API** | REST + JS lib | REST (Swagger) | REST + Hosted | REST + Checkout | REST |
| **Flutter SDK** | `flutter_kushki` | `flutter_payphone` | `paymentez_sdk` | No (WebView) | `flutter_stripe` |
| **Deno/TS Backend** | REST (fetch) | REST (fetch) | REST (fetch) | REST (fetch) | npm + fetch |
| **Tarjetas locales** | Visa/MC/Diners/Amex | Visa/MC/Diners | Visa/MC/Diners/Amex | Todas | N/A directo |
| **Pagos recurrentes** | **Nativo** | Solo tokenizacion | Parcial | **Nativo** | **Nativo** |
| **Comision** | Negociada | 5% + IVA | Negociada | $250+/mes base | 2.9% + $0.30 |
| **PCI DSS** | Level 1 | Via Cybersource | Level 1 | Level 1 | Level 1 |
| **Webhooks** | Si | Limitado | Si | Si | Si |
| **Sandbox/Testing** | Si | Si | Si | Si | Si |

## Pasarelas Configurables (Primera Clase)

El administrador de cada empresa elige cual(es) pasarela(s) usar desde la configuración. Las tres son opciones de primera clase:

| Pasarela | Flutter SDK | Fortaleza | Consideracion |
|----------|-------------|-----------|---------------|
| **Kushki** | `flutter_kushki` | Pagos recurrentes nativos, HQ Ecuador, PCI Level 1 | Comision negociada |
| **Paymentez/Nuvei** | `paymentez_sdk` | Sin costos fijos, fuerte presencia local | Nuvei adquirio, marca hasta ~2027-2028 |
| **PayPhone** | `payphone_sdk` | Pago movil mas usado en Ecuador (2M+ usuarios), QR en POS | 5% + IVA por transaccion |

La arquitectura usa un **patron adaptador** para que agregar nuevas pasarelas en el futuro sea transparente.
Ver patron genérico en [`foundation/integraciones/pagos.md`](../../../../foundation/integraciones/pagos.md).

---

## PayPhone (Pasarela de Pago Movil Ecuador)

PayPhone es el método de pago móvil más usado en Ecuador (2M+ usuarios).
Se integra como tercera pasarela junto a Kushki y Paymentez.

```sql
-- ============================================
-- PAYPHONE (PASARELA DE PAGO MOVIL ECUADOR)
-- ============================================

-- Agregar a la tabla de configuracion de pasarelas:
-- INSERT INTO pasarelas_pago (codigo, nombre, tipo) VALUES
--   ('PAYPHONE', 'PayPhone', 'WALLET_MOVIL');

-- Configuracion por empresa:
-- config_pasarela_payphone:
--   store_id VARCHAR(50)        -- ID de tienda PayPhone
--   app_id VARCHAR(100)         -- Application ID
--   app_secret TEXT             -- Application Secret (cifrado con pgcrypto)
--   environment VARCHAR(10)     -- 'sandbox' o 'production'
--   webhook_url TEXT            -- URL para notificaciones de pago
```

```
Edge Function: process-payphone-payment
Endpoint: /functions/v1/process-payphone-payment
Flujo:
  1. Flutter genera link de pago via PayPhone API (POST /api/Links)
  2. Cliente abre PayPhone y paga con tarjeta guardada
  3. PayPhone envia webhook de confirmacion
  4. Edge Function valida webhook (firma HMAC)
  5. Actualiza estado del pago en PILAR
  6. Genera factura electronica SRI si aplica

PayPhone API endpoints:
  POST /api/Links          -> Crear link de pago
  GET  /api/Links/{id}     -> Consultar estado
  POST /api/Annul          -> Anular transaccion
  POST /api/Reverse        -> Reversar pago

SDK Flutter: payphone_sdk (pub.dev)
Documentacion: https://developers.payphone.app/

Integracion en POS:
  - Boton "Pagar con PayPhone" en pantalla de cobro POS
  - Genera QR code que el cliente escanea con su app PayPhone
  - Confirmacion en tiempo real via Supabase Realtime (webhook -> broadcast)
```

---

## Débito Bancario Automático (Bancos Ecuador)

Generación de archivos de débito bancario para cobro masivo de CxC. Cada banco ecuatoriano
tiene su formato propio (Pacifico CSV, Guayaquil TXT, Pichincha ancho fijo).

```sql
-- MANDATOS DE DEBITO BANCARIO (autorizacion del cliente)
CREATE TABLE mandatos_debito (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id            UUID NOT NULL REFERENCES empresas(id),
  contacto_id           UUID NOT NULL REFERENCES contactos(id),
  banco_id              UUID NOT NULL REFERENCES catalogo_bancos(id),
  tipo_cuenta           VARCHAR(10) NOT NULL,   -- AHORRO, CORRIENTE
  numero_cuenta         VARCHAR(30) NOT NULL,
  estado                VARCHAR(15) NOT NULL DEFAULT 'ACTIVO',
    -- ACTIVO, SUSPENDIDO, CANCELADO
  fecha_autorizacion    DATE NOT NULL,
  documento_autorizacion TEXT,  -- Referencia a Storage (PDF firmado)
  created_at            TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE mandatos_debito ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON mandatos_debito
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));
```

```sql
-- RPC: Generar archivo de debito para un banco
-- Busca transferencias_bancarias con estado='PENDIENTE' para la cuenta indicada
-- y genera el contenido del archivo segun el formato del banco (banco_codigo en cuentas_bancarias).
--
-- Bancos soportados:
--   'BP'  — Banco Pichincha   : pipe-delimited (|)
--   'BPA' — Banco del Pacifico: fixed-width 120 chars
--   'BG'  — Banco Guayaquil   : CSV (coma)
CREATE OR REPLACE FUNCTION generate_debit_file(
  p_cuenta_bancaria_id UUID,
  p_fecha_proceso      DATE
)
RETURNS TEXT   -- Contenido del archivo listo para descargar
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_empresa_id    UUID;
  v_banco_codigo  VARCHAR(10);
  v_ruc           VARCHAR(20);
  v_numero_cuenta VARCHAR(30);
  v_empresa_nombre VARCHAR(300);

  -- Acumuladores
  v_lineas        TEXT[] := ARRAY[]::TEXT[];
  v_seq           INTEGER := 0;
  v_total_monto   DECIMAL(14,2) := 0;
  v_monto_fmt     TEXT;

  -- Fila de cada transferencia pendiente
  r RECORD;
BEGIN
  -- ── Obtener datos de la cuenta bancaria y la empresa ──────────────────────
  SELECT cb.empresa_id, cb.banco_codigo, cb.numero_cuenta,
         e.ruc, e.nombre
  INTO   v_empresa_id, v_banco_codigo, v_numero_cuenta, v_ruc, v_empresa_nombre
  FROM   cuentas_bancarias cb
  JOIN   empresas e ON e.id = cb.empresa_id
  WHERE  cb.id = p_cuenta_bancaria_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Cuenta bancaria % no encontrada', p_cuenta_bancaria_id;
  END IF;

  -- Verificar que el usuario pertenece a la empresa (RLS adicional)
  IF v_empresa_id <> (SELECT private.get_empresa_id()) THEN
    RAISE EXCEPTION 'Acceso denegado';
  END IF;

  -- ── Iterar sobre las transferencias PENDIENTES de la cuenta ───────────────
  FOR r IN
    SELECT tb.id,
           tb.monto,
           tb.concepto,
           COALESCE(c.numero_identificacion, '') AS cuenta_destino,
           COALESCE(c.nombre, tb.concepto)       AS nombre_beneficiario,
           COALESCE(c.email, '')                 AS email_beneficiario,
           COALESCE(cb2.numero_cuenta, '')        AS cuenta_credito,
           COALESCE(cb2.tipo_cuenta, 'AHORRO')   AS tipo_cuenta_destino,
           COALESCE(cb2.banco_codigo, '')         AS banco_destino
    FROM   transferencias_bancarias tb
    LEFT   JOIN contactos        c   ON c.id   = tb.contacto_id
    LEFT   JOIN cuentas_bancarias cb2 ON cb2.id = tb.cuenta_destino_id
    WHERE  tb.cuenta_origen_id = p_cuenta_bancaria_id
      AND  tb.estado           = 'PENDIENTE'
      AND  tb.fecha            <= p_fecha_proceso
      AND  tb.empresa_id       = v_empresa_id
    ORDER  BY tb.fecha, tb.created_at
  LOOP
    v_seq         := v_seq + 1;
    v_total_monto := v_total_monto + r.monto;

    CASE v_banco_codigo

      -- ── BANCO PICHINCHA (BP) : pipe-delimited ─────────────────────────────
      WHEN 'BP' THEN
        v_lineas := v_lineas || format(
          'DTL|%s|%s|%s|%s|%s|%s',
          v_seq,
          r.cuenta_credito,
          r.nombre_beneficiario,
          to_char(r.monto, 'FM99999999990.00'),
          COALESCE(r.concepto, 'PAGO'),
          r.banco_destino
        );

      -- ── BANCO DEL PACIFICO (BPA) : fixed-width 120 chars ─────────────────
      WHEN 'BPA' THEN
        -- Monto: 14 chars, 2 decimales, sin punto, cero-padded
        -- Ej: 1234.56 → '00000000123456'
        v_monto_fmt := lpad(
          replace(to_char(r.monto, 'FM99999999990.00'), '.', ''),
          14, '0'
        );
        v_lineas := v_lineas || (
          '02'                                          -- pos  1-2  : tipo registro detalle
          || rpad(v_ruc,                  12, ' ')      -- pos  3-14 : RUC empresa
          || rpad(v_numero_cuenta,        15, ' ')      -- pos 15-29 : cuenta debito
          || rpad(r.cuenta_credito,       20, ' ')      -- pos 30-49 : cuenta credito
          || rpad(left(r.nombre_beneficiario, 40), 40, ' ')  -- pos 50-89  : nombre
          || v_monto_fmt                                -- pos 90-103: monto (14 chars)
          || rpad(left(COALESCE(r.concepto,'PAGO'), 17), 17, ' ')  -- pos 104-120: concepto
        );

      -- ── BANCO GUAYAQUIL (BG) : CSV (coma) ────────────────────────────────
      WHEN 'BG' THEN
        -- Encabezado solo en el primer registro
        IF v_seq = 1 THEN
          v_lineas := ARRAY['secuencia,tipo_cuenta,cuenta,nombre,monto,concepto,email'];
        END IF;
        v_lineas := v_lineas || format(
          '%s,%s,%s,%s,%s,%s,%s',
          v_seq,
          r.tipo_cuenta_destino,
          r.cuenta_credito,
          replace(r.nombre_beneficiario, ',', ' '),   -- escapar comas en nombre
          to_char(r.monto, 'FM99999999990.00'),
          replace(COALESCE(r.concepto, 'PAGO'), ',', ' '),
          r.email_beneficiario
        );

      ELSE
        RAISE EXCEPTION 'Banco no soportado para debito: %', v_banco_codigo;
    END CASE;
  END LOOP;

  -- ── Encabezado y pie segun banco ──────────────────────────────────────────
  IF v_seq = 0 THEN
    RETURN '';  -- Sin transferencias pendientes
  END IF;

  CASE v_banco_codigo

    WHEN 'BP' THEN
      -- Encabezado: HDR|YYYYMMDD|ruc|cuenta_debito|total_registros|total_monto
      v_lineas := ARRAY[
        format('HDR|%s|%s|%s|%s|%s',
          to_char(p_fecha_proceso, 'YYYYMMDD'),
          v_ruc,
          v_numero_cuenta,
          v_seq,
          to_char(v_total_monto, 'FM99999999990.00')
        )
      ] || v_lineas;
      -- Pie: PIE|total_registros|total_monto
      v_lineas := v_lineas || format('PIE|%s|%s',
        v_seq,
        to_char(v_total_monto, 'FM99999999990.00')
      );

    WHEN 'BPA' THEN
      -- Encabezado fixed-width (registro tipo 01)
      v_monto_fmt := lpad(
        replace(to_char(v_total_monto, 'FM99999999990.00'), '.', ''),
        14, '0'
      );
      v_lineas := ARRAY[
        '01'
        || rpad(v_ruc,              12, ' ')
        || rpad(v_numero_cuenta,    15, ' ')
        || rpad('',                 20, ' ')   -- cuenta credito vacia en encabezado
        || rpad(left(v_empresa_nombre, 40), 40, ' ')
        || v_monto_fmt
        || rpad(to_char(p_fecha_proceso,'YYYYMMDD') || lpad(v_seq::TEXT,9,'0'), 17, ' ')
      ] || v_lineas;
      -- Pie (registro tipo 03)
      v_lineas := v_lineas || (
        '03'
        || rpad(v_ruc,       12, ' ')
        || rpad('',          15, ' ')
        || rpad('',          20, ' ')
        || rpad('',          40, ' ')
        || v_monto_fmt
        || rpad(v_seq::TEXT, 17, ' ')
      );

    WHEN 'BG' THEN
      NULL;  -- CSV: sin encabezado/pie adicional (encabezado CSV ya insertado en primer loop)

    ELSE NULL;
  END CASE;

  RETURN array_to_string(v_lineas, E'\n');
END;
$$;

-- RPC: Procesar respuesta del banco (resultados del debito automatico)
-- Parsea el archivo de respuesta, actualiza estado de transferencias_bancarias
-- y retorna conteo de procesadas / rechazadas / pendientes.
CREATE OR REPLACE FUNCTION process_debit_response(
  p_lote_id     UUID,      -- ID de la cuenta bancaria origen del lote enviado
  p_respuesta   TEXT,      -- Contenido del archivo de respuesta del banco
  p_banco_codigo VARCHAR   -- 'BP' | 'BPA' | 'BG'
)
RETURNS TABLE (
  procesadas  INTEGER,
  rechazadas  INTEGER,
  pendientes  INTEGER
) LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_empresa_id    UUID;
  v_lineas        TEXT[];
  v_linea         TEXT;
  v_campos        TEXT[];
  v_seq           INTEGER;
  v_estado_banco  VARCHAR(20);
  v_codigo_rechazo TEXT;
  v_transferencia_id UUID;

  v_procesadas    INTEGER := 0;
  v_rechazadas    INTEGER := 0;
  v_pendientes    INTEGER := 0;
BEGIN
  -- Verificar acceso: la cuenta bancaria pertenece a la empresa del JWT
  SELECT cb.empresa_id INTO v_empresa_id
  FROM   cuentas_bancarias cb
  WHERE  cb.id = p_lote_id;

  IF v_empresa_id IS NULL OR v_empresa_id <> (SELECT private.get_empresa_id()) THEN
    RAISE EXCEPTION 'Acceso denegado o cuenta bancaria no encontrada';
  END IF;

  -- Dividir el texto en lineas, ignorar lineas vacias
  v_lineas := ARRAY(
    SELECT trim(ln)
    FROM   unnest(string_to_array(p_respuesta, E'\n')) AS ln
    WHERE  trim(ln) <> ''
  );

  FOREACH v_linea IN ARRAY v_lineas LOOP

    CASE p_banco_codigo

      -- ── BANCO PICHINCHA (BP) : pipe-delimited ─────────────────────────────
      -- Formato detalle: DTL|seq|cuenta_destino|nombre|monto|concepto|banco|estado|codigo_rechazo
      WHEN 'BP' THEN
        IF left(v_linea, 4) <> 'DTL|' THEN
          CONTINUE;  -- Saltar encabezado (HDR) y pie (PIE)
        END IF;
        v_campos := string_to_array(v_linea, '|');
        -- campos[2]=seq, campos[8]=estado, campos[9]=codigo_rechazo (opcional)
        IF array_length(v_campos, 1) < 8 THEN CONTINUE; END IF;
        v_seq           := v_campos[2]::INTEGER;
        v_estado_banco  := upper(trim(v_campos[8]));
        v_codigo_rechazo := CASE WHEN array_length(v_campos,1) >= 9
                                 THEN trim(v_campos[9]) ELSE NULL END;

      -- ── BANCO DEL PACIFICO (BPA) : fixed-width 120 chars ─────────────────
      -- Registro tipo '02' (detalle):
      --   pos 1-2: tipo, pos ???: secuencia (asumimos cols 121-127 como extension)
      -- Bancos reales extienden el formato con estado en posiciones adicionales;
      -- aqui usamos una convencion practica: estado en pos 121-130, rechazo 131-140
      WHEN 'BPA' THEN
        IF left(v_linea, 2) <> '02' THEN
          CONTINUE;  -- Solo registros de detalle
        END IF;
        IF length(v_linea) < 121 THEN CONTINUE; END IF;
        -- Secuencia: interpretamos los 6 chars del final del campo concepto (104-120)
        -- como texto libre; la secuencia viene en extension pos 121-126
        v_seq            := trim(substring(v_linea FROM 121 FOR 6))::INTEGER;
        v_estado_banco   := upper(trim(substring(v_linea FROM 127 FOR 10)));
        v_codigo_rechazo := CASE WHEN length(v_linea) >= 137
                                 THEN trim(substring(v_linea FROM 137 FOR 10))
                                 ELSE NULL END;

      -- ── BANCO GUAYAQUIL (BG) : CSV (coma) ────────────────────────────────
      -- Formato respuesta: secuencia,estado,codigo_rechazo,...
      WHEN 'BG' THEN
        v_campos := string_to_array(v_linea, ',');
        IF array_length(v_campos, 1) < 2 THEN CONTINUE; END IF;
        -- Saltar encabezado CSV
        IF lower(trim(v_campos[1])) = 'secuencia' THEN CONTINUE; END IF;
        v_seq            := trim(v_campos[1])::INTEGER;
        v_estado_banco   := upper(trim(v_campos[2]));
        v_codigo_rechazo := CASE WHEN array_length(v_campos,1) >= 3
                                 THEN trim(v_campos[3]) ELSE NULL END;

      ELSE
        RAISE EXCEPTION 'Banco no soportado: %', p_banco_codigo;
    END CASE;

    -- ── Buscar la transferencia por posicion en el lote (orden enviado) ──────
    -- Se recupera la transferencia numero v_seq segun el mismo ORDER BY usado en generate_debit_file
    SELECT tb.id INTO v_transferencia_id
    FROM   transferencias_bancarias tb
    WHERE  tb.cuenta_origen_id = p_lote_id
      AND  tb.empresa_id       = v_empresa_id
    ORDER  BY tb.fecha, tb.created_at
    LIMIT  1 OFFSET (v_seq - 1);

    IF v_transferencia_id IS NULL THEN
      CONTINUE;  -- Secuencia fuera de rango, ignorar
    END IF;

    -- ── Actualizar estado segun respuesta del banco ───────────────────────
    IF v_estado_banco IN ('PROCESADO', 'APROBADO', 'OK', 'EXITOSO') THEN
      UPDATE transferencias_bancarias
      SET    estado    = 'CONFIRMADA',
             metadata  = COALESCE(metadata, '{}'::JSONB)
                         || jsonb_build_object('banco_estado', v_estado_banco,
                                               'fecha_respuesta', CURRENT_TIMESTAMP)
      WHERE  id = v_transferencia_id;
      v_procesadas := v_procesadas + 1;

    ELSIF v_estado_banco IN ('RECHAZADO', 'DEVUELTO', 'ERROR', 'FALLIDO') THEN
      UPDATE transferencias_bancarias
      SET    estado    = 'RECHAZADA',
             metadata  = COALESCE(metadata, '{}'::JSONB)
                         || jsonb_build_object('banco_estado',    v_estado_banco,
                                               'codigo_rechazo',  v_codigo_rechazo,
                                               'fecha_respuesta', CURRENT_TIMESTAMP)
      WHERE  id = v_transferencia_id;
      v_rechazadas := v_rechazadas + 1;

    ELSE
      -- Estado desconocido o 'PENDIENTE' → dejar en PENDIENTE
      v_pendientes := v_pendientes + 1;
    END IF;

  END LOOP;

  RETURN QUERY SELECT v_procesadas, v_rechazadas, v_pendientes;
END;
$$;
```

---

## Integración con Datáfonos (Terminales POS Físicos Ecuador)

Integración con terminales de pago físicos para evitar doble digitación del monto y
permitir conciliación automática en cierre de caja.

```sql
-- TRANSACCIONES DATAFONO (POS fisico)
CREATE TABLE transacciones_datafono (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id),
  pos_venta_id    UUID REFERENCES pos_ventas(id),  -- Venta POS asociada
  terminal_id     VARCHAR(30) NOT NULL,             -- ID fisico del terminal
  monto           DECIMAL(14,2) NOT NULL,
  tipo            VARCHAR(15) NOT NULL,             -- VENTA, ANULACION
  referencia      VARCHAR(30),                      -- Nro referencia del terminal
  autorizacion    VARCHAR(20),                      -- Codigo autorizacion banco
  lote            VARCHAR(10),                      -- Nro de lote
  estado          VARCHAR(15) NOT NULL DEFAULT 'ENVIADA',
    -- ENVIADA, APROBADA, RECHAZADA, ANULADA
  respuesta       JSONB,                            -- Respuesta completa del terminal
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE transacciones_datafono ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON transacciones_datafono
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));
```

```
Flujo POS con datafono:
  1. Cajero selecciona forma de pago "Tarjeta" en POS
  2. PILAR envia monto al terminal via HTTP API local:
     - Datafast (Visa/MC): POST http://<terminal_ip>/api/sale {amount, reference}
     - Medianet (Discover/Diners): flujo similar
  3. Terminal muestra monto → cliente pasa/inserta tarjeta
  4. Terminal responde con: autorizacion, referencia, lote, estado
  5. Si APROBADA: se completa la venta POS automaticamente
  6. Si RECHAZADA: POS muestra error, cajero ofrece otra forma de pago
  7. Al cierre de caja: conciliacion lote terminal vs ventas registradas

Beneficios:
  - Elimina error humano al digitar monto en terminal
  - Conciliacion automatica terminal ↔ ventas POS
  - Auditoria completa de transacciones con tarjeta
```

---

## Pago por Código QR — G-PAG-04 (P2)

```
- Genera QR con datos de pago: {monto, referencia, beneficiario, ruc}
- Estandar: EMVCo QR for Payments (compatible con apps bancarias Ecuador)
- Flutter: paquete qr_flutter para renderizar codigo QR en pantalla
- Cliente escanea QR desde su app bancaria y confirma pago
- Confirmacion: webhook del banco o confirmacion manual del cajero
- Aplicable a: facturas, CxC, cobros POS, pagos de servicios
- Futuro: integracion directa con APIs de bancos para confirmacion automatica
```

---

## De Una — Banco del Pacifico (G-PAG-05, P2)

```
- Billetera digital del Banco del Pacifico (popular en costa ecuatoriana)
- API REST similar a PayPhone: enviar solicitud de pago → usuario confirma en app → webhook
- Config empresa: deuna_api_key, deuna_secret, deuna_webhook_url en config_pasarela
- Mismo patron adaptador que Kushki/Paymentez/PayPhone (Gateway Adapter)
- Edge Function: process-deuna-payment + webhook-deuna (verify_jwt: false)
- Prioridad: despues de PayPhone (menor base de usuarios fuera de la costa)
- Implementacion: agregar DEUNA como opcion en pasarelas_pago + config_pasarela
```

---

## Notas Ecuador

- **Moneda funcional**: USD (Ecuador dolarizado desde 2000). Todas las transacciones en USD.
- **Tasas de cambio**: para cuentas en moneda extranjera, sincronizar desde API del BCE
  (Banco Central del Ecuador) via Edge Function `sync-exchange-rates` (cron diario 7am).
- **Generacion de facturas electronicas SRI**: al confirmar pago online, llamar a
  `module_bus.facturacion.queue_sri_document()` si aplica.

---

## Referencias

- Patron adaptador generico: [`foundation/integraciones/pagos.md`](../../../../foundation/integraciones/pagos.md)
- Modulo pagos-online: [`modules/extensiones/pagos-online/module.md`](../module.md)
- Edge Functions: `process-payment`, `webhook-kushki`, `webhook-paymentez`
- Tesoreria (cuentas bancarias, cheques, conciliacion): `modules/core/tesoreria/module.md`
