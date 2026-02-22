# Tarifas SRI — Referencia Tributaria Ecuador

> Catálogo de tarifas de IVA y tasas de retención reconocidas por el SRI. Vigente para el año fiscal 2026.
> Para el procedimiento de actualización ver la sección "Actualización de tarifas".
> Última revisión: 2026-02-18

---

## IVA — Tarifas Vigentes 2026

El SRI reconoce los siguientes códigos de tarifa IVA. El campo `codigo_porcentaje` es el que va en el XML del documento electrónico:

| Código SRI | Tarifa | Descripción | Aplica a |
|-----------|--------|-------------|----------|
| 0 | — | Sin impuesto | Campo vacío; usado en retenciones y documentos sin IVA |
| 2 | 0% | Tarifa cero | Bienes y servicios gravados con tarifa 0% según la LRTI |
| 4 | 15% | Tarifa general | Bienes y servicios gravados (tarifa vigente desde 2024) |
| 5 | 5% | Tarifa reducida | Bienes de primera necesidad ampliados (aplicable desde 2024) |
| 6 | Exento | Exento de IVA | Bienes y servicios expresamente exonerados por ley |
| 7 | No objeto | No objeto de IVA | Transacciones que por su naturaleza no constituyen hecho generador del IVA |
| 8 | 0% diferenciado | Régimen especial | Galápagos, zonas francas, regímenes especiales |

### Contexto histórico de tasas IVA en Ecuador

| Período | Tasa | Evento |
|---------|------|--------|
| Hasta dic. 2023 | 12% | Tasa general histórica |
| Ene. 2024 | 13% | Incremento temporal aprobado por Asamblea Nacional |
| Abr. 2024 en adelante | 15% | Tasa general vigente (Ley Orgánica de Eficiencia Económica y Generación de Empleo) |
| 2024 en adelante | 5% | Nueva tarifa reducida para bienes de primera necesidad |

> PILAR soporta cambios históricos de tarifa a través de `vigente_desde` / `vigente_hasta` en `catalogo_tarifas_iva`. Al consultar la tarifa correcta para una fecha de transacción, siempre se usa la tarifa vigente en esa fecha.

### Bienes y servicios con tarifa 0% (principales)

- Productos alimenticios de primera necesidad (leche, arroz, azúcar, pan, etc.)
- Medicamentos y productos farmacéuticos
- Insumos agrícolas, semillas, abonos, pesticidas
- Exportaciones de bienes y servicios
- Servicios de educación
- Servicios de salud
- Transporte terrestre de pasajeros y carga
- Importaciones de equipos y maquinaria destinados a producción

### Bienes con tarifa 5% (desde 2024)

- Servicios de construcción de vivienda de interés social
- Alimentos y bebidas preparadas (restaurantes con precio regulado)
- Animales vivos de producción
- Aceite de palma, manteca vegetal
- *(Lista definida en el Reglamento a la LRTI — verificar vigencia actual)*

---

## Retención IVA — Tasas Vigentes 2026

Los agentes de retención deben retener IVA según los siguientes porcentajes:

| Porcentaje | Código | Se aplica en |
|-----------|--------|--------------|
| 10% | — | Servicios prestados por medios de comunicación |
| 20% | — | Servicios y bienes en general prestados por no residentes sin establecimiento permanente |
| 30% | — | Compra de bienes muebles de naturaleza corporal a contribuyentes que no son agentes de retención |
| 70% | — | Prestación de servicios en general por contribuyentes que no son agentes de retención |
| 100% | — | Servicios profesionales; contratos de obra; honorarios; arrendamientos; agentes de retención que paguen a otros agentes de retención |

> Los porcentajes de retención IVA aplican sobre el valor del IVA, no sobre la base imponible. Ejemplo: si el IVA es $15 y la retención es 30%, se retienen $4.50.

---

## Retención en la Fuente IR — Tasas Vigentes 2026

El Reglamento para la Aplicación de la LRTI establece los siguientes porcentajes de retención del Impuesto a la Renta (sobre el valor del pago, no del IVA):

### Por tipo de pago

| Código SRI | Concepto | % Retención |
|-----------|----------|-------------|
| 303 | Honorarios profesionales (abogados, médicos, ingenieros, etc.) | 10% |
| 304 | Servicios predomina intelecto (consultores, diseñadores, etc.) | 8% |
| 307 | Servicios en los que predomina la mano de obra | 2% |
| 308 | Utilización o aprovechamiento de imagen o renombre | 10% |
| 309 | Servicios de transporte privado de pasajeros o servicio público de carga | 1% |
| 310 | Transferencia de bienes muebles de naturaleza corporal | 1% |
| 312 | Arrendamiento de bienes inmuebles | 8% |
| 319 | Arrendamiento mercantil | 1% |
| 320 | Pagos a compañías de seguros y reaseguros | 1% |
| 322 | Pagos por servicios de medios de comunicación | 1% |
| 323 | Pagos a compañías de telefonía | 1% |
| 327 | Loterías, rifas, apuestas y similares | 15% |
| 332 | Pagos a compañías de aviación y agencias de viaje | 1% |
| 340 | Otras retenciones aplicables a otros porcentajes | Variable |
| 343 | Pagos a trabajadores en relación de dependencia que no tienen RUC | 0% |

### Por tipo de contribuyente receptor

| Tipo de receptor | Concepto | % Retención |
|-----------------|----------|-------------|
| Persona natural no obligada a llevar contabilidad | Servicios en general | 8% |
| Contribuyente especial | Bienes | 1% |
| Contribuyente especial | Servicios | 2% |
| RISE (Régimen Simplificado) | Cualquier pago | 1% |
| Sociedad con sede en paraíso fiscal | Cualquier pago | 25% |

> **Importante**: las tasas de retención IR pueden variar según el tipo de pago, el tipo de contribuyente emisor/receptor y la actividad económica. Siempre verificar con la tabla oficial del SRI actualizada para el año fiscal vigente.

---

## Retención IR por Relación de Dependencia

Los empleadores actúan como agentes de retención del IR de sus empleados en relación de dependencia:

| Fracción básica anual | Fracción excedente | % sobre excedente |
|----------------------|-------------------|-------------------|
| $0 — $11,722 | $0 | 0% |
| $11,722 — $14,934 | $11,722 | 5% |
| $14,934 — $19,921 | $14,934 | 10% |
| $19,921 — $26,566 | $19,921 | 12% |
| $26,566 — $39,849 | $26,566 | 15% |
| $39,849 — $53,132 | $39,849 | 20% |
| $53,132 — $79,698 | $53,132 | 25% |
| $79,698 — $106,264 | $79,698 | 30% |
| En adelante | $106,264 | 35% |

*(Tabla referencial 2024 — verificar tabla actualizada para 2026 en el portal del SRI)*

En PILAR el módulo RRHH calcula la retención mensual y genera el RDEP anual. Ver `docs/modulos/rrhh/nomina-ecuador.md`.

---

## Procedimiento para actualizar tarifas SRI

Cuando el SRI emite una resolución que modifica tarifas, seguir este procedimiento:

### Paso 1: Verificar la resolución oficial

- Consultar el Registro Oficial en `https://www.registroficial.gob.ec`
- Identificar la fecha de vigencia de la nueva tarifa
- Documentar el número de resolución y registro oficial

### Paso 2: Actualizar la documentación

Modificar este archivo (`docs/datos-referencia/tarifas-sri.md`) con:
- La nueva tarifa en la tabla correspondiente
- El contexto histórico actualizado
- La fecha de vigencia correcta

### Paso 3: Crear la migración SQL

```sql
-- supabase/migrations/NNN_actualizar_tarifas_YYYY.sql
-- Referencia: [Número de resolución SRI] (Registro Oficial No. XXXX del DD/MM/YYYY)
-- Vigencia: a partir del DD/MM/YYYY

-- Cerrar tarifa anterior
UPDATE catalogo_tarifas_iva
SET vigente_hasta = '[YYYY-MM-DD anterior a la nueva vigencia]'
WHERE codigo_sri = '[codigo]'
  AND vigente_hasta IS NULL;

-- Insertar nueva tarifa
INSERT INTO catalogo_tarifas_iva
    (codigo_sri, descripcion, porcentaje, tipo, vigente_desde, vigente_hasta, notas)
VALUES
    ('[codigo]', '[descripcion]', [porcentaje], 'IVA', '[YYYY-MM-DD]', NULL,
     'Ref: Resolución NAC-XXXX del SRI');
```

### Paso 4: Aplicar la migración

```bash
# En entorno local (verificar primero)
supabase db push

# Verificar que la migración aplicó correctamente
supabase db lint
```

### Paso 5: Actualizar parámetros de la aplicación

Si la tarifa impacta la lógica de cálculo de XML (ej. cambio de código de porcentaje en el XSD del SRI), actualizar también:
- La Edge Function `generate-invoice` (campo `<codigoPorcentaje>`)
- Las validaciones de XSD en `supabase/functions/_shared/sri-validators.ts`

---

## SQL Seed Data

Datos iniciales que se cargan al crear una nueva empresa. Se llaman desde `private.initialize_empresa(empresa_id)`:

```sql
-- Función de seed para tarifas IVA (vigentes a la fecha de creación de la empresa)
CREATE OR REPLACE FUNCTION private.seed_tarifas_iva(p_empresa_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    -- Las tarifas IVA son globales (sin empresa_id) y se consultan por vigencia
    -- No es necesario insertar por empresa — se lee desde catalogo_tarifas_iva global
    -- Esta función existe para extensibilidad (configuraciones específicas futuras)
    NULL;
END;
$$;

-- Tabla de catálogo global de tarifas IVA
CREATE TABLE IF NOT EXISTS catalogo_tarifas_iva (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo_sri      VARCHAR(5)      NOT NULL,   -- Código del SRI para el XML
    descripcion     TEXT            NOT NULL,
    porcentaje      DECIMAL(5,2)    NOT NULL,
    tipo            VARCHAR(10)     NOT NULL CHECK (tipo IN ('IVA', 'ICE', 'IRBPNR')),
    vigente_desde   DATE            NOT NULL,
    vigente_hasta   DATE,                       -- NULL = vigente indefinidamente
    notas           TEXT,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    CONSTRAINT catalogo_tarifas_iva_unique UNIQUE (codigo_sri, vigente_desde)
);

-- Seed inicial: tarifas IVA vigentes 2024-2026
INSERT INTO catalogo_tarifas_iva
    (codigo_sri, descripcion, porcentaje, tipo, vigente_desde, vigente_hasta, notas)
VALUES
    ('0', 'Sin impuesto',         0.00, 'IVA', '2007-12-29', NULL,
        'Campo vacío en XML; usado en retenciones'),
    ('2', 'IVA 0%',               0.00, 'IVA', '2007-12-29', NULL,
        'Bienes y servicios gravados con tarifa 0%'),
    ('4', 'IVA 12%',             12.00, 'IVA', '2007-12-29', '2023-12-31',
        'Tarifa general hasta dic 2023'),
    ('4', 'IVA 13%',             13.00, 'IVA', '2024-01-01', '2024-03-31',
        'Incremento temporal Ley Org. Eficiencia Económica'),
    ('4', 'IVA 15%',             15.00, 'IVA', '2024-04-01', NULL,
        'Tarifa general vigente desde abr 2024'),
    ('5', 'IVA 5%',               5.00, 'IVA', '2024-04-01', NULL,
        'Tarifa reducida bienes primera necesidad desde 2024'),
    ('6', 'Exento de IVA',        0.00, 'IVA', '2007-12-29', NULL,
        'Bienes y servicios expresamente exonerados por ley'),
    ('7', 'No objeto de IVA',     0.00, 'IVA', '2007-12-29', NULL,
        'Transacciones que no constituyen hecho generador del IVA'),
    ('8', 'IVA 0% diferenciado',  0.00, 'IVA', '2007-12-29', NULL,
        'Galápagos, zonas francas y regímenes especiales')
ON CONFLICT (codigo_sri, vigente_desde) DO NOTHING;


-- Tabla de catálogo global de tasas de retención
CREATE TABLE IF NOT EXISTS catalogo_tasas_retencion (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tipo            VARCHAR(5)      NOT NULL CHECK (tipo IN ('IR', 'IVA')),
    codigo_sri      VARCHAR(10)     NOT NULL,   -- Código del SRI (ej. '303')
    concepto        TEXT            NOT NULL,
    porcentaje      DECIMAL(5,2)    NOT NULL,
    aplica_a        TEXT,                       -- Descripción del sujeto de retención
    vigente_desde   DATE            NOT NULL,
    vigente_hasta   DATE,
    notas           TEXT,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    CONSTRAINT catalogo_tasas_retencion_unique UNIQUE (tipo, codigo_sri, vigente_desde)
);

-- Seed inicial: retención IVA vigente 2026
INSERT INTO catalogo_tasas_retencion
    (tipo, codigo_sri, concepto, porcentaje, aplica_a, vigente_desde)
VALUES
    ('IVA', 'RIV_20',  'Retención IVA 20%',  20.00,
        'Servicios de medios de comunicación',
        '2024-01-01'),
    ('IVA', 'RIV_30',  'Retención IVA 30%',  30.00,
        'Bienes muebles de nat. corporal (contribuyente no agente de retención)',
        '2024-01-01'),
    ('IVA', 'RIV_70',  'Retención IVA 70%',  70.00,
        'Prestación de servicios generales (contribuyente no agente de retención)',
        '2024-01-01'),
    ('IVA', 'RIV_100', 'Retención IVA 100%', 100.00,
        'Servicios profesionales / arrendamientos / agentes de retención entre sí',
        '2024-01-01')
ON CONFLICT (tipo, codigo_sri, vigente_desde) DO NOTHING;

-- Seed inicial: retención IR (selección de los más comunes)
INSERT INTO catalogo_tasas_retencion
    (tipo, codigo_sri, concepto, porcentaje, aplica_a, vigente_desde)
VALUES
    ('IR', '303', 'Honorarios profesionales',           10.00,
        'Personas naturales con título de tercer o cuarto nivel',
        '2024-01-01'),
    ('IR', '304', 'Servicios predomina intelecto',       8.00,
        'Consultores, diseñadores, asesores',
        '2024-01-01'),
    ('IR', '307', 'Servicios predomina mano de obra',    2.00,
        'Instalaciones, mantenimiento, limpieza',
        '2024-01-01'),
    ('IR', '309', 'Transporte privado/carga',            1.00,
        'Empresas y personas naturales de transporte',
        '2024-01-01'),
    ('IR', '310', 'Compra de bienes muebles',            1.00,
        'Bienes muebles de naturaleza corporal',
        '2024-01-01'),
    ('IR', '312', 'Arrendamiento bienes inmuebles',      8.00,
        'Personas naturales propietarias de inmuebles',
        '2024-01-01'),
    ('IR', '320', 'Seguros y reaseguros',                1.00,
        'Compañías aseguradoras y reaseguradoras',
        '2024-01-01'),
    ('IR', '322', 'Servicios medios de comunicación',    1.00,
        'Periódicos, radios, televisoras, medios digitales',
        '2024-01-01'),
    ('IR', '340', 'Otras retenciones',                   1.00,
        'Otros conceptos no listados con tarifa general',
        '2024-01-01')
ON CONFLICT (tipo, codigo_sri, vigente_desde) DO NOTHING;
```

---

## Función helper: obtener tarifa vigente

Para obtener la tarifa IVA vigente en una fecha específica:

```sql
-- Obtener porcentaje IVA vigente para un código y fecha
CREATE OR REPLACE FUNCTION public.get_iva_porcentaje(
    p_codigo_sri    VARCHAR,
    p_fecha         DATE DEFAULT CURRENT_DATE
)
RETURNS DECIMAL(5,2)
LANGUAGE sql STABLE SECURITY DEFINER AS $$
    SELECT porcentaje
    FROM catalogo_tarifas_iva
    WHERE codigo_sri = p_codigo_sri
      AND vigente_desde <= p_fecha
      AND (vigente_hasta IS NULL OR vigente_hasta >= p_fecha)
    ORDER BY vigente_desde DESC
    LIMIT 1;
$$;

-- Uso:
-- SELECT get_iva_porcentaje('4', '2024-01-15');  -- Retorna 13.00
-- SELECT get_iva_porcentaje('4', '2024-05-01');  -- Retorna 15.00
-- SELECT get_iva_porcentaje('4');                -- Retorna tarifa del día actual
```

---

## Referencias normativas

| Norma | Descripción | Enlace |
|-------|-------------|--------|
| LRTI | Ley de Régimen Tributario Interno | [SRI Portal](https://www.sri.gob.ec) |
| RLRTI | Reglamento para la Aplicación de la LRTI | [SRI Portal](https://www.sri.gob.ec) |
| Ficha técnica comprobantes | Especificación XSD del SRI | Repositorio del proyecto (`/xsd/`) |
| Tabla retenciones IR | Tabla anual de porcentajes de retención | Portal SRI — actualizar cada enero |
| Tabla IR personas naturales | Tabla de IR por relación de dependencia | Portal SRI — actualizar cada enero |
