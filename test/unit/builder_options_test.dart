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
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:firebase_functions/src/builder/spec.dart';
import 'package:test/test.dart';

void main() {
  group('EndpointSpec.extractOptions', () {
    test('extracts callable memory from Memory.fromInt', () {
      final options = _parseOptions('''
void main() {
  final options = new CallableOptions(
    memory: Memory.fromInt(1024),
  );
}
''', 'CallableOptions');

      final endpoint = EndpointSpec(
        name: 'callableFunction',
        type: 'callable',
        options: options,
      );

      expect(
        endpoint.extractOptions(),
        containsPair('availableMemoryMb', 1024),
      );
    });

    test('extracts memory from Memory.fromOption factory', () {
      final options = _parseOptions('''
void main() {
  final options = new HttpsOptions(
    memory: Memory.fromOption(MemoryOption.gb2),
  );
}
''', 'HttpsOptions');

      final endpoint = EndpointSpec(
        name: 'memoryFromOption',
        type: 'https',
        options: options,
      );

      expect(
        endpoint.extractOptions(),
        containsPair('availableMemoryMb', 2048),
      );
    });

    test('extracts named factory options from method-style AST calls', () {
      final options = _parseOptions('''
void main() {
  final options = new HttpsOptions(
    cpu: Cpu.gcfGen1(),
    invoker: Invoker.private(),
    minInstances: DeployOption.param(minInstancesParam),
  );
}
''', 'HttpsOptions');

      final endpoint = EndpointSpec(
        name: 'methodStyleFactories',
        type: 'https',
        options: options,
        variableToParamName: {'minInstancesParam': 'MIN_INSTANCES'},
      );
      final extractedOptions = endpoint.extractOptions();

      expect(extractedOptions, containsPair('cpu', 'gcf_gen1'));
      expect(extractedOptions, containsPair('invoker', ['private']));
      expect(
        extractedOptions,
        containsPair('minInstances', '{{ params.MIN_INSTANCES }}'),
      );
    });

    test('extracts region from DeployOption dot shorthand', () {
      final options = _parseHttpsOptions('''
void main() {
  const options = const HttpsOptions(
    region: DeployOption(.asiaEast1),
  );
}
''');

      final endpoint = EndpointSpec(
        name: 'helloWorld',
        type: 'https',
        options: options,
      );

      expect(endpoint.extractOptions(), containsPair('region', ['asia-east1']));
    });

    test('extracts other unresolved wrapper literals consistently', () {
      final options = _parseHttpsOptions('''
void main() {
  const options = const HttpsOptions(
    memory: Memory(.mb512),
    cpu: Cpu(2),
    timeoutSeconds: TimeoutSeconds(60),
    maxInstances: Instances(10),
    serviceAccount: ServiceAccount('test@example.com'),
    vpcConnectorEgressSettings: VpcConnectorEgressSettings(
      .privateRangesOnly,
    ),
    ingressSettings: Ingress(.allowAll),
    invoker: Invoker(['user@example.com']),
    omit: Omit(false),
  );
}
''');

      final endpoint = EndpointSpec(
        name: 'helloWorld',
        type: 'https',
        options: options,
      );
      final extractedOptions = endpoint.extractOptions();

      expect(extractedOptions, containsPair('availableMemoryMb', 512));
      expect(extractedOptions, containsPair('cpu', 2));
      expect(extractedOptions, containsPair('timeoutSeconds', 60));
      expect(extractedOptions, containsPair('maxInstances', 10));
      expect(
        extractedOptions,
        containsPair('serviceAccount', 'test@example.com'),
      );
      expect(
        extractedOptions,
        containsPair('vpcConnectorEgressSettings', 'PRIVATE_RANGES_ONLY'),
      );
      expect(extractedOptions, containsPair('ingressSettings', 'ALLOW_ALL'));
      expect(extractedOptions, containsPair('invoker', ['user@example.com']));
      expect(extractedOptions, containsPair('omit', false));
    });
  });
}

InstanceCreationExpression _parseHttpsOptions(String content) {
  return _parseOptions(content, 'HttpsOptions');
}

InstanceCreationExpression _parseOptions(String content, String typeName) {
  final result = parseString(content: content);
  final visitor = _InstanceCreationVisitor(typeName);

  result.unit.accept(visitor);

  final node = visitor.node;
  expect(node, isNotNull);
  return node!;
}

final class _InstanceCreationVisitor extends RecursiveAstVisitor<void> {
  _InstanceCreationVisitor(this.typeName);

  final String typeName;
  InstanceCreationExpression? node;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (node.constructorName.type.toSource() == typeName) {
      this.node = node;
      return;
    }

    super.visitInstanceCreationExpression(node);
  }
}
