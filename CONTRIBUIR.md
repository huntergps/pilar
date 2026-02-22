# Guia para Contribuidores — PILAR ERP

> Documento vivo. Actualizar cuando cambien convenciones o herramientas.

---

## 1. Configuracion del Entorno Local

### Prerequisitos

| Herramienta | Version minima | Verificacion |
|-------------|---------------|--------------|
| Flutter SDK | 3.x | `flutter --version` |
| Dart | 3.x (incluido en Flutter) | `dart --version` |
| Supabase CLI | 1.x | `supabase --version` |
| Docker Desktop | Cualquier version reciente | `docker --version` |
| Git | 2.x | `git --version` |

### Configuracion Inicial

```bash
# 1. Clonar repositorio
git clone <repo-url>
cd pilar

# 2. Iniciar Supabase local (requiere Docker)
supabase start
# Anota las credenciales que imprime: API URL, anon key, service_role key

# 3. Aplicar todas las migraciones
supabase db push

# 4. Validar el schema
supabase db lint

# 5. (Cuando exista el proyecto Flutter)
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs

# 6. Copiar variables de entorno (NO commitear .env)
cp .env.example .env
# Editar .env con las credenciales de Supabase local
```

### Edge Functions en Modo Desarrollo

```bash
# Servir una Edge Function localmente (hot reload)
supabase functions serve <nombre-funcion> --env-file .env

# Ver logs en tiempo real
supabase functions logs <nombre-funcion>
```

### Ejecutar Tests

```bash
# Tests unitarios Flutter
flutter test

# Tests de integracion Flutter
flutter test integration_test/

# Lint de la base de datos
supabase db lint
```

---

## 2. Estructura de Branches

```
main              ← produccion (protegida, solo merge via PR)
develop           ← integracion (rama base para features)
feature/<nombre>  ← nueva funcionalidad
bugfix/<nombre>   ← correccion de bug en develop
hotfix/<nombre>   ← correccion urgente directamente sobre main
```

### Reglas

- `main` y `develop` estan protegidas: no se puede hacer push directo
- Toda rama parte de `develop`, excepto `hotfix/*` que parte de `main`
- Los `hotfix/*` se mergean a `main` Y a `develop` al terminar
- Nombre de rama en `kebab-case`, en español, descriptivo

### Ejemplos de Nombres de Rama

```
feature/modulo-suscripciones
feature/pos-modo-ferreteria
bugfix/rls-facturas-proveedor
hotfix/sri-timeout-soap
```

---

## 3. Convenciones de Codigo

### 3.1 Flutter / Dart

- **Archivos**: `snake_case.dart`
- **Clases**: `PascalCase`
- **Variables y funciones**: `camelCase`
- **Constantes**: `kNombreConstante` (prefijo `k`)
- Longitud maxima de linea: 120 caracteres
- Usar `const` siempre que sea posible
- **NUNCA** llamar a Supabase directamente desde widgets — siempre via Brick repository o Riverpod providers

```dart
// CORRECTO — via repository
final facturas = await ref.read(facturasRepositoryProvider).get(
  Query.where('empresa_id', empresaId),
);

// INCORRECTO — llamada directa
final facturas = await supabase.from('facturas').select().eq('empresa_id', empresaId);
```

- Modelos Brick decorados con `@ConnectOfflineFirstWithSupabase`
- Providers Riverpod globales en `lib/core/providers/`, locales en `lib/features/<modulo>/providers/`
- Screens bajo `lib/features/<modulo>/screens/`
- Widgets reutilizables del modulo bajo `lib/features/<modulo>/widgets/`
- Widgets del core bajo `lib/core/widgets/`

### 3.2 SQL / PostgreSQL

- **Tablas**: `snake_case`, plural (`facturas`, `ordenes_venta`)
- **Columnas**: `snake_case` (`empresa_id`, `created_at`)
- **Funciones RPC**: `snake_case`, verbo primero (`get_sales_summary`, `create_journal_entry`)
- **Indices**: `idx_<tabla>_<columna(s)>` (`idx_facturas_empresa_estado`)
- **Constraints**: `chk_<tabla>_<descripcion>`, `fk_<tabla>_<referencia>`, `uq_<tabla>_<campo>`

Patron RLS obligatorio para todas las tablas:

```sql
-- Habilitar RLS
ALTER TABLE <tabla> ENABLE ROW LEVEL SECURITY;

-- Policy de SELECT (usar funcion cacheada, NO parsear JWT inline)
CREATE POLICY "<tabla>_empresa_select" ON <tabla>
  FOR SELECT TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()));

-- Policy de INSERT
CREATE POLICY "<tabla>_empresa_insert" ON <tabla>
  FOR INSERT TO authenticated
  WITH CHECK (empresa_id = (SELECT private.get_empresa_id()));

-- Policy de UPDATE
CREATE POLICY "<tabla>_empresa_update" ON <tabla>
  FOR UPDATE TO authenticated
  USING (empresa_id = (SELECT private.get_empresa_id()))
  WITH CHECK (empresa_id = (SELECT private.get_empresa_id()));
```

Precision numerica obligatoria:

```sql
-- CORRECTO
monto       DECIMAL(14,2)   -- montos monetarios
cantidad    DECIMAL(18,6)   -- cantidades de productos

-- INCORRECTO — nunca usar float para valores financieros
monto       FLOAT
```

### 3.3 Edge Functions (Deno / TypeScript)

- **Archivos**: `kebab-case` (`generate-ats.ts`, `sign-invoice.ts`)
- Importar con `jsr:@supabase/functions-js/edge-runtime.d.ts`
- Variables de entorno via `Deno.env.get('VARIABLE')`, nunca hardcodeadas
- Validar Content-Type en el request antes de procesar
- Retornar errores con HTTP status apropiado (400, 401, 422, 500)
- Logging: `console.log` para info, `console.error` para errores — Supabase los captura

```typescript
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }
  // ... logica
});
```

---

## 4. Estandar de Documentacion de Modulos

Todo archivo `docs/modulos/<modulo>/<modulo>.md` debe incluir las siguientes secciones en este orden:

1. **Titulo y descripcion corta** — una linea
2. **Indice** — links a sub-secciones con `#ancla`
3. **Navegacion de Pantallas** — flujo de pantallas, jerarquia de screens en Flutter
4. **Modelo de Datos** — SQL completo con `CREATE TABLE`, constraints, indices y comentarios
5. **RLS** — policies para todas las tablas del modulo
6. **Funciones RPC** — SQL de cada funcion con descripcion, parametros y ejemplo de uso
7. **Edge Functions** — si aplica, descripcion y contrato (input/output JSON)
8. **Module Service Bus** — si es modulo Core, las funciones gateway que expone; si es Auxiliar, las que consume
9. **Integraciones** — dependencias con otros modulos o servicios externos
10. **Links a sub-modulos** — tabla con links a los archivos de sub-modulos relacionados

Los sub-modulos siguen el mismo estandar, adaptando las secciones que apliquen.

---

## 5. PR Checklist

Antes de abrir un Pull Request, verificar:

### Codigo

- [ ] El codigo compila sin errores (`flutter build web` o equivalente)
- [ ] No hay `print()` o `console.log()` de debug dejados en el codigo
- [ ] No hay credenciales, tokens ni secrets hardcodeados
- [ ] El archivo `.env` no esta siendo commiteado (verificar `.gitignore`)

### Base de Datos

- [ ] Toda tabla nueva tiene `empresa_id` y RLS habilitado
- [ ] Las policies RLS usan `(SELECT private.get_empresa_id())`, no parsing JWT inline
- [ ] Indices creados para columnas usadas en WHERE, JOIN y ORDER BY frecuentes
- [ ] Migraciones nombradas `NNN_descripcion.sql` en orden secuencial
- [ ] Las migraciones existentes NO han sido modificadas (solo agregar nuevas)
- [ ] `supabase db lint` no reporta errores
- [ ] Montos en `DECIMAL(14,2)`, cantidades en `DECIMAL(18,6)` — sin `FLOAT`

### Modulos

- [ ] Modulos Auxiliares usan `module_bus.*` para operaciones en tablas Core (sin INSERT directo)
- [ ] Documentos SRI incluyen campo `version` para bloqueo optimista
- [ ] Cola SRI usada para emision de documentos electronicos (no sincrona)

### Documentacion

- [ ] Si se agrego o modifico un modulo, su archivo `.md` en `docs/modulos/` esta actualizado
- [ ] Si se modifico la arquitectura, `docs/indice.md` y/o `docs/core/arquitectura-modular.md` estan actualizados
- [ ] Si es un cambio arquitectonico significativo, se agrego o actualizo un ADR en `docs/_meta/ADRS/`
- [ ] `docs/_meta/changelog.md` actualizado si corresponde a un cambio de version

### Tests

- [ ] Tests unitarios para logica de negocio nueva
- [ ] Tests de integracion para flujos criticos (SRI, pagos, stock)
- [ ] `flutter test` pasa sin errores

---

## 6. Como Agregar un Modulo Nuevo

Sigue estos pasos en orden. Consulta el archivo `docs/core/arquitectura-modular.md` para contexto.

### Paso 1 — Definir el modulo

1. Determinar el tipo: Auxiliar (lo mas comun para nuevos modulos)
2. Identificar de qué modulos Core depende (via Module Service Bus)
3. Definir las tablas necesarias y sus relaciones
4. Asignar numero de modulo (siguiente al ultimo en `arquitectura-modular.md`)

### Paso 2 — Documentar antes de implementar

```bash
# Crear el directorio de documentacion
mkdir -p docs/modulos/<nombre-modulo>

# Crear el archivo principal siguiendo el estandar (ver seccion 4)
touch docs/modulos/<nombre-modulo>/<nombre-modulo>.md
```

### Paso 3 — Migraciones SQL

```bash
# Crear migracion (numerada secuencialmente)
supabase migration new create_modulo_<nombre>

# La migracion debe incluir:
# 1. CREATE TABLE con empresa_id, timestamps, indices
# 2. ALTER TABLE ENABLE ROW LEVEL SECURITY
# 3. CREATE POLICY para SELECT/INSERT/UPDATE/DELETE
# 4. CREATE FUNCTION para RPCs del modulo
# 5. INSERT INTO modulos (...) para registrar el modulo
```

### Paso 4 — Registrar el modulo

```sql
-- En la migracion, registrar el modulo en la tabla de modulos
INSERT INTO modulos (id, nombre, tipo, descripcion, orden, fase)
VALUES ('<nombre-kebab>', 'Nombre Legible', 'AUXILIAR', 'Descripcion breve', N, N);
```

### Paso 5 — Estructura Flutter

```
lib/features/<nombre_modulo>/
├── screens/
│   ├── <nombre>_list_screen.dart
│   ├── <nombre>_detail_screen.dart
│   └── <nombre>_form_screen.dart
├── providers/
│   ├── <nombre>_provider.dart
│   └── <nombre>_repository_provider.dart
├── widgets/
│   └── <nombre>_card.dart
└── models/           # Si hay logica de dominio extra al modelo Brick
```

### Paso 6 — Modelo Brick

```dart
// lib/core/brick/models/<nombre>.dart
@ConnectOfflineFirstWithSupabase(
  supabaseConfig: SupabaseSerializableField(tableName: '<tabla>'),
)
class NombreModulo extends OfflineFirstWithSupabaseModel {
  // campos...
}
```

Ejecutar generacion de codigo:

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

### Paso 7 — Actualizar documentacion

- Agregar entrada en `docs/indice.md` (tabla de modulos correspondiente)
- Actualizar `docs/core/arquitectura-modular.md` (tabla de modulos, numero actualizado)
- Actualizar `CLAUDE.md` si hay tablas clave nuevas
- Agregar entrada en `docs/_meta/changelog.md`

### Paso 8 — Edge Functions (si aplica)

```bash
supabase functions new <nombre-modulo>-process
supabase functions serve <nombre-modulo>-process --env-file .env
```

### Paso 9 — Activar por empresa (testing)

```sql
-- Activar el modulo para una empresa de prueba
INSERT INTO modulos_empresa (empresa_id, modulo_id, activo)
VALUES ('<empresa-test-uuid>', '<nombre-modulo>', true);
```

---

## 7. Revision de Codigo

### Quienes Aprueban

| Area del Cambio | Revisor Requerido |
|-----------------|------------------|
| Schema SQL / RLS / Migraciones | Arquitecto de Backend |
| Edge Functions SRI / Firma XAdES-BES | Especialista SRI |
| Flutter Core (shell, brick, providers globales) | Arquitecto Flutter |
| Flutter Features (screens, widgets de modulo) | Cualquier senior |
| Documentacion de modulo | Cualquier miembro del equipo |
| ADRs (Architecture Decision Records) | Arquitecto principal |

### Criterios de Aprobacion

- Toda PR requiere al menos 1 aprobacion
- PRs que tocan `supabase/migrations/` o `core/brick/` requieren 2 aprobaciones
- PRs que modifican el pipeline SRI requieren revision del especialista SRI
- Ninguna PR se mergea con checks de CI fallando

### Proceso de Review

1. El autor abre la PR contra `develop` con descripcion clara del cambio
2. El autor asigna revisores segun la tabla de arriba
3. Los revisores comentan en el codigo; el autor responde o corrige
4. Cuando todos aprueban, el autor hace el merge (squash merge preferido para features)
5. La rama se elimina despues del merge

---

## Referencias

- [Indice de Documentacion](../indice.md)
- [Arquitectura Modular](../core/arquitectura-modular.md)
- [Patrones de Arquitectura](../core/arquitectura.md)
- [Seguridad y RLS](../core/seguridad.md)
- [ADRs](ADRS/README.md)
