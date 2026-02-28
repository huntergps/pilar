class PrintJobResult {
  final bool isOk;
  final String? errorMessage;

  const PrintJobResult._({required this.isOk, this.errorMessage});

  factory PrintJobResult.ok() => const PrintJobResult._(isOk: true);
  factory PrintJobResult.error(String message) =>
      PrintJobResult._(isOk: false, errorMessage: message);

  bool get isError => !isOk;

  @override
  String toString() =>
      isOk ? 'PrintJobResult(ok)' : 'PrintJobResult(error: $errorMessage)';
}
