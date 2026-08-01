import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/capsule_provider.dart';
import 'providers/drop_balance_provider.dart';
import 'providers/vault_provider.dart';
import 'providers/payment_provider.dart';
import 'providers/settings_provider.dart';
import 'services/supabase_service.dart';
import 'ui/router/app_router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseService.initialize();
  runApp(const TimeDropApp());
}

class TimeDropApp extends StatelessWidget {
  const TimeDropApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => CapsuleProvider()),
        ChangeNotifierProvider(create: (_) => VaultProvider()),
        ChangeNotifierProvider(create: (_) => PaymentProvider()..initialize()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => DropBalanceProvider()),
      ],
      child: MaterialApp(
        title: 'TimeDrop',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const MainRouter(),
      ),
    );
  }
}
