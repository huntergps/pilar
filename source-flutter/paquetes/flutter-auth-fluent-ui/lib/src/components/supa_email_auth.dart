import 'package:email_validator/email_validator.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:supabase_auth_ui_fluent/src/localizations/supa_email_auth_localization.dart';
import 'package:supabase_auth_ui_fluent/src/utils/constants.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Position of the checkbox in a [BooleanMetaDataField].
enum CheckboxAffinity { leading, trailing }

/// {@template metadata_field}
/// Information about the metadata to pass to the signup form.
///
/// You can use this object to create additional text fields that will be
/// passed to the metadata of the user upon signup.
/// For example, in order to create additional `username` field:
/// ```dart
/// MetaDataField(label: 'Username', key: 'username')
/// ```
/// {@endtemplate}
class MetaDataField {
  /// Label (used as placeholder) of the text field for this metadata.
  final String label;

  /// Key to be used when sending the metadata to Supabase.
  final String key;

  /// Validator function for the metadata field.
  final String? Function(String?)? validator;

  /// Icon to show as the leading icon in the text field.
  final Widget? prefixIcon;

  /// {@macro metadata_field}
  MetaDataField({
    required this.label,
    required this.key,
    this.validator,
    this.prefixIcon,
  });
}

/// {@template boolean_metadata_field}
/// Represents a boolean metadata field for the signup form.
///
/// Creates a checkbox that will be passed to the metadata of the user upon
/// signup. Supports both simple text labels and rich text labels.
///
/// ```dart
/// BooleanMetaDataField(
///   label: 'I agree to marketing emails',
///   key: 'email_consent',
/// )
/// ```
///
/// With rich text:
/// ```dart
/// BooleanMetaDataField(
///   key: 'terms_and_conditions_consent',
///   required: true,
///   richLabelSpans: [
///     TextSpan(text: 'I have read and agree to the '),
///     TextSpan(
///       text: 'Terms and Conditions',
///       style: TextStyle(color: Colors.blue),
///       recognizer: TapGestureRecognizer()..onTap = () { ... },
///     ),
///   ],
/// )
/// ```
/// {@endtemplate}
class BooleanMetaDataField extends MetaDataField {
  /// Whether the checkbox is initially checked.
  final bool value;

  /// Rich text spans for the label. If provided, used instead of [label].
  final List<InlineSpan>? richLabelSpans;

  /// Position of the checkbox relative to its label.
  ///
  /// Defaults to [CheckboxAffinity.leading].
  final CheckboxAffinity checkboxPosition;

  /// Whether the field is required.
  ///
  /// If true, the user must check the checkbox in order for the form to submit.
  final bool isRequired;

  /// Semantic label for the checkbox.
  final String? checkboxSemanticLabel;

  /// {@macro boolean_metadata_field}
  BooleanMetaDataField({
    String? label,
    this.value = false,
    this.richLabelSpans,
    this.checkboxSemanticLabel,
    this.isRequired = false,
    this.checkboxPosition = CheckboxAffinity.leading,
    required super.key,
  })  : assert(label != null || richLabelSpans != null,
            'Either label or richLabelSpans must be provided'),
        super(label: label ?? '');

  Widget getLabelWidget(BuildContext context) {
    final defaultStyle = FluentTheme.of(context).typography.body;
    return richLabelSpans != null
        ? RichText(
            text: TextSpan(
              style: defaultStyle,
              children: richLabelSpans,
            ),
          )
        : Text(label, style: defaultStyle);
  }
}

// Used to allow storing both bool and TextEditingController in the same map.
typedef MetadataController = Object;

/// {@template supa_email_auth}
/// UI component to create email and password signup / signin form.
///
/// Uses Fluent UI widgets (TextFormBox, PasswordFormBox, FilledButton, etc.)
///
/// ```dart
/// SupaEmailAuth(
///   onSignInComplete: (response) {
///     // handle sign in complete here
///   },
///   onSignUpComplete: (response) {
///     // handle sign up complete here
///   },
/// ),
/// ```
/// {@endtemplate}
class SupaEmailAuth extends StatefulWidget {
  /// Whether the email field should automatically focus when the form is shown.
  final bool autofocus;

  /// The URL to redirect the user to after clicking the confirmation link.
  final String? redirectTo;

  /// The URL to redirect the user to after clicking the password recovery link.
  ///
  /// If unspecified, the [redirectTo] value will be used.
  final String? resetPasswordRedirectTo;

  /// Validator function for the password field.
  ///
  /// If null, a default validator checks if the password is at least 6 chars.
  final String? Function(String?)? passwordValidator;

  /// Callback for the user completing a sign in.
  final void Function(AuthResponse response) onSignInComplete;

  /// Callback for the user completing a sign up.
  final void Function(AuthResponse response) onSignUpComplete;

  /// Callback for sending the password reset email.
  final void Function()? onPasswordResetEmailSent;

  /// Callback for when the auth action threw an exception.
  ///
  /// If set to `null`, an error info bar will be shown.
  final void Function(Object error)? onError;

  /// Callback for toggling between sign in and sign up.
  final void Function(bool isSigningIn)? onToggleSignIn;

  /// Callback for toggling between sign-in/sign-up and password recovery.
  final void Function(bool isRecoveringPassword)? onToggleRecoverPassword;

  /// Set of additional fields to the signup form that will become
  /// part of the user_metadata.
  final List<MetaDataField>? metadataFields;

  /// Additional properties for user_metadata on signup.
  final Map<String, dynamic>? extraMetadata;

  /// Localization for the form.
  final SupaEmailAuthLocalization localization;

  /// Whether the form should display sign-in or sign-up initially.
  final bool isInitiallySigningIn;

  /// Leading icon for the email field.
  final Widget? prefixIconEmail;

  /// Leading icon for the password field.
  final Widget? prefixIconPassword;

  /// Whether the confirm password field should be displayed.
  final bool showConfirmPasswordField;

  /// {@macro supa_email_auth}
  const SupaEmailAuth({
    super.key,
    this.autofocus = true,
    this.redirectTo,
    this.resetPasswordRedirectTo,
    this.passwordValidator,
    required this.onSignInComplete,
    required this.onSignUpComplete,
    this.onPasswordResetEmailSent,
    this.onError,
    this.onToggleSignIn,
    this.onToggleRecoverPassword,
    this.metadataFields,
    this.extraMetadata,
    this.localization = const SupaEmailAuthLocalization(),
    this.isInitiallySigningIn = true,
    this.prefixIconEmail = const Icon(FluentIcons.mail),
    this.prefixIconPassword = const Icon(FluentIcons.password_field),
    this.showConfirmPasswordField = false,
  });

  @override
  State<SupaEmailAuth> createState() => _SupaEmailAuthState();
}

class _SupaEmailAuthState extends State<SupaEmailAuth> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  late bool _isSigningIn;
  late final Map<String, MetadataController> _metadataControllers;

  bool _isLoading = false;

  /// The user has pressed the forgot password button.
  bool _isRecoveringPassword = false;

  final FocusNode _emailFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _isSigningIn = widget.isInitiallySigningIn;
    _metadataControllers = Map.fromEntries((widget.metadataFields ?? []).map(
      (metadataField) => MapEntry(
        metadataField.key,
        metadataField is BooleanMetaDataField
            ? metadataField.value
            : TextEditingController(),
      ),
    ));
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    for (final controller in _metadataControllers.values) {
      if (controller is TextEditingController) {
        controller.dispose();
      }
    }
    _emailFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localization = widget.localization;
    return AutofillGroup(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormBox(
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              autovalidateMode: AutovalidateMode.onUserInteraction,
              autofocus: widget.autofocus,
              focusNode: _emailFocusNode,
              textInputAction: _isRecoveringPassword
                  ? TextInputAction.done
                  : TextInputAction.next,
              validator: (value) {
                if (value == null ||
                    value.isEmpty ||
                    !EmailValidator.validate(_emailController.text)) {
                  return localization.validEmailError;
                }
                return null;
              },
              placeholder: localization.enterEmail,
              prefix: widget.prefixIconEmail,
              controller: _emailController,
              onFieldSubmitted: (_) {
                if (_isRecoveringPassword) {
                  _passwordRecovery();
                }
              },
            ),
            if (!_isRecoveringPassword) ...[
              spacer(16),
              PasswordFormBox(
                autovalidateMode: AutovalidateMode.onUserInteraction,
                onFieldSubmitted: (_) {
                  if (widget.metadataFields == null || _isSigningIn) {
                    _signInSignUp();
                  }
                },
                validator: widget.passwordValidator ??
                    (value) {
                      if (value == null || value.isEmpty || value.length < 6) {
                        return localization.passwordLengthError;
                      }
                      return null;
                    },
                placeholder: localization.enterPassword,
                leadingIcon: widget.prefixIconPassword,
                controller: _passwordController,
              ),
              if (widget.showConfirmPasswordField && !_isSigningIn) ...[
                spacer(16),
                PasswordFormBox(
                  controller: _confirmPasswordController,
                  placeholder: localization.confirmPassword,
                  leadingIcon: widget.prefixIconPassword,
                  validator: (value) {
                    if (value != _passwordController.text) {
                      return localization.confirmPasswordError;
                    }
                    return null;
                  },
                ),
              ],
              spacer(16),
              if (widget.metadataFields != null && !_isSigningIn)
                ...widget.metadataFields!
                    .map((metadataField) => [
                          if (metadataField is BooleanMetaDataField)
                            FormField<bool>(
                              validator: metadataField.isRequired
                                  ? (bool? value) {
                                      if (value != true) {
                                        return localization.requiredFieldError;
                                      }
                                      return null;
                                    }
                                  : null,
                              builder: (FormFieldState<bool> field) {
                                final theme = FluentTheme.of(context);
                                final checkbox = Checkbox(
                                  checked: _metadataControllers[
                                      metadataField.key] as bool,
                                  onChanged: (bool? value) {
                                    setState(() {
                                      _metadataControllers[metadataField.key] =
                                          value ?? false;
                                    });
                                    field.didChange(value);
                                  },
                                  semanticLabel:
                                      metadataField.checkboxSemanticLabel,
                                  content:
                                      metadataField.getLabelWidget(context),
                                );
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 4.0),
                                      child: metadataField.checkboxPosition ==
                                              CheckboxAffinity.trailing
                                          ? Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Flexible(
                                                  child: metadataField
                                                      .getLabelWidget(context),
                                                ),
                                                Checkbox(
                                                  checked: _metadataControllers[
                                                          metadataField.key]
                                                      as bool,
                                                  onChanged: (bool? value) {
                                                    setState(() {
                                                      _metadataControllers[
                                                              metadataField
                                                                  .key] =
                                                          value ?? false;
                                                    });
                                                    field.didChange(value);
                                                  },
                                                  semanticLabel: metadataField
                                                      .checkboxSemanticLabel,
                                                ),
                                              ],
                                            )
                                          : checkbox,
                                    ),
                                    if (field.hasError)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                            left: 4, top: 4),
                                        child: Text(
                                          field.errorText!,
                                          style: theme.typography.caption
                                              ?.copyWith(
                                            color: Colors.red,
                                          ),
                                        ),
                                      ),
                                  ],
                                );
                              },
                            )
                          else
                            TextFormBox(
                              controller: _metadataControllers[metadataField.key]
                                  as TextEditingController,
                              textInputAction:
                                  widget.metadataFields!.last == metadataField
                                      ? TextInputAction.done
                                      : TextInputAction.next,
                              placeholder: metadataField.label,
                              prefix: metadataField.prefixIcon,
                              validator: metadataField.validator,
                              autovalidateMode:
                                  AutovalidateMode.onUserInteraction,
                              onFieldSubmitted: (_) {
                                if (metadataField !=
                                    widget.metadataFields!.last) {
                                  FocusScope.of(context).nextFocus();
                                } else {
                                  _signInSignUp();
                                }
                              },
                            ),
                          spacer(16),
                        ])
                    .expand((element) => element),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isLoading ? null : _signInSignUp,
                  child: _isLoading
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: ProgressRing(strokeWidth: 2),
                        )
                      : Text(_isSigningIn
                          ? localization.signIn
                          : localization.signUp),
                ),
              ),
              spacer(16),
              if (_isSigningIn) ...[
                HyperlinkButton(
                  onPressed: () {
                    setState(() {
                      _isRecoveringPassword = true;
                    });
                    widget.onToggleRecoverPassword?.call(_isRecoveringPassword);
                  },
                  child: Text(localization.forgotPassword),
                ),
              ],
              HyperlinkButton(
                key: const ValueKey('toggleSignInButton'),
                onPressed: () {
                  setState(() {
                    _isRecoveringPassword = false;
                    _isSigningIn = !_isSigningIn;
                  });
                  widget.onToggleSignIn?.call(_isSigningIn);
                  widget.onToggleRecoverPassword?.call(_isRecoveringPassword);
                },
                child: Text(_isSigningIn
                    ? localization.dontHaveAccount
                    : localization.haveAccount),
              ),
            ],
            if (_isSigningIn && _isRecoveringPassword) ...[
              spacer(16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isLoading ? null : _passwordRecovery,
                  child: _isLoading
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: ProgressRing(strokeWidth: 2),
                        )
                      : Text(localization.sendPasswordReset),
                ),
              ),
              spacer(16),
              HyperlinkButton(
                onPressed: () {
                  setState(() {
                    _isRecoveringPassword = false;
                  });
                },
                child: Text(localization.backToSignIn),
              ),
            ],
            spacer(16),
          ],
        ),
      ),
    );
  }

  void _signInSignUp() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _isLoading = true;
    });
    try {
      if (_isSigningIn) {
        final response = await supabase.auth.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
        widget.onSignInComplete.call(response);
      } else {
        final user = supabase.auth.currentUser;
        late final AuthResponse response;
        if (user?.isAnonymous == true) {
          await supabase.auth.updateUser(
            UserAttributes(
              email: _emailController.text.trim(),
              password: _passwordController.text.trim(),
              data: _resolveData(),
            ),
            emailRedirectTo: widget.redirectTo,
          );
          final newSession = supabase.auth.currentSession;
          response = AuthResponse(session: newSession);
        } else {
          response = await supabase.auth.signUp(
            email: _emailController.text.trim(),
            password: _passwordController.text.trim(),
            emailRedirectTo: widget.redirectTo,
            data: _resolveData(),
          );
        }
        widget.onSignUpComplete.call(response);
      }
    } on AuthException catch (error) {
      if (widget.onError == null && mounted) {
        context.showErrorSnackBar(error.message);
      } else {
        widget.onError?.call(error);
      }
      _emailFocusNode.requestFocus();
    } catch (error) {
      if (widget.onError == null && mounted) {
        context.showErrorSnackBar(
            '${widget.localization.unexpectedError}: $error');
      } else {
        widget.onError?.call(error);
      }
      _emailFocusNode.requestFocus();
    }
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _passwordRecovery() async {
    try {
      if (!_formKey.currentState!.validate()) {
        _emailFocusNode.requestFocus();
        return;
      }
      setState(() {
        _isLoading = true;
      });

      final email = _emailController.text.trim();
      await supabase.auth.resetPasswordForEmail(
        email,
        redirectTo: widget.resetPasswordRedirectTo ?? widget.redirectTo,
      );
      widget.onPasswordResetEmailSent?.call();
      if (!mounted) return;
      context.showSnackBar(widget.localization.passwordResetSent);
      setState(() {
        _isRecoveringPassword = false;
      });
    } on AuthException catch (error) {
      widget.onError?.call(error);
    } catch (error) {
      widget.onError?.call(error);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Map<String, dynamic> _resolveData() {
    var extra = widget.extraMetadata ?? <String, dynamic>{};
    extra.addAll(_resolveMetadataFieldsData());
    return extra;
  }

  Map<String, dynamic> _resolveMetadataFieldsData() {
    return Map.fromEntries(_metadataControllers.entries.map((entry) => MapEntry(
        entry.key,
        entry.value is TextEditingController
            ? (entry.value as TextEditingController).text
            : entry.value)));
  }
}
