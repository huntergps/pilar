# ADR-001: Uso de brick_offline_first_with_supabase para Sincronizacion de Datos

**Estado**: Aceptado
**Fecha**: 2026-02
**Autores**: Arquitecto principal
**Tags**: datos, offline, sincronizacion, flutter, supabase

---

## Contexto

PILAR debe operar en lugares, donde la conectividad a internet es intermitente en zonas fuera de las ciudades principales, y en sectores como manufactura o logistica donde el acceso puede cortarse por horas. Al mismo tiempo, la aplicacion es multi-plataforma (Web, iOS, Android, Windows, macOS, Linux) y requiere consistencia de datos entre dispositivos via PostgreSQL (Supabase).

Los requerimientos en tension son:
- Los usuarios deben poder seguir trabajando (crear registros, registrar movimientos) sin conexion
- Los datos deben sincronizarse automaticamente al recuperar la conectividad
- Los conflictos de concurrencia (dos usuarios editando el mismo registro offline) deben resolverse de forma predecible
- El backend es Supabase (PostgreSQL), no Firebase ni otro BaaS

---

## Decision

Se adopta **`brick_offline_first_with_supabase`** como la capa de datos de PILAR.

Los widgets y providers Riverpod **leen exclusivamente de SQLite local** via `BrickDataProvider<T>`. Nunca hacen llamadas directas al cliente Supabase. El package maneja automaticamente la sincronizacion bidireccional y la resolucion de conflictos.

Los modelos Dart se decoran con `@ConnectOfflineFirstWithSupabase`:

```dart
@ConnectOfflineFirstWithSupabase(
  supabaseConfig: SupabaseSerializableField(tableName: '<tabla>'),
)
class MiModelo extends OfflineFirstWithSupabaseModel {
  final String empresaId;
  final int version; // bloqueo optimista para documentos criticos
  // ...
}
```

### Estrategias de Resolucion de Conflictos por Tipo de Dato

| Tipo de Dato | Estrategia | Razon |
|--------------|-----------|-------|
| Documentos criticos (requieren integridad absoluta) | Bloqueo optimista con campo `version` | Integridad absoluta, sin merge parcial |
| Maestros (entidades frecuentemente editadas) | Last Write Wins (LWW) + merge campos no conflictivos | Cambios raramente simultaneos |
| Transacciones (registros de auditoria) | Append-only (nunca modificar, solo revertir) | Auditoria e inmutabilidad |
| Cantidades agregadas (inventario, contadores) | Suma-delta (no guardar el total, guardar el cambio) | Evita conflictos en cantidades |

### Cola de Sincronizacion con Prioridades

```
Documentos criticos (prioridad 1) — documentos que requieren integridad absoluta
Transacciones       (prioridad 2) — transacciones financieras y operacionales
Registros           (prioridad 3) — registros de operaciones secundarias
Maestros            (prioridad 4) — entidades de catalogo
Configuracion       (prioridad 5) — parametros, preferencias UI
```

---

## Alternativas Rechazadas

### 1. Drift (antes moor) + llamadas directas a Supabase

- Drift es un ORM SQLite excelente, pero requiere implementar manualmente toda la capa de sincronizacion
- La logica de conflictos, colas de sync, deteccion de cambios remotos seria codigo de produccion critico a desarrollar desde cero
- **Rechazado por**: costo de implementacion alto, no es el core business de PILAR

### 2. Hive / Isar (NoSQL local)

- No tienen esquema relacional, lo que complica las queries con multiples condiciones y joins
- La sincronizacion con PostgreSQL (SQL) requiere mapeo ad-hoc
- **Rechazado por**: impedancia de modelo de datos (NoSQL local vs SQL remoto)

### 3. Llamadas directas a Supabase desde widgets (sin cache local)

- Dependencia total de la red para cualquier operacion
- Inaceptable para el caso de uso Ecuador (conectividad intermitente)
- **Rechazado por**: requerimiento funcional de operacion offline

### 4. Firebase Firestore (offline-first nativo)

- Excelente offline-first, pero NoSQL (documentos, no filas relacionales)
- La complejidad del modelo de negocio (compliance fiscal, integridad referencial entre documentos) requiere un modelo relacional con transacciones ACID y RLS por fila
- Ver ADR-005 para la decision Supabase vs Firebase mas ampliamente
- **Rechazado por**: modelo de datos incompatible con requisitos fiscales

---

## Consecuencias

### Positivas

- La sincronizacion offline-to-online es manejada por el package, no por codigo propio
- Supabase Realtime actualiza SQLite local cuando llegan cambios remotos (reactivo)
- Los widgets siempre leen datos locales — sin spinners de carga en operaciones comunes
- El patron es consistente en toda la app: cualquier developer sabe donde buscar los datos

### Negativas / Restricciones

- El codigo generado por `build_runner` (adapters, db/) **no debe modificarse manualmente**; se regenera con `flutter pub run build_runner build --delete-conflicting-outputs`
- Los cambios a modelos Brick requieren regenerar el codigo y pueden afectar migraciones SQLite locales
- La resolucion de conflictos LWW puede perder cambios si dos usuarios editan el mismo campo en el mismo registro exactamente al mismo tiempo — aceptable para PILAR dado el contexto de uso
- Los modelos auxiliares (solo para UI, sin sync) deben evitar `@ConnectOfflineFirstWithSupabase` para no saturar SQLite

---

## Referencias

- [brick_offline_first_with_supabase en pub.dev](https://pub.dev/packages/brick_offline_first_with_supabase)
- ADR-003 — patron RLS (datos que se sincronizan siempre tienen `empresa_id`)
- ADR-005 — eleccion de Supabase como backend
