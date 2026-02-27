import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:window_manager/window_manager.dart';

import '../offline/connectivity_service.dart';
import '../offline/offline_banner.dart';
import '../providers/empresa_provider.dart';
import '../providers/modulos_provider.dart';
import '../providers/perfil_provider.dart';
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
/// - **Mensajes** (Comunicación) at index 1 — always visible.
/// - Administración as a [PaneItemExpander] — only visible when the user has
///   at least the [administracion.empresa.ver] permission.
///   When visible, its four children occupy indices 2–5:
///     2 → Empresa, 3 → Usuarios, 4 → Módulos, 5 → Archivos.
///   When hidden, dynamic modules start at index 2.
/// - Dynamic module items start at index 7 (admin visible) or 2 (admin hidden).
/// - Configuración footer item (visible to ALL users, always in footerItems).
///   For admin users: index = 7 + dynamicModulosCount.
///   For non-admin users: index = 2 + dynamicModulosCount.
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
    final permisos =
        session.user.appMetadata['permisos'] as List<dynamic>? ?? const [];
    if (permisos.isEmpty) {
      // Escribir permisos directamente en raw_app_meta_data (lo que lee Flutter).
      // El hook solo modifica los JWT claims; raw_app_meta_data requiere un RPC
      // SECURITY DEFINER que actualice auth.users directamente.
      await Supabase.instance.client.rpc('refresh_user_permissions');
      // Luego refrescar sesión para que supabase_flutter recoja el appMetadata
      // actualizado y todos los providers dependientes se reconstruyan.
      await Supabase.instance.client.auth.refreshSession();
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
    if (!mounted) return;
    switch (state) {
      case AppLifecycleState.resumed:
        // App vuelve a foreground. Supabase reconecta WebSocket solo;
        // invalidamos para que los providers re-fetch datos perdidos.
        ref.read(connectivityProvider.notifier).reportOnline();
        ref.invalidate(notificacionesBadgeProvider);
        // comunicacionConversacionesProvider se invalidará aquí cuando
        // el módulo de comunicación esté implementado (§10 del plan).
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        // App va a background. Los WebSockets se pausarán en iOS.
        ref.read(connectivityProvider.notifier).reportOffline();
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
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
  /// When [tieneAdmin] is true:
  ///   0 → Dashboard
  ///   1 → Mensajes (Comunicación)
  ///   2 → Empresa, 3 → Usuarios, 4 → Módulos, 5 → Archivos, 6 → Comunicación (expander children)
  ///   7..6+N → Dynamic modules
  ///   7+N → Configuración (footer PaneItem)
  ///
  /// When [tieneAdmin] is false (Administración hidden):
  ///   0 → Dashboard
  ///   1 → Mensajes (Comunicación)
  ///   2..1+N → Dynamic modules
  ///   2+N  → Configuración (footer PaneItem)
  int _indexForRoute(
      String location, List<ModuloItem> modulos, bool tieneAdmin) {
    if (location.startsWith('/dashboard')) return 0;
    if (location.startsWith('/comunicacion')) return 1;

    if (tieneAdmin) {
      if (location.startsWith('/admin/empresa')) return 2;
      if (location.startsWith('/admin/usuarios')) return 3;
      if (location.startsWith('/admin/modulos')) return 4;
      if (location.startsWith('/admin/archivos')) return 5;
      if (location.startsWith('/admin/comunicacion')) return 6;
      if (location.startsWith('/admin')) return 2;
    }

    final coreModulos = modulos.where((m) => m.tipo != 'infraestructura');
    int idx = tieneAdmin ? 7 : 2;
    for (final m in coreModulos) {
      if (location.startsWith('/${m.id}')) return idx;
      idx++;
    }

    // Footer Configuración item (ALL users)
    if (location.startsWith('/configuracion')) return idx;

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
        return;
      }
      final hex = colorHex.replaceFirst('#', '');
      final value = int.tryParse('FF$hex', radix: 16);
      if (value != null) {
        ref.read(empresaColorProvider.notifier).state = Color(value);
      }
    });

    // El menú de Administración solo se muestra a usuarios con permiso de ver.
    final tieneAdmin =
        ref.watch(hasPermissionProvider('administracion.empresa.ver'));

    final selectedIndex = _indexForRoute(location, modulos, tieneAdmin);
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
          onChanged: (index) {
            final list = dynamicModulos.toList();
            if (tieneAdmin) {
              switch (index) {
                case 0:
                  context.go(PilarRoutes.dashboard);
                case 1:
                  context.go(PilarRoutes.comunicacion);
                case 2:
                  context.go(PilarRoutes.adminEmpresa);
                case 3:
                  context.go(PilarRoutes.adminUsuarios);
                case 4:
                  context.go(PilarRoutes.adminModulos);
                case 5:
                  context.go(PilarRoutes.adminArchivos);
                case 6:
                  context.go(PilarRoutes.adminComunicacion);
                default:
                  final modIdx = index - 7;
                  if (modIdx >= 0 && modIdx < list.length) {
                    // Future: context.go('/${list[modIdx].id}');
                    context.go(PilarRoutes.dashboard);
                  } else if (index == list.length + 7) {
                    context.go(PilarRoutes.configuracion);
                  }
              }
            } else {
              switch (index) {
                case 0:
                  context.go(PilarRoutes.dashboard);
                case 1:
                  context.go(PilarRoutes.comunicacion);
                default:
                  final modIdx = index - 2;
                  if (modIdx >= 0 && modIdx < list.length) {
                    // Future: context.go('/${list[modIdx].id}');
                    context.go(PilarRoutes.dashboard);
                  } else if (index == list.length + 2) {
                    context.go(PilarRoutes.configuracion);
                  }
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

            // ---- Mensajes / Comunicación (siempre visible — índice 1) ----
            PaneItem(
              icon: const Icon(FluentIcons.chat),
              title: const Text('Mensajes'),
              body: const SizedBox.shrink(),
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
            // Configuración siempre en el footer para todos los usuarios.
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
