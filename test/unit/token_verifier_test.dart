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

import 'package:firebase_functions/src/identity/token_verifier.dart';
import 'package:google_cloud_shelf/google_cloud_shelf.dart';
import 'package:test/test.dart';

void main() {
  group('AuthBlockingTokenVerifier', () {
    group('emulator mode (unsafe decode)', () {
      late AuthBlockingTokenVerifier verifier;

      setUp(() {
        verifier = AuthBlockingTokenVerifier(
          projectId: 'demo-test',
          isEmulator: true, // Emulator mode - no verification
        );
      });

      test('decodes valid JWT without verification', () async {
        // Create a test JWT (header.payload.signature)
        final header = base64Url
            .encode(
              utf8.encode(jsonEncode({'alg': 'RS256', 'kid': 'test-key'})),
            )
            .replaceAll('=', '');
        final payload = base64Url
            .encode(
              utf8.encode(
                jsonEncode({
                  'iss': 'https://securetoken.google.com/demo-test',
                  'aud': 'demo-test.cloudfunctions.net/',
                  'sub': 'user-123',
                  'exp': (DateTime.now().millisecondsSinceEpoch ~/ 1000) + 3600,
                  'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000,
                  'event_type': 'beforeCreate',
                  'user_record': {
                    'uid': 'user-123',
                    'email': 'test@example.com',
                  },
                }),
              ),
            )
            .replaceAll('=', '');
        final jwt = '$header.$payload.fake-signature';

        final result = await verifier.verifyToken(jwt);

        expect(result['sub'], equals('user-123'));
        expect(result['event_type'], equals('beforeCreate'));
        expect(result['user_record'], isA<Map<String, dynamic>>());
      });

      test('decodes JWT with any signature in emulator mode', () async {
        final header = base64Url
            .encode(utf8.encode(jsonEncode({'alg': 'none'})))
            .replaceAll('=', '');
        final payload = base64Url
            .encode(
              utf8.encode(
                jsonEncode({'sub': 'test-user', 'event_type': 'beforeSignIn'}),
              ),
            )
            .replaceAll('=', '');
        final jwt = '$header.$payload.invalid-sig';

        final result = await verifier.verifyToken(jwt);

        expect(result['sub'], equals('test-user'));
      });

      test('throws on invalid JWT format', () async {
        expect(
          () => verifier.verifyToken('not-a-jwt'),
          throwsA(isA<Exception>()),
        );
      });

      test('throws on JWT with wrong number of parts', () async {
        expect(
          () => verifier.verifyToken('only.two'),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('claims validation', () {
      late AuthBlockingTokenVerifier verifier;

      setUp(() {
        verifier = AuthBlockingTokenVerifier(
          projectId: 'test-project',
          isEmulator: true, // Use emulator mode to skip signature verification
        );
      });

      test('accepts valid issuer', () async {
        final jwt = _createTestJwt({
          'iss': 'https://securetoken.google.com/test-project',
          'aud': 'test-project.cloudfunctions.net/',
          'sub': 'user-123',
          'exp': _futureTimestamp(),
          'iat': _nowTimestamp(),
          'event_type': 'beforeCreate',
        });

        // Should not throw
        await verifier.verifyToken(jwt);
      });

      test('accepts valid audience', () async {
        final jwt = _createTestJwt({
          'iss': 'https://securetoken.google.com/test-project',
          'aud': 'test-project.cloudfunctions.net/',
          'sub': 'user-123',
          'exp': _futureTimestamp(),
          'iat': _nowTimestamp(),
          'event_type': 'beforeCreate',
        });

        await verifier.verifyToken(jwt);
      });

      test('accepts run.app audience when specified', () async {
        final jwt = _createTestJwt({
          'iss': 'https://securetoken.google.com/test-project',
          'aud': 'run.app',
          'sub': 'user-123',
          'exp': _futureTimestamp(),
          'iat': _nowTimestamp(),
          'event_type': 'beforeCreate',
        });

        await verifier.verifyToken(jwt, audience: 'run.app');
      });

      test('accepts beforeSendEmail without subject', () async {
        final jwt = _createTestJwt({
          'iss': 'https://securetoken.google.com/test-project',
          'aud': 'test-project.cloudfunctions.net/',
          'exp': _futureTimestamp(),
          'iat': _nowTimestamp(),
          'event_type': 'beforeSendEmail',
        });

        // Should not throw - beforeSendEmail doesn't require sub
        await verifier.verifyToken(jwt);
      });

      test('accepts beforeSendSms without subject', () async {
        final jwt = _createTestJwt({
          'iss': 'https://securetoken.google.com/test-project',
          'aud': 'test-project.cloudfunctions.net/',
          'exp': _futureTimestamp(),
          'iat': _nowTimestamp(),
          'event_type': 'beforeSendSms',
        });

        // Should not throw - beforeSendSms doesn't require sub
        await verifier.verifyToken(jwt);
      });
    });

    group('audience', () {
      final verifier = AuthBlockingTokenVerifier(projectId: 'test-project');

      Map<String, dynamic> claims(Object aud) => {
        'iss': 'https://securetoken.google.com/test-project',
        'aud': aud,
        'sub': 'user-123',
        'exp': _futureTimestamp(),
        'iat': _nowTimestamp(),
        'event_type': 'beforeCreate',
      };

      test('accepts the run.app URL when run.app is expected', () {
        verifier.validateClaims(
          claims('https://beforecreate-abc123-ey.a.run.app'),
          'run.app',
        );
      });

      test('accepts the cloudfunctions.net URL when run.app is expected', () {
        verifier.validateClaims(
          claims(
            'https://europe-west3-test-project.cloudfunctions.net/beforecreate',
          ),
          'run.app',
        );
      });

      test('accepts the cloudfunctions.net URL by default', () {
        verifier.validateClaims(
          claims(
            'https://europe-west3-test-project.cloudfunctions.net/beforecreate',
          ),
          null,
        );
      });

      test('rejects a run.app URL by default', () {
        expect(
          () => verifier.validateClaims(
            claims('https://beforecreate-abc123-ey.a.run.app'),
            null,
          ),
          throwsA(isA<HttpResponseException>()),
        );
      });

      test('rejects another project', () {
        expect(
          () => verifier.validateClaims(
            claims(
              'https://europe-west3-other-project.cloudfunctions.net/beforecreate',
            ),
            'run.app',
          ),
          throwsA(isA<HttpResponseException>()),
        );
      });

      test('accepts a list holding an expected audience', () {
        verifier.validateClaims(
          claims(['other', 'https://beforecreate-abc123-ey.a.run.app']),
          'run.app',
        );
      });
    });

    group('certificate cache', () {
      test('clearCertificateCache resets cache', () {
        // Just verify it doesn't throw
        AuthBlockingTokenVerifier.clearCertificateCache();
      });
    });
  });
}

/// Creates a test JWT with the given payload.
String _createTestJwt(Map<String, dynamic> payload) {
  final header = base64Url
      .encode(utf8.encode(jsonEncode({'alg': 'RS256', 'kid': 'test'})))
      .replaceAll('=', '');
  final payloadEncoded = base64Url
      .encode(utf8.encode(jsonEncode(payload)))
      .replaceAll('=', '');
  return '$header.$payloadEncoded.fake-signature';
}

/// Returns a timestamp 1 hour in the future (seconds since epoch).
int _futureTimestamp() =>
    (DateTime.now().millisecondsSinceEpoch ~/ 1000) + 3600;

/// Returns the current timestamp (seconds since epoch).
int _nowTimestamp() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
