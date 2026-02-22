# RESUMEN - PILAR ERP: Informe de Arquitectura y Analisis Tecnico

**Fuente:** `docs/` (81 archivos en 20 modulos, migrado desde INFORME_ERP_PILAR.md v17.0)
**Indice maestro:** `docs/indice.md`
**Ultima actualizacion del resumen:** 2026-02-16

---

## 1. Vision General

**PILAR** es un ERP SaaS diseñado para Ecuador con cumplimiento total del SRI. Se construye sobre una **Capa Base (Core Foundation)** inspirada en Odoo `base` (~90 modelos) y un **Module Service Bus** para comunicacion desacoplada entre modulos.

- **20 modulos**: Dashboard, Administracion, Comunicacion (Infraestructura) + Ventas, Compras, Inventario, Contabilidad, Tesoreria (Core) + POS, Ecommerce, IA/Chat, RRHH, Activos Fijos, Consumibles, CRM, Proyectos, Servicios/Contratos, Garantias/RMA y Taller, Intercompany, **Citas/Belleza** (Auxiliares) — Pagos Online es sub-modulo de Tesoreria
- **6 plataformas**: Web, Windows, macOS, Linux, iOS, Android (un solo codebase Flutter)
- **Dos apps separadas**: PILAR Admin (SaaS, web) + PILAR ERP (clientes, multi-plataforma)
- **Multi-empresa**: Un usuario puede pertenecer a N empresas con roles distintos

> Ver: `docs/resumen-ejecutivo.md`

---

## 2. Cumplimiento SRI Ecuador

### Documentos Electronicos Soportados

| Cod | Documento | Version |
|-----|-----------|---------|
| 01 | Factura | V2.1.0 |
| 03 | Liquidacion de Compra | V1.1.0 |
| 04 | Nota de Credito | V1.1.0 |
| 05 | Nota de Debito | V1.0.0 |
| 06 | Guia de Remision | V1.1.0 |
| 07 | Comprobante de Retencion | V2.0.0 |

### Impuestos y Codigos

- **IVA vigente**: 15% (cod 4), 5% diferenciada (cod 5)
- **Retenciones IVA**: 10%, 20%, 30%, 50%, 70%, 100%
- **Retenciones ISD**: 5% (cod 4580), 2.5% (cod 4586)
- **Formas de pago**: Codigos 01-21
- **Tipos ID**: RUC (04), Cedula (05), Pasaporte (06), Consumidor Final (07), Exterior (08)
- **Sustentos tributarios**: Codigos 01-15
- **ATS**: Declaracion mensual XML (ISO-8859-1, ZIP)
- **Transmision inmediata obligatoria 2026** (multa 30 RBU ~$14,460)

### Proceso de Emision Electronica

1. Generar XML segun XSD → 2. Firmar XAdES-BES (.p12 server-side) → 3. Enviar SOAP al SRI → 4. Consultar autorizacion → 5. Generar RIDE (PDF) → 6. Enviar al cliente (email/WhatsApp/Telegram)

### Clave de Acceso (49 digitos)

Fecha(8) + TipoDoc(2) + RUC(13) + Ambiente(2) + Serie(6) + Secuencial(9) + CodNumerico(8) + DigitoVerificador(1)

> Ver: `docs/regulatorio/sri-requisitos.md`, `docs/regulatorio/documentos-electronicos.md`

---

## 3. Flujos de Negocio Principales

- **Ventas**: Cotizacion → Pedido → Factura XML → Firma → SRI → RIDE → Cobro → Asiento → ATS
- **POS**: Abrir caja → Escanear/buscar → Carrito → Cobrar → Factura auto → Cerrar caja → Reporte Z
- **Compras**: Registrar factura → Validar XML → Retenciones → Firmar → SRI → Pago → ATS
- **Inventario**: Compra → Ingreso bodega → Kardex → Egreso → Despacho + Guia remision
- **Contabilidad**: Cada transaccion genera asientos automaticos (inmutables, correcciones via reverso)
- **ATS**: Cierre mes → Recopilar compras/ventas/anulados → XML → Validar XSD → ZIP

> Ver: `docs/core/flujos-casos-uso.md`

---

## 4. Actores y Casos de Uso

**10 actores**: Administrador, Vendedor, Facturador, Comprador, Contador, Bodeguero, Cajero, Gerente, SRI (externo), WooCommerce (externo)

**Casos criticos**: Emitir factura electronica (V03), Emitir retencion (C03), Configurar empresa/RUC (A01), Cargar certificado .p12 (A02), Generar ATS (CT07), Cobrar efectivo POS (POS05)

> Ver: `docs/core/flujos-casos-uso.md`

---

## 5. Arquitectura del Sistema

### Stack Tecnologico

| Capa | Tecnologia |
|------|-----------|
| Frontend | Flutter 3.x (Dart) → 6 plataformas |
| UI | Material 3 + Syncfusion + flex_color_scheme |
| Estado | Riverpod 2.x + go_router |
| Offline-First | brick_offline_first_with_supabase |
| Backend/DB | Supabase (PostgreSQL + RLS + Auth + Storage + Realtime + pgvector) |
| Firma SRI | Edge Functions (Deno/TS) con ec-sri-invoice-signer |
| Pagos | Kushki + Paymentez + PayPhone (patron adaptador) |
| Deploy | Cloudflare Pages (web, gratis) + App Stores + Supabase Cloud |

### Patron de Arquitectura

- **Multi-tenancy**: campo `empresa_id` + Row Level Security (RLS) en todas las tablas
- **Arquitectura por capas**: Presentacion → Logica de Negocio → Acceso a Datos → PostgreSQL
- **Modular por features**: cada modulo en `features/<modulo>/` con estructura consistente
- **Offline-first**: widgets leen SOLO de SQLite local via Brick, NUNCA de Supabase directo

### Core Foundation (Capa Base)

Infraestructura siempre activa que provee:
- **Multi-tenancy**: empresas, establecimientos, puntos_emision
- **Auth y permisos**: roles, permisos granulares, usuarios_empresa
- **Secuencias**: SRI + genericas (COT-, OV-, PAG-)
- **Adjuntos**: sistema polimorfico con Supabase Storage
- **Notificaciones**: multi-canal (app, email, push, WhatsApp, Telegram) con plantillas
- **Audit trail**: registro_actividad + audit_log detallado
- **Catalogos maestros**: 249 paises, provincias, ciudades, 228 monedas, 459 bancos EC, SRI
- **Entidades compartidas**: contactos, productos, precios, posiciones fiscales

### Module Service Bus

Schema `module_bus` con funciones gateway RPC. Modulos auxiliares NUNCA hacen INSERT directo en tablas de otros modulos → llaman a `module_bus.*` que verifica si el modulo destino esta activo → ejecuta o retorna NO-OP.

**3 tipos de modulos**:
1. **Infraestructura** (siempre activo): auth, config, catalogos, adjuntos, notificaciones
2. **Core** (activables, proveen servicios): Facturacion, Contabilidad, Inventario, Ventas, Compras, POS, Tesoreria
3. **Auxiliares** (opcionales, usan Service Bus): RRHH, Activos, CRM, Proyectos, Servicios, Garantias/Taller, Ecommerce, Citas

### Arquitectura Reactiva Offline-First

```
Widgets → BrickDataProvider<T>.stream (SQLite local) → Brick sync → Supabase (PostgreSQL)
```

- Widgets NUNCA llaman a Supabase directamente
- Brick sincroniza en background con cola de prioridad
- Supabase Realtime notifica cambios remotos → Brick actualiza local → widgets se rebuildan
- **Politicas de conflicto**: Bloqueo optimista (docs SRI), LWW+merge (maestros), Append-only (transacciones), Suma-delta (stock), Bloqueo pesimista (POS)

> Ver: `docs/core/arquitectura.md`, `docs/core/arquitectura-modular.md`

---

## 6. UI y Framework PilarShell

### Navegacion Odoo-style (SIN sidebar fijo)

- **App Launcher**: Grid de iconos de modulos habilitados
- **ModuleMenuBar**: Dropdowns del modulo activo en el header (desktop)
- **Tabs scrollables**: En tablet
- **Bottom Nav + Drawer**: En movil
- Jerarquia: PilarModule > PilarMenuGroup > PilarMenuItem

### PilarShell Framework

```
PilarApp → PilarShell(PilarHeader + PilarNavigation + PilarContent + PilarFooter)
```

### Breakpoints Responsive

| Breakpoint | Rango | Factor Escala |
|-----------|-------|--------------|
| COMPACT | < 600px | 0.85 |
| MEDIUM | 600-840px | 0.92 |
| EXPANDED | 840-1200px | 1.00 |
| LARGE | > 1200px | 1.00 |

### Widgets Core

- **CrudScaffold<T>**: Grid/lista reactiva con busqueda, filtros, paginacion, export PDF/Excel, permisos
- **FormScaffold<T>**: Formulario con secciones, validacion, deteccion cambios
- **WorkspaceTabs**: Sistema de tabs dinamico (click fila → tab edicion, Ctrl+T/W/Tab/N/S)
- **PilarSizes**: Escalado automatico de fuentes/botones/inputs por breakpoint

### Temas

- **flex_color_scheme**: 66 esquemas (FlexScheme), FlexTones (material/soft/vivid/highContrast)
- Preferencias persistidas: esquema, tono, fuente, densidad (shared_preferences)

---

## 7. Modelo de Datos (Tablas Principales)

### Multi-tenancy
`empresas` → `establecimientos` → `puntos_emision` → `secuenciales`

### Contactos
`contactos` (principal fiscal) + `contacto_direcciones` (entrega) + `contacto_cuentas_bancarias` + `etiquetas_contacto`

### Productos
`productos` (con UoM, IVA, costo, serie/lote) + `categorias` (arbol) + `producto_presentaciones` (multi-empaque, factor_conversion) + `producto_codigos_barras` + `producto_proveedores` + `variantes`

### Inventario
`bodegas` (principal + alternas) + `bodega_ubicaciones` + `inventario_stock` + `kardex` + `transferencias_inventario` + `series_lotes` + `lista_materiales` (BOM)

### Facturacion
`facturas` + `factura_detalles` + `factura_impuestos` + `documentos_electronicos` (cola SRI)

### Contabilidad
`cuentas_contables` (NIIF) + `diarios_contables` + `periodos_contables` + `asientos_contables` + `asiento_lineas` + `centros_costo` + `presupuestos`

### CxC/CxP
`cuentas_por_cobrar` + `cuentas_por_pagar` + `cobros` + `pagos` + `planes_pago` + `cuotas_credito`

### Tesoreria
`cuentas_bancarias` + `cheques` + `transferencias_bancarias` + `conciliaciones_bancarias`

### Auth y Permisos
`roles` + `permisos` (modulo.recurso.accion) + `usuarios_empresa` + `rol_permisos` + `permisos_campo` + `sesiones_usuario`

### Infraestructura
`modulos` + `modulos_empresa` + `planes_suscripcion` + `adjuntos` + `notificaciones` + `registro_actividad` + `audit_log` + `secuencias` + `configuracion_empresa` + `parametros_sistema` + `tareas_programadas`

> Ver: `docs/core/modelo-datos.md`

---

## 8. Modulos del ERP (Resumen)

| Modulo | Funcionalidades Clave | Docs |
|--------|----------------------|------|
| **Ventas** | Cotizaciones, OV, facturas electronicas, NC/ND, cobros mixtos, CxC, control credito, lealtad, cupones, suscripciones | `docs/modulos/ventas/` (7 archivos) |
| **Compras** | OC, facturas recibidas, retenciones V2.0.0, liquidaciones, RFQ, scoring proveedores, acuerdos marco, dropship, consignacion | `docs/modulos/compras/` (6 archivos) |
| **Inventario** | Multi-bodega, kardex, BOM multi-nivel, QC, forecast demanda, dashboard, co-productos, app bodeguero | `docs/modulos/inventario/` (8 archivos) |
| **POS** | Multi-modo (supermercado/departamental/ferreteria), sesiones caja, cobro mixto, factura auto, pre-ventas | `docs/modulos/pos/` |
| **Contabilidad** | Plan cuentas NIIF, asientos auto/manuales, libros, ATS, presupuestos, docs contables Ecuador | `docs/modulos/contabilidad/` (3 archivos) |
| **Tesoreria** | Cuentas bancarias, cheques, transferencias, conciliacion, CxC/CxP, control credito, planes pago | `docs/modulos/tesoreria/` (2 archivos) |
| **RRHH** | Departamentos, empleados, contratos, asistencia biometrica, turnos, nomina IESS/IR, prestamos | `docs/modulos/rrhh/` (2 archivos) |
| **Servicios/Contratos** | TV cable/internet, contratos N servicios, tarifas prorrateadas, ordenes trabajo | `docs/modulos/servicios-contratos/` |
| **Garantias/RMA/Taller** | RMA, taller reparacion, proforma obligatoria, evidencia fotos/video/firma, bodegas especializadas | `docs/modulos/garantias-rma-taller/` |
| **Citas (Belleza)** | Agenda por profesional, walk-in, comisiones (6 modelos), paquetes/membresias/gift cards | `docs/modulos/citas-belleza/` |
| **Ecommerce** | WooCommerce + Multi-Marketplace (MercadoLibre/Shopify/Amazon), portal autoservicio clientes | `docs/modulos/ecommerce/` (3 archivos) |
| **Intercompany** | Ventas/compras/transferencias/prestamos cross-empresa, consolidacion grupo | `docs/modulos/intercompany/` |
| **IA/Chat** | pgvector, forecast ventas/inventario, scoring CRM, churn, chat NLP→SQL, anomalias | `docs/modulos/ia/` (5 archivos) |
| **Pagos Online** | Kushki + Paymentez + PayPhone, patron adaptador configurable por empresa | `docs/core/pagos.md` |
| **Administracion** | Parametrizacion SRI, posiciones fiscales, multi-moneda | `docs/modulos/administracion/` |
| **Comunicacion** | Supabase Realtime, chat interno, envio proformas multi-canal | `docs/modulos/comunicacion/` |

---

## 9. Seguridad

- **Auth**: Supabase Auth (email/password + Google + Apple + Magic Link + MFA/TOTP)
- **JWT claims**: empresa_id, rol, permisos[], is_saas_admin
- **RLS**: `private.get_empresa_id()` helper (99.993% mejora rendimiento)
- **Permisos**: Granulares (modulo.recurso.accion) + permisos a nivel campo
- **Certificados .p12**: NUNCA en el cliente, solo Edge Functions via service_role
- **LOPDP Ecuador**: Consentimiento, derecho acceso/eliminacion/portabilidad, audit trail
- **Audit trail**: audit_log con trigger generico en tablas criticas
- **Cifrado**: TLS en transito, AES-256 en reposo, pgcrypto para columnas sensibles

> Ver: `docs/core/seguridad.md`

---

## 10. Precision Numerica y Zonas Horarias

- **DECIMAL(14,2)** para montos, **DECIMAL(18,6)** para cantidades/precios. NUNCA float
- **Redondeo**: SOLO al final del calculo, NUNCA en intermedios
- **Zonas horarias**: TIMESTAMPTZ (UTC) en BD, zona por establecimiento, conversion en Flutter
- Ecuador: America/Guayaquil (GMT-5), Pacific/Galapagos (GMT-6)

> Ver: `docs/core/precision-supabase.md`

---

## 11. Supabase Best Practices

1. SIEMPRE habilitar RLS en todas las tablas
2. SIEMPRE usar `(SELECT ...)` para funciones auth (94.97% mejora)
3. SIEMPRE especificar `TO authenticated` (99.78% mejora)
4. SIEMPRE crear indices en columnas usadas por RLS
5. NUNCA usar `user_metadata` para autorizacion (solo `app_metadata`)
6. NUNCA exponer `service_role_key` al cliente
7. Migraciones versionadas con BEGIN/COMMIT
8. Schema `private` para datos internos no accesibles via API
9. SECURITY DEFINER + search_path explicito en triggers
10. Views con `security_invoker = on`

> Ver: `docs/core/precision-supabase.md`

---

## 12. Plataformas y Despliegue

| Fase | Plataformas |
|------|------------|
| Fase 1 (MVP) | Flutter Web (Cloudflare Pages) + Android (Play Store) |
| Fase 2 | iOS (App Store) + Desktop (Windows/macOS/Linux) |
| Fase 3 | Escaneo camara, impresion termica, auto-update, Chat IA |

**Costo mensual estimado**: ~$25-45/mes (Supabase Pro + Cloudflare gratis + Resend)

> Ver: `docs/core/arquitectura.md` (seccion Plataformas), `docs/core/roadmap.md`

---

## 13. Totales del Proyecto

### Modelo de Datos Completo

| Grupo | Tablas Aprox. |
|-------|--------------|
| Core Foundation (infraestructura) | ~90 |
| Modulos de negocio (Ventas-RRHH) | ~120 |
| Citas (Belleza) | 25 |
| Ventas ampliado (lealtad, cupones, suscripciones) | ~24 |
| Inventario ampliado (BOM, QC, forecast) | ~15 |
| Compras ampliado (RFQ, scoring, dropship) | ~19 |
| Multi-Marketplace | ~6 |
| Intercompany | ~10 |
| Portal Clientes | ~6 |
| IA Avanzada | ~11 |
| **TOTAL** | **~326 tablas** |

### Funciones y Edge Functions

- **~200+ funciones** PostgreSQL (SECURITY DEFINER)
- **~30+ Edge Functions** (Deno/TypeScript)
- **~40+ vistas/MVs** para reportes
- **~25+ gateways** Module Service Bus

---

## 14. Anexos Tecnicos (Referencia Rapida)

### URLs Web Services SRI

| Servicio | Pruebas | Produccion |
|----------|---------|------------|
| Recepcion | celcer.sri.gob.ec/.../RecepcionComprobantesOffline | cel.sri.gob.ec/.../RecepcionComprobantesOffline |
| Autorizacion | celcer.sri.gob.ec/.../AutorizacionComprobantesOffline | cel.sri.gob.ec/.../AutorizacionComprobantesOffline |

### Validaciones Criticas XSD

| Campo | Pattern |
|-------|---------|
| RUC | `[0-9]{10}001` |
| Clave Acceso | `[0-9]{49}` |
| Fecha | `dd/mm/aaaa` |
| Establecimiento | `[0-9]{3}` |
| Secuencial | `[0-9]{9}` |

### Envio por Lote
Max 50 comprobantes, 500KB total, 320KB individual

### Consideraciones Tecnicas
- SRI puede tardar hasta 24h (estado PPR) → cola con reintentos
- Error 70: NO reenviar, esperar
- Consumidor final > $50 → datos obligatorios (9999999999999)
- `&` → `&amp;` en XML
- Transmision inmediata obligatoria 2026 (multa 30 RBU ~$14,460)

> Ver: `docs/regulatorio/sri-requisitos.md`, `docs/regulatorio/anexos.md`

---

## 15. Estructura de Documentacion

La documentacion se organiza en `docs/` con **81 archivos** en carpetas tematicas:

```
docs/
├── indice.md                          (tabla de contenidos maestra)
├── resumen-ejecutivo.md
│
├── core/                              (9 archivos - transversal)
│   ├── arquitectura.md                (capas, componentes, stack, deploy)
│   ├── arquitectura-modular.md        (modulos del sistema, KPIs, como agregar)
│   ├── modelo-datos.md                (esquema global PostgreSQL)
│   ├── seguridad.md                   (RLS, auth, cifrado)
│   ├── precision-supabase.md          (DECIMAL, zonas horarias, best practices)
│   ├── pagos.md                       (Kushki, Paymentez, PayPhone)
│   ├── roadmap.md                     (fases + gaps P2)
│   ├── estructura-proyecto.md         (arbol archivos Flutter)
│   └── flujos-casos-uso.md            (procesos de negocio)
│
├── regulatorio/                       (3 archivos - SRI Ecuador)
│   ├── sri-requisitos.md
│   ├── documentos-electronicos.md
│   └── anexos.md
│
├── modulos/                           (19 carpetas, 1 por modulo)
│   ├── ventas/                        (7 archivos: base + lealtad + cupones + suscripciones + pronto-pago + intercompany-ventas + ia-ventas)
│   ├── compras/                       (6 archivos: base + rfq + scoring + acuerdos-marco + dropshipping + consignacion)
│   ├── inventario/                    (8 archivos: base + bom + qc + forecast + dashboard + co-productos + bodeguero + ia-inventario)
│   ├── contabilidad/                  (3 archivos: base + docs-ecuador + ia-contabilidad)
│   ├── tesoreria/                     (2 archivos: base + cxc-cxp)
│   ├── pos/                           (1 archivo)
│   ├── ecommerce/                     (3 archivos: base + multi-marketplace + portal-clientes)
│   ├── rrhh/                          (2 archivos: base + ia-rrhh)
│   ├── activos-fijos/                 (1 archivo)
│   ├── consumibles/                   (1 archivo)
│   ├── crm/                           (1 archivo)
│   ├── proyectos/                     (1 archivo)
│   ├── servicios-contratos/           (1 archivo)
│   ├── garantias-rma-taller/          (1 archivo)
│   ├── citas-belleza/                 (1 archivo)
│   ├── intercompany/                  (1 archivo)
│   ├── ia/                            (5 archivos: base + arquitectura + chat-nlp + edge-functions + roadmap)
│   ├── administracion/                (1 archivo)
│   └── comunicacion/                  (1 archivo)
│
├── apis/
│   └── rpcs-por-modulo.md             (APIs y RPCs)
│
└── integraciones/                     (1 archivo - automatizaciones)
    └── n8n.md                         (50+ flujos por modulo: SRI, cobranza, marketplaces, notificaciones)
```

### Otros archivos de referencia

| Archivo | Contenido |
|---------|-----------|
| `INFORME_ERP_PILAR.md` | Documento original consolidado (37,549 lineas, backup) |
| `RESUMEN_INFORME_ERP_PILAR.md` | Este resumen |
| `sql/modulo_citas.sql` | 25 tablas + ENUMs del modulo Citas |
| `sql/modulo_citas_funciones.sql` | 14 funciones + 6 triggers + 6 vistas Citas |
| `comparativa_ventas.md` | Comparativa Ventas PILAR vs 8 ERPs |
| `comparativa_inventario.md` | Comparativa Inventario PILAR vs 10 ERPs |
| `comparativa_features_ecuador.md` | Features especificos Ecuador, 40+ criterios |
| `analisis_mercado_erp_ecuador.md` | Analisis mercado ERP Ecuador 2024-2026 |

---

*Este resumen refleja la estructura `docs/` (81 archivos, 20 modulos). Para agregar funcionalidad, crear nuevo archivo en `docs/modulos/<modulo>/nueva-feature.md` y actualizar `docs/indice.md`.*
