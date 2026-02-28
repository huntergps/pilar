import 'dart:async';
import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:window_manager/window_manager.dart';

import '../offline/connectivity_service.dart';
import '../offline/offline_banner.dart';
import '../providers/empresa_provider.dart';
import '../providers/modulos_provider.dart';
import '../providers/perfil_provider.dart';
import '../providers/print_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/usuario_provider.dart';
import '../router/app_router.dart';
import '../services/window_service.dart';
import '../../features/notificaciones/providers/notificaciones_provider.dart';
import 'pilar_header.dart';

/// The main authenticated navigation shell for PILAR ERP.
///
/// Wraps the go_router [ShellRoute] child in a [NavigationView] with:
/// - Adaptive pane (auto display mode: expanded → compact → minimal).
/// - Dashboard as a fixed item at index 0.
/// - **Empresa** [PaneItemExpander] — always visible (índice 0 del expander).
///   Its children occupy indices 1–3 (always) plus optionally 4 (Historial):
///     1 → Conversaciones, 2 → Email, 3 → Canales,
///     4 → Historial (only if user has `comunicacion.historial.ver`).
/// - **Mis mensajes** [PaneItemExpander] — always visible.
///   Starts at index 5 (tieneHistorial=true) or 4 (tieneHistorial=false):
///     5/4 → Mi Email, 6/5 → Mis DMs.
/// - **Administración** [PaneItemExpander] — only visible when the user has
///   at least the [administracion.empresa.menu] permission.
///   When visible, its six children start at index 7 (tieneHistorial) or 6:
///     +0 → Empresa, +1 → Usuarios, +2 → Módulos, +3 → Archivos,
///     +4 → Comunicación (admin), +5 → Roles y Permisos.
/// - Dynamic module items start after admin (or after Mis mensajes if no admin).
/// - **Mi Perfil** and **Configuración** footer items (visible to ALL users).
/// - Window geometry persistence via [WindowService.saveState].
/// - [WidgetsBindingObserver] para invalidar providers al volver de background (iOS).
class PilarShell extends ConsumerStatefulWidget {
  final Widget child;

  const PilarShell({super.key, required this.child});

  @override
  ConsumerState<PilarShell> createState() => _PilarShellState();
}

class _PilarShellState extends ConsumerState<PilarShell>
    with WindowListener, WidgetsBindingObserver {
  // ---- Window lifecycle ----------------------------------------------------

  bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  // ---- Realtime: suscripción a cambios de color de empresa -----------------

  RealtimeChannel? _colorChannel;
  String? _colorChannelEmpresaId;

  /// Suscribe (o re-suscribe) al canal Realtime de `configuracion_empresa`
  /// para la empresa [empresaId]. Cuando el admin fuerza un color, este canal
  /// notifica inmediatamente a todos los dispositivos con la app abierta.
  ///
  /// Si [empresaId] es null o el mismo al que ya estamos suscritos, no hace nada.
  void _resubscribeColor(String? empresaId) {
    if (_colorChannelEmpresaId == empresaId) return;

    // Cancelar suscripción anterior
    _colorChannel?.unsubscribe();
    _colorChannel = null;
    _colorChannelEmpresaId = null;

    if (empresaId == null) return;

    _colorChannelEmpresaId = empresaId;
    _colorChannel = Supabase.instance.client
        .channel('pilar_empresa_color_$empresaId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'configuracion_empresa',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'empresa_id',
            value: empresaId,
          ),
          callback: (_) {
            // Invalidar el provider para que se recargue con el nuevo color.
            // El ref.listen sobre empresaConfigProvider en build() hará el resto:
            // applyForceColorIfNeeded() + actualizar empresaColorProvider.
            if (mounted) ref.invalidate(empresaConfigProvider);
          },
        )
        .subscribe();
  }

  @override
  void initState() {
    super.initState();
    if (_isDesktop) windowManager.addListener(this);
    // Observar ciclo de vida para iOS: reconectar Realtime al volver de background.
    WidgetsBinding.instance.addObserver(this);
    // Si el JWT no tiene permisos (token emitido antes del hook fix o antes de
    // que se asignara el rol), lo refrescamos automáticamente. El stream
    // onAuthStateChange emitirá el nuevo token y todos los providers
    // dependientes se reconstruirán sin que el usuario tenga que cerrar sesión.
    _autoRefreshIfStaleToken();
    // Suscribir al canal Realtime al primer frame (cuando ref ya está disponible).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _resubscribeColor(ref.read(empresaActivaIdProvider));
    });
  }

  Future<void> _autoRefreshIfStaleToken() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return;

    // Evitar race condition con el auto-refresh del SDK:
    // Si el token expira en < 5 minutos, el SDK lo refrescará solo — no interferir.
    // Nuestra función solo actúa cuando el token es válido por mucho tiempo más
    // pero tiene permisos vacíos o un esquema anterior (pre-migración 056).
    final expiresAt = session.expiresAt;
    final secsLeft = expiresAt != null
        ? expiresAt - (DateTime.now().millisecondsSinceEpoch ~/ 1000)
        : 9999;
    if (secsLeft < 300) return; // SDK manejará este refresh — no competir

    final permisos =
        session.user.appMetadata['permisos'] as List<dynamic>? ?? const [];

    // Refresca si los permisos están vacíos O si usan el esquema anterior
    // (ej: tienen .ver pero no .menu, lo que indica un JWT pre-migración 056).
    // El custom_access_token_hook lee desde roles_permisos directamente — este
    // refresh lo fuerza a generar un JWT nuevo con el esquema actual.
    final esquemaStale = permisos.isNotEmpty &&
        !permisos.contains('dashboard.menu') &&
        !permisos.contains('administracion.empresa.menu');

    if (permisos.isEmpty || esquemaStale) {
      try {
        await Supabase.instance.client.auth.refreshSession();
      } catch (_) {
        // Silenciar errores de red — el SDK reintentará automáticamente.
      }
    }
  }

  @override
  void dispose() {
    _colorChannel?.unsubscribe();
    if (_isDesktop) windowManager.removeListener(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Gestiona el ciclo de vida de la app — crítico para iOS donde el OS
  /// pausa las conexiones WebSocket cuando la app va a background.
  ///
  /// Al volver a foreground ([AppLifecycleState.resumed]):
  /// - Supabase Flutter reconecta el WebSocket automáticamente.
  /// - Invalidamos providers con Realtime para re-fetch y recuperar
  ///   cualquier evento perdido mientras estábamos en background.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // En macOS, abrir/cerrar un dialog envía AppLifecycleState.inactive porque
    // la ventana pierde el foco temporalmente. En ese instante el elemento
    // puede estar deactivado aunque mounted==true, causando crash en ref.read.
    // Diferimos al siguiente frame para que el árbol esté estable.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      switch (state) {
        case AppLifecycleState.resumed:
          ref.read(connectivityProvider.notifier).reportOnline();
          ref.invalidate(notificacionesBadgeProvider);
        case AppLifecycleState.paused:
        case AppLifecycleState.inactive:
          ref.read(connectivityProvider.notifier).reportOffline();
        case AppLifecycleState.detached:
        case AppLifecycleState.hidden:
          break;
      }
    });
  }

  @override
  void onWindowResized() => WindowService.saveState();
  @override
  void onWindowMoved() => WindowService.saveState();
  @override
  void onWindowMaximize() => WindowService.saveState();
  @override
  void onWindowUnmaximize() => WindowService.saveState();

  /// Intercepted because [WindowService.initialize] sets preventClose: true.
  /// Saves window geometry before actually destroying the window.
  @override
  Future<void> onWindowClose() async {
    await WindowService.saveState();
    await windowManager.destroy();
  }

  // ---- Index calculation ---------------------------------------------------

  /// Maps the current route to the [NavigationPane] effectiveItems index.
  ///
  /// When [tieneAdmin] is true and [tieneHistorial] is true:
  ///   0 → Dashboard
  ///   Empresa expander children:
  ///     1 → /comunicacion (Conversaciones)
  ///     2 → /comunicacion/email (Email)
  ///     3 → /comunicacion/chat (Canales)
  ///     4 → /comunicacion/historial (Historial)
  ///   Mis mensajes expander children:
  ///     5 → /mis-mensajes/email (Mi Email)
  ///     6 → /mis-mensajes/chat (Mis DMs)
  ///   Administración expander children:
  ///     7 → /admin/empresa
  ///     8 → /admin/usuarios
  ///     9 → /admin/modulos
  ///     10 → /admin/archivos
  ///     11 → /admin/comunicacion
  ///     12 → /admin/permisos
  ///   13..12+N → Dynamic modules
  ///   13+N → Perfil (footer PaneItem)
  ///   14+N → Configuración (footer PaneItem)
  ///
  /// When [tieneHistorial] is false, Historial item is absent from the pane,
  /// so indices 4+ shift down by 1:
  ///     3 → /comunicacion/chat (Canales)
  ///     4 → /mis-mensajes/email (Mi Email)
  ///     5 → /mis-mensajes/chat (Mis DMs)
  ///   (admin items and modules shift down by 1 accordingly)
  ///
  /// When [tieneAdmin] is false (Administración hidden):
  ///   0 → Dashboard
  ///   1..3 (or 1..4) → Empresa expander children
  ///   5..6 (or 4..5) → Mis mensajes expander children
  ///   7+N (or 6+N) → Perfil (footer PaneItem)
  ///   8+N (or 7+N) → Configuración (footer PaneItem)
  int _indexForRoute(
      String location, List<ModuloItem> modulos, bool tieneAdmin,
      bool tieneHistorial) {
    if (location.startsWith('/dashboard')) return 0;

    // ---- Empresa expander ----
    // Sub-rutas específicas van ANTES que la ruta padre /comunicacion
    if (location.startsWith('/comunicacion/chat')) return tieneHistorial ? 3 : 3;
    if (location.startsWith('/comunicacion/historial')) {
      return tieneHistorial ? 4 : 3; // fallback a chat si no tiene permiso
    }
    if (location.startsWith('/comunicacion/email')) return 2;
    if (location.startsWith('/comunicacion')) return 1;

    // ---- Mis mensajes expander ----
    final misMensajesBase = tieneHistorial ? 5 : 4;
    if (location.startsWith('/mis-mensajes/email')) return misMensajesBase;
    if (location.startsWith('/mis-mensajes/chat')) return misMensajesBase + 1;

    final adminBase = tieneHistorial ? 7 : 6;
    if (tieneAdmin) {
      if (location.startsWith('/admin/empresa')) return adminBase;
      if (location.startsWith('/admin/usuarios')) return adminBase + 1;
      if (location.startsWith('/admin/modulos')) return adminBase + 2;
      if (location.startsWith('/admin/archivos')) return adminBase + 3;
      if (location.startsWith('/admin/comunicacion')) return adminBase + 4;
      if (location.startsWith('/admin/permisos')) return adminBase + 5;
      if (location.startsWith('/admin/impresoras')) return adminBase + 6;
      if (location.startsWith('/admin')) return adminBase;
    }

    final coreModulos = modulos.where((m) => m.tipo != 'infraestructura');
    final modulosBase = tieneAdmin
        ? (tieneHistorial ? 14 : 13)
        : (tieneHistorial ? 7 : 6);
    int idx = modulosBase;
    for (final m in coreModulos) {
      if (location.startsWith('/${m.id}')) return idx;
      idx++;
    }

    // Footer items (Mi Perfil + Configuración — ambos visibles para TODOS)
    if (location.startsWith('/perfil')) return idx;
    if (location.startsWith('/configuracion')) return idx + 1;

    return 0;
  }

  // ---- Sign-out ------------------------------------------------------------

  Future<void> _signOut(BuildContext context) async {
    await Supabase.instance.client.auth.signOut();
    if (context.mounted) context.go(PilarRoutes.login);
  }

  // ---- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final modulosAsync = ref.watch(modulosActivosProvider);
    final modulos = modulosAsync.valueOrNull ?? const <ModuloItem>[];
    final location = GoRouterState.of(context).matchedLocation;
    final paneDisplayMode = ref.watch(appConfigProvider).paneDisplayMode;

    // Pre-carga catálogo de impresoras — fire-and-forget para que PrintService
    // esté listo antes de que cualquier módulo llame a ps.print().
    ref.watch(printCatalogoProvider);

    // Cuando cambia la empresa activa:
    // 1. Notificar a ConfigService para cargar el accentColor del usuario para esa empresa.
    // 2. Aplicar el color_primario de la empresa como color por defecto (si el usuario
    //    no tiene un override guardado para esta empresa).
    ref.listen<String?>(empresaActivaIdProvider, (_, empresaId) {
      ref.read(appConfigProvider.notifier).switchEmpresa(empresaId);
      _resubscribeColor(empresaId); // cambia el canal Realtime a la nueva empresa
      ref.invalidate(perfilUsuarioProvider); // recarga el perfil de la nueva empresa
    });
    ref.listen<AsyncValue<EmpresaConfig?>>(empresaConfigProvider, (_, next) async {
      final empresa = next.valueOrNull;
      if (empresa == null) return;

      // El emit local (Brick/SQLite) usa empresas.color_primario que puede diferir
      // del color real en configuracion_empresa. Solo el emit remoto (Supabase RPC)
      // es autoritativo para el color de acento — evita el flash azul en cada inicio.
      if (!empresa.isFromRemote) return;

      // Si el admin forzó el color después del último ack de este dispositivo,
      // descartar el override personal del usuario.
      final configSvc = ref.read(appConfigProvider.notifier);
      await configSvc.applyForceColorIfNeeded(empresa.colorForzadoEn);

      // Aplicar color de empresa como predeterminado si el usuario no tiene override.
      final userOverride = ref.read(appConfigProvider).accentColor;
      final colorHex = empresa.colorPrimario;
      if (userOverride != null) return; // el usuario tiene su propio color para esta empresa
      if (colorHex == null) {
        ref.read(empresaColorProvider.notifier).state = null;
        unawaited(ref.read(appConfigProvider.notifier).cacheEmpresaColor(null));
        return;
      }
      final hex = colorHex.replaceFirst('#', '');
      final value = int.tryParse('FF$hex', radix: 16);
      if (value != null) {
        final color = Color(value);
        ref.read(empresaColorProvider.notifier).state = color;
        // Cachea el color en SharedPreferences para eliminar el flash azul
        // en el próximo inicio: main.dart lo lee antes del primer frame.
        unawaited(ref.read(appConfigProvider.notifier).cacheEmpresaColor(color));
      }
    });

    // El menú de Administración solo se muestra a usuarios con permiso de menú.
    final tieneAdmin =
        ref.watch(hasPermissionProvider('administracion.empresa.menu'));

    // Historial solo visible si el usuario tiene el permiso correspondiente.
    final tieneHistorial =
        ref.watch(hasPermissionProvider('comunicacion.historial.ver'));

    final selectedIndex =
        _indexForRoute(location, modulos, tieneAdmin, tieneHistorial);
    final dynamicModulos = modulos.where((m) => m.tipo != 'infraestructura');

    return SafeArea(
      bottom: false,
      child: NavigationView(
        // ---- Title bar ----
        titleBar: TitleBar(
          isBackButtonVisible: false,
          title: const DragToMoveArea(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text('PILAR ERP'),
            ),
          ),
          endHeader: PilarHeader(isDesktop: _isDesktop),
          captionControls: _isDesktop
              ? SizedBox(
                  width: 138,
                  height: 50,
                  child: WindowCaption(
                    brightness: FluentTheme.of(context).brightness,
                    backgroundColor: Colors.transparent,
                  ),
                )
              : null,
        ),

        // ---- Navigation pane ----
        pane: NavigationPane(
          displayMode: paneDisplayMode,
          selected: selectedIndex,
          header: Builder(
            builder: (ctx) {
              final accent = FluentTheme.of(ctx).accentColor;
              return Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
                child: SvgPicture.asset(
                  'assets/logos/pilar_logo.svg',
                  height: 32,
                  fit: BoxFit.contain,
                  alignment: Alignment.centerLeft,
                  colorFilter: ColorFilter.mode(accent, BlendMode.srcIn),
                ),
              );
            },
          ),
          onChanged: (index) {
            final list = dynamicModulos.toList();
            // Indices shift based on whether Historial is visible.
            // Historial (index 4) disappears when tieneHistorial=false,
            // so indices 4+ shift down by 1.
            final misMensajesBase = tieneHistorial ? 5 : 4;
            final adminBase = tieneHistorial ? 7 : 6;
            final modulosBase = tieneAdmin
                ? (tieneHistorial ? 14 : 13)
                : (tieneHistorial ? 7 : 6);

            if (index == 0) {
              context.go(PilarRoutes.dashboard);
            } else if (index == 1) {
              context.go(PilarRoutes.comunicacion);
            } else if (index == 2) {
              context.go(PilarRoutes.comunicacionEmail);
            } else if (index == 3) {
              // index 3 = Canales (always present)
              context.go(PilarRoutes.comunicacionChat);
            } else if (tieneHistorial && index == 4) {
              context.go(PilarRoutes.comunicacionHistorial);
            } else if (index == misMensajesBase) {
              context.go(PilarRoutes.misMensajesEmail);
            } else if (index == misMensajesBase + 1) {
              context.go(PilarRoutes.misMensajesChat);
            } else if (tieneAdmin && index == adminBase) {
              context.go(PilarRoutes.adminEmpresa);
            } else if (tieneAdmin && index == adminBase + 1) {
              context.go(PilarRoutes.adminUsuarios);
            } else if (tieneAdmin && index == adminBase + 2) {
              context.go(PilarRoutes.adminModulos);
            } else if (tieneAdmin && index == adminBase + 3) {
              context.go(PilarRoutes.adminArchivos);
            } else if (tieneAdmin && index == adminBase + 4) {
              context.go(PilarRoutes.adminComunicacion);
            } else if (tieneAdmin && index == adminBase + 5) {
              context.go(PilarRoutes.adminPermisos);
            } else if (tieneAdmin && index == adminBase + 6) {
              context.go(PilarRoutes.adminImpresoras);
            } else {
              final modIdx = index - modulosBase;
              if (modIdx >= 0 && modIdx < list.length) {
                context.go(PilarRoutes.dashboard);
              } else if (index == list.length + modulosBase) {
                context.go(PilarRoutes.perfil);
              } else if (index == list.length + modulosBase + 1) {
                context.go(PilarRoutes.configuracion);
              }
            }
          },
          items: [
            // ---- Dashboard ----
            PaneItem(
              icon: const Icon(FluentIcons.home),
              title: const Text('Dashboard'),
              body: const SizedBox.shrink(),
            ),

            // ---- Empresa (expander — hijos índices 1–3, opcionalmente 4) ----
            PaneItemExpander(
              key: ValueKey(
                  'empresa_expander_${location.startsWith('/comunicacion')}_$tieneHistorial'),
              icon: const Icon(FluentIcons.company_directory),
              title: const Text('Empresa'),
              initiallyExpanded: location.startsWith('/comunicacion'),
              items: [
                PaneItem(
                  icon: const Icon(FluentIcons.chat),
                  title: const Text('Conversaciones'),
                  body: const SizedBox.shrink(),
                ),
                PaneItem(
                  icon: const Icon(FluentIcons.mail),
                  title: const Text('Email'),
                  body: const SizedBox.shrink(),
                ),
                PaneItem(
                  icon: const Icon(FluentIcons.people),
                  title: const Text('Canales'),
                  body: const SizedBox.shrink(),
                ),
                if (tieneHistorial)
                  PaneItem(
                    icon: const Icon(FluentIcons.history),
                    title: const Text('Historial'),
                    body: const SizedBox.shrink(),
                  ),
              ],
            ),

            // ---- Mis mensajes (expander — hijos índices 5–6) ----
            PaneItemExpander(
              key: ValueKey(
                  'mis_mensajes_expander_${location.startsWith('/mis-mensajes')}'),
              icon: const Icon(FluentIcons.contact),
              title: const Text('Mis mensajes'),
              initiallyExpanded: location.startsWith('/mis-mensajes'),
              items: [
                PaneItem(
                  icon: const Icon(FluentIcons.mail),
                  title: const Text('Mi Email'),
                  body: const SizedBox.shrink(),
                ),
                PaneItem(
                  icon: const Icon(FluentIcons.chat_solid),
                  title: const Text('Mis DMs'),
                  body: const SizedBox.shrink(),
                ),
              ],
            ),

            // ---- Administración (solo visible si tiene permiso) ----
            if (tieneAdmin)
              PaneItemExpander(
                key: ValueKey(
                    'admin_expander_${location.startsWith('/admin')}'),
                icon: const Icon(FluentIcons.admin),
                title: const Text('Administración'),
                // body: null → excluded from effectiveItems, not selectable.
                // Children are what get selected (indices 1–3).
                initiallyExpanded: location.startsWith('/admin'),
                items: [
                  PaneItem(
                    icon: const Icon(FluentIcons.company_directory),
                    title: const Text('Empresa'),
                    body: const SizedBox.shrink(),
                  ),
                  PaneItem(
                    icon: const Icon(FluentIcons.people),
                    title: const Text('Usuarios'),
                    body: const SizedBox.shrink(),
                  ),
                  PaneItem(
                    icon: const Icon(FluentIcons.tiles),
                    title: const Text('Módulos'),
                    body: const SizedBox.shrink(),
                  ),
                  PaneItem(
                    icon: const Icon(FluentIcons.attach),
                    title: const Text('Archivos'),
                    body: const SizedBox.shrink(),
                  ),
                  PaneItem(
                    icon: const Icon(FluentIcons.mail),
                    title: const Text('Comunicación'),
                    body: const SizedBox.shrink(),
                  ),
                  PaneItem(
                    icon: const Icon(FluentIcons.permissions),
                    title: const Text('Roles y Permisos'),
                    body: const SizedBox.shrink(),
                  ),
                  PaneItem(
                    icon: const Icon(FluentIcons.print),
                    title: const Text('Impresoras'),
                    body: const SizedBox.shrink(),
                  ),
                ],
              ),

            // ---- Dynamic module items ----
            ...dynamicModulos.map(
              (m) => PaneItem(
                icon: const Icon(FluentIcons.app_icon_default),
                title: Text(m.nombre),
                body: const SizedBox.shrink(),
              ) as NavigationPaneItem,
            ),
          ],
          footerItems: [
            // Mi Perfil — visible para TODOS los usuarios (índice N).
            PaneItem(
              icon: const Icon(FluentIcons.contact),
              title: const Text('Mi Perfil'),
              body: const SizedBox.shrink(),
            ),
            // Configuración — visible para TODOS los usuarios (índice N+1).
            PaneItem(
              icon: const Icon(FluentIcons.settings),
              title: const Text('Configuración'),
              body: const SizedBox.shrink(),
            ),
            PaneItemSeparator(),
            PaneItemAction(
              icon: const Icon(FluentIcons.sign_out),
              title: const Text('Salir'),
              onTap: () => _signOut(context),
            ),
          ],
        ),

        // go_router owns the page lifecycle via ShellRoute.
        // OfflineStatusBar se inserta como franja roja cuando no hay red.
        paneBodyBuilder: (_, __) => Column(
          children: [
            const OfflineStatusBar(),
            Expanded(child: widget.child),
          ],
        ),
      ),
    );
  }
}
