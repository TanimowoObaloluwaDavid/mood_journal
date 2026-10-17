/// A failure that is safe to show to a user.
class AppException implements Exception {
  const AppException(this.message, {this.cause});

  factory AppException.from(Object error) {
    if (error is AppException) return error;
    return AppException(
      'Something went wrong. Your entries are still safe on this device.',
      cause: error,
    );
  }

  final String message;
  final Object? cause;

  @override
  String toString() =>
      'AppException($message${cause != null ? ', cause: $cause' : ''})';
}
