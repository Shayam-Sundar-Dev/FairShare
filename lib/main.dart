import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/services/deep_link_handler.dart';
import 'core/theme/app_theme.dart';
import 'ui/providers/auth_provider.dart';
import 'ui/providers/backup_provider.dart';
import 'ui/providers/category_provider.dart';
import 'ui/providers/event_provider.dart';
import 'ui/providers/expense_provider.dart';
import 'ui/providers/onboarding_provider.dart';
import 'ui/providers/people_provider.dart';
import 'ui/providers/theme_provider.dart';
import 'ui/providers/trip_sync_provider.dart';
import 'ui/screens/splash/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  DeepLinkHandler().init();
  runApp(const FairShareApp());
}

class FairShareApp extends StatelessWidget {
  const FairShareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => OnboardingProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => BackupProvider()),
        ChangeNotifierProvider(create: (_) => PeopleProvider()),
        ChangeNotifierProvider(create: (_) => EventProvider()),
        ChangeNotifierProvider(create: (_) => ExpenseProvider()),
        ChangeNotifierProvider(create: (_) => CategoryProvider()),
        ChangeNotifierProvider(create: (_) => TripSyncProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            title: 'FairShare',
            debugShowCheckedModeBanner: false,
            navigatorKey: DeepLinkHandler.navigatorKey,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            home: const SplashScreen(),
          );
        },
      ),
    );
  }
}
