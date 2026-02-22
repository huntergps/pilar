# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Proyecto

**PILAR ERP** — Sistema SaaS ERP para Ecuador con cumplimiento de facturación electrónica SRI. Actualmente en **fase de diseño/documentación**: toda la especificación está en `foundation/` y `modules/`, el código Flutter aún no existe.

## Stack Tecnológico

- **Frontend**: Flutter 3.x (Dart) — un solo codebase para Web/iOS/Android/Desktop
- **State management**: Riverpod 2.x
- **Offline-first**: `brick_offline_first_with_supabase` (SQLite local ↔ PostgreSQL remoto)
- **UI**: `fluent_ui` (FluentApp, NavigationView, FluentThemeData) + Syncfusion (DataGrid, PDF, Charts)
- **Backend**: Supabase (PostgreSQL 15+ con RLS, Auth JWT, Storage, Realtime WebSocket)
- **Edge Functions**: Deno/TypeScript (firma XAdES-BES, SOAP SRI, generación XML/PDF)
- **Externos**: SRI (SOAP), Resend (email), Kushki/Paymentez/PayPhone (pagos), Sentry

## Comandos

### Flutter (cuando exista el proyecto)
```bash
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs  # Genera Brick adapters
flutter test
flutter build web / apk / ipa / windows / macos / linux
```

### Supabase
```bash
# Ensamblar módulos (copia modules/ → foundation/supabase/migrations/mod_*.sql)
./scripts/build-supabase.sh

# CLI siempre desde foundation/ (ahí está config.toml)
cd foundation
supabase start                    # Entorno local
supabase db push                  # Aplicar migraciones
supabase db reset                 # Borrar y re-aplicar todo (dev)
supabase db lint                  # Validar schema
supabase functions deploy <name>
supabase functions serve <name>   # Dev local de Edge Functions
```

## Arquitectura

### Capas
```
Presentación  →  Flutter Screens + Widgets (fluent_ui + Syncfusion)
Estado        →  Riverpod Providers (globales en core/, locales en features/<modulo>/providers/)
Negocio       →  Repositories + Services + Edge Functions (Deno)
Datos         →  brick_offline_first_with_supabase (NUNCA llamar Supabase directamente desde widgets)
DB            →  PostgreSQL + RLS (Supabase managed)
```

### Multi-tenancy
Todas las tablas tienen `empresa_id`. El aislamiento se implementa con Row Level Security:
```sql
-- Patrón obligatorio (usa función cacheada, NO inline JWT parsing):
USING (empresa_id = (SELECT private.get_empresa_id()))
```

### Módulos
- **Infraestructura** (siempre activos, no desactivables): Dashboard, Administración, Comunicación — Auth = servicio Supabase (branding login → Administración); Catálogos = seed data en migraciones SQL; adjuntos/notificaciones/audit trail = servicios de Core Foundation, no módulos
- **Core** (proveen servicios vía Module Service Bus): Facturación, Ventas, Compras, Inventario, Contabilidad, Tesorería, Tributación
- **Auxiliares** (14, consumen servicios, activables por empresa): POS, Ecommerce, RRHH, CRM, Proyectos, Citas/Belleza, Taller, Garantías/RMA, Consumibles, Activos Fijos, Intercompany, Suscripciones, Servicio de Campo, IA/Chat
- Los módulos auxiliares NO escriben directamente en tablas core; usan el **Module Service Bus** (`schema module_bus`) con funciones gateway que verifican si el módulo destino está activo antes de ejecutar.
- El módulo **Facturación** es el SRI compliance layer: cualquier módulo que emita documentos electrónicos (01/03/04/05/06/07) llama a `module_bus.facturacion.queue_sri_document()` o `module_bus.facturacion.create_invoice()`

### PilarShell (layout adaptativo)
Framework de UI unificado con breakpoints:
- COMPACT (<600px): escala 0.85
- MEDIUM (600-840px): escala 0.92
- EXPANDED (840-1200px): 1.0
- LARGE (>1200px): 1.0

Navegación auto-adaptativa: sidebar → rail → drawer → bottom nav.

### Brick ORM (offline-first)
- Modelos decorados con `@ConnectOfflineFirstWithSupabase`
- Conflictos: **bloqueo optimista** (campo `version`) para documentos SRI; **LWW+merge** para maestros; **append-only** para transacciones; **suma-delta** para stock
- Cola con prioridades: documentos SRI > cobros/pagos > asientos > maestros > config

### Pipeline SRI
Edge Function → genera XML (valida XSD) → firma XAdES-BES → SOAP a SRI → cola autorización (reintentos 24h) → guarda XML autorizado en Storage → genera RIDE PDF → envía por email/WhatsApp.

## Estructura del Proyecto Flutter (planificada)

```
lib/
├── main.dart / app.dart
├── core/
│   ├── brick/          # Modelos y repository (código generado en adapters/ y db/)
│   ├── shell/          # PilarShell framework (layout, navegación, breakpoints)
│   ├── providers/      # Providers Riverpod globales (auth, empresa, permisos, tema, tabs)
│   ├── services/       # SriService, PdfService, PaymentService, AiService, etc.
│   ├── theme/          # FluentThemeData, tipografía, spacing (base 4px), accentColor
│   └── widgets/        # CrudScaffold<T>, FormScaffold<T>, DataGrid, WorkspaceTabs
└── features/           # Un directorio por módulo (screens/, providers/, widgets/)
```

## Estructura del Repositorio

```
pilar/
├── foundation/               ← Capa base (siempre activa, country-agnostic)
│   ├── supabase/             ← CLI project root (config.toml aquí)
│   │   ├── config.toml       ← Configuración Supabase CLI
│   │   ├── migrations/       ← Fuentes foundation (001-019) + módulos ensamblados (mod_*.sql)
│   │   └── functions/        ← Edge Functions foundation + módulos ensamblados
│   │       ├── _shared/      ← cors.ts (CORS genérico — único helper verdaderamente compartido)
│   │       └── upload-logo/  ← Sube logo empresa a Storage
│   ├── adrs/                 ← ADR-001 al ADR-009
│   ├── integraciones/        ← n8n.md, pagos.md (patrón adaptador genérico)
│   ├── apis/                 ← rpcs-por-modulo.md (índice 85+ RPCs; 🇪🇨 = Ecuador-specific)
│   ├── sistema-base.md       ← START HERE: Auth, Empresas, Usuarios, Module Launcher
│   ├── arquitectura.md       ← Patrones capas, Riverpod, Brick, RLS (agnóstico)
│   ├── arquitectura-modular.md ← Module Service Bus, ModuleSlot
│   ├── modelo-datos.md       ← Schema PostgreSQL completo (~326 tablas)
│   └── roadmap.md            ← Fases P1/P2/P3
│
├── modules/
│   ├── infraestructura/      ← Módulos siempre activos
│   │   ├── administracion/   ← module.md + supabase/migrations/
│   │   └── comunicacion/     ← module.md + supabase/migrations/ + supabase/functions/
│   │
│   ├── core/                 ← Módulos Core (proveen servicios via MSB)
│   │   ├── entidades/        ← Contactos + Productos (module.md + supabase/migrations/)
│   │   ├── facturacion/      ← SRI compliance (module.md + supabase/migrations + supabase/functions)
│   │   ├── ventas/           ← OV, cotizaciones, CxC (module.md + supabase/migrations + sub-docs)
│   │   ├── compras/          ← OC, recepciones, retenciones (module.md + supabase/migrations + sub-docs)
│   │   ├── inventario/       ← Stock, bodegas, movimientos (module.md + supabase/migrations + sub-docs)
│   │   ├── contabilidad/     ← Asientos, plan cuentas (module.md + supabase/migrations + sub-docs)
│   │   ├── tesoreria/        ← Cuentas bancarias, cheques (module.md + supabase/migrations + supabase/functions)
│   │   └── tributacion/      ← 103/104/ATS (module.md + supabase/migrations + 3 supabase/functions)
│   │
│   └── extensiones/          ← Módulos activables por empresa
│       ├── facturacion_ec/   ← SRI Ecuador: XML V2.1.0, XAdES-BES, RIDE, SOAP
│       │   ├── supabase/functions/_shared/ ← sri-signer.ts, ride-pdf.ts, xml-parser.ts, sri-soap.ts
│       │   ├── supabase/functions/upload-certificate/ ← Carga certificado .p12 SRI
│       │   ├── arquitectura-sri.md ← Pipeline SRI, librerías Ecuador, ambientes
│       │   └── flujos-sri.md       ← Flujos XAdES/SOAP/RIDE/ATS detallados
│       ├── tributacion_ec/   ← ATS, F-103, F-104
│       │   └── regulatorio/  ← XSD SRI, schemas XML/PDF, normativa fiscal Ecuador
│       ├── ia/               ← pgvector, embeddings, chat (module.md + supabase/migrations + 3 supabase/functions)
│       ├── pagos-online/     ← Kushki/Paymentez/PayPhone (module.md + supabase/migrations + 3 supabase/functions)
│       │   └── integraciones/pasarelas-ecuador.md ← Comparativa pasarelas, débito, datáfonos
│       ├── citas-belleza/    ← App Salón 3 flavors (module.md + 3 supabase/migrations + 2 supabase/functions)
│       ├── pos/              ← POS multi-modo (module.md)
│       ├── ecommerce/        ← WooCommerce + Marketplace (module.md + sub-docs)
│       ├── rrhh/             ← Nómina IESS/IR (module.md + sub-docs)
│       ├── crm/              ← Pipeline (module.md)
│       ├── proyectos/        ← Tareas, timesheets (module.md)
│       ├── activos-fijos/    ← Depreciaciones (module.md)
│       ├── consumibles/      ← Stock consumibles (module.md)
│       ├── suscripciones/    ← Contratos recurrentes (module.md)
│       ├── servicio-de-campo/ ← Órdenes campo, SLA (module.md)
│       ├── taller/           ← Reparaciones físicas (module.md)
│       ├── garantias-rma/    ← RMA puente (module.md)
│       └── intercompany/     ← Entre empresas del grupo (module.md)
│
├── scripts/
│   └── build-supabase.sh     ← Ensambla foundation/ + modules/ → foundation/supabase/
│
└── archive/                  ← Histórico (INFORME_ERP_PILAR.md, RESUMEN..., contexto/)
```

## Documentación Clave

> **Fuente canónica**: `foundation/` y `modules/`. No existe directorio `docs/` — fue eliminado tras verificar migración completa.

### Documentos de Arquitectura (en `foundation/`)

| Archivo | Contenido |
|---------|-----------|
| `foundation/indice.md` | **Índice maestro** — todos los módulos con descripciones y links |
| `foundation/sistema-base.md` | **START HERE** — Auth, Empresas, Usuarios, Roles, Module Launcher |
| `foundation/arquitectura.md` | Patrones capas, Riverpod, Brick, RLS, multi-tenancy (agnóstico; secciones SRI → `facturacion_ec/arquitectura-sri.md`) |
| `foundation/arquitectura-modular.md` | Module Service Bus, ModuleSlot, ciclo de vida |
| `foundation/modelo-datos.md` | Schema PostgreSQL completo (~326 tablas) + `modelo-datos-auditoria.md` |
| `foundation/roadmap.md` | Fases P1/P2/P3 con checklist |
| `foundation/seguridad.md` | RLS, auth, cifrado, LOPDP |
| `foundation/background-jobs.md` | pg_cron (14 jobs) + pgmq (4 colas) |
| `foundation/apis/rpcs-por-modulo.md` | 85+ RPCs documentadas; 🇪🇨 = Ecuador-specific con ref al módulo |
| `foundation/integraciones/pagos.md` | Patrón adaptador de pagos genérico (pasarelas Ecuador → `pagos-online/integraciones/pasarelas-ecuador.md`) |
| `foundation/adrs/ADR-009_sistema-modular.md` | Sistema modular tipo Odoo |

### Documentos Ecuador (en módulos de extensión)

| Archivo | Contenido |
|---------|-----------|
| `modules/extensiones/facturacion_ec/arquitectura-sri.md` | Pipeline SRI: librerías, Storage buckets, ambientes pruebas/prod |
| `modules/extensiones/facturacion_ec/flujos-sri.md` | Flujos XAdES-BES, SOAP SRI, RIDE PDF, nota crédito, ATS |
| `modules/extensiones/tributacion_ec/regulatorio/` | XSD SRI, schemas XML/PDF, normativa fiscal Ecuador 2024-2025 |
| `modules/extensiones/pagos-online/integraciones/pasarelas-ecuador.md` | Comparativa pasarelas, débito bancario, datáfonos, QR |

### Módulos Core — `module.md` por módulo

| Módulo | Spec | Tablas clave |
|--------|------|--------------|
| **Entidades** | `modules/core/entidades/module.md` | `contactos`, `productos`, `listas_precios`, `producto_presentaciones` |
| **Facturación** | `modules/core/facturacion/module.md` | `facturas`, `cola_documentos_electronicos`, `cobros_factura` |
| **Ventas** | `modules/core/ventas/module.md` | `cotizaciones`, `ordenes_venta`, `cuentas_por_cobrar` |
| **Compras** | `modules/core/compras/module.md` | `ordenes_compra`, `facturas_proveedor`, `retenciones` |
| **Inventario** | `modules/core/inventario/module.md` | `productos`, `bodegas`, `inventario_stock`, `guias_remision` |
| **Contabilidad** | `modules/core/contabilidad/module.md` | `asientos_contables`, `cuentas_contables`, `periodos_contables` |
| **Tesorería** | `modules/core/tesoreria/module.md` | `cuentas_bancarias`, `movimientos_bancarios`, `cheques` |
| **Tributación** | `modules/core/tributacion/module.md` | `declaraciones_tributarias`, `configuracion_tributaria` |

### Módulos Infraestructura

| Módulo | Spec |
|--------|------|
| **Administración** | `modules/infraestructura/administracion/module.md` |
| **Comunicación** | `modules/infraestructura/comunicacion/module.md` |

### Extensiones — `module.md` por módulo

Todos en `modules/extensiones/<nombre>/module.md`. Ver índice completo en `modules/README.md`.

### Specs derivadas de módulos Odoo Ecuador

| Archivo | Módulo Odoo fuente |
|---------|-------------------|
| `modules/core/tesoreria/anticipos.md` | `l10n_ec_advances` |
| `modules/core/tesoreria/caja-chica.md` | `l10n_ec_petty_cash` |
| `modules/core/tesoreria/cobro-multifactura.md` | `l10n_ec_multiinvoice_payment` |
| `modules/core/tesoreria/conciliacion-tarjetas.md` | `l10n_ec_card_reconciliation` |
| `modules/core/tesoreria/cheques.md` | `l10n_ec_checks` |
| `modules/core/tesoreria/caja-recaudadora.md` | `l10n_ec_collection_box` |
| `modules/core/inventario/reservas-productos.md` | `l10n_ec_product_reservation` |
| `modules/core/inventario/kardex.md` | `l10n_ec_stock_kardex` |
| `modules/core/inventario/devoluciones.md` | `l10n_ec_stock_return` |
| `modules/core/inventario/conversion-stock.md` | `l10n_ec_stock_conversion` |
| `modules/core/compras/importaciones.md` | `l10n_ec_importaciones` |
| `modules/core/compras/importacion-xml-sri.md` | `l10n_ec_edi_import` |
| `modules/core/compras/costos-aterrizaje.md` | `l10n_ec_stock_landed_costs` |
| `modules/core/ventas/credito-clientes.md` | `l10n_ec_sale_credit` |
| `modules/core/ventas/descuentos.md` | `l10n_ec_sale_discount` |
| `modules/core/ventas/plazos-pago.md` | `l10n_ec_sale_payment_term` |
| `modules/core/ventas/ensamblaje.md` | `l10n_ec_sale_assemble` |
| `modules/extensiones/rrhh/nomina-ecuador.md` | `l10n_ec_hr_payroll` |

## Agentes Especializados

En `.claude/agents/` hay 7 agentes con roles y convenciones específicas:

| Agente | Rol |
|--------|-----|
| `flutter-feature.md` | Flutter/Dart: Riverpod, fluent_ui, Brick offline-first, go_router ShellRoute, LayoutBuilder responsive, NUNCA dio |
| `supabase-backend.md` | PostgreSQL: migraciones en `modules/*/supabase/migrations/`, RLS con `private.get_empresa_id()`, pgmq, pg_cron |
| `api-developer.md` | Edge Functions Deno/TypeScript: lista real de funciones por módulo, helpers `_shared/`, RPCs |
| `sri-integration.md` | SRI Ecuador: pipeline `sri-firma-envio` → `poll-autorizacion` → `generate-ride`, XAdES-BES, SOAP, ATS |
| `ui-designer.md` | fluent_ui: NavigationView, SfDataGrid, ContentDialog, ProgressRing, FluentIcons, Syncfusion theming |
| `quality-check.md` | QA: checklist Flutter (FluentTheme, decimal, ProgressRing) + Backend (RLS, advisors, Module Service Bus) |
| `ai-integration.md` | IA: pgvector, embeddings asíncronos vía `pilar_ai_queue`, ai-embed/query/report, multi-tenancy |

**Antes de implementar cualquier feature, leer el agente correspondiente** para seguir las convenciones establecidas.

## Convenciones Críticas

- **RLS siempre activo**: toda tabla necesita `empresa_id` y policy con `private.get_empresa_id()`
- **Sin llamadas directas a Supabase desde widgets**: siempre a través de Brick repository o providers
- **Módulos auxiliares → Module Service Bus**: nunca INSERT directo en tablas de módulos core
- **Documentos SRI**: bloqueo optimista con campo `version` obligatorio
- **Migraciones**: nombrar `NNN_descripcion.sql`, ejecutar con `supabase db push`, nunca editar migraciones ya aplicadas
- **Precisión**: `DECIMAL(14,2)` montos, `DECIMAL(18,6)` cantidades — NUNCA `float`
- **Redondeo**: solo al final del cálculo, nunca en intermedios
- **fluent_ui**: sistema de diseño principal — `FluentApp.router` + `FluentThemeData` + `NavigationView`. `FluentTheme.of(context)` en widgets, NUNCA `Theme.of(context)`. Sin `flex_color_scheme`
- **Layout responsive**: `LayoutBuilder` para elegir entre `SfDataGrid` (>600px) y `ListView`/cards (<600px). NUNCA grids en pantallas <600px
- **Syncfusion + fluent**: integrar via `SfDataGridThemeData(headerColor: FluentTheme.of(context).accentColor.withValues(alpha:0.2))`
- **Syncfusion MANDATORIO**: usar ÚNICAMENTE paquetes del publisher oficial [`syncfusion.com`](https://pub.dev/publishers/syncfusion.com/packages). Versión única para todos (`^32.2.5`). Paquetes confirmados: `syncfusion_flutter_core`, `datagrid`, `charts`, `pdf`, `pdfviewer`, `xlsio`, `calendar`, `gauges`, `datepicker`, `signaturepad`, `syncfusion_localizations`
- **decimal package**: usar `decimal: ^2.3.3` para toda aritmética monetaria en Flutter — NUNCA `double` ni `num`
- **Background jobs**: usar pg_cron (jobs programados) y pgmq (colas con retry) — ver `foundation/background-jobs.md` y ADR-007. NUNCA schedulers externos
- **Sistema modular tipo Odoo**: `PilarModule` interface + `ModuleRegistry` (compilado) + `ModuleSlot` (inyección UI) + `activate_module()` PostgreSQL con dependencias recursivas — ver ADR-009 en `foundation/adrs/` y `foundation/arquitectura-modular.md`
- **Añadir módulo**: migración SQL en `modules/<tipo>/<mod>/supabase/migrations/` + `INSERT INTO modulos/modulo_dependencias` + clase `implements PilarModule` + registro en `ModuleRegistry._allModules` — 4 pasos, sin tocar código de otros módulos
- **build-supabase.sh**: ejecutar `./scripts/build-supabase.sh` antes de `supabase db push` para ensamblar las migraciones de todos los módulos en el orden correcto
- **Independencia de módulos**: cada módulo puede instalarse sin depender de otros (excepto foundation). Patrón obligatorio:
  - Campos cross-module se definen directamente en la tabla propietaria como `UUID` nullable (soft ref, sin FK constraint)
  - Archivos `extend_*.sql` usan `DO $$ BEGIN IF EXISTS (SELECT 1 FROM information_schema.tables WHERE ...) THEN ALTER TABLE ... ADD COLUMN IF NOT EXISTS ...; END IF; END $$;` — completamente idempotentes
  - `CREATE TABLE IF NOT EXISTS` para stubs de tablas externas necesarias (ver `tesoreria/supabase/migrations/000_shared_deps.sql`, `facturacion/supabase/migrations/000_shared_deps.sql`)
  - FK constraints solo hacia tablas de foundation (`empresas`, `establecimientos`, `contactos`, `productos`) que siempre existen
