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
import 'package:firebase_functions/src/common/expression.dart';
import 'package:firebase_functions/src/common/params.dart';
import 'package:test/test.dart';

// Test enum for defineEnumList tests
enum TestRegion { usCentral1, europeWest1, asiaNortheast1 }

void main() {
  group('Parameter Factory Functions', () {
    setUp(() {
      clearParams();
    });

    test('defineString registers a StringParam', () {
      final param = defineString('TEST_STRING');
      expect(param, isA<StringParam>());
      expect(param.name, 'TEST_STRING');
      expect(declaredParams, contains(param));
    });

    test('defineInt registers an IntParam', () {
      final param = defineInt('TEST_INT');
      expect(param, isA<IntParam>());
      expect(param.name, 'TEST_INT');
      expect(declaredParams, contains(param));
    });

    test('defineDouble registers a DoubleParam', () {
      final param = defineDouble('TEST_DOUBLE');
      expect(param, isA<DoubleParam>());
      expect(param.name, 'TEST_DOUBLE');
      expect(declaredParams, contains(param));
    });

    test('defineBoolean registers a BooleanParam', () {
      final param = defineBoolean('TEST_BOOL');
      expect(param, isA<BooleanParam>());
      expect(param.name, 'TEST_BOOL');
      expect(declaredParams, contains(param));
    });

    test('defineList registers a ListParam', () {
      final param = defineList('TEST_LIST');
      expect(param, isA<ListParam>());
      expect(param.name, 'TEST_LIST');
      expect(declaredParams, contains(param));
    });

    test('defineSecret registers a SecretParam', () {
      final param = defineSecret('TEST_SECRET');
      expect(param, isA<SecretParam>());
      expect(param.name, 'TEST_SECRET');
      expect(declaredParams, contains(param));
    });

    test('defineJsonSecret registers a JsonSecretParam', () {
      final param = defineJsonSecret<Map<String, dynamic>>('TEST_JSON_SECRET');
      expect(param, isA<JsonSecretParam<Map<String, dynamic>>>());
      expect(param.name, 'TEST_JSON_SECRET');
      expect(declaredParams, contains(param));
    });

    test('redefining a parameter replaces the old one', () {
      final param1 = defineString('SAME_NAME');
      expect(declaredParams.length, 1);

      final param2 = defineInt('SAME_NAME');
      expect(declaredParams.length, 1);
      expect(declaredParams.first, param2);
      expect(declaredParams.first, isNot(param1));
    });

    test('clearParams removes all registered params', () {
      defineString('A');
      defineInt('B');
      defineBoolean('C');
      expect(declaredParams.length, 3);

      clearParams();
      expect(declaredParams, isEmpty);
    });
  });

  group('ParamOptions', () {
    test('can be created with all options', () {
      final options = ParamOptions<String>(
        defaultValue: 'default',
        label: 'Test Label',
        description: 'Test Description',
        input: ParamInput.select(['a', 'b', 'c']),
      );

      expect(options.defaultValue, 'default');
      expect(options.label, 'Test Label');
      expect(options.description, 'Test Description');
      expect(options.input, isA<SelectParamInput>());
    });

    test('all fields are optional', () {
      const options = ParamOptions<String>();
      expect(options.defaultValue, isNull);
      expect(options.label, isNull);
      expect(options.description, isNull);
      expect(options.input, isNull);
    });
  });

  group('Param.toSpec()', () {
    setUp(() => clearParams());

    test('StringParam generates correct spec', () {
      final param = defineString(
        'MY_STRING',
        const ParamOptions(
          defaultValue: 'hello',
          label: 'My String',
          description: 'A test string',
        ),
      );

      final spec = param.toSpec();
      expect(spec.name, 'MY_STRING');
      expect(spec.type, 'string');
      expect(spec.defaultValue, 'hello');
      expect(spec.label, 'My String');
      expect(spec.description, 'A test string');
    });

    test('IntParam generates correct spec', () {
      final param = defineInt('MY_INT', const ParamOptions(defaultValue: 42));

      final spec = param.toSpec();
      expect(spec.name, 'MY_INT');
      expect(spec.type, 'int');
      expect(spec.defaultValue, 42);
    });

    test('BooleanParam generates correct spec', () {
      final param = defineBoolean(
        'MY_BOOL',
        const ParamOptions(defaultValue: true),
      );

      final spec = param.toSpec();
      expect(spec.name, 'MY_BOOL');
      expect(spec.type, 'boolean');
      expect(spec.defaultValue, true);
    });

    test('SecretParam generates correct spec', () {
      final param = defineSecret('MY_SECRET');

      final spec = param.toSpec();
      expect(spec.name, 'MY_SECRET');
      expect(spec.type, 'secret');
    });
  });

  group('JsonSecretParam.toSpec()', () {
    setUp(() => clearParams());

    test('generates spec with json format', () {
      final param = defineJsonSecret<Map<String, dynamic>>('API_CONFIG');

      final spec = param.toSpec();
      expect(spec['name'], 'API_CONFIG');
      expect(spec['type'], 'secret');
      expect(spec['format'], 'json');
    });
  });

  group('BooleanParam.thenElse()', () {
    setUp(() => clearParams());

    test('creates conditional expression', () {
      final isProduction = defineBoolean('IS_PRODUCTION');
      final conditional = isProduction.thenElse(2048, 512);

      expect(conditional, isNotNull);
      // The conditional is an If expression
      expect(conditional.toString(), contains('params.IS_PRODUCTION'));
    });
  });

  group('SelectOption', () {
    test('can be created with value only', () {
      const option = SelectOption(value: 42);
      expect(option.value, 42);
      expect(option.label, isNull);
    });

    test('can be created with value and label', () {
      const option = SelectOption(value: 512, label: 'Medium');
      expect(option.value, 512);
      expect(option.label, 'Medium');
    });

    test('works with String type', () {
      const option = SelectOption(value: 'us-central1', label: 'US Central');
      expect(option.value, 'us-central1');
      expect(option.label, 'US Central');
    });

    test('works with double type', () {
      const option = SelectOption(value: 0.5, label: 'Half');
      expect(option.value, 0.5);
      expect(option.label, 'Half');
    });

    test('select factory creates options with null labels', () {
      final input = ParamInput.select([10, 20, 30]);
      for (final option in input.options) {
        expect(option.label, isNull);
      }
      expect(input.options.map((o) => o.value).toList(), [10, 20, 30]);
    });

    test('selectWithLabels factory maps labels to values', () {
      final input = ParamInput.selectWithLabels({
        'Small': 256,
        'Medium': 512,
        'Large': 1024,
      });
      expect(input.options[0].label, 'Small');
      expect(input.options[0].value, 256);
      expect(input.options[1].label, 'Medium');
      expect(input.options[1].value, 512);
      expect(input.options[2].label, 'Large');
      expect(input.options[2].value, 1024);
    });

    test('multiSelect factory creates options with null labels', () {
      final input = ParamInput.multiSelect(['a', 'b', 'c']);
      for (final option in input.options) {
        expect(option.label, isNull);
      }
      expect(input.options.map((o) => o.value).toList(), ['a', 'b', 'c']);
    });

    test('multiSelectWithLabels factory maps labels to values', () {
      final input = ParamInput.multiSelectWithLabels({
        'Option A': 'a',
        'Option B': 'b',
        'Option C': 'c',
      });
      expect(input, isA<MultiSelectParamInput>());
      expect(input.options.length, 3);
      expect(input.options[0].label, 'Option A');
      expect(input.options[0].value, 'a');
      expect(input.options[1].label, 'Option B');
      expect(input.options[1].value, 'b');
      expect(input.options[2].label, 'Option C');
      expect(input.options[2].value, 'c');
    });

    test('can be used in SelectParamInput directly', () {
      final input = const SelectParamInput<String>(
        options: [
          SelectOption(value: 'us-central1', label: 'US Central'),
          SelectOption(value: 'europe-west1', label: 'Europe West'),
        ],
      );
      expect(input.options.length, 2);
      expect(input.options[0].value, 'us-central1');
      expect(input.options[1].label, 'Europe West');
    });

    test('can be used in MultiSelectParamInput directly', () {
      final input = const MultiSelectParamInput(
        options: [
          SelectOption(value: 'read', label: 'Read Access'),
          SelectOption(value: 'write', label: 'Write Access'),
        ],
      );
      expect(input.options.length, 2);
      expect(input.options[0].value, 'read');
      expect(input.options[1].label, 'Write Access');
    });
  });

  group('ParamInput', () {
    test('select creates SelectParamInput', () {
      final input = ParamInput.select([1, 2, 3]);
      expect(input, isA<SelectParamInput<int>>());
      expect(input.options.length, 3);
    });

    test('selectWithLabels creates SelectParamInput with labels', () {
      final input = ParamInput.selectWithLabels({
        'Small': 256,
        'Medium': 512,
        'Large': 1024,
      });
      expect(input, isA<SelectParamInput<int>>());
      expect(input.options.length, 3);
      expect(input.options[0].label, 'Small');
      expect(input.options[0].value, 256);
    });

    test('multiSelect creates MultiSelectParamInput', () {
      final input = ParamInput.multiSelect(['a', 'b', 'c']);
      expect(input, isA<MultiSelectParamInput>());
      expect(input.options.length, 3);
    });

    test('multiSelectWithLabels creates MultiSelectParamInput with labels', () {
      final input = ParamInput.multiSelectWithLabels({
        'Label A': 'val_a',
        'Label B': 'val_b',
      });
      expect(input, isA<MultiSelectParamInput>());
      expect(input.options.length, 2);
      expect(input.options[0].label, 'Label A');
      expect(input.options[0].value, 'val_a');
    });

    test('bucketPicker is a ResourceInput', () {
      expect(ParamInput.bucketPicker, isA<ResourceInput>());
    });
  });

  group('Built-in Parameters', () {
    test('projectId is an InternalExpression', () {
      expect(ParamInput.projectId, isA<InternalExpression>());
      expect(ParamInput.projectId.name, 'PROJECT_ID');
    });

    test('databaseURL is an InternalExpression', () {
      expect(ParamInput.databaseURL, isA<InternalExpression>());
      expect(ParamInput.databaseURL.name, 'DATABASE_URL');
    });

    test('storageBucket is an InternalExpression', () {
      expect(ParamInput.storageBucket, isA<InternalExpression>());
      expect(ParamInput.storageBucket.name, 'STORAGE_BUCKET');
    });

    test('gcloudProject is an InternalExpression', () {
      expect(ParamInput.gcloudProject, isA<InternalExpression>());
      expect(ParamInput.gcloudProject.name, 'GCLOUD_PROJECT');
    });
  });

  group('Param.toString()', () {
    setUp(() => clearParams());

    test('returns params.NAME format', () {
      final param = defineString('MY_PARAM');
      expect(param.toString(), 'params.MY_PARAM');
    });
  });

  group('defineFloat()', () {
    setUp(() => clearParams());

    test('registers a DoubleParam', () {
      final param = defineFloat('TEST_FLOAT');
      expect(param, isA<DoubleParam>());
      expect(param.name, 'TEST_FLOAT');
      expect(declaredParams, contains(param));
    });

    test('is an alias for defineDouble', () {
      final floatParam = defineFloat('FLOAT_PARAM');
      final doubleParam = defineDouble('DOUBLE_PARAM');

      // Both return DoubleParam
      expect(floatParam.runtimeType, doubleParam.runtimeType);
    });

    test('generates correct spec', () {
      final param = defineFloat(
        'MY_FLOAT',
        const ParamOptions(defaultValue: 3.14),
      );

      final spec = param.toSpec();
      expect(spec.name, 'MY_FLOAT');
      expect(spec.type, 'double'); // Type name from class
      expect(spec.defaultValue, 3.14);
    });
  });

  group('defineList()', () {
    setUp(() {
      clearParams();
      FirebaseEnv.mockEnvironment = null;
    });

    tearDown(() {
      FirebaseEnv.mockEnvironment = null;
    });

    test('returns parsed string list from environment', () {
      FirebaseEnv.mockEnvironment = {'MY_LIST': '["foo", "bar"]'};
      final param = defineList('MY_LIST');
      expect(param.runtimeValue(), ['foo', 'bar']);
    });

    test('returns default value when JSON is not a string array', () {
      FirebaseEnv.mockEnvironment = {'MY_LIST': '[1, 2, 3]'};
      final param = defineList(
        'MY_LIST',
        const ParamOptions(defaultValue: ['default']),
      );
      expect(param.runtimeValue(), ['default']);
    });

    test('returns default value on invalid JSON', () {
      FirebaseEnv.mockEnvironment = {'MY_LIST': '{not valid json'};
      final param = defineList(
        'MY_LIST',
        const ParamOptions(defaultValue: ['default']),
      );
      expect(param.runtimeValue(), ['default']);
    });
  });

  group('defineEnumList()', () {
    setUp(() {
      clearParams();
      FirebaseEnv.mockEnvironment = null;
    });

    tearDown(() {
      FirebaseEnv.mockEnvironment = null;
    });

    test('registers an EnumListParam', () {
      final param = defineEnumList(TestRegion.values);
      expect(param, isA<EnumListParam<TestRegion>>());
      expect(declaredParams, contains(param));
    });

    test('derives parameter name from enum type', () {
      final param = defineEnumList(TestRegion.values);
      expect(param.name, 'TEST_REGION_LIST');
    });

    test('accepts ParamOptions with default values', () {
      final param = defineEnumList(
        TestRegion.values,
        const ParamOptions(
          defaultValue: [TestRegion.usCentral1],
          label: 'Regions',
          description: 'Select deployment regions',
        ),
      );

      expect(param.options?.defaultValue, [TestRegion.usCentral1]);
      expect(param.options?.label, 'Regions');
      expect(param.options?.description, 'Select deployment regions');
    });

    test('generates correct spec', () {
      final param = defineEnumList(
        TestRegion.values,
        const ParamOptions(
          defaultValue: [TestRegion.europeWest1],
          label: 'Deployment Regions',
        ),
      );

      final spec = param.toSpec();
      expect(spec.name, 'TEST_REGION_LIST');
      expect(spec.type, 'list');
      expect(spec.label, 'Deployment Regions');
    });

    test('returns default value when JSON is not a string array', () {
      FirebaseEnv.mockEnvironment = {'TEST_REGION_LIST': '[1, 2, 3]'};
      final param = defineEnumList(
        TestRegion.values,
        const ParamOptions(defaultValue: [TestRegion.usCentral1]),
      );
      expect(param.runtimeValue(), [TestRegion.usCentral1]);
    });
  });

  group('IntParam comparison methods', () {
    setUp(() => clearParams());

    test('greaterThan creates GreaterThan expression', () {
      final param = defineInt('MEMORY_MB');
      final comparison = param.greaterThan(1024);

      expect(comparison, isA<GreaterThan>());
      expect(comparison.toString(), contains('params.MEMORY_MB'));
      expect(comparison.toString(), contains('> 1024'));
    });

    test('greaterThanOrEqualTo creates GreaterThanOrEqualTo expression', () {
      final param = defineInt('INSTANCES');
      final comparison = param.greaterThanOrEqualTo(2);

      expect(comparison, isA<GreaterThanOrEqualTo>());
      expect(comparison.toString(), contains('>= 2'));
    });

    test('lessThan creates LessThan expression', () {
      final param = defineInt('TIMEOUT');
      final comparison = param.lessThan(60);

      expect(comparison, isA<LessThan>());
      expect(comparison.toString(), contains('< 60'));
    });

    test('lessThanOrEqualTo creates LessThanOrEqualTo expression', () {
      final param = defineInt('RETRIES');
      final comparison = param.lessThanOrEqualTo(3);

      expect(comparison, isA<LessThanOrEqualTo>());
      expect(comparison.toString(), contains('<= 3'));
    });

    test('comparison can be used with thenElse for conditionals', () {
      final param = defineInt('MEMORY_MB');
      final needsMoreCpu = param.greaterThan(2048);
      final cpuCount = needsMoreCpu.when(
        then: const LiteralExpression(4),
        otherwise: const LiteralExpression(1),
      );

      expect(cpuCount, isA<If<int>>());
    });
  });

  group('DoubleParam comparison methods', () {
    setUp(() => clearParams());

    test('greaterThan creates GreaterThan expression', () {
      final param = defineDouble('THRESHOLD');
      final comparison = param.greaterThan(0.75);

      expect(comparison, isA<GreaterThan>());
      expect(comparison.toString(), contains('params.THRESHOLD'));
      expect(comparison.toString(), contains('> 0.75'));
    });

    test('greaterThanOrEqualTo creates GreaterThanOrEqualTo expression', () {
      final param = defineDouble('MIN_SCORE');
      final comparison = param.greaterThanOrEqualTo(0.5);

      expect(comparison, isA<GreaterThanOrEqualTo>());
      expect(comparison.toString(), contains('>= 0.5'));
    });

    test('lessThan creates LessThan expression', () {
      final param = defineDouble('RATE_LIMIT');
      final comparison = param.lessThan(1.0);

      expect(comparison, isA<LessThan>());
      expect(comparison.toString(), contains('< 1.0'));
    });

    test('lessThanOrEqualTo creates LessThanOrEqualTo expression', () {
      final param = defineDouble('MAX_RATIO');
      final comparison = param.lessThanOrEqualTo(0.9);

      expect(comparison, isA<LessThanOrEqualTo>());
      expect(comparison.toString(), contains('<= 0.9'));
    });

    test('defineFloat also has comparison methods', () {
      final param = defineFloat('CONFIDENCE');
      final comparison = param.greaterThan(0.8);

      expect(comparison, isA<GreaterThan>());
    });
  });

  group('cmp method on numeric params', () {
    setUp(() => clearParams());

    test('IntParam.cmp creates conditional based on equality', () {
      final param = defineInt('COUNT');
      final result = param.cmp(0, 'none', 'some');

      expect(result, isA<If<String>>());
    });

    test('DoubleParam.cmp creates conditional based on equality', () {
      final param = defineDouble('VALUE');
      final result = param.cmp(0.0, 'zero', 'non-zero');

      expect(result, isA<If<String>>());
    });
  });
}
