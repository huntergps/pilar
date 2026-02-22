# pubspec.yaml de referencia — PILAR ERP

`pubspec.yaml` canónico para el proyecto Flutter de PILAR ERP. Incluye todos los paquetes confirmados en la arquitectura con sus versiones y justificación.

> **Nota:** Este archivo es la referencia de diseño. Las versiones se deben verificar en [pub.dev](https://pub.dev) antes de iniciar el proyecto, ya que los paquetes se actualizan frecuentemente.

---

## pubspec.yaml completo

```yaml
name: pilar_erp
description: PILAR ERP — Sistema SaaS ERP multi-tenant con facturación electrónica.
publish_to: none   # No publicar en pub.dev; es aplicación privada

# Versión: MAYOR.MENOR.PATCH+BUILD_NUMBER
# BUILD_NUMBER es inyectado automáticamente por Codemagic CI
version: 1.0.0+1

environment:
  sdk: ">=3.3.0 <4.0.0"
  flutter: ">=3.22.0"

# ===========================================================
# DEPENDENCIAS DE PRODUCCIÓN
# ===========================================================
dependencies:
  flutter:
    sdk: flutter
  flutter_localizations:
    sdk: flutter

  # -----------------------------------------------------------
  # SUPABASE — Backend BaaS
  # supabase_flutter: cliente oficial para Flutter (Auth + DB + Storage + Realtime)
  # supabase_auth_ui: widgets de login/registro preconstruidos con branding
  # -----------------------------------------------------------
  supabase_flutter: ^2.5.0
  supabase_auth_ui: ^0.4.0      # SupaEmailAuth, SupaSocialsAuth, SupaMagicAuth, SupaResetPassword

  # -----------------------------------------------------------
  # ESTADO — Riverpod 2.x
  # flutter_riverpod: integración Riverpod con Flutter (Consumer, ProviderScope, etc.)
  # riverpod_annotation: anotaciones @riverpod para generación de código
  # hooks_riverpod: opcional, para usar HookConsumerWidget con flutter_hooks
  # -----------------------------------------------------------
  flutter_riverpod: ^2.5.1
  riverpod_annotation: ^2.3.5

  # -----------------------------------------------------------
  # NAVEGACIÓN — go_router
  # go_router: enrutador declarativo con soporte para ShellRoute (PilarShell)
  # Compatible con deep linking, web URLs y navegación anidada
  # -----------------------------------------------------------
  go_router: ^14.2.0

  # -----------------------------------------------------------
  # OFFLINE-FIRST — Brick ORM
  # brick_offline_first_with_supabase: sincronización SQLite ↔ Supabase
  # brick_sqlite: capa SQLite local (SqliteProvider)
  # brick_supabase: capa Supabase remota (SupabaseProvider)
  # sqflite: driver SQLite subyacente (dependencia de brick_sqlite)
  # -----------------------------------------------------------
  brick_offline_first_with_supabase: ^3.4.0
  brick_sqlite: ^3.2.0
  brick_supabase: ^3.2.0
  sqflite: ^2.3.3+1             # SQLite driver; no usar sqflite_common_ffi en mobile

  # -----------------------------------------------------------
  # UI — fluent_ui (Fluent Design System — Windows 11 / Microsoft)
  # Framework UI principal del proyecto. Proporciona:
  #   NavigationView + NavigationPane: shell adaptativo (expanded/compact/minimal/top)
  #   TabView: multi-documento (facturas, órdenes, etc.) con Ctrl+T/W/Tab
  #   MenuBar + CommandBar: menús horizontales estilo Office para desktop
  #   ScaffoldPage + PageHeader: estructura de pantalla con comandos integrados
  #   ContentDialog + FlyoutTarget + MenuFlyout: diálogos y overlays
  #   TextBox, ComboBox, AutoSuggestBox, NumberBox, PasswordBox: inputs
  #   DatePicker, TimePicker, CalendarDatePicker, ColorPicker: pickers
  #   Checkbox, RadioButton, ToggleSwitch, Slider, RatingControl: controles
  #   Card, Acrylic, Mica, Expander, InfoBar: superficies y contenedores
  #   FluentIcons: ~5000 iconos + WindowsIcons: ~1500 iconos de Windows
  #   FluentThemeData: tema con accentColor, typography, visualDensity, dark/light
  #   Funciona en iOS/Android/Web/Desktop sin modificaciones (verificado en producción)
  # -----------------------------------------------------------
  fluent_ui: ^4.14.0

  # -----------------------------------------------------------
  # UI — Desktop (Window management — solo Windows/macOS/Linux)
  # window_manager: guardar/restaurar posición y tamaño de ventana entre sesiones
  # flutter_acrylic: efecto Acrylic/Mica de Windows 11 en la ventana principal
  # system_theme: leer el accent color del sistema operativo (Windows/macOS)
  # -----------------------------------------------------------
  window_manager: ^0.5.0
  flutter_acrylic: ^1.0.0+2
  system_theme: ^3.1.2

  # -----------------------------------------------------------
  # UI — Syncfusion (publisher oficial: pub.dev/publishers/syncfusion.com/packages)
  # MANDATORIO: usar ÚNICAMENTE paquetes del publisher oficial syncfusion.com
  # Licencia Community gratuita para ingresos <$1M USD/año
  # Todos los paquetes en la misma versión (sincronización obligatoria)
  #
  # syncfusion_flutter_core: dependencia base de todos los paquetes Syncfusion
  # syncfusion_flutter_datagrid: DataGrid con virtualización, edición inline, sorting, agrupación
  # syncfusion_flutter_charts: gráficos para dashboards (SfCartesianChart, SfCircularChart, etc.)
  # syncfusion_flutter_pdf: generación de PDFs desde Dart (reportes, comprobantes)
  # syncfusion_flutter_pdfviewer: visualizar PDFs dentro de la app (SfPdfViewer)
  # syncfusion_flutter_xlsio: exportación a Excel (reportes, nóminas)
  # syncfusion_flutter_calendar: agenda/calendario — SfCalendar
  # syncfusion_flutter_gauges: gauges radiales y lineales (dashboard metas — SfRadialGauge)
  # syncfusion_flutter_datepicker: date range picker para filtros de reportes (SfDateRangePicker)
  # syncfusion_flutter_signaturepad: firma digital — SfSignaturePad
  # syncfusion_localizations: traducciones ES/en para todos los widgets Syncfusion
  # -----------------------------------------------------------
  syncfusion_flutter_core: ^32.2.5
  syncfusion_flutter_datagrid: ^32.2.5
  syncfusion_flutter_charts: ^32.2.5
  syncfusion_flutter_pdf: ^32.2.5
  syncfusion_flutter_pdfviewer: ^32.2.5
  syncfusion_flutter_xlsio: ^32.2.5
  syncfusion_flutter_calendar: ^32.2.5       # SfCalendar (day/week/month/timeline)
  syncfusion_flutter_gauges: ^32.2.5         # Dashboard: SfRadialGauge
  syncfusion_flutter_datepicker: ^32.2.5     # Filtros de reportes: SfDateRangePicker
  syncfusion_flutter_signaturepad: ^32.2.5   # Firma digital: SfSignaturePad
  syncfusion_localizations: ^32.2.5

  # -----------------------------------------------------------
  # FORMULARIOS
  # flutter_form_builder: formularios declarativos con 20+ tipos de campo
  # form_builder_validators: validadores reutilizables (required, email, minLength, etc.)
  # -----------------------------------------------------------
  flutter_form_builder: ^10.0.1
  form_builder_validators: ^11.0.0

  # -----------------------------------------------------------
  # PRECISIÓN NUMÉRICA — CRÍTICO para montos financieros
  # decimal: aritmética exacta de punto fijo para montos y cantidades
  # NUNCA usar double para dinero; siempre Decimal(montos) o usar DECIMAL en SQL
  # -----------------------------------------------------------
  decimal: ^2.3.3

  # -----------------------------------------------------------
  # INTERNACIONALIZACIÓN
  # intl: formato de fechas, monedas y números según locale (es_EC)
  # -----------------------------------------------------------
  intl: ^0.19.0

  # -----------------------------------------------------------
  # PERSISTENCIA LOCAL (preferencias UI)
  # shared_preferences: persistir preferencias del usuario (tema, locale, config)
  # Usado por: accentColor, themeMode, tamaño de fuente, anchos de columnas DataGrid,
  #            sorting persistente en grillas, flavor seleccionado
  # -----------------------------------------------------------
  shared_preferences: ^2.2.3

  # -----------------------------------------------------------
  # ARCHIVOS Y MULTIMEDIA
  # image_picker: capturar fotos/videos (evidencia, fotos de perfil)
  # file_picker: importar archivos (XMLs, CSVs, PDFs)
  # url_launcher: abrir PDFs en navegador, links externos
  # path_provider: acceso a directorios del sistema de archivos
  # path: utilidades para manipular rutas de archivos
  # -----------------------------------------------------------
  image_picker: ^1.1.2
  file_picker: ^8.0.7
  url_launcher: ^6.3.0
  path_provider: ^2.1.3
  path: ^1.9.0

  # -----------------------------------------------------------
  # RED Y CONECTIVIDAD
  # connectivity_plus: detectar cambio de conectividad (wifi/mobile/none)
  # Usado por: monitor de sincronización offline-first
  # -----------------------------------------------------------
  connectivity_plus: ^6.0.3

  # -----------------------------------------------------------
  # MONITOREO DE ERRORES
  # sentry_flutter: captura de errores en producción con contexto Flutter
  # Alternativa a Firebase Crashlytics (no usamos Firebase en PILAR)
  # -----------------------------------------------------------
  sentry_flutter: ^8.3.0

  # -----------------------------------------------------------
  # INFORMACIÓN DE LA APP
  # package_info_plus: obtener versión, build number, nombre del paquete
  # Usado en: pantalla "Acerca de", headers HTTP, reportes de error
  # -----------------------------------------------------------
  package_info_plus: ^8.0.2

  # -----------------------------------------------------------
  # UTILIDADES DE FECHA Y HORA
  # timezone: manejo de zonas horarias (base de datos IANA completa)
  # Todas las timestamps se guardan en UTC en Supabase; se convierten en Flutter
  # -----------------------------------------------------------
  timezone: ^0.9.4

  # -----------------------------------------------------------
  # CODIFICACIÓN / CRIPTOGRAFÍA
  # crypto: hashing SHA-256 para verificar integridad de documentos localmente
  # convert: utilidades base64, hex, utf8 para manejo de certificados y documentos
  # -----------------------------------------------------------
  crypto: ^3.0.3
  convert: ^3.1.1

  # -----------------------------------------------------------
  # IMPRESIÓN
  # printing: imprimir PDFs generados con syncfusion_flutter_pdf
  # Usado por: tickets, comprobantes, reportes en PDF
  # -----------------------------------------------------------
  printing: ^5.13.1

  # -----------------------------------------------------------
  # CÓDIGO DE BARRAS / QR
  # mobile_scanner: escaneo de códigos de barras
  # qr_flutter: generación de QR para comprobantes y documentos
  # -----------------------------------------------------------
  mobile_scanner: ^5.2.3
  qr_flutter: ^4.1.0

  # -----------------------------------------------------------
  # ICONOS Y ASSETS
  # flutter_svg: renderizar iconos SVG (logos, iconos de módulos)
  # cached_network_image: caché de imágenes de red (fotos productos, empleados)
  # -----------------------------------------------------------
  flutter_svg: ^2.0.10+1
  cached_network_image: ^3.3.1

  # -----------------------------------------------------------
  # LAYOUT AVANZADO
  # two_dimensional_scrollables: scroll en 2 dimensiones (tablas complejas)
  # Complementa SfDataGrid para casos con scroll horizontal + vertical anidado
  # -----------------------------------------------------------
  two_dimensional_scrollables: ^0.3.0

  # -----------------------------------------------------------
  # NOTIFICACIONES LOCALES
  # flutter_local_notifications: notificaciones push locales (alertas sync, recordatorios)
  # Usado por: recordatorios y alertas de vencimiento
  # -----------------------------------------------------------
  flutter_local_notifications: ^17.2.2

  # -----------------------------------------------------------
  # LOGGING
  # logger: logging estructurado con niveles (DEBUG/INFO/WARNING/ERROR)
  # Reemplaza print(); desactivado en producción
  # -----------------------------------------------------------
  logger: ^2.4.0

  # -----------------------------------------------------------
  # COLECCIONES Y UTILIDADES
  # collection: utilidades para listas/mapas (groupBy, sorted, etc.)
  # equatable: comparación de objetos por valor (para Riverpod y tests)
  # freezed_annotation: data classes inmutables con copyWith, equality, JSON
  # json_annotation: serialización JSON para modelos que no usan Brick
  # -----------------------------------------------------------
  collection: ^1.18.0
  equatable: ^2.0.5
  freezed_annotation: ^2.4.4
  json_annotation: ^4.9.0

# ===========================================================
# DEPENDENCIAS DE DESARROLLO
# ===========================================================
dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0         # Reglas de linting oficiales de Flutter

  # -----------------------------------------------------------
  # GENERACIÓN DE CÓDIGO
  # build_runner: ejecutor de generadores de código
  # riverpod_generator: genera providers desde @riverpod
  # brick_build: genera adapters SQLite/Supabase desde modelos @ConnectOfflineFirstWithSupabase
  # freezed: genera data classes inmutables desde @freezed
  # json_serializable: genera fromJson/toJson desde @JsonSerializable
  # -----------------------------------------------------------
  build_runner: ^2.4.11
  riverpod_generator: ^2.4.3
  brick_build: ^3.2.0
  freezed: ^2.5.2
  json_serializable: ^6.8.0

  # -----------------------------------------------------------
  # TESTING
  # mockito: generación de mocks para tests unitarios
  # mocktail: alternativa a mockito sin generación de código (más simple)
  # fake_async: simulación de tiempo en tests (crons, debounce, timeouts)
  # -----------------------------------------------------------
  mockito: ^5.4.4
  mocktail: ^1.0.4
  fake_async: ^1.3.1

  # -----------------------------------------------------------
  # INTEGRATION TESTING
  # integration_test: tests de integración ejecutados en dispositivo/emulador
  # patrol: framework avanzado de integration testing para Flutter
  # -----------------------------------------------------------
  integration_test:
    sdk: flutter
  patrol: ^3.10.0

# ===========================================================
# FLUTTER — Configuración de plataforma
# ===========================================================
flutter:
  # uses-material-design: true es necesario aunque el sistema UI sea fluent_ui,
  # porque Syncfusion Flutter utiliza Material widgets internamente (SfDataGrid,
  # SfCalendar, etc. renderizan con ThemeData via SfDataGridTheme/SfChartTheme).
  uses-material-design: true

  # Assets del proyecto
  assets:
    - assets/images/           # Logos, imágenes estáticas
    - assets/icons/            # Iconos SVG de la aplicación
    - assets/fonts/            # Fuentes personalizadas (si no se usan Google Fonts)
    - assets/xsd/              # Esquemas XSD para validación offline de documentos
    - assets/flavors/          # Assets específicos por flavor (logo, splash)

  # Tipografía
  # PILAR usa Inter como fuente principal (legibilidad en pantallas de datos)
  fonts:
    - family: Inter
      fonts:
        - asset: assets/fonts/Inter-Regular.ttf
          weight: 400
        - asset: assets/fonts/Inter-Medium.ttf
          weight: 500
        - asset: assets/fonts/Inter-SemiBold.ttf
          weight: 600
        - asset: assets/fonts/Inter-Bold.ttf
          weight: 700

  # Flavors Flutter
  # Cada flavor tiene su propio main_<flavor>.dart y configuración nativa
  # Ver lib/flavors/flavor_config.dart para la configuración en Dart
```

---

## Comandos de mantenimiento

```bash
# Instalar dependencias
flutter pub get

# Actualizar dependencias a la última versión compatible
flutter pub upgrade

# Ver dependencias desactualizadas
flutter pub outdated

# Generar código (Riverpod + Brick + Freezed + json_serializable)
flutter pub run build_runner build --delete-conflicting-outputs

# Generar código en modo watch (desarrollo)
flutter pub run build_runner watch --delete-conflicting-outputs

# Linting
flutter analyze

# Formato de código
dart format lib/ test/

# Tests unitarios con cobertura
flutter test --coverage

# Tests de integración (requiere emulador o dispositivo)
flutter test integration_test/
```

---

## Notas de versiones

### Paquetes con versiones fijadas (razones)

| Paquete | Razón del pin de versión |
|---------|--------------------------|
| `syncfusion_flutter_*: ^32.2.x` | Todos los paquetes Syncfusion deben usar la misma versión principal para evitar conflictos de licencia y API |
| `brick_*: ^3.x` | Las versiones de `brick_offline_first_with_supabase`, `brick_sqlite` y `brick_supabase` deben ser compatibles entre sí |
| `riverpod_annotation` + `riverpod_generator` | Deben ser la misma versión menor para que la generación de código funcione correctamente |
| `freezed` + `freezed_annotation` | Deben mantener compatibilidad; siempre actualizar juntos |
| `json_serializable` + `json_annotation` | Idem; actualizar juntos |

### Paquetes excluidos (y por qué)

| Paquete excluido | Razon |
|-----------------|-------|
| `firebase_*` | No usar Firebase; solo Supabase + Cloudflare |
| `flutter_bloc` | Se usa Riverpod 2.x; no mezclar patrones de estado |
| `provider` | Reemplazado completamente por Riverpod |
| `drift` | Reemplazado por Brick ORM (maneja SQLite + sync) |
| `flex_color_scheme` | Reemplazado por fluent_ui (FluentThemeData); incompatible con FluentApp |
| `flex_seed_scheme` | Dependencia de flex_color_scheme; eliminado con él |
| `hive` | Reemplazado por SQLite via Brick; no usar dos almacenamientos locales |
| `get` / `getx` | No usar GetX; incompatible con arquitectura Riverpod |
| `dio` | Supabase Flutter ya incluye http; no agregar cliente HTTP extra |
| `macos_ui` | Solo macOS; fluent_ui cubre las 6 plataformas |
| `shadcn_ui` | Parcialmente compatible; fluent_ui ya cubre todos los componentes necesarios |

### Paquetes condicionales por plataforma

Algunos paquetes tienen limitaciones de plataforma:

```yaml
# mobile_scanner solo funciona en iOS y Android (no web/desktop)
# Para web se puede usar html_qrcode_scanner o la cámara web directamente

# image_picker en web tiene limitaciones (sin cámara nativa)
# En desktop usar file_picker en su lugar

# flutter_local_notifications tiene configuración específica por plataforma
# Requiere configuración en AndroidManifest.xml, Info.plist y AppDelegate
```

---

## Configuracion adicional requerida

### Android — `android/app/build.gradle`

```groovy
android {
    compileSdkVersion 34
    defaultConfig {
        minSdkVersion 21        // Android 5.0+ (Syncfusion requiere 21+)
        targetSdkVersion 34
        multiDexEnabled true    // Necesario por cantidad de dependencias
    }
    // Flavors definidos aquí corresponden a los 3 flavors de Flutter
    flavorDimensions "app"
    productFlavors {
        erp     { dimension "app"; applicationId "com.pilarerp.erp" }
        salon   { dimension "app"; applicationId "com.pilarerp.salon" }
        cliente { dimension "app"; applicationId "com.pilarerp.cliente" }
    }
}
```

### iOS — `ios/Runner/Info.plist`

```xml
<!-- Permisos requeridos -->
<key>NSCameraUsageDescription</key>
<string>PILAR necesita la cámara para fotos de evidencia y escaneo de códigos.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>PILAR necesita acceso a fotos para adjuntar evidencia.</string>
<key>NSPhotoLibraryAddUsageDescription</key>
<string>PILAR guarda PDFs generados en tu galería.</string>
```
