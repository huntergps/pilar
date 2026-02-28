import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/usuario_provider.dart';

// ---------------------------------------------------------------------------
// Modelos
// ---------------------------------------------------------------------------

class RolItem {
  final String id;
  final String codigo;
  final String nombre;
  final String? descripcion;
  final bool esSistema;
  final String? empresaId;
  final bool activo;

  const RolItem({
    required this.id,
    required this.codigo,
    required this.nombre,
    this.descripcion,
    required this.esSistema,
    this.empresaId,
    required this.activo,
  });

  factory RolItem.fromJson(Map<String, dynamic> json) => RolItem(
        id: json['id'] as String,
        codigo: json['codigo'] as String,
        nombre: json['nombre'] as String,
        descripcion: json['descripcion'] as String?,
        esSistema: json['es_sistema'] as bool? ?? false,
        empresaId: json['empresa_id'] as String?,
        activo: json['activo'] as bool? ?? true,
      );
}

class PermisoEstado {
  final String id;
  final String codigo;
  final String modulo;
  final String recurso;
  final String accion;
  final String? descripcion;
  final int nivel;     // 0=menu, 1=tabla CRUD, 2=sub-acción
  final String? parentId;
  bool tienePermiso;

  PermisoEstado({
    required this.id,
    required this.codigo,
    required this.modulo,
    required this.recurso,
    required this.accion,
    this.descripcion,
    this.nivel = 1,
    this.parentId,
    required this.tienePermiso,
  });

  factory PermisoEstado.fromJson(Map<String, dynamic> json) => PermisoEstado(
        id: json['id'] as String,
        codigo: json['codigo'] as String,
        modulo: json['modulo'] as String,
        recurso: json['recurso'] as String,
        accion: json['accion'] as String,
        descripcion: json['descripcion'] as String?,
        nivel: (json['nivel'] as num?)?.toInt() ?? 1,
        parentId: json['parent_id'] as String?,
        tienePermiso: json['tiene_permiso'] as bool? ?? false,
      );
}

class UsuarioRolItem {
  final String usuarioId;
  final String email;
  final String nombreDisplay;
  final String? avatarUrl;
  final bool activo;

  const UsuarioRolItem({
    required this.usuarioId,
    required this.email,
    required this.nombreDisplay,
    this.avatarUrl,
    required this.activo,
  });

  factory UsuarioRolItem.fromJson(Map<String, dynamic> json) => UsuarioRolItem(
        usuarioId: json['usuario_id'] as String,
        email: json['email'] as String,
        nombreDisplay:
            json['nombre_display'] as String? ?? json['email'] as String,
        avatarUrl: json['avatar_url'] as String?,
        activo: json['activo'] as bool? ?? true,
      );
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final rolesAdminProvider = FutureProvider<List<RolItem>>((ref) async {
  final data = await Supabase.instance.client.rpc('admin_get_roles');
  return (data as List)
      .map((e) => RolItem.fromJson(e as Map<String, dynamic>))
      .toList();
});

final permisosRolProvider =
    FutureProvider.family<List<PermisoEstado>, String>((ref, rolId) async {
  final data = await Supabase.instance.client
      .rpc('admin_get_permisos_rol', params: {'p_rol_id': rolId});
  return (data as List)
      .map((e) => PermisoEstado.fromJson(e as Map<String, dynamic>))
      .toList();
});

final usuariosRolProvider =
    FutureProvider.family<List<UsuarioRolItem>, String>((ref, rolId) async {
  final data = await Supabase.instance.client
      .rpc('admin_get_usuarios_rol', params: {'p_rol_id': rolId});
  return (data as List)
      .map((e) => UsuarioRolItem.fromJson(e as Map<String, dynamic>))
      .toList();
});

final _rolSeleccionadoProvider = StateProvider<RolItem?>((ref) => null);
final _filtroModuloProvider = StateProvider<String?>((ref) => null);
final _filtroTextoProvider = StateProvider<String>((ref) => '');

// ---------------------------------------------------------------------------
// Pantalla principal
// ---------------------------------------------------------------------------

class GestorPermisosScreen extends ConsumerWidget {
  const GestorPermisosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tienePermiso =
        ref.watch(hasPermissionProvider('administracion.roles.listar'));
    if (!tienePermiso) {
      return ScaffoldPage(
        content: Center(
          child: Text('Sin permisos para acceder a esta seccion.',
              style: FluentTheme.of(context).typography.body),
        ),
      );
    }

    final rolesAsync = ref.watch(rolesAdminProvider);
    final rolSeleccionado = ref.watch(_rolSeleccionadoProvider);

    return ScaffoldPage(
      header: PageHeader(
        title: const Text('Roles y Permisos'),
        commandBar: CommandBar(
          mainAxisAlignment: MainAxisAlignment.end,
          primaryItems: [
            CommandBarButton(
              icon: const Icon(FluentIcons.add),
              label: const Text('Nuevo Rol'),
              onPressed: () => _mostrarNuevoRolDialog(context, ref),
            ),
          ],
        ),
      ),
      content: rolesAsync.when(
        loading: () => const Center(child: ProgressRing()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (roles) {
          if (rolSeleccionado == null && roles.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ref.read(_rolSeleccionadoProvider.notifier).state = roles.first;
            });
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Toolbar(roles: roles),
              const Divider(
                style: DividerThemeData(horizontalMargin: EdgeInsets.zero),
              ),
              // Aviso de rol de sistema
              if (rolSeleccionado?.esSistema == true)
                const Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: InfoBar(
                    title: Text('Personalización por empresa'),
                    content: Text(
                      'Los cambios en este rol solo afectan a esta empresa. '
                      'La configuración base global permanece intacta para las demás.',
                    ),
                    severity: InfoBarSeverity.info,
                  ),
                ),
              Expanded(
                child: rolSeleccionado == null
                    ? Center(
                        child: Text('Selecciona un rol',
                            style: FluentTheme.of(context).typography.body),
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          if (constraints.maxWidth >= 900) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _MatrizPermisos(
                                    rolId: rolSeleccionado.id,
                                    esSistema: rolSeleccionado.esSistema,
                                  ),
                                ),
                                const Divider(
                                    direction: Axis.vertical, size: 400),
                                SizedBox(
                                  width: 270,
                                  child: _PanelUsuarios(
                                      rolId: rolSeleccionado.id),
                                ),
                              ],
                            );
                          }
                          return _MatrizPermisos(
                            rolId: rolSeleccionado.id,
                            esSistema: rolSeleccionado.esSistema,
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Toolbar
// ---------------------------------------------------------------------------

class _Toolbar extends ConsumerWidget {
  final List<RolItem> roles;
  const _Toolbar({required this.roles});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rolSeleccionado = ref.watch(_rolSeleccionadoProvider);
    final filtroModulo = ref.watch(_filtroModuloProvider);
    final theme = FluentTheme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Selector de rol con etiqueta
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Rol:',
                  style: theme.typography.body
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(width: 6),
              SizedBox(
                width: 240,
                child: ComboBox<String>(
                  isExpanded: true,
                  value: rolSeleccionado?.id,
                  placeholder: const Text('Seleccionar rol...'),
                  items: roles
                      .map((r) => ComboBoxItem<String>(
                            value: r.id,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(r.nombre,
                                      overflow: TextOverflow.ellipsis),
                                ),
                                if (r.esSistema) ...[
                                  const SizedBox(width: 6),
                                  const InfoBadge(source: Text('S')),
                                ],
                              ],
                            ),
                          ))
                      .toList(),
                  onChanged: (id) {
                    if (id == null) return;
                    final rol = roles.firstWhere((r) => r.id == id);
                    ref.read(_rolSeleccionadoProvider.notifier).state = rol;
                    ref.read(_filtroModuloProvider.notifier).state = null;
                    ref.read(_filtroTextoProvider.notifier).state = '';
                  },
                ),
              ),
              // Botón eliminar rol (solo custom)
              if (rolSeleccionado != null && !rolSeleccionado.esSistema) ...[
                const SizedBox(width: 4),
                Tooltip(
                  message: 'Eliminar rol',
                  child: Button(
                    style: const ButtonStyle(
                      padding: WidgetStatePropertyAll(
                          EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6)),
                    ),
                    child: const Icon(FluentIcons.delete, size: 14),
                    onPressed: () =>
                        _confirmarEliminarRol(context, ref, rolSeleccionado),
                  ),
                ),
              ],
            ],
          ),
          // Separador visual
          Container(
            width: 1,
            height: 28,
            color: theme.resources.dividerStrokeColorDefault,
          ),
          // Filtro por módulo con etiqueta
          Consumer(
            builder: (context, ref, _) {
              if (rolSeleccionado == null) return const SizedBox.shrink();
              final permisosAsync =
                  ref.watch(permisosRolProvider(rolSeleccionado.id));
              final modulos = permisosAsync.valueOrNull
                  ?.map((p) => p.modulo)
                  .toSet()
                  .toList()
                ?..sort();
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Módulo:',
                      style: theme.typography.body
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 180,
                    child: ComboBox<String>(
                      isExpanded: true,
                      value: filtroModulo,
                      placeholder: const Text('Todos'),
                      items: [
                        ...(modulos ?? []).map((m) => ComboBoxItem<String>(
                              value: m,
                              child: Text(m),
                            )),
                      ],
                      onChanged: (m) =>
                          ref.read(_filtroModuloProvider.notifier).state = m,
                    ),
                  ),
                  if (filtroModulo != null) ...[
                    const SizedBox(width: 2),
                    IconButton(
                      icon: const Icon(FluentIcons.clear_filter, size: 14),
                      onPressed: () =>
                          ref.read(_filtroModuloProvider.notifier).state = null,
                    ),
                  ],
                ],
              );
            },
          ),
          // Búsqueda de permisos
          SizedBox(
            width: 200,
            child: TextBox(
              placeholder: 'Buscar permiso...',
              prefix: const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(FluentIcons.search, size: 14),
              ),
              onChanged: (v) =>
                  ref.read(_filtroTextoProvider.notifier).state = v,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Columnas fijas de la matriz (orden canónico Velneo-style)
// ---------------------------------------------------------------------------

const _kColumnasFijas = [
  'menu', 'crear', 'editar', 'eliminar', 'listar', 'inactivar', 'ejecutar',
];

const _kEtiquetasColumnas = {
  'menu': 'Menú',
  'crear': 'Crear',
  'editar': 'Editar',
  'eliminar': 'Eliminar',
  'listar': 'Listar',
  'inactivar': 'Inactivar',
  'ejecutar': 'Ejecutar',
  'configurar': 'Config.',
  'enviar': 'Enviar',
  'gestionar': 'Gestionar',
  'activar': 'Activar',
  'certificado': 'Certif.',
  'compartida': 'Compartida',
  'aprobar': 'Aprobar',
  'exportar': 'Exportar',
};

// ---------------------------------------------------------------------------
// Tipos de fila para la matriz jerárquica
// ---------------------------------------------------------------------------

sealed class _FilaData {}

class _FilaModuloData extends _FilaData {
  final String modulo;
  _FilaModuloData(this.modulo);
}

class _FilaMenuData extends _FilaData {
  final PermisoEstado permiso;
  final bool isAlternate;
  _FilaMenuData(this.permiso, this.isAlternate);
}

class _FilaTablaData extends _FilaData {
  final String recurso;
  final List<PermisoEstado> permisos; // nivel=1 para este recurso
  final bool isAlternate;
  _FilaTablaData(this.recurso, this.permisos, this.isAlternate);
}

class _FilaSubAccionData extends _FilaData {
  final PermisoEstado permiso;
  final bool isAlternate;
  _FilaSubAccionData(this.permiso, this.isAlternate);
}

// ---------------------------------------------------------------------------
// Matriz de permisos
// ---------------------------------------------------------------------------

class _MatrizPermisos extends ConsumerStatefulWidget {
  final String rolId;
  final bool esSistema;
  const _MatrizPermisos({required this.rolId, required this.esSistema});

  @override
  ConsumerState<_MatrizPermisos> createState() => _MatrizPermisosState();
}

class _MatrizPermisosState extends ConsumerState<_MatrizPermisos> {
  final Set<String> _cargando = {};
  final _verticalCtrl = ScrollController();
  final _horizontalCtrl = ScrollController();

  @override
  void dispose() {
    _verticalCtrl.dispose();
    _horizontalCtrl.dispose();
    super.dispose();
  }

  Future<void> _toggle(String permisoId, bool conceder) async {
    setState(() => _cargando.add(permisoId));
    try {
      await Supabase.instance.client.rpc('admin_toggle_permiso_rol', params: {
        'p_rol_id': widget.rolId,
        'p_permiso_id': permisoId,
        'p_conceder': conceder,
      });
      ref.invalidate(permisosRolProvider(widget.rolId));
      if (mounted) {
        displayInfoBar(context,
            builder: (_, close) => InfoBar(
                  title: Text(conceder ? 'Permiso concedido' : 'Permiso revocado'),
                  severity: InfoBarSeverity.success,
                  onClose: close,
                ));
      }
    } catch (e) {
      if (mounted) {
        displayInfoBar(context,
            builder: (_, close) => InfoBar(
                  title: const Text('Error al actualizar permiso'),
                  content: Text(e.toString()),
                  severity: InfoBarSeverity.error,
                  onClose: close,
                ));
      }
    } finally {
      if (mounted) setState(() => _cargando.remove(permisoId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final permisosAsync = ref.watch(permisosRolProvider(widget.rolId));
    final filtroModulo = ref.watch(_filtroModuloProvider);
    final filtroTexto = ref.watch(_filtroTextoProvider);

    return permisosAsync.when(
      loading: () => const Center(child: ProgressRing()),
      error: (e, _) => Center(child: Text('Error al cargar permisos: $e')),
      data: (todosPermisos) {
        final permisos = todosPermisos.where((p) {
          if (filtroModulo != null && p.modulo != filtroModulo) return false;
          if (filtroTexto.isNotEmpty) {
            final q = filtroTexto.toLowerCase();
            return p.codigo.toLowerCase().contains(q) ||
                p.recurso.toLowerCase().contains(q) ||
                p.accion.toLowerCase().contains(q) ||
                (p.descripcion?.toLowerCase().contains(q) ?? false);
          }
          return true;
        }).toList();

        if (permisos.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(FluentIcons.permissions,
                    size: 40,
                    color: FluentTheme.of(context).resources.textFillColorDisabled),
                const SizedBox(height: 12),
                Text('No hay permisos que mostrar',
                    style: FluentTheme.of(context).typography.body),
              ],
            ),
          );
        }

        // Calcular columnas: fijas en orden + extras al final (excepto ejecutar)
        final accionesEnDataset = permisos.map((p) => p.accion).toSet();
        final extras = accionesEnDataset
            .where((a) => !_kColumnasFijas.contains(a))
            .toList()
          ..sort();
        final columnas = [
          ..._kColumnasFijas.where((c) => c != 'ejecutar' && accionesEnDataset.contains(c)),
          ...extras,
          if (accionesEnDataset.contains('ejecutar')) 'ejecutar',
        ];

        // Construir lista de filas jerárquicas
        final Map<String, Map<String, List<PermisoEstado>>> byModuloRecurso = {};
        for (final p in permisos) {
          byModuloRecurso.putIfAbsent(p.modulo, () => {})
              .putIfAbsent(p.recurso, () => [])
              .add(p);
        }

        final List<_FilaData> filas = [];
        int rowIdx = 0;

        for (final modulo in byModuloRecurso.keys.toList()..sort()) {
          filas.add(_FilaModuloData(modulo));
          final porRecurso = byModuloRecurso[modulo]!;

          for (final recurso in porRecurso.keys.toList()..sort()) {
            final grupo = porRecurso[recurso]!;
            final menus = grupo.where((p) => p.nivel == 0).toList();
            final tabla = grupo.where((p) => p.nivel == 1).toList();
            final subacciones = grupo.where((p) => p.nivel == 2).toList();

            for (final p in menus) {
              filas.add(_FilaMenuData(p, rowIdx % 2 == 1));
              rowIdx++;
            }
            if (tabla.isNotEmpty) {
              filas.add(_FilaTablaData(recurso, tabla, rowIdx % 2 == 1));
              rowIdx++;
            }
            for (final p in subacciones) {
              filas.add(_FilaSubAccionData(p, rowIdx % 2 == 1));
              rowIdx++;
            }
          }
        }

        final theme = FluentTheme.of(context);
        const colDesc = 260.0;
        const colAccion = 80.0;
        final totalWidth = colDesc + 1 + columnas.length * colAccion;
        final borderColor = theme.resources.dividerStrokeColorDefault;

        return Scrollbar(
          controller: _verticalCtrl,
          child: SingleChildScrollView(
            controller: _verticalCtrl,
            child: SingleChildScrollView(
              controller: _horizontalCtrl,
              scrollDirection: Axis.horizontal,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Cabecera ─────────────────────────────────────
                  _CabeceraMat(
                    columnas: columnas,
                    totalWidth: totalWidth,
                    colDesc: colDesc,
                    colAccion: colAccion,
                    borderColor: borderColor,
                  ),
                  // ── Filas ─────────────────────────────────────────
                  ...filas.map((fila) {
                    return switch (fila) {
                      _FilaModuloData d => _RowModulo(
                          modulo: d.modulo,
                          totalWidth: totalWidth,
                          borderColor: borderColor,
                        ),
                      _FilaMenuData d => _RowMenu(
                          permiso: d.permiso,
                          columnas: columnas,
                          colDesc: colDesc,
                          colAccion: colAccion,
                          isAlternate: d.isAlternate,
                          borderColor: borderColor,
                          cargando: _cargando,
                          esSistema: widget.esSistema,
                          onToggle: _toggle,
                        ),
                      _FilaTablaData d => _RowTabla(
                          recurso: d.recurso,
                          permisos: d.permisos,
                          columnas: columnas,
                          colDesc: colDesc,
                          colAccion: colAccion,
                          isAlternate: d.isAlternate,
                          borderColor: borderColor,
                          cargando: _cargando,
                          esSistema: widget.esSistema,
                          onToggle: _toggle,
                        ),
                      _FilaSubAccionData d => _RowSubAccion(
                          permiso: d.permiso,
                          columnas: columnas,
                          colDesc: colDesc,
                          colAccion: colAccion,
                          isAlternate: d.isAlternate,
                          borderColor: borderColor,
                          cargando: _cargando,
                          esSistema: widget.esSistema,
                          onToggle: _toggle,
                        ),
                    };
                  }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Cabecera de la matriz
// ---------------------------------------------------------------------------

class _CabeceraMat extends StatelessWidget {
  final List<String> columnas;
  final double totalWidth, colDesc, colAccion;
  final Color borderColor;

  const _CabeceraMat({
    required this.columnas,
    required this.totalWidth,
    required this.colDesc,
    required this.colAccion,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Container(
      width: totalWidth,
      decoration: BoxDecoration(
        color: theme.accentColor.withValues(alpha: 0.12),
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: colDesc,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Text('Descripción', style: theme.typography.bodyStrong),
            ),
          ),
          Container(width: 1, height: 36, color: borderColor),
          ...columnas.map((col) => Container(
                width: colAccion,
                decoration: BoxDecoration(
                  border: Border(right: BorderSide(color: borderColor)),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                  child: Tooltip(
                    message: col,
                    child: Text(
                      _kEtiquetasColumnas[col] ?? _capitalize(col),
                      style: theme.typography.bodyStrong?.copyWith(fontSize: 11),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              )),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Fila: encabezado de módulo
// ---------------------------------------------------------------------------

class _RowModulo extends StatelessWidget {
  final String modulo;
  final double totalWidth;
  final Color borderColor;

  const _RowModulo(
      {required this.modulo, required this.totalWidth, required this.borderColor});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Container(
      width: totalWidth,
      decoration: BoxDecoration(
        color: theme.accentColor.withValues(alpha: 0.07),
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Icon(FluentIcons.permissions, size: 12, color: theme.accentColor),
          const SizedBox(width: 6),
          Text(
            modulo.toUpperCase(),
            style: theme.typography.bodyStrong
                ?.copyWith(color: theme.accentColor, letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Fila: ítem de menú (nivel=0) — solo columna "menu" activa
// ---------------------------------------------------------------------------

class _RowMenu extends StatelessWidget {
  final PermisoEstado permiso;
  final List<String> columnas;
  final double colDesc, colAccion;
  final bool isAlternate, esSistema;
  final Color borderColor;
  final Set<String> cargando;
  final void Function(String, bool) onToggle;

  const _RowMenu({
    required this.permiso,
    required this.columnas,
    required this.colDesc,
    required this.colAccion,
    required this.isAlternate,
    required this.borderColor,
    required this.cargando,
    required this.esSistema,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: isAlternate
            ? theme.resources.subtleFillColorSecondary
            : Colors.transparent,
        border: Border(bottom: BorderSide(color: borderColor, width: 0.5)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: colDesc,
            child: Padding(
              padding: const EdgeInsets.only(left: 12, right: 8, top: 7, bottom: 7),
              child: Row(
                children: [
                  Icon(FluentIcons.nav2_d_map_view,
                      size: 12,
                      color: theme.accentColor.withValues(alpha: 0.8)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Menú: ${_prettifyRecurso(permiso.recurso)}',
                      style: theme.typography.bodyStrong,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(width: 1, height: 34, color: borderColor),
          ...columnas.map((col) {
            // Solo la columna 'menu' es activa para filas de nivel=0
            if (col == 'menu') {
              return _CeldaCheck(
                permiso: permiso,
                colAccion: colAccion,
                borderColor: borderColor,
                cargando: cargando,
                esSistema: esSistema,
                onToggle: onToggle,
              );
            }
            return _CeldaVacia(colAccion: colAccion, borderColor: borderColor);
          }),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Fila: tabla/CRUD (nivel=1) — columnas CRUD activas, menu/ejecutar vacías
// ---------------------------------------------------------------------------

class _RowTabla extends StatelessWidget {
  final String recurso;
  final List<PermisoEstado> permisos;
  final List<String> columnas;
  final double colDesc, colAccion;
  final bool isAlternate, esSistema;
  final Color borderColor;
  final Set<String> cargando;
  final void Function(String, bool) onToggle;

  const _RowTabla({
    required this.recurso,
    required this.permisos,
    required this.columnas,
    required this.colDesc,
    required this.colAccion,
    required this.isAlternate,
    required this.borderColor,
    required this.cargando,
    required this.esSistema,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: isAlternate
            ? theme.resources.subtleFillColorSecondary
            : Colors.transparent,
        border: Border(bottom: BorderSide(color: borderColor, width: 0.5)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: colDesc,
            child: Padding(
              padding: const EdgeInsets.only(left: 24, right: 8, top: 7, bottom: 7),
              child: Text(
                'Tabla: ${_prettifyRecurso(recurso)}',
                style: theme.typography.body,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Container(width: 1, height: 34, color: borderColor),
          ...columnas.map((col) {
            // menu y ejecutar no aplican para nivel=1
            if (col == 'menu' || col == 'ejecutar') {
              return _CeldaVacia(colAccion: colAccion, borderColor: borderColor);
            }
            final permiso = permisos.where((p) => p.accion == col).firstOrNull;
            if (permiso == null) {
              return _CeldaVacia(colAccion: colAccion, borderColor: borderColor);
            }
            return _CeldaCheck(
              permiso: permiso,
              colAccion: colAccion,
              borderColor: borderColor,
              cargando: cargando,
              esSistema: esSistema,
              onToggle: onToggle,
            );
          }),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Fila: sub-acción (nivel=2) — solo columna "ejecutar" activa
// ---------------------------------------------------------------------------

class _RowSubAccion extends StatelessWidget {
  final PermisoEstado permiso;
  final List<String> columnas;
  final double colDesc, colAccion;
  final bool isAlternate, esSistema;
  final Color borderColor;
  final Set<String> cargando;
  final void Function(String, bool) onToggle;

  const _RowSubAccion({
    required this.permiso,
    required this.columnas,
    required this.colDesc,
    required this.colAccion,
    required this.isAlternate,
    required this.borderColor,
    required this.cargando,
    required this.esSistema,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: isAlternate
            ? theme.resources.subtleFillColorSecondary
            : Colors.transparent,
        border: Border(bottom: BorderSide(color: borderColor, width: 0.5)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: colDesc,
            child: Padding(
              padding: const EdgeInsets.only(left: 36, right: 8, top: 7, bottom: 7),
              child: Text(
                permiso.descripcion ?? permiso.codigo,
                style: theme.typography.caption
                    ?.copyWith(color: theme.resources.textFillColorSecondary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Container(width: 1, height: 34, color: borderColor),
          ...columnas.map((col) {
            // Solo la columna 'ejecutar' es activa para nivel=2
            if (col == 'ejecutar') {
              return _CeldaCheck(
                permiso: permiso,
                colAccion: colAccion,
                borderColor: borderColor,
                cargando: cargando,
                esSistema: esSistema,
                onToggle: onToggle,
              );
            }
            return _CeldaVacia(colAccion: colAccion, borderColor: borderColor);
          }),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Celda: vacía (no aplica para este nivel/recurso)
// ---------------------------------------------------------------------------

class _CeldaVacia extends StatelessWidget {
  final double colAccion;
  final Color borderColor;

  const _CeldaVacia({required this.colAccion, required this.borderColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: colAccion,
      height: 34,
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: borderColor, width: 0.5)),
      ),
      alignment: Alignment.center,
      child: Text(
        '\u2014',
        style: FluentTheme.of(context)
            .typography
            .caption
            ?.copyWith(color: FluentTheme.of(context).resources.textFillColorDisabled),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Celda: checkbox con loading y toggle
// ---------------------------------------------------------------------------

class _CeldaCheck extends StatelessWidget {
  final PermisoEstado permiso;
  final double colAccion;
  final Color borderColor;
  final Set<String> cargando;
  final bool esSistema;
  final void Function(String, bool) onToggle;

  const _CeldaCheck({
    required this.permiso,
    required this.colAccion,
    required this.borderColor,
    required this.cargando,
    required this.esSistema,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final isLoading = cargando.contains(permiso.id);
    return Container(
      width: colAccion,
      height: 34,
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: borderColor, width: 0.5)),
      ),
      alignment: Alignment.center,
      child: isLoading
          ? const SizedBox(width: 14, height: 14, child: ProgressRing(strokeWidth: 2))
          : Tooltip(
              message: esSistema
                  ? '${permiso.codigo}\n(override por empresa)'
                  : permiso.codigo,
              child: Checkbox(
                checked: permiso.tienePermiso,
                onChanged: (v) => onToggle(permiso.id, v ?? false),
              ),
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

String _prettifyRecurso(String recurso) =>
    recurso.replaceAll('_', ' ').split(' ').map(_capitalize).join(' ');

// ---------------------------------------------------------------------------
// Panel de usuarios asignados
// ---------------------------------------------------------------------------

class _PanelUsuarios extends ConsumerWidget {
  final String rolId;
  const _PanelUsuarios({required this.rolId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usuariosAsync = ref.watch(usuariosRolProvider(rolId));
    final theme = FluentTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: theme.resources.subtleFillColorSecondary,
            border: Border(
              bottom: BorderSide(
                  color: theme.resources.dividerStrokeColorDefault),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const Icon(FluentIcons.people, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Usuarios asignados',
                    style: theme.typography.bodyStrong,
                    overflow: TextOverflow.ellipsis),
              ),
              // Badge con el conteo
              usuariosAsync.whenOrNull(
                    data: (u) => u.isNotEmpty
                        ? Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: InfoBadge(source: Text('${u.length}')),
                          )
                        : null,
                  ) ??
                  const SizedBox.shrink(),
              IconButton(
                icon: const Icon(FluentIcons.add_friend, size: 16),
                onPressed: () =>
                    _mostrarAsignarUsuarioDialog(context, ref, rolId),
              ),
            ],
          ),
        ),
        Expanded(
          child: usuariosAsync.when(
            loading: () => const Center(child: ProgressRing()),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: InfoBar(
                title: const Text('Error al cargar usuarios'),
                content: Text(e.toString()),
                severity: InfoBarSeverity.error,
              ),
            ),
            data: (usuarios) {
              if (usuarios.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(FluentIcons.people,
                          size: 36,
                          color: theme.resources.textFillColorDisabled),
                      const SizedBox(height: 8),
                      Text('Sin usuarios asignados',
                          style: theme.typography.caption?.copyWith(
                              color: theme.resources.textFillColorDisabled)),
                    ],
                  ),
                );
              }
              return ListView.separated(
                itemCount: usuarios.length,
                separatorBuilder: (_, __) => Divider(
                  style: DividerThemeData(
                    horizontalMargin: const EdgeInsets.only(left: 52),
                    decoration: BoxDecoration(
                      color: theme.resources.dividerStrokeColorDefault,
                    ),
                  ),
                ),
                itemBuilder: (context, i) {
                  final u = usuarios[i];
                  return _UsuarioCard(
                    usuario: u,
                    onQuitar: () =>
                        _quitarUsuarioRol(context, ref, u, rolId),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _quitarUsuarioRol(BuildContext context, WidgetRef ref,
      UsuarioRolItem usuario, String rolId) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => ContentDialog(
        title: const Text('Quitar usuario del rol'),
        content:
            Text('Deseas quitar a ${usuario.nombreDisplay} de este rol?'),
        actions: [
          Button(
            child: const Text('Cancelar'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          FilledButton(
            child: const Text('Quitar'),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmar != true || !context.mounted) return;

    try {
      await Supabase.instance.client.rpc('admin_toggle_usuario_rol', params: {
        'p_usuario_id': usuario.usuarioId,
        'p_rol_id': rolId,
        'p_asignar': false,
      });
      ref.invalidate(usuariosRolProvider(rolId));
      if (context.mounted) {
        displayInfoBar(context,
            builder: (_, close) => InfoBar(
                  title: Text('${usuario.nombreDisplay} eliminado del rol'),
                  severity: InfoBarSeverity.success,
                  onClose: close,
                ));
      }
    } catch (e) {
      if (context.mounted) {
        displayInfoBar(context,
            builder: (_, close) => InfoBar(
                  title: const Text('Error al quitar usuario'),
                  content: Text(e.toString()),
                  severity: InfoBarSeverity.error,
                  onClose: close,
                ));
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Tarjeta de usuario en el panel
// ---------------------------------------------------------------------------

class _UsuarioCard extends StatelessWidget {
  final UsuarioRolItem usuario;
  final VoidCallback onQuitar;

  const _UsuarioCard({required this.usuario, required this.onQuitar});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final initials = usuario.nombreDisplay.isNotEmpty
        ? usuario.nombreDisplay[0].toUpperCase()
        : '?';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.accentColor.withValues(alpha: 0.18),
              border: Border.all(
                  color: theme.accentColor.withValues(alpha: 0.3), width: 1),
            ),
            alignment: Alignment.center,
            child: Text(
              initials,
              style: theme.typography.bodyStrong?.copyWith(
                color: theme.accentColor,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(usuario.nombreDisplay,
                    style: theme.typography.body,
                    overflow: TextOverflow.ellipsis),
                Text(usuario.email,
                    style: theme.typography.caption?.copyWith(
                        color: theme.resources.textFillColorSecondary),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(FluentIcons.chrome_close, size: 11),
            onPressed: onQuitar,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dialogos
// ---------------------------------------------------------------------------

Future<void> _mostrarNuevoRolDialog(BuildContext context, WidgetRef ref) async {
  final codigoCtrl = TextEditingController();
  final nombreCtrl = TextEditingController();
  final descCtrl = TextEditingController();

  await showDialog(
    context: context,
    builder: (_) => ContentDialog(
      title: const Text('Nuevo Rol'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InfoLabel(
            label: 'Codigo',
            child: TextBox(
              controller: codigoCtrl,
              placeholder: 'CUSTOM_ROL',
            ),
          ),
          const SizedBox(height: 12),
          InfoLabel(
            label: 'Nombre',
            child: TextBox(
              controller: nombreCtrl,
              placeholder: 'Nombre del rol',
            ),
          ),
          const SizedBox(height: 12),
          InfoLabel(
            label: 'Descripcion (opcional)',
            child: TextBox(
              controller: descCtrl,
              placeholder: 'Descripcion...',
              maxLines: 3,
            ),
          ),
        ],
      ),
      actions: [
        Button(
          child: const Text('Cancelar'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        FilledButton(
          child: const Text('Crear'),
          onPressed: () async {
            final codigo = codigoCtrl.text.trim();
            final nombre = nombreCtrl.text.trim();
            if (codigo.isEmpty || nombre.isEmpty) return;

            try {
              await Supabase.instance.client.rpc('admin_crear_rol', params: {
                'p_codigo': codigo,
                'p_nombre': nombre,
                'p_descripcion': descCtrl.text.trim().isEmpty
                    ? null
                    : descCtrl.text.trim(),
              });
              ref.invalidate(rolesAdminProvider);
              if (context.mounted) Navigator.of(context).pop();
              if (context.mounted) {
                displayInfoBar(context,
                    builder: (_, close) => InfoBar(
                          title: Text('Rol "$nombre" creado'),
                          severity: InfoBarSeverity.success,
                          onClose: close,
                        ));
              }
            } catch (e) {
              if (context.mounted) {
                displayInfoBar(context,
                    builder: (_, close) => InfoBar(
                          title: const Text('Error al crear rol'),
                          content: Text(e.toString()),
                          severity: InfoBarSeverity.error,
                          onClose: close,
                        ));
              }
            }
          },
        ),
      ],
    ),
  );
  codigoCtrl.dispose();
  nombreCtrl.dispose();
  descCtrl.dispose();
}

Future<void> _mostrarAsignarUsuarioDialog(
    BuildContext context, WidgetRef ref, String rolId) async {
  final usuariosRol = ref.read(usuariosRolProvider(rolId)).valueOrNull ?? [];
  final usuariosRolIds = usuariosRol.map((u) => u.usuarioId).toSet();

  List<Map<String, dynamic>> todosUsuarios = [];
  String? errorCarga;
  try {
    final data = await Supabase.instance.client.rpc('admin_get_usuarios');
    todosUsuarios = (data as List).cast<Map<String, dynamic>>();
  } catch (e) {
    errorCarga = e.toString();
  }

  // Solo usuarios reales (excluye invitaciones pendientes que tienen usuario_id=null)
  // y excluye los que YA están asignados a ESTE rol específico.
  // Usuarios con otros roles SÍ aparecen — un usuario puede tener múltiples roles.
  final disponibles = todosUsuarios
      .where((u) => u['usuario_id'] != null) // excluir invitaciones pendientes
      .where((u) => !usuariosRolIds.contains(u['usuario_id'] as String))
      .toList();

  if (!context.mounted) return;

  String? seleccionadoId;
  String? seleccionadoNombre;

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => ContentDialog(
        title: const Text('Asignar usuario al rol'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (errorCarga != null)
              InfoBar(
                title: const Text('Error al cargar usuarios'),
                content: Text(errorCarga),
                severity: InfoBarSeverity.error,
              )
            else if (disponibles.isEmpty)
              const Text('No hay usuarios disponibles para asignar')
            else
              AutoSuggestBox<String>(
                placeholder: 'Buscar usuario...',
                items: disponibles.map((u) {
                  final nombre = u['nombre_display'] as String? ??
                      u['email'] as String? ??
                      '';
                  final id = u['usuario_id'] as String? ?? '';
                  return AutoSuggestBoxItem<String>(
                    value: id,
                    label: nombre,
                    child: Text(nombre),
                  );
                }).toList(),
                onSelected: (item) {
                  setState(() {
                    seleccionadoId = item.value;
                    seleccionadoNombre = item.label;
                  });
                },
              ),
          ],
        ),
        actions: [
          Button(
            child: const Text('Cancelar'),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          FilledButton(
            onPressed: seleccionadoId == null
                ? null
                : () async {
                    try {
                      await Supabase.instance.client
                          .rpc('admin_toggle_usuario_rol', params: {
                        'p_usuario_id': seleccionadoId,
                        'p_rol_id': rolId,
                        'p_asignar': true,
                      });
                      ref.invalidate(usuariosRolProvider(rolId));
                      if (ctx.mounted) Navigator.of(ctx).pop();
                      if (context.mounted) {
                        displayInfoBar(context,
                            builder: (_, close) => InfoBar(
                                  title: Text(
                                      '${seleccionadoNombre ?? ''} asignado al rol'),
                                  severity: InfoBarSeverity.success,
                                  onClose: close,
                                ));
                      }
                    } catch (e) {
                      if (context.mounted) {
                        displayInfoBar(context,
                            builder: (_, close) => InfoBar(
                                  title:
                                      const Text('Error al asignar usuario'),
                                  content: Text(e.toString()),
                                  severity: InfoBarSeverity.error,
                                  onClose: close,
                                ));
                      }
                    }
                  },
            child: const Text('Asignar'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _confirmarEliminarRol(
    BuildContext context, WidgetRef ref, RolItem rol) async {
  final confirmar = await showDialog<bool>(
    context: context,
    builder: (_) => ContentDialog(
      title: const Text('Eliminar rol'),
      content: Text(
          'Deseas eliminar el rol "${rol.nombre}"? Esta accion no se puede deshacer.'),
      actions: [
        Button(
          child: const Text('Cancelar'),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        FilledButton(
          style: const ButtonStyle(
            backgroundColor:
                WidgetStatePropertyAll(Colors.errorPrimaryColor),
          ),
          child: const Text('Eliminar'),
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  if (confirmar != true || !context.mounted) return;

  try {
    await Supabase.instance.client
        .rpc('admin_eliminar_rol', params: {'p_rol_id': rol.id});
    ref.invalidate(rolesAdminProvider);
    ref.read(_rolSeleccionadoProvider.notifier).state = null;
    if (context.mounted) {
      displayInfoBar(context,
          builder: (_, close) => InfoBar(
                title: Text('Rol "${rol.nombre}" eliminado'),
                severity: InfoBarSeverity.success,
                onClose: close,
              ));
    }
  } catch (e) {
    final msg = e.toString().contains('tiene_usuarios_asignados')
        ? 'No se puede eliminar: el rol tiene usuarios asignados'
        : e.toString();
    if (context.mounted) {
      displayInfoBar(context,
          builder: (_, close) => InfoBar(
                title: const Text('Error al eliminar rol'),
                content: Text(msg),
                severity: InfoBarSeverity.error,
                onClose: close,
              ));
    }
  }
}
