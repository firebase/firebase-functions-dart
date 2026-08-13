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

import 'package:firebase_functions/src/common/environment.dart';
import 'package:firebase_functions/src/firebase.dart';
import 'package:firebase_functions/src/identity/auth_blocking_event.dart';
import 'package:firebase_functions/src/identity/identity_namespace.dart';
import 'package:firebase_functions/src/identity/responses.dart';
import 'package:google_cloud_shelf/google_cloud_shelf.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

// Helper to find function by name
FirebaseFunctionDeclaration? _findFunction(Firebase firebase, String name) =>
    firebase.functions.where((f) => f.name == name).singleOrNull;

void main() {
  setUpAll(() {
    FirebaseEnv.mockEnvironment = {'FIREBASE_PROJECT': 'demo-test'};
  });

  group('IdentityNamespace', () {
    const maxPayload = 1000;
    const constant = '{"k":""}'.length;
    const availablePayloadSize = maxPayload - constant;
    String fillPayload(String pattern, {bool useUtf8 = false}) {
      final patternSize = useUtf8
          ? utf8.encode(pattern).length
          : pattern.length;
      final repetitions = (availablePayloadSize ~/ patternSize) + 1;
      return pattern * repetitions;
    }

    final tooLargeCustomClaims = [
      {'k': fillPayload('*')},
      {'k': fillPayload('*', useUtf8: true)},
      {'k': fillPayload('❤️')},
      {'k': fillPayload('❤️', useUtf8: true)},
    ];

    late Firebase firebase;
    late IdentityNamespace identity;

    setUp(() {
      firebase = createFirebaseInternal()
        ..$env.environment['FUNCTIONS_EMULATOR'] = 'true';
      identity = IdentityNamespace(firebase);
    });

    Request createRequest(String name, AuthBlockingEvent event) {
      return Request(
        'POST',
        Uri.parse('http://localhost/$name'),
        headers: {'content-type': 'application/json'},
        body: json.encode({
          'data': {'jwt': event.toJwt()},
        }),
      );
    }

    AuthBlockingEvent createEvent() {
      return const AuthBlockingEvent(
        ipAddress: '0.0.0.0',
        userAgent: 'test-cli',
      );
    }

    group('beforeUserCreated', () {
      Future<Response> handle(AuthBlockingEvent event) async {
        final func = _findFunction(firebase, 'beforecreate')!;
        final req = createRequest('beforecreate', event);
        return await func.handler(req);
      }

      test('fails for invalid custom claims size', () async {
        var i = 0;
        identity.beforeUserCreated((ev) {
          return BeforeCreateResponse(customClaims: tooLargeCustomClaims[i]);
        });
        for (final l = tooLargeCustomClaims.length; i < l; i++) {
          await expectLater(
            handle(createEvent()),
            throwsA(isA<HttpResponseException>()),
          );
        }
      });
    });

    group('beforeUserSignedIn', () {
      Future<Response> handle(AuthBlockingEvent event) async {
        final func = _findFunction(firebase, 'beforesignin')!;
        final req = createRequest('beforesignin', event);
        return await func.handler(req);
      }

      test('fails for invalid custom claims size', () async {
        var i = 0;
        identity.beforeUserSignedIn((ev) {
          return BeforeSignInResponse(customClaims: tooLargeCustomClaims[i]);
        });
        for (final l = tooLargeCustomClaims.length; i < l; i++) {
          await expectLater(
            handle(createEvent()),
            throwsA(isA<HttpResponseException>()),
          );
        }
      });
    });
  });
}

extension on AuthBlockingEvent {
  String toJwt() {
    final payload = json.encode(toJson());
    final payloadBase64 = base64Url.encode(utf8.encode(payload));
    final header = json.encode({'alg': 'none', 'typ': 'JWT'});
    final headerBase64 = base64Url.encode(utf8.encode(header));
    return '$headerBase64.$payloadBase64';
  }
}
