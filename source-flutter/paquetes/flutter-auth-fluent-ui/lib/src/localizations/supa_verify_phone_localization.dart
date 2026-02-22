class SupaVerifyPhoneLocalization {
  final String enterOneTimeCode;
  final String enterCodeSent;
  final String verifyPhone;
  final String unexpectedErrorOccurred;

  const SupaVerifyPhoneLocalization({
    this.enterOneTimeCode = 'Enter the one-time code',
    this.enterCodeSent = 'Enter the code sent to your phone',
    this.verifyPhone = 'Verify Phone',
    this.unexpectedErrorOccurred = 'An unexpected error occurred',
  });
}
