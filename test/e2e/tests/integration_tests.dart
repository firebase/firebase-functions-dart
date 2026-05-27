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

import 'dart:io';

import 'package:test/test.dart';

/// Integration test group
void runIntegrationTests(String Function() getExamplePath) {
  group('Integration', () {
    late String examplePath;

    setUpAll(() {
      examplePath = getExamplePath();
    });
    test('functions.yaml was generated correctly', () {
      final manifestPath = '$examplePath/functions.yaml';
      final manifestFile = File(manifestPath);

      expect(
        manifestFile.existsSync(),
        isTrue,
        reason: 'functions.yaml should exist',
      );

      final manifestContent = manifestFile.readAsStringSync();
      expect(
        manifestContent,
        contains('hello-world'),
        reason: 'Manifest should contain hello-world function',
      );
    });

    test('service account shorthand is preserved in manifest', () {
      final manifestPath = '$examplePath/functions.yaml';
      final manifestFile = File(manifestPath);

      expect(
        manifestFile.existsSync(),
        isTrue,
        reason: 'functions.yaml should exist',
      );

      final manifestContent = manifestFile.readAsStringSync();
      expect(
        manifestContent,
        contains('service-account-shorthand'),
        reason: 'Manifest should contain serviceAccountShorthand function',
      );
      expect(
        manifestContent,
        contains('serviceAccountEmail: super-account@'),
        reason: 'Manifest should preserve project-relative service account',
      );
      expect(
        manifestContent,
        isNot(contains('serviceAccountEmail: super-account\n')),
        reason: 'Manifest should not strip the trailing @ shorthand marker',
      );
    });
  });
}
