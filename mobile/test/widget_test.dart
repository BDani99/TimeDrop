import 'package:flutter_test/flutter_test.dart';

import 'package:timedrop_mobile/core/theme/app_theme.dart';

void main() {
  test('AppTheme.light builds a valid ThemeData', () {
    final theme = AppTheme.light;
    expect(theme.useMaterial3, isTrue);
  });
}
