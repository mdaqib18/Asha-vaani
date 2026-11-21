import 'package:flutter/material.dart';

import '../models/beneficiary.dart';
import '../models/newborn_visit.dart';
import '../services/api_client.dart';
import '../state/app_state.dart';
import '../ui/ui.dart';
import '../widgets/language_toggle.dart';
import 'saved_visits_screen.dart';
import 'supervisor_flagged_screen.dart';
import 'visit_purpose_picker_screen.dart';

class HomeDashboardScreen extends StatefulWidget {
  const HomeDashboardScreen({
    super.key,
    required this.appState,
    required this.refreshSignal,
    required this.onSelectTab,
    required this.onVisitSaved,
  });

  final AppState appState;
  final ValueNotifier<int> refreshSignal;
  final ValueChanged<int> onSelectTab;
  final VoidCallback onVisitSaved;

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen> {
  List<Beneficiary> _beneficiaries = const [];
  List<VisitSummary> _visits = const [];
  int _pendingSyncCount = 0;
  bool _loading = true;
  bool _offline = false;
  String? _errorText;
  String? _loadedForAsha;
  String? _loadedForUrl;

  @override
  void initState() {
    super.initState();
    widget.appState.addListener(_onStateChanged);
    widget.appState.syncService.addListener(_load);
    widget.refreshSignal.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.appState.removeListener(_onStateChanged);
    widget.appState.syncService.removeListener(_load);
    widget.refreshSignal.removeListener(_load);
    super.dispose();
  }

  void _onStateChanged() {
    final currentAsha = widget.appState.selectedProfile?.id;
    final currentUrl = widget.appState.baseUrl;
    if (currentAsha != _loadedForAsha || currentUrl != _loadedForUrl) {
      _load();
    }
  }

  Future<void> _load() async {
    final ashaId = widget.appState.selectedProfile?.id;
    if (ashaId == null) return;

    setState(() {
      _loading = _beneficiaries.isEmpty && _visits.isEmpty;
      _errorText = null;
      _loadedForAsha = ashaId;
      _loadedForUrl = widget.appState.baseUrl;
    });

    List<Beneficiary> beneficiaries = const [];
    List<VisitSummary> visits = const [];
    var offline = false;
    String? error;

    try {
      beneficiaries = await widget.appState.api.getBeneficiaries(ashaId);
      await widget.appState.localDb.cacheBeneficiaries(ashaId, beneficiaries);
    } on ApiException catch (e) {
      if (e.code == 'NETWORK_ERROR' || e.code == 'TIMEOUT') {
        offline = true;
        beneficiaries =
            await widget.appState.localDb.getCachedBeneficiaries(ashaId);
      } else {
        error = widget.appState.strings.friendlyError(e.code, e.message);
      }
    }

    if (error == null) {
      try {
        visits = await widget.appState.api.getSavedVisits(ashaId);
        await widget.appState.localDb.cacheVisits(ashaId, visits);
      } on ApiException catch (e) {
        if (e.code == 'NETWORK_ERROR' || e.code == 'TIMEOUT') {
          offline = true;
          visits = await widget.appState.localDb.getCachedVisits(ashaId);
        } else {
          visits = await widget.appState.localDb.getCachedVisits(ashaId);
        }
      }
    }

    final pendingQueue =
        await widget.appState.localDb.getPendingQueue(ashaId: ashaId);
    final drafts = await widget.appState.localDb.getDrafts(ashaId: ashaId);

    if (!mounted) return;
    setState(() {
      _beneficiaries = beneficiaries;
      _visits = visits;
      _pendingSyncCount = pendingQueue.length + drafts.length;
      _offline = offline;
      _errorText = error;
      _loading = false;
    });
  }

  Future<void> _startVisitFor(Beneficiary beneficiary) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => VisitPurposePickerScreen(
          appState: widget.appState,
          beneficiary: beneficiary,
        ),
      ),
    );
    await _load();
    if (saved == true) {
      widget.onVisitSaved();
    }
  }

  void _openBeneficiaryPicker() {
    if (_beneficiaries.isEmpty) {
      widget.onSelectTab(1);
      return;
    }
    final tokens = AppTokens.of(context);
    final strings = widget.appState.strings;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: tokens.surfaceRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings.chooseBeneficiaryTitle,
                style: AppTypography.title(tokens.ink),
              ),
              const SizedBox(height: AppSpacing.md),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(sheetContext).size.height * 0.55,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _beneficiaries.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (_, idx) {
                    final b = _beneficiaries[idx];
                    return BeneficiaryTile(
                      name: b.label,
                      codeLabel: '#${b.id}',
                      typeAndAge: strings.dueTodayStatus,
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        _startVisitFor(b);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openSavedVisits() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AppScaffold(
          title: widget.appState.strings.savedVisitsTab,
          body: SavedVisitsScreen(
            appState: widget.appState,
            refreshSignal: widget.refreshSignal,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.appState.strings;
    final tokens = AppTokens.of(context);
    final profile = widget.appState.selectedProfile;
    final todayIso = DateTime.now().toIso8601String().substring(0, 10);

    final visitedTodayIds = _visits
        .where(
          (v) => v.visitDate == todayIso && v.beneficiaryId != null,
        )
        .map((v) => v.beneficiaryId!)
        .toSet();

    final Map<String, VisitSummary> flaggedByBen = {};
    for (final v in _visits) {
      final bid = v.beneficiaryId;
      if (bid != null && (v.referralSuggested || v.riskFlags.isNotEmpty)) {
        flaggedByBen.putIfAbsent(bid, () => v);
      }
    }

    final dueList = _beneficiaries
        .where((b) => !visitedTodayIds.contains(b.id))
        .toList()
      ..sort((a, b) {
        final aRisk = flaggedByBen.containsKey(a.id) ? 0 : 1;
        final bRisk = flaggedByBen.containsKey(b.id) ? 0 : 1;
        if (aRisk != bRisk) return aRisk.compareTo(bRisk);
        return a.id.compareTo(b.id);
      });

    final sync = widget.appState.syncService;
    final (SyncChipState syncState, String syncLabel) = sync.isSyncing
        ? (SyncChipState.syncing, strings.syncing)
        : _pendingSyncCount > 0
            ? (
                SyncChipState.pending,
                strings.pendingCountChip(_pendingSyncCount),
              )
            : _offline
                ? (SyncChipState.offline, strings.offlineLabel)
                : (SyncChipState.synced, strings.syncedLabel);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        children: [
          Text(
            strings.greeting(profile?.name ?? strings.appTitle),
            style: AppTypography.title(tokens.ink),
          ),
          if (profile != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${profile.id} · ${profile.area}',
              style: AppTypography.labelRegular(tokens.inkMuted),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              LanguageToggle(
                selected: widget.appState.language,
                onChanged: widget.appState.setLanguage,
              ),
              SyncChip(
                state: syncState,
                label: syncLabel,
                onTap: _openSavedVisits,
              ),
            ],
          ),
          if (_offline) ...[
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: RiskBadge(
                label: strings.offlineShowingCached,
                severity: RiskSeverity.info,
                icon: Icons.cloud_off_rounded,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  value: '${dueList.length}',
                  label: strings.dueTodayLabel,
                  onTap: () => widget.onSelectTab(1),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: StatTile(
                  value: '${visitedTodayIds.length}',
                  label: strings.doneTodayLabel,
                  tone: StatTileTone.ok,
                  onTap: _openSavedVisits,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: StatTile(
                  value: '${flaggedByBen.length}',
                  label: strings.needsAttentionLabel,
                  tone: flaggedByBen.isNotEmpty
                      ? StatTileTone.attention
                      : StatTileTone.neutral,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SupervisorFlaggedScreen(
                          appState: widget.appState,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: strings.recordVisitAction,
            icon: Icons.mic_rounded,
            onPressed: _openBeneficiaryPicker,
          ),
          const SizedBox(height: AppSpacing.xl),
          SectionHeader(
            title: strings.dueAndOverdueTitle,
            actionLabel: strings.viewBeneficiariesAction,
            onAction: () => widget.onSelectTab(1),
          ),
          const SizedBox(height: AppSpacing.md),
          if (_loading)
            const SkeletonLoader(itemCount: 3)
          else if (_errorText != null)
            ErrorState(
              title: strings.connectionFailed,
              message: _errorText!,
              retryLabel: strings.retry,
              onRetry: _load,
            )
          else if (dueList.isEmpty)
            EmptyState(
              icon: Icons.event_available_outlined,
              title: strings.noVisitsDueTitle,
              message: strings.noVisitsDueMessage,
              actionLabel: strings.viewBeneficiariesAction,
              actionIcon: Icons.people_outline_rounded,
              onAction: () => widget.onSelectTab(1),
            )
          else
            ...dueList.map((beneficiary) {
              final flagged = flaggedByBen[beneficiary.id];
              final firstFlag = flagged != null && flagged.riskFlags.isNotEmpty
                  ? strings.riskFlagLabel(flagged.riskFlags.first)
                  : (flagged?.referralSuggested == true
                      ? strings.consultChip
                      : null);
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: BeneficiaryTile(
                  name: beneficiary.label,
                  typeAndAge:
                      '${strings.fieldLabel('beneficiary_id')}: ${beneficiary.id}',
                  dueLabel: strings.dueTodayStatus,
                  riskLabel: firstFlag,
                  riskSeverity: firstFlag != null ? RiskSeverity.high : null,
                  onTap: () => _startVisitFor(beneficiary),
                ),
              );
            }),
        ],
      ),
    );
  }
}
