# PILAR ERP — Foundation

La **capa Foundation** es la base del ERP: se instala primero y es requerida por todos los módulos. No es desactivable.

## Contenido

```
foundation/
├── migrations/           ← SQL de Foundation (001–005)
│   ├── 001_core.sql      ← 16 tablas: empresas, roles, permisos, módulos, secuencias
│   ├── 002_functions.sql ← private.get_empresa_id(), has_permission(), trigger auth
│   ├── 003_seed_roles.sql← 11 roles sistema + 18 permisos de infraestructura
│   ├── 004_seed_modules.sql ← 4 planes SaaS + 24 módulos + dependencias + catálogos
│   └── 005_helpers.sql   ← check_permission(), get_current_empresa_id(), Storage buckets
│
├── functions/            ← Edge Functions de Foundation
│   ├── _shared/          ← Código compartido (cors.ts — único helper verdaderamente compartido)
│   └── upload-logo/      ← Sube logotipo empresa al bucket logos (público)
│
├── adrs/                 ← Architecture Decision Records (ADR-001 al ADR-009)
├── integraciones/        ← n8n, automatizaciones, patrón adaptador de pagos
├── datos-referencia/     ← Seed data fiscal
├── apis/                 ← Índice de RPCs por módulo
├── casos-uso/            ← Índice de casos de uso por vertical
│
├── arquitectura.md       ← Patrones de arquitectura, multi-tenancy, RLS
├── arquitectura-modular.md ← Sistema de módulos, Module Service Bus
├── sistema-base.md       ← START HERE: Auth, Empresas, Usuarios, Roles, Module Launcher
├── modelo-datos.md       ← Schema PostgreSQL completo (~326 tablas)
├── roadmap.md            ← Fases de implementación P1/P2/P3
├── seguridad.md          ← RLS, auth, cifrado, cumplimiento LOPDP
├── precision-supabase.md ← Buenas prácticas DECIMAL, zonas horarias
├── background-jobs.md    ← pg_cron (14 jobs) + pgmq (4 colas)
├── cicd.md               ← Codemagic, GitHub Actions, deploy
├── pubspec-referencia.md ← pubspec.yaml Flutter con todos los paquetes
├── seed-data.md          ← Estrategia seed, datos de referencia
├── CONTRIBUIR.md         ← Guía de contribución
└── resumen-ejecutivo.md  ← Resumen del proyecto
```

## Tablas Foundation

| Tabla | Descripción |
|-------|-------------|
| `empresas` | Tenants del SaaS (multi-tenant) — country-agnostic |
| `roles` | 11 roles sistema (ADMIN, CONTADOR, VENDEDOR, ...) |
| `permisos` | 200+ permisos granulares (modulo.recurso.accion) — seeded por módulo en `NNN_seed_permissions.sql` |
| `roles_permisos` | Asignación permisos a roles |
| `usuarios_empresa` | Relación usuario ↔ empresa con rol |
| `modulos` | Catálogo 24 módulos del ERP |
| `modulo_dependencias` | Grafo de dependencias entre módulos |
| `modulos_empresa` | Módulos activos por empresa |
| `configuracion_empresa` | Parámetros por empresa |
| `secuencias` | Secuencias genéricas (prefijo + siguiente_número) |
| `adjuntos` | Adjuntos genéricos polimórficos |
| `registro_actividad` | Audit trail |
| `sesiones_usuario` | Control de sesiones activas |
| `planes_suscripcion` | FREE, STARTER, PROFESSIONAL, ENTERPRISE |

> **Nota**: `establecimientos`, `puntos_emision`, `secuenciales`, `ambiente_sri` y `certificado_*` son responsabilidad de los módulos de facturación y localización, no de Foundation.

## Funciones Clave

```sql
-- Obtener empresa_id del usuario actual (cacheada, obligatoria en RLS)
private.get_empresa_id() RETURNS UUID

-- Verificar permiso (usa has_permission() interno)
public.check_permission(p_permission TEXT) RETURNS BOOLEAN

-- Activar módulo con resolución de dependencias
public.activate_module(p_empresa_id UUID, p_modulo_codigo TEXT) RETURNS JSONB

-- Desactivar módulo (nunca hace DROP TABLE)
public.deactivate_module(p_empresa_id UUID, p_modulo_codigo TEXT) RETURNS JSONB
```

## Patrones Obligatorios

### RLS
```sql
-- SIEMPRE usar (SELECT ...) para función cacheada, nunca inline
USING (empresa_id = (SELECT private.get_empresa_id()))
```

### Multi-tenancy
Todas las tablas tienen `empresa_id UUID NOT NULL` con FK a `empresas.id`.

## ADRs Relacionados

- [ADR-001](adrs/ADR-001_brick-offline-first.md) — Brick Offline-First con Supabase
- [ADR-002](adrs/ADR-002_module-service-bus.md) — Module Service Bus
- [ADR-003](adrs/ADR-003_rls-pattern.md) — Patrón RLS
- [ADR-005](adrs/ADR-005_no-firebase-si-supabase.md) — No Firebase, sí Supabase
- [ADR-009](adrs/ADR-009_sistema-modular.md) — Sistema Modular tipo Odoo
