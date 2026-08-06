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

/// Authentication and App Check token extraction for callable functions.
library;

import 'dart:convert';

import 'package:firebase_admin_sdk/app_check.dart';
import 'package:firebase_admin_sdk/auth.dart';
import 'package:firebase_admin_sdk/firebase_admin_sdk.dart';

import 'callable.dart';

/// Status of token validation.
enum TokenStatus {
  /// Token is missing from request.
  missing,

  /// Token is present but invalid.
  invalid,

  /// Token is present and valid.
  valid,
}

/// Result of checking auth and app check tokens.
class TokenVerificationResult {
  const TokenVerificationResult({required this.auth, required this.app});

  /// Status of the Firebase Auth ID token.
  final TokenStatus auth;

  /// Status of the App Check token.
  final TokenStatus app;
}

/// Regular expression for validating JWT format.
/// Allows empty signature for emulator tokens (alg: none).
final _jwtRegex = RegExp(
  r'^[a-zA-Z0-9\-_]+\.[a-zA-Z0-9\-_]+\.[a-zA-Z0-9\-_]*$',
);

/// Extracts and validates auth token from request.
///
/// In emulator mode (when [auth] is `null`), tokens are decoded
/// but not verified. In production, tokens are verified using the Firebase
/// Admin SDK.
///
/// The [auth] is required for production token verification.
///
/// Returns a tuple of (TokenStatus, AuthData?).
Future<(TokenStatus, AuthData?)> extractAuthToken(
  Map<String, String> headers, {
  Auth? auth,
}) async {
  final authorization = headers['authorization'];
  if (authorization == null || authorization.isEmpty) {
    return (TokenStatus.missing, null);
  }

  // Parse "Bearer <token>" format
  final match = RegExp(
    r'^Bearer\s+(.*)$',
    caseSensitive: false,
  ).firstMatch(authorization);
  if (match == null) {
    return (TokenStatus.invalid, null);
  }

  final idToken = match.group(1)!;

  try {
    String uid;
    Map<String, dynamic>? decodedToken;

    if (auth == null) {
      // In emulator mode, just decode without verification
      decodedToken = _unsafeDecodeIdToken(idToken);

      uid =
          decodedToken['uid'] as String? ??
          decodedToken['sub'] as String? ??
          decodedToken['user_id'] as String? ??
          '';
    } else {
      // In production, verify the token using Firebase Admin SDK
      final decoded = await auth.verifyIdToken(idToken);
      uid = decoded.uid;
      decodedToken = {
        'uid': decoded.uid,
        'sub': decoded.sub,
        'aud': decoded.aud,
        'iss': decoded.iss,
        'iat': decoded.iat,
        'exp': decoded.exp,
        if (decoded.email != null) 'email': decoded.email,
        if (decoded.emailVerified != null)
          'email_verified': decoded.emailVerified,
        if (decoded.phoneNumber != null) 'phone_number': decoded.phoneNumber,
        if (decoded.picture != null) 'picture': decoded.picture,
      };
    }

    if (uid.isEmpty) {
      return (TokenStatus.invalid, null);
    }

    return (
      TokenStatus.valid,
      AuthData(uid: uid, token: decodedToken, rawToken: idToken),
    );
  } catch (e) {
    return (TokenStatus.invalid, null);
  }
}

/// Extracts and validates App Check token from request.
///
/// In emulator mode (when [appCheck] is `null`), tokens are decoded
/// but not verified. In production, tokens are verified using the Firebase
/// Admin SDK.
///
/// The [appCheck] is required for production token verification.
///
/// Returns a tuple of (TokenStatus, AppCheckData?).
Future<(TokenStatus, AppCheckData?)> extractAppCheckToken(
  Map<String, String> headers, {
  AppCheck? appCheck,
}) async {
  final appCheckToken = headers['x-firebase-appcheck'];
  if (appCheckToken == null || appCheckToken.isEmpty) {
    return (TokenStatus.missing, null);
  }

  try {
    String appId;

    if (appCheck == null) {
      // In emulator mode, just decode without verification
      final decodedToken = _unsafeDecodeAppCheckToken(appCheckToken);

      appId =
          decodedToken['app_id'] as String? ??
          decodedToken['sub'] as String? ??
          '';
    } else {
      // In production, verify the token using Firebase Admin SDK
      final decoded = await appCheck.verifyToken(appCheckToken);
      appId = decoded.appId;
    }

    if (appId.isEmpty) {
      return (TokenStatus.invalid, null);
    }

    return (
      TokenStatus.valid,
      AppCheckData(appId: appId, token: appCheckToken),
    );
  } catch (e) {
    return (TokenStatus.invalid, null);
  }
}

/// Checks both auth and app check tokens on a request.
///
/// This is the same verification `onCall`/`onCallWithData` run internally;
/// use it directly inside an `onRequest` handler to get Auth and App Check
/// verification without reimplementing header parsing.
///
/// Pass `adminApp: null` to skip verification and decode tokens unchecked
/// (emulator mode).
///
/// Returns a record containing the verification result and extracted data.
///
/// Example:
/// ```dart
/// firebase.https.onRequest(
///   name: 'secureEndpoint',
///   (request) async {
///     final tokens = await checkTokens(
///       request.headers,
///       adminApp: firebase.adminApp,
///     );
///     final authData = tokens.authData;
///     if (tokens.result.auth != TokenStatus.valid || authData == null) {
///       return Response.forbidden('Unauthorized');
///     }
///     return Response.ok('Hello, ${authData.uid}!');
///   },
/// );
/// ```
Future<
  ({
    TokenVerificationResult result,
    AuthData? authData,
    AppCheckData? appCheckData,
  })
>
checkTokens(Map<String, String> headers, {FirebaseApp? adminApp}) async {
  final (authStatus, authData) = await extractAuthToken(
    headers,
    auth: adminApp?.auth(),
  );

  final (appStatus, appCheckData) = await extractAppCheckToken(
    headers,
    appCheck: adminApp?.appCheck(),
  );

  return (
    result: TokenVerificationResult(auth: authStatus, app: appStatus),
    authData: authData,
    appCheckData: appCheckData,
  );
}

// --- Private unsafe decode functions (for emulator mode only) ---

/// Decodes a JWT token without verification.
///
/// **WARNING**: Only use in emulator mode.
Map<String, dynamic> _unsafeDecodeToken(String token) {
  if (!_jwtRegex.hasMatch(token)) {
    return {};
  }

  final parts = token.split('.');
  if (parts.length != 3) {
    return {};
  }

  try {
    final payloadBase64 = parts[1];
    final normalized = base64Url.normalize(payloadBase64);
    final payloadJson = utf8.decode(base64Url.decode(normalized));
    final payload = jsonDecode(payloadJson);

    if (payload is Map<String, dynamic>) {
      return payload;
    }
    return {};
  } catch (e) {
    return {};
  }
}

/// Decodes an ID token without verification.
///
/// **WARNING**: Only use in emulator mode.
Map<String, dynamic> _unsafeDecodeIdToken(String token) {
  final decoded = _unsafeDecodeToken(token);
  // Set uid from sub claim if not already present
  if (!decoded.containsKey('uid') && decoded.containsKey('sub')) {
    decoded['uid'] = decoded['sub'];
  }
  return decoded;
}

/// Decodes an App Check token without verification.
///
/// **WARNING**: Only use in emulator mode.
Map<String, dynamic> _unsafeDecodeAppCheckToken(String token) {
  final decoded = _unsafeDecodeToken(token);
  // Set app_id from sub claim if not already present
  if (!decoded.containsKey('app_id') && decoded.containsKey('sub')) {
    decoded['app_id'] = decoded['sub'];
  }
  return decoded;
}
