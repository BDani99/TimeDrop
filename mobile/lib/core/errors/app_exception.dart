/// Base type for all app-thrown exceptions. Every async call site catches
/// this (or a subtype) and surfaces `message` via `AppSnackbar` — per the
/// cross-cutting rule that no async call may go unhandled.
sealed class AppException implements Exception {
  const AppException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

class AuthException extends AppException {
  const AuthException(super.message, {super.cause});
}

class CapsuleException extends AppException {
  const CapsuleException(super.message, {super.cause});
}

class CryptoException extends AppException {
  const CryptoException(super.message, {super.cause});
}

class StorageException extends AppException {
  const StorageException(super.message, {super.cause});
}

class LocationException extends AppException {
  const LocationException(super.message, {super.cause});
}

class PaymentException extends AppException {
  const PaymentException(super.message, {super.cause});
}
