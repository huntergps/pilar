# Estructura de Archivos del Proyecto

```
pilar/
├── lib/                              # Codigo Dart principal
│   ├── main_erp.dart                 # Entry point: PILAR ERP completo (20 modulos)
│   ├── main_salon.dart               # Entry point: App Salon (admin + empleados)
│   ├── main_cliente.dart             # Entry point: App Cliente del salon
│   ├── app.dart                      # PilarApp (MaterialApp.router + GoRouter, por flavor)
│   │
│   ├── core/                         # Nucleo compartido (los 3 flavors lo usan)
│   │   ├── config/
│   │   │   ├── supabase_config.dart  # Inicializacion Supabase
│   │   │   ├── app_flavor.dart       # Enum AppFlavor (erp|salon|cliente) + FlavorConfig
│   │   │   ├── app_constants.dart    # Constantes (URLs SRI, etc.)
│   │   │   └── theme.dart            # Material 3 theme + white-label dinamico
│   │   ├── brick/                    # Modelos Brick (offline-first)
│   │   │   ├── models/              # @ConnectOfflineFirstWithSupabase
│   │   │   │   ├── empresa.model.dart
│   │   │   │   ├── contacto.model.dart
│   │   │   │   ├── producto.model.dart
│   │   │   │   ├── factura.model.dart
│   │   │   │   ├── retencion.model.dart
│   │   │   │   └── asiento_contable.model.dart
│   │   │   ├── repository.dart      # Singleton OfflineFirstWithSupabaseRepository
│   │   │   ├── brick.g.dart         # Generado: model dictionaries
│   │   │   ├── adapters/            # Generado: adaptadores SQLite + Supabase
│   │   │   └── db/                  # Generado: schema + migrations SQLite
│   │   ├── shell/                    # Framework PilarShell (layout adaptativo)
│   │   │   ├── pilar_app.dart        # MaterialApp con auto-scaling + flex_color_scheme
│   │   │   ├── pilar_shell.dart      # Layout adaptativo (header+nav+content+footer)
│   │   │   ├── pilar_header.dart     # Barra superior adaptativa
│   │   │   ├── pilar_navigation.dart # Sidebar/Rail/Drawer/BottomNav unificado
│   │   │   ├── pilar_footer.dart     # Barra inferior informativa
│   │   │   ├── pilar_route.dart      # Modelo de ruta con permisos y builders
│   │   │   ├── pilar_route_config.dart # Definicion de todas las rutas
│   │   │   ├── pilar_breadcrumbs.dart  # Breadcrumbs automaticos
│   │   │   └── pilar_breakpoint.dart   # Enum + deteccion breakpoint
│   │   ├── providers/                # Riverpod providers globales
│   │   │   ├── auth_provider.dart
│   │   │   ├── empresa_provider.dart
│   │   │   ├── repository_provider.dart  # Provee Brick Repository
│   │   │   ├── theme_provider.dart       # Tema + flex_color_scheme + densidad
│   │   │   ├── preferences_provider.dart # Persistencia local (shared_preferences)
│   │   │   ├── connection_provider.dart  # Monitor estado de conexion
│   │   │   ├── tabs_provider.dart        # Estado de tabs abiertos
│   │   │   ├── permissions_provider.dart # Permisos del usuario actual
│   │   │   ├── navigation_provider.dart  # Ruta activa + breadcrumbs
│   │   │   └── breakpoint_provider.dart  # Breakpoint actual reactivo
│   │   ├── services/                 # Logica de negocio
│   │   │   ├── sri_service.dart      # Orquesta emision electronica
│   │   │   ├── xml_import_service.dart # Importa XMLs del SRI
│   │   │   ├── pdf_service.dart      # Genera RIDE con Syncfusion
│   │   │   ├── payment_service.dart  # Integra Kushki/Paymentez/PayPhone
│   │   │   ├── ai_service.dart       # Chat IA + consultas
│   │   │   ├── print_service.dart    # Impresion nativa
│   │   │   ├── export_service.dart   # Exportacion PDF/Excel de grids
│   │   │   ├── notification_service.dart # Notificaciones in-app + email + WhatsApp
│   │   │   ├── push_service.dart     # FCM push nativo iOS/Android (App Salon/Cliente)
│   │   │   └── salon_branding_service.dart # White-label: carga logo/colores del salon
│   │   ├── theme/                    # Sistema de temas (usa flex_color_scheme)
│   │   │   ├── app_theme.dart        # FlexThemeData builder (light + dark)
│   │   │   ├── responsive_sizes.dart # PilarSizes: tamanos por breakpoint
│   │   │   ├── color_schemes.dart    # FlexScheme paletas + custom schemes
│   │   │   ├── typography.dart       # TextTheme escalado por factor
│   │   │   └── spacing.dart          # EdgeInsets/padding por densidad
│   │   └── widgets/                  # Widgets reutilizables
│   │       ├── workspace_tabs.dart   # Sistema de tabs dinamico
│   │       ├── crud_scaffold.dart    # Widget base para listados CRUD
│   │       ├── form_scaffold.dart    # Widget base para formularios
│   │       ├── data_grid.dart        # Wrapper SfDataGrid con export
│   │       ├── search_bar.dart       # Barra de busqueda global
│   │       ├── filter_panel.dart     # Panel de filtros expandible
│   │       ├── export_button.dart    # Botones exportar PDF/Excel
│   │       ├── pagination_bar.dart   # Barra de paginacion
│   │       ├── status_badge.dart     # Badge de estado (colores)
│   │       ├── form_fields.dart      # Campos personalizados
│   │       ├── chat_widget.dart      # Widget chat IA
│   │       └── pdf_viewer.dart       # Visualizador RIDE
│   │
│   ├── features/                     # Modulos por funcionalidad
│   │   ├── auth/                     # Login, registro (usa supabase_auth_ui)
│   │   │   ├── screens/
│   │   │   │   ├── login_screen.dart          # SupaEmailAuth + SupaSocialsAuth
│   │   │   │   ├── signup_screen.dart         # SupaEmailAuth (modo registro + metadataFields)
│   │   │   │   ├── forgot_password_screen.dart # SupaMagicAuth (envia link reset)
│   │   │   │   ├── reset_password_screen.dart  # SupaResetPassword (nueva contraseña)
│   │   │   │   ├── magic_link_screen.dart     # SupaMagicAuth (login sin password)
│   │   │   │   └── select_empresa_screen.dart # Selector empresa post-login
│   │   │   ├── providers/
│   │   │   │   ├── auth_state_provider.dart   # Estado de sesion + deep link listener
│   │   │   │   └── empresa_selector_provider.dart # Empresas del usuario
│   │   │   └── widgets/
│   │   │       └── auth_layout.dart           # Layout centrado con logo (PILAR o salon)
│   │   ├── dashboard/                # Pantalla principal (flavor erp)
│   │   │   ├── screens/
│   │   │   └── widgets/
│   │   ├── sales/                    # Ventas (flavor erp)
│   │   │   ├── screens/
│   │   │   │   ├── quotations_screen.dart    # Proformas/Cotizaciones
│   │   │   │   ├── quotation_form_screen.dart
│   │   │   │   ├── sales_orders_screen.dart  # Ordenes de Venta
│   │   │   │   ├── sales_order_form_screen.dart
│   │   │   │   ├── invoices_screen.dart
│   │   │   │   ├── invoice_form_screen.dart
│   │   │   │   ├── credit_notes_screen.dart
│   │   │   │   └── customers_screen.dart
│   │   │   ├── providers/
│   │   │   └── widgets/
│   │   ├── purchases/                # Compras (flavor erp)
│   │   │   ├── screens/
│   │   │   │   ├── bills_screen.dart
│   │   │   │   ├── import_xml_screen.dart   # Importar XML del SRI
│   │   │   │   ├── withholdings_screen.dart
│   │   │   │   └── suppliers_screen.dart
│   │   │   ├── providers/
│   │   │   └── widgets/
│   │   ├── inventory/                # Inventario (flavor erp)
│   │   │   ├── screens/
│   │   │   │   ├── products_screen.dart
│   │   │   │   ├── warehouses_screen.dart
│   │   │   │   ├── movements_screen.dart  # Ingresos/Egresos
│   │   │   │   ├── dispatches_screen.dart # Despachos de inventario
│   │   │   │   ├── transfers_screen.dart  # Transferencias entre bodegas
│   │   │   │   └── kardex_screen.dart
│   │   │   ├── providers/
│   │   │   └── widgets/
│   │   ├── accounting/               # Contabilidad (flavor erp)
│   │   │   ├── screens/
│   │   │   │   ├── chart_of_accounts_screen.dart
│   │   │   │   ├── journal_entries_screen.dart
│   │   │   │   ├── general_ledger_screen.dart
│   │   │   │   ├── balance_screen.dart
│   │   │   │   └── ats_screen.dart
│   │   │   ├── providers/
│   │   │   └── widgets/
│   │   ├── pos/                       # Punto de Venta (flavor erp)
│   │   │   ├── screens/
│   │   │   │   ├── pos_screen.dart            # Pantalla POS principal
│   │   │   │   ├── pos_checkout_screen.dart   # Cobro
│   │   │   │   ├── cash_register_screen.dart  # Apertura/cierre caja
│   │   │   │   └── z_report_screen.dart       # Reporte Z
│   │   │   ├── providers/
│   │   │   └── widgets/
│   │   │       ├── product_grid.dart          # Grid productos (touch)
│   │   │       ├── cart_panel.dart             # Panel carrito
│   │   │       └── payment_dialog.dart        # Dialog de cobro
│   │   │
│   │   ├── taller/                    # Garantias, RMA y Taller (flavor erp)
│   │   │   ├── screens/
│   │   │   │   ├── repair_orders_screen.dart
│   │   │   │   ├── repair_order_form_screen.dart
│   │   │   │   ├── repair_order_detail_screen.dart
│   │   │   │   ├── repair_quotation_screen.dart
│   │   │   │   ├── rma_screen.dart
│   │   │   │   ├── rma_form_screen.dart
│   │   │   │   ├── workshop_dashboard_screen.dart
│   │   │   │   ├── repair_templates_screen.dart
│   │   │   │   ├── workshop_stock_screen.dart
│   │   │   │   ├── tool_management_screen.dart
│   │   │   │   └── workshop_reports_screen.dart
│   │   │   ├── providers/
│   │   │   │   ├── repair_order_provider.dart
│   │   │   │   ├── rma_provider.dart
│   │   │   │   ├── repair_material_provider.dart
│   │   │   │   ├── repair_template_provider.dart
│   │   │   │   ├── workshop_stock_provider.dart
│   │   │   │   └── workshop_tool_provider.dart
│   │   │   ├── widgets/
│   │   │   │   ├── repair_status_badge.dart
│   │   │   │   ├── evidence_capture_widget.dart
│   │   │   │   ├── repair_timeline.dart
│   │   │   │   ├── material_consumption_form.dart
│   │   │   │   └── warranty_indicator.dart
│   │   │   └── models/
│   │   │       ├── repair_order.dart
│   │   │       ├── rma_request.dart
│   │   │       ├── repair_material.dart
│   │   │       ├── repair_labor.dart
│   │   │       ├── repair_template.dart
│   │   │       └── workshop_tool.dart
│   │   │
│   │   ├── ecommerce/                 # Integraciones ecommerce (flavor erp)
│   │   │   ├── screens/
│   │   │   │   ├── stores_screen.dart
│   │   │   │   ├── store_config_screen.dart
│   │   │   │   ├── orders_screen.dart
│   │   │   │   └── sync_screen.dart
│   │   │   ├── providers/
│   │   │   └── connectors/
│   │   │       ├── woocommerce_connector.dart
│   │   │       └── base_connector.dart
│   │   │
│   │   ├── treasury/                  # Tesoreria (flavor erp)
│   │   │   ├── screens/
│   │   │   │   ├── bank_accounts_screen.dart
│   │   │   │   ├── checks_screen.dart
│   │   │   │   ├── check_form_screen.dart
│   │   │   │   ├── bank_transfers_screen.dart
│   │   │   │   ├── transfer_form_screen.dart
│   │   │   │   ├── bank_reconciliation_screen.dart
│   │   │   │   └── cash_flow_screen.dart
│   │   │   ├── providers/
│   │   │   └── widgets/
│   │   │       ├── reconciliation_grid.dart
│   │   │       └── bank_import_dialog.dart
│   │   │
│   │   ├── citas_salon/               # App Salon — 3 roles en 2 flavors (salon + cliente)
│   │   │   │                          # Visible en: flavor salon (admin+empleado) y flavor cliente
│   │   │   ├── shared/                # Compartido entre los 3 roles
│   │   │   │   ├── models/
│   │   │   │   │   ├── cita.model.dart              # @ConnectOfflineFirstWithSupabase
│   │   │   │   │   ├── cita_detalle.model.dart
│   │   │   │   │   ├── citas_servicio.model.dart
│   │   │   │   │   ├── citas_profesional.model.dart
│   │   │   │   │   └── salon_perfil.model.dart       # Branding white-label
│   │   │   │   ├── providers/
│   │   │   │   │   ├── salon_role_provider.dart      # Riverpod: admin|empleado|cliente
│   │   │   │   │   ├── salon_branding_provider.dart  # Logo/colores desde salon_perfiles_publicos
│   │   │   │   │   ├── citas_provider.dart           # Lista citas con filtros
│   │   │   │   │   └── disponibilidad_provider.dart  # Slots libres en tiempo real
│   │   │   │   └── widgets/
│   │   │   │       ├── cita_card.dart                # Card adaptativa por rol
│   │   │   │       ├── servicio_chip.dart            # Nombre + duracion + precio
│   │   │   │       ├── profesional_avatar.dart       # Avatar + nombre + estado
│   │   │   │       └── estado_badge.dart             # Badge semantico (colores M3)
│   │   │   │
│   │   │   ├── admin/                 # Rol ADMIN_SALON (flavor salon)
│   │   │   │   ├── dashboard/
│   │   │   │   │   ├── admin_dashboard_screen.dart   # KPIs diarios
│   │   │   │   │   └── widgets/
│   │   │   │   │       ├── kpi_card.dart
│   │   │   │   │       └── alertas_panel.dart
│   │   │   │   ├── agenda/
│   │   │   │   │   ├── agenda_screen.dart            # SfCalendar timeline
│   │   │   │   │   ├── nueva_cita_screen.dart        # Stepper 5 pasos
│   │   │   │   │   └── widgets/
│   │   │   │   │       ├── cita_block.dart           # Bloque por estado en calendario
│   │   │   │   │       ├── walkin_panel.dart         # Cola de espera tiempo real
│   │   │   │   │       └── horario_bloqueo_dialog.dart
│   │   │   │   ├── clientes/
│   │   │   │   │   ├── clientes_list_screen.dart
│   │   │   │   │   ├── cliente_ficha_screen.dart     # Historial, gasto, notas
│   │   │   │   │   └── widgets/
│   │   │   │   │       └── cliente_historial_tab.dart
│   │   │   │   ├── servicios/
│   │   │   │   │   ├── servicios_screen.dart
│   │   │   │   │   ├── servicio_form_screen.dart     # 5 tiempos + backbar
│   │   │   │   │   └── insumos_screen.dart
│   │   │   │   ├── equipo/
│   │   │   │   │   ├── equipo_screen.dart
│   │   │   │   │   ├── especialista_ficha_screen.dart
│   │   │   │   │   ├── horario_editor_screen.dart    # Editor visual semanal
│   │   │   │   │   └── liquidaciones_screen.dart
│   │   │   │   ├── reportes/
│   │   │   │   │   ├── reportes_screen.dart          # Hub
│   │   │   │   │   ├── ingresos_screen.dart          # SfCartesianChart
│   │   │   │   │   ├── ocupacion_screen.dart         # Heatmap
│   │   │   │   │   ├── noshows_screen.dart
│   │   │   │   │   └── rentabilidad_screen.dart
│   │   │   │   └── configuracion/
│   │   │   │       ├── salon_config_screen.dart      # Perfil + branding + horario
│   │   │   │       ├── reglas_booking_screen.dart
│   │   │   │       └── notificaciones_config_screen.dart
│   │   │   │
│   │   │   ├── empleado/              # Rol EMPLEADO (flavor salon)
│   │   │   │   ├── mi_dia/
│   │   │   │   │   ├── mi_dia_screen.dart            # Timeline personal del dia
│   │   │   │   │   └── widgets/
│   │   │   │   │       ├── proxima_cita_hero.dart
│   │   │   │   │       └── cita_timeline_item.dart
│   │   │   │   ├── cita_detalle/
│   │   │   │   │   ├── cita_detalle_screen.dart      # Cronometro + completar
│   │   │   │   │   └── widgets/
│   │   │   │   │       ├── cronometro_widget.dart
│   │   │   │   │       ├── insumos_consumidos_form.dart
│   │   │   │   │       └── propina_selector.dart
│   │   │   │   ├── checkin/
│   │   │   │   │   └── checkin_screen.dart
│   │   │   │   ├── comisiones/
│   │   │   │   │   ├── mis_comisiones_screen.dart
│   │   │   │   │   └── liquidaciones_historial_screen.dart
│   │   │   │   └── mi_agenda/
│   │   │   │       ├── mi_agenda_screen.dart
│   │   │   │       └── solicitar_bloqueo_screen.dart
│   │   │   │
│   │   │   └── cliente/               # Rol CLIENTE (flavor cliente)
│   │   │       ├── home/
│   │   │       │   ├── cliente_home_screen.dart      # Proxima cita + boton reservar
│   │   │       │   └── widgets/
│   │   │       │       ├── proxima_cita_card.dart
│   │   │       │       └── ofertas_banner.dart
│   │   │       ├── reservar/
│   │   │       │   ├── reservar_flow.dart            # Stepper 4 pasos
│   │   │       │   ├── paso1_servicios_screen.dart
│   │   │       │   ├── paso2_profesional_screen.dart
│   │   │       │   ├── paso3_horario_screen.dart
│   │   │       │   ├── paso4_confirmar_screen.dart
│   │   │       │   └── widgets/
│   │   │       │       ├── servicio_selection_card.dart
│   │   │       │       ├── profesional_selection_card.dart
│   │   │       │       └── slot_grid.dart            # Verde/rojo por disponibilidad
│   │   │       ├── mis_citas/
│   │   │       │   ├── mis_citas_screen.dart
│   │   │       │   ├── cita_detalle_cliente_screen.dart
│   │   │       │   └── calificacion_screen.dart      # Stars + comentario
│   │   │       ├── catalogo/
│   │   │       │   └── catalogo_screen.dart
│   │   │       └── perfil/
│   │   │           ├── perfil_cliente_screen.dart
│   │   │           ├── gift_cards_screen.dart
│   │   │           └── membresia_screen.dart
│   │   │
│   │   └── settings/                 # Configuracion y Preferencias (flavor erp)
│   │       ├── screens/
│   │       │   ├── empresa_screen.dart
│   │       │   ├── certificate_screen.dart
│   │       │   ├── gateway_config_screen.dart
│   │       │   ├── users_screen.dart
│   │       │   ├── profile_screen.dart
│   │       │   └── preferences_screen.dart
│   │       └── providers/
│   │
│   │   # (SQLite local es gestionado por Brick automaticamente)
│   │   # No se necesita carpeta database/ separada
│
├── flavors/                          # Assets y config por flavor
│   ├── erp/
│   │   └── assets/                   # Logo PILAR ERP, splash, iconos
│   ├── salon/
│   │   ├── assets/                   # Logo PILAR Salon, splash, iconos
│   │   └── google-services.json      # FCM config App Salon
│   └── cliente/
│       ├── assets/                   # Placeholder (reemplazado por white-label en runtime)
│       └── google-services.json      # FCM config App Cliente
│
├── supabase/                         # Backend Supabase
│   ├── migrations/                   # GENERADO por ./scripts/build-supabase.sh
│   │   #                             # NO editar directamente — editar en los
│   │   #                             # directorios migrations/ de cada módulo y
│   │   #                             # foundation/migrations/, luego ejecutar
│   │   #                             # ./scripts/build-supabase.sh
│   │   └── NNN_*.sql                 # Migraciones ensambladas (foundation + módulos)
│   ├── functions/                    # Edge Functions (Deno/TypeScript)
│   │   ├── emit-invoice/index.ts     # Genera XML + firma + envia SRI
│   │   ├── authorize-invoice/index.ts # Consulta autorizacion SRI
│   │   ├── import-xml/index.ts       # Importa XML (archivo o WS SRI)
│   │   ├── generate-ats/index.ts     # Genera ATS XML + ZIP
│   │   ├── generate-ride/index.ts    # Genera PDF RIDE (server-side)
│   │   ├── send-email/index.ts       # Envia comprobante por email (Resend)
│   │   ├── process-payment/index.ts  # Procesa pagos (Kushki/Paymentez/PayPhone)
│   │   ├── webhook-kushki/index.ts   # Recibe webhooks Kushki
│   │   ├── webhook-paymentez/index.ts # Recibe webhooks Paymentez
│   │   ├── webhook-payphone/index.ts  # Recibe webhooks PayPhone
│   │   ├── import-bank-statement/index.ts # Importa CSV/OFX bancario
│   │   ├── webhook-ecommerce/index.ts # Recibe pedidos WooCommerce/etc
│   │   ├── sync-ecommerce/index.ts   # Sincroniza productos/stock
│   │   ├── ai-query/index.ts         # Chat IA (busqueda semantica pgvector)
│   │   ├── ai-create-doc/index.ts    # Crea documentos por IA
│   │   ├── ai-report/index.ts        # Genera informes por IA
│   │   ├── ai-embed/index.ts         # Genera embeddings
│   │   ├── booking-availability/index.ts # Slots disponibles (App Cliente, sin auth staff)
│   │   ├── salon-reminders/index.ts  # Cron: recordatorios 24h y 2h antes de cita
│   │   └── push-notify/index.ts      # Push via FCM a iOS/Android (App Salon/Cliente)
│   └── seed.sql                      # Plan cuentas NIIF + catalogo impuestos SRI
│
├── test/                             # Tests
│   ├── unit/
│   ├── widget/
│   └── integration/
│
├── android/                          # Proyecto Android nativo
│   └── app/src/
│       ├── erp/                      # Flavor ERP    — bundle: com.pilar.erp
│       ├── salon/                    # Flavor Salon  — bundle: com.pilar.salon
│       └── cliente/                  # Flavor Cliente — bundle: com.pilar.cliente
├── ios/                              # Proyecto iOS nativo
│   └── Runner/
│       └── Configurations/           # Schemes Xcode: ERP / Salon / Cliente
├── web/                              # Flutter Web (solo flavor erp → Cloudflare Pages)
├── windows/                          # Flutter Windows (solo flavor erp)
├── macos/                            # Flutter macOS (solo flavor erp)
├── linux/                            # Flutter Linux (solo flavor erp)
│
├── pubspec.yaml                      # Dependencias Dart/Flutter
└── analysis_options.yaml             # Linter rules
```

## Flavors — Resumen

| Flavor | Entry point | Bundle ID | Plataformas | Usuarios |
|--------|-------------|-----------|-------------|---------|
| `erp` | `main_erp.dart` | `com.pilar.erp` | Web + iOS + Android + Desktop | Staff ERP |
| `salon` | `main_salon.dart` | `com.pilar.salon` | iOS + Android | Admin salon + Empleados |
| `cliente` | `main_cliente.dart` | `com.pilar.cliente` | iOS + Android | Clientes del salon |

## Comandos por Flavor

```bash
# Desarrollo
flutter run --flavor erp     -t lib/main_erp.dart
flutter run --flavor salon   -t lib/main_salon.dart
flutter run --flavor cliente -t lib/main_cliente.dart

# Produccion iOS
flutter build ipa --flavor salon   -t lib/main_salon.dart   --release
flutter build ipa --flavor cliente -t lib/main_cliente.dart --release

# Produccion Android
flutter build apk --flavor salon   -t lib/main_salon.dart   --release
flutter build apk --flavor cliente -t lib/main_cliente.dart --release

# Web (solo ERP — Cloudflare Pages)
flutter build web --flavor erp -t lib/main_erp.dart --release
```
