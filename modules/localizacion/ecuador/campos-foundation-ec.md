# Campos Ecuador-Specific en Foundation

> Referencia: ADR-006 — Foundation Country-Agnostic
> Ver auditoría completa histórica en `archive/modelo-datos-auditoria-2026-02-20.md`

## Campos en foundation/001_core.sql (Ecuador-first aceptado para v1.0)

Estos campos son Ecuador-specific pero permanecen en foundation porque afectan
comportamiento de múltiples módulos (no solo facturacion_ec):

| Tabla | Campo | Razón para permanecer en foundation |
|-------|-------|-------------------------------------|
| `empresas` | `ruc VARCHAR(13)` | Identificador fiscal primario; en otro país se renombraría |
| `empresas` | `tipo_ruc VARCHAR(20)` | Taxonomía SRI (PERSONA_NATURAL/SOCIEDAD) |
| `configuracion_empresa` | `plan_cuentas VARCHAR(20)` | NIIF_PYMES/NIIF_COMPLETAS regulado por Supercias Ecuador |

## Campos ya movidos a facturacion_ec (ADR-006 compliant)

| Tabla | Campos movidos | Migration |
|-------|---------------|-----------|
| `empresas` | `contribuyente_especial`, `agente_retencion`, `rimpe`, `obligado_llevar_contabilidad` | `facturacion_ec/001_ec_tables.sql` |
| `configuracion_empresa` | `ambiente_sri`, `serie_retencion`, `punto_emision_defecto`, `email_notif_sri` | `facturacion_ec/001_ec_tables.sql` |
| `usuarios_empresa` | `establecimiento_id` | `facturacion_ec/001_ec_tables.sql` |

## Campos Ecuador en módulo entidades (contactos, productos)

Ver `modules/localizacion/ecuador/campos-entidades-ec.md`

## Plan P2: Campos para refactoring futuro

Si PILAR se expande a otro país:
- `empresas.ruc` — renombrar a `tax_id VARCHAR(50)` o hacer nullable
- `empresas.tipo_ruc` — mover a facturacion_ec via ALTER TABLE
- `configuracion_empresa.plan_cuentas` — mover a contabilidad o administracion
- `productos.codigo_iva`, `tarifa_iva`, `codigo_ice`, `aplica_irbpnr` — sistema de posiciones fiscales
- `contactos.tipo_identificacion`, `parte_relacionada`, `consentimiento_datos` — modelos genéricos
