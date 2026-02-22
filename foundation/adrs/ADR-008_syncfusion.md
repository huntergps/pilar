# ADR-008: Syncfusion como Suite de Componentes UI para PILAR ERP

**Estado**: Aceptado
**Fecha**: 2026-02
**Autores**: Arquitecto principal
**Tags**: flutter, ui, componentes, datagrid, charts, pdf, excel, calendario, licencia

---

## Contexto

PILAR ERP requiere componentes UI de alto rendimiento que van más allá de los widgets estándar de Flutter/Material 3. Las necesidades concretas son:

**DataGrid empresarial:**
- Listados con miles de filas (documentos, movimientos, registros contables)
- Edición inline de celdas (ajustes, planillas)
- Agrupación, sorting multi-columna, filtros avanzados, paginación servidor
- Exportación directa a PDF y Excel desde la grilla
- Rendimiento con virtualización: solo renderizar las filas visibles

**Gráficos para dashboards:**
- KPIs con sparklines, barras horizontales, líneas temporales, donuts
- Graficos de análisis (barras + curva acumulada en eje secundario)
- Aging de cuentas (barras apiladas con colores por rango)
- Indicadores de metas (gauge radial)
- Actualización en tiempo real via Supabase Realtime

**Generación de documentos:**
- PDFs desde Dart puro (sin dependencia de server para documentos simples): comprobantes, reportes gerenciales
- Excel: reportes contables, declaraciones pre-armadas, planillas exportables

**Calendario:**
- Agendas con vistas día/semana/mes/timeline
- Drag-and-drop de eventos entre recursos
- Soporte para recursos (personas, equipos como recursos del calendario)

**Widgets especializados:**
- Date range picker para filtros de reportes (período, rango de fechas)
- Gauge radial para indicadores de metas en dashboards
- Signature pad para firma digital del usuario en formularios

**Plataformas objetivo**: Web, iOS, Android, Windows, macOS, Linux — los mismos componentes deben funcionar en las 6 plataformas sin adaptaciones por plataforma.

---

## Decision

Se adopta **Syncfusion Flutter** como la suite exclusiva de componentes UI especializados para PILAR. Se usarán **únicamente** paquetes del publisher oficial [`syncfusion.com`](https://pub.dev/publishers/syncfusion.com/packages) en pub.dev.

### Paquetes adoptados y su uso en PILAR

Todos los paquetes se mantienen en la **misma versión** (actualmente `^32.2.5`). `syncfusion_flutter_core` es la dependencia base y se instala como transitiva de los demás, pero se declara explícitamente para controlar la versión.

| Paquete | Versión | Uso principal en PILAR |
|---------|---------|------------------------|
| `syncfusion_flutter_core` | ^32.2.5 | Dependencia base de todos los paquetes Syncfusion |
| `syncfusion_flutter_datagrid` | ^32.2.5 | Listados CRUD en todos los módulos (`SfDataGrid`) |
| `syncfusion_flutter_charts` | ^32.2.5 | Dashboards: KPIs, tendencias, análisis, aging (`SfCartesianChart`, `SfCircularChart`) |
| `syncfusion_flutter_pdf` | ^32.2.5 | Generación PDFs Dart-side: comprobantes, reportes (`PdfDocument`) |
| `syncfusion_flutter_pdfviewer` | ^32.2.5 | Visualizar PDFs en la app (`SfPdfViewer`) |
| `syncfusion_flutter_xlsio` | ^32.2.5 | Exportar Excel: reportes, declaraciones, planillas (`Workbook`) |
| `syncfusion_flutter_calendar` | ^32.2.5 | Agendas multi-recurso (`SfCalendar`) |
| `syncfusion_flutter_gauges` | ^32.2.5 | Indicadores de metas en dashboards (`SfRadialGauge`) |
| `syncfusion_flutter_datepicker` | ^32.2.5 | Filtros de período en reportes y búsquedas (`SfDateRangePicker`) |
| `syncfusion_flutter_signaturepad` | ^32.2.5 | Firma digital del usuario en formularios (`SfSignaturePad`) |
| `syncfusion_localizations` | ^32.2.5 | Traducciones ES/en de todos los widgets anteriores |

### Licencia

Syncfusion ofrece una **Licencia Community gratuita** para:
- Ingresos de la empresa < USD 1.000.000 al año, **Y**
- Equipo de desarrollo < 5 personas

Para PILAR en fase de desarrollo inicial y para clientes PyME que adquieran una licencia de PILAR para uso interno, aplica la licencia Community. El equipo de PILAR debe adquirir una licencia comercial en cuanto supere cualquiera de los dos umbrales.

La clave de licencia se configura en `main.dart` antes de `runApp()`:

```dart
// lib/main_erp.dart (y main_negocio.dart, main_cliente.dart)
import 'package:syncfusion_flutter_core/core.dart';

void main() {
  SyncfusionLicense.registerLicense(
    const String.fromEnvironment('SYNCFUSION_LICENSE_KEY'),
  );
  runApp(const ProviderScope(child: PilarApp()));
}
```

La clave se inyecta en tiempo de build:
```bash
# Codemagic / CI
flutter build web --dart-define=SYNCFUSION_LICENSE_KEY=$SYNCFUSION_LICENSE_KEY
```

### Regla de versión única

Todos los paquetes Syncfusion deben declararse en la **misma versión** en `pubspec.yaml`. Los paquetes tienen dependencias cruzadas internas a través de `syncfusion_flutter_core`; versiones distintas entre paquetes del mismo release causan conflictos de resolución en `pub`.

```yaml
# CORRECTO — misma versión para todos
syncfusion_flutter_core: ^32.2.5
syncfusion_flutter_datagrid: ^32.2.5
syncfusion_flutter_charts: ^32.2.5
# ...

# INCORRECTO — versiones distintas
syncfusion_flutter_datagrid: ^32.2.5
syncfusion_flutter_charts: ^31.5.0   # ← conflicto garantizado
```

### Convención de uso en PILAR

**DataGrid** — patrón para todos los listados CRUD:

```dart
// Fuente de datos Brick → SfDataGrid (NUNCA Supabase directo)
final registros = ref.watch(miEntidadProvider);

SfDataGrid(
  source: MiEntidadDataSource(registros),
  columns: [
    GridColumn(columnName: 'numero',  label: const Text('Número')),
    GridColumn(columnName: 'fecha',   label: const Text('Fecha')),
    GridColumn(columnName: 'total',   label: const Text('Total')),
    GridColumn(columnName: 'estado',  label: const Text('Estado')),
  ],
  onCellTap: (details) => context.go('/mi-modulo/${registros[details.rowColumnIndex.rowIndex].id}'),
)
```

**Charts** — patrón para KPIs del dashboard:

```dart
SfCartesianChart(
  series: [
    ColumnSeries<MiMetricaMes, String>(
      dataSource: metricasPorMes,
      xValueMapper: (v, _) => v.mes,
      yValueMapper: (v, _) => v.total,
    ),
  ],
)
```

**Calendar** — patrón para agendas multi-recurso:

```dart
SfCalendar(
  view: CalendarView.week,
  dataSource: MisEventosDataSource(eventos),
  resourceViewSettings: const ResourceViewSettings(
    showAvatar: true,
    size: 70,
  ),
  resources: recursos.map((r) => CalendarResource(
    id: r.id,
    displayName: r.nombre,
  )).toList(),
)
```

---

## Alternativas Rechazadas

### 1. fl_chart (gráficos) + data_table_2 o pluto_grid (grilla)

Combinar múltiples librerías de distintos publishers para cubrir las necesidades:
- `fl_chart`: solo gráficos, sin DataGrid, sin PDF, sin Excel
- `data_table_2`: DataGrid básico, sin edición inline, sin exportación
- `pluto_grid`: DataGrid con edición, pero solo funciona en web/desktop (no mobile)

Problemas:
- 4-5 librerías distintas con APIs, temas y ciclos de versión incompatibles
- Cada librería tiene bugs y limitaciones distintas que requieren workarounds propios
- La experiencia visual es inconsistente entre módulos (cada grilla se ve diferente)
- Ninguna alternativa cubre PDF y Excel — requeriría añadir `pdf` (package) + `excel` (package) por separado, con APIs completamente distintas
- **Rechazado por**: fragmentación de dependencias, inconsistencia visual, cobertura incompleta de requisitos

### 2. AG Grid Flutter (web via WebView)

AG Grid es el estándar de grillas en el ecosistema web empresarial (React/Angular). Existe una versión experimental para Flutter via WebView.

- WebView en Flutter tiene problemas de rendimiento en mobile y desktop (no es nativo)
- No existe una API Flutter real de AG Grid — es un wrapper WebView sobre el JS widget
- El comportamiento es diferente por plataforma (scroll, teclado, accesibilidad)
- Pricing: AG Grid Enterprise cuesta desde $1.200 USD/developer/año
- No tiene generación de PDF/Excel nativa en Flutter
- **Rechazado por**: no es nativo Flutter, rendimiento inaceptable en mobile, costo

### 3. Implementación propia de DataGrid

Construir un DataGrid propio con `CustomScrollView`, `SliverList` y widgets Flutter estándar.

- Un DataGrid empresarial con virtualización, sorting multi-columna, agrupación, edición inline y exportación es 6-12 meses de desarrollo solo para ese componente
- Requiere mantener el componente indefinidamente con cada nueva versión de Flutter
- El DataGrid nativo de Flutter (`DataTable`) no tiene virtualización — con 500+ filas se congela
- **Rechazado por**: costo de desarrollo prohibitivo para componente no-core del ERP

### 4. Syncfusion de fuentes no oficiales (forks, mirrors, git dependencies)

Usar `syncfusion_flutter_datagrid` desde un fork en GitHub o desde dependencias `git:` para evitar actualizar la versión.

- Los forks no reciben parches de seguridad ni actualizaciones de Flutter compatibility
- Las dependencias `git:` no participan en la resolución de conflictos de `pub` — pueden romper el árbol de dependencias silenciosamente
- Viola la política de "publisher oficial" establecida en este ADR
- **Rechazado por**: seguridad, mantenibilidad, inconsistencia con la política del proyecto

### 5. Reporting server-side para PDF/Excel (Edge Functions con pdfkit/exceljs)

Generar PDFs y Excels en Edge Functions Deno/TypeScript en lugar de en el cliente Flutter.

- Para documentos que requieren datos ya disponibles en el cliente (ej: reporte de un período ya cargado), añadir un round-trip al servidor introduce latencia innecesaria
- Las Edge Functions se usan para documentos que requieren datos de servidor (documentos autorizados, archivos firmados) — correcto. Pero para reportes ad-hoc del usuario, la generación client-side es más rápida y funciona offline
- **Decisión**: híbrido — documentos que requieren lógica server-side (firma digital, datos de servidor) se generan en Edge Functions; reportes ad-hoc del ERP (balances, movimientos, exportaciones) se generan client-side con `syncfusion_flutter_pdf` y `syncfusion_flutter_xlsio`
- **Rechazado como alternativa exclusiva por**: latencia para reportes ad-hoc, no funciona offline

### 6. Tabla de Syncfusion no oficial (`^26.x` o versiones antiguas)

Usar la versión `26.x` referenciada en documentación antigua.

- La versión actual publicada por `syncfusion.com` en pub.dev es `32.2.5`
- `26.x` no existe en el publisher oficial — fue una referencia incorrecta
- **Rechazado por**: versión inexistente en el publisher oficial

---

## Consecuencias

### Positivas

- **Cobertura completa**: un solo publisher cubre DataGrid + Charts + PDF + Excel + Calendar + Gauges + DatePicker + SignaturePad — sin combinar librerías incompatibles entre sí
- **Consistencia visual**: todos los widgets de Syncfusion comparten el mismo sistema de temas (`SfDataGridTheme`, `SfChartTheme`, etc.) — integración con `fluent_ui` via `FluentTheme.of(context).accentColor` aplicado a `SfDataGridThemeData.headerColor` y `selectionColor`
- **Multi-plataforma real**: todos los paquetes soportan Web, iOS, Android, Windows, macOS, Linux sin adaptaciones específicas por plataforma
- **Virtualización nativa**: `SfDataGrid` renderiza solo las filas visibles — 100.000 filas con el mismo rendimiento que 100
- **Soporte empresarial**: Syncfusion tiene soporte técnico dedicado, documentación exhaustiva y release notes detallados con cada versión Flutter
- **Interoperabilidad**: `SfDataGrid` puede exportar su contenido directamente a `PdfDocument` (syncfusion_flutter_pdf) y `Workbook` (syncfusion_flutter_xlsio) con una API unificada

### Negativas / Restricciones

- **Licencia**: requiere monitorear los umbrales de la licencia Community (ingresos < $1M, equipo < 5). Al superar cualquiera, se debe adquirir licencia comercial antes del lanzamiento público
- **Tamaño del bundle**: añadir los 11 paquetes incrementa el tamaño del APK/IPA/web build. Mitigado con `--split-per-abi` en Android y tree-shaking en web. Los paquetes no usados en un flavor no se incluyen si no se importan
- **`fluent_ui` excluido por decisión de diseño**: `fluent_ui` (Windows-style UI) fue descartado en favor de Material 3 para mantener UI consistente en todas las plataformas con un único sistema de diseño — no por incompatibilidad técnica con Syncfusion. **`fluent_ui` está explícitamente excluido** de PILAR
- **Versión única obligatoria**: todos los paquetes deben actualizarse a la vez. No se puede actualizar solo `syncfusion_flutter_charts` sin actualizar todos los demás — requiere planificar las actualizaciones como un bloque
- **Clave de licencia en CI**: la `SYNCFUSION_LICENSE_KEY` debe gestionarse como secret en Codemagic y GitHub Actions — no commitear en el repositorio

---

## Referencias

- [Publisher oficial syncfusion.com en pub.dev](https://pub.dev/publishers/syncfusion.com/packages)
- [Syncfusion Community License](https://www.syncfusion.com/products/communitylicense)
- [SfDataGrid — documentación oficial](https://help.syncfusion.com/flutter/datagrid/overview)
- [SfCalendar — documentación oficial](https://help.syncfusion.com/flutter/calendar/overview)
- ADR-004 — Flutter single codebase para 6 plataformas (Syncfusion es condición necesaria para que el ADR-004 sea viable: sin componentes multi-plataforma de este nivel, los listados y reportes no serían posibles en todas las plataformas)
