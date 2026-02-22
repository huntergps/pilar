# Zonas Horarias Ecuador

Documentación específica de zonas horarias para despliegues PILAR ERP en Ecuador. Para la estrategia genérica UTC-first, anti-patrones y guía de implementación completa ver [`foundation/timezone-management.md`](../../../foundation/timezone-management.md).

---

## Zonas Horarias de Ecuador

```
America/Guayaquil  →  UTC-5  (continental: Costa, Sierra, Oriente — incluye Quito, Guayaquil, Cuenca)
Pacific/Galapagos  →  UTC-6  (Islas Galápagos)
```

Ecuador **no tiene DST** (Daylight Saving Time). Los offsets son fijos durante todo el año.

---

## Configuración por Defecto para Ecuador

Al crear establecimientos en un despliegue Ecuador, usar `America/Guayaquil` como valor por defecto para establecimientos continentales:

```sql
-- Valor por defecto para despliegues Ecuador
ALTER TABLE establecimientos ALTER COLUMN zona_horaria SET DEFAULT 'America/Guayaquil';

-- Establecimientos continentales (Costa, Sierra, Oriente)
UPDATE establecimientos SET zona_horaria = 'America/Guayaquil'
WHERE zona_horaria IS NULL AND -- criterio: establecimiento en territorio continental
  empresa_id = (SELECT private.get_empresa_id());

-- Establecimientos en Galápagos
UPDATE establecimientos SET zona_horaria = 'Pacific/Galapagos'
WHERE -- criterio: establecimiento en Galápagos
  empresa_id = (SELECT private.get_empresa_id());
```

---

## Casos de Uso Ecuador

### UC-EC1: Empresa con sucursales en Guayaquil y Galápagos

```
Escenario: empresa con 2 establecimientos en zonas distintas

Sucursal Guayaquil:  zona_horaria = 'America/Guayaquil' (UTC-5)
Sucursal Galápagos:  zona_horaria = 'Pacific/Galapagos' (UTC-6)

A las 00:30 UTC del 2026-02-20:
  Guayaquil ve: 19:30 del 19/02  → fecha_emision = 2026-02-19
  Galápagos ve: 18:30 del 19/02  → fecha_emision = 2026-02-19
  Ambas facturas tienen la misma fecha local ese día.

A las 05:30 UTC del 2026-02-20:
  Guayaquil ve: 00:30 del 20/02  → fecha_emision = 2026-02-20  (ya es mañana)
  Galápagos ve: 23:30 del 19/02  → fecha_emision = 2026-02-19  (sigue siendo ayer)

  Las dos sucursales emiten con su fecha local correcta.
  El ATS consolida toda la empresa filtrando por fecha_emision DATE — sin problema.
```

### UC-EC2: Cierre de período para pg_cron con zonas Ecuador

Los crons de PostgreSQL ejecutan en UTC. Para garantizar que ambas zonas Ecuador ya cerraron su día:

```sql
-- Medianoche en Guayaquil (UTC-5) = 05:00 UTC
-- Medianoche en Galápagos (UTC-6) = 06:00 UTC

-- Para garantizar que ambas zonas ya cerraron su día, ejecutar a las 06:30 UTC
-- (00:30 Galápagos, 01:30 Guayaquil — ambas en el día correcto)
SELECT cron.schedule(
  'cierre-diario-sri',
  '30 6 * * *',
  $$SELECT public.process_pending_sri_queue();$$
);

-- Para reportes de "fin de mes" (el 1ro de cada mes a las 06:30 UTC)
SELECT cron.schedule(
  'cierre-mensual-ats',
  '30 6 1 * *',
  $$SELECT public.generate_monthly_ats_data();$$
);
```

---

## Tests pgTAP Ecuador

Complementan los tests genéricos de `foundation/timezone-management.md` con validaciones específicas Ecuador:

```sql
BEGIN;
SELECT plan(4);

-- Setup Ecuador
INSERT INTO empresas (id, ruc, razon_social, estado)
VALUES ('ec000000-0000-0000-0000-000000000001', '1234567890001', 'Test Ecuador Corp', 'ACTIVO');

INSERT INTO establecimientos (id, empresa_id, codigo, nombre, zona_horaria)
VALUES
  ('ec000000-0000-0000-0000-000000000002',
   'ec000000-0000-0000-0000-000000000001',
   '001', 'Guayaquil', 'America/Guayaquil'),
  ('ec000000-0000-0000-0000-000000000003',
   'ec000000-0000-0000-0000-000000000001',
   '002', 'Galápagos', 'Pacific/Galapagos');

-- TEST 1: UTC 04:59 → 23:59 en Guayaquil (UTC-5)
SELECT is(
  EXTRACT(HOUR FROM to_local_time(
    '2026-02-20T04:59:00Z'::TIMESTAMPTZ,
    'ec000000-0000-0000-0000-000000000002'
  ))::INT,
  23,
  'UTC 04:59 debe ser 23:59 en Guayaquil (UTC-5)'
);

-- TEST 2: UTC 04:59 → 22:59 en Galápagos (UTC-6)
SELECT is(
  EXTRACT(HOUR FROM to_local_time(
    '2026-02-20T04:59:00Z'::TIMESTAMPTZ,
    'ec000000-0000-0000-0000-000000000003'
  ))::INT,
  22,
  'UTC 04:59 debe ser 22:59 en Galápagos (UTC-6)'
);

-- TEST 3: Pacific/Galapagos es zona válida en PostgreSQL
SELECT ok(
  (SELECT COUNT(*) > 0 FROM pg_timezone_names WHERE name = 'Pacific/Galapagos'),
  'Pacific/Galapagos es una zona horaria válida en PostgreSQL'
);

-- TEST 4: America/Guayaquil es zona válida en PostgreSQL
SELECT ok(
  (SELECT COUNT(*) > 0 FROM pg_timezone_names WHERE name = 'America/Guayaquil'),
  'America/Guayaquil es una zona horaria válida en PostgreSQL'
);

SELECT * FROM finish();
ROLLBACK;
```

---

## Validación SRI — Fecha de Emisión

El SRI Ecuador valida que los documentos electrónicos cumplan:

1. **No fecha futura**: `fecha_emision` no puede ser posterior a la fecha local del establecimiento emisor.
2. **No extemporánea**: `fecha_emision` no puede tener más de 5 días de diferencia respecto a la fecha local actual.
3. **Formato**: `DD/MM/YYYY` en el XML del documento electrónico.

Para la implementación de esta validación en Edge Functions, ver `modules/extensiones/facturacion_ec/`.

---

## Referencias

- [`foundation/timezone-management.md`](../../../foundation/timezone-management.md) — Estrategia UTC-first genérica, implementación Flutter/Dart, SQL, Edge Functions, anti-patrones
- [`modules/extensiones/facturacion_ec/`](../../extensiones/facturacion_ec/) — Módulo SRI Ecuador: firma XAdES-BES, SOAP, validaciones SRI
- [`modules/extensiones/tributacion_ec/`](../../extensiones/tributacion_ec/) — ATS, declaraciones 103/104
