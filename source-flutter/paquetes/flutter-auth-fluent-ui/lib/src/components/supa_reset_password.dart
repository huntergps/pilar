import 'package:fluent_ui/fluent_ui.dart';
import 'package:supabase_auth_ui_fluent/src/localizations/supa_reset_password_localization.dart';
import 'package:supabase_auth_ui_fluent/src/utils/constants.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// UI component to create a password reset form.
///
/// Uses Fluent UI widgets (PasswordFormBox, FilledButton).
class SupaResetPassword extends StatefulWidget {
  /// Access token of the user (optional).
  final String? accessToken;

  /// Method to be called when the auth action is successful.
  final void Function(UserResponse response) onSuccess;

  /// Method to be called when the auth action threw an exception.
  final void Function(Object error)? onError;

  /// Localization for the form.
  final SupaResetPasswordLocalization localization;

  const SupaResetPassword({
    super.key,
    this.accessToken,
    required this.onSuccess,
    this.onError,
    this.localization = const SupaResetPasswordLocalization(),
  });

  @override
  State<SupaResetPassword> createState() => _SupaResetPasswordState();
}

class _SupaResetPasswordState extends State<SupaResetPassword> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localization = widget.localization;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PasswordFormBox(
            validator: (value) {
              if (value == null || value.isEmpty || value.length < 6) {
                return localization.passwordLengthError;
              }
              return null;
            },
            placeholder: localization.enterPassword,
            leadingIcon: const Icon(FluentIcons.password_field),
            controller: _password,
          ),
          spacer(16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _isLoading ? null : _updatePassword,
              child: _isLoading
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: ProgressRing(strokeWidth: 2),
                    )
                  : Text(
                      localization.updatePassword,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
            ),
          ),
          spacer(10),
        ],
      ),
    );
  }

  void _updatePassword() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _isLoading = true);
    try {
      final response = await supabase.auth.updateUser(
        UserAttributes(password: _password.text),
      );
      widget.onSuccess.call(response);
      if (mounted) {
        context.showSnackBar(widget.localization.passwordResetSent);
      }
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
              '${widget.localization.unexpectedError}: $error');
        }
      } else {
        widget.onError?.call(error);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}
