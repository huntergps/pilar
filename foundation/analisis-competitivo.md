# PILAR ERP — Análisis Competitivo y Brechas vs ERPs Enterprise

> Generado: 2026-02-22 | Auditado con 3 agentes paralelos
> Fuentes: documentación foundation/ (19 migraciones + 30+ docs) + investigación ERPs (web 2024–2025)

---

## Índice

1. [Resumen Ejecutivo](#1-resumen-ejecutivo)
2. [Foundation PILAR — Inventario Completo](#2-foundation-pilar--inventario-completo)
3. [ERPs Enterprise Globales — SAP, Oracle, Dynamics, NetSuite, Workday](#3-erps-enterprise-globales)
4. [ERPs Cloud Modernos y Latam](#4-erps-cloud-modernos-y-latam)
5. [Tabla Comparativa General](#5-tabla-comparativa-general)
6. [Gap Analysis — Qué le falta a PILAR](#6-gap-analysis)
7. [Ventajas Competitivas de PILAR](#7-ventajas-competitivas-de-pilar)
8. [Recomendaciones de Roadmap](#8-recomendaciones-de-roadmap)

---

## 1. Resumen Ejecutivo

PILAR ERP está construido sobre una **capa Foundation técnicamente sólida y lista para producción** que compite favorablemente con ERPs de clase media-alta (Acumatica, ERPNext, Odoo Enterprise) y supera a todos los ERPs regionales latinoamericanos (Alegra, Siigo, Defontana, Holded) en arquitectura de plataforma.

**Fortalezas únicas de PILAR:**
- Multi-tenancy RLS nativo en PostgreSQL (ningún competidor regional lo tiene)
- Offline-first real con Brick (ningún competidor en Latam lo ofrece)
- SRI Ecuador nativo e integrado en el ERP (Datil lo hace pero no es ERP)
- Flutter mono-codebase para 6 plataformas (ventaja operativa significativa)
- Sistema modular tipo Odoo pero con seguridad a nivel de base de datos

**Brechas principales vs ERPs enterprise (SAP/Oracle/Dynamics):**
- Sin studio/low-code para customización sin código
- Sin BI integrado (requiere herramienta externa)
- Sin marketplace de extensiones de terceros
- Cifrado columnar en reposo no implementado

**Mercado objetivo validado:** El mercado ERP en Latinoamérica crecerá a $5.15 mil millones para 2030 (CAGR 13.6%). Los actores regionales dominan precio pero tienen gaps arquitectónicos severos que PILAR resuelve.

---

## 2. Foundation PILAR — Inventario Completo

### 2.1 Autenticación y Seguridad ✅ Completo

| Componente | Estado | Detalle |
|-----------|--------|---------|
| Auth JWT | ✅ | Supabase Auth + `custom_access_token_hook` (019_auth_hook.sql) inyecta `empresa_id` en cada JWT |
| MFA por empresa | ✅ | Tabla `mfa_configuracion` — `mfa_obligatorio`, `roles_requieren_mfa[]`, `dias_gracia` |
| SSO SAML 2.0 | ✅ | Tabla `saml_configuracion` — entity_id, sso_url, cert X.509, JIT provisioning, log sesiones |
| OAuth social | ✅ | Google, Microsoft (vía Supabase Auth) |
| Magic Link | ✅ | Nativo Supabase Auth |
| Sesiones | ✅ | Tabla `sesiones_usuario` — dispositivo, ip_address, revocación remota |
| Timeout inactividad | ✅ | Parámetro `timeout_inactividad_minutos` (default 30) |
| Dos apps separadas | ✅ | PILAR ADMIN (`admin.pilar.ec`, `is_saas_admin=true`) vs PILAR ERP (cliente) |

**Patrón JWT:**
```sql
-- custom_access_token_hook inyecta empresa_id sin llamadas externas
SELECT ue.empresa_id INTO v_empresa_id FROM usuarios_empresa ue
WHERE ue.usuario_id = v_user_id AND ue.activo = true
ORDER BY ue.ultimo_acceso DESC NULLS LAST LIMIT 1;
```

### 2.2 Multi-tenancy ✅ Completo y Robusto

| Componente | Estado | Detalle |
|-----------|--------|---------|
| RLS nativo PostgreSQL | ✅ | `empresa_id = (SELECT private.get_empresa_id())` en TODAS las tablas |
| Función cacheada | ✅ | `private.get_empresa_id()` — extrae del JWT, evita re-evaluación por fila |
| Schema privado | ✅ | `CREATE SCHEMA private` revocado de acceso público |
| Multi-empresa por usuario | ✅ | Tabla `usuarios_empresa` (N:M) — usuario en múltiples empresas con roles diferentes |
| Cambio de empresa activa | ✅ | `set_empresa_activa()` → `refreshSession()` → hook inyecta nuevo `empresa_id` |
| Tests de aislamiento | ✅ | pgTAP setup en `rls-testing-guide.md` con templates de cross-tenant violation |

**Patrón obligatorio en cada tabla:**
```sql
ALTER TABLE <tabla> ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON <tabla>
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));
```

### 2.3 Sistema de Roles y Permisos (RBAC) ✅ Completo

**11 roles del sistema** (`es_sistema=true`, `empresa_id=NULL`):

| Rol | Tipo | Alcance |
|-----|------|---------|
| SUPER_ADMIN | Plataforma | Solo equipo PILAR — acceso a todas las empresas |
| SAAS_ADMIN | Plataforma | Gestión SaaS, suscripciones — sin datos operativos |
| ADMIN | Empresa | Acceso completo + usuarios + configuración |
| GERENTE | Empresa | Reportes, aprobaciones, dashboards |
| CONTADOR | Operativo | Contabilidad, tesorería, tributación |
| FACTURADOR | Operativo | Facturas, notas, cobros, clientes |
| VENDEDOR | Operativo | Cotizaciones, OV, clientes asignados |
| COMPRADOR | Operativo | OC, recepción, retenciones |
| BODEGUERO | Operativo | Stock, movimientos, transferencias |
| CAJERO | Operativo | Caja, cobros, pagos, arqueos |
| LECTURA | Transversal | Ver todo, sin crear/editar |

**Permisos granulares** (patrón `modulo.recurso.accion`):
- Tabla `permisos` (codigo UNIQUE) + tabla relación `roles_permisos`
- Función `private.has_permission(permiso_codigo)` — bypass para SUPER_ADMIN
- Trigger `014_auto_permisos.sql` — nuevos permisos → ADMIN los hereda automáticamente
- Roles personalizados por empresa soportados (`empresa_id = <empresa_específica>`)

### 2.4 Sistema Modular ✅ Completo (Type-Safe)

**24 módulos totales:**
- **Infraestructura** (3): Dashboard, Administración, Comunicación — siempre activos
- **Core** (7): Entidades, Facturación, Ventas, Compras, Inventario, Contabilidad, Tesorería
- **Extensión** (14): POS, eCommerce, RRHH, CRM, Proyectos, IA, Pagos, Citas, Taller, RMA, Activos, Consumibles, Suscripciones, Intercompany

**Tablas:** `modulos`, `modulo_dependencias`, `modulos_empresa`, `plan_modulos`

**Funciones PostgreSQL:**
- `resolve_module_dependencies()` — CTE recursivo, orden topológico
- `activate_module(empresa_id, modulo_id)` — transaccional con dependencias
- `deactivate_module()` — valida que ningún módulo activo depende

**Flutter (type-safe, compilado):**
- Interface `PilarModule`: id, routes, menuItems, dashboardWidgets, slotWidgets
- `ModuleRegistry` — mapa estático compilado
- `modulosActivosProvider` (Riverpod) → invalida router dinámico
- `ModuleSlot(slotId)` — inyección de widgets entre módulos

**Module Service Bus (MSB):** extensiones NUNCA INSERT directo en tablas core → `module_bus.<modulo>.<operacion>()` — gateway verifica si módulo destino está activo.

### 2.5 Gestión de Empresas y Onboarding ✅ Completo

**Flujo onboarding:**
1. Sign-up → trigger `after_auth_user_created()` crea empresa TRIAL + membresía ADMIN
2. Activa módulos infraestructura + plan FREE
3. Crea `configuracion_empresa` con defaults
4. Flutter detecta `empresa.ruc IS NULL` → redirige a `/onboarding`
5. Wizard: datos empresa → activar módulos → invitar usuarios

**Tabla `empresas`:** nombre, ruc (UNIQUE), tipo_ruc, ubicación, branding (logo, colores), plan_id, estado (TRIAL|ACTIVO|SUSPENDIDO|CANCELADO), trial_hasta, metodos_auth, dominio_sso.

**Bucket Storage privado:** creado automáticamente en INSERT de empresa vía Database Webhook → `auth-setup-handler`.

### 2.6 Usuarios e Invitaciones ✅ Completo

**Tabla `usuarios_empresa`:** N:M con rol, activo, invitado_por, ultimo_acceso, preferencias JSONB (tema, fuente, idioma, modulo_inicio).

**Invitaciones:**
- Tabla `invitaciones_pendientes` — audit trail PENDIENTE→ENVIADA→ACEPTADA
- Edge Function `invite-user`:
  - Caso A (usuario existente): INSERT directo en `usuarios_empresa`
  - Caso B (nuevo): `crear_invitacion()` + `inviteUserByEmail()` + `marcar_invitacion_enviada()`

**RPC `get_mis_empresas()`:** lista empresas del usuario con rol, logo, estado activo.

### 2.7 Catálogos Base ✅ Completo

| Catálogo | Registros | Migración |
|----------|-----------|-----------|
| Países | 249 (ISO 3166) | 008 |
| Monedas | 228 (ISO 4217) | 009 |
| Unidades de Medida | ~50 (7 categorías) | 009 |
| Provincias Ecuador | 24 (códigos SRI 01-24) | módulo facturacion_ec |
| Ciudades Ecuador | 26 capitales | módulo facturacion_ec |

### 2.8 Precisión Numérica y Monetaria ✅ Estricto

| Contexto | PostgreSQL | Dart |
|----------|-----------|------|
| Montos (facturas, totales) | DECIMAL(14,2) | `decimal: ^2.3.3` |
| Cantidades, precios unitarios | DECIMAL(18,6) | Decimal |
| Tarifas impuesto | DECIMAL(4,2) | Decimal |
| Tipos de cambio | DECIMAL(12,6) | Decimal |

**Función `financial_round(valor, decimales=2)`** (017_financial_functions.sql):
- ROUND_HALF_UP — idéntico a validaciones SRI
- **Regla de oro:** solo redondear resultado final, NUNCA intermedios
- Validación: `ABS(total - suma_lineas) ≤ 0.01`

**Prohibido:** `FLOAT`, `REAL`, `DOUBLE PRECISION` en PostgreSQL; `double`, `num` en Dart.

### 2.9 Background Jobs ✅ Completo (ADR-007)

**pg_cron — 14 jobs totales:**
- Foundation: `pilar_cleanup_expired_sessions` (3 AM UTC diario)
- Módulos: jobs propios prefijados `pilar_<modulo>_<descripcion>`
- Vista de monitoreo: `v_cron_job_health` + tabla `cron.job_run_details`

**pgmq — 4 colas:**

| Cola | Uso | Prioridad |
|------|-----|-----------|
| `pilar_docs_queue` | Documentos SRI, autorizaciones, RIDE | Alta |
| `pilar_notifications_queue` | Email, WhatsApp, SMS, Telegram | Media |
| `pilar_integrations_queue` | Webhooks, sincronizaciones externas | Media |
| `pilar_ai_queue` | Embeddings, generación vectorial (pgvector) | Baja |

**Retry:** exponential backoff, máximo 5 intentos en 24h. Regla: todo lo que implique llamadas HTTP a terceros → pgmq (nunca bloquear al usuario).

### 2.10 Storage y Adjuntos ✅ Completo

- 1 bucket privado por empresa (`empresa-{empresa_id}`) creado en onboarding
- Subcarpetas: `/logos/`, `/adjuntos/`, `/avatares/`
- Tabla `adjuntos` polimórfica: `tabla_origen` + `registro_id` (FK suave)
- Edge Function `upload-logo`: valida MIME/tamaño, actualiza `empresas.logo_url`

### 2.11 Audit Trail ✅ Completo

**Tabla `registro_actividad`:**
- Campos: tabla_origen, registro_id, accion (CREATE|UPDATE|DELETE|CONFIRM|CANCEL|ANULAR)
- `datos_antes` (JSONB), `datos_despues` (JSONB), `campos_cambiados` (TEXT[])
- `ip_address` (INET), `user_agent`, `created_at` (TIMESTAMPTZ)
- Insertado por función `private.registrar_actividad()` (SECURITY DEFINER, sin RLS)

### 2.12 Feature Flags ✅ Granular

**Evaluación en cascada:**
1. Override por usuario (`feature_flag_usuarios`)
2. Flag de empresa (`feature_flags.empresa_id IS NOT NULL`)
3. Flag global (`empresa_id IS NULL`)

**Capacidades:** rollouts graduales (`porcentaje=50`), betas por plan (`plan_minimo='PRO'`), flags de emergencia.

**RPC:** `is_feature_enabled('clave')` → BOOLEAN.

### 2.13 Secuencias (Numeración Multi-tenant) ✅ Completo

**Tabla `secuencias_contador`:** `empresa_id` + `codigo` UNIQUE, `siguiente` BIGINT, `padding`, `prefijo`.

**Función `next_secuencial(empresa_id, codigo)`:** atómica (FOR UPDATE), genera "000001", "000002"…

### 2.14 Extensión de Campos ✅ Completo

**Sistema dual:**
- **ALTER TABLE** con naming `<modulo>_<campo>` (idempotente: `IF NOT EXISTS`)
- **Tabla `field_extensions`:** metadatos de qué módulo añadió cada campo
- **Soft references** cross-módulo: UUID nullable sin FK constraint (validación en RPC)

### 2.15 Internacionalización ✅ UTC-First

- Todas las fechas: `TIMESTAMPTZ` en UTC
- `configuracion_empresa.zona_horaria` (ej: 'America/Guayaquil')
- `configuracion_empresa.moneda_id` + tabla `tipos_cambio`
- Preferencia de idioma por usuario en `usuarios_empresa.preferencias→'idioma'`
- Conversión de timezone: en el cliente Flutter con `intl` package

### 2.16 UI Framework ✅ Sistema de Diseño Completo (ADR-004)

**Stack UI:**
- `fluent_ui ^4.14.0` — FluentApp, NavigationView, TabView, MenuBar, ContentDialog
- `syncfusion_flutter_* ^32.2.5` — DataGrid, Charts, PDF, Calendar, Gauges
- `go_router ^12.0.0` — ShellRoute para layout modular
- `riverpod ^2.0.0` — estado global, providers invalidables
- `brick_offline_first_with_supabase` — SQLite local ↔ PostgreSQL remoto
- `decimal ^2.3.3` — aritmética monetaria exacta

**PilarShell — breakpoints adaptativos:**

| Breakpoint | Ancho | Navegación | Escala |
|-----------|-------|-----------|--------|
| COMPACT | <600px | Drawer | 0.85 |
| MEDIUM | 600-840px | Rail | 0.92 |
| EXPANDED | 840-1200px | Sidebar | 1.0 |
| LARGE | >1200px | Sidebar full | 1.0 |

**Reglas UI obligatorias:**
- `FluentTheme.of(context)` — NUNCA `Theme.of(context)` ni `Colors.*` hardcoded
- `ProgressRing()` — NUNCA `CircularProgressIndicator`
- `FluentIcons.*` — NUNCA `Icons.*`
- `ContentDialog` — NUNCA `AlertDialog`
- `SfDataGrid` (>600px) / `ListView+cards` (<600px)

### 2.17 Edge Functions Foundation

| Función | Propósito | Auth |
|---------|-----------|------|
| `auth-setup-handler` | Crea bucket Storage en INSERT de empresa (Database Webhook) | verify_jwt: false (valida internamente) |
| `invite-user` | Invita usuarios (existente → membresía, nuevo → inviteUserByEmail) | verify_jwt: true |
| `upload-logo` | Sube logo empresa, valida MIME/tamaño, actualiza DB | verify_jwt: true |
| `_shared/cors.ts` | Headers CORS reutilizados por todas las EF | — |
| `_shared/db-client.ts` | `getPoolerUrl()` — fuerza puerto 6543 para PG desde Deno | — |

### 2.18 Resumen Cuantitativo Foundation

| Métrica | Valor |
|--------|-------|
| Migraciones Foundation | 19 (001_core → 019_auth_hook) |
| Migraciones Módulos (ensambladas) | 79 (`mod_020_*.sql` → `mod_098_*.sql`) |
| Total migraciones en build | 98 |
| Edge Functions Foundation | 5 (3 funciones + 2 helpers _shared) |
| Edge Functions Módulos | ~18 |
| Tablas Foundation | ~25 |
| Roles sistema | 11 |
| Permisos base | 18 (plataforma.*, dashboard.*, comunicacion.*) |
| Módulos totales | 24 |
| RPCs documentadas | 85+ |
| pg_cron jobs | 14 (1 foundation + 13 módulos) |
| pgmq colas | 4 |
| Catálogos (países + monedas + UoM) | ~530 registros |
| Documentación Foundation | 30+ archivos .md + 9 ADRs |

---

## 3. ERPs Enterprise Globales

> Investigación 2024–2025. Foco exclusivo en capa de plataforma/foundation — no funcionalidad de negocio.

### SAP S/4HANA

**Plataforma:** SAP BTP (Business Technology Platform) — base de toda la suite SAP.

**Multi-tenancy:** RISE with SAP = single-tenant dedicado por cliente en la nube SAP. Sin RLS de PostgreSQL — aislamiento a nivel de instancia completa. Cada cliente tiene su propio sistema SAP con schema propio.

**IAM (Identity):**
- SAP IAS (Identity Authentication Service) — SSO enterprise con SAML 2.0, OAuth 2.0, OIDC
- SAP IPS (Identity Provisioning Service) — sincronización de usuarios desde Active Directory/LDAP
- MFA: authenticator apps, SMS, email OTP
- Role-based: SAP Authorization Concept con objetos de autorización (más granular que RBAC simple)

**Sistema de roles SAP (único en el mercado):**
- Objetos de autorización → Perfil → Rol → Usuario
- Hasta 4 niveles de herencia de permisos
- Transacción SU01/PFCG para gestión
- Segregación de funciones (SoD) como feature nativa

**Módulos SAP (activación):**
- SAP tiene licencias modulares: FI, CO, SD, MM, PP, HR, etc.
- Activación vía contratos de licencia + configuración (no botón de "activar")
- SAP App Center: marketplace de extensiones certificadas
- SAP BTP Extensions SDK para desarrollar extensiones custom

**Extensibilidad:**
- ABAP (lenguaje propietario SAP) para customización profunda
- SAP BTP Low-Code/No-Code: SAP Build Apps (antes AppGyver), SAP Build Process Automation
- In-app extensibility: fields custom, vistas custom sin ABAP en S/4HANA Cloud
- Side-by-side extensibility: apps en BTP que extienden S/4HANA sin tocar el core

**Background Jobs:**
- SAP Job Scheduler (BTP) — jobs cloud-native con retry, alertas
- SAP Advanced Job Scheduling — jobs complejos con dependencias
- SM36/SM37 (legacy) para on-premise

**Audit / Compliance:**
- SAP Audit Management — log centralizado con retención configurable
- Change Document Object — auditoria de campos específicos
- GDPR tools nativos: anonimización, derecho al olvido
- SAP GRC (Governance, Risk, Compliance) — módulo dedicado

**Message Broker — SAP Advanced Event Mesh (AEM):**
El broker más avanzado analizado en el mercado:
- Protocolos: AMQP 1.0, MQTT 3.1/5.0, REST, JMS 1.1
- Event streaming: tópicos con replay (retener eventos históricos)
- Cross-region clustering: brokers en múltiples regiones con failover automático
- Event Portal: catálogo visual de eventos con AsyncAPI spec
- Compatible con Kafka como consumidor/productor

**APIs:**
- SAP API Business Hub: 2,500+ APIs documentadas
- OData (V2 y V4) como protocolo principal
- REST APIs para S/4HANA Cloud
- SAP Advanced Event Mesh (AEM): AMQP, MQTT, REST, JMS con event replay
- iDocs (legacy integration) aún activo

**Precio:** €100,000–€1M+/año según tamaño. Sin usuarios ilimitados — licencia por usuarios nombrados o concurrentes.

**Limitaciones:**
- Complejidad de implementación: 6-18 meses mínimo
- Costo prohibitivo para PYMES
- ABAP como lenguaje propietario = lock-in severo
- Upgrades caros y lentos

---

### Oracle Fusion Cloud ERP

**Plataforma:** Oracle Cloud Infrastructure (OCI) + Oracle Integration Cloud (OIC).

**Multi-tenancy:** Multi-tenant compartido en OCI con aislamiento fuerte a nivel de aplicación. Oracle gestiona el aislamiento — cliente no tiene acceso directo a Oracle DB subyacente.

**IAM:**
- OCI IAM — gestión de identidades con SAML 2.0, OAuth 2.0, OIDC
- Oracle Identity Governance para provisioning
- MFA nativo (TOTP, SMS, push)
- Adaptive Authentication — riesgo basado en comportamiento
- **Passkeys / FIDO2 (2024)**: Oracle fue el primer ERP enterprise en implementar autenticación sin contraseña con passkeys nativos. Disponible desde Fusion 24A en todos los tenants cloud.

**Sistema de roles Oracle (4 niveles):**
- Abstract roles → Job roles → Duty roles → Privilege roles (4 niveles de herencia)
- Data security: grant a conjuntos de datos (instancias de datos específicas)
- Segregation of Duties: Oracle Access Controls Governor
- Instance sets: filtrado de datos por instancia (equivalente parcial a RLS, pero en capa de aplicación)

**Extensibilidad:**
- Oracle Application Composer: no-code para objetos, campos, vistas, flujos
- Page Composer: drag-and-drop para modificar pantallas
- Oracle VBCS (Visual Builder Cloud Service): desarrollo low-code apps custom
- Groovy scripts para validaciones y lógica custom
- Oracle Integration Cloud: conectores a sistemas externos

**Background Jobs:**
- Oracle Enterprise Scheduler (ESS) — jobs con dependencias, retry, alertas
- Procesamiento batch con monitor de estado en tiempo real

**Audit:**
- Oracle AVDF (Audit Vault and Database Firewall) — auditoría a nivel de BD
- Fusion Audit Trail: cambios en todos los objetos de negocio
- Retención configurable, exportación a SIEM

**APIs:**
- Oracle REST Data Services (ORDS): REST automático para objetos de BD
- 500+ REST APIs documentadas en Oracle API Platform
- Oracle Integration Cloud: 200+ conectores pre-built (SAP, Salesforce, NetSuite, etc.)
- Webhooks nativos

**Precio:** $625+/usuario/mes para Fusion ERP completo. Mínimo 25 usuarios. Contrato mínimo 3 años.

---

### Microsoft Dynamics 365

**Plataforma:** Microsoft Power Platform + Azure.

**Multi-tenancy:** Azure multi-tenant con Dataverse (antes Common Data Service) como capa de datos compartida. Cada organización (tenant) tiene su propio entorno Dataverse — bases de datos separadas en Azure SQL.

**IAM:**
- Azure Active Directory (Entra ID): SAML, OAuth 2.0, OIDC — el más maduro del mercado
- Conditional Access: MFA adaptativo, device compliance, location policies
- **Entra Privileged Identity Management (PIM)**: acceso just-in-time (JIT) — los roles privilegiados están inactivos por defecto, el usuario los "activa" por N horas con justificación y aprobación. Único en el mercado ERP. Previene uso accidental de privilegios elevados.
- Microsoft Authenticator: app MFA corporativa

**Sistema de roles Dynamics:**
- Security Roles: tabla-por-tabla, columna-por-columna (más granular que SAP/Oracle para datos)
- Business Units: jerarquías de acceso geográficas/organizacionales
- Field-level security: control por campo individual (capacidad nativa)
- Teams: grupos de usuarios con roles compartidos

**Extensibilidad (Power Platform — lo más maduro del mercado):**
- **Power Apps**: crear apps canvas o model-driven sin código
- **Power Automate**: workflows con 400+ conectores (RPA incluido)
- **Power BI**: BI integrado nativo en el ERP (diferenciador único)
- **Copilot Studio**: chatbots con IA sin código
- **Dataverse extensibility**: campos custom, tablas custom, relaciones

**Background Jobs:**
- Azure Service Bus: colas de mensajes enterprise (garantías exactly-once)
- Azure Functions: serverless para procesamiento asíncrono
- Recurring Jobs nativos en Dynamics para batch processing

**Audit:**
- Audit Log integrado: cambios con usuario, timestamp, valores antes/después
- Microsoft Purview: compliance, GDPR, eDiscovery, retención de datos
- Azure Monitor + Log Analytics: telemetría de aplicación

**APIs:**
- Dataverse Web API: OData V4, 100% de entidades expuestas
- Azure API Management para governance de APIs
- Power Platform connectors: 800+ conectores certificados

**BI Integrado (diferenciador clave):**
- Power BI nativo en Dynamics: dashboards en tiempo real sin exportar datos
- AI-powered insights: anomaly detection, forecasting con Azure ML

**Precio:**
- Dynamics 365 Finance: $180/usuario/mes
- Dynamics 365 Business Central (PYMES): $70-100/usuario/mes
- Power Platform premium: $20-40/usuario/mes adicional

---

### NetSuite (Oracle)

**Plataforma:** SaaS cloud-native (pioneer del ERP cloud desde 1998). Oracle la adquirió en 2016.

**Multi-tenancy:** Single-tenant dedicado. Cada cliente tiene su propia instancia aunque comparta infraestructura física. No hay acceso a base de datos subyacente.

**IAM:**
- SSO con SAML 2.0 y OAuth 2.0
- MFA: authenticator apps, SMS
- IP Allowlisting por usuario/rol
- Two-factor authentication obligatorio para administradores

**Roles NetSuite:**
- Roles predefinidos (Administrator, Accountant, Sales Rep, etc.)
- Roles custom con permisos por formulario, lista, transacción
- Restricciones de subsidiaria (multi-empresa nativa)
- Record-level permissions: by owner, by department

**Extensibilidad (SuiteCloud):**
- **SuiteScript 2.x** (JavaScript server-side): scripting para lógica de negocio
- **SuiteFlow**: workflow builder visual sin código
- **SuiteBuilder**: campos custom, sublistas, formularios — no-code
- **SuiteAnalytics**: reportes y dashboards custom
- **SuiteTalk**: APIs (REST + SOAP + SuiteQL — SQL sobre datos NetSuite)

**Multi-empresa (fortaleza de NetSuite):**
- Subsidiaries nativas: hasta 500+ subsidiarias en un plan
- One World: consolidación financiera multi-moneda, multi-idioma, multi-impuesto
- Intercompany: transacciones y eliminaciones automáticas
- Multi-currency: 180+ monedas con tipos de cambio automáticos

**Background Jobs:**
- Scheduled Scripts (SuiteScript): jobs programados con cron-like scheduling
- Map/Reduce Scripts: procesamiento paralelo para grandes volúmenes
- Queue-based processing interno (no configurable por usuario)

**APIs:**
- REST API: 150+ record types
- SuiteQL: SQL-like sobre datos NetSuite (muy potente para reportes)
- SOAP (legacy): completo pero verboso
- OAuth 2.0 para todas las APIs

**Precio:** $999+/mes (base) + $99-129/usuario/mes + módulos adicionales. Contrato mínimo 1 año.

---

### Workday

**Plataforma:** SaaS cloud nativo. Foco: HCM (Human Capital Management) + Finance. No es un ERP generalista completo.

**Multi-tenancy — "The Grid" (modelo de aislamiento más seguro del mercado):**
Workday usa un modelo llamado "The Grid" donde cada tenant es una instancia completamente independiente con:
- Infraestructura de cómputo dedicada (no compartida)
- Base de datos propia (sin RLS ni Dataverse compartido)
- Versiones actualizadas simultáneamente en todos los tenants (pods de actualización masiva)
- Zero-downtime updates: el cliente nunca ve mantenimiento programado
Costo: mucho más alto que multi-tenant compartido, pero aislamiento absoluto. Única empresa del mercado con este modelo a escala masiva.

**IAM:**
- Workday Adaptive Authentication: MFA adaptativo por comportamiento
- SAML 2.0, OAuth 2.0, OIDC
- Role-Based Access Control muy granular (security groups)
- Segregación de funciones nativa

**Extensibilidad:**
- **Workday Studio**: IDE para extensiones (requiere Java/XML)
- **Workday Extend**: platform para apps custom (más accesible que Studio)
- **Calculated fields**: sin código para métricas derivadas
- **Custom objects**: campos y entidades custom

**Background Jobs:**
- Business Process Framework: workflows configurables para cualquier proceso
- Scheduled jobs internos para nómina, reportes, integraciones
- No configurable directamente por el usuario

**APIs:**
- Workday RaaS (Reports as a Service): reportes expuestos como API
- REST API (limitada comparada con competidores)
- SOAP/Web Services: más completo pero legacy
- Prism Analytics: data lake integrado

**Precio:** $100-200/empleado/año para HCM. Finance adicional. Mínimo 500 empleados recomendado.

---

## 4. ERPs Cloud Modernos y Latam

### 4.1 Odoo 17/18 — Análisis Técnico Profundo

**Multi-tenancy:** Base de datos **separada por tenant** (no row-level). Un servidor Odoo puede servir N bases PostgreSQL. Aislamiento total pero costoso operativamente para SaaS masivo.

**Limitación crítica de seguridad:** el filtrado de datos se hace en la capa Python (ORM), NO en PostgreSQL. Acceso directo a la base de datos bypasea completamente toda la seguridad. PILAR con RLS es arquitectónicamente superior.

**ORM Python:**
```python
class SaleOrder(models.Model):
    _name = 'sale.order'
    _inherit = ['mail.thread']  # Mixins via herencia
    name = fields.Char(required=True)
    amount_total = fields.Float(compute='_compute_amount', store=True)
    state = fields.Selection([...], tracking=True)
```

**Sistema de seguridad (dos capas):**
- `ir.model.access` (CSV): CRUD a nivel de modelo por grupo
- `ir.rule` (dominio Python): filtrado de registros específicos
- Sin RLS nativo de PostgreSQL

**Sistema de módulos:**
```python
# __manifest__.py
{'name': 'Sales', 'depends': ['product', 'account'], 'installable': True}
```
Instalación: crea tablas SQL, carga datos XML, registra en `ir.module.module`. Desinstalación problemática (puede dejar artifacts).

**Background Jobs:** `ir.cron` — worker dedicado. Simple pero funcional. Para alta frecuencia requiere Celery + Redis externo.

**Bus de eventos:** `bus.bus` basado en tabla PostgreSQL con polling. Menos robusto que Supabase Realtime (Elixir + Phoenix Channels).

**Studio (solo Enterprise):** drag-and-drop para campos, vistas, reportes. Genera módulos Python/XML serializados en BD.

**APIs:** JSON-RPC principal; REST API desde v16. API externa solo en plan Custom ($46.70/usuario/mes).

**Precios:**
| Plan | Precio/usuario/mes |
|------|--------------------|
| One App Free | $0 (1 sola app) |
| Standard | $31.10 (anual) |
| Custom | $46.70 (anual) + Studio + API |

**Limitaciones críticas:**
1. Seguridad bypaseable: filtrado en Python, no en PostgreSQL
2. Multi-tenant = multi-database: costoso para SaaS con miles de tenants
3. Customizaciones rompen upgrades de versión mayor
4. `wkhtmltopdf` como generador PDF (obsoleto, bugs de rendering)

### 4.2 ERPNext / Frappe Framework

**Multi-tenancy:** Sites separados (base de datos por site). Similar a Odoo.

**Diferenciadores técnicos vs Odoo:**
- **Celery + Redis** para background jobs (más robusto que `ir.cron`)
- **Socket.IO** (NodeJS) para realtime (más robusto que `bus.bus`)
- REST API automática por DocType sin configuración
- Frappe Cloud Marketplace + Open Source (MIT)

**Stack:** Python 3 + MariaDB/PostgreSQL + Redis + NodeJS + Socket.IO.

**Precio:** Self-hosted gratis. Frappe Cloud: $50-100/mes hosting + $10-50/usuario.

### 4.3 Acumatica (xRP Platform)

**Diferenciador único:** Precio por **volumen de transacciones, NO por usuario** — usuarios ilimitados sin costo adicional.

**Stack:** .NET/C# + SQL Server/MySQL. Multi-tenant configurable.

**Customización:** Customization Projects en C# sin recompilar el core.

**Precio:** $15,000-70,000+/año. Sin costo por usuario adicional.

**Ecuador:** No soportado nativamente.

### 4.4 Competidores Regionales Latam

| ERP | País base | Fortaleza | Debilidad | Ecuador SRI |
|-----|-----------|-----------|-----------|-------------|
| **Alegra** | Colombia | API excelente, precio ($7/mes), DIAN maduro | No es ERP completo | Básico |
| **Siigo** | Colombia | Líder Colombia (1M+ clientes), contabilidad CO | Tecnología legacy parcial, API limitada | Básico |
| **Defontana** | Chile | ERP completo en AWS, BI nativo (QuickSight) | Sin API pública documentada, sin Ecuador | No |
| **Holded** | España | UI moderna, integración Zoho/Slack | Localizaciones Latam incompletas | No |
| **Datil** | Ecuador | SRI nativo completo (los 6 docs), API-first | Solo facturación, NO es ERP | ✅ Nativo completo |
| **Facturero Móvil** | Ecuador | SRI + compras XML + ATS + 104 | Muy básico, sin módulos de gestión | ✅ Nativo |
| **Monica ERP** | Ecuador/Perú | Plan cuentas NIIF Ecuador, declaraciones SRI | Desktop-first, sin offline | Básico |

---

## 5. Tabla Comparativa General

| Capacidad | SAP S/4HANA | Oracle Fusion | Dynamics 365 | NetSuite | Odoo 17 | ERPNext | PILAR ERP |
|-----------|------------|---------------|--------------|----------|---------|---------|-----------|
| **Multi-tenancy** | Instancia dedicada | Multi-tenant app | Dataverse por org | Instancia dedicada | DB por tenant | DB por site | **RLS PostgreSQL (row-level nativo)** |
| **Seguridad en BD** | Application | Application | Dataverse rules | Application | ❌ Python only | Application | **✅ PostgreSQL RLS** |
| **MFA** | ✅ | ✅ | ✅ Azure MFA | ✅ | ✅ | ✅ | ✅ |
| **SSO SAML** | ✅ SAP IAS | ✅ OCI IAM | ✅ Azure AD | ✅ | Enterprise | ✅ | ✅ |
| **RBAC granular** | ✅ Objetos Auth | ✅ Job/Duty roles | ✅ Field-level | ✅ Record-level | ✅ | ✅ | ✅ Field+Record |
| **SoD nativa** | ✅ GRC | ✅ Access Gov | ✅ Purview | Parcial | ❌ | ❌ | ⚠️ Parcial |
| **Sistema modular** | Licencias SAP | Licencias Oracle | Apps Marketplace | SuiteApps | Python modules | DocType Python | **Type-safe compiled** |
| **No-code Studio** | ✅ SAP Build | ✅ App Composer | ✅ Power Apps | ✅ SuiteBuilder | ✅ Enterprise | ✅ Custom Fields | ❌ No implementado |
| **Marketplace** | SAP App Center | Oracle Marketplace | AppSource (5000+) | SuiteApp.com | apps.odoo.com (17K+) | Frappe Cloud | ❌ No implementado |
| **Background jobs** | SAP Job Scheduler | Oracle ESS | Azure Service Bus | Scheduled Scripts | ir.cron (simple) | **Celery + Redis** | **pg_cron + pgmq** |
| **APIs documentadas** | 2,500+ | 500+ | OData completo | REST + SuiteQL | JSON-RPC/REST | Auto REST | 85+ RPCs |
| **BI integrado** | SAP Analytics Cloud | Oracle Analytics | **✅ Power BI nativo** | SuiteAnalytics | Odoo Reporting | Frappe Analytics | ❌ Externo |
| **Offline-first** | ❌ | ❌ | Parcial (mobile) | ❌ | ❌ | ❌ | **✅ Brick SQLite** |
| **Multi-plataforma** | Web + app limitada | Web + app limitada | Web + apps nativas | Web + app limitada | Web + app limitada | Web + PWA | **✅ 6 plataformas Flutter** |
| **Ecuador SRI** | ❌ | ❌ | ❌ | ❌ | Via l10n_ec | Via comunidad | **✅ Nativo completo** |
| **Precio entrada** | €100K+/año | $600K+/año | $70/usuario/mes | $1K/mes + usuarios | $31/usuario/mes | $0 | TBD |
| **Usuarios ilimitados** | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | TBD |
| **Open Source** | ❌ | ❌ | ❌ | ❌ | Community LGPL | **✅ MIT** | Futuro |
| **Audit trail granular** | ✅ AVDF | ✅ | ✅ Purview | ✅ | Via mail.thread | ✅ | **✅ datos_antes/despues** |
| **Cifrado columnar** | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| **Multi-empresa** | ✅ | ✅ | ✅ Business Units | **✅ 500+ subsidiarias** | ✅ | ✅ | ✅ |
| **Background en BD** | Externo | Externo | Azure externo | Interno | ir.cron simple | Redis externo | **✅ pg_cron nativo** |
| **Passkeys / FIDO2** | ❌ | **✅ 2024 (primero)** | ✅ Entra | Parcial | ❌ | ❌ | ❌ |
| **JIT Privileged Access** | ✅ SAP GRC | ❌ | **✅ Entra PIM** | ❌ | ❌ | ❌ | ❌ |
| **Event Mesh / Broker** | **✅ AEM (AMQP/MQTT)** | Oracle AQ | Azure Service Bus | Interno no exp. | bus.bus (polling) | Redis simple | pgmq |
| **Audit trail inmutable** | ✅ | ✅ AVDF | ✅ Purview | ✅ | Parcial | Parcial | ⚠️ Existe sin garantía write-once |
| **Consolidación multi-empresa** | ✅ | ✅ | ✅ | **✅ One World** | ✅ | Parcial | ⚠️ Sin consolidación automática |
| **Aislamiento por tenant** | Instancia dedicada | **App-level 4-layer** | Dataverse por org | Instancia dedicada | DB separada | DB separada | **PostgreSQL RLS row-level** |

---

## 6. Gap Analysis — Qué le falta a PILAR

### 6.1 Gaps Críticos (Alta Prioridad)

| Gap | Impacto | Referencia mercado | Complejidad implementación |
|-----|---------|-------------------|--------------------------|
| **No-code Studio / Field Builder** | Alto — PYMES quieren customizar sin programador | Odoo Studio, Power Apps, SuiteBuilder | Media-Alta |
| **BI integrado** | Alto — decisiones requieren dashboards en tiempo real | Power BI en Dynamics, SuiteAnalytics | Alta (integrar Metabase/Apache Superset via iFrame o API) |
| **Marketplace de extensiones** | Medio-Alto — escalabilidad del ecosistema | apps.odoo.com (17K+), AppSource | Alta (requiere portal web, revisión de código, billing) |
| **Herramientas de migración de datos** | Alto — capturar clientes de Monica/Siigo/Alegra | Todos los ERPs tienen importadores Excel/CSV | Media |

### 6.2 Gaps Importantes (Media Prioridad)

| Gap | Impacto | Notas |
|-----|---------|-------|
| **Audit trail inmutable (write-once)** | Compliance enterprise — auditorías legales | `registro_actividad` existe pero no es write-once: service_role puede borrar registros. SAP/Oracle/Dynamics usan tablas append-only con permisos DELETE revocados incluso para service accounts. Solución: RLS con `DELETE` siempre `false` en `registro_actividad`. |
| **Consolidación financiera multi-empresa** | Enterprise y grupos empresariales | PILAR tiene multi-empresa (`usuarios_empresa` N:M) pero sin consolidación de P&L, eliminación de intercompany automática, ni balances consolidados. NetSuite One World es la referencia con 500+ subsidiarias. |
| **Cifrado columnar en reposo** | Seguridad enterprise — datos sensibles (cédulas, cuentas bancarias) | TLS en tránsito ✅. Cifrado en reposo: usar `pgcrypto` extension en Supabase |
| **GDPR/LOPDP automático** | Compliance Ecuador + exportación | Arquitectura permite, pero sin mecanismos automáticos de anonimización |
| **Segregación de funciones (SoD)** | Auditorías enterprise — evitar fraude interno | SAP GRC, Oracle Access Controls. Parcialmente cubierto por RBAC actual |
| **Aprobaciones configurables (Workflow)** | PYMES con flujos de aprobación | SuiteFlow, Odoo Aprobaciones, Power Automate — muy valorado comercialmente |
| **Notificaciones in-app (centro de notificaciones)** | UX — alertas dentro de la app | Módulo Comunicación cubre canales externos; falta centro in-app |
| **API developer portal** | Ecosistema — integraciones terceros | SAP API Hub, Oracle API Platform. PILAR tiene 85+ RPCs sin portal documentado público |

### 6.3 Gaps Menores (Baja Prioridad)

| Gap | Notas |
|-----|-------|
| **Multi-región** | Supabase lo está añadiendo; no bloqueante para Ecuador |
| **RPA/Automatización** | Power Automate, n8n (ya integrado vía `integraciones/n8n.md`) |
| **Chatbot corporativo con IA** | Módulo `ia/` cubre pgvector; Copilot Studio va más allá |
| **Firma digital de documentos** | DocuSign/HelloSign equivalente. Relacionado con SRI XAdES pero diferente |
| **Planificación de capacidad (MRP)** | Manufactura — fuera del scope actual |

---

## 7. Ventajas Competitivas de PILAR

### 7.1 Ventajas Arquitectónicas (vs todos los competidores)

**1. RLS nativo PostgreSQL** — la única garantía real de aislamiento de datos:
- Odoo, ERPNext, Alegra, Siigo: filtrado en capa de aplicación — acceso directo a BD bypasea todo
- SAP/Oracle/Dynamics: aislamiento a nivel de instancia (costoso) o application-level
- PILAR: RLS en PostgreSQL — imposible bypassear aunque accedan directamente a la BD

**2. Offline-first genuino** — diferenciador único en Latam:
- Ningún competidor en Ecuador/Latam ofrece offline-first real
- `brick_offline_first_with_supabase`: SQLite local con sync automático y resolución de conflictos
- Casos de uso: ventas en campo, bodegas sin wifi, farmacias en zonas rurales, POS en eventos

**3. SRI Ecuador nativo e integrado**:
- Datil hace SRI excelente pero solo facturación (no ERP)
- Odoo lo tiene vía `l10n_ec` community (menos mantenido)
- PILAR integra compliance SRI en el flujo nativo del ERP completo

**4. Flutter mono-codebase para 6 plataformas**:
- Competidores tienen app web + app móvil separadas (2x costo de desarrollo)
- PILAR: Web, iOS, Android, Windows, macOS, Linux con un solo codebase
- Ventaja operativa: un bug fix aplica en todas las plataformas simultáneamente

**5. Background jobs en la misma base de datos** (pg_cron + pgmq):
- Herramientas externas (Redis, RabbitMQ) requieren operación adicional
- PILAR: pg_cron + pgmq corren directamente en PostgreSQL/Supabase
- Sin infraestructura adicional, sin latencia de red entre la cola y la BD

### 7.2 Ventajas de Mercado (vs competidores Latam)

**1. ERP completo con SRI** — vacío claro en Ecuador:
- Solo software contable con SRI: Monica, Facturero, BIND
- ERP completo sin SRI: Holded, Defontana (ni siquiera intentan)
- ERP completo con SRI real: **solo PILAR** (en construcción)

**2. Stack tecnológico moderno** que permite precios competitivos:
- SAP: implementación $100K-1M+. PILAR: SaaS mensual
- Sin licencias de Oracle DB, SAP HANA, SQL Server
- PostgreSQL + Supabase: costo operativo 10-100x menor

**3. Modelo multi-plataforma = mayor retención**:
- Cliente usa PILAR en escritorio (Windows/Mac) + móvil (iOS/Android) + web
- Fricción de cambio mucho mayor que un competidor solo-web

---

## 8. Recomendaciones de Roadmap

### Prioridad 1 — Completar para MVP comercial

- [ ] **Importador de datos Excel/CSV** — para onboarding de clientes de Monica/Siigo
- [ ] **Centro de notificaciones in-app** — alertas dentro de PilarShell
- [ ] **API developer portal** — documentación pública de los 85+ RPCs para integraciones
- [ ] **Workflows de aprobación configurables** — mínimo para cotizaciones y órdenes de compra

### Prioridad 2 — Para competir con Odoo

- [ ] **Audit trail write-once** — agregar `CREATE POLICY "no_delete" ON registro_actividad FOR DELETE USING (false)` + revocar DELETE de service_role en esta tabla específica
- [ ] **Field Builder no-code** — añadir campos custom desde el admin sin SQL
- [ ] **Cifrado de campos sensibles** — `pgcrypto` para RUC, cuentas bancarias, cedulas
- [ ] **LOPDP compliance tools** — exportación de datos de usuario, anonimización

### Prioridad 3 — Para escalar el ecosistema

- [ ] **Marketplace básico** — registro de módulos de terceros con billing básico
- [ ] **BI dashboard** — integración Metabase o Apache Superset embedded
- [ ] **Herramienta de migración Monica → PILAR** — capturar el mercado ecuatoriano existente

### Lo que NO necesita hacer para ser competitivo

- ❌ No necesita On-premise (SAP target). SaaS es suficiente para Ecuador.
- ❌ No necesita implementar ABAP/SuiteScript. PostgreSQL + Edge Functions es superior.
- ❌ No necesita 2,500 APIs como SAP. 85+ RPCs bien documentadas son suficientes para V1.
- ❌ No necesita competir con SAP/Oracle en enterprise. El mercado objetivo es PYME ecuatoriana.

---

## Apéndice — Documentos relacionados

| Documento | Ruta |
|-----------|------|
| Sistema Base (START HERE) | `foundation/sistema-base.md` |
| Arquitectura Modular (MSB, ModuleSlot) | `foundation/arquitectura-modular.md` |
| Seguridad y RLS | `foundation/seguridad.md` |
| Background Jobs (pg_cron + pgmq) | `foundation/background-jobs.md` |
| Precisión y Redondeo | `foundation/precision-rounding-rules.md` |
| Módulo SRI Ecuador | `modules/extensiones/facturacion_ec/arquitectura-sri.md` |
| Guía de implementación de módulos | `foundation/module-implementation-guide.md` |
| ADR-009 Sistema Modular | `foundation/adrs/ADR-009_sistema-modular.md` |
| Roadmap Foundation | `foundation/roadmap.md` |
| Pasarelas de pago Ecuador | `modules/extensiones/pagos-online/integraciones/pasarelas-ecuador.md` |
