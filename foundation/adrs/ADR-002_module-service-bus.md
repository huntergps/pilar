# ADR-002: Module Service Bus para Comunicacion entre Modulos

**Estado**: Aceptado
**Fecha**: 2026-02
**Autores**: Arquitecto principal
**Tags**: arquitectura, modulos, desacoplamiento, postgresql, multi-tenant

---

## Contexto

PILAR tiene 24 modulos organizados en 3 tipos: Infraestructura (siempre activos), Core (proveedores de servicios) y Auxiliares (consumidores de servicios). Los modulos Auxiliares necesitan operaciones en tablas de los modulos Core.

El problema: no todas las empresas tienen todos los modulos activos. Si un modulo Auxiliar hace INSERT directo en una tabla Core que no esta activa para esa empresa, el resultado es incoherente o un error en tiempo de ejecucion.

Ademas, si un modulo Auxiliar escribe directamente en tablas Core, se crea un acoplamiento fuerte que hace imposible desactivar un modulo Core sin romper los Auxiliares que dependen de el.

---

## Decision

Se implementa un **Module Service Bus** como schema PostgreSQL `module_bus` con funciones gateway que actuan como intermediarios entre modulos.

### Patron

```sql
-- Ejemplo: un modulo Auxiliar quiere crear un movimiento en un modulo Core
-- En lugar de INSERT directo en la tabla del Core:

SELECT module_bus.<modulo_core>.create_operation(
  p_empresa_id  := empresa_id,
  p_tipo        := 'TIPO',
  p_referencia  := referencia_id
);

-- La funcion gateway verifica si el modulo Core esta activo:
-- Si activo → ejecuta el INSERT y retorna el ID del registro creado
-- Si no activo → retorna NULL sin error (NO-OP)
```

### Estructura del Schema

```sql
-- Schema dedicado para el bus
CREATE SCHEMA IF NOT EXISTS module_bus;

-- Funciones por modulo Core (patron generico):
module_bus.<modulo_core>.create_<operation>(...)
module_bus.<modulo_core>.get_<resource>(...)
```

### Verificacion de Modulo Activo

Cada funcion gateway internamente verifica:

```sql
CREATE OR REPLACE FUNCTION module_bus.<modulo_core>.create_operation(...)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_modulo_activo BOOLEAN;
BEGIN
  -- Verificar si el modulo Core esta activo para esta empresa
  SELECT EXISTS(
    SELECT 1 FROM modulos_empresa
    WHERE empresa_id = p_empresa_id
      AND modulo_id = '<modulo_core>'
      AND activo = TRUE
  ) INTO v_modulo_activo;

  -- NO-OP si no esta activo
  IF NOT v_modulo_activo THEN
    RETURN NULL;
  END IF;

  -- Logica real de la operacion
  INSERT INTO <tabla_del_modulo> (...) VALUES (...);
  -- ...
END;
$$;
```

---

## Alternativas Rechazadas

### 1. INSERT Directo con Foreign Keys

Los modulos Auxiliares hacen INSERT directo en tablas Core con FK a ellas.

- Requiere que el modulo Core siempre exista en el schema (imposible con modulos desactivables)
- Acoplamiento fuerte: desactivar un modulo Core rompe todos los Auxiliares que escriben en sus tablas
- **Rechazado por**: viola el principio de modulos activables por empresa

### 2. Eventos con Supabase Realtime / Postgres NOTIFY

Los modulos publican eventos en un channel; los Core se suscriben y procesan.

- Asincrono: el modulo Auxiliar no sabe si la operacion fue exitosa antes de continuar
- Complejo de debuggear: la traza de una transaccion queda fragmentada
- Ciertos documentos requieren confirmacion sincrona del numero de documento antes de continuar el flujo
- **Rechazado por**: operaciones criticas de negocio requieren respuesta sincrona

### 3. Triggers en Tablas Auxiliares

Triggers en tablas de modulos Auxiliares que llaman a funciones Core.

- Los triggers son invisibles para el desarrollador que lee el codigo Flutter
- Dificultan el testing unitario
- Pueden dispararse en contextos inesperados (migraciones, seeds)
- **Rechazado por**: opacidad y dificultad de testing

### 4. API REST entre Modulos (microservicios)

Cada modulo Core expone una Edge Function REST que los Auxiliares llaman.

- Latencia adicional por HTTP round-trip para cada operacion
- Complejidad operativa: gestion de autenticacion inter-servicio
- Una transaccion de negocio (ej: confirmar OV) requiere multiples llamadas HTTP → riesgo de inconsistencia parcial
- **Rechazado por**: latencia y riesgo de inconsistencia transaccional

---

## Consecuencias

### Positivas

- Una empresa puede activar un modulo Auxiliar sin todos los modulos Core relacionados — funciona en modo degradado (las operaciones hacia modulos inactivos retornan NULL sin error)
- El schema `module_bus` es el contrato explicito entre modulos — cualquier developer ve exactamente que operaciones estan disponibles
- Las funciones gateway se pueden testear independientemente de la logica de presentacion
- El comportamiento NO-OP evita errores en produccion cuando un modulo no esta activo

### Negativas / Restricciones

- Las funciones gateway son codigo adicional a mantener: cada vez que cambia la firma de una operacion Core, hay que actualizar la funcion gateway
- El comportamiento NO-OP puede confundir si no se documenta: "llame a la funcion gateway y no paso nada" — requiere logging de modulo inactivo
- No es gratuito en performance: cada llamada hace una SELECT a `modulos_empresa` para verificar — mitigado con cache en `private.get_empresa_id()` (ver ADR-003)

---

## Referencias

- ADR-003 — patron RLS (todas las funciones gateway son SECURITY DEFINER)
- ADR-009 — sistema modular (el bus verifica `modulos_empresa.activo` por empresa)
