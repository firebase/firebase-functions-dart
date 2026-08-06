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

// Regression test for https://github.com/invertase/firebase-functions-dart/issues/235:
// `checkTokens`/`extractAuthToken`/`extractAppCheckToken` and their supporting
// types must be reachable from the public package barrel so `onRequest`
// handlers can verify tokens without reaching into `src/`.
import 'dart:convert';

import 'package:firebase_functions/firebase_functions.dart';
import 'package:test/test.dart';

void main() {
  test(
    'checkTokens, extractAuthToken, extractAppCheckToken, TokenStatus and '
    'TokenVerificationResult are importable from the public barrel',
    () async {
      final authJwt = _createJwt({'sub': 'user123'});
      final appCheckJwt = _createJwt({'sub': 'app123'});

      final (authStatus, authData) = await extractAuthToken({
        'authorization': 'Bearer $authJwt',
      });
      expect(authStatus, TokenStatus.valid);
      expect(authData?.uid, 'user123');

      final (appStatus, appCheckData) = await extractAppCheckToken({
        'x-firebase-appcheck': appCheckJwt,
      });
      expect(appStatus, TokenStatus.valid);
      expect(appCheckData?.appId, 'app123');

      final tokens = await checkTokens({
        'authorization': 'Bearer $authJwt',
        'x-firebase-appcheck': appCheckJwt,
      });
      expect(
        tokens.result,
        isA<TokenVerificationResult>()
            .having((r) => r.auth, 'auth', TokenStatus.valid)
            .having((r) => r.app, 'app', TokenStatus.valid),
      );
      expect(tokens.authData?.uid, 'user123');
      expect(tokens.appCheckData?.appId, 'app123');
    },
  );
}

/// Creates a minimal JWT for testing (unverified/emulator-mode decode path).
String _createJwt(Map<String, dynamic> payload) {
  final headerJson = jsonEncode({'alg': 'HS256', 'typ': 'JWT'});
  final payloadJson = jsonEncode(payload);

  final header = base64Url.encode(utf8.encode(headerJson)).replaceAll('=', '');
  final body = base64Url.encode(utf8.encode(payloadJson)).replaceAll('=', '');
  const signature = 'dummysignature';

  return '$header.$body.$signature';
}
