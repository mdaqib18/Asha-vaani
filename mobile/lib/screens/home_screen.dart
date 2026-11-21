import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/language_toggle.dart';
import '../widgets/server_settings_sheet.dart';
import 'beneficiary_list_screen.dart';
import 'saved_visits_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.appState});

  final AppState appState;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tabIndex = 0;
  final ValueNotifier<int> _savedRefreshSignal = ValueNotifier<int>(0);

  @override
  void dispose() {
    _savedRefreshSignal.dispose();
    super.dispose();
  }

  void _onVisitSaved() {
    _savedRefreshSignal.value += 1;
    setState(() => _tabIndex = 1);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.appState,
      builder: (context, _) {
        final strings = widget.appState.strings;
        final profile = widget.appState.selectedProfile;

        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(profile?.name ?? strings.appTitle),
                if (profile != null)
                  Text(
                    profile.id,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.inkSecondary,
                    ),
                  ),
              ],
            ),
            actions: [
              LanguageToggle(
                selected: widget.appState.language,
                onChanged: widget.appState.setLanguage,
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (choice) {
                  if (choice == 'switch') {
                    widget.appState.clearProfile();
                  } else if (choice == 'server') {
                    showServerSettingsSheet(context, widget.appState);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'server',
                    child: Text(strings.serverSettings),
                  ),
                  PopupMenuItem(
                    value: 'switch',
                    child: Text(strings.switchWorker),
                  ),
                ],
              ),
            ],
          ),
          body: IndexedStack(
            index: _tabIndex,
            children: [
              BeneficiaryListScreen(
                appState: widget.appState,
                onVisitSaved: _onVisitSaved,
              ),
              SavedVisitsScreen(
                appState: widget.appState,
                refreshSignal: _savedRefreshSignal,
              ),
            ],
          ),
          bottomNavigationBar: Container(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: NavigationBar(
              selectedIndex: _tabIndex,
              onDestinationSelected: (idx) {
                if (idx == 1) {
                  _savedRefreshSignal.value += 1;
                }
                setState(() => _tabIndex = idx);
              },
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.people_outline_rounded),
                  selectedIcon: const Icon(Icons.people_rounded),
                  label: strings.beneficiariesTab,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.check_circle_outline_rounded),
                  selectedIcon: const Icon(Icons.check_circle_rounded),
                  label: strings.savedVisitsTab,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
