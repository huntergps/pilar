import 'package:supabase_flutter/supabase_flutter.dart';

class SupaSocialsAuthLocalization {
  final String successSignInMessage;
  final String unexpectedError;

  /// Overrides the name of the OAuth provider shown on the sign-in button.
  ///
  /// Defaults to `Continue with [ProviderName]`
  ///
  /// ```dart
  /// SupaSocialsAuth(
  ///   socialProviders: const [OAuthProvider.azure],
  ///   localization: const SupaSocialsAuthLocalization(
  ///     oAuthButtonLabels: {
  ///       OAuthProvider.azure: 'Microsoft (Azure)'
  ///     },
  ///   ),
  ///   onSuccess: (session) {
  ///     // Handle success
  ///   },
  /// ),
  /// ```
  final Map<OAuthProvider, String> oAuthButtonLabels;

  const SupaSocialsAuthLocalization({
    this.successSignInMessage = 'Successfully signed in!',
    this.unexpectedError = 'An unexpected error occurred',
    this.oAuthButtonLabels = const {},
  });
}
