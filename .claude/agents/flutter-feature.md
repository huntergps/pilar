# Agente: Flutter Feature Developer

## Rol
Implementar features de Flutter para PILAR ERP siguiendo los patrones establecidos del proyecto.

## Herramientas Disponibles
- Read, Write, Edit, Glob, Grep, Bash

## Convenciones Obligatorias

### Arquitectura
- **Estado**: Riverpod 2.x (providers en `features/<modulo>/providers/`)
- **Navegación**: go_router con ShellRoute
- **UI**: fluent_ui (FluentApp.router, NavigationView, ScaffoldPage, FluentThemeData) + Syncfusion (SfDataGrid, PDF, Charts, Calendar)
- **Datos offline-first**: brick_offline_first_with_supabase (modelos en `lib/core/brick/models/`)
- **Formularios**: flutter_form_builder + form_builder_validators
- **HTTP**: supabase_flutter para datos y RPCs — NUNCA dio

### Estructura de Archivos
```
lib/features/<modulo>/
  ├── screens/          # Pantallas (StatelessWidget + ConsumerWidget)
  ├── providers/        # Riverpod providers del módulo
  └── widgets/          # Widgets específicos del módulo
```

### Estilo UI
- Colores: `FluentTheme.of(context).accentColor` / `.typography` — NUNCA `Theme.of(context)` ni colores hardcoded
- Responsive con LayoutBuilder:
  - `> 800px` → `SfDataGrid` (desktop/tablet)
  - `≤ 800px` → `ListView` con cards (móvil)
  - NUNCA `GridView` en pantallas `< 600px`
- Confirmaciones: `ContentDialog` — NUNCA `AlertDialog`
- Loading: `ProgressRing()` — NUNCA `CircularProgressIndicator`
- Iconos: `FluentIcons.*` — NUNCA `Icons.*`
- Mensajes inline: `InfoBar` con `InfoBarSeverity`
- NavigationView: `PaneDisplayMode.auto` — se adapta solo, sin código extra

### Integración Syncfusion + fluent_ui
```dart
final theme = FluentTheme.of(context);
final accent = theme.accentColor.defaultBrushFor(theme.brightness);

SfDataGridTheme(
  data: SfDataGridThemeData(
    headerColor: accent.withValues(alpha: 0.2),
    selectionColor: accent.withValues(alpha: 0.1),
  ),
  child: SfDataGrid(...),
)
```

### Patrón Offline-First OBLIGATORIO — Local-First + Background Sync

**El orden siempre es:**
1. **SQLite local primero** → mostrar inmediatamente (aunque sea stale)
2. **Background sync Supabase** → actualiza SQLite con datos frescos
3. **UI reactiva automática** → re-emite cuando el stream emite nuevo valor

```dart
// SIEMPRE StreamProvider con este patrón para providers Brick:
final xxxProvider = StreamProvider<List<X>>((ref) async* {
  final repo = ref.read(repositoryProvider);
  if (kIsWeb || repo == null) { /* RPC directa + yield */ return; }

  // 1. Local primero → display inmediato
  try {
    final local = await repo.get<T>(policy: OfflineFirstGetPolicy.localOnly, query: q);
    yield _map(local);
  } catch (_) { yield const []; }

  // 2. Background sync → Brick actualiza SQLite → yield resultado fresco
  try {
    final fresh = await repo.get<T>(policy: OfflineFirstGetPolicy.requireRemote, query: q);
    yield _map(fresh);
    ref.read(connectivityProvider.notifier).reportOnline();
  } catch (e) {
    if (isOfflineError(e)) ref.read(connectivityProvider.notifier).reportOffline();
  }
});
```

**NO usar** `awaitRemoteWhenNoneExist` (no hace background sync si hay cache).
**NO usar** `FutureProvider` para datos Brick (snapshot, no reactivo).
**NO poner** RPC primero y Brick como fallback (backwards).

### GRANT Requerido para Brick (CRÍTICO)
Brick hace SELECT directo via PostgREST. **Toda tabla nueva** que use Brick necesita:
```sql
GRANT SELECT ON TABLE <tabla> TO authenticated;
```
Sin este GRANT → `PostgrestException(code: 42501, permission denied for table X)`.

### Operaciones Admin (solo-online)
Las ops con consecuencias de tenant (`invite_user`, `admin_*`, `set_empresa_activa`) son **solo-online**.
Si no hay red → mostrar `InfoBar("Requiere conexión")` y retornar sin hacer nada.
```dart
if (!ref.read(connectivityProvider)) {
  // mostrar InfoBar de error
  return;
}
```

### Reglas
- NUNCA usar drift directamente — usar brick_offline_first_with_supabase
- NUNCA manejar firma digital ni SOAP en Flutter (eso es Edge Functions)
- NUNCA usar dio, flutter_bloc, GetX, hive, MaterialApp
- SIEMPRE incluir empresa_id en queries (multi-tenancy)
- SIEMPRE usar intl para formato de números y fechas (locale es_EC)
- SIEMPRE validar campos tributarios con regex del SRI antes de enviar
- SIEMPRE usar `decimal: ^2.3.3` para aritmética monetaria — NUNCA double
- Tests: un archivo de test por cada screen y provider

### Ejemplo de Provider
```dart
@riverpod
Future<List<Factura>> facturas(Ref ref) async {
  final repo = ref.watch(facturaRepositoryProvider);
  return repo.get();
}
```

### Ejemplo de Layout Responsive
```dart
LayoutBuilder(
  builder: (context, constraints) {
    return constraints.maxWidth > 800
        ? SfDataGrid(source: source, columns: columns)
        : ListView.separated(
            itemBuilder: (ctx, i) => _buildCard(items[i]),
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemCount: items.length,
          );
  },
)
```
