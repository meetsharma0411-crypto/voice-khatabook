import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:keshav_ai_voice_khatabook/core/auth/auth_token_store.dart';
import 'package:keshav_ai_voice_khatabook/core/network/api_client.dart';

void main() {
  test(
    'multipart voice upload uses the bearer token and idempotency key',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final received = Completer<Map<String, Object?>>();
      server.listen((request) async {
        final bodyBytes = await request.fold<BytesBuilder>(
          BytesBuilder(),
          (builder, chunk) => builder..add(chunk),
        );
        final body = utf8.decode(bodyBytes.takeBytes());
        received.complete({
          'authorization': request.headers.value(
            HttpHeaders.authorizationHeader,
          )!,
          'idempotency': request.headers.value('Idempotency-Key')!,
          'contentType': request.headers.contentType!.mimeType,
          'hasAudioField': body.contains(
            'name="audio"; filename="voice-client-test.m4a"',
          ),
          'hasCustomerField': body.contains('name="customer_id"'),
        });
        request.response
          ..statusCode = HttpStatus.created
          ..headers.contentType = ContentType.json
          ..write('{"id":4}');
        await request.response.close();
      });
      final file = File('${Directory.systemTemp.path}/voice-client-test.m4a');
      await file.writeAsBytes([1, 2, 3]);
      final store = MemoryAuthTokenStore();
      await store.saveTokens(
        const AuthTokens(access: 'voice-access', refresh: 'voice-refresh'),
      );
      final client = ApiClient(
        baseUrl: 'http://127.0.0.1:${server.port}/api/',
        tokenStore: store,
      );

      expect(
        await client.postMultipartFile(
          path: 'voice/proposals/',
          file: file,
          fileField: 'audio',
          fields: {'customer_id': '7'},
          idempotencyKey: 'voice-test-1',
        ),
        {'id': 4},
      );
      expect(await received.future, {
        'authorization': 'Bearer voice-access',
        'idempotency': 'voice-test-1',
        'contentType': 'multipart/form-data',
        'hasAudioField': true,
        'hasCustomerField': true,
      });
      client.close(force: true);
      await server.close(force: true);
      await file.delete();
    },
  );

  test('client sends JSON, bearer token and idempotency key', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final handled = Completer<Map<String, Object?>>();
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      handled.complete({
        'authorization': request.headers.value(
          HttpHeaders.authorizationHeader,
        )!,
        'idempotency': request.headers.value('Idempotency-Key')!,
        'body': jsonDecode(body),
      });
      request.response
        ..statusCode = HttpStatus.created
        ..headers.contentType = ContentType.json
        ..write('{"saved":true}');
      await request.response.close();
    });
    final store = MemoryAuthTokenStore();
    await store.saveTokens(
      const AuthTokens(access: 'abc', refresh: 'refresh-abc'),
    );
    final client = ApiClient(
      baseUrl: 'http://127.0.0.1:${server.port}/api/',
      tokenStore: store,
    );
    expect(
      await client.post(
        'transactions/',
        body: {'amount': '5.00'},
        idempotencyKey: 'unique-1',
      ),
      {'saved': true},
    );
    expect(await handled.future, {
      'authorization': 'Bearer abc',
      'idempotency': 'unique-1',
      'body': {'amount': '5.00'},
    });
    client.close(force: true);
    await server.close(force: true);
  });

  test(
    'multipart upload uses the normal JWT refresh and single retry',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var refreshes = 0;
      final uploadTokens = <String>[];
      server.listen((request) async {
        await request.drain<void>();
        if (request.uri.path == '/api/auth/token/refresh/') {
          refreshes++;
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write('{"access":"access-new","refresh":"refresh-new"}');
        } else {
          uploadTokens.add(
            request.headers.value(HttpHeaders.authorizationHeader)!,
          );
          request.response
            ..statusCode = uploadTokens.length == 1
                ? HttpStatus.unauthorized
                : HttpStatus.created
            ..headers.contentType = ContentType.json
            ..write('{"ok":true}');
        }
        await request.response.close();
      });
      final file = File('${Directory.systemTemp.path}/voice-refresh-test.m4a');
      await file.writeAsBytes([1, 2, 3]);
      final store = MemoryAuthTokenStore();
      await store.saveTokens(
        const AuthTokens(access: 'access-old', refresh: 'refresh-old'),
      );
      final client = ApiClient(
        baseUrl: 'http://127.0.0.1:${server.port}/api/',
        tokenStore: store,
      );

      expect(
        await client.postMultipartFile(
          path: 'voice/proposals/',
          file: file,
          fileField: 'audio',
          fields: const {},
          idempotencyKey: 'voice-refresh-1',
        ),
        {'ok': true},
      );
      expect(refreshes, 1);
      expect(uploadTokens, ['Bearer access-old', 'Bearer access-new']);
      client.close(force: true);
      await server.close(force: true);
      await file.delete();
    },
  );

  test('parallel expired requests share one refresh and retry once', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final oldRequestsReady = Completer<void>();
    var oldRequests = 0;
    var refreshRequests = 0;
    var protectedRequests = 0;
    server.listen((request) async {
      final path = request.uri.path;
      if (path == '/api/auth/token/refresh/') {
        refreshRequests++;
        await Future<void>.delayed(const Duration(milliseconds: 40));
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write('{"access":"access-new","refresh":"refresh-new"}');
      } else {
        protectedRequests++;
        if (request.headers.value(HttpHeaders.authorizationHeader) ==
            'Bearer access-old') {
          oldRequests++;
          if (oldRequests == 2) oldRequestsReady.complete();
          await oldRequestsReady.future;
          request.response.statusCode = HttpStatus.unauthorized;
        } else {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write('{"ok":true}');
        }
      }
      await request.response.close();
    });

    final store = MemoryAuthTokenStore();
    await store.saveTokens(
      const AuthTokens(access: 'access-old', refresh: 'refresh-old'),
    );
    final client = ApiClient(
      baseUrl: 'http://127.0.0.1:${server.port}/api/',
      tokenStore: store,
    );
    final responses = await Future.wait([
      client.get('one/'),
      client.get('two/'),
    ]);

    expect(responses, [
      {'ok': true},
      {'ok': true},
    ]);
    expect(refreshRequests, 1);
    expect(protectedRequests, 4);
    final rotated = await store.readTokens();
    expect(rotated?.access, 'access-new');
    expect(rotated?.refresh, 'refresh-new');
    client.close(force: true);
    await server.close(force: true);
  });

  test(
    'revoked refresh clears credentials and reports unauthenticated',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.statusCode = HttpStatus.unauthorized;
        await request.response.close();
      });
      var unauthenticatedCalls = 0;
      final store = MemoryAuthTokenStore();
      await store.saveTokens(
        const AuthTokens(access: 'expired', refresh: 'revoked'),
      );
      final client = ApiClient(
        baseUrl: 'http://127.0.0.1:${server.port}/api/',
        tokenStore: store,
        onUnauthenticated: () => unauthenticatedCalls++,
      );

      await expectLater(client.get('protected/'), throwsA(isA<ApiException>()));
      expect(await store.readTokens(), isNull);
      expect(unauthenticatedCalls, 1);
      client.close(force: true);
      await server.close(force: true);
    },
  );

  test('a request is retried only once after refresh', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var protectedRequests = 0;
    server.listen((request) async {
      if (request.uri.path == '/api/auth/token/refresh/') {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write('{"access":"new-access","refresh":"new-refresh"}');
      } else {
        protectedRequests++;
        request.response.statusCode = HttpStatus.unauthorized;
      }
      await request.response.close();
    });
    var unauthenticatedCalls = 0;
    final store = MemoryAuthTokenStore();
    await store.saveTokens(
      const AuthTokens(access: 'old-access', refresh: 'old-refresh'),
    );
    final client = ApiClient(
      baseUrl: 'http://127.0.0.1:${server.port}/api/',
      tokenStore: store,
      onUnauthenticated: () => unauthenticatedCalls++,
    );

    await expectLater(
      client.get('always-denied/'),
      throwsA(isA<ApiException>()),
    );
    expect(protectedRequests, 2);
    expect(unauthenticatedCalls, 1);
    expect(await store.readTokens(), isNull);
    client.close(force: true);
    await server.close(force: true);
  });
}
