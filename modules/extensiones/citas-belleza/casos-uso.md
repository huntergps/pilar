# CU-03: Salón de belleza

> Caso de uso de referencia para implementación de PILAR ERP en servicios de belleza.
> Ver índice completo en [`foundation/casos-uso/README.md`](../../../foundation/casos-uso/README.md).

**Tipo de negocio**: Salón de belleza con múltiples especialistas, venta de productos y agenda online.

## Módulos activos

| Módulo | Rol en el negocio |
|--------|------------------|
| **Facturación** (Core) | Facturas por servicios y productos vendidos |
| **Inventario** (Core) | Productos de reventa + insumos consumidos en servicios |
| **Tesorería** (Core) | Caja del día, formas de pago múltiples |
| **Citas/Belleza** (Auxiliar) | Agenda, especialistas, recordatorios, tiempo de servicio |
| **POS** (Auxiliar) | Cobro en mostrador integrado con citas completadas |
| **RRHH** (Auxiliar) | Empleados, nómina, comisiones por servicios/ventas |
| **Consumibles** (Auxiliar) | Tinte, tratamientos, insumos: solicitud → entrega → egreso |

## Flavors Flutter

PILAR Citas/Belleza usa tres apps separadas (un solo codebase, 3 entry points):
- **`erp`**: Web/Desktop para la administración del salón (dueño/administrador).
- **`salon`**: iOS/Android para especialistas (ver agenda propia, marcar servicio completado).
- **`cliente`**: iOS/Android white-label por salón (los clientes agendan citas y ven historial).

## Flujos principales

1. **Agendamiento de cita**:
   ```
   Cliente selecciona servicio + especialista + horario (app cliente o web) →
   Confirmación por WhatsApp → Recordatorio 24h y 1h antes →
   Especialista marca "llegó" + "en progreso" + "completado" →
   POS cobra automáticamente los servicios de la cita
   ```

2. **Gestión de consumibles**:
   ```
   Especialista solicita insumos para el servicio →
   Administrador aprueba y entrega →
   Salida de inventario y registro de costo del servicio
   ```

## Consideraciones especiales

- Servicios con duración variable (15 min corte express, 3h coloración completa).
- Comisiones de especialistas por servicio prestado + porcentaje de productos vendidos.
- White-label de la app cliente: logo, colores y nombre del salón desde `salon_perfiles_publicos`.
- Push notifications (FCM) para recordatorios y confirmaciones.
