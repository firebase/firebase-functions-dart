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

import 'package:firebase_admin_sdk/auth.dart';
import 'package:firebase_admin_sdk/firebase_admin_sdk.dart';
import 'package:firebase_functions/src/https/auth.dart';
import 'package:firebase_functions/src/https/callable.dart';
import 'package:firebase_functions/testing.dart';
import 'package:test/test.dart';

import '../fixtures/mock_credentials.dart';

void main() {
  late FirebaseApp app;
  late Auth auth;

  setUp(() {
    final mock = createMockAuthApp();
    app = mock.app;
    auth = mock.auth;
  });

  tearDown(() => FirebaseApp.deleteApp(app));

  group('extractAuthToken with real token verification', () {
    test('accepts a valid cryptographically-signed ID token', () async {
      final token = mintIdToken(uid: 'user-123');

      final (status, authData) = await extractAuthToken({
        'authorization': 'Bearer $token',
      }, auth: auth);

      expect(status, TokenStatus.valid);
      expect(authData, isNotNull);
      expect(authData!.uid, 'user-123');
      expect(authData.rawToken, token);
    });

    test('extracts all standard claims from verified token', () async {
      final token = mintIdToken(uid: 'user-abc');

      final (status, authData) = await extractAuthToken({
        'authorization': 'Bearer $token',
      }, auth: auth);

      expect(status, TokenStatus.valid);
      expect(
        authData!.token?['iss'],
        'https://securetoken.google.com/$mockProjectId',
      );
      expect(authData.token?['aud'], mockProjectId);
      expect(authData.token?['sub'], 'user-abc');
    });

    test('rejects an expired token', () async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final token = mintIdToken(exp: now - 3600, iat: now - 7200);

      final (status, authData) = await extractAuthToken({
        'authorization': 'Bearer $token',
      }, auth: auth);

      expect(status, TokenStatus.invalid);
      expect(authData, isNull);
    });

    test('rejects a token with wrong audience (wrong project)', () async {
      final token = mintIdToken(projectId: 'wrong-project');

      final (status, authData) = await extractAuthToken({
        'authorization': 'Bearer $token',
      }, auth: auth);

      expect(status, TokenStatus.invalid);
      expect(authData, isNull);
    });

    test('rejects a token with a kid not in the certificate set', () async {
      final token = mintIdToken(kid: 'unknown-kid');

      final (status, authData) = await extractAuthToken({
        'authorization': 'Bearer $token',
      }, auth: auth);

      expect(status, TokenStatus.invalid);
      expect(authData, isNull);
    });

    test('rejects a token with a tampered signature', () async {
      final token = tamperToken(mintIdToken());

      final (status, authData) = await extractAuthToken({
        'authorization': 'Bearer $token',
      }, auth: auth);

      expect(status, TokenStatus.invalid);
      expect(authData, isNull);
    });

    test('rejects when Authorization header is absent', () async {
      final (status, authData) = await extractAuthToken({}, auth: auth);

      expect(status, TokenStatus.missing);
      expect(authData, isNull);
    });
  });

  group('onCall with real token verification', () {
    late FunctionsTestClient client;

    setUp(() async {
      client = await runFunctionsTest(adminApp: app, (firebase) {
        firebase.https.onCall(
          name: 'echoAuth',
          (req, _) async => CallableResult({
            'uid': req.auth?.uid,
            'authed': req.auth != null,
          }),
        );
      });
    });

    tearDown(() => client.dispose());

    test(
      'populates req.auth for a valid token through the full onCall pipeline',
      () async {
        final token = mintIdToken(uid: 'caller-uid');
        final response = await client.call(
          'echoAuth',
          data: <String, dynamic>{},
          idToken: token,
        );

        expect(response.statusCode, 200);
        final result =
            await client.parseCallableResponse(response)
                as Map<String, dynamic>;
        expect(result['authed'], isTrue);
        expect(result['uid'], 'caller-uid');
      },
    );

    test(
      'allows unauthenticated call (req.auth is null when no token)',
      () async {
        final response = await client.call(
          'echoAuth',
          data: <String, dynamic>{},
        );

        expect(response.statusCode, 200);
        final result =
            await client.parseCallableResponse(response)
                as Map<String, dynamic>;
        expect(result['authed'], isFalse);
        expect(result['uid'], isNull);
      },
    );

    test('returns 401 for an invalid (tampered) token', () async {
      final response = await client.call(
        'echoAuth',
        data: <String, dynamic>{},
        idToken: tamperToken(mintIdToken()),
      );

      expect(response.statusCode, 401);
    });

    test('returns 401 for an expired token', () async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final token = mintIdToken(exp: now - 3600, iat: now - 7200);

      final response = await client.call(
        'echoAuth',
        data: <String, dynamic>{},
        idToken: token,
      );

      expect(response.statusCode, 401);
    });
  });
}
