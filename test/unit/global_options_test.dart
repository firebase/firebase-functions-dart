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

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:firebase_functions/src/builder/manifest.dart';
import 'package:firebase_functions/src/builder/spec.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  group('setGlobalOptions', () {
    test('merges global defaults with endpoint options', () {
      final globalOptions = _initializerFor('''
final globalOptions = new GlobalOptions(
  region: new Region(SupportedRegion.europeWest1),
  memory: new Memory(MemoryOption.mb512),
  timeoutSeconds: new TimeoutSeconds(120),
  minInstances: new Instances(1),
  enforceAppCheck: new EnforceAppCheck(true),
);
''', 'globalOptions');
      final endpointOptions = _initializerFor('''
final endpointOptions = new HttpsOptions(
  region: new Region(SupportedRegion.usWest1),
  memory: new Memory(MemoryOption.gb1),
  timeoutSeconds: new TimeoutSeconds.reset(),
);
''', 'endpointOptions');

      final yaml = generateManifestYaml({}, {
        'globalEndpoint': EndpointSpec(
          name: 'globalEndpoint',
          type: 'https',
          globalOptions: globalOptions,
          options: endpointOptions,
        ),
      });
      final manifest = loadYaml(yaml) as YamlMap;
      final endpoint =
          (manifest['endpoints'] as YamlMap)['global-endpoint'] as YamlMap;

      expect(endpoint['region'], equals(['us-west1']));
      expect(endpoint['availableMemoryMb'], equals(1024));
      expect(endpoint['minInstances'], equals(1));
      expect(endpoint['timeoutSeconds'], isNull);
      expect(endpoint['httpsTrigger'], equals({}));
    });

    test('does not emit reset values from global options', () {
      final globalOptions = _initializerFor('''
final globalOptions = new GlobalOptions(
  timeoutSeconds: new TimeoutSeconds.reset(),
);
''', 'globalOptions');

      final yaml = generateManifestYaml({}, {
        'globalResetEndpoint': EndpointSpec(
          name: 'globalResetEndpoint',
          type: 'https',
          globalOptions: globalOptions,
        ),
      });
      final manifest = loadYaml(yaml) as YamlMap;
      final endpoint =
          (manifest['endpoints'] as YamlMap)['global-reset-endpoint']
              as YamlMap;

      expect(endpoint['timeoutSeconds'], isNull);
    });
  });
}

InstanceCreationExpression _initializerFor(String source, String name) {
  final unit = parseString(content: source).unit;
  for (final declaration in unit.declarations) {
    if (declaration is! TopLevelVariableDeclaration) continue;
    for (final variable in declaration.variables.variables) {
      if (variable.name.lexeme == name) {
        return variable.initializer! as InstanceCreationExpression;
      }
    }
  }
  throw StateError('No initializer found for $name');
}
