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

/// The user backed out of the store sheet. Not a failure — callers swallow it
/// rather than showing an error for a deliberate cancellation.
class PurchaseCancelledException extends AppException {
  const PurchaseCancelledException() : super('Purchase cancelled.');
}

/// The server refused a drop for a quota reason — no drops left, or a free drop
/// aimed too far into the future. Distinct from [PaymentException] so the UI can
/// route straight to the paywall on a type check instead of matching on message
/// text.
class DropQuotaException extends AppException {
  const DropQuotaException(super.message, {super.cause, this.canBuyMore = true});

  /// False when buying drops would not help (the free-drop horizon cap).
  final bool canBuyMore;
}

class FeedbackException extends AppException {
  const FeedbackException(super.message, {super.cause});
}
