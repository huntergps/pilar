# Architecture Decision Records (ADRs) — PILAR ERP

Los ADRs documentan las decisiones arquitectonicas significativas del proyecto: el contexto que llevo a la decision, las alternativas evaluadas y las consecuencias aceptadas. Son documentos de referencia historica — una vez aceptado, un ADR no se borra; si la decision cambia, se crea un nuevo ADR que lo reemplaza o supera.

---

## Indice

| ADR | Titulo | Estado | Fecha |
|-----|--------|--------|-------|
| [ADR-001](ADR-001_brick-offline-first.md) | Uso de brick_offline_first_with_supabase para Sincronizacion de Datos | Aceptado | 2026-02 |
| [ADR-002](ADR-002_module-service-bus.md) | Module Service Bus para Comunicacion entre Modulos | Aceptado | 2026-02 |
| [ADR-003](ADR-003_rls-pattern.md) | Patron RLS con Funcion Cacheada private.get_empresa_id() | Aceptado | 2026-02 |
| [ADR-004](ADR-004_flutter-single-codebase.md) | Flutter como Único Codebase para 6 Plataformas + fluent_ui como Sistema de Diseño | Aceptado | 2026-02 |
| [ADR-005](ADR-005_no-firebase-si-supabase.md) | Supabase + Cloudflare Pages en lugar de Firebase | Aceptado | 2026-02 |
| [ADR-006](ADR-006_compliance-como-extension.md) | Compliance de Pais como Extension — Foundation Country-Agnostic | Aceptado | 2026-02 |
| [ADR-007](ADR-007_pg-cron-pgmq.md) | Procesamiento Asincrono con pg_cron y pgmq (Supabase-native) | Aceptado | 2026-02 |
| [ADR-008](ADR-008_syncfusion.md) | Syncfusion como Suite de Componentes UI para PILAR ERP | Aceptado | 2026-02 |
| [ADR-009](ADR-009_sistema-modular.md) | Sistema Modular — Activacion por Empresa con Dependencias y Registry Compilado | Aceptado | 2026-02 |

---

## Resumen de Decisiones

### ADR-001 — Brick Offline-First

Uso de `brick_offline_first_with_supabase` en lugar de llamadas directas a Supabase o almacenamiento local con Hive/Isar. Los widgets leen exclusivamente de SQLite local; la sincronizacion con PostgreSQL es automatica y bidireccional. Estrategias de conflicto: bloqueo optimista con `version` (documentos criticos), LWW+merge (maestros), append-only (transacciones), suma-delta (cantidades agregadas).

### ADR-002 — Module Service Bus

Schema `module_bus` con funciones gateway como intermediarios entre modulos Auxiliares y Core. Las funciones verifican si el modulo destino esta activo; si no lo esta, retornan NULL (NO-OP) en lugar de error. Permite empresas con solo un subconjunto de modulos activos sin romper los demas.

### ADR-003 — Patron RLS

Todas las tablas usan `private.get_empresa_id()` — funcion `STABLE` que cachea el parsing del JWT y se ejecuta una vez por transaccion, no una vez por fila. El patron obligatorio es `USING (empresa_id = (SELECT private.get_empresa_id()))` con la subquery wrapping.

### ADR-004 — Flutter Single Codebase + fluent_ui

Un solo codebase Dart para Web, iOS, Android, Windows, macOS y Linux. Sistema de diseño: **fluent_ui** (Fluent Design System de Windows 11) — `NavigationView` + `TabView` + `MenuBar` + `FluentThemeData`. `PaneDisplayMode.auto` adapta la navegación a todos los tamaños de pantalla sin código adicional. Para listas de datos: `SfDataGrid` en pantallas >800px, `ListView` con cards en <800px via `LayoutBuilder`; NUNCA `GridView` en pantallas <600px. Integración Syncfusion via `SfDataGridTheme` con colores del `FluentTheme`. Paquetes desktop complementarios: `window_manager`, `flutter_acrylic`, `system_theme`. 3 flavors: `erp`, `negocio`, `cliente`. Material 3 + flex_color_scheme descartados por shell de navegación insuficiente para la complejidad del ERP.

### ADR-005 — Supabase vs Firebase

Supabase en lugar de Firebase por: PostgreSQL (modelo relacional requerido por el ERP), RLS nativo, pgvector para busqueda semantica, costos predecibles, sin vendor lock-in. Cloudflare Pages en lugar de Firebase Hosting por: gratis ilimitado, CDN global, independencia del stack Firebase.

### ADR-006 — Compliance de Pais como Extension

Foundation y los modulos Core son completamente country-agnostic. Todo el compliance especifico de cada pais vive en Extension modules activables por empresa. La firma digital es server-side (Edge Function). Los catalogos de tarifas fiscales son datos en BD con vigencias, no constantes en codigo.

### ADR-007 — pg_cron + pgmq para Jobs Asincronos

Se adoptan pg_cron (jobs programados) y pgmq (colas de mensajes con retry) como unica solucion de procesamiento asincrono, ambas extensiones nativas de Supabase. Eliminan la necesidad de servicios externos (n8n, Redis, AWS EventBridge). Las colas proveen durabilidad transaccional y retry automatico por visibility timeout.

### ADR-008 — Syncfusion como Suite UI

Se adopta Syncfusion Flutter (publisher oficial `syncfusion.com`) como unica suite de componentes UI especializados: SfDataGrid, SfCartesianChart, SfCalendar, syncfusion_flutter_pdf, syncfusion_flutter_xlsio, SfRadialGauge, SfDateRangePicker, SfSignaturePad y syncfusion_localizations. Todos en version unica `^32.2.5`. Licencia Community gratuita durante el desarrollo inicial.

### ADR-009 — Sistema Modular tipo Odoo

Se implementa un sistema modular de dos capas inspirado en Odoo 18: PostgreSQL gestiona estados de modulos (`uninstalled/installed`), grafo de dependencias (`modulo_dependencias`) y activacion con resolucion automatica (`activate_module()`). Flutter implementa `PilarModule` interface + `ModuleRegistry` compilado + `ModuleSlot` para inyeccion de widgets entre modulos (equivalente a `inherit_id + xpath` de Odoo). Anadir un modulo requiere: clase Dart + registro en `ModuleRegistry` + migracion SQL + INSERT en `modulos`.

---

## Estados Posibles

| Estado | Descripcion |
|--------|-------------|
| **Propuesto** | En discusion, no aprobado aun |
| **Aceptado** | Decision tomada y vigente |
| **Deprecado** | Reemplazado por un ADR mas reciente (se mantiene por historia) |
| **Rechazado** | Propuesta evaluada y descartada |

---

## Como Agregar un Nuevo ADR

1. Crear el archivo `ADR-NNN_nombre-descriptivo.md` (NNN = siguiente numero en secuencia)
2. Usar la siguiente estructura:
   ```markdown
   # ADR-NNN: Titulo

   **Estado**: Propuesto | Aceptado | Deprecado
   **Fecha**: YYYY-MM
   **Autores**: ...
   **Tags**: ...

   ## Contexto
   ## Decision
   ## Alternativas Rechazadas
   ## Consecuencias
   ## Referencias
   ```
3. Agregar la entrada en la tabla de indice de este README
4. Si el ADR reemplaza uno existente, actualizar el estado del ADR anterior a "Deprecado" y agregar una referencia al nuevo ADR

---

## Referencias Cruzadas con la Documentacion

Los ADRs se relacionan con los siguientes documentos de arquitectura en `foundation/`:

- `foundation/arquitectura.md` — implementacion de las decisiones ADR-001, ADR-003, ADR-004
- `foundation/arquitectura-modular.md` — implementacion de la decision ADR-002 y ADR-009
- `foundation/seguridad.md` — implementacion detallada de ADR-003
- `foundation/background-jobs.md` — implementacion completa de ADR-007
