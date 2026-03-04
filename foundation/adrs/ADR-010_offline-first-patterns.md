# ADR-010: Patrones Offline-First con Brick ORM

**Estado:** Aceptado
**Fecha:** 2026-03-04
**Contexto:** Completar la cobertura offline-first de la app Flutter (de ~55% a ~90%)

---

## Contexto

PILAR ERP debe funcionar correctamente en condiciones de red intermitente (Ecuador, zonas rurales, cortes de luz). El stack es `brick_offline_first_with_supabase` que sincroniza SQLite local ↔ PostgreSQL remoto via Supabase.

La auditoría inicial detectó:
- 55–60% de cumplimiento offline-first en plataformas native
- Módulo Comunicación con 0% de cobertura Brick
- Providers core (módulos, perfil) ignorando modelos Brick existentes
- Sin índices SQLite en queries frecuentes

---

## Decisiones

### 1. Cuándo crear un modelo Brick vs. usar RPC directa

| Situación | Decisión | Razón |
|-----------|----------|-------|
| Tabla con filas por empresa que el usuario navega frecuentemente | **Crear modelo Brick** | Offline disponible, queries locales rápidas |
| Vista derivada (JOIN multi-tabla) | **RPC directa** | Brick no puede reproducir JOINs complejos offline |
| Tabla de auth (`users`) | **Supabase Auth directamente** | Brick no modela tablas de auth |
| Binarios (Storage) | **Supabase Storage directamente** | Archivos no van por SQLite |
| Query con filtros dinámicos complejos | **RPC** si no hay modelo Brick; **Brick** si la tabla ya tiene modelo |
| Conteos y agregaciones | **RPC** | Brick no tiene primitivas de agregación |

**Casos especiales justificados (RPC-only):**
- `emailThreadsProvider` → Vista `email_threads` (JOIN en Supabase). Se mantiene como RPC.
- `adjuntosCountProvider` → `COUNT(*)`. Se mantiene como RPC.
- `todosAdjuntosProvider` → Query empresa-wide con filtros opcionales. Se mantiene como RPC.
- `chatterActividadesProvider` → Datos de actividades rara vez se consultan offline.

---

### 2. Patrón `@Sqlite(ignore: true)` para `empresa_id`

Todas las tablas tienen RLS basado en `empresa_id`. En SQLite local no se necesita filtrar por empresa porque el dispositivo pertenece a un solo usuario/empresa a la vez.

```dart
/// empresa_id: solo Supabase, no SQLite (RLS filtra en servidor).
@Supabase(name: 'empresa_id')
@Sqlite(ignore: true)
final String? empresaId;
```

**Consecuencia:** `empresaId` es `String?` nullable en el modelo Brick (viene null al leer de SQLite offline, viene del servidor cuando online).

---

### 3. Manejo de JSONB y arrays

Brick no soporta `Map<String,dynamic>` ni `List<T>` complejos en SQLite. Patrón:

```dart
/// Almacena el JSON serializado como String en SQLite.
/// Solo se llena desde fromJson (RPC online). Vacío '{}' o '[]' offline.
@Supabase(ignore: true)
@Sqlite(ignore: true)
final String metadatosJson;

/// Getter que deserializa en tiempo de ejecución.
@Supabase(ignore: true)
@Sqlite(ignore: true)
Map<String, dynamic> get metadatos {
  try { return Map<String,dynamic>.from(jsonDecode(metadatosJson) as Map? ?? {}); }
  catch (_) { return const {}; }
}
```

Para JSONB que se quiere también disponible offline con valor null:

```dart
@Supabase(name: 'meta_json')
@Sqlite(ignore: true)
final Map<String, dynamic>? metaJson;
```

---

### 4. Getters computados — DEBEN tener `@Supabase(ignore:true) @Sqlite(ignore:true)`

El generador de Brick incluye TODOS los getters de la clase como columnas a menos que estén anotados. Regla obligatoria:

```dart
// ❌ INCORRECTO — genera columna espuria
bool get esLog => tipo == 'log_sistema';

// ✅ CORRECTO
@Supabase(ignore: true)
@Sqlite(ignore: true)
bool get esLog => tipo == 'log_sistema';
```

---

### 5. Patrón native/web en providers

```dart
// Native: local-first con Brick
final repo = ref.read(repositoryProvider);
if (!kIsWeb && repo != null) {
  try {
    final results = await repo.get<MiModelo>(
      policy: OfflineFirstGetPolicy.awaitRemoteFallbackLocalOnly,
      query: Query(where: [Where.exact('campoIndexado', valor)]),
    );
    if (results.isNotEmpty) return results;
  } catch (_) {
    // fall through to web path
  }
}

// Web / fallback RPC
final data = await Supabase.instance.client.rpc('mi_rpc', params: {...});
```

**`OfflineFirstGetPolicy.awaitRemoteFallbackLocalOnly`**: intenta Supabase primero, cae a SQLite si hay error de red.
**`OfflineFirstGetPolicy.localOnly`**: solo SQLite, sin llamada a red.

---

### 6. Criterios para índices SQLite

Se añade `@Sqlite(index: true)` a campos usados en cláusulas `Where.exact(...)` de queries Brick frecuentes:

| Campo | Modelos | Razón |
|-------|---------|-------|
| `empresaId` | `AlertaEmpresa`, `Notificacion`, `ModuloEmpresa`, `UsuarioEmpresaPerfil` | Filtro por empresa en queries frecuentes |
| `activo` | `Contacto`, `Producto` | Lista activos/inactivos |
| `activa` | `ComConversacion` | Bandeja de conversaciones activas |
| `conversacionId` | `ComMensaje` | Mensajes de una conversación |
| `estado` | `ComMensaje` | Filtro por estado de envío |
| `canalId` | `ChatMensaje` | Mensajes de un canal de chat |
| `entidadTipo`, `entidadId` | `ChatterMensaje`, `Adjunto` | Mensajes/adjuntos de un registro |

---

### 7. Modelo Brick para campos `DateTime?`

Los campos `DateTime` que provienen de Supabase via INSERT automático (ej: `created_at`, `creado_en`) se declaran como **nullable** en el modelo Brick:

```dart
@Supabase(name: 'creado_en')
final DateTime? creadoEn;
```

**Consecuencia para UI:** El código que usa estos campos debe manejar null:

```dart
// ❌ Puede fallar si creadoEn es null
Text(_formatFecha(m.creadoEn))

// ✅ Con fallback
Text(_formatFecha(m.creadoEn ?? m.enviadoEn ?? DateTime.now()))
```

---

### 8. `fromJson` factories en modelos Brick

Cada modelo Brick tiene un factory `fromJson(Map<String,dynamic>)` para el path web/RPC. Los adapters generados por build_runner tienen su propio mecanismo de deserialización que no usa este factory; `fromJson` solo se usa en el fallback RPC:

```dart
// Web fallback
return (data as List)
    .map((e) => MiModelo.fromJson(e as Map<String, dynamic>))
    .toList();
```

---

### 9. `typedef` para retrocompatibilidad de nombres

Si un modelo Brick renombra una clase (ej: `AdjuntoItem` → `Adjunto`), añadir typedef en el modelo:

```dart
/// Alias de compatibilidad.
typedef AdjuntoItem = Adjunto;
```

---

## Consecuencias

**Positivas:**
- ~90% cobertura offline-first en native (iOS, Android, Desktop)
- Carga inicial instantánea desde SQLite cache cuando hay red intermitente
- Sync automático background cuando se recupera la conexión
- Queries SQLite indexadas: tiempo de respuesta < 10ms para listas típicas

**Negativas / trade-offs:**
- Brick requiere `build_runner` para regenerar adapters al cambiar modelos
- JSONB complejo no está disponible offline (accesible como `null` o `'{}'`)
- `empresa_id` no es filtrable en SQLite (depende de RLS en Supabase para isolation)
- `DateTime?` nullable agrega necesidad de null checks en UI

---

## Modelos Brick implementados

| Modelo | Tabla Supabase | Prioridad |
|--------|---------------|-----------|
| `ComConversacion` | `com_conversaciones` | P0 |
| `ComMensaje` | `com_mensajes` | P0 |
| `ChatMensaje` | `chat_mensajes` | P1 |
| `Rol` | `roles` | P1 |
| `ChatterMensaje` | `chatter_mensajes` | P2 |
| `Adjunto` | `adjuntos` | P2 |
| `Modulo` | `modulos` | Existente |
| `ModuloEmpresa` | `modulo_empresas` | Existente |
| `UsuarioEmpresaPerfil` | `usuarios_empresa` | Existente |
| `Contacto` | `contactos` | Existente |
| `Producto` | `productos` | Existente |
| `AlertaEmpresa` | `alertas_empresa` | Existente |
| `Notificacion` | `notificaciones` | Existente |
