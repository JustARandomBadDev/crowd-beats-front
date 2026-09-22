import 'dart:convert';

import 'package:crowd_beats_front/core/api/api_client.dart';
import 'package:crowd_beats_front/core/api/api_failure.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../fixtures.dart';

void main() {
  test('decodes success envelope and retains status and meta', () async {
    final client = ApiClient(
      baseUrl: 'http://localhost:8080/',
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'data': {'status': 'ready'},
            'error': null,
            'meta': {'request_id': '123'},
          }),
          200,
        ),
      ),
    );
    addTearDown(client.close);

    final response = await client.get<Map<String, dynamic>>(
      '/health/ready',
      decode: (data) => data as Map<String, dynamic>,
    );
    expect(response.statusCode, 200);
    expect(response.data['status'], 'ready');
    expect(response.meta['request_id'], '123');
  });

  test('preserves backend code, message, status and meta on error', () async {
    final client = ApiClient(
      baseUrl: 'http://localhost:8080',
      httpClient: MockClient(
        (request) async => apiError('INVALID_QR_CODE', status: 403),
      ),
    );
    addTearDown(client.close);

    await expectLater(
      client.get('/api/v1/rooms/id', decode: (data) => data),
      throwsA(
        isA<ApiFailure>()
            .having((e) => e.category, 'category', ApiFailureCategory.backend)
            .having((e) => e.statusCode, 'status', 403)
            .having((e) => e.backendCode, 'code', 'INVALID_QR_CODE')
            .having((e) => e.backendMessage, 'message', 'backend detail')
            .having((e) => e.meta?['request_id'], 'meta', 'test'),
      ),
    );
  });

  test('distinguishes invalid JSON from malformed envelope', () async {
    final invalidJson = ApiClient(
      baseUrl: 'http://localhost:8080',
      httpClient: MockClient((request) async => http.Response('{', 500)),
    );
    addTearDown(invalidJson.close);
    await expectLater(
      invalidJson.get('/health/ready', decode: (data) => data),
      throwsA(
        isA<ApiFailure>()
            .having(
              (e) => e.category,
              'category',
              ApiFailureCategory.invalidJson,
            )
            .having((e) => e.statusCode, 'status', 500),
      ),
    );

    final malformed = ApiClient(
      baseUrl: 'http://localhost:8080',
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'data': {'status': 'ready'},
            'meta': {},
          }),
          200,
        ),
      ),
    );
    addTearDown(malformed.close);
    await expectLater(
      malformed.get('/health/ready', decode: (data) => data),
      throwsA(
        isA<ApiFailure>()
            .having((e) => e.category, 'category', ApiFailureCategory.protocol)
            .having((e) => e.statusCode, 'status', 200),
      ),
    );
  });

  test('rejects an HTTP failure without a backend error envelope', () async {
    final client = ApiClient(
      baseUrl: 'http://localhost:8080',
      httpClient: MockClient(
        (request) async => apiResponse({'status': 'not_ready'}, status: 503),
      ),
    );
    addTearDown(client.close);
    await expectLater(
      client.get('/health/ready', decode: (data) => data),
      throwsA(
        isA<ApiFailure>()
            .having((e) => e.category, 'category', ApiFailureCategory.protocol)
            .having((e) => e.statusCode, 'status', 503),
      ),
    );
  });

  test('rejects data with wrong DTO shape as protocol failure', () async {
    final client = ApiClient(
      baseUrl: 'http://localhost:8080',
      httpClient: MockClient((request) async => apiResponse({'items': []})),
    );
    addTearDown(client.close);
    await expectLater(
      client.get('/example', decode: (data) => (data as Map)['missing'] as int),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.category,
          'category',
          ApiFailureCategory.protocol,
        ),
      ),
    );
  });

  test(
    'public requests omit bearer while authenticated requests add it',
    () async {
      final requests = <http.Request>[];
      final client = ApiClient(
        baseUrl: 'http://localhost:8080/proxy//',
        httpClient: MockClient((request) async {
          requests.add(request);
          return apiResponse({'status': 'ready'});
        }),
      );
      addTearDown(client.close);

      await client.get('/health/ready', decode: (data) => data);
      await client.get(
        '/api/v1/sessions/me',
        bearerToken: 'session-token',
        decode: (data) => data,
      );
      expect(requests.first.headers.containsKey('authorization'), isFalse);
      expect(requests.last.headers['authorization'], 'Bearer session-token');
      expect(requests.first.url.path, '/proxy/health/ready');
      expect(requests.last.url.path, '/proxy/api/v1/sessions/me');
    },
  );

  test('distinguishes timeout and transport failure', () async {
    final timedOut = ApiClient(
      baseUrl: 'http://localhost:8080',
      timeout: const Duration(milliseconds: 1),
      httpClient: MockClient((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return apiResponse({});
      }),
    );
    addTearDown(timedOut.close);
    await expectLater(
      timedOut.get('/health/ready', decode: (data) => data),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.category,
          'category',
          ApiFailureCategory.timeout,
        ),
      ),
    );

    final disconnected = ApiClient(
      baseUrl: 'http://localhost:8080',
      httpClient: MockClient(
        (request) async => throw http.ClientException('offline'),
      ),
    );
    addTearDown(disconnected.close);
    await expectLater(
      disconnected.get('/health/ready', decode: (data) => data),
      throwsA(
        isA<ApiFailure>()
            .having((e) => e.category, 'category', ApiFailureCategory.transport)
            .having((e) => e.statusCode, 'status', isNull),
      ),
    );
  });

  test('invalid base URL fails before sending a request', () {
    expect(() => ApiClient(baseUrl: ''), throwsArgumentError);
    expect(
      () => ApiClient(baseUrl: 'ws://localhost:8080'),
      throwsArgumentError,
    );
    expect(
      () => ApiClient(baseUrl: 'http://localhost:8080?x=1'),
      throwsArgumentError,
    );
  });
}
