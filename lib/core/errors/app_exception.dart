class AppException implements Exception {
  final String message;
  final Object? cause;
  AppException(this.message, {this.cause});
  @override
  String toString() => 'AppException: $message';
}
