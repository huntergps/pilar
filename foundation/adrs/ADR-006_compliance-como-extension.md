# ADR-006: Compliance de Pais como Extension — Foundation Country-Agnostic

**Estado**: Aceptado
**Fecha**: 2026-02
**Autores**: Arquitecto principal
**Tags**: ecuador, sri, fiscal, arquitectura, internacionalizacion, compliance, multi-pais

---

## Contexto

Al disenar un ERP con requisitos fiscales locales existe una tension entre dos extremos:

**Opcion A — Localizacion total posterior**: construir el ERP completamente generico y agregar el compliance fiscal como plugin tardio.

**Opcion B — Compliance embebido en Foundation**: integrar la logica fiscal directamente en las migraciones base, asumiendo un unico pais para siempre.

La normativa fiscal ecuatoriana es sustancialmente mas compleja que lo que un ERP generico asume por defecto:

- **Facturacion electronica obligatoria**: 6 tipos de documento con firma XAdES-BES, claves de acceso de 49 digitos, envio SOAP al SRI, autorizacion en tiempo real
- **Retenciones**: en la fuente (renta) e IVA, calculadas segun tabla de tarifas SRI, emitidas como documento electronico tipo 07
- **Liquidaciones de compra**: para personas naturales sin RUC — documento tipo 03 con reglas especiales
- **ATS (Anexo Transaccional Simplificado)**: declaracion mensual que cruza todas las facturas de compra y venta
- **Formularios 103 y 104**: declaraciones mensuales de retenciones e IVA
- **Plan de cuentas NIIF PYMES**: estructura contable especifica para Ecuador
- **IESS y nomina Ecuador**: aportes personal y patronal, decimotercero, decimocuarto, fondos de reserva, utilidades, IR, RDEP

Embeber este compliance en Foundation lo acoplaria a Ecuador de forma irrevocable. Tratarlo como plugin tardio ignoraria que el pipeline de firma digital debe integrarse en el punto de emision del documento — no puede agregarse como capa externa post-hoc.

---

## Decision

PILAR implementa Foundation como una capa completamente country-agnostic. Todo el compliance especifico de Ecuador vive en Extension modules activables por empresa:

- **Foundation (migrations 001-009)**: autenticacion, multi-tenancy, roles, permisos, modulos, planes SaaS, secuencias, adjuntos, audit trail. Cero contenido especifico de ningun pais.
- **Core facturacion**: ciclo de vida generico de documentos — BORRADOR → CONFIRMADA → AUTORIZADA → ANULADA. Sin campos de autoridad fiscal, sin logica de firma.
- **Extension `facturacion_ec`**: todo el compliance SRI Ecuador — establecimientos, puntos de emision, secuenciales, cola de documentos electronicos, firma XAdES-BES, generacion de PDF (RIDE), almacenamiento de certificados, catalogos de tarifas SRI.
- **Extension `tributacion_ec`**: compliance fiscal exclusivamente ecuatoriano — ATS, F-103, F-104. No pertenece a Foundation ni a Core.

Esta arquitectura no es una evolucion hacia lo generico — **es generica desde el inicio**. Ecuador es el primer pais soportado porque sus extensiones ya estan implementadas, no porque Foundation sea ecuatoriana.

---

## Manifestaciones Especificas

### Foundation Country-Agnostic

Foundation (migrations 001-009) es completamente generico:

```
Foundation (001-009)
├── empresas   ← generico (sin campos de autoridad fiscal ni certificados)
├── roles      ← genericos
├── modulos    ← catalogo de modulos declarados
└── secuencias ← secuencias genericas (NO son secuenciales de autoridad fiscal)
```

Los campos especificos de cumplimiento fiscal (ambiente de autoridad, rutas de certificado, fecha de vencimiento del certificado) **no estan en Foundation**. Viven en la primera migracion de la Extension correspondiente via `ALTER TABLE empresas ADD COLUMN IF NOT EXISTS`.

### Split facturacion Core / Extension de pais

El modulo Core de facturacion implementa el ciclo de vida generico de documentos sin logica de autoridad fiscal. La Extension de pais lo extiende con toda la logica especifica:

```
facturacion (Core)
    └── facturacion_ec (Extension)  ← Ecuador: XAdES-BES, SOAP SRI, RIDE
    └── facturacion_co (Extension)  ← Colombia: DIAN (a implementar)
    └── facturacion_pe (Extension)  ← Peru: SUNAT (a implementar)
```

La Extension extiende las tablas del Core via `ALTER TABLE` e implementa o reemplaza las funciones del ciclo de vida con las versiones que orquestan el pipeline de la autoridad fiscal.

### Firma Digital Server-Side

La firma digital requiere la clave privada del certificado de la empresa — no puede ejecutarse en Flutter ni en el cliente. Se implementa en Edge Functions Deno dentro de la Extension correspondiente. Esta es una restriccion de seguridad, no una decision de conveniencia. El certificado nunca sale del servidor.

### Catalogos de Tarifas en Base de Datos con Vigencias

Las tarifas fiscales (impuestos, retenciones, formas de pago reconocidas) se almacenan en tablas de catalogo con campo `vigente_desde` en la Extension:

```sql
-- Cuando la autoridad fiscal cambia una tarifa: nueva fila, sin tocar datos historicos
INSERT INTO catalogo_tarifas (codigo, descripcion, porcentaje, vigente_desde)
VALUES ('codigo', 'Nueva tarifa', 15.00, '2024-04-01');
```

Los documentos historicos conservan la tarifa vigente al momento de su emision. Los cambios normativos no requieren cambios de schema.

### Datos de Inicializacion como Seed Data de la Extension

Los datos especificos del pais (plan de cuentas, parametros fiscales, roles locales) se inicializan al activar el modulo correspondiente via su `post_install_rpc`. No estan en Foundation.

### Auto-Registro de Modulos de Extension

Cada Extension de pais se auto-registra en su propia primera migracion — no se seedea en `foundation/migrations/`. Cada una incluye en su `001_*.sql` el `INSERT INTO modulos` y `INSERT INTO modulo_dependencias` correspondientes:

```sql
-- Fragmento de la primera migracion de una Extension de pais:
INSERT INTO modulos (id, nombre, tipo, version, descripcion)
VALUES ('<extension_pais>', 'Nombre Extension', 'extension', '1.0', 'descripcion')
ON CONFLICT (id) DO NOTHING;

INSERT INTO modulo_dependencias (modulo_id, depende_de, requerido)
VALUES ('<extension_pais>', 'facturacion', TRUE)
ON CONFLICT (modulo_id, depende_de) DO NOTHING;
```

Esto garantiza que si la Extension no esta en el build (empresa de otro pais), no se insertan registros huerfanos en las tablas del sistema. Foundation nunca referencia ninguna Extension directamente.

---

## Para Agregar Otro Pais

Dado que Foundation y Core son genericos, agregar soporte para un nuevo pais requiere unicamente:

1. Crear la Extension `facturacion_XX` con las tablas y el pipeline del pais (establecimientos, secuenciales, firma digital local, envio a autoridad fiscal)
2. Crear la Extension `tributacion_XX` con las declaraciones fiscales locales
3. Para un tenant del nuevo pais: activar `facturacion_XX` y `tributacion_XX`; no activar las extensiones de otros paises

Lo que no cambia al agregar otro pais:

- Foundation (001-009): sin modificaciones
- Core facturacion: sin modificaciones — el ciclo de vida generico ya funciona
- Todos los modulos Core: sin modificaciones
- Module Service Bus: los gateways genericos ya funcionan

---

## Alternativas Rechazadas

### 1. Plugin de Localizacion Total Posterior

Construir Foundation con logica de autoridad fiscal embebida y luego extraerla como plugin.

- El pipeline de firma digital requiere integracion en el punto de emision del documento — no se puede agregar como capa externa sin redisenar el flujo de confirmacion
- Las retenciones afectan la estructura de las tablas de documentos desde el inicio
- **Rechazado por**: la complejidad del compliance fiscal no es superficial; no cabe en un plugin que se agrega a posteriori sin romper el modelo de datos

### 2. Foundation Totalmente Generica con Configuracion JSON/YAML

Un ERP donde "tipo de documento", "clave de acceso" y "firma digital" son configurables via JSON de forma completamente abstracta.

- Sobre-ingenieria sin beneficio real: la separacion Foundation / Extension ya provee la flexibilidad necesaria
- La firma XAdES-BES es tan especifica que ningun modelo generico basado en configuracion la abstrae correctamente
- **Rechazado por**: YAGNI — el patron Extension ya resuelve el problema sin añadir una capa de configuracion que nadie mas usaria en v1.0

### 3. Compliance como Microservicio Externo

Consumir una API de facturacion de terceros via REST.

- Dependencia critica de negocio en un tercero fuera del control del producto
- Costo adicional por transaccion incompatible con el modelo SaaS de PILAR
- Menor control sobre la personalizacion de documentos y el manejo de errores de la autoridad fiscal
- **Rechazado por**: dependencia critica en funcionalidad no negociable + costo por transaccion que destruye el margen SaaS

---

## Consecuencias

### Positivas

- Foundation puede desplegarse para cualquier pais sin modificaciones — el aislamiento esta garantizado por diseño, no por convencion
- Los cambios de normativa fiscal se implementan en la Extension del pais sin tocar Foundation ni ningun otro modulo
- El ciclo de vida generico del Core de facturacion es reutilizable por cualquier modulo que emita documentos, sin acoplarse a la autoridad fiscal de ningun pais
- Los catalogos con `vigente_desde` permiten absorber cambios de tarifas sin migraciones de schema ni perdida de datos historicos
- La firma digital en Edge Function centraliza la seguridad del certificado: nunca sale del servidor

### Negativas / Restricciones

- El conocimiento de la normativa fiscal local es prerequisito para desarrollar la Extension del pais — curva de aprendizaje para nuevos developers
- Cada nueva version de los esquemas XSD de la autoridad fiscal requiere actualizar las Edge Functions de la Extension — mantenimiento continuo
- Los certificados digitales requieren rotacion y monitoreo de vencimiento — operacion adicional

### Mitigacion

- La documentacion especifica del pais (normativa, esquemas, flujos) reside en la Extension, no en Foundation — cada Extension es autodescriptiva
- El campo de fecha de vencimiento del certificado en la Extension permite alertas proactivas
- Agregar otro pais es crear una nueva Extension — el path esta abierto y no requiere modificar nada existente

---

## Referencias

- ADR-002 — Module Service Bus (gateways genericos usados por las Extensions de pais)
- ADR-005 — Supabase (PostgreSQL provee la precision DECIMAL requerida para calculos fiscales)
- ADR-009 — Sistema Modular (dependencias entre modulos, activate_module(), Extension pattern)
