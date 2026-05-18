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
import 'dart:io';

import 'package:meta/meta.dart';

/// Provides unified access to environment variables, emulator checks, and
/// Google Cloud / Firebase configuration.
class FirebaseEnv {
  FirebaseEnv() : environment = mockEnvironment ?? Platform.environment;

  @internal
  static Map<String, String>? mockEnvironment;

  final Map<String, String> environment;

  /// Whether running within a Firebase emulator environment.
  bool get isEmulator {
    // Explicit functions emulator flag
    return environment['FUNCTIONS_EMULATOR'] == 'true' ||
        // Generic fallback: check if any common emulator hosts are configured
        _emulatorHostKeys.any(environment.containsKey);
  }

  /// Timezone setting.
  String get tz => environment['TZ'] ?? 'UTC';

  /// Whether debug mode is enabled.
  bool get debugMode => environment['FIREBASE_DEBUG_MODE'] == 'true';

  /// Whether to skip token verification (emulator only).
  bool get skipTokenVerification => _getDebugFeature('skipTokenVerification');

  /// Whether CORS is enabled (emulator only).
  bool get enableCors => _getDebugFeature('enableCors');

  bool _getDebugFeature(String key) {
    if (environment['FIREBASE_DEBUG_FEATURES'] case final String json) {
      try {
        if (jsonDecode(json) case final Map<String, dynamic> m) {
          return switch (m[key]) {
            final bool value => value,
            _ => false,
          };
        }
      } on FormatException {
        // ignore
      }
    }
    return false;
  }

  /// Returns the current Firebase project ID.
  ///
  /// Checks standard environment variables in order:
  /// 1. FIREBASE_PROJECT
  /// 2. GCLOUD_PROJECT
  /// 3. GOOGLE_CLOUD_PROJECT
  /// 4. GCP_PROJECT
  ///
  /// If none are set, throws [StateError].
  String get projectId {
    for (final option in _projectIdEnvKeyOptions) {
      final value = environment[option];
      if (value != null && value.isNotEmpty) return value;
    }

    throw StateError(
      'No project ID found in environment. Checked: ${_projectIdEnvKeyOptions.join(', ')}',
    );
  }

  /// The port to listen on.
  ///
  /// Uses the `PORT` environment variable, defaulting to 8080.
  int get port => int.tryParse(environment['PORT'] ?? '8080') ?? 8080;

  /// The name of the Cloud Run service.
  ///
  /// Uses the `K_SERVICE` environment variable.
  ///
  /// See https://cloud.google.com/run/docs/container-contract#env-vars
  String? get kService => environment['K_SERVICE'];

  /// The name of the target function.
  ///
  /// Uses the `FUNCTION_TARGET` environment variable.
  ///
  /// See https://docs.cloud.google.com/run/docs/configuring/services/environment-variables#additional_reserved_environment_variables_when_deploying_functions
  String? get functionTarget => environment['FUNCTION_TARGET'];

  /// Whether the functions control API is enabled.
  ///
  /// Uses the `FUNCTIONS_CONTROL_API` environment variable.
  ///
  /// This is part of the contract with `firebase-tools`.
  bool get functionsControlApi =>
      environment['FUNCTIONS_CONTROL_API'] == 'true';
}

/// Common project ID environment variables checked in order.
const _projectIdEnvKeyOptions = [
  'FIREBASE_PROJECT',
  'GCLOUD_PROJECT',
  'GOOGLE_CLOUD_PROJECT',
  'GCP_PROJECT',
];

/// Common emulator host keys used to detect emulator environment.
const _emulatorHostKeys = [
  'FIRESTORE_EMULATOR_HOST',
  'FIREBASE_AUTH_EMULATOR_HOST',
  'FIREBASE_DATABASE_EMULATOR_HOST',
  'FIREBASE_STORAGE_EMULATOR_HOST',
];
