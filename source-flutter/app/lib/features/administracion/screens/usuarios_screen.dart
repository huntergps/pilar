import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluent_ui_reactive/fluent_ui_reactive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/admin_providers.dart';

/// Gestión de usuarios de la empresa activa.
///
/// Muestra un [PilarStreamGrid] con todos los usuarios registrados,
/// obtenidos vía el RPC `admin_get_usuarios`. Incluye un botón para
/// invitar nuevos usuarios mediante el RPC `crear_invitacion`.
class UsuariosScreen extends ConsumerWidget {
  const UsuariosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usuariosAsync = ref.watch(adminUsuariosProvider);

    return ScaffoldPage(
      header: PageHeader(
        title: const Text('Usuarios'),
        commandBar: CommandBar(
          mainAxisAlignment: MainAxisAlignment.end,
          primaryItems: [
            CommandBarButton(
              icon: const Icon(FluentIcons.add_friend),
              label: const Text('Invitar usuario'),
              onPressed: () => _showInviteDialog(context, ref),
            ),
          ],
        ),
      ),
      content: PilarStreamGrid<Map<String, dynamic>>(
        value: usuariosAsync,
        columns: const [
          PilarColumn(field: 'email', label: 'Email'),
          PilarColumn(field: 'nombre', label: 'Nombre'),
          PilarColumn(field: 'rol_nombre', label: 'Rol'),
          PilarColumn(
            field: 'activo',
            label: 'Activo',
            format: ColumnFormat.boolean,
          ),
          PilarColumn(
            field: 'ultimo_acceso',
            label: 'Último acceso',
            format: ColumnFormat.datetime,
          ),
        ],
        rowToMap: (row) => row,
      ),
    );
  }

  void _showInviteDialog(BuildContext context, WidgetRef ref) {
    final emailController = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (ctx) => ContentDialog(
        title: const Text('Invitar usuario'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InfoLabel(
              label: 'Correo electrónico',
              child: TextBox(
                controller: emailController,
                placeholder: 'usuario@empresa.com',
                keyboardType: TextInputType.emailAddress,
              ),
            ),
          ],
        ),
        actions: [
          Button(
            child: const Text('Cancelar'),
            onPressed: () => Navigator.pop(ctx),
          ),
          FilledButton(
            child: const Text('Enviar invitación'),
            onPressed: () async {
              final email = emailController.text.trim();
              if (email.isEmpty) return;

              await Supabase.instance.client.rpc(
                'crear_invitacion',
                params: {'p_email': email, 'p_rol_id': null},
              );

              // Refresh the list so the new invitation appears.
              ref.invalidate(adminUsuariosProvider);

              if (ctx.mounted) Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
  }
}
