import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../ui/ui.dart';

/// Hidden developer gallery showcasing all 19 V2 components in every state.
class ComponentGalleryScreen extends StatefulWidget {
  const ComponentGalleryScreen({super.key});

  @override
  State<ComponentGalleryScreen> createState() => _ComponentGalleryScreenState();
}

class _ComponentGalleryScreenState extends State<ComponentGalleryScreen> {
  bool _highContrast = false;
  int _navIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.lightTheme(highContrast: _highContrast),
      child: Builder(
        builder: (themedContext) {
          final tokens = AppTokens.of(themedContext);
          return AppScaffold(
            title: 'V2 UI Gallery',
            actions: [
              TextAction(
                label: _highContrast ? 'Standard' : 'High contrast',
                icon: Icons.contrast_rounded,
                onPressed: () =>
                    setState(() => _highContrast = !_highContrast),
              ),
            ],
            bottomNavigationBar: NavigationBar(
              selectedIndex: _navIndex,
              onDestinationSelected: (idx) => setState(() => _navIndex = idx),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.people_outline_rounded),
                  selectedIcon: Icon(Icons.people_rounded),
                  label: 'Beneficiaries',
                ),
                NavigationDestination(
                  icon: Icon(Icons.bar_chart_outlined),
                  selectedIcon: Icon(Icons.bar_chart_rounded),
                  label: 'Insights',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings_rounded),
                  label: 'Settings',
                ),
              ],
            ),
            body: ListView(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              children: [
                Text(
                  'Typography & Indic Scripts',
                  style: AppTypography.title(tokens.ink),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Namaste, Lakshmi · नमस्ते, लक्ष्मी · ನಮಸ್ಕಾರ, ಲಕ್ಷ್ಮಿ',
                  style: AppTypography.body(tokens.ink),
                ),
                const SizedBox(height: AppSpacing.xl),
                const SectionHeader(
                  title: 'Buttons',
                  subtitle: 'Icon + label, min 48dp touch target',
                ),
                const SizedBox(height: AppSpacing.md),
                PrimaryButton(
                  label: 'Record visit',
                  icon: Icons.mic_rounded,
                  onPressed: () {},
                ),
                const SizedBox(height: AppSpacing.sm),
                const PrimaryButton(
                  label: 'Saving record...',
                  icon: Icons.check_rounded,
                  loading: true,
                  onPressed: null,
                ),
                const SizedBox(height: AppSpacing.sm),
                const PrimaryButton(
                  label: 'Disabled action',
                  icon: Icons.block_rounded,
                  onPressed: null,
                ),
                const SizedBox(height: AppSpacing.sm),
                SecondaryButton(
                  label: 'Read back fields',
                  icon: Icons.volume_up_outlined,
                  onPressed: () {},
                ),
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextAction(
                    label: 'Open confirm sheet',
                    icon: Icons.open_in_new_rounded,
                    onPressed: () => ConfirmSheet.show(
                      themedContext,
                      title: 'Confirm visit record?',
                      message:
                          'Confirmed visits become read-only and create an audit entry.',
                      confirmLabel: 'Confirm',
                      cancelLabel: 'Cancel',
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextAction(
                    label: 'Delete local audio',
                    icon: Icons.delete_outline_rounded,
                    destructive: true,
                    onPressed: () => ConfirmSheet.show(
                      themedContext,
                      title: 'Delete audio clip?',
                      message:
                          'The structured record stays saved, while raw audio is removed.',
                      confirmLabel: 'Delete clip',
                      cancelLabel: 'Keep clip',
                      confirmIcon: Icons.delete_outline_rounded,
                      destructive: true,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                const SectionHeader(title: 'MicButton States (88dp)'),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.lg,
                  runSpacing: AppSpacing.md,
                  children: [
                    MicButton(
                      state: MicButtonState.ready,
                      label: 'Ready',
                      onTap: () {},
                    ),
                    MicButton(
                      state: MicButtonState.listening,
                      label: 'Listening',
                      onTap: () {},
                    ),
                    const MicButton(
                      state: MicButtonState.processing,
                      label: 'Processing',
                    ),
                    const MicButton(
                      state: MicButtonState.disabled,
                      label: 'Disabled',
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                const SectionHeader(title: 'StatTile & Badges'),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: StatTile(
                        value: '3',
                        label: 'Due today',
                        onTap: () {},
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: StatTile(
                        value: '7',
                        label: 'Done today',
                        tone: StatTileTone.ok,
                        onTap: () {},
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: StatTile(
                        value: '2',
                        label: 'High risk',
                        tone: StatTileTone.attention,
                        onTap: () {},
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                const Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    RiskBadge(label: 'High risk', severity: RiskSeverity.high),
                    RiskBadge(
                      label: 'Needs attention',
                      severity: RiskSeverity.medium,
                    ),
                    RiskBadge(label: 'Normal', severity: RiskSeverity.ok),
                    RiskBadge(label: 'Info', severity: RiskSeverity.info),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    const SyncChip(
                      state: SyncChipState.synced,
                      label: 'Synced 2 min ago',
                    ),
                    const SyncChip(
                      state: SyncChipState.syncing,
                      label: 'Syncing',
                    ),
                    SyncChip(
                      state: SyncChipState.pending,
                      label: '2 pending',
                      onTap: () {},
                    ),
                    const SyncChip(
                      state: SyncChipState.offline,
                      label: 'Offline',
                    ),
                    const SyncChip(
                      state: SyncChipState.error,
                      label: 'Retry sync',
                    ),
                    SecurityChip(
                      label: 'Encrypted on device',
                      onTap: () {},
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                SectionHeader(
                  title: 'BeneficiaryTile & VisitTile',
                  actionLabel: 'View all',
                  onAction: () {},
                ),
                const SizedBox(height: AppSpacing.md),
                BeneficiaryTile(
                  name: 'Baby of Sunita',
                  codeLabel: '#1042',
                  typeAndAge: 'Newborn · 7 days',
                  dueLabel: '2 days overdue',
                  dueOverdue: true,
                  riskLabel: 'Low weight',
                  riskSeverity: RiskSeverity.high,
                  onTap: () {},
                ),
                const SizedBox(height: AppSpacing.sm),
                BeneficiaryTile(
                  name: 'सुनीता देवी / ಲಕ್ಷ್ಮಿ',
                  codeLabel: '#1057',
                  typeAndAge: 'Pregnant · 28 weeks',
                  dueLabel: 'Due today',
                  riskLabel: 'On schedule',
                  riskSeverity: RiskSeverity.ok,
                  onTap: () {},
                ),
                const SizedBox(height: AppSpacing.sm),
                VisitTile(
                  purposeLabel: 'Newborn home visit',
                  subtitle: '2026-11-21 · 2.3 kg · 37.8 °C',
                  statusLabel: 'Confirmed',
                  statusSeverity: RiskSeverity.ok,
                  riskLabel: 'Suggest ANM consult',
                  riskSeverity: RiskSeverity.high,
                  onTap: () {},
                ),
                const SizedBox(height: AppSpacing.sm),
                VisitTile(
                  purposeLabel: 'ANC checkup',
                  subtitle: '2026-11-21 · Draft',
                  statusLabel: 'Pending sync',
                  statusSeverity: RiskSeverity.medium,
                  onTap: () {},
                ),
                const SizedBox(height: AppSpacing.xl),
                const SectionHeader(title: 'FieldCard States'),
                const SizedBox(height: AppSpacing.md),
                FieldCard(
                  label: 'Baby weight (kg)',
                  valueText: '2.5 kg',
                  tabularValue: true,
                  status: FieldCardStatus.verified,
                  statusLabel: 'Verified',
                  confidenceLabel: '0.94',
                  editLabel: 'Edit',
                  onEdit: () {},
                ),
                const SizedBox(height: AppSpacing.sm),
                FieldCard(
                  label: 'Temperature (°C)',
                  valueText: '37.9 °C',
                  tabularValue: true,
                  status: FieldCardStatus.needsReview,
                  statusLabel: 'Check value',
                  confidenceLabel: '0.68',
                  editLabel: 'Edit',
                  onEdit: () {},
                ),
                const SizedBox(height: AppSpacing.sm),
                FieldCard(
                  label: 'Umbilical cord status',
                  valueText: 'Not recorded',
                  status: FieldCardStatus.missing,
                  statusLabel: 'Missing',
                  editLabel: 'Edit',
                  onEdit: () {},
                ),
                const SizedBox(height: AppSpacing.sm),
                FieldCard(
                  label: 'Baby weight (kg)',
                  valueText: '25.0 kg',
                  tabularValue: true,
                  status: FieldCardStatus.outOfRange,
                  statusLabel: 'Out of range',
                  editLabel: 'Edit',
                  onEdit: () {},
                ),
                const SizedBox(height: AppSpacing.xl),
                const SectionHeader(title: 'LiveTranscript & FollowUpCard'),
                const SizedBox(height: AppSpacing.md),
                const LiveTranscript(
                  label: 'Live captions',
                  finalizedText: 'Beneficiary 1042 weight 2.5 kg',
                  partialText: 'temperature 36...',
                  audioLevel: 0.65,
                ),
                const SizedBox(height: AppSpacing.sm),
                const LiveTranscript(
                  label: 'Offline fallback',
                  finalizedText: '',
                  placeholder: 'Hold microphone button to speak.',
                  pausedNotice: 'Live captions paused, still recording locally.',
                ),
                const SizedBox(height: AppSpacing.sm),
                FollowUpCard(
                  stepLabel: 'Follow-up 1 of 2',
                  questionText:
                      'कृपया बच्चे का तापमान और स्तनपान की स्थिति बताएं। / ಮಗುವಿನ ತಾಪಮಾನ ತಿಳಿಸಿ.',
                  replayLabel: 'Replay',
                  onReplay: () {},
                  skipLabel: 'Type instead',
                  onSkip: () {},
                ),
                const SizedBox(height: AppSpacing.xl),
                const SectionHeader(title: 'Empty, Error & Skeleton States'),
                const SizedBox(height: AppSpacing.md),
                EmptyState(
                  icon: Icons.event_available_outlined,
                  title: 'No visits due today',
                  message: 'All scheduled visits for your area are completed.',
                  actionLabel: 'Add beneficiary',
                  onAction: () {},
                ),
                const SizedBox(height: AppSpacing.sm),
                ErrorState(
                  title: 'Could not reach server',
                  message:
                      'Audio stays queued on this phone and will sync later.',
                  retryLabel: 'Retry connection',
                  onRetry: () {},
                ),
                const SizedBox(height: AppSpacing.sm),
                const SkeletonLoader(itemCount: 2),
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
          );
        },
      ),
    );
  }
}
