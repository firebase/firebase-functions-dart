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
import 'package:firebase_functions/src/https/https.dart';
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

    // Exercises CORS through the real router, including its interaction with
    // hosting rewrite path matching.
    group('CORS routing', () {
      Handler handlerFor(
        void Function(Firebase) register, {
        bool emulatorCors = false,
      }) {
        FirebaseEnv.mockEnvironment = {
          'FIREBASE_PROJECT': 'demo-test',
          if (emulatorCors)
            'FIREBASE_DEBUG_FEATURES':
                '{"enableCors":true,"skipTokenVerification":true}',
        };
        final firebase = createFirebaseInternal();
        register(firebase);
        return createTestHandler(firebase);
      }

      Request preflight(String path, {String origin = 'https://example.com'}) =>
          Request(
            'OPTIONS',
            Uri.parse('http://localhost$path'),
            headers: {
              'origin': origin,
              'access-control-request-method': 'POST',
              'access-control-request-headers': 'authorization,content-type',
            },
          );

      Request get(String path, {String origin = 'https://example.com'}) =>
          Request(
            'GET',
            Uri.parse('http://localhost$path'),
            headers: {'origin': origin},
          );

      void echoAllowingExample(Firebase f) => f.https.onRequest(
        name: 'echo',
        options: const HttpsOptions(cors: Cors(['https://example.com'])),
        (request) async => Response.ok('ok'),
      );

      test('onRequest without cors emits no CORS headers', () async {
        final handler = handlerFor(
          (f) => f.https.onRequest(
            name: 'echo',
            (request) async => Response.ok('ok'),
          ),
        );

        final response = await handler(get('/echo'));
        expect(
          response.headers.containsKey('access-control-allow-origin'),
          isFalse,
        );
      });

      test('preflight returns 204 and echoes Authorization', () async {
        final handler = handlerFor(echoAllowingExample);
        final response = await handler(preflight('/echo'));

        expect(response.statusCode, 204);
        expect(
          response.headers['access-control-allow-origin'],
          'https://example.com',
        );
        // The wildcard would not authorise Authorization; it must be echoed.
        expect(
          response.headers['access-control-allow-headers'],
          'authorization,content-type',
        );
        expect(response.headers['vary'], contains('Origin'));
      });

      test('preflight works on a hosting sub-path', () async {
        // The router matches on parts[0], so /echo/deep/path must still resolve
        // to `echo` and answer the preflight.
        final handler = handlerFor(echoAllowingExample);
        final response = await handler(preflight('/echo/deep/path'));

        expect(response.statusCode, 204);
        expect(
          response.headers['access-control-allow-origin'],
          'https://example.com',
        );
      });

      test('disallowed origin gets no allow-origin header', () async {
        final handler = handlerFor(echoAllowingExample);
        final response = await handler(
          preflight('/echo', origin: 'https://evil.com'),
        );

        expect(
          response.headers.containsKey('access-control-allow-origin'),
          isFalse,
        );
      });

      test('callable advertises POST only', () async {
        final handler = handlerFor(
          (f) => f.https.onCall(
            name: 'greet',
            (request, response) async => CallableResult('hi'),
          ),
        );

        final response = await handler(preflight('/greet'));
        expect(response.statusCode, 204);
        expect(response.headers['access-control-allow-methods'], 'POST');
      });

      test('emulator enableCors turns on an unconfigured onRequest', () async {
        final handler = handlerFor(
          (f) => f.https.onRequest(
            name: 'echo',
            (request) async => Response.ok('ok'),
          ),
          emulatorCors: true,
        );

        final response = await handler(get('/echo'));
        expect(
          response.headers['access-control-allow-origin'],
          'https://example.com',
        );
      });

      test('emulator enableCors respects an explicit opt-out', () async {
        final handler = handlerFor(
          (f) => f.https.onRequest(
            name: 'echo',
            options: const HttpsOptions(cors: corsDisabled),
            (request) async => Response.ok('ok'),
          ),
          emulatorCors: true,
        );

        final response = await handler(get('/echo'));
        expect(
          response.headers.containsKey('access-control-allow-origin'),
          isFalse,
        );
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
  });
}
