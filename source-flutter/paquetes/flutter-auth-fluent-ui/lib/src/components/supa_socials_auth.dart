import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_auth_ui_fluent/src/localizations/supa_socials_auth_localization.dart';
import 'package:supabase_auth_ui_fluent/src/utils/constants.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

extension on OAuthProvider {
  IconData get iconData => switch (this) {
        OAuthProvider.apple => FontAwesomeIcons.apple,
        OAuthProvider.azure => FontAwesomeIcons.microsoft,
        OAuthProvider.bitbucket => FontAwesomeIcons.bitbucket,
        OAuthProvider.discord => FontAwesomeIcons.discord,
        OAuthProvider.facebook => FontAwesomeIcons.facebook,
        OAuthProvider.figma => FontAwesomeIcons.figma,
        OAuthProvider.github => FontAwesomeIcons.github,
        OAuthProvider.gitlab => FontAwesomeIcons.gitlab,
        OAuthProvider.google => FontAwesomeIcons.google,
        OAuthProvider.linkedin => FontAwesomeIcons.linkedin,
        OAuthProvider.slack => FontAwesomeIcons.slack,
        OAuthProvider.spotify => FontAwesomeIcons.spotify,
        OAuthProvider.twitch => FontAwesomeIcons.twitch,
        OAuthProvider.twitter => FontAwesomeIcons.xTwitter,
        _ => FontAwesomeIcons.circleXmark,
      };

  Color get btnBgColor => switch (this) {
        OAuthProvider.apple => const Color(0xFF000000),
        OAuthProvider.azure => Colors.blue,
        OAuthProvider.bitbucket => Colors.blue,
        OAuthProvider.discord => const Color(0xFF7289DA),
        OAuthProvider.facebook => const Color(0xFF3b5998),
        OAuthProvider.figma => const Color.fromRGBO(241, 77, 27, 1),
        OAuthProvider.github => const Color(0xFF000000),
        OAuthProvider.gitlab => const Color(0xFFFF5722),
        OAuthProvider.google => Colors.white,
        OAuthProvider.kakao => const Color(0xFFFFE812),
        OAuthProvider.keycloak => const Color.fromRGBO(0, 138, 170, 1),
        OAuthProvider.linkedin => const Color.fromRGBO(0, 136, 209, 1),
        OAuthProvider.notion => const Color.fromRGBO(69, 75, 78, 1),
        OAuthProvider.slack => const Color.fromRGBO(74, 21, 75, 1),
        OAuthProvider.spotify => const Color(0xFF1DB954),
        OAuthProvider.twitch => const Color(0xFF9B59B6),
        OAuthProvider.twitter => const Color(0xFF000000),
        OAuthProvider.workos => const Color.fromRGBO(99, 99, 241, 1),
        _ => const Color(0xFF000000),
      };

  String get labelText =>
      'Continue with ${name[0].toUpperCase()}${name.substring(1)}';
}

enum SocialButtonVariant {
  /// Displays social login buttons horizontally with icons only.
  icon,

  /// Displays social login buttons vertically with icons and text labels.
  iconAndText,
}

class NativeGoogleAuthConfig {
  /// Web Client ID registered with Google Cloud.
  ///
  /// Required for native Google Sign In on Android.
  final String? webClientId;

  /// iOS Client ID registered with Google Cloud.
  ///
  /// Required for native Google Sign In on iOS.
  final String? iosClientId;

  const NativeGoogleAuthConfig({
    this.webClientId,
    this.iosClientId,
  });
}

/// UI Component to create a social login form.
///
/// Uses Fluent UI styled buttons for provider authentication.
class SupaSocialsAuth extends StatefulWidget {
  /// Defines native Google provider configuration.
  final NativeGoogleAuthConfig? nativeGoogleAuthConfig;

  /// Whether to use native Apple sign in on iOS and macOS.
  final bool enableNativeAppleAuth;

  /// List of social providers to show in the form.
  final List<OAuthProvider> socialProviders;

  /// Whether to color the social buttons in their respective brand colors.
  ///
  /// You can control appearance via button style overrides when set to false.
  final bool colored;

  /// Whether to show icon only or icon and text.
  final SocialButtonVariant socialButtonVariant;

  /// `redirectUrl` to be passed to the `.signIn()` or `signUp()` methods.
  ///
  /// Typically used to pass a DeepLink.
  final String? redirectUrl;

  /// Method to be called when the auth action is successful.
  final void Function(Session session) onSuccess;

  /// Method to be called when the auth action threw an exception.
  final void Function(Object error)? onError;

  /// Whether to show an info bar notification after a successful sign in.
  final bool showSuccessSnackBar;

  /// OpenID scope(s) for provider authorization request.
  final Map<OAuthProvider, String>? scopes;

  /// Parameters to include in provider authorization request.
  final Map<OAuthProvider, Map<String, String>>? queryParams;

  /// Localization for the form.
  final SupaSocialsAuthLocalization localization;

  /// Custom LaunchMode for the OAuth auth screen.
  final LaunchMode authScreenLaunchMode;

  const SupaSocialsAuth({
    super.key,
    this.nativeGoogleAuthConfig,
    this.enableNativeAppleAuth = true,
    required this.socialProviders,
    this.colored = true,
    this.redirectUrl,
    required this.onSuccess,
    this.onError,
    this.socialButtonVariant = SocialButtonVariant.iconAndText,
    this.showSuccessSnackBar = true,
    this.scopes,
    this.queryParams,
    this.localization = const SupaSocialsAuthLocalization(),
    this.authScreenLaunchMode = LaunchMode.platformDefault,
  });

  @override
  State<SupaSocialsAuth> createState() => _SupaSocialsAuthState();
}

class _SupaSocialsAuthState extends State<SupaSocialsAuth> {
  late final StreamSubscription<AuthState> _gotrueSubscription;
  late final SupaSocialsAuthLocalization localization;

  Future<AuthResponse> _nativeGoogleSignIn({
    required String? webClientId,
    required String? iosClientId,
  }) async {
    final GoogleSignIn googleSignIn = GoogleSignIn(
      clientId: iosClientId,
      serverClientId: webClientId,
    );

    final googleUser = await googleSignIn.signIn();
    final googleAuth = await googleUser!.authentication;
    final accessToken = googleAuth.accessToken;
    final idToken = googleAuth.idToken;

    if (accessToken == null) {
      throw const AuthException(
          'No Access Token found from Google sign in result.');
    }
    if (idToken == null) {
      throw const AuthException(
          'No ID Token found from Google sign in result.');
    }

    return supabase.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: accessToken,
    );
  }

  Future<AuthResponse> _nativeAppleSignIn() async {
    final rawNonce = supabase.auth.generateRawNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: hashedNonce,
    );

    final idToken = credential.identityToken;
    if (idToken == null) {
      throw const AuthException(
          'Could not find ID Token from generated Apple sign in credential.');
    }

    return supabase.auth.signInWithIdToken(
      provider: OAuthProvider.apple,
      idToken: idToken,
      nonce: rawNonce,
    );
  }

  @override
  void initState() {
    super.initState();
    localization = widget.localization;
    _gotrueSubscription =
        Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final session = data.session;
      if (session != null && mounted) {
        widget.onSuccess.call(session);
        if (widget.showSuccessSnackBar) {
          context.showSnackBar(localization.successSignInMessage);
        }
      }
    });
  }

  @override
  void dispose() {
    _gotrueSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final providers = widget.socialProviders;
    final googleAuthConfig = widget.nativeGoogleAuthConfig;
    final isNativeAppleAuthEnabled = widget.enableNativeAppleAuth;
    final coloredBg = widget.colored;

    if (providers.isEmpty) {
      return ErrorWidget(Exception('Social provider list cannot be empty'));
    }

    final authButtons = List.generate(
      providers.length,
      (index) {
        final socialProvider = providers[index];

        Color? foregroundColor = coloredBg ? Colors.white : null;
        Color? backgroundColor = coloredBg ? socialProvider.btnBgColor : null;
        Color? iconColor = coloredBg ? Colors.white : null;

        Widget iconWidget = SizedBox(
          height: 24,
          width: 24,
          child: Icon(
            socialProvider.iconData,
            color: iconColor,
            size: 20,
          ),
        );

        if (socialProvider == OAuthProvider.google && coloredBg) {
          iconWidget = Image.asset(
            'assets/logos/google_light.png',
            package: 'supabase_auth_ui_fluent',
            width: 24,
            height: 24,
          );
          foregroundColor = Colors.black;
          backgroundColor = Colors.white;
        }

        switch (socialProvider) {
          case OAuthProvider.notion:
            iconWidget = Image.asset(
              'assets/logos/notion.png',
              package: 'supabase_auth_ui_fluent',
              width: 24,
              height: 24,
              color: coloredBg ? Colors.white : null,
            );
            break;
          case OAuthProvider.kakao:
            iconWidget = Image.asset(
              'assets/logos/kakao.png',
              package: 'supabase_auth_ui_fluent',
              width: 24,
              height: 24,
            );
            break;
          case OAuthProvider.keycloak:
            iconWidget = Image.asset(
              'assets/logos/keycloak.png',
              package: 'supabase_auth_ui_fluent',
              width: 24,
              height: 24,
            );
            break;
          case OAuthProvider.workos:
            iconWidget = Image.asset(
              'assets/logos/workOS.png',
              package: 'supabase_auth_ui_fluent',
              width: 24,
              height: 24,
              color: coloredBg ? Colors.white : null,
            );
            break;
          default:
            break;
        }

        Future<void> onAuthButtonPressed() async {
          try {
            if (socialProvider == OAuthProvider.google) {
              final webClientId = googleAuthConfig?.webClientId;
              final iosClientId = googleAuthConfig?.iosClientId;
              final shouldPerformNativeGoogleSignIn =
                  (webClientId != null && !kIsWeb && Platform.isAndroid) ||
                      (iosClientId != null && !kIsWeb && Platform.isIOS);
              if (shouldPerformNativeGoogleSignIn) {
                await _nativeGoogleSignIn(
                  webClientId: webClientId,
                  iosClientId: iosClientId,
                );
                return;
              }
            }

            if (socialProvider == OAuthProvider.apple) {
              final shouldPerformNativeAppleSignIn =
                  (isNativeAppleAuthEnabled && !kIsWeb && Platform.isIOS) ||
                      (isNativeAppleAuthEnabled && !kIsWeb && Platform.isMacOS);
              if (shouldPerformNativeAppleSignIn) {
                await _nativeAppleSignIn();
                return;
              }
            }

            final user = supabase.auth.currentUser;
            if (user?.isAnonymous == true) {
              await supabase.auth.linkIdentity(
                socialProvider,
                redirectTo: widget.redirectUrl,
                scopes: widget.scopes?[socialProvider],
                queryParams: widget.queryParams?[socialProvider],
              );
              return;
            }

            await supabase.auth.signInWithOAuth(
              socialProvider,
              redirectTo: widget.redirectUrl,
              scopes: widget.scopes?[socialProvider],
              queryParams: widget.queryParams?[socialProvider],
              authScreenLaunchMode: widget.authScreenLaunchMode,
            );
          } on AuthException catch (error) {
            if (widget.onError == null && context.mounted) {
              context.showErrorSnackBar(error.message);
            } else {
              widget.onError?.call(error);
            }
          } catch (error) {
            if (widget.onError == null && context.mounted) {
              context.showErrorSnackBar(
                  '${localization.unexpectedError}: $error');
            } else {
              widget.onError?.call(error);
            }
          }
        }

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: widget.socialButtonVariant == SocialButtonVariant.icon
              ? _CircleSocialButton(
                  backgroundColor: backgroundColor,
                  onPressed: onAuthButtonPressed,
                  child: iconWidget,
                )
              : _buildIconAndTextButton(
                  backgroundColor: backgroundColor,
                  foregroundColor: foregroundColor,
                  iconWidget: iconWidget,
                  label: localization.oAuthButtonLabels[socialProvider] ??
                      socialProvider.labelText,
                  onPressed: onAuthButtonPressed,
                  colored: coloredBg,
                ),
        );
      },
    );

    return widget.socialButtonVariant == SocialButtonVariant.icon
        ? Wrap(
            alignment: WrapAlignment.spaceEvenly,
            children: authButtons,
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: authButtons,
          );
  }

  Widget _buildIconAndTextButton({
    required Color? backgroundColor,
    required Color? foregroundColor,
    required Widget iconWidget,
    required String label,
    required VoidCallback onPressed,
    required bool colored,
  }) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        iconWidget,
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: foregroundColor,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    if (colored && backgroundColor != null) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton(
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.all(backgroundColor),
            foregroundColor: WidgetStateProperty.all(foregroundColor),
          ),
          onPressed: onPressed,
          child: child,
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: Button(
        onPressed: onPressed,
        child: child,
      ),
    );
  }
}

/// A circular button used for icon-only social provider buttons.
class _CircleSocialButton extends StatefulWidget {
  final Color? backgroundColor;
  final VoidCallback onPressed;
  final Widget child;

  const _CircleSocialButton({
    required this.backgroundColor,
    required this.onPressed,
    required this.child,
  });

  @override
  State<_CircleSocialButton> createState() => _CircleSocialButtonState();
}

class _CircleSocialButtonState extends State<_CircleSocialButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bgColor =
        widget.backgroundColor ?? FluentTheme.of(context).cardColor;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _hovered
                ? Color.lerp(bgColor, Colors.white, 0.15) ?? bgColor
                : bgColor,
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: widget.child,
        ),
      ),
    );
  }
}
