# Foundation — Índice de Documentación

> Este índice cubre exclusivamente la capa Foundation. La documentación de cada módulo vive en su propio directorio.
> Última revisión: 2026-02-22 — Añadidas 3 migraciones transversales: `020_notification_center.sql` (notificaciones in-app con Realtime), `021_approval_workflows.sql` (workflows de aprobación configurables), `022_data_importer.sql` (importador CSV/XLSX genérico al estilo Odoo). Edge Function `import-data` añadida.

## Documentación de Foundation

Esta carpeta contiene la capa base del sistema: patterns, decisiones técnicas y documentos transversales. Todos country-agnostic (ADR-006).

| Documento | Descripción |
|-----------|-------------|
| [Sistema Base](sistema-base.md) | **START HERE** — Auth, Empresas, Usuarios, Roles, Module Launcher, Onboarding. Funcional sin módulos. |
| [Arquitectura del Sistema](arquitectura.md) | Capas, Riverpod, Brick offline-first, RLS, multi-tenancy |
| [Arquitectura Modular](arquitectura-modular.md) | Module Service Bus, ModuleSlot, KPIs, cómo agregar módulos |
| [Modelo de Datos](modelo-datos.md) | Schema global PostgreSQL (~326 tablas), convenciones, relaciones entre entidades |
| [Seguridad](seguridad.md) | RLS con `private.get_empresa_id()`, auth JWT, cifrado, cumplimiento LOPDP, roles PG vs negocio |
| [Precisión Numérica](precision-supabase.md) | `DECIMAL(14,2)` montos, `DECIMAL(18,6)` cantidades, zonas horarias, best practices Supabase |
| [Background Jobs](background-jobs.md) | pg_cron (14 jobs) y pgmq (4 colas async): procesamiento asíncrono de documentos, notificaciones, sincronización, embeddings |
| [CI/CD](cicd.md) | Codemagic multi-plataforma (5 workflows), GitHub Actions migraciones, code signing iOS/Android, Cloudflare Pages |
| [Pubspec de Referencia](pubspec-referencia.md) | `pubspec.yaml` completo — fluent_ui, Syncfusion, Brick, Riverpod, paquetes desktop; excluidos con razones |
| [Roadmap](roadmap.md) | Fases de Foundation (plataforma, widgets core, sistema modular); módulos tienen su propio roadmap |
| [Estructura del Proyecto Flutter](estructura-proyecto.md) | Árbol `lib/core/`, `lib/features/`, flavors, convenciones Riverpod/Brick |
| [Flujos y Casos de Uso](flujos-casos-uso.md) | Procesos genéricos de plataforma (ciclos de documentos, cobros, notificaciones) |
| [Glosario](glossario.md) | Términos de arquitectura PILAR, ERP, finanzas genéricas, stack técnico |
| [Seed Data](seed-data.md) | 11 roles, permisos `plataforma.*` y por módulo, UoM, parámetros del sistema |
| [Timezone Management](timezone-management.md) | UTC-first, patrones Dart/SQL/Edge Functions, anti-patrones |
| [Field Ownership Matrix](field-ownership-matrix.md) | Matriz de campos por módulo: propietario vs. extensión, cross-module soft refs |
| [Centro de Notificaciones](notification-center.md) | Notificaciones in-app con Supabase Realtime, `crear_notificacion()`, widget `NotificationBell`, pg_cron cleanup |
| [Workflows de Aprobación](approval-workflows.md) | Reglas configurables por módulo/recurso, modos simple y consenso, notificaciones automáticas, integración en módulos |
| [Importador CSV/Excel](data-importer.md) | Templates data-driven, validación por campo, Edge Function `import-data`, templates seed (contactos, productos, saldos) |

### Guías de Implementación

| Documento | Descripción |
|-----------|-------------|
| [Contrato del Module Service Bus](module-service-bus-contract.md) | **Referencia MSB** — Patrón exacto, funciones gateway, ejemplos `create_invoice()` y `reserve_stock()`, contrato JSONB |
| [Patrones ALTER TABLE Cross-Módulo](alter-table-patterns.md) | Naming `<modulo>_<campo>`, patrón idempotente `IF NOT EXISTS`, cuándo usar ALTER vs tabla propia vs soft ref |
| [Garantías de Activación de Módulos](module-activation-guarantees.md) | Diagrama de estados, transacciones, `post_install_rpc`, idempotencia, timeout de Edge Functions |
| [Reglas de Precisión y Redondeo](precision-rounding-rules.md) | Regla de oro del redondeo, `financial_round()`, conversión de monedas, IVA correcto vs incorrecto |
| [Guía de Desactivación de Módulos](module-deactivation-guide.md) | Validaciones pre-desactivación, archivado de datos, cascadas, `pre_uninstall_check_rpc` |
| [Guía de Testing de RLS](rls-testing-guide.md) | pgTAP setup, template de test de aislamiento entre tenants, checklist mínimo, CI/CD |
| [Guía de Implementación de Módulos](module-implementation-guide.md) | Checklist completo paso a paso, boilerplate SQL y Dart, errores comunes |

---

## Migraciones SQL de Foundation

`supabase/migrations/` — 22 archivos (fuentes foundation). Los módulos se ensamblan aquí como `mod_*.sql` con `build-supabase.sh`. El CLI de Supabase se ejecuta desde `foundation/` (project root: `foundation/supabase/config.toml`).

| Migración | Contenido |
|-----------|-----------|
| `001_core.sql` | Tablas base: empresas, roles, permisos, módulos, usuarios, sesiones, adjuntos, audit trail |
| `002_functions.sql` | Funciones privadas: `get_empresa_id()`, `has_permission()`, trigger onboarding con validaciones NULL |
| `003_seed_roles.sql` | 11 roles sistema + permisos `plataforma.*` + asignaciones a ADMIN/SUPER_ADMIN |
| `004_seed_modules.sql` | 3 módulos infraestructura + planes SaaS (FREE/STARTER/PRO/ENTERPRISE) |
| `005_helpers.sql` | Wrappers públicos, Storage buckets (logos/adjuntos/avatares), RLS Storage |
| `006_field_extensions.sql` | Sistema de extensión de campos (análogo a `ir.model.fields` de Odoo) |
| `007_shared_tables.sql` | Entidades base: contactos, productos, UoM, categorías, metadatos JSONB |
| `008_catalogo_geografico.sql` | 239 países + **24 provincias Ecuador** (códigos SRI 01–24) + **26 ciudades capitales** |
| `009_catalogo_monedas.sql` | Monedas ISO 4217 (seed USD) |
| `010_secuencias.sql` | Contadores atómicos multi-tenant `secuencias_contador` + `next_secuencial()` |
| `011_feature_flags.sql` | Feature flags por empresa/usuario/plan + `is_feature_enabled()` + 6 flags de sistema |
| `012_invitaciones_pendientes.sql` | Registro de auditoría de invitaciones: estados PENDIENTE→ENVIADA→ACEPTADA, reenvío, expiración. El envío real lo hace la EF `invite-user` vía Supabase Auth Admin |
| `013_plan_modulos.sql` | Tabla relacional `plan_modulos` + migración desde array + `register_module_in_plans()` |
| `014_auto_permisos.sql` | Trigger `AFTER INSERT ON permisos` → ADMIN hereda permisos nuevos automáticamente |
| `015_mfa_config.sql` | Config MFA por empresa: roles obligados, periodo de gracia, métodos permitidos |
| `016_saml_sso.sql` | Infraestructura SAML 2.0: config IdP, certificado X.509, JIT provisioning, log sesiones |
| `017_financial_functions.sql` | Función `financial_round()` — redondeo monetario canónico (ROUND_HALF_UP). Ver `precision-rounding-rules.md` |
| `018_background_jobs.sql` | Extensiones pg_cron + pgmq, 4 colas (`pilar_docs_queue`, `pilar_notifications_queue`, `pilar_integrations_queue`, `pilar_ai_queue`), jobs de limpieza, vista `v_cron_job_health` |
| `019_auth_hook.sql` | `custom_access_token_hook` — inyecta `app_metadata.empresa_id` en cada JWT automáticamente. Reemplaza el patrón pg_notify → auth-setup-handler → updateUserById. Requiere habilitación en Dashboard: Authentication → Hooks |
| `020_notification_center.sql` | Tabla `notificaciones_usuario` (inmutable, Realtime), `crear_notificacion()`, `get_notificaciones()`, `marcar_*_leida()`, pg_cron cleanup 90 días |
| `021_approval_workflows.sql` | Tablas `reglas_aprobacion`, `solicitudes_aprobacion`, `aprobacion_votos`. RPCs: `evaluar_reglas_aprobacion()`, `solicitar_aprobacion()`, `resolver_aprobacion()`, `get_aprobaciones_pendientes_mias()` |
| `022_data_importer.sql` | Tablas `import_templates`, `import_jobs`. RPCs: `registrar_import_template()`, `finalizar_import_job()`, `get_import_templates()`. Seed: 3 templates (contactos, productos, saldos_iniciales) |

## Edge Functions de Foundation

`supabase/functions/` — helpers compartidos + funciones propias.

| Función/Helper | Descripción |
|----------------|-------------|
| `_shared/cors.ts` | Headers CORS genéricos, reutilizado por todas las Edge Functions |
| `_shared/db-client.ts` | Helper `getPoolerUrl()` — fuerza puerto 6543 para conexiones PG desde Deno |
| `auth-setup-handler/` | Crea el bucket privado de Storage cuando se registra una empresa nueva. Invocada por Database Webhook sobre `empresas INSERT` (no Realtime). `app_metadata` ya no se actualiza aquí — lo hace `custom_access_token_hook` |
| `invite-user/` | Invita usuarios a la empresa. Caso A (usuario existente): crea membresía directo en BD. Caso B (nuevo usuario): inserta en `invitaciones_pendientes` + llama `inviteUserByEmail()` de Supabase Auth |
| `upload-logo/` | Sube logo empresa a Storage, valida MIME/tamaño, actualiza `configuracion_empresa` |
| `import-data/` | Importa CSV o XLSX contra un template de `import_templates`. Valida tipos/patrones, llama RPC destino, retorna resumen con errores por fila. Soporta `dry_run=true` para prevalidar sin importar |

---

## ADRs (Architecture Decision Records)

Decisiones técnicas con contexto, alternativas evaluadas y consecuencias.

| ADR | Título | Estado |
|-----|--------|--------|
| [ADR-001](adrs/ADR-001_brick-offline-first.md) | Brick Offline-First con Supabase | Aceptado |
| [ADR-002](adrs/ADR-002_module-service-bus.md) | Module Service Bus para módulos auxiliares | Aceptado |
| [ADR-003](adrs/ADR-003_rls-pattern.md) | Patrón RLS con `private.get_empresa_id()` | Aceptado |
| [ADR-004](adrs/ADR-004_flutter-single-codebase.md) | Flutter single codebase para 6 plataformas + **fluent_ui** como sistema de diseño | Aceptado |
| [ADR-005](adrs/ADR-005_no-firebase-si-supabase.md) | Supabase sobre Firebase | Aceptado |
| [ADR-006](adrs/ADR-006_compliance-como-extension.md) | Compliance como Extension — Foundation Country-Agnostic | Aceptado |
| [ADR-007](adrs/ADR-007_pg-cron-pgmq.md) | pg_cron + pgmq para procesamiento asíncrono (14 jobs, 4 colas) | Aceptado |
| [ADR-008](adrs/ADR-008_syncfusion.md) | Syncfusion como suite UI exclusiva (DataGrid, Charts, PDF, Calendar, Gauges) | Aceptado |
| [ADR-009](adrs/ADR-009_sistema-modular.md) | Sistema modular tipo Odoo: `activate_module()` + `PilarModule` + `ModuleRegistry` + `ModuleSlot` | Aceptado |

---

## APIs y RPCs

| Documento | Descripción |
|-----------|-------------|
| [rpcs-por-modulo.md](apis/rpcs-por-modulo.md) | Índice de referencia de RPCs de plataforma; cada módulo documenta sus propias RPCs |

---

## Integraciones

| Documento | Descripción |
|-----------|-------------|
| [n8n.md](integraciones/n8n.md) | Flujos de automatización n8n |
| [pagos.md](integraciones/pagos.md) | Patrón adaptador de pagos genérico (PaymentResult, PaymentAdapter interface) |

---

## Datos de Referencia

Seed data fiscal y tributaria. Se carga como migraciones SQL.

| Documento | Descripción |
|-----------|-------------|
| [README.md](datos-referencia/README.md) | Índice de seed data, qué son, cómo se mantienen, qué tablas poblan |

---

## Casos de Uso

| Documento | Descripción |
|-----------|-------------|
| [README.md](casos-uso/README.md) | Índice de navegación de casos de uso por vertical |

---

## Meta-Documentación

| Documento | Descripción |
|-----------|-------------|
| [changelog.md](changelog.md) | Historial de cambios arquitectónicos (v0.1 → v0.5) |
| [adrs/README.md](adrs/README.md) | Índice de todas las decisiones arquitectónicas |

---

## Referencia Rápida

| Necesitas | Ve a |
|-----------|------|
| Entender el sistema desde cero | [sistema-base.md](sistema-base.md) |
| Patrón RLS correcto | [ADR-003](adrs/ADR-003_rls-pattern.md) |
| Glosario de términos | [glossario.md](glossario.md) |
| Roadmap de Foundation | [roadmap.md](roadmap.md) |
| Implementar un módulo nuevo | [module-implementation-guide.md](module-implementation-guide.md) |
| Patrón MSB (Module Service Bus) | [module-service-bus-contract.md](module-service-bus-contract.md) |
| Extender tablas de otros módulos | [alter-table-patterns.md](alter-table-patterns.md) |
| Garantías de activación de módulos | [module-activation-guarantees.md](module-activation-guarantees.md) |
| Desactivar un módulo de forma segura | [module-deactivation-guide.md](module-deactivation-guide.md) |
| Reglas de precisión numérica | [precision-rounding-rules.md](precision-rounding-rules.md) |
| Tests de RLS obligatorios | [rls-testing-guide.md](rls-testing-guide.md) |
| Enviar notificación in-app a un usuario | `SELECT crear_notificacion(empresa_id, usuario_id, tipo, titulo, ...)` — ver [notification-center.md](notification-center.md) |
| Ver notificaciones no leídas (Flutter) | `SELECT * FROM get_notificaciones(p_solo_no_leidas => true)` — ver [notification-center.md](notification-center.md) |
| Solicitar aprobación para un registro | `SELECT solicitar_aprobacion('modulo','recurso', registro_id, datos_jsonb)` — ver [approval-workflows.md](approval-workflows.md) |
| Ver aprobaciones pendientes para mí | `SELECT * FROM get_aprobaciones_pendientes_mias()` — ver [approval-workflows.md](approval-workflows.md) |
| Aprobar o rechazar una solicitud | `SELECT resolver_aprobacion(solicitud_id, 'APROBADO', comentario)` — ver [approval-workflows.md](approval-workflows.md) |
| Importar contactos/productos desde CSV | Edge Function `import-data` con template `entidades/contactos` — ver [data-importer.md](data-importer.md) |
| Registrar template de importación en módulo | `SELECT registrar_import_template(modulo, recurso, nombre, desc, campos, rpc)` — ver [data-importer.md](data-importer.md) |
| Registrar módulo en planes SaaS | `SELECT register_module_in_plans('modulo', ARRAY['PRO','ENTERPRISE'])` — ver [013_plan_modulos.sql](supabase/migrations/013_plan_modulos.sql) |
| Verificar si un feature está activo | `SELECT is_feature_enabled('clave_flag')` — ver [011_feature_flags.sql](supabase/migrations/011_feature_flags.sql) |
| Invitar usuarios con cola confiable | `SELECT crear_invitacion(email, rol_id)` — ver [012_invitaciones_pendientes.sql](supabase/migrations/012_invitaciones_pendientes.sql) |
| Configurar MFA por empresa | `SELECT set_mfa_config(...)` — ver [015_mfa_config.sql](supabase/migrations/015_mfa_config.sql) |
| Configurar SSO SAML | Tabla `saml_configuracion` — ver [016_saml_sso.sql](supabase/migrations/016_saml_sso.sql) |
| Provincias/ciudades de Ecuador | Tablas `provincias`, `ciudades` — ver [008_catalogo_geografico.sql](supabase/migrations/008_catalogo_geografico.sql) |
| Sistema de diseño UI (fluent_ui) | [ADR-004](adrs/ADR-004_flutter-single-codebase.md) — NavigationView, TabView, FluentThemeData, integración Syncfusion |
| Paquetes Flutter y versiones | [pubspec-referencia.md](pubspec-referencia.md) |
| Documentación de un módulo específico | Directorio del módulo correspondiente |
