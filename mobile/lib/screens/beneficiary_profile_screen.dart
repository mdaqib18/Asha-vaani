import 'package:flutter/material.dart';

import '../models/beneficiary.dart';
import '../models/newborn_visit.dart';
import '../models/v2_models.dart';
import '../services/api_client.dart';
import '../state/app_state.dart';
import '../ui/ui.dart';
import '../widgets/language_toggle.dart';
import 'visit_purpose_picker_screen.dart';

/// Detailed beneficiary overview with masked PII reveal, trend chart, and visit timeline (SPEC_V2 §3.5).
class BeneficiaryProfileScreen extends StatefulWidget {
  const BeneficiaryProfileScreen({
    super.key,
    required this.appState,
    required this.beneficiary,
  });

  final AppState appState;
  final Beneficiary beneficiary;

  @override
  State<BeneficiaryProfileScreen> createState() =>
      _BeneficiaryProfileScreenState();
}

class _BeneficiaryProfileScreenState extends State<BeneficiaryProfileScreen> {
  late Beneficiary _beneficiary;
  List<VisitSummary> _visits = const [];
  List<MeasurementPoint> _measurements = const [];
  Map<String, int> _amendmentCounts = const {};
  bool _loading = true;
  bool _offline = false;
  bool _phoneRevealed = false;
  bool _externalIdRevealed = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _beneficiary = widget.beneficiary;
    _load();
  }

  Future<void> _load() async {
    final ashaId = widget.appState.selectedProfile?.id;
    setState(() {
      _loading = true;
      _offline = false;
      _errorText = null;
    });

    Beneficiary profile = _beneficiary;
    List<VisitSummary> visits = const [];
    List<MeasurementPoint> measurements = const [];
    var offline = false;

    try {
      final fetched = await widget.appState.api.getBeneficiaryProfile(
        _beneficiary.uuid ?? _beneficiary.id,
      );
      if (fetched.label.isNotEmpty) {
        profile = fetched.copyWith(
          phoneLocal: _beneficiary.phoneLocal ?? fetched.phoneLocal,
        );
      }
    } on ApiException catch (e) {
      if (e.code == 'NETWORK_ERROR' || e.code == 'TIMEOUT') {
        offline = true;
      }
    }

    try {
      final res = await widget.appState.api.getBeneficiaryVisits(
        profile.uuid ?? profile.id,
      );
      visits = res.visits;
      measurements = res.measurements;
    } on ApiException catch (e) {
      if (e.code == 'NETWORK_ERROR' || e.code == 'TIMEOUT') {
        offline = true;
        if (ashaId != null) {
          final cached = await widget.appState.localDb.getCachedVisits(ashaId);
          visits = cached
              .where((v) => v.beneficiaryId == profile.id)
              .toList();
          final localVisits = await widget.appState.localDb.getVisitsV2(
            beneficiaryId: profile.uuid ?? profile.id,
          );
          for (final lv in localVisits) {
            if (!visits.any((v) => v.visitId == lv.id)) {
              visits.add(
                VisitSummary(
                  visitId: lv.id,
                  sessionId: lv.id,
                  ashaId: lv.workerId,
                  beneficiaryId: profile.id,
                  visitDate: lv.visitedAt,
                  riskFlags: lv.riskFlags,
                  referralSuggested: lv.referralSuggested,
                  status: lv.status,
                  updatedAt: lv.updatedAt,
                ),
              );
            }
          }
          final localMeas = await widget.appState.localDb.getVisitMeasurements(
            profile.uuid ?? profile.id,
          );
          measurements = localMeas
              .map(
                (m) => MeasurementPoint(
                  key: m.key,
                  valueNum: m.valueNum,
                  unit: m.unit,
                  measuredAt: m.measuredAt,
                ),
              )
              .toList();
        }
      } else {
        _errorText = widget.appState.strings.friendlyError(e.code, e.message);
      }
    }

    final counts = <String, int>{};
    for (final v in visits) {
      final vid = v.visitId ?? v.sessionId;
      if (vid.isEmpty) continue;
      final amendments =
          await widget.appState.localDb.getVisitAmendments(vid);
      counts[vid] = amendments.length;
    }

    if (!mounted) return;
    setState(() {
      _beneficiary = profile;
      _visits = visits;
      _measurements = measurements;
      _amendmentCounts = counts;
      _offline = offline;
      _loading = false;
    });
  }

  Future<void> _toggleSensitiveField({
    required bool currentlyRevealed,
    required ValueSetter<bool> setter,
  }) async {
    final nextState = !currentlyRevealed;
    setState(() => setter(nextState));
    if (nextState) {
      final actorId = widget.appState.selectedProfile?.id ?? 'worker';
      await widget.appState.localDb.recordAuditLog(
        AuditLogEntry(
          id: UuidV4.generate(),
          actorId: actorId,
          action: 'pii_revealed',
          entity: 'beneficiary',
          entityId: _beneficiary.uuid ?? _beneficiary.id,
          at: DateTime.now().toUtc().toIso8601String(),
        ),
      );
    }
  }

  Future<void> _recordVisit() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => VisitPurposePickerScreen(
          appState: widget.appState,
          beneficiary: _beneficiary,
          beneficiaryType: _beneficiary.beneficiaryType,
          dobIso: _beneficiary.dob,
        ),
      ),
    );
    await _load();
    if (saved == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  RiskSeverity? _riskSeverity(String level) {
    switch (level) {
      case 'high':
        return RiskSeverity.high;
      case 'watch':
        return RiskSeverity.medium;
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.appState,
      builder: (context, _) {
        final tokens = AppTokens.of(context);
        final strings = widget.appState.strings;
        final typeLabel =
            strings.beneficiaryTypeDisplay(_beneficiary.beneficiaryType);
        final agePart = _beneficiary.ageSummary();
        final typeAndAge = [
          typeLabel,
          if (agePart.isNotEmpty)
            _beneficiary.dobIsEstimated ? '~$agePart' : agePart,
          if (_beneficiary.area != null && _beneficiary.area!.isNotEmpty)
            _beneficiary.area!,
        ].join(' · ');

        final severity = _riskSeverity(_beneficiary.riskLevel);
        final hasPhone = _beneficiary.hasPhone;
        final revealedPhone = _beneficiary.phoneLocal ??
            _beneficiary.phoneMasked ??
            strings.notRecorded;
        final maskedPhone = _beneficiary.phoneMasked ??
            Beneficiary.maskPhone(_beneficiary.phoneLocal) ??
            strings.notRecorded;
        final hasExternalId = _beneficiary.hasExternalId;
        final revealedExternalId = _beneficiary.externalId ?? strings.notRecorded;
        final maskedExternalId =
            Beneficiary.maskSecret(_beneficiary.externalId) ??
                strings.notRecorded;

        return AppScaffold(
          title: _beneficiary.label,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: LanguageToggle(
                selected: widget.appState.language,
                onChanged: widget.appState.setLanguage,
              ),
            ),
          ],
          body: ListView(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: tokens.surfaceRaised,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(
                    color: tokens.outline,
                    width: AppSizes.borderWidth,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _beneficiary.label,
                                style: AppTypography.title(tokens.ink),
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                typeAndAge,
                                style: AppTypography.body(tokens.inkMuted),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          '#${_beneficiary.id}',
                          style: AppTypography.tabular(
                            AppTypography.label(tokens.inkMuted),
                          ),
                        ),
                      ],
                    ),
                    if (severity != null ||
                        _beneficiary.nextDueAt != null ||
                        _beneficiary.eddDate != null ||
                        _offline) ...[
                      const SizedBox(height: AppSpacing.md),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xs,
                        children: [
                          if (severity != null)
                            RiskBadge(
                              label: severity == RiskSeverity.high
                                  ? strings.consultChip
                                  : strings.needsAttentionLabel,
                              severity: severity,
                            ),
                          if (_beneficiary.nextDueAt != null &&
                              _beneficiary.nextDueAt!.isNotEmpty)
                            RiskBadge(
                              label:
                                  '${strings.dueTodayLabel}: ${_beneficiary.nextDueAt}',
                              severity: RiskSeverity.info,
                              icon: Icons.event_available_outlined,
                            ),
                          if (_beneficiary.eddDate != null &&
                              _beneficiary.eddDate!.isNotEmpty)
                            RiskBadge(
                              label: 'EDD: ${_beneficiary.eddDate}',
                              severity: RiskSeverity.ok,
                              icon: Icons.calendar_today_outlined,
                            ),
                          if (_offline)
                            RiskBadge(
                              label: strings.offlineShowingCached,
                              severity: RiskSeverity.info,
                              icon: Icons.cloud_off_rounded,
                            ),
                        ],
                      ),
                    ],
                    if (hasPhone) ...[
                      const SizedBox(height: AppSpacing.md),
                      Divider(color: tokens.outline, height: 1),
                      const SizedBox(height: AppSpacing.sm),
                      SizedBox(
                        width: double.infinity,
                        child: Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.xs,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.phone_outlined,
                                  size: 18,
                                  color: tokens.inkMuted,
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Flexible(
                                  child: Text(
                                    '${strings.phoneLabel}: ${_phoneRevealed ? revealedPhone : maskedPhone}',
                                    style: AppTypography.tabular(
                                      AppTypography.body(tokens.ink),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            TextAction(
                              label: _phoneRevealed
                                  ? strings.hideSensitiveAction
                                  : strings.tapToRevealAction,
                              onPressed: () => _toggleSensitiveField(
                                currentlyRevealed: _phoneRevealed,
                                setter: (v) => _phoneRevealed = v,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (hasExternalId) ...[
                      const SizedBox(height: AppSpacing.md),
                      Divider(color: tokens.outline, height: 1),
                      const SizedBox(height: AppSpacing.sm),
                      SizedBox(
                        width: double.infinity,
                        child: Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.xs,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.badge_outlined,
                                  size: 18,
                                  color: tokens.inkMuted,
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Flexible(
                                  child: Text(
                                    '${strings.externalIdLabel}: ${_externalIdRevealed ? revealedExternalId : maskedExternalId}',
                                    style: AppTypography.tabular(
                                      AppTypography.body(tokens.ink),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            TextAction(
                              label: _externalIdRevealed
                                  ? strings.hideSensitiveAction
                                  : strings.tapToRevealAction,
                              onPressed: () => _toggleSensitiveField(
                                currentlyRevealed: _externalIdRevealed,
                                setter: (v) => _externalIdRevealed = v,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(
                label: strings.recordVisitAction,
                icon: Icons.mic_rounded,
                onPressed: _recordVisit,
              ),
              if (_measurements.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xl),
                SectionHeader(title: strings.recentMeasurementsTitle),
                const SizedBox(height: AppSpacing.sm),
                _MeasurementTrendCard(
                  points: _measurements,
                  labelBuilder: strings.fieldLabel,
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              SectionHeader(title: strings.visitTimelineTitle),
              const SizedBox(height: AppSpacing.sm),
              if (_loading)
                const SkeletonLoader(itemCount: 2)
              else if (_errorText != null)
                ErrorState(
                  title: strings.connectionFailed,
                  message: _errorText!,
                  retryLabel: strings.retry,
                  onRetry: _load,
                )
              else if (_visits.isEmpty)
                EmptyState(
                  icon: Icons.history_outlined,
                  title: strings.noVisitsRecordedYet,
                  message: strings.recordFirstVisitNowAction,
                  actionLabel: strings.recordVisitAction,
                  actionIcon: Icons.mic_rounded,
                  onAction: _recordVisit,
                )
              else
                ..._visits.map(
                  (visit) {
                    final dateText = (visit.visitDate != null &&
                            visit.visitDate!.isNotEmpty)
                        ? visit.visitDate!
                        : (visit.updatedAt.length >= 10
                            ? visit.updatedAt.substring(0, 10)
                            : visit.updatedAt);
                    final hasRisk = visit.referralSuggested ||
                        visit.riskFlags.isNotEmpty;
                    final vid = visit.visitId ?? visit.sessionId;
                    final amendCount = _amendmentCounts[vid] ?? 0;
                    final workerLabel = visit.ashaId ??
                        widget.appState.selectedProfile?.name ??
                        'ASHA';
                    final auditLine = strings.visitAuditLine(
                      workerLabel,
                      dateText,
                      amendCount,
                    );
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: VisitTile(
                        purposeLabel: strings.recordVisitTitle,
                        subtitle: auditLine,
                        statusLabel: strings.visitSaved,
                        statusSeverity: RiskSeverity.ok,
                        riskLabel: hasRisk
                            ? (visit.riskFlags.isNotEmpty
                                ? strings.riskFlagLabel(visit.riskFlags.first)
                                : strings.consultChip)
                            : null,
                        riskSeverity: hasRisk ? RiskSeverity.high : null,
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

class _MeasurementTrendCard extends StatelessWidget {
  const _MeasurementTrendCard({
    required this.points,
    required this.labelBuilder,
  });

  final List<MeasurementPoint> points;
  final String Function(String key) labelBuilder;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final primaryKey = points.first.key;
    final series = points.where((p) => p.key == primaryKey).toList();
    final values = series.map((p) => p.valueNum).toList();
    final minVal = values.reduce((a, b) => a < b ? a : b);
    final maxVal = values.reduce((a, b) => a > b ? a : b);
    final latest = series.last;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: tokens.outline,
          width: AppSizes.borderWidth,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  labelBuilder(primaryKey),
                  style: AppTypography.bodySemiBold(tokens.ink),
                ),
              ),
              Text(
                '${latest.valueNum} ${latest.unit}',
                style: AppTypography.tabular(
                  AppTypography.heading(tokens.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 72,
            width: double.infinity,
            child: CustomPaint(
              painter: _SparklinePainter(
                values: values,
                lineColor: tokens.primary,
                dotColor: tokens.accent,
                gridColor: tokens.outline,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Min: $minVal ${latest.unit} · Max: $maxVal ${latest.unit} (${series.length})',
            style: AppTypography.tabular(
              AppTypography.labelRegular(tokens.inkMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({
    required this.values,
    required this.lineColor,
    required this.dotColor,
    required this.gridColor,
  });

  final List<double> values;
  final Color lineColor;
  final Color dotColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height - 8),
      Offset(size.width, size.height - 8),
      gridPaint,
    );
    if (values.isEmpty) return;

    final minV = values.reduce((a, b) => a < b ? a : b);
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final span = (maxV - minV).abs() < 0.001 ? 1.0 : (maxV - minV);

    final pts = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1
          ? size.width / 2
          : (i / (values.length - 1)) * (size.width - 16) + 8;
      final normY = (values[i] - minV) / span;
      final y = size.height - 14 - (normY * (size.height - 24));
      pts.add(Offset(x, y));
    }

    if (pts.length > 1) {
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (var i = 1; i < pts.length; i++) {
        path.lineTo(pts[i].dx, pts[i].dy);
      }
      final linePaint = Paint()
        ..color = lineColor
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke;
      canvas.drawPath(path, linePaint);
    }

    final dotPaint = Paint()..color = dotColor;
    for (final p in pts) {
      canvas.drawCircle(p, 4.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.lineColor != lineColor;
  }
}
