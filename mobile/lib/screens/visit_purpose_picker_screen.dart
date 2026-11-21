import 'package:flutter/material.dart';

import '../models/beneficiary.dart';
import '../models/visit_type.dart';
import '../services/api_client.dart';
import '../state/app_state.dart';
import '../ui/ui.dart';
import '../widgets/language_toggle.dart';
import 'record_visit_screen.dart';

/// Suggested and alternative visit purpose selector for a beneficiary (SPEC_V2 §3.6, §4).
class VisitPurposePickerScreen extends StatefulWidget {
  const VisitPurposePickerScreen({
    super.key,
    required this.appState,
    required this.beneficiary,
    this.beneficiaryType = 'newborn',
    this.dobIso,
    this.spokenHint,
  });

  final AppState appState;
  final Beneficiary beneficiary;
  final String beneficiaryType;
  final String? dobIso;
  final String? spokenHint;

  @override
  State<VisitPurposePickerScreen> createState() =>
      _VisitPurposePickerScreenState();
}

class _VisitPurposePickerScreenState extends State<VisitPurposePickerScreen> {
  final TextEditingController _hintController = TextEditingController();

  List<VisitTypeSummary> _catalog = const [];
  SuggestedPurposeResult? _suggestion;
  DetectedPurpose? _detected;
  bool _loading = true;
  bool _offlineFallback = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    if (widget.spokenHint != null && widget.spokenHint!.isNotEmpty) {
      _hintController.text = widget.spokenHint!;
    }
    _load();
  }

  @override
  void dispose() {
    _hintController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorText = null;
      _offlineFallback = false;
    });

    List<VisitTypeSummary> catalog = BuiltInVisitTypes.all;
    SuggestedPurposeResult? suggestion;
    var offline = false;
    String? error;

    try {
      final remoteTypes = await widget.appState.api.getVisitTypes();
      if (remoteTypes.isNotEmpty) {
        catalog = remoteTypes;
      }
      suggestion = await widget.appState.api.getSuggestedPurpose(
        widget.beneficiary.id,
        beneficiaryType: widget.beneficiaryType,
        dob: widget.dobIso,
        spokenHint: _hintController.text.trim().isEmpty
            ? null
            : _hintController.text.trim(),
      );
    } on ApiException catch (e) {
      if (e.code == 'NETWORK_ERROR' || e.code == 'TIMEOUT') {
        offline = true;
        catalog = BuiltInVisitTypes.all;
        suggestion = BuiltInVisitTypes.suggestForBeneficiary(
          beneficiaryId: widget.beneficiary.id,
          beneficiaryType: widget.beneficiaryType,
          dobIso: widget.dobIso,
          spokenHint: _hintController.text.trim().isEmpty
              ? null
              : _hintController.text.trim(),
          types: catalog,
        );
      } else {
        error = widget.appState.strings.friendlyError(e.code, e.message);
      }
    }

    if (!mounted) return;
    setState(() {
      _catalog = catalog;
      _suggestion = suggestion;
      _detected = suggestion?.detectedPurpose ??
          BuiltInVisitTypes.detectFromSpeech(
            _hintController.text,
            types: catalog,
          );
      _offlineFallback = offline;
      _errorText = error;
      _loading = false;
    });
  }

  void _onHintChanged(String value) {
    final detected = BuiltInVisitTypes.detectFromSpeech(
      value,
      types: _catalog.isNotEmpty ? _catalog : BuiltInVisitTypes.all,
    );
    setState(() {
      _detected = detected;
    });
  }

  IconData _iconForCode(String code) {
    switch (code) {
      case 'newborn_home_visit':
        return Icons.child_care_outlined;
      case 'anc_visit':
        return Icons.pregnant_woman_outlined;
      case 'general_illness':
        return Icons.medical_services_outlined;
      case 'ncd_screening':
        return Icons.monitor_heart_outlined;
      default:
        return Icons.assignment_outlined;
    }
  }

  Future<void> _openRecordFor(VisitTypeSummary purpose) async {
    final lang = widget.appState.language;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => RecordVisitScreen(
          appState: widget.appState,
          beneficiary: widget.beneficiary,
          visitTypeCode: purpose.code,
          visitTypeLabel: purpose.localizedName(lang),
        ),
      ),
    );
    if (!mounted) return;
    if (saved == true) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.appState,
      builder: (context, _) {
        final tokens = AppTokens.of(context);
        final strings = widget.appState.strings;
        final lang = widget.appState.language;

        final suggestedCode = _suggestion?.suggestedCode ?? 'newborn_home_visit';
        final suggestedPurpose =
            BuiltInVisitTypes.findByCode(suggestedCode, _catalog) ??
                BuiltInVisitTypes.all.first;
        final reasonText = _suggestion?.localizedReason(lang) ?? '';

        final detectedPurpose = _detected != null &&
                _detected!.code != suggestedPurpose.code
            ? BuiltInVisitTypes.findByCode(_detected!.code, _catalog)
            : null;

        final otherIds = _suggestion?.otherCodes ??
            _catalog
                .where((c) => c.code != suggestedPurpose.code)
                .map((c) => c.code)
                .toList();
        final otherPurposes = otherIds
            .map((id) => BuiltInVisitTypes.findByCode(id, _catalog))
            .whereType<VisitTypeSummary>()
            .toList();

        return AppScaffold(
          title: strings.selectVisitPurposeTitle,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: LanguageToggle(
                selected: lang,
                onChanged: widget.appState.setLanguage,
              ),
            ),
          ],
          body: _loading
              ? const Padding(
                  padding: EdgeInsets.only(top: AppSpacing.lg),
                  child: SkeletonLoader(itemCount: 3),
                )
              : _errorText != null
                  ? Center(
                      child: ErrorState(
                        title: strings.connectionFailed,
                        message: _errorText!,
                        retryLabel: strings.retry,
                        onRetry: _load,
                      ),
                    )
                  : _catalog.isEmpty
                      ? EmptyState(
                          icon: Icons.assignment_outlined,
                          title: strings.noMatchingPurposesTitle,
                          message: strings.offlineRegistryNotice,
                        )
                      : ListView(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.lg,
                          ),
                          children: [
                            Text(
                              '${widget.beneficiary.label} · ${widget.beneficiary.id}',
                              style: AppTypography.label(tokens.inkMuted),
                            ),
                            if (_offlineFallback) ...[
                              const SizedBox(height: AppSpacing.sm),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: RiskBadge(
                                  label: strings.offlineRegistryNotice,
                                  severity: RiskSeverity.info,
                                  icon: Icons.cloud_off_rounded,
                                ),
                              ),
                            ],
                            const SizedBox(height: AppSpacing.lg),
                            _SuggestedPurposeCard(
                              badgeLabel: strings.suggestedPurposeLabel,
                              title: suggestedPurpose.localizedName(lang),
                              reason: reasonText.isNotEmpty
                                  ? reasonText
                                  : suggestedPurpose.localizedDescription(lang),
                              actionLabel: strings.continueWithPurposeAction,
                              icon: _iconForCode(suggestedPurpose.code),
                              onContinue: () =>
                                  _openRecordFor(suggestedPurpose),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            Text(
                              strings.purposeVoiceHintLabel,
                              style: AppTypography.label(tokens.ink),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            TextField(
                              key: const ValueKey('purpose_voice_hint_input'),
                              controller: _hintController,
                              onChanged: _onHintChanged,
                              textInputAction: TextInputAction.done,
                              decoration: InputDecoration(
                                hintText: strings.purposeVoiceHintPlaceholder,
                                prefixIcon: Icon(
                                  Icons.record_voice_over_outlined,
                                  color: tokens.inkMuted,
                                ),
                                suffixIcon: _hintController.text.isNotEmpty
                                    ? IconButton(
                                        onPressed: () {
                                          _hintController.clear();
                                          _onHintChanged('');
                                        },
                                        tooltip: strings.clear,
                                        icon: const Icon(Icons.close_rounded),
                                      )
                                    : null,
                              ),
                            ),
                            if (detectedPurpose != null) ...[
                              const SizedBox(height: AppSpacing.md),
                              _DetectedPurposeConfirmationCard(
                                message: strings.detectedPurposeBanner(
                                  detectedPurpose.localizedName(lang),
                                ),
                                actionLabel: strings.switchPurposeAction(
                                  detectedPurpose.localizedName(lang),
                                ),
                                icon: _iconForCode(detectedPurpose.code),
                                onConfirm: () =>
                                    _openRecordFor(detectedPurpose),
                              ),
                            ],
                            if (otherPurposes.isNotEmpty) ...[
                              const SizedBox(height: AppSpacing.xl),
                              SectionHeader(title: strings.otherPurposesTitle),
                              const SizedBox(height: AppSpacing.sm),
                              for (final purpose in otherPurposes)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: AppSpacing.sm,
                                  ),
                                  child: _PurposeOptionTile(
                                    title: purpose.localizedName(lang),
                                    description:
                                        purpose.localizedDescription(lang),
                                    icon: _iconForCode(purpose.code),
                                    onTap: () => _openRecordFor(purpose),
                                  ),
                                ),
                            ],
                          ],
                        ),
        );
      },
    );
  }
}

class _SuggestedPurposeCard extends StatelessWidget {
  const _SuggestedPurposeCard({
    required this.badgeLabel,
    required this.title,
    required this.reason,
    required this.actionLabel,
    required this.icon,
    required this.onContinue,
  });

  final String badgeLabel;
  final String title;
  final String reason;
  final String actionLabel;
  final IconData icon;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: tokens.primary,
          width: AppSizes.borderWidth,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: RiskBadge(
              label: badgeLabel,
              severity: RiskSeverity.ok,
              icon: Icons.auto_awesome_outlined,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: AppSizes.icon, color: tokens.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTypography.heading(tokens.ink)),
                    if (reason.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        reason,
                        style: AppTypography.body(tokens.inkMuted),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: actionLabel,
            icon: Icons.mic_rounded,
            onPressed: onContinue,
          ),
        ],
      ),
    );
  }
}

class _DetectedPurposeConfirmationCard extends StatelessWidget {
  const _DetectedPurposeConfirmationCard({
    required this.message,
    required this.actionLabel,
    required this.icon,
    required this.onConfirm,
  });

  final String message;
  final String actionLabel;
  final IconData icon;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return Container(
      key: const ValueKey('detected_purpose_confirmation'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: tokens.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: tokens.primary,
          width: AppSizes.borderWidth,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: AppSizes.icon, color: tokens.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(message, style: AppTypography.body(tokens.ink)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SecondaryButton(
            label: actionLabel,
            icon: Icons.check_rounded,
            onPressed: onConfirm,
          ),
        ],
      ),
    );
  }
}

class _PurposeOptionTile extends StatelessWidget {
  const _PurposeOptionTile({
    required this.title,
    required this.description,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String description;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return Semantics(
      button: true,
      label: title,
      child: Material(
        color: tokens.surfaceRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(
            color: tokens.outline,
            width: AppSizes.borderWidth,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppSizes.minTouchTarget,
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(icon, size: AppSizes.icon, color: tokens.primary),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: AppTypography.body(tokens.ink)),
                        if (description.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            description,
                            style: AppTypography.labelRegular(tokens.inkMuted),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: AppSizes.icon,
                    color: tokens.inkMuted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
