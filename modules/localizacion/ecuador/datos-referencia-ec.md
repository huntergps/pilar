# Datos de Referencia Ecuador — PILAR ERP

> Catálogos y tablas maestras específicas de Ecuador. Forman parte del módulo
> `facturacion_ec` y `tributacion_ec`, no de Foundation genérica (ADR-006).
> Última revisión: 2026-02-20

---

## Catálogos Ecuador (SRI / INEC / BCE)

| Catálogo | Tabla SQL | Módulo propietario | Descripción |
|----------|-----------|-------------------|-------------|
| Formas de pago SRI | `catalogo_formas_pago` | `facturacion_ec` | Efectivo (01), tarjeta (16), transferencia (17), etc. — códigos SRI |
| Tipos de identificación | `tipos_identificacion` | `facturacion_ec` | RUC (04), Cédula (05), Pasaporte (06), Exterior (07), Consumidor Final (08) |
| Provincias del Ecuador | `provincias_ecuador` | `facturacion_ec` | 24 provincias INEC con código de 2 dígitos |
| Cantones | `ciudades_ecuador` | `facturacion_ec` | 222 cantones INEC con código INEC y provincia |
| Actividades económicas CIIU | `actividades_economicas` | `facturacion_ec` | CIIU v4 (para RUC) — usada al registrar empresa |
| Partidas arancelarias NANDINA | `nandina_partidas` | `compras/importaciones` | Para declaración aduanera; ver `modules/core/compras/importaciones.md` |
| Bancos e instituciones financieras | `bancos` | `tesoreria` | 459+ bancos con código SWIFT y código SRI |
| Tarifas IVA vigentes | `catalogo_tarifas_iva` | `facturacion_ec` | Histórico por vigencia; actualmente IVA 15% (2024+) |
| Tasas de retención IR | `catalogo_retencion_ir` | `facturacion_ec` | Porcentajes por tipo de bien/servicio; tabla anual SRI |
| Tasas de retención IVA | `catalogo_retencion_iva` | `facturacion_ec` | 30% / 70% / 100% según tipo de compra |

---

## Inicialización de empresa Ecuador

Cuando `facturacion_ec` está activo, el módulo agrega estos pasos a `private.initialize_empresa()`:

```sql
-- Agregado por facturacion_ec al instalar el módulo
-- (vía su primera migración, no en foundation)

-- Cargar plan de cuentas NIIF PYMES (Supercias Ecuador)
PERFORM create_niif_pymes_chart_of_accounts(p_empresa_id);

-- Cargar tarifas IVA vigentes (SRI)
PERFORM seed_tarifas_iva(p_empresa_id);

-- Cargar tasas de retención vigentes (SRI)
PERFORM seed_tasas_retencion(p_empresa_id);
```

---

## Actualizar tarifas SRI (evento regulatorio)

Cuando el SRI emite una nueva resolución de tarifas, se crea una migración en `facturacion_ec`:

```sql
-- Migración: modules/extensiones/facturacion_ec/migrations/NNN_actualizar_iva_YYYY.sql
-- Referencia: Resolución NAC-DGERCGC24-00000007 del SRI (Registro Oficial No. 509)
-- Vigencia: a partir del 1 de abril de 2026

UPDATE catalogo_tarifas_iva
SET vigente_hasta = '2026-03-31'
WHERE codigo_sri = '4' AND vigente_hasta IS NULL;

INSERT INTO catalogo_tarifas_iva
    (codigo_sri, descripcion, porcentaje, tipo, vigente_desde, vigente_hasta)
VALUES
    ('4', 'IVA 15%', 15.00, 'IVA', '2026-04-01', NULL);
```

> **Regla**: Nunca modificar registros históricos. Usar `vigente_hasta` para cerrar el período
> anterior y `vigente_desde` para abrir el nuevo. Ver patrón genérico en
> [`foundation/datos-referencia/README.md`](../../foundation/datos-referencia/README.md).

---

## Responsables de mantenimiento Ecuador

| Tipo de dato | Organismo fuente | Cuándo actualizar |
|-------------|-----------------|-------------------|
| Tarifas IVA | SRI | Cuando el SRI emita resolución de cambio de tasa |
| Tasas de retención IR/IVA | SRI | Cuando el SRI publique la tabla anual de retenciones |
| Catálogo de bancos | BCE (Banco Central) | Cuando el BCE actualice el catálogo de instituciones |
| Plan de cuentas NIIF | Supercias | Cuando Supercias emita nuevo catálogo de cuentas |
| Formas de pago | SRI | Cuando el SRI agregue nuevas formas de pago electrónico |
| Provincias / cantones | INEC | Cuando INEC modifique la división político-administrativa |
| Partidas NANDINA | SENAE | Cuando SENAE actualice el arancel de importaciones |
| Actividades CIIU | SRI/INEC | Cuando se actualice la clasificación CIIU |

---

## Parámetros tributarios Ecuador

Gestionados en `modules/extensiones/tributacion_ec/migrations/003_seed_parametros_ec.sql`.

| Parámetro | Categoría | Valor 2025 |
|-----------|-----------|-----------|
| `SBU_2025` | LABORAL | 460.00 |
| `APORTE_PERSONAL_IESS` | IESS | 9.45% |
| `APORTE_PATRONAL_IESS` | IESS | 12.15% |
| `FONDOS_RESERVA_PCT` | IESS | 8.33% |
| `IVA_VIGENTE_PCT` | SRI | 15.00% |
| `RETENCION_IVA_30PCT` | SRI | 30.00% |
| `RETENCION_IVA_70PCT` | SRI | 70.00% |
| `RETENCION_IVA_100PCT` | SRI | 100.00% |
| `UMBRAL_LLEVAR_CONTABILIDAD` | SRI | 300000.00 |
| `LIMITE_CONSUMIDOR_FINAL` | SRI | 50.00 |

Ver listado completo en `modules/extensiones/tributacion_ec/migrations/003_seed_parametros_ec.sql`.
