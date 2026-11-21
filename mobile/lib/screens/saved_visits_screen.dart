import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../models/newborn_visit.dart';
import '../services/api_client.dart';
import '../services/local_db_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'review_confirm_screen.dart';

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
  List<QueuedAudioItem> _pendingQueue = const [];
  List<LocalDraft> _drafts = const [];
  List<VisitSummary> _visits = const [];
  bool _loading = true;
  bool _isOffline = false;
  String? _errorText;
  String? _loadedForAsha;
  String? _loadedForUrl;

  @override
  void initState() {
    super.initState();
    widget.appState.addListener(_onStateChange);
    widget.appState.syncService.addListener(_load);
    widget.refreshSignal.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.appState.removeListener(_onStateChange);
    widget.appState.syncService.removeListener(_load);
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
      _loading = _pendingQueue.isEmpty && _drafts.isEmpty && _visits.isEmpty;
      _errorText = null;
      _loadedForAsha = ashaId;
      _loadedForUrl = widget.appState.baseUrl;
    });

    final pending = await widget.appState.localDb.getPendingQueue(ashaId: ashaId);
    final drafts = await widget.appState.localDb.getDrafts(ashaId: ashaId);

    List<VisitSummary> visits = const [];
    var offline = false;
    String? error;

    try {
      visits = await widget.appState.api.getSavedVisits(ashaId);
      await widget.appState.localDb.cacheVisits(ashaId, visits);
    } on ApiException catch (e) {
      if (e.code == 'NETWORK_ERROR' || e.code == 'TIMEOUT') {
        offline = true;
        visits = await widget.appState.localDb.getCachedVisits(ashaId);
      } else if (pending.isEmpty && drafts.isEmpty) {
        error = widget.appState.strings.friendlyError(e.code, e.message);
      }
    }

    if (!mounted) return;
    setState(() {
      _pendingQueue = pending;
      _drafts = drafts;
      _visits = visits;
      _isOffline = offline;
      _errorText = error;
      _loading = false;
    });
  }

  Future<void> _openDraft(LocalDraft draft) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ReviewConfirmScreen(
          appState: widget.appState,
          initialTurn: draft.turn,
        ),
      ),
    );
    if (saved == true) {
      await _load();
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

    final isSyncing = widget.appState.syncService.isSyncing;
    final hasAnyItems =
        _pendingQueue.isNotEmpty || _drafts.isNotEmpty || _visits.isNotEmpty;

    return RefreshIndicator(
      onRefresh: () async {
        await widget.appState.syncService.syncPending();
        await _load();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        children: [
          if (_pendingQueue.isNotEmpty || isSyncing) ...[
            _SyncStatusBanner(
              text: isSyncing
                  ? strings.syncing
                  : strings.pendingSyncBanner(_pendingQueue.length),
              isSyncing: isSyncing,
              buttonLabel: strings.syncNow,
              onSyncNow: () => widget.appState.syncService.syncPending(),
            ),
            const SizedBox(height: 10),
          ],
          if (_isOffline) ...[
            Container(
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
            const SizedBox(height: 10),
          ],
          if (!hasAnyItems) ...[
            const SizedBox(height: 100),
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
          ..._pendingQueue.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _PendingQueueCard(item: item, strings: strings),
            ),
          ),
          ..._drafts.map(
            (draft) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ReadyDraftCard(
                draft: draft,
                strings: strings,
                onTap: () => _openDraft(draft),
              ),
            ),
          ),
          ..._visits.map(
            (visit) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _SyncedVisitCard(visit: visit, strings: strings),
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncStatusBanner extends StatelessWidget {
  const _SyncStatusBanner({
    required this.text,
    required this.isSyncing,
    required this.buttonLabel,
    required this.onSyncNow,
  });

  final String text;
  final bool isSyncing;
  final String buttonLabel;
  final VoidCallback onSyncNow;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warningBorder),
      ),
      child: Row(
        children: [
          if (isSyncing)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            const Icon(Icons.sync_rounded, color: AppColors.warningText, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.warningText,
              ),
            ),
          ),
          if (!isSyncing)
            TextButton(
              onPressed: onSyncNow,
              child: Text(buttonLabel),
            ),
        ],
      ),
    );
  }
}

class _PendingQueueCard extends StatelessWidget {
  const _PendingQueueCard({required this.item, required this.strings});

  final QueuedAudioItem item;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.primaryTint,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                item.beneficiaryId,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryDark,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.beneficiaryLabel,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (item.lastError != null && item.lastError!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.lastError!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.riskText,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.warningBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.warningBorder),
              ),
              child: Text(
                strings.pendingBadge,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.warningText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadyDraftCard extends StatelessWidget {
  const _ReadyDraftCard({
    required this.draft,
    required this.strings,
    required this.onTap,
  });

  final LocalDraft draft;
  final AppStrings strings;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.primaryTint,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  draft.beneficiaryId,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  draft.turn.transcript,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primaryTint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  strings.readyToReviewBadge,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded, color: AppColors.inkSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _SyncedVisitCard extends StatelessWidget {
  const _SyncedVisitCard({required this.visit, required this.strings});

  final VisitSummary visit;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
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
  }
}
