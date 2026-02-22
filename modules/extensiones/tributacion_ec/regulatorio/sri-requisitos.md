# Requisitos SRI Ecuador


### Documentos Electronicos Obligatorios

El SRI de Ecuador exige la emision electronica de los siguientes comprobantes, todos analizados a partir de los XSD oficiales presentes en el proyecto:

| Cod | Documento | Versiones Disponibles | Version Recomendada |
|-----|-----------|----------------------|---------------------|
| 01 | Factura | V1.0.0, V1.1.0, V2.0.0, V2.1.0 | **V2.1.0** |
| 03 | Liquidacion de Compra | V1.0.0, V1.1.0 | **V1.1.0** |
| 04 | Nota de Credito | V1.0.0, V1.1.0 | **V1.1.0** |
| 05 | Nota de Debito | V1.0.0 | **V1.0.0** |
| 06 | Guia de Remision | V1.0.0, V1.1.0 | **V1.1.0** |
| 07 | Comprobante de Retencion | V1.0.0, V2.0.0 | **V2.0.0** |

### Impuestos Soportados

| Codigo | Impuesto | Descripcion |
|--------|----------|-------------|
| 2 | IVA | Impuesto al Valor Agregado (15% vigente desde abril 2024) |
| 3 | ICE | Impuesto a los Consumos Especiales |
| 5 | IRBPNR | Impuesto Redimible Botellas Plasticas No Retornables |

### Porcentajes IVA Historicos (necesarios para periodos anteriores)

| Porcentaje | Vigencia |
|------------|----------|
| 12% | 01/01/2000 - 31/05/2016 |
| 14% | 01/06/2016 - 31/05/2017 |
| 12% | 01/06/2017 - 31/03/2024 |
| **15%** | **01/04/2024 - vigente** |
| 5% | 01/04/2024 - vigente (tarifa diferenciada) |
| 8% | Feriados (variable) |

### Tarifas IVA - Codigos SRI para XML Electronico

| Porcentaje | Codigo SRI | Uso en XML |
|------------|-----------|------------|
| 0% | 0 | Base tarifa 0% |
| 12% | 2 | Periodos anteriores |
| 14% | 3 | Periodo jun 2016 - may 2017 |
| **15%** | **4** | **Vigente desde abril 2024** |
| 5% | 5 | Tarifa diferenciada |
| No Objeto de Impuesto | 6 | Sin impuesto |
| Exento de IVA | 7 | Exento |
| IVA diferenciado | 8 | Tarifa especial |
| 13% | 10 | Tarifa intermedia |

### Codigos de Retencion IVA e ISD

**Retenciones IVA (Tabla 20 SRI):**

| Porcentaje | Codigo | Caso de Aplicacion |
|-----------|--------|-------------------|
| 10% | 9 | Agente retencion CE compra bienes a otro CE |
| 20% | 10 | Agente retencion CE compra servicios a otro CE |
| 30% | 1 | Consumo gravado transferencia bienes y construccion |
| 50% | 11 | Exportadores recursos naturales, servicios, comisiones |
| 70% | 2 | Consumo gravado prestacion servicios |
| 100% | 3 | Servicios profesionales, arriendo inmuebles PN, liquidaciones compra |
| 0% (no procede) | 8 | No procede retencion |
| 0% (en cero) | 7 | Retencion en cero |

**Retenciones ISD:**

| Porcentaje | Codigo | Vigencia |
|-----------|--------|----------|
| 5% | 4580 | Desde abril 2024 |
| 2.5% | 4586 | Desde mayo 2025 |

### Tipos de Identificacion

| Codigo SRI | Codigo CE | Tipo |
|------------|-----------|------|
| 01 / 04 | 04 | RUC |
| 02 / 05 | 05 | Cedula |
| 03 / 06 | 06 | Pasaporte |
| 07 | 07 | Consumidor Final |
| 08 | 08 | Identificacion del Exterior |

### Formas de Pago (Codigos 01-21)

| Codigo | Forma de Pago |
|--------|---------------|
| 01 | Sin utilizacion del sistema financiero |
| 15 | Compensacion de deudas |
| 16 | Tarjeta de credito nacional |
| 17 | Tarjeta de credito internacional |
| 18 | Tarjeta de debito nacional |
| 19 | Tarjeta de debito internacional |
| 20 | Otros con utilizacion del sistema financiero |
| 21 | Endoso de titulos |

### Codigos de Sustento Tributario (para compras)

| Codigo | Descripcion |
|--------|-------------|
| 01 | Credito tributario: servicios/bienes distintos inventarios y activos fijos |
| 02 | Costo/gasto: bienes gravados sin credito tributario |
| 03 | Credito tributario: activos fijos gravados |
| 04 | Costo/gasto: activos fijos sin credito tributario |
| 05 | Gastos viaje, hospedaje, alimentacion |
| 06 | Credito tributario: inventario gravado |
| 07 | Costo/gasto: inventario sin credito tributario |
| 08 | Reembolso de gastos |
| 09 | Gastos medicos y medicina prepagada |
| 10 | Dividendos y utilidades |
| 11 | Instituciones financieras como agentes retencion |
| 12 | Retenciones presuntivas |
| 13 | Valores reconocidos sector publico |
| 14 | Valores facturados socios a operadoras transporte |
| 15 | Servicios digitales propios y terceros |

### ATS (Anexo Transaccional Simplificado)

Declaracion informativa mensual/semestral que consolida:

- **Compras**: Desglose comprobante por comprobante con bases imponibles, retenciones IVA/Renta
- **Ventas**: Agrupadas por cliente + tipo comprobante + tipo emision
- **Exportaciones**: Con datos de refrendo aduanero
- **Anulados**: Rangos de comprobantes anulados
- **RECAP**: Tarjetas de credito (emisores)
- **Fideicomisos**: Operaciones fiduciarias
- **Rendimientos Financieros**: Instituciones financieras

**Formato**: XML comprimido en ZIP, codificacion ISO-8859-1, nombre `ATmmaaaa.zip`

---

