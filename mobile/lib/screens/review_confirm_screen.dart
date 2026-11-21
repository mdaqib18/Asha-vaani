import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../models/newborn_visit.dart';
import '../services/api_client.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/language_toggle.dart';

class ReviewConfirmScreen extends StatefulWidget {
  const ReviewConfirmScreen({
    super.key,
    required this.appState,
    required this.initialTurn,
  });

  final AppState appState;
  final VisitTurnResponse initialTurn;

  @override
  State<ReviewConfirmScreen> createState() => _ReviewConfirmScreenState();
}

class _ReviewConfirmScreenState extends State<ReviewConfirmScreen> {
  static const List<String> _fieldOrder = [
    'beneficiary_id',
    'baby_weight_kg',
    'temperature_c',
    'breastfeeding',
    'cord_status',
    'jaundice',
    'breathing_rate_per_min',
    'limb_abnormality',
    'danger_signs',
    'mother_notes',
    'notes',
  ];

  static const Set<String> _requiredFields = {
    'beneficiary_id',
    'baby_weight_kg',
    'temperature_c',
    'breastfeeding',
    'cord_status',
    'jaundice',
    'limb_abnormality',
  };

  late NewbornVisitRecord _record;
  late List<ValidationFlag> _flags;
  late List<String> _riskFlags;
  late bool _referralSuggested;
  FollowupPayload? _followup;

  bool _saving = false;
  bool _readingBack = false;

  @override
  void initState() {
    super.initState();
    _record = widget.initialTurn.record;
    _flags = widget.initialTurn.flags;
    _riskFlags = widget.initialTurn.riskFlags;
    _referralSuggested = widget.initialTurn.referralSuggested;
    _followup = widget.initialTurn.followup;
  }

  @override
  void dispose() {
    widget.appState.audioPlayer.stop();
    super.dispose();
  }

  ValidationFlag? _flagFor(String field) {
    for (final f in _flags) {
      if (f.field == field) return f;
    }
    return null;
  }

  ExtractedField<dynamic>? _extractedFor(String field) {
    switch (field) {
      case 'beneficiary_id':
        return _record.beneficiaryId;
      case 'baby_weight_kg':
        return _record.babyWeightKg;
      case 'temperature_c':
        return _record.temperatureC;
      case 'breastfeeding':
        return _record.breastfeeding;
      case 'cord_status':
        return _record.cordStatus;
      case 'jaundice':
        return _record.jaundice;
      case 'breathing_rate_per_min':
        return _record.breathingRatePerMin;
      case 'limb_abnormality':
        return _record.limbAbnormality;
      case 'danger_signs':
        return _record.dangerSigns;
      case 'mother_notes':
        return _record.motherNotes;
      case 'notes':
        return _record.notes;
      default:
        return null;
    }
  }

  String? _formattedValue(String field, AppStrings strings) {
    switch (field) {
      case 'beneficiary_id':
        return _record.beneficiaryId?.value;
      case 'baby_weight_kg':
        final w = _record.babyWeightKg?.value;
        return w == null ? null : '$w kg';
      case 'temperature_c':
        final t = _record.temperatureC?.value;
        return t == null ? null : '${t.toStringAsFixed(1)} °C';
      case 'breastfeeding':
        final b = _record.breastfeeding?.value;
        return b == null ? null : strings.breastfeedingLabel(b);
      case 'cord_status':
        final c = _record.cordStatus?.value;
        return c == null ? null : strings.cordStatusLabel(c);
      case 'jaundice':
        final j = _record.jaundice?.value;
        return j == null ? null : (j ? strings.yes : strings.no);
      case 'breathing_rate_per_min':
        final br = _record.breathingRatePerMin?.value;
        return br == null ? null : '$br / min';
      case 'limb_abnormality':
        final limb = _record.limbAbnormality?.value;
        if (limb == null) return null;
        if (!limb.present) return strings.no;
        final loc = limb.location != null ? strings.limbLocationLabel(limb.location!) : '';
        final desc = limb.description?.trim() ?? '';
        final parts = [strings.yes, if (loc.isNotEmpty) loc, if (desc.isNotEmpty) desc];
        return parts.join(' · ');
      case 'danger_signs':
        final signs = _record.dangerSigns?.value;
        if (signs == null) return null;
        if (signs.isEmpty) return strings.no;
        return signs.map(strings.dangerSignLabel).join(', ');
      case 'mother_notes':
        return _record.motherNotes?.value;
      case 'notes':
        return _record.notes?.value;
      default:
        return null;
    }
  }

  String? _statusBadgeLabel(String field, AppStrings strings) {
    final flag = _flagFor(field);
    if (flag != null) {
      if (flag.reason == 'out_of_range') return strings.outOfRangeTag;
      if (flag.reason == 'unknown_beneficiary') return strings.unknownIdTag;
      if (flag.reason == 'missing_required') return strings.missingTag;
    }
    final extracted = _extractedFor(field);
    if (extracted?.needsConfirmation == true) return strings.verifyTag;
    if (_requiredFields.contains(field) && extracted?.value == null) {
      return strings.missingTag;
    }
    return null;
  }

  Future<void> _applyPatch(Map<String, dynamic> patch) async {
    try {
      final resp = await widget.appState.api.patchVisitRecord(
        widget.initialTurn.sessionId,
        patch,
      );
      if (!mounted) return;
      setState(() {
        _record = resp.record;
        _flags = resp.flags;
        _riskFlags = resp.riskFlags;
        _referralSuggested = resp.referralSuggested;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.appState.strings.friendlyError(e.code, e.message)),
        ),
      );
    }
  }

  Future<void> _openEditor(String field) async {
    switch (field) {
      case 'baby_weight_kg':
      case 'temperature_c':
      case 'breathing_rate_per_min':
      case 'beneficiary_id':
      case 'mother_notes':
      case 'notes':
        await _openTextOrNumberEditor(field);
        break;
      case 'breastfeeding':
        await _openSingleChoiceEditor(
          field,
          const ['exclusive', 'partial', 'not_feeding', 'unknown'],
          widget.appState.strings.breastfeedingLabel,
          _record.breastfeeding?.value,
        );
        break;
      case 'cord_status':
        await _openSingleChoiceEditor(
          field,
          const ['clean_dry', 'red_swollen', 'pus_discharge', 'unknown'],
          widget.appState.strings.cordStatusLabel,
          _record.cordStatus?.value,
        );
        break;
      case 'jaundice':
        await _openBoolEditor(field, _record.jaundice?.value);
        break;
      case 'limb_abnormality':
        await _openLimbEditor();
        break;
      case 'danger_signs':
        await _openDangerSignsEditor();
        break;
    }
  }

  Future<void> _openTextOrNumberEditor(String field) async {
    final strings = widget.appState.strings;
    final isDecimal = field == 'baby_weight_kg' || field == 'temperature_c';
    final isInt = field == 'breathing_rate_per_min';
    final initial = _extractedFor(field)?.value?.toString() ?? '';
    final controller = TextEditingController(text: initial);

    final result = await showModalBottomSheet<Object?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings.fieldLabel(field),
                style: Theme.of(ctx).textTheme.headlineSmall,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: isDecimal
                    ? const TextInputType.numberWithOptions(decimal: true)
                    : (isInt ? TextInputType.number : TextInputType.text),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(_ClearSentinel()),
                    child: Text(strings.clear),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(null),
                    child: Text(strings.cancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      final raw = controller.text.trim();
                      if (raw.isEmpty) {
                        Navigator.of(ctx).pop(_ClearSentinel());
                        return;
                      }
                      if (isDecimal) {
                        final parsed = double.tryParse(raw);
                        if (parsed == null) return;
                        Navigator.of(ctx).pop(parsed);
                      } else if (isInt) {
                        final parsed = int.tryParse(raw);
                        if (parsed == null) return;
                        Navigator.of(ctx).pop(parsed);
                      } else {
                        Navigator.of(ctx).pop(raw);
                      }
                    },
                    child: Text(strings.save),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    if (result == null) return;
    if (result is _ClearSentinel) {
      await _applyPatch({field: null});
    } else {
      await _applyPatch({field: result});
    }
  }

  Future<void> _openSingleChoiceEditor(
    String field,
    List<String> options,
    String Function(String) labelOf,
    String? current,
  ) async {
    final strings = widget.appState.strings;
    final selected = await showModalBottomSheet<String?>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings.fieldLabel(field),
                style: Theme.of(ctx).textTheme.headlineSmall,
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: options.map((opt) {
                  return ChoiceChip(
                    label: Text(labelOf(opt)),
                    selected: opt == current,
                    onSelected: (_) => Navigator.of(ctx).pop(opt),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
    if (selected != null) {
      await _applyPatch({field: selected});
    }
  }

  Future<void> _openBoolEditor(String field, bool? current) async {
    final strings = widget.appState.strings;
    final chosen = await showModalBottomSheet<bool?>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings.fieldLabel(field),
                style: Theme.of(ctx).textTheme.headlineSmall,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: Text(strings.yes),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: Text(strings.no),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    if (chosen != null) {
      await _applyPatch({field: chosen});
    }
  }

  Future<void> _openLimbEditor() async {
    final strings = widget.appState.strings;
    final initial = _record.limbAbnormality?.value;
    var present = initial?.present ?? false;
    var location = initial?.location ?? 'unspecified';
    final descController = TextEditingController(text: initial?.description ?? '');

    const locations = [
      'left_arm',
      'right_arm',
      'left_leg',
      'right_leg',
      'both_arms',
      'both_legs',
      'unspecified',
    ];

    final saved = await showModalBottomSheet<LimbAbnormality?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    strings.fieldLabel('limb_abnormality'),
                    style: Theme.of(ctx).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text(strings.no),
                        selected: !present,
                        onSelected: (_) => setModalState(() => present = false),
                      ),
                      ChoiceChip(
                        label: Text(strings.yes),
                        selected: present,
                        onSelected: (_) => setModalState(() => present = true),
                      ),
                    ],
                  ),
                  if (present) ...[
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: locations.map((loc) {
                        return ChoiceChip(
                          label: Text(strings.limbLocationLabel(loc)),
                          selected: location == loc,
                          onSelected: (_) => setModalState(() => location = loc),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descController,
                      decoration: InputDecoration(
                        hintText: strings.fieldLabel('notes'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () {
                      final desc = descController.text.trim();
                      Navigator.of(ctx).pop(
                        LimbAbnormality(
                          present: present,
                          location: present ? location : null,
                          description: present && desc.isNotEmpty ? desc : null,
                        ),
                      );
                    },
                    child: Text(strings.save),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (saved != null) {
      await _applyPatch({'limb_abnormality': saved.toJson()});
    }
  }

  Future<void> _openDangerSignsEditor() async {
    final strings = widget.appState.strings;
    final selected = Set<String>.from(_record.dangerSigns?.value ?? const []);
    const allSigns = [
      'not_feeding',
      'convulsions',
      'lethargy',
      'fast_breathing',
      'fever',
      'hypothermia',
      'pus_umbilicus',
    ];

    final updated = await showModalBottomSheet<List<String>?>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    strings.fieldLabel('danger_signs'),
                    style: Theme.of(ctx).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: allSigns.map((sign) {
                      final isChecked = selected.contains(sign);
                      return FilterChip(
                        label: Text(strings.dangerSignLabel(sign)),
                        selected: isChecked,
                        onSelected: (val) {
                          setModalState(() {
                            if (val) {
                              selected.add(sign);
                            } else {
                              selected.remove(sign);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(selected.toList()),
                    child: Text(strings.save),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (updated != null) {
      await _applyPatch({'danger_signs': updated});
    }
  }

  Future<void> _readBack() async {
    setState(() => _readingBack = true);
    try {
      final res = await widget.appState.api.getReadback(
        widget.initialTurn.sessionId,
        widget.appState.language.code,
      );
      if (!mounted) return;
      setState(() => _readingBack = false);
      await showDialog<void>(
        context: context,
        builder: (ctx) => _ReadbackDialog(
          appState: widget.appState,
          readback: res,
        ),
      );
      await widget.appState.audioPlayer.stop();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _readingBack = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.appState.strings.friendlyError(e.code, e.message)),
        ),
      );
    }
  }

  Future<void> _confirmVisit() async {
    setState(() => _saving = true);
    try {
      await widget.appState.api.confirmVisit(widget.initialTurn.sessionId);
      await widget.appState.localDb.deleteDraft(widget.initialTurn.sessionId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.appState.strings.visitSaved)),
      );
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.appState.strings.friendlyError(e.code, e.message)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.appState,
      builder: (context, _) {
        final strings = widget.appState.strings;
        final transcript = widget.initialTurn.transcript.trim();

        return Scaffold(
          appBar: AppBar(
            title: Text(strings.reviewTitle),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: LanguageToggle(
                  selected: widget.appState.language,
                  onChanged: widget.appState.setLanguage,
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                  children: [
                    if (_referralSuggested || _riskFlags.isNotEmpty) ...[
                      _RiskBanner(
                        title: strings.referralBannerTitle,
                        flagLabels: _riskFlags.map(strings.riskFlagLabel).toList(),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (_followup != null) ...[
                      _FollowupNoticeCard(
                        title: strings.followupNoteTitle,
                        question: _followup!.questionText,
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (transcript.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceSubtle,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              strings.transcriptLabel,
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              transcript,
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    ..._fieldOrder.map((fieldKey) {
                      final valueText = _formattedValue(fieldKey, strings);
                      final badge = _statusBadgeLabel(fieldKey, strings);
                      final highlighted = badge != null;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _EditableFieldCard(
                          key: ValueKey('field_card_$fieldKey'),
                          label: strings.fieldLabel(fieldKey),
                          valueText: valueText,
                          missingText: strings.notRecorded,
                          badgeText: badge,
                          highlighted: highlighted,
                          onTap: () => _openEditor(fieldKey),
                        ),
                      );
                    }),
                  ],
                ),
              ),
              Container(
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: SafeArea(
                  top: false,
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _readingBack || _saving ? null : _readBack,
                          icon: _readingBack
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.volume_up_outlined),
                          label: Text(strings.readBack),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton(
                          onPressed: _saving ? null : _confirmVisit,
                          child: _saving
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(strings.confirmAndSave),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ClearSentinel {}

class _RiskBanner extends StatelessWidget {
  const _RiskBanner({required this.title, required this.flagLabels});

  final String title;
  final List<String> flagLabels;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.riskBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.riskBorder.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.medical_services_outlined, color: AppColors.riskText),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.riskText,
                  ),
                ),
              ),
            ],
          ),
          if (flagLabels.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: flagLabels.map((label) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.riskBorder.withValues(alpha: 0.35)),
                  ),
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.riskText,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _FollowupNoticeCard extends StatelessWidget {
  const _FollowupNoticeCard({required this.title, required this.question});

  final String title;
  final String question;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryTint,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.help_outline_rounded, color: AppColors.primaryDark),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryDark,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  question,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.inkPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EditableFieldCard extends StatelessWidget {
  const _EditableFieldCard({
    super.key,
    required this.label,
    required this.valueText,
    required this.missingText,
    required this.badgeText,
    required this.highlighted,
    required this.onTap,
  });

  final String label;
  final String? valueText;
  final String missingText;
  final String? badgeText;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: highlighted ? AppColors.warningBg : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlighted ? AppColors.warningBorder : AppColors.border,
          width: highlighted ? 1.4 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          label,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        if (badgeText != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.warningBorder),
                            ),
                            child: Text(
                              badgeText!,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.warningText,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      valueText ?? missingText,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: valueText != null ? FontWeight.w600 : FontWeight.w400,
                        fontStyle: valueText != null ? FontStyle.normal : FontStyle.italic,
                        color: valueText != null
                            ? AppColors.inkPrimary
                            : AppColors.inkSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.edit_outlined,
                size: 20,
                color: AppColors.inkSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadbackDialog extends StatefulWidget {
  const _ReadbackDialog({required this.appState, required this.readback});

  final AppState appState;
  final ReadbackResponse readback;

  @override
  State<_ReadbackDialog> createState() => _ReadbackDialogState();
}

class _ReadbackDialogState extends State<_ReadbackDialog> {
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    if (widget.readback.audioUrl != null &&
        widget.readback.audioUrl!.isNotEmpty) {
      _play();
    }
  }

  Future<void> _play() async {
    final rawUrl = widget.readback.audioUrl;
    if (rawUrl == null || rawUrl.isEmpty) return;
    setState(() => _playing = true);
    try {
      await widget.appState.audioPlayer.playUrl(
        widget.appState.api.resolveAudioUrl(rawUrl),
      );
    } catch (_) {
      // Text remains visible even if playback fails.
    } finally {
      if (mounted) {
        setState(() => _playing = false);
      }
    }
  }

  @override
  void dispose() {
    widget.appState.audioPlayer.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.appState.strings;
    final hasAudio = widget.readback.audioUrl != null &&
        widget.readback.audioUrl!.isNotEmpty;

    return AlertDialog(
      title: Text(strings.readBack),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.readback.text),
          if (_playing) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.volume_up_rounded,
                  size: 18,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  strings.playingReadback,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryDark,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      actions: [
        if (hasAudio && !_playing)
          TextButton.icon(
            onPressed: _play,
            icon: const Icon(Icons.volume_up_outlined, size: 18),
            label: Text(strings.replayQuestion),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.ok),
        ),
      ],
    );
  }
}
