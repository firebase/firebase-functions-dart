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

/// JWT token verification for Auth Blocking functions.
library;

import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:google_cloud_shelf/google_cloud_shelf.dart';
import 'package:http/http.dart' as http;

/// URL to fetch Google's public keys in JWK format for JWT verification.
/// This endpoint returns keys directly as JWKs, no certificate parsing needed.
const _googleJwksUrl = 'https://www.googleapis.com/oauth2/v3/certs';

/// Cache duration for Google keys (1 hour default).
const _keysCacheDuration = Duration(hours: 1);

/// Verifier for Auth Blocking JWT tokens.
///
/// This class handles JWT signature verification and claims validation
/// for Identity Platform blocking functions.
///
/// In production, tokens are verified against Google's public keys.
/// In emulator/debug mode, verification can be skipped.
class AuthBlockingTokenVerifier {
  AuthBlockingTokenVerifier({
    required this.projectId,
    this.isEmulator = false,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  final String projectId;
  final bool isEmulator;
  final http.Client _httpClient;

  /// Cached public keys.
  static Map<String, JWTKey>? _cachedKeys;

  /// When the cached keys expire.
  static DateTime? _keysExpireAt;

  /// Expected issuer for Auth Blocking tokens.
  String get _expectedIssuer => 'https://securetoken.google.com/$projectId';

  /// Default audience for GCF v1.
  String get _defaultAudience => '$projectId.cloudfunctions.net/';

  /// Verifies an Auth Blocking JWT token and returns the decoded payload.
  ///
  /// If [audience] is provided, it's used for audience validation.
  /// For Cloud Run (GCF v2), pass `"run.app"` as the audience.
  ///
  /// Throws [HttpResponseException] if verification fails.
  Future<Map<String, dynamic>> verifyToken(
    String token, {
    String? audience,
  }) async {
    // In emulator mode, just decode without verification
    if (isEmulator) {
      return _unsafeDecode(token);
    }

    // Decode the token first to get the header
    JWT decoded;
    try {
      decoded = JWT.decode(token);
    } catch (e) {
      throw HttpResponseException.unauthorized(
        message: 'Invalid JWT format: $e',
      );
    }

    final kid = decoded.header?['kid'];
    if (kid is! String) {
      throw HttpResponseException.unauthorized(
        message: 'Invalid JWT: missing "kid" header or not String',
      );
    }

    // Get the keys from Google
    final keys = await _getGoogleKeys();
    final key = keys[kid];

    if (key == null) {
      throw HttpResponseException.unauthorized(
        message: 'Invalid JWT: unknown "kid"',
      );
    }

    // Verify the token using dart_jsonwebtoken
    try {
      JWT.verify(token, key);
    } on JWTException catch (e) {
      throw HttpResponseException.unauthorized(
        message: 'Invalid JWT: ${e.message}',
      );
    } catch (e) {
      throw HttpResponseException.unauthorized(message: 'Invalid JWT: $e');
    }

    // Extract the payload as a map
    final payload = decoded.payload as Map<String, dynamic>;

    // Validate Firebase-specific claims
    _validateClaims(payload, audience);

    return payload;
  }

  /// Decodes a JWT without verification (for emulator mode only).
  Map<String, dynamic> _unsafeDecode(String token) {
    try {
      final decoded = JWT.decode(token);
      return decoded.payload as Map<String, dynamic>;
    } catch (e) {
      throw HttpResponseException.badRequest(message: 'Invalid JWT format');
    }
  }

  /// Fetches Google's public keys and returns a map of kid to JWTKey.
  ///
  /// Uses the JWK endpoint which returns keys directly in JSON Web Key format,
  /// so no manual certificate parsing is needed.
  Future<Map<String, JWTKey>> _getGoogleKeys() async {
    // Return cached keys if still valid
    if (_cachedKeys != null &&
        _keysExpireAt != null &&
        DateTime.now().isBefore(_keysExpireAt!)) {
      return _cachedKeys!;
    }

    // Fetch keys from Google's JWK endpoint
    final response = await _httpClient.get(Uri.parse(_googleJwksUrl));

    if (response.statusCode != 200) {
      throw StateError(
        'Failed to fetch Google public keys from $_googleJwksUrl: ${response.statusCode}',
      );
    }

    // Parse the JWK Set response
    final jwksJson = jsonDecode(response.body) as Map<String, dynamic>;
    final newKeys = <String, JWTKey>{};

    // The response contains a "keys" array with JWK objects
    final keys = jwksJson['keys'] as List<dynamic>?;
    if (keys != null) {
      for (final keyJson in keys) {
        try {
          final jwk = keyJson as Map<String, dynamic>;
          final kid = jwk['kid'] as String?;
          if (kid != null) {
            newKeys[kid] = JWTKey.fromJWK(jwk);
          }
        } catch (e) {
          // Skip keys that fail to parse
          continue;
        }
      }
    }

    // Cache with expiration from Cache-Control header or default
    final cacheControl = response.headers['cache-control'];
    var cacheDuration = _keysCacheDuration;

    if (cacheControl != null) {
      final maxAgeMatch = RegExp(r'max-age=(\d+)').firstMatch(cacheControl);
      if (maxAgeMatch != null) {
        cacheDuration = Duration(seconds: int.parse(maxAgeMatch.group(1)!));
      }
    }

    _cachedKeys = newKeys;
    _keysExpireAt = DateTime.now().add(cacheDuration);

    return newKeys;
  }

  /// Validates JWT claims.
  void _validateClaims(Map<String, dynamic> payload, String? audience) {
    // Validate issuer
    final iss = payload['iss'] as String?;
    if (iss != _expectedIssuer) {
      throw HttpResponseException.unauthorized(
        message: 'Invalid token issuer. Expected $_expectedIssuer, got $iss',
      );
    }

    // Validate audience
    final aud = payload['aud'];
    final expectedAudience = audience ?? _defaultAudience;

    bool audienceValid;
    if (aud is String) {
      audienceValid = aud == expectedAudience || aud.contains(expectedAudience);
    } else if (aud is List) {
      audienceValid = aud.any(
        (a) =>
            a == expectedAudience || (a as String).contains(expectedAudience),
      );
    } else {
      audienceValid = false;
    }

    if (!audienceValid) {
      throw HttpResponseException.unauthorized(
        message: 'Invalid token audience. Expected $expectedAudience, got $aud',
      );
    }

    // Validate expiration
    final exp = payload['exp'] as int?;
    if (exp == null) {
      throw HttpResponseException.unauthorized(
        message: 'Token missing expiration claim',
      );
    }

    final expiration = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
    if (DateTime.now().isAfter(expiration)) {
      throw HttpResponseException.unauthorized(message: 'Token has expired');
    }

    // Validate issued-at (not in the future)
    final iat = payload['iat'] as int?;
    if (iat != null) {
      final issuedAt = DateTime.fromMillisecondsSinceEpoch(iat * 1000);
      // Allow 5 minutes of clock skew
      if (issuedAt.isAfter(DateTime.now().add(const Duration(minutes: 5)))) {
        throw HttpResponseException.unauthorized(
          message: 'Token issued in the future',
        );
      }
    }

    // Validate subject (except for beforeSendEmail/beforeSendSms)
    final eventType = payload['event_type'] as String?;
    if (eventType != 'beforeSendEmail' && eventType != 'beforeSendSms') {
      final sub = payload['sub'] as String?;
      if (sub == null || sub.isEmpty) {
        throw HttpResponseException.unauthorized(
          message: 'Token missing subject claim',
        );
      }
      if (sub.length > 128) {
        throw HttpResponseException.unauthorized(
          message: 'Token subject exceeds 128 characters',
        );
      }
    }
  }

  /// Clears the key cache (useful for testing).
  static void clearCertificateCache() {
    _cachedKeys = null;
    _keysExpireAt = null;
  }
}
