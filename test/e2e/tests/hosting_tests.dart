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

import 'package:test/test.dart';

import '../helpers/hosting_client.dart';

/// Hosting rewrite test group.
///
/// Verifies that the hosting emulator correctly forwards requests to the Dart
/// function and that handlers receive the original request path, not the
/// routing prefix added by the emulator.
void runHostingTests(HostingHttpClient Function() getClient) {
  group('Hosting rewrites', () {
    late HostingHttpClient client;

    setUpAll(() {
      client = getClient();
    });

    test('root path is passed correctly to handler', () async {
      final response = await client.get('/');
      expect(response.statusCode, equals(200));
      expect(response.body, equals('/'));
    });

    test('sub-path is passed correctly to handler', () async {
      final response = await client.get('/about');
      expect(response.statusCode, equals(200));
      expect(response.body, equals('/about'));
    });

    test('deep path is passed correctly to handler', () async {
      final response = await client.get('/a/b/c');
      expect(response.statusCode, equals(200));
      expect(response.body, equals('/a/b/c'));
    });
  });
}
