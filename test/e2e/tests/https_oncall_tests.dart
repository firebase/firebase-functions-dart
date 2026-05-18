// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:convert';

import 'package:test/test.dart';

import '../helpers/http_client.dart';

/// HTTPS onCall and onCallWithData test group
void runHttpsOnCallTests(FunctionsHttpClient Function() getClient) {
  group('HTTPS onCall', () {
    late FunctionsHttpClient client;

    setUpAll(() {
      client = getClient();
    });

    test('greet returns expected response with name', () async {
      final response = await client.call('greet', data: {'name': 'Dart'});

      expect(response.statusCode, equals(200));

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      expect(
        json['result'],
        equals(<String, dynamic>{'message': 'Hello, Dart!'}),
      );
    });

    test('greet returns default name when no name provided', () async {
      final response = await client.call('greet', data: <String, dynamic>{});

      expect(response.statusCode, equals(200));

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      expect(
        json['result'],
        equals(<String, dynamic>{'message': 'Hello, World!'}),
      );
    });

    test('greet returns default name for missing "data"', () async {
      final response = await client.post('greet', body: {});

      expect(response.statusCode, equals(200));

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      expect(
        json['result'],
        equals(<String, dynamic>{'message': 'Hello, World!'}),
      );
    });

    test('greet returns correct content type', () async {
      final response = await client.call('greet', data: {'name': 'Test'});

      expect(response.statusCode, equals(200));
      expect(response.headers['content-type'], contains('application/json'));
    });

    test('divide returns correct result', () async {
      final response = await client.call('divide', data: {'a': 10, 'b': 2});

      expect(response.statusCode, equals(200));

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      expect(json['result'], equals(<String, dynamic>{'result': 5.0}));
    });

    test('divide throws INVALID_ARGUMENT when args missing', () async {
      final response = await client.call('divide', data: <String, dynamic>{});

      expect(response.statusCode, equals(400));

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final error = json['error'] as Map<String, dynamic>;
      expect(error['status'], equals('INVALID_ARGUMENT'));
      expect(error['message'], contains('required'));
    });

    test('divide throws FAILED_PRECONDITION on divide by zero', () async {
      final response = await client.call('divide', data: {'a': 10, 'b': 0});

      expect(response.statusCode, equals(400));

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final error = json['error'] as Map<String, dynamic>;
      expect(error['status'], equals('FAILED_PRECONDITION'));
      expect(error['message'], contains('divide by zero'));
    });

    test(
      'signInWithCode returns a custom token via Admin SDK createCustomToken',
      () async {
        final response = await client.call(
          'sign-in-with-code',
          data: <String, dynamic>{},
        );

        expect(response.statusCode, equals(200));

        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final result = json['result'] as Map<String, dynamic>;
        expect(result['token'], isA<String>());
        expect(result['token'], isNotEmpty);
      },
    );

    test('getAuthInfo returns unauthenticated when no auth token', () async {
      final response = await client.call(
        'get-auth-info',
        data: <String, dynamic>{},
      );

      expect(response.statusCode, equals(200));

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final result = json['result'] as Map<String, dynamic>;
      expect(result['authenticated'], equals(false));
    });

    test('callable rejects GET requests', () async {
      final response = await client.get('greet');

      // Callable functions only accept POST
      expect(response.statusCode, isNot(equals(200)));
    });

    test('callable rejects invalid content type', () async {
      final response = await client.post(
        'greet',
        body: {'data': 'test'},
        headers: {'Content-Type': 'text/plain'},
      );

      expect(response.statusCode, equals(400));
    });

    test('countdown returns result without streaming', () async {
      final response = await client.call('countdown', data: {'start': 3});

      expect(response.statusCode, equals(200));

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      expect(
        json['result'],
        equals(<String, dynamic>{'message': 'Countdown complete!'}),
      );
    });
  });

  group('HTTPS onCallWithData', () {
    late FunctionsHttpClient client;

    setUpAll(() {
      client = getClient();
    });

    test('greetTyped returns expected response with name', () async {
      final response = await client.call('greet-typed', data: {'name': 'Dart'});

      expect(response.statusCode, equals(200));

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      expect(
        json['result'],
        equals(<String, dynamic>{'message': 'Hello, Dart!'}),
      );
    });

    test('greetTyped uses default name when not provided', () async {
      final response = await client.call(
        'greet-typed',
        data: <String, dynamic>{},
      );

      expect(response.statusCode, equals(200));

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      expect(
        json['result'],
        equals(<String, dynamic>{'message': 'Hello, World!'}),
      );
    });

    test('greetTyped fails when missing "data"', () async {
      final response = await client.post('greetTyped', body: {});

      expect(response.statusCode, isNot(equals(200)));
    });

    test('greetTyped returns correct content type', () async {
      final response = await client.call('greet-typed', data: {'name': 'Test'});

      expect(response.statusCode, equals(200));
      expect(response.headers['content-type'], contains('application/json'));
    });

    test('greetTyped rejects GET requests', () async {
      final response = await client.get('greet-typed');

      expect(response.statusCode, isNot(equals(200)));
    });
  });
}
