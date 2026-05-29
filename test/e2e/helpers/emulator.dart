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

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Helper for managing Firebase Functions Emulator lifecycle in tests.
class EmulatorHelper {
  EmulatorHelper({
    required this.projectPath,
    this.functionsPort = 5001,
    this.pubsubPort = 8085,
    this.firestorePort = 8080,
    this.databasePort = 9000,
    this.authPort = 9099,
    this.storagePort = 9199,
    this.startupTimeout = const Duration(seconds: 90),
  });
  Process? _process;
  final String projectPath;
  final int functionsPort;
  final int pubsubPort;
  final int firestorePort;
  final int databasePort;
  final int authPort;
  final int storagePort;
  final Duration startupTimeout;

  // Completer to signal when emulator is ready
  Completer<void>? _readyCompleter;

  // Buffer to store emulator output for verification
  final List<String> _outputLines = [];
  final List<String> _errorLines = [];

  /// Starts the Firebase emulator and waits for it to be ready.
  Future<void> start() async {
    print('Starting Firebase emulator...');

    // Check if firebase CLI is available
    final firebaseCmd = await _findFirebaseCli();
    if (firebaseCmd == null) {
      throw Exception(
        'Firebase CLI not found. Please install: npm install -g firebase-tools',
      );
    }

    print('Using Firebase CLI: $firebaseCmd');

    // Parse command into executable and base arguments
    final cmdParts = firebaseCmd.split(' ');
    final executable = cmdParts.first;
    final baseArgs = cmdParts.skip(1).toList();

    // Start the emulator with debug logging
    _process = await Process.start(
      executable,
      [
        ...baseArgs,
        'emulators:start',
        '--only',
        'functions,pubsub,firestore,database,auth,storage',
        '--project',
        'demo-test',
        '--non-interactive',
      ],
      workingDirectory: projectPath,
      environment: {
        'FIREBASE_EMULATOR_HUB': 'true',
        'FIREBASE_CLI_EXPERIMENTS': 'dartfunctions',
        ...Platform.environment,
        'GOOGLE_APPLICATION_CREDENTIALS':
            '${Directory(projectPath).parent.path}/dummy_service_account.json',
      },
    );

    // Create completer to signal readiness
    _readyCompleter = Completer<void>();

    // Capture output for debugging and detect readiness
    _process!.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((
      line,
    ) {
      print('[EMULATOR] $line');
      _outputLines.add(line);

      // Detect when emulator is ready
      // We need to wait for functions to be initialized, not just the emulator hub
      // Look for "http function initialized" which indicates triggers are registered
      if (line.contains('http function initialized') ||
          line.contains('All emulators ready') ||
          line.contains('All emulators started') ||
          line.contains('It is now safe to connect')) {
        if (!_readyCompleter!.isCompleted) {
          _readyCompleter!.complete();
        }
      }
    });

    _process!.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          print('[EMULATOR ERROR] $line');
          _errorLines.add(line);
        });

    // Wait for emulator to be ready
    try {
      print('Waiting for emulator to be ready...');
      await _waitForReady();

      // Additional wait to ensure Dart runtime is fully initialized
      // The first request triggers Dart process startup which takes ~2-3 seconds
      print('Waiting for Dart runtime to stabilize...');
      await Future<void>.delayed(const Duration(seconds: 2));
      print('✓ Emulator is ready');
    } catch (e) {
      print('Error starting emulator: $e');
      await stop();
      rethrow;
    }
  }

  /// Stops the Firebase emulator.
  Future<void> stop() async {
    if (_process == null) return;

    print('Stopping Firebase emulator...');

    // Try graceful shutdown first
    _process!.kill();

    // Wait a bit for graceful shutdown
    await Future<void>.delayed(const Duration(seconds: 2));

    // Force kill if still running
    if (!_process!.kill(ProcessSignal.sigkill)) {
      print('Warning: Could not kill emulator process');
    }

    _process = null;
    print('✓ Emulator stopped');
  }

  /// Waits for the emulator to be ready by monitoring stdout and polling the hub.
  Future<void> _waitForReady() async {
    final client = HttpClient();
    final deadline = DateTime.now().add(startupTimeout);

    while (DateTime.now().isBefore(deadline)) {
      // Check if ready message was received
      if (_readyCompleter!.isCompleted) {
        client.close();
        return;
      }

      // Poll the hello-world function endpoint as a fallback
      // We poll a specific function to ensure triggers are registered, not just the server
      try {
        final request = await client
            .getUrl(
              Uri.parse(
                'http://127.0.0.1:$functionsPort/demo-test/us-central1/hello-world',
              ),
            )
            .timeout(const Duration(seconds: 5));
        final response = await request.close().timeout(
          const Duration(seconds: 5),
        );
        await response.drain<void>();
        // Only consider ready if we get 200 (not 404 which means function not registered)
        if (response.statusCode == 200) {
          print('Function hello-world responding on port $functionsPort');
          client.close();
          if (!_readyCompleter!.isCompleted) {
            _readyCompleter!.complete();
          }
          return;
        } else if (response.statusCode == 404) {
          // Function not registered yet, keep waiting
          print('Waiting for functions to be registered (got 404)...');
        }
      } catch (e) {
        // Connection failed, emulator not ready yet
      }

      await Future<void>.delayed(const Duration(seconds: 1));
    }

    client.close();
    throw TimeoutException(
      'Emulator did not start within ${startupTimeout.inSeconds} seconds',
    );
  }

  /// Finds the Firebase CLI executable.
  Future<String?> _findFirebaseCli() async {
    // First, try to find the custom firebase-tools with Dart support
    // This is in the parent directory structure: ../../firebase-tools
    final customFirebasePath = _findCustomFirebaseCli();
    if (customFirebasePath != null) {
      try {
        final result = await Process.run('node', [
          customFirebasePath,
          '--version',
        ]);
        if (result.exitCode == 0) {
          print(
            'Using custom firebase-tools with Dart support: $customFirebasePath',
          );
          return 'node $customFirebasePath';
        }
      } catch (e) {
        // Custom version not found or failed, try standard locations
      }
    }

    // Try common locations
    final candidates = [
      'firebase', // In PATH
      'npx firebase', // Via npx
      '/usr/local/bin/firebase',
      if (Platform.environment['HOME'] != null)
        '${Platform.environment['HOME']}/.npm-global/bin/firebase'
      else
        null,
    ].where((c) => c != null).cast<String>();

    for (final cmd in candidates) {
      try {
        final result = await Process.run(cmd.split(' ').first, [
          ...cmd.split(' ').skip(1),
          '--version',
        ]);

        if (result.exitCode == 0) {
          return cmd;
        }
      } catch (e) {
        // Command not found, try next
        continue;
      }
    }

    return null;
  }

  /// Finds the custom firebase-tools CLI with Dart support.
  /// Returns the path to lib/bin/firebase.js if found.
  String? _findCustomFirebaseCli() {
    // Start from current directory and traverse up looking for firebase-tools
    var dir = Directory.current;

    // Check both possible directory names:
    // - 'firebase-tools' (local development)
    // - 'custom-firebase-tools' (CI environment)
    const possibleDirNames = ['firebase-tools', 'custom-firebase-tools'];

    for (var i = 0; i < 5; i++) {
      // Only check up to 5 levels
      for (final dirName in possibleDirNames) {
        final firebaseToolsPath = '${dir.path}/$dirName/lib/bin/firebase.js';
        if (File(firebaseToolsPath).existsSync()) {
          return firebaseToolsPath;
        }
      }

      final parentDir = dir.parent;
      if (parentDir.path == dir.path) {
        break; // Reached root
      }
      dir = parentDir;
    }

    return null;
  }

  /// Gets the base URL for the functions emulator.
  String get functionsUrl =>
      'http://localhost:$functionsPort/demo-test/us-central1';

  /// Gets the base URL for the Pub/Sub emulator.
  String get pubsubUrl => 'http://localhost:$pubsubPort';

  /// Gets the base URL for the Firestore emulator REST API.
  String get firestoreUrl =>
      'http://localhost:$firestorePort/v1/projects/demo-test/databases/(default)/documents';

  /// Gets the base URL for the Realtime Database emulator REST API.
  String get databaseUrl => 'http://localhost:$databasePort';

  /// Gets the base URL for the Auth emulator REST API.
  String get authUrl => 'http://localhost:$authPort';

  /// Gets the base URL for the Storage emulator REST API.
  String get storageUrl => 'http://localhost:$storagePort';

  /// Verifies that a function was executed in the emulator logs.
  /// Returns true if we find both "Beginning execution" and "Finished" messages.
  bool verifyFunctionExecution(String functionName) {
    final executionStart = _outputLines.any(
      (line) => line.contains('Beginning execution of "$functionName"'),
    );
    final executionEnd = _outputLines.any(
      (line) => line.contains('Finished "$functionName"'),
    );

    return executionStart && executionEnd;
  }

  /// Verifies that the Dart runtime actually processed a request.
  /// Looks for the Shelf server request logs (timestamp + method + status + path).
  bool verifyDartRuntimeRequest(String method, int statusCode, String path) {
    // Look for logs like: "2025-11-20T08:19:30.853342  0:00:00.000395 GET     [200] /helloWorld"
    final pattern = RegExp(
      r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+\s+\d+:\d+:\d+\.\d+\s+' +
          RegExp.escape(method) +
          r'\s+\[' +
          statusCode.toString() +
          r'\]\s+' +
          RegExp.escape(path),
    );

    return _outputLines.any(pattern.hasMatch);
  }

  /// Gets all output lines captured from the emulator.
  List<String> get outputLines => List.unmodifiable(_outputLines);

  /// Gets all error lines captured from the emulator.
  List<String> get errorLines => List.unmodifiable(_errorLines);

  /// Clears the output buffer (useful for testing specific requests).
  void clearOutputBuffer() {
    _outputLines.clear();
    _errorLines.clear();
  }
}
