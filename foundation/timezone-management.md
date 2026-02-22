# Manejo de Zonas Horarias en PILAR ERP

Guía completa de implementación para el manejo de zonas horarias en todas las capas del sistema. Para los conceptos base y la arquitectura general, ver [`precision-supabase.md`](./precision-supabase.md) (sección "Manejo de Zonas Horarias").

---

## 1. Resumen Ejecutivo

| Capa | Regla | Herramienta |
|------|-------|-------------|
| BD | `TIMESTAMPTZ` UTC siempre para momentos; `DATE` para fechas de documentos | PostgreSQL nativo |
| API / RPC | ISO 8601 UTC en respuestas (`TIMESTAMPTZ::text`) | `TIMESTAMPTZ` cast |
| Flutter | Convertir UTC a local solo al mostrar al usuario | `timezone` + `intl` |
| Documentos / Edge Fn | Usar fecha LOCAL del establecimiento para el documento | `DATE` sin hora |

---

## 2. Por qué `fecha_emision` es `DATE` y no `TIMESTAMP`

El sistema valida que la fecha del documento sea fecha local del emisor, no UTC — se espera `fechaEmision` en el formato `DD/MM/YYYY`, una fecha sin hora. Este diseño es intencional por tres razones:

1. **La fecha es LOCAL del establecimiento**, no UTC. El usuario ve el reloj de su establecimiento.
2. **El sistema rechaza documentos con fecha futura** respecto a la hora local del establecimiento emisor.
3. **El sistema rechaza documentos extemporáneos** con más de N días de diferencia respecto a la fecha actual (configurable por localización).

Almacenar `DATE` (sin hora) elimina la ambigüedad UTC vs local y simplifica toda la lógica de generación del XML.

```
Documento emitido a las 23:59 en zona UTC-5:
  fecha_emision = 2026-02-19  (fecha LOCAL — correcta para el documento)
  created_at    = 2026-02-20T04:59:00Z  (UTC — momento exacto)

Si se almacenara TIMESTAMP:
  Al convertir created_at a DATE UTC → 2026-02-20  → documento con fecha incorrecta
  El sistema rechazaría el documento como "fecha extemporanea"
```

La regla es: `fecha_emision` registra lo que el usuario vio en su pantalla. `created_at` registra el momento exacto en el tiempo.

---

## 3. Capa de Base de Datos (PostgreSQL)

### Reglas de columnas

| Tipo | Usar para |
|------|-----------|
| `DATE` | `fecha_emision`, `fecha_vencimiento`, `fecha_inicio_periodo`, cualquier "solo fecha" donde la hora no tiene significado |
| `TIMESTAMPTZ` | `created_at`, `updated_at`, `fecha_autorizacion`, `procesado_en`, cualquier momento exacto |
| `TIMESTAMP WITHOUT TIME ZONE` | **NUNCA usar** — ambiguo, sin zona, causa bugs silenciosos |

### Funciones SQL disponibles

Definidas en las migraciones de foundation y documentadas en `precision-supabase.md`:

```sql
-- Convierte un TIMESTAMPTZ UTC a la hora local del establecimiento
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

-- Retorna la fecha de hoy en la zona del establecimiento (para documentos con fecha de emisión)
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

Uso típico en una RPC de creación de documento:

```sql
-- Asignar fecha_emision automáticamente si no viene del cliente
NEW.fecha_emision := COALESCE(NEW.fecha_emision, get_local_date(NEW.establecimiento_id));
```

### Checklist SQL para PRs

Ejecutar antes de aprobar cualquier migración que agregue tablas nuevas:

```sql
-- 1. Verificar que no hay TIMESTAMP sin zona horaria
SELECT column_name, table_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND data_type = 'timestamp without time zone';
-- Resultado esperado: 0 filas

-- 2. Verificar que todos los establecimientos tienen zona_horaria
SELECT id, nombre FROM establecimientos WHERE zona_horaria IS NULL;
-- Resultado esperado: 0 filas

-- 3. Verificar que las zonas configuradas son válidas en PostgreSQL
SELECT e.nombre, e.zona_horaria,
       (SELECT name FROM pg_timezone_names WHERE name = e.zona_horaria) AS valida
FROM establecimientos e
WHERE NOT EXISTS (
  SELECT 1 FROM pg_timezone_names WHERE name = e.zona_horaria
);
-- Resultado esperado: 0 filas
```

---

## 4. Capa Flutter/Dart

### Inicialización (una vez en `main()`)

El paquete `timezone` requiere inicialización explícita antes de usar cualquier conversión. Hacerlo al arrancar la app:

```dart
// lib/main.dart
import 'package:timezone/data/latest.dart' as tz;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones(); // inicializa la base de datos IANA incluida en el paquete
  // ...
  runApp(const ProviderScope(child: PilarApp()));
}
```

> La función se llama `initializeTimeZones()` (sin `await` — es síncrona). Importar desde `timezone/data/latest.dart`, no desde `timezone/timezone.dart`.

### Extensión helper `DateTimeToLocalExt`

Ubicación: `lib/core/services/timezone_service.dart`

```dart
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

extension DateTimeToLocalExt on DateTime {
  /// Convierte un DateTime UTC al TZDateTime del establecimiento dado.
  /// El DateTime receptor DEBE estar en UTC (como viene de Brick/Supabase).
  tz.TZDateTime toEstablecimientoTime(String zonaHoraria) {
    final location = tz.getLocation(zonaHoraria);
    // TZDateTime.from() acepta un DateTime UTC y lo convierte a la zona dada
    return tz.TZDateTime.from(this, location);
  }

  /// Formatea para mostrar al usuario: "19/02/2026 23:59"
  String toLocalDisplay(String zonaHoraria) {
    final local = toEstablecimientoTime(zonaHoraria);
    return DateFormat('dd/MM/yyyy HH:mm').format(local);
  }

  /// Solo fecha (para mostrar fecha_emision): "19/02/2026"
  String toLocalDateDisplay(String zonaHoraria) {
    final local = toEstablecimientoTime(zonaHoraria);
    return DateFormat('dd/MM/yyyy').format(local);
  }

  /// Fecha larga para encabezados de reporte: "19 de febrero de 2026"
  String toLocalDateLong(String zonaHoraria) {
    final local = toEstablecimientoTime(zonaHoraria);
    return DateFormat('d \'de\' MMMM \'de\' yyyy').format(local);
  }
}
```

### Patrón en Brick: cómo deserializar TIMESTAMPTZ de Supabase

Supabase retorna timestamps como strings ISO 8601: `"2026-02-20T04:59:00+00:00"`. Brick los deserializa con `DateTime.parse()`, que produce un `DateTime` en UTC con `isUtc = true`. Este es el comportamiento correcto.

```dart
// lib/features/<modulo>/models/<documento>.dart

@ConnectOfflineFirstWithSupabase(
  supabaseConfig: SupabaseSerializable(tableName: '<tabla>'),
)
class Documento extends OfflineFirstWithSupabaseModel {
  final String id;

  // fecha_emision es DATE en PostgreSQL.
  // Supabase retorna: "2026-02-19" (string ISO date sin hora).
  // DateTime.parse("2026-02-19") produce DateTime(2026, 2, 19, 0, 0, 0) en UTC.
  // Para mostrar: usar .toLocalDateDisplay() o formatear como Date sin conversión de zona.
  // NUNCA convertir fecha_emision con toEstablecimientoTime() — ya es una fecha local.
  final DateTime fechaEmision;

  // created_at es TIMESTAMPTZ en PostgreSQL.
  // Supabase retorna: "2026-02-20T04:59:00+00:00"
  // DateTime.parse() lo produce correctamente como UTC (isUtc = true).
  // Para mostrar: createdAt.toLocalDisplay(establecimiento.zonaHoraria)
  final DateTime createdAt;

  // fecha_autorizacion es TIMESTAMPTZ — momento exacto retornado por el sistema externo.
  // Para mostrar: fechaAutorizacion?.toLocalDisplay(establecimiento.zonaHoraria)
  final DateTime? fechaAutorizacion;

  const Documento({
    required this.id,
    required this.fechaEmision,
    required this.createdAt,
    this.fechaAutorizacion,
  });
}
```

**Regla fundamental**: los `DateTime` en Brick siempre representan UTC. La conversión a hora local ocurre **solo** en la capa de presentación (widgets o proveedores de display). Nunca almacenar ni transmitir horas locales.

### Patrón en Providers (Riverpod)

```dart
// lib/core/providers/timezone_providers.dart
import 'package:timezone/timezone.dart' as tz;

/// Retorna la fecha de hoy en la zona horaria del establecimiento activo.
/// Usar para precargar fecha_emision en formularios de documentos.
final fechaLocalHoyProvider = Provider<DateTime>((ref) {
  final establecimiento = ref.watch(establecimientoActivoProvider);
  final location = tz.getLocation(establecimiento.zonaHoraria);
  final localNow = tz.TZDateTime.now(location);
  // Retornar solo la fecha (sin hora) como DateTime con componente de hora en cero
  return DateTime(localNow.year, localNow.month, localNow.day);
});

/// Verifica si una fecha está dentro del rango permitido para emisión de documentos.
/// El límite de días atrás es configurable por localización.
final esFechaEmisionValidaProvider = Provider.family<bool, DateTime>((ref, fecha) {
  final hoy = ref.watch(fechaLocalHoyProvider);
  final diferencia = hoy.difference(fecha).inDays;
  final limiteDias = ref.watch(limiteExtemporaneidadProvider); // configurable por localización
  return diferencia >= 0 && diferencia <= limiteDias;
});
```

### Widget helper `LocalDateTimeText`

Ubicación: `lib/core/widgets/local_datetime_text.dart`

```dart
import 'package:flutter/material.dart';
import 'package:pilar_erp/core/services/timezone_service.dart';

/// Muestra un DateTime UTC formateado en la zona horaria del establecimiento.
/// Usar en lugar de Text(dateTime.toString()) para cualquier timestamp visible al usuario.
class LocalDateTimeText extends StatelessWidget {
  const LocalDateTimeText({
    super.key,
    required this.utcDateTime,
    required this.zonaHoraria,
    this.soloFecha = false,
    this.style,
  });

  final DateTime utcDateTime;
  final String zonaHoraria;

  /// Si true, muestra solo "19/02/2026". Si false, muestra "19/02/2026 23:59".
  final bool soloFecha;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final text = soloFecha
        ? utcDateTime.toLocalDateDisplay(zonaHoraria)
        : utcDateTime.toLocalDisplay(zonaHoraria);
    return Text(text, style: style);
  }
}
```

### DatePicker timezone-aware para `fecha_emision`

Ubicación: `lib/core/widgets/fecha_emision_picker.dart`

Este picker limita la selección al rango válido para emisión de documentos, calculado en hora local del establecimiento. El número de días atrás permitidos es configurable por localización:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_datepicker/datepicker.dart';
import 'package:timezone/timezone.dart' as tz;

class FechaEmisionPicker extends ConsumerWidget {
  const FechaEmisionPicker({
    super.key,
    required this.onChanged,
    this.initialDate,
  });

  final ValueChanged<DateTime> onChanged;
  final DateTime? initialDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final establecimiento = ref.watch(establecimientoActivoProvider);
    final location = tz.getLocation(establecimiento.zonaHoraria);
    final localHoy = tz.TZDateTime.now(location);

    // maxDate: hoy en hora local (no puede ser fecha futura)
    final maxDate = DateTime(localHoy.year, localHoy.month, localHoy.day);
    // minDate: N días atrás (límite extemporáneo configurable por localización)
    final limiteDias = ref.watch(limiteExtemporaneidadProvider);
    final minDate = maxDate.subtract(Duration(days: limiteDias));

    return SfDateRangePicker(
      selectionMode: DateRangePickerSelectionMode.single,
      maxDate: maxDate,
      minDate: minDate,
      initialSelectedDate: initialDate ?? maxDate,
      monthFormat: 'MMMM',
      onSelectionChanged: (DateRangePickerSelectionChangedArgs args) {
        if (args.value is DateTime) {
          onChanged(args.value as DateTime);
        }
      },
    );
  }
}
```

---

## 5. Capa Edge Functions (Deno/TypeScript)

### Regla fundamental

Las Edge Functions que generan documentos **nunca convierten** `fecha_emision` — simplemente toman el string `DATE` que viene de la BD (`"2026-02-19"`) y lo reformatean al formato requerido (`"19/02/2026"`). No hay timezone involucrado porque `DATE` no tiene hora.

```typescript
// supabase/functions/generate-documento/index.ts

// ✅ CORRECTO: fecha_emision es DATE, no tiene timezone
// Supabase retorna el string: "2026-02-19"
function formatearFechaDocumento(fechaIso: string): string {
  const [year, month, day] = fechaIso.split('-');
  return `${day}/${month}/${year}`; // "19/02/2026"
}
// No hay new Date(), no hay conversión de zona, no hay ambigüedad.

// ✅ CORRECTO: fecha_autorizacion SÍ es TIMESTAMPTZ (retornada por el sistema externo en UTC)
// Mostrarla en hora local del establecimiento en el documento PDF
function formatearFechaAutorizacion(
  isoUtc: string,
  zonaHoraria: string
): string {
  return new Date(isoUtc).toLocaleString('es-EC', {
    timeZone: zonaHoraria,
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false,
  });
  // Ejemplo: "19/02/2026, 23:59:00"
}

// ❌ INCORRECTO: construir Date desde fecha_emision
// new Date("2026-02-19") produce medianoche UTC
// Si el servidor corre en UTC+0, toLocaleDateString da "19/02/2026" — parece correcto
// Pero si el servidor tiene otra zona, el resultado cambia silenciosamente
const fechaMal = new Date(documento.fecha_emision).toLocaleDateString(); // NO hacer esto
```

### Timestamps en paths de Storage

Los paths de Storage deben ser consistentes independientemente de la zona del establecimiento. Usar siempre UTC para construirlos:

```typescript
// ✅ CORRECTO: paths con UTC (sin ambigüedad entre establecimientos)
function buildStoragePath(empresaId: string, claveAcceso: string): string {
  const now = new Date();
  const year = now.getUTCFullYear();
  const month = String(now.getUTCMonth() + 1).padStart(2, '0');
  return `${empresaId}/${year}/${month}/${claveAcceso}.xml`;
  // Ejemplo: "uuid-empresa/2026/02/claveacceso49chars.xml"
}

// ❌ INCORRECTO: usar getMonth() sin UTC
const month = new Date().getMonth() + 1; // Depende de la zona del servidor Deno
```

### Validación de extemporaneidad en Edge Function

```typescript
// Validar que fecha_emision no sea futura ni extemporánea
// El límite de días atrás (limiteDias) es configurable por localización
// comparar en hora local del establecimiento
function validarFechaEmision(
  fechaEmisionStr: string, // "2026-02-19" — DATE de la BD
  zonaHoraria: string,     // zona IANA del establecimiento
  limiteDias: number       // configurable por localización (ej: 5)
): { valida: boolean; error?: string } {
  // Fecha del documento (sin hora — tratar como fecha local)
  const [year, month, day] = fechaEmisionStr.split('-').map(Number);
  const fechaDoc = new Date(year, month - 1, day); // fecha local sin zona

  // Fecha de hoy en la zona del establecimiento
  const ahora = new Date();
  const localHoy = new Intl.DateTimeFormat('en-CA', {
    timeZone: zonaHoraria,
    year: 'numeric', month: '2-digit', day: '2-digit',
  }).format(ahora); // "2026-02-19"
  const [hy, hm, hd] = localHoy.split('-').map(Number);
  const hoy = new Date(hy, hm - 1, hd);

  const diffDias = Math.floor((hoy.getTime() - fechaDoc.getTime()) / 86_400_000);

  if (diffDias < 0) return { valida: false, error: 'fecha_emision no puede ser futura' };
  if (diffDias > limiteDias) return { valida: false, error: `fecha_emision extemporanea (>${limiteDias} dias)` };
  return { valida: true };
}
```

---

## 6. Casos de Uso Críticos

### UC1: Documento emitido a las 23:59 en zona UTC-5

```
Escenario: usuario en zona UTC-5 emite un documento a las 23:59 del 19 de febrero de 2026

Hora local (UTC-5):    23:59:00 del 2026-02-19
Momento UTC:           04:59:00 del 2026-02-20

Lo que se almacena en la BD:
  fecha_emision = 2026-02-19  (DATE — lo que el usuario vio en su pantalla)
  created_at    = 2026-02-20T04:59:00Z  (TIMESTAMPTZ — momento exacto)

Documento generado:
  fechaEmision: 19/02/2026  ← correcto

Reporte de febrero 2026:
  SELECT * FROM <tabla_documentos>
  WHERE fecha_emision BETWEEN '2026-02-01' AND '2026-02-28'
  → el documento aparece en febrero  ✅

Si se filtrara por created_at::DATE:
  DATE('2026-02-20T04:59:00Z') = '2026-02-20'
  → el documento quedaría fuera del reporte de febrero  ❌
```

### UC2: Empresa con sucursales en diferentes zonas horarias

```
Escenario: empresa con 2 establecimientos en zonas distintas

Sucursal A:  zona_horaria = 'America/Guayaquil' (UTC-5)
Sucursal B:  zona_horaria = 'Pacific/Galapagos' (UTC-6)

A las 00:30 UTC del 2026-02-20:
  Sucursal A ve: 19:30 del 19/02  → fecha_emision = 2026-02-19
  Sucursal B ve: 18:30 del 19/02  → fecha_emision = 2026-02-19
  Ambos documentos tienen la misma fecha local ese día.

A las 05:30 UTC del 2026-02-20:
  Sucursal A ve: 00:30 del 20/02  → fecha_emision = 2026-02-20  (ya es mañana)
  Sucursal B ve: 23:30 del 19/02  → fecha_emision = 2026-02-19  (sigue siendo ayer)

  Las dos sucursales emiten con su fecha local correcta.
  Los reportes consolidan toda la empresa filtrando por fecha_emision DATE — sin problema.
```

### UC3: Cierre de período contable y pg_cron

Los crons de PostgreSQL ejecutan en UTC. Para tareas que deben correr después de medianoche local en todos los establecimientos, usar la hora UTC más tardía considerando todas las zonas configuradas:

```sql
-- Ejemplo: si los establecimientos más tardíos están en UTC-6, medianoche = 06:00 UTC
-- Para garantizar que todos ya cerraron su día, ejecutar a las 06:30 UTC

SELECT cron.schedule(
  'cierre-diario-documentos',
  '30 6 * * *',
  $$SELECT public.process_pending_document_queue();$$
);

-- Para reportes de "fin de mes" (el 1ro de cada mes a las 06:30 UTC)
SELECT cron.schedule(
  'cierre-mensual-reportes',
  '30 6 1 * *',
  $$SELECT public.generate_monthly_report_data();$$
);
```

---

## 7. Tests pgTAP para Zonas Horarias

Ubicación sugerida: `supabase/tests/database/test_timezone.sql`

> Los valores de zona horaria en este ejemplo usan zonas IANA estándar. Reemplazar con las zonas configuradas en el despliegue concreto.

```sql
BEGIN;
SELECT plan(5);

-- Setup: empresa y establecimientos de prueba
-- (zona_horaria: usar zonas IANA válidas del despliegue concreto)
INSERT INTO empresas (id, ruc, razon_social, estado)
VALUES ('00000000-0000-0000-0000-000000000001', '1234567890001', 'Test Corp', 'ACTIVO');

INSERT INTO establecimientos (id, empresa_id, codigo, nombre, zona_horaria)
VALUES
  ('00000000-0000-0000-0000-000000000002',
   '00000000-0000-0000-0000-000000000001',
   '001', 'Oficina Central', 'America/Guayaquil'),  -- UTC-5
  ('00000000-0000-0000-0000-000000000003',
   '00000000-0000-0000-0000-000000000001',
   '002', 'Sucursal Islas', 'Pacific/Galapagos');   -- UTC-6

-- TEST 1: to_local_time convierte UTC 04:59 → 23:59 en zona UTC-5
SELECT is(
  EXTRACT(HOUR FROM to_local_time(
    '2026-02-20T04:59:00Z'::TIMESTAMPTZ,
    '00000000-0000-0000-0000-000000000002'
  ))::INT,
  23,
  'UTC 04:59 debe ser 23:59 en establecimiento con zona UTC-5'
);

-- TEST 2: get_local_date retorna un valor no null para establecimiento válido
SELECT isnt(
  get_local_date('00000000-0000-0000-0000-000000000002'),
  NULL,
  'get_local_date retorna valor no null para establecimiento con zona configurada'
);

-- TEST 3: Documento emitido a las 23:59 en zona UTC-5 aparece en reporte del mes correcto
-- created_at es día siguiente en UTC, pero fecha_emision es el día local
-- (Reemplazar <tabla_documentos> con la tabla de documentos del módulo bajo prueba)
-- INSERT INTO <tabla_documentos> (id, empresa_id, establecimiento_id, fecha_emision, ...)
-- VALUES ('00000000-0000-0000-0000-000000000010', ..., '2026-02-19'::DATE, ...);

SELECT is(
  (SELECT COUNT(*)::INT FROM <tabla_documentos>
   WHERE empresa_id = '00000000-0000-0000-0000-000000000001'
     AND fecha_emision BETWEEN '2026-02-01'::DATE AND '2026-02-28'::DATE),
  1,
  'Documento emitido 23:59 en zona UTC-5 aparece en el reporte de febrero'
);

-- TEST 4: Pacific/Galapagos es zona válida en PostgreSQL
SELECT ok(
  (SELECT COUNT(*) > 0 FROM pg_timezone_names WHERE name = 'Pacific/Galapagos'),
  'Pacific/Galapagos es una zona horaria válida en PostgreSQL'
);

-- TEST 5: America/Guayaquil es zona válida en PostgreSQL
SELECT ok(
  (SELECT COUNT(*) > 0 FROM pg_timezone_names WHERE name = 'America/Guayaquil'),
  'America/Guayaquil es una zona horaria válida en PostgreSQL'
);

SELECT * FROM finish();
ROLLBACK;
```

---

## 8. Anti-Patrones a Evitar

### Flutter/Dart

```dart
// ❌ MAL: usar DateTime.now() para fecha_emision
// DateTime.now() retorna la hora del dispositivo del usuario,
// que puede estar en cualquier zona o tener el reloj incorrecto.
final fechaEmision = DateTime.now();

// ✅ BIEN: hora del establecimiento via timezone package
final location = tz.getLocation(establecimiento.zonaHoraria);
final localNow = tz.TZDateTime.now(location);
final fechaEmision = DateTime(localNow.year, localNow.month, localNow.day);
```

```dart
// ❌ MAL: mostrar un DateTime UTC directamente en la UI
Text(documento.createdAt.toString());
// Muestra "2026-02-20 04:59:00.000Z" — confuso para el usuario (no es su hora local)

// ✅ BIEN: usar el widget o la extensión para convertir
LocalDateTimeText(
  utcDateTime: documento.createdAt,
  zonaHoraria: establecimientoActivo.zonaHoraria,
);
// Muestra "19/02/2026 23:59"
```

```dart
// ❌ MAL: formatear fecha_emision con toEstablecimientoTime()
// fecha_emision ya es una fecha local; convertirla introduce error doble
final display = documento.fechaEmision.toEstablecimientoTime(zona); // ERROR: aplica conversión de zona a una fecha que ya es local

// ✅ BIEN: formatear fecha_emision directamente
final display = DateFormat('dd/MM/yyyy', 'es_EC').format(documento.fechaEmision);
// O con la extensión de solo fecha (que formatea sin conversión de zona):
// documento.fechaEmision.toLocalDateDisplay(zona)  ← también funciona si TZDateTime.from no desplaza una fecha sin hora
```

### TypeScript / Edge Functions

```typescript
// ❌ MAL: usar new Date() sin UTC para paths de Storage
const month = new Date().getMonth() + 1; // Zona del servidor Deno, no del establecimiento

// ✅ BIEN: siempre UTC para paths (consistencia entre establecimientos)
const month = new Date().getUTCMonth() + 1;
```

```typescript
// ❌ MAL: asumir que new Date("2026-02-19") es medianoche en la zona local
// En JavaScript, Date.parse("2026-02-19") → medianoche UTC (no local)
// Esto puede producir el día anterior en zonas UTC-X
const fecha = new Date("2026-02-19");
fecha.toLocaleDateString('es', { timeZone: 'America/Guayaquil' }); // puede dar "18/02/2026" ← incorrecto

// ✅ BIEN: tratar fecha_emision como string y reformatear sin Date
const [year, month, day] = "2026-02-19".split('-');
const fechaDocumento = `${day}/${month}/${year}`; // "19/02/2026" — siempre correcto
```

### SQL

```sql
-- ❌ MAL: filtrar por DATE(created_at) para reportes mensuales
-- created_at está en UTC; un documento emitido a las 23:59 en zona UTC-5
-- aparece con DATE = dia siguiente en UTC
WHERE DATE(created_at) BETWEEN '2026-02-01' AND '2026-02-28';

-- ✅ BIEN: filtrar siempre por fecha_emision (DATE local, sin ambigüedad)
WHERE fecha_emision BETWEEN '2026-02-01'::DATE AND '2026-02-28'::DATE;
```

```sql
-- ❌ MAL: usar TIMESTAMP WITHOUT TIME ZONE para cualquier momento
created_at TIMESTAMP NOT NULL DEFAULT NOW();
-- "NOW()" devuelve TIMESTAMPTZ; al castearlo a TIMESTAMP pierde la zona silenciosamente

-- ✅ BIEN: siempre TIMESTAMPTZ
created_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
```

---

## 9. Referencias

- [`precision-supabase.md`](./precision-supabase.md) — Sección "Manejo de Zonas Horarias": estrategia base, diagrama de capas, reglas para documentos, casos especiales
- [`pubspec-referencia.md`](./pubspec-referencia.md) — Paquetes `timezone: ^0.9.4` e `intl: ^0.19.0` con justificación
- Migraciones de foundation — Funciones `to_local_time()` y `get_local_date()`
