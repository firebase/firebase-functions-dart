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

import 'package:firebase_admin_sdk/firebase_admin_sdk.dart';
import 'package:firebase_functions/firebase_functions.dart';
import 'package:firebase_functions/testing.dart';
import 'package:test/test.dart';

import '../fixtures/mock_credentials.dart';

final _greeting = defineString(
  'TESTING_GREETING',
  const ParamOptions(defaultValue: 'default'),
);
final _apiKey = defineSecret('TESTING_API_KEY');

void main() {
  group('withEnvironment', () {
    test('sets param values for the code it runs', () {
      expect(
        withEnvironment({'TESTING_GREETING': 'hello'}, _greeting.value),
        'hello',
      );
    });

    test('keeps the values after an await', () async {
      await withEnvironment({'TESTING_API_KEY': 'test-key'}, () async {
        await Future<void>.delayed(Duration.zero);
        expect(_apiKey.value(), 'test-key');
      });
    });

    test('replaces the process environment', () {
      expect(withEnvironment({}, _greeting.value), 'default');
    });
  });

  group('runFunctionsTest environment', () {
    late FirebaseApp app;
    late FunctionsTestClient client;

    setUp(() async {
      app = createMockAuthApp().app;
      client = await runFunctionsTest(
        adminApp: app,
        environment: {'TESTING_API_KEY': 'test-key'},
        (firebase) {
          firebase.https.onCall(
            name: 'apiKey',
            (request, response) async => CallableResult(_apiKey.value()),
          );
        },
      );
    });

    tearDown(() async {
      client.dispose();
      await FirebaseApp.deleteApp(app);
    });

    test('sets param values while handling calls', () async {
      final response = await client.call('apiKey');

      expect(response.statusCode, 200);
      expect(await client.parseCallableResponse(response), 'test-key');
    });
  });
}
