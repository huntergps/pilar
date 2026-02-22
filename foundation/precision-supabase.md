# Precisión Numérica y Supabase Best Practices


### Precision Numerica y Redondeo

El manejo correcto de decimales es **critico** para cumplimiento tributario. La moneda funcional por defecto es USD (configurable por empresa/sistema).

#### Reglas de Precision en PostgreSQL

```sql
-- REGLA: Usar DECIMAL (no FLOAT) para TODOS los montos
-- NUNCA usar DOUBLE PRECISION ni REAL para valores monetarios
-- Aplicar en todas las tablas: de foundation y de módulos

-- Montos generales (totales, subtotales, impuestos)
DECIMAL(14,2)   -- Hasta 999,999,999,999.99

-- Cantidades y precios unitarios (6 decimales para compatibilidad con documentos electrónicos)
DECIMAL(18,6)   -- Precision para cantidades fraccionarias

-- Tarifas de impuestos
DECIMAL(4,2)    -- Ej: 15.00, 5.00, 0.00

-- Porcentajes de retencion
DECIMAL(5,2)    -- Ej: 100.00, 30.00, 10.00
```

#### Funciones de Redondeo

```sql
-- Funcion de redondeo estandar para documentos financieros
-- Redondea a 2 decimales con ROUND_HALF_UP (redondeo bancario)
CREATE OR REPLACE FUNCTION financial_round(
  p_valor DECIMAL,
  p_decimales INTEGER DEFAULT 2
) RETURNS DECIMAL
LANGUAGE sql IMMUTABLE AS $$
  SELECT ROUND(p_valor, p_decimales);
$$;

-- REGLA DE ORO del redondeo en documentos fiscales:
-- 1. Calcular precio_total_sin_impuesto por linea SIN redondear intermedios
--    precio_total = (cantidad * precio_unitario) - descuento
-- 2. Calcular base_imponible por linea (sum de precios_total por tarifa)
-- 3. Calcular impuesto = ROUND(base_imponible * tarifa / 100, 2)
-- 4. Total = ROUND(sum(subtotales) + sum(impuestos), 2)
--
-- IMPORTANTE: El redondeo SOLO se aplica al FINAL de cada calculo,
-- NUNCA en valores intermedios. Esto evita errores de centavo.
```

#### Redondeo en Dart (Flutter)

```dart
// NUNCA usar double para montos. Usar Decimal package o int (centavos)
// Opcion 1: Usar paquete decimal
import 'package:decimal/decimal.dart';

final precio = Decimal.parse('10.50');
final cantidad = Decimal.parse('3.000000');
final subtotal = precio * cantidad; // 31.500000
final redondeado = subtotal.round(scale: 2); // 31.50

// Opcion 2: Trabajar en centavos (int)
final precioEnCentavos = 1050; // $10.50
final cantidadX1000 = 3000;   // 3.000
final subtotalCentavos = (precioEnCentavos * cantidadX1000) ~/ 1000;

// REGLA: Mostrar con exactly 2 decimales
final formatted = subtotal.toStringAsFixed(2); // "31.50"
```

#### Validacion de Centavo

```sql
-- Trigger para verificar que los totales cuadren (tolerancia 0.01)
-- Patrón aplicable a cualquier documento con líneas e impuestos
CREATE OR REPLACE FUNCTION validate_document_totals()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
  v_sum_detalles DECIMAL;
  v_sum_impuestos DECIMAL;
  v_calculated_total DECIMAL;
BEGIN
  -- Sumar detalles (adaptar nombre de tabla y columna al documento concreto)
  SELECT COALESCE(SUM(subtotal_sin_impuesto), 0) INTO v_sum_detalles
  FROM <tabla_lineas> WHERE documento_id = NEW.id;

  -- Sumar impuestos totales (solo a nivel documento, no por línea)
  SELECT COALESCE(SUM(valor), 0) INTO v_sum_impuestos
  FROM <tabla_impuestos> WHERE documento_id = NEW.id AND linea_id IS NULL;

  v_calculated_total := v_sum_detalles + v_sum_impuestos;

  -- Verificar que cuadre (tolerancia de 1 centavo)
  IF ABS(NEW.importe_total - v_calculated_total) > 0.01 THEN
    RAISE EXCEPTION 'Total del documento no cuadra: esperado %, registrado %',
      v_calculated_total, NEW.importe_total;
  END IF;

  RETURN NEW;
END;
$$;
```

### Manejo de Zonas Horarias

PILAR soporta empresas con sucursales en diferentes zonas horarias (cada establecimiento configura su propia zona horaria).

#### Estrategia de Zonas Horarias

```
REGLA FUNDAMENTAL:
  - PostgreSQL almacena SIEMPRE en UTC (TIMESTAMPTZ)
  - La zona horaria se configura POR ESTABLECIMIENTO (sucursal)
  - La conversion a hora local se hace en el FRONTEND (Flutter)
  - Los documentos fiscales usan la hora del ESTABLECIMIENTO emisor

┌──────────────────────────────────────────────────────┐
│  FRONTEND (Flutter)                                   │
│  - Muestra fechas/horas en zona del establecimiento  │
│  - Usa timezone package para conversiones            │
│  - Envia a backend SIEMPRE en UTC                    │
└──────────────────────┬───────────────────────────────┘
                       │ UTC
┌──────────────────────┴───────────────────────────────┐
│  POSTGRESQL (Supabase)                                │
│  - Almacena SIEMPRE como TIMESTAMPTZ (UTC)           │
│  - Funciones de conversion para reportes             │
│  - Edge Functions convierten para XML de documentos electrónicos │
└──────────────────────────────────────────────────────┘
```

#### Configuracion por Establecimiento

```sql
-- Agregar zona horaria al establecimiento
ALTER TABLE establecimientos ADD COLUMN
  zona_horaria VARCHAR(50) DEFAULT 'UTC';  -- Configurable por empresa/región

-- La zona horaria por defecto es UTC; cada despliegue la configura según su región.
-- Ejemplos de zonas IANA válidas: 'America/New_York', 'Europe/Madrid', 'America/Guayaquil'
```

#### Funciones de Conversion

```sql
-- Convertir UTC a hora local del establecimiento
CREATE OR REPLACE FUNCTION to_local_time(
  p_utc_timestamp TIMESTAMPTZ,
  p_establecimiento_id UUID
) RETURNS TIMESTAMP
LANGUAGE sql STABLE AS $$
  SELECT p_utc_timestamp AT TIME ZONE (
    SELECT COALESCE(zona_horaria, 'UTC')
    FROM establecimientos WHERE id = p_establecimiento_id
  );
$$;

-- Obtener fecha local del establecimiento (para documentos de facturación)
-- IMPORTANTE: La fecha del documento es dd/mm/aaaa en hora LOCAL del establecimiento
CREATE OR REPLACE FUNCTION get_local_date(
  p_establecimiento_id UUID
) RETURNS DATE
LANGUAGE sql STABLE AS $$
  SELECT (now() AT TIME ZONE (
    SELECT COALESCE(zona_horaria, 'UTC')
    FROM establecimientos WHERE id = p_establecimiento_id
  ))::DATE;
$$;
```

#### Implementacion en Flutter (Dart)

```dart
// Paquete: timezone (para conversiones)
import 'package:timezone/timezone.dart' as tz;

// Inicializar zonas horarias al arrancar
await tz.initializeTimeZones();

// Obtener zona del establecimiento actual
final zonaStr = establecimiento.zonaHoraria ?? 'UTC';
final location = tz.getLocation(zonaStr);

// Convertir UTC a local para mostrar al usuario
final utcTime = DateTime.parse(registro.createdAt); // viene de Supabase
final localTime = tz.TZDateTime.from(utcTime, location);

// Formatear para UI
final formatted = DateFormat('dd/MM/yyyy HH:mm').format(localTime);

// Formatear para documentos fiscales (solo fecha, formato dd/mm/aaaa)
final docDate = DateFormat('dd/MM/yyyy').format(localTime);
```

#### Reglas para Documentos de Facturación

```
1. FECHA DE EMISION
   - Debe ser la fecha LOCAL del establecimiento emisor
   - Formato: dd/mm/aaaa (no incluye hora)
   - El sistema de facturación valida que la fecha del documento sea fecha
     local del emisor, no UTC (no puede ser fecha futura ni extemporanea)

2. FECHA DE AUTORIZACION
   - La retorna el sistema de facturación electrónica en UTC; convertir a local para mostrar
   - Se almacena como TIMESTAMPTZ (UTC) en la BD

3. REPORTES Y PERIODOS FISCALES
   - Los reportes periódicos agrupan por MES del periodo fiscal (hora local)
   - Filtros de fecha en reportes: convertir rango a UTC antes de consultar

4. CIERRE DE PERIODO
   - El cierre mensual se basa en la fecha LOCAL del establecimiento
   - Un documento emitido a las 23:30 en la zona local pertenece a ese mes
     aunque en UTC ya sea el dia siguiente
```

#### Casos Especiales

```
EMPRESA CON SUCURSALES EN DIFERENTES ZONAS HORARIAS:
  - Establecimiento A (zona_horaria = 'America/New_York', UTC-5/-4)
  - Establecimiento B (zona_horaria = 'Europe/Madrid', UTC+1/+2)
  - Una factura emitida a las 18:00 en la zona B puede ser otra fecha en UTC
  - Cada establecimiento emite con su hora local
  - Los reportes consolidan toda la empresa usando fecha_emision (DATE local)

CAMBIO DE HORARIO (DST):
  - Algunos paises tienen horario de verano (DST); TIMESTAMPTZ maneja automaticamente
  - El paquete 'timezone' de Dart tiene la base de datos IANA completa
  - Para zonas sin DST (offset fijo), el comportamiento es mas simple
```

---


---


PILAR sigue las mejores practicas oficiales de Supabase para seguridad y rendimiento. Estas reglas son **obligatorias** en todo el proyecto.

### Row Level Security (CRITICAL)

```sql
-- ============================================
-- PATRON RLS ESTANDAR PARA PILAR ERP
-- Aplicar en TODAS las tablas del schema public
-- ============================================

-- 1. SIEMPRE habilitar RLS
ALTER TABLE <tabla> ENABLE ROW LEVEL SECURITY;

-- 2. SIEMPRE usar (SELECT ...) para funciones auth (94.97% mejora rendimiento)
-- 3. SIEMPRE especificar TO authenticated (99.78% mejora)
-- 4. SIEMPRE usar FOR ALL (o FOR SELECT/INSERT/UPDATE/DELETE segun caso)
CREATE POLICY "tenant_isolation" ON <tabla>
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT (auth.jwt() -> 'app_metadata' ->> 'empresa_id')::uuid))
  WITH CHECK (empresa_id = (SELECT (auth.jwt() -> 'app_metadata' ->> 'empresa_id')::uuid));

-- 5. SIEMPRE crear indices en columnas usadas por RLS (99.94% mejora)
CREATE INDEX idx_<tabla>_empresa_id ON <tabla>(empresa_id);
```

#### Helper Function para Multi-Tenancy (SECURITY DEFINER)

```sql
-- Funcion helper que extrae empresa_id del JWT (evalua UNA vez)
-- 99.993% mejora vs joins en cada policy
CREATE OR REPLACE FUNCTION private.get_empresa_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT (auth.jwt() -> 'app_metadata' ->> 'empresa_id')::uuid;
$$;

-- Uso simplificado en policies:
CREATE POLICY "tenant_isolation" ON <tabla>
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()))
  WITH CHECK (empresa_id = (SELECT private.get_empresa_id()));
```

#### Policy RESTRICTIVE para Operaciones Sensibles

```sql
-- Requiere MFA para operaciones criticas (firma certificados, eliminar datos)
CREATE POLICY "require_mfa_for_sensitive"
  ON certificados_digitales
  AS RESTRICTIVE
  FOR ALL TO authenticated
  USING ((SELECT auth.jwt()->>'aal') = 'aal2');
```

### Database Security (HIGH)

```sql
-- MIGRACIONES VERSIONADAS (obligatorio)
-- supabase/migrations/YYYYMMDDHHMMSS_descripcion.sql
BEGIN;
  CREATE TABLE public.nueva_tabla (...);
  ALTER TABLE public.nueva_tabla ENABLE ROW LEVEL SECURITY;
  CREATE POLICY "..." ON public.nueva_tabla ...;
  CREATE INDEX idx_... ON public.nueva_tabla(...);
COMMIT;

-- SCHEMA PRIVADO para datos internos (no accesible via API)
CREATE SCHEMA IF NOT EXISTS private;
CREATE TABLE private.audit_logs (...);       -- Logs de auditoria
CREATE TABLE private.system_config (...);    -- Configuracion interna
CREATE TABLE private.encryption_keys (...);  -- Claves de encriptacion

-- TRIGGERS con SECURITY DEFINER + search_path explicito
CREATE OR REPLACE FUNCTION handle_new_<entidad>()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Lógica de negocio del trigger (ej: generar registros relacionados)
  PERFORM <funcion_de_negocio>(...);
  RETURN NEW;
END;
$$;

-- VIEWS con SECURITY INVOKER (respeta RLS del usuario)
CREATE VIEW public.<nombre_vista>
WITH (security_invoker = on)
AS
SELECT fecha, count(*), sum(importe_total)
FROM <tabla>
GROUP BY fecha;

-- FOREIGN KEYS con CASCADE apropiado
CREATE TABLE <tabla_lineas> (
  documento_id UUID NOT NULL REFERENCES <tabla_documentos>(id) ON DELETE CASCADE,
  producto_id  UUID REFERENCES <tabla_productos>(id) ON DELETE SET NULL
);
```

### Authentication & API Security (HIGH)

```
REGLAS DE AUTENTICACION:
  - NUNCA usar user_metadata para autorizacion (el usuario puede modificarla)
  - SIEMPRE usar app_metadata para roles y permisos (solo el server puede modificar)
  - SIEMPRE validar JWT claims antes de autorizar operaciones
  - service_role_key SOLO en Edge Functions (NUNCA en Flutter)

REGLAS DE API:
  - SIEMPRE filtrar queries aunque tengas RLS (defense in depth)
  - NUNCA exponer service_role_key al cliente
  - SIEMPRE usar el anon_key en supabase_flutter
  - SIEMPRE filtrar por empresa_id en el cliente tambien

Ejemplo Flutter (defense in depth):
  // Aunque RLS filtra, siempre filtrar explicitamente
  final registros = await supabase
    .from('<tabla>')
    .select('*')
    .eq('empresa_id', empresaId)  // Filtro explicito
    .eq('estado', '<estado>');
```

### Storage Security (MEDIUM-HIGH)

```sql
-- RLS en storage.objects (OBLIGATORIO para cada bucket)
CREATE POLICY "empresa_can_access_own_files"
ON storage.objects
FOR ALL TO authenticated
USING (
  bucket_id IN ('<bucket_1>', '<bucket_2>')   -- adaptar a los buckets del módulo
  AND (storage.foldername(name))[1] = (SELECT private.get_empresa_id()::text)
)
WITH CHECK (
  bucket_id IN ('<bucket_1>', '<bucket_2>')
  AND (storage.foldername(name))[1] = (SELECT private.get_empresa_id()::text)
);

-- Buckets sensibles (claves, certificados): SOLO acceso server-side (Edge Functions)
-- NO crear policy pública para estos buckets — acceder via service_role en Edge Functions
```

```
Estructura de carpetas en Storage (patrón obligatorio):
  <bucket>/{empresa_id}/<año>/<mes>/<nombre_archivo>.<ext>
  <bucket_privado>/{empresa_id}/<archivo_sensible>  (SOLO server-side)
  assets/{empresa_id}/logo.png

Configuracion de buckets:
  Buckets de documentos: private, allowedMimeTypes según lo que almacena el módulo
  Buckets sensibles:     private, tamaño pequeño (max 50KB), NO RLS public (solo service_role)
  assets:                private, max 5MB, allowedMimeTypes: ['image/*']
```

### Realtime Security (MEDIUM)

```sql
-- Habilitar Realtime SOLO en tablas con RLS activo
-- Las policies de RLS aplican automaticamente a Realtime
-- Agregar aqui las tablas del modulo que requieran sincronizacion en tiempo real
-- ALTER PUBLICATION supabase_realtime ADD TABLE <nombre_tabla>;

-- Usar canales privados para datos sensibles
-- En Flutter:
-- final channel = supabase.channel('private-empresa-$empresaId',
--   opts: RealtimeChannelConfig(private: true));
```

```dart
// Flutter: SIEMPRE limpiar suscripciones al desmontar
@override
void dispose() {
  _facturaSubscription?.cancel();
  supabase.removeChannel(_channel);
  super.dispose();
}
```

### Edge Functions Security (MEDIUM)

```typescript
// REGLAS para Edge Functions:
// 1. verify_jwt: true en TODAS (excepto webhooks)
// 2. CORS con dominio especifico (no wildcard *)
// 3. Secretos via Deno.env.get() (supabase secrets set)
// 4. SIEMPRE validar JWT y empresa_id
// 5. service_role SOLO cuando sea estrictamente necesario

const corsHeaders = {
  'Access-Control-Allow-Origin': 'https://pilar-erp.pages.dev', // Dominio especifico
  'Access-Control-Allow-Headers': 'authorization, x-client-info, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

// Secretos NUNCA hardcodeados
const kushkiApiKey = Deno.env.get('PAYMENT_GATEWAY_KEY');
const certPassword = Deno.env.get('SIGNING_CERT_PASSWORD');
const resendApiKey = Deno.env.get('RESEND_API_KEY');
```

### Testing con pgTAP (MEDIUM)

```sql
-- Test RLS para multi-tenancy (patrón genérico — aplicar a cada tabla con RLS)
-- supabase/tests/database/rls_<tabla>.test.sql
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(3);

-- Setup: crear 2 empresas con registros de prueba
INSERT INTO auth.users (id, raw_app_meta_data) VALUES
  ('aaa...', '{"empresa_id": "empresa-1-uuid"}'),
  ('bbb...', '{"empresa_id": "empresa-2-uuid"}');

-- Test: empresa 1 NO ve registros de empresa 2
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = 'aaa...';
SET LOCAL request.jwt.claims = '{"app_metadata": {"empresa_id": "empresa-1-uuid"}}';

SELECT results_eq(
  'SELECT count(*) FROM <tabla> WHERE empresa_id = ''empresa-2-uuid''',
  ARRAY[0::bigint],
  'Empresa 1 no debe ver registros de empresa 2'
);

-- Test: empresa 1 SI ve sus propios registros
SELECT results_ne(
  'SELECT count(*) FROM <tabla>',
  ARRAY[0::bigint],
  'Empresa 1 debe ver sus propios registros'
);

SELECT * FROM finish();
ROLLBACK;
```

### Checklist Supabase Pre-Deploy

```
OBLIGATORIO antes de cada deploy:

RLS:
  [ ] RLS habilitado en TODAS las tablas del schema public
  [ ] Funciones auth envueltas con (SELECT ...)
  [ ] Indices en columnas usadas por RLS (empresa_id, user_id)
  [ ] Policies con TO authenticated
  [ ] Tests pgTAP para policies criticas

Seguridad:
  [ ] service_role NUNCA en cliente (solo Edge Functions)
  [ ] app_metadata para autorizacion (no user_metadata)
  [ ] JWT validado en Edge Functions
  [ ] CORS con dominio especifico
  [ ] Secretos en Deno.env.get() (no hardcodeados)

Storage:
  [ ] RLS en storage.objects para cada bucket
  [ ] Certificados .p12 solo accesibles via service_role
  [ ] Signed URLs para archivos privados

Realtime:
  [ ] Solo tablas con RLS en supabase_realtime
  [ ] Canales privados para datos sensibles
  [ ] Suscripciones limpiadas al desmontar widgets

Base de Datos:
  [ ] Migraciones versionadas para TODOS los cambios
  [ ] Schema private para datos internos
  [ ] Triggers con SECURITY DEFINER + search_path
  [ ] Views con SECURITY INVOKER
  [ ] Foreign keys con CASCADE apropiado
  [ ] Ejecutar Security Advisor (get_advisors)
```

---

## Multi-moneda

PILAR soporta múltiples monedas en cuentas bancarias (campo `moneda_id` en `cuentas_bancarias`, `cheques`, `transferencias_bancarias`). La **moneda funcional por defecto es USD** (configurable por empresa/sistema).

**Reglas:**
- Todos los asientos contables son en la moneda funcional de la empresa
- Los documentos fiscales emitidos se expresan en la moneda funcional
- Las cuentas bancarias en otras monedas se reexpresan a la moneda funcional al cierre del período usando la tasa de cambio de `tasas_cambio`
- La tabla `monedas` tiene el campo `es_funcional BOOLEAN DEFAULT false` — la moneda funcional configurada tiene `es_funcional = true`

```sql
-- Moneda funcional del sistema
UPDATE monedas SET es_funcional = true WHERE codigo_iso = 'USD';
```

Para operaciones en moneda extranjera, usar la RPC:
```sql
SELECT convert_to_functional_currency(
  p_monto       := 1000.00,
  p_moneda_id   := (SELECT id FROM monedas WHERE codigo_iso = 'COP'),
  p_fecha       := CURRENT_DATE
) -- retorna el equivalente en USD
```

---

