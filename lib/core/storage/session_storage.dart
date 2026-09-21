import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SessionStorage {
  SessionStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _tokenKey = 'session_token';

  final FlutterSecureStorage _storage;

  Future<void> saveToken(String token) {
    return _storage.write(key: _tokenKey, value: token);
  }

  Future<String?> readToken() {
    return _storage.read(key: _tokenKey);
  }

  Future<void> clearSession() {
    return _storage.delete(key: _tokenKey);
  }
}
