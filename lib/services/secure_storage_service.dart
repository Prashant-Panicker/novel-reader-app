import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Wraps [FlutterSecureStorage] to persist the user's personal Moonshot
/// (Kimi) API key on-device using the platform keystore/keychain.
///
/// The key is never sent anywhere except directly from this device to
/// Moonshot's API when the user taps "Translate This Page".
class SecureStorageService {
  SecureStorageService._();
  static final SecureStorageService instance = SecureStorageService._();

  static const String _kimiApiKeyLabel = 'KIMI_API_KEY';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  /// Saves the user's private Kimi API key, encrypted at rest.
  Future<void> saveApiKey(String apiKey) async {
    await _storage.write(key: _kimiApiKeyLabel, value: apiKey.trim());
  }

  /// Returns the saved API key, or null if the user hasn't set one yet.
  Future<String?> getApiKey() async {
    final value = await _storage.read(key: _kimiApiKeyLabel);
    if (value == null || value.isEmpty) return null;
    return value;
  }

  /// Removes the stored API key (e.g. "Clear Key" in Settings).
  Future<void> clearApiKey() async {
    await _storage.delete(key: _kimiApiKeyLabel);
  }

  /// Convenience check used before allowing a translation request.
  Future<bool> hasApiKey() async {
    final key = await getApiKey();
    return key != null && key.isNotEmpty;
  }
}
