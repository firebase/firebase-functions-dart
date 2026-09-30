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

import 'package:firebase_admin_sdk/firebase_admin_sdk.dart';
import 'package:firebase_functions/src/common/environment.dart';
import 'package:firebase_functions/src/firebase.dart';
import 'package:test/test.dart';

void main() {
  setUp(() async {
    FirebaseEnv.mockEnvironment = {'FIREBASE_PROJECT': 'demo-test'};
    await _deleteInitializedApps();
  });

  tearDown(() async {
    await _deleteInitializedApps();
    FirebaseEnv.mockEnvironment = null;
  });

  group('createFirebaseInternal', () {
    test('initializes a default Admin SDK app when none exists', () {
      final firebase = createFirebaseInternal();

      expect(FirebaseApp.apps, hasLength(1));
      expect(identical(firebase.adminApp, FirebaseApp.getApp()), isTrue);
      expect(firebase.adminApp.options.projectId, 'demo-test');
    });

    test('initializes a default Admin SDK app from FIREBASE_CONFIG alone', () {
      FirebaseEnv.mockEnvironment = {
        'FIREBASE_CONFIG': '{"projectId":"config-only-project"}',
      };

      final firebase = createFirebaseInternal();

      expect(FirebaseApp.apps, hasLength(1));
      expect(firebase.adminApp.options.projectId, 'config-only-project');
    });

    test('reuses an existing user-initialized default Admin SDK app', () {
      final userApp = FirebaseApp.initializeApp(
        options: AppOptions(
          credential: Credential.fromApplicationDefaultCredentials(),
          projectId: 'custom-project',
        ),
      );

      final firebase = createFirebaseInternal();

      expect(FirebaseApp.apps, hasLength(1));
      expect(identical(firebase.adminApp, userApp), isTrue);
      expect(firebase.adminApp.options.projectId, 'custom-project');
    });
  });

  group('FirebaseEnv.projectId', () {
    test('resolves projectId from inline FIREBASE_CONFIG JSON', () {
      FirebaseEnv.mockEnvironment = {
        'FIREBASE_CONFIG': '{"projectId":"inline-config-project"}',
      };

      expect(FirebaseEnv().projectId, 'inline-config-project');
    });

    test('resolves projectId from FIREBASE_CONFIG file path', () {
      final tempDir = Directory.systemTemp.createTempSync('firebase_env_test_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final configFile = File('${tempDir.path}/firebase_config.json')
        ..writeAsStringSync(jsonEncode({'projectId': 'file-config-project'}));

      FirebaseEnv.mockEnvironment = {'FIREBASE_CONFIG': configFile.path};

      expect(FirebaseEnv().projectId, 'file-config-project');
    });

    test('prefers FIREBASE_CONFIG projectId over flat env variables', () {
      FirebaseEnv.mockEnvironment = {
        'FIREBASE_CONFIG': '{"projectId":"from-firebase-config"}',
        'FIREBASE_PROJECT': 'from-firebase-project',
        'GCLOUD_PROJECT': 'from-gcloud-project',
      };

      expect(FirebaseEnv().projectId, 'from-firebase-config');
    });

    test(
      'falls back to flat env variables when FIREBASE_CONFIG lacks projectId',
      () {
        FirebaseEnv.mockEnvironment = {
          'FIREBASE_CONFIG': '{"storageBucket":"my-bucket.appspot.com"}',
          'GCLOUD_PROJECT': 'fallback-gcloud-project',
        };

        expect(FirebaseEnv().projectId, 'fallback-gcloud-project');
      },
    );

    test(
      'falls back to flat env variables when FIREBASE_CONFIG is invalid JSON '
      'or a missing file',
      () {
        FirebaseEnv.mockEnvironment = {
          'FIREBASE_CONFIG': '{not-valid-json',
          'GOOGLE_CLOUD_PROJECT': 'fallback-google-cloud-project',
        };
        expect(FirebaseEnv().projectId, 'fallback-google-cloud-project');

        FirebaseEnv.mockEnvironment = {
          'FIREBASE_CONFIG': '/nonexistent/path/firebase_config.json',
          'GCP_PROJECT': 'fallback-gcp-project',
        };
        expect(FirebaseEnv().projectId, 'fallback-gcp-project');
      },
    );

    test('throws StateError when no project ID is configured', () {
      FirebaseEnv.mockEnvironment = {};

      expect(
        () => FirebaseEnv().projectId,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Checked: FIREBASE_CONFIG, FIREBASE_PROJECT'),
          ),
        ),
      );
    });
  });
}

Future<void> _deleteInitializedApps() async {
  for (final app in FirebaseApp.apps) {
    await FirebaseApp.deleteApp(app);
  }
}
