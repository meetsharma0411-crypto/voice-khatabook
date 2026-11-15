import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthTokens {
  const AuthTokens({required this.access, required this.refresh});
  final String access;
  final String refresh;
}

abstract interface class AuthTokenStore {
  Future<AuthTokens?> readTokens();
  Future<void> saveTokens(AuthTokens tokens);
  Future<void> clearTokens();
}

/// Adapter interface keeps secure storage replaceable and testable.
abstract interface class SecureKeyValueStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterSecureKeyValueStorage implements SecureKeyValueStorage {
  FlutterSecureKeyValueStorage([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Stores the pair as one encrypted value, avoiding partially updated tokens.
class SecureAuthTokenStore implements AuthTokenStore {
  SecureAuthTokenStore({required this.storage});

  static const _key = 'keshav.jwt.token_pair.v1';
  final SecureKeyValueStorage storage;

  @override
  Future<AuthTokens?> readTokens() async {
    final value = await storage.read(_key);
    if (value == null) return null;
    try {
      final json = jsonDecode(value) as Map<String, dynamic>;
      final access = json['access'] as String;
      final refresh = json['refresh'] as String;
      if (access.isEmpty || refresh.isEmpty) throw const FormatException();
      return AuthTokens(access: access, refresh: refresh);
    } on Object {
      await clearTokens();
      return null;
    }
  }

  @override
  Future<void> saveTokens(AuthTokens tokens) => storage.write(
    _key,
    jsonEncode({'access': tokens.access, 'refresh': tokens.refresh}),
  );

  @override
  Future<void> clearTokens() => storage.delete(_key);
}

/// In-memory implementation for tests only; it is never used by the app.
class MemoryAuthTokenStore implements AuthTokenStore {
  AuthTokens? _tokens;

  @override
  Future<AuthTokens?> readTokens() async => _tokens;

  @override
  Future<void> saveTokens(AuthTokens tokens) async => _tokens = tokens;

  @override
  Future<void> clearTokens() async => _tokens = null;
}
