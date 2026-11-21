import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// API keys live in the platform keystore (Keychain, Android Keystore, Windows Credential
/// Manager, encrypted browser storage), never in the app document.
class KeyStore {
  KeyStore({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  final _cache = <String, String>{};

  Future<String> read(String name) async {
    if (_cache.containsKey(name)) return _cache[name]!;
    try {
      final v = await _storage.read(key: name) ?? '';
      _cache[name] = v;
      return v;
    } catch (_) {
      return '';
    }
  }

  Future<void> write(String name, String value) async {
    _cache[name] = value;
    try {
      if (value.isEmpty) {
        await _storage.delete(key: name);
      } else {
        await _storage.write(key: name, value: value);
      }
    } catch (_) {}
  }
}
