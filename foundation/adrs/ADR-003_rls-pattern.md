# ADR-003: Patron RLS con Funcion Cacheada private.get_empresa_id()

**Estado**: Aceptado
**Fecha**: 2026-02
**Autores**: Arquitecto principal
**Tags**: seguridad, rls, multi-tenancy, postgresql, performance

---

## Contexto

PILAR es un SaaS multi-tenant: multiples empresas comparten la misma base de datos PostgreSQL en Supabase. Cada empresa debe ver exclusivamente sus propios datos sin posibilidad de acceso cruzado, incluso si el usuario manipula el token JWT.

El aislamiento debe ser:
1. Impereable: no puede haber ninguna ruta de acceso no autorizado, ni por error del desarrollador en el codigo Flutter/Dart
2. Eficiente: con decenas de tablas y cientos de queries por sesion, la verificacion de tenancy no puede ser costosa
3. Consistente: el mismo patron en todas las tablas, sin excepciones ad-hoc que se olviden

Supabase implementa autenticacion via JWT. El `empresa_id` del usuario autenticado esta disponible en el claim del JWT como `app_metadata.empresa_id`.

---

## Decision

Se adopta el patron de **funcion cacheada `private.get_empresa_id()`** para todas las policies RLS de PILAR.

### La Funcion

```sql
-- En schema privado (no expuesto via API REST de Supabase)
CREATE SCHEMA IF NOT EXISTS private;

CREATE OR REPLACE FUNCTION private.get_empresa_id()
RETURNS UUID
LANGUAGE sql
STABLE       -- misma entrada = misma salida dentro de la transaccion
SECURITY DEFINER
AS $$
  SELECT COALESCE(
    (current_setting('request.jwt.claims', true)::jsonb -> 'app_metadata' ->> 'empresa_id')::UUID,
    (current_setting('request.jwt.claims', true)::jsonb ->> 'empresa_id')::UUID
  );
$$;
```

La clausula `STABLE` permite a PostgreSQL cachear el resultado durante la transaccion, evitando el parsing JSON del JWT en cada fila evaluada.

### Patron Obligatorio para Todas las Tablas

```sql
-- Habilitar RLS
ALTER TABLE <tabla> ENABLE ROW LEVEL SECURITY;

-- SELECT (usar subquery SELECT, no llamada directa)
CREATE POLICY "<tabla>_empresa_select" ON <tabla>
  FOR SELECT TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- INSERT
CREATE POLICY "<tabla>_empresa_insert" ON <tabla>
  FOR INSERT TO authenticated
  WITH CHECK (empresa_id = (SELECT private.get_empresa_id()));

-- UPDATE
CREATE POLICY "<tabla>_empresa_update" ON <tabla>
  FOR UPDATE TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()))
  WITH CHECK (empresa_id = (SELECT private.get_empresa_id()));

-- DELETE (cuando aplique)
CREATE POLICY "<tabla>_empresa_delete" ON <tabla>
  FOR DELETE TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));
```

**Punto critico**: siempre usar `(SELECT private.get_empresa_id())` con la subquery wrapping, no `private.get_empresa_id()` directamente. La subquery permite al planner de PostgreSQL cachear el resultado y ejecutarla una sola vez por query en lugar de una vez por fila.

### Tablas de Sistema (sin empresa_id)

Las tablas de sistema que no tienen `empresa_id` (ej: `modulos`, `planes_saas`) usan policies separadas de acuerdo a su naturaleza:

```sql
-- Tabla de solo lectura para todos los usuarios autenticados
CREATE POLICY "modulos_select_all" ON modulos
  FOR SELECT TO authenticated
  USING (true);
```

---

## Alternativas Rechazadas

### 1. Parsing JWT Inline en cada Policy

```sql
-- INCORRECTO — no hacer esto
USING (empresa_id = (auth.jwt() -> 'app_metadata' ->> 'empresa_id')::UUID)
```

- PostgreSQL ejecuta `auth.jwt()` una vez por fila en una SELECT — si una tabla tiene 10,000 registros y la query retorna 100, PostgreSQL evalua la policy 100 veces llamando `auth.jwt()` 100 veces
- `auth.jwt()` parsea el JWT cada vez — O(n) en el numero de filas filtradas
- Con la funcion `STABLE` cacheada, es O(1) por transaccion
- **Rechazado por**: degradacion de performance inaceptable en tablas grandes

### 2. Filtrado en Codigo de Aplicacion (sin RLS)

Los widgets y providers siempre incluyen `.eq('empresa_id', empresaId)` en las queries.

- Un bug o descuido en el codigo Flutter puede omitir el filtro y exponer datos de otras empresas
- Un usuario con acceso directo a la API de Supabase (con su token valido) puede omitir el filtro
- **Rechazado por**: el aislamiento de tenancy no puede depender de disciplina del desarrollador

### 3. Schemas Separados por Empresa

Cada empresa tiene su propio schema PostgreSQL (`empresa_abc.<tabla>`, `empresa_xyz.<tabla>`).

- Escalabilidad problematica: con 1,000 empresas = 1,000 schemas = migraciones ejecutadas 1,000 veces
- Supabase no esta disenado para este patron
- Las queries cross-empresa (ej: analytics del SaaS) requieren UNION sobre todos los schemas
- **Rechazado por**: inmanejable en produccion SaaS

### 4. Base de Datos Separada por Empresa

Cada empresa tiene su propia instancia Supabase.

- Costo prohibitivo en plan inicial
- Actualizaciones de schema requieren coordinar N instancias
- **Rechazado por**: modelo de negocio SaaS requiere multi-tenancy en instancia compartida

---

## Consecuencias

### Positivas

- El aislamiento es garantizado por la base de datos — ninguna falla en el codigo de aplicacion puede filtrar datos entre empresas
- El patron es identico en todas las tablas — cualquier developer puede auditarlo y es imposible "olvidarlo" si se sigue el checklist de PR
- Performance aceptable: el costo de `STABLE` es un solo parsing JWT por transaccion
- Las Edge Functions y RPCs que son `SECURITY DEFINER` omiten RLS por diseno — lo cual es intencional para el Module Service Bus

### Negativas / Restricciones

- Las funciones `SECURITY DEFINER` (incluidas todas las del `module_bus`) no estan sujetas a RLS — el desarrollador es responsable de incluir el filtro `empresa_id` dentro de la logica de la funcion manualmente
- Si se agrega una tabla sin RLS, es una vulnerabilidad silenciosa — el checklist de PR debe verificar esto. El advisor de seguridad de Supabase (`get_advisors`) detecta tablas sin RLS
- La funcion `private.get_empresa_id()` asume que `empresa_id` esta en `app_metadata` del JWT — si cambia la estructura del claim, hay que actualizar la funcion en una migracion

---

## Referencias

- [Supabase RLS docs](https://supabase.com/docs/guides/database/postgres/row-level-security)
- ADR-005 — eleccion de Supabase (RLS nativo es una de las razones)
