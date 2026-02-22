# Garantías de Activación de Módulos

**Estado**: Referencia canónica — leer antes de implementar lógica de activación/desactivación
**Relacionado con**: `arquitectura-modular.md`, ADR-009, `module-deactivation-guide.md`

---

## Diagrama de estados de un módulo

```
                    activate_module()
                   ┌──────────────────────────────────┐
                   │                                  │
          ┌────────▼──────────┐              ┌────────┴──────────┐
          │                   │   onActivate │                   │
          │   TO_INSTALL      │─────────────►│    INSTALLED      │
          │                   │  completado  │                   │
          └────────┬──────────┘              └────────┬──────────┘
                   │                                  │
                   │ error en                         │ deactivate_module()
                   │ activación                       │ (validaciones OK)
                   │                                  │
          ┌────────▼──────────┐              ┌────────▼──────────┐
          │                   │              │                   │
          │   UNINSTALLED     │◄─────────────│   TO_REMOVE       │
          │                   │  onDeactivate│                   │
          └───────────────────┘   completado └───────────────────┘
                   ▲
                   │ rollback manual
                   │ (ver sección correspondiente)
          ┌────────┴──────────┐
          │                   │
          │  UNINSTALLABLE    │  ← Módulo marcado como no desinstalable
          │                   │     (ej: módulos de infraestructura)
          └───────────────────┘
```

### Estados en la tabla `modulos_empresa`

| Estado | Significado | Qué hace la app |
|--------|-------------|-----------------|
| (registro no existe) | Módulo no instalado para esta empresa | No aparece en menú ni en ModuleRegistry activo |
| `activo = TRUE` | Módulo instalado y en funcionamiento | Visible en menú, rutas activas, MSB habilitado |
| `activo = FALSE` | Módulo en proceso de desactivación o suspendido temporalmente | No visible en menú, funciones MSB retornan NO-OP |

> La tabla `modulos_empresa` no tiene una columna de estado explícita: el módulo "existe" (instalado) o "no existe" (no instalado). El campo `activo` permite suspensión temporal sin eliminar el registro.

---

## Qué hace exactamente `activate_module()` paso a paso

### Implementación completa con ciclo de vida

```sql
CREATE OR REPLACE FUNCTION activate_module(
    p_empresa_id UUID,
    p_modulo_id  TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
    v_modulos_a_activar TEXT[];
    v_modulo             TEXT;
    v_activados          TEXT[]  := '{}';
    v_ya_activos         TEXT[]  := '{}';
    v_post_install_rpc   TEXT;
    v_rpc_resultado      JSONB;
BEGIN
    -- PASO 1: Verificar que el módulo existe en el catálogo global
    IF NOT EXISTS (SELECT 1 FROM modulos WHERE id = p_modulo_id) THEN
        RETURN jsonb_build_object(
            'ok', FALSE, 'error', 'MODULE_NOT_FOUND',
            'modulo', p_modulo_id
        );
    END IF;

    -- PASO 2: Verificar que el módulo no está marcado como uninstallable
    IF EXISTS (
        SELECT 1 FROM modulos WHERE id = p_modulo_id AND estado = 'uninstallable'
    ) THEN
        RETURN jsonb_build_object(
            'ok', FALSE, 'error', 'MODULE_UNINSTALLABLE',
            'modulo', p_modulo_id
        );
    END IF;

    -- PASO 3: Resolver árbol completo de dependencias en orden topológico
    -- (primero las dependencias, último el módulo solicitado)
    SELECT array_agg(modulo_id ORDER BY nivel DESC)
    INTO v_modulos_a_activar
    FROM resolve_module_dependencies(p_modulo_id);

    -- PASO 4: Verificar que todas las dependencias están registradas
    IF EXISTS (
        SELECT 1 FROM unnest(v_modulos_a_activar) AS m(id)
        WHERE NOT EXISTS (SELECT 1 FROM modulos WHERE modulos.id = m.id)
    ) THEN
        RETURN jsonb_build_object(
            'ok', FALSE, 'error', 'DEPENDENCY_NOT_REGISTERED',
            'modulos_solicitados', to_jsonb(v_modulos_a_activar)
        );
    END IF;

    -- PASO 5: Activar módulos en orden (dependencias primero)
    -- Esta sección está dentro de una transacción implícita
    FOREACH v_modulo IN ARRAY v_modulos_a_activar LOOP
        INSERT INTO modulos_empresa (empresa_id, modulo_id, activo, activated_at)
        VALUES (p_empresa_id, v_modulo, TRUE, NOW())
        ON CONFLICT (empresa_id, modulo_id) DO UPDATE
            SET activo = TRUE, activated_at = NOW()
            WHERE modulos_empresa.activo = FALSE;  -- Solo actualizar si estaba inactivo

        IF FOUND THEN
            v_activados := array_append(v_activados, v_modulo);
        ELSE
            v_ya_activos := array_append(v_ya_activos, v_modulo);
        END IF;
    END LOOP;

    -- PASO 6: Ejecutar post_install_rpc si existe (fuera de la transacción principal)
    -- IMPORTANTE: post_install_rpc se ejecuta DESPUÉS del commit implícito de los pasos 1-5
    -- Si falla, los módulos quedan activos pero sin datos iniciales (ver sección de errores)
    SELECT m.post_install_rpc INTO v_post_install_rpc
    FROM modulos m
    WHERE m.id = p_modulo_id AND m.post_install_rpc IS NOT NULL;

    IF v_post_install_rpc IS NOT NULL AND array_length(v_activados, 1) > 0 THEN
        BEGIN
            EXECUTE format('SELECT %I($1)', v_post_install_rpc)
            USING p_empresa_id
            INTO v_rpc_resultado;

            IF NOT (v_rpc_resultado->>'ok')::BOOLEAN THEN
                -- post_install_rpc falló pero el módulo ya está activo
                -- Loguear para que el admin pueda reintentar
                INSERT INTO system_logs (
                    empresa_id, tipo, nivel, mensaje, metadata, created_at
                ) VALUES (
                    p_empresa_id, 'module_activation', 'warning',
                    format('post_install_rpc falló para módulo %s', p_modulo_id),
                    jsonb_build_object('modulo', p_modulo_id, 'error', v_rpc_resultado),
                    NOW()
                );
            END IF;
        EXCEPTION WHEN OTHERS THEN
            -- No revertir la activación por un error en post_install
            RAISE WARNING '[activate_module] post_install_rpc falló para %: %', p_modulo_id, SQLERRM;
        END;
    END IF;

    -- PASO 7: Retornar resultado
    RETURN jsonb_build_object(
        'ok',         TRUE,
        'activados',  to_jsonb(v_activados),
        'ya_activos', to_jsonb(v_ya_activos),
        'total',      COALESCE(array_length(v_activados, 1), 0)
    );

EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '[activate_module] Error inesperado: %', SQLERRM;
    RETURN jsonb_build_object('ok', FALSE, 'error', 'INTERNAL_ERROR', 'msg', SQLERRM);
END;
$$;
```

---

## Garantías transaccionales

### Lo que está dentro de la transacción (ACID garantizado)

Los pasos 1 al 5 de `activate_module()` ocurren dentro de una sola transacción PostgreSQL:
- La verificación de existencia del módulo
- La resolución de dependencias
- Los INSERT/UPDATE en `modulos_empresa`

**Si cualquiera de estos pasos falla, ningún módulo queda activado a medias.**

### Lo que está fuera de la transacción (sin garantía ACID)

El `post_install_rpc` (paso 6) se ejecuta **después** de que la transacción principal fue committeada. Esto es intencional porque:

1. El hook puede necesitar crear datos semilla que requieren que el módulo ya esté activo
2. Un error en el hook no debe revertir la activación del módulo (es recuperable)
3. Algunos hooks son lentos y no deben bloquear la transacción principal

**Consecuencia**: si `post_install_rpc` falla, el módulo queda activo pero sin datos de inicialización. El administrador debe reintentar manualmente llamando a la RPC de inicialización directamente.

---

## Manejo de errores: qué queda en la BD si falla

| Momento del fallo | Estado resultante | Acción requerida |
|-------------------|-------------------|-----------------|
| Durante pasos 1-5 (transacción) | Ningún módulo activado (rollback automático) | Reintentar `activate_module()` después de corregir el error |
| Durante `post_install_rpc` | Módulo activo, datos semilla ausentes | Llamar manualmente a la función de inicialización del módulo |
| Error de red al llamar desde Flutter | Módulo puede o no estar activo en BD | Verificar con `SELECT * FROM modulos_empresa WHERE empresa_id = :id` |
| Timeout de Edge Function de inicialización | Módulo activo, inicialización incompleta | Ver sección "Timeout de Edge Functions" |

---

## Idempotencia: qué pasa si `activate_module()` se llama dos veces

La función es completamente idempotente gracias al `ON CONFLICT DO UPDATE`:

```sql
-- Primera llamada: activa el módulo
SELECT activate_module('empresa-uuid', 'inventario');
-- Resultado: {"ok": true, "activados": ["inventario"], "ya_activos": [], "total": 1}

-- Segunda llamada: detecta que ya está activo
SELECT activate_module('empresa-uuid', 'inventario');
-- Resultado: {"ok": true, "activados": [], "ya_activos": ["inventario"], "total": 0}
```

El campo `ya_activos` permite que el caller distinga entre "se activó ahora" y "ya estaba activo", sin lanzar error en ningún caso.

---

## Cómo hacer rollback manual si una activación queda a medias

Si `activate_module()` dejó un módulo en estado inconsistente (activo en BD pero sin datos de inicialización), el proceso de rollback manual es:

```sql
-- PASO 1: Identificar el módulo problemático
SELECT modulo_id, activo, activated_at
FROM modulos_empresa
WHERE empresa_id = 'tu-empresa-uuid'
ORDER BY activated_at DESC;

-- PASO 2: Si el módulo debe desactivarse (rollback completo)
SELECT deactivate_module('tu-empresa-uuid', 'modulo_id');

-- PASO 3: Si solo falló la inicialización (reintentar post_install)
-- Llamar directamente a la función de inicialización del módulo:
SELECT <modulo>_post_install('tu-empresa-uuid');

-- PASO 4: Si quedan dependencias parciales activadas
-- Desactivar cada módulo en orden inverso (primero el que se pidió, luego sus dependencias)
SELECT deactivate_module('tu-empresa-uuid', 'modulo_solicitado');
SELECT deactivate_module('tu-empresa-uuid', 'dependencia_2');
SELECT deactivate_module('tu-empresa-uuid', 'dependencia_1');
```

---

## Timeout de Edge Functions: qué hacer si la inicialización tarda más de 15 segundos

Las Edge Functions de Supabase tienen un timeout de 150 segundos en producción y 60 segundos en desarrollo. Sin embargo, si la inicialización de un módulo requiere operaciones lentas (importar catálogos, generar configuración inicial para muchas empresas), puede exceder el timeout.

### Patrón recomendado para inicializaciones lentas

En lugar de ejecutar todo en el `post_install_rpc`, dividir en dos fases:

**Fase 1 (síncrona, en `post_install_rpc`)**: solo insertar la configuración mínima del módulo.

```sql
-- post_install_rpc del módulo (siempre rápido, < 1 segundo)
CREATE OR REPLACE FUNCTION modulo_inventario_post_install(p_empresa_id UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    -- Solo crear la configuración mínima requerida
    INSERT INTO inventario_configuracion (empresa_id, valoracion_metodo, created_at)
    VALUES (p_empresa_id, 'promedio', NOW())
    ON CONFLICT (empresa_id) DO NOTHING;

    -- Crear bodega principal vacía
    INSERT INTO bodegas (empresa_id, codigo, nombre, es_principal, activo, created_at)
    VALUES (p_empresa_id, 'BG-001', 'Bodega Principal', TRUE, TRUE, NOW())
    ON CONFLICT (empresa_id, codigo) DO NOTHING;

    -- Encolar la inicialización lenta en pgmq (sin bloquear)
    PERFORM pgmq.send(
        'modulo_init_queue',
        jsonb_build_object(
            'modulo', 'inventario',
            'empresa_id', p_empresa_id,
            'tarea', 'seed_catalogo_ubicaciones'
        )
    );

    RETURN jsonb_build_object('ok', TRUE, 'inicializacion_asincrona', TRUE);
END;
$$;
```

**Fase 2 (asíncrona, procesada por pg_cron o worker)**: la tarea pesada se procesa en background.

```sql
-- Job de pg_cron que procesa la cola de inicializaciones pendientes
-- Definido en foundation/background-jobs.md
SELECT cron.schedule(
    'procesar-modulo-init-queue',
    '* * * * *',  -- cada minuto
    $$ SELECT procesar_cola_modulo_init(); $$
);
```

---

## Template de `post_install_rpc` para módulos que inicializan datos

Todo módulo que necesite datos iniciales debe implementar este template:

```sql
-- ============================================================
-- modules/core/<modulo>/migrations/NNN_post_install.sql
-- ============================================================

CREATE OR REPLACE FUNCTION <modulo>_post_install(p_empresa_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
    v_ya_inicializado BOOLEAN;
BEGIN
    -- PASO 1: Verificar idempotencia (no re-inicializar si ya se hizo)
    SELECT EXISTS(
        SELECT 1 FROM <modulo>_configuracion WHERE empresa_id = p_empresa_id
    ) INTO v_ya_inicializado;

    IF v_ya_inicializado THEN
        RETURN jsonb_build_object(
            'ok', TRUE,
            'msg', 'Módulo ya inicializado — omitiendo',
            'idempotente', TRUE
        );
    END IF;

    -- PASO 2: Crear configuración por defecto del módulo
    INSERT INTO <modulo>_configuracion (
        empresa_id,
        -- parámetros con valores por defecto sensatos
        created_at
    ) VALUES (
        p_empresa_id,
        -- valores por defecto
        NOW()
    );

    -- PASO 3: Crear datos semilla específicos del módulo (si aplica)
    -- Preferir encolar en pgmq si son muchos registros

    -- PASO 4: Registrar en log del sistema
    INSERT INTO system_logs (
        empresa_id, tipo, nivel, mensaje, created_at
    ) VALUES (
        p_empresa_id,
        'module_post_install',
        'info',
        format('Módulo <modulo> inicializado para empresa %s', p_empresa_id),
        NOW()
    );

    RETURN jsonb_build_object(
        'ok',     TRUE,
        'modulo', '<modulo>',
        'empresa_id', p_empresa_id
    );

EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '[<modulo>_post_install] Error: %', SQLERRM;
    RETURN jsonb_build_object('ok', FALSE, 'error', 'INTERNAL_ERROR', 'msg', SQLERRM);
END;
$$;

-- Registrar el RPC en el catálogo de módulos
UPDATE modulos
SET post_install_rpc = '<modulo>_post_install'
WHERE id = '<modulo>';
```

---

## Implementación del hook `onActivate()` en Dart

Cuando `activate_module()` retorna exitosamente en el backend, Flutter ejecuta el hook Dart del módulo:

```dart
abstract class PilarModule {
  // ... otros miembros ...

  /// Hook ejecutado DESPUÉS de que activate_module() completó en el backend.
  /// Usar para: pre-fetch de datos, setup de providers, cache warmup.
  /// NO usar para: lógica de negocio que deba ejecutarse en el servidor.
  Future<void> onActivate(Ref ref) async {
    // Implementación por defecto: no hacer nada
  }
}

// Ejemplo de implementación en un módulo concreto:
class InventarioModule implements PilarModule {
  @override
  String get id => 'inventario';

  @override
  Future<void> onActivate(Ref ref) async {
    // Pre-cargar catálogo de bodegas en el cache local
    final bodegasRepo = ref.read(bodegasRepositoryProvider);
    await bodegasRepo.fetchAll();

    // Invalidar providers que dependían del estado sin inventario
    ref.invalidate(stockProvider);
    ref.invalidate(dashboardKpisProvider);
  }
}
```

### Cuándo se llama `onActivate()`

```dart
// En el provider que gestiona la activación de módulos:
@riverpod
class ModuleActivationNotifier extends _$ModuleActivationNotifier {
  Future<void> activateModule(String moduloId) async {
    // 1. Llamar al backend
    final result = await ref.read(supabaseProvider).rpc(
      'activate_module',
      params: {
        'p_empresa_id': ref.read(empresaActivaProvider)!.id,
        'p_modulo_id':  moduloId,
      },
    );

    final msbResult = MsbResult.fromJson(result);
    if (!msbResult.ok) throw ModuleActivationException(msbResult.error);

    // 2. Si el módulo se activó ahora (no estaba ya activo), ejecutar hook Dart
    if ((msbResult.json['activados'] as List).contains(moduloId)) {
      final module = ModuleRegistry.get(moduloId);
      await module?.onActivate(ref);
    }

    // 3. Invalidar providers de módulos activos para reconstruir menú y router
    ref.invalidate(modulosActivosProvider);
  }
}
```

---

## Referencias

- `foundation/arquitectura-modular.md` — ciclo completo de activación, ModuleRegistry
- `foundation/module-deactivation-guide.md` — desactivación y sus garantías
- `foundation/background-jobs.md` — pgmq para inicializaciones asíncronas
- `foundation/adrs/ADR-009_sistema-modular.md` — decisión de diseño del sistema modular
