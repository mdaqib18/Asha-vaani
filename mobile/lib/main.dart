import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/component_gallery_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/prefs_service.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final sharedPrefs = await SharedPreferences.getInstance();
  final prefs = PrefsService(sharedPrefs);
  final appState = AppState(prefs: prefs);
  try {
    await appState.syncService.start();
  } catch (_) {}
  runApp(AshaVaaniApp(appState: appState));
}

class AshaVaaniApp extends StatelessWidget {
  const AshaVaaniApp({super.key, required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final showLock = appState.selectedProfile == null || appState.isLocked;
        return MaterialApp(
          title: 'Asha Vaani',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme(highContrast: appState.highContrast),
          routes: {
            '/gallery': (_) => const ComponentGalleryScreen(),
          },
          home: showLock
              ? LoginScreen(appState: appState)
              : HomeScreen(appState: appState),
        );
      },
    );
  }
}
