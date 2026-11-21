import 'package:flutter/material.dart';

import '../models/beneficiary.dart';
import '../services/api_client.dart';
import '../state/app_state.dart';
import '../ui/ui.dart';
import 'add_beneficiary_screen.dart';
import 'beneficiary_profile_screen.dart';

enum _BeneficiaryFilter { all, pregnantWoman, newborn, child, other }

/// Beneficiaries tab with search, type/risk filters, Add Beneficiary, and profile launch (SPEC_V2 §3.3).
class BeneficiaryListScreen extends StatefulWidget {
  const BeneficiaryListScreen({
    super.key,
    required this.appState,
    required this.onVisitSaved,
  });

  final AppState appState;
  final VoidCallback onVisitSaved;

  @override
  State<BeneficiaryListScreen> createState() => _BeneficiaryListScreenState();
}

class _BeneficiaryListScreenState extends State<BeneficiaryListScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Beneficiary> _items = const [];
  bool _loading = true;
  bool _isOfflineCached = false;
  String? _errorText;
  String _query = '';
  _BeneficiaryFilter _selectedFilter = _BeneficiaryFilter.all;
  bool _highRiskOnly = false;
  String? _loadedForAsha;
  String? _loadedForUrl;

  @override
  void initState() {
    super.initState();
    widget.appState.addListener(_onAppStateChanged);
    _load();
  }

  @override
  void dispose() {
    widget.appState.removeListener(_onAppStateChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onAppStateChanged() {
    final currentAsha = widget.appState.selectedProfile?.id;
    final currentUrl = widget.appState.baseUrl;
    if (currentAsha != _loadedForAsha || currentUrl != _loadedForUrl) {
      _load();
    }
  }

  List<Beneficiary> _mergeRemoteAndLocal(
    List<Beneficiary> remote,
    List<Beneficiary> localOnlyV2,
  ) {
    final seenCodes = remote.map((b) => b.id).toSet();
    final merged = List<Beneficiary>.of(remote);
    for (final item in localOnlyV2) {
      if (!seenCodes.contains(item.id)) {
        merged.add(item);
      }
    }
    return merged;
  }

  Future<void> _load() async {
    final ashaId = widget.appState.selectedProfile?.id;
    if (ashaId == null) return;

    setState(() {
      _loading = true;
      _errorText = null;
      _isOfflineCached = false;
      _loadedForAsha = ashaId;
      _loadedForUrl = widget.appState.baseUrl;
    });

    final localRecords = await widget.appState.localDb.getBeneficiariesV2(ashaId);
    final localConverted = localRecords
        .where((r) => !r.id.startsWith('legacy_'))
        .map((r) => Beneficiary.fromV2Record(r, localOnly: true))
        .toList();

    try {
      final list = await widget.appState.api.getBeneficiaries(ashaId);
      await widget.appState.localDb.cacheBeneficiaries(ashaId, list);
      if (!mounted) return;
      setState(() {
        _items = _mergeRemoteAndLocal(list, localConverted);
        _isOfflineCached = false;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (e.code == 'NETWORK_ERROR' || e.code == 'TIMEOUT') {
        final cached =
            await widget.appState.localDb.getCachedBeneficiaries(ashaId);
        final combined = _mergeRemoteAndLocal(cached, localConverted);
        if (!mounted) return;
        if (combined.isNotEmpty) {
          setState(() {
            _items = combined;
            _isOfflineCached = true;
            _errorText = null;
            _loading = false;
          });
          return;
        }
      }
      if (!mounted) return;
      setState(() {
        _errorText = widget.appState.strings.friendlyError(e.code, e.message);
        _loading = false;
      });
    }
  }

  Future<void> _openAddBeneficiary() async {
    final created = await Navigator.of(context).push<Beneficiary>(
      MaterialPageRoute<Beneficiary>(
        builder: (_) => AddBeneficiaryScreen(
          appState: widget.appState,
          existingBeneficiaries: _items,
        ),
      ),
    );
    await _load();
    if (created != null) {
      widget.onVisitSaved();
    }
  }

  Future<void> _openProfile(Beneficiary beneficiary) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => BeneficiaryProfileScreen(
          appState: widget.appState,
          beneficiary: beneficiary,
        ),
      ),
    );
    await _load();
    if (changed == true) {
      widget.onVisitSaved();
    }
  }

  bool _matchesFilter(Beneficiary b) {
    if (_highRiskOnly && b.riskLevel != 'high') return false;
    switch (_selectedFilter) {
      case _BeneficiaryFilter.all:
        break;
      case _BeneficiaryFilter.pregnantWoman:
        if (b.beneficiaryType != 'pregnant_woman') return false;
        break;
      case _BeneficiaryFilter.newborn:
        if (b.beneficiaryType != 'newborn') return false;
        break;
      case _BeneficiaryFilter.child:
        if (b.beneficiaryType != 'child_u5') return false;
        break;
      case _BeneficiaryFilter.other:
        if (b.beneficiaryType == 'pregnant_woman' ||
            b.beneficiaryType == 'newborn' ||
            b.beneficiaryType == 'child_u5') {
          return false;
        }
        break;
    }

    final normalized = _query.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    return b.id.toLowerCase().contains(normalized) ||
        b.label.toLowerCase().contains(normalized) ||
        (b.area != null && b.area!.toLowerCase().contains(normalized));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final strings = widget.appState.strings;
    final filtered = _items.where(_matchesFilter).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenHorizontal,
            AppSpacing.md,
            AppSpacing.screenHorizontal,
            AppSpacing.xs,
          ),
          child: TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: strings.searchBeneficiariesHint,
              prefixIcon: Icon(Icons.search_rounded, color: tokens.inkMuted),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                      icon: const Icon(Icons.close_rounded),
                    )
                  : null,
            ),
          ),
        ),
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenHorizontal,
              vertical: AppSpacing.xs,
            ),
            children: [
              _FilterChipItem(
                label: strings.filterAll,
                selected: _selectedFilter == _BeneficiaryFilter.all,
                onTap: () =>
                    setState(() => _selectedFilter = _BeneficiaryFilter.all),
              ),
              const SizedBox(width: AppSpacing.xs),
              _FilterChipItem(
                label: strings.filterPregnant,
                selected: _selectedFilter == _BeneficiaryFilter.pregnantWoman,
                onTap: () => setState(
                  () => _selectedFilter = _BeneficiaryFilter.pregnantWoman,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              _FilterChipItem(
                label: strings.filterNewborns,
                selected: _selectedFilter == _BeneficiaryFilter.newborn,
                onTap: () => setState(
                  () => _selectedFilter = _BeneficiaryFilter.newborn,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              _FilterChipItem(
                label: strings.filterChildren,
                selected: _selectedFilter == _BeneficiaryFilter.child,
                onTap: () =>
                    setState(() => _selectedFilter = _BeneficiaryFilter.child),
              ),
              const SizedBox(width: AppSpacing.xs),
              _FilterChipItem(
                label: strings.filterOthers,
                selected: _selectedFilter == _BeneficiaryFilter.other,
                onTap: () =>
                    setState(() => _selectedFilter = _BeneficiaryFilter.other),
              ),
              const SizedBox(width: AppSpacing.xs),
              FilterChip(
                label: Text(strings.filterHighRisk),
                selected: _highRiskOnly,
                onSelected: (v) => setState(() => _highRiskOnly = v),
              ),
            ],
          ),
        ),
        Expanded(child: _buildBody(filtered)),
      ],
    );
  }

  Widget _buildBody(List<Beneficiary> filtered) {
    final strings = widget.appState.strings;

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.screenHorizontal),
        child: SkeletonLoader(itemCount: 3),
      );
    }

    if (_errorText != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
          child: ErrorState(
            title: strings.connectionFailed,
            message: _errorText!,
            retryLabel: strings.retry,
            onRetry: _load,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenHorizontal,
          AppSpacing.sm,
          AppSpacing.screenHorizontal,
          AppSpacing.xl,
        ),
        children: [
          if (_isOfflineCached) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: RiskBadge(
                label: strings.offlineShowingCached,
                severity: RiskSeverity.info,
                icon: Icons.cloud_off_rounded,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          PrimaryButton(
            label: strings.addBeneficiaryAction,
            icon: Icons.person_add_alt_1_outlined,
            onPressed: _openAddBeneficiary,
          ),
          const SizedBox(height: AppSpacing.md),
          if (filtered.isEmpty)
            EmptyState(
              icon: Icons.people_outline_rounded,
              title: strings.noBeneficiaries,
              message: strings.addBeneficiaryAction,
              actionLabel: strings.addBeneficiaryAction,
              actionIcon: Icons.person_add_alt_1_outlined,
              onAction: _openAddBeneficiary,
            )
          else
            ...filtered.map((beneficiary) {
              final typeLabel =
                  strings.beneficiaryTypeDisplay(beneficiary.beneficiaryType);
              final age = beneficiary.ageSummary();
              final meta = [
                typeLabel,
                if (age.isNotEmpty) age,
                if (beneficiary.area != null && beneficiary.area!.isNotEmpty)
                  beneficiary.area!,
              ].join(' · ');

              RiskSeverity? riskSeverity;
              String? riskLabel;
              if (beneficiary.riskLevel == 'high') {
                riskSeverity = RiskSeverity.high;
                riskLabel = strings.filterHighRisk;
              } else if (beneficiary.riskLevel == 'watch') {
                riskSeverity = RiskSeverity.medium;
                riskLabel = strings.needsAttentionLabel;
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: BeneficiaryTile(
                  name: beneficiary.label,
                  typeAndAge: meta,
                  codeLabel: beneficiary.id,
                  dueLabel: beneficiary.nextDueAt != null
                      ? '${strings.dueTodayLabel}: ${beneficiary.nextDueAt}'
                      : null,
                  riskLabel: riskLabel,
                  riskSeverity: riskSeverity,
                  onTap: () => _openProfile(beneficiary),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _FilterChipItem extends StatelessWidget {
  const _FilterChipItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}
