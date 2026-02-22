# Auditoría: Campos Ecuador-Specific en Tablas de Foundation

**Fecha**: 2026-02-20
**Autor**: Claude Code (auditoría arquitectónica)
**Referencia**: `foundation/migrations/001_core.sql`, `foundation/modelo-datos.md`
**Marco normativo**: ADR-006 — Foundation Country-Agnostic

---

## 1. Resumen Ejecutivo

La migration `001_core.sql` tiene comentario explícito en su encabezado: _"Foundation — genérico, reutilizable en cualquier país"_. El ADR-006 establece que Foundation (migrations 001-009) debe ser completamente country-agnostic y que todo el compliance Ecuador vive en extensiones activables.

**Hallazgo principal**: La tabla `empresas` contiene **4 campos Ecuador-specific** que representan conceptos fiscales propios del SRI ecuatoriano. La tabla `configuracion_empresa` contiene **3 campos Ecuador-specific** adicionales. La tabla `contactos` (en `modelo-datos.md`, fuera de `001_core.sql`) contiene **5 campos Ecuador-specific**. La tabla `productos` contiene **3 campos Ecuador-specific** de IVA/ICE.

Los campos de certificado digital (`ambiente_sri`, `certificado_*`) ya fueron correctamente movidos al módulo `facturacion_ec` — esto es un acierto del diseño actual.

---

## 2. Inventario de Campos Ecuador-Specific por Tabla

### 2.1 Tabla `empresas` (en `001_core.sql`)

| Campo | Tipo | Valor Default | Concepto Ecuador-Specific |
|-------|------|--------------|--------------------------|
| `ruc` | `VARCHAR(13)` | `'9999999999999'` | RUC (Registro Único de Contribuyentes) es el identificador fiscal de Ecuador. El placeholder `9999999999999` y la validación de 13 dígitos son reglas SRI. En otros países este campo se llama NIT, CUIT, RFC, RUT, etc. con longitudes distintas. |
| `tipo_ruc` | `VARCHAR(20)` | `'SOCIEDAD'` | Los valores `PERSONA_NATURAL \| SOCIEDAD` corresponden a la taxonomía SRI. Otros países usan clasificaciones diferentes. |
| `contribuyente_especial` | `VARCHAR(13)` | `NULL` | Designación del SRI para empresas con facturación alta. Concepto inexistente fuera de Ecuador. El comentario incluso lo define: _"Número de resolución si aplica"_. |
| `agente_retencion` | `BOOLEAN` | `false` | Empresas designadas por el SRI para retener IVA/Renta a proveedores. Concepto fiscal SRI-specific. |
| `rimpe` | `BOOLEAN` | `false` | Régimen MIPYMES del SRI (Microempresas). Ley ecuatoriana vigente desde 2022. Inexistente en otros países. |
| `obligado_llevar_contabilidad` | `BOOLEAN` | `true` | Obligación regulada por la Ley de Régimen Tributario Interno (LRTI) del Ecuador. El SRI define los umbrales de ingresos que obligan a llevar contabilidad. |

**Total campos Ecuador-specific en `empresas`: 6**

> Nota: `ruc` es estructuralmente el campo "identificador fiscal de la empresa" y existe en todos los países (aunque con nombre y longitud diferente). Se incluye en el análisis porque su implementación actual está hardcodeada para las reglas del SRI (13 dígitos, placeholder `9999999999999`).

### 2.2 Tabla `configuracion_empresa` (en `001_core.sql`)

| Campo | Tipo | Valor Default | Concepto Ecuador-Specific |
|-------|------|--------------|--------------------------|
| `plan_cuentas` | `VARCHAR(20)` | `'NIIF_PYMES'` | Los valores `NIIF_PYMES \| NIIF_COMPLETAS` son marcos contables con adopción específica regulada por la Superintendencia de Compañías del Ecuador. Aunque las NIIF son internacionales, los valores hardcodeados y el concepto de "obligado/no obligado" están regulados localmente. |
| `ambiente_sri` | `SMALLINT` | `1` | Literal: `1 = PRUEBAS \| 2 = PRODUCCION` — son los dos ambientes del SRI ecuatoriano. Comentario del código: _"refleja empresas.ambiente_sri como integer"_. El campo almacena configuración del servicio web del SRI. |
| `serie_retencion` | `VARCHAR(10)` | `NULL` | Formato `'001-001'`: serie de numeración para comprobantes de retención SRI (documento electrónico tipo 07). Inexistente fuera de Ecuador. |
| `punto_emision_defecto` | `UUID` | `NULL` | FK a `puntos_emision` (que vive en `facturacion_ec/001_ec_tables.sql`). Concepto exclusivamente SRI. |
| `email_notif_sri` | `TEXT` | `NULL` | Email específico para notificaciones del SRI. El nombre del campo revela el acoplamiento al SRI ecuatoriano. |

**Total campos Ecuador-specific en `configuracion_empresa`: 5**

### 2.3 Tabla `contactos` (en `modelo-datos.md`, módulo `entidades`)

> Nota: `contactos` no está en `001_core.sql` sino en `modules/core/entidades/`. Se incluye en esta auditoría porque `modelo-datos.md` la documenta como parte del modelo de datos central y tiene referencias cruzadas con foundation.

| Campo | Tipo | Concepto Ecuador-Specific |
|-------|------|--------------------------|
| `tipo_identificacion` | `VARCHAR(2)` | Códigos `04-08` son los tipos de identificación del SRI (cédula, RUC, pasaporte, identificación exterior, placa). La numeración y los valores son SRI-specific. |
| `parte_relacionada` | `BOOLEAN` | Concepto tributario ecuatoriano del Reglamento para la Aplicación de la Ley de Régimen Tributario Interno: empresas vinculadas sujetas a precios de transferencia. Aparece en el XML de retenciones. |
| `consentimiento_datos` | `BOOLEAN` | El comentario lo explicita: _"LOPDP Ecuador (Ley Orgánica de Protección de Datos Personales)"_. LOPDP es la ley ecuatoriana promulgada en 2021. Otros países tienen sus propias regulaciones (GDPR, LGPD, etc.) con campos de nombre diferente. |
| `fecha_consentimiento` | `TIMESTAMPTZ` | Relacionado directamente con LOPDP. |
| `tipo_proveedor` | `VARCHAR(2)` | Los valores `01=PN \| 02=Sociedad` son los códigos del SRI para el ATS (Anexo Transaccional Simplificado). |

**Total campos Ecuador-specific en `contactos`: 5**

### 2.4 Tabla `productos` (en `modelo-datos.md`, módulo `entidades`)

| Campo | Tipo | Concepto Ecuador-Specific |
|-------|------|--------------------------|
| `codigo_iva` | `VARCHAR(4)` | Código de tarifa IVA según catálogo SRI (`'4'` = 15%, `'0'` = 0%, etc.). Es la codificación interna del SRI, no un porcentaje directo. |
| `tarifa_iva` | `DECIMAL(4,2)` | Tarifa porcentual que complementa `codigo_iva`. El default `15.00` corresponde a la tarifa IVA vigente en Ecuador desde abril 2024. |
| `codigo_ice` | `VARCHAR(4)` | ICE = Impuesto a los Consumos Especiales del Ecuador (bebidas alcohólicas, cigarrillos, vehículos, etc.). Concepto fiscal exclusivamente ecuatoriano. |
| `aplica_irbpnr` | `BOOLEAN` | IRBPNR = Impuesto Redimible a las Botellas Plásticas No Retornables. Impuesto ambiental ecuatoriano. Concepto inexistente en otros países. |

**Total campos Ecuador-specific en `productos`: 4**

### 2.5 Tabla `producto_presentaciones` (en `modelo-datos.md`)

| Campo | Tipo | Concepto Ecuador-Specific |
|-------|------|--------------------------|
| `codigo_iva` | `VARCHAR(4)` | Idem `productos.codigo_iva` — herencia del código de tarifa SRI por presentación. |
| `tarifa_iva` | `DECIMAL(4,2)` | Idem `productos.tarifa_iva`. |

**Total campos Ecuador-specific en `producto_presentaciones`: 2**

### 2.6 Tabla `usuarios_empresa` (en `001_core.sql`)

| Campo | Tipo | Concepto Ecuador-Specific |
|-------|------|--------------------------|
| `establecimiento_id` | `UUID` | Referencia al establecimiento SRI del usuario. El comentario lo explicita: _"Establecimiento predeterminado (para SRI, POS y filtros de interfaz)"_ y _"afecta numeración SRI"_. Los establecimientos (código de 3 dígitos) son un concepto del SRI ecuatoriano para la numeración de documentos electrónicos. |

**Total campos Ecuador-specific en `usuarios_empresa`: 1**

---

## 3. Resumen Consolidado

| Tabla | Campos EC-Specific | Ubicación Actual |
|-------|-------------------|-----------------|
| `empresas` | 6 (`ruc`, `tipo_ruc`, `contribuyente_especial`, `agente_retencion`, `rimpe`, `obligado_llevar_contabilidad`) | `foundation/migrations/001_core.sql` |
| `configuracion_empresa` | 5 (`plan_cuentas`, `ambiente_sri`, `serie_retencion`, `punto_emision_defecto`, `email_notif_sri`) | `foundation/migrations/001_core.sql` |
| `usuarios_empresa` | 1 (`establecimiento_id`) | `foundation/migrations/001_core.sql` |
| `contactos` | 5 (`tipo_identificacion`, `parte_relacionada`, `consentimiento_datos`, `fecha_consentimiento`, `tipo_proveedor`) | `modules/core/entidades/` |
| `productos` | 4 (`codigo_iva`, `tarifa_iva`, `codigo_ice`, `aplica_irbpnr`) | `modules/core/entidades/` |
| `producto_presentaciones` | 2 (`codigo_iva`, `tarifa_iva`) | `modules/core/entidades/` |

**Total campos Ecuador-specific identificados: 23**

---

## 4. Análisis por Categoría

### Categoría A: Campos que DEFINITIVAMENTE deberían estar en `facturacion_ec`

Estos campos son SRI-API-specific: su existencia es puramente para generar documentos electrónicos XML conforme a las especificaciones técnicas del SRI.

- `configuracion_empresa.ambiente_sri` — ambiente del servicio web SRI (PRUEBAS/PRODUCCION)
- `configuracion_empresa.serie_retencion` — numeración SRI del documento tipo 07
- `configuracion_empresa.punto_emision_defecto` — FK a tabla que vive en `facturacion_ec`
- `configuracion_empresa.email_notif_sri` — notificaciones del SRI

Estos campos no tienen sentido si `facturacion_ec` no está activado. En un país sin SRI, estas columnas nunca se usarían.

### Categoría B: Campos que son "fiscal core" de Ecuador — justificablemente en foundation si PILAR es Ecuador-first

Estos campos representan la identidad tributaria de una empresa ecuatoriana. Son necesarios para el onboarding, el dashboard, y el módulo de Administración — incluso antes de activar `facturacion_ec`.

- `empresas.contribuyente_especial` — afecta las retenciones que recibe la empresa
- `empresas.agente_retencion` — afecta qué retenciones debe emitir
- `empresas.rimpe` — determina tarifa IVA y retenciones aplicables
- `empresas.obligado_llevar_contabilidad` — determina flujos contables completos vs. simplificados
- `empresas.tipo_ruc` — necesario para el onboarding y validación del RUC

### Categoría C: Campos que son "identidad universal" con implementación Ecuador-specific

- `empresas.ruc` — toda empresa tiene un identificador fiscal; la longitud de 13 y el placeholder `9999999999999` son Ecuador-specific
- `contactos.tipo_identificacion` — todo sistema de contactos tiene tipos de identificación; los códigos `04-08` son SRI-specific

### Categoría D: Campos de compliance regulatorio ecuatoriano

- `contactos.consentimiento_datos` y `fecha_consentimiento` — LOPDP Ecuador. Análogos existirían en Europa (GDPR), Brasil (LGPD), etc., pero con campos de nombre diferente
- `contactos.parte_relacionada` — concepto tributario LRTI Ecuador
- `contactos.tipo_proveedor` — códigos SRI para ATS

### Categoría E: Campos de impuestos SRI en tablas de entidades core

- `productos.codigo_iva`, `tarifa_iva`, `codigo_ice`, `aplica_irbpnr`
- `producto_presentaciones.codigo_iva`, `tarifa_iva`

Estos son datos maestros de impuestos del SRI que afectan el cálculo de facturas. En sistemas internacionales se manejarían como "posiciones fiscales" o referencias a tablas de impuestos — no como campos directos en el producto.

---

## 5. Recomendación

### 5.1 Decisión Estratégica: PILAR es Ecuador-first intencionalmente

ADR-006 es claro: **Foundation debe ser country-agnostic**. Sin embargo, la ADR también acepta implícitamente que algunos campos de identidad fiscal básica (como el RUC) son necesarios en `empresas` para el funcionamiento del sistema en Ecuador.

**La recomendación no es mover todos los campos — es clasificarlos y tomar decisiones explícitas.**

### 5.2 Acciones Recomendadas (sin tocar migraciones ya aplicadas)

#### Acción 1: Documentar como "Ecuador-first acceptable" (sin cambios de código)

Los siguientes campos deben quedar documentados como "presentes en foundation porque PILAR es Ecuador-first en v1.0" y su presencia es una deuda técnica conocida si PILAR alguna vez se expande a otro país:

| Campo | Justificación para quedarse en foundation |
|-------|------------------------------------------|
| `empresas.ruc` | Identificador primario de negocio; en otro país se renombraría o haría nullable |
| `empresas.tipo_ruc` | Datos de identidad necesarios para el onboarding |
| `empresas.contribuyente_especial` | Afecta flujos de negocio completos, no solo el SRI |
| `empresas.agente_retencion` | Determina si la empresa emite o recibe retenciones — afecta Ventas, Compras, Contabilidad |
| `empresas.rimpe` | Determina tarifas fiscales de alto impacto en el sistema |
| `empresas.obligado_llevar_contabilidad` | Afecta si Contabilidad opera en modo completo o simplificado |
| `contactos.tipo_identificacion` | Necesario para cualquier documento fiscal; los códigos son SRI-specific |
| `contactos.parte_relacionada` | Afecta retenciones y ATS — impacto en múltiples módulos |

#### Acción 2: Mover a `facturacion_ec` en la próxima iteración de diseño

Cuando sea técnicamente posible (sin romper migraciones aplicadas), estos campos deberían migrar a `facturacion_ec` vía `ALTER TABLE ... ADD COLUMN IF NOT EXISTS`:

| Campo | Destino recomendado |
|-------|-------------------|
| `configuracion_empresa.ambiente_sri` | `facturacion_ec` via ALTER TABLE |
| `configuracion_empresa.serie_retencion` | `facturacion_ec` via ALTER TABLE |
| `configuracion_empresa.punto_emision_defecto` | `facturacion_ec` via ALTER TABLE |
| `configuracion_empresa.email_notif_sri` | `facturacion_ec` via ALTER TABLE |
| `usuarios_empresa.establecimiento_id` | `facturacion_ec` via ALTER TABLE (ya tiene patrón para esto) |

> El patrón `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` en `facturacion_ec/000_shared_deps.sql` ya existe para exactamente este propósito — agregar columnas Ecuador-specific a tablas de foundation.

#### Acción 3: Refactorizar campos de impuestos en productos (diseño P2)

Los campos `codigo_iva`, `tarifa_iva`, `codigo_ice`, `aplica_irbpnr` en `productos` y `producto_presentaciones` deberían reemplazarse en P2 por un sistema de posiciones fiscales genérico:

```sql
-- Diseño futuro country-agnostic:
-- productos.posicion_fiscal_id → posiciones_fiscales (tabla en facturacion_ec o administracion)
-- En lugar de:
-- productos.codigo_iva VARCHAR(4)  -- hardcoded para SRI
-- productos.tarifa_iva DECIMAL(4,2) -- hardcoded para Ecuador
```

Los catálogos de tarifas (`catalogo_tarifas_iva` con `vigente_desde`) ya están definidos en `facturacion_ec` — el plan correcto es hacer que `productos` referencie ese catálogo, no que almacene los valores SRI directamente.

#### Acción 4: Normalizar campos LOPDP en `contactos`

`consentimiento_datos` y `fecha_consentimiento` con el comentario explícito "LOPDP Ecuador" son correctos para Ecuador pero no generalizables. En P2 considerar:

```sql
-- Diseño más genérico:
-- contacto_consentimientos (tabla hija)
--   id, contacto_id, tipo_ley ('LOPDP'|'GDPR'|'LGPD'), consentido BOOLEAN, fecha TIMESTAMPTZ
```

Esto permite agregar compliance de otros países sin modificar la tabla `contactos`.

### 5.3 ¿Tiene sentido moverlos ahora?

**No, por las siguientes razones:**

1. **Las migraciones ya están escritas y posiblemente aplicadas** en entornos de prueba. Modificarlas requiere migraciones adicionales, no edición de las existentes.

2. **El impacto en lógica de aplicación sería extenso**: mover `ambiente_sri` de `configuracion_empresa` a `facturacion_ec` requiere actualizar todas las queries y RPCs que lo referencian (al menos en `background-jobs.md`, triggers de `facturacion_ec`, y el wizard de onboarding).

3. **El sistema de `ALTER TABLE IF NOT EXISTS` ya maneja este caso**: el patrón `facturacion_ec/000_shared_deps.sql` con stubs idempotentes es exactamente el mecanismo correcto para que `facturacion_ec` "reclaime" estos campos cuando esté activo.

4. **PILAR es Ecuador-first en v1.0 por diseño explícito**: el ADR-006 mismo reconoce que Foundation es country-agnostic "desde el inicio", no porque se vaya a desplegar en otro país mañana.

---

## 6. ¿Cuál es la posición arquitectónica correcta?

### Opción A: "PILAR es Ecuador-first, documentar y seguir" (RECOMENDADA para v1.0)

Documentar los 23 campos como "deuda técnica conocida de Ecuador-first" en esta auditoría y en el ADR-006 (como addendum). No mover nada. Cuando PILAR soporte un segundo país, el patrón ya existe: crear `facturacion_XX`, agregar columnas vía ALTER TABLE, reemplazar funciones con `CREATE OR REPLACE FUNCTION`.

**Pros**: cero riesgo de regresión, cero trabajo de refactoring, sistema funciona hoy.

**Contras**: los campos Ecuador-specific en `empresas` y `configuracion_empresa` son visibles en Foundation para cualquier futuro desarrollador que no conozca el contexto.

### Opción B: "Completar el trabajo del ADR-006 para foundation pura" (RECOMENDADA para v2.0)

Mover los campos de Categoría A (`configuracion_empresa.ambiente_sri`, etc.) a `facturacion_ec` vía ALTER TABLE en una migración explícita de refactoring. Esto completa la separación que el ADR-006 ya logró con `ambiente_sri` y `certificado_*` en `empresas`.

**Pros**: coherencia total con ADR-006, Foundation genuinamente country-agnostic.

**Contras**: requiere coordinar con todas las queries que referencian esos campos.

---

## 7. Campos Correctamente Posicionados (aciertos del diseño actual)

Para referencia, los siguientes campos SRI que PODRIAN haber estado en foundation fueron correctamente ubicados en `facturacion_ec`:

| Campo | Ubicación Correcta | Nota |
|-------|-------------------|------|
| `ambiente_sri` (en `empresas`) | `facturacion_ec` via ALTER TABLE | Comentario en `001_core.sql`: "ambiente_sri... están en módulo Facturación Ecuador" |
| `certificado_path` | `facturacion_ec` | El certificado .p12 no pertenece a foundation |
| `certificado_vault_key_id` | `facturacion_ec` | Seguridad del certificado |
| `certificado_vence` | `facturacion_ec` | Gestión operativa del certificado |
| `certificado_activo` | `facturacion_ec` | Estado del certificado |
| `establecimientos` (tabla) | `facturacion_ec/001_ec_tables.sql` | Correctamente separada |
| `puntos_emision` (tabla) | `facturacion_ec/001_ec_tables.sql` | Correctamente separada |
| `secuenciales` (tabla) | `facturacion_ec/001_ec_tables.sql` | Correctamente separada |
| `get_next_sri_sequence()` (función) | `facturacion_ec/001_ec_tables.sql` | Comentario en `001_core.sql`: "movida a facturacion/migrations/001_ec_tables.sql" |

El equipo ya recorrió la mayor parte del camino hacia la separación correcta. Los campos que permanecen en foundation son un conjunto acotado y justificable para un sistema Ecuador-first en v1.0.

---

## 8. Conclusión

El diseño actual de Foundation en PILAR ERP es **correcto para v1.0 de un sistema Ecuador-first**, con algunas inconsistencias menores respecto al ADR-006 que son aceptables como deuda técnica conocida.

**Los campos más problemáticos** (porque no tienen ningún análogo en otros países y accionan directamente la API del SRI) son:
- `configuracion_empresa.ambiente_sri`
- `configuracion_empresa.serie_retencion`
- `configuracion_empresa.email_notif_sri`
- `usuarios_empresa.establecimiento_id`

**Los campos justificablemente en foundation** (porque afectan comportamiento de múltiples módulos, no solo `facturacion_ec`) son:
- `empresas.agente_retencion`
- `empresas.rimpe`
- `empresas.contribuyente_especial`
- `empresas.obligado_llevar_contabilidad`

**Acción inmediata recomendada**: Ninguna. Documentar esta auditoría como referencia para cuando PILAR inicie soporte multi-país. El sistema funciona correctamente para Ecuador hoy.
