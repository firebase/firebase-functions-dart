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

import 'package:firebase_functions/src/builder/manifest.dart';
import 'package:firebase_functions/src/builder/spec.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  group('Cloud Run command', () {
    test('defaults to the dart compile exe path', () {
      // Omitting the flag entirely must keep pre-existing projects building
      // the way they always have.
      final yaml = generateManifestYaml({}, {
        'demo': EndpointSpec(name: 'demo', type: 'https'),
      });
      expect(_commandIn(yaml), equals(['./bin/server']));
    });

    test('uses the dart compile exe path without native assets support', () {
      expect(
        _commandFor(nativeAssetsAvailable: false),
        equals(['./bin/server']),
      );
    });

    test('uses the dart build cli bundle path with native assets support', () {
      expect(
        _commandFor(nativeAssetsAvailable: true),
        equals(['./build/cli/linux_x64/bundle/bin/server']),
      );
    });

    test('matches the paths the Firebase CLI builds to', () {
      // A mismatch only surfaces as a container that fails to start.
      expect(dartCompileExeCommand, equals('./bin/server'));
      expect(
        dartBuildCliCommand,
        equals('./build/cli/linux_x64/bundle/bin/server'),
      );
    });
  });
}

/// Generates a manifest for a single endpoint and returns its `command`.
List<Object?> _commandFor({required bool nativeAssetsAvailable}) {
  final yaml = generateManifestYaml({}, {
    'demo': EndpointSpec(name: 'demo', type: 'https'),
  }, nativeAssetsAvailable: nativeAssetsAvailable);
  return _commandIn(yaml);
}

/// Extracts the `command` of the sole endpoint in a generated manifest.
List<Object?> _commandIn(String yaml) {
  final manifest = loadYaml(yaml) as YamlMap;
  final endpoint = (manifest['endpoints'] as YamlMap)['demo'] as YamlMap;
  return (endpoint['command'] as YamlList).toList();
}
