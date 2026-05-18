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

// IMPORTANT: this keypair has been specifically generated for this test suite.

// ignore_for_file: invalid_use_of_internal_member

import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:firebase_admin_sdk/auth.dart';
import 'package:firebase_admin_sdk/firebase_admin_sdk.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// Test RSA private key — generated specifically for this test suite, not for
// production use. The matching self-signed X.509 certificate below was
// generated with: openssl req -new -x509 -key <key> -days 36500 -subj "/CN=test"
const mockPrivateKeyPem = '''
-----BEGIN RSA PRIVATE KEY-----
MIIEowIBAAKCAQEA6xkrY7pxvazMDAesPtRqsnQN+7Nv1boCQeFP+crgJLZN9gnD
vqiDCIqPOv0p/n687npEp1eGDJcL/ZxK/wXQqvonwUeTwZnglKSRL6W76zXyYiFa
ibVLdHgg/KIUrlokS8/pWbFkI7kideTgQp+1vh3jUcdpq46tatPvINzZEj5xrV/2
NSzyBSMNPrXsMEk9cEh8e3GkgGuitHVfLp5M4K/d31ezoBt1dZjtxKS7JI+OHya5
C9Z208BllZNklUERK8lSw0EG1y1VahMl4mBpKpfswq1Dysv9JPv3hMEWt/S4864l
dxN4VE5M6MB8hWFPq+f4UY7MhNkeYcNfyqgMxQIDAQABAoIBADmp1kEjSWOe/vtS
ZHaSrkrv+UALznnrIkObanzXvGt0xaF72qWoel89cQ0kbEjuOBP8LFupNYlgAQJm
8+QiPoC5U8ft8PlS70k2JiA8M9/ovvc/vA+7xnKeRmUAsjbjiDSKHe+weWHjtmaZ
SUI+HxsvBIMZ+LqqB7IEoon6cUmuS+TBGeBtPUZkwtjhzAXeyy9xNKjEJ94NcPRo
fIBIPGXMroc2fafbVsr+Wq931oficPEpjRd+JLkojHqcq/aY1sIWpYwNxu6jF9sm
KsUUtrwsQL6s3vxwkuKd3X0XhEgJSQBxkY40BLFMLFR0gmoVzw3+OtfEagMiXzyb
SAYbFk8CgYEA94lcWzOGGUijpQQKBwcNBo/kvcQ6h9NGlJ7ZUeuAyIIq4aRxGFBV
yWnpKOFC7ywsNeoatLXXTiTe6Xq0JBkup3WZktsNe1BI2R1kX6PHHYBVMKXA02tX
uGANaqg/A+ZYA2VMPdcRTNhgXgsJnj7mcDCKHdPYQHvLGqU5WRA185cCgYEA8yLw
bb6oZ3YtMbBYYay0u3iqlN74GWqLwLH2ZovQIWnVYbYUNmJNTVhkHlShXWK3qKOY
p26K67LBIRYRaseIH4e9hPROy1vsl4dkmd8FJfhsx8WXpa3/3pHw9hmbhmhhjVLo
ABtQKxjLDa430mi3jFgcN7yn6B4qklpO6lmpngMCgYB8BAOTZbLvg+cIy4dCkhPC
j+Dn+iHg3sbjutniIvz4d86IEdzfc5AnQrqf0ou4TAcyU8FhfCEMc4iCrQkHdN5c
45w3aSvN9iEpNYKOL/2YGC2WG9UJlyPxqZ3PK8+2YncB7IRQDyoJt/Y/54PAFn9Z
AdiQrQwQ8nSFOvYKWwbMrQKBgAhem4grmAB3wPaE64XxPAd4D+cwBbpaQJVRivnc
tj1wNzg13FxC5gZTlJ62qxdb3pafixG4bG/Qp3VMHS1f0P/E3HFHN68oauyMbJof
Yz37X0NBOgcqBjTTMUhHeWMXFMSYpgPa7NeO8u51oNZNZIQgRFhm1iDXaP/AvBa1
H3GhAoGBAKGcU+cw5dx9jf4Dj3Xechknrl5aDdK5FNrIC4IJ20A4N3S+WQ1cQuRO
QjJNH9ASKTmmuslFJZZcBX5ybnr9Eg3MUeCyaru1CSWubrKraMo71mgzTexZOtV5
nlc5+GKKhkC/Vp5ZNE04kdT+35eMZUTbv1/d3Y5TzUIGd6QwtPtM
-----END RSA PRIVATE KEY-----
''';

// Self-signed X.509 certificate for [mockPrivateKeyPem].
const mockCertPem = '''
-----BEGIN CERTIFICATE-----
MIIDATCCAemgAwIBAgIUdpnWgxIuEG62mljLvQfgWGGeeMYwDQYJKoZIhvcNAQEL
BQAwDzENMAsGA1UEAwwEdGVzdDAgFw0yNjA1MDYxNDU5NDBaGA8yMTI2MDQxMjE0
NTk0MFowDzENMAsGA1UEAwwEdGVzdDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCC
AQoCggEBAOsZK2O6cb2szAwHrD7UarJ0Dfuzb9W6AkHhT/nK4CS2TfYJw76ogwiK
jzr9Kf5+vO56RKdXhgyXC/2cSv8F0Kr6J8FHk8GZ4JSkkS+lu+s18mIhWom1S3R4
IPyiFK5aJEvP6VmxZCO5InXk4EKftb4d41HHaauOrWrT7yDc2RI+ca1f9jUs8gUj
DT617DBJPXBIfHtxpIBrorR1Xy6eTOCv3d9Xs6AbdXWY7cSkuySPjh8muQvWdtPA
ZZWTZJVBESvJUsNBBtctVWoTJeJgaSqX7MKtQ8rL/ST794TBFrf0uPOuJXcTeFRO
TOjAfIVhT6vn+FGOzITZHmHDX8qoDMUCAwEAAaNTMFEwHQYDVR0OBBYEFAIv6+5g
m6TTzkNJKQpCWcG1uCDfMB8GA1UdIwQYMBaAFAIv6+5gm6TTzkNJKQpCWcG1uCDf
MA8GA1UdEwEB/wQFMAMBAf8wDQYJKoZIhvcNAQELBQADggEBANLHD5ToQ/AuYPFJ
rnW5sg+I0Mnpj/vAUVXCF7I98dQgnIUXB4t/h7Ir5Oz4JUP6d2koih5eSi+71ROm
ehcH2txvuvg90i0cnT9oGbaWEvK5m8+axn14uSqfk/tX0EcRZT5WjwAT+m1TPCUs
+EuukhZoAIsJXlcFwo9oKNsIUGMoy4+WmHFWatUpeW2fQo2j5f2tsMXgCBUQZgQd
1dc6ijlMcB5ymzGsYaCKTKCTdU+8tN6/QEh1WTGpesjYou0nhYVCzS/mk0GJ+RLk
EnxlzPPcXzRpTBkH98NpaLYHlRmaU5BSZIwyMLQ3Zsil82b4NcrSu99bB+0OCYY3
x5Y7CG0=
-----END CERTIFICATE-----
''';

const mockProjectId = 'test-project';

/// Key ID used when minting test tokens — must match the key in the mock
/// certificate response returned by the [mockCertUrl] interceptor.
const mockCertKid = 'test-key-1';

/// The Google X.509 certificate endpoint that `dart_firebase_admin` fetches
/// public keys from during ID token verification.
const mockCertUrl =
    'https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com';

/// Returns an [http.Client] that intercepts [mockCertUrl] and responds with
/// the test X.509 certificate keyed by [mockCertKid].
http.Client mockFetchPublicKeysClient() {
  return MockClient((request) async {
    if (request.url.toString() == mockCertUrl) {
      return http.Response(
        jsonEncode({mockCertKid: mockCertPem}),
        200,
        headers: {'cache-control': 'public, max-age=3600'},
      );
    }
    return http.Response('Not found', 404);
  });
}

/// Creates a [FirebaseApp] wired to a mock certificate HTTP client and
/// registers a matching [Auth] instance against it.
///
/// Returns both so callers can pass `app` to `runFunctionsTest` and `auth`
/// to `extractAuthToken` directly.
///
/// Remember to call `FirebaseApp.deleteApp(app)` in `tearDown`.
({FirebaseApp app, Auth auth}) createMockAuthApp({String? appName}) {
  final name = appName ?? 'mock-auth-${DateTime.now().microsecondsSinceEpoch}';

  final app = FirebaseApp.initializeApp(
    name: name,
    options: AppOptions(
      credential: Credential.fromServiceAccountParams(
        privateKey: mockPrivateKeyPem,
        email: 'test@$mockProjectId.iam.gserviceaccount.com',
        projectId: mockProjectId,
      ),
      projectId: mockProjectId,
    ),
  );

  final tokenVerifier = FirebaseTokenVerifier(
    clientCertUrl: Uri.parse(mockCertUrl),
    issuer: Uri.parse('https://securetoken.google.com/'),
    tokenInfo: FirebaseTokenInfo(
      url: Uri.parse(
        'https://firebase.google.com/docs/auth/admin/verify-id-tokens',
      ),
      verifyApiName: 'verifyIdToken()',
      jwtName: 'Firebase ID token',
      shortName: 'ID token',
      expiredErrorCode: AuthClientErrorCode.idTokenExpired,
    ),
    app: app,
    httpClient: mockFetchPublicKeysClient(),
  );

  final auth = Auth.internal(app, idTokenVerifier: tokenVerifier);
  return (app: app, auth: auth);
}

/// Mints a real RS256-signed Firebase ID token using [mockPrivateKeyPem].
String mintIdToken({
  String uid = 'test-uid',
  int? exp,
  int? iat,
  String? projectId,
  String kid = mockCertKid,
  Map<String, dynamic> extraClaims = const {},
}) {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final project = projectId ?? mockProjectId;

  final payload = {
    'iss': 'https://securetoken.google.com/$project',
    'aud': project,
    'auth_time': now,
    'uid': uid,
    'sub': uid,
    'iat': iat ?? now,
    'exp': exp ?? (now + 3600),
    'firebase': {
      'identities': <String, dynamic>{},
      'sign_in_provider': 'custom',
    },
    ...extraClaims,
  };

  return JWT(
    payload,
    header: {'kid': kid},
  ).sign(RSAPrivateKey(mockPrivateKeyPem), algorithm: JWTAlgorithm.RS256);
}

/// Flips the last character of a JWT signature to produce an invalid token.
String tamperToken(String token) {
  final parts = token.split('.');
  final sig = parts[2];
  final tampered = sig.endsWith('A')
      ? '${sig.substring(0, sig.length - 1)}B'
      : '${sig.substring(0, sig.length - 1)}A';
  return '${parts[0]}.${parts[1]}.$tampered';
}
