# LOPDP — Ley Orgánica de Protección de Datos Personales (Ecuador)

> **Ecuador-específico.** Este documento es parte de la localización Ecuador (`modules/localizacion/ecuador/`).
> El cumplimiento genérico de privacidad de datos está en `foundation/seguridad.md`.

---

## Marco Legal

Vigente desde mayo 2023. Multas hasta 1% de facturación anual.

PILAR implementa los siguientes controles para el cumplimiento de la LOPDP:

---

## Controles Implementados

### 1. Consentimiento informado

- Al registrar un contacto (cliente/proveedor), se muestra aviso de privacidad
- Campo `consentimiento_datos BOOLEAN DEFAULT false` en tabla contactos
- Campo `fecha_consentimiento TIMESTAMPTZ` en tabla contactos
- Sin consentimiento, solo se almacenan datos necesarios para obligaciones legales (SRI)

### 2. Derecho de acceso

- RPC `get_personal_data(contacto_id)`: retorna TODOS los datos del titular en formato JSON
- Incluye: datos basicos, direcciones, facturas, CxC, contratos, ordenes

### 3. Derecho de eliminación/olvido

- RPC `anonymize_contact(contacto_id)`: anonimiza datos personales
- NO elimina fisicamente (documentos SRI deben conservarse 7 anios por obligacion tributaria)
- Reemplaza: nombre -> "ANONIMIZADO", email -> null, telefono -> null, direccion -> "DATOS ELIMINADOS"
- Mantiene: RUC/cedula (obligacion tributaria), facturas (trazabilidad SRI)

### 4. Portabilidad de datos

- RPC `export_personal_data(contacto_id)`: genera JSON/CSV con todos los datos del titular
- Edge Function que genera archivo ZIP cifrado descargable

### 5. Registro de actividades de tratamiento

- Tabla audit_log registra TODOS los accesos y modificaciones a datos personales
- Reporte `reporte_tratamiento_datos`: quien accedio, cuando, que datos, con que proposito

### 6. Minimización de datos

- Solo se recopilan datos necesarios para la operacion del negocio
- Campos opcionales claramente marcados en formularios
- Datos de tarjetas de credito NUNCA se almacenan (solo tokens de Kushki/Paymentez)

---

## Relación con otros módulos Ecuador

- **Módulo `facturacion_ec`**: los documentos electrónicos autorizados por el SRI no pueden anonimizarse ni eliminarse (obligación tributaria supera el derecho al olvido cuando existe base legal). Ver `modules/extensiones/facturacion_ec/module.md`.
- **Módulo `tributacion_ec`**: las declaraciones 103/104 y ATS contienen datos de terceros protegidos por LOPDP. Ver `modules/extensiones/tributacion_ec/module.md`.

---

## Retención de Datos

| Tipo de dato | Plazo mínimo | Base legal |
|---|---|---|
| Documentos electrónicos SRI (facturas, NC, ND, retenciones, guías) | 7 años | Código Tributario Art. 94 |
| Datos personales de contactos sin relación activa | Hasta revocación de consentimiento | LOPDP Art. 22 |
| Audit log de accesos a datos personales | 3 años | LOPDP Art. 30 |

---

## Referencias

- Ley Orgánica de Protección de Datos Personales (RO Suplemento 459, 26-may-2021)
- Reglamento LOPDP (DS 1063, 2023)
- Código Tributario Ecuador — Art. 94 (conservación de archivos)
