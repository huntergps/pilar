# Roadmap de Implementación — Foundation

> Este roadmap cubre exclusivamente la **capa Foundation**: infraestructura de plataforma, widgets core, sistema modular y arquitectura base. Las fases de implementación de cada módulo viven en `modules/<tipo>/<modulo>/roadmap.md`.

---

### Fase 1 — Foundation, Core Widgets y Arquitectura Modular (Semanas 1-6)

**CAPA 1: Infraestructura (Semana 1-2)**
- [ ] Setup proyecto Flutter + Supabase (supabase_flutter)
- [ ] Configurar Riverpod, go_router, fluent_ui (FluentApp.router + FluentThemeData)
- [ ] Configurar brick_offline_first_with_supabase (Repository, code gen, offline queue)
- [ ] **Core Foundation**: migracion 001_core_foundation.sql con todas las tablas base:
  - Infraestructura: adjuntos, notificaciones, plantillas_notificacion, registro_actividad, secuencias, configuracion_empresa, parametros_sistema, tareas_programadas
  - Catalogos geopoliticos: paises (249 ISO 3166-1); divisiones administrativas por pais van en modulos de extension de localizacion
  - Catalogos financieros: monedas (228 ISO 4217)
  - Seed data completo para arranque inmediato (catalogos pais-especificos van en modulos de extension)
- [x] **Sistema de alertas de empresa** (`023_alertas_empresa.sql`): alertas persistentes por empresa generadas por módulos o jobs. A diferencia de `notificaciones_usuario` (efímeras, por usuario), las alertas permanecen activas hasta resolverse o ignorarse. Incluye: tabla `alertas_empresa` con deduplicación via `codigo_alerta`, Realtime habilitado, RLS por `roles_destino`, 5 RPCs (`crear_alerta` solo-backend, `resolver_alerta`, `ignorar_alerta`, `get_alertas_activas`, `get_count_alertas_activas`), 2 jobs pg_cron (expire horario + cleanup 90 días), badge en PilarHeader con color por severidad, `AlertasPanel` con acciones resolver/ignorar.
- [ ] **Module Service Bus**: schema module_bus con funciones gateway (create_journal_entry, request_inventory_transfer, request_inventory_movement, check_stock_availability, request_invoice, request_quotation, send_notification, log_activity)
- [ ] Modelo de datos PostgreSQL (migraciones modulares Supabase) + RLS policies
- [ ] Supabase Storage (buckets con RLS por empresa_id)
- [ ] **supabase_auth_ui**: login (SupaEmailAuth + SupaSocialsAuth), signup, forgot/reset password
- [ ] **Deep links**: io.pilar.erp://auth-callback (iOS Universal Links, Android App Links)
- [ ] **go_router + ShellRoute**: rutas auth (sin PilarShell) + rutas autenticadas (dentro de PilarShell)
- [ ] **Auth state listener**: onAuthStateChange (signedIn, signedOut, passwordRecovery, tokenRefreshed)
- [ ] **Sistema de roles multi-empresa**: tablas roles, permisos, usuarios_empresa
- [ ] **Select empresa post-login**: pantalla selector empresa, skip si solo 1, actualizar JWT claims

**CAPA 2: Capa Reactiva de Datos (Semana 2-3)**
- [ ] **BrickDataProvider<T>**: provider Riverpod generico con subscribe()/subscribeToRealtime()
- [ ] **brickItemProvider<T>**: provider para item individual (formularios)
- [ ] **Politicas de conflicto**: bloqueo optimista (version field) para documentos criticos, LWW+merge para maestros, append-only para transacciones, suma-delta para datos acumulativos
- [ ] **Trigger check_version_conflict()**: PostgreSQL trigger para bloqueo optimista
- [ ] **Cola offline con prioridades**: documentos criticos > pagos/cobros > asientos > maestros > config
- [ ] **Monitor de conectividad**: estados ONLINE/SIN_SYNC/OFFLINE/SINCRONIZANDO
- [ ] **Log de sincronizacion**: tabla local con filtros, reintentos, resolucion errores
- [ ] **Supabase Realtime**: suscripciones por tabla + empresa_id (RLS)
- [ ] Tests: verificar reactividad (cambio local → widget se actualiza), sync offline→online, conflictos
- [ ] **Catalogo unidades de medida**: categorias UoM, conversiones, seed de unidades comunes
- [ ] **Listas de precios**: Publico/Mayorista/Distribuidor, reglas por qty/fecha, formula costo+margen
- [ ] **Posiciones fiscales**: mapeo de impuestos por tipo de contribuyente (exento, exportador, sector publico, regimenes especiales)

**CAPA 3: Widgets Core (Semana 3-5)**
- [x] **PilarShell framework**: FluentApp.router + PilarShell (NavigationView) + PilarHeader
- [x] **Navegación adaptativa**: NavigationPane con PaneDisplayMode.auto (expanded/compact/minimal nativos de fluent_ui, sin widget custom)
- [ ] **Auto-escalado responsive**: PilarSizes por breakpoint (fuentes, botones, inputs, cards, grid rows)
- [ ] **WorkspaceTabs**: sistema de tabs dinamico (abrir/cerrar/persistir), keyboard shortcuts
- [ ] **CrudScaffold<T>**: usa BrickDataProvider, search, filtros custom, grid/list, paginacion, export, permisos
- [ ] **FormScaffold<T>**: usa brickItemProvider + Repository.upsert, secciones, validacion, deteccion cambios
- [ ] **DataGrid + FilterPanel + SearchBar + PaginationBar + ExportButton**: widgets auxiliares
- [ ] **Preferencias de usuario**: modo tema (claro/oscuro/auto), color de acento, tamaño de fuente, densidad de filas, persistencia (shared_preferences)
- [x] **Perfil de usuario**: datos personales ✅, zona horaria ✅ | pendiente: cambiar contraseña, 2FA
- [ ] **PilarFooter**: version, empresa, estado conexion/sync, fecha/hora
- [ ] Tests: CrudScaffold renderiza datos, FormScaffold guarda/valida, tabs abren/cierran, responsive

**CAPA 4: Sistema Modular y Validacion (Semana 5-6)**
- [ ] **Implementar sistema modular**: tabla modulos, modulos_empresa, App Launcher dinamico
- [ ] CRUD Empresa, Establecimientos (usando CrudScaffold + FormScaffold)
- [ ] CRUD Contactos base (usando CrudScaffold + FormScaffold + filtros custom)
- [ ] CRUD Productos base, Categorias
- [ ] **Validar que los widgets core funcionan** con datos reales de entidades base
- [ ] **Chat interno**: conversaciones, grupos, canales, adjuntos (Storage)
- [ ] Tests pgTAP para RLS y multi-tenancy
- [ ] **Panel admin SaaS**: gestion empresas, usuarios, suscripciones

---

### Fase 2 — Modulos del Producto (Semanas 7+)

A partir de esta fase, la implementacion se organiza modulo a modulo. Cada modulo tiene su propio roadmap detallado en `modules/<tipo>/<modulo>/roadmap.md`.

El orden de implementacion recomendado sigue el grafo de dependencias definido en `modules/README.md`.

---

### Fase Final — Lanzamiento y Operaciones

- [ ] **PILAR Admin** (app web separada): dashboard, CRUD empresas, usuarios, suscripciones
- [ ] PILAR Admin: gestion certificados, activacion modulos, soporte/diagnostico
- [ ] Deploy PILAR Admin en admin.pilar.ec (Cloudflare Pages)
- [ ] Compilar y publicar Android (Play Store)
- [ ] Compilar y publicar iOS (App Store)
- [ ] Compilar builds desktop (Windows/macOS/Linux)
- [ ] Deploy PILAR ERP Web en app.pilar.ec (Cloudflare Pages)
- [ ] Pruebas en ambientes de pruebas de integraciones externas
- [ ] Migracion a ambientes de produccion
- [ ] Onboarding primer cliente
- [ ] Monitoreo con Sentry

---

### Gaps Planeados para Iteraciones Posteriores (P2)

Funcionalidades planificadas para iteraciones posteriores al lanzamiento inicial.
Cada gap incluye tablas/RPCs en pseudocodigo y descripcion breve del flujo.
Los gaps especificos de cada modulo viven en la documentacion del modulo correspondiente.

#### G-PLAT-01: Alertas Configurables por Usuario (plataforma)

> **Nota**: El sistema base de alertas de empresa (`alertas_empresa`) ya está implementado en `023_alertas_empresa.sql` y es generado por módulos/jobs del backend. Este gap cubre una capa adicional distinta: alertas **definidas por el usuario** basadas en umbrales/condiciones sobre métricas de negocio (ej: "avísame cuando el stock de X baje de 10 unidades").

```sql
CREATE TABLE alertas_configuradas (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id UUID NOT NULL REFERENCES empresas(id),
  usuario_id UUID NOT NULL REFERENCES auth.users(id),
  nombre VARCHAR(100) NOT NULL,
  condicion JSONB NOT NULL,       -- {metrica, operador, valor}
  canal JSONB NOT NULL,           -- ["EMAIL","WHATSAPP","PUSH"]
  frecuencia VARCHAR(20) DEFAULT 'INMEDIATA', -- INMEDIATA, DIARIA, SEMANAL
  activa BOOLEAN DEFAULT true
);
```

**Edge Function `check-custom-alerts`:** Cron cada hora, evalúa condiciones activas, dispara notificación por los canales configurados usando el sistema de notificaciones multi-canal existente. Cuando se supera un umbral puede también llamar a `crear_alerta()` para que aparezca en el panel de alertas de la empresa.
