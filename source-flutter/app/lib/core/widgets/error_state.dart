import 'package:fluent_ui/fluent_ui.dart';

/// Estado de error consistente para pantallas y listas.
///
/// Uso:
/// ```dart
/// PilarErrorState(error: e)
/// PilarErrorState(error: e, onRetry: () => ref.invalidate(provider))
/// PilarErrorState(
///   message: 'No se pudo cargar los datos',
///   onRetry: () => ref.invalidate(provider),
/// )
/// ```
class PilarErrorState extends StatelessWidget {
  const PilarErrorState({
    super.key,
    this.error,
    this.message,
    this.onRetry,
  }) : assert(error != null || message != null,
            'Provide error or message');

  final Object? error;
  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final errorText = message ?? _simplify(error);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FluentIcons.error_badge,
              size: 48,
              color: theme.resources.systemFillColorCriticalBackground,
            ),
            const SizedBox(height: 12),
            Text(
              errorText,
              style: theme.typography.body,
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              Button(
                onPressed: onRetry,
                child: const Text('Reintentar'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _simplify(Object? error) {
    if (error == null) return 'Error desconocido';
    final s = error.toString();
    // Muestra solo la primera línea para no exponer stack traces
    return s.split('\n').first.trim();
  }
}
