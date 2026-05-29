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

/// Testing utilities for Firebase Functions.
///
/// Import `package:firebase_functions/testing.dart` in your tests.
library;

import 'dart:convert';

import 'package:firebase_admin_sdk/firebase_admin_sdk.dart';
import 'package:shelf/shelf.dart';

import 'common/cloud_run_id.dart';
import 'common/environment.dart';
import 'common/on_init.dart';
import 'firebase.dart';
import 'server.dart' show FunctionsRunner;

export 'firebase.dart' show Firebase;

/// Sets up a [Firebase] instance for testing without starting an HTTP server.
///
/// The [runner] callback registers functions exactly as in production
/// (`firebase.https.onCall`, `firebase.https.onRequest`, etc.). The returned
/// [FunctionsTestClient] lets tests invoke those handlers in-process,
/// preserving the full request pipeline (token verification, error handling,
/// streaming) without network overhead or a running emulator.
///
/// Pass the [adminApp] you have already initialised for your test — typically
/// one whose `Auth` service is wired to a mock certificate HTTP client (see
/// `Auth.internal` and `FirebaseTokenVerifier`).
///
/// Example:
/// ```dart
/// final client = await runFunctionsTest(
///   adminApp: app,
///   (firebase) {
///     firebase.https.onCall(name: 'echo', (req, _) async {
///       return CallableResult({'uid': req.auth?.uid});
///     });
///   },
/// );
///
/// final response = await client.call('echo', data: {}, idToken: token);
/// expect(response.statusCode, 200);
/// ```
///
/// See also:
/// - [FunctionsTestClient] for invoking registered functions.
/// - `EmulatorHelper` (in `test/e2e/helpers/emulator.dart`) for full E2E
///   testing with the Firebase emulator.
Future<FunctionsTestClient> runFunctionsTest(
  FunctionsRunner runner, {
  required FirebaseApp adminApp,
}) async {
  final projectId =
      adminApp.options.projectId ??
      (throw ArgumentError(
        'adminApp must have a projectId set in its AppOptions.',
      ));

  FirebaseEnv.mockEnvironment = {'FIREBASE_PROJECT': projectId};
  try {
    final firebase = createTestFirebaseInternal(adminApp);
    await runner(firebase);
    return FunctionsTestClient._(firebase);
  } finally {
    FirebaseEnv.mockEnvironment = null;
  }
}

/// In-process test client returned by [runFunctionsTest].
///
/// Invokes registered function handlers directly without a network hop,
/// using the same [Request]/[Response] types as the production Shelf handler.
///
/// This is the unit/integration-test counterpart to `EmulatorHelper` +
/// `FunctionsHttpClient` used in E2E tests.
class FunctionsTestClient {
  FunctionsTestClient._(this._firebase);

  final Firebase _firebase;

  /// Invokes an `onCall` or `onCallWithData` function by [name].
  ///
  /// Constructs the standard callable wire format (`{"data": ...}`) and
  /// the optional `Authorization: Bearer <idToken>` header automatically.
  ///
  /// Returns the raw Shelf [Response]; use [parseCallableResponse] to extract
  /// the result payload.
  Future<Response> call(
    String name, {
    dynamic data,
    String? idToken,
    Map<String, String>? extraHeaders,
  }) {
    final headers = <String, String>{
      'content-type': 'application/json',
      if (idToken != null) 'authorization': 'Bearer $idToken',
      ...?extraHeaders,
    };
    final request = Request(
      'POST',
      Uri.parse('http://localhost/${toCloudRunId(name)}'),
      body: jsonEncode({'data': data}),
      headers: headers,
    );
    return _invoke(toCloudRunId(name), request);
  }

  /// Invokes an `onRequest` function by [name] with a raw Shelf [Request].
  Future<Response> request(String name, Request req) =>
      _invoke(toCloudRunId(name), req);

  /// Parses the `result` field from a successful callable [Response] body.
  ///
  /// Throws [FormatException] if the body is not valid JSON or does not
  /// contain a `result` key.
  Future<dynamic> parseCallableResponse(Response response) async {
    final body = await response.readAsString();
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('Response body is not a JSON object: $body');
    }
    return decoded['result'];
  }

  /// Removes all registered functions from this instance.
  ///
  /// Call this in `tearDown` when reusing the same [Firebase] instance across
  /// tests to prevent "function already registered" errors.
  void dispose() => _firebase.functions.clear();

  Future<Response> _invoke(String functionName, Request request) async {
    final fn = _firebase.functions
        .where((f) => f.name == functionName)
        .firstOrNull;
    if (fn == null) {
      throw ArgumentError(
        'No function registered with name "$functionName". '
        'Available: ${_firebase.functions.map((f) => f.name).join(', ')}',
      );
    }
    return withInit(fn.handler)(request);
  }
}
