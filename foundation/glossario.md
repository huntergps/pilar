# Glosario PILAR ERP

> Referencia de términos de arquitectura, stack técnico y negocio utilizados en el proyecto.
> Los términos son country-agnostic (ADR-006). Última revisión: 2026-02-21 — fluent_ui como sistema de diseño (ADR-004).

---

## Arquitectura PILAR

### Module Service Bus
Capa de integración entre módulos implementada como schema `module_bus` en PostgreSQL. Contiene funciones gateway que: (1) verifican si el módulo destino está activo para la empresa actual, (2) ejecutan la operación o retornan un NO-OP si el módulo no está activo. Los módulos Auxiliares NUNCA hacen INSERT directo en tablas de módulos Core — siempre llaman a `module_bus.<modulo>.<funcion>()`. Esto permite que una empresa tenga solo un subconjunto de módulos activos y el sistema funcione sin errores.

### Core Foundation
Capa base inspirada en el módulo `base` de Odoo (~90 modelos). Siempre activa, no desactivable. Incluye: infraestructura de adjuntos, notificaciones multi-canal, audit trail, secuencias genéricas, configuración de empresa, parámetros del sistema, tareas programadas (crons). Más los catálogos maestros como seed data: países, monedas, bancos, catálogos tributarios por localización. Y las entidades compartidas entre módulos: contactos, productos, listas de precios.

### Bloqueo optimista (version field)
Estrategia de control de concurrencia para documentos críticos. Cada tabla de documento tiene un campo `version INTEGER DEFAULT 1`. Al actualizar, se verifica que `version = version_leida`; si no coincide, otro proceso modificó el registro y la operación falla con un error controlado. Esto evita que dos usuarios simultáneos corrompan el mismo documento sin usar locks pesimistas que degraden el rendimiento.

### LWW (Last Write Wins)
**Last Write Wins** — Estrategia de resolución de conflictos para registros maestros (clientes, proveedores, productos) en la sincronización offline. Cuando hay un conflicto entre la versión local (SQLite) y la remota (PostgreSQL), gana la escritura con el `updated_at` más reciente. Implementado en Brick ORM mediante el campo `updated_at TIMESTAMPTZ` obligatorio en todas las tablas de maestros. Para datos donde LWW no es adecuado (stock, saldos) se usa suma-delta.

### Suma-delta (stock)
Estrategia de sincronización para datos acumulativos como saldos de stock o acumuladores financieros. En lugar de sincronizar el valor absoluto (que causaría pérdidas con LWW), se sincronizan los deltas (movimientos). Cada movimiento se registra como append-only en `<tabla_movimientos>`; el valor acumulado resultante se recalcula sumando todos los deltas en `<tabla_acumulativa>`. Esto garantiza que operaciones offline no se pierdan al sincronizar.

### Offline-first
Principio de diseño donde la aplicación funciona completamente sin conexión a internet. En PILAR se implementa con `brick_offline_first_with_supabase`: todos los datos se almacenan localmente en SQLite y se sincronizan con PostgreSQL cuando hay conectividad. Los widgets leen SIEMPRE de SQLite local (nunca directamente de Supabase). La cola de documentos encola las operaciones localmente y las procesa cuando hay conexión, con reintentos automáticos.

### RLS (Row Level Security)
**Row Level Security** — Característica de PostgreSQL que aplica políticas de acceso a nivel de fila. En PILAR TODAS las tablas tienen RLS habilitado y políticas que filtran por `empresa_id`. Esto garantiza el aislamiento entre tenants a nivel de base de datos, no solo a nivel de aplicación. Un usuario autenticado solo puede ver y modificar datos de su propia empresa, aunque comparta el mismo esquema PostgreSQL con otros tenants.

### private.get_empresa_id()
Función PostgreSQL cacheada (`STABLE SECURITY DEFINER`) que extrae el `empresa_id` del JWT del usuario autenticado. Se usa en TODAS las políticas RLS del sistema:
```sql
USING (empresa_id = (SELECT private.get_empresa_id()))
```
El uso de `(SELECT ...)` (en lugar de llamar la función directamente) permite que PostgreSQL optimice la consulta cacheando el resultado. **Nunca** se usa parsing inline del JWT en las policies — siempre a través de esta función.

### Módulo Infraestructura
Categoría de módulos siempre activos y no desactivables por empresa. Proveen la base del sistema: dashboard con KPIs configurables por rol, administración de empresa y usuarios, y comunicación interna con notificaciones multicanal. Auth (Supabase Auth) y Catálogos (seed data SQL) son servicios de plataforma, no módulos.

### Módulo Core
Categoría de módulos que constituyen el backbone del ERP. Proveen servicios a otros módulos vía Module Service Bus. Son activables por empresa según el plan SaaS contratado, pero una vez activos exponen sus funciones gateway en `module_bus.*`.

### Módulo Auxiliar
Categoría de módulos que consumen servicios de los módulos Core. Son activables por empresa. La regla fundamental: **nunca hacen INSERT directo en tablas Core** — toda escritura cross-módulo pasa por `module_bus.*`.

### PilarShell
Framework de UI unificado que implementa el layout adaptativo de PILAR. Construido sobre `fluent_ui`: internamente usa `NavigationView` con `PaneDisplayMode.auto` que adapta la navegación automáticamente al tamaño de pantalla. Compuesto por `FluentApp.router → NavigationView(appBar + pane + content)`. El contenido de cada pantalla se sirve vía `GoRouter` con `ShellRoute` en el `paneBodyBuilder`. Vive en `lib/core/shell/`.

### PilarNavigation
La navegación de PILAR usa directamente el `NavigationPane` de fluent_ui, sin un widget custom `PilarNavigation`. Estructura: `PaneItem` para ítems simples, `PaneItemExpander` para grupos con sub-ítems (ej: Administración), `PaneItemSeparator` y `PaneItemAction` en `footerItems` (Salir). `PaneDisplayMode.auto` adapta el layout automáticamente: `expanded` (sidebar, ≥1008px), `compact` (rail de iconos, 641-1007px), `minimal` (hamburguesa/drawer, ≤640px). El índice seleccionado se calcula mapeando la ruta go_router actual.

### COMPACT / MEDIUM / EXPANDED / LARGE
Los cuatro breakpoints responsive de PILAR. `NavigationView` de fluent_ui maneja el layout de navegación automáticamente; `LayoutBuilder` dentro de cada pantalla adapta la visualización de datos:

| Breakpoint | Ancho | PaneDisplayMode | Visualización de listas |
|-----------|-------|-----------------|------------------------|
| COMPACT | < 600px | `minimal` (hamburguesa) | `ListView` con cards — NUNCA `GridView` |
| MEDIUM | 600–840px | `compact` (solo iconos) | `ListView` con cards o 2 columnas máximo |
| EXPANDED | 840–1200px | `expanded` (sidebar) | `SfDataGrid` |
| LARGE | > 1200px | `expanded` (sidebar) | `SfDataGrid` + panel detalle opcional |

`FluentThemeData(typography: ..apply(fontSizeFactor: factor))` ajusta la escala tipográfica por dispositivo.

### WorkspaceTabs
Paradigma de trabajo multi-tab de PILAR, implementado sobre el `TabView` de fluent_ui. Permite tener múltiples registros abiertos simultáneamente: clic en una fila de lista abre un tab de edición; `+ Nuevo` abre un tab de creación. Atajos de teclado nativos de `TabView`: `Ctrl+T` (nuevo tab), `Ctrl+W` / `Ctrl+F4` (cerrar tab), `Ctrl+1–8` (navegar a tab N), `Ctrl+9` (último tab). Los tabs se pueden reordenar con drag. Vive en `lib/core/widgets/workspace_tabs.dart` como wrapper sobre `TabView`.

---

## Stack Técnico

### fluent_ui
Librería Flutter que implementa el **Fluent Design System** de Microsoft (Windows 11). Es el sistema de diseño UI principal de PILAR. Proporciona el shell completo del ERP: `NavigationView` para el layout adaptativo, `TabView` para multi-documento, `MenuBar`/`CommandBar` para acciones de módulo, y `FluentThemeData` para temas configurables por empresa. Funciona en las 6 plataformas (Web, iOS, Android, Windows, macOS, Linux) sin modificaciones. Ver ADR-004.

### FluentApp / FluentThemeData
`FluentApp` es el widget raíz de la aplicación, equivalente a `MaterialApp`. `FluentThemeData` configura el tema visual completo: `accentColor` (personalizable por empresa), `typography` (escalable con `fontSizeFactor`), `brightness` (light/dark/system), `visualDensity`. Se accede al tema desde cualquier widget con `FluentTheme.of(context)` — **nunca** con `Theme.of(context)`.

### NavigationView / NavigationPane
Componentes centrales del shell de PILAR. `NavigationView` es el contenedor principal (equivalente a `Scaffold` en Material). `NavigationPane` define la estructura de navegación con `items` (principales) y `footerItems` (configuración/logout). `PaneDisplayMode.auto` adapta el layout automáticamente: `expanded` (≥1008px), `compact` (641–1007px), `minimal` (≤640px). Items anidables con `PaneItemExpander` para grupos de módulos.

### TabView (fluent_ui)
Componente de fluent_ui que implementa navegación por pestañas estilo navegador, usado en PILAR para el paradigma WorkspaceTabs. Cada `Tab` puede tener icono, título y widget de contenido independiente. Soporta apertura, cierre, reorden por drag y atajos de teclado nativos (`Ctrl+T/W/1-9`). Configuración: `minTabWidth`, `maxTabWidth`, `closeButtonVisibility`, `onNewPressed`.

### ScaffoldPage / PageHeader / CommandBar
Estructura estándar de una pantalla en fluent_ui. `ScaffoldPage` es el equivalente al body de un Scaffold, con padding y scroll gestionados. `PageHeader` muestra el título de la pantalla y opcionalmente un `CommandBar` con acciones primarias (botones con icono+texto) y secundarias (en desbordamiento). `CommandBarButton` es el componente de acción estándar.

### ContentDialog / FlyoutTarget
`ContentDialog` es el diálogo modal de fluent_ui, reemplaza al `AlertDialog` de Material. Tiene `title`, `content` y `actions` (lista de botones). `FlyoutTarget` + `MenuFlyout` implementan menús contextuales y dropdowns: el target envuelve el widget que dispara el flyout; el flyout puede contener `MenuFlyoutItem`, `MenuFlyoutSubItem` y `MenuFlyoutSeparator`. `showDialog<T>()` con `builder: (ctx) => ContentDialog(...)` es el patrón estándar.

### FluentIcons / WindowsIcons
Conjuntos de iconos incluidos en fluent_ui. `FluentIcons` contiene ~5000 iconos del Fluent Design System de Microsoft (ej: `FluentIcons.receipt`, `FluentIcons.add`, `FluentIcons.search`). `WindowsIcons` contiene ~1500 iconos específicos de Windows. En PILAR se usa exclusivamente `FluentIcons.*` — nunca `Icons.*` de Material.

### Acrylic / Mica
Efectos visuales de superficie del Fluent Design System. `Acrylic` aplica un efecto de desenfoque gaussiano (`BackdropFilter`) que simula vidrio translúcido — se usa en paneles y sidebars en desktop. `Mica` es un efecto más sutil basado en el color de fondo del sistema. **Importante**: Acrylic usa `BackdropFilter` que es costoso en GPU; en PILAR se desactiva en iOS/Android y se reemplaza por un color sólido con `FluentTheme.of(context).micaBackgroundColor`.

### SfDataGridTheme (integración fluent_ui + Syncfusion)
Mecanismo para conectar el tema de fluent_ui con Syncfusion DataGrid. `SfDataGridTheme` envuelve a `SfDataGrid` y acepta `SfDataGridThemeData` con colores explícitos. Patrón estándar en PILAR:
```dart
final accent = FluentTheme.of(context).accentColor
    .defaultBrushFor(FluentTheme.of(context).brightness);
SfDataGridTheme(
  data: SfDataGridThemeData(
    headerColor: accent.withValues(alpha: 0.2),
    selectionColor: accent.withValues(alpha: 0.1),
  ),
  child: SfDataGrid(...),
)
```

### Brick ORM
Librería Dart `brick_offline_first_with_supabase` que implementa el patrón offline-first. Los modelos se decoran con `@ConnectOfflineFirstWithSupabase` y Brick genera automáticamente los adapters para SQLite (local) y Supabase (remoto). Los widgets leen siempre de SQLite mediante `BrickDataProvider<T>` y Brick sincroniza en background. Soporta subscriptions reactivas vía `subscribeToRealtime`.

### BrickDataProvider
Clase de Brick que expone los datos locales de SQLite como stream reactivo. Los widgets de Flutter suscriben a `BrickDataProvider<T>.subscribe(query)` o `subscribeToRealtime(query)` para recibir actualizaciones automáticas sin llamar directamente a Supabase. Es la única forma correcta de leer datos en los widgets de PILAR — nunca `supabase.from('tabla').select()` directamente.

### Supabase Realtime
Sistema de WebSockets de Supabase que transmite cambios de PostgreSQL en tiempo real a los clientes Flutter. En PILAR se usa para: notificaciones del sistema, actualizaciones de estado en documentos, chat interno y sincronización de cambios entre dispositivos del mismo usuario. Implementado a través de Brick con `subscribeToRealtime`.

### pgvector
Extensión de PostgreSQL que añade soporte para vectores de alta dimensión y búsqueda por similitud. En PILAR se usa para almacenar embeddings de entidades del sistema (tipo `VECTOR(1536)`), búsqueda semántica y cálculo de similitud para recomendaciones. Los embeddings se generan en Edge Functions con modelos de lenguaje de largo alcance y se almacenan en tablas con índices `ivfflat` o `hnsw`.

### Edge Function (Deno/TypeScript)
Funciones serverless que corren en el runtime Deno en la infraestructura de Supabase. En PILAR se usan para operaciones que requieren ejecucion server-side: firma digital, generacion de documentos, procesamiento de pagos, reportes y consultas semanticas con pgvector. Se despliegan con `supabase functions deploy <nombre>`. Viven en `supabase/functions/`.

---

## Negocio / ERP

### Multi-tenancy / empresa_id
Arquitectura donde múltiples empresas (tenants) comparten la misma base de datos PostgreSQL pero sus datos están completamente aislados. En PILAR el aislamiento se implementa con `empresa_id UUID` en cada tabla y políticas RLS que filtran por `private.get_empresa_id()`. Un usuario puede tener roles en N empresas distintas (multi-empresa); el `empresa_id` activo se determina por el JWT de la sesión actual.

### BOM (Bill of Materials) / Ensamblaje
**Lista de Materiales** — Especificación jerárquica de los componentes necesarios para producir o ensamblar un producto. En PILAR se implementa BOM multi-nivel: un producto puede tener componentes que a su vez tienen sus propios BOM. Las órdenes de ensamblaje consumen materiales del stock y producen el producto terminado con los movimientos de stock correspondientes.

### Serie / Lote (trazabilidad)
Mecanismos para rastrear productos individuales o grupos de productos a lo largo de la cadena de suministro:
- **Serie**: identificador único por unidad (ej: número de serie de un equipo electrónico). Tabla `producto_series`.
- **Lote**: identificador para un grupo de unidades producidas/recibidas juntas (ej: lote de medicamentos con fecha de vencimiento). Tabla `producto_lotes`.

En PILAR, las devoluciones de productos con serie requieren validar que la serie devuelta corresponde al documento de origen.

### Multi-bodega
Capacidad de gestionar el stock en múltiples ubicaciones físicas. En PILAR cada empresa puede tener N ubicaciones. El stock se controla por ubicación en `<tabla_stock>(<item_id>, <ubicacion_id>, cantidad)`. Las transferencias entre ubicaciones generan documentos de traslado si tienen diferente dirección. Modos: PRINCIPAL (solo ubicación activa), CONSOLIDADO (suma todas), SIN_CONTROL.

### Multi-empaque / presentaciones
Un mismo producto físico puede venderse en diferentes presentaciones con distintas unidades de medida y factores de conversión. Ejemplo: aceite de cocina disponible como unidad (1L), caja (12 unidades) o bidón (20L). En PILAR se implementa con `producto_presentaciones(producto_id, nombre, factor_conversion)` y `producto_codigos_barras` (N códigos por presentación). El POS detecta automáticamente la presentación escaneando el código de barras.

### CxC (Cuentas por Cobrar) / CxP (Cuentas por Pagar)
Registros de deudas de clientes (CxC) y deudas con proveedores (CxP). En PILAR se generan automáticamente al confirmar documentos de venta o compra. Soportan cobros/pagos mixtos (múltiples formas de pago en una operación) y generan asientos contables automáticamente vía Module Service Bus.

### Asiento contable
Registro de doble partida que documenta una transacción económica. Cada asiento tiene una o más líneas con cuenta débito/crédito, monto y descripción. En PILAR la tabla principal es `<tabla_asientos>` con sus líneas en `<tabla_lineas_asiento>`. Los asientos se generan automáticamente desde los módulos que producen transacciones económicas vía `module_bus.<modulo>.create_journal_entry()`. Un trigger de secuencia asigna el número secuencial al aprobar.

### Plan de cuentas (NIIF PYMES)
Estructura jerárquica de cuentas contables adaptada a las Normas Internacionales de Información Financiera para Pequeñas y Medianas Entidades (IFRS for SMEs). En PILAR se carga como seed data con `create_niif_pymes_chart_of_accounts()` al crear una empresa. La tabla `cuentas_contables` tiene estructura de árbol con `cuenta_padre_id` y campo `tipo` (ACTIVO, PASIVO, PATRIMONIO, INGRESO, GASTO, COSTO). Las localizaciones country-specific pueden extender o reemplazar el plan de cuentas base.

### Centro de costo
Unidad de análisis que agrupa costos e ingresos para medir la rentabilidad de áreas, proyectos o departamentos específicos, sin afectar el plan de cuentas principal. En PILAR la tabla `centros_costo` tiene estructura jerárquica. Las líneas de asiento (`asiento_lineas`) pueden vincularse opcionalmente a un `centro_costo_id`, permitiendo reportes de rentabilidad por área.

### Conciliación bancaria
Proceso de verificar que los movimientos registrados en el sistema coincidan con los extractos del banco. En PILAR se gestionan `conciliaciones_bancarias` con dos fuentes: movimientos del sistema (`movimientos_bancarios`) y líneas del extracto bancario (importadas desde CSV). La auto-conciliación cruza por monto y fecha; las diferencias quedan como ítems pendientes para revisión manual.

### Caja chica / Fondo a rendir
Dos modalidades de manejo de efectivo menor:
- **Caja chica (Fondo fijo)**: monto establecido que se repone periódicamente. El custodio gasta y presenta comprobantes; el área responsable repone el monto gastado.
- **Fondo a rendir**: el empleado solicita un monto, lo recibe como anticipo, gasta y luego presenta los comprobantes. La diferencia se devuelve o se cobra.

En PILAR ambas modalidades tienen aprobación de 2 pasos y generan asientos contables automáticos.

### RMA (Return Merchandise Authorization)
**Autorización de Devolución de Mercadería** — Proceso formal para gestionar devoluciones de productos de clientes. En PILAR se gestionan las `solicitudes_rma` con evidencia fotográfica/de video, evaluación técnica y resoluciones: reparar, reemplazar, emitir nota de crédito, devolver al proveedor o dar de baja (scrap). Actúa como módulo puente entre los módulos que gestionan transacciones comerciales.

### POS (Point of Sale)
**Punto de Venta** — Sistema de operaciones de venta directa. En PILAR el módulo de POS soporta múltiples modos de operación según el tipo de negocio (flujo rápido de autoservicio, multi-vendedor departamental, pre-venta con despacho). Las sesiones son pausables, funciona offline, soporta promociones automáticas y controla stock por ubicación predeterminada.

### Pipeline CRM
Representación visual del proceso comercial como un conjunto de etapas secuenciales (Kanban). En PILAR se gestionan `oportunidades` que avanzan por `etapas_pipeline` (Prospecto → Calificado → Propuesta → Negociación → Cerrado Ganado/Perdido). Cada empresa puede configurar sus propias etapas y probabilidades de cierre.

### Lead scoring
Puntuación automática de prospectos/oportunidades basada en múltiples factores: industria, tamaño de empresa, interacciones previas, comportamiento en canales digitales, solvencia crediticia. En PILAR el score se calcula usando modelos de machine learning con pgvector y guía al vendedor para priorizar el tiempo con las oportunidades de mayor probabilidad de cierre.

### Timesheet
Registro del tiempo dedicado por empleados o técnicos a proyectos, órdenes de reparación u órdenes de campo. En PILAR los timesheets se integran con el módulo de recursos humanos para el cálculo de horas extras y con el módulo contable para el costeo real de proyectos.

---

> Términos de localización específicos de cada país o región son responsabilidad del módulo de localización correspondiente.
