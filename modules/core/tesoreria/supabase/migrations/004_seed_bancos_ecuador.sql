-- =============================================================================
-- PILAR ERP — Foundation Gap: Catálogo de Bancos Ecuador
-- =============================================================================
-- Tabla de bancos + seed data de instituciones financieras ecuatorianas.
-- Usado por Tesorería, Cobros, Pagos, Conciliación bancaria.
-- =============================================================================

-- ─── 1. Tabla de bancos ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.bancos (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo      VARCHAR(10) UNIQUE NOT NULL,
  nombre      TEXT NOT NULL,
  tipo        TEXT NOT NULL CHECK (tipo IN (
    'banco_privado', 'banco_publico', 'cooperativa', 'mutualista', 'financiera'
  )),
  activo      BOOLEAN NOT NULL DEFAULT TRUE,
  pais_codigo CHAR(2) NOT NULL DEFAULT 'EC',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.bancos IS
  'Catálogo de instituciones financieras. Filtrar por pais_codigo para multi-country.';

-- ─── 2. Indexes ─────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_bancos_pais ON public.bancos(pais_codigo) WHERE activo = TRUE;
CREATE INDEX IF NOT EXISTS idx_bancos_tipo ON public.bancos(tipo) WHERE activo = TRUE;

-- ─── 3. RLS ─────────────────────────────────────────────────────────────────
-- Bancos is a public catalog — no empresa_id needed.
ALTER TABLE public.bancos ENABLE ROW LEVEL SECURITY;

CREATE POLICY "bancos_read_all" ON public.bancos
  FOR SELECT TO authenticated, anon
  USING (true);

-- Only service_role can manage the catalog
CREATE POLICY "bancos_manage_service" ON public.bancos
  FOR ALL TO service_role
  USING (true)
  WITH CHECK (true);

-- ─── 4. Grants ──────────────────────────────────────────────────────────────
GRANT SELECT ON public.bancos TO authenticated, anon;

-- ─── 5. Seed: Bancos del Ecuador ────────────────────────────────────────────
INSERT INTO public.bancos (codigo, nombre, tipo) VALUES
  -- Banco público central
  ('BCE',      'Banco Central del Ecuador',                    'banco_publico'),
  ('BANECUA',  'BanEcuador B.P.',                              'banco_publico'),
  ('CFN',      'Corporación Financiera Nacional B.P.',         'banco_publico'),
  ('BIESS',    'Banco del Instituto Ecuatoriano de Seguridad Social', 'banco_publico'),

  -- Bancos privados grandes
  ('PICHINCHA','Banco del Pichincha',                          'banco_privado'),
  ('GUAYAQUIL','Banco de Guayaquil',                           'banco_privado'),
  ('PACIFICO', 'Banco del Pacífico',                           'banco_privado'),
  ('PRODUBANCO','Produbanco (Grupo Promerica)',                 'banco_privado'),
  ('BOLIVAR',  'Banco Bolivariano',                            'banco_privado'),
  ('INTERNAC', 'Banco Internacional',                          'banco_privado'),

  -- Bancos privados medianos
  ('AUSTRO',   'Banco del Austro',                             'banco_privado'),
  ('SOLIDARIO','Banco Solidario',                              'banco_privado'),
  ('MACHALA',  'Banco de Machala',                             'banco_privado'),
  ('GENERAL',  'Banco General Rumiñahui',                      'banco_privado'),
  ('PROCREDIT','Banco ProCredit',                              'banco_privado'),
  ('AMAZONAS', 'Banco Amazonas',                               'banco_privado'),
  ('COOPNAC',  'Banco Coopnacional',                           'banco_privado'),
  ('CAPITAL',  'Banco Capital',                                'banco_privado'),
  ('LOJA',     'Banco de Loja',                                'banco_privado'),
  ('LITORAL',  'Banco Litoral',                                'banco_privado'),
  ('FINCA',    'Banco Finca',                                  'banco_privado'),
  ('DINERS',   'Diners Club del Ecuador',                      'banco_privado'),
  ('DESARROLLO','Banco de Desarrollo del Ecuador B.P.',        'banco_publico'),

  -- Cooperativas de ahorro y crédito (segmento 1 — las más grandes)
  ('JEP',      'Cooperativa de Ahorro y Crédito JEP',         'cooperativa'),
  ('JARDIN',   'Cooperativa Jardín Azuayo',                    'cooperativa'),
  ('POLICIA',  'Cooperativa de la Policía Nacional',           'cooperativa'),
  ('29OCT',    'Cooperativa 29 de Octubre',                    'cooperativa'),
  ('COOPROG',  'Cooperativa de Ahorro y Crédito Cooprogreso',  'cooperativa'),
  ('OSCUS',    'Cooperativa OSCUS',                            'cooperativa'),
  ('SANBERN',  'Cooperativa San Francisco de Asís',            'cooperativa'),
  ('ALIANZA',  'Cooperativa Alianza del Valle',                'cooperativa'),
  ('CACPE',    'Cooperativa CACPE Biblián',                    'cooperativa'),
  ('ATUNTAQ',  'Cooperativa Atuntaqui',                        'cooperativa'),
  ('TULCAN',   'Cooperativa Tulcán',                           'cooperativa'),
  ('RIOBAMBA', 'Cooperativa Riobamba',                         'cooperativa'),
  ('MUSHUC',   'Cooperativa Mushuc Runa',                      'cooperativa'),
  ('CACPECO',  'Cooperativa CACPECO',                          'cooperativa'),
  ('PNAZAR',   'Cooperativa Pablo Muñoz Vega',                 'cooperativa'),

  -- Mutualistas
  ('MUPICHIN', 'Mutualista Pichincha',                         'mutualista'),
  ('MUAZUAY',  'Mutualista Azuay',                             'mutualista'),
  ('MUIMBAB',  'Mutualista Imbabura',                          'mutualista'),

  -- Financieras
  ('COFIEC',   'COFIEC S.A.',                                  'financiera'),
  ('VAZCORP',  'Visionfund Ecuador (antes Financiera Vazcorp)','financiera')
ON CONFLICT (codigo) DO NOTHING;
