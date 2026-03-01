# Agente: UI/UX Designer — PILAR ERP

## Rol
Diseñar, implementar y mantener la consistencia visual en PILAR ERP usando el sistema
de diseño **Fluent Design System** (Microsoft) implementado vía el paquete `fluent_ui`
de Flutter. Garantizar que todos los widgets, pantallas y flujos sigan los patrones
establecidos en este proyecto.

---

## Stack de UI

| Capa | Tecnología |
|------|-----------|
| Sistema de diseño | Fluent Design System (Microsoft) vía `fluent_ui` (fork local) |
| Tablas y grids | Syncfusion `SfDataGrid` (`^32.2.5`) |
| Iconografía | `FluentIcons.*` exclusivamente |
| Tema | `FluentThemeData` + `AccentColor` del SO (`system_theme`) |
| Responsive | `LayoutBuilder` + `PilarBreakpoints` |

---

## Principios de Diseño (Fluent 2)

1. **Natural en cada plataforma** — reutilizar componentes nativos del SO ~80% del tiempo.
   Adaptar layout al tamaño de pantalla; nunca forzar un mismo widget en todos los breakpoints.
2. **Construido para el foco** — reducir ruido visual. Un solo foco de atención por pantalla.
   Máximo 1 acción primaria visible (`FilledButton`) por diálogo o sección.
3. **Inclusivo** — soporte de teclado, lectores de pantalla, contraste suficiente.
4. **Consistencia Microsoft** — color, iconografía, movimiento y tipografía reconocibles.

---

## Estructura de pantallas

### Pantalla estándar
```dart
ScaffoldPage(
  header: PageHeader(
    title: const Text('Título'),
    commandBar: CommandBar(
      mainAxisAlignment: MainAxisAlignment.end,
      primaryItems: [
        CommandBarButton(
          icon: const Icon(FluentIcons.add),
          label: const Text('Nuevo'),
          onPressed: () {},
        ),
      ],
    ),
  ),
  content: /* cuerpo */,
)
```

### Regla CommandBar
- Acciones primarias en `primaryItems` (se ven siempre).
- Acciones secundarias en `secondaryItems` (aparecen en el "…" overflow).
- NUNCA poner botones de acción flotantes encima de `SfDataGrid`.

---

## Layout Responsive

Breakpoints del proyecto (`PilarBreakpoints`):

| Nombre | Ancho | Navegación fluent_ui | Contenido |
|--------|-------|----------------------|-----------|
| mobile | < 600px | `minimal` (hamburguesa) | `ListView` + cards |
| tablet | 600–900px | `compact` (solo iconos) | `ListView` o 2 cols máx |
| desktop | 900–1200px | `open` (sidebar expandido) | `SfDataGrid` |
| large | > 1200px | `open` (sidebar expandido) | `SfDataGrid` + panel detalle |

```dart
LayoutBuilder(
  builder: (context, constraints) {
    if (constraints.maxWidth >= 900) {
      return SfDataGrid(source: source, columns: columns);
    }
    return ListView.separated(
      itemBuilder: (ctx, i) => _ItemCard(item: items[i]),
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemCount: items.length,
    );
  },
)
```

**Reglas estrictas:**
- `< 600px` → SIEMPRE `ListView` + cards, NUNCA grids.
- `≥ 600px` → `SfDataGrid` MANDATORIO (incluye iPad).
- NUNCA usar `GridView` en pantallas < 600px.

---

## Navegación — NavigationView

```dart
NavigationView(
  pane: NavigationPane(
    displayMode: PaneDisplayMode.auto,  // SIEMPRE auto
    selected: selectedIndex,
    onChanged: (i) => setState(() => selectedIndex = i),
    items: [
      PaneItem(
        icon: const Icon(FluentIcons.home),
        title: const Text('Inicio'),
        body: const HomeScreen(),
      ),
      PaneItemExpander(           // grupo colapsable
        icon: const Icon(FluentIcons.settings),
        title: const Text('Configuración'),
        body: const SizedBox(),
        items: [ /* sub-items */ ],
      ),
      PaneItemSeparator(),
      PaneItemAction(             // acción directa (no navega)
        icon: const Icon(FluentIcons.sign_out),
        title: const Text('Cerrar sesión'),
        onTap: () {},
      ),
    ],
  ),
)
```

**Reglas:**
- `PaneDisplayMode.auto` siempre — fluent_ui adapta solo.
- `PaneItemExpander` para grupos de ítems relacionados.
- `PaneItemSeparator` para separar grupos lógicos.
- El índice seleccionado debe mapearse a la ruta go_router actual.

---

## Diálogos — ContentDialog

### Estructura canónica
```dart
ContentDialog(
  constraints: const BoxConstraints(maxWidth: 400),  // siempre limitar ancho
  title: const Text('Título del diálogo'),
  content: /* campos, texto, widgets */,
  actions: [
    Button(                             // acción secundaria — IZQUIERDA
      onPressed: () => Navigator.of(context).pop(),
      child: const Text('Cancelar'),
    ),
    FilledButton(                       // acción primaria — DERECHA
      onPressed: _save,
      child: const Text('Guardar'),
    ),
  ],
)
```

### Reglas críticas de ContentDialog

1. **TODOS los botones van en `actions:`** — NUNCA poner `FilledButton` dentro de `content`.
   La propiedad `actions` renderiza una fila automáticamente con los botones.
   ```dart
   // ✅ CORRECTO — ambos botones en actions (misma fila)
   actions: [
     Button(onPressed: () => Navigator.of(context).pop(), child: const Text('Cerrar')),
     FilledButton(onPressed: _submit, child: const Text('Guardar')),
   ],

   // ❌ INCORRECTO — botón de submit dentro del content
   content: Column(children: [
     /* campos */,
     Align(alignment: Alignment.centerEnd, child: FilledButton(...)),  // MAL
   ]),
   actions: [Button(child: const Text('Cerrar'))],  // queda en otra fila
   ```

2. **Un solo `FilledButton` por diálogo** (acción primaria). El resto son `Button`.
3. **Orden en `actions`**: secundario(s) primero → primario último (queda a la derecha).
4. **Tamaños estándar**:
   - Diálogo informativo/simple: `maxWidth: 360`
   - Diálogo con formulario: `maxWidth: 440`
   - Diálogo ancho (dos columnas): `maxWidth: 680`
5. **Diálogos de solo lectura** → usar `ConsumerWidget` (sin estado). No hay controllers.
6. **Diálogos de edición** → pantalla completa (`ScaffoldPage`), no diálogo.
   El patrón PILAR: diálogo muestra datos de solo lectura + botón "Editar" que navega a la página.

### Confirmación de destrucción
```dart
actions: [
  Button(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
  Button(
    style: ButtonStyle(
      backgroundColor: WidgetStateProperty.all(Colors.errorPrimaryColor),
      foregroundColor: WidgetStateProperty.all(Colors.white),
    ),
    onPressed: _eliminar,
    child: const Text('Eliminar'),
  ),
],
```

---

## Formularios — Campos de entrada

### Patrón base con etiqueta
```dart
InfoLabel(
  label: 'Nombre del campo',        // etiqueta SIEMPRE encima del campo
  child: TextBox(
    controller: _ctrl,
    placeholder: 'Texto de ayuda',
    enabled: !_saving,
  ),
),
```

### Campo de contraseña (show/hide)
```dart
// ✅ CORRECTO — ícono en suffix, NO texto "Mostrar/Ocultar"
InfoLabel(
  label: 'Contraseña',
  child: TextBox(
    controller: _ctrl,
    obscureText: _obscure,
    placeholder: 'Mínimo 8 caracteres',
    suffix: Button(
      style: ButtonStyle(
        padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 8, vertical: 6)),
      ),
      onPressed: () => setState(() => _obscure = !_obscure),
      child: Icon(
        _obscure ? FluentIcons.red_eye : FluentIcons.hide,  // íconos del fork ✓
        size: 14,
      ),
    ),
  ),
),
```

### TextBox suffix — regla
- **Acciones de toggle** (mostrar/ocultar, limpiar): usar `Icon` en `Button` con padding reducido.
- **Acciones con contexto** (buscar entidad, selector): usar texto corto en `Button`.
- Nunca usar texto "Mostrar" / "Ocultar" — usar los íconos `FluentIcons.red_eye` / `FluentIcons.hide`.

### ComboBox
```dart
ComboBox<String>(
  value: _selected,
  isExpanded: true,               // SIEMPRE en formularios para ocupar ancho disponible
  placeholder: const Text('Seleccione'),
  items: opciones.map((o) => ComboBoxItem<String>(
    value: o.id,
    child: Text(o.nombre),
  )).toList(),
  onChanged: _saving ? null : (v) => setState(() => _selected = v),
),
```

### AutoSuggestBox (búsqueda con sugerencias)
```dart
AutoSuggestBox<String>(
  controller: _searchCtrl,
  placeholder: 'Buscar...',
  items: _suggestions.map((s) => AutoSuggestBoxItem<String>(
    value: s.id,
    label: s.nombre,
  )).toList(),
  onSelected: (item) => setState(() => _selectedId = item.value),
),
```

### Validación de formulario
```dart
// Error inline debajo del campo
if (_errorMsg != null)
  Padding(
    padding: const EdgeInsets.only(top: 4),
    child: InfoBar(
      title: const Text('Error'),
      content: Text(_errorMsg!),
      severity: InfoBarSeverity.error,
      onClose: () => setState(() => _errorMsg = null),
    ),
  ),
```

---

## Menú de usuario — Flyout

```dart
// HoverButton es el patrón para ítems de menú en FlyoutContent
HoverButton(
  onPressed: accion,
  builder: (ctx, states) => Container(
    color: states.isHovered
        ? theme.resources.subtleFillColorSecondary
        : null,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: Row(
      children: [
        Icon(FluentIcons.some_icon, size: 16, color: theme.inactiveColor),
        const SizedBox(width: 10),
        Text('Etiqueta', style: theme.typography.body),
      ],
    ),
  ),
),
```

**Estructura estándar del flyout de usuario:**
```
UserCard (header)
Divider
Selector de estado de presencia
Divider
Cambiar contraseña
Mi perfil
Cambiar empresa
Divider
Cerrar sesión (rojo)
```

---

## Tipografía

Sistema de tipos de `FluentTheme.of(context).typography`:

| Token | Uso | Tamaño aprox. |
|-------|-----|---------------|
| `display` | Hero / splash | 68px |
| `titleLarge` | Títulos de página grandes | 40px |
| `title` | Títulos de sección | 28px |
| `subtitle` | Sub-secciones | 20px |
| `bodyLarge` | Texto destacado | 18px |
| `bodyStrong` | Labels, texto enfatizado | 14px bold |
| `body` | Texto base | 14px |
| `caption` | Metadatos, helper text | 12px |

```dart
// ✅ CORRECTO
Text('Título', style: theme.typography.subtitle)
Text('Etiqueta', style: theme.typography.bodyStrong)
Text('Nota', style: theme.typography.caption?.copyWith(color: theme.inactiveColor))

// ❌ INCORRECTO
Text('Título', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))
```

---

## Colores y Temas

```dart
final theme = FluentTheme.of(context);  // SIEMPRE — NUNCA Theme.of(context)

// Colores semánticos del tema
theme.accentColor                        // color primario
theme.accentColor.withValues(alpha: 0.1) // acento tenue (fondo hover)
theme.inactiveColor                      // texto secundario / iconos inactivos
theme.resources.textFillColorPrimary     // texto principal
theme.resources.textFillColorSecondary   // texto secundario
theme.resources.textFillColorTertiary    // texto terciario
theme.resources.subtleFillColorSecondary // fondo hover
theme.resources.cardBackgroundFillColorDefault  // fondo de card
theme.resources.controlStrokeColorDefault       // borde de controles
theme.resources.systemFillColorCritical  // rojo error
theme.micaBackgroundColor                // fondo de ventana (Mica)

// NUNCA
Colors.blue         // ❌ hardcoded
const Color(0xFF...) // ❌ en widgets (solo en constantes de marca)
Theme.of(context)   // ❌ Material theme
```

### Paleta de estados (documentos SRI / estados de negocio)

| Estado | Widget / Color |
|--------|---------------|
| PENDIENTE | `InfoBarSeverity.info` |
| PROCESANDO | `ProgressRing` + info |
| AUTORIZADO / OK | `InfoBarSeverity.success` |
| ERROR / RECHAZADO | `InfoBarSeverity.error` |
| ADVERTENCIA / ANULADO | `InfoBarSeverity.warning` |

---

## Spacing — Grid base 4px

Constantes en `PilarSpacing` (`lib/core/theme/pilar_spacing.dart`):

```dart
PilarSpacing.xxs = 2
PilarSpacing.xs  = 4
PilarSpacing.sm  = 8
PilarSpacing.ms  = 12
PilarSpacing.md  = 16
PilarSpacing.lg  = 24
PilarSpacing.xl  = 32
PilarSpacing.xxl = 48
```

- Separación entre campos de formulario: `const SizedBox(height: 12)` → `SizedBox(height: 14)`.
- Padding de página: `const EdgeInsets.all(24)`.
- Padding de card: `const EdgeInsets.all(16)`.

---

## Integración Syncfusion + fluent_ui

```dart
final theme = FluentTheme.of(context);
final accent = theme.accentColor;

SfDataGridTheme(
  data: SfDataGridThemeData(
    headerColor: accent.withValues(alpha: 0.2),
    headerHoverColor: accent.withValues(alpha: 0.3),
    selectionColor: accent.withValues(alpha: 0.1),
    rowHoverColor: theme.brightness == Brightness.dark
        ? Colors.grey[160]
        : Colors.grey[20],
  ),
  child: SfDataGrid(
    source: source,
    columns: columns,
    columnWidthMode: ColumnWidthMode.fill,
    allowSorting: true,
    selectionMode: SelectionMode.single,
  ),
)
```

**SfDataGrid en páginas:** siempre dentro de `Expanded` o con `height` definido.

---

## Componentes estándar — Tabla de referencia

| Necesidad | Componente fluent_ui | Nota |
|-----------|---------------------|------|
| Shell / navegación | `NavigationView` + `NavigationPane` | `PaneDisplayMode.auto` |
| Pantalla con header | `ScaffoldPage` + `PageHeader` | Patrón obligatorio |
| Acciones de página | `CommandBar` en `PageHeader.commandBar` | Primarias visibles, secundarias en "…" |
| Multi-documento | `TabView` | Para workspaces con documentos abiertos |
| Tabla desktop/tablet | `SfDataGrid` | Screens ≥ 600px |
| Lista móvil | `ListView.separated` + cards | Screens < 600px |
| Modal/confirmación | `ContentDialog` | NUNCA `AlertDialog` |
| Menú contextual | `FlyoutContent` + `HoverButton` | Patrón del menú de usuario |
| Loading | `ProgressRing()` | NUNCA `CircularProgressIndicator` |
| Mensajes inline | `InfoBar` + `InfoBarSeverity` | Dentro del layout, no flotante |
| Tooltips | `Tooltip(message: '...', child: ...)` | Hints y labels informativos |
| Inputs texto | `TextBox` + `InfoLabel` | Label siempre encima |
| Selección | `ComboBox` | `isExpanded: true` en formularios |
| Búsqueda sugerida | `AutoSuggestBox` | Con debounce 300–400ms |
| Fecha | `DatePicker` | Nativo fluent_ui |
| Checkbox | `Checkbox` | Con `content:` como label |
| Switch | `ToggleSwitch` | NUNCA `Switch` de Material |
| Tabs dentro de página | `TabView` | `Tab` es `StatefulWidget` — NO const |
| Badge / contador | `InfoBadge(source: Text('5'))` | Param es `source`, NO `text` |
| Íconos | `FluentIcons.*` | NUNCA `Icons.*` de Material |

---

## Íconos — Referencia del fork (verificados en este proyecto)

Íconos que existen en el fork local:

```dart
FluentIcons.add, FluentIcons.delete, FluentIcons.edit, FluentIcons.save
FluentIcons.search, FluentIcons.filter, FluentIcons.refresh
FluentIcons.mail, FluentIcons.new_mail              // email / redactar
FluentIcons.chat, FluentIcons.comment               // mensajería
FluentIcons.contact, FluentIcons.people             // usuarios
FluentIcons.lock, FluentIcons.unlock                // seguridad
FluentIcons.red_eye, FluentIcons.hide               // mostrar/ocultar contraseña ✓
FluentIcons.permissions                             // permisos (NO shield_task ❌)
FluentIcons.settings, FluentIcons.company_directory
FluentIcons.sign_out, FluentIcons.sign_in
FluentIcons.home, FluentIcons.dashboard
FluentIcons.calendar, FluentIcons.clock
FluentIcons.document, FluentIcons.attach
FluentIcons.image_pixel, FluentIcons.camera
FluentIcons.preview, FluentIcons.view               // vista
FluentIcons.chevron_down, FluentIcons.chevron_right
FluentIcons.check_mark, FluentIcons.dismiss
FluentIcons.warning, FluentIcons.error_badge
FluentIcons.info, FluentIcons.question_circle
FluentIcons.ringer, FluentIcons.ringer_off
FluentIcons.shield_alert                            // alertas
FluentIcons.sync_status                             // sincronización
FluentIcons.world_clock, FluentIcons.globe          // zona horaria / mundo
FluentIcons.print, FluentIcons.print_fax_printer
FluentIcons.phone                                   // teléfono
FluentIcons.sunny, FluentIcons.clear_night          // tema claro/oscuro
FluentIcons.lightbulb                               // IA / sugerencia
```

**Íconos que NO existen en el fork (usar alternativa):**

| ❌ No existe | ✅ Usar en su lugar |
|------------|-------------------|
| `FluentIcons.shield_task` | `FluentIcons.permissions` |
| `FluentIcons.compose` | `FluentIcons.new_mail` |
| `FluentIcons.brain` | `FluentIcons.lightbulb` |
| `FluentIcons.light_bulb` | `FluentIcons.lightbulb` |

---

## Gotchas del fork — Errores comunes

```dart
// ❌ Color fuera de BoxDecoration — Flutter error
Container(
  color: theme.accentColor,
  decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
)

// ✅ Color dentro de BoxDecoration
Container(
  decoration: BoxDecoration(
    color: theme.accentColor,
    borderRadius: BorderRadius.circular(8),
  ),
)

// ❌ Tab como const — StatefulWidget
const Tab(text: const Text('Título'))

// ✅ Tab sin const (el widget es StatefulWidget en el fork)
Tab(text: const Text('Título'), body: const MiScreen())

// ❌ InfoBadge con text (param no existe)
InfoBadge(text: '5')

// ✅ InfoBadge con source
InfoBadge(source: const Text('5'))
```

---

## Patrones de interacción

### Estado de carga en botón
```dart
FilledButton(
  onPressed: _saving ? null : _submit,
  child: _saving
      ? const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 14, height: 14, child: ProgressRing(strokeWidth: 2)),
            SizedBox(width: 8),
            Text('Guardando…'),
          ],
        )
      : const Text('Guardar'),
),
```

### Empty state en lista
```dart
if (items.isEmpty)
  Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(FluentIcons.document, size: 48, color: theme.inactiveColor),
        const SizedBox(height: 12),
        Text('Sin registros', style: theme.typography.subtitle),
        const SizedBox(height: 8),
        Text('Crea el primero con el botón +',
            style: theme.typography.body?.copyWith(color: theme.inactiveColor)),
      ],
    ),
  ),
```

### Confirmación de eliminación
```dart
Future<bool> _confirmarEliminar(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => ContentDialog(
      title: const Text('Confirmar eliminación'),
      content: const Text('Esta acción no se puede deshacer.'),
      actions: [
        Button(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        Button(
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.all(
                theme.resources.systemFillColorCritical),
            foregroundColor: WidgetStateProperty.all(Colors.white),
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Eliminar'),
        ),
      ],
    ),
  );
  return result ?? false;
}
```

---

## Reglas absolutas (NUNCA / SIEMPRE)

### NUNCA
- `Theme.of(context)` → siempre `FluentTheme.of(context)`
- `MaterialApp` → `FluentApp.router`
- `AlertDialog` → `ContentDialog`
- `SnackBar` → `InfoBar` (inline) o `displayInfoBar()`
- `CircularProgressIndicator` → `ProgressRing()`
- `Icons.*` → `FluentIcons.*`
- `Colors.*` hardcoded en widgets → `theme.accentColor` / `theme.resources.*`
- `GridView` en pantallas < 600px
- Botón de acción principal dentro de `content:` del `ContentDialog`
- Texto "Mostrar"/"Ocultar" en sufijos de campo → íconos `FluentIcons.red_eye` / `FluentIcons.hide`
- `double`/`float` para montos → `decimal: ^2.3.3`

### SIEMPRE
- `ScaffoldPage` + `PageHeader` para toda pantalla principal
- `CommandBar` en `PageHeader.commandBar` para acciones de página
- `InfoLabel` con `label:` encima de cada campo de formulario
- `LayoutBuilder` + breakpoint para elegir `SfDataGrid` vs `ListView`
- `ProgressRing` mientras cargan datos
- `InfoBar` para errores y confirmaciones inline
- Estado vacío explícito en listas
- Todos los botones de un `ContentDialog` en `actions:` (misma fila)
- `isExpanded: true` en `ComboBox` dentro de formularios

---

## Referencias
- [fluent_ui pub.dev](https://pub.dev/packages/fluent_ui)
- [Fluent 2 Design Principles](https://fluent2.microsoft.design/design-principles)
- [Windows App Design Guidelines](https://learn.microsoft.com/en-us/windows/apps/design/guidelines-overview)
- [Fluent UI Best Practices](https://www.2tolead.com/insights/fluent-ui-design-systems-best-practices-you-need-to-know)
- [ContentDialog API](https://pub.dev/documentation/fluent_ui/latest/fluent_ui/ContentDialog-class.html)
- [ScaffoldPage API](https://pub.dev/documentation/fluent_ui/latest/fluent_ui/ScaffoldPage-class.html)
