import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/beneficiary.dart';
import '../services/due_engine.dart';
import '../services/local_stats_engine.dart';
import '../state/app_state.dart';
import '../ui/ui.dart';
import 'beneficiary_profile_screen.dart';
import 'saved_visits_screen.dart';

/// Offline-first statistical Insights dashboard powered by local SQLite (SPEC_V2 §6).
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
  StatsPeriod _period = StatsPeriod.sevenDays;
  LocalInsightsReport? _report;
  bool _loading = true;
  bool _busyDemo = false;

  @override
  void initState() {
    super.initState();
    widget.refreshSignal.addListener(_handleExternalRefresh);
    widget.appState.addListener(_handleExternalRefresh);
    _load();
  }

  @override
  void dispose() {
    widget.refreshSignal.removeListener(_handleExternalRefresh);
    widget.appState.removeListener(_handleExternalRefresh);
    super.dispose();
  }

  void _handleExternalRefresh() {
    _load();
  }

  Future<void> _load() async {
    final profile = widget.appState.selectedProfile;
    final ashaId = profile?.id ?? 'asha_001';
    final strings = widget.appState.strings;
    final language = widget.appState.language;

    if (mounted && _report == null) {
      setState(() => _loading = true);
    }

    final report = await LocalStatsEngine.compute(
      localDb: widget.appState.localDb,
      workerId: ashaId,
      period: _period,
      strings: strings,
      language: language,
      paperBaselineMinutes: widget.appState.paperBaselineMinutes,
    );

    if (!mounted) return;
    setState(() {
      _report = report;
      _loading = false;
    });
  }

  Future<void> _toggleDemoData(bool clear) async {
    if (_busyDemo) return;
    setState(() => _busyDemo = true);
    final ashaId = widget.appState.selectedProfile?.id ?? 'asha_001';
    try {
      if (clear) {
        await LocalStatsEngine.clearDemoData(
          widget.appState.localDb,
          workerId: ashaId,
        );
      } else {
        await LocalStatsEngine.seedDemoData(
          widget.appState.localDb,
          workerId: ashaId,
        );
      }
      widget.refreshSignal.value++;
      await _load();
    } finally {
      if (mounted) {
        setState(() => _busyDemo = false);
      }
    }
  }

  void _openBeneficiary(Beneficiary beneficiary) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BeneficiaryProfileScreen(
          appState: widget.appState,
          beneficiary: beneficiary,
        ),
      ),
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
    final report = _report;

    if (_loading && report == null) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: const [
          SkeletonLoader(itemCount: 3, itemHeight: 96),
        ],
      );
    }

    final current = report ??
        LocalInsightsReport(
          period: _period,
          visitsDone: 0,
          dueToday: 0,
          overdue: 0,
          activeBeneficiaries: 0,
          coverage: 0,
          highRiskOpen: 0,
          referralsSuggested: 0,
          avgRecordSeconds: null,
          voiceShare: null,
          followupRate: null,
          pendingSyncCount: 0,
          hasDemoData: false,
          dailySeries: const [],
          byPurpose: const [],
          riskBreakdown: const [],
          dueList: const [],
          estimatedMinutesSavedPerVisit: null,
          estimatedMinutesSavedTotal: null,
        );

    final totalFlaggedInPeriod = current.dailySeries.fold<int>(
      0,
      (sum, bucket) => sum + bucket.highRiskCount,
    );

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenHorizontal,
          AppSpacing.lg,
          AppSpacing.screenHorizontal,
          AppSpacing.xxl,
        ),
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                strings.insightsTitle,
                style: AppTypography.title(tokens.ink),
              ),
              if (current.hasDemoData)
                RiskBadge(
                  label: strings.demoDataBadge,
                  severity: RiskSeverity.medium,
                  icon: Icons.science_outlined,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            current.hasDemoData
                ? strings.demoDataNotice
                : strings.insightsSummaryNote,
            style: AppTypography.labelRegular(tokens.inkMuted),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              _PeriodChip(
                label: strings.periodToday,
                selected: _period == StatsPeriod.today,
                onTap: () {
                  if (_period == StatsPeriod.today) return;
                  setState(() => _period = StatsPeriod.today);
                  _load();
                },
              ),
              _PeriodChip(
                label: strings.period7Days,
                selected: _period == StatsPeriod.sevenDays,
                onTap: () {
                  if (_period == StatsPeriod.sevenDays) return;
                  setState(() => _period = StatsPeriod.sevenDays);
                  _load();
                },
              ),
              _PeriodChip(
                label: strings.period30Days,
                selected: _period == StatsPeriod.thirtyDays,
                onTap: () {
                  if (_period == StatsPeriod.thirtyDays) return;
                  setState(() => _period = StatsPeriod.thirtyDays);
                  _load();
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),

          // 2x2 Summary StatTiles (SPEC_V2 §6.2: max 4 visible at once)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: StatTile(
                    value: '${current.visitsDone}',
                    label: strings.confirmedVisitsMetric,
                    icon: Icons.check_circle_outline_rounded,
                    tone: current.visitsDone > 0
                        ? StatTileTone.ok
                        : StatTileTone.neutral,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: StatTile(
                    value: '${(current.coverage * 100).round()}%',
                    label: strings.coverageMetric,
                    icon: Icons.pie_chart_outline_rounded,
                    tone: current.coverage >= 0.7
                        ? StatTileTone.ok
                        : StatTileTone.neutral,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: StatTile(
                    value: '${current.highRiskOpen}',
                    label: strings.highRiskMetric,
                    icon: Icons.warning_amber_rounded,
                    tone: current.highRiskOpen > 0
                        ? StatTileTone.attention
                        : StatTileTone.neutral,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: StatTile(
                    value: '${current.referralsSuggested}',
                    label: strings.referralsMetric,
                    icon: Icons.local_hospital_outlined,
                    tone: current.referralsSuggested > 0
                        ? StatTileTone.attention
                        : StatTileTone.neutral,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.sectionGap),
          _FlatCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.insightsTelemetryTitle,
                  style: AppTypography.heading(tokens.ink),
                ),
                const SizedBox(height: AppSpacing.md),
                _TelemetryRow(
                  label: strings.dueOverdueMetric,
                  value: '${current.dueToday} / ${current.overdue}',
                ),
                _TelemetryRow(
                  label: strings.avgRecordTimeMetric,
                  value: current.avgRecordSeconds != null
                      ? strings.avgSecondsFormat(current.avgRecordSeconds!)
                      : '—',
                ),
                _TelemetryRow(
                  label: strings.voiceShareMetric,
                  value: current.voiceShare != null
                      ? '${(current.voiceShare! * 100).round()}%'
                      : '—',
                ),
                _TelemetryRow(
                  label: strings.followupRateMetric,
                  value: current.followupRate != null
                      ? '${(current.followupRate! * 100).round()}%'
                      : '—',
                ),
                _TelemetryRow(
                  label: strings.pendingSyncMetric,
                  value: '${current.pendingSyncCount}',
                  isLast: current.estimatedMinutesSavedPerVisit == null,
                ),
                if (current.estimatedMinutesSavedPerVisit != null &&
                    current.estimatedMinutesSavedTotal != null)
                  _TelemetryRow(
                    label: strings.estTimeSavedMetric,
                    value: strings.minutesSavedValue(
                      current.estimatedMinutesSavedPerVisit!,
                      current.estimatedMinutesSavedTotal!,
                    ),
                    valueColor: current.estimatedMinutesSavedPerVisit! >= 0
                        ? tokens.riskOk
                        : tokens.riskMedium,
                    isLast: true,
                  ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.sectionGap),
          _FlatCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.visitsPerDayTitle,
                  style: AppTypography.heading(tokens.ink),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  current.visitsDone > 0
                      ? strings.visitsPerDaySummary(
                          current.visitsDone,
                          totalFlaggedInPeriod,
                          _period.days,
                        )
                      : strings.visitsPerDayEmpty,
                  style: AppTypography.labelRegular(tokens.inkMuted),
                ),
                const SizedBox(height: AppSpacing.md),
                if (current.visitsDone == 0 || current.dailySeries.isEmpty)
                  EmptyState(
                    icon: Icons.bar_chart_rounded,
                    title: strings.visitsPerDayTitle,
                    message: strings.visitsPerDayEmpty,
                  )
                else
                  _DailyVisitsChart(buckets: current.dailySeries),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.sectionGap),
          _FlatCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.visitsByPurposeTitle,
                  style: AppTypography.heading(tokens.ink),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  current.byPurpose.isNotEmpty
                      ? strings.visitsByPurposeSummary(
                          current.byPurpose.first.count,
                          current.byPurpose.first.label,
                        )
                      : strings.visitsByPurposeEmpty,
                  style: AppTypography.labelRegular(tokens.inkMuted),
                ),
                const SizedBox(height: AppSpacing.md),
                if (current.byPurpose.isEmpty)
                  EmptyState(
                    icon: Icons.category_outlined,
                    title: strings.visitsByPurposeTitle,
                    message: strings.visitsByPurposeEmpty,
                  )
                else
                  _HorizontalBarList(
                    items: current.byPurpose,
                    barColor: tokens.primary,
                  ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.sectionGap),
          _FlatCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.riskBreakdownTitle,
                  style: AppTypography.heading(tokens.ink),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  current.riskBreakdown.isNotEmpty
                      ? strings.riskBreakdownSummary(
                          current.riskBreakdown
                              .fold<int>(0, (sum, e) => sum + e.count),
                          current.riskBreakdown.first.label,
                        )
                      : strings.riskBreakdownEmpty,
                  style: AppTypography.labelRegular(tokens.inkMuted),
                ),
                const SizedBox(height: AppSpacing.md),
                if (current.riskBreakdown.isEmpty)
                  EmptyState(
                    icon: Icons.verified_user_outlined,
                    title: strings.riskBreakdownTitle,
                    message: strings.riskBreakdownEmpty,
                  )
                else
                  _HorizontalBarList(
                    items: current.riskBreakdown,
                    barColor: tokens.riskHigh,
                    leadingIcon: Icons.warning_amber_rounded,
                  ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.sectionGap),
          SectionHeader(
            title: strings.dueListCompactTitle,
            subtitle: strings.dueListSummary(current.overdue, current.dueToday),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (current.dueList.isEmpty)
            _FlatCard(
              child: EmptyState(
                icon: Icons.event_available_outlined,
                title: strings.dueListCompactTitle,
                message: strings.dueListEmpty,
              ),
            )
          else
            Column(
              children: current.dueList.take(5).map((item) {
                final b = item.beneficiary;
                final isOverdue = item.daysOverdue > 0;
                final dueText = isOverdue
                    ? '${item.daysOverdue}d'
                    : strings.dueTodayStatus;
                final riskSev = switch (b.riskLevel) {
                  'high' => RiskSeverity.high,
                  'watch' || 'medium' => RiskSeverity.medium,
                  _ => null,
                };
                final riskText = switch (b.riskLevel) {
                  'high' => strings.filterHighRisk,
                  'watch' || 'medium' => strings.needsAttentionLabel,
                  _ => null,
                };
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: BeneficiaryTile(
                    name: b.label,
                    typeAndAge: strings.beneficiaryTypeDisplay(b.beneficiaryType),
                    codeLabel: b.id,
                    dueLabel: dueText,
                    dueOverdue: isOverdue,
                    riskLabel: riskText,
                    riskSeverity: riskSev,
                    onTap: () => _openBeneficiary(b),
                  ),
                );
              }).toList(),
            ),

          const SizedBox(height: AppSpacing.sectionGap),
          SecondaryButton(
            label: strings.openSavedVisitsAction,
            icon: Icons.fact_check_outlined,
            onPressed: _openSavedVisits,
          ),
          const SizedBox(height: AppSpacing.sm),
          SecondaryButton(
            label: current.hasDemoData
                ? strings.clearDemoDataAction
                : strings.loadDemoDataAction,
            icon: current.hasDemoData
                ? Icons.delete_sweep_outlined
                : Icons.science_outlined,
            onPressed: _busyDemo
                ? null
                : () => _toggleDemoData(current.hasDemoData),
          ),
        ],
      ),
    );
  }
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected ? tokens.primaryContainer : tokens.surfaceRaised,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected ? tokens.primary : tokens.outline,
            width: AppSizes.borderWidth,
          ),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppSizes.minTouchTarget),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  style: selected
                      ? AppTypography.label(tokens.primary)
                      : AppTypography.labelRegular(tokens.ink),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FlatCard extends StatelessWidget {
  const _FlatCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: tokens.outline,
          width: AppSizes.borderWidth,
        ),
      ),
      child: child,
    );
  }
}

class _TelemetryRow extends StatelessWidget {
  const _TelemetryRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.isLast = false,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: isLast
          ? null
          : BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: tokens.outline,
                  width: AppSizes.borderWidth,
                ),
              ),
            ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTypography.body(tokens.inkMuted),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: AppTypography.tabular(
                AppTypography.bodySemiBold(valueColor ?? tokens.ink),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DailyVisitsChart extends StatelessWidget {
  const _DailyVisitsChart({required this.buckets});

  final List<DailyVisitBucket> buckets;

  static String _shortDate(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    return '$d/$m';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final maxCount = math.max(
      1,
      buckets.fold<int>(0, (prev, b) => math.max(prev, b.count)),
    );
    final first = buckets.first.date;
    final mid = buckets[buckets.length ~/ 2].date;
    final last = buckets.last.date;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '0 – $maxCount',
              style: AppTypography.tabular(AppTypography.caption(tokens.inkMuted)),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        SizedBox(
          height: 132,
          width: double.infinity,
          child: CustomPaint(
            painter: _DailyVisitsPainter(
              buckets: buckets,
              maxCount: maxCount,
              barColor: tokens.primary,
              flaggedColor: tokens.riskHigh,
              gridColor: tokens.outline,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        if (buckets.length == 1)
          Text(
            DueEngine.formatIsoDate(first),
            style: AppTypography.tabular(AppTypography.caption(tokens.inkMuted)),
          )
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _shortDate(first),
                style: AppTypography.tabular(AppTypography.caption(tokens.inkMuted)),
              ),
              if (buckets.length >= 4)
                Text(
                  _shortDate(mid),
                  style: AppTypography.tabular(
                    AppTypography.caption(tokens.inkMuted),
                  ),
                ),
              Text(
                _shortDate(last),
                style: AppTypography.tabular(AppTypography.caption(tokens.inkMuted)),
              ),
            ],
          ),
      ],
    );
  }
}

class _DailyVisitsPainter extends CustomPainter {
  const _DailyVisitsPainter({
    required this.buckets,
    required this.maxCount,
    required this.barColor,
    required this.flaggedColor,
    required this.gridColor,
  });

  final List<DailyVisitBucket> buckets;
  final int maxCount;
  final Color barColor;
  final Color flaggedColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (buckets.isEmpty || size.width <= 0 || size.height <= 0) return;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      gridPaint,
    );
    canvas.drawLine(
      Offset(0, size.height * 0.5),
      Offset(size.width, size.height * 0.5),
      gridPaint,
    );

    final primaryPaint = Paint()..color = barColor;
    final riskPaint = Paint()..color = flaggedColor;

    final n = buckets.length;
    final slotWidth = size.width / n;
    final barWidth = math.max(3.0, math.min(28.0, slotWidth * 0.64));
    final topInset = 6.0;
    final usableHeight = math.max(1.0, size.height - topInset);

    for (var i = 0; i < n; i++) {
      final bucket = buckets[i];
      if (bucket.count <= 0) continue;
      final totalHeight = (bucket.count / maxCount) * usableHeight;
      final left = i * slotWidth + (slotWidth - barWidth) / 2;
      final top = size.height - totalHeight;
      final rrect = RRect.fromRectAndCorners(
        Rect.fromLTWH(left, top, barWidth, totalHeight),
        topLeft: const Radius.circular(3),
        topRight: const Radius.circular(3),
      );
      canvas.drawRRect(rrect, primaryPaint);

      if (bucket.highRiskCount > 0) {
        final flaggedRatio = math.min(1.0, bucket.highRiskCount / bucket.count);
        final flaggedHeight = totalHeight * flaggedRatio;
        canvas.drawRect(
          Rect.fromLTWH(
            left,
            size.height - flaggedHeight,
            barWidth,
            flaggedHeight,
          ),
          riskPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DailyVisitsPainter oldDelegate) {
    return oldDelegate.buckets != buckets ||
        oldDelegate.maxCount != maxCount ||
        oldDelegate.barColor != barColor ||
        oldDelegate.flaggedColor != flaggedColor ||
        oldDelegate.gridColor != gridColor;
  }
}

class _HorizontalBarList extends StatelessWidget {
  const _HorizontalBarList({
    required this.items,
    required this.barColor,
    this.leadingIcon,
  });

  final List<CategoryCount> items;
  final Color barColor;
  final IconData? leadingIcon;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final maxCount = math.max(
      1,
      items.fold<int>(0, (prev, item) => math.max(prev, item.count)),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items.map((item) {
        final fraction = (item.count / maxCount).clamp(0.06, 1.0);
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (leadingIcon != null) ...[
                    Icon(leadingIcon, size: 18, color: barColor),
                    const SizedBox(width: AppSpacing.xs),
                  ],
                  Expanded(
                    child: Text(
                      item.label,
                      style: AppTypography.body(tokens.ink),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    '${item.count}',
                    style: AppTypography.tabular(
                      AppTypography.bodySemiBold(tokens.ink),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.subtle),
                child: SizedBox(
                  height: 8,
                  width: double.infinity,
                  child: Stack(
                    children: [
                      Container(color: tokens.surface),
                      FractionallySizedBox(
                        widthFactor: fraction,
                        heightFactor: 1,
                        child: Container(color: barColor),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
