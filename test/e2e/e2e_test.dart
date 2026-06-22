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

/// Main entry point for E2E tests.
/// Sets up a single emulator instance and runs all E2E test groups.
@Tags(['e2e'])
library;

import 'dart:io';

import 'package:test/test.dart';

import 'helpers/auth_client.dart';
import 'helpers/database_client.dart';
import 'helpers/emulator.dart';
import 'helpers/firestore_client.dart';
import 'helpers/hosting_client.dart';
import 'helpers/http_client.dart';
import 'helpers/pubsub_client.dart';
import 'helpers/storage_client.dart';
import 'helpers/test_client_base.dart';
import 'tests/database_tests.dart';
import 'tests/firestore_tests.dart';
import 'tests/hosting_tests.dart';
import 'tests/https_oncall_tests.dart';
import 'tests/https_onrequest_tests.dart';
import 'tests/identity_tests.dart';
import 'tests/integration_tests.dart';
import 'tests/pubsub_tests.dart';
import 'tests/scheduler_tests.dart';
import 'tests/storage_tests.dart';

void main() {
  EmulatorHelper? emulator;
  FunctionsHttpClient? client;
  HostingHttpClient? hostingClient;
  PubSubClient? pubsubClient;
  FirestoreClient? firestoreClient;
  DatabaseClient? databaseClient;
  AuthClient? authClient;
  StorageClient? storageClient;

  // Debug: Show Directory.current.path at module load time
  print('DEBUG e2e_test: Directory.current.path = ${Directory.current.path}');

  final examplePath = '${Directory.current.path}/test/fixtures/dart_reference'
      .replaceAll('/test/e2e', '');

  print('DEBUG e2e_test: examplePath = $examplePath');

  setUpAll(() async {
    print('');
    print('========================================');
    print('Setting up Firebase Emulator for E2E tests');
    print('========================================');
    print('');

    // Build the functions first
    print('Building functions...');
    final buildResult = await Process.run('dart', [
      'run',
      'build_runner',
      'build',
      '--delete-conflicting-outputs',
    ], workingDirectory: examplePath);

    if (buildResult.exitCode != 0) {
      throw Exception('Failed to build functions: ${buildResult.stderr}');
    }

    print('✓ Functions built successfully');

    // Debug: Check if functions.yaml exists after build
    final functionsYamlPath = '$examplePath/functions.yaml';
    final functionsYamlFile = File(functionsYamlPath);
    print(
      'DEBUG: After build, functions.yaml exists = ${functionsYamlFile.existsSync()}',
    );
    print('DEBUG: functionsYamlPath = $functionsYamlPath');

    print('');

    // Start the emulator
    emulator = EmulatorHelper(projectPath: examplePath);
    await emulator!.start();

    // Create HTTP client
    client = FunctionsHttpClient(emulator!.functionsUrl);

    // Create Hosting client
    hostingClient = HostingHttpClient(emulator!.hostingUrl);

    // Create Pub/Sub client
    pubsubClient = PubSubClient(emulator!.pubsubUrl, 'demo-test');

    // Create Firestore client
    firestoreClient = FirestoreClient(emulator!.firestoreUrl);

    // Create Database client
    databaseClient = DatabaseClient(emulator!.databaseUrl, 'demo-test');

    // Create Auth client
    authClient = AuthClient(emulator!.authUrl, 'demo-test');

    // Create Storage client
    storageClient = StorageClient(
      emulator!.storageUrl,
      'demo-test.firebasestorage.app',
    );

    // Give emulator a moment to fully initialize
    await Future<void>.delayed(const Duration(seconds: 2));
  });

  tearDownAll(() async {
    print('');
    print('========================================');
    print('Cleaning up');
    print('========================================');
    print('');

    try {
      for (final client in <TestClientBase>[
        ?client,
        ?hostingClient,
        ?pubsubClient,
        ?firestoreClient,
        ?databaseClient,
        ?authClient,
        ?storageClient,
      ]) {
        try {
          client.close();
        } catch (e, s) {
          print('Error closing client in tearDownAll: $e\n$s');
        }
      }
    } finally {
      await emulator?.stop();
    }
  });

  // Run all test groups (pass closures to defer value access)
  runHttpsOnRequestTests(() => client!, () => emulator!);
  runHostingTests(() => hostingClient!);
  runHttpsOnCallTests(() => client!);
  runIntegrationTests(() => examplePath);
  runPubSubTests(() => examplePath, () => pubsubClient!, () => emulator!);
  runFirestoreTests(() => examplePath, () => firestoreClient!, () => emulator!);
  runDatabaseTests(() => examplePath, () => databaseClient!, () => emulator!);
  runIdentityTests(() => examplePath, () => authClient!, () => emulator!);
  runStorageTests(() => examplePath, () => storageClient!, () => emulator!);
  runSchedulerTests(
    () => examplePath,
    () => emulator!,
    () => emulator!.functionsPort,
  );
}
