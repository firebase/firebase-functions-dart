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

import 'package:firebase_functions/src/https/auth.dart';
import 'package:firebase_functions/src/https/callable.dart';
import 'package:test/test.dart';

import 'shared_utils.dart';

void main() {
  // All tests use skipTokenVerification: true since we can't easily mock
  // the certificate fetching in unit tests. Integration tests would cover
  // the production path with real certificates.

  group('extractAuthToken', () {
    test('returns missing when no Authorization header', () async {
      final (status, auth) = await extractAuthToken({});

      expect(status, TokenStatus.missing);
      expect(auth, isNull);
    });

    test(
      'returns invalid when Authorization header is not Bearer format',
      () async {
        final (status, auth) = await extractAuthToken({
          'authorization': 'Basic abc123',
        });

        expect(status, TokenStatus.invalid);
        expect(auth, isNull);
      },
    );

    test('returns invalid when token has no uid/sub claim', () async {
      final jwt = createJwt({'email': 'test@example.com'});

      final (status, auth) = await extractAuthToken({
        'authorization': 'Bearer $jwt',
      });

      expect(status, TokenStatus.invalid);
      expect(auth, isNull);
    });

    test('returns valid with AuthData for valid token', () async {
      final jwt = createJwt({
        'sub': 'user123',
        'email': 'test@example.com',
        'custom_claim': 'value',
      });

      final (status, auth) = await extractAuthToken({
        'authorization': 'Bearer $jwt',
      });

      expect(status, TokenStatus.valid);
      expect(auth, isNotNull);
      expect(auth!.uid, 'user123');
      expect(auth.token?['email'], 'test@example.com');
      expect(auth.token?['custom_claim'], 'value');
      expect(auth.rawToken, jwt);
    });

    test('extracts uid from user_id claim as fallback', () async {
      final jwt = createJwt({'user_id': 'user456'});

      final (status, auth) = await extractAuthToken({
        'authorization': 'Bearer $jwt',
      });

      expect(status, TokenStatus.valid);
      expect(auth?.uid, 'user456');
    });

    test('handles case-insensitive Bearer prefix', () async {
      final jwt = createJwt({'sub': 'user123'});

      final (status, auth) = await extractAuthToken({
        'authorization': 'bearer $jwt',
      });

      expect(status, TokenStatus.valid);
      expect(auth?.uid, 'user123');
    });

    test('returns invalid for malformed JWT', () async {
      final (status, auth) = await extractAuthToken({
        'authorization': 'Bearer not-a-valid-jwt',
      });

      expect(status, TokenStatus.invalid);
      expect(auth, isNull);
    });

    test('returns invalid for JWT with empty payload', () async {
      final jwt = createJwt({});

      final (status, auth) = await extractAuthToken({
        'authorization': 'Bearer $jwt',
      });

      expect(status, TokenStatus.invalid);
      expect(auth, isNull);
    });
  });

  group('extractAppCheckToken', () {
    test('returns missing when no X-Firebase-AppCheck header', () async {
      final (status, appCheck) = await extractAppCheckToken({});

      expect(status, TokenStatus.missing);
      expect(appCheck, isNull);
    });

    test('returns invalid when token has no sub claim', () async {
      final jwt = createJwt({'other': 'value'});

      final (status, appCheck) = await extractAppCheckToken({
        'x-firebase-appcheck': jwt,
      });

      expect(status, TokenStatus.invalid);
      expect(appCheck, isNull);
    });

    test('returns valid with AppCheckData for valid token', () async {
      final jwt = createJwt({'sub': 'app123'});

      final (status, appCheck) = await extractAppCheckToken({
        'x-firebase-appcheck': jwt,
      });

      expect(status, TokenStatus.valid);
      expect(appCheck, isNotNull);
      expect(appCheck!.appId, 'app123');
      expect(appCheck.token, jwt);
    });

    test('extracts app_id from explicit claim', () async {
      final jwt = createJwt({'sub': 'sub-value', 'app_id': 'explicit-app-id'});

      final (status, appCheck) = await extractAppCheckToken({
        'x-firebase-appcheck': jwt,
      });

      expect(status, TokenStatus.valid);
      expect(appCheck?.appId, 'explicit-app-id');
    });
  });

  group('checkTokens', () {
    test('returns both auth and app check data when present', () async {
      final authJwt = createJwt({'sub': 'user123'});
      final appCheckJwt = createJwt({'sub': 'app123'});

      final result = await checkTokens({
        'authorization': 'Bearer $authJwt',
        'x-firebase-appcheck': appCheckJwt,
      });

      expect(result.result.auth, TokenStatus.valid);
      expect(result.result.app, TokenStatus.valid);
      expect(result.authData?.uid, 'user123');
      expect(result.appCheckData?.appId, 'app123');
    });

    test('returns missing status when headers are absent', () async {
      final result = await checkTokens({});

      expect(result.result.auth, TokenStatus.missing);
      expect(result.result.app, TokenStatus.missing);
      expect(result.authData, isNull);
      expect(result.appCheckData, isNull);
    });

    test('handles mixed valid and invalid tokens', () async {
      final authJwt = createJwt({'sub': 'user123'});
      final invalidAppCheckJwt = createJwt({'no_sub': 'value'});

      final result = await checkTokens({
        'authorization': 'Bearer $authJwt',
        'x-firebase-appcheck': invalidAppCheckJwt,
      });

      expect(result.result.auth, TokenStatus.valid);
      expect(result.result.app, TokenStatus.invalid);
      expect(result.authData?.uid, 'user123');
      expect(result.appCheckData, isNull);
    });
  });

  group('AuthData', () {
    test('rawToken field is accessible', () {
      const auth = AuthData(uid: 'user123', rawToken: 'raw-token-value');

      expect(auth.rawToken, 'raw-token-value');
    });

    test('all fields are populated correctly', () {
      const auth = AuthData(
        uid: 'user123',
        token: {'email': 'test@example.com'},
        rawToken: 'raw-token',
      );

      expect(auth.uid, 'user123');
      expect(auth.token, {'email': 'test@example.com'});
      expect(auth.rawToken, 'raw-token');
    });
  });

  group('TokenStatus', () {
    test('has correct enum values', () {
      expect(TokenStatus.values, hasLength(3));
      expect(TokenStatus.values, contains(TokenStatus.missing));
      expect(TokenStatus.values, contains(TokenStatus.invalid));
      expect(TokenStatus.values, contains(TokenStatus.valid));
    });
  });

  group('TokenVerificationResult', () {
    test('holds auth and app status', () {
      const result = TokenVerificationResult(
        auth: TokenStatus.valid,
        app: TokenStatus.missing,
      );

      expect(result.auth, TokenStatus.valid);
      expect(result.app, TokenStatus.missing);
    });
  });
}
