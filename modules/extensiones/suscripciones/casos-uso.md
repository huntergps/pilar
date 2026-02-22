# CU-04: ISP/Telecomunicaciones

> Caso de uso de referencia para implementación de PILAR ERP en servicios de internet/telecomunicaciones.
> Ver índice completo en [`foundation/casos-uso/README.md`](../../../foundation/casos-uso/README.md).

**Tipo de negocio**: Proveedor de servicios de internet con clientes residenciales y empresariales.

## Módulos activos

| Módulo | Rol en el negocio |
|--------|------------------|
| **Facturación** (Core) | Facturas mensuales masivas, NC por cortes proporcionales |
| **Contabilidad** (Core) | Asientos de ingresos recurrentes, provisiones |
| **Tesorería** (Core) | Recaudación masiva, conciliación de pagos online |
| **Tributación** (Core) | ATS mensual con volumen alto de transacciones |
| **Suscripciones** (Auxiliar) | Planes, contratos, facturación automática, portal clientes |
| **Servicio de Campo** (Auxiliar) | Instalaciones, cortes, reinstalaciones, mantenimiento |
| **RRHH** (Auxiliar) | Técnicos de campo, turnos rotativos, nómina |
| **CRM** (Auxiliar) | Prospección de nuevos clientes, gestión de reclamos |

## Flujos principales

1. **Alta de nuevo cliente**:
   ```
   Prospecto CRM → Contrato Suscripción (plan elegido) →
   Orden de Campo INSTALACION → Técnico asignado (app móvil) →
   Instalación con foto de evidencia y firma digital del cliente →
   Contrato activado → Primer factura prorrateada → Email bienvenida
   ```

2. **Facturación masiva mensual**:
   ```
   Cron mensual (1ero de cada mes) → Genera facturas por contrato activo →
   Envío masivo por email/WhatsApp → Recordatorio día 5 →
   Corte automático día 10 si no pagó → Orden de Campo CORTE
   ```

3. **Proceso de corte y reinstalación**:
   ```
   Contrato en mora → Orden de Campo CORTE (técnico deshabilita) →
   Cliente paga (portal online) → Contrato activo → Orden de Campo REINSTALACION →
   NC proporcional por días sin servicio (automática)
   ```

4. **Soporte técnico**:
   ```
   Reclamo CRM → Diagnóstico remoto → Si requiere visita: Orden de Campo REVISION →
   Técnico con app móvil (historial equipos, guía solución) →
   Cierre con firma digital del cliente
   ```

## Consideraciones especiales

- `equipos_cliente` en Suscripciones: router/antena/ONT en comodato con link a Activos Fijos.
- SLA con alertas de breach al 80%: WhatsApp automático al técnico y supervisor.
- Facturación prorrateada: si el cliente sube de plan a mitad de mes, NC + nueva factura proporcional.
- Integración con n8n para despacho masivo de notificaciones de cobro.
