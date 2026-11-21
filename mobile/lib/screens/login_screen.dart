import 'package:flutter/material.dart';

import '../models/beneficiary.dart';
import '../services/api_client.dart';
import '../state/app_state.dart';
import '../ui/ui.dart';
import '../widgets/language_toggle.dart';
import '../widgets/server_settings_sheet.dart';
import 'privacy_and_data_screen.dart';
import 'supervisor_flagged_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.appState});

  final AppState appState;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final TextEditingController _codeController;
  final TextEditingController _pinController = TextEditingController();
  bool _submitting = false;
  String? _errorText;
  bool _allowSwitchAccount = false;

  @override
  void initState() {
    super.initState();
    final savedCode = widget.appState.lastProfile?.id ??
        widget.appState.selectedProfile?.id ??
        AshaProfile.defaults.first.id;
    _codeController = TextEditingController(text: savedCode);
  }

  @override
  void dispose() {
    _codeController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _errorText = null;
    });

    try {
      await widget.appState.signInWithPin(
        workerCode: _codeController.text,
        pin: _pinController.text,
      );
      if (mounted) {
        _pinController.clear();
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = widget.appState.strings.friendlyError(e.code, e.message);
      });
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  void _selectDemoWorker(AshaProfile profile) {
    setState(() {
      _codeController.text = profile.id;
      _errorText = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.appState,
      builder: (context, _) {
        final strings = widget.appState.strings;
        final tokens = AppTokens.of(context);
        final lockedProfile =
            widget.appState.isLocked && !_allowSwitchAccount
                ? widget.appState.lastProfile
                : null;

        return AppScaffold(
          body: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - AppSpacing.xl,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.sm,
                            children: [
                              IconButton(
                                onPressed: () => showServerSettingsSheet(
                                  context,
                                  widget.appState,
                                ),
                                icon: Icon(
                                  Icons.tune_rounded,
                                  size: AppSizes.icon,
                                  color: tokens.inkMuted,
                                ),
                                tooltip: strings.serverSettings,
                                constraints: const BoxConstraints(
                                  minWidth: AppSizes.minTouchTarget,
                                  minHeight: AppSizes.minTouchTarget,
                                ),
                              ),
                              LanguageToggle(
                                selected: widget.appState.language,
                                onChanged: widget.appState.setLanguage,
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                width: AppSizes.minTouchTarget,
                                height: AppSizes.minTouchTarget,
                                decoration: BoxDecoration(
                                  color: tokens.primaryContainer,
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.card),
                                ),
                                child: Icon(
                                  Icons.graphic_eq_rounded,
                                  size: AppSizes.icon,
                                  color: tokens.primary,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      strings.appTitle,
                                      style: AppTypography.display(tokens.ink),
                                    ),
                                    Text(
                                      strings.appSubtitle,
                                      style: AppTypography.labelRegular(
                                        tokens.inkMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.xs,
                            children: [
                              SecurityChip(
                                label: widget.appState.hasOfflineCredentials
                                    ? strings.pinLockOfflineChip
                                    : strings.pinLockChip,
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => PrivacyAndDataScreen(
                                        appState: widget.appState,
                                      ),
                                    ),
                                  );
                                },
                              ),
                              if (widget.appState.isLocalDbEncrypted)
                                SecurityChip(
                                  label: strings.encryptedOnDeviceChip,
                                  icon: Icons.enhanced_encryption_outlined,
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => PrivacyAndDataScreen(
                                          appState: widget.appState,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          if (lockedProfile != null) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(AppSpacing.md),
                              decoration: BoxDecoration(
                                color: tokens.surfaceRaised,
                                borderRadius:
                                    BorderRadius.circular(AppRadius.card),
                                border: Border.all(
                                  color: tokens.outline,
                                  width: AppSizes.borderWidth,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          lockedProfile.name,
                                          style: AppTypography.bodySemiBold(
                                            tokens.ink,
                                          ),
                                        ),
                                        Text(
                                          '${lockedProfile.id} · ${lockedProfile.area}',
                                          style: AppTypography.labelRegular(
                                            tokens.inkMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  TextAction(
                                    label: strings.switchAccountAction,
                                    onPressed: () {
                                      setState(() {
                                        _allowSwitchAccount = true;
                                        _errorText = null;
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                          ] else ...[
                            Text(
                              strings.workerCodeLabel,
                              style: AppTypography.label(tokens.ink),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            TextField(
                              key: const ValueKey('worker_code_field'),
                              controller: _codeController,
                              textInputAction: TextInputAction.next,
                              autocorrect: false,
                              decoration: InputDecoration(
                                hintText: strings.workerCodeHint,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Wrap(
                              spacing: AppSpacing.sm,
                              runSpacing: AppSpacing.xs,
                              children: AshaProfile.defaults.map((profile) {
                                final selected =
                                    _codeController.text.trim() == profile.id;
                                return ChoiceChip(
                                  label: Text(
                                    '${profile.name} (${profile.id})',
                                    style: AppTypography.labelRegular(
                                      selected ? tokens.primary : tokens.ink,
                                    ),
                                  ),
                                  selected: selected,
                                  selectedColor: tokens.primaryContainer,
                                  backgroundColor: tokens.surfaceRaised,
                                  side: BorderSide(color: tokens.outline),
                                  onSelected: (_) => _selectDemoWorker(profile),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                          ],
                          Text(
                            strings.pinLabel,
                            style: AppTypography.label(tokens.ink),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          TextField(
                            key: const ValueKey('pin_field'),
                            controller: _pinController,
                            obscureText: true,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _submit(),
                            decoration: InputDecoration(
                              hintText: strings.pinHint,
                              errorText: _errorText,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          PrimaryButton(
                            label: lockedProfile != null
                                ? strings.unlockAction
                                : strings.signInAction,
                            icon: Icons.lock_open_rounded,
                            loading: _submitting,
                            onPressed: _submit,
                          ),
                          if (lockedProfile != null &&
                              widget.appState.biometricEnabled &&
                              widget.appState.biometricAvailable) ...[
                            const SizedBox(height: AppSpacing.sm),
                            SecondaryButton(
                              label: strings.unlockWithBiometricAction,
                              icon: Icons.fingerprint_rounded,
                              onPressed: _submitting
                                  ? null
                                  : () async {
                                      final ok = await widget.appState
                                          .unlockWithBiometric(
                                        reason: strings.biometricReason,
                                      );
                                      if (!ok && mounted) {
                                        setState(() {
                                          _errorText = strings.friendlyError(
                                            'INVALID_CREDENTIALS',
                                          );
                                        });
                                      }
                                    },
                            ),
                          ],
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            strings.demoPinHint,
                            style: AppTypography.caption(tokens.inkMuted),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xl),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextAction(
                              label: strings.openSupervisorView,
                              icon: Icons.health_and_safety_outlined,
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => SupervisorFlaggedScreen(
                                      appState: widget.appState,
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              strings.demoConsentNotice,
                              style: AppTypography.caption(tokens.inkMuted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
