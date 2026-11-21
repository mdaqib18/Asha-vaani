import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_strings.dart';

class PrefsService {
  PrefsService(this._prefs);

  static const String _keyAshaId = 'asha_id';
  static const String _keyLanguage = 'language_code';
  static const String _keyBaseUrl = 'backend_base_url';
  static const String _keySessionToken = 'session_token';
  static const String _keyPinDigest = 'pin_digest';
  static const String _keyLastWorkerId = 'last_worker_id';
  static const String _keyLastWorkerName = 'last_worker_name';
  static const String _keyLastWorkerArea = 'last_worker_area';
  static const String _keyHighContrast = 'high_contrast_mode';

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

  String? get sessionToken => _prefs.getString(_keySessionToken);

  Future<void> setSessionToken(String? token) async {
    if (token == null || token.isEmpty) {
      await _prefs.remove(_keySessionToken);
    } else {
      await _prefs.setString(_keySessionToken, token);
    }
  }

  String? get pinDigest => _prefs.getString(_keyPinDigest);

  Future<void> setPinDigest(String? digest) async {
    if (digest == null || digest.isEmpty) {
      await _prefs.remove(_keyPinDigest);
    } else {
      await _prefs.setString(_keyPinDigest, digest);
    }
  }

  String? get lastWorkerId => _prefs.getString(_keyLastWorkerId);
  String? get lastWorkerName => _prefs.getString(_keyLastWorkerName);
  String? get lastWorkerArea => _prefs.getString(_keyLastWorkerArea);

  Future<void> setLastWorker({
    required String id,
    required String name,
    required String area,
  }) async {
    await _prefs.setString(_keyLastWorkerId, id);
    await _prefs.setString(_keyLastWorkerName, name);
    await _prefs.setString(_keyLastWorkerArea, area);
  }

  bool get highContrast => _prefs.getBool(_keyHighContrast) ?? false;

  Future<void> setHighContrast(bool enabled) async {
    await _prefs.setBool(_keyHighContrast, enabled);
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
