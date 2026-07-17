/// Formats a [DateTime] for capsule-related screens (config, detail, home card).
///
/// Example outputs:
///   12h: "Jul 17, 2026 · 2:30 PM"
///   24h: "Jul 17, 2026 · 14:30"
String formatCapsuleDateTime(DateTime dt, {required bool use24h}) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final minute = dt.minute.toString().padLeft(2, '0');
  final datePart = '${months[dt.month - 1]} ${dt.day}, ${dt.year}';

  if (use24h) {
    final hour = dt.hour.toString().padLeft(2, '0');
    return '$datePart · $hour:$minute';
  } else {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final amPm = dt.hour < 12 ? 'AM' : 'PM';
    return '$datePart · $hour:$minute $amPm';
  }
}
