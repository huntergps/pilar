# Resumen Ejecutivo — PILAR ERP

## 1. Que es PILAR ERP

**PILAR ERP** es un sistema de gestion empresarial (ERP) en modalidad SaaS, disenado especificamente para PyMEs ecuatorianas. Combina cumplimiento total de las normativas del Servicio de Rentas Internas (SRI) con una arquitectura moderna, offline-first y multi-plataforma.

- **Ano de desarrollo**: 2026 (fase de diseno/documentacion completada, implementacion proxima)
- **Mercado objetivo**: PyMEs ecuatorianas de 10 a 200 empleados en sectores comercio, servicios, manufactura ligera y talleres
- **Modalidad**: SaaS multi-tenant con planes activables por modulo

### Diferenciadores vs. competidores en Ecuador

| Criterio | PILAR ERP | Monica / ContaGo | Odoo Ecuador | SAP Business One |
|---|---|---|---|---|
| Cumplimiento SRI nativo | Si — todos los documentos | Parcial (solo facturas) | Modulo l10n_ec externo | Conector de terceros |
| Offline-first | Si — SQLite local + sync | No | No | No |
| Multi-plataforma (6) | Si — Flutter nativo | Web solamente | Web / Electron | Web / Windows |
| Modulos activables | Si — paga solo lo que usa | No (precio fijo) | Si (pero complejo) | No |
| IA integrada | Si — chat, forecast, anomalias | No | Parcial (OpenAI addon) | No |
| Precio mensual (base) | Desde $49/mes | $30-80/mes | Desde $600/mes | Desde $3,000/mes |
| Firma XAdES-BES | Server-side (Edge Function) | Descarga local .exe | Modulo externo | Tercero |

---

## 2. Propuesta de Valor

### 2.1 Cumplimiento SRI nativo

PILAR soporta los 6 tipos de documentos electronicos del SRI sin plugins de terceros: Facturas (01), Liquidaciones de Compra (03), Notas de Credito (04), Notas de Debito (05), Guias de Remision (06) y Comprobantes de Retencion (07). La firma XAdES-BES se ejecuta en el servidor (Edge Function Deno) con la biblioteca `ec-sri-invoice-signer`. El modulo Tributacion genera automaticamente el ATS mensual, los formularios 103, 104 y 101, y el RDEP anual.

### 2.2 Offline-first

La aplicacion Flutter usa `brick_offline_first_with_supabase` para mantener una copia local en SQLite. El usuario puede registrar facturas, movimientos de inventario y cobros sin conexion a internet. Al reconectarse, la sincronizacion bidireccional aplica una estrategia de resolucion de conflictos por tipo de dato: bloqueo optimista para documentos SRI, LWW+merge para maestros, append-only para transacciones, suma-delta para stock. Esto es critico para Ecuador, donde la conectividad en zonas rurales o en campo es irregular.

### 2.3 Multi-plataforma

Un solo codebase Flutter 3.x compila nativamente para Web, iOS, Android, Windows, macOS y Linux. No hay aplicaciones separadas para cada plataforma: la interfaz PilarShell se adapta automaticamente con cuatro breakpoints (COMPACT / MEDIUM / EXPANDED / LARGE) y selecciona el patron de navegacion apropiado (bottom nav → rail → sidebar → MenuBar).

### 2.4 Modulos activables

El **Module Service Bus** (schema `module_bus`) permite que cada empresa active solo los modulos que necesita. Los modulos auxiliares nunca hacen INSERT directo en tablas de modulos core; llaman a funciones gateway que verifican si el modulo destino esta activo y ejecutan la operacion o retornan un NO-OP seguro. Esto permite, por ejemplo, usar solo Facturacion + Inventario sin activar Contabilidad ni RRHH.

### 2.5 IA integrada

El modulo IA/Chat incluye: chat NLP en espanol sobre datos propios de la empresa (pgvector + embeddings), forecast de ventas e inventario (series de tiempo), deteccion de anomalias contables, scoring de oportunidades CRM y generacion de reportes en lenguaje natural. No requiere conocimiento tecnico del usuario.

### 2.6 Precio accesible

La infraestructura backend tiene un costo fijo de $25-45/mes (Supabase Cloud). El frontend web se sirve desde Cloudflare Pages (gratuito). Esto permite ofrecer planes desde $49/mes, muy por debajo de Odoo Enterprise (~$600+/mes) o SAP Business One (~$3,000+/mes), con funcionalidad comparable en el contexto ecuatoriano.

---

## 3. Stack Tecnologico

| Capa | Tecnologia | Rol |
|---|---|---|
| Frontend | Flutter 3.x (Dart) | 6 plataformas desde un solo codebase |
| State management | Riverpod 2.x | Providers globales y por modulo |
| Offline / Sync | brick_offline_first_with_supabase | SQLite local ↔ PostgreSQL remoto |
| UI | Material 3 + Syncfusion + flex_color_scheme | DataGrid, PDF, Charts, 66 esquemas de color |
| Layout | PilarShell | Framework adaptativo con 4 breakpoints |
| Backend / BD | Supabase (PostgreSQL 15+) | RLS, Auth JWT, Storage, Realtime WebSocket |
| Edge Functions | Deno / TypeScript | Firma XAdES-BES, SOAP SRI, XML, PDF |
| Firma SRI | ec-sri-invoice-signer | XAdES-BES server-side, sin dependencias externas |
| Pagos online | Kushki + Paymentez + PayPhone | Patron adaptador, configurables por empresa |
| IA | pgvector + OpenAI | Embeddings, chat NLP, forecasts, anomalias |
| Email | Resend | Envio RIDE, notificaciones, estados de cuenta |
| Deploy web | Cloudflare Pages | Gratis, CDN global |
| Deploy mobile | App Store + Play Store | iOS / Android |
| Deploy backend | Supabase Cloud | PostgreSQL managed, ~$25-45/mes |
| Monitoreo | Sentry | Errores frontend y Edge Functions |

---

## 4. Plataformas Objetivo

| Plataforma | Solucion tecnica | Tipo de distribucion |
|---|---|---|
| Web (Chrome, Firefox, Safari, Edge) | Flutter Web | Principal — `app.pilar.ec` |
| Windows | Flutter Desktop nativo | Instalable — Microsoft Store / .exe |
| macOS | Flutter Desktop nativo | Instalable — Mac App Store / .dmg |
| Linux | Flutter Desktop nativo | Instalable — .deb / .AppImage |
| iOS | Flutter Mobile | App Store |
| Android | Flutter Mobile | Google Play Store |

**Nota de diseno**: el frontend es la misma base de codigo para las 6 plataformas. El backend (Supabase + Edge Functions) es independiente de la plataforma cliente y maneja toda la logica SRI de forma centralizada.

---

## 5. Modulos del Sistema (24 total)

### 5.1 Infraestructura — siempre activos, no desactivables

| # | Modulo | Descripcion |
|---|---|---|
| 1 | Dashboard | KPIs en tiempo real, App Launcher de modulos, widgets configurables por usuario y empresa |
| 2 | Administracion | Configuracion de empresa, establecimientos, sucursales, certificados SRI, usuarios, roles, permisos, parametros del sistema, branding del login |
| 3 | Comunicacion | Notificaciones multi-canal (email via Resend, WhatsApp Cloud API, Telegram Bot API, Push FCM), chat interno entre usuarios, plantillas de mensajes |

### 5.2 Core — backbone del ERP, proveen servicios via Module Service Bus

| # | Modulo | Descripcion | Tablas clave |
|---|---|---|---|
| 4 | Facturacion | Emision de documentos electronicos SRI (01/03/04/05/06/07), cola de envio no bloqueante, RIDE PDF, firma XAdES-BES, cobros asociados | `facturas`, `factura_lineas`, `notas_credito`, `notas_debito`, `cola_documentos_electronicos`, `cobros_factura` |
| 5 | Ventas | Cotizaciones → Ordenes de Venta → Despacho, CxC, credito cliente (limite, bloqueo, excepciones), cupones, lealtad, ensamblaje por OV | `cotizaciones`, `ordenes_venta`, `ordenes_venta_lineas`, `cuentas_por_cobrar` |
| 6 | Compras | Ordenes de Compra → Recepciones → Facturas proveedor → Retenciones → CxP, importaciones NANDINA, costos de aterrizaje, importacion XML SRI | `ordenes_compra`, `recepciones_compra`, `facturas_proveedor`, `liquidaciones_compra`, `retenciones` |
| 7 | Inventario | Multi-bodega, BOM/Ensamblaje multi-nivel, Series y Lotes, Kardex valorado, reservas con bodega virtual, devoluciones, conversion de stock, QC | `productos`, `bodegas`, `inventario_stock`, `movimientos_inventario`, `transferencias_bodega` |
| 8 | Contabilidad | Plan de cuentas NIIF PYMES, asientos automaticos, EEFF (balance, resultados, flujo de caja), diarios, centros de costo, periodos contables | `asientos_contables`, `asiento_lineas`, `cuentas_contables`, `periodos_contables`, `diarios_contables` |
| 9 | Tesoreria | Cuentas bancarias, cheques (Art.1/Art.58), conciliacion bancaria, caja chica (fondos fijos y fondos a rendir), anticipos cliente/proveedor, cobro multi-factura, caja recaudadora | `cuentas_bancarias`, `movimientos_bancarios`, `transferencias_bancarias`, `conciliaciones_bancarias` |
| 10 | Tributacion | ATS mensual, Formulario 103 (retenciones en la fuente), Formulario 104 (IVA), Formulario 101 (IR anual), RDEP, calendarios de vencimiento SRI | `declaraciones_tributarias`, `configuracion_tributaria` |

### 5.3 Auxiliares — activables por empresa, nunca INSERT directo en tablas Core

| # | Modulo | Descripcion |
|---|---|---|
| 11 | POS | Punto de venta multi-modo: SUPERMERCADO (autoservicio), DEPARTAMENTAL (multi-vendedor/piso, pre-ventas), FERRETERIA (pre-venta + despacho post-pago). Sesiones pausables, control de stock por bodega |
| 12 | Ecommerce | Integracion WooCommerce, multi-marketplace (MercadoLibre / Shopify / Amazon), portal autoservicio para clientes (consulta de facturas, pagos online, estado de pedidos) |
| 13 | RRHH | Empleados, contratos, historial laboral, asistencia biometrica (6 metodos), turnos rotativos, nomina con IESS e IR, decimos tercero y cuarto, fondos de reserva, prestamos con tabla de amortizacion, archivo bancario para pago masivo |
| 14 | Activos Fijos | Registro, depreciacion segun tabla SRI Ecuador, mantenimiento preventivo, baja, revalorizacion, integracion con asientos contables |
| 15 | Consumibles | Solicitudes internas de materiales, entregas desde bodega, control de consumo por departamento, integracion contable via module_bus |
| 16 | CRM | Pipeline de oportunidades, etapas configurables, actividades y recordatorios, campanas, scoring de oportunidades por IA, conversion a Orden de Venta |
| 17 | Proyectos | Proyectos y tareas, timesheets, presupuesto de proyecto, costeo real vs. presupuestado, integracion con Facturacion para cobro por avance |
| 18 | Suscripciones | Contratos recurrentes genericos (ISP, gimnasios, parking, SaaS), planes configurables, facturacion manual o automatica, portal autoservicio con token, equipos de cliente |
| 19 | Taller | Reparaciones fisicas (interna, externa, en garantia), proforma obligatoria, consumo de materiales con conversion de UoM, mano de obra por tecnico, herramientas vinculadas a activos fijos, bodegas especializadas, evidencia con fotos/video/firma digital |
| 20 | Garantias/RMA | Solicitudes de devolucion de clientes, diagnostico, reemplazo de producto, emision de Nota de Credito o scrap, puente entre Ventas y Compras para garantias transferidas a proveedor |
| 21 | Citas/Belleza | Agenda multi-especialista, app salon para administradores y empleados, app cliente white-label, carga de logo y colores desde el perfil del salon, notificaciones push FCM |
| 22 | Intercompany | Transacciones entre empresas del mismo grupo empresarial, consolidacion de estados financieros, eliminacion de transacciones intragrupo |
| 23 | IA/Chat | Chat NLP en espanol sobre datos propios via pgvector + embeddings, forecast de ventas e inventario, deteccion de anomalias contables, scoring CRM, generacion de reportes en lenguaje natural |
| 24 | Servicio de Campo | Ordenes de campo con tipos INSTALACION / CORTE / REINSTALACION / MANTENIMIENTO / PREVENTIVO / EMERGENCIA / RETIRO, zonificacion GeoJSON, SLA con alertas al 80%, reportes diarios, actualizacion de contratos via module_bus |

---

## 6. Planes SaaS

| Plan | Modulos incluidos | Precio referencial / mes | Usuarios |
|---|---|---|---|
| **Basico** | Infraestructura + Facturacion + Inventario basico | $49 | Hasta 3 |
| **Profesional** | Basico + Ventas + Compras + Contabilidad + Tesoreria + Tributacion | $149 | Hasta 10 |
| **Business** | Profesional + POS + RRHH + CRM + Proyectos | $299 | Hasta 25 |
| **Enterprise** | Todos los 24 modulos | $499 | Ilimitados |
| **Custom** | Modulos a la carta segun necesidad | Cotizar | Ilimitados |

Los precios son referenciales. El modelo final puede incluir cargos por volumen de documentos electronicos emitidos (pay-as-you-go) o por numero de usuarios activos.

---

## 7. Documentos SRI Soportados

| Codigo | Documento | Version XML | Observaciones |
|---|---|---|---|
| 01 | Factura | V2.1.0 | Incluye IVA 0%, 5%, 15%, exento; retenciones en la fuente |
| 03 | Liquidacion de Compra | V1.1.0 | Para compras a personas naturales no obligadas a llevar contabilidad |
| 04 | Nota de Credito | V1.1.0 | Devolucion total o parcial de factura, anulacion |
| 05 | Nota de Debito | V1.0.0 | Cargos adicionales sobre una factura emitida |
| 06 | Guia de Remision | V1.1.0 | Traslado de mercaderia, vinculada a OV o transferencia de bodega |
| 07 | Comprobante de Retencion | V2.0.0 | Retencion en la fuente de IR e IVA, generado automaticamente al recibir factura proveedor |

**Pipeline de envio SRI** (no bloqueante):

```
Confirmacion pago → Asignacion secuencial offline → Generacion XML → Validacion XSD
→ Firma XAdES-BES (Edge Function) → Envio SOAP SRI → Cola de autorizacion (reintentos 24h)
→ Almacenamiento XML autorizado (Supabase Storage) → Generacion RIDE PDF
→ Envio por email / WhatsApp / Telegram
```

---

## 8. Cumplimiento Regulatorio Ecuador

### 8.1 SRI — Servicio de Rentas Internas

| Obligacion | Soporte en PILAR | Modulo responsable |
|---|---|---|
| Facturacion electronica (documentos 01/03/04/05/06/07) | Completo, firma XAdES-BES server-side | Facturacion |
| ATS mensual (Anexo Transaccional Simplificado) | Generacion automatica desde transacciones | Tributacion |
| Formulario 103 (retenciones en la fuente) | Calculo y generacion mensual | Tributacion |
| Formulario 104 (declaracion de IVA) | Calculo y generacion mensual | Tributacion |
| Formulario 101 (impuesto a la renta anual) | Datos preparados para declaracion | Tributacion |
| RDEP (rol de pagos para empleados) | Generacion anual | RRHH + Tributacion |
| Retenciones automaticas en compras | Si — al recibir factura proveedor | Compras + Facturacion |
| Guia de remision vinculada | Si — a OV o transferencia de bodega | Inventario + Facturacion |

### 8.2 IESS — Instituto Ecuatoriano de Seguridad Social

| Obligacion | Soporte |
|---|---|
| Planilla mensual IESS (aportes patron y personal) | Si — calculo automatico |
| Decimo tercero y cuarto sueldo | Si — acumulacion mensual y pago |
| Fondos de reserva | Si — desde el primer ano de contrato |
| RDEP anual | Si — generacion automatica |

### 8.3 Superintendencia de Companias (Supercias)

| Obligacion | Soporte |
|---|---|
| Balance General (NIIF PYMES) | Si — generado desde cuentas contables |
| Estado de Resultados | Si — por periodo o acumulado |
| Estado de Flujo de Efectivo | Si — metodo indirecto |
| Notas a los estados financieros | Preparacion de datos; redaccion manual |

### 8.4 LOPDP — Ley Organica de Proteccion de Datos Personales

| Requisito | Implementacion |
|---|---|
| Cifrado de datos personales | Datos sensibles cifrados en reposo (Supabase) |
| Consentimiento informado | Campo `consentimiento_datos` en contactos |
| Retencion limitada | Politicas de retencion configurables por empresa |
| Derecho al olvido | Procedimiento de anonimizacion documentado |

---

## 9. Arquitectura de Despliegue

```
[Usuarios]
    |
    +-- Web: Cloudflare Pages → app.pilar.ec (Flutter Web, gratis)
    +-- iOS: App Store → PILAR ERP
    +-- Android: Play Store → PILAR ERP
    +-- Windows / macOS / Linux: instalable

[Backend — Supabase Cloud, ~$25-45/mes fijo]
    |
    +-- PostgreSQL 15+ con RLS (Row Level Security)
    +-- Auth JWT (multi-empresa, multi-rol)
    +-- Storage (XMLs SRI, PDFs RIDE, certificados, adjuntos)
    +-- Realtime WebSocket (sync de cambios)
    +-- Edge Functions (Deno/TS): firma XAdES-BES, SOAP SRI, IA, pagos
    +-- pgvector: embeddings para IA/Chat

[PILAR Admin — admin.pilar.ec]
    Panel de control del operador SaaS: alta de empresas, gestion de planes, soporte
```

### Costos de infraestructura estimados

| Componente | Costo mensual |
|---|---|
| Supabase Cloud (Pro plan) | $25 - $45 fijo |
| Cloudflare Pages (web frontend) | $0 (gratuito) |
| App Stores (iOS / Android) | $1 / $25 anuales (alta unica) |
| Resend (email, primeros 3,000/mes) | $0 (gratuito) |
| OpenAI API (IA/Chat, variable) | $5 - $30 segun uso |
| **Total infraestructura base** | **~$30-75/mes** |

El margen operativo a partir del plan Profesional ($149/mes) cubre holgadamente los costos de infraestructura.

---

## 10. Multi-Tenancy y Seguridad

### Row Level Security (RLS)

Todas las tablas incluyen `empresa_id`. El aislamiento entre tenants se implementa mediante politicas RLS en PostgreSQL:

```sql
-- Patron obligatorio en todas las tablas:
CREATE POLICY "empresa_isolation" ON tabla_ejemplo
  USING (empresa_id = (SELECT private.get_empresa_id()))
  WITH CHECK (empresa_id = (SELECT private.get_empresa_id()));
```

La funcion `private.get_empresa_id()` es cacheada por sesion (no inline JWT parsing), evitando N+1 en queries complejas.

### Precision de calculos financieros

- **Montos**: `DECIMAL(14,2)` — nunca `float` ni `real`
- **Cantidades**: `DECIMAL(18,6)` — para productos con alta precision (medicamentos, materias primas)
- **Redondeo**: solo al final del calculo, nunca en intermedios (evita errores de centavo acumulados)
- **Zonas horarias**: `TIMESTAMPTZ` (UTC) en base de datos, conversion a zona horaria del establecimiento en Flutter

### Autenticacion y roles

- Supabase Auth (JWT) con branding por empresa (logo, colores, textos del login)
- Un usuario puede pertenecer a N empresas con roles distintos en cada una
- Roles en `raw_user_meta_data`: ADMIN / CONTADOR / VENDEDOR / BODEGUERO / CAJERO / LECTOR + roles especiales por modulo (ADMIN_SALON, EMPLEADO, CLIENTE para el flavor Citas/Belleza)

---

## 11. Caracteristicas Tecnicas Destacadas

### Offline-first con sincronizacion inteligente

| Tipo de dato | Estrategia de conflicto | Justificacion |
|---|---|---|
| Documentos SRI (facturas, NC, ND) | Bloqueo optimista (`version` field) | Evita doble emision de documentos electronicos |
| Maestros (productos, contactos, precios) | LWW + merge de campos | Cambios no criticos, ultimo gana |
| Transacciones contables | Append-only | No se modifican asientos ya registrados |
| Stock de inventario | Suma-delta | Los movimientos son incrementales, no absolutos |

### Cola de documentos electronicos (no bloqueante)

El usuario confirma la factura y recibe inmediatamente el RIDE (PDF). La firma y el envio al SRI ocurren en segundo plano con reintentos automaticos durante 24 horas. Los secuenciales se asignan offline (sin conexion) para no bloquear la operacion del negocio.

### PilarShell — UI adaptativa

| Breakpoint | Ancho | Factor escala | Navegacion |
|---|---|---|---|
| COMPACT | < 600 px | 0.85 | Bottom navigation (max 5 items) + drawer |
| MEDIUM | 600-840 px | 0.92 | Tabs scrollables del modulo activo |
| EXPANDED | 840-1200 px | 1.0 | Navigation rail + contenido |
| LARGE | > 1200 px | 1.0 | MenuBar con dropdowns estilo Odoo (PilarModule > PilarMenuGroup > PilarMenuItem) |

### WorkspaceTabs (UI de productividad)

Click en una fila de lista → abre tab de edicion. Boton "+ Nuevo" → tab de creacion. Soporte para Ctrl+T (nuevo tab), Ctrl+W (cerrar tab), Ctrl+Tab (navegar tabs), Ctrl+S (guardar). Persistencia de tabs entre sesiones.

---

## 12. Flavors de la Aplicacion Flutter

PILAR compila tres sabores desde un solo codebase Flutter:

| Flavor | Entry point | Audiencia | Plataformas |
|---|---|---|---|
| `erp` | `main_erp.dart` | Usuarios del ERP (todos los modulos) | Web + Desktop + Mobile |
| `salon` | `main_salon.dart` | Duenos y empleados de salon/spa | iOS + Android |
| `cliente` | `main_cliente.dart` | Clientes finales del salon (white-label) | iOS + Android |

El flavor `cliente` carga logo, colores y nombre desde `salon_perfiles_publicos` en Supabase, permitiendo que cada salon tenga una app de clientes con su propia marca sin costos adicionales de desarrollo.

---

## 13. Estado del Proyecto (febrero 2026)

| Componente | Estado | Detalle |
|---|---|---|
| Documentacion tecnica | Completada | 110+ archivos .md, ~73,000 lineas |
| Migraciones SQL | En progreso | 17 migraciones (001-017) |
| Edge Functions | En progreso | 18 funciones Deno/TypeScript |
| Flutter — Core Foundation | Pendiente | Inicio planificado post-documentacion |
| Flutter — Modulos Core (7) | Pendiente | Siguiente fase |
| Flutter — Modulos Auxiliares (14) | Pendiente | Fases P2 y P3 |
| Tests automatizados | Pendiente | Planificados con cobertura RLS |
| Deploy produccion | Pendiente | Supabase Cloud + Cloudflare Pages |

### Hoja de ruta de implementacion (resumen)

| Fase | Contenido | Prioridad |
|---|---|---|
| P1 — Backend base | Core Foundation, RLS, Auth, Catalogos SRI, Edge Functions firma | Alta |
| P1 — Modulos Core | Facturacion, Ventas, Compras, Inventario, Contabilidad, Tesoreria, Tributacion | Alta |
| P1 — Flutter Core | PilarShell, Riverpod, Brick ORM, pantallas CRUD de modulos Core | Alta |
| P2 — Auxiliares | POS, RRHH, CRM, Activos Fijos, Consumibles, Proyectos | Media |
| P3 — Auxiliares avanzados | Ecommerce, Taller, Garantias/RMA, Suscripciones, Citas/Belleza, Intercompany, Servicio de Campo, IA/Chat | Media-baja |

---

## 14. Documentacion Tecnica

La especificacion completa del sistema se encuentra en el directorio `docs/` del repositorio:

| Directorio | Contenido |
|---|---|
| `docs/core/` | Arquitectura, modelo de datos (~326 tablas), seguridad, roadmap, estructura Flutter |
| `docs/modulos/` | Un archivo por modulo con modelo SQL completo, RPCs, RLS, integraciones |
| `docs/regulatorio/` | Requisitos SRI, tipos de documentos, estructura ATS, LOPDP |
| `docs/apis/` | 85+ funciones RPC documentadas, Module Service Bus |
| `docs/integraciones/` | n8n, WooCommerce, marketplaces, pasarelas de pago |
| `supabase/migrations/` | Migraciones SQL versionadas (001-017) |

El indice maestro con descripciones de todos los archivos esta en `docs/indice.md`.

---

> Ultima actualizacion: 2026-02-19 | Version de documentacion: v1.0
