import 'package:flutter_test/flutter_test.dart';
import 'package:keshav_ai_voice_khatabook/core/auth/auth_token_store.dart';

void main() {
  test(
    'secure token store persists pair through secure storage adapter',
    () async {
      final storage = _FakeSecureStorage();
      final store = SecureAuthTokenStore(storage: storage);
      const pair = AuthTokens(
        access: 'access-secret',
        refresh: 'refresh-secret',
      );
      expect(await store.readTokens(), isNull);
      await store.saveTokens(pair);
      final restored = await store.readTokens();
      expect(restored?.access, pair.access);
      expect(restored?.refresh, pair.refresh);
      await store.clearTokens();
      expect(await store.readTokens(), isNull);
      expect(storage.values, isEmpty);
    },
  );
}

class _FakeSecureStorage implements SecureKeyValueStorage {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}
