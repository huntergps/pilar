# Arquitectura del Sistema

> **Nota sobre country-agnostic (ADR-006):** Este documento describe la arquitectura genérica de PILAR ERP. Los elementos específicos de cada país o jurisdicción están implementados en módulos de extensión.

### Arquitectura General

```
┌──────────────────────────────────────────────────────────────┐
│              FLUTTER APP (un solo codebase Dart)              │
│    ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌──────────┐     │
│    │  Web    │  │  iOS    │  │ Android │  │ Desktop  │     │
│    │ (WASM) │  │ (nativo)│  │ (nativo)│  │ (nativo) │     │
│    └────┬────┘  └────┬────┘  └────┬────┘  └────┬─────┘     │
│         └────────────┴────────────┴─────────────┘            │
│    UI: Material 3 + Syncfusion DataGrid/Charts/PDF           │
│    Estado: Riverpod  |  Offline: brick_offline_first_supabase│
│    SDK: supabase_flutter  |  HTTP: dio                       │
│                          │ HTTPS                              │
└──────────────────────────┼───────────────────────────────────┘
                           │
┌──────────────────────────┼───────────────────────────────────┐
│                    SUPABASE (Backend)                         │
│              ┌───────────┴──────────┐                        │
│              │  PostgreSQL 15+      │  Auth (JWT + MFA)      │
│              │  + Row Level Security│  Storage (XMLs, PDFs)  │
│              │  + pgvector (IA)    │  Realtime (WebSocket)  │
│              │  + Triggers/RPC      │                        │
│              └──────────────────────┘                        │
│                                                               │
│              ┌──────────────────────┐                        │
│              │  Edge Functions      │                        │
│              │  (Deno/TypeScript)   │                        │
│              │  ┌────────────────┐  │                        │
│              │  │ Doc Electronicos│  │                        │
│              │  │ Envia Email   │  │                        │
│              │  │ Pagos         │  │                        │
│              │  │ AI Query/Chat │  │                        │
│              │  └────────────────┘  │                        │
│              └──────────────────────┘                        │
└──────────────────────────────────────────────────────────────┘
                           │
┌──────────────────────────┼───────────────────────────────────┐
│                 SERVICIOS EXTERNOS                            │
│   ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│   ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│   │ Doc Elec │  │  Email   │  │  Pagos   │  │ Monitor  │   │
│   │ (ext.)   │  │ (Resend) │  │          │  │ (Sentry) │   │
│   └──────────┘  └──────────┘  └──────────┘  └──────────┘   │
└──────────────────────────────────────────────────────────────┘
```

### Patron de Arquitectura

**Modelo:** Arquitectura por capas con multi-tenancy a nivel de base de datos (Row Level Security)

```
┌─────────────────────────────────────────────────┐
│              PRESENTACION (Flutter/Dart)          │
│  Screens / Widgets / Riverpod Providers          │
├─────────────────────────────────────────────────┤
│              LOGICA DE NEGOCIO                   │
│  Repositories / Services / Edge Functions (Deno) │
│  Validaciones / Calculos Tributarios / Flujos    │
├─────────────────────────────────────────────────┤
│              ACCESO A DATOS                      │
│  brick_offline_first_with_supabase / RPC         │
│  Row Level Security / Policies                   │
├─────────────────────────────────────────────────┤
│              BASE DE DATOS                       │
│  PostgreSQL (Supabase Managed)                   │
│  Schemas: public, auth, storage                  │
└─────────────────────────────────────────────────┘
```

### Multi-Tenancy

```
Cada empresa (tenant) se aisla mediante:

1. Campo empresa_id en todas las tablas
2. Row Level Security (RLS) en PostgreSQL
3. Politicas que filtran por empresa del usuario autenticado

Ejemplo politica RLS (Supabase Best Practices):
  -- NOTA DE ESTANDARIZACION: Todas las policies RLS deben usar el patron optimizado:
  --   USING (empresa_id = (SELECT private.get_empresa_id()))
  -- La funcion private.get_empresa_id() cachea el resultado del JWT y ofrece
  -- 99.993% mejor rendimiento que inline JWT parsing. Ver seccion 17.
  -- Los ejemplos en este documento usan el patron inline por simplicidad,
  -- pero la implementacion final DEBE usar private.get_empresa_id().
  CREATE POLICY "tenant_isolation" ON <tabla>
    FOR ALL TO authenticated
    USING (empresa_id = (SELECT (auth.jwt() -> 'app_metadata' ->> 'empresa_id')::uuid));
  -- TO authenticated: solo evalua para usuarios autenticados (99.78% mejora)
  -- (SELECT ...): evalua auth.jwt() UNA vez, no por cada fila (94.97% mejora)
```

### Arquitectura Modular y Extensible

PILAR usa una arquitectura **modular por features** que permite agregar nuevos modulos sin modificar los existentes.

#### Principios de Extensibilidad

```
1. MODULOS INDEPENDIENTES
   - Cada modulo vive en su propio directorio (features/<modulo>/)
   - Estructura consistente: screens/, providers/, widgets/, models/
   - Sin dependencias circulares entre modulos

2. CONTRATO COMUN
   - Cada modulo expone un ServiceProvider (Riverpod) como punto de entrada
   - Navegacion via go_router: cada modulo registra sus rutas
   - App Launcher/menu se genera dinamicamente segun modulos habilitados

3. BASE DE DATOS EXTENSIBLE
   - Nuevas tablas siguen el patron: empresa_id + RLS + created_at/updated_at
   - Migraciones numeradas e incrementales (Supabase CLI)
   - RPCs para operaciones transaccionales complejas

4. EDGE FUNCTIONS DESACOPLADAS
   - Cada Edge Function es independiente (una responsabilidad)
   - Comparten utilidades via imports relativos
   - Deploy individual sin afectar otras funciones

5. HABILITACION POR EMPRESA
   - Tabla modulos_empresa controla que modulos tiene activos cada empresa
   - El App Launcher solo muestra modulos habilitados
   - Permite planes SaaS con distintos conjuntos de módulos activos (FREE, STARTER, PRO, ENTERPRISE)
```

#### Patron para Agregar un Nuevo Modulo

```
Para agregar un modulo nuevo (ej: "nomina"):

1. FLUTTER (features/)
   features/nomina/
     ├── screens/          # Pantallas del modulo
     ├── providers/        # Riverpod providers (estado + logica)
     ├── widgets/          # Widgets especificos del modulo
     └── models/           # Modelos Brick (offline-first)

2. BASE DE DATOS (supabase/migrations/)
   0XX_create_nomina.sql   # Tablas + RLS + indices

3. EDGE FUNCTIONS (supabase/functions/)
   nomina-process/index.ts # Logica server-side si necesaria

4. REGISTRO
   - Agregar rutas en router_config.dart
   - Agregar PilarModule en module_registry.dart
   - Agregar en tabla modulos_empresa
   - Agregar en plans_config (que plan incluye este modulo)
```

#### Modelo de Datos - Habilitacion de Modulos

```sql
-- Modulos disponibles en el sistema
CREATE TABLE modulos (
  id VARCHAR(30) PRIMARY KEY,   -- ID del modulo (ej: 'administracion', 'mi_modulo')
  nombre VARCHAR(100) NOT NULL,
  descripcion TEXT,
  icono VARCHAR(50),            -- Material Icon name
  orden INTEGER DEFAULT 0,
  tipo VARCHAR(20) NOT NULL DEFAULT 'auxiliar',
    -- 'infraestructura': siempre activos, no desactivables
    -- 'core':            proveen servicios via Module Service Bus
    -- 'auxiliar':        consumen servicios, activables por empresa/plan
  activo BOOLEAN DEFAULT true
);

-- Modulos habilitados por empresa (segun plan)
CREATE TABLE modulos_empresa (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id UUID REFERENCES empresas(id) NOT NULL,
  modulo_id VARCHAR(30) REFERENCES modulos(id) NOT NULL,
  habilitado BOOLEAN DEFAULT true,
  fecha_activacion DATE DEFAULT CURRENT_DATE,
  UNIQUE(empresa_id, modulo_id)
);

ALTER TABLE modulos_empresa ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON modulos_empresa
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- Seed de modulos de infraestructura (siempre activos, no desactivables)
-- Core y Auxiliares: cada modulo registra su propio INSERT al instalarse
INSERT INTO modulos (id, nombre, orden, tipo) VALUES
  ('dashboard',        'Dashboard',              1,  'infraestructura'),
  ('administracion',   'Administración',         2,  'infraestructura'),
  ('comunicacion',     'Comunicación',           3,  'infraestructura');

-- Planes de suscripcion SaaS
CREATE TABLE planes_suscripcion (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo          VARCHAR(20) UNIQUE NOT NULL,    -- 'FREE', 'STARTER', 'PRO', 'ENTERPRISE'
  nombre          VARCHAR(100) NOT NULL,
  descripcion     TEXT,
  precio_mensual  DECIMAL(14,2) NOT NULL DEFAULT 0,
  precio_anual    DECIMAL(14,2) NOT NULL DEFAULT 0,
  max_usuarios    INTEGER DEFAULT 1,
  max_empresas    INTEGER DEFAULT 1,
  max_documentos_mes INTEGER,                     -- NULL = ilimitado
  max_storage_mb  INTEGER DEFAULT 500,
  modulos_incluidos TEXT[],                       -- IDs de modulos del plan (NULL = todos)
  activo          BOOLEAN DEFAULT true,
  orden           INTEGER DEFAULT 0,              -- Para mostrar en UI
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Los IDs de modulos_incluidos se definen al configurar los planes SaaS
-- NULL en modulos_incluidos = acceso a todos los modulos activos
INSERT INTO planes_suscripcion (codigo, nombre, precio_mensual, precio_anual, max_usuarios, max_empresas, modulos_incluidos) VALUES
('FREE',       'Gratuito',    0,      0,      1,    1,    '{...}'),
('STARTER',    'Starter',     29.99,  299.90, 3,    1,    '{...}'),
('PRO',        'Profesional', 59.99,  599.90, 10,   3,    '{...}'),
('ENTERPRISE', 'Empresarial', 99.99,  999.90, NULL, NULL, NULL); -- NULL = todos los modulos
```

### Capa Base (Core Foundation)

Inspirado en el modulo `base` de Odoo (~90 modelos que existen ANTES de cualquier modulo de negocio), PILAR define una **Capa Base** que provee la infraestructura comun sobre la cual todos los modulos se construyen.

```
┌────────────────────────────────────────────────────────────────────────┐
│                        PILAR CORE FOUNDATION                           │
│                                                                        │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │  INFRAESTRUCTURA (siempre presente, no desactivable)            │  │
│  │                                                                  │  │
│  │  ● Multi-tenancy: empresas, usuarios_empresa                    │  │
│  │  ● Auth & Permisos: roles, permisos, roles_permisos             │  │
│  │  ● Modulos: modulos, modulos_empresa, planes_suscripcion        │  │
│  │  ● Secuencias: secuencias (genéricas)                           │  │
│  │  ● Adjuntos: adjuntos (attachments polimorfico)                 │  │
│  │  ● Notificaciones: notificaciones, plantillas_notificacion      │  │
│  │  ● Actividad: registro_actividad (audit trail)                  │  │
│  │  ● Configuracion: configuracion_empresa, parametros_sistema     │  │
│  │  ● Tareas programadas: tareas_programadas (cron config)         │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                                                                        │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │  CATALOGOS MAESTROS (seed data, globales, read-mostly)          │  │
│  │                                                                  │  │
│  │  ● Geopoliticos: paises, provincias, ciudades                   │  │
│  │  ● Financieros: monedas, tasas_cambio, bancos                  │  │
│  │  ● Fiscales: catalogos tributarios (gestionados por extensiones)│  │
│  │  ● Parametros: parametros_sistema (limites UI, sesiones, trial)  │  │
│  │  ● Unidades: categorias_uom, unidades_medida                   │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                                                                        │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │  MODULOS CORE (activables, proveen servicios a auxiliares)      │  │
│  │  Cada modulo registra sus propias tablas y RPCs al instalarse   │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                                                                        │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │  MODULOS AUXILIARES (opcionales, se comunican via Service Bus)  │  │
│  │  Cada modulo registra sus propias tablas y RPCs al instalarse   │  │
│  └──────────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────┘
```

#### Comparativa con Odoo `base`

| Concepto Odoo `base` | Equivalente PILAR | Diferencia |
|----------------------|-------------------|------------|
| `res.partner` (contacto universal) | `contactos` + `contacto_direcciones` | PILAR separa direcciones como tabla hija |
| `res.company` (multi-company) | `empresas` + RLS | PILAR usa RLS en vez de company_id manual |
| `res.users` + `res.groups` | `auth.users` + `roles` + `permisos` | PILAR delega auth a Supabase Auth |
| `ir.sequence` (numeracion) | `secuencias` (genéricas en Foundation) | Secuenciales de documentos específicos en módulos de extensión |
| `ir.attachment` (adjuntos) | `adjuntos` (NUEVO) | Polimorfico con Supabase Storage |
| `ir.cron` (tareas programadas) | `tareas_programadas` (NUEVO) | Config visual + pg_cron real |
| `ir.config_parameter` | `parametros_sistema` + `configuracion_empresa` (NUEVO) | Nivel global y por empresa |
| `ir.rule` (record rules) | RLS policies (PostgreSQL) | PILAR usa RLS nativo, no software |
| `ir.model.access` (ACL) | `permisos` (modulo.recurso.accion) | Granular por accion |
| `res.country` + `res.country.state` | `paises` + `provincias` + `ciudades` (NUEVO) | PILAR agrega ciudades |
| `res.currency` + `res.currency.rate` | `monedas` + `tasas_cambio` | Ya definido |
| `res.bank` | `catalogo_bancos` (NUEVO) | Catálogo centralizado |
| `base_data.xml` (seed data) | Migracion 001_core_foundation.sql | SQL seed en vez de XML |
| `ir.module.module` | `modulos` + `modulos_empresa` | Activacion por empresa, no por instancia |
| `mail.message` (chatter/audit) | `registro_actividad` (NUEVO) | Log de cambios por entidad |
| `ir.mail_server` + `mail.template` | `plantillas_notificacion` (NUEVO) | Templates multi-canal |
| Modulo `_inherit` (extension Python) | **Module Service Bus** (RPC gateway) | Desacoplado via funciones |

#### Clasificacion de Modulos

```
CLASIFICACION DE MODULOS PILAR:

┌─────────────────────────────────────────────────────────────────────┐
│  TIPO 1: INFRAESTRUCTURA (siempre activo, no aparece en App Launcher)
│  ─────────────────────────────────────────────────────────────────  │
│  No se puede desactivar. Es la base sobre la que todo funciona.    │
│  Equivalente: Odoo "base" + "web" + "bus"                          │
│                                                                     │
│  Incluye: auth, roles, permisos, empresas (country-agnostic),      │
│  adjuntos, notificaciones, audit log, config, secuencias genéricas,│
│  catalogos (paises, monedas, bancos, UoM),                         │
│  Dashboard, Administracion, Comunicacion                            │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│  TIPO 2: MODULOS CORE (activables, proveen servicios)               │
│  ─────────────────────────────────────────────────────────────────  │
│  Son modulos de negocio pero otros modulos dependen de ellos.       │
│  Cuando activos, exponen funciones via Module Service Bus.          │
│  Cuando inactivos, las llamadas a sus servicios son NO-OP.         │
│                                                                     │
│  Cada modulo core define sus servicios al instalarse.               │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│  TIPO 3: MODULOS AUXILIARES (opcionales, independientes)            │
│  ─────────────────────────────────────────────────────────────────  │
│  Funcionan solos o en combinacion con modulos core.                 │
│  NUNCA llaman directamente a tablas de otros modulos.               │
│  Usan el Service Bus para interactuar con los core.                │
└─────────────────────────────────────────────────────────────────────┘
```

#### Regla de Oro

```
UN MODULO AUXILIAR NUNCA HACE INSERT/UPDATE/DELETE DIRECTO
EN TABLAS DE OTRO MODULO.

Siempre usa el Module Service Bus (funciones RPC gateway).
Esto permite que un modulo funcione con o sin los otros.
```

### Module Service Bus (Comunicacion Inter-Modulos Desacoplada)

El Module Service Bus es el mecanismo que permite a los modulos auxiliares solicitar operaciones en modulos core SIN depender de que esten activos. Es el equivalente PILAR al sistema `_inherit` de Odoo, pero completamente desacoplado.

#### Principio de Funcionamiento

```
┌─────────────────────────────────────────────────────────────────────┐
│  MODULO AUXILIAR (cualquiera)                                       │
│                                                                     │
│  Necesita datos o accion de un modulo core:                         │
│  → Llama: module_bus.<modulo_core>_<operacion>(...)                 │
│                                                                     │
│  Necesita operacion de otro modulo core:                            │
│  → Llama: module_bus.<otro_modulo>_<operacion>(...)                 │
└──────────┬──────────────────────────────────────────────────────────┘
           │
           ▼
┌─────────────────────────────────────────────────────────────────────┐
│  MODULE SERVICE BUS (RPC Gateway en PostgreSQL)                     │
│                                                                     │
│  CREATE FUNCTION module_bus.<modulo>_<operacion>(...)               │
│  BEGIN                                                              │
│    -- 1. Verificar si el modulo core esta activo                    │
│    IF NOT module_bus.is_module_active('<modulo>') THEN              │
│      -- Modulo NO activo: retorna sin hacer nada (NO-OP)           │
│      RETURN jsonb_build_object(                                     │
│        'executed', false,                                           │
│        'reason', 'module_inactive',                                │
│        'module', '<modulo>'                                         │
│      );                                                             │
│    END IF;                                                          │
│                                                                     │
│    -- 2. Modulo SI activo: ejecutar la operacion real               │
│    result := <modulo>.do_operation(...);                            │
│    RETURN jsonb_build_object('executed', true, 'data', result);    │
│  END;                                                               │
└─────────────────────────────────────────────────────────────────────┘
```

#### Implementacion: Schema `module_bus`

```sql
-- ============================================
-- MODULE SERVICE BUS
-- Schema dedicado para funciones inter-modulo
-- ============================================

CREATE SCHEMA IF NOT EXISTS module_bus;

-- Funcion helper: verificar si un modulo esta activo para la empresa
CREATE OR REPLACE FUNCTION module_bus.is_module_active(
  p_empresa_id UUID,
  p_modulo_id VARCHAR(30)
) RETURNS BOOLEAN
LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT EXISTS (
    SELECT 1 FROM modulos_empresa
    WHERE empresa_id = p_empresa_id
      AND modulo_id = p_modulo_id
      AND habilitado = true
  );
$$;

-- Tipo de respuesta estandar del bus
-- Todos los servicios retornan este formato
CREATE TYPE module_bus.bus_response AS (
  executed    BOOLEAN,     -- true si se ejecuto, false si modulo inactivo
  reason      TEXT,        -- null si ok, 'module_inactive' si no activo
  module      VARCHAR(30), -- modulo que se intento llamar
  data        JSONB        -- datos de retorno (id creado, etc.)
);
```

#### Patron de Implementacion de Servicios del Bus

Cada módulo core que provee servicios via el bus implementa sus propias funciones gateway en el schema `module_bus`. Foundation NO define estas funciones — las define cada módulo al instalarse.

**Estructura de una función gateway (patron):**

```sql
-- Cada modulo core implementa sus servicios en su propia migración
-- Ejemplo generico — la implementación concreta va en el módulo correspondiente:

CREATE OR REPLACE FUNCTION module_bus.<modulo>_<operacion>(
  p_empresa_id    UUID,
  -- ... parametros especificos de la operacion
) RETURNS module_bus.bus_response
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_result module_bus.bus_response;
BEGIN
  -- 1. Verificar si el modulo esta activo
  IF NOT module_bus.is_module_active(p_empresa_id, '<modulo>') THEN
    v_result.executed := false;
    v_result.reason   := 'module_inactive';
    v_result.module   := '<modulo>';
    v_result.data     := null;
    RETURN v_result;
  END IF;

  -- 2. Ejecutar la operacion real del modulo
  -- ... llamar al RPC interno del modulo ...

  v_result.executed := true;
  v_result.reason   := null;
  v_result.module   := '<modulo>';
  v_result.data     := jsonb_build_object(/* resultado */);
  RETURN v_result;
END;
$$;
```

#### Flutter: Patron en Providers (Dart)

```dart
// lib/core/services/module_bus_service.dart
// NOTA: Las llamadas a module_bus.* son RPCs de PostgreSQL (schema.function),
// NO Edge Functions. Para Edge Functions se usa supabase.functions.invoke('nombre-kebab-case').
// Los RPCs del module_bus se invocan via wrappers en schema public:
//   supabase.rpc('module_bus_create_journal_entry', params: {...})
// Esto requiere crear funciones wrapper en public que deleguen al schema module_bus.
class ModuleBusService {
  final SupabaseClient _supabase;

  ModuleBusService(this._supabase);

  /// Llama a cualquier funcion del Module Service Bus
  /// Retorna BusResponse con executed, reason, data
  ///
  /// Las funciones del schema module_bus requieren wrappers en schema public.
  /// En PostgreSQL se crean funciones proxy:
  ///   CREATE FUNCTION public.module_bus_create_journal_entry(...)
  ///   RETURNS ... AS $$ SELECT module_bus.create_journal_entry(...) $$ LANGUAGE sql;
  ///
  /// Alternativa: configurar search_path en Supabase para incluir module_bus
  Future<BusResponse> call(String function, Map<String, dynamic> params) async {
    final response = await _supabase.rpc('module_bus_$function', params: params);
    return BusResponse.fromJson(response);
  }
}

class BusResponse {
  final bool executed;
  final String? reason;
  final String? module;
  final Map<String, dynamic>? data;

  bool get wasSkipped => !executed && reason == 'module_inactive';

  // Si el modulo estaba inactivo, no es error → flujo continua
}

// Uso en el provider de cualquier modulo auxiliar:
class MiModuloProvider extends StateNotifier<MiModuloState> {
  final ModuleBusService _bus;

  Future<void> completarOperacion(String operacionId) async {
    // 1. Ejecutar operacion local del modulo
    await _updateStatus(operacionId, 'COMPLETADO');

    // 2. Intentar llamar servicio de modulo core A
    final resultA = await _bus.call('<modulo_core_a>_<operacion>', {
      'p_empresa_id': empresaId,
      'p_fecha': DateTime.now().toIso8601String(),
      'p_descripcion': 'Descripcion de la operacion',
      'p_origen': 'MI_MODULO',
      'p_referencia_id': operacionId,
    });
    // Si modulo_core_a inactivo → resultA.wasSkipped = true → OK, continua

    // 3. Intentar llamar servicio de modulo core B
    final resultB = await _bus.call('<modulo_core_b>_<operacion>', {
      'p_empresa_id': empresaId,
      'p_tipo': 'EGRESO',
      'p_items': itemsUsados,
      'p_origen': 'MI_MODULO',
      'p_referencia_id': operacionId,
    });
    // Si modulo_core_b inactivo → resultB.wasSkipped = true → OK, continua

    // 4. Actualizar UI
    state = state.copyWith(completado: true);
  }
}
```

#### Convenciones del Module Bus

Reglas que todos los servicios del bus deben cumplir:

| Regla | Descripcion |
|-------|-------------|
| Patron NO-OP | Si el modulo esta inactivo, retorna `{executed: false, reason: 'module_inactive'}` — nunca lanza error |
| SECURITY DEFINER | Todas las funciones del bus se ejecutan con privilegios del owner (no del caller) |
| Schema dedicado | Todas las funciones viven en el schema `module_bus`, nunca en `public` |
| Respuesta estandar | Siempre retorna `module_bus.bus_response` (executed, reason, module, data) |
| Cada modulo registra los suyos | Foundation NO define funciones de negocio — cada modulo core las implementa al instalarse |
| Servicios de infraestructura | `send_notification` y `log_activity` SIEMPRE se ejecutan (son infraestructura, no modulos) |

### Tablas Base Nuevas (Core Foundation)

Tablas que forman parte de la infraestructura base y no existian previamente:

```sql
-- ============================================
-- CATALOGOS GEOPOLITICOS (seed data global)
-- ============================================

-- Provincias/Estados (1547+ registros pre-cargados)
CREATE TABLE provincias (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pais_codigo     VARCHAR(2) REFERENCES paises(id) NOT NULL,
  codigo          VARCHAR(10) NOT NULL,     -- Codigo ISO 3166-2 (EC-P, EC-G, etc.)
  nombre          VARCHAR(100) NOT NULL,
  UNIQUE(pais_codigo, codigo)
);

-- Ciudades/Cantones (para Ecuador: 221 cantones)
CREATE TABLE ciudades (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  provincia_id    UUID REFERENCES provincias(id) NOT NULL,
  codigo          VARCHAR(10),
  nombre          VARCHAR(100) NOT NULL,
  zona_horaria    VARCHAR(50) DEFAULT 'America/Guayaquil',
  UNIQUE(provincia_id, nombre)
);

-- ============================================
-- CATALOGO DE BANCOS (centralizado)
-- ============================================

CREATE TABLE catalogo_bancos (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pais_codigo     VARCHAR(2) REFERENCES paises(id) DEFAULT 'EC',
  codigo_banco    VARCHAR(20),              -- Codigo SBS o SWIFT
  nombre          VARCHAR(200) NOT NULL,
  tipo            VARCHAR(30),              -- BANCO, COOPERATIVA, MUTUALISTA, FINANCIERA
  swift_bic       VARCHAR(11),
  activo          BOOLEAN DEFAULT true,
  UNIQUE(pais_codigo, codigo_banco)
);

-- Seed: ~459 bancos de Ecuador (Pichincha, Guayaquil, Cooperativas, etc.)

-- ============================================
-- ADJUNTOS (sistema polimorfico de archivos)
-- ============================================

CREATE TABLE adjuntos (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID REFERENCES empresas(id) NOT NULL,
  entidad_tipo    VARCHAR(50) NOT NULL,     -- Tipo de entidad a la que pertenece el adjunto
  entidad_id      UUID NOT NULL,            -- ID del registro al que se adjunta
  nombre_archivo  VARCHAR(255) NOT NULL,
  mime_type       VARCHAR(100),
  tamano_bytes    BIGINT,
  storage_path    TEXT NOT NULL,            -- Path en Supabase Storage
  bucket          VARCHAR(50) DEFAULT 'attachments',
  subido_por      UUID REFERENCES auth.users(id),
  created_at      TIMESTAMPTZ DEFAULT now(),
  metadata        JSONB DEFAULT '{}'        -- Datos extra (ej: {tipo: 'evidencia_ingreso'})
);

CREATE INDEX idx_adjuntos_entidad ON adjuntos(entidad_tipo, entidad_id);

ALTER TABLE adjuntos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON adjuntos
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT (auth.jwt() -> 'app_metadata' ->> 'empresa_id')::uuid));

-- ============================================
-- NOTIFICACIONES (sistema in-app + multi-canal)
-- ============================================

CREATE TABLE notificaciones (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID REFERENCES empresas(id) NOT NULL,
  usuario_id      UUID REFERENCES auth.users(id) NOT NULL,
  tipo            VARCHAR(50) NOT NULL,     -- Tipo de notificacion (definido por cada modulo)
  titulo          VARCHAR(200) NOT NULL,
  mensaje         TEXT,
  entidad_tipo    VARCHAR(50),              -- Navegacion: click → ir a esta entidad
  entidad_id      UUID,
  leida           BOOLEAN DEFAULT false,
  fecha_leida     TIMESTAMPTZ,
  canal           VARCHAR(20) DEFAULT 'APP', -- APP, EMAIL, PUSH
  created_at      TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_notificaciones_usuario ON notificaciones(usuario_id, leida, created_at DESC);

ALTER TABLE notificaciones ENABLE ROW LEVEL SECURITY;
CREATE POLICY "own_notifications" ON notificaciones
  FOR ALL TO authenticated
  USING (usuario_id = (SELECT auth.uid()));

-- Policy adicional para que administradores vean notificaciones de su empresa
CREATE POLICY "admin_read" ON notificaciones
  FOR SELECT TO authenticated
  USING (
    empresa_id = (SELECT private.get_empresa_id())
    AND private.has_permission('administracion.notificaciones.leer')
  );

CREATE TABLE plantillas_notificacion (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID REFERENCES empresas(id),  -- NULL = global/default
  tipo            VARCHAR(50) NOT NULL UNIQUE,
  titulo_template TEXT NOT NULL,             -- 'Factura {{numero}} emitida'
  mensaje_template TEXT NOT NULL,
  canales         VARCHAR(20)[] DEFAULT '{APP}', -- {APP, EMAIL, PUSH}
  activo          BOOLEAN DEFAULT true
);

-- ============================================
-- REGISTRO DE ACTIVIDAD (audit trail por entidad)
-- ============================================

CREATE TABLE registro_actividad (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID REFERENCES empresas(id) NOT NULL,
  entidad_tipo    VARCHAR(50) NOT NULL,     -- Tipo de entidad (definido por cada modulo)
  entidad_id      UUID NOT NULL,
  accion          VARCHAR(30) NOT NULL,     -- 'CREADO', 'MODIFICADO', 'ESTADO_CAMBIO', 'ELIMINADO'
  descripcion     TEXT,                     -- 'Estado cambio de BORRADOR a EMITIDA'
  datos_antes     JSONB,                    -- Snapshot del campo antes del cambio
  datos_despues   JSONB,                    -- Snapshot del campo despues del cambio
  usuario_id      UUID REFERENCES auth.users(id),
  usuario_nombre  VARCHAR(200),             -- Desnormalizado para consultas rapidas
  created_at      TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_actividad_entidad ON registro_actividad(entidad_tipo, entidad_id, created_at DESC);

ALTER TABLE registro_actividad ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON registro_actividad
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT (auth.jwt() -> 'app_metadata' ->> 'empresa_id')::uuid));

-- ============================================
-- AUDIT TRAIL COMPLETO
-- ============================================
-- Registro detallado de TODOS los cambios en tablas sensibles.
-- Incluye: valores antes/despues, usuario, IP, dispositivo.

CREATE TABLE audit_log (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tabla           TEXT NOT NULL,                    -- Tabla donde ocurrio el cambio
  registro_id     UUID NOT NULL,                   -- ID del registro modificado
  accion          VARCHAR(10) NOT NULL,            -- INSERT, UPDATE, DELETE
  usuario_id      UUID REFERENCES auth.users(id),
  empresa_id      UUID,
  ip_address      INET,                            -- IP de origen
  user_agent      TEXT,                            -- Navegador/app
  dispositivo     VARCHAR(20),                     -- WEB, ANDROID, IOS, WINDOWS, MACOS, LINUX
  session_id      TEXT,                            -- ID de sesion Supabase
  valores_anteriores JSONB,                        -- Valores ANTES del cambio (UPDATE/DELETE)
  valores_nuevos  JSONB,                           -- Valores DESPUES del cambio (INSERT/UPDATE)
  campos_modificados TEXT[],                       -- Lista de campos que cambiaron
  motivo          TEXT,                            -- Obligatorio para anulaciones y ajustes
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Indices para consulta eficiente
CREATE INDEX idx_audit_tabla_registro ON audit_log(tabla, registro_id);
CREATE INDEX idx_audit_usuario ON audit_log(usuario_id, created_at);
CREATE INDEX idx_audit_empresa_fecha ON audit_log(empresa_id, created_at);

-- Funcion trigger generica para audit trail
CREATE OR REPLACE FUNCTION audit_trigger() RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO audit_log (tabla, registro_id, accion, usuario_id, empresa_id,
      valores_nuevos, created_at)
    VALUES (TG_TABLE_NAME, NEW.id, 'INSERT', auth.uid(),
      COALESCE(NEW.empresa_id, NULL), to_jsonb(NEW), NOW());
    RETURN NEW;
  ELSIF TG_OP = 'UPDATE' THEN
    INSERT INTO audit_log (tabla, registro_id, accion, usuario_id, empresa_id,
      valores_anteriores, valores_nuevos,
      campos_modificados, created_at)
    VALUES (TG_TABLE_NAME, NEW.id, 'UPDATE', auth.uid(),
      COALESCE(NEW.empresa_id, NULL), to_jsonb(OLD), to_jsonb(NEW),
      ARRAY(SELECT key FROM jsonb_each(to_jsonb(NEW))
            WHERE to_jsonb(NEW) -> key IS DISTINCT FROM to_jsonb(OLD) -> key),
      NOW());
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    INSERT INTO audit_log (tabla, registro_id, accion, usuario_id, empresa_id,
      valores_anteriores, created_at)
    VALUES (TG_TABLE_NAME, OLD.id, 'DELETE', auth.uid(),
      COALESCE(OLD.empresa_id, NULL), to_jsonb(OLD), NOW());
    RETURN OLD;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Aplicar trigger a tablas sensibles (cada modulo aplica este trigger a sus propias tablas)
-- Ejemplo:
-- CREATE TRIGGER audit_<tabla> AFTER INSERT OR UPDATE OR DELETE ON <tabla>
--   FOR EACH ROW EXECUTE FUNCTION audit_trigger();

-- RLS: Solo lectura para auditores, no modificable
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY "read_own_company" ON audit_log
  FOR SELECT TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));
-- NOTA: No hay policy INSERT/UPDATE/DELETE para usuarios normales.
-- Solo el trigger (SECURITY DEFINER) puede escribir en audit_log.

-- ============================================
-- SECUENCIAS GENERICAS (para documentos internos y operativos)
-- ============================================

CREATE TABLE secuencias (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID REFERENCES empresas(id) NOT NULL,
  codigo          VARCHAR(30) NOT NULL,     -- Codigo corto de la secuencia (ej: 'DOC', 'ORD')
  nombre          VARCHAR(100) NOT NULL,    -- Nombre descriptivo de la secuencia
  prefijo         VARCHAR(20),              -- 'COT-', 'OV-', 'PAG-'
  sufijo          VARCHAR(20),
  siguiente_numero BIGINT DEFAULT 1,
  padding         INTEGER DEFAULT 6,       -- COT-000001
  reinicio_anual  BOOLEAN DEFAULT false,   -- Reiniciar al cambiar de año
  anio_actual     INTEGER,
  UNIQUE(empresa_id, codigo)
);

ALTER TABLE secuencias ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON secuencias
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT (auth.jwt() -> 'app_metadata' ->> 'empresa_id')::uuid));

-- Funcion para obtener siguiente numero de secuencia
CREATE OR REPLACE FUNCTION next_sequence(
  p_empresa_id UUID,
  p_codigo     VARCHAR(30)
) RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_seq secuencias%ROWTYPE;
  v_numero TEXT;
  v_anio INTEGER := EXTRACT(YEAR FROM CURRENT_DATE);
BEGIN
  SELECT * INTO v_seq FROM secuencias
  WHERE empresa_id = p_empresa_id AND codigo = p_codigo
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Secuencia % no encontrada', p_codigo;
  END IF;

  -- Reinicio anual si aplica
  IF v_seq.reinicio_anual AND (v_seq.anio_actual IS NULL OR v_seq.anio_actual < v_anio) THEN
    v_seq.siguiente_numero := 1;
    v_seq.anio_actual := v_anio;
  END IF;

  v_numero := COALESCE(v_seq.prefijo, '') ||
    LPAD(v_seq.siguiente_numero::TEXT, v_seq.padding, '0') ||
    COALESCE(v_seq.sufijo, '');

  UPDATE secuencias SET
    siguiente_numero = v_seq.siguiente_numero + 1,
    anio_actual = v_anio
  WHERE id = v_seq.id;

  RETURN v_numero;
END;
$$;

-- ============================================
-- CONFIGURACION POR EMPRESA (settings generales)
-- ============================================

CREATE TABLE configuracion_empresa (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID REFERENCES empresas(id) NOT NULL UNIQUE,
  moneda_principal UUID REFERENCES monedas(id),   -- Default: USD
  moneda_secundaria UUID REFERENCES monedas(id),  -- Para reportes en otra moneda
  formato_fecha   VARCHAR(20) DEFAULT 'dd/MM/yyyy',
  formato_numero  VARCHAR(20) DEFAULT '#,##0.00',
  separador_miles VARCHAR(1) DEFAULT ',',
  separador_decimal VARCHAR(1) DEFAULT '.',
  logo_url        TEXT,
  favicon_url     TEXT,
  color_primario  VARCHAR(7) DEFAULT '#1565C0',
  -- Cada modulo core puede añadir sus propios campos de configuracion via extend_configuracion_empresa.sql
  -- (soft references UUID nullable sin FK constraint hacia tablas de modulos externos)
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE configuracion_empresa ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON configuracion_empresa
  FOR ALL TO authenticated
  USING (empresa_id = (SELECT (auth.jwt() -> 'app_metadata' ->> 'empresa_id')::uuid));

-- ============================================
-- PARAMETROS DEL SISTEMA (key-value global)
-- ============================================

CREATE TABLE parametros_sistema (
  clave           VARCHAR(100) PRIMARY KEY,
  valor           TEXT NOT NULL,
  descripcion     TEXT,
  tipo            VARCHAR(20) DEFAULT 'TEXT', -- TEXT, INTEGER, DECIMAL, BOOLEAN, JSON
  editable        BOOLEAN DEFAULT false,      -- Si el admin puede editar desde UI
  updated_at      TIMESTAMPTZ DEFAULT now()
);

-- Seed de parametros globales
INSERT INTO parametros_sistema (clave, valor, tipo, descripcion) VALUES
  ('APP_VERSION', '1.0.0', 'TEXT', 'Version actual de la aplicacion'),
  ('MAINTENANCE_MODE', 'false', 'BOOLEAN', 'Modo mantenimiento activo'),
  ('MAX_UPLOAD_SIZE_MB', '10', 'INTEGER', 'Tamano maximo de archivo en MB'),
  ('SESSION_TIMEOUT_MINUTES', '480', 'INTEGER', 'Timeout de sesion inactiva'),
  ('ALLOWED_FILE_TYPES', 'pdf,png,jpg,jpeg,xml,xlsx,csv', 'TEXT', 'Extensiones permitidas');

-- ============================================
-- TAREAS PROGRAMADAS (cron configuration)
-- ============================================

CREATE TABLE tareas_programadas (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre          VARCHAR(100) NOT NULL,
  descripcion     TEXT,
  tipo            VARCHAR(20) NOT NULL,     -- 'RPC', 'EDGE_FUNCTION', 'SQL'
  funcion         VARCHAR(200) NOT NULL,    -- 'process_doc_queue', 'process_depreciation'
  parametros      JSONB DEFAULT '{}',
  cron_expression VARCHAR(50) NOT NULL,     -- '0 */5 * * *' (cada 5 min)
  activo          BOOLEAN DEFAULT true,
  ultima_ejecucion TIMESTAMPTZ,
  ultimo_resultado VARCHAR(20),             -- 'OK', 'ERROR', 'RUNNING'
  ultimo_error     TEXT,
  created_at      TIMESTAMPTZ DEFAULT now()
);

-- Seed de tareas programadas de infraestructura
INSERT INTO tareas_programadas (nombre, tipo, funcion, cron_expression) VALUES
  ('Limpiar notificaciones antiguas', 'SQL', 'DELETE FROM notificaciones WHERE created_at < now() - interval ''90 days'' AND leida = true', '0 2 * * 0');
-- Cada modulo registra sus propias tareas al instalarse
```

#### Seed Data - Migracion Base (001_core_foundation.sql)

```
La migracion base de PILAR carga los siguientes datos semilla:

CATALOGOS GEOPOLITICOS:
  ● 249 paises (ISO 3166-1) con codigo, nombre, codigo_telefono, moneda_id
  ● Provincias/estados de paises soportados
  ● Ciudades/cantones vinculadas a sus provincias
  ● Zonas horarias por pais/region

CATALOGOS FINANCIEROS:
  ● 228 monedas (ISO 4217)
  ● Bancos y entidades financieras (por pais — extensiones de localizacion)

CATALOGOS TRIBUTARIOS:
  ● Los catalogos fiscales (tarifas, retenciones, formas de pago, etc.)
    son gestionados por los modulos de localizacion correspondientes,
    no por foundation.

UNIDADES DE MEDIDA:
  ● Categorias y unidades base (longitud, peso, volumen, tiempo, etc.)

MODULOS DE INFRAESTRUCTURA:
  ● Dashboard, Administracion, Comunicacion (siempre activos)

PARAMETROS SISTEMA:
  ● Parametros globales iniciales (version, limites, timeouts)

TAREAS PROGRAMADAS DE INFRAESTRUCTURA:
  ● Limpieza de notificaciones antiguas

ROLES BASE:
  ● Roles predefinidos del sistema
  ● Permisos iniciales por rol
```

### Conectividad, Sincronizacion y UI Responsive

#### Monitor de Conectividad

```
PILAR monitorea constantemente el estado de conexion y lo muestra al usuario:

┌─────────────────────────────────────────────────────────────┐
│  ESTADOS DE CONEXION (indicador en la barra de estado)      │
├─────────────────────────────────────────────────────────────┤
│  🟢 ONLINE     - Conectado a internet y al servidor Supabase│
│  🟡 SIN_SYNC   - Hay internet pero falla la conexion a     │
│                   Supabase (servidor caido, mantenimiento)   │
│  🔴 OFFLINE    - Sin conexion a internet                     │
│  🔵 SINCRONIZANDO - Enviando cambios pendientes al servidor │
└─────────────────────────────────────────────────────────────┘

Implementacion Flutter:
  - connectivity_plus: detecta cambios de red (wifi, mobile, ethernet, none)
  - Timer periodico: ping a Supabase cada 30 seg para verificar alcance
  - Riverpod provider global: ConnectivityProvider
  - Widget: ConnectionStatusBar (banner o chip en AppBar)
  - Notificacion al cambiar estado (ej: "Conexion restaurada, sincronizando...")
```

#### Log de Sincronizacion

```
PILAR mantiene un log visible de operaciones de sincronizacion:

Pantalla: Configuracion → Sincronizacion → Log

┌──────────────────────────────────────────────────────────────────┐
│  FECHA/HORA          │ OPERACION       │ ESTADO   │ DETALLE     │
├──────────────────────────────────────────────────────────────────┤
│  14/02/2026 10:30:00 │ Sync tabla_a    │ ✅ OK    │ 3 enviados  │
│  14/02/2026 10:29:55 │ Sync tabla_b    │ ✅ OK    │ 1 recibido  │
│  14/02/2026 10:29:50 │ Envio Doc #001  │ ⏳ Cola  │ Reintento 2 │
│  14/02/2026 10:25:00 │ Sync tabla_c    │ ❌ Error │ Timeout     │
│  14/02/2026 10:20:00 │ Conexion        │ 🔴 OFF  │ Sin red     │
│  14/02/2026 10:15:00 │ Conexion        │ 🟢 ON   │ Restaurada  │
└──────────────────────────────────────────────────────────────────┘

Datos almacenados en SQLite local (no requiere conexion para consultar):

sync_log (SQLite local)
  id              INTEGER PK AUTOINCREMENT
  timestamp       TEXT NOT NULL          -- ISO 8601
  operacion       TEXT NOT NULL          -- 'sync_tabla', 'envio_documento', 'conexion'
  estado          TEXT NOT NULL          -- 'ok', 'error', 'pendiente', 'cola'
  tabla           TEXT                   -- Tabla sincronizada (ej: nombre de la entidad)
  registros       INTEGER DEFAULT 0     -- Cantidad de registros afectados
  detalle         TEXT                   -- Mensaje descriptivo
  error           TEXT                   -- Stack trace o mensaje de error
  resuelta        INTEGER DEFAULT 0     -- 1=error fue resuelta manualmente

Funcionalidades:
  - Filtrar por tipo: todos, errores, sincronizacion, documentos, conexion
  - Boton "Reintentar" para operaciones fallidas
  - Boton "Forzar sincronizacion" (envia todo lo pendiente)
  - Contador de operaciones pendientes en el sidebar (badge)
  - Notificacion push cuando hay errores de sync persistentes
```

#### Interfaz Responsive (Adaptativa)

```
PILAR se adapta a TODAS las plataformas con un solo codebase Flutter:

╔══════════════════════════════════════════════════════════════════╗
║  BREAKPOINTS (puntos de quiebre)                                ║
╠══════════════════════════════════════════════════════════════════╣
║  COMPACT  (< 600px)  → Telefono (portrait)                     ║
║    - Sin sidebar, usa bottom navigation o hamburger menu        ║
║    - Listas en vez de tablas (cards apiladas)                   ║
║    - Formularios de una columna                                 ║
║    - FAB para acciones principales                              ║
║                                                                  ║
║  MEDIUM   (600-840px) → Tablet (portrait) / Telefono landscape  ║
║    - Sidebar colapsado (solo iconos, expandible)                ║
║      (ver nota: reemplazado por PilarShell sin sidebar, seccion 6.8)
║    - Tablas con columnas prioritarias (scroll horizontal)       ║
║    - Formularios de 2 columnas                                   ║
║                                                                  ║
║  EXPANDED (840-1200px) → Tablet landscape / Desktop pequeno     ║
║    - Sidebar expandido fijo                                      ║
║      (ver nota: reemplazado por PilarShell sin sidebar, seccion 6.8)
║    - SfDataGrid completo con todas las columnas                  ║
║    - Formularios de 2-3 columnas                                 ║
║    - Master-detail layout (lista + detalle lado a lado)          ║
║                                                                  ║
║  LARGE   (> 1200px) → Desktop / Web                              ║
║    - Sidebar expandido + area de contenido amplia                ║
║      (ver nota: reemplazado por PilarShell sin sidebar, seccion 6.8)
║    - Dashboard con multiples widgets/graficos                    ║
║    - Formularios de 3-4 columnas                                 ║
║    - Multiples paneles visibles simultaneamente                  ║
╚══════════════════════════════════════════════════════════════════╝

Implementacion:
  - LayoutBuilder + MediaQuery para responsive
  - AdaptiveScaffold (Material 3) para structure base
  - Breakpoints como constantes globales
  - Componentes que se adaptan automaticamente:
    • ResponsiveDataView: SfDataGrid en desktop, ListView de cards en mobile
    • ResponsiveForm: columnas segun ancho disponible
    • ResponsiveSidebar: expandido/colapsado/oculto segun breakpoint
      (ver nota: reemplazado por PilarShell sin sidebar, seccion 6.8)
    • ResponsiveDialog: modal en desktop, pantalla completa en mobile

Modulos touch-intensivos (pantallas de operacion directa con el cliente):
  - Touch-friendly: botones grandes, grids con imagenes
  - Landscape optimizado (paneles laterales)
  - Optimizados para tablet y desktop
```

#### Evaluacion de fluent_ui vs Framework Propio (PilarShell)

```
Se evaluo el paquete fluent_ui (https://pub.dev/packages/fluent_ui) que implementa
Microsoft Fluent Design (WinUI3) en Flutter. Ofrece NavigationView responsive,
acrilicos, tipografia adaptativa y layout de desktop profesional.

VENTAJAS de fluent_ui:
  + NavigationView con panel izquierdo que se adapta a 3 modos (open/compact/minimal)
  + Look & feel profesional tipo aplicacion de escritorio
  + Tipografia y spacing adaptativo integrado
  + Soporte multi-plataforma (Windows, macOS, Linux, Web, iOS, Android)
  + Acrylic/Mica effects para interfaces modernas

PROBLEMAS CRITICOS para PILAR:
  ✗ INCOMPATIBLE con Syncfusion: fluent_ui REEMPLAZA Material, no lo complementa.
    Conflictos de nombres: ThemeData, TextButton, Colors, Divider, Tooltip,
    showDialog, Tab, Scrollbar, TextStyle (requiere import 'as' en TODO el codigo)
  ✗ SfDataGrid, SfCalendar, SfCartesianChart, syncfusion_flutter_pdf dependen
    de Material 3 ThemeData/ColorScheme → se romperian con fluent_ui ThemeData
  ✗ flutter_form_builder depende de Material InputDecoration → incompatible
  ✗ go_router + MaterialPage → conflicto con FluentPage de fluent_ui
  ✗ Mantenimiento: paquete no oficial, mantenido por 1 persona (bdlukaa)
  ✗ Toda la documentacion/ejemplos de Supabase y Brick asumen Material

DECISION: NO usar fluent_ui. Construir framework propio "PilarShell" sobre Material 3
que ofrece las mismas capacidades sin conflictos de compatibilidad.

Referencia: https://github.com/bdlukaa/fluent_ui/issues/150
```

#### PilarShell: Framework Responsive Propio sobre Material 3

```
PilarShell es el framework de UI responsive de PILAR ERP. Gestiona automaticamente:
  - Menus/navegacion (sidebar, bottom nav, drawer)
  - Rutas + titulos + breadcrumbs
  - Header y footer informativos
  - Escalado automatico de fuentes y componentes segun dispositivo
  - Breakpoints con transiciones animadas

═══════════════════════════════════════════════════════════════════════════
ARQUITECTURA DEL FRAMEWORK
═══════════════════════════════════════════════════════════════════════════

  PilarApp (MaterialApp + ThemeData responsive)
    └── PilarShell (layout principal adaptativo)
          ├── PilarHeader (barra superior con info contextual)
          ├── PilarNavigation (sidebar/rail/drawer/bottom segun breakpoint)
          ├── PilarContent (area de contenido con WorkspaceTabs)
          └── PilarFooter (barra inferior con info de estado)

═══════════════════════════════════════════════════════════════════════════
PilarApp: MaterialApp con Tipografia y Componentes Auto-Escalados
═══════════════════════════════════════════════════════════════════════════

El punto de entrada configura Material 3 con escalado automatico:

  class PilarApp extends StatelessWidget {
    Widget build(context) {
      return MaterialApp(
        theme: _buildTheme(context, Brightness.light),
        darkTheme: _buildTheme(context, Brightness.dark),
        themeMode: ref.watch(themeProvider).mode,
        builder: (context, child) {
          // Escalar TODA la tipografia y componentes segun dispositivo
          final scaleFactor = _getScaleFactor(context);
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scaleFactor),
            ),
            child: child!,
          );
        },
      );
    }
  }

ESCALADO AUTOMATICO DE FUENTES Y COMPONENTES:

  ┌─────────────────┬───────────────────┬───────────────────────────────┐
  │ Breakpoint       │ Factor de Escala  │ Efecto                        │
  ├─────────────────┼───────────────────┼───────────────────────────────┤
  │ COMPACT (<600)   │ 0.85              │ Fuentes mas pequenas, botones │
  │                   │                   │ mas compactos, padding 4-8px  │
  ├─────────────────┼───────────────────┼───────────────────────────────┤
  │ MEDIUM (600-840) │ 0.92              │ Fuentes ligeramente menores,  │
  │                   │                   │ padding 8-12px                │
  ├─────────────────┼───────────────────┼───────────────────────────────┤
  │ EXPANDED (840+)  │ 1.00              │ Tamano base (14px body),      │
  │                   │                   │ padding 12-16px               │
  ├─────────────────┼───────────────────┼───────────────────────────────┤
  │ LARGE (>1200)    │ 1.00              │ Mismo tamano base, mas espacio│
  │                   │                   │ para multi-panel y dashboards │
  └─────────────────┴───────────────────┴───────────────────────────────┘

  Ademas del factor global, cada TextTheme se escala:
    - displayLarge:  28 * factor  (titulos de pagina)
    - headlineMedium: 22 * factor (titulos de seccion)
    - titleLarge:    18 * factor  (titulos de card/panel)
    - titleMedium:   16 * factor  (subtitulos)
    - bodyLarge:     15 * factor  (texto principal)
    - bodyMedium:    14 * factor  (texto normal - BASE)
    - bodySmall:     12 * factor  (texto secundario)
    - labelLarge:    14 * factor  (botones)
    - labelSmall:    11 * factor  (badges, chips)

COMPONENTES QUE SE ADAPTAN AUTOMATICAMENTE:
  - Botones: tamano minimo 36px (COMPACT) → 40px (MEDIUM) → 48px (EXPANDED)
  - IconButtons: 32px → 36px → 40px
  - Inputs (TextField): altura 40px → 44px → 48px
  - Cards: padding 8px → 12px → 16px
  - DataGrid: row height 36px → 44px → 48px (configurable en preferencias)
  - Dialog: ancho max(320, 50% pantalla) en desktop, fullscreen en mobile
  - FAB: 48px → 56px (solo visible en COMPACT/MEDIUM)
  - Chips/Badges: 24px → 28px → 32px

IMPLEMENTACION:
  // core/theme/responsive_sizes.dart
  class PilarSizes {
    final double buttonHeight;
    final double inputHeight;
    final double iconButtonSize;
    final double cardPadding;
    final double rowHeight;
    final double chipHeight;
    final EdgeInsets pagePadding;

    factory PilarSizes.fromBreakpoint(PilarBreakpoint bp) {
      switch (bp) {
        case PilarBreakpoint.compact:
          return PilarSizes(buttonHeight: 36, inputHeight: 40, ...);
        case PilarBreakpoint.medium:
          return PilarSizes(buttonHeight: 40, inputHeight: 44, ...);
        case PilarBreakpoint.expanded:
        case PilarBreakpoint.large:
          return PilarSizes(buttonHeight: 48, inputHeight: 48, ...);
      }
    }
  }

  // Acceso via InheritedWidget o Riverpod:
  final sizes = PilarSizes.of(context);
  // o
  final sizes = ref.watch(pilarSizesProvider);

═══════════════════════════════════════════════════════════════════════════
PilarShell: Layout Adaptativo Completo
═══════════════════════════════════════════════════════════════════════════

Detecta automaticamente el breakpoint y muestra el layout apropiado.
SIN SIDEBAR: El espacio completo es para contenido (datos, grids, formularios).
La navegacion esta en el Header (MenuBar + App Launcher estilo Odoo).

LARGE (> 1200px) - Desktop/Web:
┌──────────────────────────────────────────────────────────────────────────┐
│ PilarHeader con ModuleMenuBar                                             │
│ [⊞][Modulo A ▼][Modulo B ▼][Modulo C ▼][Config ▼]  [Emp ▼][🔔][🌙][👤]│
├──────────────────────────────────────────────────────────────────────────┤
│ PilarContent (100% ancho)                                                 │
│ ┌──────────────────────────────────────────────────────────────────────┐ │
│ │ [Tab 1 x] [Tab 2 x] [Tab 3 x] [+]                                   │ │
│ ├──────────────────────────────────────────────────────────────────────┤ │
│ │                                                                        │ │
│ │  Contenido del tab activo (CrudScaffold, FormScaffold, Dashboard)     │ │
│ │  Aprovecha TODO el ancho → grids mas anchos, formularios 2-3 cols     │ │
│ │                                                                        │ │
│ └──────────────────────────────────────────────────────────────────────┘ │
├──────────────────────────────────────────────────────────────────────────┤
│ PilarFooter                                                               │
│ [v1.0.0] [Empresa: Comercial XYZ - RUC: 1790XXX001] [● Online] [🕐]    │
└──────────────────────────────────────────────────────────────────────────┘

EXPANDED (840-1200px) - Tablet Landscape / Desktop Pequeno:
┌──────────────────────────────────────────────────────────────────────────┐
│ PilarHeader con ModuleMenuBar (compacto)                                  │
│ [⊞][Modulo A][Modulo B][Modulo C][Config]      [Emp ▼][🔔][🌙][👤]      │
├──────────────────────────────────────────────────────────────────────────┤
│ PilarContent (100% ancho)                                                 │
│ ┌──────────────────────────────────────────────────────────────────────┐ │
│ │ [Tab 1 x] [Tab 2 x] [+]                                              │ │
│ ├──────────────────────────────────────────────────────────────────────┤ │
│ │  Contenido                                                             │ │
│ │                                                                        │ │
│ └──────────────────────────────────────────────────────────────────────┘ │
├──────────────────────────────────────────────────────────────────────────┤
│ PilarFooter (compacto: version + estado conexion)                         │
└──────────────────────────────────────────────────────────────────────────┘

MEDIUM (600-840px) - Tablet Portrait:
┌──────────────────────────────────────────────────────────────────────┐
│ PilarHeader                                                           │
│ [⊞][Ventas] [Pedidos][Facturacion][Clientes]       [🔔][👤]         │
├──────────────────────────────────────────────────────────────────────┤
│ PilarContent (sin tabs, pantalla completa)                            │
│ ┌──────────────────────────────────────────────────────────────────┐ │
│ │  Breadcrumb: Modulo > Seccion > Registro                          │ │
│ ├──────────────────────────────────────────────────────────────────┤ │
│ │  Contenido (CrudScaffold o FormScaffold)                         │ │
│ └──────────────────────────────────────────────────────────────────┘ │
├──────────────────────────────────────────────────────────────────────┤
│ PilarFooter (solo icono de estado)                                    │
└──────────────────────────────────────────────────────────────────────┘
  - MenuBar se convierte en tabs scrollables en el header
  - Sub-items se muestran al tap (PopupMenu)

COMPACT (< 600px) - Telefono:
┌────────────────────────────────┐
│ AppBar: [⊞] Facturas [🔔][👤] │
├────────────────────────────────┤
│                                │
│  Contenido (lista cards o     │
│  formulario fullscreen)        │
│                                │
├────────────────────────────────┤
│ BottomNav: [🏠][📄][➕][📊][⋮]│
└────────────────────────────────┘
  ⊞ = Drawer con grid de modulos + menu del activo
  BottomNav: items principales del modulo activo (max 5)
  [⋮] Mas: lista completa de items del modulo
  Sin tabs, sin footer. Breadcrumb en AppBar title

═══════════════════════════════════════════════════════════════════════════
PilarNavigation: Menus y Modulos Estilo Odoo
═══════════════════════════════════════════════════════════════════════════

Inspirado en Odoo: App Launcher (grid de modulos) + MenuBar por modulo activo.
NO usa sidebar fijo (desperdicia espacio en pantallas con mucho dato tabular).

CONCEPTO CENTRAL:
  1. App Launcher: Grid de iconos de todos los modulos habilitados
  2. Modulo Activo: Al seleccionar un modulo, su MenuBar aparece en el header
  3. MenuBar: Items del modulo activo con dropdowns de sub-items
  4. Cada modulo tiene opcionalmente un menu "Configuracion"

LAYOUT DESKTOP (LARGE/EXPANDED):
┌──────────────────────────────────────────────────────────────────────────┐
│ [⊞] [SeccionA ▼] [SeccionB ▼] [SeccionC ▼] [Reportes ▼] [Config ▼]   │
│                                                   [🔔3] [🌙] [👤 Juan]│
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│                    CONTENT AREA (100% ancho disponible)                   │
│                    DataGrid / Formulario / Dashboard / Kanban            │
│                                                                          │
├──────────────────────────────────────────────────────────────────────────┤
│ [Footer: Pilar v1.0 | Empresa | RUC | 🟢 Online | 15:30]               │
└──────────────────────────────────────────────────────────────────────────┘

  Al hacer click en [⊞] App Launcher:
  ┌─────────────────────────────────────────┐
  │  🔍 Buscar modulo...                     │
  │                                          │
  │  📊 Módulo A      📦 Módulo B            │
  │  🛒 Módulo C      🏭 Módulo D            │
  │  💳 Módulo E      📒 Módulo F            │
  │  ...              ⚙️ Admin               │
  │                                          │
  │  Solo muestra modulos habilitados por    │
  │  modulos_empresa + permisos del usuario  │
  └─────────────────────────────────────────┘

  Al hacer click en [Modulo A ▼]:
  ┌──────────────────┐
  │  Seccion 1        │
  │  Seccion 2        │
  │  Seccion 3        │
  │  ─────────────    │
  │  Reportes         │
  └──────────────────┘

LAYOUT TABLET (MEDIUM):
┌──────────────────────────────────────────────────────────────────┐
│ [⊞] [Modulo A] [Modulo B] [Modulo C] [Modulo D]  [🔔] [👤]    │
├──────────────────────────────────────────────────────────────────┤
│                    CONTENT AREA                                  │
├──────────────────────────────────────────────────────────────────┤
│ [Footer compacto]                                                │
└──────────────────────────────────────────────────────────────────┘
  - MenuBar se convierte en tabs scrollables
  - Sub-items se muestran al tap (bottom sheet o dropdown)

LAYOUT MOVIL (COMPACT):
┌──────────────────────────────┐
│ [⊞] [Titulo Pagina]  [🔔][👤]│
├──────────────────────────────┤
│                              │
│      CONTENT AREA            │
│                              │
├──────────────────────────────┤
│ [🏠] [📄] [➕] [📊] [⋮]    │ ← Bottom Navigation
└──────────────────────────────┘
  - ⊞ abre drawer con grid de modulos
  - Bottom Nav: max 5 items del modulo activo
  - [⋮] Mas: abre lista completa de items del modulo

MODELO DE DATOS DE MENU:

  // Modelo jerarquico: PilarModule > PilarMenuGroup > PilarMenuItem
  class PilarModule {
    final String id;               // 'mi_modulo' → vinculado a tabla modulos
    final String label;            // 'Mi Modulo'
    final IconData icon;           // Icons.widgets
    final String? permission;      // Permiso a nivel modulo
    final List<PilarMenuGroup> menuGroups;  // Grupos de menu del modulo
  }

  class PilarMenuGroup {
    final String label;            // 'Principal', 'Reportes', 'Configuracion'
    final List<PilarMenuItem> items;
  }

  class PilarMenuItem {
    final String id;               // 'mi_seccion'
    final String label;            // 'Mi Seccion'
    final String path;             // '/mi_modulo/mi_seccion'
    final IconData? icon;          // Icono opcional (para bottom nav)
    final String? permission;      // Permiso especifico
    final int Function()? badge;   // Badge count (ej: pendientes)
    final Widget Function()? builder; // Constructor de la pantalla
  }

EJEMPLO GENERICO - UN MODULO:

  PilarModule(
    id: 'mi_modulo', label: 'Mi Modulo', icon: Icons.extension,
    menuGroups: [
      PilarMenuGroup(label: 'Seccion A', items: [
        PilarMenuItem(id: 'item_1', label: 'Item 1',
          path: '/mi_modulo/item_1', permission: 'mi_modulo.item_1.ver'),
        PilarMenuItem(id: 'item_2', label: 'Item 2',
          path: '/mi_modulo/item_2', permission: 'mi_modulo.item_2.ver'),
      ]),
      PilarMenuGroup(label: 'Reportes', items: [
        PilarMenuItem(id: 'reportes', label: 'Reportes',
          path: '/mi_modulo/reportes'),
      ]),
      PilarMenuGroup(label: 'Configuracion', items: [
        PilarMenuItem(id: 'config', label: 'Ajustes',
          path: '/mi_modulo/config', permission: 'mi_modulo.config'),
      ]),
    ],
  ),

  // Cada modulo define su propia instancia de PilarModule en su propio directorio features/<modulo>/

GENERACION AUTOMATICA:
  - go_router ShellRoutes se generan desde pilarModules
  - App Launcher grid se genera desde pilarModules (filtrado por modulos_empresa)
  - MenuBar se genera desde menuGroups del modulo activo (filtrado por permisos)
  - Bottom Nav se genera desde los primeros items de cada grupo (max 5)
  - Breadcrumbs: Modulo > Grupo > Item
  - Titulos de pagina se extraen de PilarMenuItem.label

WIDGET AppLauncherGrid:
  - GridView.builder con modulos habilitados
  - Cada tile: icono + label + badge opcional (notificaciones pendientes)
  - Filtrado por: modulos_empresa + permisos del usuario
  - Busqueda por texto (filter)
  - Se puede agregar a favoritos (se guardan en preferencias)
  - Animacion: Overlay que sale desde el boton ⊞ (como Odoo)

WIDGET ModuleMenuBar (solo desktop/tablet):
  - Row de TextButton con PopupMenuButton por cada MenuGroup
  - Separadores visuales entre grupos
  - Badges en items con notificaciones
  - Highlight del item activo (current route)
  - En tablet: ScrollableRow con overflow indicator

═══════════════════════════════════════════════════════════════════════════
PilarHeader: Barra Superior Adaptativa
═══════════════════════════════════════════════════════════════════════════

Se integra con el MenuBar del modulo activo (estilo Odoo):

  LARGE:    [⊞] [ModuleMenuBar...............] [Empresa ▼] [🔔 3] [🌙] [👤 Juan ▼]
  EXPANDED: [⊞] [ModuleMenuBar...............] [Empresa ▼] [🔔]   [🌙] [👤]
  MEDIUM:   [⊞] [Modulo] [Tab1] [Tab2] [Tab3]              [🔔]         [👤]
  COMPACT:  [⊞] [Titulo Pagina]                             [🔔]         [👤]

Componentes:
  - ⊞ App Launcher: abre grid de modulos (overlay en desktop, drawer en movil)
  - ModuleMenuBar: menus del modulo activo con dropdowns (solo LARGE/EXPANDED)
  - Empresa selector: dropdown, recarga datos y modulos al cambiar
  - 🔔 Notificaciones: badge + panel lateral (EndDrawer)
  - 🌙/☀ toggle tema (solo LARGE/EXPANDED, en MEDIUM/COMPACT va en drawer)
  - 👤 menu usuario: perfil, preferencias, cambiar empresa, cerrar sesion

═══════════════════════════════════════════════════════════════════════════
PilarFooter: Barra Inferior Informativa
═══════════════════════════════════════════════════════════════════════════

Barra inferior con informacion contextual (solo desktop/tablet):

  LARGE:    [v1.0.0] [Comercial XYZ S.A. - RUC: 1790XXX001] [● Online | Sync OK] [15/02/2026 10:30]
  EXPANDED: [v1.0.0] [Comercial XYZ] [● Online] [10:30]
  MEDIUM:   [● Online]
  COMPACT:  (sin footer - se usa la barra de estado del SO)

Componentes:
  - Version de la app
  - Nombre/RUC de la empresa activa
  - Indicador de conexion + estado sync
  - Fecha/hora actual (actualizada cada minuto)
  - Click en estado conexion: abre log de sincronizacion

═══════════════════════════════════════════════════════════════════════════
Breadcrumbs Automaticos
═══════════════════════════════════════════════════════════════════════════

En MEDIUM/COMPACT donde no hay sidebar visible, se muestran breadcrumbs:

  Modulo > Seccion > Registro

  - Se generan automaticamente desde la jerarquia de PilarRoute
  - Click en cualquier nivel navega a esa pantalla
  - En LARGE/EXPANDED se muestran DENTRO del area de contenido (sobre el titulo)
  - En MEDIUM/COMPACT se muestran debajo del AppBar
```

```
ESTRUCTURA DE ARCHIVOS DEL FRAMEWORK PilarShell:

lib/core/
  ├── shell/                          # Framework PilarShell
  │   ├── pilar_app.dart              # MaterialApp con auto-scaling
  │   ├── pilar_shell.dart            # Layout adaptativo (header+nav+content+footer)
  │   ├── pilar_header.dart           # Barra superior adaptativa
  │   ├── pilar_navigation.dart       # Sidebar/Rail/Drawer/BottomNav unificado
  │   ├── pilar_footer.dart           # Barra inferior informativa
  │   ├── pilar_route.dart            # Modelo de ruta con permisos y builders
  │   ├── pilar_route_config.dart     # Definicion de todas las rutas del ERP
  │   ├── pilar_breadcrumbs.dart      # Breadcrumbs automaticos
  │   └── pilar_breakpoint.dart       # Enum + deteccion de breakpoint actual
  ├── theme/                          # Sistema de temas
  │   ├── app_theme.dart              # ThemeData builder (light + dark + seedColor)
  │   ├── responsive_sizes.dart       # PilarSizes: tamanos por breakpoint
  │   ├── color_schemes.dart          # Paletas predefinidas
  │   ├── typography.dart             # TextTheme escalado por factor
  │   └── spacing.dart                # EdgeInsets/padding por densidad
  ├── widgets/                        # Widgets reutilizables (usan PilarSizes)
  │   ├── workspace_tabs.dart
  │   ├── crud_scaffold.dart
  │   ├── form_scaffold.dart
  │   ├── data_grid.dart
  │   ├── search_bar.dart
  │   ├── filter_panel.dart
  │   ├── export_button.dart
  │   ├── pagination_bar.dart
  │   ├── status_badge.dart
  │   ├── connection_indicator.dart
  │   ├── empresa_selector.dart
  │   ├── notification_bell.dart
  │   ├── theme_toggle.dart
  │   ├── form_fields.dart
  │   ├── chat_widget.dart
  │   └── pdf_viewer.dart
  └── providers/
      ├── theme_provider.dart         # Tema + preferencias visuales
      ├── preferences_provider.dart   # shared_preferences
      ├── connection_provider.dart    # Estado conexion
      ├── tabs_provider.dart          # Tabs abiertos
      ├── permissions_provider.dart   # Permisos usuario
      ├── navigation_provider.dart    # Ruta activa + breadcrumbs
      └── breakpoint_provider.dart    # Breakpoint actual reactivo
```

#### go_router: Navegacion Declarativa Integrada con PilarShell

```
go_router es el paquete oficial de navegacion declarativa de Flutter.
Se integra con PilarShell usando ShellRoute para envolver todas las
pantallas autenticadas dentro del layout principal (header+sidebar+tabs+footer).

ESTRUCTURA DE RUTAS:

  GoRouter(
    initialLocation: '/dashboard',
    redirect: (context, state) {
      // Redirigir a login si no autenticado
      final session = supabase.auth.currentSession;
      final isAuthRoute = state.matchedLocation.startsWith('/auth');
      if (session == null && !isAuthRoute) return '/auth/login';
      if (session != null && isAuthRoute) return '/dashboard';
      // Redirigir a selector empresa si no tiene empresa activa
      final empresaId = ref.read(empresaProvider);
      if (session != null && empresaId == null && !isAuthRoute)
        return '/auth/select-empresa';
      return null;
    },
    routes: [
      // ═══════════════════════════════════════════════
      // RUTAS DE AUTENTICACION (sin PilarShell)
      // ═══════════════════════════════════════════════
      GoRoute(
        path: '/auth/login',
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: '/auth/signup',
        builder: (_, __) => const SignupScreen(),
      ),
      GoRoute(
        path: '/auth/forgot-password',
        builder: (_, __) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/auth/reset-password',
        builder: (_, __) => const ResetPasswordScreen(),
      ),
      GoRoute(
        path: '/auth/magic-link',
        builder: (_, __) => const MagicLinkScreen(),
      ),
      GoRoute(
        path: '/auth/select-empresa',
        builder: (_, __) => const SelectEmpresaScreen(),
      ),

      // ═══════════════════════════════════════════════
      // RUTAS AUTENTICADAS (dentro de PilarShell)
      // ═══════════════════════════════════════════════
      ShellRoute(
        builder: (context, state, child) {
          // PilarShell envuelve TODAS las pantallas autenticadas
          return PilarShell(child: child);
        },
        routes: [
          GoRoute(path: '/dashboard', builder: (_, __) => DashboardScreen()),

          // Las rutas de cada modulo se registran dinamicamente via PilarModule.routes
          // Cada modulo activo aporta sus propias rutas al router global:
          //   GoRoute(path: '/modulo_a/seccion_1', builder: ...),
          //   GoRoute(path: '/modulo_a/seccion_1/:id', builder: ...),
          //   GoRoute(path: '/modulo_b/seccion_1', builder: ...),
          //   ... etc.

          // ... todas las rutas de modulos generadas desde PilarRoute

          // Settings
          GoRoute(path: '/settings/profile', builder: ...),
          GoRoute(path: '/settings/preferences', builder: ...),
          GoRoute(path: '/settings/empresa', builder: ...),
        ],
      ),
    ],
  )

GENERACION AUTOMATICA DE RUTAS:
  Las GoRoute se generan programaticamente desde pilarRoutes (PilarRoute[]):
    - Cada PilarRoute con path != null genera un GoRoute
    - Los children generan sub-rutas
    - PilarRoute sin permiso siempre se incluye
    - PilarRoute con permiso verifica en runtime (redirect a /403 si no tiene)
    - Rutas con :id parametro abren FormScaffold en modo edicion

DEEP LINKS (requeridos para supabase_auth_ui):
  - Web: configurados automaticamente
  - iOS: Universal Links (apple-app-site-association)
  - Android: App Links (assetlinks.json)
  - Esquema custom: io.pilar.erp://callback
  - Redirect URL para Supabase Auth: io.pilar.erp://auth-callback
```

#### supabase_auth_ui: Widgets de Autenticacion Pre-Construidos

```
PILAR usa supabase_auth_ui para las pantallas de autenticacion,
aprovechando los widgets pre-construidos que se adaptan al tema de la app
(flex_color_scheme les aplica estilos automaticamente).

═══════════════════════════════════════════════════════════════════
LOGIN SCREEN (features/auth/screens/login_screen.dart)
═══════════════════════════════════════════════════════════════════

  Usa AuthLayout (widget propio con logo PILAR centrado) + widgets de supabase_auth_ui:

  ┌──────────────────────────────────────────────────────┐
  │                                                        │
  │              [Logo PILAR ERP]                           │
  │              Sistema ERP para Ecuador                   │
  │                                                        │
  │  ┌──────────────────────────────────────────────────┐ │
  │  │  SupaEmailAuth(                                   │ │
  │  │    redirectTo: kIsWeb ? null                       │ │
  │  │      : 'io.pilar.erp://auth-callback',            │ │
  │  │    onSignInComplete: (response) {                  │ │
  │  │      // Navegar a selector de empresa              │ │
  │  │      context.go('/auth/select-empresa');           │ │
  │  │    },                                              │ │
  │  │    onSignUpComplete: (response) {                  │ │
  │  │      // Mostrar mensaje "revisa tu email"          │ │
  │  │    },                                              │ │
  │  │  )                                                 │ │
  │  │                                                    │ │
  │  │  [Email: ___________________]                      │ │
  │  │  [Password: ________________]                      │ │
  │  │  [     Iniciar Sesion      ]                       │ │
  │  │  [     Crear Cuenta        ]                       │ │
  │  │  ¿Olvidaste tu contraseña?                        │ │
  │  └──────────────────────────────────────────────────┘ │
  │                                                        │
  │  ─────────── o continuar con ───────────               │
  │                                                        │
  │  ┌──────────────────────────────────────────────────┐ │
  │  │  SupaSocialsAuth(                                 │ │
  │  │    socialProviders: [                              │ │
  │  │      OAuthProvider.google,                         │ │
  │  │      OAuthProvider.apple,  // solo iOS/macOS       │ │
  │  │    ],                                              │ │
  │  │    colored: true,                                  │ │
  │  │    redirectUrl: 'io.pilar.erp://auth-callback',   │ │
  │  │    onSuccess: (session) {                          │ │
  │  │      context.go('/auth/select-empresa');           │ │
  │  │    },                                              │ │
  │  │  )                                                 │ │
  │  │                                                    │ │
  │  │  [G  Continuar con Google  ]                       │ │
  │  │  [   Continuar con Apple  ]  (si aplica)          │ │
  │  └──────────────────────────────────────────────────┘ │
  │                                                        │
  │  [Magic Link: Acceder sin contraseña →]               │
  │                                                        │
  └──────────────────────────────────────────────────────┘

═══════════════════════════════════════════════════════════════════
SIGNUP SCREEN (features/auth/screens/signup_screen.dart)
═══════════════════════════════════════════════════════════════════

  SupaEmailAuth con metadataFields adicionales:

  SupaEmailAuth(
    redirectTo: kIsWeb ? null : 'io.pilar.erp://auth-callback',
    onSignUpComplete: (response) {
      // Mostrar "Revisa tu email para confirmar tu cuenta"
      ScaffoldMessenger.of(context).showSnackBar(...);
      context.go('/auth/login');
    },
    metadataFields: [
      MetaDataField(
        label: 'Nombre completo',
        key: 'full_name',
        validator: (val) => val == null || val.isEmpty
          ? 'El nombre es requerido' : null,
      ),
      MetaDataField(
        label: 'Telefono',
        key: 'phone',
        prefixIcon: const Icon(Icons.phone),
      ),
      BooleanMetaDataField(
        label: 'Acepto los terminos y condiciones',
        key: 'terms_accepted',
        isRequired: true,
      ),
    ],
  )

  Metadata se almacena en auth.users.raw_user_meta_data (JSONB).
  Un trigger PostgreSQL puede copiar estos datos a la tabla usuarios al crear cuenta.

═══════════════════════════════════════════════════════════════════
FORGOT PASSWORD SCREEN (features/auth/screens/forgot_password_screen.dart)
═══════════════════════════════════════════════════════════════════

  Envia email con link para restablecer contraseña:

  SupaMagicAuth(
    redirectUrl: kIsWeb ? null : 'io.pilar.erp://reset-callback',
    onSuccess: (session) {
      // Si viene del deep link, navegar a reset password
      context.go('/auth/reset-password');
    },
    onError: (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${error.message}')),
      );
    },
  )

═══════════════════════════════════════════════════════════════════
RESET PASSWORD SCREEN (features/auth/screens/reset_password_screen.dart)
═══════════════════════════════════════════════════════════════════

  El usuario llega aqui via deep link despues de hacer click en el email:

  SupaResetPassword(
    accessToken: supabase.auth.currentSession?.accessToken ?? '',
    onSuccess: (response) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Contraseña actualizada')),
      );
      context.go('/auth/login');
    },
    onError: (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${error.message}')),
      );
    },
  )

═══════════════════════════════════════════════════════════════════
SELECT EMPRESA SCREEN (features/auth/screens/select_empresa_screen.dart)
═══════════════════════════════════════════════════════════════════

  Pantalla PROPIA (no de supabase_auth_ui) que se muestra post-login:

  ┌──────────────────────────────────────────────────────┐
  │                                                        │
  │  Bienvenido, Juan Carlos                               │
  │  Selecciona la empresa con la que deseas trabajar:     │
  │                                                        │
  │  ┌────────────────────────────────────────────────┐   │
  │  │ 🏢 Comercial XYZ S.A.                          │   │
  │  │    RUC: 1790123456001                           │   │
  │  │    Rol: Administrador                           │   │
  │  │    Plan: Professional                            │   │
  │  └────────────────────────────────────────────────┘   │
  │  ┌────────────────────────────────────────────────┐   │
  │  │ 🏢 Distribuidora ABC                           │   │
  │  │    RUC: 1791234567001                           │   │
  │  │    Rol: Contador                                │   │
  │  │    Plan: Basic                                   │   │
  │  └────────────────────────────────────────────────┘   │
  │                                                        │
  │  Al seleccionar → actualiza JWT claims (empresa_id,    │
  │  rol, permisos[]) → navega a /dashboard                │
  │                                                        │
  └──────────────────────────────────────────────────────┘

  Si el usuario solo tiene 1 empresa → se selecciona automaticamente.
  Si tiene 0 empresas → muestra mensaje "Contacta al administrador".

FLUJO COMPLETO DE AUTENTICACION:

  ┌─────────┐    ┌──────────┐    ┌───────────────┐    ┌───────────┐
  │ Login   │───→│ Supabase │───→│ Select Empresa│───→│ Dashboard │
  │ Screen  │    │ Auth     │    │ Screen        │    │ (PilarShell)│
  │(email/  │    │(verifica)│    │(carga empresas│    │            │
  │ social/ │    │          │    │ del usuario,  │    │            │
  │ magic)  │    │          │    │ setea JWT)    │    │            │
  └─────────┘    └──────────┘    └───────────────┘    └───────────┘
       │                               │
       │ ¿Olvido password?             │ Si solo 1 empresa
       ▼                               │ → skip automatico
  ┌───────────┐                        ▼
  │ Forgot PW │──→ Email ──→ Deep Link ──→ Reset Password Screen
  └───────────┘

DEEP LINK LISTENER (auth_state_provider.dart):
  // Escucha cambios de sesion (login, logout, token refresh, deep link)
  supabase.auth.onAuthStateChange.listen((data) {
    final event = data.event;
    if (event == AuthChangeEvent.signedIn) {
      // Navegar a selector empresa
    } else if (event == AuthChangeEvent.signedOut) {
      // Navegar a login
    } else if (event == AuthChangeEvent.passwordRecovery) {
      // Navegar a reset password
    } else if (event == AuthChangeEvent.tokenRefreshed) {
      // Actualizar providers
    }
  });
```

#### Estrategia: Core Widgets Primero, Modulos Despues

```
PILAR sigue una estrategia "CORE FIRST": todos los widgets base, providers
reactivos y la capa de datos offline-first deben estar listos y probados
ANTES de implementar cualquier modulo de negocio.

RAZON: Cada modulo de negocio usa exactamente los mismos patrones.
Si los widgets core estan bien hechos, implementar un modulo nuevo es solo
"configurar" CrudScaffold/FormScaffold con las columnas, filtros y campos
especificos. Sin el core, cada modulo reinventaria la rueda.

ORDEN DE IMPLEMENTACION (Fase 1):

  ┌─────────────────────────────────────────────────────────────────────┐
  │ CAPA 1: INFRAESTRUCTURA (semana 1-2)                                │
  │  ✦ Supabase config + Auth + RLS + Storage                          │
  │  ✦ brick_offline_first_with_supabase (Repository, modelos base)    │
  │  ✦ flex_color_scheme + theme provider + shared_preferences         │
  │  ✦ go_router + deep links + supabase_auth_ui (login/signup/reset)  │
  ├─────────────────────────────────────────────────────────────────────┤
  │ CAPA 2: CAPA REACTIVA DE DATOS (semana 2-3)                        │
  │  ✦ BrickDataProvider<T> (Riverpod + Brick subscribe/Realtime)      │
  │  ✦ Politicas de resolucion de conflictos                           │
  │  ✦ Monitor de conectividad + cola offline                          │
  │  ✦ Log de sincronizacion                                           │
  ├─────────────────────────────────────────────────────────────────────┤
  │ CAPA 3: WIDGETS CORE (semana 3-5)                                   │
  │  ✦ PilarShell (header, nav, footer, tabs)                          │
  │  ✦ CrudScaffold<T> (usa BrickDataProvider para datos reactivos)    │
  │  ✦ FormScaffold<T> (usa Repository.upsert para guardar)            │
  │  ✦ DataGrid, FilterPanel, SearchBar, PaginationBar, ExportButton   │
  │  ✦ Roles/Permisos provider                                         │
  ├─────────────────────────────────────────────────────────────────────┤
  │ CAPA 4: MODULOS DE NEGOCIO (semana 5+)                              │
  │  ✦ Cada modulo define: modelo Brick, columnas, filtros,            │
  │    campos del formulario, acciones especificas del modulo           │
  │  ✦ TODO lo demas (grid, paginacion, export, sync, permisos,        │
  │    tabs, responsive) viene del core                                 │
  └─────────────────────────────────────────────────────────────────────┘

BENEFICIOS:
  - Un modulo nuevo se implementa en 2-3 dias en vez de 2 semanas
  - Consistencia visual y funcional garantizada entre todos los modulos
  - Bugs se corrigen UNA VEZ en el core, se arreglan en TODOS los modulos
  - Tests del core cubren la funcionalidad comun (80% del codigo)
  - Facilita agregar modulos futuros sin tocar el core
```

#### Arquitectura Reactiva Offline-First (Brick + Riverpod + Realtime)

```
PRINCIPIO FUNDAMENTAL:
  Los widgets NUNCA leen directamente de Supabase.
  Los widgets SIEMPRE leen de la base local SQLite (via Brick).
  Brick se encarga de sincronizar con Supabase en background.
  Cuando un dato cambia en la base local, TODOS los widgets que
  muestran ese dato se actualizan automaticamente.

═══════════════════════════════════════════════════════════════════════════
FLUJO DE DATOS COMPLETO
═══════════════════════════════════════════════════════════════════════════

  ┌──────────────────────────────────────────────────────────────────────┐
  │                        WIDGETS (UI)                                   │
  │   CrudScaffold ← StreamBuilder ← BrickDataProvider<T>.stream        │
  │   FormScaffold ← ref.watch(brickItemProvider(id))                    │
  │   Dashboard    ← ref.watch(brickStatsProvider)                       │
  │   Badges/KPIs  ← ref.watch(brickCountProvider<T>)                   │
  └──────────────────────────┬──────────────────────────────┬────────────┘
                             │ LECTURA (stream/watch)       │ ESCRITURA
                             ▼                               ▼
  ┌──────────────────────────────────────────────────────────────────────┐
  │                  BrickDataProvider<T> (Riverpod)                      │
  │                                                                       │
  │  subscribe():                                                         │
  │    Stream<List<T>> de la BD local SQLite                              │
  │    Se emite CADA VEZ que la tabla local cambia                        │
  │    (por sync remoto, por escritura local, por cache invalidation)     │
  │                                                                       │
  │  subscribeToRealtime():                                               │
  │    Stream<List<T>> que ADEMAS escucha Supabase Realtime               │
  │    Cuando otro usuario modifica datos → Realtime notifica →           │
  │    Brick descarga el cambio → actualiza SQLite local →                │
  │    subscribe() emite nueva lista → widgets se actualizan              │
  └──────────────────────────┬──────────────────────────────┬────────────┘
                             │                               │
                             ▼                               ▼
  ┌──────────────────────────────────────────────────────────────────────┐
  │              OfflineFirstWithSupabaseRepository                       │
  │                                                                       │
  │  get<T>(query):   SQLite primero → si stale → fetch Supabase →       │
  │                   actualiza SQLite → retorna datos locales            │
  │                                                                       │
  │  upsert<T>(model): Guarda en SQLite INMEDIATAMENTE →                 │
  │                     Encola POST/PATCH a Supabase →                    │
  │                     Si online: ejecuta inmediatamente                 │
  │                     Si offline: queda en cola, reintenta al reconectar│
  │                                                                       │
  │  delete<T>(model):  Borra de SQLite INMEDIATAMENTE →                 │
  │                     Encola DELETE a Supabase                          │
  │                                                                       │
  │  subscribe<T>(query): Stream local (cambios en SQLite)               │
  │  subscribeToRealtime<T>(query): Stream local + Realtime remoto       │
  └──────────────────────────┬──────────────────────────────┬────────────┘
                             │                               │
                    ┌────────▼────────┐            ┌────────▼────────┐
                    │   SQLite Local   │            │  Supabase Remote│
                    │   (Brick cache)  │            │  (PostgreSQL)   │
                    │                  │            │                  │
                    │  Fuente primaria │◄──────────│  Fuente de verdad│
                    │  para la UI      │  sync      │  (con RLS)       │
                    └─────────────────┘            └──────────────────┘

═══════════════════════════════════════════════════════════════════════════
BrickDataProvider<T>: Provider Riverpod Reactivo
═══════════════════════════════════════════════════════════════════════════

  Cada modelo tiene su provider que expone un Stream reactivo:

  // core/providers/brick_data_provider.dart

  /// Provider generico que conecta Brick con Riverpod.
  /// TODOS los CrudScaffold y FormScaffold usan este patron.
  @riverpod
  class BrickList<T extends OfflineFirstWithSupabaseModel> extends _$BrickList {
    StreamSubscription? _subscription;

    @override
    AsyncValue<List<T>> build({Query? query}) {
      // Suscribirse a cambios locales + Realtime
      _subscription = Repository()
        .subscribeToRealtime<T>(query: query)
        .listen((items) {
          state = AsyncData(items);
        });

      ref.onDispose(() => _subscription?.cancel());

      return const AsyncLoading();
    }

    // Refrescar datos (pull-to-refresh, F5)
    Future<void> refresh() async {
      state = const AsyncLoading();
      final items = await Repository().get<T>(query: query);
      state = AsyncData(items);
    }
  }

  /// Provider para un solo item (FormScaffold)
  @riverpod
  Future<T?> brickItem<T extends OfflineFirstWithSupabaseModel>(
    String id,
  ) async {
    return await Repository().get<T>(
      query: Query.where('id', id, limit1: true),
    ).then((list) => list.firstOrNull);
  }

  // USO EN CrudScaffold (cada modulo define su propio modelo T):
  CrudScaffold<MiModelo>(
    dataSource: ref.watch(brickListProvider<MiModelo>(
      query: Query.where('empresa_id', empresaId)
        ..orderBy('created_at', ascending: false),
    )),
    // ... columnas, filtros, acciones
  )

  // El CrudScaffold internamente:
  // - Muestra shimmer/skeleton mientras AsyncLoading
  // - Muestra la lista cuando AsyncData
  // - Muestra error cuando AsyncError
  // - Se REBUILD automaticamente cuando la lista cambia
  //   (por sync, realtime, o escritura local)

═══════════════════════════════════════════════════════════════════════════
REACTIVIDAD: Cuando un Dato Cambia, TODO se Actualiza
═══════════════════════════════════════════════════════════════════════════

  Escenario: Usuario A edita la factura #123 en la app web.
             Usuario B tiene la misma factura abierta en tablet.

  1. Usuario A guarda → Repository.upsert<Factura>(factura123)
  2. Brick guarda en SQLite local de A → subscribe() emite → UI de A se actualiza
  3. Brick envia POST a Supabase (o encola si offline)
  4. Supabase actualiza PostgreSQL
  5. Supabase Realtime notifica a TODOS los suscriptores de esa tabla/empresa
  6. Brick de Usuario B recibe el evento Realtime
  7. Brick descarga la factura actualizada y la guarda en SQLite local de B
  8. subscribe() emite nueva lista → UI de B se actualiza automaticamente

  Widgets que se actualizan automaticamente:
    ✓ Fila del registro en el CrudScaffold (listado)
    ✓ FormScaffold del registro si esta abierto en otro tab
    ✓ Dashboard KPIs que dependen del registro
    ✓ Badges de estado en el sidebar

  TODO esto pasa automaticamente porque TODOS leen del mismo Stream<List<T>>
  que Brick emite desde SQLite local.

  Esto aplica para CUALQUIER tabla/modelo registrado en Brick.

═══════════════════════════════════════════════════════════════════════════
POLITICAS DE RESOLUCION DE CONFLICTOS
═══════════════════════════════════════════════════════════════════════════

  Brick usa "Last Write Wins" (LWW) por defecto: la ultima escritura que
  llega a Supabase gana. Esto es adecuado para la mayoria de escenarios ERP
  pero necesita politicas adicionales para documentos criticos.

  ESTRATEGIA POR TIPO DE DATO:

  ┌─────────────────────┬─────────────────────────────────────────────────┐
  │ Tipo de Dato         │ Politica de Conflicto                          │
  ├─────────────────────┼─────────────────────────────────────────────────┤
  │ Documentos criticos  │ BLOQUEO OPTIMISTA: campo `version` (integer).  │
  │ (facturas, pedidos,   │ Al guardar, se envia version actual. Si otro   │
  │  y similares)         │ usuario ya incremento la version, Supabase     │
  │                       │ rechaza con error → UI muestra "Documento      │
  │                       │ modificado por otro usuario, recargar?"        │
  │                       │ Implementacion: trigger PostgreSQL que valida  │
  │                       │ WHERE version = expected_version               │
  ├─────────────────────┼─────────────────────────────────────────────────┤
  │ Datos maestros       │ LAST WRITE WINS con merge parcial.             │
  │ (entidades, maestros  │ Campos independientes se fusionan:             │
  │  de catalogo)         │ si A cambia telefono y B cambia email,        │
  │                       │ ambos cambios se mantienen.                    │
  │                       │ Si ambos cambian el MISMO campo: LWW          │
  │                       │ (campo updated_at decide quien gano).         │
  ├─────────────────────┼─────────────────────────────────────────────────┤
  │ Transacciones        │ APPEND-ONLY: registros transaccionales son    │
  │                       │ INMUTABLES una vez                             │
  │                       │ confirmados. No se editan, se anulan y crean  │
  │                       │ nuevos. No hay conflicto posible.              │
  ├─────────────────────┼─────────────────────────────────────────────────┤
  │ Secuenciales de      │ PRE-ASIGNACION: secuenciales offline se       │
  │ documentos           │ pre-asignan por bloque (ej: 100 numeros).     │
  │                       │ No hay conflicto porque cada dispositivo       │
  │                       │ tiene su rango exclusivo.                      │
  ├─────────────────────┼─────────────────────────────────────────────────┤
  │ Stock/Inventario     │ SUMA DELTA: no se sobreescribe el stock total.│
  │                       │ Se registran MOVIMIENTOS (delta +/-).          │
  │                       │ El stock total se calcula como SUM(deltas).   │
  │                       │ Dos movimientos concurrentes no conflictan.    │
  ├─────────────────────┼─────────────────────────────────────────────────┤
  │ Sesiones exclusivas   │ BLOQUEO PESIMISTA: solo 1 usuario por sesion. │
  │ (ej: sesiones de caja)│ La sesion se "lockea" al abrir y se libera    │
  │                       │ al cerrar/pausar. PostgreSQL advisory lock.    │
  ├─────────────────────┼─────────────────────────────────────────────────┤
  │ Chat mensajes        │ APPEND-ONLY: mensajes solo se crean, no se    │
  │                       │ editan. Ordenados por timestamp.               │
  └─────────────────────┴─────────────────────────────────────────────────┘

  IMPLEMENTACION DEL BLOQUEO OPTIMISTA (version field):

  -- Trigger PostgreSQL para documentos criticos (bloqueo optimista)
  CREATE OR REPLACE FUNCTION check_version_conflict()
  RETURNS TRIGGER AS $$
  BEGIN
    IF OLD.version != NEW.version - 1 THEN
      RAISE EXCEPTION 'CONFLICT: documento modificado por otro usuario (version % != %)',
        OLD.version, NEW.version - 1;
    END IF;
    RETURN NEW;
  END;
  $$ LANGUAGE plpgsql;

  -- Cada modulo aplica el trigger a sus propias tablas con documentos criticos:
  CREATE TRIGGER tr_<tabla>_version
    BEFORE UPDATE ON <tabla>
    FOR EACH ROW EXECUTE FUNCTION check_version_conflict();

  -- En Flutter: al guardar, incrementar version
  documento.version += 1;
  try {
    await Repository().upsert<MiModelo>(documento);
  } on PostgrestException catch (e) {
    if (e.message.contains('CONFLICT')) {
      // Mostrar dialogo: "Modificado por otro usuario"
      // Opcion 1: Recargar (pierde mis cambios)
      // Opcion 2: Forzar guardar (sobreescribe)
    }
  }

═══════════════════════════════════════════════════════════════════════════
COLA OFFLINE Y REINTENTOS
═══════════════════════════════════════════════════════════════════════════

  Brick maneja la cola automaticamente:

  ESCRITURA OFFLINE:
    1. Usuario crea factura sin internet
    2. Brick guarda en SQLite local INMEDIATAMENTE (UI responde al instante)
    3. Brick encola el POST a Supabase en la offline queue (SQLite)
    4. UI muestra badge "1 operacion pendiente" en el sidebar
    5. Cuando vuelve internet, Brick reintenta automaticamente
    6. Si exito: marca como sincronizado
    7. Si error (ej: conflicto de version): marca como error
       → UI muestra en Log de Sincronizacion con boton "Reintentar" / "Resolver"

  PRIORIDAD DE COLA (configurable por modulo):
    1. Documentos criticos de negocio (mayor impacto si se pierden)
    2. Transacciones financieras (afectan saldos)
    3. Registros contables (afectan libros)
    4. Datos maestros (entidades, catalogos)
    5. Configuracion y preferencias (baja prioridad)

  EXCLUSIONES DE LA COLA (no se encolan offline):
    - /auth/v1 (autenticacion requiere internet)
    - /storage/v1 (archivos requieren internet)
    - /functions/v1 (Edge Functions requieren internet)
    - Estas se manejan con mensajes "Requiere conexion a internet"

═══════════════════════════════════════════════════════════════════════════
TABLA RESUMEN: QUE LEE DE DONDE
═══════════════════════════════════════════════════════════════════════════

  ┌────────────────────────┬──────────────────────────────────────────────┐
  │ Componente UI           │ Fuente de Datos                             │
  ├────────────────────────┼──────────────────────────────────────────────┤
  │ CrudScaffold (grids)    │ BrickList<T>.stream (SQLite local, reactivo)│
  │ FormScaffold (forms)    │ brickItem<T>(id) (SQLite local)            │
  │ Dashboard KPIs          │ BrickList<T>.stream con agregaciones        │
  │ Badges en sidebar       │ BrickList<T>.stream con count()            │
  │ Autocompletados         │ Repository.get<T>(query) (SQLite local)    │
  │ Reportes PDF/Excel      │ Repository.get<T>(query) (SQLite local)    │
  │ Chat                    │ subscribeToRealtime (Realtime directo)      │
  │ Pantallas de alta freq. │ subscribe() (local, sin Realtime por perf) │
  │ Doc. Electronicos       │ Edge Function (requiere internet)           │
  └────────────────────────┴──────────────────────────────────────────────┘

  REGLA DE ORO:
    ✓ Widgets leen de SQLite local (via Brick subscribe/subscribeToRealtime)
    ✓ Widgets escriben a SQLite local (via Brick upsert/delete)
    ✓ Brick sincroniza con Supabase en background
    ✓ Supabase Realtime notifica cambios remotos → Brick actualiza local → widgets se rebuildan
    ✗ Widgets NUNCA llaman a Supabase directamente
    ✗ Widgets NUNCA hacen HTTP a PostgREST
    ✗ Widgets NUNCA manejan la cola offline (Brick lo hace)
```

#### Interfaz Base CRUD (Plantilla para Todas las Pantallas de Listado)

```
Todas las pantallas de listado de datos de cualquier modulo
heredan de un widget base CrudScaffold<T> que estandariza la experiencia de usuario:

╔════════════════════════════════════════════════════════════════════════════╗
║  HEADER BAR (AppBar fijo)                                                 ║
║  ┌─────────┬──────────────────────────────┬──────────────────────────────┐ ║
║  │ ☰ Logo  │  Empresa: Comercial XYZ ▼    │  🔔  🌙/☀  👤 Juan Pérez ▼│ ║
║  │ PILAR   │  Sucursal: Matriz            │  ● Online   Preferencias    │ ║
║  └─────────┴──────────────────────────────┴──────────────────────────────┘ ║
╠════════════════════════════════════════════════════════════════════════════╣
║ SIDEBAR ║  AREA DE CONTENIDO (con sistema de tabs)                        ║
║ (nav)   ║  ┌──────────────────────────────────────────────────────────┐   ║
║         ║  │ [Tab Listado x] [Tab Registro #1 x] [Tab Nuevo + x]     │   ║
║ 📊 Dash ║  ├──────────────────────────────────────────────────────────┤   ║
║ M.A.    ║  │                                                          │   ║
║ M.B.    ║  │  CONTENIDO DEL TAB ACTIVO                                │   ║
║ M.C.    ║  │  (listado CRUD o formulario de edicion/creacion)         │   ║
║ M.D.    ║  │                                                          │   ║
║ M.E.    ║  └──────────────────────────────────────────────────────────┘   ║
║ M.F.    ║                                                                 ║
║ ...      ║                                                                 ║
╚════════════════════════════════════════════════════════════════════════════╝

ESTRUCTURA DEL TAB DE LISTADO (CrudScaffold):
┌──────────────────────────────────────────────────────────────────────┐
│  BARRA DE ACCIONES                                                    │
│  ┌────────────────────────┐  ┌─────┐ ┌─────────────┐ ┌────┐ ┌────┐ │
│  │ 🔍 Buscar...           │  │ ⚙ ▼ │ │ + Nuevo      │ │🗑️ │ │ ⋮  │ │
│  └────────────────────────┘  │Filtros│ └─────────────┘ │Del │ │Mas │ │
│                               └─────┘                   └────┘ └────┘ │
│                                                                        │
│  FILTROS EXPANDIDOS (cuando se activan, especificos por modelo):       │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ │
│  │ Fecha desde  │ │ Fecha hasta  │ │ Estado ▼     │ │ Vendedor ▼   │ │
│  └──────────────┘ └──────────────┘ └──────────────┘ └──────────────┘ │
│  ┌──────────────┐ ┌───────────────────────────────┐                   │
│  │ Sucursal ▼   │ │ [Aplicar] [Limpiar filtros]   │                   │
│  └──────────────┘ └───────────────────────────────┘                   │
│                                                                        │
│  REJILLA DE DATOS (SfDataGrid en desktop, ListView de cards en mobile) │
│  ┌────┬──────────┬──────────────┬────────────┬──────────┬───────────┐ │
│  │ ☐  │ Numero ▲ │ Cliente      │ Fecha      │ Total    │ Estado    │ │
│  ├────┼──────────┼──────────────┼────────────┼──────────┼───────────┤ │
│  │ ☐  │ REC-001  │ Empresa A    │ 15/02/2026 │ $1,250.00│ ● Activo │ │
│  │ ☐  │ REC-002  │ Empresa B    │ 15/02/2026 │ $  850.00│ ● Cerrado│ │
│  │ ☐  │ REC-003  │ Empresa C    │ 14/02/2026 │ $2,100.00│ ● Pendien│ │
│  └────┴──────────┴──────────────┴────────────┴──────────┴───────────┘ │
│                                                                        │
│  BARRA INFERIOR                                                        │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │ 3 seleccionados │ Mostrando 1-25 de 347 │ ◀ 1 2 3 ... 14 ▶    │  │
│  │                  │ [📄 PDF] [📊 Excel]   │ Filas por pagina: 25▼│  │
│  └──────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────┘

INTERACCIONES:
  - Click en fila → abre formulario de vista/edicion en un NUEVO TAB
  - Click en "+" Nuevo → abre formulario vacio de creacion en un NUEVO TAB
  - Seleccionar filas (checkbox) → habilita acciones masivas (borrar, exportar, enviar)
  - Doble click en fila → abre formulario en modo edicion
  - Columnas ordenables (click en header)
  - Columnas redimensionables y reordenables (drag & drop en header)
  - Filtro rapido: campo de busqueda global filtra en todas las columnas visibles
  - Filtros avanzados: especificos por modelo, se abren/cierran con boton
  - Exportar: PDF (syncfusion_flutter_pdf), Excel (syncfusion_flutter_xlsio)
  - Paginacion server-side (Supabase range queries)
  - Filas por pagina configurable: 10, 25, 50, 100

PERMISOS EN BOTONES:
  - Boton "Nuevo" visible solo si usuario tiene permiso <modulo>.<recurso>.crear
  - Boton "Borrar" visible solo si tiene <modulo>.<recurso>.eliminar
  - Columnas sensibles ocultas si no tiene <modulo>.<recurso>.ver_costos (ej: costo unitario)
  - Acciones masivas condicionadas a permisos individuales
```

#### Sistema de Tabs para Navegacion de Documentos

```
El area de contenido usa un sistema de tabs dinamico que permite al usuario
tener abiertos multiples documentos simultaneamente (similar a navegador web):

IMPLEMENTACION:
  - TabController dinamico (cantidad variable de tabs)
  - Cada tab tiene: titulo, icono, boton cerrar (x), indicador de cambios sin guardar
  - Al cerrar tab con cambios sin guardar: dialogo de confirmacion
  - Persistencia de tabs abiertos entre sesiones (shared_preferences)
  - Limite configurable de tabs maximos (default: 15)

WIDGET: WorkspaceTabs (core/widgets/workspace_tabs.dart)

  ┌─────────────────────────────────────────────────────────────────────┐
  │ [📋 Listado   x] [📝 Registro #1  ●x] [➕ Nuevo Registro x] [+]  │
  ├─────────────────────────────────────────────────────────────────────┤
  │                                                                      │
  │   Contenido del tab seleccionado                                     │
  │   (CrudScaffold para listados, FormScaffold para formularios)        │
  │                                                                      │
  └─────────────────────────────────────────────────────────────────────┘

  ● = indicador de cambios sin guardar (dot rojo junto al x)
  [+] = boton para abrir tab de listado de cualquier modulo (atajos rapidos)

TIPOS DE TAB:
  1. ListTab: contiene un CrudScaffold (listado con filtros, grid, paginacion)
  2. FormTab: contiene un FormScaffold (formulario de creacion/edicion)
  3. ReportTab: contiene un reporte/grafico generado
  4. DashboardTab: tab especial para el dashboard (no se puede cerrar)

NAVEGACION EN MOBILE (COMPACT):
  - Sin sistema de tabs (pantalla completa por vista)
  - Boton "atras" para regresar al listado
  - Stack de navegacion con go_router
  - Formularios se abren como pantalla completa (push)

KEYBOARD SHORTCUTS (desktop/web):
  - Ctrl+T: nuevo tab (listado del modulo actual)
  - Ctrl+W: cerrar tab actual
  - Ctrl+Tab / Ctrl+Shift+Tab: navegar entre tabs
  - Ctrl+N: nuevo registro en el modulo actual
  - Ctrl+S: guardar formulario actual
  - Ctrl+F: enfocar campo de busqueda
  - F5: refrescar datos del listado
```

#### App Shell: Header, Sidebar y Layout Principal

> **NOTA:** Este widget `AppShell` con sidebar ha sido **reemplazado** por `PilarShell` (ver seccion 6.8).
> PILAR usa navegacion Odoo-style con App Launcher + ModuleMenuBar, SIN sidebar fijo.
> Las referencias a sidebar en esta seccion se mantienen solo como referencia historica.

```
WIDGET: AppShell (core/widgets/app_shell.dart)

Es el widget raiz de la aplicacion autenticada. Contiene:
  1. Header Bar (fijo arriba)
  2. Sidebar (izquierda, colapsable)
  3. Area de contenido (WorkspaceTabs)
  4. Chat FAB (floating action button, esquina inferior derecha)

═══════════════════════════════════════════════════════════════════
HEADER BAR DETALLE:
═══════════════════════════════════════════════════════════════════

┌────────────────────────────────────────────────────────────────────────┐
│ ☰ │ PILAR │ Comercial XYZ S.A. ▼ │ Sucursal Matriz │   │🔔│🌙│👤 ▼│
│   │  ERP  │ (selector empresa)     │ (info)          │   │3 │  │Juan│
└────────────────────────────────────────────────────────────────────────┘

Componentes del header (izquierda a derecha):
  ☰  Boton hamburger: toggle sidebar (colapsado/expandido/oculto)
  PILAR ERP: logo + nombre de la app (click → dashboard)
  Selector empresa: dropdown con las empresas del usuario
    - Muestra nombre + RUC de la empresa activa
    - Al cambiar empresa: recarga datos, actualiza JWT claims
    - Solo muestra empresas donde el usuario tiene rol activo
  Info sucursal: nombre del establecimiento actual
  Indicador de conexion:
    ● Verde = ONLINE (sincronizado)
    ● Amarillo = SIN_SYNC (online pero con pendientes)
    ● Rojo = OFFLINE (sin internet)
    ● Azul pulsante = SINCRONIZANDO
  🔔 Notificaciones: badge con conteo, click abre panel lateral
  🌙/☀ Toggle modo oscuro/claro (persistido localmente)
  👤 Avatar + nombre usuario: click abre menu desplegable:
    - Mi perfil
    - Preferencias
    - Cambiar empresa
    - Cerrar sesion

═══════════════════════════════════════════════════════════════════
SIDEBAR DETALLE:
═══════════════════════════════════════════════════════════════════

ESTADOS DEL SIDEBAR (segun breakpoint y toggle manual):
  EXPANDIDO: icono + texto + badge (> 840px default, o toggle manual)
  COLAPSADO: solo icono + tooltip (600-840px default, o toggle manual)
  OCULTO: hamburger para mostrar como drawer (< 600px)

┌──────────────────────┐
│ SIDEBAR EXPANDIDO     │
│                       │
│ 🔍 Buscar modulo...  │  ← Filtro rapido de menu
│                       │
│ 📊 Dashboard          │
│ ─────────────────     │
│ 📦 Modulo A        ▼ │  ← Expande sub-items
│    Seccion 1          │
│    Seccion 2          │
│    Seccion 3          │
│ 📋 Modulo B        ▼ │
│    Seccion 1          │
│    Seccion 2          │
│ 💰 Modulo C        ▼ │
│ 🏦 Modulo D        ▼ │
│ ... (modulos activos  │
│     segun empresa)    │
│ ─────────────────     │
│ ⚙️ Administracion  ▼ │
│ ─────────────────     │
│ 📋 Sync Log (3)  🔴  │  ← Badge con pendientes
│ ❓ Ayuda              │
└──────────────────────┘

GENERACION DINAMICA:
  - Los items del sidebar se generan desde tabla modulos_empresa
  - Solo aparecen modulos habilitados para la empresa actual
  - Sub-items filtrados por permisos del usuario actual
  - Orden configurable por empresa (tabla modulos_empresa.orden)
  - Badge de notificaciones por modulo (ej: items pendientes de accion)
  - Animacion de expansion/colapso con AnimatedContainer
  - Estado de expansion persistido localmente (shared_preferences)
```

#### Pantalla de Perfil y Preferencias de Usuario

```
UBICACION: features/settings/screens/

═══════════════════════════════════════════════════════════════════
PERFIL DE USUARIO (profile_screen.dart)
═══════════════════════════════════════════════════════════════════

┌──────────────────────────────────────────────────────────────┐
│  MI PERFIL                                                    │
│                                                               │
│  ┌───────┐                                                    │
│  │ 👤    │  Juan Carlos Perez                                │
│  │ Avatar│  juan.perez@empresa.com                           │
│  └───────┘  Rol: Administrador (Comercial XYZ)               │
│             Ultimo acceso: 15/02/2026 10:30                   │
│                                                               │
│  Datos Personales                                             │
│  ┌────────────────────┐ ┌────────────────────┐               │
│  │ Nombre: Juan Carlos│ │ Apellido: Perez    │               │
│  └────────────────────┘ └────────────────────┘               │
│  ┌────────────────────┐ ┌────────────────────┐               │
│  │ Email: juan@...    │ │ Telefono: 09...    │               │
│  └────────────────────┘ └────────────────────┘               │
│                                                               │
│  Seguridad                                                    │
│  [Cambiar contraseña]  [Configurar 2FA]                      │
│                                                               │
│  Empresas Vinculadas                                          │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ Comercial XYZ S.A.    │ Administrador  │ ● Activa       │ │
│  │ Distribuidora ABC     │ Contador       │   Cambiar →    │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                               │
│  [Guardar cambios]                                            │
└──────────────────────────────────────────────────────────────┘

═══════════════════════════════════════════════════════════════════
PREFERENCIAS DE APARIENCIA (preferences_screen.dart)
═══════════════════════════════════════════════════════════════════

┌──────────────────────────────────────────────────────────────┐
│  PREFERENCIAS                                                 │
│                                                               │
│  Tema                                                         │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐                     │
│  │ ☀ Claro  │ │ 🌙 Oscuro│ │ 💻 Auto  │  (sigue al SO)    │
│  └──────────┘ └──────────┘ └──────────┘                     │
│                                                               │
│  Esquema de Colores (flex_color_scheme)                        │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │ Esquemas recomendados:                                    │ │
│  │ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ │ │
│  │ │██████│ │██████│ │██████│ │██████│ │██████│ │██████│ │ │
│  │ │Blue  │ │Indigo│ │Green │ │Money │ │Whale │ │Espres│ │ │
│  │ │ M3   │ │ M3   │ │ M3   │ │      │ │      │ │  so  │ │ │
│  │ └──────┘ └──────┘ └──────┘ └──────┘ └──────┘ └──────┘ │ │
│  │ [Ver todos (66 esquemas)] [🎨 Color personalizado]      │ │
│  └──────────────────────────────────────────────────────────┘ │
│  Estrategia de tonos (flex_seed_scheme):                       │
│  [Material ▼] (Material, Soft, Vivid, Alto contraste)         │
│  Preview: [████ primary ████ secondary ████ tertiary ████]    │
│                                                               │
│  Tipografia                                                    │
│  Tamano de fuente base:  [ ◀ 14px ▶ ]  (rango: 12-18px)     │
│  Fuente:  [Roboto ▼]  (Roboto, Inter, Noto Sans, monospace)  │
│  Preview: "Texto de ejemplo con la fuente seleccionada"       │
│                                                               │
│  Espaciado                                                     │
│  Densidad visual:  [Compacta ▼]  (Compacta, Normal, Comoda)  │
│    - Compacta: padding reducido (4-8px), ideal para desktop   │
│    - Normal: padding estandar (8-12px), balance general       │
│    - Comoda: padding amplio (12-16px), ideal para touch       │
│  Se aplica via VisualDensity de MaterialApp                    │
│                                                               │
│  Tabla de Datos                                                │
│  Filas por pagina:  [25 ▼]  (10, 25, 50, 100)               │
│  Altura de fila:    [Normal ▼]  (Compacta 36px, Normal 48px, │
│                                   Grande 56px)                │
│  Mostrar lineas de grid:  [☑]                                 │
│  Columnas fijas a la izquierda: [1 ▼] (0, 1, 2)             │
│                                                               │
│  Sidebar                                                       │
│  Estado inicial:  [Expandido ▼]  (Expandido, Colapsado)      │
│  Ancho expandido: [ ◀ 260px ▶ ]  (200-320px)                │
│                                                               │
│  Notificaciones                                                │
│  ☑ Sonido al recibir notificaciones                           │
│  ☑ Notificaciones push (web/mobile)                           │
│  ☑ Notificar errores de sincronizacion                        │
│  ☐ Modo silencioso (solo badge, sin sonido/push)              │
│                                                               │
│  [Aplicar]  [Restaurar defaults]                              │
└──────────────────────────────────────────────────────────────┘

PERSISTENCIA LOCAL:
  - Package: shared_preferences (web, mobile, desktop)
  - Clave prefijo: "pilar_prefs_"
  - Almacena: tema, flex_scheme (o custom_seed_color), font_size, font_family,
    visual_density, flex_tones, rows_per_page, row_height, show_grid_lines,
    frozen_columns, sidebar_state, sidebar_width, sound_enabled, push_enabled
    # NOTA: sidebar_state y sidebar_width ya no aplican con PilarShell (ver seccion 6.8)
  - Se carga al inicio de la app (antes de MaterialApp)
  - Provider: preferencesProvider (Riverpod StateNotifier)

PROVIDER DE TEMA (core/providers/theme_provider.dart):
  Usa flex_color_scheme + flex_seed_scheme para temas Material 3 avanzados.

  final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeState>((ref) {
    return ThemeNotifier(ref.read(preferencesProvider));
  });

  ThemeState contiene:
    - ThemeMode (light/dark/system)
    - FlexScheme? scheme           # Esquema predefinido (66 opciones) o null=custom
    - Color? customSeedColor       # Solo si scheme es null (color picker custom)
    - FlexTones tones              # Estrategia de tonos (material, vivid, soft, etc.)
    - double baseFontSize
    - String fontFamily
    - VisualDensity density
    - int rowsPerPage
    - double rowHeight
    - bool showGridLines
    - int frozenColumns
    - SidebarConfig sidebarConfig  # NOTA: ya no aplica con PilarShell (ver seccion 6.8)

  Se aplica en PilarApp (MaterialApp):
    MaterialApp(
      // flex_color_scheme genera ThemeData completo y consistente
      theme: FlexThemeData.light(
        scheme: state.scheme ?? FlexScheme.blueM3,
        // Si custom seed color:
        colors: state.customSeedColor != null
          ? FlexSchemeColor.from(primary: state.customSeedColor!)
          : null,
        useMaterial3: true,
        fontFamily: state.fontFamily,
        textTheme: _buildScaledTextTheme(state.baseFontSize),
        visualDensity: state.density,
        // flex_seed_scheme: estrategia de tonos
        tones: state.tones.tones(Brightness.light),
        subThemesData: const FlexSubThemesData(
          interactionEffects: true,
          blendOnLevel: 10,
          blendOnColors: true,
          defaultRadius: 12.0,    // Border radius global
          inputDecoratorRadius: 8.0,
        ),
      ),
      darkTheme: FlexThemeData.dark(
        scheme: state.scheme ?? FlexScheme.blueM3,
        colors: state.customSeedColor != null
          ? FlexSchemeColor.from(primary: state.customSeedColor!)
          : null,
        useMaterial3: true,
        fontFamily: state.fontFamily,
        textTheme: _buildScaledTextTheme(state.baseFontSize),
        visualDensity: state.density,
        tones: state.tones.tones(Brightness.dark),
        subThemesData: const FlexSubThemesData(
          interactionEffects: true,
          blendOnLevel: 20,
          blendOnColors: true,
          defaultRadius: 12.0,
          inputDecoratorRadius: 8.0,
        ),
      ),
      themeMode: state.themeMode,
    )

VENTAJAS DE flex_color_scheme sobre ColorScheme.fromSeed:
  ✓ 66 esquemas predefinidos (FlexScheme enum) - profesionales y bien balanceados
  ✓ Sub-temas automaticos para TODOS los widgets Material (botones, inputs, chips, etc.)
  ✓ Control de chroma/saturacion via flex_seed_scheme (FlexTones)
  ✓ Estrategias de tonos: material, soft, vivid, highContrast, candyPop, ultraContrast
  ✓ Blending de colores en superficies (profundidad visual sin esfuerzo)
  ✓ Border radius global configurable (un solo valor para todo)
  ✓ 100% compatible con Material 3 + Syncfusion + flutter_form_builder
  ✓ NO conflicta con ninguna dependencia (es un wrapper sobre ThemeData nativo)

ESQUEMAS PREDEFINIDOS RECOMENDADOS PARA ERP:
  - FlexScheme.blueM3        → Azul profesional (default)
  - FlexScheme.indigoM3      → Indigo corporativo
  - FlexScheme.greenM3       → Verde profesional
  - FlexScheme.dellGenoa     → Azul-verde ejecutivo
  - FlexScheme.money         → Verde financiero
  - FlexScheme.blueWhale     → Azul oscuro elegante
  - FlexScheme.espresso      → Marron calido
  - FlexScheme.flutterDash   → Azul Flutter (familiar)

  El usuario puede elegir cualquiera de los 66 o usar el color picker custom.

FLEX_TONES (flex_seed_scheme) - Estrategias de tonos:
  - FlexTones.material()     → Tono Material 3 estandar (default)
  - FlexTones.soft()         → Menos saturacion, mas suave
  - FlexTones.vivid()        → Mas saturacion, mas vibrante
  - FlexTones.highContrast() → Alto contraste (accesibilidad)
  - FlexTones.ultraContrast()→ Maximo contraste (vision reducida)
  - FlexTones.candyPop()     → Colores brillantes (informal)
  - FlexTones.jolly()        → Equilibrio vivido
```

#### Widget Base CrudScaffold - Especificacion Tecnica

```dart
/// Widget base para TODAS las pantallas de listado CRUD.
/// Cada pantalla solo define: columnas, filtros, y acciones especificas.
///
/// Ejemplo de uso:
/// CrudScaffold<MiModelo>(
///   title: 'Lista de registros',
///   columns: [...],
///   filters: [...],
///   dataSource: (params) => ref.read(miModeloProvider).getPage(params),
///   onRowTap: (item) => openTab(FormTab(item)),
///   onNew: () => openTab(FormTab.create<MiModelo>()),
///   canCreate: 'mi_modulo.recurso.crear',
///   canDelete: 'mi_modulo.recurso.eliminar',
///   exportConfig: ExportConfig(pdf: true, excel: true),
/// )
```

```
PARAMETROS DEL CrudScaffold<T>:

  Obligatorios:
    - title: String                   # Titulo de la pantalla
    - columns: List<CrudColumn<T>>    # Definicion de columnas
    - dataSource: Future<PageResult<T>> Function(PageParams)  # Fuente de datos paginada

  Opcionales - Filtros:
    - searchFields: List<String>      # Campos donde busca el search global
    - filters: List<CrudFilter>       # Filtros personalizados por modelo
    - defaultSort: SortConfig         # Ordenamiento por defecto

  Opcionales - Acciones:
    - onRowTap: void Function(T)      # Al hacer click en fila
    - onNew: VoidCallback             # Al presionar "+"
    - onDelete: Future<void> Function(List<T>)  # Borrado masivo
    - actions: List<CrudAction<T>>    # Acciones adicionales (enviar, aprobar, etc.)
    - canCreate: String?              # Permiso requerido para crear (null = sin boton)
    - canDelete: String?              # Permiso requerido para borrar

  Opcionales - Exportacion:
    - exportConfig: ExportConfig      # Habilita botones PDF/Excel
    - exportFileName: String          # Nombre del archivo generado

  Opcionales - Apariencia:
    - emptyWidget: Widget             # Widget cuando no hay datos
    - rowColor: Color? Function(T)    # Color condicional de fila
    - selectable: bool                # Habilitar checkboxes (default: true)

CrudColumn<T>:
  - field: String                     # Nombre del campo
  - label: String                     # Titulo de la columna
  - width: double?                    # Ancho (null = auto)
  - sortable: bool                    # Permite ordenar (default: true)
  - formatter: String Function(T)?    # Formato custom (ej: moneda, fecha)
  - cellBuilder: Widget Function(T)?  # Widget custom para la celda
  - visible: bool                     # Visible en grid (default: true)
  - exportable: bool                  # Incluir en export (default: true)
  - permission: String?               # Permiso para ver esta columna

CrudFilter:
  - field: String                     # Campo a filtrar
  - label: String                     # Label del filtro
  - type: FilterType                  # TEXT, DATE_RANGE, SELECT, MULTI_SELECT, NUMBER_RANGE, BOOL
  - options: List<FilterOption>?      # Para SELECT/MULTI_SELECT
  - defaultValue: dynamic?            # Valor por defecto

PageParams:
  - page: int
  - pageSize: int
  - search: String?
  - sortField: String?
  - sortAsc: bool
  - filters: Map<String, dynamic>

PageResult<T>:
  - items: List<T>
  - totalCount: int
  - page: int
  - pageSize: int
```

#### Widget Base FormScaffold - Especificacion Tecnica

```
FormScaffold<T> es el widget base para formularios de creacion y edicion.
Cada formulario define los campos especificos, FormScaffold se encarga del resto.

┌──────────────────────────────────────────────────────────────┐
│  FORMULARIO: Registro #DOC-001                                │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ [💾 Guardar] [🖨 Imprimir] [📧 Enviar] [⋮ Mas]       │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                               │
│  Estado: ● Activo     Creado: 15/02/2026 10:30               │
│          por: Juan Perez                                      │
│                                                               │
│  ┌──────────────────────────────────────────────────────────┐│
│  │ [Datos Generales] [Detalles] [Pagos] [Adjuntos] [Log]  ││
│  ├──────────────────────────────────────────────────────────┤│
│  │                                                           ││
│  │  Seccion del sub-tab seleccionado                        ││
│  │  (flutter_form_builder con validacion)                   ││
│  │                                                           ││
│  └──────────────────────────────────────────────────────────┘│
└──────────────────────────────────────────────────────────────┘

PARAMETROS:
  - title: String                           # Titulo del formulario
  - record: T?                              # null = creacion, valor = edicion
  - sections: List<FormSection>             # Secciones (sub-tabs)
  - onSave: Future<T> Function(Map<String, dynamic>)  # Guardar
  - onDelete: Future<void> Function(T)?     # Borrar (opcional)
  - actions: List<FormAction>               # Acciones extras (imprimir, enviar, etc.)
  - readOnly: bool                          # Modo solo lectura
  - canEdit: String?                        # Permiso para editar
  - canDelete: String?                      # Permiso para borrar

FormSection:
  - label: String                           # Tab label
  - icon: IconData                          # Tab icon
  - builder: Widget Function(FormGroup)     # Contenido del tab
  - visible: bool Function(T?)?            # Condicion de visibilidad

VALIDACION:
  - Usa flutter_form_builder con FormBuilderValidators
  - Validacion en tiempo real (onChanged)
  - Validacion completa al intentar guardar
  - Mensajes de error inline bajo cada campo
  - Scroll automatico al primer campo con error
  - Indicador visual de campos requeridos (asterisco rojo)

DETECCION DE CAMBIOS:
  - Compara estado inicial vs actual (DeepCollectionEquality)
  - ● Dot rojo en tab del WorkspaceTabs si hay cambios sin guardar
  - Confirmacion al cerrar tab con cambios pendientes
  - Ctrl+S para guardar rapido (desktop)

ESTADOS DEL FORMULARIO:
  - CARGANDO: Skeleton/shimmer mientras obtiene datos
  - EDICION: Campos editables, botones activos
  - GUARDANDO: Campos deshabilitados, indicador de progreso
  - ERROR: Resalta campos con error, mensaje en SnackBar
  - SOLO_LECTURA: Campos deshabilitados, sin botones de edicion
```

```
ESTRUCTURA DE ARCHIVOS PARA UI BASE:

lib/core/
  ├── widgets/
  │   ├── app_shell.dart              # REEMPLAZADO por pilar_shell.dart (ver seccion 6.8)
  │   ├── app_scaffold.dart           # REEMPLAZADO por pilar_shell.dart (ver seccion 6.8)
  │   ├── workspace_tabs.dart         # Sistema de tabs dinamico
  │   ├── crud_scaffold.dart          # Widget base para listados CRUD
  │   ├── form_scaffold.dart          # Widget base para formularios
  │   ├── data_grid.dart              # Wrapper SfDataGrid (existente, se mejora)
  │   ├── search_bar.dart             # Barra de busqueda global
  │   ├── filter_panel.dart           # Panel de filtros expandible
  │   ├── export_button.dart          # Botones PDF/Excel
  │   ├── pagination_bar.dart         # Barra de paginacion
  │   ├── status_badge.dart           # Badge de estado (colores)
  │   ├── connection_indicator.dart   # Indicador de conexion
  │   ├── empresa_selector.dart       # Dropdown selector de empresa
  │   ├── notification_bell.dart      # Campana de notificaciones
  │   ├── theme_toggle.dart           # Boton dark/light mode
  │   ├── app_launcher_grid.dart      # Grid de modulos estilo Odoo (overlay)
  │   ├── module_menu_bar.dart        # MenuBar del modulo activo (dropdowns)
  │   ├── form_fields.dart            # Campos personalizados (existente)
  │   ├── chat_widget.dart            # Widget chat IA (existente)
  │   └── pdf_viewer.dart             # Visualizador RIDE (existente)
  ├── providers/
  │   ├── auth_provider.dart          # Autenticacion (existente)
  │   ├── empresa_provider.dart       # Empresa activa (existente)
  │   ├── repository_provider.dart    # Brick Repository (existente)
  │   ├── theme_provider.dart         # Tema y preferencias visuales
  │   ├── preferences_provider.dart   # Persistencia local de preferencias
  │   ├── connection_provider.dart    # Monitor estado de conexion
  │   ├── tabs_provider.dart          # Estado de tabs abiertos
  │   ├── permissions_provider.dart   # Permisos del usuario actual
  │   ├── active_module_provider.dart  # Modulo activo y su MenuBar
  │   └── app_launcher_provider.dart  # Estado del App Launcher (abierto/cerrado)
  ├── services/
  │   ├── pdf_service.dart            # Generacion de PDFs
  │   ├── print_service.dart          # Impresion nativa
  │   ├── export_service.dart         # Exportacion PDF/Excel de grids
  │   └── notification_service.dart   # Push notifications
  └── theme/
      ├── app_theme.dart              # ThemeData builder (light + dark)
      ├── color_schemes.dart          # Paletas de colores predefinidas
      ├── typography.dart             # Estilos de texto configurables
      └── spacing.dart                # Constantes de spacing por densidad
```

---


---


### Stack Principal

| Capa | Tecnologia | Version | Justificacion |
|------|-----------|---------|---------------|
| **Frontend** | Flutter | 3.x (stable) | Un codebase → 6 plataformas nativas |
| **Lenguaje Frontend** | Dart | 3.x | Type-safe, compilacion nativa, null-safety |
| **UI Components** | Material 3 + Syncfusion | Latest | Widgets empresariales profesionales |
| **Estado** | Riverpod | 2.x | Reactivo, inyeccion dependencias, testing facil |
| **Tablas** | syncfusion_flutter_datagrid | Latest | Sort, filter, group, export, paginacion |
| **Formularios** | flutter_form_builder | Latest | Validacion, campos custom |
| **Navegacion** | go_router | Latest | Deep linking, rutas anidadas |
| **Backend/DB** | Supabase | Latest | PostgreSQL managed + Auth + Storage + Realtime + pgvector |
| **Offline-First** | brick_offline_first_with_supabase | 2.1.0 | SQLite local + sync automatico + Realtime |
| **PDF** | syncfusion_flutter_pdf + printing | Latest | Generacion RIDE y reportes |
| **HTTP** | dio | Latest | Interceptors, retry, logging |
| **Firma XML (server)** | Libreria de firma XAdES | Latest | Edge Function de firma — módulo de localización |
| **XML (server)** | fast-xml-parser + xmlbuilder2 | Latest | Generacion/parseo XML en Edge Functions — módulo de localización |
| **Pagos** | Adaptador de pasarelas | Latest | Pasarelas de pago — módulo de pagos |
| **Email** | Resend | Latest | Envio transaccional de comprobantes |
| **IA/Embeddings** | pgvector (Supabase) | Latest | Busqueda semantica, chat IA, agentes |
| **Deploy Frontend** | Cloudflare Pages (web, gratis) + Stores | Latest | CDN global para Flutter Web |
| **Deploy Backend** | Supabase Cloud | Latest | Managed PostgreSQL + Edge Functions |
| **Monitoreo** | Sentry (sentry_flutter) | Latest | Error tracking, performance |
| **Testing** | flutter_test + integration_test | Latest | Unit + Widget + Integration tests |

### Arquitectura Cliente-Servidor

```
┌─────────────────────────────────┐
│   FLUTTER APP (Dart)            │
│   ├── UI (Material 3 + Syncf.) │
│   ├── Estado (Riverpod)        │
│   ├── Offline (Brick+SQLite)   │
│   ├── Pagos (flutter_kushki)   │
│   └── supabase_flutter SDK     │
└───────────┬─────────────────────┘
            │ HTTPS (REST + Realtime)
            ▼
┌─────────────────────────────────┐
│   SUPABASE                      │
│   ├── Auth (JWT + RLS)         │
│   ├── PostgreSQL + pgvector    │
│   ├── Storage (XMLs, PDFs)     │
│   ├── Realtime (WebSocket)     │
│   └── Edge Functions (Deno)    │
│       ├── Doc. Electronicos    │
│       ├── Pagos                │
│       ├── AI Query/Chat        │
│       └── Envio email          │
└─────────────────────────────────┘
```

**Separacion de responsabilidades:**
- **Flutter maneja:** UI, formularios, validaciones locales, cache offline (Brick+SQLite), navegacion, impresion, tokenizacion de pagos
- **Supabase maneja:** Datos, auth, archivos (Storage), notificaciones en tiempo real, embeddings IA (pgvector)
- **Edge Functions manejan:** Documentos electronicos (firma, envio, generacion XML), email, procesamiento de pagos, consultas IA

### Justificacion de Flutter como Frontend

Flutter fue elegido por las siguientes razones:

| Criterio | Flutter | Ventaja |
|----------|---------|---------|
| Cobertura plataformas | Web + iOS + Android + Windows + macOS + Linux | **6/6 plataformas nativas** |
| Un solo lenguaje | Dart | Sin necesidad de JavaScript/TypeScript en el frontend |
| App Stores | Compilacion nativa iOS/Android | Presencia directa en stores |
| Desktop nativo | Compilacion Windows/macOS/Linux | Rendimiento nativo, sin Electron |
| Offline-first | brick_offline_first_with_supabase | Sync automatico + cola offline |
| Widgets empresariales | Syncfusion (grids, charts, PDF, calendarios) | Componentes profesionales listos |
| Hot Reload | Desarrollo rapido | Iteracion inmediata |

**Arquitectura cliente-servidor:**
- **Flutter (cliente):** UI, estado local, cache, offline
- **Supabase (servidor):** PostgreSQL + Auth + RLS + Storage + Realtime
- **Edge Functions (servidor):** Documentos electronicos (firma, envio, generacion XML), email, pagos
- Los materiales criptograficos **nunca residen en el dispositivo** del usuario

### Librerias Flutter (Frontend - Dart)

| Libreria | Funcion | Licencia |
|----------|---------|----------|
| **supabase_flutter** | Cliente Supabase (Auth, DB, Storage, Realtime) | MIT |
| **supabase_auth_ui** | Widgets pre-construidos: login, registro, reset password, magic link, social auth | MIT |
| **flutter_riverpod** | Estado reactivo, inyeccion de dependencias | MIT |
| **syncfusion_flutter_datagrid** | Tablas de datos empresariales (sort, filter, export) | Comercial/Community |
| **syncfusion_flutter_pdf** | Generacion RIDE y reportes PDF | Comercial/Community |
| **syncfusion_flutter_charts** | Graficos para dashboard | Comercial/Community |
| **syncfusion_flutter_calendar** | Calendario de vencimientos | Comercial/Community |
| **go_router** | Navegacion declarativa (deep linking) | BSD |
| **brick_offline_first_with_supabase** | Offline-first: SQLite local + sync Supabase + Realtime | MIT |
| **brick_offline_first_with_supabase_build** | Code generator para modelos Brick (dev dep) | MIT |
| **dio** | HTTP client (llamadas a Edge Functions) | MIT |
| **flutter_form_builder** | Formularios con validacion | MIT |
| **form_builder_validators** | Validadores (identificacion fiscal, etc.) | MIT |
| **printing** | Impresion nativa de documentos | MIT |
| **file_picker** | Seleccion de archivos | MIT |
| **Adaptador de pasarela** | Tokenizacion de tarjetas — módulo de pagos | MIT |
| **mobile_scanner** | Escaneo codigos de barras/QR (camara) | BSD |
| **flutter_secure_storage** | Almacenamiento seguro de tokens | BSD |
| **shared_preferences** | Persistencia local de preferencias UI (tema, fuente, densidad) | BSD |
| **flex_color_scheme** | Temas Material 3 avanzados: 66 esquemas, sub-temas, blending | BSD |
| **flex_seed_scheme** | Generador ColorScheme con multiples seeds, chroma, tones (dep. de flex_color_scheme) | BSD |
| **intl** | Formato numeros/fechas Ecuador | BSD |

**Nota sobre Syncfusion:** La licencia Community es gratuita para empresas con menos de $1M de ingreso anual y para desarrolladores individuales. Incluye soporte tecnico.

**Nota sobre Brick:** `brick_offline_first_with_supabase` reemplaza el uso directo de drift. Los modelos se definen con `@ConnectOfflineFirstWithSupabase()` y extienden `OfflineFirstWithSupabaseModel`. El code generator crea adaptadores duales (SQLite + Supabase). Las mutaciones offline se encolan automaticamente y se replican al reconectar. Realtime se consume via `Repository().subscribeToRealtime<T>()`.

### Librerias Backend (Edge Functions - Deno/TypeScript)

Las librerías de firma electrónica, generación de XML y comunicación con organismos fiscales son específicas de cada país y pertenecen a los módulos de localización correspondientes.

**El frontend Flutter NO maneja firma, protocolos de comunicación fiscal ni pagos server-side.** Solo envía datos/tokens al servidor y recibe resultados.

### Supabase Storage (Archivos)

Supabase Storage gestiona todos los archivos del ERP:

| Bucket | Contenido | Acceso |
|--------|-----------|--------|
| `assets` | Logos, plantillas, recursos de la app | Lectura por empresa (RLS) |
| `attachments` | Adjuntos polimórficos de cualquier entidad | Lectura por empresa (RLS) |
| Buckets adicionales | Definidos por cada módulo según sus necesidades | Server-side o lectura por empresa (RLS) |

**Politicas de acceso:** Cada bucket tiene policies que filtran por `empresa_id` del JWT. Los archivos de criptografía y certificados solo son accesibles desde Edge Functions via service_role key.

### Costos Comparativos de Hosting a Escala

Con Flutter, el frontend no tiene costo de hosting significativo (apps nativas se ejecutan en el dispositivo, Flutter Web usa Cloudflare Pages (gratis)).

| Tenants | Supabase + Cloudflare Pages | AWS (ECS + RDS) | Railway |
|---------|---------------------|-----------------|---------|
| 1-50 | ~$25-35/mes | ~$150/mes | ~$60/mes |
| 50-200 | ~$50-75/mes | ~$300/mes | ~$120/mes |
| 200-1000 | ~$150-200/mes | ~$800/mes | ~$300/mes |
| 1000+ | ~$500/mes | ~$3,000+/mes | ~$800/mes |

Con Flutter el costo es **menor** que con Next.js/Vercel porque no hay serverless functions frontend. Todo el costo esta en Supabase (backend).

---


---


### Estrategia Multi-Plataforma

```
FASE 1 (MVP): Flutter Web + Android
  - Flutter Web desplegado en Cloudflare Pages (CDN global)
  - Flutter Android en Google Play Store
  - Offline-first con brick_offline_first_with_supabase
  - Push notifications via Supabase Realtime

FASE 2: iOS + Desktop
  - Flutter iOS en App Store
  - Flutter Windows (distribucion directa o Microsoft Store)
  - Flutter macOS (distribucion directa o Mac App Store)
  - Flutter Linux (Snap/Flatpak o descarga directa)

FASE 3: Funcionalidades avanzadas
  - Escaneo de documentos con camara (mobile_scanner)
  - Impresion termica (esc_pos_printer)
  - Auto-update para desktop
  - Chat IA integrado (pgvector + Edge Functions)
```

### Infraestructura de Despliegue

```
┌─────────────────────────────────────────────┐
│                 PRODUCCION                   │
│                                             │
│  Cloudflare Pages (Flutter Web)             │
│  ├── CDN Global (gratis)                   │
│  ├── SSL automatico                         │
│  └── Deploy: wrangler pages deploy          │
│                                             │
│  Google Play Store (Android)                │
│  Apple App Store (iOS)                      │
│  Distribucion directa (Desktop)             │
│                                             │
│  Supabase Cloud (Backend unico)             │
│  ├── PostgreSQL + pgvector (managed)       │
│  ├── Auth (JWT, MFA)                        │
│  ├── Storage (XMLs, PDFs, certificados)     │
│  ├── Edge Functions (doc. electronicos, pagos, IA) │
│  ├── Realtime (notificaciones, sync)        │
│  └── Logs & Monitoring                      │
│                                             │
│  Servicios Adicionales                      │
│  ├── Resend (emails transaccionales)        │
│  ├── Sentry (error monitoring)              │
│  └── Kushki (pasarela de pagos)            │
└─────────────────────────────────────────────┘

Costo estimado mensual:
  Supabase Pro:        $25/mes (TODO incluido: DB, Auth, Storage, Edge, Realtime)
  Cloudflare Pages:    $0 (gratis, hosting Flutter Web)
  Resend:              $0-20/mes (segun volumen)
  Sentry:              $0 (tier free)
  Kushki:              Comision por transaccion (negociada)
  Google Play:         $25 (unico)
  Apple Developer:     $99/anio (~$8/mes)
  ─────────────────────────────────
  TOTAL FIJO:          ~$25-45/mes + comisiones Kushki
```

### Ambientes

| Ambiente | Proposito |
|----------|-----------|
| **Local** | Desarrollo |
| **Staging** | QA y pruebas |
| **Produccion** | Produccion |

---

