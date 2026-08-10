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

/// @docImport 'params.dart';
library;

import 'dart:async';

import '../logger/logger.dart' as logger;

/// Callback registered via [onInit].
FutureOr<void> Function()? _initCallback;

/// Whether the init callback has been executed.
bool _didInit = false;

/// Registers a callback to run once before any function executes.
///
/// Use this to safely initialize globals that depend on secrets or other
/// runtime-only values. The callback runs once before the first function
/// invocation, but NOT during deployment when secrets are unavailable.
///
/// This is particularly useful when you need to initialize SDK clients
/// that require API keys stored as secrets:
///
/// ```dart
/// import 'package:firebase_functions/firebase_functions.dart';
/// import 'package:some_api/some_api.dart';
///
/// final apiKey = defineSecret('API_KEY');
///
/// late SomeApiClient apiClient;
///
/// void main(List<String> args) {
///   // Register initialization that needs the secret
///   onInit(() {
///     apiClient = SomeApiClient(apiKey: apiKey.value());
///   });
///
///   runFunctions((firebase) {
///     firebase.https.onRequest(
///       name: 'api',
///       options: HttpsOptions(secrets: [apiKey]),
///       (request) async {
///         // apiClient is safely initialized here
///         final result = await apiClient.doSomething();
///         return Response.ok(result);
///       },
///     );
///   });
/// }
/// ```
///
/// **Important notes:**
/// - The callback runs only once, before the first function invocation
/// - It does NOT run during deployment (when `FUNCTIONS_CONTROL_API` is set)
/// - If you use secrets in your callback, you must bind them to all functions
///   that might trigger the initialization
/// - Calling this function more than once will overwrite the previous callback;
///   only the most recent callback will be called
///
/// See also:
/// - [defineSecret] for defining secret parameters
/// - [defineJsonSecret] for JSON-encoded secrets
void onInit(FutureOr<void> Function() callback) {
  if (_initCallback != null) {
    logger.warning(
      'Setting onInit callback more than once. '
      'Only the most recent callback will be called.',
    );
  }
  _initCallback = callback;
  _didInit = false;
}

/// Wraps a handler function to ensure [onInit] is called before execution.
///
/// This is used internally by the server to wrap function handlers.
/// The init callback runs at most once, regardless of how many functions
/// are invoked.
///
/// @internal
FutureOr<T> Function(R) withInit<T, R>(FutureOr<T> Function(R) handler) {
  return (R arg) async {
    if (!_didInit) {
      if (_initCallback != null) {
        await _initCallback!();
      }
      _didInit = true;
    }
    return await handler(arg);
  };
}

/// Wraps a void handler function to ensure [onInit] is called before execution.
///
/// Similar to [withInit] but for handlers that don't return a value.
///
/// @internal
FutureOr<void> Function(R) withInitVoid<R>(FutureOr<void> Function(R) handler) {
  return (R arg) async {
    if (!_didInit) {
      if (_initCallback != null) {
        await _initCallback!();
      }
      _didInit = true;
    }
    await handler(arg);
  };
}

/// Returns whether the init callback has been executed.
///
/// @internal
bool get didInit => _didInit;

/// Resets the init state. For testing only.
///
/// @internal
void resetInit() {
  _initCallback = null;
  _didInit = false;
}
