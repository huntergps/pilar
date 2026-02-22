# Dashboard

## Descripción

Pantalla principal del ERP. Muestra KPIs en tiempo real, alertas activas y accesos rápidos adaptados al rol del usuario. Configurable por usuario/empresa.

## Tabla `dashboard_config_usuario`

```sql
CREATE TABLE dashboard_config_usuario (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id UUID NOT NULL REFERENCES auth.users(id),
  empresa_id UUID NOT NULL REFERENCES empresas(id),
  widgets    JSONB NOT NULL DEFAULT '[]',
    -- [{tipo, posicion, tamano, config}]
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(usuario_id, empresa_id)
);
```

## KPIs por Módulo

Cada KPI se calcula via RPC dedicada para performance. Usa Syncfusion Charts (`SfCartesianChart`, `SfCircularChart`).

### Ventas

| KPI | RPC | Visualización |
|-----|-----|---------------|
| Ventas del periodo (día/semana/mes) | `get_sales_summary(empresa_id, periodo)` | Card + sparkline |
| Ticket promedio | Ventas / Nro facturas | Card |
| Top 10 productos | `get_top_products(empresa_id, limite, periodo)` | Barras horizontales |
| Top 10 clientes | `get_top_customers(empresa_id, limite, periodo)` | Barras horizontales |
| Comparativo periodo anterior | `get_sales_comparison(empresa_id, periodo)` | Card con % cambio |
| Conversión cotización→factura | Facturas / Cotizaciones del periodo | Card con % |

### Finanzas

| KPI | RPC | Visualización |
|-----|-----|---------------|
| Flujo de caja proyectado | `project_cash_flow(empresa_id, dias)` | Línea temporal |
| DSO (Days Sales Outstanding) | CxC promedio / Ventas diarias | Card |
| DPO (Days Payable Outstanding) | CxP promedio / Compras diarias | Card |
| Aging CxC | `get_aging_report(empresa_id, 'CXC')` | Barras apiladas (0-30, 31-60, 61-90, 90+) |
| P&L resumido | `get_pyl_summary(empresa_id, periodo)` | Card (Ingresos - Gastos = Utilidad) |
| Saldo cuentas bancarias | `get_bank_balances(empresa_id)` | Cards por banco |

### Inventario

| KPI | RPC | Visualización |
|-----|-----|---------------|
| Valor de inventario | `get_inventory_value(empresa_id)` | Card |
| Productos bajo mínimo | `get_low_stock_products(empresa_id)` | Lista con alerta |
| Productos sin movimiento (>90 días) | `get_dead_stock(empresa_id, dias)` | Lista |

### POS

| KPI | RPC | Visualización |
|-----|-----|---------------|
| Ventas POS del día | `get_pos_daily_sales(empresa_id)` | Card + línea por hora |
| Sesiones activas | `get_active_pos_sessions(empresa_id)` | Cards |
| Arqueos pendientes | `get_pending_closings(empresa_id)` | Badge |

## Alertas (barra inferior)

- Productos bajo stock mínimo
- Facturas CxC vencidas (con monto total)
- Declaraciones tributarias pendientes
- Sesiones POS sin cerrar
- Contratos de servicio por vencer

## Plantillas por Rol

Cada rol del sistema tiene un dashboard predeterminado que se asigna automáticamente al usuario la primera vez que accede. El usuario puede personalizarlo después.

```sql
ALTER TABLE roles
  ADD COLUMN dashboard_plantilla_rol JSONB DEFAULT '[]';
  -- [{tipo: "kpi_card", config: {rpc: "...", params: {}}, posicion: 0, tamano: "small"}, ...]
```

| Rol | KPIs predeterminados |
|-----|---------------------|
| **GERENTE_GENERAL** | P&L resumen · Ventas vs presupuesto · Flujo de caja proyectado · DSO/DPO/margen · Alertas CxC/stock/tributarias |
| **VENDEDOR** | Mis ventas del mes · Meta vs real · Top clientes propios · Comisiones acumuladas · Cotizaciones pendientes |
| **CONTADOR** | Asientos pendientes · Conciliaciones pendientes · Periodos contables · Alertas tributarias · Aging CxC/CxP |
| **BODEGUERO** | Productos bajo mínimo · Transferencias pendientes · Recepciones programadas hoy · Órdenes ensamblaje en proceso |
| **CAJERO_POS** | Ventas de hoy · Ticket promedio · Items vendidos hoy · Sesión activa: monto en caja |

## Drill-Down en KPIs

Cada tarjeta KPI permite navegación al detalle (drill-down) al hacer tap.

```
Arquitectura:
  - Cada tarjeta KPI tiene onTap → navega a vista detalle
  - Cadena: KPI → lista filtrada → detalle registro
  - Ejemplo: "Ventas Mes $50K" → facturas del mes → detalle factura

Implementación go_router:
  /ventas/facturas?fecha_desde=2026-01-01&fecha_hasta=2026-01-31&estado=AUTORIZADA

Cada RPC de KPI retorna campo drill_down_url con parámetros pre-configurados:
  {
    "valor": 50000.00,
    "label": "Ventas Enero 2026",
    "drill_down_url": "/ventas/facturas?fecha_desde=2026-01-01&fecha_hasta=2026-01-31",
    "tendencia": "+12.5%"
  }

Widget PilarKpiCard:
  PilarKpiCard(
    title: kpi.label,
    value: kpi.valor,
    trend: kpi.tendencia,
    onTap: () => context.go(kpi.drill_down_url),
  )
```
