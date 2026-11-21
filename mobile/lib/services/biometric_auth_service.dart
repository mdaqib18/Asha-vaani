import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// Abstraction over device biometric / local credential unlock (`SPEC_V2 §7`).
abstract class BiometricAuthService {
  Future<bool> canAuthenticate();
  Future<bool> authenticate({required String reason});
}

class LocalBiometricAuthService implements BiometricAuthService {
  LocalBiometricAuthService({LocalAuthentication? auth})
      : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> canAuthenticate() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final supported = await _auth.isDeviceSupported();
      return canCheck || supported;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> authenticate({required String reason}) async {
    try {
      final available = await canAuthenticate();
      if (!available) return false;
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

class FakeBiometricAuthService implements BiometricAuthService {
  FakeBiometricAuthService({
    this.available = false,
    this.shouldSucceed = true,
  });

  bool available;
  bool shouldSucceed;
  int authCalls = 0;
  String? lastReason;

  @override
  Future<bool> canAuthenticate() async => available;

  @override
  Future<bool> authenticate({required String reason}) async {
    authCalls += 1;
    lastReason = reason;
    if (!available) return false;
    return shouldSucceed;
  }
}
