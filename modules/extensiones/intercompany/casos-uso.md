# CU-08: Holding empresarial

> Caso de uso de referencia para implementación de PILAR ERP en grupos económicos multi-empresa.
> Ver índice completo en [`foundation/casos-uso/README.md`](../../../foundation/casos-uso/README.md).

**Tipo de negocio**: Grupo económico con múltiples empresas relacionadas que realizan transacciones entre sí.

## Módulos activos

Todos los módulos Core activos en cada empresa del grupo, más:

| Módulo adicional | Rol en el negocio |
|-----------------|------------------|
| **Intercompany** (Auxiliar) | Transacciones entre empresas, documentos espejo, eliminación inter-compañía |

## Estructura multi-empresa

```
Grupo Económico XYZ
├── Empresa A: Importadora (Compras, Inventario, Ventas)
├── Empresa B: Distribuidora (Compras a A, Ventas al público)
├── Empresa C: Inmobiliaria (Activos Fijos, Proyectos, RRHH)
└── Empresa D: Holding (Contabilidad consolidada, Tesorería grupo)
```

## Flujos principales

1. **Venta intercompany (A vende a B)**:
   ```
   OV en Empresa A → Precio de transferencia →
   Factura electrónica tipo 01 (RUC de A → RUC de B) →
   OC espejo automática en Empresa B →
   Retención de B hacia A (si B es agente de retención) →
   Asientos en ambas empresas
   ```

2. **Consolidación financiera**:
   ```
   Cierre mensual de cada empresa →
   Eliminación de transacciones intercompany →
   Balance consolidado del grupo →
   Reporte para holding en formato Supercias
   ```

3. **Distribución de costos entre empresas**:
   ```
   RRHH compartido (personal que trabaja en varias empresas) →
   Asiento en Empresa A (empleador) →
   Cargo intercompany a Empresas B y C (proporcional a horas) →
   Facturas internas mensuales
   ```

## Consideraciones especiales

- Cada empresa tiene su propio RUC, certificado digital, establecimientos y secuencias SRI.
- Un mismo usuario puede tener roles distintos en cada empresa del grupo.
- Los precios de transferencia intercompany deben documentarse para cumplimiento del SRI (precios de mercado o acuerdos documentados).
- La consolidación elimina las transacciones entre empresas del grupo para presentar el balance como una sola entidad económica.
- El ATS de cada empresa incluye las facturas intercompany como cualquier otra transacción.
