# Campos Ecuador-Specific en Módulo Entidades

> Estos campos están en `modules/core/entidades/` (NO en foundation).
> Son Ecuador-specific pero se aceptan para v1.0 Ecuador-first.

## Tabla `contactos`

| Campo | Tipo | Concepto Ecuador |
|-------|------|-----------------|
| `tipo_identificacion` | `VARCHAR(2)` | Códigos SRI: 04=RUC, 05=Cédula, 06=Pasaporte, 07=Exterior, 08=Placa |
| `parte_relacionada` | `BOOLEAN` | LRTI Art. 4 — empresas vinculadas, precios de transferencia |
| `consentimiento_datos` | `BOOLEAN` | LOPDP (Ley Orgánica Protección Datos Personales, 2021) |
| `fecha_consentimiento` | `TIMESTAMPTZ` | Relacionado con LOPDP |
| `tipo_proveedor` | `VARCHAR(2)` | Códigos SRI para ATS: 01=PN, 02=Sociedad |

## Tabla `productos`

| Campo | Tipo | Concepto Ecuador |
|-------|------|-----------------|
| `codigo_iva` | `VARCHAR(4)` | Código tarifa IVA según catálogo SRI |
| `tarifa_iva` | `DECIMAL(4,2)` | % IVA vigente (15.00 desde abril 2024) |
| `codigo_ice` | `VARCHAR(4)` | ICE — Impuesto Consumos Especiales Ecuador |
| `aplica_irbpnr` | `BOOLEAN` | IRBPNR — Impuesto Botellas Plásticas No Retornables |

## Tabla `producto_presentaciones`

| Campo | Tipo | Concepto Ecuador |
|-------|------|-----------------|
| `codigo_iva` | `VARCHAR(4)` | Hereda código IVA SRI por presentación |
| `tarifa_iva` | `DECIMAL(4,2)` | Hereda tarifa IVA por presentación |

## Plan P2

Reemplazar `codigo_iva` / `tarifa_iva` / `codigo_ice` / `aplica_irbpnr` por sistema de
**posiciones fiscales** (`posicion_fiscal_id UUID → posiciones_fiscales`) genérico.
