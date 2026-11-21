import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Controls Android `FLAG_SECURE` screenshot/recents protection via platform channel.
abstract class ScreenSecurityService {
  bool get isSupported;
  bool get isProtected;
  Future<bool> setProtected(bool enabled);
}

class PlatformScreenSecurityService implements ScreenSecurityService {
  PlatformScreenSecurityService({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel('com.ashavaani.asha_vaani/security');

  final MethodChannel _channel;
  bool _supported = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool _protected = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  bool get isSupported => _supported;

  @override
  bool get isProtected => _protected;

  @override
  Future<bool> setProtected(bool enabled) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      _supported = false;
      _protected = false;
      return false;
    }
    try {
      final result = await _channel.invokeMethod<bool>(
        'setSecureFlag',
        <String, Object>{'enabled': enabled},
      );
      _supported = result ?? false;
      _protected = _supported && enabled;
      return _supported;
    } on MissingPluginException {
      _supported = false;
      _protected = false;
      return false;
    } on PlatformException {
      _supported = false;
      _protected = false;
      return false;
    }
  }
}

class FakeScreenSecurityService implements ScreenSecurityService {
  FakeScreenSecurityService({
    this.supported = true,
    bool initialProtected = true,
  }) : _protected = supported && initialProtected;

  final bool supported;
  bool _protected;
  final List<bool> calls = [];

  @override
  bool get isSupported => supported;

  @override
  bool get isProtected => supported && _protected;

  @override
  Future<bool> setProtected(bool enabled) async {
    calls.add(enabled);
    if (!supported) {
      _protected = false;
      return false;
    }
    _protected = enabled;
    return true;
  }
}
