import 'package:fluent_ui/fluent_ui.dart';
import 'package:fluent_ui_reactive/src/crud/form_section.dart';

/// Pantalla estándar de creación/edición para PILAR ERP.
///
/// Combina [ScaffoldPage] + [PageHeader] + [CommandBar] con botones Cancelar y
/// Guardar, y un formulario de secciones desplazable.
///
/// ### Ejemplo básico
/// ```dart
/// FormScaffold(
///   title: 'Nuevo cliente',
///   isDirty: _dirty,
///   isLoading: _loading,
///   onSave: _guardar,
///   onCancel: () => context.pop(),
///   sections: [
///     FormSection(
///       title: 'Datos generales',
///       columns: 2,
///       children: [
///         PilarTextField(label: 'Nombre', controller: _nombreCtrl),
///         PilarTextField(label: 'RUC',    controller: _rucCtrl),
///       ],
///     ),
///   ],
/// )
/// ```
///
/// ### Comportamiento
/// - El [CommandBar] incluye `[...extraActions, Cancelar, Guardar]`.
/// - Mientras [onSave] está en curso, el botón Guardar muestra un [ProgressRing]
///   inline y se desactiva para evitar envíos duplicados.
/// - Si [isDirty] es `true`, el título muestra `"$title •"`.
/// - Si [isLoading] es `true`, el cuerpo muestra un [ProgressRing] centrado.
/// - Los errores se muestran como [InfoBar] encima de las secciones.
class FormScaffold extends StatefulWidget {
  const FormScaffold({
    required this.title,
    required this.sections,
    required this.onSave,
    super.key,
    this.formKey,
    this.onCancel,
    this.saveLabel = 'Guardar',
    this.cancelLabel = 'Cancelar',
    this.isDirty = false,
    this.isLoading = false,
    this.autovalidate = false,
    this.padding = const EdgeInsets.all(24),
    this.extraActions,
  });

  /// Título de la pantalla. Se le agrega " •" cuando [isDirty] es `true`.
  final String title;

  /// Secciones del formulario, renderizadas en orden vertical.
  final List<FormSection> sections;

  /// Callback asíncrono ejecutado al presionar Guardar.
  ///
  /// Si lanza una excepción, el error se muestra en un [InfoBar].
  final Future<void> Function() onSave;

  /// Clave global del [Form] interno. Útil para invocar `validate()` desde fuera.
  final GlobalKey<FormState>? formKey;

  /// Callback ejecutado al presionar Cancelar. Si es `null`, el botón no se muestra.
  final VoidCallback? onCancel;

  /// Etiqueta del botón de guardado. Por defecto: `'Guardar'`.
  final String saveLabel;

  /// Etiqueta del botón de cancelación. Por defecto: `'Cancelar'`.
  final String cancelLabel;

  /// Indica si hay cambios sin guardar. Cuando es `true`, agrega " •" al título.
  final bool isDirty;

  /// Cuando es `true`, muestra un [ProgressRing] en lugar del contenido del formulario.
  final bool isLoading;

  /// Si `true`, activa la validación automática al cambiar campos ([AutovalidateMode.onUserInteraction]).
  final bool autovalidate;

  /// Padding aplicado al cuerpo del formulario.
  final EdgeInsets padding;

  /// Acciones adicionales en el [CommandBar], antes de Cancelar y Guardar.
  final List<CommandBarItem>? extraActions;

  @override
  State<FormScaffold> createState() => _FormScaffoldState();
}

class _FormScaffoldState extends State<FormScaffold> {
  late final GlobalKey<FormState> _formKey;
  bool _saving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _formKey = widget.formKey ?? GlobalKey<FormState>();
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _handleSave() async {
    // Validate the form if it has validators.
    final formState = _formKey.currentState;
    if (formState != null && !formState.validate()) return;

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      await widget.onSave();
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Build helpers
  // ---------------------------------------------------------------------------

  String get _effectiveTitle =>
      widget.isDirty ? '${widget.title} •' : widget.title;

  List<CommandBarItem> _buildCommandBarItems() {
    return [
      if (widget.extraActions != null) ...widget.extraActions!,
      if (widget.onCancel != null)
        CommandBarButton(
          icon: const Icon(FluentIcons.chrome_close),
          label: Text(widget.cancelLabel),
          onPressed: _saving ? null : widget.onCancel,
        ),
      CommandBarBuilderItem(
        builder: (context, displayMode, child) => child,
        wrappedItem: CommandBarButton(
          icon: const Icon(FluentIcons.save),
          label: Text(widget.saveLabel),
          onPressed: _saving ? null : _handleSave,
        ),
      ),
    ];
  }

  Widget _buildContent(BuildContext context) {
    if (widget.isLoading) {
      return const Center(child: ProgressRing());
    }

    return SingleChildScrollView(
      child: Padding(
        padding: widget.padding,
        child: Form(
          key: _formKey,
          autovalidateMode: widget.autovalidate
              ? AutovalidateMode.onUserInteraction
              : AutovalidateMode.disabled,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_errorMessage != null) ...[
                InfoBar(
                  title: const Text('Error al guardar'),
                  content: Text(_errorMessage!),
                  severity: InfoBarSeverity.error,
                  onClose: () => setState(() => _errorMessage = null),
                ),
                const SizedBox(height: 16),
              ],
              for (int i = 0; i < widget.sections.length; i++) ...[
                widget.sections[i],
                if (i < widget.sections.length - 1)
                  const SizedBox(height: 24),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      header: PageHeader(
        title: Text(_effectiveTitle),
        commandBar: CommandBar(
          mainAxisAlignment: MainAxisAlignment.end,
          primaryItems: _buildCommandBarItems(),
        ),
      ),
      content: _buildContent(context),
    );
  }
}
