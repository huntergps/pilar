import 'package:fluent_ui/fluent_ui.dart';
import 'package:supabase_auth_ui_fluent/src/localizations/supa_verify_phone_localization.dart';
import 'package:supabase_auth_ui_fluent/src/utils/constants.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// UI component for verifying a phone number via OTP.
///
/// Uses Fluent UI widgets (TextFormBox, FilledButton).
class SupaVerifyPhone extends StatefulWidget {
  /// Method to be called when the auth action is successful.
  final void Function(AuthResponse response) onSuccess;

  /// Method to be called when the auth action threw an exception.
  final void Function(Object error)? onError;

  /// Localization for the form.
  final SupaVerifyPhoneLocalization localization;

  const SupaVerifyPhone({
    super.key,
    required this.onSuccess,
    this.onError,
    this.localization = const SupaVerifyPhoneLocalization(),
  });

  @override
  State<SupaVerifyPhone> createState() => _SupaVerifyPhoneState();
}

class _SupaVerifyPhoneState extends State<SupaVerifyPhone> {
  Map? data;
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localization = widget.localization;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args != null) data = args as Map;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormBox(
            validator: (value) {
              if (value == null || value.isEmpty) {
                return localization.enterOneTimeCode;
              }
              return null;
            },
            placeholder: localization.enterCodeSent,
            prefix: const Icon(FluentIcons.number_field),
            controller: _code,
          ),
          spacer(16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _isLoading ? null : _verifyPhone,
              child: _isLoading
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: ProgressRing(strokeWidth: 2),
                    )
                  : Text(
                      localization.verifyPhone,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
            ),
          ),
          spacer(10),
        ],
      ),
    );
  }

  void _verifyPhone() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _isLoading = true);
    try {
      final response = await supabase.auth.verifyOTP(
        phone: data!["phone"] as String,
        token: _code.text,
        type: OtpType.sms,
      );
      widget.onSuccess(response);
    } on AuthException catch (error) {
      if (widget.onError == null) {
        if (mounted) context.showErrorSnackBar(error.message);
      } else {
        widget.onError?.call(error);
      }
    } catch (error) {
      if (widget.onError == null) {
        if (mounted) {
          context.showErrorSnackBar(
              '${widget.localization.unexpectedErrorOccurred}: $error');
        }
      } else {
        widget.onError?.call(error);
      }
    }
    if (mounted) {
      setState(() {
        _isLoading = false;
        _code.text = '';
      });
    }
  }
}
