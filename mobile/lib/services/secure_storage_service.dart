import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Abstraction over hardware-backed key/secret storage (Android Keystore / iOS Keychain).
abstract class SecureStorageService {
  static const String keyDbPassphrase = 'asha_v2_db_key';
  static const String keyPinDigest = 'asha_v2_pin_digest';
  static const String keySessionToken = 'asha_v2_session_token';

  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);

  Future<String> getOrCreateDbPassphrase() async {
    final existing = await read(keyDbPassphrase);
    if (existing != null && existing.trim().isNotEmpty) {
      return existing;
    }
    final generated = generateRandomPassphrase();
    await write(keyDbPassphrase, generated);
    return generated;
  }

  Future<String?> readPinDigest() => read(keyPinDigest);

  Future<void> writePinDigest(String? digest) async {
    if (digest == null || digest.isEmpty) {
      await delete(keyPinDigest);
    } else {
      await write(keyPinDigest, digest);
    }
  }

  Future<String?> readSessionToken() => read(keySessionToken);

  Future<void> writeSessionToken(String? token) async {
    if (token == null || token.isEmpty) {
      await delete(keySessionToken);
    } else {
      await write(keySessionToken, token);
    }
  }

  Future<void> clearSession() => delete(keySessionToken);

  Future<void> clearAll() async {
    await delete(keySessionToken);
    await delete(keyPinDigest);
    await delete(keyDbPassphrase);
  }

  static String generateRandomPassphrase([int byteLength = 32]) {
    final rng = Random.secure();
    final bytes = List<int>.generate(byteLength, (_) => rng.nextInt(256));
    return base64UrlEncode(bytes);
  }
}

class FlutterSecureStorageService extends SecureStorageService {
  FlutterSecureStorageService({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class InMemorySecureStorageService extends SecureStorageService {
  final Map<String, String> _store = {};

  Map<String, String> get debugSnapshot => Map.unmodifiable(_store);

  @override
  Future<String?> read(String key) async => _store[key];

  @override
  Future<void> write(String key, String value) async {
    _store[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _store.remove(key);
  }
}
