# Guía de Testing de RLS

**Estado**: Referencia canónica — seguir antes de hacer merge de cualquier migración con tablas nuevas
**Relacionado con**: ADR-003, `seguridad.md`, `foundation/adrs/ADR-003_rls-pattern.md`

---

## Por qué testear RLS es crítico

Row Level Security es la única barrera que garantiza el aislamiento entre tenants en PILAR. A diferencia de otros bugs, un fallo de RLS no produce un error visible: simplemente filtra datos de una empresa a otra, silenciosamente.

**Consecuencias de un fallo de RLS**:
- Violación de la Ley Orgánica de Protección de Datos Personales (LOPDP) — Ecuador
- Exposición de información financiera y fiscal confidencial
- Pérdida de confianza de los clientes
- Posible responsabilidad legal del operador del SaaS

**Regla**: toda tabla nueva debe tener tests de RLS antes de llegar a producción. Una tabla sin tests de RLS es un bug no detectado, no código funcional.

---

## Setup de tests con pgTAP

[pgTAP](https://pgtap.org/) es una suite de testing para PostgreSQL que permite escribir tests unitarios directamente en SQL. Supabase lo incluye por defecto en entornos locales.

### Instalar pgTAP en el entorno local Supabase

```bash
# pgTAP ya está disponible en el contenedor PostgreSQL de supabase start
# Verificar:
supabase db diff --use-migra
psql postgresql://postgres:postgres@localhost:54322/postgres -c "SELECT pgtap_version();"
# Debe retornar la versión de pgTAP
```

### Estructura de archivos de test

```
supabase/
└── tests/
    ├── rls/
    │   ├── 00_setup.sql           ← Usuarios y empresas de prueba
    │   ├── 01_contactos_rls.sql   ← Tests RLS para tabla contactos
    │   ├── 02_facturas_rls.sql    ← Tests RLS para tabla facturas
    │   ├── 03_productos_rls.sql   ← Tests RLS para tabla productos
    │   └── ...                    ← Un archivo por tabla sensible
    └── run_rls_tests.sh           ← Script para ejecutar todos los tests
```

### Script para ejecutar tests

```bash
#!/bin/bash
# supabase/tests/run_rls_tests.sh

DB_URL="postgresql://postgres:postgres@localhost:54322/postgres"

echo "=== Ejecutando tests de RLS ==="

# Ejecutar cada archivo de test y recopilar resultados
FAILED=0
for test_file in supabase/tests/rls/*.sql; do
    echo "Ejecutando: $test_file"
    psql "$DB_URL" -f "$test_file" 2>&1 | tee /tmp/pgtap_output.txt

    if grep -q "^not ok" /tmp/pgtap_output.txt; then
        echo "FALLÓ: $test_file"
        FAILED=$((FAILED + 1))
    else
        echo "OK: $test_file"
    fi
done

if [ $FAILED -gt 0 ]; then
    echo "=== $FAILED archivo(s) de test fallaron ==="
    exit 1
else
    echo "=== Todos los tests de RLS pasaron ==="
    exit 0
fi
```

---

## Template de setup: usuarios y empresas de prueba

```sql
-- supabase/tests/rls/00_setup.sql
-- Crea el entorno de pruebas para tests de RLS
-- Se ejecuta antes de todos los demás archivos

BEGIN;

SELECT plan(1);  -- Solo verificar que el setup funciona

-- Crear empresas de prueba si no existen
INSERT INTO empresas (id, ruc, razon_social, estado)
VALUES
    ('11111111-1111-1111-1111-111111111111'::UUID, '1790012345001', 'Empresa Alpha S.A.', 'activa'),
    ('22222222-2222-2222-2222-222222222222'::UUID, '1790054321001', 'Empresa Beta Cía. Ltda.', 'activa')
ON CONFLICT (id) DO NOTHING;

-- Crear usuarios de prueba en auth.users
-- (Supabase Test Helpers o inserción directa en modo local)
INSERT INTO auth.users (id, email, encrypted_password, raw_app_meta_data, raw_user_meta_data)
VALUES
    (
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::UUID,
        'user_alpha@test.pilar',
        crypt('password', gen_salt('bf')),
        jsonb_build_object('empresa_id', '11111111-1111-1111-1111-111111111111', 'rol', 'admin'),
        '{}'::JSONB
    ),
    (
        'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::UUID,
        'user_beta@test.pilar',
        crypt('password', gen_salt('bf')),
        jsonb_build_object('empresa_id', '22222222-2222-2222-2222-222222222222', 'rol', 'vendedor'),
        '{}'::JSONB
    )
ON CONFLICT (id) DO NOTHING;

-- Crear registros en empresa_usuarios
INSERT INTO empresa_usuarios (empresa_id, user_id, rol_id)
VALUES
    ('11111111-1111-1111-1111-111111111111'::UUID, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::UUID, 'admin'),
    ('22222222-2222-2222-2222-222222222222'::UUID, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::UUID, 'vendedor')
ON CONFLICT DO NOTHING;

SELECT ok(TRUE, 'Setup de usuarios y empresas de prueba completado');

SELECT finish();
ROLLBACK;
```

---

## Template de test para aislamiento entre tenants

```sql
-- supabase/tests/rls/01_contactos_rls.sql

BEGIN;

SELECT plan(12);  -- Número total de aserciones en este archivo

-- ================================================================
-- HELPERS: funciones para simular sesión de usuario autenticado
-- ================================================================

-- Simula el JWT de un usuario de la Empresa Alpha
CREATE OR REPLACE FUNCTION set_session_alpha()
RETURNS VOID LANGUAGE SQL AS $$
    SELECT set_config(
        'request.jwt.claims',
        jsonb_build_object(
            'sub',  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
            'role', 'authenticated',
            'app_metadata', jsonb_build_object(
                'empresa_id', '11111111-1111-1111-1111-111111111111',
                'rol', 'admin'
            )
        )::TEXT,
        TRUE  -- Solo para esta transacción
    );
$$;

-- Simula el JWT de un usuario de la Empresa Beta
CREATE OR REPLACE FUNCTION set_session_beta()
RETURNS VOID LANGUAGE SQL AS $$
    SELECT set_config(
        'request.jwt.claims',
        jsonb_build_object(
            'sub',  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
            'role', 'authenticated',
            'app_metadata', jsonb_build_object(
                'empresa_id', '22222222-2222-2222-2222-222222222222',
                'rol', 'vendedor'
            )
        )::TEXT,
        TRUE
    );
$$;

-- Resetear sesión (sin empresa activa)
CREATE OR REPLACE FUNCTION clear_session()
RETURNS VOID LANGUAGE SQL AS $$
    SELECT set_config('request.jwt.claims', '', TRUE);
$$;

-- ================================================================
-- DATOS DE PRUEBA
-- ================================================================

-- Insertar como superuser (bypass RLS para setup)
SET LOCAL ROLE postgres;

INSERT INTO contactos (
    id, empresa_id, tipo_id, numero_id, razon_social, es_cliente, activo
) VALUES
    -- Contactos de Alpha
    ('cc111111-0000-0000-0000-000000000001'::UUID,
     '11111111-1111-1111-1111-111111111111'::UUID,
     '04', '1712345678', 'Cliente Alpha 1', TRUE, TRUE),
    ('cc111111-0000-0000-0000-000000000002'::UUID,
     '11111111-1111-1111-1111-111111111111'::UUID,
     '04', '1798765432', 'Cliente Alpha 2', TRUE, TRUE),
    -- Contacto de Beta
    ('cc222222-0000-0000-0000-000000000001'::UUID,
     '22222222-2222-2222-2222-222222222222'::UUID,
     '04', '1756789012', 'Cliente Beta 1', TRUE, TRUE)
ON CONFLICT (id) DO NOTHING;

-- Cambiar a rol autenticado para los tests
SET LOCAL ROLE authenticated;

-- ================================================================
-- TESTS DE SELECT (aislamiento de lectura)
-- ================================================================

-- Test 1: Usuario Alpha solo ve contactos de Alpha
SELECT set_session_alpha();
SELECT is(
    (SELECT COUNT(*) FROM contactos),
    2::BIGINT,
    'Usuario Alpha ve exactamente 2 contactos (solo los de su empresa)'
);

-- Test 2: Usuario Alpha NO ve contactos de Beta
SELECT is(
    (SELECT COUNT(*) FROM contactos
     WHERE empresa_id = '22222222-2222-2222-2222-222222222222'::UUID),
    0::BIGINT,
    'Usuario Alpha NO puede ver contactos de la Empresa Beta'
);

-- Test 3: Usuario Beta solo ve contactos de Beta
SELECT set_session_beta();
SELECT is(
    (SELECT COUNT(*) FROM contactos),
    1::BIGINT,
    'Usuario Beta ve exactamente 1 contacto (solo los de su empresa)'
);

-- Test 4: Usuario Beta NO ve contactos de Alpha directamente por ID
SELECT is(
    (SELECT razon_social FROM contactos
     WHERE id = 'cc111111-0000-0000-0000-000000000001'::UUID),
    NULL,
    'Usuario Beta NO puede leer un contacto de Alpha por su UUID'
);

-- ================================================================
-- TESTS DE INSERT (aislamiento de escritura)
-- ================================================================

-- Test 5: Usuario Alpha puede insertar contactos en su empresa
SELECT set_session_alpha();
SELECT lives_ok(
    $$
        INSERT INTO contactos (id, empresa_id, tipo_id, numero_id, razon_social, es_cliente, activo)
        VALUES (
            'cc111111-0000-0000-0000-000000000099'::UUID,
            '11111111-1111-1111-1111-111111111111'::UUID,
            '04', '1700000099', 'Contacto Test Insert', TRUE, TRUE
        )
    $$,
    'Usuario Alpha puede insertar contactos en su empresa'
);

-- Test 6: Usuario Alpha NO puede insertar contactos en empresa Beta
SELECT throws_ok(
    $$
        INSERT INTO contactos (id, empresa_id, tipo_id, numero_id, razon_social, es_cliente, activo)
        VALUES (
            'cc999999-0000-0000-0000-000000000001'::UUID,
            '22222222-2222-2222-2222-222222222222'::UUID,
            '04', '1700000099', 'Intento Invasión', TRUE, TRUE
        )
    $$,
    'Usuario Alpha NO puede insertar contactos en empresa Beta'
);

-- ================================================================
-- TESTS DE UPDATE
-- ================================================================

-- Test 7: Usuario Alpha puede actualizar sus propios contactos
SELECT set_session_alpha();
SELECT lives_ok(
    $$
        UPDATE contactos
        SET notas = 'nota actualizada'
        WHERE id = 'cc111111-0000-0000-0000-000000000001'::UUID
    $$,
    'Usuario Alpha puede actualizar sus contactos'
);

-- Test 8: El UPDATE de Alpha no afecta contactos de Beta (0 filas afectadas, sin error)
SELECT set_session_alpha();
SELECT is(
    (
        UPDATE contactos SET notas = 'intento hackeo'
        WHERE id = 'cc222222-0000-0000-0000-000000000001'::UUID
        RETURNING id
    ),
    NULL,
    'UPDATE de Alpha sobre contacto de Beta retorna 0 filas (RLS bloquea silenciosamente)'
);

-- ================================================================
-- TESTS DE DELETE
-- ================================================================

-- Test 9: Usuario Alpha puede eliminar sus propios contactos (si hay policy DELETE)
SELECT set_session_alpha();
SELECT lives_ok(
    $$
        DELETE FROM contactos
        WHERE id = 'cc111111-0000-0000-0000-000000000099'::UUID
    $$,
    'Usuario Alpha puede eliminar sus propios contactos'
);

-- Test 10: DELETE de Alpha sobre contacto de Beta no afecta nada
SELECT set_session_alpha();
SELECT is(
    (
        WITH deleted AS (
            DELETE FROM contactos
            WHERE id = 'cc222222-0000-0000-0000-000000000001'::UUID
            RETURNING id
        ) SELECT COUNT(*) FROM deleted
    ),
    0::BIGINT,
    'DELETE de Alpha sobre contacto de Beta afecta 0 filas'
);

-- ================================================================
-- VERIFICAR QUE RLS ESTÁ HABILITADO EN LA TABLA
-- ================================================================

-- Test 11: RLS está habilitado en la tabla contactos
SELECT ok(
    (SELECT relrowsecurity FROM pg_class WHERE relname = 'contactos'),
    'RLS está habilitado en la tabla contactos'
);

-- Test 12: Existen policies para todas las operaciones CRUD
SELECT is(
    (
        SELECT COUNT(*)
        FROM pg_policies
        WHERE tablename = 'contactos'
          AND schemaname = 'public'
    ),
    4::BIGINT,
    'Existen exactamente 4 policies RLS para contactos (SELECT, INSERT, UPDATE, DELETE)'
);

-- ================================================================
-- CLEANUP y RESULTADO
-- ================================================================

SELECT clear_session();
SELECT finish();

-- Rollback para no contaminar datos de otros tests
ROLLBACK;
```

---

## Casos de prueba obligatorios para cada tabla

Para cada tabla que contenga datos de empresa, verificar:

| # | Caso de prueba | Resultado esperado |
|---|---------------|-------------------|
| 1 | SELECT desde empresa A | Solo ve registros de empresa A |
| 2 | SELECT de registro de empresa B por UUID | Retorna NULL / 0 filas |
| 3 | INSERT con empresa_id de empresa A (siendo usuario A) | Éxito |
| 4 | INSERT con empresa_id de empresa B (siendo usuario A) | Error de RLS |
| 5 | UPDATE de registro propio | Éxito |
| 6 | UPDATE de registro de otra empresa por UUID | 0 filas afectadas (sin error) |
| 7 | DELETE de registro propio | Éxito |
| 8 | DELETE de registro de otra empresa | 0 filas afectadas |
| 9 | RLS habilitado en `pg_class` | `relrowsecurity = TRUE` |
| 10 | Policies existen en `pg_policies` | Al menos SELECT e INSERT |
| 11 | Sin sesión activa (anonymous) | 0 resultados en SELECT |
| 12 | Función `private.get_empresa_id()` retorna empresa correcta | UUID de empresa del JWT |

---

## Cómo testear políticas de permisos basadas en rol

Además del aislamiento por empresa, algunas tablas tienen políticas adicionales por rol:

```sql
-- Test de permisos por rol: solo admin puede borrar
-- (asumiendo policy adicional: DELETE solo para rol admin)

SELECT plan(2);

-- Usuario vendedor NO puede borrar
SELECT set_session_beta();  -- Usuario Beta tiene rol 'vendedor'
SELECT is(
    (
        WITH deleted AS (
            DELETE FROM contactos
            WHERE empresa_id = '22222222-2222-2222-2222-222222222222'::UUID
              AND id = 'cc222222-0000-0000-0000-000000000001'::UUID
            RETURNING id
        ) SELECT COUNT(*) FROM deleted
    ),
    0::BIGINT,
    'Usuario con rol vendedor NO puede eliminar contactos (policy de rol)'
);

-- Usuario admin SÍ puede borrar
SELECT set_session_alpha();  -- Usuario Alpha tiene rol 'admin'
SELECT lives_ok(
    $$
        DELETE FROM contactos
        WHERE empresa_id = '11111111-1111-1111-1111-111111111111'::UUID
          AND id = 'cc111111-0000-0000-0000-000000000002'::UUID
    $$,
    'Usuario con rol admin puede eliminar contactos'
);

SELECT finish();
ROLLBACK;
```

---

## Integrar pgTAP en CI/CD con Supabase CLI

### GitHub Actions workflow

```yaml
# .github/workflows/rls-tests.yml
name: RLS Tests

on:
  pull_request:
    paths:
      - 'supabase/migrations/**'
      - 'supabase/tests/rls/**'

jobs:
  rls-tests:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Setup Supabase CLI
        uses: supabase/setup-cli@v1
        with:
          version: latest

      - name: Start Supabase local
        run: supabase start

      - name: Apply migrations
        run: supabase db push

      - name: Run RLS tests
        run: |
          chmod +x supabase/tests/run_rls_tests.sh
          ./supabase/tests/run_rls_tests.sh

      - name: Stop Supabase local
        run: supabase stop
        if: always()
```

### Ejecutar tests localmente

```bash
# 1. Iniciar entorno local
supabase start

# 2. Aplicar migraciones
supabase db push

# 3. Ejecutar todos los tests de RLS
./supabase/tests/run_rls_tests.sh

# 4. Ejecutar test específico
psql postgresql://postgres:postgres@localhost:54322/postgres \
     -f supabase/tests/rls/01_contactos_rls.sql
```

---

## Lista de verificación mínima antes de hacer merge

Antes de aprobar cualquier PR que incluya tablas nuevas con datos de empresa:

### En la migración SQL

- [ ] `ALTER TABLE <tabla> ENABLE ROW LEVEL SECURITY;` presente
- [ ] Policy `SELECT` con `USING (empresa_id = (SELECT private.get_empresa_id()))` creada
- [ ] Policy `INSERT` con `WITH CHECK (empresa_id = (SELECT private.get_empresa_id()))` creada
- [ ] Policy `UPDATE` con `USING` y `WITH CHECK` creadas
- [ ] Policy `DELETE` creada (o documentada la razón por la que no aplica)
- [ ] Columna `empresa_id UUID NOT NULL` presente en la tabla
- [ ] Índice sobre `(empresa_id, ...)` creado para las queries principales

### En los tests

- [ ] Archivo `supabase/tests/rls/<NNN_tabla_rls.sql>` creado
- [ ] Tests de SELECT (aislamiento entre tenants) pasan
- [ ] Tests de INSERT (no puede insertar en otra empresa) pasan
- [ ] Tests de UPDATE (no puede modificar registros de otra empresa) pasan
- [ ] Test de RLS habilitado en `pg_class` pasa
- [ ] Test de policies existentes en `pg_policies` pasa

### Verificación con el advisor de Supabase

```bash
# Ejecutar el advisor de seguridad después de aplicar migraciones
supabase db push && npx supabase-mcp get_advisors --type security
# No debe haber alertas de "tabla sin RLS" ni "política faltante"
```

---

## Comandos SQL de diagnóstico rápido

```sql
-- Verificar qué tablas NO tienen RLS habilitado
SELECT schemaname, tablename
FROM pg_tables
WHERE schemaname = 'public'
  AND NOT relrowsecurity
FROM pg_class
JOIN pg_tables ON relname = tablename AND schemaname = 'public'
WHERE NOT relrowsecurity;

-- Forma correcta (corrección del query anterior):
SELECT t.tablename
FROM pg_tables t
JOIN pg_class c ON c.relname = t.tablename
WHERE t.schemaname = 'public'
  AND c.relrowsecurity = FALSE
  AND c.relkind = 'r';  -- solo tablas base, no vistas ni secuencias

-- Ver todas las policies de una tabla
SELECT policyname, cmd, qual, with_check
FROM pg_policies
WHERE tablename = 'contactos' AND schemaname = 'public';

-- Verificar que private.get_empresa_id() está en las policies
SELECT tablename, policyname, qual
FROM pg_policies
WHERE schemaname = 'public'
  AND qual LIKE '%get_empresa_id%'
ORDER BY tablename;

-- Tablas con empresa_id pero sin policy de RLS (potencial bug)
SELECT t.tablename
FROM pg_tables t
JOIN pg_class c ON c.relname = t.tablename
JOIN information_schema.columns col ON col.table_name = t.tablename
WHERE t.schemaname = 'public'
  AND col.column_name = 'empresa_id'
  AND col.table_schema = 'public'
  AND c.relrowsecurity = FALSE;
```

---

## Referencias

- `foundation/seguridad.md` — modelo de seguridad completo y roles
- `foundation/adrs/ADR-003_rls-pattern.md` — decisión y patrón de `private.get_empresa_id()`
- [pgTAP documentation](https://pgtap.org/documentation.html)
- [Supabase RLS Testing](https://supabase.com/docs/guides/database/postgres/row-level-security#testing-rls)
