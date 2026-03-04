import 'package:fluent_ui/fluent_ui.dart';

/// Wrapper consistente sobre [ProgressRing] con tamaño configurable.
///
/// Reemplaza el boilerplate `SizedBox(width: X, height: X, child: ProgressRing())`.
///
/// Uso:
/// ```dart
/// const PilarProgressRing()         // 24×24 (default)
/// const PilarProgressRing(size: 32) // grande
/// const PilarProgressRing.small()   // 16×16
/// ```
class PilarProgressRing extends StatelessWidget {
  const PilarProgressRing({super.key, this.size = 24.0});
  const PilarProgressRing.small({super.key}) : size = 16.0;
  const PilarProgressRing.large({super.key}) : size = 36.0;

  final double size;

  @override
  Widget build(BuildContext context) =>
      SizedBox.square(dimension: size, child: const ProgressRing());
}

/// Centro con [PilarProgressRing] — para pantallas en estado loading.
class PilarLoadingCenter extends StatelessWidget {
  const PilarLoadingCenter({super.key});

  @override
  Widget build(BuildContext context) =>
      const Center(child: PilarProgressRing());
}
