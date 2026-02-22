# Guía de Desactivación de Módulos

**Estado**: Referencia canónica — leer antes de implementar lógica de desactivación
**Relacionado con**: `module-activation-guarantees.md`, `arquitectura-modular.md`, ADR-009

---

## Principio fundamental: los datos nunca se eliminan

Cuando un módulo se desactiva, sus datos persisten en la base de datos. La desactivación solo afecta:
- La visibilidad en la UI (el módulo deja de aparecer en el menú)
- Las funciones del MSB (retornan `MODULE_NOT_ACTIVE` en lugar de ejecutar)
- El router de Flutter (las rutas del módulo se eliminan del `appRouter`)

**Los datos del módulo son activos de la empresa.** Eliminarlos al desactivar sería una violación de las obligaciones tributarias (Ecuador exige conservar documentos fiscales por 7 años) y un riesgo inaceptable de pérdida de información.

---

## Validaciones que `deactivate_module()` debe hacer antes de proceder

```sql
CREATE OR REPLACE FUNCTION deactivate_module(
    p_empresa_id UUID,
    p_modulo_id  TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
    v_dependientes_activos  TEXT[];
    v_bloqueos              JSONB  := '[]'::JSONB;
    v_pre_check_rpc         TEXT;
    v_check_resultado       JSONB;
BEGIN
    -- VALIDACIÓN 1: Verificar que el módulo está activo para esta empresa
    IF NOT EXISTS (
        SELECT 1 FROM modulos_empresa
        WHERE empresa_id = p_empresa_id AND modulo_id = p_modulo_id AND activo = TRUE
    ) THEN
        RETURN jsonb_build_object(
            'ok', FALSE, 'error', 'MODULE_NOT_ACTIVE',
            'msg', 'El módulo no está activo para esta empresa'
        );
    END IF;

    -- VALIDACIÓN 2: Verificar que ningún módulo activo depende de este
    SELECT array_agg(me.modulo_id)
    INTO v_dependientes_activos
    FROM modulos_empresa me
    JOIN modulo_dependencias md ON md.modulo_id = me.modulo_id
    WHERE me.empresa_id  = p_empresa_id
      AND md.depende_de  = p_modulo_id
      AND md.requerido   = TRUE
      AND me.activo      = TRUE
      AND me.modulo_id  != p_modulo_id;

    IF v_dependientes_activos IS NOT NULL
       AND array_length(v_dependientes_activos, 1) > 0
    THEN
        RETURN jsonb_build_object(
            'ok',            FALSE,
            'error',         'DEPENDENCY_CONFLICT',
            'msg',           'Otros módulos activos dependen de este. Desactivarlos primero.',
            'dependientes',  to_jsonb(v_dependientes_activos)
        );
    END IF;

    -- VALIDACIÓN 3: Ejecutar pre_uninstall_check del módulo
    SELECT m.pre_uninstall_check_rpc INTO v_pre_check_rpc
    FROM modulos m
    WHERE m.id = p_modulo_id AND m.pre_uninstall_check_rpc IS NOT NULL;

    IF v_pre_check_rpc IS NOT NULL THEN
        EXECUTE format('SELECT %I($1)', v_pre_check_rpc)
        USING p_empresa_id
        INTO v_check_resultado;

        IF NOT (v_check_resultado->>'puede_desactivar')::BOOLEAN THEN
            RETURN jsonb_build_object(
                'ok',      FALSE,
                'error',   'PRE_CHECK_FAILED',
                'msg',     v_check_resultado->>'mensaje',
                'bloqueos', v_check_resultado->'bloqueos'
            );
        END IF;
    END IF;

    -- VALIDACIÓN 4: Verificar módulos de infraestructura (no desactivables)
    IF EXISTS (
        SELECT 1 FROM modulos WHERE id = p_modulo_id AND tipo = 'infraestructura'
    ) THEN
        RETURN jsonb_build_object(
            'ok', FALSE, 'error', 'UNDEACTIVATABLE',
            'msg', 'Los módulos de infraestructura no pueden desactivarse'
        );
    END IF;

    -- PROCEDER: Marcar como inactivo (no eliminar el registro)
    UPDATE modulos_empresa
    SET activo = FALSE, deactivated_at = NOW()
    WHERE empresa_id = p_empresa_id AND modulo_id = p_modulo_id;

    -- Loguear la desactivación
    INSERT INTO system_logs (
        empresa_id, tipo, nivel, mensaje, created_at
    ) VALUES (
        p_empresa_id, 'module_deactivation', 'info',
        format('Módulo %s desactivado', p_modulo_id),
        NOW()
    );

    RETURN jsonb_build_object(
        'ok',          TRUE,
        'desactivado', p_modulo_id
    );

EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '[deactivate_module] Error: %', SQLERRM;
    RETURN jsonb_build_object('ok', FALSE, 'error', 'INTERNAL_ERROR', 'msg', SQLERRM);
END;
$$;
```

---

## Estados que bloquean la desactivación

### Documentos en estados intermedios

No se puede desactivar un módulo que tenga documentos pendientes de completar:

| Módulo | Documentos que bloquean | Estado que bloquea |
|--------|------------------------|--------------------|
| **Facturación** | `facturas` | `borrador`, `pendiente_envio`, `enviado_sri`, `autorizado` (si tiene saldo pendiente) |
| **Ventas** | `ordenes_venta` | `confirmada`, `en_entrega`, `parcialmente_facturada` |
| **Compras** | `ordenes_compra` | `confirmada`, `recibida_parcial`, `pendiente_factura` |
| **Inventario** | `inventario_reservas` | `activa` |
| **Tesorería** | `cheques` | `emitido`, `entregado` |
| **Contabilidad** | `periodos_contables` | `abierto` (si queda asientos sin conciliar) |
| **RRHH** | `nomina_periodos` | `en_proceso`, `calculado` (no pagado) |

### Colas con ítems pendientes

```sql
-- Verificar si hay ítems en pgmq para este módulo
SELECT count(*)
FROM pgmq.q_<nombre_cola>
WHERE (message->>'modulo')::TEXT = p_modulo_id
  AND (message->>'empresa_id')::UUID = p_empresa_id;
-- Si count > 0, bloquear desactivación
```

---

## Template de `pre_uninstall_check_rpc`

Cada módulo con documentos que pueden estar en estados intermedios debe implementar esta función:

```sql
-- ============================================================
-- modules/core/<modulo>/migrations/NNN_pre_uninstall_check.sql
-- ============================================================

CREATE OR REPLACE FUNCTION <modulo>_pre_uninstall_check(p_empresa_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
    v_bloqueos      JSONB := '[]'::JSONB;
    v_puede         BOOLEAN := TRUE;
    -- Contadores de documentos bloqueantes
    v_facturas_pendientes   INTEGER := 0;
    v_ordenes_activas       INTEGER := 0;
    v_cola_pendiente        INTEGER := 0;
BEGIN
    -- CHECK 1: Documentos en estado intermedio
    SELECT COUNT(*) INTO v_facturas_pendientes
    FROM facturas
    WHERE empresa_id = p_empresa_id
      AND estado IN ('borrador', 'pendiente_envio', 'enviado_sri');

    IF v_facturas_pendientes > 0 THEN
        v_puede   := FALSE;
        v_bloqueos := v_bloqueos || jsonb_build_object(
            'tipo',     'documentos_pendientes',
            'tabla',    'facturas',
            'cantidad', v_facturas_pendientes,
            'mensaje',  format('%s factura(s) en estado pendiente o en tránsito con el SRI', v_facturas_pendientes)
        );
    END IF;

    -- CHECK 2: Cola de documentos electrónicos con ítems
    SELECT COUNT(*) INTO v_cola_pendiente
    FROM cola_documentos_electronicos
    WHERE empresa_id = p_empresa_id AND estado IN ('pendiente', 'procesando');

    IF v_cola_pendiente > 0 THEN
        v_puede   := FALSE;
        v_bloqueos := v_bloqueos || jsonb_build_object(
            'tipo',     'cola_pendiente',
            'tabla',    'cola_documentos_electronicos',
            'cantidad', v_cola_pendiente,
            'mensaje',  format('%s documento(s) pendiente(s) de envío al SRI', v_cola_pendiente)
        );
    END IF;

    -- CHECK 3: Advertencia (no bloqueo) sobre datos que quedarán huérfanos
    -- (datos que existen pero no bloquean la desactivación)
    -- ...

    RETURN jsonb_build_object(
        'puede_desactivar', v_puede,
        'bloqueos',          v_bloqueos,
        'mensaje',           CASE
            WHEN v_puede THEN 'No hay impedimentos para desactivar el módulo'
            ELSE format('%s impedimento(s) encontrado(s). Resolver antes de desactivar.', jsonb_array_length(v_bloqueos))
        END
    );
END;
$$;

-- Registrar el RPC en el catálogo de módulos
UPDATE modulos
SET pre_uninstall_check_rpc = '<modulo>_pre_uninstall_check'
WHERE id = '<modulo>';
```

---

## Estrategia de archivado de datos

Cuando un módulo se desactiva, sus datos se marcan como archivados pero no se eliminan:

```sql
-- Patrón para archivar datos al desactivar (ejecutado por el onDeactivate del módulo)
-- NUNCA eliminar: solo marcar como archivado y ocultar en la UI

-- Opción 1: Columna is_archived en tablas del módulo
ALTER TABLE <tabla_del_modulo>
    ADD COLUMN IF NOT EXISTS is_archived       BOOLEAN     DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS archived_at       TIMESTAMPTZ DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS archived_reason   TEXT        DEFAULT NULL;

-- Opción 2: Para tablas cross-módulo, solo desactivar las referencias activas
-- (no modificar datos históricos de otros módulos)
UPDATE inventario_reservas
SET estado = 'cancelada', updated_at = NOW()
WHERE empresa_id = p_empresa_id AND estado = 'activa';
```

### Lo que sí se puede limpiar de forma segura al desactivar

- Caches y datos temporales de sesión del módulo
- Configuraciones de preferencia (no datos de negocio)
- Suscripciones a canales de Realtime del módulo

### Lo que NUNCA se elimina al desactivar

- Transacciones históricas (facturas, asientos, movimientos, etc.)
- Configuraciones que afectan cálculos históricos (listas de precio, tarifas)
- Registros de auditoría
- Documentos electrónicos y sus XMLs

---

## Cascadas de dependencias: qué pasa cuando desactivo un módulo del que otros dependen

### Escenario: intento desactivar `inventario` cuando `pos` y `ventas` dependen de él

```
modulo_dependencias:
  pos.depende_de = inventario (requerido=TRUE)
  ventas.depende_de = inventario (requerido=TRUE)

Estado actual de la empresa:
  inventario → activo
  pos         → activo
  ventas      → activo

Resultado de deactivate_module(empresa, 'inventario'):
{
  "ok": false,
  "error": "DEPENDENCY_CONFLICT",
  "msg": "Otros módulos activos dependen de este. Desactivarlos primero.",
  "dependientes": ["pos", "ventas"]
}
```

**No hay cascada automática de desactivación.** El administrador debe desactivar los módulos dependientes primero, en el orden correcto:

```
1. deactivate_module(empresa, 'pos')       → OK (pos no tiene dependientes)
2. deactivate_module(empresa, 'ventas')    → OK (si no hay otros dependientes de ventas)
3. deactivate_module(empresa, 'inventario') → OK (ya no hay dependientes activos)
```

La UI debe mostrar el árbol de dependencias y el orden recomendado de desactivación.

---

## El hook `onDeactivate()` en Dart

```dart
abstract class PilarModule {
  /// Hook ejecutado ANTES de que deactivate_module() sea llamado en el backend.
  /// Usar para: liberar recursos, cancelar suscripciones, limpiar cache local.
  /// NO usar para: eliminar datos de negocio.
  /// Retornar false si hay razones en cliente para bloquear la desactivación.
  Future<bool> onDeactivate(Ref ref) async {
    // Por defecto: permitir desactivación
    return true;
  }
}

// Ejemplo en un módulo concreto:
class PosModule implements PilarModule {
  @override
  String get id => 'pos';

  @override
  Future<bool> onDeactivate(Ref ref) async {
    // Verificar si hay una sesión de caja abierta en este dispositivo
    final cajaActiva = ref.read(cajaPosProvider);
    if (cajaActiva != null) {
      // No bloquear pero avisar: la sesión de caja debe cerrarse primero
      // (el bloqueo real viene del pre_uninstall_check en el backend)
      return true;
    }

    // Cancelar suscripción Realtime del POS
    ref.read(posRealtimeSubscriptionProvider.notifier).cancel();

    // Limpiar cache local de productos del POS
    await ref.read(posCacheProvider.notifier).clear();

    // Invalidar providers
    ref.invalidate(posProvider);

    return true;
  }
}
```

### Flujo completo de desactivación desde Flutter

```dart
@riverpod
class ModuleDeactivationNotifier extends _$ModuleDeactivationNotifier {
  Future<DeactivationResult> deactivateModule(String moduloId) async {
    final empresaId = ref.read(empresaActivaProvider)!.id;

    // 1. Ejecutar hook Dart pre-desactivación
    final module = ModuleRegistry.get(moduloId);
    if (module != null) {
      final canDeactivate = await module.onDeactivate(ref);
      if (!canDeactivate) {
        return DeactivationResult.blocked(
          reason: 'El módulo tiene recursos activos en este dispositivo',
        );
      }
    }

    // 2. Llamar al backend (incluye pre_uninstall_check)
    final result = await ref.read(supabaseProvider).rpc(
      'deactivate_module',
      params: {
        'p_empresa_id': empresaId,
        'p_modulo_id':  moduloId,
      },
    );

    final msbResult = MsbResult.fromJson(result);

    if (!msbResult.ok) {
      // El backend rechazó la desactivación (documentos pendientes, dependencias, etc.)
      return DeactivationResult.blocked(
        reason: msbResult.error,
        bloqueos: msbResult.json['bloqueos'],
      );
    }

    // 3. Actualizar el estado local
    ref.invalidate(modulosActivosProvider);

    return DeactivationResult.success(moduloId: moduloId);
  }
}
```

---

## Casos especiales: módulos de infraestructura

Los módulos de Infraestructura (Administración, Comunicación) **nunca pueden desactivarse**. Son prerrequisitos del sistema y están marcados en la tabla `modulos` con `tipo = 'infraestructura'` y `desactivable = FALSE`.

```sql
-- En la UI de administración, verificar antes de mostrar el botón de desactivar:
SELECT desactivable
FROM modulos
WHERE id = p_modulo_id;
-- Si FALSE → no mostrar botón "Desactivar", mostrar "Este módulo es parte del núcleo del sistema"
```

---

## Rollback de una desactivación fallida o inconsistente

Si `deactivate_module()` retornó error pero el módulo quedó en estado inconsistente:

```sql
-- Paso 1: Verificar el estado actual
SELECT modulo_id, activo, activated_at, deactivated_at
FROM modulos_empresa
WHERE empresa_id = 'tu-empresa-uuid'
  AND modulo_id  = 'modulo-afectado';

-- Paso 2a: Si activo=FALSE pero debería estar activo (falsa desactivación)
UPDATE modulos_empresa
SET activo = TRUE, deactivated_at = NULL
WHERE empresa_id = 'tu-empresa-uuid' AND modulo_id = 'modulo-afectado';

-- Paso 2b: Si activo=TRUE pero el módulo quedó sin datos de configuración
-- Ejecutar manualmente el post_install_rpc:
SELECT <modulo>_post_install('tu-empresa-uuid');

-- Paso 3: Verificar en los logs del sistema
SELECT mensaje, metadata, created_at
FROM system_logs
WHERE empresa_id = 'tu-empresa-uuid'
  AND tipo IN ('module_activation', 'module_deactivation')
ORDER BY created_at DESC
LIMIT 20;
```

---

## Checklist para implementar desactivación en un módulo nuevo

- [ ] `pre_uninstall_check_rpc` implementado y registrado en tabla `modulos`
- [ ] La función identifica todos los documentos en estados intermedios
- [ ] La función identifica colas pgmq con ítems pendientes del módulo
- [ ] Hook `onDeactivate()` en Dart implementado en `<Modulo>Module`
- [ ] Las tablas del módulo tienen columna `is_archived` si aplica archivado
- [ ] La UI muestra el árbol de dependencias antes de confirmar desactivación
- [ ] La UI muestra los bloqueos con instrucciones claras para resolverlos
- [ ] Está documentado en `module.md` qué datos persisten tras la desactivación

---

## Referencias

- `foundation/module-activation-guarantees.md` — activación y sus garantías
- `foundation/arquitectura-modular.md` — estados de módulos, `deactivate_module()` base
- `foundation/background-jobs.md` — verificación de colas pgmq
- `modules/core/*/module.md` — qué documentos/estados tiene cada módulo
