class SupaResetPasswordLocalization {
  final String enterPassword;
  final String passwordLengthError;
  final String updatePassword;
  final String passwordResetSent;
  final String unexpectedError;

  const SupaResetPasswordLocalization({
    this.enterPassword = 'Enter your new password',
    this.passwordLengthError =
        'Please enter a password that is at least 6 characters long',
    this.updatePassword = 'Update Password',
    this.passwordResetSent = 'Your password has been updated!',
    this.unexpectedError = 'An unexpected error occurred',
  });
}
