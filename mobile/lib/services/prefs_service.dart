import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_strings.dart';

class PrefsService {
  PrefsService(this._prefs);

  static const String _keyAshaId = 'asha_id';
  static const String _keyLanguage = 'language_code';
  static const String _keyBaseUrl = 'backend_base_url';

  static const String defaultBaseUrl = 'http://10.0.2.2:8000';

  final SharedPreferences _prefs;

  String? get selectedAshaId => _prefs.getString(_keyAshaId);

  Future<void> setSelectedAshaId(String? id) async {
    if (id == null) {
      await _prefs.remove(_keyAshaId);
    } else {
      await _prefs.setString(_keyAshaId, id);
    }
  }

  AppLanguage get language => AppLanguage.fromCode(_prefs.getString(_keyLanguage));

  Future<void> setLanguage(AppLanguage lang) async {
    await _prefs.setString(_keyLanguage, lang.code);
  }

  String get baseUrl {
    final saved = _prefs.getString(_keyBaseUrl);
    if (saved == null || saved.trim().isEmpty) return defaultBaseUrl;
    return saved.trim();
  }

  Future<void> setBaseUrl(String url) async {
    await _prefs.setString(_keyBaseUrl, url.trim());
  }
}
