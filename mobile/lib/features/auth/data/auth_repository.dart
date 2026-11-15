import '../../../core/auth/auth_token_store.dart';
import '../../../core/network/api_client.dart';

class AuthRepository {
  AuthRepository({required this.apiClient, required this.tokenStore});

  final ApiClient apiClient;
  final AuthTokenStore tokenStore;

  Future<void> login({
    required String username,
    required String password,
  }) async {
    final result = await apiClient.postUnauthenticated(
      'auth/token/',
      body: {'username': username, 'password': password},
    );
    if (result is! Map ||
        result['access'] is! String ||
        result['refresh'] is! String) {
      throw const FormatException(
        'The login response did not contain JWT tokens.',
      );
    }
    final access = result['access'] as String;
    final refresh = result['refresh'] as String;
    if (access.isEmpty || refresh.isEmpty) {
      throw const FormatException(
        'The login response contained empty JWT tokens.',
      );
    }
    await tokenStore.saveTokens(AuthTokens(access: access, refresh: refresh));
  }

  /// Always clears local credentials, even if the network logout call fails.
  Future<void> logout() async {
    try {
      final tokens = await tokenStore.readTokens();
      if (tokens != null && tokens.refresh.isNotEmpty) {
        await apiClient.postUnauthenticated(
          'auth/logout/',
          body: {'refresh': tokens.refresh},
        );
      }
    } finally {
      await tokenStore.clearTokens();
    }
  }
}
