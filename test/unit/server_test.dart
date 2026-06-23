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

import 'package:firebase_functions/src/common/environment.dart';
import 'package:firebase_functions/src/firebase.dart';
import 'package:firebase_functions/src/server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  group('server', () {
    group('RunFunctionsOptions', () {
      test('defaults to null (no header)', () {
        const opts = RunFunctionsOptions();
        expect(opts.poweredByHeader, isNull);
      });

      test('accepts a custom header value', () {
        const opts = RunFunctionsOptions(poweredByHeader: 'MyApp/1.0');
        expect(opts.poweredByHeader, 'MyApp/1.0');
      });
    });

    group('hosting rewrite path handling', () {
      late Handler handler;

      setUp(() {
        FirebaseEnv.mockEnvironment = {'FIREBASE_PROJECT': 'demo-test'};
        final firebase = createFirebaseInternal();
        firebase.https.onRequest(
          name: 'echo',
          (request) async => Response.ok(request.requestedUri.path),
        );
        handler = createTestHandler(firebase);
      });

      // Hosting rewrite of root path: emulator sends /{function}
      test('/{fn} → handler sees /', () async {
        final request = Request('GET', Uri.parse('http://localhost/echo'));
        final response = await handler(request);
        expect(await response.readAsString(), '/');
      });

      // Hosting rewrite with sub-path: emulator sends /{function}/{rest}
      // Bug: was routing to a function named 'other' instead of 'echo'
      test('/{fn}/{rest} → handler sees /{rest}', () async {
        final request = Request(
          'GET',
          Uri.parse('http://localhost/echo/other'),
        );
        final response = await handler(request);
        expect(await response.readAsString(), '/other');
      });

      // Direct emulator call: /{project}/{region}/{function}
      test('/{project}/{region}/{fn} → handler sees /', () async {
        final request = Request(
          'GET',
          Uri.parse('http://localhost/my-project/us-central1/echo'),
        );
        final response = await handler(request);
        expect(await response.readAsString(), '/');
      });

      // Direct emulator call with sub-path: /{project}/{region}/{function}/{rest}
      test('/{project}/{region}/{fn}/{rest} → handler sees /{rest}', () async {
        final request = Request(
          'GET',
          Uri.parse('http://localhost/my-project/us-central1/echo/other'),
        );
        final response = await handler(request);
        expect(await response.readAsString(), '/other');
      });

      // Emulator sends /{fn}/{a}/{b} for a client request to /{a}/{b} — 3 segments,
      // no header. Must not be confused with /{project}/{region}/{fn} direct format.
      test('/{fn}/{a}/{b} → handler sees /{a}/{b} (no header)', () async {
        final request = Request(
          'GET',
          Uri.parse('http://localhost/echo/deep/path'),
        );
        final response = await handler(request);
        expect(await response.readAsString(), '/deep/path');
      });

      // X-Firebase-Function header: emulator uses /{fn}/{rest} even for deep paths
      test(
        'X-Firebase-Function header routes correctly for deep path',
        () async {
          final request = Request(
            'GET',
            Uri.parse('http://localhost/echo/deep/path'),
            headers: {'x-firebase-function': 'echo'},
          );
          final response = await handler(request);
          expect(await response.readAsString(), '/deep/path');
        },
      );

      test('unknown function returns 404', () async {
        final request = Request('GET', Uri.parse('http://localhost/unknown'));
        final response = await handler(request);
        expect(response.statusCode, 404);
      });
    });
    group('corsHeadersFor', () {
      test('returns asterisk when allowedOrigins contains asterisk', () {
        final request = Request('GET', Uri.parse('http://localhost/test'));
        final headers = corsHeadersFor(request, ['*']);
        expect(headers['Access-Control-Allow-Origin'], '*');
      });

      test('echoes the Origin header if it matches allowedOrigins', () {
        final request = Request(
          'GET',
          Uri.parse('http://localhost/test'),
          headers: {'origin': 'https://example.com'},
        );
        final headers = corsHeadersFor(request, ['https://example.com']);
        expect(headers['Access-Control-Allow-Origin'], 'https://example.com');
      });

      test('returns empty map if no match is found', () {
        final request = Request(
          'GET',
          Uri.parse('http://localhost/test'),
          headers: {'origin': 'https://evil.com'},
        );
        final headers = corsHeadersFor(request, ['https://example.com']);
        expect(headers, isEmpty);
      });
    });
  });
}
