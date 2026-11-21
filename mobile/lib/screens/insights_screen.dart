import 'package:flutter/material.dart';

import '../models/newborn_visit.dart';
import '../services/api_client.dart';
import '../state/app_state.dart';
import '../ui/ui.dart';
import 'saved_visits_screen.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({
    super.key,
    required this.appState,
    required this.refreshSignal,
  });

  final AppState appState;
  final ValueNotifier<int> refreshSignal;

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  List<VisitSummary> _visits = const [];
  int _pendingCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    widget.appState.syncService.addListener(_load);
    widget.refreshSignal.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.appState.syncService.removeListener(_load);
    widget.refreshSignal.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final ashaId = widget.appState.selectedProfile?.id;
    if (ashaId == null) return;

    List<VisitSummary> visits = const [];
    try {
      visits = await widget.appState.api.getSavedVisits(ashaId);
      await widget.appState.localDb.cacheVisits(ashaId, visits);
    } on ApiException {
      visits = await widget.appState.localDb.getCachedVisits(ashaId);
    }

    final pending =
        await widget.appState.localDb.getPendingQueue(ashaId: ashaId);
    final drafts = await widget.appState.localDb.getDrafts(ashaId: ashaId);

    if (!mounted) return;
    setState(() {
      _visits = visits;
      _pendingCount = pending.length + drafts.length;
      _loading = false;
    });
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
    final highRiskCount = _visits
        .where((v) => v.referralSuggested || v.riskFlags.isNotEmpty)
        .length;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        children: [
          SectionHeader(
            title: strings.insightsTitle,
            subtitle: strings.insightsSummaryNote,
          ),
          const SizedBox(height: AppSpacing.md),
          if (_loading)
            const SkeletonLoader(itemCount: 2)
          else ...[
            Row(
              children: [
                Expanded(
                  child: StatTile(
                    value: '${_visits.length}',
                    label: strings.confirmedVisitsMetric,
                    tone: StatTileTone.ok,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: StatTile(
                    value: '$highRiskCount',
                    label: strings.highRiskMetric,
                    tone: highRiskCount > 0
                        ? StatTileTone.attention
                        : StatTileTone.neutral,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            StatTile(
              value: '$_pendingCount',
              label: strings.pendingSyncMetric,
              onTap: _openSavedVisits,
            ),
            const SizedBox(height: AppSpacing.lg),
            SecondaryButton(
              label: strings.openSavedVisitsAction,
              icon: Icons.fact_check_outlined,
              onPressed: _openSavedVisits,
            ),
            const SizedBox(height: AppSpacing.xl),
            EmptyState(
              icon: Icons.bar_chart_rounded,
              title: strings.insightsComingNextTitle,
              message: strings.insightsComingNextBody,
            ),
          ],
        ],
      ),
    );
  }
}
