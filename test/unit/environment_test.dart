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

import 'package:firebase_functions/src/common/environment.dart';
import 'package:google_cloud/constants.dart';
import 'package:test/test.dart';

void main() {
  group('FirebaseEnv', () {
    tearDown(() {
      FirebaseEnv.mockEnvironment = null;
    });

    test('kService reads from serviceEnvironmentVariable (K_SERVICE)', () {
      FirebaseEnv.mockEnvironment = {serviceEnvironmentVariable: 'my-service'};
      final env = FirebaseEnv();
      expect(env.kService, 'my-service');
    });

    test('projectId resolves from FIREBASE_PROJECT first', () {
      FirebaseEnv.mockEnvironment = {
        'FIREBASE_PROJECT': 'firebase-proj',
        projectIdEnvironmentVariable: 'gcp-proj',
      };
      final env = FirebaseEnv();
      expect(env.projectId, 'firebase-proj');
    });

    test(
      'projectId resolves from projectIdEnvironmentVariableOptions in order',
      () {
        for (final option in projectIdEnvironmentVariableOptions) {
          FirebaseEnv.mockEnvironment = {option: 'test-$option'};
          final env = FirebaseEnv();
          expect(env.projectId, 'test-$option');
        }
      },
    );

    test(
      'projectId throws StateError when no option is set in environment',
      () {
        FirebaseEnv.mockEnvironment = {};
        final env = FirebaseEnv();
        expect(
          () => env.projectId,
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('No project ID found in environment.'),
            ),
          ),
        );
      },
    );
  });
}
