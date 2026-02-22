import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluent_ui_reactive/fluent_ui_reactive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/empresa_provider.dart';

/// Pantalla de configuración de la empresa activa.
///
/// Permite editar los datos principales (nombre, RUC, nombre comercial,
/// dirección, teléfono, email, ambiente SRI) usando [PilarForm] y
/// [PilarTextField] del paquete `fluent_ui_reactive`.
///
/// Los cambios se guardan vía el RPC `admin_update_empresa`.
class EmpresaScreen extends ConsumerStatefulWidget {
  const EmpresaScreen({super.key});

  @override
  ConsumerState<EmpresaScreen> createState() => _EmpresaScreenState();
}

class _EmpresaScreenState extends ConsumerState<EmpresaScreen> {
  // Saved field values accumulated from PilarTextField.onSaved callbacks.
  String? _nombre;
  String? _ruc;
  String? _nombreComercial;
  String? _direccion;
  String? _telefono;
  String? _email;

  Future<void> _handleSave() async {
    final empresaId = ref.read(empresaActivaIdProvider);
    if (empresaId == null) return;

    await Supabase.instance.client.rpc(
      'admin_update_empresa',
      params: {
        'p_empresa_id': empresaId,
        if (_nombre != null) 'p_nombre': _nombre,
        if (_ruc != null) 'p_ruc': _ruc,
        if (_nombreComercial != null)
          'p_nombre_comercial': _nombreComercial,
        if (_direccion != null) 'p_direccion': _direccion,
        if (_telefono != null) 'p_telefono': _telefono,
        if (_email != null) 'p_email': _email,
      },
    );

    // Refresh empresa config so PilarShell header updates.
    ref.invalidate(empresaConfigProvider);
  }

  @override
  Widget build(BuildContext context) {
    final empresaAsync = ref.watch(empresaConfigProvider);

    return ScaffoldPage(
      header: const PageHeader(title: Text('Empresa')),
      content: PilarAsyncBuilder<EmpresaConfig?>(
        value: empresaAsync,
        builder: (context, empresa) {
          if (empresa == null) {
            return const Center(child: Text('Sin empresa activa'));
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: PilarForm(
                onSave: _handleSave,
                padding: EdgeInsets.zero,
                children: [
                  PilarTextField(
                    name: 'nombre',
                    label: 'Nombre de empresa',
                    initialValue: empresa.nombre,
                    required: true,
                    onSaved: (v) => _nombre = v,
                  ),
                  const SizedBox(height: 12),
                  PilarTextField(
                    name: 'ruc',
                    label: 'RUC / Cédula',
                    initialValue: empresa.ruc,
                    onSaved: (v) => _ruc = v,
                  ),
                  const SizedBox(height: 12),
                  PilarTextField(
                    name: 'nombre_comercial',
                    label: 'Nombre comercial',
                    onSaved: (v) => _nombreComercial = v,
                  ),
                  const SizedBox(height: 12),
                  PilarTextField(
                    name: 'direccion',
                    label: 'Dirección',
                    maxLines: 2,
                    onSaved: (v) => _direccion = v,
                  ),
                  const SizedBox(height: 12),
                  PilarTextField(
                    name: 'telefono',
                    label: 'Teléfono',
                    keyboardType: TextInputType.phone,
                    onSaved: (v) => _telefono = v,
                  ),
                  const SizedBox(height: 12),
                  PilarTextField(
                    name: 'email',
                    label: 'Email',
                    keyboardType: TextInputType.emailAddress,
                    onSaved: (v) => _email = v,
                  ),
                  const SizedBox(height: 12),
                  PilarTextField(
                    name: 'ambiente_sri',
                    label: 'Ambiente SRI',
                    initialValue: empresa.ambienteSri,
                    readOnly: true,
                    infoMessage:
                        'Cambia el ambiente SRI desde Configuración > SRI.',
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
