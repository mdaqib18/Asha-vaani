import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    return MaterialApp(
      title: 'Asha Vaani',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(),
      home: ListenableBuilder(
        listenable: appState,
        builder: (context, _) {
          if (appState.selectedProfile == null) {
            return LoginScreen(appState: appState);
          }
          return HomeScreen(appState: appState);
        },
      ),
    );
  }
}
