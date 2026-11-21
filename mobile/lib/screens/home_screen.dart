import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../ui/ui.dart';
import '../widgets/language_toggle.dart';
import 'beneficiary_list_screen.dart';
import 'home_dashboard_screen.dart';
import 'insights_screen.dart';
import 'saved_visits_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.appState});

  final AppState appState;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tabIndex = 0;
  final ValueNotifier<int> _refreshSignal = ValueNotifier<int>(0);

  @override
  void dispose() {
    _refreshSignal.dispose();
    super.dispose();
  }

  void _selectTab(int idx) {
    setState(() => _tabIndex = idx);
    _refreshSignal.value += 1;
  }

  void _onVisitSaved() {
    _refreshSignal.value += 1;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AppScaffold(
          title: widget.appState.strings.savedVisitsTab,
          body: SavedVisitsScreen(
            appState: widget.appState,
            refreshSignal: _refreshSignal,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.appState,
      builder: (context, _) {
        final strings = widget.appState.strings;
        final String? appBarTitle = switch (_tabIndex) {
          1 => strings.beneficiariesTab,
          2 => strings.insightsTitle,
          3 => strings.settingsTitle,
          _ => null,
        };

        return AppScaffold(
          title: appBarTitle,
          actions: appBarTitle != null
              ? [
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.md),
                    child: LanguageToggle(
                      selected: widget.appState.language,
                      onChanged: widget.appState.setLanguage,
                    ),
                  ),
                ]
              : null,
          padding: _tabIndex == 1
              ? EdgeInsets.zero
              : const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenHorizontal,
                ),
          body: IndexedStack(
            index: _tabIndex,
            children: [
              HomeDashboardScreen(
                appState: widget.appState,
                refreshSignal: _refreshSignal,
                onSelectTab: _selectTab,
                onVisitSaved: _onVisitSaved,
              ),
              BeneficiaryListScreen(
                appState: widget.appState,
                onVisitSaved: _onVisitSaved,
              ),
              InsightsScreen(
                appState: widget.appState,
                refreshSignal: _refreshSignal,
              ),
              SettingsScreen(
                appState: widget.appState,
                refreshSignal: _refreshSignal,
              ),
            ],
          ),
          bottomNavigationBar: ListenableBuilder(
            listenable: widget.appState.syncService,
            builder: (context, _) {
              final pendingCount = widget.appState.syncService.pendingCount;
              return NavigationBar(
                selectedIndex: _tabIndex,
                onDestinationSelected: _selectTab,
                destinations: [
                  NavigationDestination(
                    icon: const Icon(Icons.home_outlined),
                    selectedIcon: const Icon(Icons.home_rounded),
                    label: strings.homeTab,
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.people_outline_rounded),
                    selectedIcon: const Icon(Icons.people_rounded),
                    label: strings.beneficiariesTab,
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.bar_chart_outlined),
                    selectedIcon: const Icon(Icons.bar_chart_rounded),
                    label: strings.insightsTab,
                  ),
                  NavigationDestination(
                    icon: Badge.count(
                      count: pendingCount,
                      isLabelVisible: pendingCount > 0,
                      child: const Icon(Icons.settings_outlined),
                    ),
                    selectedIcon: Badge.count(
                      count: pendingCount,
                      isLabelVisible: pendingCount > 0,
                      child: const Icon(Icons.settings_rounded),
                    ),
                    label: strings.settingsTab,
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
