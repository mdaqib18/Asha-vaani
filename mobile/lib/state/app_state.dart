import 'package:flutter/foundation.dart';

import '../l10n/app_strings.dart';
import '../models/beneficiary.dart';
import '../services/api_client.dart';
import '../services/audio_player_service.dart';
import '../services/audio_recorder_service.dart';
import '../services/local_db_service.dart';
import '../services/pin_hasher.dart';
import '../services/prefs_service.dart';
import '../services/sync_service.dart';

class AppState extends ChangeNotifier {
  AppState({
    PrefsService? prefs,
    AshaApiClient? apiClient,
    AudioCaptureService? recorder,
    AudioPlaybackService? audioPlayer,
    LocalDbService? localDb,
    ConnectivityMonitor? connectivity,
    SyncService? syncService,
    AppLanguage initialLanguage = AppLanguage.hi,
    AshaProfile? initialProfile,
    bool? initialLocked,
    bool? initialHighContrast,
    double? initialPaperBaselineMinutes,
    String initialBaseUrl = PrefsService.defaultBaseUrl,
  })  : _prefs = prefs,
        _language = prefs?.language ?? initialLanguage,
        _sessionToken = prefs?.sessionToken,
        _pinDigest = prefs?.pinDigest,
        _highContrast = initialHighContrast ?? prefs?.highContrast ?? false,
        _paperBaselineMinutes =
            initialPaperBaselineMinutes ?? prefs?.paperBaselineMinutes,
        _baseUrl = prefs?.baseUrl ?? initialBaseUrl,
        _apiClient = apiClient ??
            DioAshaApiClient(baseUrl: prefs?.baseUrl ?? initialBaseUrl),
        _recorder = recorder ?? RecordAudioCaptureService(),
        _audioPlayer = audioPlayer ?? JustAudioPlaybackService(),
        _localDb = localDb ?? SqfliteLocalDbService() {
    if (prefs?.lastWorkerId != null && prefs!.lastWorkerId!.isNotEmpty) {
      _lastProfile = AshaProfile(
        id: prefs.lastWorkerId!,
        name: prefs.lastWorkerName ?? prefs.lastWorkerId!,
        area: prefs.lastWorkerArea ?? '',
      );
    }
    _selectedProfile = initialProfile ??
        _lastProfile ??
        (prefs?.selectedAshaId != null
            ? AshaProfile.byId(prefs!.selectedAshaId)
            : null);
    _isLocked =
        initialLocked ?? (_pinDigest != null && initialProfile == null);

    _syncService = syncService ??
        SyncService(
          localDb: _localDb,
          apiProvider: () => _apiClient,
          connectivity: connectivity ?? PlusConnectivityMonitor(),
        );
  }

  final PrefsService? _prefs;
  final AudioCaptureService _recorder;
  final AudioPlaybackService _audioPlayer;
  final LocalDbService _localDb;
  late final SyncService _syncService;

  AppLanguage _language;
  AshaProfile? _selectedProfile;
  AshaProfile? _lastProfile;
  String? _sessionToken;
  String? _pinDigest;
  bool _isLocked = false;
  bool _isSignedInOffline = false;
  bool _highContrast;
  double? _paperBaselineMinutes;
  String _baseUrl;
  AshaApiClient _apiClient;

  AppLanguage get language => _language;
  AppStrings get strings => AppStrings.of(_language);
  AshaProfile? get selectedProfile => _selectedProfile;
  AshaProfile? get lastProfile => _lastProfile ?? _selectedProfile;
  String? get sessionToken => _sessionToken;
  bool get isLocked => _isLocked;
  bool get hasOfflineCredentials => _pinDigest != null && _lastProfile != null;
  bool get isSignedInOffline => _isSignedInOffline;
  bool get highContrast => _highContrast;
  double? get paperBaselineMinutes => _paperBaselineMinutes;
  String get baseUrl => _baseUrl;
  AshaApiClient get api => _apiClient;
  AudioCaptureService get recorder => _recorder;
  AudioPlaybackService get audioPlayer => _audioPlayer;
  LocalDbService get localDb => _localDb;
  SyncService get syncService => _syncService;

  Future<void> setLanguage(AppLanguage lang) async {
    if (_language == lang) return;
    _language = lang;
    await _prefs?.setLanguage(lang);
    notifyListeners();
  }

  Future<void> setHighContrast(bool enabled) async {
    if (_highContrast == enabled) return;
    _highContrast = enabled;
    await _prefs?.setHighContrast(enabled);
    notifyListeners();
  }

  Future<void> signInWithPin({
    required String workerCode,
    required String pin,
  }) async {
    final code = workerCode.trim();
    final cleanPin = pin.trim();
    if (code.isEmpty || cleanPin.isEmpty) {
      throw const ApiException('INVALID_CREDENTIALS');
    }

    try {
      final result = await _apiClient.login(workerCode: code, pin: cleanPin);
      final digest = PinHasher.hashPin(result.profile.id, cleanPin);
      _selectedProfile = result.profile;
      _lastProfile = result.profile;
      _sessionToken = result.token;
      _pinDigest = digest;
      _isLocked = false;
      _isSignedInOffline = false;
      await _prefs?.setSelectedAshaId(result.profile.id);
      await _prefs?.setSessionToken(result.token);
      await _prefs?.setPinDigest(digest);
      await _prefs?.setLastWorker(
        id: result.profile.id,
        name: result.profile.name,
        area: result.profile.area,
      );
      notifyListeners();
    } on ApiException catch (e) {
      if (e.code != 'NETWORK_ERROR' && e.code != 'TIMEOUT') rethrow;
      final savedProfile = _lastProfile;
      final savedDigest = _pinDigest;
      if (savedProfile != null &&
          savedDigest != null &&
          savedProfile.id.toLowerCase() == code.toLowerCase() &&
          PinHasher.verify(savedProfile.id, cleanPin, savedDigest)) {
        _selectedProfile = savedProfile;
        _isLocked = false;
        _isSignedInOffline = true;
        await _prefs?.setSelectedAshaId(savedProfile.id);
        notifyListeners();
        return;
      }
      throw const ApiException('OFFLINE_FIRST_LOGIN');
    }
  }

  Future<void> selectProfile(AshaProfile profile) async {
    _selectedProfile = profile;
    _lastProfile = profile;
    _isLocked = false;
    await _prefs?.setSelectedAshaId(profile.id);
    notifyListeners();
  }

  Future<void> lockApp() async {
    _isLocked = true;
    notifyListeners();
  }

  Future<void> clearProfile() => signOut();

  Future<void> signOut() async {
    _selectedProfile = null;
    _lastProfile = null;
    _sessionToken = null;
    _pinDigest = null;
    _isLocked = false;
    _isSignedInOffline = false;
    await _prefs?.setSelectedAshaId(null);
    await _prefs?.setSessionToken(null);
    await _prefs?.setPinDigest(null);
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

  Future<void> setPaperBaselineMinutes(double? minutes) async {
    final normalized = (minutes == null || minutes <= 0) ? null : minutes;
    if (_paperBaselineMinutes == normalized) return;
    _paperBaselineMinutes = normalized;
    await _prefs?.setPaperBaselineMinutes(normalized);
    notifyListeners();
  }
}
