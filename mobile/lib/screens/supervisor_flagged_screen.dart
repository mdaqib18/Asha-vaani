import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../models/newborn_visit.dart';
import '../services/api_client.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/language_toggle.dart';

class SupervisorFlaggedScreen extends StatefulWidget {
  const SupervisorFlaggedScreen({super.key, required this.appState});

  final AppState appState;

  @override
  State<SupervisorFlaggedScreen> createState() =>
      _SupervisorFlaggedScreenState();
}

class _SupervisorFlaggedScreenState extends State<SupervisorFlaggedScreen> {
  List<VisitSummary> _visits = const [];
  bool _loading = true;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _visits.isEmpty;
      _errorText = null;
    });

    try {
      final items = await widget.appState.api.getFlaggedVisits();
      if (!mounted) return;
      setState(() {
        _visits = items;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = widget.appState.strings.friendlyError(e.code, e.message);
        _loading = false;
      });
    }
  }

  void _openDetail(VisitSummary summary) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _VisitDetailSheet(
        appState: widget.appState,
        summary: summary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.appState,
      builder: (context, _) {
        final strings = widget.appState.strings;
        return Scaffold(
          appBar: AppBar(
            title: Text(strings.supervisorTitle),
            actions: [
              LanguageToggle(
                selected: widget.appState.language,
                onChanged: widget.appState.setLanguage,
              ),
              IconButton(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                tooltip: strings.retry,
              ),
            ],
          ),
          body: _buildBody(strings),
        );
      },
    );
  }

  Widget _buildBody(AppStrings strings) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorText != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_rounded,
                size: 42,
                color: AppColors.inkSecondary,
              ),
              const SizedBox(height: 12),
              Text(_errorText!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(strings.retry),
              ),
            ],
          ),
        ),
      );
    }

    if (_visits.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.65,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.verified_user_outlined,
                        size: 46,
                        color: AppColors.primary,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        strings.supervisorEmpty,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        strings.supervisorSubtitle,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.warningBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.warningBorder),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.health_and_safety_outlined,
                  color: AppColors.warningText,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        strings.flaggedCountLabel(_visits.length),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.inkPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        strings.referralBannerTitle,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.warningText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ..._visits.map((visit) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: InkWell(
                  onTap: () => _openDetail(visit),
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${strings.fieldLabel('beneficiary_id')}: ${visit.beneficiaryId ?? strings.notRecorded}',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            if (visit.ashaId != null &&
                                visit.ashaId!.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryTint,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${strings.workerIdLabel}: ${visit.ashaId}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primaryDark,
                                  ),
                                ),
                              ),
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: AppColors.inkSecondary,
                            ),
                          ],
                        ),
                        if (visit.visitDate != null &&
                            visit.visitDate!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            visit.visitDate!,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        if (visit.riskFlags.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: visit.riskFlags
                                .map(
                                  (flag) => Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.riskBg,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      strings.riskFlagLabel(flag),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.riskText,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _VisitDetailSheet extends StatefulWidget {
  const _VisitDetailSheet({required this.appState, required this.summary});

  final AppState appState;
  final VisitSummary summary;

  @override
  State<_VisitDetailSheet> createState() => _VisitDetailSheetState();
}

class _VisitDetailSheetState extends State<_VisitDetailSheet> {
  VisitDetail? _detail;
  bool _loading = true;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _fetchDetail();
  }

  Future<void> _fetchDetail() async {
    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      final detail =
          await widget.appState.api.getVisitDetail(widget.summary.sessionId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = widget.appState.strings.friendlyError(e.code, e.message);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.appState.strings;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      strings.visitDetailsTitle,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _buildSheetBody(strings, scrollController),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSheetBody(
    AppStrings strings,
    ScrollController scrollController,
  ) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorText != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_errorText!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _fetchDetail,
              child: Text(strings.retry),
            ),
          ],
        ),
      );
    }

    final detail = _detail!;
    final rec = detail.record;
    final limb = rec.limbAbnormality?.value;
    final limbDisplay = limb == null
        ? strings.notRecorded
        : (!limb.present
            ? strings.no
            : '${strings.yes} (${strings.limbLocationLabel(limb.location ?? 'unspecified')})');
    final dangerVal = rec.dangerSigns?.value;
    final dangerDisplay = (dangerVal == null || dangerVal.isEmpty)
        ? strings.notRecorded
        : dangerVal.map(strings.dangerSignLabel).join(', ');

    final rows = <(String, String)>[
      (
        strings.fieldLabel('beneficiary_id'),
        rec.beneficiaryId?.value ?? strings.notRecorded,
      ),
      if (detail.ashaId != null && detail.ashaId!.isNotEmpty)
        (strings.workerIdLabel, detail.ashaId!),
      (
        strings.fieldLabel('baby_weight_kg'),
        rec.babyWeightKg?.value != null
            ? '${rec.babyWeightKg!.value} kg'
            : strings.notRecorded,
      ),
      (
        strings.fieldLabel('temperature_c'),
        rec.temperatureC?.value != null
            ? '${rec.temperatureC!.value} °C'
            : strings.notRecorded,
      ),
      (
        strings.fieldLabel('breastfeeding'),
        rec.breastfeeding?.value != null
            ? strings.breastfeedingLabel(rec.breastfeeding!.value!)
            : strings.notRecorded,
      ),
      (
        strings.fieldLabel('cord_status'),
        rec.cordStatus?.value != null
            ? strings.cordStatusLabel(rec.cordStatus!.value!)
            : strings.notRecorded,
      ),
      (
        strings.fieldLabel('jaundice'),
        rec.jaundice?.value != null
            ? (rec.jaundice!.value! ? strings.yes : strings.no)
            : strings.notRecorded,
      ),
      (
        strings.fieldLabel('breathing_rate_per_min'),
        rec.breathingRatePerMin?.value != null
            ? '${rec.breathingRatePerMin!.value} /min'
            : strings.notRecorded,
      ),
      (strings.fieldLabel('limb_abnormality'), limbDisplay),
      (strings.fieldLabel('danger_signs'), dangerDisplay),
      if (rec.motherNotes?.value != null &&
          rec.motherNotes!.value!.trim().isNotEmpty)
        (strings.fieldLabel('mother_notes'), rec.motherNotes!.value!.trim()),
      if (rec.notes?.value != null && rec.notes!.value!.trim().isNotEmpty)
        (strings.fieldLabel('notes'), rec.notes!.value!.trim()),
    ];

    return ListView(
      controller: scrollController,
      children: [
        if (rec.referralSuggested) ...[
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.warningBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.warningBorder),
            ),
            child: Text(
              strings.referralBannerTitle,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.warningText,
              ),
            ),
          ),
        ],
        ...rows.map(
          (entry) => Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    entry.$1,
                    style: const TextStyle(
                      color: AppColors.inkSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: Text(
                    entry.$2,
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                      color: AppColors.inkPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (detail.lastTranscript.trim().isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            strings.transcriptLabel,
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceSubtle,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(detail.lastTranscript.trim()),
          ),
        ],
      ],
    );
  }
}
