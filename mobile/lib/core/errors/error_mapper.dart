import 'app_exception.dart';

/// Maps any caught error to a user-facing message for `AppSnackbar`. Known
/// [AppException]s pass their message through; anything unexpected gets a
/// generic message so raw exception text never reaches the UI.
String mapErrorToMessage(Object error) {
  if (error is AppException) return error.message;
  return 'Something went wrong. Please try again.';
}
