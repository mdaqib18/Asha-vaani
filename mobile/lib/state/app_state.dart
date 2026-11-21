import 'package:flutter/foundation.dart';

import '../l10n/app_strings.dart';
import '../models/beneficiary.dart';
import '../models/v2_models.dart';
import '../services/api_client.dart';
import '../services/audio_player_service.dart';
import '../services/audio_recorder_service.dart';
import '../services/biometric_auth_service.dart';
import '../services/local_db_service.dart';
import '../services/pin_hasher.dart';
import '../services/prefs_service.dart';
import '../services/screen_security_service.dart';
import '../services/secure_storage_service.dart';
import '../services/sync_service.dart';
import '../services/visit_stream_client.dart';

class AppState extends ChangeNotifier {
  AppState({
    PrefsService? prefs,
    AshaApiClient? apiClient,
    AudioCaptureService? recorder,
    AudioPlaybackService? audioPlayer,
    LocalDbService? localDb,
    ConnectivityMonitor? connectivity,
    SyncService? syncService,
    SecureStorageService? secureStorage,
    BiometricAuthService? biometricAuth,
    ScreenSecurityService? screenSecurity,
    VisitStreamClient? visitStreamClient,
    AppLanguage initialLanguage = AppLanguage.hi,
    AshaProfile? initialProfile,
    bool? initialLocked,
    bool? initialHighContrast,
    double? initialPaperBaselineMinutes,
    bool? allowDevSecurityToggle,
    String initialBaseUrl = PrefsService.defaultBaseUrl,
  })  : _prefs = prefs,
        _secureStorage = secureStorage ?? FlutterSecureStorageService(),
        _biometricAuth = biometricAuth ?? LocalBiometricAuthService(),
        _screenSecurity = screenSecurity ?? PlatformScreenSecurityService(),
        _visitStreamClient = visitStreamClient ?? IoVisitStreamClient(),
        _language = prefs?.language ?? initialLanguage,
        _sessionToken = prefs?.sessionToken,
        _pinDigest = prefs?.pinDigest,
        _highContrast = initialHighContrast ?? prefs?.highContrast ?? false,
        _paperBaselineMinutes =
            initialPaperBaselineMinutes ?? prefs?.paperBaselineMinutes,
        _autoLockSeconds = prefs?.autoLockSeconds ?? 60,
        _biometricEnabled = prefs?.biometricEnabled ?? true,
        _screenshotProtectionEnabled =
            prefs?.screenshotProtectionEnabled ?? true,
        _allowDevSecurityToggle = allowDevSecurityToggle ?? kDebugMode,
        _initialLockedExplicit = initialLocked != null,
        _baseUrl = prefs?.baseUrl ?? initialBaseUrl,
        _apiClient = apiClient ??
            DioAshaApiClient(baseUrl: prefs?.baseUrl ?? initialBaseUrl),
        _recorder = recorder ?? RecordAudioCaptureService(),
        _audioPlayer = audioPlayer ?? JustAudioPlaybackService() {
    _localDb = localDb ??
        SqfliteLocalDbService(
          passphraseProvider: _secureStorage.getOrCreateDbPassphrase,
        );
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
  final SecureStorageService _secureStorage;
  final BiometricAuthService _biometricAuth;
  final ScreenSecurityService _screenSecurity;
  final VisitStreamClient _visitStreamClient;
  final AudioCaptureService _recorder;
  final AudioPlaybackService _audioPlayer;
  late final LocalDbService _localDb;
  final bool _allowDevSecurityToggle;
  final bool _initialLockedExplicit;
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
  int _autoLockSeconds;
  bool _biometricEnabled;
  bool _biometricAvailable = false;
  bool _screenshotProtectionEnabled;
  int _lastRetentionPurgedCount = 0;
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
  int get autoLockSeconds => _autoLockSeconds;
  bool get biometricEnabled => _biometricEnabled;
  bool get biometricAvailable => _biometricAvailable;
  bool get screenshotProtectionEnabled => _screenshotProtectionEnabled;
  bool get isScreenProtected =>
      _screenSecurity.isSupported && _screenSecurity.isProtected;
  bool get allowDevSecurityToggle => _allowDevSecurityToggle;
  bool get isLocalDbEncrypted => _localDb.isEncrypted;
  bool get isHttpsTransport => _baseUrl.toLowerCase().startsWith('https://');
  int get lastRetentionPurgedCount => _lastRetentionPurgedCount;
  String get baseUrl => _baseUrl;
  AshaApiClient get api => _apiClient;
  AudioCaptureService get recorder => _recorder;
  AudioPlaybackService get audioPlayer => _audioPlayer;
  LocalDbService get localDb => _localDb;
  SyncService get syncService => _syncService;
  SecureStorageService get secureStorage => _secureStorage;
  VisitStreamClient get visitStream => _visitStreamClient;

  Future<void> initializeSecurity() async {
    // Migrate legacy secrets out of SharedPreferences into encrypted storage.
    final legacyPin = _prefs?.pinDigest;
    if (legacyPin != null && legacyPin.isNotEmpty) {
      await _secureStorage.writePinDigest(legacyPin);
      await _prefs?.setPinDigest(null);
    }
    final legacyToken = _prefs?.sessionToken;
    if (legacyToken != null && legacyToken.isNotEmpty) {
      await _secureStorage.writeSessionToken(legacyToken);
      await _prefs?.setSessionToken(null);
    }

    _pinDigest = await _secureStorage.readPinDigest() ?? _pinDigest;
    _sessionToken = await _secureStorage.readSessionToken() ?? _sessionToken;
    if (!_initialLockedExplicit && _pinDigest != null) {
      _isLocked = true;
    }

    try {
      _biometricAvailable = await _biometricAuth.canAuthenticate();
    } catch (_) {
      _biometricAvailable = false;
    }

    await _screenSecurity.setProtected(_screenshotProtectionEnabled);
    await runAudioRetentionSweep();
    notifyListeners();
  }

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
      await _secureStorage.writeSessionToken(result.token);
      await _secureStorage.writePinDigest(digest);
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

  Future<bool> unlockWithBiometric({required String reason}) async {
    if (!_biometricEnabled || !_biometricAvailable || !hasOfflineCredentials) {
      return false;
    }
    final authenticated = await _biometricAuth.authenticate(reason: reason);
    if (!authenticated) return false;
    _selectedProfile = _lastProfile;
    _sessionToken = await _secureStorage.readSessionToken();
    _isLocked = false;
    _isSignedInOffline = true;
    final actorId = _lastProfile?.id ?? 'worker';
    try {
      await _localDb.recordAuditLog(
        AuditLogEntry(
          id: UuidV4.generate(),
          actorId: actorId,
          action: 'biometric_unlock',
          entity: 'worker',
          entityId: actorId,
          at: DateTime.now().toUtc().toIso8601String(),
        ),
      );
    } catch (_) {}
    notifyListeners();
    return true;
  }

  Future<void> lockApp() async {
    _sessionToken = null;
    _isLocked = true;
    try {
      await _localDb.closeDb();
    } catch (_) {}
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
    await _secureStorage.clearSession();
    await _secureStorage.writePinDigest(null);
    try {
      await _localDb.closeDb();
    } catch (_) {}
    notifyListeners();
  }

  Future<void> setAutoLockSeconds(int seconds) async {
    final normalized = seconds < 10 ? 10 : seconds;
    if (_autoLockSeconds == normalized) return;
    _autoLockSeconds = normalized;
    await _prefs?.setAutoLockSeconds(normalized);
    notifyListeners();
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    if (_biometricEnabled == enabled) return;
    _biometricEnabled = enabled;
    await _prefs?.setBiometricEnabled(enabled);
    notifyListeners();
  }

  Future<void> setScreenshotProtectionEnabled(bool enabled) async {
    _screenshotProtectionEnabled = enabled;
    await _prefs?.setScreenshotProtectionEnabled(enabled);
    await _screenSecurity.setProtected(enabled);
    notifyListeners();
  }

  Future<int> runAudioRetentionSweep({DateTime? now}) async {
    try {
      final purged = await _localDb.purgeExpiredAudioAssets(now: now);
      _lastRetentionPurgedCount = purged.length;
      notifyListeners();
      return purged.length;
    } catch (_) {
      return 0;
    }
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
