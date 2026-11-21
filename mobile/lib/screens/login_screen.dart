import 'package:flutter/material.dart';

import '../models/beneficiary.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/language_toggle.dart';
import '../widgets/server_settings_sheet.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key, required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final strings = appState.strings;
        return Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        onPressed: () => showServerSettingsSheet(context, appState),
                        icon: const Icon(Icons.tune_rounded),
                        tooltip: strings.serverSettings,
                        color: AppColors.inkSecondary,
                      ),
                      LanguageToggle(
                        selected: appState.language,
                        onChanged: appState.setLanguage,
                      ),
                    ],
                  ),
                  const Spacer(flex: 1),
                  Center(
                    child: Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        color: AppColors.primaryTint,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Icon(
                        Icons.graphic_eq_rounded,
                        size: 36,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    strings.appTitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: AppColors.inkPrimary,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    strings.appSubtitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 36),
                  Text(
                    strings.selectWorker,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 12),
                  ...AshaProfile.defaults.map((profile) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _WorkerCard(
                        profile: profile,
                        onTap: () => appState.selectProfile(profile),
                      ),
                    );
                  }),
                  const Spacer(flex: 2),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WorkerCard extends StatelessWidget {
  const _WorkerCard({required this.profile, required this.onTap});

  final AshaProfile profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final initial = profile.name.isNotEmpty ? profile.name[0].toUpperCase() : 'A';
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.primaryTint,
                child: Text(
                  initial,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${profile.id} · ${profile.area}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: AppColors.inkSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
