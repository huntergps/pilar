# Consideraciones Técnicas y Roadmap IA


## Costos, Latencia, Limites

### Modelo de Embeddings

| Parametro | Valor |
|-----------|-------|
| Provider | OpenAI (text-embedding-3-small) |
| Dimensiones | 1536 |
| Costo | $0.02 / 1M tokens (~$0.00002 por embedding) |
| Latencia | 50-100ms por embedding |
| Indice | IVFFlat (cosine similarity), lists=100 |
| Tamano estimado | ~6KB por embedding (1536 x float32) |

**Estimacion para empresa mediana (1000 productos, 5000 clientes, 500 facturas/mes):**
- Embeddings iniciales: ~6500 registros x $0.00002 = ~$0.13
- Embeddings mensuales (facturas nuevas): ~500 x $0.00002 = ~$0.01/mes
- Storage: ~6500 x 6KB = ~39MB

### Modelo LLM (Chat e Interpretacion)

| Parametro | Valor |
|-----------|-------|
| Provider | Anthropic |
| Modelo | claude-sonnet-4-20250514 |
| Costo input | $3 / 1M tokens |
| Costo output | $15 / 1M tokens |
| Latencia | 500-2000ms (primera respuesta) |
| Context window | 200K tokens |

**Estimacion de uso mensual por empresa:**
- Chat: ~200 consultas/mes x ~1000 tokens avg = 200K tokens = ~$0.60 input + ~$3.00 output = ~$3.60/mes
- Interpretaciones: ~50 solicitudes/mes x ~500 tokens = 25K tokens = ~$0.08 input + ~$0.38 output = ~$0.46/mes
- **Total LLM: ~$4.06/mes por empresa**

### Estrategias de Optimizacion de Costos

1. **PostgreSQL-first:** Todos los calculos estadisticos (forecast, scoring, churn, anomalias) se ejecutan en PostgreSQL sin llamar a LLM. Solo se llama a LLM para interpretacion textual y chat NLP.

2. **Caching:** Resultados de vistas materializadas se cachean. Refresh programado (no en tiempo real). Los forecasts se persisten en `ia_predictions` y se reusan si tienen <24h.

3. **Token budget:** Cada empresa tiene un limite diario configurable (`max_tokens_dia` en `ia_model_config`). Default: 50,000 tokens/dia (~$0.20/dia).

4. **Modelo escalonado:** Usar claude-sonnet-4-20250514 para chat (rapido, barato). Solo usar claude-opus-4-6 para analisis complejos si el usuario lo solicita explicitamente.

5. **Embeddings batch:** Generar embeddings en batch durante cron nocturno, no en tiempo real para cada INSERT.

6. **Graceful degradation:** Si se agotan tokens o la API falla, las funciones SQL siguen trabajando. Solo se pierde la interpretacion en lenguaje natural.

### Limites y Restricciones

| Restriccion | Valor | Razon |
|-------------|-------|-------|
| Max tokens/dia por empresa | 50,000 (configurable) | Control de costos |
| Max mensajes/conversacion | 100 | Performance |
| Max conversaciones activas/usuario | 10 | Storage |
| Historico de predicciones | 365 dias, luego purge | Storage |
| Refresh MV minimo | 1 vez/dia | Performance DB |
| Max resultados query IA | 100 filas | Tokens LLM |
| Min datos para forecast | 90 dias historico | Precision |
| Min datos para churn | 3 compras del cliente | Significancia |
| Timeout Edge Function | 25 segundos | Supabase limit |
| SQL injection proteccion | Whitelist de operaciones | Seguridad |

### Seguridad

1. **Multi-tenancy:** Toda tabla IA tiene `empresa_id` + RLS. Las funciones SQL usan `SECURITY DEFINER` con verificacion explicita de `empresa_id`.

2. **SQL Injection:** La funcion `execute_ai_query` rechaza cualquier operacion DDL o DML. Solo permite SELECT. Los parametros se pasan posicionalmente, nunca concatenados.

3. **API Keys:** Se almacenan en Supabase Vault, nunca en tablas regulares. La columna `api_key_vault` contiene solo la referencia al secret.

4. **Audit trail:** Todas las interacciones del chat se registran en `ai_messages`. Todas las acciones ejecutadas via IA se marcan con `origen = 'AI_AGENT'` en `registro_actividad`.

5. **Confirmacion obligatoria:** Cualquier accion que modifique datos requiere confirmacion explicita del usuario en la UI. El chat nunca ejecuta acciones destructivas automaticamente.

6. **Rate limiting:** Max 60 requests/minuto por usuario, implementado en `ai-gateway`.

---

## Roadmap de Implementacion IA

### Fase 1: Infraestructura (P2, mes 1-2)

| Tarea | Dependencia | Esfuerzo |
|-------|-------------|----------|
| Crear tablas comunes IA (22.2) | Core Foundation | 2 dias |
| Crear vistas materializadas | Datos transaccionales existentes | 3 dias |
| Configurar pg_cron para refresh | Supabase | 1 dia |
| Implementar ia_model_config + token tracking | Auth + Vault | 2 dias |
| Seed calendario estacional Ecuador | Ninguna | 1 dia |
| Edge Function ai-gateway (auth + routing) | Auth | 2 dias |

### Fase 2: Funciones Estadisticas (P2, mes 2-3)

| Tarea | Dependencia | Esfuerzo |
|-------|-------------|----------|
| fn_forecast_ventas | mv_ventas_diarias | 3 dias |
| fn_scoring_crm | mv_customer_metrics, oportunidades_crm | 3 dias |
| fn_detectar_churn | mv_customer_metrics | 2 dias |
| fn_reabastecimiento_inteligente | mv_demanda_producto | 3 dias |
| fn_detectar_anomalias_stock | mv_abc_classification | 2 dias |
| fn_detectar_anomalias_gastos | mv_gastos_historico | 2 dias |
| fn_proyeccion_flujo_caja | mv_cashflow_projection | 3 dias |
| fn_prediccion_ausentismo | mv_hr_attendance_patterns | 2 dias |
| fn_detectar_horas_extras_anomalas | mv_hr_overtime | 2 dias |
| fn_what_if_inventario | mv_abc_classification | 2 dias |
| fn_precio_sugerido | ia_historial_precios | 2 dias |
| Module Bus: request_ia_analysis | Todas las fn_* | 1 dia |

### Fase 3: Edge Functions + LLM (P2, mes 3-4)

| Tarea | Dependencia | Esfuerzo |
|-------|-------------|----------|
| Edge Function ai-forecast | fn_forecast_*, fn_scoring_*, fn_churn | 3 dias |
| Edge Function ai-anomaly | fn_anomalias_* | 2 dias |
| Edge Function ai-cashflow | fn_proyeccion_flujo_caja | 2 dias |
| Edge Function ai-hr | fn_ausentismo, fn_he | 2 dias |
| Edge Function ai-chat (NLP completo) | ia_skills, ai_conversations | 5 dias |
| Seed de skills fundamentales | ia_skills | 2 dias |
| Funcion execute_ai_query (sandbox) | Ninguna | 1 dia |
| Edge Function ai-refresh-mv | Todas las MVs | 1 dia |

### Fase 4: Flutter UI (P2, mes 4-5)

| Tarea | Dependencia | Esfuerzo |
|-------|-------------|----------|
| Widget Chat IA (panel lateral) | ai-chat Edge Function | 5 dias |
| Dashboard IA Ventas (forecast + churn + scoring) | ai-forecast | 5 dias |
| Dashboard IA Inventario (reabastecimiento + anomalias + ABC + what-if) | ai-anomaly | 5 dias |
| Dashboard IA Finanzas (anomalias + categorizacion + cashflow) | ai-cashflow | 4 dias |
| Dashboard IA RRHH (ausentismo + HE) | ai-hr | 3 dias |
| Integracion con notificaciones (alertas IA → push/email) | Sistema notificaciones existente | 2 dias |

### Fase 5: Refinamiento (P2, mes 5-6)

| Tarea | Dependencia | Esfuerzo |
|-------|-------------|----------|
| Feedback loop (ia_feedback → mejora modelos) | UI + ia_predictions | 3 dias |
| Backfill de valor_real en ia_predictions | Datos reales post-prediccion | 2 dias |
| Dashboard de accuracy (% acierto por tipo) | ia_predictions + valor_real | 2 dias |
| Optimizacion de queries (EXPLAIN ANALYZE) | Todas las funciones | 3 dias |
| Testing con datos reales de empresa piloto | Todo | 5 dias |

### Resumen de Esfuerzo

| Fase | Esfuerzo | Acumulado |
|------|----------|-----------|
| 1. Infraestructura | 11 dias | 11 dias |
| 2. Funciones SQL | 25 dias | 36 dias |
| 3. Edge Functions | 18 dias | 54 dias |
| 4. Flutter UI | 24 dias | 78 dias |
| 5. Refinamiento | 15 dias | 93 dias |
| **TOTAL** | **93 dias** | ~4.5 meses (1 desarrollador) |

**Con 2 desarrolladores en paralelo (backend + frontend):** ~2.5-3 meses.

---

## Resumen de Artefactos

### Tablas Nuevas (8)
1. `ia_model_config` - Configuracion de modelos IA por empresa
2. `ia_predictions` - Historico de predicciones
3. `ia_feedback` - Feedback de usuarios
4. `ia_token_usage` - Tracking de consumo de tokens
5. `ia_calendario_estacional` - Eventos estacionales Ecuador
6. `ia_historial_precios` - Historial de cambios de precio
7. `ia_reabastecimiento_config` - Config de reabastecimiento por producto
8. `ia_anomalias_stock` - Anomalias de inventario detectadas
9. `ia_gastos_recurrentes` - Patrones de gasto recurrente
10. `ia_skills` - Skills del chat IA
11. `ia_intent_examples` - Ejemplos de intent para NLP

### Tablas Modificadas (2)
1. `alertas_anomalias` - Campos adicionales: modulo, subtipo, accion_sugerida, feedback
2. `ai_conversations` + `ai_messages` - Campos adicionales

### Vistas Materializadas (7)
1. `mv_ventas_diarias` - Ventas diarias por producto
2. `mv_customer_metrics` - Metricas por cliente
3. `mv_demanda_producto` - Demanda diaria por producto
4. `mv_abc_classification` - Clasificacion ABC
5. `mv_gastos_historico` - Gastos por proveedor/cuenta
6. `mv_cashflow_projection` - Proyeccion de flujo de caja
7. `mv_hr_attendance_patterns` - Patrones de asistencia
8. `mv_hr_overtime` - Horas extras por empleado

### Funciones PostgreSQL (11)
1. `fn_factor_estacional` - Helper de estacionalidad Ecuador
2. `fn_forecast_ventas` - Prediccion de ventas
3. `fn_scoring_crm` - Scoring de oportunidades
4. `fn_detectar_churn` - Deteccion de abandono
5. `fn_precio_sugerido` - Analisis de elasticidad
6. `fn_reabastecimiento_inteligente` - Punto de reorden optimo
7. `fn_detectar_anomalias_stock` - Anomalias de inventario
8. `fn_what_if_inventario` - Simulacion de escenarios
9. `fn_detectar_anomalias_gastos` - Anomalias contables
10. `fn_proyeccion_flujo_caja` - Proyeccion cashflow
11. `fn_prediccion_ausentismo` - Prediccion RRHH
12. `fn_detectar_horas_extras_anomalas` - HE anomalas
13. `execute_ai_query` - Sandbox SQL para chat
14. `module_bus.request_ia_analysis` - Gateway Module Bus

### Edge Functions (9)
1. `ai-gateway` - Router + auth + rate limiting
2. `ai-forecast` - Predicciones de ventas/CRM
3. `ai-anomaly` - Deteccion de anomalias
4. `ai-chat` - Chat NLP conversacional
5. `ai-cashflow` - Proyeccion flujo de caja
6. `ai-hr` - Analisis RRHH
7. `ai-embed` - Embeddings (existente)
8. `ai-query` - RAG queries (existente)
9. `ai-refresh-mv` - Refresh de MVs

### Cron Jobs (11)
7 refresh de MVs diarios + 1 ABC mensual + deteccion anomalias semanal + scoring CRM semanal + churn quincenal + RRHH mensual + reset tokens diario

---

*Documento generado a partir del analisis exhaustivo de los esquemas XSD oficiales del SRI Ecuador (Version 2.32, Octubre 2025), la ficha tecnica de comprobantes electronicos, la ficha tecnica del ATS, investigacion de pasarelas de pago para Ecuador, y analisis del ecosistema brick_offline_first_with_supabase.*

*Version 17.0 - Incluye: Core Foundation (Capa Base), Module Service Bus (comunicacion desacoplada), Offline-first (Brick), pgvector IA, Pasarelas de Pago (Kushki/Paymentez), POS con control de stock, BOM/Ensamblaje, Multi-bodega (principal+alternas, auto-transferencia), Multi-empaque/codigos de barras, SaaS Admin como app separada, Ecommerce (WooCommerce + Multi-Marketplace), Cola de documentos electronicos, Notificaciones multi-canal (email/WhatsApp/Telegram), Validacion XSD, Chat interno + IA Avanzada, Supabase Realtime, UI responsive, Monitor conectividad, Supabase Best Practices, Precision numerica y zonas horarias, Documentos contables Ecuador, Garantias/RMA y Taller, Servicios/Contratos, RRHH completo, CxC/CxP, Direcciones Entrega, Variantes, Listas Precios, Posiciones Fiscales, PilarShell Framework, fluent_ui NavigationView, Gestion de Citas (Belleza/Spa), Lealtad/Cupones/Suscripciones, BOM Multi-nivel, Control de Calidad (QC), Forecast Demanda, Multi-Marketplace (MercadoLibre/Shopify), Transacciones Intercompany, Portal Autoservicio Clientes, IA Avanzada (Ventas/Inventario/Contabilidad/Chat/RRHH).*
