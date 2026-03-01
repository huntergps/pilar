# Testing de PILAR ERP

## Tests de RLS (Row Level Security)

El archivo de tests pgTAP principal se encuentra en:

```
foundation/supabase/migrations/20260228040000_pgtap_rls_tests.sql
```

Adicionalmente, existe una guía de referencia completa con templates y patrones en:

```
foundation/rls-testing-guide.md
```

---

## Por qué son críticos

El aislamiento multi-tenant de PILAR depende exclusivamente de las RLS policies de PostgreSQL. Un fallo de RLS no genera un error visible en la aplicación: simplemente expone datos de una empresa a otra silenciosamente. Las consecuencias incluyen violación de la LOPDP (Ecuador), exposición de información fiscal confidencial y pérdida de confianza de clientes.

**Regla**: toda tabla con `empresa_id` debe tener tests de RLS antes de llegar a producción.

---

## Cómo ejecutar los tests pgTAP

### Entorno local (recomendado para desarrollo)

```bash
# 1. Iniciar Supabase local
cd foundation
supabase start

# 2. Aplicar todas las migraciones (incluyendo los tests)
supabase db push

# 3. Ejecutar el archivo de tests directamente
psql postgresql://postgres:postgres@localhost:54322/postgres \
     -f supabase/migrations/20260228040000_pgtap_rls_tests.sql

# Salida esperada:
# ok 1 - T01.1: RLS habilitado en notificaciones_usuario
# ok 2 - T01.2: RLS habilitado en adjuntos
# ...
# ok 45 - T13.2: Alice NO puede ver la empresa Beta
# 1..45
```

### Ejecutar en el proyecto remoto (Supabase Cloud)

El archivo tiene `BEGIN` y `ROLLBACK` al final, por lo que es seguro aplicarlo vía MCP:

```bash
# Via Supabase CLI apuntando al proyecto remoto
supabase db execute --project-ref bsqhqmmxnfyufozhyszj \
  --file foundation/supabase/migrations/20260228040000_pgtap_rls_tests.sql
```

O vía MCP `apply_migration` con `project_id: bsqhqmmxnfyufozhyszj`.

---

## Qué cubre el archivo de tests

El archivo `20260228040000_pgtap_rls_tests.sql` contiene **45 aserciones** organizadas en 13 grupos:

| Grupo | Tests | Qué verifica |
|-------|-------|--------------|
| T01 (x8) | RLS habilitado | Confirma que las 8 tablas críticas tienen `relrowsecurity = TRUE` en `pg_class` |
| T02 (x3) | `get_empresa_id()` | La función lee correctamente `app_metadata.empresa_id` del JWT simulado; retorna NULL sin JWT |
| T03 (x5) | `notificaciones_usuario` | Aislamiento empresa + usuario: Alice solo ve sus notificaciones, no las de Beta ni las de otro usuario en su mismo tenant |
| T04 (x4) | `adjuntos` | Aislamiento empresa: Alice ve 1 adjunto (Alpha), Bob ve 1 adjunto (Beta), cross-tenant retorna NULL |
| T05 (x4) | `chatter_mensajes` | Aislamiento empresa: cada usuario ve solo los mensajes de su empresa |
| T06 (x4) | `invitaciones_pendientes` | Aislamiento empresa: cada empresa ve solo sus invitaciones |
| T07 (x2) | `usuarios_empresa` | Un usuario ve sus propias membresías; no puede ver las de otro usuario en otra empresa |
| T08 (x2) | INSERT cross-tenant | INSERT con empresa_id ajeno falla con error de RLS; INSERT con empresa_id propio tiene éxito |
| T09 (x2) | UPDATE cross-tenant | UPDATE silencioso: afecta 0 filas si el registro pertenece a otra empresa; afecta 1 fila para el propio |
| T10 (x3) | Sin JWT activo | Sin sesión, las tablas tenant retornan 0 filas (protección anon) |
| T11 (x4) | Patrón get_empresa_id() | Verifica que las policies de 4 tablas críticas usan `private.get_empresa_id()` en su definición |
| T12 (x2) | `configuracion_empresa` | Relación 1:1 con empresa — cada empresa ve solo su configuración |
| T13 (x2) | `empresas` | El usuario solo ve empresas en las que tiene membresía activa |

---

## Estructura del fixture de tests

El archivo crea dos tenants ficticios con UUIDs fijos:

| Entidad | UUID | Rol |
|---------|------|-----|
| Empresa Alpha | `a1a1a1a1-0000-0000-0000-000000000001` | Tenant A |
| Empresa Beta | `b2b2b2b2-0000-0000-0000-000000000002` | Tenant B |
| Usuario Alice | `a1000001-0000-0000-0000-000000000001` | ADMIN en Alpha |
| Usuario Bob | `b2000002-0000-0000-0000-000000000002` | ADMIN en Beta |

La simulación del JWT se hace con `set_config('request.jwt.claims', ...)`, que es el mismo mecanismo que usa PostgREST/Supabase en producción al procesar cada request HTTP.

El archivo termina con `ROLLBACK`, por lo que ningún dato de prueba persiste.

---

## Cómo agregar nuevos tests

### 1. Incrementar el plan

```sql
-- Al inicio del archivo, cambiar el número total de tests:
SELECT plan(45);  -- cambiar a SELECT plan(45 + número_nuevos_tests);
```

### 2. Añadir fixture data (como superuser)

```sql
SET LOCAL ROLE postgres;

INSERT INTO mi_tabla_nueva (id, empresa_id, ...)
VALUES (
    'mifix01-0000-0000-0000-000000000001'::UUID,
    'a1a1a1a1-0000-0000-0000-000000000001'::UUID,  -- Alpha
    ...
) ON CONFLICT (id) DO NOTHING;
```

### 3. Escribir los tests (como authenticated)

```sql
SET LOCAL ROLE authenticated;

-- Aislamiento básico de SELECT
SELECT pilar_test_alice();
SELECT is(
    (SELECT COUNT(*) FROM mi_tabla_nueva)::BIGINT,
    1::BIGINT,
    'TNuevo.1: Alice ve solo registros de Alpha en mi_tabla_nueva'
);

-- Cross-tenant: retorna NULL/0
SELECT is(
    (SELECT id FROM mi_tabla_nueva
     WHERE id = 'mifix_beta...'::UUID),
    NULL::UUID,
    'TNuevo.2: Alice NO puede leer registros de Beta'
);

-- INSERT rechazado (SQLSTATE 42501 = new row violates RLS policy)
-- IMPORTANTE: usar la forma throws_ok(sql, errcode, errmsg, descripcion).
-- throws_ok(sql, text) con 2 args interpreta el 2do arg como errcode o mensaje a comparar,
-- NO como descripción del test. Usar siempre la forma de 4 args:
SELECT throws_ok(
    $$ INSERT INTO mi_tabla_nueva (empresa_id, ...) VALUES ('b2b2b2b2...'::UUID, ...) $$,
    '42501',
    NULL,
    'TNuevo.3: INSERT cross-tenant rechazado por RLS (SQLSTATE 42501)'
);
```

### 4. Verificar el patrón RLS en la migración de la tabla

Antes de agregar tests, asegurarse de que la migración de la tabla tiene:

```sql
ALTER TABLE mi_tabla_nueva ENABLE ROW LEVEL SECURITY;

CREATE POLICY "mi_tabla_nueva_tenant" ON mi_tabla_nueva
    FOR ALL TO authenticated
    USING (empresa_id = (SELECT private.get_empresa_id()))
    WITH CHECK (empresa_id = (SELECT private.get_empresa_id()));
```

Ver el checklist completo en `foundation/rls-testing-guide.md`.

---

## Helpers disponibles

| Función | Descripción |
|---------|-------------|
| `pilar_test_set_jwt(user_id, empresa_id, rol)` | Simula un JWT con los claims dados |
| `pilar_test_alice()` | Activa sesión como Alice en empresa Alpha |
| `pilar_test_bob()` | Activa sesión como Bob en empresa Beta |
| `pilar_test_clear_jwt()` | Limpia el JWT (simula usuario anónimo) |

Estos helpers usan `set_config('request.jwt.claims', ..., TRUE)` (local = TRUE para que el cambio solo aplique a la transacción actual), lo que garantiza que los tests no se contaminen entre sí.

---

## Integración con CI/CD

Ver `foundation/rls-testing-guide.md` para el workflow completo de GitHub Actions que ejecuta los tests en cada PR que modifica migraciones.

---

## Referencias

- `foundation/rls-testing-guide.md` — guía completa de RLS testing con templates
- `foundation/seguridad.md` — modelo de seguridad, roles y multi-tenancy
- `foundation/adrs/ADR-003_rls-pattern.md` — decisión de usar `private.get_empresa_id()`
- `foundation/supabase/migrations/20260101000000_core.sql` — tablas y policies base
- `foundation/supabase/migrations/20260101000001_functions.sql` — implementación de `get_empresa_id()`
- [pgTAP documentation](https://pgtap.org/documentation.html)
- [Supabase RLS Testing Guide](https://supabase.com/docs/guides/database/postgres/row-level-security#testing-rls)
