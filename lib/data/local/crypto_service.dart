import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the master key is kept.
///
/// Extracted so [CryptoService] can be tested without platform channels: the
/// app passes [PlatformSecretStore], tests pass an in-memory fake. The security
/// property under test is the envelope format, not the keystore.
abstract interface class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Keystore on Android, Keychain on iOS.
class PlatformSecretStore implements SecretStore {
  PlatformSecretStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              // v10+ encrypts the shared-preferences file by default, so
              // `encryptedSharedPreferences` is gone — passing it throws.
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
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

/// Encrypts entry text at rest with AES-256-GCM.
///
/// Threat model: someone has the unlocked device, or reads its storage over USB.
///
/// Only `title` and `body` are encrypted. Dates and moods stay plaintext so that
/// the heatmap, streaks and charts can be computed in SQL without decrypting
/// every row.
///
/// Envelope format: `v1:<b64 nonce>:<b64 mac>:<b64 ciphertext>`
///
/// The key lives in the Android Keystore / iOS Keychain. Losing it means losing
/// the entries, because there is also no cloud copy.
class CryptoService {
  CryptoService({SecretStore? store})
      : _store = store ??
            PlatformSecretStore(
              const FlutterSecureStorage(
                iOptions: IOSOptions(
                  accessibility: KeychainAccessibility.first_unlock,
                ),
              ),
            );

  static const _keyName = 'mood_journal_master_key';
  static const _prefix = 'v1';

  final SecretStore _store;
  final AesGcm _algorithm = AesGcm.with256bits();

  SecretKey? _cachedKey;
  Future<SecretKey>? _pending;

  /// True when a value is already an encrypted envelope rather than plaintext.
  ///
  /// Every decrypt path checks this, because turning encryption off leaves
  /// plaintext rows behind and turning it back on must not try to open them.
  static bool isEnvelope(String? value) =>
      value != null && value.startsWith('$_prefix:');

  Future<SecretKey> _key() {
    final cached = _cachedKey;
    if (cached != null) return Future.value(cached);
    return _pending ??= _loadKey().whenComplete(() => _pending = null);
  }

  Future<SecretKey> _loadKey() async {
    final existing = await _store.read(_keyName);
    if (existing != null && existing.isNotEmpty) {
      final key = SecretKey(base64Decode(existing));
      _cachedKey = key;
      return key;
    }

    final generated = await _algorithm.newSecretKey();
    await _store.write(_keyName, base64Encode(await generated.extractBytes()));
    _cachedKey = generated;
    return generated;
  }

  Future<String> encrypt(String plaintext) async {
    if (plaintext.isEmpty) return plaintext;

    final box = await _algorithm.encrypt(
      plaintext.codeUnits,
      secretKey: await _key(),
      nonce: _algorithm.newNonce(),
    );

    return [
      _prefix,
      base64Encode(box.nonce),
      base64Encode(box.mac.bytes),
      base64Encode(box.cipherText),
    ].join(':');
  }

  /// Returns the input unchanged when it is not an envelope.
  Future<String> decrypt(String payload) async {
    if (!isEnvelope(payload)) return payload;

    final parts = payload.split(':');
    if (parts.length != 4) {
      throw const FormatException('Malformed ciphertext envelope');
    }

    final box = SecretBox(
      base64Decode(parts[3]),
      nonce: base64Decode(parts[1]),
      mac: Mac(base64Decode(parts[2])),
    );

    final clear = await _algorithm.decrypt(box, secretKey: await _key());
    return utf8.decode(clear);
  }

  Future<String?> encryptNullable(String? value) async {
    if (value == null) return null;
    return encrypt(value);
  }

  Future<String?> decryptNullable(String? value) async {
    if (value == null) return null;
    return decrypt(value);
  }

  /// Drops the cached key handle.
  void forgetCachedKey() => _cachedKey = null;

  Future<void> destroyKey() async {
    await _store.delete(_keyName);
    _cachedKey = null;
  }
}
