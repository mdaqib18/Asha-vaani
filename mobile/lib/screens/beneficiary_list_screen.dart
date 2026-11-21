import 'package:flutter/material.dart';

import '../models/beneficiary.dart';
import '../services/api_client.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'record_visit_screen.dart';

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

    try {
      final list = await widget.appState.api.getBeneficiaries(ashaId);
      await widget.appState.localDb.cacheBeneficiaries(ashaId, list);
      if (!mounted) return;
      setState(() {
        _items = list;
        _isOfflineCached = false;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (e.code == 'NETWORK_ERROR' || e.code == 'TIMEOUT') {
        final cached = await widget.appState.localDb.getCachedBeneficiaries(ashaId);
        if (!mounted) return;
        if (cached.isNotEmpty) {
          setState(() {
            _items = cached;
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

  Future<void> _openVisit(Beneficiary beneficiary) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => RecordVisitScreen(
          appState: widget.appState,
          beneficiary: beneficiary,
        ),
      ),
    );
    if (saved == true) {
      widget.onVisitSaved();
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.appState.strings;
    final normalized = _query.trim().toLowerCase();
    final filtered = normalized.isEmpty
        ? _items
        : _items
            .where(
              (b) =>
                  b.id.toLowerCase().contains(normalized) ||
                  b.label.toLowerCase().contains(normalized),
            )
            .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: strings.searchBeneficiariesHint,
              prefixIcon: const Icon(Icons.search_rounded, color: AppColors.inkSecondary),
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
        Expanded(
          child: Column(
            children: [
              if (_isOfflineCached)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceSubtle,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.cloud_off_rounded,
                          size: 16,
                          color: AppColors.inkSecondary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            strings.offlineShowingCached,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.inkSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Expanded(child: _buildBody(filtered)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBody(List<Beneficiary> filtered) {
    final strings = widget.appState.strings;

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
              const Icon(Icons.cloud_off_rounded, size: 42, color: AppColors.inkSecondary),
              const SizedBox(height: 12),
              Text(
                _errorText!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
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

    if (filtered.isEmpty) {
      return Center(
        child: Text(
          strings.noBeneficiaries,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        itemCount: filtered.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final beneficiary = filtered[index];
          return Card(
            child: InkWell(
              onTap: () => _openVisit(beneficiary),
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.primaryTint,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        beneficiary.id,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: AppColors.primaryDark,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        beneficiary.label,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    const Icon(
                      Icons.mic_none_rounded,
                      color: AppColors.primary,
                      size: 22,
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.inkSecondary,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
