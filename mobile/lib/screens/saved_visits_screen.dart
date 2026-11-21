import 'package:flutter/material.dart';

import '../models/newborn_visit.dart';
import '../services/api_client.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

class SavedVisitsScreen extends StatefulWidget {
  const SavedVisitsScreen({
    super.key,
    required this.appState,
    required this.refreshSignal,
  });

  final AppState appState;
  final ValueNotifier<int> refreshSignal;

  @override
  State<SavedVisitsScreen> createState() => _SavedVisitsScreenState();
}

class _SavedVisitsScreenState extends State<SavedVisitsScreen> {
  List<VisitSummary> _visits = const [];
  bool _loading = true;
  String? _errorText;
  String? _loadedForAsha;
  String? _loadedForUrl;

  @override
  void initState() {
    super.initState();
    widget.appState.addListener(_onStateChange);
    widget.refreshSignal.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.appState.removeListener(_onStateChange);
    widget.refreshSignal.removeListener(_load);
    super.dispose();
  }

  void _onStateChange() {
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
      _loadedForAsha = ashaId;
      _loadedForUrl = widget.appState.baseUrl;
    });

    try {
      final list = await widget.appState.api.getSavedVisits(ashaId);
      if (!mounted) return;
      setState(() {
        _visits = list;
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
            const SizedBox(height: 120),
            const Icon(
              Icons.fact_check_outlined,
              size: 48,
              color: AppColors.inkSecondary,
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                strings.noSavedVisits,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        itemCount: _visits.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final visit = _visits[index];
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.primaryTint,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          visit.beneficiaryId ?? '—',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.primaryDark,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          visit.visitDate ?? '',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.successBg,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          strings.syncedBadge,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.successText,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (visit.referralSuggested || visit.riskFlags.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.riskBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.riskBorder.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.medical_services_outlined,
                            size: 15,
                            color: AppColors.riskText,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            strings.consultChip,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.riskText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
