import 'package:flutter/material.dart';
import 'package:personal_finance_tracker/theme/app_icons.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'auth_gate.dart';
import 'firebase_options.dart';
import 'helpers/notification_service.dart';
import 'helpers/theme_service.dart';
import 'screens/home_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/profile_screen.dart';
import 'theme/app_theme.dart';

final NotificationService notificationService = NotificationService();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Configure image cache limits to reduce memory usage
  const int maxCacheSize = 50 * 1024 * 1024; // 50MB maximum cache size in bytes
  imageCache.maximumSize = 100; // Maximum number of images to cache
  imageCache.maximumSizeBytes = maxCacheSize;

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase initialization error: $e');
    // If Firebase fails to initialize, we'll still run the app but auth won't work
    // This allows the app to start and show a proper error message
  }

  tz.initializeTimeZones();

  try {
    await notificationService.init();
  } catch (e) {
    debugPrint('Notification service initialization error: $e');
  }

  // Initialize ThemeService
  final themeService = ThemeService();
  await themeService.init();

  runApp(
    ChangeNotifierProvider<ThemeService>(
      create: (_) => themeService,
      child: const PersonalFinanceTracker(),
    ),
  );
}

class PersonalFinanceTracker extends StatelessWidget {
  const PersonalFinanceTracker({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, themeService, _) {
        final brightness = themeService.isDarkMode(context)
            ? Brightness.dark
            : Brightness.light;

        // Keep status bar icons readable in both light and dark themes.
        SystemChrome.setSystemUIOverlayStyle(
          SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: brightness == Brightness.dark
                ? Brightness.light
                : Brightness.dark,
            statusBarBrightness: brightness,
          ),
        );

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Ledgerlite',
          themeMode: themeService.themeMode,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          home: const AuthGate(),
        );
      },
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  static const List<Widget> _widgetOptions = <Widget>[
    HomeScreen(),
    ReportsScreen(),
    ProfileScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _widgetOptions.elementAt(_selectedIndex),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onItemTapped,
        backgroundColor: Theme.of(context).colorScheme.surface,
        height: 72,
        elevation: 0,
        indicatorColor: AppColors.primary.withValues(alpha: 0.14),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(AppIcons.account_balance_wallet_outlined),
            selectedIcon: Icon(AppIcons.account_balance_wallet),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(AppIcons.analytics_outlined),
            selectedIcon: Icon(AppIcons.analytics),
            label: 'Reports',
          ),
          NavigationDestination(
            icon: Icon(AppIcons.person_outline),
            selectedIcon: Icon(AppIcons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
