import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keshav_ai_voice_khatabook/core/auth/auth_token_store.dart';
import 'package:keshav_ai_voice_khatabook/core/network/api_client.dart';
import 'package:keshav_ai_voice_khatabook/features/auth/data/auth_repository.dart';
import 'package:keshav_ai_voice_khatabook/features/auth/presentation/login_screen.dart';

void main() {
  testWidgets('login screen validates empty username and password', (
    tester,
  ) async {
    final store = MemoryAuthTokenStore();
    final repository = AuthRepository(
      apiClient: ApiClient(baseUrl: 'http://127.0.0.1/api/', tokenStore: store),
      tokenStore: store,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(authRepository: repository, onLogin: () {}),
      ),
    );

    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Enter your username.'), findsOneWidget);
    expect(find.text('Enter your password.'), findsOneWidget);
    expect(await store.readTokens(), isNull);
  });
}
