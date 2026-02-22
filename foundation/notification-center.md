# Centro de Notificaciones In-App

> Migración: `020_notification_center.sql`
> Módulo: Foundation (transversal — cualquier módulo puede emitir notificaciones)
> Última revisión: 2026-02-22

---

## Descripción

El Centro de Notificaciones In-App es una capa transversal de Foundation que permite a **cualquier módulo** enviar notificaciones internas a usuarios específicos dentro de su empresa. Las notificaciones persisten en base de datos y se entregan en tiempo real mediante **Supabase Realtime**.

**Características:**
- Push en tiempo real (Supabase Realtime WebSocket)
- Historial persistente e inmutable (DELETE=false)
- Paginación, filtrado por leídas/no leídas
- Limpieza automática vía pg_cron (leídas > 90 días)
- Integración nativa con Workflows de Aprobación (migration 021)

---

## Tabla: `notificaciones_usuario`

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `id` | UUID PK | Identificador |
| `empresa_id` | UUID FK | Tenant (RLS) |
| `usuario_id` | UUID FK → `auth.users` | Destinatario |
| `tipo` | TEXT | `info` · `alerta` · `aprobacion` · `sistema` · `modulo` |
| `titulo` | TEXT | Máx 200 caracteres |
| `cuerpo` | TEXT | Máx 1000 caracteres — opcional |
| `datos` | JSONB | Payload libre: `{ registro_id, modulo, recurso, link }` |
| `icono` | TEXT | Nombre FluentIcons (ej: `mail_20_regular`) |
| `accion_url` | TEXT | Deep link interno (ej: `/compras/ordenes/uuid`) |
| `leida` | BOOLEAN | `false` por defecto |
| `leida_at` | TIMESTAMPTZ | Cuándo se marcó como leída |
| `created_at` | TIMESTAMPTZ | Inmutable |

**RLS:**
- SELECT: solo el propio `usuario_id` dentro de su `empresa_id`
- INSERT: autenticado (funciones internas usan SECURITY DEFINER)
- UPDATE: solo el propio usuario (para marcar leída)
- DELETE: `false` — historial inmutable

---

## RPCs disponibles

### `crear_notificacion(empresa_id, usuario_id, tipo, titulo, [cuerpo, datos, icono, accion_url])`
**Tipo:** SECURITY DEFINER — llamada desde otros módulos o funciones internas.

```sql
-- Ejemplo: notificar desde un módulo
SELECT crear_notificacion(
    private.get_empresa_id(),
    '550e8400-e29b-41d4-a716-446655440000',   -- usuario_id destinatario
    'modulo',
    'Pedido #001234 confirmado',
    'Tu pedido fue confirmado y está siendo procesado.',
    '{"registro_id": "uuid-pedido", "modulo": "ventas"}'::JSONB,
    'checkmark_circle_20_regular',
    '/ventas/ordenes/uuid-pedido'
);
```

### `get_notificaciones([limite=20, offset=0, solo_no_leidas=false])`
Retorna notificaciones paginadas del usuario actual.

```sql
-- Últimas 20 notificaciones
SELECT * FROM get_notificaciones();

-- Solo no leídas
SELECT * FROM get_notificaciones(p_solo_no_leidas => true);
```

### `get_count_notificaciones_no_leidas()`
Retorna INTEGER — el número que aparece en el badge de la campana.

### `marcar_notificacion_leida(notificacion_id)`
Marca una notificación como leída. Solo aplica si pertenece al usuario actual.

### `marcar_todas_notificaciones_leidas()`
Marca todas las no leídas del usuario actual. Retorna `INTEGER` (cuántas marcó).

---

## Tipos de notificación

| Tipo | Uso | Icono sugerido |
|------|-----|----------------|
| `info` | Informativa genérica | `info_20_regular` |
| `alerta` | Acción requerida urgente | `warning_20_regular` |
| `aprobacion` | Solicitud/resolución de aprobación | `checkmark_circle_20_regular` |
| `sistema` | Mensajes del sistema PILAR | `settings_20_regular` |
| `modulo` | Notificaciones específicas de módulo | (definido por el módulo) |

---

## Configuración Supabase Realtime

Para que el cliente Flutter reciba notificaciones en tiempo real sin polling:

**En Supabase Dashboard:**
1. Database → Replication → Tables
2. Habilitar `notificaciones_usuario` en `supabase_realtime` publication

**Flutter — suscripción:**
```dart
// En notificacionesProvider (Riverpod)
final channel = supabase.channel('notifications:${user.id}')
    .onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'notificaciones_usuario',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'usuario_id',
        value: user.id,
      ),
      callback: (payload) {
        ref.invalidate(notificacionesProvider);
        ref.invalidate(countNoLeidasProvider);
      },
    )
    .subscribe();
```

---

## Implementación Flutter

### Widget: `NotificationBell`

Ubicación sugerida: `lib/core/widgets/notification_bell.dart`

```dart
class NotificationBell extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(countNoLeidasProvider);

    return IconButton(
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text(count > 99 ? '99+' : '$count'),
        child: const Icon(FluentIcons.alert_20_regular),
      ),
      onPressed: () => _showNotificationsPanel(context, ref),
    );
  }
}
```

### Panel de notificaciones

```dart
void _showNotificationsPanel(BuildContext context, WidgetRef ref) {
  // ContentDialog (fluent_ui) con ListView de notificaciones
  // Botón "Marcar todas como leídas" en el header
  // Cada item: icono, titulo, cuerpo (truncado), tiempo relativo, dot azul si no leída
  // onTap: marcar como leída + navegar a accion_url
}
```

### Providers Riverpod sugeridos

```dart
// count badge en tiempo real
final countNoLeidasProvider = StreamProvider<int>((ref) { ... });

// lista paginada
final notificacionesProvider = FutureProvider.family<List<Notificacion>, bool>((ref, soloNoLeidas) { ... });
```

---

## Integración desde módulos

Cualquier módulo puede emitir notificaciones llamando `crear_notificacion()` desde:

1. **Funciones SQL** (recomendado): llamada directa a `crear_notificacion()`
2. **Edge Functions**: via `adminClient.rpc('crear_notificacion', {...})`
3. **Workflows de aprobación**: automático desde `021_approval_workflows.sql`

### Ejemplo: notificación de stock bajo desde Inventario

```sql
-- Trigger en inventario_stock cuando cantidad < stock_minimo
CREATE OR REPLACE FUNCTION inventario.notificar_stock_bajo()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE v_usuario UUID;
BEGIN
    FOR v_usuario IN
        SELECT ue.usuario_id FROM usuarios_empresa ue
        JOIN roles r ON r.id = ue.rol_id
        WHERE ue.empresa_id = NEW.empresa_id
          AND r.nombre IN ('BODEGUERO','GERENTE','ADMIN')
          AND ue.activo = true
    LOOP
        PERFORM crear_notificacion(
            NEW.empresa_id, v_usuario,
            'alerta',
            format('Stock bajo: %s', NEW.producto_nombre),
            format('Quedan %s unidades. Mínimo: %s', NEW.cantidad, NEW.stock_minimo),
            jsonb_build_object('producto_id', NEW.producto_id, 'modulo', 'inventario'),
            'box_20_regular',
            format('/inventario/productos/%s', NEW.producto_id)
        );
    END LOOP;
    RETURN NEW;
END;
$$;
```

---

## pg_cron

| Job | Schedule | Descripción |
|-----|----------|-------------|
| `pilar_cleanup_old_notifications` | `0 4 * * *` | Elimina notificaciones leídas con más de 90 días |

---

## Consideraciones de diseño

**¿Por qué historial inmutable?**
Las notificaciones son eventos del sistema. Borrar una notificación podría ocultar que un usuario fue informado de algo. La política `DELETE USING (false)` garantiza esto.

**¿Por qué no usar el módulo `comunicacion`?**
El módulo `comunicacion` maneja **canales externos** (email, WhatsApp, Telegram). Las notificaciones in-app son una capa diferente — viven dentro del ERP y no requieren integraciones externas. Son complementarias, no alternativas.

**Límites por diseño:**
- `get_notificaciones` tiene un tope de 100 registros por página (LEAST constraint)
- La limpieza automática aplica solo a notificaciones leídas — las no leídas persisten indefinidamente
