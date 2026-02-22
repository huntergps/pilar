# PILAR ERP

**Sistema SaaS ERP para Ecuador con cumplimiento de facturación electrónica SRI**

![Estado](https://img.shields.io/badge/Estado-En%20Dise%C3%B1o%2FDesarrollo-yellow)
![Stack](https://img.shields.io/badge/Stack-Flutter%20%2B%20Supabase-blue)
![License](https://img.shields.io/badge/License-Proprietary-red)
![Ecuador](https://img.shields.io/badge/Compliance-SRI%20Ecuador-green)

---

## Que es PILAR

PILAR es un sistema ERP SaaS diseñado desde cero para empresas ecuatorianas. Cubre el ciclo completo de operaciones comerciales: ventas, compras, inventario, contabilidad, tesorería y tributación, con cumplimiento nativo del Servicio de Rentas Internas (SRI) para facturación electrónica, retenciones, ATS y formularios tributarios.

A diferencia de los ERPs genéricos adaptados para Ecuador, PILAR tiene la normativa fiscal ecuatoriana integrada en su núcleo. Los documentos electrónicos (01 facturas, 03 liquidaciones de compra, 04 notas de crédito, 05 notas de débito, 06 guías de remisión, 07 retenciones) se procesan mediante un pipeline automático: generación XML validado contra XSD del SRI, firma XAdES-BES, envío SOAP, autorización en tiempo real y almacenamiento del RIDE PDF.

La plataforma opera con un único codebase Flutter que compila para Web, iOS, Android, Windows, macOS y Linux. El diseño offline-first garantiza continuidad operativa en zonas con conectividad intermitente, sincronizando automáticamente contra PostgreSQL (Supabase) cuando la conexión se restablece.

---

## Caracteristicas Principales

- **24 módulos** organizados en 3 categorías: Infraestructura (siempre activos), Core (backbone ERP) y Auxiliares (activables por empresa según plan SaaS)
- **Facturación electrónica SRI**: 6 tipos de documentos, firma XAdES-BES server-side, cola con reintentos 24h
- **Offline-first**: SQLite local sincronizado con PostgreSQL via `brick_offline_first_with_supabase`
- **Multi-plataforma**: Web + iOS + Android + Windows + macOS + Linux desde un solo codebase Dart
- **Multi-tenant**: aislamiento completo por empresa con Row Level Security (RLS) en PostgreSQL
- **Multi-empresa**: un usuario puede pertenecer a N empresas con roles diferentes
- **Module Service Bus**: módulos auxiliares nunca escriben directo en tablas core — usan funciones gateway que verifican disponibilidad
- **Tributación completa**: ATS mensual, Formulario 104 (IVA), Formulario 103 (Retenciones), Formulario 101 (IR Anual), EEFF Supercias
- **RRHH Ecuador**: nómina con IESS, décimos, fondos de reserva, IR, RDEP, planilla IESS
- **POS multi-modo**: supermercado, departamental (multi-vendedor) y ferretería con pre-ventas
- **IA integrada**: pgvector, forecast de ventas/inventario, chat NLP, scoring CRM, detección de anomalías
- **Notificaciones multi-canal**: email (Resend), WhatsApp (Cloud API), Telegram (Bot API)

---

## Stack Tecnologico

| Capa | Tecnología | Detalle |
|------|-----------|---------|
| **Frontend** | Flutter 3.x (Dart) | Un codebase para 6 plataformas |
| **Estado** | Riverpod 2.x | Providers globales (core/) y locales (features/) |
| **UI** | Material 3 + Syncfusion | DataGrid, PDF, Charts + flex_color_scheme |
| **Datos / Offline** | brick_offline_first_with_supabase | SQLite local ↔ PostgreSQL remoto |
| **Backend** | Supabase | PostgreSQL 15+, Auth JWT, Storage, Realtime, pgvector |
| **Edge Functions** | Deno / TypeScript | Firma XAdES-BES, SOAP SRI, XML/PDF, IA |
| **Routing** | go_router | ShellRoute para PilarShell |
| **Deploy Web** | Cloudflare Pages | Gratis, sin vendor lock-in |
| **Deploy Backend** | Supabase Cloud | PostgreSQL managed + todos los servicios |
| **Pagos** | Kushki + Paymentez + PayPhone | Patron adaptador, configurables por empresa |
| **Errores** | Sentry | Monitoreo de excepciones en producción |

---

## Estructura del Proyecto

```
pilar/
├── README.md                        # Este archivo
├── CLAUDE.md                        # Instrucciones para Claude Code
├── docs/                            # Documentacion tecnica (82 archivos .md)
│   ├── indice.md                    # Indice maestro de toda la documentacion
│   ├── core/                        # Arquitectura, modelo de datos, roadmap
│   ├── modulos/                     # Un directorio por modulo (24 modulos)
│   ├── regulatorio/                 # Normativa SRI, documentos electronicos, ATS
│   ├── apis/                        # RPCs PostgreSQL (85+ funciones)
│   ├── integraciones/               # n8n, marketplaces, pasarelas pago
│   └── _meta/                       # Metadocumentacion: ADRs, changelog, guia contribucion
├── sql/                             # Scripts SQL de modulos implementados
├── supabase/
│   └── migrations/                  # Migraciones versionadas (NNN_descripcion.sql)
└── .claude/
    └── agents/                      # 7 agentes especializados para Claude Code
```

### Estructura Flutter Planificada (lib/)

```
lib/
├── main.dart / app.dart
├── core/
│   ├── brick/          # Modelos Brick y repository (codigo generado en adapters/ y db/)
│   ├── shell/          # PilarShell: layout adaptativo, breakpoints, navegacion
│   ├── providers/      # Providers Riverpod globales (auth, empresa, permisos, tema, tabs)
│   ├── services/       # SriService, PdfService, PaymentService, AiService
│   ├── theme/          # flex_color_scheme, tipografia, espaciado responsive
│   └── widgets/        # CrudScaffold<T>, FormScaffold<T>, DataGrid, WorkspaceTabs
└── features/           # Un directorio por modulo (screens/, providers/, widgets/)
```

---

## Primeros Pasos para Developers

### Prerequisitos

- Flutter SDK 3.x (`flutter --version`)
- Supabase CLI (`supabase --version`)
- Docker Desktop (para entorno local Supabase)

### Entorno Local

```bash
# 1. Clonar el repositorio
git clone <repo-url>
cd pilar

# 2. Iniciar Supabase local
supabase start

# 3. Aplicar migraciones
supabase db push

# 4. (Cuando exista el proyecto Flutter)
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
flutter run -d chrome
```

### Agentes Especializados

Antes de implementar cualquier feature, consulta el agente correspondiente en `.claude/agents/`:

| Agente | Area |
|--------|------|
| `flutter-feature.md` | Pantallas Flutter, Riverpod, Brick, navegacion |
| `supabase-backend.md` | Migraciones SQL, RLS, Storage, funciones |
| `api-developer.md` | Edge Functions Deno/TypeScript, RPCs |
| `sri-integration.md` | Cumplimiento SRI, XML, firma electronica, SOAP |
| `ui-designer.md` | UI/UX Material 3, accesibilidad, responsive |
| `quality-check.md` | Tests, RLS, multi-tenancy, validaciones |
| `ai-integration.md` | pgvector, embeddings, chat NLP |

---

## Documentacion

El directorio `docs/` contiene 82 archivos de especificacion tecnica organizada por modulo. El punto de entrada es:

**[docs/indice.md](docs/indice.md)** — Indice maestro con descripcion de cada documento y tablas SQL clave por modulo.

Documentos core mas importantes:

| Documento | Contenido |
|-----------|-----------|
| [docs/core/arquitectura.md](docs/core/arquitectura.md) | Capas del sistema, brick offline-first, diagramas |
| [docs/core/arquitectura-modular.md](docs/core/arquitectura-modular.md) | Module Service Bus, clasificacion de modulos |
| [docs/core/modelo-datos.md](docs/core/modelo-datos.md) | Schema PostgreSQL completo (~326 tablas) |
| [docs/core/roadmap.md](docs/core/roadmap.md) | Fases de implementacion P1/P2/P3 |
| [docs/core/seguridad.md](docs/core/seguridad.md) | RLS, auth, cifrado, LOPDP |
| [docs/_meta/ADRS/](docs/_meta/ADRS/) | Architecture Decision Records |
| [docs/_meta/changelog.md](docs/_meta/changelog.md) | Historial de cambios arquitectonicos |
| [docs/_meta/CONTRIBUIR.md](docs/_meta/CONTRIBUIR.md) | Guia para contribuidores |

---

## Cumplimiento Ecuador

PILAR esta disenado para cumplir con la normativa ecuatoriana vigente:

| Marco | Cobertura |
|-------|-----------|
| **SRI — Facturacion Electronica** | Tipos 01/03/04/05/06/07, firma XAdES-BES, ambientes prueba/produccion |
| **SRI — Declaraciones** | ATS mensual, Formulario 103 (Retenciones), 104 (IVA), 101 (IR Anual) |
| **Supercias** | 5 estados financieros en formato TXT (EEFF obligatorios) |
| **IESS — Nomina** | Decimos 13/14, fondos de reserva, IR empleados, planilla IESS, RDEP |
| **LOPDP** | Ley Organica de Proteccion de Datos Personales — cifrado, auditoría, consentimiento |
| **NIIF PYMES** | Plan de cuentas Ecuador, asientos automaticos por tipo de documento |

---

## Licencia

Copyright (c) 2026. Todos los derechos reservados.

Este software es propietario y confidencial. No esta permitida su reproduccion, distribucion ni uso sin autorizacion expresa por escrito del titular de los derechos.
