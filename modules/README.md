# PILAR ERP — Módulos

Cada módulo es una **unidad autocontenida** con su spec (`module.md`), migraciones SQL y Edge Functions propias.

## Estructura por módulo

```
<modulo>/
├── module.md         ← Spec completa: descripción, tablas, RPCs, MSB, flujos
├── migrations/       ← SQL específico del módulo (001_*.sql, 002_*.sql, ...)
├── functions/        ← Edge Functions del módulo (si aplica)
└── *.md              ← Sub-docs de features específicas
```

## 3 Tipos de Módulos

| Tipo | Descripción | Activable |
|------|-------------|-----------|
| **Infraestructura** | Siempre activos, no desactivables | No |
| **Core** | Proveen servicios via Module Service Bus | Sí* |
| **Extensiones** | Consumen servicios, nunca INSERT directo en tablas core | Sí |

*Los módulos Core son activables, pero Foundation + Infraestructura siempre están activos.

---

## Módulos de Infraestructura

| Módulo | Descripción | SQL |
|--------|-------------|-----|
| [administracion](infraestructura/administracion/module.md) | Configuración empresa, branding, usuarios, roles | — |
| [comunicacion](infraestructura/comunicacion/module.md) | Notificaciones multi-canal (Email/WhatsApp/Telegram) | 012 |

---

## Módulos Core

| # | Módulo | Descripción | SQL |
|---|--------|-------------|-----|
| 1 | [entidades](core/entidades/module.md) | Contactos + Productos (maestros compartidos) | 018 |
| 2 | [facturacion](core/facturacion/module.md) | Facturación genérica: ciclo de vida docs, NC, ND, cobros, CxC | 000–002 |
| 3 | [ventas](core/ventas/module.md) | Cotizaciones, órdenes de venta, CxC | 020 |
| 4 | [compras](core/compras/module.md) | Órdenes compra, recepciones, retenciones, CxP | 021 |
| 5 | [inventario](core/inventario/module.md) | Stock, bodegas, movimientos, guías remisión | 022 |
| 6 | [contabilidad](core/contabilidad/module.md) | Asientos, plan de cuentas, periodos, reportes NIIF | 023 |
| 7 | [tesoreria](core/tesoreria/module.md) | Cuentas bancarias, conciliación, cheques, CxC/CxP | 014, 024 |

---

## Módulos de Extensión

| Módulo | Descripción | SQL | Edge Fns |
|--------|-------------|-----|----------|
| [facturacion_ec](extensiones/facturacion_ec/module.md) | SRI Ecuador: establecimientos, firma XAdES-BES, cola electrónica, RIDE PDF, certificado digital | 001–015 | sri-firma-envio, generate-ride, poll-autorizacion |
| [tributacion_ec](extensiones/tributacion_ec/module.md) | ATS mensual, F-103/104/101, RDEP — SRI Ecuador | 013 | generate-ats, generate-declaracion-103/104 |
| [ia](extensiones/ia/module.md) | pgvector, embeddings, chat NLP, forecast | 016 | ai-embed, ai-query, ai-report |
| [pagos-online](extensiones/pagos-online/module.md) | Kushki, Paymentez, PayPhone (adaptador) | 015 | process-payment, webhook-* |
| [citas-belleza](extensiones/citas-belleza/module.md) | Reservas, turnos, App Salón (3 flavors) | 017 | push-notify, booking-reminders |
| [pos](extensiones/pos/module.md) | Punto de venta multi-modo (supermercado/departamental/ferretería) | 001 | — |
| [ecommerce](extensiones/ecommerce/module.md) | WooCommerce + Multi-Marketplace (ML/Shopify/Amazon) | 001 | — |
| [rrhh](extensiones/rrhh/module.md) | Empleados, contratos, nómina IESS/IR, asistencia | 003 | — |
| [crm](extensiones/crm/module.md) | Pipeline oportunidades, actividades, scoring IA | 001 | — |
| [proyectos](extensiones/proyectos/module.md) | Proyectos, tareas, timesheets | 001 | — |
| [activos-fijos](extensiones/activos-fijos/module.md) | Activos, depreciaciones, mejoras, bajas | 002 | — |
| [consumibles](extensiones/consumibles/module.md) | Stock consumibles, solicitudes, entregas | 001 | — |
| [suscripciones](extensiones/suscripciones/module.md) | Contratos recurrentes ISP/gimnasio/SaaS | 001 | — |
| [servicio-de-campo](extensiones/servicio-de-campo/module.md) | Órdenes campo, zonificación GeoJSON, SLA | 001 | — |
| [taller](extensiones/taller/module.md) | Reparaciones físicas, proformas, mano de obra | 001 | — |
| [garantias-rma](extensiones/garantias-rma/module.md) | RMA puente Ventas↔Compras↔Taller | 001 | — |
| [intercompany](extensiones/intercompany/module.md) | Transacciones entre empresas del mismo grupo | 001 | — |

---

## Regla de Módulos Auxiliares

Los módulos de extensión **NUNCA** hacen INSERT directo en tablas de módulos Core. Toda comunicación es via Module Service Bus (`schema module_bus`):

```sql
-- Correcto: via MSB
SELECT module_bus.facturacion.create_invoice(...);
SELECT module_bus.inventario.update_stock(...);

-- Incorrecto: INSERT directo
INSERT INTO facturas (...) VALUES (...);  -- ❌
```

## Agregar un Módulo Nuevo

1. **SQL** (en `modules/<tipo>/<modulo>/migrations/`):
   - `001_tables.sql` — tablas + RLS + índices + `INSERT INTO modulos, modulo_dependencias`
   - `002_seed_permissions.sql` — permisos del módulo + asignaciones a roles del sistema
2. **Directorio**: `modules/<tipo>/<modulo>/module.md` (spec completa del módulo)
3. **Flutter**: clase `<Modulo>Module implements PilarModule` + registro en `ModuleRegistry._allModules`
4. **Sin tocar** código de otros módulos

Ver [ADR-009](../foundation/adrs/ADR-009_sistema-modular.md) para el ciclo de vida completo.
