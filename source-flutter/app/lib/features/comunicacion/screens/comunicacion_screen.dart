import 'package:fluent_ui/fluent_ui.dart';

import 'conversaciones_tab.dart';
import 'email_tab.dart';
import 'historial_tab.dart';
import 'chat_tab.dart';

/// Pantalla principal del módulo de Comunicación.
///
/// Presenta un [TabView] de fluent_ui con 4 pestañas:
///   0 → Conversaciones (bandeja externa multicanal WhatsApp/Telegram)
///   1 → Email (interfaz estilo Gmail para email_api/email_smtp)
///   2 → Historial (log de mensajes salientes)
///   3 → Chat interno (entre usuarios ERP)
///
/// El parámetro [tabIndex] permite navegar directamente a una pestaña
/// desde el router (rutas /comunicacion/email, /comunicacion/historial, /comunicacion/chat).
class ComunicacionScreen extends StatefulWidget {
  final int tabIndex;

  const ComunicacionScreen({super.key, this.tabIndex = 0});

  @override
  State<ComunicacionScreen> createState() => _ComunicacionScreenState();
}

class _ComunicacionScreenState extends State<ComunicacionScreen> {
  late int _tabIndex;

  @override
  void initState() {
    super.initState();
    _tabIndex = widget.tabIndex.clamp(0, 3);
  }

  @override
  void didUpdateWidget(ComunicacionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabIndex != widget.tabIndex) {
      setState(() => _tabIndex = widget.tabIndex.clamp(0, 3));
    }
  }

  @override
  Widget build(BuildContext context) {
    return TabView(
      currentIndex: _tabIndex,
      onChanged: (i) => setState(() => _tabIndex = i),
      closeButtonVisibility: CloseButtonVisibilityMode.never,
      tabs: [
        Tab(
          text: const Text('Conversaciones'),
          icon: const Icon(FluentIcons.chat),
          body: const ConversacionesTab(),
        ),
        Tab(
          text: const Text('Email'),
          icon: const Icon(FluentIcons.mail),
          body: const EmailTab(),
        ),
        Tab(
          text: const Text('Historial'),
          icon: const Icon(FluentIcons.history),
          body: const HistorialTab(),
        ),
        Tab(
          text: const Text('Chat interno'),
          icon: const Icon(FluentIcons.people),
          body: const ChatTab(),
        ),
      ],
    );
  }
}
