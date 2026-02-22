import 'package:fluent_ui/fluent_ui.dart';
import 'package:supabase_auth_ui_fluent/src/utils/constants.dart';
import 'package:supabase_auth_ui_fluent/supabase_auth_ui_fluent.dart';

/// UI component to create a phone + password signin / signup form.
///
/// Uses Fluent UI widgets (TextFormBox, PasswordFormBox, FilledButton).
class SupaPhoneAuth extends StatefulWidget {
  /// Whether the user is signing in or signing up.
  final SupaAuthAction authAction;

  /// Method to be called when the auth action is successful.
  final void Function(AuthResponse response) onSuccess;

  /// Method to be called when the auth action threw an exception.
  final void Function(Object error)? onError;

  /// Localization for the form.
  final SupaPhoneAuthLocalization localization;

  const SupaPhoneAuth({
    super.key,
    required this.authAction,
    required this.onSuccess,
    this.onError,
    this.localization = const SupaPhoneAuthLocalization(),
  });

  @override
  State<SupaPhoneAuth> createState() => _SupaPhoneAuthState();
}

class _SupaPhoneAuthState extends State<SupaPhoneAuth> {
  final _formKey = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localization = widget.localization;
    final isSigningIn = widget.authAction == SupaAuthAction.signIn;
    return AutofillGroup(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormBox(
              autofillHints: const [AutofillHints.telephoneNumber],
              textInputAction: TextInputAction.next,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return localization.validPhoneNumberError;
                }
                return null;
              },
              placeholder: localization.enterPhoneNumber,
              prefix: const Icon(FluentIcons.phone),
              controller: _phone,
            ),
            spacer(16),
            PasswordFormBox(
              onFieldSubmitted: (_) => _submit(isSigningIn),
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
                onPressed: () => _submit(isSigningIn),
                child: Text(
                  isSigningIn ? localization.signIn : localization.signUp,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            spacer(10),
          ],
        ),
      ),
    );
  }

  void _submit(bool isSigningIn) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    try {
      if (isSigningIn) {
        final response = await supabase.auth.signInWithPassword(
          phone: _phone.text,
          password: _password.text,
        );
        widget.onSuccess(response);
      } else {
        late final AuthResponse response;
        final user = supabase.auth.currentUser;
        if (user?.isAnonymous == true) {
          await supabase.auth.updateUser(
            UserAttributes(
              phone: _phone.text,
              password: _password.text,
            ),
          );
          final newSession = supabase.auth.currentSession;
          response = AuthResponse(session: newSession);
        } else {
          response = await supabase.auth.signUp(
            phone: _phone.text,
            password: _password.text,
          );
        }
        if (!mounted) return;
        widget.onSuccess(response);
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
    }
    if (mounted) {
      setState(() {
        _phone.text = '';
        _password.text = '';
      });
    }
  }
}
