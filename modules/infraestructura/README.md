# Guía de Módulos PILAR ERP

> Referencia de navegación para los 24 módulos del sistema.
> Para el índice completo con sub-módulos ver `docs/indice.md`.
> Última revisión: 2026-02-18

---

## Los 24 Módulos

### Infraestructura (3) — Siempre activos, no desactivables

| # | Módulo | Archivo | Descripción |
|---|--------|---------|-------------|
| 1 | Dashboard | *(en `lib/core/shell/`)* | KPIs configurables por rol, alertas del sistema, drill-down a detalle |
| 2 | Administración | [administracion/administracion.md](administracion/administracion.md) | Config empresa, usuarios/roles, certificado digital SRI, parametrización tributaria |
| 3 | Comunicación | [comunicacion/comunicacion.md](comunicacion/comunicacion.md) | Realtime WebSocket, chat interno, notificaciones multicanal (email/WhatsApp/Telegram) |

### Core (7) — Proveen servicios vía Module Service Bus

| # | Módulo | Archivo | Descripción |
|---|--------|---------|-------------|
| 4 | Facturación | [facturacion/module.md](../core/facturacion/module.md) | Ciclo de vida de facturas, NC, ND, cobros, CxC. Con `facturacion_ec`: pipeline SRI completo |
| 5 | Ventas | [ventas/ventas.md](../core/ventas/ventas.md) | Cotizaciones, órdenes de venta, CxC, crédito clientes, garantías de venta |
| 6 | Compras | [compras/compras.md](../core/compras/compras.md) | OC, recepciones, facturas proveedor, liquidaciones, retenciones, garantías proveedor |
| 7 | Inventario | [inventario/inventario.md](../core/inventario/inventario.md) | Productos, bodegas, stock multi-bodega, movimientos, series/lotes, BOM |
| 8 | Contabilidad | [contabilidad/contabilidad.md](../core/contabilidad/contabilidad.md) | Plan de cuentas NIIF, asientos, estados financieros, cierre de período |
| 9 | Tesorería | [tesoreria/tesoreria.md](../core/tesoreria/tesoreria.md) | Cuentas bancarias, CxC/CxP, conciliación, cheques, caja chica, pagos online |
| 10 | Tributación | [tributacion/tributacion.md](../core/tributacion/tributacion.md) | ATS, Form 103/104/101, Supercias, RDEP, calendario tributario |

### Auxiliares (14) — Activables por empresa, consumen servicios Core

| # | Módulo | Archivo | Descripción |
|---|--------|---------|-------------|
| 11 | POS | [pos/pos.md](../extensiones/pos/pos.md) | Punto de venta con 3 modos (Supermercado/Departamental/Ferretería), offline |
| 12 | Ecommerce | [ecommerce/ecommerce.md](../extensiones/ecommerce/ecommerce.md) | Tienda online, WooCommerce, MercadoLibre, Shopify, Amazon, portal clientes |
| 13 | RRHH | [rrhh/rrhh.md](../extensiones/rrhh/rrhh.md) | Empleados, nómina IESS/IR, asistencia biométrica, turnos, préstamos |
| 14 | Activos Fijos | [activos-fijos/activos-fijos.md](../extensiones/activos-fijos/activos-fijos.md) | Registro, depreciación NIIF/fiscal, mantenimiento preventivo, bajas |
| 15 | Consumibles | [consumibles/consumibles.md](../extensiones/consumibles/consumibles.md) | Suministros internos: solicitud → aprobación → entrega → egreso → asiento |
| 16 | CRM | [crm/crm.md](../extensiones/crm/crm.md) | Pipeline oportunidades, actividades, campañas, lead scoring, Customer 360 |
| 17 | Proyectos | [proyectos/proyectos.md](../extensiones/proyectos/proyectos.md) | Proyectos, tareas, Gantt, timesheets, presupuesto vs real, costeo |
| 18 | Taller | [taller/taller.md](../extensiones/taller/taller.md) | Reparaciones físicas, proforma, consumo materiales, mano de obra, evidencia |
| 19 | Garantías/RMA | [garantias-rma/garantias-rma.md](../extensiones/garantias-rma/garantias-rma.md) | Módulo puente Ventas↔Compras↔Taller: RMA, resoluciones, scrap |
| 20 | Suscripciones | [suscripciones/suscripciones.md](../extensiones/suscripciones/suscripciones.md) | Contratos recurrentes (ISP/gimnasio/parking/SaaS), facturación automática |
| 21 | Servicio de Campo | [servicio-de-campo/servicio-de-campo.md](../extensiones/servicio-de-campo/servicio-de-campo.md) | Despacho técnicos, zonas GeoJSON, SLA, reportes diarios |
| 22 | Citas/Belleza | [citas-belleza/citas-belleza.md](../extensiones/citas-belleza/citas-belleza.md) | Agenda para salones: servicios, especialistas, recordatorios multicanal |
| 23 | Intercompany | [intercompany/intercompany.md](../extensiones/intercompany/intercompany.md) | Transacciones entre empresas del grupo, documentos espejo, consolidación |
| 24 | IA/Chat | [ia/ia.md](../extensiones/ia/ia.md) | pgvector, embeddings, chat NLP, forecast, detección de anomalías, agentes |

---

## Cómo leer la documentación de un módulo

Cada archivo de módulo sigue una estructura estándar de secciones:

```
1. Descripción          — Propósito, tipo y valor de negocio
2. Dependencias         — Qué módulos requiere y a cuáles provee servicios
3. Navegación           — Rutas go_router y estructura de archivos Flutter
4. Modelo de datos SQL  — CREATE TABLE con constraints, CHECKs y FKs
5. Funciones RPC        — Firmas, descripción y ejemplos de uso
6. Module Service Bus   — Funciones que expone o consume
7. Políticas RLS        — SELECT/INSERT/UPDATE/DELETE por tabla
8. Índices              — Índices de rendimiento
9. Triggers             — Numeración, bloqueo optimista, validaciones
10. Edge Functions      — Si requiere procesamiento server-side
11. Integraciones       — Tabla de integración con otros módulos
12. Sub-módulos         — Links a documentos relacionados
```

Para crear la documentación de un nuevo módulo, copiar `_template.md` y completar cada sección marcada con `[FILL: ...]`.

---

## Cómo agregar un nuevo módulo

1. Decidir la categoría: Infraestructura, Core o Auxiliar (criterio: ¿provee o consume servicios?).

2. Crear el directorio del módulo:
   ```bash
   mkdir docs/infraestructura/[nombre-modulo]/
   ```

3. Copiar la plantilla:
   ```bash
   cp docs/infraestructura/_template.md docs/infraestructura/[nombre-modulo]/[nombre-modulo].md
   ```

4. Completar todas las secciones `[FILL: ...]` en el nuevo archivo.

5. Actualizar `docs/indice.md` — agregar el módulo en la sección correspondiente.

6. Actualizar `docs/infraestructura/README.md` — agregar fila en la tabla del tipo correcto.

7. Actualizar `docs/arquitectura/roadmap.md` — agregar la fase de implementación.

8. Actualizar `CLAUDE.md` — añadir el módulo en la lista de la sección "Módulos".

9. Si el módulo expone servicios (Core), crear las funciones gateway en `module_bus.<modulo>` y documentarlas en `docs/apis/rpcs-por-modulo.md`.

---

## Convenciones de nomenclatura de tablas por módulo

Todas las tablas del sistema siguen estas reglas:

### Reglas generales

- Nombres en `snake_case` plural (ej. `ordenes_venta`, no `orden_venta` ni `OrdenVenta`).
- Siempre incluir `empresa_id UUID NOT NULL` como segundo campo (después de `id`).
- Siempre incluir `created_at` y `updated_at TIMESTAMPTZ`.
- Montos: `DECIMAL(14,2)`. Cantidades: `DECIMAL(18,6)`. Nunca `FLOAT` ni `REAL`.
- Estados: `VARCHAR(20) CHECK (estado IN (...))` con valores en MAYÚSCULAS.
- PKs: `UUID DEFAULT gen_random_uuid()` — nunca `SERIAL` ni `BIGSERIAL`.

### Prefijos por módulo

Los módulos Core usan nombres sin prefijo para sus tablas principales; los módulos Auxiliares pueden prefijar si hay riesgo de colisión:

| Módulo | Prefijo (si aplica) | Ejemplos de tablas |
|--------|---------------------|--------------------|
| Facturación | *(ninguno)* | `facturas`, `factura_lineas`, `notas_credito`, `cola_documentos_electronicos` |
| Ventas | *(ninguno)* | `cotizaciones`, `ordenes_venta`, `ordenes_venta_lineas`, `cuentas_por_cobrar` |
| Compras | *(ninguno)* | `ordenes_compra`, `recepciones_compra`, `facturas_proveedor`, `retenciones` |
| Inventario | *(ninguno)* | `productos`, `bodegas`, `inventario_stock`, `movimientos_inventario` |
| Contabilidad | *(ninguno)* | `asientos_contables`, `cuentas_contables`, `periodos_contables`, `centros_costo` |
| Tesorería | *(ninguno)* | `cuentas_bancarias`, `movimientos_bancarios`, `conciliaciones_bancarias` |
| Tributación | `declaraciones_` | `declaraciones_tributarias`, `configuracion_tributaria` |
| POS | `cajas_`, `sesiones_`, `preventas` | `cajas_pos`, `sesiones_caja`, `preventa_lineas` |
| Ecommerce | `ec_` | `ec_tiendas`, `ec_pedidos`, `ec_marketplace_sync` |
| RRHH | *(ninguno)* | `empleados`, `contratos`, `nominas`, `asistencias`, `prestamos` |
| Activos Fijos | `activos_` | `activos_fijos`, `depreciaciones`, `mantenimientos_activos` |
| Consumibles | `consumibles_` | `consumibles_solicitudes`, `consumibles_entregas` |
| CRM | *(ninguno)* | `oportunidades`, `etapas_pipeline`, `actividades_crm`, `campanas_crm` |
| Proyectos | `proyectos_` | `proyectos`, `proyectos_tareas`, `hojas_tiempo` |
| Taller | *(ninguno)* | `ordenes_reparacion`, `reparacion_materiales`, `reparacion_mano_obra` |
| Garantías/RMA | `solicitudes_` | `solicitudes_rma`, `mermas_garantia` |
| Suscripciones | *(ninguno)* | `planes_suscripcion`, `contratos_suscripcion`, `equipos_cliente` |
| Servicio de Campo | *(ninguno)* | `ordenes_campo`, `zonas_campo`, `sla_campo`, `reportes_diarios_campo` |
| Citas/Belleza | *(ninguno)* | `citas`, `servicios_cita`, `especialistas` |
| Intercompany | `intercompany_` | `grupos_empresariales`, `intercompany_transacciones` |
| IA/Chat | `ia_` | `ia_embeddings`, `ia_conversaciones`, `ia_predictions` |

### Tablas compartidas (Core Foundation)

Estas tablas pertenecen a Core Foundation y son usadas por todos los módulos. **Nunca crear duplicados**:

| Tabla | Usado por |
|-------|-----------|
| `empresas` | Todos |
| `contactos` | Ventas, Compras, RRHH, CRM |
| `contacto_direcciones` | Ventas, Compras, Inventario |
| `productos` | Inventario, Ventas, Compras, POS |
| `producto_presentaciones` | Inventario, Ventas, POS |
| `producto_codigos_barras` | Inventario, POS, Ecommerce |
| `unidades_medida` | Inventario, Taller |
| `listas_precios` | Ventas, POS, Ecommerce |
| `modulos` | Administración (catálogo de módulos disponibles) |
| `modulos_empresa` | Administración (módulos activos por empresa) |
| `usuarios_empresa` | Administración (usuarios con roles por empresa) |
| `audit_log` | Todos (Core Foundation) |
| `adjuntos` | Todos (Core Foundation) |
| `notificaciones` | Todos (Core Foundation) |
