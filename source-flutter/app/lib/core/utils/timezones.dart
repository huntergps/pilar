/// Zonas horarias soportadas por PILAR ERP.
///
/// Cada entrada es un par `(id IANA, etiqueta legible)`.
/// El `id` es el valor guardado en base de datos; la `etiqueta` se muestra en UI.
///
/// Uso en ComboBox:
/// ```dart
/// ComboBox<String>(
///   value: zonaHoraria,
///   items: kZonasHorarias
///       .map((z) => ComboBoxItem<String>(value: z.$1, child: Text(z.$2)))
///       .toList(),
///   onChanged: onChanged,
/// )
/// ```
const kZonasHorarias = <(String, String)>[
  // ---- Ecuador ----------------------------------------------------------------
  ('America/Guayaquil',              '(UTC-5) Ecuador — Guayaquil, Quito'),
  ('Pacific/Galapagos',              '(UTC-6) Ecuador — Galápagos'),

  // ---- Colombia ---------------------------------------------------------------
  ('America/Bogota',                 '(UTC-5) Colombia — Bogotá'),

  // ---- Perú -------------------------------------------------------------------
  ('America/Lima',                   '(UTC-5) Perú — Lima'),

  // ---- Panamá -----------------------------------------------------------------
  ('America/Panama',                 '(UTC-5) Panamá'),

  // ---- Venezuela --------------------------------------------------------------
  ('America/Caracas',                '(UTC-4) Venezuela — Caracas'),

  // ---- Bolivia ----------------------------------------------------------------
  ('America/La_Paz',                 '(UTC-4) Bolivia — La Paz'),

  // ---- Paraguay ---------------------------------------------------------------
  ('America/Asuncion',               '(UTC-4/-3) Paraguay — Asunción'),

  // ---- Chile ------------------------------------------------------------------
  ('America/Santiago',               '(UTC-4/-3) Chile — Santiago'),
  ('America/Punta_Arenas',           '(UTC-3) Chile — Punta Arenas'),

  // ---- Argentina --------------------------------------------------------------
  ('America/Argentina/Buenos_Aires', '(UTC-3) Argentina — Buenos Aires'),
  ('America/Argentina/Cordoba',      '(UTC-3) Argentina — Córdoba'),
  ('America/Argentina/Mendoza',      '(UTC-3) Argentina — Mendoza'),

  // ---- Uruguay ----------------------------------------------------------------
  ('America/Montevideo',             '(UTC-3) Uruguay — Montevideo'),

  // ---- Brasil -----------------------------------------------------------------
  ('America/Sao_Paulo',              '(UTC-3/-2) Brasil — São Paulo, Río de Janeiro'),
  ('America/Fortaleza',              '(UTC-3) Brasil — Fortaleza, Recife'),
  ('America/Belem',                  '(UTC-3) Brasil — Belém'),
  ('America/Manaus',                 '(UTC-4) Brasil — Manaos'),
  ('America/Cuiaba',                 '(UTC-4/-3) Brasil — Cuiabá'),
  ('America/Noronha',                '(UTC-2) Brasil — Fernando de Noronha'),

  // ---- Caribe -----------------------------------------------------------------
  ('America/Santo_Domingo',          '(UTC-4) República Dominicana'),
  ('America/Puerto_Rico',            '(UTC-4) Puerto Rico'),
  ('America/Jamaica',                '(UTC-5) Jamaica'),
  ('America/Havana',                 '(UTC-5/-4) Cuba — La Habana'),

  // ---- Centroamérica ----------------------------------------------------------
  ('America/Guatemala',              '(UTC-6) Guatemala'),
  ('America/El_Salvador',            '(UTC-6) El Salvador'),
  ('America/Tegucigalpa',            '(UTC-6) Honduras — Tegucigalpa'),
  ('America/Managua',                '(UTC-6) Nicaragua — Managua'),
  ('America/Costa_Rica',             '(UTC-6) Costa Rica — San José'),
  ('America/Belize',                 '(UTC-6) Belice'),

  // ---- México -----------------------------------------------------------------
  ('America/Mexico_City',            '(UTC-6/-5) México — Ciudad de México'),
  ('America/Cancun',                 '(UTC-5) México — Cancún, Quintana Roo'),
  ('America/Monterrey',              '(UTC-6/-5) México — Monterrey'),
  ('America/Tijuana',                '(UTC-8/-7) México — Tijuana, Baja California'),
  ('America/Mazatlan',               '(UTC-7/-6) México — Mazatlán, Sinaloa'),

  // ---- Estados Unidos ---------------------------------------------------------
  ('America/New_York',               '(UTC-5/-4) EE.UU. — Nueva York (ET)'),
  ('America/Chicago',                '(UTC-6/-5) EE.UU. — Chicago (CT)'),
  ('America/Denver',                 '(UTC-7/-6) EE.UU. — Denver (MT)'),
  ('America/Phoenix',                '(UTC-7) EE.UU. — Phoenix (sin DST)'),
  ('America/Los_Angeles',            '(UTC-8/-7) EE.UU. — Los Ángeles (PT)'),
  ('America/Anchorage',              '(UTC-9/-8) EE.UU. — Alaska'),
  ('Pacific/Honolulu',               '(UTC-10) EE.UU. — Hawái'),

  // ---- Canadá -----------------------------------------------------------------
  ('America/Toronto',                '(UTC-5/-4) Canadá — Toronto, Ottawa'),
  ('America/Vancouver',              '(UTC-8/-7) Canadá — Vancouver'),

  // ---- Europa -----------------------------------------------------------------
  ('Europe/London',                  '(UTC+0/+1) Reino Unido — Londres'),
  ('Europe/Lisbon',                  '(UTC+0/+1) Portugal — Lisboa'),
  ('Europe/Madrid',                  '(UTC+1/+2) España — Madrid'),
  ('Europe/Paris',                   '(UTC+1/+2) Francia — París'),
  ('Europe/Berlin',                  '(UTC+1/+2) Alemania — Berlín'),
  ('Europe/Rome',                    '(UTC+1/+2) Italia — Roma'),
  ('Europe/Amsterdam',               '(UTC+1/+2) Países Bajos — Ámsterdam'),
  ('Europe/Zurich',                  '(UTC+1/+2) Suiza — Zúrich'),

  // ---- UTC --------------------------------------------------------------------
  ('UTC',                            'UTC (sin offset)'),
];
