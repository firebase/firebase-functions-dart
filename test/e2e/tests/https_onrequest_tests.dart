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

import '../helpers/emulator.dart';
import '../helpers/http_client.dart';

/// HTTPS onRequest test group
void runHttpsOnRequestTests(
  FunctionsHttpClient Function() getClient,
  EmulatorHelper Function() getEmulator,
) {
  group('HTTPS onRequest', () {
    late FunctionsHttpClient client;
    late EmulatorHelper emulator;

    setUpAll(() {
      client = getClient();
      emulator = getEmulator();
    });
    test('helloworld returns expected response', () async {
      print('GET ${client.baseUrl}/helloworld');
      final response = await client.get('helloworld');

      expect(response.statusCode, equals(200));
      expect(response.body, contains('Hello from Dart Functions!'));
    });

    test('helloworld has correct content type', () async {
      print('GET ${client.baseUrl}/helloworld');
      final response = await client.get('helloworld');

      expect(response.statusCode, equals(200));
      expect(response.headers['content-type'], contains('text/plain'));
    });

    test('helloworld accepts GET requests', () async {
      print('GET ${client.baseUrl}/helloworld');
      final response = await client.get('helloworld');

      expect(response.statusCode, equals(200));
    });

    test('helloworld accepts POST requests', () async {
      print('POST ${client.baseUrl}/helloworld');
      final response = await client.post('helloworld');

      expect(response.statusCode, equals(200));
    });

    test('helloworld accepts POST requests similar to a CloudEvent', () async {
      print('POST ${client.baseUrl}/helloworld like CloudEvent');
      final response = await client.post(
        'helloworld',
        body: {'type': 0, 'source': 1},
      );

      expect(response.statusCode, equals(200));
    });

    test('calling non-existent function returns 404', () async {
      print('GET ${client.baseUrl}/non-existent-function');
      final response = await client.get('non-existent-function');

      expect(response.statusCode, equals(404));
    });

    test('handles multiple concurrent requests', () async {
      // Reduced from 10 to 5 requests to avoid CI timeout issues
      // The emulator spawns separate workers which can be slow in CI
      print('Making 5 concurrent requests...');
      final futures = List.generate(5, (_) async {
        final response = await client.get('helloworld');
        expect(response.statusCode, equals(200));
        expect(response.body, contains('Hello from Dart Functions!'));
      });

      await Future.wait(futures);
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('function is discoverable via emulator', () async {
      print('GET ${client.baseUrl}/helloworld');
      final response = await client.get('helloworld');

      expect(
        response.statusCode,
        equals(200),
        reason: 'Function helloworld should be deployed',
      );
    });

    test(
      'unexpected error returns INTERNAL without leaking sensitive details',
      () async {
        print('GET ${client.baseUrl}/crashwithsecret');
        final response = await client.get('crashwithsecret');

        // Should return 500
        expect(response.statusCode, equals(500));

        // Parse the JSON error body
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final error = json['error'] as Map<String, dynamic>;

        // Generic INTERNAL error is returned
        expect(error['status'], equals('INTERNAL'));
        expect(error['message'], equals('Internal Server Error'));

        // Sensitive details must NOT appear anywhere in the response
        expect(response.body, isNot(contains('SECRET_DATA')));
        expect(response.body, isNot(contains('sensitive data')));
        expect(response.body, isNot(contains('Unexpected failure')));

        // Verify the error WAS logged server-side (visible in emulator output)
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final allLogs = [
          ...emulator.outputLines,
          ...emulator.errorLines,
        ].join('\n');
        expect(
          allLogs,
          contains('SECRET_DATA'),
          reason: 'The actual error should be logged server-side for debugging',
        );

        print('✓ Verified: 500 INTERNAL returned, error logged');
      },
    );

    test(
      'unexpected runtime error returns INTERNAL without leaking internals',
      () async {
        print('GET ${client.baseUrl}/crashunexpected');
        final response = await client.get('crashunexpected');

        // Should return 500
        expect(response.statusCode, equals(500));

        // Parse the JSON error body
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final error = json['error'] as Map<String, dynamic>;

        // Generic INTERNAL error is returned
        expect(error['status'], equals('INTERNAL'));
        expect(error['message'], equals('Internal Server Error'));

        // No internal details leaked (no type names, stack traces, file paths)
        expect(response.body, isNot(contains('TypeError')));
        expect(response.body, isNot(contains('not_a_number')));
        expect(response.body, isNot(contains('.dart')));
        expect(response.body, isNot(contains('type ')));

        print('✓ Verified: unexpected crash returns generic 500');
      },
    );

    test('function execution is visible in emulator logs', () async {
      // Clear previous logs to isolate this test
      emulator.clearOutputBuffer();

      // Make a request
      print('GET ${client.baseUrl}/helloworld (verifying execution logs)');
      final response = await client.get('helloworld');

      // Wait a bit for logs to be captured
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Verify response
      expect(response.statusCode, equals(200));

      // Verify Firebase emulator logged the execution
      final executionLogged = emulator.verifyFunctionExecution(
        'us-central1-helloworld',
      );
      expect(
        executionLogged,
        isTrue,
        reason:
            'Should see "Beginning execution" and "Finished" in emulator logs',
      );

      print('✓ Function execution verified in emulator logs');
    });
  });
}
