import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keshav_ai_voice_khatabook/core/auth/auth_token_store.dart';
import 'package:keshav_ai_voice_khatabook/core/network/api_client.dart';
import 'package:keshav_ai_voice_khatabook/features/auth/data/auth_repository.dart';

void main() {
  test('login stores issued tokens and logout clears them', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final received = <Map<String, Object?>>[];
    final allRequestsHandled = Completer<void>();
    server.listen((request) async {
      final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      received.add({'path': request.uri.path, 'body': body});
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(
          request.uri.path.endsWith('/logout/')
              ? '{"detail":"Token is blacklisted"}'
              : '{"access":"server-access","refresh":"server-refresh"}',
        );
      await request.response.close();
      if (received.length == 2 && !allRequestsHandled.isCompleted) {
        allRequestsHandled.complete();
      }
    });

    final store = MemoryAuthTokenStore();
    final client = ApiClient(
      baseUrl: 'http://127.0.0.1:${server.port}/api/',
      tokenStore: store,
    );
    final auth = AuthRepository(apiClient: client, tokenStore: store);
    await auth.login(
      username: 'operator',
      password: 'password-never-persisted',
    );
    expect((await store.readTokens())?.access, 'server-access');
    expect((await store.readTokens())?.refresh, 'server-refresh');
    await auth.logout();
    await allRequestsHandled.future;
    expect(await store.readTokens(), isNull);
    expect(received[0]['path'], '/api/auth/token/');
    expect(received[0]['body'], {
      'username': 'operator',
      'password': 'password-never-persisted',
    });
    expect(received[1]['path'], '/api/auth/logout/');
    expect(received[1]['body'], {'refresh': 'server-refresh'});
    client.close(force: true);
    await server.close(force: true);
  });

  test('login rejects credentials when server returns unauthorized', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.statusCode = HttpStatus.unauthorized;
      request.response.write('{"detail":"No active account found"}');
      await request.response.close();
    });
    final store = MemoryAuthTokenStore();
    final client = ApiClient(
      baseUrl: 'http://127.0.0.1:${server.port}/api/',
      tokenStore: store,
    );
    final auth = AuthRepository(apiClient: client, tokenStore: store);

    await expectLater(
      auth.login(username: 'operator', password: 'wrong'),
      throwsA(isA<ApiException>()),
    );
    expect(await store.readTokens(), isNull);
    client.close(force: true);
    await server.close(force: true);
  });
}
