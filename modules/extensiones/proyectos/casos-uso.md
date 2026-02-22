# CU-07: Empresa constructora

> Caso de uso de referencia para implementación de PILAR ERP en construcción y gestión de proyectos.
> Ver índice completo en [`foundation/casos-uso/README.md`](../../../foundation/casos-uso/README.md).

**Tipo de negocio**: Constructora que ejecuta proyectos habitacionales y de infraestructura.

## Módulos activos

| Módulo | Rol en el negocio |
|--------|------------------|
| **Facturación** (Core) | Facturas por avance de obra, anticipos, planillas |
| **Ventas** (Core) | Contratos de venta de unidades habitacionales |
| **Compras** (Core) | Materiales de construcción, subcontratistas, importaciones |
| **Inventario** (Core) | Materiales por bodega/proyecto, BOM de construcción |
| **Contabilidad** (Core) | Costeo por proyecto, centros de costo, informes Supercias |
| **Tesorería** (Core) | Flujo de caja por proyecto, anticipos bancarios |
| **Tributación** (Core) | ATS, planilla IESS, IR relación dependencia |
| **Proyectos** (Auxiliar) | Cronogramas, tareas, Gantt, avance físico vs financiero |
| **RRHH** (Auxiliar) | Personal de obra, nómina con IESS, subcontratistas |
| **Activos Fijos** (Auxiliar) | Maquinaria pesada, depreciación, mantenimiento |
| **Consumibles** (Auxiliar) | Herramientas y EPP para el personal de obra |

## Flujos principales

1. **Planificación de proyecto**:
   ```
   Contrato con cliente → Proyecto creado →
   Plan de cuentas por proyecto (centro de costo) →
   Presupuesto de obra (BOM multi-nivel: materiales + MO + subcontratos) →
   Cronograma Gantt con hitos de cobro
   ```

2. **Ejecución y control**:
   ```
   OC materiales por proyecto → Recepción en bodega del proyecto →
   Consumo por tarea → Costo real vs presupuesto (semáforo) →
   Nómina semanal de obreros por centro de costo →
   Horas-máquina de activos fijos por proyecto
   ```

3. **Facturación por avance**:
   ```
   Fiscalizador aprueba avance (% obra) →
   Factura de planilla al cliente (tipo 01) →
   Anticipo imputado a la planilla →
   Cobro → Flujo de caja actualizado
   ```

## Consideraciones especiales

- Proyectos multi-año: cierre de período contable sin cerrar el proyecto.
- Importaciones de materiales especializados con costos de aterrizaje (módulo Compras).
- Presupuesto vs real: alerta automática si el costo supera el 80% del presupuesto antes del 70% de avance físico.
- Subcontratistas tratados como proveedores con liquidaciones de compra (tipo 03) si son personas naturales.
