import 'package:flutter/foundation.dart';

import '../l10n/app_strings.dart';
import '../models/beneficiary.dart';
import '../services/api_client.dart';
import '../services/audio_player_service.dart';
import '../services/audio_recorder_service.dart';
import '../services/prefs_service.dart';

class AppState extends ChangeNotifier {
  AppState({
    PrefsService? prefs,
    AshaApiClient? apiClient,
    AudioCaptureService? recorder,
    AudioPlaybackService? audioPlayer,
    AppLanguage initialLanguage = AppLanguage.hi,
    AshaProfile? initialProfile,
    String initialBaseUrl = PrefsService.defaultBaseUrl,
  })  : _prefs = prefs,
        _language = prefs?.language ?? initialLanguage,
        _selectedProfile = initialProfile ??
            (prefs?.selectedAshaId != null
                ? AshaProfile.byId(prefs!.selectedAshaId)
                : null),
        _baseUrl = prefs?.baseUrl ?? initialBaseUrl,
        _apiClient = apiClient ??
            DioAshaApiClient(baseUrl: prefs?.baseUrl ?? initialBaseUrl),
        _recorder = recorder ?? RecordAudioCaptureService(),
        _audioPlayer = audioPlayer ?? JustAudioPlaybackService();

  final PrefsService? _prefs;
  final AudioCaptureService _recorder;
  final AudioPlaybackService _audioPlayer;

  AppLanguage _language;
  AshaProfile? _selectedProfile;
  String _baseUrl;
  AshaApiClient _apiClient;

  AppLanguage get language => _language;
  AppStrings get strings => AppStrings.of(_language);
  AshaProfile? get selectedProfile => _selectedProfile;
  String get baseUrl => _baseUrl;
  AshaApiClient get api => _apiClient;
  AudioCaptureService get recorder => _recorder;
  AudioPlaybackService get audioPlayer => _audioPlayer;

  Future<void> setLanguage(AppLanguage lang) async {
    if (_language == lang) return;
    _language = lang;
    await _prefs?.setLanguage(lang);
    notifyListeners();
  }

  Future<void> selectProfile(AshaProfile profile) async {
    _selectedProfile = profile;
    await _prefs?.setSelectedAshaId(profile.id);
    notifyListeners();
  }

  Future<void> clearProfile() async {
    _selectedProfile = null;
    await _prefs?.setSelectedAshaId(null);
    notifyListeners();
  }

  Future<void> updateBaseUrl(String newUrl, {AshaApiClient? customClient}) async {
    final trimmed = newUrl.trim();
    if (trimmed.isEmpty) return;
    _baseUrl = trimmed;
    _apiClient = customClient ?? DioAshaApiClient(baseUrl: trimmed);
    await _prefs?.setBaseUrl(trimmed);
    notifyListeners();
  }
}
