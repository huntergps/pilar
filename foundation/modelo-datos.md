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
-- CORE FOUNDATION (servicios compartidos)
-- Siempre presentes, sin necesidad de activar módulo
-- Migración: 023_alertas_empresa.sql
-- ============================================

alertas_empresa                               -- Alertas persistentes por empresa (≠ notificaciones_usuario efímeras)
  id              UUID PK
  empresa_id      UUID NOT NULL FK -> empresas ON DELETE CASCADE

  -- Origen
  origen_modulo   VARCHAR(60) NOT NULL        -- 'facturacion_ec', 'inventario', 'sistema', …
  codigo_alerta   VARCHAR(100)                -- Clave semántica para deduplicación, ej: 'SRI_CERT_EXPIRING'
                                              -- UNIQUE parcial: (empresa_id, codigo_alerta) WHERE estado='activa'
  registro_id     UUID                        -- Soft ref al registro relacionado (sin FK constraint)

  -- Contenido
  severidad       VARCHAR(20) NOT NULL DEFAULT 'warning'  -- 'info' | 'warning' | 'error' | 'critical'
  titulo          VARCHAR(300) NOT NULL
  cuerpo          TEXT
  datos           JSONB NOT NULL DEFAULT '{}'  -- Metadata extra para el handler (días restantes, importes, etc.)
  accion_url      TEXT                         -- Deep-link opcional para navegar al problema

  -- Visibilidad por rol
  roles_destino   TEXT[]                       -- NULL = visible para todos los roles; ['ADMIN','CONTADOR'] = solo esos

  -- Ciclo de vida: activa → resuelta | ignorada
  estado          VARCHAR(20) NOT NULL DEFAULT 'activa'  -- 'activa' | 'resuelta' | 'ignorada'
  resuelta_por    UUID FK -> auth.users
  resuelta_at     TIMESTAMPTZ
  nota_resolucion TEXT
  expira_at       TIMESTAMPTZ                  -- NULL = no expira; pg_cron expire horario

  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()

  -- Índices:
  --   idx_alertas_empresa_activas: (empresa_id, severidad, created_at DESC) WHERE estado='activa'
  --   idx_alertas_dedup: UNIQUE (empresa_id, codigo_alerta) WHERE estado='activa' AND codigo_alerta IS NOT NULL
  -- Realtime: REPLICA IDENTITY FULL + supabase_realtime publication
  -- pg_cron: pilar_expire_alertas (cada hora) + pilar_cleanup_old_alertas (diario 03:30, retención 1 año)

  -- RPCs: crear_alerta() [SECURITY DEFINER, solo backend]
  --       resolver_alerta(p_alerta_id, p_nota?)
  --       ignorar_alerta(p_alerta_id)
  --       get_alertas_activas(p_limite, p_offset)
  --       get_count_alertas_activas()

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
