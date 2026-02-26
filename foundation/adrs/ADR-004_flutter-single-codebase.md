# ADR-004: Flutter como Único Codebase para 6 Plataformas + fluent_ui como Sistema de Diseño

**Estado**: Aceptado
**Fecha**: 2026-02 (actualizado 2026-02-21: sistema de diseño fluent_ui)
**Autores**: Arquitecto principal
**Tags**: flutter, frontend, multi-plataforma, arquitectura-ui, fluent_ui, diseño

---

## Contexto

PILAR debe estar disponible en las plataformas donde operan las empresas ecuatorianas:

- **Web**: uso principal del ERP (computadoras de escritorio en oficinas)
- **Windows**: ERP instalado en equipos sin acceso a internet estable
- **macOS / Linux**: desarrollo y usuarios técnicos
- **iOS / Android**: vendedores en campo, bodegueros, técnicos de servicio, app de citas para clientes

Desarrollar y mantener 6 aplicaciones nativas separadas no es viable para un equipo pequeño. La UI del ERP tiene complejidad alta: grillas de datos, formularios largos, reportes PDF, gráficos, navegación multi-nivel.

Además, el proyecto tiene un requisito de **3 flavors** para casos de uso especializados:
- Flavor `erp`: ERP completo (Web + Desktop + Mobile)
- Flavor `negocio`: app especializada para administradores y empleados de un tipo de negocio (iOS/Android)
- Flavor `cliente`: app white-label para usuarios finales (iOS/Android)

---

## Decisión

Se adoptan **dos decisiones complementarias**:

1. **Flutter 3.x (Dart)** como el único framework de frontend para las 6 plataformas
2. **fluent_ui** como el sistema de diseño UI principal del proyecto

---

## Parte 1 — Flutter como único codebase

### Justificación Técnica

Flutter compila a código nativo en iOS, Android, Windows, macOS y Linux, y a JavaScript/WebAssembly para Web. Un solo codebase Dart genera 6 artefactos de plataforma.

### Flavors

```dart
// lib/flavors/
// main_erp.dart     → entry point del ERP completo
// main_negocio.dart → entry point del flavor especializado (admin/empleados)
// main_cliente.dart → entry point white-label clientes

// Configuración por flavor:
class FlavorConfig {
  final String appName;
  final String supabaseUrl;
  final Color primaryColor;
  final List<String> modulosHabilitados;
}
```

### Alternativas de framework rechazadas

**1. Aplicaciones Nativas por Plataforma (Swift/Kotlin/C#/etc.)**
- 6 codebases independientes con 6 equipos o 6x el trabajo de mantenimiento
- **Rechazado por**: inviable en términos de recursos

**2. React Native**
- Ecosistema maduro para iOS/Android, pero Web es un ciudadano de segunda clase (React Native Web no compila a Windows/macOS/Linux nativos)
- Los componentes de grilla de datos complejos (Syncfusion equivalente) son más limitados en RN
- **Rechazado por**: no cubre Windows/macOS/Linux con un solo codebase

**3. Electron + React/Vue para Desktop + React Native para Mobile**
- Dos frameworks, dos codebases, dos equipos de frontend
- Electron consume mucha memoria (Chromium embebido) — inaceptable para equipos con 4GB RAM en Ecuador
- **Rechazado por**: dos codebases es la situación que se quería evitar

**4. Web-Only (PWA) + Electron Wrapper**
- Las PWA tienen limitaciones en acceso a filesystem, puertos COM (impresoras fiscales), integración con biométricos
- **Rechazado por**: limitaciones de hardware para los casos de uso de bodega y punto de venta

**5. Tauri (Rust + WebView) para Desktop**
- Muy liviano comparado con Electron, pero solo para Desktop — no cubre iOS/Android
- **Rechazado por**: no cubre mobile

---

## Parte 2 — fluent_ui como Sistema de Diseño

### Justificación

PILAR es principalmente un ERP de escritorio — la mayoría de los usuarios trabajan en Web/Windows. Se necesita un shell de navegación tipo Odoo/SAP con:
- Sidebar jerárquico con grupos y sub-items
- Multi-documento (múltiples registros abiertos simultáneamente en tabs)
- MenuBar horizontal estilo Office para acciones de módulo
- Formularios de datos densos (muchos campos visibles)
- Integración con Syncfusion DataGrid/Charts sin conflictos de tema

fluent_ui implementa el **Fluent Design System de Microsoft (Windows 11)** y cubre exactamente estos casos. Ha sido verificado en producción funcionando correctamente en **iOS/iPad y Android sin ninguna modificación** de la librería.

### Componentes clave que fluent_ui aporta

| Componente | Uso en PILAR |
|-----------|-------------|
| `NavigationView` + `NavigationPane` | Shell principal con `PaneDisplayMode.auto` (responsive automático) |
| `TabView` | Multi-documento: facturas, órdenes, clientes abiertos simultáneamente |
| `MenuBar` + `CommandBar` | Acciones de módulo en header (desktop/web) |
| `ScaffoldPage` + `PageHeader` | Estructura estándar de pantalla con título y comandos |
| `ContentDialog` | Confirmaciones, formularios modales, búsquedas |
| `FlyoutTarget` + `MenuFlyout` | Menú contextual de usuario, dropdowns |
| `TextBox`, `ComboBox`, `AutoSuggestBox` | Inputs de formulario nativos |
| `DatePicker`, `TimePicker`, `CalendarDatePicker` | Selectores de fecha/hora |
| `FluentThemeData` | Tema con `accentColor` configurable por empresa, dark/light/auto |
| `FluentIcons` (~5000) + `WindowsIcons` (~1500) | Iconografía completa |

### Comportamiento responsive — NavigationView

`PaneDisplayMode.auto` adapta la navegación automáticamente sin código adicional:

| Ancho | Modo | Comportamiento |
|-------|------|---------------|
| ≥ 1008px | `expanded` | Sidebar con iconos + etiquetas |
| 641–1007px | `compact` | Solo iconos, expande al hover |
| ≤ 640px | `minimal` | Botón hamburguesa, pane superpuesta |
| manual | `top` | Barra horizontal superior |

### Layout de datos — regla SfDataGrid vs Cards

Dentro de cada pantalla se usa `LayoutBuilder` para adaptar la visualización de listas:

```dart
LayoutBuilder(
  builder: (context, constraints) {
    return constraints.maxWidth > 800
        ? SfDataGrid(source: source, columns: columns)  // desktop/tablet
        : ListView.separated(                            // móvil
            itemBuilder: (ctx, i) => _buildCard(items[i]),
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemCount: items.length,
          );
  },
)
```

**Regla**: NUNCA usar grillas (`GridView`) en pantallas menores a 600px — usar siempre `ListView` con cards.

### Integración fluent_ui + Syncfusion

Syncfusion utiliza Material internamente, pero acepta theming explícito via `SfDataGridTheme`. El patrón para conectar ambos sistemas:

```dart
// Leer el tema Fluent y aplicarlo a Syncfusion
final theme = FluentTheme.of(context);
final headerColor = theme.accentColor
    .defaultBrushFor(theme.brightness)
    .withValues(alpha: 0.2);

SfDataGridTheme(
  data: SfDataGridThemeData(
    headerColor: headerColor,
    headerHoverColor: headerColor.withValues(alpha: 0.3),
    selectionColor: theme.accentColor.withValues(alpha: 0.1),
    rowHoverColor: theme.brightness == Brightness.dark
        ? Colors.grey[160]
        : Colors.grey[20],
  ),
  child: SfDataGrid(...),
)
```

### Setup de la app

```dart
FluentApp.router(
  themeMode: configService.themeMode,         // light/dark/system
  theme: FluentThemeData(
    brightness: Brightness.light,
    accentColor: empresa.colorPrimario.toAccentColor(),
    typography: Typography.fromBrightness(brightness: Brightness.light)
        .apply(fontSizeFactor: configService.fontFactor),
    visualDensity: VisualDensity.standard,
    focusTheme: const FocusThemeData(glowFactor: 0.0),
  ),
  darkTheme: FluentThemeData(brightness: Brightness.dark, ...),
  routerConfig: appRouter,  // GoRouter con ShellRoute
)
```

### Paquetes complementarios (solo desktop)

| Paquete | Uso |
|---------|-----|
| `window_manager: ^0.5.0` | Guardar/restaurar posición y tamaño de ventana entre sesiones |
| `flutter_acrylic: ^1.0.0+2` | Efecto Acrylic/Mica de Windows 11 en la ventana principal |
| `system_theme: ^3.1.2` | Leer el accent color del sistema operativo |

Estos paquetes se inicializan condicionalmente:
```dart
if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
  await windowManager.ensureInitialized();
  await Window.initialize();  // flutter_acrylic
  SystemTheme.accentInstance.load();
}
```

### Alternativas de sistema de diseño rechazadas

**Material 3**
- Mobile-first; su NavigationDrawer/NavigationRail no tienen la riqueza del `NavigationPane` de fluent_ui (sin PaneItemExpander, sin sub-items anidados, sin autoSuggestBox integrado)
- **Rechazado por**: shell de navegación insuficiente para la complejidad del ERP

**shadcn_ui (nank1ro)**
- Buen aspecto visual y compatible con MaterialApp, pero no tiene shell de navegación completo
- 0.46.x — aún en desarrollo activo, API puede cambiar
- **Rechazado por**: no tiene NavigationView/TabView/MenuBar equivalentes; solo componentes individuales

**macos_ui**
- Excelente para macOS nativo, pero solo funciona en macOS
- **Rechazado por**: no cubre las 6 plataformas

**fluent_ui — razón de adopción vs las anteriores**
- Es el único que tiene NavigationView + TabView + MenuBar listos para usar
- Verified en producción en iOS/Android (proyecto `dev_odoo18/app` — 502 archivos Dart)
- `PaneDisplayMode.auto` hace el responsive automáticamente
- `FluentThemeData` con `accentColor` permite personalización por empresa sin código extra

---

## Consecuencias

### Positivas

- Un solo codebase: un feature implementado una vez funciona en las 6 plataformas
- Dart es un lenguaje tipado con excelente tooling — errores en compilación, no en runtime
- Flutter tiene soporte oficial de Google para las 6 plataformas objetivo
- `fluent_ui` provee NavigationView, TabView, MenuBar, ContentDialog — el shell completo de un ERP sin construirlo desde cero
- Syncfusion cubre DataGrid, PDF, Charts, Calendar con APIs consistentes en todas las plataformas y se integra con fluent_ui via `SfDataGridTheme`
- `PaneDisplayMode.auto` hace el responsive de navegación sin una sola línea de código de breakpoints

### Negativas / Restricciones

- La web en Flutter usa un renderer canvas (CanvasKit) que es más pesado que HTML nativo — primera carga puede ser lenta. Mitigado con lazy loading de módulos (deferred imports)
- Los builds de iOS requieren una Mac con Xcode — en CI/CD se necesita un runner macOS
- `build_runner` para Brick puede ser lento en proyectos grandes — mitigar con `--delete-conflicting-outputs` y cache de CI
- fluent_ui usa Fluent Design (Windows 11) — en iOS/Android el look es diferente al nativo de cada plataforma, pero esto es aceptable para un ERP (prioridad: funcionalidad y consistencia entre plataformas)

---

## Referencias

- ADR-001 — brick_offline_first_with_supabase (funciona en las 6 plataformas)
- ADR-008 — Syncfusion como suite UI exclusiva para DataGrid/Charts/PDF
- `foundation/pubspec-referencia.md` — versiones de fluent_ui y paquetes complementarios
- Proyecto de referencia: `dev_odoo18/app` — implementación en producción de fluent_ui + Syncfusion + Riverpod + GoRouter
