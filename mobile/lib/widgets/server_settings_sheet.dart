import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';

Future<void> showServerSettingsSheet(BuildContext context, AppState appState) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _ServerSettingsSheet(appState: appState),
  );
}

class _ServerSettingsSheet extends StatefulWidget {
  const _ServerSettingsSheet({required this.appState});

  final AppState appState;

  @override
  State<_ServerSettingsSheet> createState() => _ServerSettingsSheetState();
}

class _ServerSettingsSheetState extends State<_ServerSettingsSheet> {
  late final TextEditingController _controller;
  bool _testing = false;
  bool? _healthy;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.appState.baseUrl);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _testAndSave({required bool closeAfter}) async {
    final url = _controller.text.trim();
    if (url.isEmpty) return;
    await widget.appState.updateBaseUrl(url);
    if (closeAfter) {
      if (mounted) Navigator.of(context).pop();
      return;
    }

    setState(() {
      _testing = true;
      _healthy = null;
    });
    final ok = await widget.appState.api.checkHealth();
    if (!mounted) return;
    setState(() {
      _testing = false;
      _healthy = ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.appState.strings;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            strings.serverSettings,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: strings.backendUrlLabel,
              hintText: 'https://your-domain.duckdns.org',
            ),
          ),
          if (_healthy != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _healthy! ? AppColors.successBg : AppColors.riskBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    _healthy! ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                    size: 18,
                    color: _healthy! ? AppColors.successText : AppColors.riskText,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _healthy! ? strings.connectionOk : strings.connectionFailed,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: _healthy! ? AppColors.successText : AppColors.riskText,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _testing ? null : () => _testAndSave(closeAfter: false),
                  child: _testing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(strings.testConnection),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => _testAndSave(closeAfter: true),
                  child: Text(strings.save),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
