import 'dart:io';

import 'package:flutter/material.dart';

import '../models/beneficiary.dart';
import '../models/v2_models.dart';
import '../services/api_client.dart';
import '../services/audio_recorder_service.dart';
import '../services/due_engine.dart';
import '../services/duplicate_detector.dart';
import '../services/local_code_generator.dart';
import '../state/app_state.dart';
import '../ui/ui.dart';
import '../widgets/language_toggle.dart';
import 'beneficiary_profile_screen.dart';
import 'visit_purpose_picker_screen.dart';

/// 3-step Add Beneficiary + Speak-to-Add screen with consent and duplicate screening (SPEC_V2 §3.4).
class AddBeneficiaryScreen extends StatefulWidget {
  const AddBeneficiaryScreen({
    super.key,
    required this.appState,
    this.existingBeneficiaries = const [],
  });

  final AppState appState;
  final List<Beneficiary> existingBeneficiaries;

  @override
  State<AddBeneficiaryScreen> createState() => _AddBeneficiaryScreenState();
}

class _AddBeneficiaryScreenState extends State<AddBeneficiaryScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _dobController = TextEditingController();
  final TextEditingController _ageYearsController = TextEditingController();
  final TextEditingController _areaController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _monthsPregnantController =
      TextEditingController();

  String _beneficiaryType = 'pregnant_woman';
  String _sex = 'female';
  bool _ageEstimated = false;
  String? _motherId;
  bool _consentGiven = false;
  final String _consentGivenBy = 'self';
  String _consentMethod = 'verbal';

  bool _recording = false;
  bool _extracting = false;
  String? _activeRecordingPath;
  String? _spokenTranscript;
  String? _voiceError;

  bool _saving = false;
  String? _formError;
  List<DuplicateMatchItem> _duplicateMatches = const [];
  bool _duplicateCheckBypassed = false;
  Beneficiary? _savedBeneficiary;

  @override
  void dispose() {
    _nameController.dispose();
    _dobController.dispose();
    _ageYearsController.dispose();
    _areaController.dispose();
    _phoneController.dispose();
    _monthsPregnantController.dispose();
    super.dispose();
  }

  String? _computedLmpIso() {
    if (_beneficiaryType != 'pregnant_woman') return null;
    final months = int.tryParse(_monthsPregnantController.text.trim());
    if (months == null || months < 1 || months > 10) return null;
    final lmp = DateTime.now().subtract(Duration(days: months * 30));
    return DueEngine.formatIsoDate(lmp);
  }

  String? _computedEddIso() {
    final lmpStr = _computedLmpIso();
    final parsed = DueEngine.parseIsoDate(lmpStr);
    if (parsed == null) return null;
    return DueEngine.formatIsoDate(DueEngine.computeEdd(parsed));
  }

  String? _resolvedDobIso() {
    final manual = _dobController.text.trim();
    if (manual.isNotEmpty) return manual;
    final years = int.tryParse(_ageYearsController.text.trim());
    if (years != null && years > 0 && years < 120) {
      final now = DateTime.now();
      return DueEngine.formatIsoDate(
        DateTime.utc(now.year - years, now.month, now.day),
      );
    }
    return null;
  }

  Future<void> _toggleVoiceCapture() async {
    if (_extracting || _saving) return;
    if (_recording) {
      await _finishVoiceCapture();
    } else {
      await _startVoiceCapture();
    }
  }

  Future<void> _startVoiceCapture() async {
    final perm = await widget.appState.recorder.ensurePermission();
    if (perm != MicPermissionState.granted) {
      if (!mounted) return;
      setState(() => _voiceError = widget.appState.strings.micPermissionNeeded);
      return;
    }
    final path = await widget.appState.recorder.createTempWavPath();
    await widget.appState.recorder.startRecording(path);
    if (!mounted) return;
    setState(() {
      _activeRecordingPath = path;
      _recording = true;
      _voiceError = null;
    });
  }

  Future<void> _finishVoiceCapture() async {
    if (!_recording) return;
    setState(() {
      _recording = false;
      _extracting = true;
      _voiceError = null;
    });

    final stoppedPath = await widget.appState.recorder.stopRecording();
    final path = stoppedPath ?? _activeRecordingPath;
    if (path == null) {
      if (!mounted) return;
      setState(() => _extracting = false);
      return;
    }

    final workerId = widget.appState.selectedProfile?.id ?? 'asha_001';
    try {
      final extracted = await widget.appState.api.extractBeneficiaryFromAudio(
        filePath: path,
        language: widget.appState.language.code,
        workerId: workerId,
      );
      if (!mounted) return;
      final draft = extracted.draft;
      setState(() {
        _spokenTranscript = extracted.transcript;
        if (draft.fullName.isNotEmpty) _nameController.text = draft.fullName;
        _beneficiaryType = draft.beneficiaryType;
        _sex = draft.sex;
        if (draft.dob != null) _dobController.text = draft.dob!;
        if (draft.ageYears != null) {
          _ageYearsController.text = '${draft.ageYears}';
        }
        _ageEstimated = draft.dobIsEstimated;
        if (draft.pregnancyMonths != null) {
          _monthsPregnantController.text = '${draft.pregnancyMonths}';
        }
        if (draft.areaNote != null && draft.areaNote!.isNotEmpty) {
          _areaController.text = draft.areaNote!;
        }
        if (draft.phone != null && draft.phone!.isNotEmpty) {
          _phoneController.text = draft.phone!;
        }
        _duplicateMatches = extracted.duplicateCandidates;
        _extracting = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _extracting = false;
        _voiceError = widget.appState.strings.friendlyError(e.code, e.message);
      });
    } finally {
      try {
        final f = File(path);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
  }

  Future<List<DuplicateMatchItem>> _runDuplicateCheck(
    String workerId,
    String fullName,
    String? dobIso,
    String? phone,
  ) async {
    try {
      return await widget.appState.api.checkDuplicateBeneficiary(
        workerId: workerId,
        fullName: fullName,
        dob: dobIso,
        phone: phone,
      );
    } on ApiException catch (e) {
      if (e.code != 'NETWORK_ERROR' && e.code != 'TIMEOUT') rethrow;
      final localRows =
          await widget.appState.localDb.getBeneficiariesV2(workerId);
      final matches = DuplicateDetector.findCandidates(
        fullName: fullName,
        workerId: workerId,
        dob: dobIso,
        phoneEnc: phone,
        existing: localRows,
      );
      return matches
          .map(
            (m) => DuplicateMatchItem(
              beneficiaryId: m.beneficiary.id,
              localCode: m.beneficiary.localCode,
              fullName: m.beneficiary.fullName,
              dob: m.beneficiary.dob,
              score: m.score,
              reasons: m.reasons,
            ),
          )
          .toList();
    }
  }

  Future<void> _submit({bool ignoreDuplicates = false}) async {
    final strings = widget.appState.strings;
    final fullName = _nameController.text.trim();
    if (fullName.isEmpty) {
      setState(() => _formError = strings.missingTag);
      return;
    }
    if (!_consentGiven) {
      setState(() => _formError = strings.consentRequiredError);
      return;
    }

    final workerId = widget.appState.selectedProfile?.id ?? 'asha_001';
    final dobIso = _resolvedDobIso();
    final phone = _phoneController.text.trim();
    final areaNote = _areaController.text.trim();
    final lmpIso = _computedLmpIso();
    final pregMonths = int.tryParse(_monthsPregnantController.text.trim());

    setState(() {
      _saving = true;
      _formError = null;
    });

    if (!ignoreDuplicates && !_duplicateCheckBypassed) {
      try {
        final matches = await _runDuplicateCheck(
          workerId,
          fullName,
          dobIso,
          phone.isEmpty ? null : phone,
        );
        if (!mounted) return;
        if (matches.isNotEmpty) {
          setState(() {
            _duplicateMatches = matches;
            _saving = false;
          });
          return;
        }
      } catch (_) {
        // Proceed if duplicate screening endpoint fails unexpectedly.
      }
    }

    final uuid = UuidV4.generate();
    final existingCodes = widget.existingBeneficiaries.map((b) => b.id);
    final offlineCode = LocalCodeGenerator.nextCode(existingCodes: existingCodes);
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final eddIso = _computedEddIso();

    Beneficiary? saved;
    try {
      saved = await widget.appState.api.createBeneficiary(
        BeneficiaryCreatePayload(
          workerId: workerId,
          fullName: fullName,
          beneficiaryType: _beneficiaryType,
          sex: _sex,
          dob: dobIso,
          dobIsEstimated: _ageEstimated || _dobController.text.trim().isEmpty,
          areaNote: areaNote.isEmpty ? null : areaNote,
          motherId: _beneficiaryType == 'newborn' ? _motherId : null,
          phone: phone.isEmpty ? null : phone,
          lmpDate: lmpIso,
          pregnancyMonths:
              _beneficiaryType == 'pregnant_woman' ? pregMonths : null,
          consentGiven: true,
          consentGivenBy: _consentGivenBy,
          consentMethod: _consentMethod,
          beneficiaryUuid: uuid,
        ),
      );
    } on ApiException catch (e) {
      if (e.code != 'NETWORK_ERROR' && e.code != 'TIMEOUT') {
        if (!mounted) return;
        setState(() {
          _saving = false;
          _formError = strings.friendlyError(e.code, e.message);
        });
        return;
      }

      // Offline-first save to local encrypted/SQLite V2 store + sync queue
      final consentId = UuidV4.generate();
      final record = BeneficiaryRecord(
        id: uuid,
        localCode: offlineCode,
        workerId: workerId,
        areaId: areaNote.isEmpty ? null : areaNote,
        fullName: fullName,
        sex: _sex,
        dob: dobIso,
        dobIsEstimated: _ageEstimated || _dobController.text.trim().isEmpty,
        beneficiaryType: _beneficiaryType,
        motherId: _beneficiaryType == 'newborn' ? _motherId : null,
        phoneEnc: phone.isEmpty ? null : phone,
        consentId: consentId,
        createdAt: nowIso,
        updatedAt: nowIso,
      );
      await widget.appState.localDb.upsertBeneficiaryV2(
        record,
        consent: ConsentRecord(
          id: consentId,
          beneficiaryId: uuid,
          givenBy: _consentGivenBy,
          method: _consentMethod,
          givenAt: nowIso,
        ),
        pregnancy: _beneficiaryType == 'pregnant_woman' && lmpIso != null
            ? PregnancyRecord(
                id: UuidV4.generate(),
                beneficiaryId: uuid,
                lmpDate: lmpIso,
                eddDate: eddIso,
                createdAt: nowIso,
                updatedAt: nowIso,
              )
            : null,
        actorId: workerId,
      );
      await widget.appState.localDb.enqueueSyncV2(
        SyncQueueEntry(
          id: UuidV4.generate(),
          entity: 'beneficiary',
          entityId: uuid,
          op: 'create',
          createdAt: nowIso,
        ),
      );
      saved = Beneficiary.fromV2Record(
        record,
        eddDate: eddIso,
        localOnly: true,
      );
    }

    if (!mounted) return;
    setState(() {
      _saving = false;
      _savedBeneficiary = saved;
    });
  }

  Future<void> _openExistingDuplicate(DuplicateMatchItem dup) async {
    final matched = widget.existingBeneficiaries.firstWhere(
      (b) => b.id == dup.localCode || b.uuid == dup.beneficiaryId,
      orElse: () => Beneficiary(
        id: dup.localCode,
        label: dup.fullName,
        uuid: dup.beneficiaryId,
        dob: dup.dob,
      ),
    );
    await Navigator.of(context).push(
      MaterialPageRoute<bool>(
        builder: (_) => BeneficiaryProfileScreen(
          appState: widget.appState,
          beneficiary: matched,
        ),
      ),
    );
  }

  Future<void> _recordFirstVisit() async {
    final saved = _savedBeneficiary;
    if (saved == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<bool>(
        builder: (_) => VisitPurposePickerScreen(
          appState: widget.appState,
          beneficiary: saved,
          beneficiaryType: saved.beneficiaryType,
          dobIso: saved.dob,
        ),
      ),
    );
    if (mounted) {
      Navigator.of(context).pop(saved);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.appState,
      builder: (context, _) {
        final tokens = AppTokens.of(context);
        final strings = widget.appState.strings;

        if (_savedBeneficiary != null) {
          final saved = _savedBeneficiary!;
          return AppScaffold(
            title: strings.beneficiarySavedTitle,
            body: ListView(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
              children: [
                EmptyState(
                  icon: Icons.check_circle_outline_rounded,
                  title: strings.beneficiarySavedTitle,
                  message:
                      '${saved.label} (#${saved.id})${saved.eddDate != null ? ' · EDD ${saved.eddDate}' : ''}',
                  actionLabel: strings.recordFirstVisitNowAction,
                  actionIcon: Icons.mic_rounded,
                  onAction: _recordFirstVisit,
                ),
                const SizedBox(height: AppSpacing.md),
                SecondaryButton(
                  label: strings.done,
                  icon: Icons.check_rounded,
                  onPressed: () => Navigator.of(context).pop(saved),
                ),
              ],
            ),
          );
        }

        final eddPreview = _computedEddIso();
        final mothers = widget.existingBeneficiaries
            .where(
              (b) =>
                  b.beneficiaryType == 'pregnant_woman' ||
                  b.beneficiaryType == 'pnc_mother' ||
                  b.sex == 'female',
            )
            .toList();

        return AppScaffold(
          title: strings.addBeneficiaryAction,
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
              // Recommended Speak-to-Add Card
              Container(
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
                    SectionHeader(
                      title: strings.speakToAddTitle,
                      subtitle: strings.speakToAddHint,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Center(
                      child: MicButton(
                        key: const ValueKey('speak_to_add_mic'),
                        state: _extracting
                            ? MicButtonState.processing
                            : (_recording
                                ? MicButtonState.listening
                                : MicButtonState.ready),
                        label: _extracting
                            ? strings.statusProcessing
                            : (_recording
                                ? strings.statusListening
                                : strings.holdToSpeak),
                        onTap: _toggleVoiceCapture,
                        onHoldStart: _startVoiceCapture,
                        onHoldEnd: _finishVoiceCapture,
                      ),
                    ),
                    if (_spokenTranscript != null &&
                        _spokenTranscript!.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.md),
                      LiveTranscript(
                        finalizedText: _spokenTranscript!,
                      ),
                    ],
                    if (_voiceError != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        _voiceError!,
                        style: AppTypography.label(tokens.riskHigh),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),

              // Step 1: Who
              SectionHeader(title: strings.beneficiaryWhoStep),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                key: const ValueKey('add_ben_name'),
                controller: _nameController,
                decoration: InputDecoration(labelText: strings.fullNameLabel),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                strings.beneficiaryTypeLabel,
                style: AppTypography.label(tokens.inkMuted),
              ),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final btype in const [
                    'pregnant_woman',
                    'newborn',
                    'child_u5',
                    'adult',
                    'other',
                  ])
                    ChoiceChip(
                      label: Text(strings.beneficiaryTypeDisplay(btype)),
                      selected: _beneficiaryType == btype,
                      onSelected: (_) {
                        setState(() {
                          _beneficiaryType = btype;
                          if (btype == 'pregnant_woman') _sex = 'female';
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(strings.sexLabel, style: AppTypography.label(tokens.inkMuted)),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  ChoiceChip(
                    label: Text(strings.sexFemale),
                    selected: _sex == 'female',
                    onSelected: (_) => setState(() => _sex = 'female'),
                  ),
                  ChoiceChip(
                    label: Text(strings.sexMale),
                    selected: _sex == 'male',
                    onSelected: (_) => setState(() => _sex = 'male'),
                  ),
                  ChoiceChip(
                    label: Text(strings.sexUnknown),
                    selected: _sex == 'unknown',
                    onSelected: (_) => setState(() => _sex = 'unknown'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                key: const ValueKey('add_ben_dob'),
                controller: _dobController,
                decoration: InputDecoration(labelText: strings.dobLabel),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                key: const ValueKey('add_ben_age'),
                controller: _ageYearsController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: strings.ageYearsLabel),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  strings.ageEstimatedFlag,
                  style: AppTypography.body(tokens.ink),
                ),
                value: _ageEstimated,
                onChanged: (v) => setState(() => _ageEstimated = v ?? false),
              ),

              const SizedBox(height: AppSpacing.lg),

              // Step 2: Where & Details by type
              SectionHeader(title: strings.beneficiaryWhereStep),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                key: const ValueKey('add_ben_area'),
                controller: _areaController,
                decoration: InputDecoration(labelText: strings.areaVillageLabel),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                key: const ValueKey('add_ben_phone'),
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: strings.phoneOptionalLabel,
                ),
              ),
              if (_beneficiaryType == 'pregnant_woman') ...[
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  key: const ValueKey('add_ben_preg_months'),
                  controller: _monthsPregnantController,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: strings.monthsPregnantLabel,
                  ),
                ),
                if (eddPreview != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: RiskBadge(
                      label: strings.computedEddBanner(eddPreview),
                      severity: RiskSeverity.ok,
                      icon: Icons.calendar_today_outlined,
                    ),
                  ),
                ],
              ],
              if (_beneficiaryType == 'newborn' && mothers.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<String>(
                  initialValue: _motherId,
                  decoration: InputDecoration(labelText: strings.linkMotherLabel),
                  items: [
                    for (final m in mothers)
                      DropdownMenuItem(
                        value: m.uuid ?? m.id,
                        child: Text('${m.label} (#${m.id})'),
                      ),
                  ],
                  onChanged: (val) => setState(() => _motherId = val),
                ),
              ],

              const SizedBox(height: AppSpacing.xl),

              // Step 3: Consent & Duplicate Check
              SectionHeader(title: strings.beneficiaryConsentStep),
              const SizedBox(height: AppSpacing.xs),
              CheckboxListTile(
                key: const ValueKey('add_ben_consent_checkbox'),
                contentPadding: EdgeInsets.zero,
                value: _consentGiven,
                onChanged: (v) => setState(() {
                  _consentGiven = v ?? false;
                  _formError = null;
                }),
                title: Text(
                  strings.consentRequiredCheckbox,
                  style: AppTypography.body(tokens.ink),
                ),
              ),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  ChoiceChip(
                    label: Text(strings.consentMethodVerbal),
                    selected: _consentMethod == 'verbal',
                    onSelected: (_) =>
                        setState(() => _consentMethod = 'verbal'),
                  ),
                  ChoiceChip(
                    label: Text(strings.consentMethodSigned),
                    selected: _consentMethod == 'signed',
                    onSelected: (_) =>
                        setState(() => _consentMethod = 'signed'),
                  ),
                ],
              ),

              if (_duplicateMatches.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                Container(
                  key: const ValueKey('duplicate_match_card'),
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: tokens.riskMediumContainer,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(
                      color: tokens.riskMedium,
                      width: AppSizes.borderWidth,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      RiskBadge(
                        label: strings.possibleDuplicateTitle,
                        severity: RiskSeverity.medium,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      for (final dup in _duplicateMatches) ...[
                        Text(
                          '${dup.fullName} (#${dup.localCode})${dup.dob != null ? ' · ${dup.dob}' : ''}',
                          style: AppTypography.bodySemiBold(tokens.ink),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextAction(
                            label: strings.openExistingPersonAction,
                            onPressed: () => _openExistingDuplicate(dup),
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xs),
                      SecondaryButton(
                        label: strings.saveAsNewPersonAction,
                        icon: Icons.person_add_outlined,
                        onPressed: () {
                          setState(() => _duplicateCheckBypassed = true);
                          _submit(ignoreDuplicates: true);
                        },
                      ),
                    ],
                  ),
                ),
              ],

              if (_formError != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  _formError!,
                  style: AppTypography.label(tokens.riskHigh),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(
                key: const ValueKey('save_beneficiary_button'),
                label: strings.saveBeneficiaryAction,
                icon: Icons.check_rounded,
                loading: _saving,
                onPressed: _saving ? null : () => _submit(),
              ),
            ],
          ),
        );
      },
    );
  }
}
