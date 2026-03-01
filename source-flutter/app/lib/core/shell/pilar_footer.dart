import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../offline/connectivity_service.dart';
import '../providers/app_version_provider.dart';
import '../providers/empresa_provider.dart';

/// Barra de estado inferior de PILAR ERP.
///
/// Muestra tres zonas:
/// - **Izquierda**: nombre de la empresa activa.
/// - **Centro**: versión de la aplicación.
/// - **Derecha**: indicador de conectividad + reloj en tiempo real.
///
/// Altura fija de 24 px. Se integra como última fila del [paneBodyBuilder]
/// en [PilarShell].
class PilarFooter extends ConsumerStatefulWidget {
  const PilarFooter({super.key});

  @override
  ConsumerState<PilarFooter> createState() => _PilarFooterState();
}

class _PilarFooterState extends ConsumerState<PilarFooter> {
  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _timeStr {
    final h = _now.hour.toString().padLeft(2, '0');
    final m = _now.minute.toString().padLeft(2, '0');
    final s = _now.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = ref.watch(connectivityProvider);
    final empresaAsync = ref.watch(empresaConfigProvider);
    final empresaNombre = empresaAsync.valueOrNull?.nombre ?? '';
    final versionInfo = ref.watch(appVersionProvider).valueOrNull;
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgColor =
        isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF0F0F0);
    final textColor = theme.resources.textFillColorSecondary;
    final appVersion = versionInfo != null
        ? 'PILAR ERP v${versionInfo.version}'
        : 'PILAR ERP';

    return Container(
      height: 24,
      color: bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          // ── Izquierda: empresa ───────────────────────────────────────────
          if (empresaNombre.isNotEmpty) ...[
            Icon(
              FluentIcons.company_directory,
              size: 11,
              color: textColor,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                empresaNombre,
                style: theme.typography.caption?.copyWith(color: textColor),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],

          const Spacer(),

          // ── Centro: versión ──────────────────────────────────────────────
          Text(
            appVersion,
            style: theme.typography.caption?.copyWith(color: textColor),
          ),

          const Spacer(),

          // ── Derecha: conectividad + reloj ────────────────────────────────
          _ConnectivityBadge(isOnline: isOnline, textColor: textColor),
          const SizedBox(width: 10),
          Icon(
            FluentIcons.clock,
            size: 11,
            color: textColor,
          ),
          const SizedBox(width: 3),
          Text(
            _timeStr,
            style: theme.typography.caption?.copyWith(
              color: textColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectivityBadge extends StatelessWidget {
  const _ConnectivityBadge({
    required this.isOnline,
    required this.textColor,
  });

  final bool isOnline;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final dotColor =
        isOnline ? Colors.successPrimaryColor : Colors.errorPrimaryColor;
    final label = isOnline ? 'Conectado' : 'Sin conexión';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: dotColor,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.typography.caption?.copyWith(color: textColor),
        ),
      ],
    );
  }
}
