# Modelo de Datos


### Esquema Principal

```sql
-- ============================================
-- MULTI-TENANCY (Foundation — genérico)
-- ============================================

empresas
  id              UUID PK
  ruc             VARCHAR(13) UNIQUE NOT NULL
  nombre          VARCHAR(300) NOT NULL
  nombre_comercial VARCHAR(300)
  -- Dirección fiscal
  provincia_id    INTEGER
  ciudad_id       INTEGER
  direccion       TEXT
  telefono        VARCHAR(20)
  email           VARCHAR(200)
  web             VARCHAR(300)
  -- Branding
  logo_url        TEXT
  color_primario  VARCHAR(7) DEFAULT '#1565C0'
  color_secundario VARCHAR(7) DEFAULT '#0288D1'
  -- SaaS
  plan_id         UUID FK -> planes_suscripcion
  estado          VARCHAR(20) DEFAULT 'TRIAL'  -- TRIAL|ACTIVO|SUSPENDIDO|CANCELADO
  created_at      TIMESTAMPTZ
  updated_at      TIMESTAMPTZ
  -- Los módulos pueden añadir campos adicionales a esta tabla via ALTER TABLE

-- ============================================
-- TABLAS DE MÓDULOS
-- ============================================
-- Las tablas de negocio (contactos, productos, documentos transaccionales,
-- movimientos, etc.) son responsabilidad de cada módulo.
-- Cada módulo define sus propias tablas en sus migraciones bajo:
--   modules/<tipo>/<modulo>/migrations/
--
-- Foundation no conoce ni depende de ninguna tabla de módulo.
-- El aislamiento multi-tenant se aplica mediante el patrón:
--   empresa_id = (SELECT private.get_empresa_id())
-- en todas las policies RLS de cualquier tabla que un módulo defina.
```
