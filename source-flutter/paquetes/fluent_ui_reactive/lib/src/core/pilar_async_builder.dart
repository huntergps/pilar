import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Core building block for all reactive widgets in fluent_ui_reactive.
///
/// Handles the three states of [AsyncValue] using fluent_ui widgets:
/// - **loading** → [ProgressRing] (or custom [loadingWidget])
/// - **error** → [InfoBar] with error severity (or custom [errorBuilder])
/// - **data** → your [builder] (or [emptyWidget] if [isEmpty] returns true)
///
/// ## Example
///
/// ```dart
/// // In a ConsumerWidget:
/// PilarAsyncBuilder<List<Cliente>>(
///   value: ref.watch(clientesProvider),
///   builder: (context, clientes) => Text('${clientes.length} clientes'),
/// )
/// ```
///
/// ## Reactive pattern with Brick + Riverpod
///
/// ```dart
/// // 1. StreamProvider wraps Brick's subscribe()
/// @riverpod
/// Stream<List<Factura>> facturas(Ref ref) =>
///     ref.watch(facturaRepoProvider).subscribe();
///
/// // 2. ConsumerWidget uses PilarAsyncBuilder
/// class FacturasWidget extends ConsumerWidget {
///   @override
///   Widget build(BuildContext context, WidgetRef ref) {
///     return PilarAsyncBuilder<List<Factura>>(
///       value: ref.watch(facturasProvider),
///       builder: (context, facturas) => Text('${facturas.length} facturas'),
///     );
///   }
/// }
/// ```
///
/// When SQLite changes via `repo.upsert()` → Stream emits new list
/// → Riverpod AsyncValue updates → widget rebuilds automatically.
class PilarAsyncBuilder<T> extends StatelessWidget {
  /// The async value to react to. Typically from [ref.watch(someProvider)].
  final AsyncValue<T> value;

  /// Called when data is available (and not empty per [isEmpty]).
  final Widget Function(BuildContext context, T data) builder;

  /// Shown while [value] is [AsyncLoading]. Defaults to centered [ProgressRing].
  final Widget? loadingWidget;

  /// Called when [value] is [AsyncError]. Defaults to an error [InfoBar].
  final Widget Function(Object error, StackTrace? stack)? errorBuilder;

  /// Shown when [isEmpty] returns true. Defaults to 'Sin registros' text.
  final Widget? emptyWidget;

  /// Predicate to determine if data should show [emptyWidget] instead of [builder].
  /// If null, [builder] is always called when data is available.
  final bool Function(T data)? isEmpty;

  const PilarAsyncBuilder({
    super.key,
    required this.value,
    required this.builder,
    this.loadingWidget,
    this.errorBuilder,
    this.emptyWidget,
    this.isEmpty,
  });

  @override
  Widget build(BuildContext context) {
    return value.when(
      loading: () => loadingWidget ?? const Center(child: ProgressRing()),
      error: (err, stack) {
        if (errorBuilder != null) return errorBuilder!(err, stack);
        return Padding(
          padding: const EdgeInsets.all(8.0),
          child: InfoBar(
            title: const Text('Error al cargar datos'),
            content: Text(err.toString()),
            severity: InfoBarSeverity.error,
          ),
        );
      },
      data: (data) {
        if (isEmpty != null && isEmpty!(data)) {
          return emptyWidget ??
              Center(
                child: Text(
                  'Sin registros',
                  style: FluentTheme.of(context).typography.body,
                ),
              );
        }
        return builder(context, data);
      },
    );
  }
}
