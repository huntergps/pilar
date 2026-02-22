# Localización Ecuador

Documentación específica para PILAR ERP en Ecuador. Estos archivos son **extensiones
country-specific** y NO son parte de foundation genérica (ADR-006).

Los módulos técnicos están en `modules/extensiones/facturacion_ec/` y `modules/extensiones/tributacion_ec/`.
Este directorio contiene documentación de referencia y auditoría.

## Archivos

| Archivo | Descripción |
|---------|-------------|
| `glosario-ec.md` | Glosario Ecuador: SRI, RUC, RIDE, ATS, XAdES-BES, LOPDP, IVA Ecuador, retenciones, NANDINA, CIIU, organismos reguladores |
| `campos-foundation-ec.md` | Campos Ecuador-specific que permanecen en foundation (deuda técnica documentada) |
| `campos-entidades-ec.md` | Campos Ecuador-specific en módulo entidades (contactos, productos) |
| `integraciones-ec.md` | Integraciones específicas Ecuador: BCE, SRI, bancos locales |
| `datos-referencia-ec.md` | Catálogos Ecuador: formas de pago SRI, tipos identificación, provincias INEC, tarifas IVA, retenciones, parámetros tributarios |
| `lopdp.md` | Cumplimiento LOPDP — Ley Orgánica de Protección de Datos Personales: consentimiento, derecho al olvido, portabilidad, retención de datos |
| `zonas-horarias-ec.md` | Zonas horarias Ecuador: America/Guayaquil (UTC-5) y Pacific/Galapagos (UTC-6), configuración por defecto, casos de uso multi-zona, tests pgTAP, validaciones SRI fecha_emision |
